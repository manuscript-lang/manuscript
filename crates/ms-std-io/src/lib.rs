//! `@std/io` natives for host streams. Symbols are `msstd_io_<name>`.
//!
//! A stream is a refcounted handle (`stdin`, `stdout`, `stderr` borrow their descriptors, `open`
//! owns one). Operations return an `IoError` status: `0` ok, `STATUS_NONE` for end of stream,
//! `CLOSED`, `INVALID_INPUT`, `UNAVAILABLE`, `INVALID_DATA`, `LIMIT_EXCEEDED`, or `FAILED` with
//! its Go-style text from `msstd_io_failure_message`. Outputs are written only on success.
//! Generic `copy`/`read_all`/`read_line` over user-defined `ReadStream`s stay compiler-lowered.
#![no_std]

extern crate alloc;

pub use ms_std_fs::stream;

mod accumulate;

use alloc::vec::Vec;
use ms_rt_abi::{STATUS_NONE, StrObj};
use ms_std_core::{ObjMut, ObjRef, Object, StatusCode, Text, native};
use ms_std_rt::{fault, record_failure};
use stream::{IoFail, IoRes, Stream};

/// A stream result as a status: a failure records its text for `msstd_io_failure_message`.
fn status<T>(r: IoRes<T>) -> Result<T, StatusCode> {
    r.map_err(|IoFail { status, message }| {
        record_failure(message);
        StatusCode(status)
    })
}

/// Like [`status`], with end of stream (`None`) as `STATUS_NONE`.
fn chunk(r: IoRes<Option<Vec<u8>>>) -> Result<Vec<u8>, StatusCode> {
    status(r)?.ok_or(StatusCode(STATUS_NONE))
}

fn optional(has: bool, v: i64) -> Option<i64> {
    has.then_some(v)
}

native! {
    /// The text of the last `FAILED` stream result.
    safe fn msstd_io_failure_message() -> *mut StrObj {
        ms_std_rt::failure_message()
    }

    /// `which`: 0 standard input, 1 standard output, 2 standard error. The descriptor stays open.
    safe fn msstd_io_standard(which: i64) -> Object<Stream> {
        Object(Stream::standard(which))
    }

    fn msstd_io_open(path: &str) -> Result<Object<Stream>, StatusCode> {
        status(Stream::open(path.as_bytes())).map(Object)
    }

    /// Reads a chunk; `STATUS_NONE` at end of stream.
    fn msstd_io_read(
        h: ObjMut<Stream>,
        has_max: bool,
        max: i64,
    ) -> Result<Vec<u8>, StatusCode> {
        let mut h = h;
        chunk(h.read(optional(has_max, max)))
    }

    /// Reads one line without its ending; `STATUS_NONE` at end of stream.
    fn msstd_io_read_line(
        h: ObjMut<Stream>,
        has_max: bool,
        max: i64,
    ) -> Result<Text, StatusCode> {
        let mut h = h;
        chunk(h.read_line(optional(has_max, max))).map(Text)
    }

    fn msstd_io_write_bytes(h: ObjMut<Stream>, data: &[u8]) -> Result<(), StatusCode> {
        let mut h = h;
        status(h.write(data))
    }

    fn msstd_io_write(h: ObjMut<Stream>, data: &str) -> Result<(), StatusCode> {
        let mut h = h;
        status(h.write(data.as_bytes()))
    }

    fn msstd_io_flush(h: ObjMut<Stream>) -> Result<(), StatusCode> {
        let mut h = h;
        status(h.flush())
    }

    /// Closes the stream; a failing descriptor release raises a fault with its text.
    fn msstd_io_close(h: ObjMut<Stream>) -> () {
        let mut h = h;
        if let Err(IoFail { message, .. }) = h.close() {
            fault(core::str::from_utf8(&message).unwrap_or("close failed"));
        }
    }

    fn msstd_io_is_closed(h: ObjRef<Stream>) -> bool {
        h.is_closed()
    }
}

/// Stand-ins for the runtime symbols `ms-std-rt` links against, so the crate's unit tests link alone.
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
}
