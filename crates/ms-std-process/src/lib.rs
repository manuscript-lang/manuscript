//! `@std/process` natives. Symbols are `msstd_process_<name>`.
//!
//! Fallible functions return a `STATUS_*` code (`0` ok) and write results only on success; for
//! `STATUS_FAILED` the Go-style text comes from `msstd_process_failure_message`. `ProcessError`
//! maps to the shared statuses (`InvalidInput`, `InvalidData`, `LimitExceeded`, `NotFound`,
//! `AlreadyExists`, `PermissionDenied`, `Unsupported`, `Closed`, `Failed`) and `CommandError` to
//! `InvalidInput`, `Unavailable`, `Timeout` (13), `OutputLimit` (14) and `Failed`. Optional values
//! are a present flag plus the value. A `Map[String, String]` crosses as two parallel string lists.

extern crate alloc;

pub mod command;
#[allow(unsafe_code)] // libc and Win32 process calls
pub mod control;
#[cfg(windows)]
#[allow(unsafe_code)]
mod control_windows;
pub mod envfile;
#[cfg(unix)]
#[path = "signals_unix.rs"]
#[allow(unsafe_code)] // libc signal handling
pub mod signals;
#[cfg(windows)]
#[path = "signals_windows.rs"]
#[allow(unsafe_code)]
pub mod signals;
#[allow(unsafe_code)] // posix_spawn
mod spawn;

/// Serialises tests that spawn children with tests that change the process environment: `setenv`
/// may reallocate `environ` while `posix_spawnp` reads it, which makes the spawn fail at random.
#[cfg(all(test, unix))]
pub(crate) fn environment_guard() -> std::sync::MutexGuard<'static, ()> {
    static LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());
    LOCK.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

use alloc::vec::Vec;
use command::Subprocess;
use ms_rt_abi::{STATUS_INVALID_INPUT, StrObj};
use ms_std_core::{
    Bytes, IntList, ObjBox, ObjMut, ObjRef, ObjShare, Object, StatusCode, Str, StrMap, StringList,
    Text, TextList, abi_handle, abi_record, argv, native, start_nanos,
};
use ms_std_fs::err::{Fail, Res};
use ms_std_fs::fs_status;
use ms_std_io::stream::Stream;

/// Nanoseconds since the runtime started (or since the first call when it did not record a start).
fn uptime_ns() -> i64 {
    use core::sync::atomic::{AtomicI64, Ordering};
    static FIRST: AtomicI64 = AtomicI64::new(0);
    let mut origin = start_nanos();
    if origin == 0 {
        origin = FIRST.load(Ordering::Relaxed);
        if origin == 0 {
            origin = command::now_ns();
            FIRST.store(origin, Ordering::Relaxed);
        }
    }
    command::now_ns() - origin
}

