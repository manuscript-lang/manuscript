//! The Windows console: virtual-terminal input and output modes over the standard handles.
//!
//! Input is read as console input records, never with a blocking `ReadFile`, because a resize or
//! focus record would leave a byte read waiting. With virtual-terminal input on, each key record
//! carries one character of the escape sequence the shared decoder understands.
#![allow(unsafe_code)] // the Win32 console calls below

use crate::NS_PER_MS;
use alloc::vec::Vec;
use core::sync::atomic::{AtomicUsize, Ordering};
use ms_rt::ffi::Failure;
use ms_rt::glue::pool::Cancelled;
use ms_rt::glue::pool::Lane;
use ms_rt_abi::STATUS_NOT_TERMINAL;
use std::ffi::OsString;
use windows_sys::Win32::Foundation::{HANDLE, INVALID_HANDLE_VALUE};
use windows_sys::Win32::Storage::FileSystem::WriteFile;
use windows_sys::Win32::System::Console::{
    CONSOLE_MODE, CONSOLE_SCREEN_BUFFER_INFO, ENABLE_ECHO_INPUT, ENABLE_LINE_INPUT,
    ENABLE_PROCESSED_INPUT, ENABLE_PROCESSED_OUTPUT, ENABLE_VIRTUAL_TERMINAL_INPUT,
    ENABLE_VIRTUAL_TERMINAL_PROCESSING, ENABLE_WINDOW_INPUT, GetConsoleCP, GetConsoleMode,
    GetConsoleOutputCP, GetConsoleScreenBufferInfo, GetNumberOfConsoleInputEvents, GetStdHandle,
    INPUT_RECORD, KEY_EVENT, ReadConsoleInputW, STD_INPUT_HANDLE, STD_OUTPUT_HANDLE, SetConsoleCP,
    SetConsoleMode, SetConsoleOutputCP,
};
use windows_sys::Win32::System::Threading::{
    CreateEventW, INFINITE, SetEvent, WaitForMultipleObjects,
};

const UTF8: u32 = 65001;

/// An event that ends a wait for input: set when the terminal closes or a wait is abandoned.
/// One event serves the process for good, since an abandoned wait may still hold it.
static WAKE: AtomicUsize = AtomicUsize::new(0);

fn wake_event() -> Result<HANDLE, Failure> {
    if WAKE.load(Ordering::Acquire) == 0 {
        // SAFETY: an unnamed auto-reset event, initially clear.
        let event = unsafe { CreateEventW(core::ptr::null(), 0, 0, core::ptr::null()) };
        if event.is_null() {
            return Err(Failure::failed("cannot make the terminal wake event"));
        }
        // The runtime thread opens terminals one at a time, so no other thread races this store.
        WAKE.store(event as usize, Ordering::Release);
    }
    Ok(WAKE.load(Ordering::Acquire) as HANDLE)
}

fn wake() {
    let event = WAKE.load(Ordering::Acquire);
    if event != 0 {
        // SAFETY: the event is never closed.
        unsafe { SetEvent(event as HANDLE) };
    }
}

/// Blocks until the console input is signalled (a key, a resize or another record), the wake
/// event is set, or `ms` passes (`INFINITE` for no limit). Runs on a pool thread.
fn wait_input_or_wake(job: &(usize, usize, u32)) {
    let handles = [job.0 as HANDLE, job.1 as HANDLE];
    // SAFETY: both handles outlive every wait: standard input, and the never-closed wake event.
    unsafe { WaitForMultipleObjects(2, handles.as_ptr(), 0, job.2) };
}

/// The console handles and the settings to put back.
pub struct Term {
    input: HANDLE,
    output: HANDLE,
    input_mode: CONSOLE_MODE,
    output_mode: CONSOLE_MODE,
    input_cp: u32,
    output_cp: u32,
    wake: HANDLE,
    /// A high surrogate waiting for its low half.
    high: core::cell::Cell<Option<u16>>,
}

fn env(name: &str) -> Option<OsString> {
    std::env::var_os(name)
}

