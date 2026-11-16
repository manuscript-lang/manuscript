//! The native watcher on Windows: one overlapped `ReadDirectoryChangesW` request on the watched
//! directory handle. The request completes an event, and `close` sets the same event, so a
//! pending `next` parks until a change or a close; the request is cancelled before its buffer
//! is freed.
use super::{Event, Gate, valid_native, wait_object};
use crate::err::{Fail, Res};
use crate::ops::poll_cancel;
use crate::path;
use crate::sys::{self, CPath};
use alloc::boxed::Box;
use alloc::collections::VecDeque;
use alloc::vec::Vec;
use ms_rt_abi::{STATUS_CLOSED, STATUS_LIMIT_EXCEEDED, STATUS_NONE, STATUS_UNSUPPORTED};
use std::fs::OpenOptions;
use std::os::windows::fs::OpenOptionsExt;
use std::os::windows::io::AsRawHandle;
use windows_sys::Win32::Foundation::{
    CloseHandle, ERROR_ACCESS_DENIED, ERROR_DELETE_PENDING, ERROR_FILE_NOT_FOUND,
    ERROR_IO_INCOMPLETE, ERROR_PATH_NOT_FOUND, GetLastError, HANDLE,
};
use windows_sys::Win32::Storage::FileSystem::{
    FILE_FLAG_BACKUP_SEMANTICS, FILE_FLAG_OVERLAPPED, FILE_LIST_DIRECTORY,
    FILE_NOTIFY_CHANGE_ATTRIBUTES, FILE_NOTIFY_CHANGE_CREATION, FILE_NOTIFY_CHANGE_DIR_NAME,
    FILE_NOTIFY_CHANGE_FILE_NAME, FILE_NOTIFY_CHANGE_LAST_WRITE, FILE_NOTIFY_CHANGE_SIZE,
    ReadDirectoryChangesW,
};
use windows_sys::Win32::System::IO::{CancelIoEx, GetOverlappedResult, OVERLAPPED};
use windows_sys::Win32::System::Threading::{CreateEventW, ResetEvent, SetEvent};

const WATCH: u32 = FILE_NOTIFY_CHANGE_FILE_NAME
    | FILE_NOTIFY_CHANGE_DIR_NAME
    | FILE_NOTIFY_CHANGE_ATTRIBUTES
    | FILE_NOTIFY_CHANGE_SIZE
    | FILE_NOTIFY_CHANGE_LAST_WRITE
    | FILE_NOTIFY_CHANGE_CREATION;

/// `FILE_ACTION_ADDED`, `FILE_ACTION_REMOVED`, `FILE_ACTION_RENAMED_OLD_NAME` and
/// `FILE_ACTION_RENAMED_NEW_NAME`.
const ADDED: u32 = 1;
const REMOVED: u32 = 2;
const RENAMED_OLD: u32 = 4;
const RENAMED_NEW: u32 = 5;

/// The actions that mean an entry appeared, vanished or was renamed.
const RENAMES: [u32; 4] = [ADDED, REMOVED, RENAMED_OLD, RENAMED_NEW];

/// What a pending request fails with once the watched directory is gone for certain.
const ROOT_GONE: [u32; 3] = [
    ERROR_DELETE_PENDING,
    ERROR_FILE_NOT_FOUND,
    ERROR_PATH_NOT_FOUND,
];

/// The request buffer, in `u32`s so the records inside it are aligned.
const WORDS: usize = 16 * 1024;

pub struct Native {
    /// The watched directory's handle; `None` once it was released to let a removal finish.
    dir: Option<std::fs::File>,
    root: Vec<u8>,
    /// The name of the single file being watched through its parent directory.
    only: Option<Vec<u8>>,
    recursive: bool,
    ignore_overflow: bool,
    capacity: usize,
    buffer: Box<[u32; WORDS]>,
    overlapped: Box<OVERLAPPED>,
    /// A manual-reset event the request completes and `close` sets.
    event: HANDLE,
    pending: bool,
    queue: VecDeque<Event>,
    terminal: Option<Fail>,
    /// The watched file or directory is gone: the stream ends after the queue drains.
    ended: bool,
}

impl Native {
    /// Wakes a `wait` parked on the event, for `close`.
    pub fn interrupt(&self) {
        // SAFETY: the event is open until `Drop`.
        unsafe { SetEvent(self.event) };
    }

