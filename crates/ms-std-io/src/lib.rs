//! `@std/io` natives. Symbols are `msstd_io_<name>`.
//!
//! The `ReadStream` and `WriteStream` types are Manuscript over the runtime stream table
//! (`ms-rt/src/streams.rs`). What remains here is the file-handle read and write that `NativeFile`
//! uses and the standard-stream redirect. Operations return a status: `0` ok,
//! `STATUS_NONE` for end of stream, or `FAILED` with its text stored through `err`.
//! ms: domain I/O
#![no_std]

extern crate alloc;

pub use ms_std_fs::stream;

use alloc::vec::Vec;
use ms_rt::ffi::{ErrOut, Has, ObjMut, StatusCode, native};
use ms_rt_abi::{STATUS_FAILED, STATUS_NONE};
use stream::{IoFail, IoRes, Stream};

/// A stream result as a status: a failure stores its text in `err`, which the caller reads for
/// `STATUS_FAILED`.
fn status<T>(r: IoRes<T>, err: &ErrOut) -> Result<T, StatusCode> {
    r.map_err(|IoFail { status, message }| {
        // The failing operation's frames have returned and dropped what they held; the jump
        // would skip the failure's own destructor.
        if ms_rt::glue::cancel_pending() && !ms_rt::glue::pool::on_pool_thread() {
            drop(message);
            ms_rt::glue::cancelled();
        }
        if status == STATUS_FAILED {
            err.set_bytes(&message);
        }
        StatusCode(status)
    })
}

/// Like [`status`], with end of stream (`None`) as `STATUS_NONE`.
fn chunk(r: IoRes<Option<Vec<u8>>>, err: &ErrOut) -> Result<Vec<u8>, StatusCode> {
    status(r, err)?.ok_or(StatusCode(STATUS_NONE))
}

fn optional(has: bool, v: i64) -> Option<i64> {
    has.then_some(v)
}

native! {
    /// Points this process's standard stream `which` (0 input, 1 output, 2 error) at the null device. Pending buffered output is written first.
    fn msstd_io_redirect_null(which: i64; err: ErrOut) -> Result<(), StatusCode> {
        if !(0..=2).contains(&which) {
            return Err(StatusCode(ms_rt_abi::STATUS_INVALID_INPUT));
        }
        ms_rt::io::flush_stdout();
        ms_std_fs::sys::redirect_standard_to_null(which).map_err(|errno| {
            err.set(&alloc::format!("redirect standard stream: errno {errno}"));
            StatusCode(STATUS_FAILED)
        })
    }

    /// The result of writing standard output: with `flush`, the buffered text is written first;
    /// the first write that failed (a full disk, a closed descriptor) is returned as an error.
    fn msstd_io_stdout_status(flush: bool; err: ErrOut) -> Result<(), StatusCode> {
        if flush {
            ms_rt::io::flush_stdout();
        }
        match ms_rt::io::stdout_error() {
            0 => Ok(()),
            code => status(
                Err(IoFail {
                    status: ms_std_fs::sys::classify(code),
                    message: ms_std_fs::sys::describe(code).into_bytes(),
                }),
                &err,
            ),
        }
    }

    /// Reads a chunk; `STATUS_NONE` at end of stream.
    fn msstd_io_read(
        h: ObjMut<Stream>,
        has_max: Has,
        max: i64;
        err: ErrOut
    ) -> Result<Vec<u8>, StatusCode> {
        let mut h = h;
        chunk(h.read(optional(*has_max, max)), &err)
    }

    fn msstd_io_write_bytes(h: ObjMut<Stream>, data: &[u8]; err: ErrOut) -> Result<(), StatusCode> {
        let mut h = h;
        status(h.write(data), &err)
    }

    fn msstd_io_write(h: ObjMut<Stream>, data: &str; err: ErrOut) -> Result<(), StatusCode> {
        let mut h = h;
        status(h.write(data.as_bytes()), &err)
    }

    /// Closes the stream; a failing descriptor release is returned as an error.
    fn msstd_io_close(h: ObjMut<Stream>; err: ErrOut) -> Result<(), StatusCode> {
        let mut h = h;
        status(h.close(), &err)
    }
}