/// Supported colors of standard output: 0, 16, 256 or 16777216. Windows 10 consoles take
/// 24-bit color through virtual-terminal sequences.
pub fn colors() -> i64 {
    if !crate::is_terminal(1)
        || env("NO_COLOR").is_some()
        || env("TERM").is_some_and(|t| t == "dumb")
    {
        return 0;
    }
    if env("COLORTERM").is_none()
        && env("TERM").is_some_and(|t| t.to_string_lossy().contains("256color"))
    {
        256
    } else {
        16_777_216
    }
}

fn size_of(handle: HANDLE) -> Option<(i64, i64)> {
    // SAFETY: an all-zero info record is valid and the call fills it in.
    let mut info: CONSOLE_SCREEN_BUFFER_INFO = unsafe { core::mem::zeroed() };
    // SAFETY: `info` is a valid out record.
    if unsafe { GetConsoleScreenBufferInfo(handle, &mut info) } == 0 {
        return None;
    }
    let w = info.srWindow;
    Some((
        i64::from(w.Right) - i64::from(w.Left) + 1,
        i64::from(w.Bottom) - i64::from(w.Top) + 1,
    ))
}

fn std_handle(which: u32) -> Option<HANDLE> {
    // SAFETY: plain query of a standard handle.
    let h = unsafe { GetStdHandle(which) };
    (h != INVALID_HANDLE_VALUE && !h.is_null()).then_some(h)
}

/// `(columns, rows)` of standard output, or `None` when it is not a console.
pub fn stdout_size() -> Option<(i64, i64)> {
    size_of(std_handle(STD_OUTPUT_HANDLE)?)
}

fn mode_of(handle: HANDLE) -> Option<CONSOLE_MODE> {
    let mut mode = 0;
    // SAFETY: `mode` is a valid out value.
    (unsafe { GetConsoleMode(handle, &mut mode) } != 0).then_some(mode)
}

impl Term {
    /// The process's own console: standard input and output.
    pub fn open_standard() -> Result<Term, Failure> {
        let (Some(input), Some(output)) =
            (std_handle(STD_INPUT_HANDLE), std_handle(STD_OUTPUT_HANDLE))
        else {
            return Err(STATUS_NOT_TERMINAL.into());
        };
        let (Some(input_mode), Some(output_mode)) = (mode_of(input), mode_of(output)) else {
            return Err(STATUS_NOT_TERMINAL.into());
        };
        // SAFETY: plain queries and settings of the console code pages and modes.
        let (input_cp, output_cp) = unsafe { (GetConsoleCP(), GetConsoleOutputCP()) };
        let term = Term {
            input,
            output,
            input_mode,
            output_mode,
            input_cp,
            output_cp,
            wake: wake_event()?,
            high: core::cell::Cell::new(None),
        };
        let raw_input = (input_mode
            & !(ENABLE_ECHO_INPUT | ENABLE_LINE_INPUT | ENABLE_PROCESSED_INPUT))
            | ENABLE_VIRTUAL_TERMINAL_INPUT
            | ENABLE_WINDOW_INPUT;
        let vt_output = output_mode | ENABLE_PROCESSED_OUTPUT | ENABLE_VIRTUAL_TERMINAL_PROCESSING;
        // SAFETY: settings of handles this process owns.
        let ok = unsafe {
            SetConsoleMode(output, vt_output) != 0 && SetConsoleMode(input, raw_input) != 0
        };
        if !ok {
            term.restore();
            return Err(Failure::failed("cannot enter raw mode"));
        }
        // SAFETY: as above; the code pages are restored with the modes.
        unsafe {
            SetConsoleCP(UTF8);
            SetConsoleOutputCP(UTF8);
        }
        Ok(term)
    }

    /// Puts the saved modes and code pages back.
    pub fn restore(&self) {
        // SAFETY: settings of handles this process owns; failures leave nothing to report.
        unsafe {
            SetConsoleMode(self.input, self.input_mode);
            SetConsoleMode(self.output, self.output_mode);
            SetConsoleCP(self.input_cp);
            SetConsoleOutputCP(self.output_cp);
        }
        // A task waiting for input sees the terminal closed.
        wake();
    }

    pub fn size(&self) -> Option<(i64, i64)> {
        size_of(self.output)
    }

