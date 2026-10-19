//! `@std/process` natives. Symbols are `msstd_process_<name>`.
//!
//! Fallible functions return a `STATUS_*` code (`0` ok) and write results only on success; for
//! `STATUS_FAILED` the Go-style text comes from `msstd_process_failure_message`. `ProcessError`
//! maps to the shared statuses (`InvalidInput`, `InvalidData`, `LimitExceeded`, `NotFound`,
//! `AlreadyExists`, `PermissionDenied`, `Unsupported`, `Closed`, `Failed`) and `CommandError` to
//! `InvalidInput`, `Unavailable`, `Timeout` (13), `OutputLimit` (14) and `Failed`. Optional values
//! are a present flag plus the value. A `Map[String, String]` crosses as two parallel string lists.
#![no_std]
// The exports below are the C ABI compiled code links against.
#![allow(unsafe_code)]
#![allow(clippy::missing_safety_doc)]

extern crate alloc;

pub mod command;
pub mod control;
pub mod envfile;
pub mod signals;

use alloc::vec::Vec;
use command::Subprocess;
use ms_rt_abi::{STATUS_INVALID_INPUT, STATUS_OK, StrObj, VecVal};
use ms_std_fs::err::{Fail, Res};
use ms_std_io::stream::Stream;
use ms_std_rt::{
    Handle, list_slice, new_handle, new_string, record_failure, str_bytes, write_bytes, write_list,
    write_string_list,
};

fn finish<T>(r: Res<T>, ok: impl FnOnce(T)) -> u8 {
    match r {
        Ok(v) => {
            ok(v);
            STATUS_OK
        }
        Err(Fail { status, message }) => {
            record_failure(message.unwrap_or_default());
            status
        }
    }
}

/// The text of the last `FAILED` result.
#[unsafe(no_mangle)]
pub extern "C" fn msstd_process_failure_message() -> *mut StrObj {
    ms_std_rt::failure_message()
}

unsafe extern "C-unwind" {
    fn msrt_start_nanos() -> i64;
    fn msrt_argv(out: *mut VecVal);
}

