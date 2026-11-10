//! The Unix terminal: termios raw input over a pair of descriptors, polled for readiness.
#![allow(unsafe_code)] // the `ms-rt` task wait call below

use crate::{NS_PER_MS, pause};
use ms_rt::ffi::Failure;
use ms_rt::glue::pool::Cancelled;
use ms_rt_abi::STATUS_NOT_TERMINAL;
use rustix::event::{PollFd, PollFlags, poll};
use rustix::fd::BorrowedFd;
use rustix::io::{Errno, read, write};
use rustix::termios::{
    ControlModes, InputModes, LocalModes, OptionalActions, SpecialCodeIndex, Termios, isatty,
    tcgetattr, tcgetwinsize, tcsetattr,
};
use rustix::time::Timespec;
use std::ffi::OsString;
use std::os::unix::ffi::OsStrExt;

#[cfg(not(test))]
const WAIT_READ: u32 = 1;
#[cfg(not(test))]
const WAIT_CANCELLED: u32 = 16;

/// The terminal's descriptors and the settings to put back.
pub struct Term {
    input: BorrowedFd<'static>,
    output: BorrowedFd<'static>,
    saved: Termios,
}

fn env(name: &str) -> Option<OsString> {
    std::env::var_os(name)
}

/// Supported colors of standard output: 0, 16, 256 or 16777216.
pub fn colors() -> i64 {
    let term = env("TERM").unwrap_or_default();
    let term = term.as_bytes();
    if !crate::is_terminal(1) || env("NO_COLOR").is_some() || term == b"dumb" {
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

fn stdin_fd() -> BorrowedFd<'static> {
    // SAFETY: descriptor 0 stays open for the life of the process.
    unsafe { BorrowedFd::borrow_raw(0) }
}

fn stdout_fd() -> BorrowedFd<'static> {
    // SAFETY: descriptor 1 stays open for the life of the process.
    unsafe { BorrowedFd::borrow_raw(1) }
}

fn size_of(fd: BorrowedFd<'_>) -> Option<(i64, i64)> {
    let w = tcgetwinsize(fd).ok()?;
    Some((i64::from(w.ws_col), i64::from(w.ws_row)))
}

/// `(columns, rows)` of standard output, or `None` when it is not a sized terminal.
pub fn stdout_size() -> Option<(i64, i64)> {
    size_of(stdout_fd())
}

fn poll_readable(fd: BorrowedFd<'_>, timeout_ns: i64) -> bool {
    let timeout = Timespec {
        tv_sec: timeout_ns / 1_000_000_000,
        tv_nsec: (timeout_ns % 1_000_000_000) as _,
    };
    let mut fds = [PollFd::new(&fd, PollFlags::IN)];
    poll(&mut fds, Some(&timeout)).is_ok_and(|n| n > 0)
}

impl Term {
    /// The process's own terminal: standard input and output.
    pub fn open_standard() -> Result<Term, Failure> {
        Term::open(stdin_fd(), stdout_fd())
    }

    /// Puts `input` into raw mode; both descriptors must be terminals.
    pub fn open(input: BorrowedFd<'static>, output: BorrowedFd<'static>) -> Result<Term, Failure> {
        if !(isatty(input) && isatty(output)) {
            return Err(STATUS_NOT_TERMINAL.into());
        }
        let Ok(saved) = tcgetattr(input) else {
            return Err(Failure::failed("cannot read terminal settings"));
        };
        let mut raw = saved.clone();
        raw.input_modes.remove(
            InputModes::IGNBRK
                | InputModes::BRKINT
                | InputModes::PARMRK
                | InputModes::ISTRIP
                | InputModes::INLCR
                | InputModes::IGNCR
                | InputModes::ICRNL
                | InputModes::IXON,
        );
        raw.local_modes.remove(
            LocalModes::ECHO
                | LocalModes::ECHONL
                | LocalModes::ICANON
                | LocalModes::ISIG
                | LocalModes::IEXTEN,
        );
        raw.control_modes
            .remove(ControlModes::CSIZE | ControlModes::PARENB);
        raw.control_modes.insert(ControlModes::CS8);
        raw.special_codes[SpecialCodeIndex::VMIN] = 1;
        raw.special_codes[SpecialCodeIndex::VTIME] = 0;
        if tcsetattr(input, OptionalActions::Now, &raw).is_err() {
            return Err(Failure::failed("cannot enter raw mode"));
        }
        Ok(Term {
            input,
            output,
            saved,
        })
    }

    /// Puts the saved settings back; nothing to report if the terminal vanished already.
    pub fn restore(&self) {
        let _ = tcsetattr(self.input, OptionalActions::Now, &self.saved);
    }

    pub fn size(&self) -> Option<(i64, i64)> {
        size_of(self.output).or_else(|| size_of(self.input))
    }

    /// Blocks the task until input is ready or `timeout_ns` passes; `Err` when a stop request
    /// ends the wait, so the caller returns and drops what it holds.
    pub fn wait_readable(&self, timeout_ns: i64) -> Result<bool, Cancelled> {
        if poll_readable(self.input, 0) {
            return Ok(true);
        }
        if timeout_ns <= 0 {
            return Ok(false);
        }
        #[cfg(not(test))]
        {
            // SAFETY: provided by `ms-rt`; parks the running task.
            let woke = unsafe {
                ms_rt::task::msrt_task_wait_fd(
                    rustix::fd::AsRawFd::as_raw_fd(&self.input),
                    WAIT_READ,
                    timeout_ns.max(0),
                )
            };
            if woke & WAIT_CANCELLED != 0 {
                return Err(Cancelled);
            }
            // Readable or hung up; a read then reports which.
            Ok(woke & 0b101 != 0)
        }
        #[cfg(test)]
        Ok(poll_readable(self.input, timeout_ns))
    }

    /// Appends the ready input to `out`; `Err(())` once input ended or failed.
    pub fn read_ready(&self, out: &mut alloc::vec::Vec<u8>) -> Result<(), ()> {
        let mut buf = [0u8; 4096];
        match read(self.input, &mut buf[..]) {
            Ok(0) => Err(()),
            Ok(n) => {
                out.extend_from_slice(&buf[..n]);
                Ok(())
            }
            Err(Errno::INTR | Errno::AGAIN) => Ok(()),
            Err(_) => Err(()),
        }
    }

    pub fn write_all(&self, bytes: &[u8]) -> Result<(), Failure> {
        let mut rest = bytes;
        while !rest.is_empty() {
            match write(self.output, rest) {
                Ok(n) => rest = &rest[n..],
                Err(Errno::INTR) => {}
                Err(Errno::AGAIN) => {
                    if pause(NS_PER_MS).is_err() {
                        return Err(Failure::failed("cancelled"));
                    }
                }
                Err(_) => return Err(Failure::failed("cannot write to the terminal")),
            }
        }
        Ok(())
    }
}
