use crate::files;
use crate::json::Json;
use crate::nvml::{Nvml, ProcessUse};
use crate::system;
use std::collections::HashMap;
use std::fmt::Write;
use std::os::unix::fs::MetadataExt;
use std::time::Instant;

pub const MAX_GROUPS: usize = 50;
const MAX_MEMBERS: usize = 50;
const COMM_LENGTH: usize = 15;
const MIN_RATE_INTERVAL: f64 = 0.2;

#[derive(Clone, Copy, PartialEq)]
pub enum Kind {
    Memory,
    Processor,
    Graphics,
}

#[derive(Debug, PartialEq)]
pub struct Stat<'a> {
    pub comm: &'a [u8],
    pub ppid: u32,
    pub ticks: u64,
    pub start: u64,
}

pub fn parse_stat(bytes: &[u8]) -> Option<Stat<'_>> {
    let open = bytes.iter().position(|&b| b == b'(')?;
    let close = bytes.iter().rposition(|&b| b == b')')?;
    let mut rest = files::fields(bytes.get(close + 1..)?);
    let ppid = files::parse(rest.nth(1)?)?;
    let utime: u64 = files::parse(rest.nth(9)?)?;
    let stime: u64 = files::parse(rest.next()?)?;
    let start = files::parse(rest.nth(6)?)?;
    Some(Stat { comm: bytes.get(open + 1..close)?, ppid, ticks: utime + stime, start })
}

pub fn private_memory(statm: &[u8], page: u64) -> Option<u64> {
    let mut fields = files::fields(statm);
    let resident: u64 = files::parse(fields.nth(1)?)?;
    let shared: u64 = files::parse(fields.next()?)?;
    Some(resident.saturating_sub(shared) * page)
}

pub fn is_session(cgroup: &str) -> bool {
    cgroup.contains("/session.slice/")
        || cgroup.ends_with("/init.scope")
        || cgroup.rsplit('/').next().is_some_and(|unit| unit.starts_with("session-") && unit.ends_with(".scope"))
}

pub fn fold(text: &str) -> String {
    text.chars()
        .flat_map(char::to_lowercase)
        .map(|c| match c {
            'à'..='å' | 'ā' | 'ă' | 'ą' => 'a',
            'ç' | 'ć' | 'č' => 'c',
            'è'..='ë' | 'ē' | 'ė' | 'ę' | 'ě' => 'e',
            'ì'..='ï' | 'ī' | 'į' => 'i',
            'ñ' | 'ń' | 'ň' => 'n',
            'ò'..='ö' | 'ø' | 'ō' | 'ő' => 'o',
            'ù'..='ü' | 'ū' | 'ů' | 'ű' | 'ų' => 'u',
            'ý' | 'ÿ' => 'y',
            'š' | 'ś' => 's',
            'ž' | 'ź' | 'ż' => 'z',
            c => c,
        })
        .collect()
}

pub struct Node {
    pub pid: u32,
    pub ppid: u32,
    pub cgroup: u32,
    pub start: u64,
}

fn find(parent: &mut [usize], mut i: usize) -> usize {
    while parent[i] != i {
        parent[i] = parent[parent[i]];
        i = parent[i];
    }
    i
}

pub fn group(nodes: &[Node], locked: &[bool]) -> Vec<(u32, Vec<u32>)> {
    let mut parent: Vec<usize> = (0..nodes.len()).collect();
    let mut first_in_cgroup: Vec<Option<usize>> = vec![None; locked.len()];
    let index = |pid: u32| nodes.binary_search_by_key(&pid, |n| n.pid).ok();
    for (i, node) in nodes.iter().enumerate() {
        let join = |other: usize, parent: &mut Vec<usize>| {
            let (a, b) = (find(parent, i), find(parent, other));
            parent[a] = b;
        };
        match first_in_cgroup.get_mut(node.cgroup as usize) {
            Some(Some(first)) => join(*first, &mut parent),
            Some(slot) => *slot = Some(i),
            None => {}
        }
        if node.ppid > 2
            && let Some(p) = index(node.ppid)
            && !locked.get(nodes[p].cgroup as usize).copied().unwrap_or(false)
        {
            join(p, &mut parent);
        }
    }
    let mut runs: Vec<(usize, u32)> = (0..nodes.len()).map(|i| (find(&mut parent, i), nodes[i].pid)).collect();
    runs.sort_unstable();
    runs.chunk_by(|a, b| a.0 == b.0)
        .map(|run| {
            let pids: Vec<u32> = run.iter().map(|r| r.1).collect();
            let root = pids
                .iter()
                .map(|&pid| &nodes[index(pid).unwrap_or(0)])
                .filter(|n| pids.binary_search(&n.ppid).is_err())
                .min_by_key(|n| (n.start, n.pid))
                .map_or(pids[0], |n| n.pid);
            (root, pids)
        })
        .collect()
}