/// Nanoseconds since the runtime started (or since the first call when it did not record a start).
fn uptime_ns() -> i64 {
    use core::sync::atomic::{AtomicI64, Ordering};
    static FIRST: AtomicI64 = AtomicI64::new(0);
    // SAFETY: provided by `ms-rt`.
    let mut origin = unsafe { msrt_start_nanos() };
    if origin == 0 {
        origin = FIRST.load(Ordering::Relaxed);
        if origin == 0 {
            origin = command::now_ns();
            FIRST.store(origin, Ordering::Relaxed);
        }
    }
    command::now_ns() - origin
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_process_monotonic_time() -> i64 {
    uptime_ns()
}

/// `uptime()` as a `Duration` in nanoseconds.
#[unsafe(no_mangle)]
pub extern "C" fn msstd_process_uptime() -> i64 {
    uptime_ns()
}

unsafe fn strings<'a>(list: *const VecVal) -> Vec<&'a [u8]> {
    // SAFETY: a `List[String]` holds string pointers.
    unsafe {
        list_slice::<*const StrObj>(list)
            .iter()
            .map(|&s| str_bytes(s))
            .collect()
    }
}

fn new_strings(items: &[Vec<u8>]) -> Vec<*mut StrObj> {
    items.iter().map(|s| new_string(s)).collect()
}

/// The live environment as parallel `names` and `values` string lists.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_process_environment(names: *mut VecVal, values: *mut VecVal) -> u8 {
    finish(control::environment(), |pairs| {
        let (n, v): (Vec<_>, Vec<_>) = pairs.into_iter().unzip();
        // SAFETY: both outs are writable.
        unsafe {
            write_string_list(&new_strings(&n), names);
            write_string_list(&new_strings(&v), values);
        }
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_process_set_environment(
    name: *const StrObj,
    has_value: u8,
    value: *const StrObj,
) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    let r = unsafe {
        control::set_environment(str_bytes(name), (has_value != 0).then(|| str_bytes(value)))
    };
    finish(r, |()| ())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_process_load_environment(
    path: *const StrObj,
    has_max: u8,
    max: i64,
) -> u8 {
    let limit = ms_std_fs::ops::limit(has_max != 0, max);
    // SAFETY: arguments follow the ABI contract.
    let r = limit.and_then(|m| control::load_environment(unsafe { str_bytes(path) }, m));
    finish(r, |()| ())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_process_working_directory(out: *mut *mut StrObj) -> u8 {
    // SAFETY: `out` is writable.
    finish(control::working_directory(), |d| unsafe {
        *out = new_string(&d)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_process_change_directory(path: *const StrObj) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    finish(
        control::change_directory(unsafe { str_bytes(path) }),
        |()| (),
    )
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_process_send_signal(pid: i64, signal: i64) -> u8 {
    finish(control::send_signal(pid, signal), |()| ())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_process_groups(out: *mut VecVal) -> u8 {
    // SAFETY: `out` is writable.
    finish(control::groups(), |g| unsafe { write_list(&g, out) })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_process_set_groups(groups: *const VecVal) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    finish(
        control::set_groups(unsafe { list_slice::<i64>(groups) }),
        |()| (),
    )
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_process_initialize_groups(username: *const StrObj, gid: i64) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    finish(
        control::initialize_groups(unsafe { str_bytes(username) }, gid),
        |()| (),
    )
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_process_umask(mask: i64, out: *mut i64) -> u8 {
    // SAFETY: `out` is writable.
    finish(control::umask(mask), |old| unsafe { *out = old })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_process_set_identity(kind: *const StrObj, id: i64) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    finish(
        control::set_identity(unsafe { str_bytes(kind) }, id),
        |()| (),
    )
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_process_title(out: *mut *mut StrObj) -> u8 {
    // SAFETY: `out` is writable.
    finish(control::title(), |t| unsafe { *out = new_string(&t) })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_process_set_title(title: *const StrObj) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    finish(control::set_title(unsafe { str_bytes(title) }), |()| ())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_process_constrained_memory(out: *mut i64) -> u8 {
    // SAFETY: `out` is writable.
    finish(control::memory_limit(), |(limit, _)| unsafe {
        *out = limit
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_process_available_memory(out: *mut i64) -> u8 {
    // SAFETY: `out` is writable.
    finish(control::available_memory(), |v| unsafe { *out = v })
}

/// Flattened `CpuUsage` / `ResourceUsage` (microseconds, bytes and counts, in declaration order).
#[repr(C)]
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

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_process_resource_usage(out: *mut ResourceOut) -> u8 {
    // SAFETY: `out` is writable.
    finish(control::resource_usage(), |u| unsafe {
        out.write(ResourceOut {
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
    })
}

type SignalHandle = Handle<signals::Watcher>;

/// `watch_signals`: `signals` is a `List[Int]`; the capacity is a present flag plus the value.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_process_watch_signals(
    signals: *const VecVal,
    has_capacity: u8,
    capacity: i64,
    out: *mut *mut SignalHandle,
) -> u8 {
    // SAFETY: `signals` is an Int list and `out` writable.
    let r = signals::Watcher::new(
        unsafe { list_slice::<i64>(signals) },
        (has_capacity != 0).then_some(capacity),
    );
    // SAFETY: `out` is writable.
    finish(r, |w| unsafe { *out = new_handle(w) })
}

/// Waits for the next signal; `STATUS_CLOSED` after `msstd_process_signal_close`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_process_signal_next(h: *mut SignalHandle, out: *mut i64) -> u8 {
    // SAFETY: `h` is a live signal handle and `out` writable.
    finish(unsafe { (*h).value.wait() }, |n| unsafe { *out = n })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_process_signal_close(h: *mut SignalHandle) {
    // SAFETY: `h` is a live signal handle.
    unsafe { (*h).value.close() }
}

/// `memory_usage`: `heap_used`, `heap_total`, `heap_system`, `external`, `resident` in bytes.
/// Linux only; other hosts report `STATUS_UNSUPPORTED`.
#[repr(C)]
pub struct MemoryOut {
    pub heap_used: i64,
    pub heap_total: i64,
    pub heap_system: i64,
    pub external: i64,
    pub resident: i64,
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_process_memory_usage(out: *mut MemoryOut) -> u8 {
    // SAFETY: `out` is writable.
    finish(control::memory_usage(), |m| unsafe {
        out.write(MemoryOut {
            heap_used: m[0],
            heap_total: m[1],
            heap_system: m[2],
            external: m[3],
            resident: m[4],
        })
    })
}

/// Flattened `ProcessInfo`.
#[repr(C)]
pub struct InfoOut {
    pub pid: i64,
    pub parent_pid: i64,
    pub executable: *mut StrObj,
    pub arguments: VecVal,
    pub os: *mut StrObj,
    pub architecture: *mut StrObj,
    pub uid: i64,
    pub gid: i64,
    pub effective_uid: i64,
    pub effective_gid: i64,
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_process_info(out: *mut InfoOut) -> u8 {
    finish(control::info(), |i| {
        // SAFETY: `out` is writable; `msrt_argv` initialises the list.
        unsafe {
            let mut arguments = VecVal {
                ptr: core::ptr::null_mut(),
                len: 0,
                cap: 0,
            };
            msrt_argv(&mut arguments);
            out.write(InfoOut {
                pid: i.pid,
                parent_pid: i.parent_pid,
                executable: new_string(&i.executable),
                arguments,
                os: new_string(control::OS.as_bytes()),
                architecture: new_string(control::ARCH.as_bytes()),
                uid: i.uid,
                gid: i.gid,
                effective_uid: i.effective_uid,
                effective_gid: i.effective_gid,
            })
        }
    })
}

/// Replaces the process image; returns only on failure. `env_names`/`env_values` are parallel lists.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_process_replace(
    program: *const StrObj,
    arguments: *const VecVal,
    env_names: *const VecVal,
    env_values: *const VecVal,
) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    let r = unsafe {
        replace(
            str_bytes(program),
            &strings(arguments),
            &strings(env_names),
            &strings(env_values),
        )
    };
    match r {
        Ok(()) => STATUS_OK,
        Err(f) => finish::<()>(Err(f), |()| ()),
    }
}

fn nul_terminated(items: impl Iterator<Item = Vec<u8>>) -> Vec<Vec<u8>> {
    items
        .map(|mut v| {
            v.push(0);
            v
        })
        .collect()
}

fn replace(program: &[u8], args: &[&[u8]], names: &[&[u8]], values: &[&[u8]]) -> Res<()> {
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

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

/// Flattened `CommandOutput`.
#[repr(C)]
pub struct CommandOut {
    pub exit_code: i64,
    pub stdout: VecVal,
    pub stderr: VecVal,
}

/// A negative or absent `timeout`: `Ok(None)` for none, `InvalidInput` for a negative duration.
fn timeout(has: u8, value: i64) -> Res<Option<i64>> {
    match (has != 0, value) {
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

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_process_command_run(
    program: *const StrObj,
    arguments: *const VecVal,
    input: *const VecVal,
    has_max: u8,
    max: i64,
    has_timeout: u8,
    timeout_ns: i64,
    out: *mut CommandOut,
) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    let (program, args, input) = unsafe {
        (
            str_bytes(program),
            strings(arguments),
            ms_std_rt::vec_bytes(input),
        )
    };
    let r = ms_std_fs::ops::limit(has_max != 0, max)
        .and_then(|limit| Ok((limit, timeout(has_timeout, timeout_ns)?)))
        .and_then(|(limit, t)| {
            let args = valid_command(program, &args)?;
            command::run(program, &args, input, limit, t)
        });
    finish(r, |o| {
        let mut res = CommandOut {
            exit_code: o.code,
            stdout: VecVal {
                ptr: core::ptr::null_mut(),
                len: 0,
                cap: 0,
            },
            stderr: VecVal {
                ptr: core::ptr::null_mut(),
                len: 0,
                cap: 0,
            },
        };
        // SAFETY: `out` is writable.
        unsafe {
            write_bytes(&o.stdout, &mut res.stdout);
            write_bytes(&o.stderr, &mut res.stderr);
            out.write(res);
        }
    })
}

/// A live child and the handles of its three pipes.
pub struct Child {
    proc: Subprocess,
    streams: [*mut Handle<Stream>; 3],
}

impl Drop for Child {
    fn drop(&mut self) {
        self.proc.stop();
        for h in self.streams {
            // SAFETY: each handle was created by `spawn` and is released once here.
            unsafe {
                let _ = (*h).value.close();
                ms_std_rt::release(h.cast());
            }
        }
    }
}

type ChildHandle = Handle<Child>;

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_process_command_spawn(
    program: *const StrObj,
    arguments: *const VecVal,
    out: *mut *mut ChildHandle,
) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    let (program, args) = unsafe { (str_bytes(program), strings(arguments)) };
    let r = valid_command(program, &args).and_then(|args| command::spawn(program, &args));
    finish(r, |mut p| {
        let streams = [
            new_handle(Stream::new(p.stdin.take(), true, b"|1")),
            new_handle(Stream::new(p.stdout.take(), true, b"|0")),
            new_handle(Stream::new(p.stderr.take(), true, b"|0")),
        ];
        // SAFETY: `out` is writable.
        unsafe { *out = new_handle(Child { proc: p, streams }) }
    })
}

/// `which`: 0 stdin, 1 stdout, 2 stderr. Returns a new reference to the stream.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_process_subprocess_stream(
    h: *mut ChildHandle,
    which: i64,
) -> *mut Handle<Stream> {
    // SAFETY: `h` is a live child handle; the stream handle gains a reference for the caller.
    unsafe {
        let s = (*h).value.streams[which.clamp(0, 2) as usize];
        ms_std_rt::retain(s.cast());
        s
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_process_subprocess_wait(
    h: *mut ChildHandle,
    has_timeout: u8,
    timeout_ns: i64,
    out: *mut i64,
) -> u8 {
    // SAFETY: `h` is a live child handle and `out` writable.
    let r = timeout(has_timeout, timeout_ns).and_then(|t| unsafe { (*h).value.proc.wait(t) });
    // SAFETY: `out` is writable.
    finish(r, |code| unsafe { *out = code })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_process_subprocess_terminate(h: *mut ChildHandle) {
    // SAFETY: `h` is a live child handle.
    unsafe { (*h).value.proc.child.signal(false) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_process_subprocess_kill(h: *mut ChildHandle) {
    // SAFETY: `h` is a live child handle.
    unsafe { (*h).value.proc.child.signal(true) }
}

/// Kills the group, joins the child and closes all three pipes. Idempotent.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_process_subprocess_close(h: *mut ChildHandle) {
    // SAFETY: `h` is a live child handle.
    unsafe {
        let c = &mut (*h).value;
        c.proc.stop();
        for s in c.streams {
            let _ = (*s).value.close();
        }
    }
}

/// Stand-ins for the runtime symbols the crate links against, so its unit tests link alone.
#[cfg(test)]
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
