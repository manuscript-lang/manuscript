//! `@std/process` natives. Symbols are `msstd_system_<name>`.
//!
//! Fallible functions return a `STATUS_*` code (`0` ok) and write results only on success; for
//! `STATUS_FAILED` the text is written to the trailing `err` slot. A record result crosses as
//! one getter per field (`msstd_system_info_os`, ...) so the generated code builds the record
//! without sharing a layout. `os` and `architecture` report the target names `@std/process`
//! uses (`linux`, `darwin`, `windows`; `amd64`, `arm64`).
#![no_std]

// Links the msrt_* runtime symbols into this crate's test binaries.
#[cfg(test)]
use ms_rt as _;

extern crate alloc;
#[cfg(unix)]
extern crate std;

mod inventory;

use alloc::vec::Vec;
use inventory::{Cpu, Interface, Metrics, Slot};
use ms_rt::ffi::{ErrOut, Failure, IntMap, StatusCode, Text, native};
use ms_rt_abi::STATUS_UNSUPPORTED;
use ms_std_process::control;

ms_rt::isolate_static! {
    static INTERFACE_CELL: Option<Vec<Interface>> = None;
    static CPU_CELL: Option<Vec<Cpu>> = None;
    static METRIC_CELL: Option<Metrics> = None;
}

static INTERFACES: Slot<Vec<Interface>> = Slot::new(|| INTERFACE_CELL.ptr());
static CPUS: Slot<Vec<Cpu>> = Slot::new(|| CPU_CELL.ptr());
static METRICS: Slot<Metrics> = Slot::new(|| METRIC_CELL.ptr());

fn text(r: Result<Vec<u8>, Failure>, err: &ErrOut) -> Result<Text, StatusCode> {
    r.map(Text).map_err(|f| err.fail(f))
}

fn snapshot<T>(slot: &Slot<T>, taken: Result<T, Failure>, err: &ErrOut) -> Result<(), StatusCode> {
    slot.set(taken.map_err(|f| err.fail(f))?);
    Ok(())
}

/// Reads field `read` of list element `i` (`None` when out of range).
fn item<T, R>(slot: &Slot<Vec<T>>, i: i64, read: impl FnOnce(&T) -> R) -> Option<R> {
    slot.with(|v| v?.get(usize::try_from(i).ok()?).map(read))
}

fn metric<T: Default>(read: impl FnOnce(&Metrics) -> T) -> T {
    METRICS.with(|m| m.map(read)).unwrap_or_default()
}

