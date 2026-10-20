//! `@std/terminal` natives. Symbols are `msstd_terminal_<name>`.
//!
//! `capabilities()` and `size()` cross as one getter per record field (`size` also has a
//! `_status` call first). `raw_mode` returns a handle whose operations are the
//! `msstd_terminal_raw_terminal_*` exports; the event delivered by `next_event` is read back
//! through the `msstd_terminal_event_*` getters.
#![no_std]
// The exports below are the C ABI compiled code links against.
#![allow(unsafe_code)]
#![allow(clippy::missing_safety_doc)]

extern crate alloc;

mod decoder;
#[cfg(unix)]
mod raw;
#[cfg(not(unix))]
#[path = "raw_unsupported.rs"]
mod raw;

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

/// The raw terminal handle the lowered `RawTerminal` operations pass back.
pub type RawHandle = ms_std_rt::Handle<raw::Raw>;

/// Enters raw mode on standard input and output. Redirected streams answer `NotTerminal`,
/// another open raw terminal `Busy`, and hosts without termios `Unsupported`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_terminal_raw_mode(
    alternate_screen: u8,
    out: *mut *mut RawHandle,
) -> u8 {
    match raw::Raw::open(0, 1, alternate_screen != 0) {
        Ok(handle) => {
            // SAFETY: `out` is writable.
            unsafe { out.write(handle) };
            STATUS_OK
        }
        Err(status) => status,
    }
}

/// Restores the terminal; closing again does nothing.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_terminal_raw_terminal_close(h: *mut RawHandle) {
    // SAFETY: `h` is a live raw terminal handle.
    unsafe { (*h).value.close() };
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_terminal_raw_terminal_size_status(h: *mut RawHandle) -> u8 {
    ms_std_rt::poll_cancel();
    // SAFETY: `h` is a live raw terminal handle.
    unsafe { (*h).value.size() }.err().unwrap_or(STATUS_OK)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_terminal_raw_terminal_size_columns(h: *mut RawHandle) -> i64 {
    // SAFETY: `h` is a live raw terminal handle.
    unsafe { (*h).value.size() }.map_or(0, |s| s.0)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_terminal_raw_terminal_size_rows(h: *mut RawHandle) -> i64 {
    // SAFETY: `h` is a live raw terminal handle.
    unsafe { (*h).value.size() }.map_or(0, |s| s.1)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_terminal_raw_terminal_move_cursor(
    h: *mut RawHandle,
    row: i64,
    column: i64,
) -> u8 {
    ms_std_rt::poll_cancel();
    // SAFETY: `h` is a live raw terminal handle.
    unsafe { (*h).value.move_cursor(row, column) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_terminal_raw_terminal_show_cursor(
    h: *mut RawHandle,
    visible: u8,
) -> u8 {
    ms_std_rt::poll_cancel();
    // SAFETY: `h` is a live raw terminal handle.
    unsafe { (*h).value.show_cursor(visible != 0) }
}

/// `region` is the `EraseRegion` case index: screen, line, line end, line start.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_terminal_raw_terminal_erase(h: *mut RawHandle, region: i64) -> u8 {
    ms_std_rt::poll_cancel();
    // SAFETY: `h` is a live raw terminal handle.
    unsafe { (*h).value.erase(region) }
}

/// Waits for the next event (a negative timeout polls). `STATUS_OK` leaves the event for the
/// `msstd_terminal_event_*` getters; `STATUS_NONE` means the timeout elapsed first.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msstd_terminal_raw_terminal_next_event(
    h: *mut RawHandle,
    has_timeout: u8,
    timeout_ns: i64,
) -> u8 {
    ms_std_rt::poll_cancel();
    let timeout = (has_timeout != 0).then_some(timeout_ns.max(0));
    // SAFETY: `h` is a live raw terminal handle and the runtime is single-threaded.
    unsafe { (*h).value.next_event(timeout, &mut *CURRENT.0.get()) }
}

/// The event `next_event` last delivered.
struct Current(core::cell::UnsafeCell<Option<decoder::Event>>);

// SAFETY: the runtime runs Manuscript code on one thread.
unsafe impl Sync for Current {}

static CURRENT: Current = Current(core::cell::UnsafeCell::new(None));

fn current<T>(read: impl FnOnce(&decoder::Event) -> T) -> Option<T> {
    // SAFETY: single-threaded; the reference does not outlive the call.
    unsafe { (*CURRENT.0.get()).as_ref() }.map(read)
}

/// The kind of the delivered event, as its `TerminalEvent` case index: text, key, resize.
#[unsafe(no_mangle)]
pub extern "C" fn msstd_terminal_event_kind() -> i64 {
    current(|e| match e {
        decoder::Event::Text(_) => 0,
        decoder::Event::Key { .. } => 1,
        decoder::Event::Resize { .. } => 2,
    })
    .unwrap_or(0)
}

/// The typed text, or the key name.
#[unsafe(no_mangle)]
pub extern "C" fn msstd_terminal_event_text() -> *mut StrObj {
    let text = current(|e| match e {
        decoder::Event::Text(t) => t.clone(),
        decoder::Event::Key { name, .. } => name.clone(),
        decoder::Event::Resize { .. } => alloc::vec::Vec::new(),
    });
    ms_std_rt::new_string(&text.unwrap_or_default())
}

fn key_flag(read: impl FnOnce(bool, bool, bool) -> bool) -> u8 {
    let flag = current(|e| match e {
        decoder::Event::Key {
            ctrl, alt, shift, ..
        } => read(*ctrl, *alt, *shift),
        _ => false,
    });
    u8::from(flag.unwrap_or(false))
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_terminal_event_ctrl() -> u8 {
    key_flag(|ctrl, _, _| ctrl)
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_terminal_event_alt() -> u8 {
    key_flag(|_, alt, _| alt)
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_terminal_event_shift() -> u8 {
    key_flag(|_, _, shift| shift)
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_terminal_event_columns() -> i64 {
    current(|e| match e {
        decoder::Event::Resize { columns, .. } => *columns,
        _ => 0,
    })
    .unwrap_or(0)
}

#[unsafe(no_mangle)]
pub extern "C" fn msstd_terminal_event_rows() -> i64 {
    current(|e| match e {
        decoder::Event::Resize { rows, .. } => *rows,
        _ => 0,
    })
    .unwrap_or(0)
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
