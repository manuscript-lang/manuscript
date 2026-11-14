//! Buffered standard output and unbuffered standard error.
use crate::sys;
use core::cell::UnsafeCell;
use ms_rt_abi::{MapVal, StrVal, VecVal};
use std::sync::atomic::{AtomicBool, AtomicI32, AtomicU8, Ordering};

const BUF_LIMIT: usize = 64 * 1024;
/// The process-wide output buffer. Every thread that runs Manuscript code writes through it, so
/// lines stay in program order. The lock is held only to append or to write out what is buffered,
/// so it is a flag and not a `Mutex`: a lone writer pays one atomic swap.
struct Out {
    locked: AtomicBool,
    buf: UnsafeCell<Vec<u8>>,
}

// SAFETY: `buf` is only reached through a `Guard`, which holds `locked`.
unsafe impl Sync for Out {}

static OUT: Out = Out {
    locked: AtomicBool::new(false),
    buf: UnsafeCell::new(Vec::new()),
};
/// 0 unknown, 1 pipe/file, 2 terminal.
static TTY: AtomicU8 = AtomicU8::new(0);

struct Guard(&'static Out);

impl core::ops::Deref for Guard {
    type Target = Vec<u8>;
    fn deref(&self) -> &Vec<u8> {
        // SAFETY: the guard holds the lock.
        unsafe { &*self.0.buf.get() }
    }
}

impl core::ops::DerefMut for Guard {
    fn deref_mut(&mut self) -> &mut Vec<u8> {
        // SAFETY: the guard holds the lock.
        unsafe { &mut *self.0.buf.get() }
    }
}

impl Drop for Guard {
    fn drop(&mut self) {
        self.0.locked.store(false, Ordering::Release);
    }
}

fn out() -> Guard {
    lock(&OUT)
}

fn lock(target: &'static Out) -> Guard {
    let mut spins = 0u32;
    while target.locked.swap(true, Ordering::Acquire) {
        spins += 1;
        if spins < 64 {
            core::hint::spin_loop();
        } else {
            // The holder may be writing to a full pipe.
            std::thread::yield_now();
        }
    }
    Guard(target)
}

/// The first failed stdout write since `msrt_io_error` last ran (an OS code), or 0. A broken
/// pipe is not kept: a reader that went away ends the output quietly.
static WRITE_ERROR: AtomicI32 = AtomicI32::new(0);

fn flush_locked(out: &mut Vec<u8>) {
    drain(sys::STDOUT, out);
}

fn drain(fd: i32, out: &mut Vec<u8>) {
    if !out.is_empty() {
        if let Err(code) = sys::write_all(fd, out.as_slice())
            && std::io::Error::from_raw_os_error(code).kind() != std::io::ErrorKind::BrokenPipe
        {
            let _ = WRITE_ERROR.compare_exchange(0, code, Ordering::Relaxed, Ordering::Relaxed);
        }
        out.clear();
    }
}

/// Takes the kept stdout write failure as text, or an empty string.
///
/// # Safety
/// `out` is writable memory for a string.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_io_error(out: *mut StrVal) {
    let code = WRITE_ERROR.swap(0, Ordering::Relaxed);
    let text = if code == 0 {
        String::new()
    } else {
        std::io::Error::from_raw_os_error(code).to_string()
    };
    // SAFETY: `out` is uninitialised memory for a string.
    unsafe { *out = crate::string::from_bytes(text.as_bytes()) };
}

pub fn flush_stdout() {
    flush_locked(&mut out());
}

pub fn write_stdout(data: &[u8]) {
    write_stdout_parts(data, b"");
}

/// Appends `data` and `end` under one lock, so a line written by one thread is never split by
/// another thread's output.
pub fn write_stdout_parts(data: &[u8], end: &[u8]) {
    let mut tty = TTY.load(Ordering::Relaxed);
    if tty == 0 {
        // SAFETY: plain libc call.
        tty = if unsafe { sys::isatty(sys::STDOUT) } != 0 {
            2
        } else {
            1
        };
        TTY.store(tty, Ordering::Relaxed);
    }
    let capture = crate::task::capture();
    if capture != 0 && append_capture(capture, data, end) {
        return;
    }
    append(&OUT, tty == 2, data, end);
}

/// Standard output of the tasks under each test capture, by capture id.
static CAPTURES: std::sync::Mutex<Vec<(u64, Vec<u8>)>> = std::sync::Mutex::new(Vec::new());
static NEXT_CAPTURE: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);

/// Appends to capture `id`; false when it has ended (the output goes to standard output).
fn append_capture(id: u64, data: &[u8], end: &[u8]) -> bool {
    let mut captures = CAPTURES.lock().unwrap_or_else(|e| e.into_inner());
    let Some((_, buf)) = captures.iter_mut().find(|(c, _)| *c == id) else {
        return false;
    };
    buf.extend_from_slice(data);
    buf.extend_from_slice(end);
    true
}

