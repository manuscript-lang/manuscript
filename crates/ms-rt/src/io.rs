//! Buffered standard output and unbuffered standard error.
use crate::sys;
use core::cell::UnsafeCell;
use ms_rt_abi::{StrVal, VecVal};
use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};

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
    let mut spins = 0u32;
    while OUT.locked.swap(true, Ordering::Acquire) {
        spins += 1;
        if spins < 64 {
            core::hint::spin_loop();
        } else {
            // The holder may be writing to a full pipe.
            std::thread::yield_now();
        }
    }
    Guard(&OUT)
}

fn flush_locked(out: &mut Vec<u8>) {
    if !out.is_empty() {
        sys::write_all(sys::STDOUT, out.as_slice());
        out.clear();
    }
}

pub fn flush_stdout() {
    flush_locked(&mut out());
}

pub fn write_stdout(data: &[u8]) {
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
    let mut out = out();
    out.extend_from_slice(data);
    if out.len() >= BUF_LIMIT || (tty == 2 && data.contains(&b'\n')) {
        flush_locked(&mut out);
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

/// The last failure built by a test assertion: its message and source position.
static TEST_SITE: std::sync::Mutex<Option<(Vec<u8>, Vec<u8>)>> = std::sync::Mutex::new(None);

/// Remembers where the assertion failure carrying `message` was built.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_test_site(message: *const StrVal, site: *const StrVal) {
    // SAFETY: caller passes live strings.
    let entry = unsafe {
        (
            crate::string::bytes(message).to_vec(),
            crate::string::bytes(site).to_vec(),
        )
    };
    if let Ok(mut slot) = TEST_SITE.lock() {
        // A failure the standard library builds around an earlier assertion's message (a
        // property check reporting its counterexample) keeps the assertion's own position.
        if entry.1.starts_with(b"@std/")
            && let Some((earlier, site)) = slot.as_ref()
            && !earlier.is_empty()
            && !site.starts_with(b"@std/")
            && entry
                .0
                .windows(earlier.len())
                .any(|w| w == earlier.as_slice())
        {
            let site = site.clone();
            *slot = Some((entry.0, site));
            return;
        }
        *slot = Some(entry);
    }
}

/// Writes `  at <position>` to stderr when `message` is the last recorded assertion failure.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_test_site_report(message: *const StrVal) {
    // SAFETY: caller passes a live string.
    let message = unsafe { crate::string::bytes(message) };
    let Ok(slot) = TEST_SITE.lock() else { return };
    if let Some((recorded, site)) = slot.as_ref()
        && recorded == message
    {
        let mut line = b"\n  at ".to_vec();
        line.extend_from_slice(site);
        write_stderr(&line);
    }
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
