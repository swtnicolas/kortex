use crate::files;
use crate::json::Json;
use std::path::PathBuf;

#[derive(Default, Clone, Copy, PartialEq, Debug)]
pub struct Info {
    pub total: u64,
    pub free: u64,
    pub available: u64,
    pub anon: u64,
    pub shmem: u64,
    pub swap_total: u64,
    pub swap_free: u64,
}

#[derive(PartialEq, Debug)]
pub struct Breakdown {
    pub apps: u64,
    pub system: u64,
    pub compressed: u64,
    pub cache: u64,
    pub free: u64,
}

impl Info {
    pub fn parse(bytes: &[u8]) -> Info {
        let mut info = Info::default();
        for line in bytes.split(|&b| b == b'\n') {
            let mut fields = files::fields(line);
            let (Some(key), Some(value)) = (fields.next(), fields.next()) else { continue };
            let Some(kib) = files::parse::<u64>(value) else { continue };
            let bytes = kib * 1024;
            match key {
                b"MemTotal:" => info.total = bytes,
                b"MemFree:" => info.free = bytes,
                b"MemAvailable:" => info.available = bytes,
                b"AnonPages:" => info.anon = bytes,
                b"Shmem:" => info.shmem = bytes,
                b"SwapTotal:" => info.swap_total = bytes,
                b"SwapFree:" => info.swap_free = bytes,
                _ => {}
            }
        }
        info
    }

    pub fn used(&self) -> u64 {
        self.total.saturating_sub(self.available)
    }

    pub fn usage(&self) -> Option<f64> {
        (self.total > 0).then(|| self.used() as f64 / self.total as f64 * 100.0)
    }

    pub fn breakdown(&self, compressed: u64) -> Breakdown {
        let used = self.used();
        let apps = (self.anon + self.shmem).min(used);
        let compressed = compressed.min(used - apps);
        Breakdown {
            apps,
            system: used - apps - compressed,
            compressed,
            cache: self.available.saturating_sub(self.free),
            free: self.free.min(self.available),
        }
    }
}

pub struct Memory {
    zram: Vec<PathBuf>,
    buf: Vec<u8>,
}

impl Memory {
    pub fn new() -> Memory {
        let zram = std::fs::read_dir("/sys/block")
            .into_iter()
            .flatten()
            .flatten()
            .filter(|e| e.file_name().to_string_lossy().starts_with("zram"))
            .map(|e| e.path().join("mm_stat"))
            .collect();
        Memory { zram, buf: Vec::with_capacity(2048) }
    }

    pub fn info(&mut self) -> Option<Info> {
        files::read("/proc/meminfo", &mut self.buf).then(|| Info::parse(&self.buf))
    }

    fn compressed(&mut self) -> u64 {
        let mut total = 0;
        for path in &self.zram {
            if files::read(path, &mut self.buf) {
                total += files::fields(&self.buf).nth(2).and_then(files::parse::<u64>).unwrap_or(0);
            }
        }
        total
    }

    fn pressure(&mut self) -> Option<f64> {
        if !files::read("/proc/pressure/memory", &mut self.buf) {
            return None;
        }
        let line = self.buf.split(|&b| b == b'\n').find(|l| l.starts_with(b"some "))?;
        let avg10 = files::fields(line).find_map(|f| f.strip_prefix(b"avg10="))?;
        files::parse(avg10)
    }

    fn disk_swap(&mut self) -> u64 {
        if files::read("/proc/swaps", &mut self.buf) { disk_swap(&self.buf) } else { 0 }
    }

    pub fn detail(&mut self, info: &Info, json: &mut Json) {
        let parts = info.breakdown(self.compressed());
        let pressure = self.pressure();
        let swap = info.swap_total.saturating_sub(info.swap_free);
        let swap_disk = if swap > 0 { self.disk_swap() } else { 0 };
        json.field("total", Some(info.total as f64), 0)
            .field("used", Some(info.used() as f64), 0)
            .field("apps", Some(parts.apps as f64), 0)
            .field("system", Some(parts.system as f64), 0)
            .field("compressed", Some(parts.compressed as f64), 0)
            .field("cache", Some(parts.cache as f64), 0)
            .field("free", Some(parts.free as f64), 0)
            .field("swap", Some(swap as f64), 0)
            .field("swapDisk", Some(swap_disk as f64), 0)
            .field("swapTotal", Some(info.swap_total as f64), 0)
            .field("pressure", pressure, 2);
    }
}

fn disk_swap(swaps: &[u8]) -> u64 {
    swaps
        .split(|&b| b == b'\n')
        .filter_map(|line| {
            let mut fields = files::fields(line);
            let name = fields.next()?;
            if name.starts_with(b"/dev/zram") {
                return None;
            }
            files::parse::<u64>(fields.nth(2)?)
        })
        .sum::<u64>()
        * 1024
}

#[cfg(test)]
mod tests {
    use super::*;

    const MEMINFO: &[u8] = b"MemTotal:       32724296 kB\nMemFree:        16391616 kB\n\
MemAvailable:   25449636 kB\nBuffers:              64 kB\nCached:          8704332 kB\n\
SwapTotal:      32723964 kB\nSwapFree:       31966248 kB\nAnonPages:       4706440 kB\n\
Shmem:            122292 kB\nHugePages_Total:       0\n";

    #[test]
    fn parses_the_fields_it_uses_in_bytes() {
        let info = Info::parse(MEMINFO);
        assert_eq!(info.total, 32724296 * 1024);
        assert_eq!(info.available, 25449636 * 1024);
        assert_eq!(info.anon, 4706440 * 1024);
        assert_eq!(info.shmem, 122292 * 1024);
        assert_eq!(info.swap_free, 31966248 * 1024);
    }

    #[test]
    fn usage_is_what_memavailable_leaves_out_of_the_total() {
        let info = Info { total: 1000, available: 300, ..Info::default() };
        assert_eq!(info.usage(), Some(70.0));
        assert_eq!(Info::default().usage(), None);
    }

    #[test]
    fn breakdown_splits_the_total_with_zram_taken_out_of_the_system_part() {
        let info = Info { total: 1000, free: 200, available: 500, anon: 300, shmem: 50, ..Info::default() };
        let parts = info.breakdown(40);
        assert_eq!(parts, Breakdown { apps: 350, system: 110, compressed: 40, cache: 300, free: 200 });
        assert_eq!(parts.apps + parts.system + parts.compressed + parts.cache + parts.free, info.total);
    }

    #[test]
    fn disk_swap_counts_every_swap_but_zram() {
        let swaps = b"Filename\t\t\t\tType\t\tSize\t\tUsed\t\tPriority\n\
/dev/zram0                              partition\t32723964\t966784\t\t100\n\
/dev/nvme0n1p3                          partition\t8388604\t1024\t\t-2\n\
/swap/swapfile                          file\t\t4194300\t512\t\t-3\n";
        assert_eq!(disk_swap(swaps), (1024 + 512) * 1024);
    }

    #[test]
    fn breakdown_never_goes_past_the_used_memory() {
        let info = Info { total: 1000, free: 400, available: 600, anon: 450, shmem: 0, ..Info::default() };
        let parts = info.breakdown(100);
        assert_eq!((parts.apps, parts.system, parts.compressed), (400, 0, 0));
    }
}
