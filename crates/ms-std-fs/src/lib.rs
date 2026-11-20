//! `@std/fs` natives for path-based operations. Symbols are `msstd_fs_<name>`.
//!
//! Paths arrive as strings; fallible functions return a `STATUS_*` code (`0` ok) and write results
//! only on success. For `STATUS_FAILED` the diagnostic text is available from
//! the `err` out string of the failing call. `FileInfo` is flattened into
//! [`InfoOut`]; optional limits are a present flag plus an `i64`.
//! ms: domain filesystem
// `libc::statfs` field widths differ per target, so the portable casts look redundant on Linux.
#![allow(clippy::unnecessary_cast)]
#![recursion_limit = "256"]

extern crate alloc;

pub mod err;
pub mod ops;
pub mod path;
#[allow(unsafe_code)] // libc and Win32 calls
pub mod sys;

use alloc::vec::Vec;
use err::{Fail, Res};
use ms_rt::ffi::{ErrOut, StatusCode};
use ms_rt_abi::STATUS_FAILED;

/// Delivers a pending cancel once the failing operation's frames have returned and dropped what
/// they held. Runs only at the FFI boundary, never on a pool thread; the native then returns its
/// status as usual. The failure's text is dropped first while a cancel can still jump.
fn raise_cancel(message: &mut Option<Vec<u8>>) {
    if !ms_rt::glue::pool::on_pool_thread() && ms_rt::glue::cancel_pending() {
        drop(message.take());
        ms_rt::glue::cancel_return();
    }
}

/// A filesystem result as a status: a failure stores its text in `err`, which the caller reads
/// for `STATUS_FAILED` (so it is always written for that status).
pub fn fs_status<T>(r: Res<T>, err: &ErrOut) -> Result<T, StatusCode> {
    r.map_err(
        |Fail {
             status,
             mut message,
         }| {
            raise_cancel(&mut message);
            if status == STATUS_FAILED {
                err.set_bytes(&message.unwrap_or_default());
            }
            StatusCode(status)
        },
    )
}

/// Like [`fs_status`], naming `path` for every failure but `STATUS_FAILED`, which has its own text:
/// the message reads `filesystem: <failure>: <path>`.
pub fn fs_status_at<T>(path: &[u8], r: Res<T>, err: &ErrOut) -> Result<T, StatusCode> {
    r.map_err(
        |Fail {
             status,
             mut message,
         }| {
            raise_cancel(&mut message);
            if status == STATUS_FAILED {
                err.set_bytes(&message.unwrap_or_default());
            } else {
                err.set_bytes(path);
            }
            StatusCode(status)
        },
    )
}

/// Like [`fs_status_at`] for a two-path operation: the detail reads `<source> -> <destination>`.
pub fn fs_status_pair<T>(
    source: &[u8],
    destination: &[u8],
    r: Res<T>,
    err: &ErrOut,
) -> Result<T, StatusCode> {
    let both = [source, b" -> ", destination].concat();
    fs_status_at(&both, r, err)
}
