//! `@std/process` natives. Symbols are `msstd_system_<name>`.
//!
//! Fallible functions return a `STATUS_*` code (`0` ok) and write results only on success; for
//! `STATUS_FAILED` the text is written to the trailing `err` slot. Record results
//! (`SystemInfo`, `UserInfo`, `CpuInfo`, `NetworkInterface` and the metrics snapshot) cross as
//! one record, or a list of them, per call. `os` and `architecture` report the target names
//! `@std/system` uses (`linux`, `darwin`, `windows`; `amd64`, `arm64`).
//! ms: domain system
#![no_std]

// Links the msrt_* runtime symbols into this crate's test binaries.
#[cfg(test)]
use ms_rt as _;

extern crate alloc;
extern crate std;

mod inventory;

use alloc::vec::Vec;
use inventory::{Cpu, Interface, Metrics};
use ms_rt::ffi::{ErrOut, Failure, IntMap, StatusCode, Str, Text, TypeList, abi_type, native};
use ms_rt_abi::STATUS_UNSUPPORTED;
use ms_std_process::control;

abi_type! {
    /// `SystemInfo`: `os`, `architecture`, `cpu_count`.
    pub struct SystemInfoOut {
        pub os: Str,
        pub architecture: Str,
        pub cpu_count: i64,
    }
}

abi_type! {
    /// `UserInfo`: `username`, `uid`, `gid`, `home`, `shell`.
    pub struct UserInfoOut {
        pub username: Str,
        pub uid: i64,
        pub gid: i64,
        pub home: Str,
        pub shell: Str,
    }
}

abi_type! {
    /// `NetworkInterface`; `family` is the case index of `IpFamily`.
    pub struct InterfaceOut {
        pub name: Str,
        pub address: Str,
        pub netmask: Str,
        pub family: i64,
        pub mac: Str,
        pub internal: u8,
        pub scope_id: i64,
    }
}

abi_type! {
    /// `CpuInfo`.
    pub struct CpuOut {
        pub model: Str,
        pub speed_mhz: i64,
        pub user: i64,
        pub nice: i64,
        pub system: i64,
        pub idle: i64,
        pub irq: i64,
    }
}

abi_type! {
    /// `MetricsSnapshot`: the fields of `SystemMetrics` with the uptime in nanoseconds and the
    /// three load averages flattened.
    pub struct MetricsOut {
        pub total_memory: i64,
        pub free_memory: i64,
        pub available_memory: i64,
        pub uptime_nanos: i64,
        pub load_1: f64,
        pub load_5: f64,
        pub load_15: f64,
        pub available_parallelism: i64,
    }
}

fn text(r: Result<Vec<u8>, Failure>, err: &ErrOut) -> Result<Text, StatusCode> {
    r.map(Text).map_err(|f| err.fail(f))
}

fn interface_out(i: &Interface) -> InterfaceOut {
    InterfaceOut {
        name: Str::from_bytes(&i.name),
        address: Str::from_bytes(&i.address),
        netmask: Str::from_bytes(&i.netmask),
        family: i64::from(i.v6),
        mac: Str::from_bytes(&i.mac),
        internal: u8::from(i.internal),
        scope_id: i.scope_id,
    }
}

fn cpu_out(c: &Cpu) -> CpuOut {
    CpuOut {
        model: Str::from_bytes(&c.model),
        speed_mhz: c.speed_mhz,
        user: c.user,
        nice: c.nice,
        system: c.system,
        idle: c.idle,
        irq: c.irq,
    }
}

fn metrics_out(m: &Metrics) -> MetricsOut {
    MetricsOut {
        total_memory: m.total_memory,
        free_memory: m.free_memory,
        available_memory: m.available_memory,
        uptime_nanos: m.uptime_ns,
        load_1: m.load[0],
        load_5: m.load[1],
        load_15: m.load[2],
        available_parallelism: m.parallelism,
    }
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

    // The case index of `Os`: 0 Linux, 1 Macos, 2 Windows, 3 Other.
    safe fn msstd_system_os() -> i64 {
        if cfg!(target_os = "linux") {
            0
        } else if cfg!(target_os = "macos") {
            1
        } else if cfg!(windows) {
            2
        } else {
            3
        }
    }

    fn msstd_system_info() -> out SystemInfoOut {
        SystemInfoOut {
            os: Str::new(control::OS),
            architecture: Str::new(control::ARCH),
            cpu_count: imp::cpu_count(),
        }
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

    fn msstd_system_user_info(; err: ErrOut) -> Result<UserInfoOut, StatusCode> {
        imp::user().map_err(|f| err.fail(f)).map(|u| UserInfoOut {
            username: Str::from_bytes(&u.name),
            uid: u.uid,
            gid: u.gid,
            home: Str::from_bytes(&u.home),
            shell: Str::from_bytes(&u.shell),
        })
    }

    fn msstd_system_network_interfaces(; err: ErrOut) -> Result<TypeList<InterfaceOut>, StatusCode> {
        let all = inventory::interfaces().map_err(|f| err.fail(f))?;
        Ok(TypeList::new(all.iter().map(interface_out)))
    }

    fn msstd_system_cpus(; err: ErrOut) -> Result<TypeList<CpuOut>, StatusCode> {
        let all = inventory::cpus().map_err(|f| err.fail(f))?;
        Ok(TypeList::new(all.iter().map(cpu_out)))
    }

    fn msstd_system_metrics(; err: ErrOut) -> Result<MetricsOut, StatusCode> {
        inventory::metrics().map(|m| metrics_out(&m)).map_err(|f| err.fail(f))
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
        let all = inventory::interfaces().expect("interfaces");
        assert!(all.iter().any(|i| i.internal));
        assert!(all[0].scope_id >= 1);
    }

    #[cfg(target_os = "linux")]
    #[test]
    fn cpus_and_metrics_read_proc() {
        let cpus = inventory::cpus().expect("cpus");
        assert!(!cpus.is_empty() && cpus[0].idle >= 0);
        let m = inventory::metrics().expect("metrics");
        assert!(m.total_memory > 0 && m.available_memory <= m.total_memory);
        assert!(m.uptime_ns > 0 && m.parallelism >= 1 && m.load[0] >= 0.0);
    }

    #[test]
    fn priorities_validate_and_read() {
        assert!(imp::cpu_count() >= 1);
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