struct Known {
    start: u64,
    ppid: u32,
    uid: u32,
    group: u32,
    comm: String,
    full: Option<String>,
    ticks: u64,
    memory: u64,
    cpu: Option<f64>,
    gpu: f64,
    vram: u64,
    on_gpu: bool,
    generation: u32,
}

impl Known {
    fn name(&self) -> &str {
        self.full.as_deref().unwrap_or(&self.comm)
    }
}

pub struct Processes {
    known: HashMap<u32, Known>,
    locked_cgroups: Vec<bool>,
    cgroup_index: HashMap<String, u32>,
    gpu: Vec<ProcessUse>,
    generation: u32,
    last_walk: Option<Instant>,
    has_rates: bool,
    uid: u32,
    page: u64,
    ticks_per_second: f64,
    buf: Vec<u8>,
    path: String,
}

struct Group {
    all: Vec<u32>,
    members: Vec<u32>,
    root: u32,
    value: f64,
    vram: u64,
    locked: bool,
    expanded: bool,
}

impl Processes {
    pub fn new() -> Processes {
        Processes {
            known: HashMap::new(),
            locked_cgroups: Vec::new(),
            cgroup_index: HashMap::new(),
            gpu: Vec::new(),
            generation: 0,
            last_walk: None,
            has_rates: false,
            uid: system::uid(),
            page: system::page_size(),
            ticks_per_second: system::ticks_per_second(),
            buf: Vec::with_capacity(1024),
            path: String::with_capacity(32),
        }
    }

    fn cgroup(&mut self, pid: u32) -> u32 {
        self.path.clear();
        let _ = write!(self.path, "/proc/{pid}/cgroup");
        let path = if files::read(&self.path, &mut self.buf) {
            let text = String::from_utf8_lossy(&self.buf);
            text.lines().find_map(|l| l.strip_prefix("0::")).unwrap_or("/").to_owned()
        } else {
            "/".to_owned()
        };
        if let Some(&index) = self.cgroup_index.get(&path) {
            return index;
        }
        let index = self.locked_cgroups.len() as u32;
        self.locked_cgroups.push(is_session(&path));
        self.cgroup_index.insert(path, index);
        index
    }

