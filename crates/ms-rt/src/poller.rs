//! The scheduler's descriptor poller. A task parks on one descriptor at a time; each
//! registration is one-shot and level-like: registering an already-ready descriptor reports
//! it at once. Both platforms use mio.

use crate::fault;
#[cfg(unix)]
use crate::sys;
#[cfg(unix)]
use crate::task::WAIT_KEEP;
use crate::task::{WAIT_HUP, WAIT_READ, WAIT_WRITE};
#[cfg(unix)]
use core::sync::atomic::AtomicI32;
#[cfg(unix)]
use core::sync::atomic::Ordering;

/// A descriptor that became ready, with the `WAIT_*` bits it reports.
#[derive(Clone, Copy)]
pub struct Ready {
    pub fd: usize,
    pub bits: u32,
}

/// What registering a descriptor came to.
pub enum Watch {
    Armed,
    /// The descriptor cannot be polled (a regular file): ready at once.
    Always,
    Failed,
}

/// The interest a wait asks for; waiting on nothing watches for readability.
fn interest(events: u32) -> mio::Interest {
    match (events & WAIT_READ != 0, events & WAIT_WRITE != 0) {
        (false, true) => mio::Interest::WRITABLE,
        (true, true) => mio::Interest::READABLE | mio::Interest::WRITABLE,
        _ => mio::Interest::READABLE,
    }
}

/// The `WAIT_*` bits an event reports.
fn bits(ev: &mio::event::Event) -> u32 {
    let mut r = 0;
    if ev.is_readable() || ev.is_read_closed() {
        r |= WAIT_READ;
    }
    if ev.is_writable() || ev.is_write_closed() {
        r |= WAIT_WRITE;
    }
    if ev.is_error() || (ev.is_read_closed() && ev.is_write_closed()) {
        r |= WAIT_READ | WAIT_WRITE | WAIT_HUP;
    }
    r
}

/// Write side of the descriptor that interrupts the wait; used by signal handlers.
#[cfg(unix)]
static WAKE_FD: AtomicI32 = AtomicI32::new(-1);

#[cfg(unix)]
mod imp {
    use super::*;
    use crate::global::Global;
    use mio::unix::SourceFd;
    use mio::unix::pipe;
    use mio::{Events, Poll, Token};
    use std::io::{ErrorKind, Read};
    use std::os::fd::AsRawFd;
    use std::time::Duration;

    const WAKE_TOKEN: Token = Token(usize::MAX);
    const EPERM: i32 = 1;

    struct State {
        poll: Poll,
        events: Events,
        /// Per descriptor: the interest bits of a kept registration (see `WAIT_KEEP`), or 0.
        kept: Vec<u8>,
        wake_rx: pipe::Receiver,
        // Owns the write end that `WAKE_FD` points at.
        _wake_tx: pipe::Sender,
    }

    static STATE: Global<Option<State>> = Global::new(None);

