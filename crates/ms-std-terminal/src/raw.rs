//! The raw terminal: termios raw input, cursor and screen control, and decoded input events.
//!
//! One raw terminal holds the host terminal at a time. Closing it (explicitly, by the scope that
//! acquired it, by dropping the last reference, or at process exit) shows the cursor, leaves the
//! alternate screen and restores the saved settings. Window changes are noticed by comparing the
//! size while waiting for input, so a `Resize` event can lag by up to one wait step.
#![allow(unsafe_code)] // the `ms-rt` task and exit-hook calls below

use crate::decoder::{Decoder, Event};
use alloc::collections::VecDeque;
use alloc::rc::{Rc, Weak};
use alloc::vec::Vec;
use core::cell::{Cell, RefCell};
use core::ops::Deref;
use ms_rt_abi::{STATUS_CLOSED, STATUS_INVALID_INPUT, STATUS_NONE, STATUS_NOT_TERMINAL, STATUS_OK};
use ms_std_core::Global;
use rustix::event::{PollFd, PollFlags, poll};
use rustix::fd::BorrowedFd;
use rustix::io::{Errno, read, write};
use rustix::termios::{
    ControlModes, InputModes, LocalModes, OptionalActions, SpecialCodeIndex, Termios, isatty,
    tcgetattr, tcgetwinsize, tcsetattr,
};
use rustix::time::{ClockId, Timespec, clock_gettime};

unsafe extern "C-unwind" {
    fn msrt_io_flush();
    #[cfg(not(test))]
    fn msrt_task_wait_fd(fd: i32, events: u32, timeout_ns: i64) -> u32;
    fn msrt_process_on_exit(hook: extern "C" fn());
}

#[cfg(not(test))]
const WAIT_READ: u32 = 1;
#[cfg(not(test))]
const WAIT_CANCELLED: u32 = 16;

const NS_PER_MS: i64 = 1_000_000;
/// The longest wait before the window size is compared again.
const TICK_NS: i64 = 50 * NS_PER_MS;
/// How long a lone escape byte waits for the rest of its sequence.
const ESCAPE_NS: i64 = 40 * NS_PER_MS;
/// Cursor positions beyond this are refused, as the escape sequences cannot carry them.
const MAX_POSITION: i64 = 65534;

pub struct State {
    input: BorrowedFd<'static>,
    output: BorrowedFd<'static>,
    saved: Termios,
    alternate: bool,
    hidden: Cell<bool>,
    closed: Cell<bool>,
    /// A task is inside `next_event`; others wait their turn.
    reading: Cell<bool>,
    decoder: RefCell<Decoder>,
    queue: RefCell<VecDeque<Event>>,
    size: Cell<Option<(i64, i64)>>,
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

fn now_ns() -> i64 {
    let ts = clock_gettime(ClockId::Monotonic);
    ts.tv_sec
        .saturating_mul(1_000_000_000)
        .saturating_add(ts.tv_nsec as i64)
}

/// `(columns, rows)` of the terminal open on `fd`.
pub fn tty_size(fd: BorrowedFd<'_>) -> Option<(i64, i64)> {
    let w = tcgetwinsize(fd).ok()?;
    Some((i64::from(w.ws_col), i64::from(w.ws_row)))
}

fn number(out: &mut Vec<u8>, n: i64) {
    let mut digits = [0u8; 20];
    let (mut at, mut n) = (digits.len(), n.max(0) as u64);
    loop {
        at -= 1;
        digits[at] = b'0' + (n % 10) as u8;
        n /= 10;
        if n == 0 {
            break;
        }
    }
    out.extend_from_slice(&digits[at..]);
}

/// Polls `fd` for input for up to `timeout_ns`; a hangup counts as ready.
fn poll_readable(fd: BorrowedFd<'_>, timeout_ns: i64) -> bool {
    let timeout = Timespec {
        tv_sec: timeout_ns / 1_000_000_000,
        tv_nsec: (timeout_ns % 1_000_000_000) as _,
    };
    let mut fds = [PollFd::new(&fd, PollFlags::IN)];
    poll(&mut fds, Some(&timeout)).is_ok_and(|n| n > 0)
}

/// Whether `fd` has input (or a hangup) ready now.
fn readable_now(fd: BorrowedFd<'_>) -> bool {
    poll_readable(fd, 0)
}

/// Blocks the task until `fd` is readable or `timeout_ns` passes; a stop request unwinds.
fn wait_readable(fd: BorrowedFd<'_>, timeout_ns: i64) -> bool {
    if readable_now(fd) {
        return true;
    }
    if timeout_ns <= 0 {
        return false;
    }
    #[cfg(not(test))]
    {
        // SAFETY: provided by `ms-rt`; parks the running task.
        let woke = unsafe {
            msrt_task_wait_fd(
                rustix::fd::AsRawFd::as_raw_fd(&fd),
                WAIT_READ,
                timeout_ns.max(0),
            )
        };
        if woke & WAIT_CANCELLED != 0 {
            ms_std_rt::cancelled();
        }
        // Readable or hung up; a read then reports which.
        woke & 0b101 != 0
    }
    #[cfg(test)]
    {
        poll_readable(fd, timeout_ns)
    }
}

/// Sleeps the task for `ns` so another task's read can finish.
fn pause(ns: i64) {
    #[cfg(not(test))]
    {
        unsafe extern "C-unwind" {
            fn msrt_task_sleep(ns: i64) -> u32;
        }
        // SAFETY: provided by `ms-rt`.
        if unsafe { msrt_task_sleep(ns) } & WAIT_CANCELLED != 0 {
            ms_std_rt::cancelled();
        }
    }
    #[cfg(test)]
    std::thread::sleep(core::time::Duration::from_nanos(ns.max(0) as u64));
}

/// Clears the reading flag when `next_event` leaves, by any path.
struct Reading<'a>(&'a Cell<bool>);

