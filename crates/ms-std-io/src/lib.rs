//! `@std/io` natives for host streams. Symbols are `msstd_io_<name>`.
//!
//! A stream is a refcounted handle (`stdin`, `stdout`, `stderr` borrow their descriptors, `open`
//! owns one). Operations return an `IoError` status: `0` ok, `STATUS_NONE` for end of stream,
//! `CLOSED`, `INVALID_INPUT`, `UNAVAILABLE`, `INVALID_DATA`, `LIMIT_EXCEEDED`, or `FAILED` with
//! its Go-style text from `msstd_io_failure_message`. Outputs are written only on success.
//! Generic `copy`/`read_all`/`read_line` over user-defined `ReadStream`s stay compiler-lowered.
#![no_std]
// The exports below are the C ABI compiled code links against.
#![allow(unsafe_code)]
#![allow(clippy::missing_safety_doc)]

extern crate alloc;

pub use ms_std_fs::stream;

mod accumulate;

use ms_rt_abi::{STATUS_NONE, STATUS_OK, StrObj, VecVal};
use ms_std_rt::{
    Handle, fault, new_handle, new_string, record_failure, str_bytes, vec_bytes, write_bytes,
};
use stream::{IoFail, IoRes, Stream};

type Host = Handle<Stream>;

fn done<T>(r: IoRes<T>, ok: impl FnOnce(T)) -> u8 {
    match r {
        Ok(v) => {
            ok(v);
            STATUS_OK
        }
        Err(IoFail { status, message }) => {
            record_failure(message);
            status
        }
    }
}

fn optional(has: u8, v: i64) -> Option<i64> {
    (has != 0).then_some(v)
}

/// The text of the last `FAILED` stream result.
#[unsafe(no_mangle)]
pub extern "C" fn msstd_io_failure_message() -> *mut StrObj {
    ms_std_rt::failure_message()
}

/// `which`: 0 standard input, 1 standard output, 2 standard error. The descriptor stays open.
#[unsafe(no_mangle)]
pub extern "C" fn msstd_io_standard(which: i64) -> *mut Host {
    let (fd, name): (i32, &[u8]) = match which {
        0 => (0, b"/dev/stdin"),
        1 => (1, b"/dev/stdout"),
        _ => (2, b"/dev/stderr"),
    };
    new_handle(Stream::new(fd, false, name))
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_io_open(path: *const StrObj, out: *mut *mut Host) -> u8 {
    // SAFETY: arguments follow the ABI contract.
    done(Stream::open(unsafe { str_bytes(path) }), |s| unsafe {
        *out = new_handle(s)
    })
}

/// Reads a chunk; `STATUS_NONE` at end of stream.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_io_read(
    h: *mut Host,
    has_max: u8,
    max: i64,
    out: *mut VecVal,
) -> u8 {
    // SAFETY: `h` is a live stream handle.
    let r = unsafe { (*h).value.read(optional(has_max, max)) };
    match r {
        Ok(None) => STATUS_NONE,
        // SAFETY: `out` is writable.
        other => done(other, |c| unsafe {
            write_bytes(&c.unwrap_or_default(), out)
        }),
    }
}

/// Reads one line without its ending; `STATUS_NONE` at end of stream.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_io_read_line(
    h: *mut Host,
    has_max: u8,
    max: i64,
    out: *mut *mut StrObj,
) -> u8 {
    // SAFETY: `h` is a live stream handle.
    let r = unsafe { (*h).value.read_line(optional(has_max, max)) };
    match r {
        Ok(None) => STATUS_NONE,
        // SAFETY: `out` is writable.
        other => done(other, |l| unsafe {
            *out = new_string(&l.unwrap_or_default())
        }),
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_io_write_bytes(h: *mut Host, data: *const VecVal) -> u8 {
    // SAFETY: `h` is a live stream handle and `data` a live byte vector.
    done(unsafe { (*h).value.write(vec_bytes(data)) }, |()| ())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_io_write(h: *mut Host, data: *const StrObj) -> u8 {
    // SAFETY: `h` is a live stream handle and `data` a live string.
    done(unsafe { (*h).value.write(str_bytes(data)) }, |()| ())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_io_flush(h: *mut Host) -> u8 {
    // SAFETY: `h` is a live stream handle.
    done(unsafe { (*h).value.flush() }, |()| ())
}

/// Closes the stream; a failing descriptor release raises a fault with its text.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_io_close(h: *mut Host) {
    // SAFETY: `h` is a live stream handle.
    if let Err(IoFail { message, .. }) = unsafe { (*h).value.close() } {
        fault(core::str::from_utf8(&message).unwrap_or("close failed"));
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_io_is_closed(h: *const Host) -> u8 {
    // SAFETY: `h` is a live stream handle.
    unsafe { (*h).value.is_closed() as u8 }
}

/// Stand-ins for the runtime symbols `ms-std-rt` links against, so the crate's unit tests link alone.
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
}