    fn state() -> &'static mut State {
        // SAFETY: only the scheduler thread reaches the poller state.
        match unsafe { &mut *STATE.ptr() } {
            Some(s) => s,
            None => fault::fault(b"the I/O poller is not open"),
        }
    }

    /// Opens the poller; the returned value is only a placeholder for the old descriptor API.
    pub unsafe fn create() -> i32 {
        let open = || -> std::io::Result<State> {
            let poll = Poll::new()?;
            let (tx, mut rx) = pipe::new()?;
            poll.registry()
                .register(&mut rx, WAKE_TOKEN, mio::Interest::READABLE)?;
            WAKE_FD.store(tx.as_raw_fd(), Ordering::Relaxed);
            Ok(State {
                poll,
                events: Events::with_capacity(64),
                kept: Vec::new(),
                wake_rx: rx,
                _wake_tx: tx,
            })
        };
        match open() {
            // SAFETY: only the scheduler thread reaches the poller state.
            Ok(s) => unsafe { *STATE.ptr() = Some(s) },
            Err(_) => fault::fault(b"cannot create the I/O poller"),
        }
        0
    }

    /// Interrupts the wait. One `write`, so signal handlers may call it.
    pub fn kick() {
        let fd = WAKE_FD.load(Ordering::Relaxed);
        if fd >= 0 {
            let one = 1u8;
            // SAFETY: writes one byte from a live local; a full pipe already holds a wake-up.
            unsafe { sys::write(fd, core::ptr::addr_of!(one).cast(), 1) };
        }
    }

    /// Nothing to undo: a one-shot registration stays disarmed until the next wait.
    pub fn unwatch(_: i32) {}

    /// Ends the kept registration of `fd` (see `WAIT_KEEP`) before its owner closes it. Closing
    /// removes the descriptor from the kernel's set, but the record here would survive and make
    /// a later descriptor with the same number look registered when it is not.
    pub fn forget(fd: i32) {
        // SAFETY: only the scheduler thread reaches the poller state.
        let Some(s) = (unsafe { &mut *STATE.ptr() }) else {
            return;
        };
        if let Some(code) = s.kept.get_mut(fd as usize)
            && *code != 0
        {
            *code = 0;
            let _ = s.poll.registry().deregister(&mut SourceFd(&fd));
        }
    }

    pub unsafe fn close(_: i32) {
        WAKE_FD.store(-1, Ordering::Relaxed);
        // SAFETY: only the scheduler thread reaches the poller state.
        unsafe { *STATE.ptr() = None };
    }

    pub unsafe fn watch(_: i32, fd: i32, events: u32) -> Watch {
        let interest = interest(events);
        let s = state();
        let idx = fd as usize;
        if s.kept.len() <= idx {
            s.kept.resize(idx + 1, 0);
        }
        let code = (events & (WAIT_READ | WAIT_WRITE)) as u8 | 0x80;
        if events & WAIT_KEEP != 0 && s.kept[idx] == code {
            return Watch::Armed;
        }
        s.kept[idx] = 0;
        let registry = s.poll.registry();
        let (token, mut source) = (Token(fd as usize), SourceFd(&fd));
        // Re-registering reports a descriptor that is already ready, which is what makes a
        // wait level-like on top of mio's edge-triggered events.
        let mut r = registry.reregister(&mut source, token, interest);
        if matches!(&r, Err(e) if e.kind() == ErrorKind::NotFound) {
            r = registry.register(&mut source, token, interest);
            if matches!(&r, Err(e) if e.kind() == ErrorKind::AlreadyExists) {
                r = registry.reregister(&mut source, token, interest);
            }
        }
        match r {
            Ok(()) => {
                if events & WAIT_KEEP != 0 {
                    s.kept[idx] = code;
                }
                Watch::Armed
            }
            Err(e) if e.raw_os_error() == Some(EPERM) => Watch::Always,
            Err(_) => Watch::Failed,
        }
    }

    pub unsafe fn wait(_: i32, timeout_ms: i32, out: &mut [Ready; 64]) -> Option<usize> {
        let s = state();
        let timeout = (timeout_ms >= 0).then(|| Duration::from_millis(timeout_ms as u64));
        match s.poll.poll(&mut s.events, timeout) {
            Ok(()) => {}
            Err(e) if e.kind() == ErrorKind::Interrupted => return None,
            Err(_) => fault::fault(b"I/O poller failed"),
        }
        let mut count = 0;
        for ev in s.events.iter() {
            if ev.token() == WAKE_TOKEN {
                let mut drain = [0u8; 64];
                while matches!(s.wake_rx.read(&mut drain), Ok(n) if n > 0) {}
                continue;
            }
            out[count] = Ready {
                fd: ev.token().0,
                bits: bits(ev),
            };
            count += 1;
        }
        Some(count)
    }
}