native! {
    safe fn msstd_system_endianness() -> &'static str {
        if cfg!(target_endian = "little") { "LE" } else { "BE" }
    }

    safe fn msstd_system_end_of_line() -> &'static str {
        if cfg!(windows) { "\r\n" } else { "\n" }
    }

    safe fn msstd_system_dev_null() -> &'static str {
        if cfg!(windows) { "\\\\.\\nul" } else { "/dev/null" }
    }

    safe fn msstd_system_os_type() -> &'static str {
        if cfg!(target_os = "macos") {
            "Darwin"
        } else if cfg!(windows) {
            "Windows_NT"
        } else {
            "Linux"
        }
    }

    safe fn msstd_system_info_os() -> &'static str {
        control::OS
    }

    safe fn msstd_system_info_architecture() -> &'static str {
        control::ARCH
    }

    safe fn msstd_system_info_cpu_count() -> i64 {
        imp::cpu_count()
    }

    safe fn msstd_system_working_directory() -> Text {
        Text(control::working_directory().unwrap_or_default())
    }

    fn msstd_system_hostname(; err: ErrOut) -> Result<Text, StatusCode> {
        text(imp::hostname(), &err)
    }

    fn msstd_system_home_directory(; err: ErrOut) -> Result<Text, StatusCode> {
        text(imp::home_directory(), &err)
    }

    fn msstd_system_os_release(; err: ErrOut) -> Result<Text, StatusCode> {
        text(imp::uname(imp::Field::Release), &err)
    }

    fn msstd_system_os_version(; err: ErrOut) -> Result<Text, StatusCode> {
        text(imp::uname(imp::Field::Version), &err)
    }

    fn msstd_system_machine(; err: ErrOut) -> Result<Text, StatusCode> {
        text(imp::uname(imp::Field::Machine), &err)
    }

    fn msstd_system_get_priority(pid: i64; err: ErrOut) -> Result<i64, StatusCode> {
        imp::get_priority(pid).map_err(|f| err.fail(f))
    }

    fn msstd_system_set_priority(pid: i64, priority: i64; err: ErrOut) -> Result<(), StatusCode> {
        imp::set_priority(pid, priority).map_err(|f| err.fail(f))
    }

    fn msstd_system_constants() -> out IntMap {
        IntMap(
            imp::CONSTANTS
                .iter()
                .map(|&(name, value)| (name.as_bytes().to_vec(), value))
                .collect(),
        )
    }

    // `user_info()` crosses as a status plus one getter per field.
    fn msstd_system_user_info_status(; err: ErrOut) -> Result<(), StatusCode> {
        imp::user().map(drop).map_err(|f| err.fail(f))
    }

    safe fn msstd_system_user_info_username() -> Text {
        Text(imp::user().map(|u| u.name).unwrap_or_default())
    }

    safe fn msstd_system_user_info_uid() -> i64 {
        imp::user().map(|u| u.uid).unwrap_or(-1)
    }

    safe fn msstd_system_user_info_gid() -> i64 {
        imp::user().map(|u| u.gid).unwrap_or(-1)
    }

    safe fn msstd_system_user_info_home() -> Text {
        Text(imp::user().map(|u| u.home).unwrap_or_default())
    }

    safe fn msstd_system_user_info_shell() -> Text {
        Text(imp::user().map(|u| u.shell).unwrap_or_default())
    }

    // Lists and the metrics record cross as a status call that takes a snapshot, then getters
    // (indexed for lists): `msstd_system_<call>_status`, `_count`, `_<field>`.
    fn msstd_system_network_interfaces_status(; err: ErrOut) -> Result<(), StatusCode> {
        snapshot(&INTERFACES, inventory::interfaces(), &err)
    }

    safe fn msstd_system_network_interfaces_count() -> i64 {
        INTERFACES.with(|v| v.map_or(0, |v| v.len() as i64))
    }

    safe fn msstd_system_network_interfaces_name(i: i64) -> Text {
        Text(item(&INTERFACES, i, |x| x.name.clone()).unwrap_or_default())
    }

    safe fn msstd_system_network_interfaces_address(i: i64) -> Text {
        Text(item(&INTERFACES, i, |x| x.address.clone()).unwrap_or_default())
    }

    safe fn msstd_system_network_interfaces_netmask(i: i64) -> Text {
        Text(item(&INTERFACES, i, |x| x.netmask.clone()).unwrap_or_default())
    }

    safe fn msstd_system_network_interfaces_mac(i: i64) -> Text {
        Text(item(&INTERFACES, i, |x| x.mac.clone()).unwrap_or_default())
    }

    safe fn msstd_system_network_interfaces_scope_id(i: i64) -> i64 {
        item(&INTERFACES, i, |x| x.scope_id).unwrap_or(0)
    }

    safe fn msstd_system_network_interfaces_family(i: i64) -> i64 {
        item(&INTERFACES, i, |x| i64::from(x.v6)).unwrap_or(0)
    }

    safe fn msstd_system_network_interfaces_internal(i: i64) -> bool {
        item(&INTERFACES, i, |x| x.internal).unwrap_or(false)
    }

    fn msstd_system_cpus_status(; err: ErrOut) -> Result<(), StatusCode> {
        snapshot(&CPUS, inventory::cpus(), &err)
    }

    safe fn msstd_system_cpus_count() -> i64 {
        CPUS.with(|v| v.map_or(0, |v| v.len() as i64))
    }

    safe fn msstd_system_cpus_model(i: i64) -> Text {
        Text(item(&CPUS, i, |x| x.model.clone()).unwrap_or_default())
    }

    safe fn msstd_system_cpus_speed_mhz(i: i64) -> i64 {
        item(&CPUS, i, |x| x.speed_mhz).unwrap_or(0)
    }

    safe fn msstd_system_cpus_user(i: i64) -> i64 {
        item(&CPUS, i, |x| x.user).unwrap_or(0)
    }

    safe fn msstd_system_cpus_nice(i: i64) -> i64 {
        item(&CPUS, i, |x| x.nice).unwrap_or(0)
    }

    safe fn msstd_system_cpus_system(i: i64) -> i64 {
        item(&CPUS, i, |x| x.system).unwrap_or(0)
    }

    safe fn msstd_system_cpus_idle(i: i64) -> i64 {
        item(&CPUS, i, |x| x.idle).unwrap_or(0)
    }

    safe fn msstd_system_cpus_irq(i: i64) -> i64 {
        item(&CPUS, i, |x| x.irq).unwrap_or(0)
    }

    fn msstd_system_metrics_status(; err: ErrOut) -> Result<(), StatusCode> {
        snapshot(&METRICS, inventory::metrics(), &err)
    }

    safe fn msstd_system_metrics_total_memory() -> i64 {
        metric(|m| m.total_memory)
    }

    safe fn msstd_system_metrics_free_memory() -> i64 {
        metric(|m| m.free_memory)
    }

    safe fn msstd_system_metrics_available_memory() -> i64 {
        metric(|m| m.available_memory)
    }

    safe fn msstd_system_metrics_uptime() -> i64 {
        metric(|m| m.uptime_ns)
    }

    safe fn msstd_system_metrics_available_parallelism() -> i64 {
        metric(|m| m.parallelism)
    }

    safe fn msstd_system_metrics_load_average(window: i64) -> f64 {
        metric(|m| {
            let slot = usize::try_from(window).unwrap_or(usize::MAX);
            m.load.get(slot).copied().unwrap_or(0.0)
        })
    }
}

