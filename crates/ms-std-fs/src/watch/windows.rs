//! The native watcher on Windows: one overlapped `ReadDirectoryChangesW` request on the watched
//! directory handle. `next` checks the request without blocking between short sleeps, so a
//! pending call stays cancellable, and the request is cancelled before its buffer is freed.
use super::{Event, sleep_slice, valid_native};
use crate::err::{Fail, Res};
use crate::path;
use crate::sys;
use alloc::boxed::Box;
use alloc::collections::VecDeque;
use alloc::vec::Vec;
use ms_rt::glue::poll_cancel;
use ms_rt_abi::{STATUS_LIMIT_EXCEEDED, STATUS_UNSUPPORTED};
use std::fs::OpenOptions;
use std::os::windows::fs::OpenOptionsExt;
use std::os::windows::io::AsRawHandle;
use windows_sys::Win32::Foundation::{ERROR_IO_INCOMPLETE, GetLastError};
use windows_sys::Win32::Storage::FileSystem::{
    FILE_FLAG_BACKUP_SEMANTICS, FILE_FLAG_OVERLAPPED, FILE_LIST_DIRECTORY,
    FILE_NOTIFY_CHANGE_ATTRIBUTES, FILE_NOTIFY_CHANGE_CREATION, FILE_NOTIFY_CHANGE_DIR_NAME,
    FILE_NOTIFY_CHANGE_FILE_NAME, FILE_NOTIFY_CHANGE_LAST_WRITE, FILE_NOTIFY_CHANGE_SIZE,
    ReadDirectoryChangesW,
};
use windows_sys::Win32::System::IO::{CancelIoEx, GetOverlappedResult, OVERLAPPED};

const WATCH: u32 = FILE_NOTIFY_CHANGE_FILE_NAME
    | FILE_NOTIFY_CHANGE_DIR_NAME
    | FILE_NOTIFY_CHANGE_ATTRIBUTES
    | FILE_NOTIFY_CHANGE_SIZE
    | FILE_NOTIFY_CHANGE_LAST_WRITE
    | FILE_NOTIFY_CHANGE_CREATION;

/// `FILE_ACTION_*` values that mean an entry appeared, vanished or was renamed.
const RENAMES: [u32; 4] = [1, 2, 4, 5];

/// The request buffer, in `u32`s so the records inside it are aligned.
const WORDS: usize = 16 * 1024;

pub struct Native {
    dir: std::fs::File,
    root: Vec<u8>,
    /// The name of the single file being watched through its parent directory.
    only: Option<Vec<u8>>,
    recursive: bool,
    ignore_overflow: bool,
    capacity: usize,
    buffer: Box<[u32; WORDS]>,
    overlapped: Box<OVERLAPPED>,
    pending: bool,
    queue: VecDeque<Event>,
    terminal: Option<Fail>,
}

impl Native {
    /// `overflow` is `error` or `ignore`; `events` bounds the queued events. `max` is unused: one
    /// handle watches the whole tree.
    pub fn new(
        root: &[u8],
        recursive: bool,
        max: i64,
        events: i64,
        overflow: &[u8],
    ) -> Res<Native> {
        valid_native(root, max, events, overflow)?;
        let text = core::str::from_utf8(root).map_err(|_| Fail::status(STATUS_UNSUPPORTED))?;
        let meta = std::fs::metadata(text).map_err(|e| Fail::errno(sys::code(&e), "stat", root))?;
        // A file is watched through its directory, keeping only the events that name it.
        let (watched, only, recursive) = if meta.is_dir() {
            (root.to_vec(), None, recursive)
        } else {
            (path::dir(root), Some(path::base(root)), false)
        };
        let dir_text =
            core::str::from_utf8(&watched).map_err(|_| Fail::status(STATUS_UNSUPPORTED))?;
        let dir = OpenOptions::new()
            .access_mode(FILE_LIST_DIRECTORY)
            .share_mode(7)
            .custom_flags(FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED)
            .open(dir_text)
            .map_err(|e| Fail::errno(sys::code(&e), "open", &watched))?;
        let mut n = Native {
            dir,
            root: watched,
            only,
            recursive,
            ignore_overflow: overflow == b"ignore",
            capacity: events as usize,
            buffer: Box::new([0; WORDS]),
            // SAFETY: a zeroed `OVERLAPPED` is the documented initial state.
            overlapped: Box::new(unsafe { core::mem::zeroed() }),
            pending: false,
            queue: VecDeque::new(),
            terminal: None,
        };
        n.issue()?;
        Ok(n)
    }

