//! The raw terminal: raw input mode, UTF-8 text reads, writes and size.
//!
//! One raw terminal holds the host terminal at a time. Closing it (explicitly, by the scope that
//! acquired it, by dropping the last reference, or at process exit) writes the restore text the
//! program registered (leaving the alternate screen, showing the cursor, and so on) and puts the
//! saved settings back. Decoding keys and pastes from the text, resize detection and every
//! escape sequence live in `@std/cli/terminal.ms`.

use crate::NS_PER_MS;
use crate::sys::Term;
use alloc::rc::{Rc, Weak};
use alloc::string::String;
use alloc::vec::Vec;
use core::cell::{Cell, RefCell};
use core::ops::Deref;
use ms_rt::ffi::Failure;
use ms_rt::ffi::Global;
use ms_rt_abi::{STATUS_CLOSED, STATUS_FAILED, STATUS_NONE, STATUS_NOT_TERMINAL, STATUS_OK};

use ms_rt::io::msrt_io_flush;
use ms_rt::process::msrt_process_on_exit;

/// The wait for input before the caller compares the window size.
const SLICE_NS: i64 = 50 * NS_PER_MS;
/// How long a lone escape byte waits for the rest of its sequence.
const QUICK_NS: i64 = 40 * NS_PER_MS;

pub struct State {
    term: Term,
    /// Written, then the settings restored, when the terminal closes.
    restore: RefCell<Vec<u8>>,
    closed: Cell<bool>,
    /// Bytes of an incomplete UTF-8 scalar read so far.
    carry: RefCell<Vec<u8>>,
}

/// The raw terminal currently holding the host terminal.
static ACTIVE: Global<RefCell<Weak<State>>> = Global::new(RefCell::new(Weak::new()));

/// Whether the exit hook is registered.
static HOOKED: Global<Cell<bool>> = Global::new(Cell::new(false));

extern "C" fn restore_at_exit() {
    let active = ACTIVE.get().borrow().upgrade();
    if let Some(active) = active {
        active.close();
    }
}

/// A raw terminal; dropping the last reference restores the host terminal.
pub struct Raw(Rc<State>);

impl Deref for Raw {
    type Target = State;
    fn deref(&self) -> &State {
        &self.0
    }
}

impl Drop for Raw {
    fn drop(&mut self) {
        self.0.close();
    }
}

impl Raw {
    /// Puts the process's terminal into raw mode. `Err` with `STATUS_BUSY` while another raw
    /// terminal is open.
    pub fn open() -> Result<Raw, Failure> {
        if !(crate::is_terminal(0) && crate::is_terminal(1)) {
            return Err(STATUS_NOT_TERMINAL.into());
        }
        Raw::attach(Term::open_standard)
    }

    /// Like `open`, with the terminal supplied by `make`.
    pub fn attach(make: impl FnOnce() -> Result<Term, Failure>) -> Result<Raw, Failure> {
        if ACTIVE.get().borrow().upgrade().is_some() {
            return Err(ms_rt_abi::STATUS_BUSY.into());
        }
        let terminal = Rc::new(State {
            term: make()?,
            restore: RefCell::new(Vec::new()),
            closed: Cell::new(false),
            carry: RefCell::new(Vec::new()),
        });
        *ACTIVE.get().borrow_mut() = Rc::downgrade(&terminal);
        if !HOOKED.get().replace(true) {
            msrt_process_on_exit(restore_at_exit);
        }
        Ok(Raw(terminal))
    }
}

impl State {
    pub fn is_closed(&self) -> bool {
        self.closed.get()
    }

    /// Writes the restore text and the saved settings; closing again does nothing.
    pub fn close(&self) {
        if self.closed.replace(true) {
            return;
        }
        // Nothing useful to report if the terminal vanished already.
        let _ = self.write(&self.restore.borrow());
        self.term.restore();
        let mut active = ACTIVE.get().borrow_mut();
        if core::ptr::eq(active.as_ptr(), self) {
            *active = Weak::new();
        }
    }

    fn write(&self, bytes: &[u8]) -> Result<(), Failure> {
        // Text the program printed earlier must reach the terminal before the control sequence.
        msrt_io_flush();
        self.term.write_all(bytes)
    }

    /// Writes text or control sequences to the terminal; fails on a closed terminal.
    pub fn command(&self, bytes: &[u8]) -> Result<(), Failure> {
        if self.closed.get() {
            return Err(STATUS_CLOSED.into());
        }
        self.write(bytes)
    }

    /// Sets the text written when the terminal closes.
    pub fn set_restore(&self, bytes: &[u8]) {
        *self.restore.borrow_mut() = bytes.to_vec();
    }

    pub fn size(&self) -> Result<(i64, i64), u8> {
        if self.closed.get() {
            return Err(STATUS_CLOSED);
        }
        self.term.size().ok_or(STATUS_NOT_TERMINAL)
    }

    /// Waits for input, for 40 ms when `quick` and 50 ms otherwise, then stores its complete
    /// UTF-8 scalars in `text`: `STATUS_OK`, `STATUS_NONE` when nothing came, `STATUS_CLOSED` once
    /// closed or when input ended. The short wait lets the caller compare the window size and
    /// resolve a lone escape byte into the Escape key.
    pub fn read(&self, quick: bool, text: &mut String) -> u8 {
        if ms_rt::glue::cancel_pending() {
            return STATUS_FAILED;
        }
        if self.closed.get() {
            return STATUS_CLOSED;
        }
        let Ok(ready) = self
            .term
            .wait_readable(if quick { QUICK_NS } else { SLICE_NS })
        else {
            return STATUS_FAILED;
        };
        if !ready {
            return STATUS_NONE;
        }
        let mut bytes = Vec::new();
        if self.term.read_ready(&mut bytes).is_err() {
            return STATUS_CLOSED;
        }
        self.decode(bytes, text);
        if text.is_empty() {
            STATUS_NONE
        } else {
            STATUS_OK
        }
    }

    /// Appends the complete scalars of `carry + bytes` to `text`, replacing invalid bytes with
    /// U+FFFD and keeping an incomplete trailing scalar for the next read.
    fn decode(&self, bytes: Vec<u8>, text: &mut String) {
        let mut carry = self.carry.borrow_mut();
        carry.extend_from_slice(&bytes);
        let mut rest = carry.as_slice();
        loop {
            match core::str::from_utf8(rest) {
                Ok(valid) => {
                    text.push_str(valid);
                    rest = &[];
                    break;
                }
                Err(e) => {
                    let (valid, after) = rest.split_at(e.valid_up_to());
                    text.push_str(core::str::from_utf8(valid).unwrap_or_default());
                    match e.error_len() {
                        Some(n) => {
                            text.push('\u{fffd}');
                            rest = &after[n..];
                        }
                        None => {
                            rest = after;
                            break;
                        }
                    }
                }
            }
        }
        let kept = rest.to_vec();
        *carry = kept;
    }
}

#[cfg(all(test, unix))]
#[path = "raw_tests.rs"]
mod tests;
