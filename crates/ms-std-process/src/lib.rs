//! `@std/process` natives. Symbols are `msstd_process_<name>`.
//!
//! Fallible functions return a `STATUS_*` code (`0` ok) and write results only on success; for
//! `STATUS_FAILED` the Go-style text is the `err` out string of the call. control errors
//! map to the shared statuses (`InvalidInput`, `InvalidData`, `LimitExceeded`, `NotFound`,
//! `AlreadyExists`, `PermissionDenied`, `Unsupported`, `Closed`, `Failed`) and command errors to
//! `InvalidInput`, `Unavailable`, `Timeout` (13), `OutputLimit` (14) and `Failed`. Optional values
//! are a present flag plus the value. A `Map[String, String]` crosses as two parallel string lists.
//! ms: domain process

extern crate alloc;

#[allow(unsafe_code)] // libc and Win32 process calls
pub mod control;
#[cfg(windows)]
#[allow(unsafe_code)]
mod control_windows;
#[cfg(unix)]
#[path = "signals_unix.rs"]
#[allow(unsafe_code)] // libc signal handling
pub mod signals;
#[cfg(windows)]
#[path = "signals_windows.rs"]
#[allow(unsafe_code)]
pub mod signals;

/// Serialises tests that spawn children with tests that change the process environment: `setenv`
/// may reallocate `environ` while `posix_spawnp` reads it, which makes the spawn fail at random.
#[cfg(all(test, unix))]
pub(crate) fn environment_guard() -> std::sync::MutexGuard<'static, ()> {
    static LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());
    LOCK.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

use alloc::vec::Vec;
use ms_rt::ffi::ErrOut;
use ms_rt::ffi::{
    Has, IntList, ObjMut, Object, StatusCode, Str, StrMap, StringList, Text, TextList, abi_type,
    argv, monotonic_nanos, native, start_nanos,
};
use ms_std_fs::fs_status;

/// Nanoseconds since the runtime started (or since the first call when it did not record a start).
fn uptime_ns() -> i64 {
    static FIRST: std::sync::OnceLock<i64> = std::sync::OnceLock::new();
    let now = monotonic_nanos();
    let origin = match start_nanos() {
        0 => *FIRST.get_or_init(|| now),
        start => start,
    };
    now - origin
}

abi_type! {
    /// Flattened `ResourceUsage` (microseconds, bytes and counts, in declaration order).
    pub struct ResourceOut {
        pub user_microseconds: i64,
        pub system_microseconds: i64,
        pub max_resident_bytes: i64,
        pub minor_faults: i64,
        pub major_faults: i64,
        pub filesystem_reads: i64,
        pub filesystem_writes: i64,
        pub voluntary_switches: i64,
        pub involuntary_switches: i64,
    }
}

abi_type! {
    /// Flattened `CpuUsage`: user and kernel microseconds.
    pub struct CpuOut {
        pub user_microseconds: i64,
        pub system_microseconds: i64,
    }
}

abi_type! {
    /// `runtime_counts`: allocations and bytes, list copies and bytes, string clones and bytes, MIR operations.
    pub struct CountsOut {
        pub allocations: i64,
        pub allocated_bytes: i64,
        pub list_copies: i64,
        pub list_copy_bytes: i64,
        pub string_clones: i64,
        pub string_clone_bytes: i64,
        pub operations: i64,
    }
}

abi_type! {
    /// `memory_usage`: `heap_used`, `heap_total`, `heap_system`, `external`, `resident` in bytes.
    /// Linux, macOS and Windows; other hosts report `STATUS_UNSUPPORTED`.
    pub struct MemoryOut {
        pub heap_used: i64,
        pub heap_total: i64,
        pub heap_system: i64,
        pub external: i64,
        pub resident: i64,
    }
}

abi_type! {
    /// Flattened `ProcessInfo`.
    pub struct ProcessInfoOut {
        pub pid: i64,
        pub parent_pid: i64,
        pub executable: Str,
        pub arguments: StringList,
        pub os: Str,
        pub architecture: Str,
        pub uid: i64,
        pub gid: i64,
        pub effective_uid: i64,
        pub effective_gid: i64,
    }
}

