use crate::files;
use std::collections::VecDeque;
use std::path::{Path, PathBuf};

const SMOOTHING_WINDOW: usize = 3;
const ZONES: [&str; 6] = ["CPU", "GPU", "Placa", "SSD", "Red", "Otros"];
const PLAUSIBLE: std::ops::RangeInclusive<f64> = 0.5..=150.0;

struct Sensor {
    zone: &'static str,
    input: PathBuf,
}

pub struct BoardFan {
    pub name: String,
    input: PathBuf,
}

pub struct Zone {
    pub name: &'static str,
    pub max: f64,
    pub average: f64,
}

pub struct Temperatures {
    sensors: Vec<Sensor>,
    package: Option<PathBuf>,
    pub fans: Vec<BoardFan>,
    recent: VecDeque<f64>,
    buf: Vec<u8>,
}

pub fn zone_of(driver: &str) -> &'static str {
    match driver {
        "coretemp" | "k10temp" => "CPU",
        "nvme" => "SSD",
        "nct6775" | "nct6683" => "Placa",
        d if d.starts_with("r8169") => "Red",
        _ => "Otros",
    }
}

pub fn smooth(recent: &mut VecDeque<f64>, hottest: f64) -> f64 {
    recent.push_back(hottest);
    if recent.len() > SMOOTHING_WINDOW {
        recent.pop_front();
    }
    recent.iter().sum::<f64>() / recent.len() as f64
}

pub fn summarize(readings: &[(&'static str, f64)]) -> Vec<Zone> {
    let mut zones: Vec<(Zone, usize)> = Vec::new();
    for &(name, value) in readings {
        match zones.iter_mut().find(|(z, _)| z.name == name) {
            Some((zone, count)) => {
                zone.max = zone.max.max(value);
                zone.average += value;
                *count += 1;
            }
            None => zones.push((Zone { name, max: value, average: value }, 1)),
        }
    }
    zones
        .into_iter()
        .map(|(mut zone, count)| {
            zone.average /= count as f64;
            zone
        })
        .collect()
}

fn celsius(path: &Path, buf: &mut Vec<u8>) -> Option<f64> {
    let value = files::value::<f64>(path, buf)? / 1000.0;
    PLAUSIBLE.contains(&value).then_some(value)
}

fn is_package(label: &str) -> bool {
    label.starts_with("Package id") || label == "Tctl" || label == "Tdie"
}

impl Temperatures {
    pub fn new() -> Temperatures {
        let mut sensors = Vec::new();
        let mut fans = Vec::new();
        let mut package = None;
        let mut hwmons: Vec<PathBuf> =
            std::fs::read_dir("/sys/class/hwmon").into_iter().flatten().flatten().map(|e| e.path()).collect();
        hwmons.sort();
        for hwmon in hwmons {
            let driver = files::text(hwmon.join("name")).unwrap_or_default();
            let zone = zone_of(&driver);
            let mut entries: Vec<String> = std::fs::read_dir(&hwmon)
                .into_iter()
                .flatten()
                .flatten()
                .map(|e| e.file_name().to_string_lossy().into_owned())
                .filter(|n| n.ends_with("_input"))
                .collect();
            entries.sort();
            for entry in entries {
                let base = entry.trim_end_matches("_input");
                let label = files::text(hwmon.join(format!("{base}_label")));
                if base.starts_with("temp") {
                    let input = hwmon.join(&entry);
                    if zone == "CPU" && package.is_none() && label.as_deref().is_some_and(is_package) {
                        package = Some(input.clone());
                    }
                    sensors.push(Sensor { zone, input });
                } else if base.starts_with("fan") {
                    let name = label.unwrap_or_else(|| format!("Ventilador {}", &base[3..]));
                    fans.push(BoardFan { name, input: hwmon.join(&entry) });
                }
            }
        }
        if package.is_none() {
            package = sensors.iter().find(|s| s.zone == "CPU").map(|s| s.input.clone());
        }
        Temperatures { sensors, package, fans, recent: VecDeque::new(), buf: Vec::with_capacity(64) }
    }

    pub fn peak(&mut self, gpu: Option<f64>) -> Option<f64> {
        let cpu = self.package.as_deref().and_then(|path| celsius(path, &mut self.buf));
        let hottest = match (cpu, gpu) {
            (Some(c), Some(g)) => c.max(g),
            (c, g) => c.or(g)?,
        };
        Some(smooth(&mut self.recent, hottest))
    }

    pub fn zones(&mut self, gpu: Option<f64>) -> Vec<Zone> {
        let readings: Vec<_> = self
            .sensors
            .iter()
            .filter_map(|s| Some((s.zone, celsius(&s.input, &mut self.buf)?)))
            .collect();
        let mut zones = summarize(&readings);
        if let Some(g) = gpu {
            zones.push(Zone { name: "GPU", max: g, average: g });
        }
        zones.sort_by_key(|z| ZONES.iter().position(|&name| name == z.name));
        zones
    }

    pub fn fan_rpm(&mut self, index: usize) -> Option<f64> {
        files::value(&self.fans.get(index)?.input, &mut self.buf)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn smoothing_averages_the_last_three_peaks() {
        let mut recent = VecDeque::new();
        assert_eq!(smooth(&mut recent, 60.0), 60.0);
        assert_eq!(smooth(&mut recent, 66.0), 63.0);
        assert_eq!(smooth(&mut recent, 66.0), 64.0);
        assert_eq!(smooth(&mut recent, 72.0), 68.0);
    }

    #[test]
    fn zones_keep_first_seen_order_with_max_and_average() {
        let zones = summarize(&[("CPU", 40.0), ("CPU", 50.0), ("GPU", 55.0), ("SSD", 35.0), ("CPU", 45.0)]);
        let summary: Vec<_> = zones.iter().map(|z| (z.name, z.max, z.average)).collect();
        assert_eq!(summary, [("CPU", 50.0, 45.0), ("GPU", 55.0, 55.0), ("SSD", 35.0, 35.0)]);
    }

    #[test]
    fn classifies_hwmon_drivers_into_zones() {
        assert_eq!(zone_of("coretemp"), "CPU");
        assert_eq!(zone_of("nvme"), "SSD");
        assert_eq!(zone_of("r8169_0_500:00"), "Red");
        assert_eq!(zone_of("hidpp_battery_0"), "Otros");
    }
}