/// A new, empty test output capture for the test runner (`@std/internal/test_runner.ms`).
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_test_capture_new() -> i64 {
    let id = NEXT_CAPTURE.fetch_add(1, Ordering::Relaxed);
    CAPTURES
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .push((id, Vec::new()));
    id as i64
}

/// Sends the standard output of the running task, and of the tasks and promises it starts
/// from now on, to capture `id` (0: standard output).
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_test_capture_set(id: i64) {
    crate::task::set_capture(id as u64);
}

/// Bounds the running task's waits for one test (`on`), or lifts the bound: from
/// `MS_TEST_TIMEOUT_NS` from now (unset or 0: no bound) each fails with `ETIMEDOUT`, as a promise
/// `timeout` does.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_test_deadline(on: bool) {
    static TIMEOUT: std::sync::OnceLock<i64> = std::sync::OnceLock::new();
    let timeout = *TIMEOUT.get_or_init(|| {
        std::env::var("MS_TEST_TIMEOUT_NS")
            .ok()
            .and_then(|v| v.parse().ok())
            .unwrap_or(0)
    });
    let at = match timeout {
        _ if !on => i64::MAX,
        ..=0 => i64::MAX,
        ns => crate::sys::monotonic_ns().saturating_add(ns),
    };
    crate::task::set_defer_deadline(at);
}

/// The capture the running task's standard output goes to, or 0.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_test_capture_current() -> i64 {
    crate::task::capture() as i64
}

/// Returns and clears what capture `id` has collected.
///
/// # Safety
/// `out` is writable memory for a string.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_test_capture_take(id: i64, out: *mut StrVal) {
    let mut captures = CAPTURES.lock().unwrap_or_else(|e| e.into_inner());
    let text = captures
        .iter_mut()
        .find(|(c, _)| *c == id as u64)
        .map(|(_, buf)| core::mem::take(buf))
        .unwrap_or_default();
    drop(captures);
    // SAFETY: `out` is uninitialised memory for a string.
    unsafe { *out = crate::string::from_bytes(&text) };
}

/// Appends `text` to the file at `path` (the test runner's results file), whole: records from
/// files running at once never interleave. Failure is ignored; the host reports the test as
/// unfinished.
///
/// # Safety
/// `path` and `text` are live strings.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_test_record(path: *const StrVal, text: *const StrVal) {
    use std::io::Write;
    static LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());
    // SAFETY: the caller passes live strings.
    let (path, text) = unsafe { (crate::string::bytes(path), crate::string::bytes(text)) };
    let Ok(path) = core::str::from_utf8(path) else {
        return;
    };
    let _held = LOCK.lock().unwrap_or_else(|e| e.into_inner());
    if let Ok(mut file) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
    {
        let _ = file.write_all(text);
    }
}

/// Keeps the encoded record of a fault that ended a task under capture `id`, for
/// `msrt_test_capture_fault`.
pub(crate) fn capture_fault(id: u64, record: Vec<u8>) {
    let mut faults = CAPTURE_FAULTS.lock().unwrap_or_else(|e| e.into_inner());
    faults.retain(|(c, _)| *c != id);
    faults.push((id, record));
}

static CAPTURE_FAULTS: std::sync::Mutex<Vec<(u64, Vec<u8>)>> = std::sync::Mutex::new(Vec::new());

/// The encoded fault record (`ms_rt_abi::record`) of the last task under capture `id` that
/// faulted, or an empty string; taking it clears it.
///
/// # Safety
/// `out` is writable memory for a string.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_test_capture_fault(id: i64, out: *mut StrVal) {
    let mut faults = CAPTURE_FAULTS.lock().unwrap_or_else(|e| e.into_inner());
    let record = match faults.iter().position(|(c, _)| *c == id as u64) {
        Some(at) => faults.swap_remove(at).1,
        None => Vec::new(),
    };
    drop(faults);
    // SAFETY: `out` is uninitialised memory for a string.
    unsafe { *out = crate::string::from_bytes(&record) };
}

/// Ends capture `id`; later output of its tasks goes to standard output.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_test_capture_free(id: i64) {
    let mut captures = CAPTURES.lock().unwrap_or_else(|e| e.into_inner());
    captures.retain(|(c, _)| *c != id as u64);
}

fn append(target: &'static Out, tty: bool, data: &[u8], end: &[u8]) {
    let mut out = lock(target);
    out.extend_from_slice(data);
    out.extend_from_slice(end);
    if out.len() >= BUF_LIMIT || (tty && (data.contains(&b'\n') || end.contains(&b'\n'))) {
        flush_locked(&mut out);
    }
}