    fn walk(&mut self) {
        let now = Instant::now();
        let since = self.last_walk.map(|t| now.duration_since(t).as_secs_f64());
        let rates = since.filter(|&s| s >= MIN_RATE_INTERVAL);
        self.generation = self.generation.wrapping_add(1);
        let Ok(dir) = std::fs::read_dir("/proc") else { return };
        for entry in dir.flatten() {
            let Some(pid) = entry.file_name().to_str().and_then(|n| n.parse::<u32>().ok()) else { continue };
            self.path.clear();
            let _ = write!(self.path, "/proc/{pid}");
            let base = self.path.len();
            self.path.push_str("/stat");
            if !files::read(&self.path, &mut self.buf) {
                continue;
            }
            let Some(stat) = parse_stat(&self.buf) else { continue };
            let (ppid, ticks, start) = (stat.ppid, stat.ticks, stat.start);
            let comm = String::from_utf8_lossy(stat.comm);
            let fresh = self.known.get(&pid).is_none_or(|k| k.start != start);
            let previous = if fresh { None } else { self.known.get(&pid).map(|k| k.ticks) };
            if fresh {
                let uid = std::fs::metadata(&self.path[..base]).map(|m| m.uid()).unwrap_or(0);
                let comm = comm.into_owned();
                let group = self.cgroup(pid);
                self.known.insert(
                    pid,
                    Known {
                        start,
                        ppid,
                        uid,
                        group,
                        comm,
                        full: None,
                        ticks,
                        memory: 0,
                        cpu: None,
                        gpu: 0.0,
                        vram: 0,
                        on_gpu: false,
                        generation: 0,
                    },
                );
            } else if let Some(known) = self.known.get_mut(&pid) {
                if known.comm != comm {
                    known.comm.clear();
                    known.comm.push_str(&comm);
                    known.full = None;
                }
                known.ppid = ppid;
            }
            self.path.truncate(base);
            self.path.push_str("/statm");
            let memory =
                if files::read(&self.path, &mut self.buf) { private_memory(&self.buf, self.page) } else { None };
            let Some(known) = self.known.get_mut(&pid) else { continue };
            known.memory = memory.unwrap_or(0);
            if let Some(seconds) = rates {
                let used = previous.map_or(ticks, |before| ticks.saturating_sub(before));
                known.cpu = Some(used as f64 / self.ticks_per_second / seconds * 100.0);
                known.ticks = ticks;
            }
            known.on_gpu = false;
            known.gpu = 0.0;
            known.vram = 0;
            known.generation = self.generation;
        }
        let generation = self.generation;
        self.known.retain(|_, k| k.generation == generation);
        if since.is_none() || rates.is_some() {
            self.last_walk = Some(now);
        }
        self.has_rates |= rates.is_some();
    }

    fn full_name(&mut self, pid: u32) {
        let Some(known) = self.known.get(&pid) else { return };
        if known.full.is_some() || known.comm.len() < COMM_LENGTH {
            return;
        }
        let path = format!("/proc/{pid}/cmdline");
        let full = if files::read(&path, &mut self.buf) {
            let argv0 = self.buf.split(|&b| b == 0).next().unwrap_or_default();
            let base = argv0.rsplit(|&b| b == b'/').next().unwrap_or_default();
            let name = String::from_utf8_lossy(base).into_owned();
            if name.starts_with(known.comm.as_str()) { name } else { known.comm.clone() }
        } else {
            known.comm.clone()
        };
        if let Some(known) = self.known.get_mut(&pid) {
            known.full = Some(full);
        }
    }

    fn value(&self, known: &Known, kind: Kind) -> f64 {
        match kind {
            Kind::Memory => known.memory as f64,
            Kind::Processor => known.cpu.unwrap_or(0.0),
            Kind::Graphics => known.gpu,
        }
    }

