use std::ffi::{CStr, c_char, c_int, c_uint, c_void};

unsafe extern "C" {
    fn dlopen(file: *const c_char, mode: c_int) -> *mut c_void;
    fn dlsym(handle: *mut c_void, name: *const c_char) -> *mut c_void;
}

const RTLD_NOW: c_int = 2;
const SUCCESS: c_int = 0;
const INSUFFICIENT_SIZE: c_int = 7;
const TEMPERATURE_GPU: c_uint = 0;
const CLOCK_GRAPHICS: c_uint = 0;

type Device = *mut c_void;

#[repr(C)]
#[derive(Default)]
struct Utilization {
    gpu: c_uint,
    memory: c_uint,
}

#[repr(C)]
#[derive(Default)]
struct MemoryInfo {
    total: u64,
    free: u64,
    used: u64,
}

#[repr(C)]
struct FanSpeedInfo {
    version: c_uint,
    fan: c_uint,
    speed: c_uint,
}

#[repr(C)]
#[derive(Default, Clone, Copy)]
struct ProcessSample {
    pid: c_uint,
    timestamp: u64,
    sm: c_uint,
    memory: c_uint,
    encoder: c_uint,
    decoder: c_uint,
}

#[repr(C)]
#[derive(Default, Clone, Copy)]
struct ProcessInfo {
    pid: c_uint,
    used_memory: u64,
    gpu_instance: c_uint,
    compute_instance: c_uint,
}

type GetU32 = unsafe extern "C" fn(Device, *mut c_uint) -> c_int;
type GetU32By = unsafe extern "C" fn(Device, c_uint, *mut c_uint) -> c_int;
type GetPair = unsafe extern "C" fn(Device, *mut c_uint, *mut c_uint) -> c_int;
type GetProcesses = unsafe extern "C" fn(Device, *mut c_uint, *mut ProcessInfo) -> c_int;

struct Api {
    utilization: unsafe extern "C" fn(Device, *mut Utilization) -> c_int,
    temperature: GetU32By,
    memory: Option<unsafe extern "C" fn(Device, *mut MemoryInfo) -> c_int>,
    clock: Option<GetU32By>,
    max_clock: Option<GetU32By>,
    power: Option<GetU32>,
    power_limit: Option<GetU32>,
    encoder: Option<GetPair>,
    decoder: Option<GetPair>,
    fans: Option<GetU32>,
    fan_percent: Option<GetU32By>,
    fan_rpm: Option<unsafe extern "C" fn(Device, *mut FanSpeedInfo) -> c_int>,
    cores: Option<GetU32>,
    process_samples: Option<unsafe extern "C" fn(Device, *mut ProcessSample, *mut c_uint, u64) -> c_int>,
    compute_processes: Option<GetProcesses>,
    graphics_processes: Option<GetProcesses>,
}

pub struct Gpu {
    pub usage: Option<f64>,
    pub memory_controller: Option<f64>,
    pub encoder: Option<f64>,
    pub decoder: Option<f64>,
    pub clock: Option<f64>,
    pub clock_max: Option<f64>,
    pub power: Option<f64>,
    pub power_limit: Option<f64>,
    pub vram: Option<f64>,
    pub vram_total: Option<f64>,
    pub temperature: Option<f64>,
    pub cores: Option<f64>,
}

pub struct Fan {
    pub rpm: Option<f64>,
    pub percent: Option<f64>,
}

#[derive(Default, Clone, Copy)]
pub struct ProcessUse {
    pub pid: u32,
    pub sm: f64,
    pub vram: u64,
}

pub struct Nvml {
    api: Api,
    device: Device,
    pub name: String,
    last_seen: u64,
    samples: Vec<ProcessSample>,
    infos: Vec<ProcessInfo>,
}

unsafe fn symbol<T>(lib: *mut c_void, name: &CStr) -> Option<T> {
    let pointer = unsafe { dlsym(lib, name.as_ptr()) };
    (!pointer.is_null()).then(|| unsafe { std::mem::transmute_copy(&pointer) })
}