#[cfg(unix)]
#[allow(unsafe_code)] // libc `sysconf` and `getpwuid_r`
mod imp {
    use super::*;
    use alloc::vec;
    use core::ffi::CStr;
    use ms_rt_abi::{STATUS_INVALID_INPUT, STATUS_NOT_FOUND, STATUS_PERMISSION_DENIED};
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
    fn status_of(e: Errno) -> Failure {
        match e {
            Errno::INVAL => STATUS_INVALID_INPUT.into(),
            Errno::SRCH | Errno::NOENT => STATUS_NOT_FOUND.into(),
            Errno::PERM | Errno::ACCESS => STATUS_PERMISSION_DENIED.into(),
            _ => Failure::failed("system call failed"),
        }
    }

    pub(crate) fn cpu_count() -> i64 {
        // SAFETY: plain system call.
        let n = unsafe { libc::sysconf(libc::_SC_NPROCESSORS_ONLN) };
        i64::from(n.max(1) as i32)
    }

    fn utf8(bytes: Vec<u8>) -> Result<Vec<u8>, Failure> {
        match core::str::from_utf8(&bytes) {
            Ok(_) => Ok(bytes),
            Err(_) => Err(STATUS_UNSUPPORTED.into()),
        }
    }

    pub fn hostname() -> Result<Vec<u8>, Failure> {
        utf8(host_uname().nodename().to_bytes().to_vec())
    }

    pub fn uname(field: Field) -> Result<Vec<u8>, Failure> {
        let u = host_uname();
        let text = match field {
            Field::Release => u.release(),
            Field::Version => u.version(),
            Field::Machine => u.machine(),
        };
        utf8(text.to_bytes().trim_ascii().to_vec())
    }

    pub fn home_directory() -> Result<Vec<u8>, Failure> {
        if let Some(home) = std::env::var_os("HOME").filter(|h| !h.is_empty()) {
            return utf8(home.as_bytes().to_vec());
        }
        user().map(|u| u.home)
    }