    pub fn list(&mut self, kind: Kind, query: &str, limit: usize, nvml: Option<&mut Nvml>, json: &mut Json) {
        self.walk();
        if kind == Kind::Graphics {
            if let Some(nvml) = nvml {
                nvml.processes(&mut self.gpu);
            }
            for use_ in &self.gpu {
                if let Some(known) = self.known.get_mut(&use_.pid) {
                    known.gpu = use_.sm;
                    known.vram = use_.vram;
                    known.on_gpu = true;
                }
            }
        }
        let nodes: Vec<Node> = {
            let mut pids: Vec<u32> = self.known.keys().copied().collect();
            pids.sort_unstable();
            pids.iter()
                .map(|pid| {
                    let k = &self.known[pid];
                    Node { pid: *pid, ppid: k.ppid, cgroup: k.group, start: k.start }
                })
                .collect()
        };
        let mut groups: Vec<Group> = Vec::new();
        for (root, all) in group(&nodes, &self.locked_cgroups) {
            let root_known = &self.known[&root];
            let locked = self.locked_cgroups[root_known.group as usize] || root_known.uid != self.uid;
            let members: Vec<u32> =
                all.iter().copied().filter(|p| kind != Kind::Graphics || self.known[p].on_gpu).collect();
            if members.is_empty() {
                continue;
            }
            groups.push(Group { all, members, root, value: 0.0, vram: 0, locked, expanded: false });
        }
        let roots: Vec<u32> = groups.iter().map(|g| g.root).collect();
        for pid in roots {
            self.full_name(pid);
        }

        let needle = fold(query.trim());
        if !needle.is_empty() {
            let mut pids: Vec<u32> = groups.iter().flat_map(|g| g.members.iter().copied()).collect();
            pids.retain(|p| self.known[p].comm.len() >= COMM_LENGTH);
            for pid in pids {
                self.full_name(pid);
            }
            let known = &self.known;
            groups.retain_mut(|group| {
                if fold(known[&group.root].name()).contains(&needle) {
                    return true;
                }
                group.members.retain(|p| fold(known[p].name()).contains(&needle));
                group.expanded = true;
                !group.members.is_empty()
            });
        }

        for group in &mut groups {
            group.value = group.members.iter().map(|p| self.value(&self.known[p], kind)).sum();
            group.vram = group.members.iter().map(|p| self.known[p].vram).sum();
            let known = &self.known;
            group.members.sort_by(|a, b| {
                let (ka, kb) = (&known[a], &known[b]);
                let (va, vb) = (self.value(ka, kind), self.value(kb, kind));
                vb.total_cmp(&va).then(kb.vram.cmp(&ka.vram)).then(a.cmp(b))
            });
        }
        let known = &self.known;
        groups.sort_by(|a, b| {
            b.value
                .total_cmp(&a.value)
                .then(b.vram.cmp(&a.vram))
                .then_with(|| known[&a.root].name().cmp(known[&b.root].name()))
        });

        let shown = groups.len().min(limit.clamp(1, MAX_GROUPS));
        for group in &groups[..shown] {
            for i in 0..group.members.len().min(MAX_MEMBERS) {
                self.full_name(group.members[i]);
            }
        }

        let percent = kind != Kind::Memory;
        json.key("baseline").boolean(kind == Kind::Processor && !self.has_rates);
        json.key("total").integer(groups.len() as u64);
        json.key("groups").open_list();
        for group in &groups[..shown] {
            let root = &self.known[&group.root];
            json.open().key("name").string(root.name());
            json.key("key").string(&format!("{}:{}", group.root, root.start));
            json.field("value", Some(group.value), if percent { 2 } else { 0 });
            if kind == Kind::Graphics {
                json.field("vram", Some(group.vram as f64), 0);
            }
            json.key("count").integer(group.members.len() as u64);
            json.key("locked").boolean(group.locked);
            json.key("expanded").boolean(group.expanded);
            json.key("targets").string(&self.targets(group));
            json.key("members").open_list();
            for &pid in group.members.iter().take(MAX_MEMBERS) {
                let k = &self.known[&pid];
                json.open().key("name").string(k.name());
                json.key("pid").integer(pid as u64);
                json.field("value", Some(self.value(k, kind)), if percent { 2 } else { 0 });
                if kind == Kind::Graphics {
                    json.field("vram", Some(k.vram as f64), 0);
                }
                json.key("locked").boolean(group.locked || k.uid != self.uid || self.locked_cgroups[k.group as usize]);
                json.key("target").string(&format!("{pid}:{}", k.start));
                json.close();
            }
            json.close_list().close();
        }
        json.close_list();
    }

    fn targets(&self, group: &Group) -> String {
        let mut targets = String::new();
        if group.locked {
            return targets;
        }
        for pid in &group.all {
            let known = &self.known[pid];
            if known.uid == self.uid && !self.locked_cgroups[known.group as usize] {
                if !targets.is_empty() {
                    targets.push(',');
                }
                let _ = write!(targets, "{pid}:{}", known.start);
            }
        }
        targets
    }

