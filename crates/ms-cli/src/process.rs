//! Child processes under signal forwarding.
//!
//! `ms` stays alive until the native program completes
//! its own cancellation and cleanup: SIGINT and SIGTERM sent to `ms` are
//! forwarded to the child instead of killing the launcher on Unix. Windows has no POSIX
//! `kill`: an interrupted child is force-stopped through its handle, without a cleanup guarantee.

// The only FFI in the CLI: std has no signal API, so `signal`/`kill` come from libc.
#![allow(unsafe_code)]

use std::process::{Child, ExitStatus};
use std::sync::atomic::{AtomicI32, Ordering};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender};
use std::sync::{Mutex, MutexGuard};
use std::time::{Duration, Instant};

const SIGINT: i32 = 2;
const SIGTERM: i32 = 15;
const SIGKILL: i32 = 9;
const SIG_DFL: usize = 0;

unsafe extern "C" {
    fn signal(signum: i32, handler: usize) -> usize;
    #[cfg(unix)]
    fn kill(pid: i32, signum: i32) -> i32;
    #[cfg(unix)]
    fn pipe(fds: *mut i32) -> i32;
    #[cfg(unix)]
    fn read(fd: i32, buf: *mut core::ffi::c_void, len: usize) -> isize;
    #[cfg(unix)]
    fn write(fd: i32, buf: *const core::ffi::c_void, len: usize) -> isize;
    #[cfg(unix)]
    fn close(fd: i32) -> i32;
}

#[cfg(windows)]
unsafe extern "system" {
    fn TerminateProcess(process: isize, code: u32) -> i32;
}

/// What a supervised wait wakes for.
enum Event {
    /// The child ended.
    Exited(std::io::Result<ExitStatus>),
    /// SIGINT or SIGTERM arrived.
    Signal,
    /// A reader thread has output waiting.
    Output,
}

/// Wakes a supervised wait when output is ready; one per reader thread.
#[derive(Clone)]
pub struct Wake(Sender<Event>);

impl Wake {
    pub fn output(&self) {
        let _ = self.0.send(Event::Output);
    }
}

/// Every live `Stops` listens here: a signal reaches each of their waits.
static HUB: Mutex<Vec<(usize, Sender<Event>)>> = Mutex::new(Vec::new());
/// The write end of the pipe the Unix signal handler writes to (-1 when none is open).
static SIGNAL_PIPE: AtomicI32 = AtomicI32::new(-1);

fn hub() -> MutexGuard<'static, Vec<(usize, Sender<Event>)>> {
    HUB.lock().unwrap_or_else(|e| e.into_inner())
}

fn broadcast() {
    for (_, sender) in hub().iter() {
        let _ = sender.send(Event::Signal);
    }
}

/// Forwards `signum` to the child with process id `pid`. Windows has no `kill`, so the child is
/// terminated through its handle instead.
fn send_signal(pid: u32, handle: isize, signum: i32) {
    #[cfg(unix)]
    {
        let _ = handle;
        // SAFETY: the pid belongs to a child of this process that has not been reaped (its waiter
        // reports the exit only after this loop stops sending).
        unsafe { kill(pid as i32, signum) };
    }
    #[cfg(windows)]
    {
        let _ = (pid, signum);
        // SAFETY: the handle belongs to a `Child` that stays alive until its wait returns.
        unsafe { TerminateProcess(handle, 1) };
    }
}

#[cfg(unix)]
fn child_handle(_: &Child) -> isize {
    0
}

#[cfg(windows)]
fn child_handle(child: &Child) -> isize {
    use std::os::windows::io::AsRawHandle;
    child.as_raw_handle() as isize
}

static PENDING: AtomicI32 = AtomicI32::new(0);

extern "C" fn record(signum: i32) {
    PENDING.store(signum, Ordering::SeqCst);
    #[cfg(unix)]
    {
        let fd = SIGNAL_PIPE.load(Ordering::SeqCst);
        if fd >= 0 {
            // SAFETY: `write` is async-signal-safe; a failed or short write only loses the wake,
            // and the pending signal is still taken at the next event.
            unsafe { write(fd, [signum as u8].as_ptr().cast(), 1) };
        }
    }
    // On Windows the handler runs on a thread of its own, where locking is allowed.
    #[cfg(not(unix))]
    broadcast();
}

/// How a supervised child ended.
pub struct Waited {
    pub status: ExitStatus,
    /// The deadline passed and the child was killed.
    pub timed_out: bool,
    /// SIGINT or SIGTERM arrived while waiting (forwarded on Unix; force-stop on Windows).
    pub interrupted: bool,
}

/// SIGINT and SIGTERM are recorded instead of killing `ms` while this lives;
/// the previous dispositions return on drop. Catch before spawning the child: a signal sent as
/// soon as the child reports ready must not find the launcher still on the default disposition.
pub struct Stops {
    old_int: usize,
    old_term: usize,
    id: usize,
    wake: Sender<Event>,
    events: Receiver<Event>,
}

static NEXT_ID: AtomicI32 = AtomicI32::new(1);

