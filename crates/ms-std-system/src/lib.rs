//! `@std/system` natives. Symbols are `msstd_system_<name>`.
//!
//! Fallible functions return a `STATUS_*` code (`0` ok) and write results only on success; for
//! `STATUS_FAILED` the text comes from `msstd_system_failure_message`. A record result crosses as
//! one getter per field (`msstd_system_info_os`, ...) so the generated code builds the record
//! without sharing a layout. `os` and `architecture` report the target names `@std/process`
//! uses (`linux`, `darwin`, `windows`; `amd64`, `arm64`).
#![no_std]
// The exports below are the C ABI compiled code links against.
#![allow(unsafe_code)]
#![allow(clippy::missing_safety_doc)]

extern crate alloc;
#[cfg(unix)]
extern crate std;

mod inventory;

use alloc::vec::Vec;
use inventory::{Cpu, Interface, Metrics, Slot};
use ms_rt_abi::{MapVal, STATUS_OK, STATUS_UNSUPPORTED, StrObj};
use ms_std_process::control;
use ms_std_rt::{MapValue, new_string, write_string_map};

/// The text of the last `FAILED` result.
#[unsafe(no_mangle)]
pub extern "C" fn msstd_system_failure_message() -> *mut StrObj {
    ms_std_rt::failure_message()
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_system_endianness() -> *mut StrObj {
    new_string(if cfg!(target_endian = "little") {
        b"LE"
    } else {
        b"BE"
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_system_end_of_line() -> *mut StrObj {
    new_string(if cfg!(windows) { b"\r\n" } else { b"\n" })
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_system_dev_null() -> *mut StrObj {
    new_string(if cfg!(windows) {
        b"\\\\.\\nul"
    } else {
        b"/dev/null"
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_system_os_type() -> *mut StrObj {
    new_string(if cfg!(target_os = "macos") {
        b"Darwin"
    } else if cfg!(windows) {
        b"Windows_NT"
    } else {
        b"Linux"
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_system_info_os() -> *mut StrObj {
    new_string(control::OS.as_bytes())
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_system_info_architecture() -> *mut StrObj {
    new_string(control::ARCH.as_bytes())
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_system_info_cpu_count() -> i64 {
    imp::cpu_count()
}

/// The live working directory; a host failure yields an empty string.
#[unsafe(no_mangle)]
pub extern "C" fn msstd_system_working_directory() -> *mut StrObj {
    new_string(&control::working_directory().unwrap_or_default())
}

fn finish(r: Result<Vec<u8>, u8>, out: *mut *mut StrObj) -> u8 {
    match r {
        Ok(text) => {
            // SAFETY: `out` is writable.
            unsafe { out.write(new_string(&text)) };
            STATUS_OK
        }
        Err(status) => status,
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_system_hostname(out: *mut *mut StrObj) -> u8 {
    finish(imp::hostname(), out)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_system_home_directory(out: *mut *mut StrObj) -> u8 {
    finish(imp::home_directory(), out)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_system_os_release(out: *mut *mut StrObj) -> u8 {
    finish(imp::uname(imp::Field::Release), out)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_system_os_version(out: *mut *mut StrObj) -> u8 {
    finish(imp::uname(imp::Field::Version), out)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_system_machine(out: *mut *mut StrObj) -> u8 {
    finish(imp::uname(imp::Field::Machine), out)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_system_get_priority(pid: i64, out: *mut i64) -> u8 {
    match imp::get_priority(pid) {
        Ok(p) => {
            // SAFETY: `out` is writable.
            unsafe { out.write(p) };
            STATUS_OK
        }
        Err(status) => status,
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_system_set_priority(pid: i64, priority: i64) -> u8 {
    imp::set_priority(pid, priority).err().unwrap_or(STATUS_OK)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_system_constants(out: *mut MapVal) {
    // SAFETY: `out` is writable.
    unsafe {
        write_string_map(
            imp::CONSTANTS
                .iter()
                .map(|&(name, value)| (name.as_bytes(), MapValue::Int(value))),
            true,
            out,
        );
    }
}

// `user_info()` crosses as a status plus one getter per field.
#[unsafe(no_mangle)]
pub extern "C" fn msstd_system_user_info_status() -> u8 {
    imp::user().err().unwrap_or(STATUS_OK)
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_system_user_info_username() -> *mut StrObj {
    new_string(&imp::user().map(|u| u.name).unwrap_or_default())
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_system_user_info_uid() -> i64 {
    imp::user().map(|u| u.uid).unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_system_user_info_gid() -> i64 {
    imp::user().map(|u| u.gid).unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_system_user_info_home() -> *mut StrObj {
    new_string(&imp::user().map(|u| u.home).unwrap_or_default())
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_system_user_info_shell() -> *mut StrObj {
    new_string(&imp::user().map(|u| u.shell).unwrap_or_default())
}

// Lists and the metrics record cross as a status call that takes a snapshot, then getters
// (indexed for lists): `msstd_system_<call>_status`, `_count`, `_<field>`.
static INTERFACES: Slot<Vec<Interface>> = Slot::new();
static CPUS: Slot<Vec<Cpu>> = Slot::new();
static METRICS: Slot<Metrics> = Slot::new();

fn snapshot<T>(slot: &Slot<T>, taken: Result<T, u8>) -> u8 {
    match taken {
        Ok(v) => {
            slot.set(v);
            STATUS_OK
        }
        Err(status) => status,
    }
}

fn item<T>(slot: &Slot<Vec<T>>, i: i64) -> Option<&T> {
    slot.get()?.get(usize::try_from(i).ok()?)
}

/// Exports `$name(i)` reading the text field `$field` of item `i`.
macro_rules! text_getter {
    ($name:ident, $slot:ident, $field:ident) => {
        #[unsafe(no_mangle)]
        pub extern "C" fn $name(i: i64) -> *mut StrObj {
            new_string(item(&$slot, i).map_or(&[][..], |x| &x.$field))
        }
    };
}

/// Exports `$name(i)` reading the integer field `$field` of item `i`.
macro_rules! int_getter {
    ($name:ident, $slot:ident, $field:ident) => {
        #[unsafe(no_mangle)]
        pub extern "C" fn $name(i: i64) -> i64 {
            item(&$slot, i).map_or(0, |x| x.$field)
        }
    };
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_system_network_interfaces_status() -> u8 {
    snapshot(&INTERFACES, inventory::interfaces())
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_system_network_interfaces_count() -> i64 {
    INTERFACES.get().map_or(0, |v| v.len() as i64)
}

text_getter!(msstd_system_network_interfaces_name, INTERFACES, name);
text_getter!(msstd_system_network_interfaces_address, INTERFACES, address);
text_getter!(msstd_system_network_interfaces_netmask, INTERFACES, netmask);
text_getter!(msstd_system_network_interfaces_mac, INTERFACES, mac);
int_getter!(
    msstd_system_network_interfaces_scope_id,
    INTERFACES,
    scope_id
);

/// The family's `IpFamily` case index: `0` is IPv4, `1` is IPv6.
#[unsafe(no_mangle)]
pub extern "C" fn msstd_system_network_interfaces_family(i: i64) -> i64 {
    item(&INTERFACES, i).map_or(0, |x| i64::from(x.v6))
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_system_network_interfaces_internal(i: i64) -> u8 {
    item(&INTERFACES, i).map_or(0, |x| u8::from(x.internal))
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_system_cpus_status() -> u8 {
    snapshot(&CPUS, inventory::cpus())
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_system_cpus_count() -> i64 {
    CPUS.get().map_or(0, |v| v.len() as i64)
}

text_getter!(msstd_system_cpus_model, CPUS, model);
int_getter!(msstd_system_cpus_speed_mhz, CPUS, speed_mhz);
int_getter!(msstd_system_cpus_user, CPUS, user);
int_getter!(msstd_system_cpus_nice, CPUS, nice);
int_getter!(msstd_system_cpus_system, CPUS, system);
int_getter!(msstd_system_cpus_idle, CPUS, idle);
int_getter!(msstd_system_cpus_irq, CPUS, irq);

#[unsafe(no_mangle)]
pub extern "C" fn msstd_system_metrics_status() -> u8 {
    snapshot(&METRICS, inventory::metrics())
}

fn metric<T: Default>(read: impl FnOnce(&Metrics) -> T) -> T {
    METRICS.get().map(read).unwrap_or_default()
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_system_metrics_total_memory() -> i64 {
    metric(|m| m.total_memory)
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_system_metrics_free_memory() -> i64 {
    metric(|m| m.free_memory)
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_system_metrics_available_memory() -> i64 {
    metric(|m| m.available_memory)
}

/// Host uptime in nanoseconds, the representation of a `Duration`.
#[unsafe(no_mangle)]
pub extern "C" fn msstd_system_metrics_uptime() -> i64 {
    metric(|m| m.uptime_ns)
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_system_metrics_available_parallelism() -> i64 {
    metric(|m| m.parallelism)
}

/// The 1, 5 and 15 minute load average for `window` 0, 1 and 2.
#[unsafe(no_mangle)]
pub extern "C" fn msstd_system_metrics_load_average(window: i64) -> f64 {
    metric(|m| {
        let slot = usize::try_from(window).unwrap_or(usize::MAX);
        m.load.get(slot).copied().unwrap_or(0.0)
    })
}

#[cfg(unix)]
mod imp {
    use super::*;
    use alloc::vec;
    use core::ffi::CStr;
    use ms_rt_abi::{
        STATUS_FAILED, STATUS_INVALID_INPUT, STATUS_NOT_FOUND, STATUS_PERMISSION_DENIED,
    };
    use rustix::io::Errno;
    use rustix::process::{Pid, Signal, getpriority_process, getuid, setpriority_process};
    use rustix::system::uname as host_uname;
    use std::os::unix::ffi::OsStrExt;

    pub enum Field {
        Release,
        Version,
        Machine,
    }

    pub struct User {
        pub name: Vec<u8>,
        pub uid: i64,
        pub gid: i64,
        pub home: Vec<u8>,
        pub shell: Vec<u8>,
    }

    /// Signal and priority constants by name; the values are the host's.
    pub const CONSTANTS: &[(&str, i64)] = &[
        ("SIGHUP", Signal::HUP.as_raw() as i64),
        ("SIGINT", Signal::INT.as_raw() as i64),
        ("SIGQUIT", Signal::QUIT.as_raw() as i64),
        ("SIGABRT", Signal::ABORT.as_raw() as i64),
        ("SIGKILL", Signal::KILL.as_raw() as i64),
        ("SIGUSR1", Signal::USR1.as_raw() as i64),
        ("SIGSEGV", Signal::SEGV.as_raw() as i64),
        ("SIGUSR2", Signal::USR2.as_raw() as i64),
        ("SIGPIPE", Signal::PIPE.as_raw() as i64),
        ("SIGALRM", Signal::ALARM.as_raw() as i64),
        ("SIGTERM", Signal::TERM.as_raw() as i64),
        ("SIGCHLD", Signal::CHILD.as_raw() as i64),
        ("SIGCONT", Signal::CONT.as_raw() as i64),
        ("SIGSTOP", Signal::STOP.as_raw() as i64),
        ("PRIORITY_LOW", 19),
        ("PRIORITY_HIGH", -20),
    ];

    /// The status of an OS error; other errors are `Failed` with a fixed text.
    fn status_of(e: Errno) -> u8 {
        match e {
            Errno::INVAL => STATUS_INVALID_INPUT,
            Errno::SRCH | Errno::NOENT => STATUS_NOT_FOUND,
            Errno::PERM | Errno::ACCESS => STATUS_PERMISSION_DENIED,
            _ => {
                ms_std_rt::record_failure(b"system call failed".to_vec());
                STATUS_FAILED
            }
        }
    }

    pub(crate) fn cpu_count() -> i64 {
        // SAFETY: plain system call.
        let n = unsafe { libc::sysconf(libc::_SC_NPROCESSORS_ONLN) };
        i64::from(n.max(1) as i32)
    }

    fn utf8(bytes: Vec<u8>) -> Result<Vec<u8>, u8> {
        match core::str::from_utf8(&bytes) {
            Ok(_) => Ok(bytes),
            Err(_) => Err(STATUS_UNSUPPORTED),
        }
    }

    pub fn hostname() -> Result<Vec<u8>, u8> {
        utf8(host_uname().nodename().to_bytes().to_vec())
    }

    pub fn uname(field: Field) -> Result<Vec<u8>, u8> {
        let u = host_uname();
        let text = match field {
            Field::Release => u.release(),
            Field::Version => u.version(),
            Field::Machine => u.machine(),
        };
        utf8(text.to_bytes().trim_ascii().to_vec())
    }

    pub fn home_directory() -> Result<Vec<u8>, u8> {
        if let Some(home) = std::env::var_os("HOME").filter(|h| !h.is_empty()) {
            return utf8(home.as_bytes().to_vec());
        }
        user().map(|u| u.home)
    }

    pub fn user() -> Result<User, u8> {
        let uid = getuid().as_raw();
        let mut buf = vec![0u8; 1024];
        loop {
            // SAFETY: `passwd` is plain data that `getpwuid_r` fills.
            let mut pw: libc::passwd = unsafe { core::mem::zeroed() };
            let mut found: *mut libc::passwd = core::ptr::null_mut();
            // SAFETY: all pointers are writable for their stated lengths.
            let rc = unsafe {
                libc::getpwuid_r(uid, &mut pw, buf.as_mut_ptr().cast(), buf.len(), &mut found)
            };
            if rc == libc::ERANGE && buf.len() < 1 << 20 {
                buf.resize(buf.len() * 2, 0);
                continue;
            }
            if rc != 0 {
                return Err(status_of(Errno::from_raw_os_error(rc)));
            }
            if found.is_null() {
                return Err(STATUS_NOT_FOUND);
            }
            let text = |p: *const libc::c_char| -> Result<Vec<u8>, u8> {
                if p.is_null() {
                    return Ok(Vec::new());
                }
                // SAFETY: the passwd strings are NUL-terminated and live in `buf`.
                utf8(unsafe { CStr::from_ptr(p) }.to_bytes().to_vec())
            };
            return Ok(User {
                name: text(pw.pw_name)?,
                uid: i64::from(pw.pw_uid),
                gid: i64::from(pw.pw_gid),
                home: text(pw.pw_dir)?,
                shell: text(pw.pw_shell)?,
            });
        }
    }

    /// `None` is the calling process, as for pid 0.
    fn process(pid: i64) -> Result<Option<Pid>, u8> {
        let raw = i32::try_from(pid).map_err(|_| STATUS_INVALID_INPUT)?;
        match raw {
            0 => Ok(None),
            1.. => Ok(Pid::from_raw(raw)),
            _ => Err(STATUS_INVALID_INPUT),
        }
    }

    pub fn get_priority(pid: i64) -> Result<i64, u8> {
        let pid = process(pid)?;
        getpriority_process(pid).map(i64::from).map_err(status_of)
    }

    pub fn set_priority(pid: i64, priority: i64) -> Result<(), u8> {
        let pid = process(pid)?;
        if !(-20..=19).contains(&priority) {
            return Err(STATUS_INVALID_INPUT);
        }
        setpriority_process(pid, priority as i32).map_err(status_of)
    }
}

#[cfg(not(unix))]
mod imp {
    use super::*;

    pub enum Field {
        Release,
        Version,
        Machine,
    }

    pub struct User {
        pub name: Vec<u8>,
        pub uid: i64,
        pub gid: i64,
        pub home: Vec<u8>,
        pub shell: Vec<u8>,
    }

    pub const CONSTANTS: &[(&str, i64)] = &[];

    pub fn cpu_count() -> i64 {
        1
    }

    pub fn hostname() -> Result<Vec<u8>, u8> {
        Err(STATUS_UNSUPPORTED)
    }

    pub fn uname(_: Field) -> Result<Vec<u8>, u8> {
        Err(STATUS_UNSUPPORTED)
    }

    pub fn home_directory() -> Result<Vec<u8>, u8> {
        Err(STATUS_UNSUPPORTED)
    }

    pub fn user() -> Result<User, u8> {
        Err(STATUS_UNSUPPORTED)
    }

    pub fn get_priority(_: i64) -> Result<i64, u8> {
        Err(STATUS_UNSUPPORTED)
    }

    pub fn set_priority(_: i64, _: i64) -> Result<(), u8> {
        Err(STATUS_UNSUPPORTED)
    }
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use ms_rt as _; // links the msrt_* runtime symbols
    use ms_rt_abi::STATUS_INVALID_INPUT;

    #[test]
    fn interfaces_include_a_loopback_address() {
        assert_eq!(msstd_system_network_interfaces_status(), STATUS_OK);
        let n = msstd_system_network_interfaces_count();
        assert!(n >= 1);
        let loopback = (0..n).any(|i| msstd_system_network_interfaces_internal(i) == 1);
        assert!(loopback);
        assert!(msstd_system_network_interfaces_scope_id(0) >= 1);
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn cpus_and_metrics_read_proc() {
        assert_eq!(msstd_system_cpus_status(), STATUS_OK);
        assert!(msstd_system_cpus_count() >= 1);
        assert!(msstd_system_cpus_idle(0) >= 0);
        assert_eq!(msstd_system_metrics_status(), STATUS_OK);
        assert!(msstd_system_metrics_total_memory() > 0);
        assert!(msstd_system_metrics_available_memory() <= msstd_system_metrics_total_memory());
        assert!(msstd_system_metrics_uptime() > 0);
        assert!(msstd_system_metrics_available_parallelism() >= 1);
        assert!(msstd_system_metrics_load_average(0) >= 0.0);
        assert_eq!(msstd_system_metrics_load_average(3), 0.0);
    }

    #[test]
    fn priorities_validate_and_read() {
        assert!(msstd_system_info_cpu_count() >= 1);
        let mut out = 0i64;
        // SAFETY: `out` is writable; pid 0 is the calling process.
        assert_eq!(unsafe { msstd_system_get_priority(0, &mut out) }, STATUS_OK);
        assert!((-20..=19).contains(&out));
        // SAFETY: `out` is writable.
        let bad = unsafe { msstd_system_get_priority(-1, &mut out) };
        assert_eq!(bad, STATUS_INVALID_INPUT);
        assert_eq!(msstd_system_set_priority(0, 20), STATUS_INVALID_INPUT);
    }
}