fn bytes_of<'a>(items: &'a [&'a str]) -> Vec<&'a [u8]> {
    items.iter().map(|s| s.as_bytes()).collect()
}

abi_record! {
    /// Flattened `CpuUsage` / `ResourceUsage` (microseconds, bytes and counts, in declaration order).
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

abi_record! {
    /// `memory_usage`: `heap_used`, `heap_total`, `heap_system`, `external`, `resident` in bytes.
    /// Linux only; other hosts report `STATUS_UNSUPPORTED`.
    pub struct MemoryOut {
        pub heap_used: i64,
        pub heap_total: i64,
        pub heap_system: i64,
        pub external: i64,
        pub resident: i64,
    }
}

abi_record! {
    /// Flattened `ProcessInfo`.
    pub struct InfoOut {
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

abi_record! {
    /// Flattened `CommandOutput`.
    pub struct CommandOut {
        pub exit_code: i64,
        pub stdout: Bytes,
        pub stderr: Bytes,
    }
}

abi_handle!(Child);

/// A negative or absent `timeout`: `Ok(None)` for none, `InvalidInput` for a negative duration.
fn timeout(has: bool, value: i64) -> Res<Option<i64>> {
    match (has, value) {
        (false, _) => Ok(None),
        (true, v) if v >= 0 => Ok(Some(v)),
        _ => Err(Fail::invalid()),
    }
}

fn valid_command(program: &[u8], args: &[&[u8]]) -> Res<Vec<Vec<u8>>> {
    if program.is_empty() || program.contains(&0) || args.iter().any(|a| a.contains(&0)) {
        return Err(Fail::status(STATUS_INVALID_INPUT));
    }
    Ok(args.iter().map(|a| a.to_vec()).collect())
}

/// A live child and its three pipes (stdin, stdout, stderr), each a runtime stream object that
/// the program may also hold.
pub struct Child {
    proc: Subprocess,
    streams: [ObjBox<Stream>; 3],
}

impl Drop for Child {
    fn drop(&mut self) {
        self.proc.stop();
        for s in &mut self.streams {
            let _ = s.get_mut().close();
        }
    }
}

/// One field of `ProcessInfo` per getter, so the generated code builds the record without a
/// shared layout. A host that cannot answer reads as an empty or zero field.
fn info_or_default() -> control::Info {
    control::info().unwrap_or(control::Info {
        pid: 0,
        parent_pid: 0,
        executable: Vec::new(),
        uid: -1,
        gid: -1,
        effective_uid: -1,
        effective_gid: -1,
    })
}

native! {
    /// The text of the last `FAILED` result.
    safe fn msstd_process_failure_message() -> *mut StrObj {
        ms_std_rt::failure_message()
    }

    safe fn msstd_process_monotonic_time() -> i64 {
        uptime_ns()
    }

    /// `uptime()` as a `Duration` in nanoseconds.
    safe fn msstd_process_uptime() -> i64 {
        uptime_ns()
    }

    /// The live environment as parallel `names` and `values` string lists.
    fn msstd_process_environment() -> Result<(TextList, TextList), StatusCode> {
        let (names, values): (Vec<_>, Vec<_>) = fs_status(control::environment())?.into_iter().unzip();
        Ok((TextList(names), TextList(values)))
    }

    fn msstd_process_set_environment(
        name: &str,
        has_value: bool,
        value: Option<&str>,
    ) -> Result<(), StatusCode> {
        let value = value.filter(|_| has_value).map(str::as_bytes);
        fs_status(control::set_environment(name.as_bytes(), value))
    }

    fn msstd_process_load_environment(
        path: &str,
        has_max: bool,
        max: i64,
    ) -> Result<(), StatusCode> {
        fs_status(ms_std_fs::ops::limit(has_max, max)
            .and_then(|m| control::load_environment(path.as_bytes(), m)))
    }

    fn msstd_process_working_directory() -> Result<Text, StatusCode> {
        fs_status(control::working_directory()).map(Text)
    }

    fn msstd_process_change_directory(path: &str) -> Result<(), StatusCode> {
        fs_status(control::change_directory(path.as_bytes()))
    }

    safe fn msstd_process_send_signal(pid: i64, signal: i64) -> Result<(), StatusCode> {
        fs_status(control::send_signal(pid, signal))
    }

    fn msstd_process_groups() -> Result<IntList, StatusCode> {
        fs_status(control::groups()).map(IntList)
    }

    fn msstd_process_set_groups(groups: &[i64]) -> Result<(), StatusCode> {
        fs_status(control::set_groups(groups))
    }

    fn msstd_process_initialize_groups(username: &str, gid: i64) -> Result<(), StatusCode> {
        fs_status(control::initialize_groups(username.as_bytes(), gid))
    }

    fn msstd_process_umask(mask: i64) -> Result<i64, StatusCode> {
        fs_status(control::umask(mask))
    }

    fn msstd_process_set_identity(kind: &str, id: i64) -> Result<(), StatusCode> {
        fs_status(control::set_identity(kind.as_bytes(), id))
    }

    fn msstd_process_title() -> Result<Text, StatusCode> {
        fs_status(control::title()).map(Text)
    }

    fn msstd_process_set_title(title: &str) -> Result<(), StatusCode> {
        fs_status(control::set_title(title.as_bytes()))
    }

    fn msstd_process_constrained_memory() -> Result<i64, StatusCode> {
        fs_status(control::memory_limit()).map(|(limit, _)| limit)
    }

    fn msstd_process_available_memory() -> Result<i64, StatusCode> {
        fs_status(control::available_memory())
    }

    fn msstd_process_resource_usage() -> Result<ResourceOut, StatusCode> {
        fs_status(control::resource_usage()).map(|u| ResourceOut {
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
        has_capacity: bool,
        capacity: i64,
    ) -> Result<Object<signals::Watcher>, StatusCode> {
        fs_status(signals::Watcher::new(signals, has_capacity.then_some(capacity))).map(Object)
    }

    /// Waits for the next signal; `STATUS_CLOSED` after `msstd_process_signal_close`.
    fn msstd_process_signal_next(h: ObjMut<signals::Watcher>) -> Result<i64, StatusCode> {
        let mut h = h;
        fs_status(h.wait())
    }

    fn msstd_process_signal_close(h: ObjMut<signals::Watcher>) -> () {
        let mut h = h;
        h.close()
    }

    fn msstd_process_memory_usage() -> Result<MemoryOut, StatusCode> {
        fs_status(control::memory_usage()).map(|m| MemoryOut {
            heap_used: m[0],
            heap_total: m[1],
            heap_system: m[2],
            external: m[3],
            resident: m[4],
        })
    }

    fn msstd_process_info() -> Result<InfoOut, StatusCode> {
        fs_status(control::info()).map(|i| InfoOut {
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

    /// Replaces the process image; returns only on failure. `env_names`/`env_values` are
    /// parallel lists.
    fn msstd_process_replace(
        program: &str,
        arguments: Vec<&str>,
        env_names: Vec<&str>,
        env_values: Vec<&str>,
    ) -> Result<(), StatusCode> {
        fs_status(replace(
            program.as_bytes(),
            &bytes_of(&arguments),
            &bytes_of(&env_names),
            &bytes_of(&env_values),
        ))
    }

    fn msstd_process_command_run(
        program: &str,
        arguments: Vec<&str>,
        input: &[u8],
        has_max: bool,
        max: i64,
        has_timeout: bool,
        timeout_ns: i64,
    ) -> Result<CommandOut, StatusCode> {
        let program = program.as_bytes();
        let ran = ms_std_fs::ops::limit(has_max, max)
            .and_then(|limit| Ok((limit, timeout(has_timeout, timeout_ns)?)))
            .and_then(|(limit, t)| {
                let args = valid_command(program, &bytes_of(&arguments))?;
                command::run(program, &args, input, limit, t)
            });
        fs_status(ran).map(|o| CommandOut {
            exit_code: o.code,
            stdout: Bytes::new(&o.stdout),
            stderr: Bytes::new(&o.stderr),
        })
    }

    fn msstd_process_command_spawn(
        program: &str,
        arguments: Vec<&str>,
    ) -> Result<Object<Child>, StatusCode> {
        let program = program.as_bytes();
        let spawned = valid_command(program, &bytes_of(&arguments))
            .and_then(|args| command::spawn(program, &args));
        let mut p = fs_status(spawned)?;
        let streams = [
            ObjBox::new(Stream::new(p.stdin.take(), true, b"|1")),
            ObjBox::new(Stream::new(p.stdout.take(), true, b"|0")),
            ObjBox::new(Stream::new(p.stderr.take(), true, b"|0")),
        ];
        Ok(Object(Child { proc: p, streams }))
    }

    /// `which`: 0 stdin, 1 stdout, 2 stderr. Returns a new reference to the stream.
    fn msstd_process_subprocess_stream(h: ObjRef<Child>, which: i64) -> ObjShare<Stream> {
        h.streams[which.clamp(0, 2) as usize].share()
    }

    fn msstd_process_subprocess_wait(
        h: ObjMut<Child>,
        has_timeout: bool,
        timeout_ns: i64,
    ) -> Result<i64, StatusCode> {
        let mut h = h;
        fs_status(timeout(has_timeout, timeout_ns).and_then(|t| h.proc.wait(t)))
    }

    fn msstd_process_subprocess_terminate(h: ObjMut<Child>) -> () {
        let mut h = h;
        h.proc.child.signal(false)
    }

    fn msstd_process_subprocess_kill(h: ObjMut<Child>) -> () {
        let mut h = h;
        h.proc.child.signal(true)
    }

    /// Kills the group, joins the child and closes all three pipes. Idempotent.
    fn msstd_process_subprocess_close(h: ObjMut<Child>) -> () {
        let mut h = h;
        h.proc.stop();
        for s in &mut h.streams {
            let _ = s.get_mut().close();
        }
    }

    /// `uptime()` as `Result[Duration, ProcessError]`: the nanoseconds since the runtime started.
    fn msstd_process_elapsed() -> Result<i64, StatusCode> {
        Ok(uptime_ns())
    }

    /// The live environment as a `Map[String, String]`.
    fn msstd_process_environment_map() -> Result<StrMap, StatusCode> {
        fs_status(control::environment()).map(StrMap)
    }

    safe fn msstd_process_info_pid() -> i64 {
        info_or_default().pid
    }

    safe fn msstd_process_info_parent_pid() -> i64 {
        info_or_default().parent_pid
    }

    safe fn msstd_process_info_executable() -> Text {
        Text(info_or_default().executable)
    }

    fn msstd_process_info_arguments() -> out StringList {
        argv()
    }

    safe fn msstd_process_info_os() -> &'static str {
        control::OS
    }

    safe fn msstd_process_info_architecture() -> &'static str {
        control::ARCH
    }

    safe fn msstd_process_info_uid() -> i64 {
        info_or_default().uid
    }

    safe fn msstd_process_info_gid() -> i64 {
        info_or_default().gid
    }

    safe fn msstd_process_info_effective_uid() -> i64 {
        info_or_default().effective_uid
    }

    safe fn msstd_process_info_effective_gid() -> i64 {
        info_or_default().effective_gid
    }
}

#[cfg(unix)]
use exec::replace;
#[cfg(windows)]
fn replace(_: &[u8], _: &[&[u8]], _: &[&[u8]], _: &[&[u8]]) -> Res<()> {
    // Go's syscall.Exec is EWINDOWS there.
    Err(Fail::status(ms_rt_abi::STATUS_UNSUPPORTED))
}

#[cfg(unix)]
#[allow(unsafe_code)] // libc `execve`
mod exec {
    use alloc::vec::Vec;
    use ms_std_fs::err::{Fail, Res};

    fn nul_terminated(items: impl Iterator<Item = Vec<u8>>) -> Vec<Vec<u8>> {
        items
            .map(|mut v| {
                v.push(0);
                v
            })
            .collect()
    }

    pub(crate) fn replace(
        program: &[u8],
        args: &[&[u8]],
        names: &[&[u8]],
        values: &[&[u8]],
    ) -> Res<()> {
        if program.is_empty()
            || program.contains(&0)
            || args.is_empty()
            || args.iter().any(|a| a.contains(&0))
        {
            return Err(Fail::invalid());
        }
        let mut env: Vec<Vec<u8>> = Vec::new();
        for (k, v) in names.iter().zip(values) {
            if k.is_empty() || k.contains(&b'=') || k.contains(&0) || v.contains(&0) {
                return Err(Fail::invalid());
            }
            let mut e = k.to_vec();
            e.push(b'=');
            e.extend_from_slice(v);
            env.push(e);
        }
        let prog = nul_terminated(core::iter::once(program.to_vec()));
        let argv = nul_terminated(args.iter().map(|a| a.to_vec()));
        let envp = nul_terminated(env.into_iter());
        let mut argp: Vec<*const libc::c_char> = argv
            .iter()
            .map(|a| a.as_ptr() as *const libc::c_char)
            .collect();
        argp.push(core::ptr::null());
        let mut envs: Vec<*const libc::c_char> = envp
            .iter()
            .map(|a| a.as_ptr() as *const libc::c_char)
            .collect();
        envs.push(core::ptr::null());
        // SAFETY: all strings are NUL-terminated and both arrays are NULL-terminated.
        unsafe {
            libc::execve(
                prog[0].as_ptr() as *const libc::c_char,
                argp.as_ptr(),
                envs.as_ptr(),
            )
        };
        let mut m = b"exec ".to_vec();
        m.extend_from_slice(program);
        m.extend_from_slice(b": ");
        let e = ms_std_fs::sys::errno();
        let status = ms_std_fs::err::classify(e);
        m.extend_from_slice(ms_std_fs::err::describe(e).as_bytes());
        Err(Fail {
            status,
            message: Some(m),
        })
    }
}

/// Stand-ins for the runtime symbols the crate links against, so its unit tests link alone.
#[cfg(test)]
#[allow(unsafe_code)]
mod runtime_stubs {
    #[unsafe(no_mangle)]
    pub static msrt_cancel_flag: u8 = 0;

    #[unsafe(no_mangle)]
    pub extern "C" fn msrt_cancelled() -> ! {
        panic!("cancelled")
    }

    #[unsafe(no_mangle)]
    pub extern "C-unwind" fn msrt_io_flush() {}

    #[unsafe(no_mangle)]
    pub extern "C-unwind" fn msrt_heap_stats(out: *mut i64) {
        // SAFETY: tests pass two writable words.
        unsafe {
            out.write(1);
            out.add(1).write(2);
        }
    }

    #[unsafe(no_mangle)]
    pub extern "C-unwind" fn msrt_start_nanos() -> i64 {
        0
    }

    #[unsafe(no_mangle)]
    pub extern "C-unwind" fn msrt_argv(_: *mut ms_rt_abi::VecVal) {}
}
