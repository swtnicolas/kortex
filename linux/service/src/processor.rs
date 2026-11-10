use crate::files;
use crate::json::Json;
use std::collections::HashSet;
use std::time::{Duration, Instant};

#[derive(Default, Clone, Copy, PartialEq, Debug)]
pub struct Times {
    pub busy: u64,
    pub total: u64,
}

impl Times {
    pub fn parse(stat: &[u8]) -> Option<Times> {
        let line = stat.split(|&b| b == b'\n').next()?;
        let mut fields = files::fields(line);
        if fields.next()? != b"cpu" {
            return None;
        }
        let ticks: Vec<u64> = fields.take(8).filter_map(files::parse).collect();
        if ticks.len() < 5 {
            return None;
        }
        let total: u64 = ticks.iter().sum();
        let idle = ticks[3] + ticks[4];
        Some(Times { busy: total - idle, total })
    }

    pub fn usage_since(&self, earlier: &Times) -> Option<f64> {
        let total = self.total.checked_sub(earlier.total)?;
        let busy = self.busy.checked_sub(earlier.busy)?;
        (total > 0).then(|| busy.min(total) as f64 / total as f64 * 100.0)
    }
}

struct Topology {
    cpus: Vec<String>,
    cores: usize,
    max_khz: Option<f64>,
}

const MIN_INTERVAL: Duration = Duration::from_millis(250);

pub struct Processor {
    last: Option<Times>,
    at: Instant,
    latest: Option<f64>,
    topology: Option<Topology>,
    buf: Vec<u8>,
}

impl Processor {
    pub fn new() -> Processor {
        let mut processor =
            Processor { last: None, at: Instant::now(), latest: None, topology: None, buf: Vec::with_capacity(4096) };
        processor.usage();
        processor
    }

    pub fn usage(&mut self) -> Option<f64> {
        if self.latest.is_some() && self.at.elapsed() < MIN_INTERVAL {
            return self.latest;
        }
        let now = if files::read("/proc/stat", &mut self.buf) { Times::parse(&self.buf) } else { None };
        let Some(now) = now else { return self.latest };
        if let Some(last) = self.last {
            self.latest = now.usage_since(&last).or(self.latest);
        }
        self.last = Some(now);
        self.at = Instant::now();
        self.latest
    }

    fn topology(&mut self) -> &Topology {
        self.topology.get_or_insert_with(|| {
            let mut cpus: Vec<String> = std::fs::read_dir("/sys/devices/system/cpu")
                .into_iter()
                .flatten()
                .flatten()
                .map(|e| e.file_name().to_string_lossy().into_owned())
                .filter(|n| n.len() > 3 && n.starts_with("cpu") && n[3..].bytes().all(|b| b.is_ascii_digit()))
                .map(|n| format!("/sys/devices/system/cpu/{n}"))
                .collect();
            cpus.sort();
            let cores: HashSet<(String, String)> = cpus
                .iter()
                .filter_map(|c| {
                    Some((
                        files::text(format!("{c}/topology/physical_package_id"))?,
                        files::text(format!("{c}/topology/core_id"))?,
                    ))
                })
                .collect();
            let max_khz = cpus.first().and_then(|c| files::text(format!("{c}/cpufreq/cpuinfo_max_freq"))?.parse().ok());
            Topology { cores: cores.len(), cpus, max_khz }
        })
    }

    fn frequency(&mut self) -> Option<f64> {
        let topology = self.topology.as_ref()?;
        let mut sum = 0.0;
        let mut count = 0;
        for cpu in &topology.cpus {
            if let Some(khz) = files::value::<f64>(format!("{cpu}/cpufreq/scaling_cur_freq"), &mut self.buf) {
                sum += khz;
                count += 1;
            }
        }
        (count > 0).then(|| sum / count as f64 / 1000.0)
    }

    pub fn detail(&mut self, usage: Option<f64>, json: &mut Json) {
        let (threads, cores, max) = {
            let t = self.topology();
            (t.cpus.len(), t.cores, t.max_khz.map(|k| k / 1000.0))
        };
        let frequency = self.frequency();
        json.field("usage", usage, 1)
            .field("frequency", frequency, 0)
            .field("frequencyMax", max, 0)
            .field("cores", Some(cores as f64), 0)
            .field("threads", Some(threads as f64), 0);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn counts_idle_and_iowait_as_idle_and_leaves_guest_time_out() {
        let times = Times::parse(b"cpu  100 10 50 800 40 0 0 0 30 0\ncpu0 1 2 3 4 5 6 7 8 9 10\n").unwrap();
        assert_eq!(times, Times { busy: 160, total: 1000 });
    }

    #[test]
    fn usage_is_the_busy_share_of_the_ticks_between_two_readings() {
        let before = Times { busy: 160, total: 1000 };
        let after = Times { busy: 260, total: 1400 };
        assert_eq!(after.usage_since(&before), Some(25.0));
        assert_eq!(after.usage_since(&after), None);
    }

    #[test]
    fn rejects_a_stat_file_without_the_aggregate_line() {
        assert_eq!(Times::parse(b"cpu0 1 2 3 4 5 6 7 8\n"), None);
    }
}
