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

    crate::isolate_static! {
        static STATE: Option<State> = None;
    }

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
            let fd = tx.as_raw_fd();
            if crate::isolate::is_main() {
                WAKE_FD.store(fd, Ordering::Relaxed);
            }
            crate::isolate::set_wake(Some(Box::new(move || {
                let one = 1u8;
                // SAFETY: writes one byte from a live local; `close` unsets this closure
                // before the descriptor is closed, and a full pipe already holds a wake-up.
                unsafe { sys::write(fd, core::ptr::addr_of!(one).cast(), 1) };
            })));
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
        if crate::isolate::is_main() {
            WAKE_FD.store(-1, Ordering::Relaxed);
        }
        crate::isolate::set_wake(None);
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

    /// Waits until the poller's descriptor has events or `ns` nanoseconds pass. `epoll_wait`
    /// counts whole milliseconds and rounds up, so a shorter timer would sleep a millisecond;
    /// `ppoll` on the epoll descriptor takes a `timespec`.
    #[cfg(any(target_os = "linux", target_os = "android"))]
    fn sleep_until_ready(poll: &Poll, ns: i64) {
        let mut fd = libc::pollfd {
            fd: poll.as_raw_fd(),
            events: libc::POLLIN,
            revents: 0,
        };
        let ts = libc::timespec {
            tv_sec: (ns / 1_000_000_000) as _,
            tv_nsec: (ns % 1_000_000_000) as _,
        };
        // SAFETY: `fd` and `ts` are live locals; an interrupted or failed wait just returns early
        // and the caller polls without blocking next.
        unsafe { libc::ppoll(&mut fd, 1, &ts, core::ptr::null()) };
    }

    pub unsafe fn wait(_: i32, timeout_ns: i64, out: &mut [Ready; 64]) -> Option<usize> {
        let s = state();
        #[cfg(any(target_os = "linux", target_os = "android"))]
        let timeout = if timeout_ns > 0 {
            sleep_until_ready(&s.poll, timeout_ns);
            Some(Duration::ZERO)
        } else {
            (timeout_ns == 0).then_some(Duration::ZERO)
        };
        #[cfg(not(any(target_os = "linux", target_os = "android")))]
        let timeout = (timeout_ns >= 0).then(|| Duration::from_nanos(timeout_ns as u64));
        match s.poll.poll(&mut s.events, timeout) {
            Ok(()) => {}
            Err(e) if e.kind() == ErrorKind::Interrupted => return None,
            Err(_) => fault::fault(b"I/O poller failed"),
        }
        let mut count = 0;
        for ev in s.events.iter() {
            if ev.token() == WAKE_TOKEN {
                let mut drain = [0u8; 64];
                // A short read emptied the pipe; a later wake-up is a new event, so another
                // read to see `WouldBlock` would only cost a system call.
                while matches!(s.wake_rx.read(&mut drain), Ok(n) if n == drain.len()) {}
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
        /// Thread-pool waits on kernel objects (a child process), by object handle: the wait and
        /// the context its callback was given.
        objects: HashMap<usize, (usize, usize)>,
        /// Where the callbacks of this isolate's waits report.
        signals: Arc<Signals>,
        /// Pipes whose readiness wakes the task waiting on another key instead, by handle.
        groups: HashMap<usize, usize>,
        /// Wakes an idle wait at a timer deadline, which the poll's millisecond timeout cannot.
        timer: Option<PreciseTimer>,
    }

    /// A high-resolution timer whose signal wakes the poller (see `wait`).
    struct PreciseTimer {
        handle: usize,
        wait: usize,
        /// The `Arc<Waker>` the wait callback was given, to free after the wait ends.
        context: *mut Arc<Waker>,
    }

    unsafe extern "system" fn timer_fired(context: *mut core::ffi::c_void, _: u8) {
        // SAFETY: the context lives until the wait is unregistered, which blocks on this callback.
        let waker = unsafe { &*(context as *const Arc<Waker>) };
        let _ = waker.wake();
    }

    impl PreciseTimer {
        fn open(waker: &Arc<Waker>) -> Option<PreciseTimer> {
            let handle = crate::sys::precise_timer_create();
            if handle.is_null() {
                return None;
            }
            let context = Box::into_raw(Box::new(waker.clone()));
            // SAFETY: the timer stays open until `Drop` unregisters the wait.
            let wait =
                unsafe { crate::sys::register_repeating_wait(handle, timer_fired, context.cast()) };
            if wait.is_null() {
                // SAFETY: the context was never shared; the handle is ours.
                unsafe {
                    drop(Box::from_raw(context));
                    crate::sys::close_handle(handle);
                }
                return None;
            }
            Some(PreciseTimer {
                handle: handle as usize,
                wait: wait as usize,
                context,
            })
        }
    }

    impl Drop for PreciseTimer {
        fn drop(&mut self) {
            // SAFETY: the wait and timer are ours; unregistering returns after a running
            // callback, so the context is no longer used.
            unsafe {
                crate::sys::unregister_wait(self.wait as *mut _);
                crate::sys::close_handle(self.handle as *mut _);
                drop(Box::from_raw(self.context));
            }
        }
    }

    crate::isolate_static! {
        static STATE: Option<State> = None;
    }
    static WAKER: Mutex<Option<Arc<Waker>>> = Mutex::new(None);

    /// Watched objects of one isolate that became signalled, filled by thread-pool callbacks,
    /// and the waker of that isolate's poller: a worker's wait is not the main isolate's.
    struct Signals {
        ready: Mutex<Vec<usize>>,
        waker: Arc<Waker>,
    }

    /// What a wait callback receives: where to report, and which object.
    struct Signalled {
        signals: Arc<Signals>,
        object: usize,
    }

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
            let signals = Arc::new(Signals {
                ready: Mutex::new(Vec::new()),
                waker: waker.clone(),
            });
            let state = State {
                poll,
                signals,
                // Half the 64 ready slots: a pipe event can wake a reader and a writer.
                events: Events::with_capacity(32),
                views: HashMap::new(),
                pipes: HashMap::new(),
                objects: HashMap::new(),
                groups: HashMap::new(),
                timer: PreciseTimer::open(&waker),
            };
            Ok((state, waker))
        };
        match open() {
            Ok((s, waker)) => {
                // SAFETY: only the scheduler thread reaches the poller state.
                unsafe { *STATE.ptr() = Some(s) };
                if crate::isolate::is_main() {
                    *WAKER.lock().unwrap_or_else(|e| e.into_inner()) = Some(waker.clone());
                }
                crate::isolate::set_wake(Some(Box::new(move || {
                    let _ = waker.wake();
                })));
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
        if crate::isolate::is_main() {
            *WAKER.lock().unwrap_or_else(|e| e.into_inner()) = None;
        }
        crate::isolate::set_wake(None);
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

    fn diag(text: &str) {
        if std::env::var_os("MS_DIAG_POLL").is_some() {
            crate::sys::write_all(crate::sys::STDERR, text.as_bytes());
        }
    }

    pub unsafe fn watch(_: i32, fd: i32, events: u32) -> Watch {
        let (s, sock) = (state(), fd as usize);
        if s.pipes.contains_key(&(sock & !3)) || s.objects.contains_key(&sock) {
            diag(&format!("[poll] watch sock={sock:#x} is a pipe/object\n"));
            return Watch::Armed;
        }
        release(s, sock);
        let interest = interest(events);
        // SAFETY: the view never closes the socket: it ends in `into_raw_socket`.
        let stream = unsafe { std::net::TcpStream::from_raw_socket(sock as u64) };
        let mut view = TcpStream::from_std(stream);
        match s.poll.registry().register(&mut view, Token(sock), interest) {
            Ok(()) => {
                diag(&format!("[poll] watch sock={sock:#x} events={events} armed\n"));
                s.views.insert(sock, view);
                Watch::Armed
            }
            Err(e) => {
                diag(&format!("[poll] watch sock={sock:#x} events={events} register failed: {e}\n"));
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

    /// Whether `handle` is a pipe the poller adopted.
    pub fn pipe_adopted(handle: usize) -> bool {
        // SAFETY: only the scheduler thread reaches the poller state.
        unsafe { &*STATE.ptr() }
            .as_ref()
            .is_some_and(|s| s.pipes.contains_key(&handle))
    }

    /// Wakes the task waiting on `key` for reading, instead of the pipe's own reader and
    /// writer, whenever the adopted pipe `handle` becomes readable or writable; one task can
    /// then park on several pipes at once.
    pub fn pipe_group(handle: usize, key: usize) {
        let s = state();
        if s.pipes.contains_key(&handle) {
            s.groups.insert(handle, key);
        }
    }

    /// Deregisters and closes an adopted pipe.
    pub fn pipe_drop(handle: usize) {
        let s = state();
        s.groups.remove(&handle);
        if let Some(mut pipe) = s.pipes.remove(&handle) {
            let _ = s.poll.registry().deregister(&mut pipe);
        }
    }

    unsafe extern "system" fn signalled(context: *mut core::ffi::c_void, _: u8) {
        // SAFETY: the context is the box `object_watch` made, freed only after the wait is
        // unregistered, which waits for this callback.
        let done = unsafe { &*(context as *const Signalled) };
        done.signals
            .ready
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .push(done.object);
        let _ = done.signals.waker.wake();
    }

    /// Watches the waitable kernel object `handle` (a process): a task waiting on it for
    /// reading wakes once it is signalled. False when the wait cannot be registered.
    ///
    /// # Safety
    /// `handle` stays open until [`object_drop`].
    pub unsafe fn object_watch(handle: usize) -> bool {
        let s = state();
        if s.objects.contains_key(&handle) {
            return true;
        }
        let context = Box::into_raw(Box::new(Signalled {
            signals: s.signals.clone(),
            object: handle,
        }));
        // SAFETY: the caller keeps `handle` open until `object_drop`, which frees the context
        // after the wait is unregistered.
        let wait =
            unsafe { crate::sys::register_wait(handle as *mut _, signalled, context.cast()) };
        if wait.is_null() {
            // SAFETY: never handed to a wait.
            drop(unsafe { Box::from_raw(context) });
            return false;
        }
        s.objects.insert(handle, (wait as usize, context as usize));
        true
    }

    /// Ends the watch on `handle`; the caller may close it afterwards.
    pub fn object_drop(handle: usize) {
        // SAFETY: only the scheduler thread reaches the poller state.
        let Some(s) = (unsafe { &mut *STATE.ptr() }) else {
            return;
        };
        let Some((wait, context)) = s.objects.remove(&handle) else {
            return;
        };
        // SAFETY: registered by `object_watch` and removed from the map, so unregistered once;
        // that returns after a running callback, so the context is no longer used.
        unsafe {
            crate::sys::unregister_wait(wait as *mut _);
            drop(Box::from_raw(context as *mut Signalled));
        }
        s.signals
            .ready
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .retain(|&h| h != handle);
    }

    pub unsafe fn wait(_: i32, timeout_ns: i64, out: &mut [Ready; 64]) -> Option<usize> {
        let s = state();
        // The completion port waits in whole milliseconds, rounded up, and on the system tick
        // unless the process raised its resolution. A high-resolution timer wakes the wait at
        // the deadline; the poll timeout is only a bound.
        let timeout = (timeout_ns >= 0).then(|| Duration::from_nanos(timeout_ns as u64));
        let armed = match &s.timer {
            Some(t) if timeout_ns > 0 => {
                // SAFETY: the timer is open for as long as the state.
                unsafe { crate::sys::precise_timer_set(t.handle as *mut _, timeout_ns) };
                Some(t.handle)
            }
            _ => None,
        };
        let polled = s.poll.poll(&mut s.events, timeout);
        if let Some(handle) = armed {
            // SAFETY: as above. A wake for another reason must not leave a stale signal behind.
            unsafe { crate::sys::precise_timer_cancel(handle as *mut _) };
        }
        if polled.is_err() {
            fault::fault(b"I/O poller failed");
        }
        if std::env::var_os("MS_DIAG_POLL").is_some() {
            let toks: Vec<String> = s
                .events
                .iter()
                .map(|ev| format!("{:#x}:{:#x}", ev.token().0, bits(ev)))
                .collect();
            diag(&format!("[poll] wait timeout_ns={timeout_ns} events={toks:?}\n"));
        }
        let mut count = 0;
        let mut ready: Vec<(usize, u32)> = Vec::new();
        for ev in s.events.iter().filter(|ev| ev.token() != WAKE_TOKEN) {
            let (fd, bits) = (ev.token().0, bits(ev));
            if !s.pipes.contains_key(&fd) {
                ready.push((fd, bits));
                continue;
            }
            if let Some(&key) = s.groups.get(&fd) {
                out[count] = Ready {
                    fd: key,
                    bits: WAIT_READ,
                };
                count += 1;
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
        let signals = s.signals.clone();
        let mut objects = signals.ready.lock().unwrap_or_else(|e| e.into_inner());
        while count < out.len() {
            let Some(handle) = objects.pop() else { break };
            if s.objects.contains_key(&handle) {
                out[count] = Ready {
                    fd: handle,
                    bits: WAIT_READ,
                };
                count += 1;
            }
        }
        if !objects.is_empty() {
            // No room this round: the next wait returns at once for the rest.
            let _ = signals.waker.wake();
        }
        Some(count)
    }
}

pub use imp::{close, create, forget, kick, unwatch, wait, watch};
#[cfg(windows)]
pub use imp::{
    object_drop, object_watch, pipe_adopt, pipe_adopted, pipe_drop, pipe_group, pipe_read,
    pipe_write,
};
