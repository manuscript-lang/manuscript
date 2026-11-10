//! `@std/io` natives. Symbols are `msstd_terminal_<name>`.
//!
//! `capabilities()` and `size()` cross as one getter per record field (`size` also has a
//! `_status` call first). `raw_mode` returns a handle whose operations are the
//! `msstd_terminal_raw_terminal_*` exports; the event delivered by `next_event` is read back
//! through the `msstd_terminal_event_*` getters.
//! ms: domain terminal
#![no_std]

// Links the msrt_* runtime symbols into this crate's test binaries.
#[cfg(test)]
use ms_rt as _;

extern crate alloc;
extern crate std;

mod raw;
#[cfg(unix)]
#[path = "sys_unix.rs"]
mod sys;
#[cfg(windows)]
#[path = "sys_windows.rs"]
mod sys;

use core::cell::Cell;
use ms_rt::ffi::{ErrOut, Failure, Global, ObjRef, Object, Out, StatusCode, abi_handle, native};
use ms_rt::glue::poll_cancel;

/// The status of `f`, raising a pending cancel first: operations that parked return a failure
/// instead of jumping, so their frames have returned and dropped what they held.
fn fail(err: &ErrOut, f: Failure) -> StatusCode {
    poll_cancel();
    err.fail(f)
}
use ms_rt_abi::StrVal;
use ms_rt_abi::{STATUS_NOT_TERMINAL, STATUS_OK, STATUS_UNSUPPORTED};

/// A raw terminal handle. The event stream and the terminal's controls hold one each.
#[repr(transparent)]
pub struct RawH(pub alloc::rc::Rc<raw::Raw>);
abi_handle!(RawH);

impl core::ops::Deref for RawH {
    type Target = raw::Raw;
    fn deref(&self) -> &raw::Raw {
        &self.0
    }
}

const NS_PER_MS: i64 = 1_000_000;

/// Sleeps the task for `ns` so another task's read can finish; `Err` when a stop request ends it.
#[allow(unsafe_code)]
fn pause(ns: i64) -> Result<(), ms_rt::glue::pool::Cancelled> {
    #[cfg(not(test))]
    {
        // SAFETY: provided by `ms-rt`; the wait bit 16 reports a stop request.
        if unsafe { ms_rt::task::msrt_task_sleep(ns) } & 16 != 0 {
            return Err(ms_rt::glue::pool::Cancelled);
        }
    }
    #[cfg(test)]
    std::thread::sleep(core::time::Duration::from_nanos(ns.max(0) as u64));
    Ok(())
}

/// Whether standard descriptor `fd` (0 and 1; anything else is standard error) is a terminal.
fn is_terminal(fd: i32) -> bool {
    use std::io::IsTerminal;
    match fd {
        0 => std::io::stdin().is_terminal(),
        1 => std::io::stdout().is_terminal(),
        _ => std::io::stderr().is_terminal(),
    }
}

/// The text the last `read` delivered.
static INPUT: Global<Cell<alloc::string::String>> =
    Global::new(Cell::new(alloc::string::String::new()));

fn raw_mode_capable() -> bool {
    is_terminal(0) && is_terminal(1)
}

native! {
    safe fn msstd_terminal_capabilities_input_is_terminal() -> bool {
        is_terminal(0)
    }

    safe fn msstd_terminal_capabilities_output_is_terminal() -> bool {
        is_terminal(1)
    }

    safe fn msstd_terminal_capabilities_error_is_terminal() -> bool {
        is_terminal(2)
    }

    safe fn msstd_terminal_capabilities_raw_mode() -> bool {
        raw_mode_capable()
    }

    safe fn msstd_terminal_capabilities_resize_events() -> bool {
        raw_mode_capable()
    }

    safe fn msstd_terminal_capabilities_colors() -> i64 {
        sys::colors()
    }

    safe fn msstd_terminal_size_status() -> u8 {
        if !is_terminal(1) {
            STATUS_NOT_TERMINAL
        } else if sys::stdout_size().is_some() {
            STATUS_OK
        } else {
            STATUS_UNSUPPORTED
        }
    }

    safe fn msstd_terminal_size_columns() -> i64 {
        sys::stdout_size().map_or(0, |s| s.0)
    }

    safe fn msstd_terminal_size_rows() -> i64 {
        sys::stdout_size().map_or(0, |s| s.1)
    }

    fn msstd_terminal_raw_mode(out: Out<Object<RawH>>; err: ErrOut) -> Result<(), StatusCode> {
        out.write(Object(RawH(alloc::rc::Rc::new(
            raw::Raw::open().map_err(|f| fail(&err, f))?,
        ))));
        Ok(())
    }

    fn msstd_terminal_raw_terminal_close(h: ObjRef<RawH>) -> () {
        h.close();
    }

    /// Another handle on the same terminal, for the event stream.
    fn msstd_terminal_raw_terminal_share(h: ObjRef<RawH>) -> Object<RawH> {
        Object(RawH(h.0.0.clone()))
    }

    fn msstd_terminal_raw_terminal_size_status(h: ObjRef<RawH>) -> u8 {
        poll_cancel();
        h.size().err().unwrap_or(STATUS_OK)
    }

    fn msstd_terminal_raw_terminal_size_columns(h: ObjRef<RawH>) -> i64 {
        h.size().map_or(0, |s| s.0)
    }

    fn msstd_terminal_raw_terminal_size_rows(h: ObjRef<RawH>) -> i64 {
        h.size().map_or(0, |s| s.1)
    }

    /// Writes text or control sequences to the terminal, after flushing buffered output.
    fn msstd_terminal_raw_terminal_write(h: ObjRef<RawH>, text: &str; err: ErrOut) -> Result<(), StatusCode> {
        poll_cancel();
        h.command(text.as_bytes()).map_err(|f| fail(&err, f))
    }

    /// Sets the text written when the terminal closes, before its settings are restored.
    fn msstd_terminal_raw_terminal_set_restore(h: ObjRef<RawH>, text: &str) -> () {
        h.set_restore(text.as_bytes());
    }

    /// Waits for input: `STATUS_OK` with the text in `msstd_terminal_input_text`,
    /// `STATUS_NONE` when nothing came in 40 ms (`quick`) or 50 ms, `STATUS_CLOSED` once closed.
    fn msstd_terminal_raw_terminal_read(h: ObjRef<RawH>, quick: bool) -> u8 {
        poll_cancel();
        let mut text = alloc::string::String::new();
        let status = h.read(quick, &mut text);
        // The wait returned instead of jumping, so its frames are gone; raise a cancel now.
        poll_cancel();
        if status == STATUS_OK {
            INPUT.get().set(text);
        }
        status
    }

    /// The text of the last successful read.
    fn msstd_terminal_input_text() -> out StrVal {
        let text = INPUT.get().take();
        let value = ms_rt::glue::new_string(text.as_bytes());
        INPUT.get().set(text);
        value
    }
}

#[cfg(all(test, unix))]
#[allow(unsafe_code)]
mod tests {
    use super::*;
    use ms_rt as _; // links the msrt_* runtime symbols

    #[test]
    fn redirected_streams_refuse_raw_mode() {
        if msstd_terminal_capabilities_input_is_terminal() == 1 {
            return;
        }
        let mut out = core::ptr::null_mut();
        // SAFETY: the handle pointer is never written.
        let status =
            unsafe { msstd_terminal_raw_mode(&mut out, ms_rt_abi::ErrSlot(core::ptr::null_mut())) };
        assert_eq!(status, STATUS_NOT_TERMINAL);
        assert_eq!(msstd_terminal_capabilities_raw_mode(), 0);
    }
}