    fn pending_records(&self) -> u32 {
        let mut n = 0;
        // SAFETY: `n` is a valid out value.
        if unsafe { GetNumberOfConsoleInputEvents(self.input, &mut n) } == 0 {
            return 0;
        }
        n
    }

    /// Blocks the task until input records are ready. `timeout_ns` is a protocol delay (the wait
    /// for the rest of an escape sequence); `None` waits for a record (a key or a resize) or a
    /// wake with no limit. `Ok(false)` on the timeout or a wake.
    pub fn wait_readable(&self, timeout_ns: Option<i64>) -> Result<bool, Cancelled> {
        if self.pending_records() > 0 {
            return Ok(true);
        }
        let ms = match timeout_ns {
            None => INFINITE,
            Some(ns) if ns <= 0 => return Ok(false),
            Some(ns) => ((ns + NS_PER_MS - 1) / NS_PER_MS).min(i64::from(INFINITE - 1)) as u32,
        };
        let job = (self.input as usize, self.wake as usize, ms);
        // The wait runs on a pool thread: nothing on the console's side can be waited on by the
        // scheduler's poller.
        match ms_rt::glue::pool::try_run(Lane::General, job, wait_input_or_wake, -1) {
            Ok(Some(())) => Ok(self.pending_records() > 0),
            // A stop request or a task limit ended the wait; the abandoned wait holds a pool
            // thread until the event is set.
            outcome => {
                wake();
                outcome.map(|_| false)
            }
        }
    }

    /// Appends the characters of the ready key records to `out` as UTF-8; `Err(())` when the
    /// console input fails.
    pub fn read_ready(&self, out: &mut Vec<u8>) -> Result<(), ()> {
        // SAFETY: an all-zero record is valid; `ReadConsoleInputW` fills what it reports.
        let mut records: [INPUT_RECORD; 128] = unsafe { core::mem::zeroed() };
        let want = self.pending_records().min(records.len() as u32);
        if want == 0 {
            return Ok(());
        }
        let mut got = 0;
        // SAFETY: the buffer holds `want` records and `got` is a valid out value.
        if unsafe { ReadConsoleInputW(self.input, records.as_mut_ptr(), want, &mut got) } == 0 {
            return Err(());
        }
        for record in &records[..got as usize] {
            if record.EventType != KEY_EVENT as u16 {
                continue;
            }
            // SAFETY: the event type says the key member is the active one.
            let key = unsafe { record.Event.KeyEvent };
            // SAFETY: `uChar` is read as the UTF-16 unit the console delivers.
            let unit = unsafe { key.uChar.UnicodeChar };
            if key.bKeyDown == 0 || unit == 0 {
                continue;
            }
            self.push_unit(unit, out);
        }
        Ok(())
    }

    fn push_unit(&self, unit: u16, out: &mut Vec<u8>) {
        let mut buf = [0u8; 4];
        let scalar = match (self.high.take(), unit) {
            (_, 0xd800..=0xdbff) => {
                self.high.set(Some(unit));
                return;
            }
            (Some(high), 0xdc00..=0xdfff) => {
                0x10000 + ((u32::from(high) - 0xd800) << 10) + (u32::from(unit) - 0xdc00)
            }
            (_, u) => u32::from(u),
        };
        let c = char::from_u32(scalar).unwrap_or('\u{fffd}');
        out.extend_from_slice(c.encode_utf8(&mut buf).as_bytes());
    }

    pub fn write_all(&self, bytes: &[u8]) -> Result<(), Failure> {
        let mut rest = bytes;
        while !rest.is_empty() {
            let mut written = 0;
            let len = rest.len().min(1 << 20) as u32;
            // SAFETY: `rest` holds at least `len` bytes and `written` is a valid out value.
            let ok = unsafe {
                WriteFile(
                    self.output,
                    rest.as_ptr(),
                    len,
                    &mut written,
                    core::ptr::null_mut(),
                )
            };
            if ok == 0 || written == 0 {
                return Err(Failure::failed("cannot write to the terminal"));
            }
            rest = &rest[written as usize..];
        }
        Ok(())
    }
}