native! {
    /// `uptime()` as a `Duration` in nanoseconds.
    safe fn msstd_process_uptime() -> i64 {
        uptime_ns()
    }

    /// The live environment as parallel `names` and `values` string lists.
    fn msstd_process_environment(; err: ErrOut) -> Result<(TextList, TextList), StatusCode> {
        let (names, values): (Vec<_>, Vec<_>) = fs_status(control::environment(), &err)?.into_iter().unzip();
        Ok((TextList(names), TextList(values)))
    }

    fn msstd_process_set_environment(
        name: &str,
        has_value: Has,
        value: &str; err: ErrOut) -> Result<(), StatusCode> {
        let value = has_value.then_some(value.as_bytes());
        fs_status(control::set_environment(name.as_bytes(), value), &err)
    }

    fn msstd_process_environment_is_set(name: &str) -> bool {
        control::environment_is_set(name.as_bytes())
    }

    fn msstd_process_working_directory(; err: ErrOut) -> Result<Text, StatusCode> {
        fs_status(control::working_directory(), &err).map(Text)
    }

    fn msstd_process_change_directory(path: &str; err: ErrOut) -> Result<(), StatusCode> {
        fs_status(control::change_directory(path.as_bytes()), &err)
    }

    fn msstd_process_send_signal(pid: i64, signal: i64; err: ErrOut) -> Result<(), StatusCode> {
        fs_status(control::send_signal(pid, signal), &err)
    }

    fn msstd_process_groups(; err: ErrOut) -> Result<IntList, StatusCode> {
        fs_status(control::groups(), &err).map(IntList)
    }

    fn msstd_process_set_groups(groups: &[i64]; err: ErrOut) -> Result<(), StatusCode> {
        fs_status(control::set_groups(groups), &err)
    }

    fn msstd_process_initialize_groups(username: &str, gid: i64; err: ErrOut) -> Result<(), StatusCode> {
        fs_status(control::initialize_groups(username.as_bytes(), gid), &err)
    }

    fn msstd_process_umask(mask: i64; err: ErrOut) -> Result<i64, StatusCode> {
        fs_status(control::umask(mask), &err)
    }

    fn msstd_process_set_identity(kind: &str, id: i64; err: ErrOut) -> Result<(), StatusCode> {
        fs_status(control::set_identity(kind.as_bytes(), id), &err)
    }

    fn msstd_process_title(; err: ErrOut) -> Result<Text, StatusCode> {
        fs_status(control::title(), &err).map(Text)
    }

    fn msstd_process_set_title(title: &str; err: ErrOut) -> Result<(), StatusCode> {
        fs_status(control::set_title(title.as_bytes()), &err)
    }

    fn msstd_process_constrained_memory(; err: ErrOut) -> Result<i64, StatusCode> {
        fs_status(control::memory_limit(), &err).map(|(limit, _)| limit)
    }

    fn msstd_process_available_memory(; err: ErrOut) -> Result<i64, StatusCode> {
        fs_status(control::available_memory(), &err)
    }

    fn msstd_process_resource_usage(; err: ErrOut) -> Result<ResourceOut, StatusCode> {
        fs_status(control::resource_usage(), &err).map(|u| ResourceOut {
            user_microseconds: u.user_us,
            system_microseconds: u.system_us,
            max_resident_bytes: u.max_rss,
            minor_faults: u.minor_faults,
            major_faults: u.major_faults,
            filesystem_reads: u.reads,
            filesystem_writes: u.writes,
            voluntary_switches: u.voluntary,
            involuntary_switches: u.involuntary,
        })
    }

    /// `watch_signals`: `signals` is a `List[Int]`; the capacity is a present flag plus the value.
    fn msstd_process_watch_signals(
        signals: &[i64],
        has_capacity: Has,
        capacity: i64; err: ErrOut) -> Result<Object<signals::Watcher>, StatusCode> {
        fs_status(signals::Watcher::new(signals, has_capacity.then_some(capacity)), &err).map(Object)
    }

    /// Waits for the next signal; `STATUS_CLOSED` after `msstd_process_signal_close`.
    fn msstd_process_signal_next(h: ObjMut<signals::Watcher>; err: ErrOut) -> Result<i64, StatusCode> {
        let mut h = h;
        fs_status(h.wait(), &err)
    }

    fn msstd_process_signal_close(h: ObjMut<signals::Watcher>) -> () {
        let mut h = h;
        h.close()
    }

    fn msstd_process_cpu_usage(; err: ErrOut) -> Result<CpuOut, StatusCode> {
        fs_status(control::resource_usage(), &err).map(|u| CpuOut {
            user_microseconds: u.user_us,
            system_microseconds: u.system_us,
        })
    }

    /// `runtime_counts()` as `Result[RuntimeCounts, ControlError]`: the runtime's work counters.
    fn msstd_process_runtime_counts() -> Result<CountsOut, StatusCode> {
        let mut c = [0u64; 7];
        // SAFETY: `c` holds the seven words the runtime writes.
        unsafe { ms_rt::obj::msrt_counts(c.as_mut_ptr()) };
        let [a, b, d, e, f, g, h] = c.map(|v| v as i64);
        Ok(CountsOut {
            allocations: a,
            allocated_bytes: b,
            list_copies: d,
            list_copy_bytes: e,
            string_clones: f,
            string_clone_bytes: g,
            operations: h,
        })
    }

    fn msstd_process_memory_usage(; err: ErrOut) -> Result<MemoryOut, StatusCode> {
        fs_status(control::memory_usage(), &err).map(|m| MemoryOut {
            heap_used: m[0],
            heap_total: m[1],
            heap_system: m[2],
            external: m[3],
            resident: m[4],
        })
    }

    fn msstd_process_info(; err: ErrOut) -> Result<ProcessInfoOut, StatusCode> {
        fs_status(control::info(), &err).map(|i| ProcessInfoOut {
            pid: i.pid,
            parent_pid: i.parent_pid,
            executable: Str::from_bytes(&i.executable),
            arguments: argv(),
            os: Str::new(control::OS),
            architecture: Str::new(control::ARCH),
            uid: i.uid,
            gid: i.gid,
            effective_uid: i.effective_uid,
            effective_gid: i.effective_gid,
        })
    }

    /// `uptime()` as `Result[Duration, ControlError]`: the nanoseconds since the runtime started.
    fn msstd_process_elapsed() -> Result<i64, StatusCode> {
        Ok(uptime_ns())
    }

    /// The live environment as a `Map[String, String]`.
    fn msstd_process_environment_map(; err: ErrOut) -> Result<StrMap, StatusCode> {
        fs_status(control::environment(), &err).map(StrMap)
    }
}