#[cfg(windows)]
mod imp {
    //! mio over the sockets tasks wait on. mio only watches its own socket types, so a wait
    //! lends the raw `SOCKET` to a short-lived [`TcpStream`] view that is registered and, when
    //! the wait ends, deregistered and turned back into the raw handle without closing it.
    //! A handle that is not a socket cannot be registered and counts as ready at once.
    //!
    //! An overlapped named pipe adopted with [`pipe_adopt`] stays registered, as a mio
    //! `NamedPipe`, until [`pipe_drop`]; its reads and writes go through mio's overlapped buffers.
    //! A task waits on the handle to read and on the handle plus one to write (handles are
    //! multiples of four), so one task can read while another writes.

    use super::*;
    use crate::global::Global;
    use mio::net::TcpStream;
    use mio::windows::NamedPipe;
    use mio::{Events, Poll, Token, Waker};
    use std::collections::HashMap;
    use std::io::{Read, Write};
    use std::os::windows::io::{FromRawHandle, RawHandle};
    use std::os::windows::io::{FromRawSocket, IntoRawSocket};
    use std::sync::{Arc, Mutex};
    use std::time::Duration;

    const WAKE_TOKEN: Token = Token(usize::MAX);

    struct State {
        poll: Poll,
        events: Events,
        /// The registered views, by socket.
        views: HashMap<usize, TcpStream>,
        /// Adopted named pipes, by handle; registered until dropped.
        pipes: HashMap<usize, NamedPipe>,
    }

    static STATE: Global<Option<State>> = Global::new(None);
    static WAKER: Mutex<Option<Arc<Waker>>> = Mutex::new(None);