impl Stops {
    pub fn catch() -> Stops {
        PENDING.store(0, Ordering::SeqCst);
        let (wake, events) = mpsc::channel();
        let id = NEXT_ID.fetch_add(1, Ordering::SeqCst) as usize;
        {
            let mut listeners = hub();
            #[cfg(unix)]
            if listeners.is_empty() {
                open_signal_pipe();
            }
            listeners.push((id, wake.clone()));
        }
        // SAFETY: `record` is async-signal-safe (an atomic store and a pipe write) and has the C
        // ABI `signal` expects; the previous disposition is restored on drop.
        unsafe {
            Stops {
                old_int: signal(SIGINT, record as *const () as usize),
                old_term: signal(SIGTERM, record as *const () as usize),
                id,
                wake,
                events,
            }
        }
    }

    /// The signal that arrived since the last call, if any.
    pub fn take(&self) -> Option<i32> {
        Some(PENDING.swap(0, Ordering::SeqCst)).filter(|&signum| signum != 0)
    }

    /// A handle for reader threads to wake the wait when they have output.
    pub fn wake(&self) -> Wake {
        Wake(self.wake.clone())
    }
}

/// Opens the pipe the handler writes to and the thread that turns its bytes into wakes; the
/// thread ends, closing the read end, when the last `Stops` drops and the write end closes.
#[cfg(unix)]
fn open_signal_pipe() {
    let mut fds = [-1i32; 2];
    // SAFETY: `fds` holds the two descriptors `pipe` writes.
    if unsafe { pipe(fds.as_mut_ptr()) } != 0 {
        return;
    }
    SIGNAL_PIPE.store(fds[1], Ordering::SeqCst);
    let reader = fds[0];
    std::thread::spawn(move || {
        let mut byte = 0u8;
        // SAFETY: `byte` is writable for one byte; the descriptor is this thread's own.
        while unsafe { read(reader, (&raw mut byte).cast(), 1) } > 0 {
            broadcast();
        }
        // SAFETY: the read end belongs to this thread.
        unsafe { close(reader) };
    });
}

impl Drop for Stops {
    fn drop(&mut self) {
        let restore = |old: usize| if old == usize::MAX { SIG_DFL } else { old };
        // SAFETY: restoring the dispositions returned by the earlier calls.
        unsafe {
            signal(SIGINT, restore(self.old_int));
            signal(SIGTERM, restore(self.old_term));
        }
        let mut listeners = hub();
        listeners.retain(|(id, _)| *id != self.id);
        #[cfg(unix)]
        if listeners.is_empty() {
            let fd = SIGNAL_PIPE.swap(-1, Ordering::SeqCst);
            if fd >= 0 {
                // SAFETY: the write end was opened by `open_signal_pipe` and no handler uses it now.
                unsafe { close(fd) };
            }
        }
    }
}

/// Wait for `child`, forwarding SIGINT and SIGTERM received meanwhile.
pub fn wait_with_signals(child: &mut Child, stops: &Stops) -> std::io::Result<ExitStatus> {
    wait_supervised(child, stops, None, None, &mut || false).map(|waited| waited.status)
}

/// Wait for `child`, forwarding SIGINT and SIGTERM, killing it once `timeout` has elapsed, and
/// calling `drain` (true kills the child as timed out) whenever a reader wakes the wait through
/// `Stops::wake` and, for callers whose input has no wake, every `poll_every`.
///
/// The wait is an event wait: the child's exit, a signal and reader output each arrive on one
/// channel, and the only clock is the deadline of `timeout` and, when given, `poll_every`.
pub fn wait_supervised(
    child: &mut Child,
    stops: &Stops,
    timeout: Option<Duration>,
    poll_every: Option<Duration>,
    drain: &mut dyn FnMut() -> bool,
) -> std::io::Result<Waited> {
    let started = Instant::now();
    let (mut timed_out, mut interrupted) = (false, false);
    let mut last = None;
    let pid = child.id();
    let handle = child_handle(child);
    let sender = stops.wake.clone();
    let result = std::thread::scope(|scope| {
        scope.spawn(move || {
            let _ = sender.send(Event::Exited(child.wait()));
        });
        let mut next_poll = poll_every.map(|every| Instant::now() + every);
        loop {
            let deadline = [
                timeout.filter(|_| !timed_out).map(|limit| started + limit),
                next_poll,
            ]
            .into_iter()
            .flatten()
            .min();
            let event = match deadline {
                Some(at) => stops
                    .events
                    .recv_timeout(at.saturating_duration_since(Instant::now())),
                None => stops
                    .events
                    .recv()
                    .map_err(|_| RecvTimeoutError::Disconnected),
            };
            match event {
                Ok(Event::Exited(Ok(status))) => {
                    break Ok(Waited {
                        status,
                        timed_out,
                        interrupted,
                    });
                }
                Ok(Event::Exited(Err(error))) => break Err(error),
                Ok(Event::Signal) => {
                    if let Some(pending) = stops.take() {
                        interrupted = true;
                        last = Some(pending);
                        send_signal(pid, handle, pending);
                    }
                }
                Ok(Event::Output) | Err(RecvTimeoutError::Timeout) => {}
                Err(RecvTimeoutError::Disconnected) => {
                    break Err(std::io::Error::other("supervision ended"));
                }
            }
            if !timed_out && timeout.is_some_and(|limit| started.elapsed() >= limit) {
                timed_out = true;
                send_signal(pid, handle, SIGKILL);
            }
            let polled = next_poll.is_some_and(|at| Instant::now() >= at);
            if polled {
                next_poll = poll_every.map(|every| Instant::now() + every);
            }
            if drain() && !timed_out {
                timed_out = true;
                send_signal(pid, handle, SIGKILL);
            }
        }
    });
    // Hand the signal back to the caller's `Stops` (and a surrounding one in the watch loops).
    if let Some(pending) = last {
        PENDING.store(pending, Ordering::SeqCst);
    }
    result
}

