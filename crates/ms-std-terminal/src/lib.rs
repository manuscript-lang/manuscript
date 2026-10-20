//! `@std/terminal` natives. Symbols are `msstd_terminal_<name>`.
//!
//! `capabilities()` and `size()` cross as one getter per record field (`size` also has a
//! `_status` call first). Raw mode is not implemented: on a terminal `raw_mode` answers
//! `Unsupported`, and with a redirected stream it answers `NotTerminal` like the Go runtime.
#![no_std]
// The exports below are the C ABI compiled code links against.
#![allow(unsafe_code)]
#![allow(clippy::missing_safety_doc)]

use ms_rt_abi::{STATUS_NOT_TERMINAL, STATUS_OK, STATUS_UNSUPPORTED, StrObj};

/// The text of the last `FAILED` result.
#[unsafe(no_mangle)]
pub extern "C" fn msstd_terminal_failure_message() -> *mut StrObj {
    ms_std_rt::failure_message()
}

#[cfg(unix)]
mod imp {
    use core::ffi::CStr;

    pub fn is_terminal(fd: i32) -> bool {
        // SAFETY: plain system call.
        unsafe { libc::isatty(fd) == 1 }
    }

    fn env(name: &CStr) -> Option<&'static [u8]> {
        // SAFETY: `getenv` answers a NUL-terminated string that stays valid until the
        // environment changes; callers only compare it at once.
        let p = unsafe { libc::getenv(name.as_ptr()) };
        // SAFETY: a non-null result is a NUL-terminated string.
        (!p.is_null()).then(|| unsafe { CStr::from_ptr(p) }.to_bytes())
    }

    pub fn colors() -> i64 {
        let term = env(c"TERM").unwrap_or_default();
        if !is_terminal(1) || env(c"NO_COLOR").is_some() || term == b"dumb" {
            return 0;
        }
        let truecolor = env(c"COLORTERM").unwrap_or_default();
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
        // SAFETY: `winsize` is plain data that the ioctl fills.
        let mut w: libc::winsize = unsafe { core::mem::zeroed() };
        // SAFETY: `w` is writable.
        let rc = unsafe { libc::ioctl(1, libc::TIOCGWINSZ, &mut w) };
        (rc == 0).then_some((i64::from(w.ws_col), i64::from(w.ws_row)))
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
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_terminal_capabilities_input_is_terminal() -> u8 {
    u8::from(imp::is_terminal(0))
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_terminal_capabilities_output_is_terminal() -> u8 {
    u8::from(imp::is_terminal(1))
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_terminal_capabilities_error_is_terminal() -> u8 {
    u8::from(imp::is_terminal(2))
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_terminal_capabilities_raw_mode() -> u8 {
    u8::from(cfg!(unix) && imp::is_terminal(0) && imp::is_terminal(1))
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_terminal_capabilities_resize_events() -> u8 {
    msstd_terminal_capabilities_raw_mode()
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_terminal_capabilities_colors() -> i64 {
    imp::colors()
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_terminal_size_status() -> u8 {
    if !imp::is_terminal(1) {
        STATUS_NOT_TERMINAL
    } else if imp::size().is_some() {
        STATUS_OK
    } else {
        STATUS_UNSUPPORTED
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_terminal_size_columns() -> i64 {
    imp::size().map_or(0, |s| s.0)
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_terminal_size_rows() -> i64 {
    imp::size().map_or(0, |s| s.1)
}

/// Raw mode is not implemented yet: redirected streams answer `NotTerminal`, terminals
/// `Unsupported`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_terminal_raw_mode(
    _alternate_screen: u8,
    out: *mut *mut ms_std_rt::Handle<()>,
) -> u8 {
    // No handle is ever written to `out`.
    let _ = out;
    if imp::is_terminal(0) && imp::is_terminal(1) {
        STATUS_UNSUPPORTED
    } else {
        STATUS_NOT_TERMINAL
    }
}

#[cfg(all(test, unix))]
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
