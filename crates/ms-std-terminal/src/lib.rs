//! `@std/io` natives. Symbols are `msstd_terminal_<name>`.
//!
//! `capabilities()` and `size()` cross as one getter per record field (`size` also has a
//! `_status` call first). `raw_mode` returns a handle whose operations are the
//! `msstd_terminal_raw_terminal_*` exports; the event delivered by `next_event` is read back
//! through the `msstd_terminal_event_*` getters.
#![no_std]

extern crate alloc;
#[cfg(unix)]
extern crate std;

mod decoder;
#[cfg(unix)]
mod raw;
#[cfg(not(unix))]
#[path = "raw_unsupported.rs"]
mod raw;

use core::cell::RefCell;
use ms_rt_abi::StrObj;
use ms_rt_abi::{STATUS_NOT_TERMINAL, STATUS_OK, STATUS_UNSUPPORTED};
use ms_std_core::{Global, ObjRef, Object, Out, StatusCode, abi_handle, native};
use ms_std_rt::poll_cancel;

abi_handle!(raw::Raw);

#[cfg(unix)]
mod imp {
    use rustix::fd::BorrowedFd;
    use rustix::stdio::{stderr, stdin, stdout};
    use rustix::termios::{isatty, tcgetwinsize};
    use std::ffi::OsString;
    use std::os::unix::ffi::OsStrExt;

    /// The standard descriptor numbered `fd` (0 and 1; anything else is standard error).
    fn standard(fd: i32) -> BorrowedFd<'static> {
        match fd {
            0 => stdin(),
            1 => stdout(),
            _ => stderr(),
        }
    }

    pub fn is_terminal(fd: i32) -> bool {
        isatty(standard(fd))
    }

    fn env(name: &str) -> Option<OsString> {
        std::env::var_os(name)
    }

    pub fn open_raw(alternate: bool) -> Result<crate::raw::Raw, u8> {
        crate::raw::Raw::open(stdin(), stdout(), alternate)
    }

    pub fn colors() -> i64 {
        let term = env("TERM").unwrap_or_default();
        let term = term.as_bytes();
        if !is_terminal(1) || env("NO_COLOR").is_some() || term == b"dumb" {
            return 0;
        }
        let truecolor = env("COLORTERM").unwrap_or_default();
        let truecolor = truecolor.as_bytes();
        if truecolor == b"truecolor" || truecolor == b"24bit" {
            16_777_216
        } else if term.windows(8).any(|w| w == b"256color") {
            256
        } else {
            16
        }
    }

    /// `(columns, rows)` of standard output, or `None` when it is not a sized terminal.
    pub fn size() -> Option<(i64, i64)> {
        let w = tcgetwinsize(stdout()).ok()?;
        Some((i64::from(w.ws_col), i64::from(w.ws_row)))
    }
}

#[cfg(not(unix))]
mod imp {
    pub fn is_terminal(_: i32) -> bool {
        false
    }

    pub fn colors() -> i64 {
        0
    }

    pub fn size() -> Option<(i64, i64)> {
        None
    }

    pub fn open_raw(alternate: bool) -> Result<crate::raw::Raw, u8> {
        crate::raw::Raw::open(0, 1, alternate)
    }
}

/// The event `next_event` last delivered.
static CURRENT: Global<RefCell<Option<decoder::Event>>> = Global::new(RefCell::new(None));

fn current<T>(read: impl FnOnce(&decoder::Event) -> T) -> Option<T> {
    CURRENT.get().borrow().as_ref().map(read)
}

fn key_flag(read: impl FnOnce(bool, bool, bool) -> bool) -> bool {
    current(|e| match e {
        decoder::Event::Key {
            ctrl, alt, shift, ..
        } => read(*ctrl, *alt, *shift),
        _ => false,
    })
    .unwrap_or(false)
}

fn raw_mode_capable() -> bool {
    cfg!(unix) && imp::is_terminal(0) && imp::is_terminal(1)
}