impl Drop for Reading<'_> {
    fn drop(&mut self) {
        self.0.set(false);
    }
}

impl Raw {
    /// Puts `input` into raw mode and (optionally) switches `output` to the alternate screen.
    pub fn open(
        input: BorrowedFd<'static>,
        output: BorrowedFd<'static>,
        alternate: bool,
    ) -> Result<Raw, u8> {
        if !(isatty(input) && isatty(output)) {
            return Err(STATUS_NOT_TERMINAL);
        }
        if ACTIVE.get().borrow().upgrade().is_some() {
            return Err(ms_rt_abi::STATUS_BUSY);
        }
        let Ok(saved) = tcgetattr(input) else {
            return Err(ms_std_rt::failed(b"cannot read terminal settings"));
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
            return Err(ms_std_rt::failed(b"cannot enter raw mode"));
        }
        let terminal = State {
            input,
            output,
            saved,
            alternate,
            hidden: Cell::new(false),
            closed: Cell::new(false),
            reading: Cell::new(false),
            decoder: RefCell::new(Decoder::default()),
            queue: RefCell::new(VecDeque::new()),
            size: Cell::new(tty_size(output).or_else(|| tty_size(input))),
        };
        if alternate {
            // Nothing useful to report if the terminal vanished already; reads will say so.
            let _ = terminal.write(b"\x1b[?1049h");
        }
        let terminal = Rc::new(terminal);
        *ACTIVE.get().borrow_mut() = Rc::downgrade(&terminal);
        if !HOOKED.get().replace(true) {
            // SAFETY: provided by `ms-rt`.
            unsafe { msrt_process_on_exit(restore_at_exit) };
        }
        Ok(Raw(terminal))
    }
}

impl State {
    pub fn is_closed(&self) -> bool {
        self.closed.get()
    }

    /// Restores the terminal; closing again does nothing.
    pub fn close(&self) {
        if self.closed.replace(true) {
            return;
        }
        if self.hidden.get() {
            let _ = self.write(b"\x1b[?25h");
        }
        if self.alternate {
            let _ = self.write(b"\x1b[?1049l");
        }
        // Nothing to report if the terminal vanished already.
        let _ = tcsetattr(self.input, OptionalActions::Now, &self.saved);
        let mut active = ACTIVE.get().borrow_mut();
        if core::ptr::eq(active.as_ptr(), self) {
            *active = Weak::new();
        }
    }

    fn write(&self, bytes: &[u8]) -> Result<(), u8> {
        // Text the program printed earlier must reach the terminal before the control sequence.
        // SAFETY: provided by `ms-rt`.
        unsafe { msrt_io_flush() };
        let mut rest = bytes;
        while !rest.is_empty() {
            match write(self.output, rest) {
                Ok(n) => rest = &rest[n..],
                Err(Errno::INTR) => {}
                Err(Errno::AGAIN) => pause(NS_PER_MS),
                Err(_) => return Err(ms_std_rt::failed(b"cannot write to the terminal")),
            }
        }
        Ok(())
    }