/// Ask `child` to stop the way Ctrl-C does, so it can cancel and clean up.
pub fn interrupt(child: &mut Child) {
    send_signal(child.id(), child_handle(child), SIGINT);
}

/// The exit status as a process status: the code, or 128 + signal (the shell convention).
pub fn exit_code(status: ExitStatus) -> i32 {
    #[cfg(unix)]
    {
        use std::os::unix::process::ExitStatusExt;
        status
            .code()
            .or_else(|| status.signal().map(|s| 128 + s))
            .unwrap_or(255)
    }
    #[cfg(not(unix))]
    {
        status.code().unwrap_or(255)
    }
}

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use std::io::Read;
    use std::process::{Command, Stdio};

    /// Signals are process-wide, so these tests take turns.
    static SERIAL: Mutex<()> = Mutex::new(());

    fn serial() -> MutexGuard<'static, ()> {
        SERIAL.lock().unwrap_or_else(|e| e.into_inner())
    }

    fn sh(script: &str) -> Child {
        Command::new("/bin/sh")
            .args(["-c", script])
            .stdout(Stdio::piped())
            .spawn()
            .expect("spawn sh")
    }

    #[test]
    fn a_quick_exit_is_seen_at_once() {
        let _turn = serial();
        let stops = Stops::catch();
        let mut child = sh("exit 3");
        let started = Instant::now();
        let waited = wait_supervised(&mut child, &stops, None, None, &mut || false).unwrap();
        assert_eq!(waited.status.code(), Some(3));
        assert!(!waited.timed_out && !waited.interrupted);
        assert!(started.elapsed() < Duration::from_secs(5));
    }

    #[test]
    fn the_deadline_kills_the_child() {
        let _turn = serial();
        let stops = Stops::catch();
        let mut child = sh("sleep 30");
        let started = Instant::now();
        let waited = wait_supervised(
            &mut child,
            &stops,
            Some(Duration::from_millis(200)),
            None,
            &mut || false,
        )
        .unwrap();
        assert!(waited.timed_out);
        assert!(started.elapsed() < Duration::from_secs(10));
    }

    #[test]
    fn output_wakes_the_wait_without_a_tick() {
        let _turn = serial();
        let stops = Stops::catch();
        let mut child = sh("echo one; sleep 1; echo two");
        let mut pipe = child.stdout.take().unwrap();
        let wake = stops.wake();
        let (chunks, seen) = mpsc::channel();
        std::thread::spawn(move || {
            let mut buf = [0u8; 64];
            while let Ok(n) = pipe.read(&mut buf) {
                if n == 0 {
                    break;
                }
                let _ = chunks.send(buf[..n].to_vec());
                wake.output();
            }
        });
        let mut drained = 0;
        let waited = wait_supervised(&mut child, &stops, None, None, &mut || {
            while seen.try_recv().is_ok() {
                drained += 1;
            }
            false
        })
        .unwrap();
        assert!(waited.status.success());
        // Each line woke the wait once; a draining pass that found nothing would count zero.
        assert_eq!(drained, 2);
    }

    #[test]
    fn a_drain_that_asks_for_it_kills_the_child() {
        let _turn = serial();
        let stops = Stops::catch();
        let mut child = sh("sleep 30");
        let waited = wait_supervised(
            &mut child,
            &stops,
            None,
            Some(Duration::from_millis(20)),
            &mut || true,
        )
        .unwrap();
        assert!(waited.timed_out);
    }

    #[test]
    fn a_signal_to_the_launcher_reaches_the_child() {
        let _turn = serial();
        let stops = Stops::catch();
        let mut child = sh("trap 'exit 7' INT; while :; do sleep 0.05; done");
        let pid = std::process::id() as i32;
        std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(300));
            // SAFETY: sends SIGINT to this process, whose disposition `Stops` replaced.
            unsafe { kill(pid, SIGINT) };
        });
        let waited = wait_supervised(&mut child, &stops, None, None, &mut || false).unwrap();
        assert!(waited.interrupted);
        assert_eq!(waited.status.code(), Some(7));
    }
}
