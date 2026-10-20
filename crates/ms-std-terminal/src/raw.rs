//! The raw terminal: termios raw input, cursor and screen control, and decoded input events.
//!
//! One raw terminal holds the host terminal at a time. Closing it (explicitly, by the scope that
//! acquired it, by dropping the last reference, or at process exit) shows the cursor, leaves the
//! alternate screen and restores the saved settings. Window changes are noticed by comparing the
//! size while waiting for input, so a `Resize` event can lag by up to one wait step.

use crate::decoder::{Decoder, Event};
use alloc::collections::VecDeque;
use alloc::vec::Vec;
use core::cell::{Cell, RefCell};
use ms_rt_abi::{
    STATUS_CLOSED, STATUS_FAILED, STATUS_INVALID_INPUT, STATUS_NONE, STATUS_NOT_TERMINAL, STATUS_OK,
};

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

pub struct Raw {
    input: i32,
    output: i32,
    saved: libc::termios,
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
struct Active(Cell<*const Raw>);

// SAFETY: the runtime runs Manuscript code on one thread.
unsafe impl Sync for Active {}

static ACTIVE: Active = Active(Cell::new(core::ptr::null()));

/// Whether the exit hook is registered.
struct Flag(Cell<bool>);

// SAFETY: the runtime runs Manuscript code on one thread.
unsafe impl Sync for Flag {}

static HOOKED: Flag = Flag(Cell::new(false));

extern "C" fn restore_at_exit() {
    let active = ACTIVE.0.get();
    if !active.is_null() {
        // SAFETY: the pointer is cleared before its terminal is freed.
        unsafe { (*active).close() };
    }
}

#[allow(clippy::useless_conversion)] // `time_t` is narrower than `i64` on 32-bit hosts
fn now_ns() -> i64 {
    // SAFETY: `timespec` is plain data that the call fills.
    let mut ts: libc::timespec = unsafe { core::mem::zeroed() };
    // SAFETY: `ts` is writable.
    unsafe { libc::clock_gettime(libc::CLOCK_MONOTONIC, &mut ts) };
    i64::from(ts.tv_sec) * 1_000_000_000 + i64::from(ts.tv_nsec)
}

/// `(columns, rows)` of the terminal open on `fd`.
pub fn tty_size(fd: i32) -> Option<(i64, i64)> {
    // SAFETY: `winsize` is plain data that the ioctl fills.
    let mut w: libc::winsize = unsafe { core::mem::zeroed() };
    // SAFETY: `w` is writable.
    let rc = unsafe { libc::ioctl(fd, libc::TIOCGWINSZ, &mut w) };
    (rc == 0).then_some((i64::from(w.ws_col), i64::from(w.ws_row)))
}

fn failed(text: &[u8]) -> u8 {
    ms_std_rt::record_failure(text.to_vec());
    STATUS_FAILED
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

/// Whether `fd` has input (or a hangup) ready now.
fn readable_now(fd: i32) -> bool {
    let mut p = libc::pollfd {
        fd,
        events: libc::POLLIN,
        revents: 0,
    };
    // SAFETY: `p` is one valid pollfd.
    unsafe { libc::poll(&mut p, 1, 0) > 0 }
}

/// Blocks the task until `fd` is readable or `timeout_ns` passes; a stop request unwinds.
fn wait_readable(fd: i32, timeout_ns: i64) -> bool {
    if readable_now(fd) {
        return true;
    }
    if timeout_ns <= 0 {
        return false;
    }
    #[cfg(not(test))]
    {
        // SAFETY: provided by `ms-rt`; parks the running task.
        let woke = unsafe { msrt_task_wait_fd(fd, WAIT_READ, timeout_ns.max(0)) };
        if woke & WAIT_CANCELLED != 0 {
            ms_std_rt::cancelled();
        }
        // Readable or hung up; a read then reports which.
        woke & 0b101 != 0
    }
    #[cfg(test)]
    {
        let mut p = libc::pollfd {
            fd,
            events: libc::POLLIN,
            revents: 0,
        };
        // SAFETY: `p` is one valid pollfd.
        let n = unsafe { libc::poll(&mut p, 1, (timeout_ns.max(0) / NS_PER_MS) as i32) };
        n > 0
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
    // SAFETY: plain system call.
    unsafe {
        libc::usleep((ns / 1000) as u32);
    }
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
        input: i32,
        output: i32,
        alternate: bool,
    ) -> Result<*mut ms_std_rt::Handle<Raw>, u8> {
        // SAFETY: plain system calls.
        let terminals = unsafe { libc::isatty(input) == 1 && libc::isatty(output) == 1 };
        if !terminals {
            return Err(STATUS_NOT_TERMINAL);
        }
        if !ACTIVE.0.get().is_null() {
            return Err(ms_rt_abi::STATUS_BUSY);
        }
        // SAFETY: `termios` is plain data that `tcgetattr` fills.
        let mut saved: libc::termios = unsafe { core::mem::zeroed() };
        // SAFETY: `saved` is writable.
        if unsafe { libc::tcgetattr(input, &mut saved) } != 0 {
            return Err(failed(b"cannot read terminal settings"));
        }
        let mut raw = saved;
        raw.c_iflag &= !(libc::IGNBRK
            | libc::BRKINT
            | libc::PARMRK
            | libc::ISTRIP
            | libc::INLCR
            | libc::IGNCR
            | libc::ICRNL
            | libc::IXON);
        raw.c_lflag &= !(libc::ECHO | libc::ECHONL | libc::ICANON | libc::ISIG | libc::IEXTEN);
        raw.c_cflag &= !(libc::CSIZE | libc::PARENB);
        raw.c_cflag |= libc::CS8;
        raw.c_cc[libc::VMIN] = 1;
        raw.c_cc[libc::VTIME] = 0;
        // SAFETY: `raw` is a valid settings block.
        if unsafe { libc::tcsetattr(input, libc::TCSANOW, &raw) } != 0 {
            return Err(failed(b"cannot enter raw mode"));
        }
        let terminal = Raw {
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
        let handle = ms_std_rt::new_handle(terminal);
        // SAFETY: `handle` was just allocated and is not shared yet.
        ACTIVE.0.set(unsafe { &(*handle).value });
        if !HOOKED.0.replace(true) {
            // SAFETY: provided by `ms-rt`.
            unsafe { msrt_process_on_exit(restore_at_exit) };
        }
        Ok(handle)
    }

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
        // SAFETY: `saved` came from `tcgetattr` on this descriptor.
        unsafe { libc::tcsetattr(self.input, libc::TCSANOW, &self.saved) };
        if core::ptr::eq(ACTIVE.0.get(), self) {
            ACTIVE.0.set(core::ptr::null());
        }
    }

    fn write(&self, bytes: &[u8]) -> Result<(), u8> {
        // Text the program printed earlier must reach the terminal before the control sequence.
        // SAFETY: provided by `ms-rt`.
        unsafe { msrt_io_flush() };
        let mut rest = bytes;
        while !rest.is_empty() {
            // SAFETY: `rest` is readable for its length.
            let n = unsafe { libc::write(self.output, rest.as_ptr().cast(), rest.len()) };
            if n < 0 {
                // SAFETY: reads this thread's errno.
                match unsafe { *errno() } {
                    libc::EINTR => continue,
                    libc::EAGAIN => {
                        pause(NS_PER_MS);
                        continue;
                    }
                    _ => return Err(failed(b"cannot write to the terminal")),
                }
            }
            rest = &rest[n as usize..];
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
        // SAFETY: `buf` is writable for its length.
        let n = unsafe { libc::read(self.input, buf.as_mut_ptr().cast(), buf.len()) };
        if n < 0 {
            // SAFETY: reads this thread's errno.
            return match unsafe { *errno() } {
                libc::EINTR | libc::EAGAIN => Ok(()),
                _ => Err(STATUS_CLOSED),
            };
        }
        if n == 0 {
            // Input ended: hangup.
            return Err(STATUS_CLOSED);
        }
        let events = self.decoder.borrow_mut().feed(&buf[..n as usize]);
        self.queue.borrow_mut().extend(events);
        Ok(())
    }
}

impl Drop for Raw {
    fn drop(&mut self) {
        self.close();
    }
}

fn errno() -> *mut i32 {
    // SAFETY: the libc accessor returns the calling thread's slot.
    #[cfg(any(target_os = "linux", target_os = "android"))]
    unsafe {
        libc::__errno_location()
    }
    // SAFETY: the libc accessor returns the calling thread's slot.
    #[cfg(not(any(target_os = "linux", target_os = "android")))]
    unsafe {
        libc::__error()
    }
}

#[cfg(test)]
#[path = "raw_tests.rs"]
mod tests;