pub fn write_stderr(data: &[u8]) {
    flush_stdout();
    let _ = sys::write_all(sys::STDERR, data);
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_io_write_stdout(s: *const StrVal) {
    // SAFETY: caller passes a live string.
    write_stdout(unsafe { crate::string::bytes(s) });
}

/// `print`: the text and its ending in one locked append.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_io_write_stdout_line(s: *const StrVal, end: *const StrVal) {
    // SAFETY: caller passes live strings.
    write_stdout_parts(unsafe { crate::string::bytes(s) }, unsafe {
        crate::string::bytes(end)
    });
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_io_write_stderr(s: *const StrVal) {
    // SAFETY: caller passes a live string.
    write_stderr(unsafe { crate::string::bytes(s) });
}

/// The `details` key under which a failed test expectation carries the `file:line:column` that
/// built it.
const SITE_KEY: &[u8] = b"site";

/// Reports a failed test: the message and the site its `Error` carries in `details`, as text on
/// standard error and as a structured record for the CLI.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_test_failure(message: *const StrVal, details: *const MapVal) {
    // SAFETY: caller passes a live string and a live `Map[String, String]`.
    let (message, site) = unsafe {
        let key = crate::string::from_bytes(SITE_KEY);
        let found = crate::map::msrt_map_get_ptr(
            details,
            &crate::desc::msrt_desc_string,
            &crate::desc::msrt_desc_string,
            (&raw const key).cast(),
        )
        .cast::<StrVal>();
        let site = (!found.is_null()).then(|| crate::string::bytes(found).to_vec());
        crate::string::release(&key);
        (crate::string::bytes(message).to_vec(), site)
    };
    let mut text = message.clone();
    if let Some(site) = &site {
        text.extend_from_slice(b"\n  at ");
        text.extend_from_slice(site);
    }
    text.push(b'\n');
    write_stderr(&text);
    let mut record =
        ms_rt_abi::record::Record::new(ms_rt_abi::record::FaultKind::TestFailure, &message);
    record.site = site;
    crate::fault::write_record(&record);
}

/// The bytes of a live byte vector.
///
/// # Safety
/// `v` points to a live byte vector.
unsafe fn vec_bytes<'a>(v: *const VecVal) -> &'a [u8] {
    // SAFETY: a byte vector is `len` initialised bytes at `ptr` (null when empty).
    unsafe {
        let v = &*v;
        if v.len == 0 {
            &[]
        } else {
            core::slice::from_raw_parts(v.ptr, v.len)
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_io_write_bytes_stdout(v: *const VecVal) {
    // SAFETY: caller passes a live byte vector.
    write_stdout(unsafe { vec_bytes(v) });
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_io_write_bytes_stderr(v: *const VecVal) {
    // SAFETY: caller passes a live byte vector.
    write_stderr(unsafe { vec_bytes(v) });
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_io_flush() {
    flush_stdout();
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A failed drain is kept for `msrt_io_error` and the buffer is dropped.
    #[test]
    fn failed_drain_is_reported_once() {
        let mut buf = b"lost".to_vec();
        drain(9999, &mut buf);
        assert!(buf.is_empty());
        let mut text = core::mem::MaybeUninit::<StrVal>::uninit();
        // SAFETY: `text` is writable memory for a string.
        unsafe { msrt_io_error(text.as_mut_ptr()) };
        // SAFETY: initialised by the call above.
        assert!(!unsafe { crate::string::bytes(text.as_ptr()) }.is_empty());
        // SAFETY: as above.
        unsafe { msrt_io_error(text.as_mut_ptr()) };
        // SAFETY: as above.
        assert!(unsafe { crate::string::bytes(text.as_ptr()) }.is_empty());
    }

    /// A line and its ending are one append: threads printing at once never split a line, which
    /// two separate writes allowed ("startedstarted\n\n").
    #[test]
    fn concurrent_lines_are_not_split() {
        // Its own buffer: tests that print through `OUT` must not add to or flush it.
        static LOCAL: Out = Out {
            locked: AtomicBool::new(false),
            buf: UnsafeCell::new(Vec::new()),
        };
        let threads: Vec<_> = (0..4)
            .map(|_| {
                std::thread::spawn(|| {
                    for _ in 0..200 {
                        append(&LOCAL, false, b"started", b"\n");
                    }
                })
            })
            .collect();
        for t in threads {
            t.join().unwrap();
        }
        let mut out = lock(&LOCAL);
        let text = String::from_utf8(core::mem::take(&mut *out)).unwrap();
        assert_eq!(text, "started\n".repeat(800));
    }
}
