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
use core::cell::RefCell;
use ms_rt_abi::{STATUS_NONE, StrVal};
use ms_std_core::{Global, Handed, ObjBox, ObjMut, ObjRef, Object, StatusCode, Text, native};
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

/// The standard-input handle `stdin()` returns while nothing else holds it. Programs call
/// `stdin()` once per read, so reusing the handle makes a call a retain instead of an allocation.
static STDIN: Global<RefCell<Option<ObjBox<Stream>>>> = Global::new(RefCell::new(None));

/// A standard-input handle. The shared one is reused only while this slot is its sole holder,
/// so no caller can tell it from the new handle each call used to get: a kept handle or a
/// reader parked mid-read makes the next call get a handle of its own.
fn standard_input() -> Handed<Stream> {
    let mut slot = STDIN.get().borrow_mut();
    if let Some(h) = slot.as_mut() {
        if !h.is_unique() {
            return Handed::New(Object(Stream::standard(0)));
        }
        let stream = h.get_mut();
        if !stream.is_closed() {
            stream.take_stashed();
            return Handed::Shared(h.share());
        }
    }
    // Dropping a closed handle stashes its read-ahead for the new one.
    if slot.take().is_none() {
        ms_std_rt::on_exit(release_standard_input);
    }
    Handed::Shared(slot.insert(ObjBox::new(Stream::standard(0))).share())
}

/// Releases the shared standard-input handle when the program ends, so it is not counted as
/// a leak.
extern "C" fn release_standard_input() {
    drop(STDIN.get().borrow_mut().take());
}

fn optional(has: bool, v: i64) -> Option<i64> {
    has.then_some(v)
}

native! {
    /// The text of the last `FAILED` stream result.
    fn msstd_io_failure_message() -> out StrVal {
        ms_std_rt::failure_message()
    }

    /// `which`: 0 standard input, 1 standard output, 2 standard error. The descriptor stays open.
    safe fn msstd_io_standard(which: i64) -> Handed<Stream> {
        if which == 0 {
            return standard_input();
        }
        Handed::New(Object(Stream::standard(which)))
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