    /// `overflow` is `error` or `ignore`; `max` bounds the paths under the root at start and
    /// `events` the queued events.
    pub fn new(
        root: &[u8],
        recursive: bool,
        max: i64,
        events: i64,
        overflow: &[u8],
    ) -> Res<Native> {
        valid_native(root, recursive, max, events, overflow)?;
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
        // SAFETY: plain call; a manual-reset event, not signalled.
        let event = unsafe { CreateEventW(core::ptr::null(), 1, 0, core::ptr::null()) };
        if event.is_null() {
            return Err(Fail::raw(sys::errno()));
        }
        let mut n = Native {
            event,
            dir: Some(dir),
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
            ended: false,
        };
        n.issue()?;
        Ok(n)
    }

    fn handle(&self) -> HANDLE {
        self.dir
            .as_ref()
            .map_or(core::ptr::null_mut(), |d| d.as_raw_handle())
    }

    /// Whether the watched directory no longer exists. Our own open handle keeps a deleted
    /// directory alive, so it is released first; the request has already failed, so nothing
    /// is pending on it.
    fn root_removed(&mut self) -> bool {
        self.dir = None;
        CPath::new(&self.root).is_some_and(|c| sys::stat(&c, false).is_err_and(sys::is_not_found))
    }

    /// Starts the next request.
    fn issue(&mut self) -> Res<()> {
        // SAFETY: a zeroed `OVERLAPPED` is the documented initial state.
        *self.overlapped = unsafe { core::mem::zeroed() };
        self.overlapped.hEvent = self.event;
        // SAFETY: the buffer and `OVERLAPPED` live in boxes that outlast the request, which `Drop`
        // cancels and waits for.
        let started = unsafe {
            ReadDirectoryChangesW(
                self.handle(),
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
                // Watching one file through its parent: its removal or rename ends the stream.
                if self.only.is_some() && (action == REMOVED || action == RENAMED_OLD) {
                    self.ended = true;
                }
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

    pub fn wait(&mut self, gate: &Gate) -> Res<Vec<Event>> {
        loop {
            if let Some(f) = self.terminal.take() {
                return Err(f);
            }
            if let Some(e) = self.queue.pop_front() {
                return Ok(alloc::vec![e]);
            }
            if self.ended {
                return Err(Fail::status(STATUS_NONE));
            }
            poll_cancel()?;
            if gate.is_closed() {
                return Err(Fail::status(STATUS_CLOSED));
            }
            // Reset before looking, so a completion or a close after the look sets it again.
            // SAFETY: the event is open until `Drop`.
            unsafe { ResetEvent(self.event) };
            if gate.is_closed() {
                return Err(Fail::status(STATUS_CLOSED));
            }
            let mut got = 0u32;
            // SAFETY: the request is ours and `got` is writable; the call does not wait.
            let done =
                unsafe { GetOverlappedResult(self.handle(), &*self.overlapped, &mut got, 0) };
            if done == 0 {
                // SAFETY: plain query.
                let code = unsafe { GetLastError() };
                if code == ERROR_IO_INCOMPLETE {
                    if !wait_object(self.event as isize) {
                        return Err(Fail::failed("watch"));
                    }
                    continue;
                }
                self.pending = false;
                // A removed directory fails its pending request with one of a few codes: that is
                // the end, not an error. Any other code is a real failure.
                // Access denied also has unrelated causes, so it ends the stream only when the
                // directory is confirmed gone.
                if ROOT_GONE.contains(&code) || (code == ERROR_ACCESS_DENIED && self.root_removed())
                {
                    // The directory's own removal is not a record in its own change list, so
                    // report it here before the stream ends.
                    let gone = self
                        .only
                        .as_ref()
                        .map_or_else(|| self.root.clone(), |n| path::join(&self.root, n));
                    self.push(Event {
                        path: gone,
                        rename: true,
                    });
                    self.ended = true;
                    continue;
                }
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
                CancelIoEx(self.handle(), &*self.overlapped);
                GetOverlappedResult(self.handle(), &*self.overlapped, &mut got, 1);
            }
        }
        // SAFETY: the event is ours and the request that used it is finished.
        unsafe { CloseHandle(self.event) };
    }
}