native! {
    /// The text of the last `FAILED` result.
    safe fn msstd_terminal_failure_message() -> *mut StrObj {
        ms_std_rt::failure_message()
    }

    safe fn msstd_terminal_capabilities_input_is_terminal() -> bool {
        imp::is_terminal(0)
    }

    safe fn msstd_terminal_capabilities_output_is_terminal() -> bool {
        imp::is_terminal(1)
    }

    safe fn msstd_terminal_capabilities_error_is_terminal() -> bool {
        imp::is_terminal(2)
    }

    safe fn msstd_terminal_capabilities_raw_mode() -> bool {
        raw_mode_capable()
    }

    safe fn msstd_terminal_capabilities_resize_events() -> bool {
        raw_mode_capable()
    }

    safe fn msstd_terminal_capabilities_colors() -> i64 {
        imp::colors()
    }

    safe fn msstd_terminal_size_status() -> u8 {
        if !imp::is_terminal(1) {
            STATUS_NOT_TERMINAL
        } else if imp::size().is_some() {
            STATUS_OK
        } else {
            STATUS_UNSUPPORTED
        }
    }

    safe fn msstd_terminal_size_columns() -> i64 {
        imp::size().map_or(0, |s| s.0)
    }

    safe fn msstd_terminal_size_rows() -> i64 {
        imp::size().map_or(0, |s| s.1)
    }

    fn msstd_terminal_raw_mode(
        alternate_screen: bool,
        out: Out<Object<raw::Raw>>,
    ) -> Result<(), StatusCode> {
        out.write(Object(imp::open_raw(alternate_screen).map_err(StatusCode)?));
        Ok(())
    }

    fn msstd_terminal_raw_terminal_close(h: ObjRef<raw::Raw>) -> () {
        h.close();
    }

    fn msstd_terminal_raw_terminal_size_status(h: ObjRef<raw::Raw>) -> u8 {
        poll_cancel();
        h.size().err().unwrap_or(STATUS_OK)
    }

    fn msstd_terminal_raw_terminal_size_columns(h: ObjRef<raw::Raw>) -> i64 {
        h.size().map_or(0, |s| s.0)
    }

    fn msstd_terminal_raw_terminal_size_rows(h: ObjRef<raw::Raw>) -> i64 {
        h.size().map_or(0, |s| s.1)
    }

    fn msstd_terminal_raw_terminal_move_cursor(h: ObjRef<raw::Raw>, row: i64, column: i64) -> u8 {
        poll_cancel();
        h.move_cursor(row, column)
    }

    fn msstd_terminal_raw_terminal_show_cursor(h: ObjRef<raw::Raw>, visible: bool) -> u8 {
        poll_cancel();
        h.show_cursor(visible)
    }

    fn msstd_terminal_raw_terminal_erase(h: ObjRef<raw::Raw>, region: i64) -> u8 {
        poll_cancel();
        h.erase(region)
    }

    fn msstd_terminal_raw_terminal_next_event(
        h: ObjRef<raw::Raw>,
        has_timeout: bool,
        timeout_ns: i64,
    ) -> u8 {
        poll_cancel();
        let timeout = has_timeout.then_some(timeout_ns.max(0));
        h.next_event(timeout, &mut CURRENT.get().borrow_mut())
    }

    /// The kind of the delivered event, as its `TerminalEvent` case index: text, key, resize.
    safe fn msstd_terminal_event_kind() -> i64 {
        current(|e| match e {
            decoder::Event::Text(_) => 0,
            decoder::Event::Key { .. } => 1,
            decoder::Event::Resize { .. } => 2,
        })
        .unwrap_or(0)
    }

    /// The text of a text event, or the key name of a key event.
    safe fn msstd_terminal_event_text() -> *mut StrObj {
        let text = current(|e| match e {
            decoder::Event::Text(t) => t.clone(),
            decoder::Event::Key { name, .. } => name.clone(),
            decoder::Event::Resize { .. } => alloc::vec::Vec::new(),
        });
        ms_std_rt::new_string(&text.unwrap_or_default())
    }

    safe fn msstd_terminal_event_ctrl() -> bool {
        key_flag(|ctrl, _, _| ctrl)
    }

    safe fn msstd_terminal_event_alt() -> bool {
        key_flag(|_, alt, _| alt)
    }

    safe fn msstd_terminal_event_shift() -> bool {
        key_flag(|_, _, shift| shift)
    }

    safe fn msstd_terminal_event_columns() -> i64 {
        current(|e| match e {
            decoder::Event::Resize { columns, .. } => *columns,
            _ => 0,
        })
        .unwrap_or(0)
    }

    safe fn msstd_terminal_event_rows() -> i64 {
        current(|e| match e {
            decoder::Event::Resize { rows, .. } => *rows,
            _ => 0,
        })
        .unwrap_or(0)
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
        let status = unsafe { msstd_terminal_raw_mode(0, &mut out) };
        assert_eq!(status, STATUS_NOT_TERMINAL);
        assert_eq!(msstd_terminal_capabilities_raw_mode(), 0);
    }
}