    pub fn user() -> Result<User, Failure> {
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
                return Err(STATUS_NOT_FOUND.into());
            }
            let text = |p: *const libc::c_char| -> Result<Vec<u8>, Failure> {
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
    fn process(pid: i64) -> Result<Option<Pid>, Failure> {
        let raw = i32::try_from(pid).map_err(|_| STATUS_INVALID_INPUT)?;
        match raw {
            0 => Ok(None),
            1.. => Ok(Pid::from_raw(raw)),
            _ => Err(STATUS_INVALID_INPUT.into()),
        }
    }

    pub fn get_priority(pid: i64) -> Result<i64, Failure> {
        let pid = process(pid)?;
        getpriority_process(pid).map(i64::from).map_err(status_of)
    }

    pub fn set_priority(pid: i64, priority: i64) -> Result<(), Failure> {
        let pid = process(pid)?;
        if !(-20..=19).contains(&priority) {
            return Err(STATUS_INVALID_INPUT.into());
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

    #[cfg(windows)]
    #[allow(unsafe_code)] // kernel32 `GetActiveProcessorCount`
    pub fn cpu_count() -> i64 {
        unsafe extern "system" {
            fn GetActiveProcessorCount(group: u16) -> u32;
        }
        const ALL_PROCESSOR_GROUPS: u16 = 0xffff;
        // SAFETY: a kernel32 call that takes no pointers.
        let n = unsafe { GetActiveProcessorCount(ALL_PROCESSOR_GROUPS) };
        i64::from(n.max(1))
    }

    #[cfg(not(windows))]
    pub fn cpu_count() -> i64 {
        1
    }

    pub fn hostname() -> Result<Vec<u8>, Failure> {
        Err(STATUS_UNSUPPORTED.into())
    }

    pub fn uname(_: Field) -> Result<Vec<u8>, Failure> {
        Err(STATUS_UNSUPPORTED.into())
    }

    pub fn home_directory() -> Result<Vec<u8>, Failure> {
        Err(STATUS_UNSUPPORTED.into())
    }

    pub fn user() -> Result<User, Failure> {
        Err(STATUS_UNSUPPORTED.into())
    }

    pub fn get_priority(_: i64) -> Result<i64, Failure> {
        Err(STATUS_UNSUPPORTED.into())
    }

    pub fn set_priority(_: i64, _: i64) -> Result<(), Failure> {
        Err(STATUS_UNSUPPORTED.into())
    }
}

#[cfg(all(test, unix))]
#[allow(unsafe_code)]
mod tests {
    use super::*;
    use ms_rt as _; // links the msrt_* runtime symbols
    use ms_rt_abi::{ErrSlot, STATUS_INVALID_INPUT, STATUS_OK};

    const NO_ERR: ErrSlot = ErrSlot(core::ptr::null_mut());

    fn interfaces_status() -> u8 {
        // SAFETY: a null `err` slot is allowed, and `out` is writable.
        unsafe { msstd_system_network_interfaces_status(NO_ERR) }
    }
    fn cpus_status() -> u8 {
        // SAFETY: a null `err` slot is allowed, and `out` is writable.
        unsafe { msstd_system_cpus_status(NO_ERR) }
    }
    fn metrics_status() -> u8 {
        // SAFETY: a null `err` slot is allowed, and `out` is writable.
        unsafe { msstd_system_metrics_status(NO_ERR) }
    }
    fn get_priority(pid: i64, out: &mut i64) -> u8 {
        // SAFETY: a null `err` slot is allowed, and `out` is writable.
        unsafe { msstd_system_get_priority(pid, out, NO_ERR) }
    }
    fn set_priority(pid: i64, priority: i64) -> u8 {
        // SAFETY: a null `err` slot is allowed, and `out` is writable.
        unsafe { msstd_system_set_priority(pid, priority, NO_ERR) }
    }

    #[test]
    fn interfaces_include_a_loopback_address() {
        assert_eq!(interfaces_status(), STATUS_OK);
        let n = msstd_system_network_interfaces_count();
        assert!(n >= 1);
        let loopback = (0..n).any(|i| msstd_system_network_interfaces_internal(i) == 1);
        assert!(loopback);
        assert!(msstd_system_network_interfaces_scope_id(0) >= 1);
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn cpus_and_metrics_read_proc() {
        assert_eq!(cpus_status(), STATUS_OK);
        assert!(msstd_system_cpus_count() >= 1);
        assert!(msstd_system_cpus_idle(0) >= 0);
        assert_eq!(metrics_status(), STATUS_OK);
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
        assert_eq!(get_priority(0, &mut out), STATUS_OK);
        assert!((-20..=19).contains(&out));
        // SAFETY: `out` is writable.
        let bad = get_priority(-1, &mut out);
        assert_eq!(bad, STATUS_INVALID_INPUT);
        assert_eq!(set_priority(0, 20), STATUS_INVALID_INPUT);
    }
}