    pub fn terminate(&mut self, targets: &str, force: bool) -> u32 {
        let mut sent = 0;
        for target in targets.split(',') {
            let Some((pid, start)) = target.split_once(':') else { continue };
            let (Ok(pid), Ok(start)) = (pid.parse::<u32>(), start.parse::<u64>()) else { continue };
            let path = format!("/proc/{pid}/stat");
            if !files::read(&path, &mut self.buf) {
                continue;
            }
            if parse_stat(&self.buf).is_none_or(|s| s.start != start) {
                continue;
            }
            let owned = std::fs::metadata(format!("/proc/{pid}")).is_ok_and(|m| m.uid() == self.uid);
            let session = files::text(format!("/proc/{pid}/cgroup"))
                .and_then(|c| c.lines().find_map(|l| l.strip_prefix("0::").map(is_session)))
                .unwrap_or(true);
            if owned && !session && system::signal(pid, force) {
                sent += 1;
            }
        }
        sent
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const STAT: &[u8] = b"4242 (Web Content (x)) S 4100 4242 4242 0 -1 4194560 100 0 0 0 \
1500 250 0 0 20 0 30 0 987654 1000000 500 18446744073709551615";

    #[test]
    fn stat_keeps_parentheses_inside_the_name_and_adds_user_and_system_ticks() {
        let stat = parse_stat(STAT).unwrap();
        assert_eq!(stat, Stat { comm: b"Web Content (x)", ppid: 4100, ticks: 1750, start: 987654 });
    }

    #[test]
    fn private_memory_is_resident_minus_shared_pages() {
        assert_eq!(private_memory(b"5629 4040 2753 20 0 1109 0\n", 4096), Some((4040 - 2753) * 4096));
        assert_eq!(private_memory(b"5629", 4096), None);
    }

    #[test]
    fn session_services_init_and_login_scopes_are_locked_and_apps_are_not() {
        let base = "/user.slice/user-1000.slice";
        assert!(is_session(&format!("{base}/user@1000.service/session.slice/plasma-kwin_wayland.service")));
        assert!(is_session(&format!("{base}/user@1000.service/init.scope")));
        assert!(is_session(&format!("{base}/session-2.scope")));
        assert!(!is_session(&format!("{base}/user@1000.service/app.slice/app-org.chromium.Chromium-293588.scope")));
        assert!(!is_session(&format!("{base}/user@1000.service/background.slice/plasma-ksystemstats.service")));
    }

    fn node(pid: u32, ppid: u32, cgroup: u32, start: u64) -> Node {
        Node { pid, ppid, cgroup, start }
    }

    fn sorted(nodes: &[Node], locked: &[bool]) -> Vec<(u32, Vec<u32>)> {
        let mut groups = group(nodes, locked);
        groups.sort();
        groups
    }

    #[test]
    fn an_app_split_across_units_is_one_group_named_by_its_oldest_root() {
        let locked = [true, false, false];
        let nodes = [
            node(2004, 1, 0, 10),
            node(5000, 2004, 1, 100),
            node(5001, 2004, 2, 101),
            node(5002, 5000, 2, 102),
            node(5003, 5002, 2, 103),
        ];
        assert_eq!(sorted(&nodes, &locked), [(2004, vec![2004]), (5000, vec![5000, 5001, 5002, 5003])]);
    }

    #[test]
    fn children_of_session_services_stay_in_their_own_groups() {
        let locked = [true, false, false];
        let nodes = [node(2404, 2004, 0, 10), node(7000, 2404, 1, 50), node(7100, 2404, 2, 60)];
        assert_eq!(sorted(&nodes, &locked), [(2404, vec![2404]), (7000, vec![7000]), (7100, vec![7100])]);
    }

    #[test]
    fn kernel_threads_share_the_root_cgroup_under_kthreadd() {
        let locked = [false, true];
        let nodes = [node(1, 0, 1, 1), node(2, 0, 0, 1), node(3, 2, 0, 2), node(9, 2, 0, 5)];
        assert_eq!(sorted(&nodes, &locked), [(1, vec![1]), (2, vec![2, 3, 9])]);
    }

    #[test]
    fn search_ignores_case_and_accents() {
        assert_eq!(fold("Música ÑANDÚ"), "musica nandu");
        assert!(fold("Configuración del sistema").contains(&fold("CONFIGURACION")));
    }
}
