//! The Windows console: virtual-terminal input and output modes over the standard handles.
//!
//! Input is read as console input records, never with a blocking `ReadFile`, because a resize or
//! focus record would leave a byte read waiting. With virtual-terminal input on, each key record
//! carries one character of the escape sequence the shared decoder understands.
#![allow(unsafe_code)] // the Win32 console calls below

use crate::{NS_PER_MS, pause};
use alloc::vec::Vec;
use ms_rt::ffi::Failure;
use ms_rt::glue::pool::Cancelled;
use ms_rt_abi::STATUS_NOT_TERMINAL;
use std::ffi::OsString;
use windows_sys::Win32::Foundation::{HANDLE, INVALID_HANDLE_VALUE, WAIT_OBJECT_0};
use windows_sys::Win32::Storage::FileSystem::WriteFile;
use windows_sys::Win32::System::Console::{
    CONSOLE_MODE, CONSOLE_SCREEN_BUFFER_INFO, ENABLE_ECHO_INPUT, ENABLE_LINE_INPUT,
    ENABLE_PROCESSED_INPUT, ENABLE_PROCESSED_OUTPUT, ENABLE_VIRTUAL_TERMINAL_INPUT,
    ENABLE_VIRTUAL_TERMINAL_PROCESSING, ENABLE_WINDOW_INPUT, GetConsoleCP, GetConsoleMode,
    GetConsoleOutputCP, GetConsoleScreenBufferInfo, GetNumberOfConsoleInputEvents, GetStdHandle,
    INPUT_RECORD, KEY_EVENT, ReadConsoleInputW, STD_INPUT_HANDLE, STD_OUTPUT_HANDLE, SetConsoleCP,
    SetConsoleMode, SetConsoleOutputCP,
};
use windows_sys::Win32::System::Threading::WaitForSingleObject;

const UTF8: u32 = 65001;
/// The longest the task sleeps between checks for input.
const SLICE_NS: i64 = 10 * NS_PER_MS;

/// The console handles and the settings to put back.
pub struct Term {
    input: HANDLE,
    output: HANDLE,
    input_mode: CONSOLE_MODE,
    output_mode: CONSOLE_MODE,
    input_cp: u32,
    output_cp: u32,
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

    /// Sleeps in short slices until input records are ready or `timeout_ns` passes.
    pub fn wait_readable(&self, timeout_ns: i64) -> Result<bool, Cancelled> {
        let mut left = timeout_ns.max(0);
        loop {
            // SAFETY: a zero-timeout poll of the input handle.
            let signalled = unsafe { WaitForSingleObject(self.input, 0) } == WAIT_OBJECT_0;
            if signalled && self.pending_records() > 0 {
                return Ok(true);
            }
            if left <= 0 {
                return Ok(false);
            }
            let step = left.min(SLICE_NS);
            pause(step)?;
            left -= step;
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