    fn state() -> &'static mut State {
        // SAFETY: only the scheduler thread reaches the poller state.
        match unsafe { &mut *STATE.ptr() } {
            Some(s) => s,
            None => fault::fault(b"the I/O poller is not open"),
        }
    }

    pub unsafe fn create() -> i32 {
        let open = || -> std::io::Result<(State, Arc<Waker>)> {
            let poll = Poll::new()?;
            let waker = Arc::new(Waker::new(poll.registry(), WAKE_TOKEN)?);
            let state = State {
                poll,
                // Half the 64 ready slots: a pipe event can wake a reader and a writer.
                events: Events::with_capacity(32),
                views: HashMap::new(),
                pipes: HashMap::new(),
            };
            Ok((state, waker))
        };
        match open() {
            Ok((s, waker)) => {
                // SAFETY: only the scheduler thread reaches the poller state.
                unsafe { *STATE.ptr() = Some(s) };
                *WAKER.lock().unwrap_or_else(|e| e.into_inner()) = Some(waker);
            }
            Err(_) => fault::fault(b"cannot create the I/O poller"),
        }
        0
    }

    /// Interrupts the wait; the stop request comes from a console handler thread.
    pub fn kick() {
        if let Some(waker) = &*WAKER.lock().unwrap_or_else(|e| e.into_inner()) {
            let _ = waker.wake();
        }
    }

    pub unsafe fn close(_: i32) {
        *WAKER.lock().unwrap_or_else(|e| e.into_inner()) = None;
        // SAFETY: only the scheduler thread reaches the poller state.
        unsafe { *STATE.ptr() = None };
    }

    /// Ends the registration of `sock`, leaving the socket open.
    fn release(s: &mut State, sock: usize) {
        if let Some(mut view) = s.views.remove(&sock) {
            let _ = s.poll.registry().deregister(&mut view);
            let _ = view.into_raw_socket();
        }
    }

    pub fn unwatch(fd: i32) {
        release(state(), fd as usize);
    }

    /// Nothing kept here: registrations are one-shot.
    pub fn forget(_: i32) {}

    pub unsafe fn watch(_: i32, fd: i32, events: u32) -> Watch {
        let (s, sock) = (state(), fd as usize);
        if s.pipes.contains_key(&(sock & !3)) {
            return Watch::Armed;
        }
        release(s, sock);
        let interest = interest(events);
        // SAFETY: the view never closes the socket: it ends in `into_raw_socket`.
        let stream = unsafe { std::net::TcpStream::from_raw_socket(sock as u64) };
        let mut view = TcpStream::from_std(stream);
        match s.poll.registry().register(&mut view, Token(sock), interest) {
            Ok(()) => {
                s.views.insert(sock, view);
                Watch::Armed
            }
            Err(_) => {
                let _ = view.into_raw_socket();
                Watch::Always
            }
        }
    }

    /// Registers the overlapped named pipe `handle` for reads and writes; it is closed by
    /// [`pipe_drop`]. False when it cannot be registered (not opened for overlapped I/O).
    ///
    /// # Safety
    /// `handle` is an open named-pipe handle opened with `FILE_FLAG_OVERLAPPED`, owned from now
    /// on by the poller.
    pub unsafe fn pipe_adopt(handle: usize) -> bool {
        let s = state();
        // SAFETY: the caller hands over an open overlapped pipe handle.
        let mut pipe = unsafe { NamedPipe::from_raw_handle(handle as RawHandle) };
        let interest = mio::Interest::READABLE | mio::Interest::WRITABLE;
        if s.poll
            .registry()
            .register(&mut pipe, Token(handle), interest)
            .is_err()
        {
            // Hand the handle back to the caller unclosed.
            core::mem::forget(pipe);
            return false;
        }
        s.pipes.insert(handle, pipe);
        true
    }

    /// One non-blocking read from an adopted pipe; `WouldBlock` until data arrives.
    pub fn pipe_read(handle: usize, buf: &mut [u8]) -> std::io::Result<usize> {
        match state().pipes.get(&handle) {
            Some(mut pipe) => pipe.read(buf),
            None => Err(std::io::ErrorKind::NotFound.into()),
        }
    }

    /// One non-blocking write to an adopted pipe; `WouldBlock` while an earlier write is in
    /// flight.
    pub fn pipe_write(handle: usize, buf: &[u8]) -> std::io::Result<usize> {
        match state().pipes.get(&handle) {
            Some(mut pipe) => pipe.write(buf),
            None => Err(std::io::ErrorKind::NotFound.into()),
        }
    }

    /// Deregisters and closes an adopted pipe.
    pub fn pipe_drop(handle: usize) {
        let s = state();
        if let Some(mut pipe) = s.pipes.remove(&handle) {
            let _ = s.poll.registry().deregister(&mut pipe);
        }
    }

    pub unsafe fn wait(_: i32, timeout_ms: i32, out: &mut [Ready; 64]) -> Option<usize> {
        let s = state();
        let timeout = (timeout_ms >= 0).then(|| Duration::from_millis(timeout_ms as u64));
        if s.poll.poll(&mut s.events, timeout).is_err() {
            fault::fault(b"I/O poller failed");
        }
        let mut count = 0;
        let mut ready: Vec<(usize, u32)> = Vec::new();
        for ev in s.events.iter().filter(|ev| ev.token() != WAKE_TOKEN) {
            let (fd, bits) = (ev.token().0, bits(ev));
            if !s.pipes.contains_key(&fd) {
                ready.push((fd, bits));
                continue;
            }
            // A pipe stays registered: wake its reader and its writer separately.
            if bits & (WAIT_READ | WAIT_HUP) != 0 {
                out[count] = Ready { fd, bits };
                count += 1;
            }
            if bits & (WAIT_WRITE | WAIT_HUP) != 0 {
                out[count] = Ready { fd: fd + 1, bits };
                count += 1;
            }
        }
        for (sock, bits) in ready {
            // One-shot: the task registers again when it waits again.
            release(s, sock);
            out[count] = Ready { fd: sock, bits };
            count += 1;
        }
        Some(count)
    }
}

pub use imp::{close, create, forget, kick, unwatch, wait, watch};
#[cfg(windows)]
pub use imp::{pipe_adopt, pipe_drop, pipe_read, pipe_write};