fn read<F: FnOnce(*mut c_uint) -> c_int>(call: F) -> Option<f64> {
    let mut value: c_uint = 0;
    (call(&mut value) == SUCCESS).then_some(value as f64)
}

impl Nvml {
    pub fn open() -> Option<Nvml> {
        unsafe {
            let lib = dlopen(c"libnvidia-ml.so.1".as_ptr(), RTLD_NOW);
            if lib.is_null() {
                return None;
            }
            let init: unsafe extern "C" fn() -> c_int = symbol(lib, c"nvmlInit_v2")?;
            let handle: unsafe extern "C" fn(c_uint, *mut Device) -> c_int =
                symbol(lib, c"nvmlDeviceGetHandleByIndex_v2")?;
            let name: Option<unsafe extern "C" fn(Device, *mut c_char, c_uint) -> c_int> =
                symbol(lib, c"nvmlDeviceGetName");
            let api = Api {
                utilization: symbol(lib, c"nvmlDeviceGetUtilizationRates")?,
                temperature: symbol(lib, c"nvmlDeviceGetTemperature")?,
                memory: symbol(lib, c"nvmlDeviceGetMemoryInfo"),
                clock: symbol(lib, c"nvmlDeviceGetClockInfo"),
                max_clock: symbol(lib, c"nvmlDeviceGetMaxClockInfo"),
                power: symbol(lib, c"nvmlDeviceGetPowerUsage"),
                power_limit: symbol(lib, c"nvmlDeviceGetEnforcedPowerLimit"),
                encoder: symbol(lib, c"nvmlDeviceGetEncoderUtilization"),
                decoder: symbol(lib, c"nvmlDeviceGetDecoderUtilization"),
                fans: symbol(lib, c"nvmlDeviceGetNumFans"),
                fan_percent: symbol(lib, c"nvmlDeviceGetFanSpeed_v2"),
                fan_rpm: symbol(lib, c"nvmlDeviceGetFanSpeedRPM"),
                cores: symbol(lib, c"nvmlDeviceGetNumGpuCores"),
                process_samples: symbol(lib, c"nvmlDeviceGetProcessUtilization"),
                compute_processes: symbol(lib, c"nvmlDeviceGetComputeRunningProcesses_v3"),
                graphics_processes: symbol(lib, c"nvmlDeviceGetGraphicsRunningProcesses_v3"),
            };
            if init() != SUCCESS {
                return None;
            }
            let mut device: Device = std::ptr::null_mut();
            if handle(0, &mut device) != SUCCESS {
                return None;
            }
            let mut buffer = [0 as c_char; 96];
            let name = match name {
                Some(get) if get(device, buffer.as_mut_ptr(), buffer.len() as c_uint) == SUCCESS => {
                    CStr::from_ptr(buffer.as_ptr()).to_string_lossy().into_owned()
                }
                _ => String::new(),
            };
            Some(Nvml { api, device, name, last_seen: 0, samples: Vec::new(), infos: Vec::new() })
        }
    }

    pub fn usage(&self) -> Option<f64> {
        let mut u = Utilization::default();
        (unsafe { (self.api.utilization)(self.device, &mut u) } == SUCCESS).then_some(u.gpu as f64)
    }

    pub fn temperature(&self) -> Option<f64> {
        read(|v| unsafe { (self.api.temperature)(self.device, TEMPERATURE_GPU, v) })
    }