    /// Starts the next request.
    fn issue(&mut self) -> Res<()> {
        // SAFETY: a zeroed `OVERLAPPED` is the documented initial state.
        *self.overlapped = unsafe { core::mem::zeroed() };
        // SAFETY: the buffer and `OVERLAPPED` live in boxes that outlast the request, which `Drop`
        // cancels and waits for.
        let started = unsafe {
            ReadDirectoryChangesW(
                self.dir.as_raw_handle(),
                self.buffer.as_mut_ptr().cast(),
                (WORDS * 4) as u32,
                i32::from(self.recursive),
                WATCH,
                core::ptr::null_mut(),
                &mut *self.overlapped,
                None,
            )
        };
        if started == 0 {
            return Err(Fail::raw(sys::errno()));
        }
        self.pending = true;
        Ok(())
    }

    fn push(&mut self, e: Event) {
        if self.queue.len() >= self.capacity {
            if !self.ignore_overflow && self.terminal.is_none() {
                self.terminal = Some(Fail::status(STATUS_LIMIT_EXCEEDED));
            }
            return;
        }
        self.queue.push_back(e);
    }

    /// Queues the events of one finished request; `bytes` is the filled part of the buffer.
    fn decode(&mut self, bytes: &[u8]) {
        let mut at = 0usize;
        while at + 12 <= bytes.len() {
            let word = |o: usize| u32::from_ne_bytes(bytes[at + o..at + o + 4].try_into().unwrap());
            let (next, action, len) = (word(0) as usize, word(4), word(8) as usize);
            let end = (at + 12 + len).min(bytes.len());
            let units: Vec<u16> = bytes[at + 12..end]
                .chunks_exact(2)
                .map(|c| u16::from_ne_bytes([c[0], c[1]]))
                .collect();
            let name = alloc::string::String::from_utf16_lossy(&units).replace('\\', "/");
            let wanted = self
                .only
                .as_ref()
                .is_none_or(|only| only.as_slice() == name.as_bytes());
            if wanted {
                let full = if self.only.is_some() {
                    self.only
                        .as_ref()
                        .map_or_else(Vec::new, |n| path::join(&self.root, n))
                } else {
                    path::join(&self.root, name.as_bytes())
                };
                self.push(Event {
                    path: full,
                    rename: RENAMES.contains(&action),
                });
            }
            if next == 0 {
                break;
            }
            at += next;
        }
    }

    pub fn wait(&mut self) -> Res<Vec<Event>> {
        loop {
            if let Some(f) = self.terminal.take() {
                return Err(f);
            }
            if let Some(e) = self.queue.pop_front() {
                return Ok(alloc::vec![e]);
            }
            poll_cancel();
            let mut got = 0u32;
            // SAFETY: the request is ours and `got` is writable; the call does not wait.
            let done = unsafe {
                GetOverlappedResult(self.dir.as_raw_handle(), &*self.overlapped, &mut got, 0)
            };
            if done == 0 {
                // SAFETY: plain query.
                if unsafe { GetLastError() } == ERROR_IO_INCOMPLETE {
                    sleep_slice();
                    continue;
                }
                self.pending = false;
                return Err(Fail::raw(sys::errno()));
            }
            self.pending = false;
            // Copy the records out and ask again at once, so changes during decoding are kept.
            let used = got as usize;
            let bytes: Vec<u8> = self
                .buffer
                .iter()
                .flat_map(|w| w.to_ne_bytes())
                .take(used)
                .collect();
            self.issue()?;
            if used == 0 {
                // The kernel dropped events because the buffer filled.
                if !self.ignore_overflow {
                    return Err(Fail::status(STATUS_LIMIT_EXCEEDED));
                }
                continue;
            }
            self.decode(&bytes);
        }
    }
}

impl Drop for Native {
    fn drop(&mut self) {
        if self.pending {
            let mut got = 0u32;
            // SAFETY: the request is ours; it is cancelled and finished before the buffers go.
            unsafe {
                CancelIoEx(self.dir.as_raw_handle(), &*self.overlapped);
                GetOverlappedResult(self.dir.as_raw_handle(), &*self.overlapped, &mut got, 1);
            }
        }
    }
}
