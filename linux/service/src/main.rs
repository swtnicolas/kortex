mod bus;
mod files;
mod json;
mod memory;
mod nvml;
mod processes;
mod processor;
mod system;
mod temperature;
mod usage;

use bus::{Call, Connection, Message};
use json::Json;
use memory::Memory;
use nvml::Nvml;
use processes::{Kind, Processes};
use processor::Processor;
use std::ffi::{CStr, c_int, c_void};
use std::time::{Duration, Instant};
use temperature::Temperatures;
use usage::Usage;

const NAME: &CStr = c"local.Kortex";
const PATH: &CStr = c"/local/Kortex";
const INTERFACE: &CStr = c"local.Kortex";
const IDLE: Duration = Duration::from_secs(60);
const DETAIL_TIMEOUT: Duration = Duration::from_secs(30);
const EINVAL: c_int = 22;

#[derive(Default)]
struct Detail(Option<Instant>);

impl Detail {
    fn touch(&mut self, now: Instant) {
        self.0 = Some(now);
    }

    fn expired(&self, now: Instant) -> bool {
        self.0.is_some_and(|seen| now.duration_since(seen) >= DETAIL_TIMEOUT)
    }

    fn is_open(&self) -> bool {
        self.0.is_some()
    }
}

struct Service {
    memory: Memory,
    processor: Processor,
    temperatures: Temperatures,
    nvml: Option<Nvml>,
    processes: Option<Processes>,
    detail: Detail,
    usage: Usage,
    json: Json,
    last_call: Instant,
}

impl Service {
    fn new() -> Service {
        Service {
            memory: Memory::new(),
            processor: Processor::new(),
            temperatures: Temperatures::new(),
            nvml: Nvml::open(),
            processes: None,
            detail: Detail::default(),
            usage: Usage::new(),
            json: Json::new(),
            last_call: Instant::now(),
        }
    }

    fn close_detail(&mut self) {
        self.detail = Detail::default();
        if self.processes.take().is_some() {
            if let Some(nvml) = &mut self.nvml {
                nvml.release();
            }
            system::trim();
        }
    }

    fn bar(&mut self, tab: &str) -> &[u8] {
        let now = Instant::now();
        if !tab.is_empty() {
            self.detail.touch(now);
        } else if self.detail.expired(now) {
            self.close_detail();
        }
        let open = self.detail.is_open();
        let info = self.memory.info();
        let cpu = self.processor.usage();
        let gpu = self.nvml.as_ref().and_then(Nvml::usage);
        let gpu_temperature = self.nvml.as_ref().and_then(Nvml::temperature);
        let temperature = self.temperatures.peak(gpu_temperature);
        self.usage.sample(open);

        let j = &mut self.json;
        j.reset();
        j.open();
        j.field("ram", info.and_then(|i| i.usage()), 1)
            .field("cpu", cpu, 1)
            .field("gpu", gpu, 0)
            .field("temp", temperature, 1);
        j.key("own").open().field("ram", self.usage.ram, 0).field("cpu", self.usage.cpu.latest, 2).close();
        j.key("closed").open().field("ram", self.usage.closed_ram, 0).field("cpu", self.usage.cpu.closed, 2).close();
        match tab {
            "ram" => {
                if let Some(info) = info {
                    j.key("detail").open();
                    self.memory.detail(&info, j);
                    j.close();
                }
            }
            "cpu" => {
                j.key("detail").open();
                self.processor.detail(cpu, j);
                j.close();
            }
            "gpu" => {
                if let Some(nvml) = &self.nvml {
                    let g = nvml.detail();
                    j.key("detail").open().key("name").string(&nvml.name);
                    j.field("usage", g.usage, 0)
                        .field("memoryController", g.memory_controller, 0)
                        .field("encoder", g.encoder, 0)
                        .field("decoder", g.decoder, 0)
                        .field("clock", g.clock, 0)
                        .field("clockMax", g.clock_max, 0)
                        .field("power", g.power, 1)
                        .field("powerLimit", g.power_limit, 0)
                        .field("vram", g.vram, 0)
                        .field("vramTotal", g.vram_total, 0)
                        .field("temperature", g.temperature, 0)
                        .field("cores", g.cores, 0)
                        .close();
                }
            }
            _ => {}
        }
        j.close();
        j.finish()
    }

