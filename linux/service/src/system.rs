unsafe extern "C" {
    fn sysconf(name: i32) -> i64;
    fn getuid() -> u32;
    fn kill(pid: i32, signal: i32) -> i32;
    fn malloc_trim(pad: usize) -> i32;
}

const SC_CLK_TCK: i32 = 2;
const SC_PAGESIZE: i32 = 30;
const SIGTERM: i32 = 15;
const SIGKILL: i32 = 9;

pub fn page_size() -> u64 {
    unsafe { sysconf(SC_PAGESIZE) }.max(1) as u64
}

pub fn ticks_per_second() -> f64 {
    unsafe { sysconf(SC_CLK_TCK) }.max(1) as f64
}

pub fn uid() -> u32 {
    unsafe { getuid() }
}

pub fn signal(pid: u32, force: bool) -> bool {
    unsafe { kill(pid as i32, if force { SIGKILL } else { SIGTERM }) == 0 }
}

pub fn trim() {
    unsafe { malloc_trim(0) };
}