    /// Writes a control sequence for an operation that fails on a closed terminal.
    fn command(&self, bytes: &[u8]) -> u8 {
        if self.closed.get() {
            return STATUS_CLOSED;
        }
        self.write(bytes).err().unwrap_or(STATUS_OK)
    }

    pub fn size(&self) -> Result<(i64, i64), u8> {
        if self.closed.get() {
            return Err(STATUS_CLOSED);
        }
        tty_size(self.output)
            .or_else(|| tty_size(self.input))
            .ok_or(STATUS_NOT_TERMINAL)
    }

    pub fn move_cursor(&self, row: i64, column: i64) -> u8 {
        if self.closed.get() {
            return STATUS_CLOSED;
        }
        if !(0..=MAX_POSITION).contains(&row) || !(0..=MAX_POSITION).contains(&column) {
            return STATUS_INVALID_INPUT;
        }
        let mut seq = b"\x1b[".to_vec();
        number(&mut seq, row + 1);
        seq.push(b';');
        number(&mut seq, column + 1);
        seq.push(b'H');
        self.command(&seq)
    }

    pub fn show_cursor(&self, visible: bool) -> u8 {
        if self.closed.get() {
            return STATUS_CLOSED;
        }
        self.hidden.set(!visible);
        self.command(if visible { b"\x1b[?25h" } else { b"\x1b[?25l" })
    }

    /// `region` is the `EraseRegion` case index: screen, line, line end, line start.
    pub fn erase(&self, region: i64) -> u8 {
        self.command(match region {
            0 => b"\x1b[2J",
            1 => b"\x1b[2K",
            2 => b"\x1b[K",
            _ => b"\x1b[1K",
        })
    }

    /// Waits for the next event: `STATUS_OK` with the event in `current`, `STATUS_NONE` when
    /// `timeout_ns` elapsed first, `STATUS_CLOSED` once closed or when input ended.
    pub fn next_event(&self, timeout_ns: Option<i64>, current: &mut Option<Event>) -> u8 {
        let deadline = timeout_ns.map(|t| now_ns().saturating_add(t));
        let remaining = || deadline.map(|d| d - now_ns());
        // Concurrent callers are served one at a time.
        while self.reading.get() {
            if self.closed.get() {
                return STATUS_CLOSED;
            }
            if remaining().is_some_and(|r| r <= 0) {
                return STATUS_NONE;
            }
            pause(NS_PER_MS);
        }
        self.reading.set(true);
        let _reading = Reading(&self.reading);
        loop {
            ms_std_rt::poll_cancel();
            if self.closed.get() {
                return STATUS_CLOSED;
            }
            if let Some(event) = self.queue.borrow_mut().pop_front() {
                *current = Some(event);
                return STATUS_OK;
            }
            let size = tty_size(self.output).or_else(|| tty_size(self.input));
            if size.is_some() && size != self.size.get() {
                self.size.set(size);
                if let Some((columns, rows)) = size {
                    *current = Some(Event::Resize { columns, rows });
                    return STATUS_OK;
                }
            }
            let partial = self.decoder.borrow().pending();
            let natural = if partial { ESCAPE_NS } else { TICK_NS };
            let step = remaining().map_or(natural, |r| natural.min(r.max(0)));
            if wait_readable(self.input, step) {
                match self.fill() {
                    Ok(()) => continue,
                    Err(status) => return status,
                }
            }
            // A full quiet pause resolves a lone escape into the Escape key.
            if partial && step == natural {
                let events = self.decoder.borrow_mut().flush();
                self.queue.borrow_mut().extend(events);
            }
            if self.queue.borrow().is_empty() && remaining().is_some_and(|r| r <= 0) {
                return STATUS_NONE;
            }
        }
    }

    /// Reads what the terminal has ready into the event queue.
    fn fill(&self) -> Result<(), u8> {
        let mut buf = [0u8; 4096];
        match read(self.input, &mut buf[..]) {
            Ok(0) => Err(STATUS_CLOSED), // input ended: hangup
            Ok(n) => {
                let events = self.decoder.borrow_mut().feed(&buf[..n]);
                self.queue.borrow_mut().extend(events);
                Ok(())
            }
            Err(Errno::INTR | Errno::AGAIN) => Ok(()),
            Err(_) => Err(STATUS_CLOSED),
        }
    }
}

#[cfg(test)]
#[path = "raw_tests.rs"]
mod tests;
