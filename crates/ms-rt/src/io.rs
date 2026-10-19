//! Buffered standard output and unbuffered standard error.
use crate::buf::ByteBuf;
use crate::global::Global;
use crate::sys;
use ms_rt_abi::StrObj;

const BUF_LIMIT: usize = 64 * 1024;
static OUT: Global<ByteBuf> = Global::new(ByteBuf::new());
/// 0 unknown, 1 pipe/file, 2 terminal.
static TTY: Global<u8> = Global::new(0);

pub fn flush_stdout() {
    // SAFETY: single threaded access to the output buffer (the fault path may
    // run on the same thread inside a write; the buffer is only appended to).
    let out = unsafe { &mut *OUT.ptr() };
    if !out.is_empty() {
        sys::write_all(sys::STDOUT, out.as_slice());
        out.clear();
    }
}

pub fn write_stdout(data: &[u8]) {
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
    out.extend(data);
    if out.len() >= BUF_LIMIT || (*tty == 2 && data.contains(&b'\n')) {
        flush_stdout();
    }
}

pub fn write_stderr(data: &[u8]) {
    flush_stdout();
    sys::write_all(sys::STDERR, data);
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_io_write_stdout(s: *mut StrObj) {
    // SAFETY: caller passes a live string.
    write_stdout(unsafe { crate::string::bytes(s) });
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_io_write_stderr(s: *mut StrObj) {
    // SAFETY: caller passes a live string.
    write_stderr(unsafe { crate::string::bytes(s) });
}

#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_io_flush() {
    flush_stdout();
}
