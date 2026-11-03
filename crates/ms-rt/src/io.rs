//! Buffered standard output and unbuffered standard error.
use crate::global::Process;
use crate::sys;
use ms_rt_abi::{MapVal, StrVal, VecVal};

const BUF_LIMIT: usize = 64 * 1024;
static OUT: Process<Vec<u8>> = Process::new(Vec::new());
/// 0 unknown, 1 pipe/file, 2 terminal.
static TTY: Process<u8> = Process::new(0);

/// Serializes whole writes from worker isolates, which skip the main isolate's buffer.
static WORKER_OUT: std::sync::Mutex<()> = std::sync::Mutex::new(());

pub fn flush_stdout() {
    // The buffer belongs to the main isolate; a worker writes straight through.
    if crate::isolate::is_worker() {
        return;
    }
    // SAFETY: single threaded access to the output buffer (the fault path may
    // run on the same thread inside a write; the buffer is only appended to).
    let out = unsafe { &mut *OUT.ptr() };
    if !out.is_empty() {
        sys::write_all(sys::STDOUT, out.as_slice());
        out.clear();
    }
}

pub fn write_stdout(data: &[u8]) {
    if crate::isolate::is_worker() {
        let _turn = WORKER_OUT.lock().unwrap_or_else(|e| e.into_inner());
        sys::write_all(sys::STDOUT, data);
        return;
    }
    // SAFETY: single threaded access.
    let (out, tty) = unsafe { (&mut *OUT.ptr(), &mut *TTY.ptr()) };
    if *tty == 0 {
        // SAFETY: plain libc call.
        *tty = if unsafe { sys::isatty(sys::STDOUT) } != 0 {
            2
        } else {
            1
        };
    }
    out.extend_from_slice(data);
    if out.len() >= BUF_LIMIT || (*tty == 2 && data.contains(&b'\n')) {
        flush_stdout();
    }
}

pub fn write_stderr(data: &[u8]) {
    flush_stdout();
    sys::write_all(sys::STDERR, data);
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_io_write_stdout(s: *const StrVal) {
    // SAFETY: caller passes a live string.
    write_stdout(unsafe { crate::string::bytes(s) });
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

/// Closing a standard stream only flushes it: the descriptors belong to the process, so the
/// stream stays usable (`which` is 0 for output, 1 for error).
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_io_close(_which: i64) {
    flush_stdout();
}
