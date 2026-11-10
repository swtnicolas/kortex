use std::ffi::{CStr, c_char, c_int, c_void};
use std::time::Duration;

#[repr(C)]
pub struct Message {
    _private: [u8; 0],
}

#[repr(C)]
struct Bus {
    _private: [u8; 0],
}

pub type Handler = unsafe extern "C" fn(*mut Message, *mut c_void, *mut c_void) -> c_int;

#[link(name = "systemd")]
unsafe extern "C" {
    fn sd_bus_open_user(ret: *mut *mut Bus) -> c_int;
    fn sd_bus_request_name(bus: *mut Bus, name: *const c_char, flags: u64) -> c_int;
    fn sd_bus_add_object(
        bus: *mut Bus,
        slot: *mut *mut c_void,
        path: *const c_char,
        callback: Handler,
        userdata: *mut c_void,
    ) -> c_int;
    fn sd_bus_process(bus: *mut Bus, ret: *mut *mut Message) -> c_int;
    fn sd_bus_wait(bus: *mut Bus, timeout_usec: u64) -> c_int;
    fn sd_bus_message_is_method_call(m: *mut Message, interface: *const c_char, member: *const c_char) -> c_int;
    fn sd_bus_message_read(m: *mut Message, types: *const c_char, ...) -> c_int;
    fn sd_bus_reply_method_return(m: *mut Message, types: *const c_char, ...) -> c_int;
    fn sd_bus_message_get_bus(m: *mut Message) -> *mut Bus;
    fn sd_bus_emit_signal(
        bus: *mut Bus,
        path: *const c_char,
        interface: *const c_char,
        member: *const c_char,
        types: *const c_char,
        ...
    ) -> c_int;
}

pub struct Connection(*mut Bus);

impl Connection {
    pub fn user() -> Option<Connection> {
        let mut bus = std::ptr::null_mut();
        (unsafe { sd_bus_open_user(&mut bus) } >= 0).then_some(Connection(bus))
    }

    pub fn serve(&self, path: &CStr, handler: Handler, userdata: *mut c_void) -> bool {
        unsafe { sd_bus_add_object(self.0, std::ptr::null_mut(), path.as_ptr(), handler, userdata) >= 0 }
    }

    pub fn own(&self, name: &CStr) -> bool {
        unsafe { sd_bus_request_name(self.0, name.as_ptr(), 0) >= 0 }
    }

    pub fn process(&self) -> c_int {
        unsafe { sd_bus_process(self.0, std::ptr::null_mut()) }
    }

    pub fn wait(&self, timeout: Duration) -> c_int {
        unsafe { sd_bus_wait(self.0, timeout.as_micros() as u64) }
    }
}

pub struct Call(pub *mut Message);

impl Call {
    pub fn is(&self, interface: &CStr, member: &CStr) -> bool {
        unsafe { sd_bus_message_is_method_call(self.0, interface.as_ptr(), member.as_ptr()) > 0 }
    }

    pub fn string(&self) -> Option<String> {
        let mut value: *const c_char = std::ptr::null();
        if unsafe { sd_bus_message_read(self.0, c"s".as_ptr(), &mut value) } <= 0 || value.is_null() {
            return None;
        }
        Some(unsafe { CStr::from_ptr(value) }.to_string_lossy().into_owned())
    }

    pub fn unsigned(&self) -> Option<u32> {
        let mut value: u32 = 0;
        (unsafe { sd_bus_message_read(self.0, c"u".as_ptr(), &mut value) } > 0).then_some(value)
    }

    pub fn boolean(&self) -> Option<bool> {
        let mut value: c_int = 0;
        (unsafe { sd_bus_message_read(self.0, c"b".as_ptr(), &mut value) } > 0).then_some(value != 0)
    }

    pub fn reply_string(&self, nul_terminated: &[u8]) -> c_int {
        let text = CStr::from_bytes_until_nul(nul_terminated).unwrap_or(c"");
        let status = unsafe { sd_bus_reply_method_return(self.0, c"s".as_ptr(), text.as_ptr()) };
        if status < 0 { status } else { 1 }
    }

    pub fn reply_unsigned(&self, value: u32) -> c_int {
        let status = unsafe { sd_bus_reply_method_return(self.0, c"u".as_ptr(), value) };
        if status < 0 { status } else { 1 }
    }

    pub fn reply_empty(&self) -> c_int {
        let status = unsafe { sd_bus_reply_method_return(self.0, std::ptr::null()) };
        if status < 0 { status } else { 1 }
    }

    pub fn signal_string(&self, path: &CStr, interface: &CStr, member: &CStr, nul_terminated: &[u8]) {
        let text = CStr::from_bytes_until_nul(nul_terminated).unwrap_or(c"");
        unsafe {
            let bus = sd_bus_message_get_bus(self.0);
            sd_bus_emit_signal(bus, path.as_ptr(), interface.as_ptr(), member.as_ptr(), c"s".as_ptr(), text.as_ptr());
        }
    }
}