    pub fn detail(&self) -> Gpu {
        let d = self.device;
        let mut u = Utilization::default();
        let utilized = unsafe { (self.api.utilization)(d, &mut u) } == SUCCESS;
        let mut m = MemoryInfo::default();
        let memory = self.api.memory.is_some_and(|f| unsafe { f(d, &mut m) } == SUCCESS);
        let pair = |f: Option<GetPair>| {
            let mut period: c_uint = 0;
            f.and_then(|f| read(|v| unsafe { f(d, v, &mut period) }))
        };
        let by = |f: Option<GetU32By>, arg| f.and_then(|f| read(|v| unsafe { f(d, arg, v) }));
        let one = |f: Option<GetU32>| f.and_then(|f| read(|v| unsafe { f(d, v) }));
        Gpu {
            usage: utilized.then_some(u.gpu as f64),
            memory_controller: utilized.then_some(u.memory as f64),
            encoder: pair(self.api.encoder),
            decoder: pair(self.api.decoder),
            clock: by(self.api.clock, CLOCK_GRAPHICS),
            clock_max: by(self.api.max_clock, CLOCK_GRAPHICS),
            power: one(self.api.power).map(|mw| mw / 1000.0),
            power_limit: one(self.api.power_limit).map(|mw| mw / 1000.0),
            vram: memory.then_some(m.used as f64),
            vram_total: memory.then_some(m.total as f64),
            temperature: self.temperature(),
            cores: one(self.api.cores),
        }
    }

    pub fn fans(&self) -> Vec<Fan> {
        let d = self.device;
        let Some(count) = self.api.fans.and_then(|f| read(|v| unsafe { f(d, v) })) else { return Vec::new() };
        (0..count as c_uint)
            .map(|fan| Fan {
                rpm: self.api.fan_rpm.and_then(|f| {
                    let mut info =
                        FanSpeedInfo { version: size_of::<FanSpeedInfo>() as c_uint | 1 << 24, fan, speed: 0 };
                    (unsafe { f(d, &mut info) } == SUCCESS).then_some(info.speed as f64)
                }),
                percent: self.api.fan_percent.and_then(|f| read(|v| unsafe { f(d, fan, v) })),
            })
            .collect()
    }

    pub fn processes(&mut self, out: &mut Vec<ProcessUse>) {
        out.clear();
        for get in [self.api.compute_processes, self.api.graphics_processes].into_iter().flatten() {
            let mut count = self.infos.capacity().max(64) as c_uint;
            self.infos.resize(count as usize, ProcessInfo::default());
            let mut status = unsafe { get(self.device, &mut count, self.infos.as_mut_ptr()) };
            if status == INSUFFICIENT_SIZE {
                self.infos.resize(count as usize + 16, ProcessInfo::default());
                count = self.infos.len() as c_uint;
                status = unsafe { get(self.device, &mut count, self.infos.as_mut_ptr()) };
            }
            if status != SUCCESS {
                continue;
            }
            for info in &self.infos[..count as usize] {
                let vram = if info.used_memory == u64::MAX { 0 } else { info.used_memory };
                match out.iter_mut().find(|p| p.pid == info.pid) {
                    Some(p) => p.vram = p.vram.max(vram),
                    None => out.push(ProcessUse { pid: info.pid, sm: 0.0, vram }),
                }
            }
        }
        let Some(samples) = self.api.process_samples else { return };
        let mut count: c_uint = 0;
        let probe = unsafe { samples(self.device, std::ptr::null_mut(), &mut count, self.last_seen) };
        if probe != INSUFFICIENT_SIZE || count == 0 {
            return;
        }
        self.samples.resize(count as usize, ProcessSample::default());
        if unsafe { samples(self.device, self.samples.as_mut_ptr(), &mut count, self.last_seen) } != SUCCESS {
            return;
        }
        let mut sums: Vec<(u32, f64, u32)> = Vec::new();
        for s in &self.samples[..count as usize] {
            self.last_seen = self.last_seen.max(s.timestamp);
            match sums.iter_mut().find(|e| e.0 == s.pid) {
                Some(e) => {
                    e.1 += s.sm as f64;
                    e.2 += 1;
                }
                None => sums.push((s.pid, s.sm as f64, 1)),
            }
        }
        for (pid, sum, n) in sums {
            let sm = sum / n as f64;
            match out.iter_mut().find(|p| p.pid == pid) {
                Some(p) => p.sm = sm,
                None => out.push(ProcessUse { pid, sm, vram: 0 }),
            }
        }
    }

    pub fn release(&mut self) {
        self.samples = Vec::new();
        self.infos = Vec::new();
        self.last_seen = 0;
    }
}

const _: () = assert!(size_of::<ProcessSample>() == 32 && size_of::<ProcessInfo>() == 24);
