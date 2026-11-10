use crate::files;
use crate::processes::parse_stat;
use crate::system;
use std::time::Instant;

#[derive(Default)]
pub struct Split {
    pub latest: Option<f64>,
    pub closed: Option<f64>,
    opened_during_interval: bool,
}

impl Split {
    pub fn opened(&mut self) {
        self.opened_during_interval = true;
    }

    pub fn record(&mut self, cpu: Option<f64>, open: bool) {
        if open {
            self.opened_during_interval = true;
        }
        if let Some(cpu) = cpu {
            self.latest = Some(cpu);
            if !self.opened_during_interval {
                self.closed = Some(cpu);
            }
        }
        self.opened_during_interval = open;
    }
}

pub struct Usage {
    pub cpu: Split,
    pub ram: Option<f64>,
    pub closed_ram: Option<f64>,
    last: Option<(u64, Instant)>,
    ticks_per_second: f64,
    buf: Vec<u8>,
}

impl Usage {
    pub fn new() -> Usage {
        let mut usage = Usage {
            cpu: Split::default(),
            ram: None,
            closed_ram: None,
            last: None,
            ticks_per_second: system::ticks_per_second(),
            buf: Vec::with_capacity(1024),
        };
        usage.last = usage.ticks().map(|t| (t, Instant::now()));
        usage
    }

    fn ticks(&mut self) -> Option<u64> {
        files::read("/proc/self/stat", &mut self.buf).then(|| parse_stat(&self.buf).map(|s| s.ticks))?
    }

    fn proportional(&mut self) -> Option<f64> {
        if !files::read("/proc/self/smaps_rollup", &mut self.buf) {
            return None;
        }
        let line = self.buf.split(|&b| b == b'\n').find(|l| l.starts_with(b"Pss:"))?;
        let kib: f64 = files::parse(files::fields(line).nth(1)?)?;
        Some(kib * 1024.0)
    }

    pub fn sample(&mut self, open: bool) {
        let now = Instant::now();
        let ticks = self.ticks();
        let cpu = match (ticks, self.last) {
            (Some(t), Some((t0, at))) => {
                let seconds = now.duration_since(at).as_secs_f64();
                (seconds > 0.2).then(|| t.saturating_sub(t0) as f64 / self.ticks_per_second / seconds * 100.0)
            }
            _ => None,
        };
        if cpu.is_some() || self.last.is_none() {
            self.last = ticks.map(|t| (t, now));
        }
        self.cpu.record(cpu, open);
        self.ram = self.proportional();
        if !open {
            self.closed_ram = self.ram;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn closed_cpu_only_comes_from_intervals_closed_from_start_to_end() {
        let mut split = Split::default();
        split.record(Some(0.1), false);
        assert_eq!((split.latest, split.closed), (Some(0.1), Some(0.1)));

        split.opened();
        split.record(Some(3.0), false);
        assert_eq!((split.latest, split.closed), (Some(3.0), Some(0.1)));

        split.record(Some(0.2), false);
        assert_eq!(split.closed, Some(0.2));
    }

    #[test]
    fn an_interval_that_starts_open_does_not_count_as_closed() {
        let mut split = Split::default();
        split.record(Some(4.0), true);
        split.record(Some(2.5), false);
        assert_eq!((split.latest, split.closed), (Some(2.5), None));
    }
}