    fn list(&mut self, tab: &str, query: &str, limit: u32) -> &[u8] {
        self.detail.touch(Instant::now());
        self.usage.cpu.opened();
        let j = &mut self.json;
        j.reset();
        j.open();
        let kind = match tab {
            "ram" => Some(Kind::Memory),
            "cpu" => Some(Kind::Processor),
            "gpu" => Some(Kind::Graphics),
            _ => None,
        };
        if let Some(kind) = kind {
            let processes = self.processes.get_or_insert_with(Processes::new);
            processes.list(kind, query, limit as usize, self.nvml.as_mut(), j);
        } else if tab == "temp" {
            let gpu = self.nvml.as_ref().and_then(Nvml::temperature);
            j.key("zones").open_list();
            for zone in self.temperatures.zones(gpu) {
                j.open().key("name").string(zone.name);
                j.field("max", Some(zone.max), 1).field("average", Some(zone.average), 1).close();
            }
            j.close_list();
            j.key("fans").open_list();
            let gpu_fans = self.nvml.as_ref().map(Nvml::fans).unwrap_or_default();
            let single = gpu_fans.len() == 1;
            for (i, fan) in gpu_fans.iter().enumerate() {
                let name = if single { "GPU".to_owned() } else { format!("GPU {}", i + 1) };
                j.open().key("name").string(&name);
                j.field("rpm", fan.rpm, 0).field("percent", fan.percent, 0).close();
            }
            for i in 0..self.temperatures.fans.len() {
                let rpm = self.temperatures.fan_rpm(i);
                j.open().key("name").string(&self.temperatures.fans[i].name);
                j.field("rpm", rpm, 0).field("percent", None, 0).close();
            }
            j.close_list();
        }
        j.close();
        j.finish()
    }

    fn terminate(&mut self, targets: &str, force: bool) -> u32 {
        self.detail.touch(Instant::now());
        self.processes.get_or_insert_with(Processes::new).terminate(targets, force)
    }
}

unsafe extern "C" fn handle(message: *mut Message, userdata: *mut c_void, _error: *mut c_void) -> c_int {
    let service = unsafe { &mut *(userdata as *mut Service) };
    let call = Call(message);
    service.last_call = Instant::now();
    if call.is(INTERFACE, c"Bar") {
        let Some(tab) = call.string() else { return -EINVAL };
        let reading = service.bar(&tab);
        let status = call.reply_string(reading);
        call.signal_string(PATH, INTERFACE, c"Reading", reading);
        status
    } else if call.is(INTERFACE, c"Close") {
        service.close_detail();
        call.reply_empty()
    } else if call.is(INTERFACE, c"List") {
        let (Some(tab), Some(query), Some(limit)) = (call.string(), call.string(), call.unsigned()) else {
            return -EINVAL;
        };
        call.reply_string(service.list(&tab, &query, limit))
    } else if call.is(INTERFACE, c"Terminate") {
        let (Some(targets), Some(force)) = (call.string(), call.boolean()) else { return -EINVAL };
        call.reply_unsigned(service.terminate(&targets, force))
    } else {
        0
    }
}

fn main() {
    let service = Box::into_raw(Box::new(Service::new()));
    let Some(bus) = Connection::user() else { std::process::exit(1) };
    if !bus.serve(PATH, handle, service as *mut c_void) || !bus.own(NAME) {
        std::process::exit(1);
    }
    loop {
        let processed = bus.process();
        if processed < 0 {
            break;
        }
        if processed > 0 {
            continue;
        }
        let idle = unsafe { (*service).last_call.elapsed() };
        if idle >= IDLE || bus.wait(IDLE - idle) < 0 {
            break;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_detail_expires_thirty_seconds_after_its_last_call() {
        let opened = Instant::now();
        let mut detail = Detail::default();
        detail.touch(opened);
        assert!(!detail.expired(opened + DETAIL_TIMEOUT - Duration::from_millis(1)));
        assert!(detail.expired(opened + DETAIL_TIMEOUT));

        detail.touch(opened + Duration::from_secs(20));
        assert!(!detail.expired(opened + DETAIL_TIMEOUT));
    }
}
