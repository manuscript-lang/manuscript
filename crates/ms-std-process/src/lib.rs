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
use ms_rt::ffi::ErrOut;
use ms_rt::ffi::{
    Bytes, Has, IntList, ObjBox, ObjMut, ObjRef, Object, StatusCode, Str, StrMap, StringList, Text,
    TextList, abi_handle, abi_type, argv, monotonic_nanos, native, start_nanos,
};
use ms_rt_abi::STATUS_INVALID_INPUT;
use ms_std_fs::err::Fail as FsFail;
use ms_std_fs::err::{Fail, Res};
use ms_std_fs::{fs_status, fs_status_at};
use ms_std_io::stream::Stream;

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

fn bytes_of<'a>(items: &'a [&'a str]) -> Vec<&'a [u8]> {
    items.iter().map(|s| s.as_bytes()).collect()
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

abi_type! {
    /// Flattened `CommandOutput`.
    pub struct CommandOut {
        pub exit_code: i64,
        pub stdout: Bytes,
        pub stderr: Bytes,
        pub max_resident_bytes: i64,
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

/// The stream over a subprocess's parent end, or an already closed stream when that standard
/// stream was not piped.
pub(crate) fn parent_end(fd: &mut command::Fd, name: &[u8]) -> Stream {
    if fd.is_open() {
        return Stream::new(fd.take(), true, name);
    }
    let mut closed = Stream::new(fd.0, false, name);
    let _ = closed.close();
    closed
}

/// The working directory and extra variables of a command, checked for NUL bytes and for names
/// that cannot be variables (empty, or holding `=`).
fn valid_environment<'a>(
    cwd: Option<&'a [u8]>,
    names: &[&'a str],
    values: &[&'a str],
) -> Res<Vec<(&'a str, &'a [u8])>> {
    let bad_name = |n: &&str| n.is_empty() || n.contains(['=', '\0']);
    if cwd.is_some_and(|c| c.is_empty() || c.contains(&0))
        || names.iter().any(bad_name)
        || values.iter().any(|v| v.contains('\0'))
    {
        return Err(Fail::status(STATUS_INVALID_INPUT));
    }
    Ok(names
        .iter()
        .copied()
        .zip(values.iter().map(|v| v.as_bytes()))
        .collect())
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
    /// The runtime stream-table id of each pipe once taken (-2 not yet, -1 no pipe).
    ids: [i64; 3],
}

impl Drop for Child {
    fn drop(&mut self) {
        self.proc.stop();
        for s in &mut self.streams {
            let _ = s.get_mut().close();
        }
    }
}

/// [`fs_status`], naming `program` when it could not be started (not found, not allowed, not
/// executable); invalid arguments, a timeout or an output limit are not about the program's name.
fn command_status<T>(
    program: &[u8],
    cwd: Option<&[u8]>,
    r: Res<T>,
    err: &ErrOut,
) -> Result<T, StatusCode> {
    match r {
        Err(FsFail {
            status:
                ms_rt_abi::STATUS_UNAVAILABLE
                | ms_rt_abi::STATUS_NOT_FOUND
                | ms_rt_abi::STATUS_PERMISSION_DENIED,
            ..
        }) => {
            // A missing working directory fails the start the same way a missing program does.
            let dir = cwd.filter(|d| {
                core::str::from_utf8(d).is_ok_and(|d| !std::path::Path::new(d).is_dir())
            });
            match dir {
                Some(dir) => {
                    let mut named = b"working directory ".to_vec();
                    named.extend_from_slice(dir);
                    fs_status_at(&named, r, err)
                }
                None => fs_status_at(program, r, err),
            }
        }
        r => fs_status(r, err),
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

    fn msstd_process_load_environment(
        path: &str,
        has_max: Has,
        max: i64; err: ErrOut) -> Result<(), StatusCode> {
        fs_status(ms_std_fs::ops::limit(*has_max, max)
            .and_then(|m| control::load_environment(path.as_bytes(), m)), &err)
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

    /// Replaces the process image; returns only on failure. `env_names`/`env_values` are
    /// parallel lists.
    fn msstd_process_replace(
        program: &str,
        arguments: Vec<&str>,
        env_names: Vec<&str>,
        env_values: Vec<&str>; err: ErrOut) -> Result<(), StatusCode> {
        command_status(program.as_bytes(), None, replace(
            program.as_bytes(),
            &bytes_of(&arguments),
            &bytes_of(&env_names),
            &bytes_of(&env_values),
        ), &err)
    }

    fn msstd_process_command_run(
        program: &str,
        arguments: Vec<&str>,
        input: &[u8],
        has_max: Has,
        max: i64,
        has_timeout: Has,
        timeout_ns: i64,
        has_cwd: Has,
        cwd: &str,
        env_names: Vec<&str>,
        env_values: Vec<&str>; err: ErrOut) -> Result<CommandOut, StatusCode> {
        let program = program.as_bytes();
        let cwd = has_cwd.then_some(cwd.as_bytes());
        let ran = ms_std_fs::ops::limit(*has_max, max)
            .and_then(|limit| Ok((limit, timeout(*has_timeout, timeout_ns)?)))
            .and_then(|(limit, t)| {
                let args = valid_command(program, &bytes_of(&arguments))?;
                let env = valid_environment(cwd, &env_names, &env_values)?;
                command::run(program, &args, input, limit, t, cwd, &env)
            });
        // `run` returns early when cancelled, its child already reaped by its frame's drop.
        if ms_rt::glue::cancel_pending() {
            ms_rt::glue::cancelled();
        }
        command_status(program, cwd, ran, &err).map(|o| CommandOut {
            exit_code: o.code,
            stdout: Bytes::new(&o.stdout),
            stderr: Bytes::new(&o.stderr),
            max_resident_bytes: o.max_resident,
        })
    }

    /// `stdin`, `stdout`, `stderr`: the case index of `Stdio` (`command::STDIO_*`).
    fn msstd_process_command_spawn(
        program: &str,
        arguments: Vec<&str>,
        stdin: i64,
        stdout: i64,
        stderr: i64,
        has_cwd: Has,
        cwd: &str,
        env_names: Vec<&str>,
        env_values: Vec<&str>; err: ErrOut) -> Result<Object<Child>, StatusCode> {
        let program = program.as_bytes();
        let cwd = has_cwd.then_some(cwd.as_bytes());
        let spawned = valid_command(program, &bytes_of(&arguments)).and_then(|args| {
            let env = valid_environment(cwd, &env_names, &env_values)?;
            command::spawn(program, &args, [stdin, stdout, stderr], cwd, &env)
        });
        let mut p = command_status(program, cwd, spawned, &err)?;
        let streams = [
            ObjBox::new(parent_end(&mut p.stdin, b"|1")),
            ObjBox::new(parent_end(&mut p.stdout, b"|0")),
            ObjBox::new(parent_end(&mut p.stderr, b"|0")),
        ];
        Ok(Object(Child { proc: p, streams, ids: [-2; 3] }))
    }

    /// The runtime stream-table id of the child's pipe `which` (0 stdin, 1 stdout, 2 stderr): the
    /// first call moves the descriptor into the table, later calls answer the same id; -1 when
    /// there is no pipe (or the host cannot hand the descriptor over).
    fn msstd_process_subprocess_stream_id(h: ObjMut<Child>, which: i64) -> i64 {
        let mut h = h;
        let which = which.clamp(0, 2) as usize;
        let h = &mut *h;
        stream_id(&mut h.streams[which], &mut h.ids[which], which == 0)
    }

    fn msstd_process_subprocess_wait(
        h: ObjMut<Child>,
        has_timeout: Has,
        timeout_ns: i64; err: ErrOut) -> Result<i64, StatusCode> {
        let mut h = h;
        fs_status(timeout(*has_timeout, timeout_ns).and_then(|t| h.proc.wait(t)), &err)
    }

    /// The peak resident set size of the exited child in bytes; 0 while it runs or when unknown.
    fn msstd_process_subprocess_max_resident(h: ObjRef<Child>) -> i64 {
        h.proc.child.max_resident
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

    /// `uptime()` as `Result[Duration, ControlError]`: the nanoseconds since the runtime started.
    fn msstd_process_elapsed() -> Result<i64, StatusCode> {
        Ok(uptime_ns())
    }

    /// The live environment as a `Map[String, String]`.
    fn msstd_process_environment_map(; err: ErrOut) -> Result<StrMap, StatusCode> {
        fs_status(control::environment(), &err).map(StrMap)
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

/// Moves the descriptor of `stream` into the runtime stream table once and answers its id.
pub(crate) fn stream_id(stream: &mut ObjBox<Stream>, id: &mut i64, writes: bool) -> i64 {
    if *id == -2 {
        let fd = stream.get_mut().take_fd();
        use ms_rt::streams::{NONBLOCK, OWNS, READS, WRITES};
        *id = if fd < 0 {
            -1
        } else {
            ms_rt::streams::msrt_streams_open(
                fd,
                OWNS | NONBLOCK | if writes { WRITES } else { READS },
            )
        };
    }
    *id
}
