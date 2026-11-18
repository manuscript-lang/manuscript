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
/// Windows Ctrl-Break; reported as SIGINT, like Ctrl-C.
#[cfg(windows)]
const SIGBREAK: i32 = 21;
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
    fn fcntl(fd: i32, cmd: i32, arg: i32) -> i32;
    #[cfg(unix)]
    fn waitid(idtype: i32, id: u32, info: *mut core::ffi::c_void, options: i32) -> i32;
}

#[cfg(windows)]
unsafe extern "system" {
    fn TerminateProcess(process: isize, code: u32) -> i32;
    fn WaitForSingleObject(handle: isize, millis: u32) -> u32;
}

#[cfg(unix)]
const F_SETFD: i32 = 2;
#[cfg(unix)]
const F_SETFL: i32 = 4;
#[cfg(unix)]
const FD_CLOEXEC: i32 = 1;
#[cfg(all(unix, target_os = "linux"))]
const O_NONBLOCK: i32 = 0o4000;
#[cfg(all(unix, not(target_os = "linux")))]
const O_NONBLOCK: i32 = 0x4;
/// `waitid`: wait for a process id, for its exit, leaving the exit status to be reaped later.
#[cfg(unix)]
const P_PID: i32 = 1;
#[cfg(unix)]
const WEXITED: i32 = 4;
#[cfg(all(unix, target_os = "linux"))]
const WNOWAIT: i32 = 0x0100_0000;
#[cfg(all(unix, not(target_os = "linux")))]
const WNOWAIT: i32 = 0x20;

/// What a supervised wait wakes for.
enum Event {
    /// The child ended (and is not yet reaped).
    Exited,
    /// SIGINT or SIGTERM arrived (its number).
    Signal(i32),
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
#[cfg(unix)]
static SIGNAL_PIPE: AtomicI32 = AtomicI32::new(-1);

fn hub() -> MutexGuard<'static, Vec<(usize, Sender<Event>)>> {
    HUB.lock().unwrap_or_else(|e| e.into_inner())
}

fn broadcast(signum: i32) {
    for (_, sender) in hub().iter() {
        let _ = sender.send(Event::Signal(signum));
    }
}

/// Forwards `signum` to the child with process id `pid`. Windows has no `kill`, so the child is
/// terminated through its handle instead.
fn send_signal(pid: u32, handle: isize, signum: i32) {
    #[cfg(unix)]
    {
        let _ = handle;
        // SAFETY: the pid belongs to a child of this process that has not been reaped: only the
        // supervising thread reaps it, after it has stopped sending.
        unsafe { kill(pid as i32, signum) };
    }
    #[cfg(windows)]
    {
        let _ = pid;
        // The status is 128 + signal, as on Unix, so an interrupt reads the same everywhere.
        // SAFETY: the handle belongs to a `Child` that stays alive until its wait returns.
        unsafe { TerminateProcess(handle, 128 + signum as u32) };
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
    #[cfg(windows)]
    let signum = if signum == SIGBREAK { SIGINT } else { signum };
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
    broadcast(signum);
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
    #[cfg(windows)]
    old_break: usize,
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
            open_signal_pipe();
            listeners.push((id, wake.clone()));
        }
        // SAFETY: `record` is async-signal-safe (an atomic store and a pipe write) and has the C
        // ABI `signal` expects; the previous disposition is restored on drop.
        unsafe {
            Stops {
                old_int: signal(SIGINT, record as *const () as usize),
                old_term: signal(SIGTERM, record as *const () as usize),
                #[cfg(windows)]
                old_break: signal(SIGBREAK, record as *const () as usize),
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

/// Opens, once for the process, the pipe the handler writes to and the thread that turns its
/// bytes into wakes. Both live as long as the process, so a handler never meets a closed
/// descriptor; both ends close on exec so a child does not hold them.
#[cfg(unix)]
fn open_signal_pipe() {
    static OPENED: std::sync::Once = std::sync::Once::new();
    OPENED.call_once(|| {
        let mut fds = [-1i32; 2];
        // SAFETY: `fds` holds the two descriptors `pipe` writes.
        if unsafe { pipe(fds.as_mut_ptr()) } != 0 {
            return;
        }
        for fd in fds {
            // SAFETY: plain `fcntl` on the descriptors just created; the write end must not
            // block a signal handler.
            unsafe {
                fcntl(fd, F_SETFD, FD_CLOEXEC);
            }
        }
        // SAFETY: as above.
        unsafe { fcntl(fds[1], F_SETFL, O_NONBLOCK) };
        SIGNAL_PIPE.store(fds[1], Ordering::SeqCst);
        let reader = fds[0];
        std::thread::spawn(move || {
            let mut byte = 0u8;
            loop {
                // SAFETY: `byte` is writable for one byte; the descriptor stays open for the
                // process.
                let n = unsafe { read(reader, (&raw mut byte).cast(), 1) };
                if n > 0 {
                    broadcast(i32::from(byte));
                } else if n == 0
                    || std::io::Error::last_os_error().kind() != std::io::ErrorKind::Interrupted
                {
                    break;
                }
            }
        });
    });
}

impl Drop for Stops {
    fn drop(&mut self) {
        let restore = |old: usize| if old == usize::MAX { SIG_DFL } else { old };
        // SAFETY: restoring the dispositions returned by the earlier calls.
        unsafe {
            signal(SIGINT, restore(self.old_int));
            signal(SIGTERM, restore(self.old_term));
            #[cfg(windows)]
            signal(SIGBREAK, restore(self.old_break));
        }
        hub().retain(|(id, _)| *id != self.id);
    }
}

/// What a drain pass found: whether the child must be killed as timed out, and when the next
/// pass is due (a deadline the caller computed from what it saw, such as a test's time limit).
#[derive(Default)]
pub struct Drained {
    pub kill: bool,
    pub next: Option<Instant>,
}

/// A pipe whose write end a child inherits and rings after each record it writes elsewhere (the
/// test harness's records file), so the supervising wait wakes when there is something to read.
/// The data stays in the file, which keeps records whole and in order; the pipe carries only
/// the wake.
pub struct Doorbell {
    reader: std::fs::File,
    writer: std::fs::File,
}

impl Doorbell {
    /// Opens the pipe. The read end is not inherited; the write end is, and `rings_as` names it.
    pub fn new() -> std::io::Result<Doorbell> {
        Doorbell::open()
    }

    /// The value for `MS_TEST_WAKE`: the write end's descriptor (Unix) or handle (Windows).
    pub fn rings_as(&self) -> String {
        #[cfg(unix)]
        {
            use std::os::fd::AsRawFd;
            self.writer.as_raw_fd().to_string()
        }
        #[cfg(windows)]
        {
            use std::os::windows::io::AsRawHandle;
            (self.writer.as_raw_handle() as usize).to_string()
        }
    }

    /// Call after spawning the child: closes this process's copy of the write end (so the pipe
    /// ends with the child) and wakes `wake` on every ring, from a thread that ends with it.
    pub fn listen(self, wake: Wake) {
        use std::io::Read;
        let Doorbell { mut reader, writer } = self;
        drop(writer);
        std::thread::spawn(move || {
            let mut buffer = [0u8; 256];
            while let Ok(n) = reader.read(&mut buffer) {
                if n == 0 {
                    break;
                }
                wake.output();
            }
        });
    }

    #[cfg(unix)]
    fn open() -> std::io::Result<Doorbell> {
        use std::os::fd::FromRawFd;
        let mut fds = [-1i32; 2];
        // SAFETY: `fds` holds the two descriptors `pipe` writes.
        if unsafe { pipe(fds.as_mut_ptr()) } != 0 {
            return Err(std::io::Error::last_os_error());
        }
        // SAFETY: the read end must not leak into other children; plain `fcntl`.
        unsafe { fcntl(fds[0], F_SETFD, FD_CLOEXEC) };
        // SAFETY: both descriptors were just created and belong to these files alone.
        let (reader, writer) = unsafe {
            (
                std::fs::File::from_raw_fd(fds[0]),
                std::fs::File::from_raw_fd(fds[1]),
            )
        };
        Ok(Doorbell { reader, writer })
    }

    #[cfg(windows)]
    fn open() -> std::io::Result<Doorbell> {
        use std::os::windows::io::FromRawHandle;
        #[repr(C)]
        struct SecurityAttributes {
            length: u32,
            descriptor: *mut core::ffi::c_void,
            inherit: i32,
        }
        unsafe extern "system" {
            fn CreatePipe(
                read: *mut isize,
                write: *mut isize,
                attributes: *const SecurityAttributes,
                size: u32,
            ) -> i32;
            fn SetHandleInformation(handle: isize, mask: u32, flags: u32) -> i32;
        }
        const HANDLE_FLAG_INHERIT: u32 = 1;
        let attributes = SecurityAttributes {
            length: core::mem::size_of::<SecurityAttributes>() as u32,
            descriptor: core::ptr::null_mut(),
            inherit: 1,
        };
        let (mut read, mut write) = (0isize, 0isize);
        // SAFETY: both out-pointers are valid; the attributes make both ends inheritable.
        if unsafe { CreatePipe(&mut read, &mut write, &attributes, 0) } == 0 {
            return Err(std::io::Error::last_os_error());
        }
        // SAFETY: the read end must not leak into other children.
        unsafe { SetHandleInformation(read, HANDLE_FLAG_INHERIT, 0) };
        // SAFETY: both handles were just created and belong to these files alone.
        let (reader, writer) = unsafe {
            (
                std::fs::File::from_raw_handle(read as *mut core::ffi::c_void),
                std::fs::File::from_raw_handle(write as *mut core::ffi::c_void),
            )
        };
        Ok(Doorbell { reader, writer })
    }
}

/// Wait for `child`, forwarding SIGINT and SIGTERM received meanwhile.
pub fn wait_with_signals(child: &mut Child, stops: &Stops) -> std::io::Result<ExitStatus> {
    wait_supervised(child, stops, None, &mut Drained::default).map(|waited| waited.status)
}

/// Wait for `child`, forwarding SIGINT and SIGTERM, killing it once `timeout` has elapsed, and
/// calling `drain` whenever a reader wakes the wait through `Stops::wake` and when the pass it
/// last returned said the next one was due.
///
/// The wait is an event wait: the child's exit, a signal and reader output each arrive on one
/// channel, and the only clocks are the deadline of `timeout` and the one `drain` asked for.
pub fn wait_supervised(
    child: &mut Child,
    stops: &Stops,
    timeout: Option<Duration>,
    drain: &mut dyn FnMut() -> Drained,
) -> std::io::Result<Waited> {
    let started = Instant::now();
    let (mut timed_out, mut interrupted) = (false, false);
    let mut last = None;
    let pid = child.id();
    let handle = child_handle(child);
    // The thread only learns that the child ended; this one reaps it, so until then the process
    // id is the child's and a signal sent to it cannot reach another process.
    let sender = stops.wake.clone();
    std::thread::spawn(move || {
        wait_for_exit(pid, handle);
        let _ = sender.send(Event::Exited);
    });
    // One pass at the start, so a caller can set its first deadline and take early output.
    let mut next_pass = Some(Instant::now());
    let result = loop {
        let deadline = [
            timeout.filter(|_| !timed_out).map(|limit| started + limit),
            next_pass,
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
            Ok(Event::Exited) => {
                break child.wait().map(|status| Waited {
                    status,
                    timed_out,
                    interrupted,
                });
            }
            Ok(Event::Signal(signum)) => {
                // The event carries the number: the process-wide pending slot may be taken by
                // another waiter, and each wait must forward what it was woken for.
                stops.take();
                interrupted = true;
                last = Some(signum);
                send_signal(pid, handle, signum);
            }
            Ok(Event::Output) | Err(RecvTimeoutError::Timeout) => {}
            Err(RecvTimeoutError::Disconnected) => {
                break Err(std::io::Error::other("supervision ended"));
            }
        }
        let late = !timed_out && timeout.is_some_and(|limit| started.elapsed() >= limit);
        // Draining goes on after a kill, so the last output is taken as it arrives.
        let passed = drain();
        next_pass = passed.next;
        if late || (passed.kill && !timed_out) {
            // A child that ended first keeps its own status.
            match child.try_wait() {
                Ok(Some(status)) => {
                    break Ok(Waited {
                        status,
                        timed_out,
                        interrupted,
                    });
                }
                Ok(None) => {}
                Err(error) => break Err(error),
            }
            timed_out = true;
            send_signal(pid, handle, SIGKILL);
        }
    };
    // Hand the signal back to the caller's `Stops` (and a surrounding one in the watch loops).
    if let Some(pending) = last {
        PENDING.store(pending, Ordering::SeqCst);
    }
    result
}

/// Blocks until the process ends, without reaping it.
#[cfg(unix)]
fn wait_for_exit(pid: u32, _handle: isize) {
    // `waitid` fills a `siginfo_t` (128 bytes at most on the platforms here); its contents
    // are not read.
    let mut info = [0u64; 32];
    loop {
        // SAFETY: `info` is writable and larger than a `siginfo_t`; waiting on a child's pid
        // with `WNOWAIT` leaves it to be reaped by its parent.
        let done = unsafe { waitid(P_PID, pid, info.as_mut_ptr().cast(), WEXITED | WNOWAIT) };
        if done == 0 || std::io::Error::last_os_error().kind() != std::io::ErrorKind::Interrupted {
            return;
        }
    }
}

/// Blocks until the process ends.
#[cfg(windows)]
fn wait_for_exit(_pid: u32, handle: isize) {
    // SAFETY: the handle belongs to a `Child` that its supervisor keeps until the exit is seen.
    unsafe { WaitForSingleObject(handle, u32::MAX) };
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
        let waited = wait_supervised(&mut child, &stops, None, &mut Drained::default).unwrap();
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
            &mut Drained::default,
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
        let waited = wait_supervised(&mut child, &stops, None, &mut || {
            while seen.try_recv().is_ok() {
                drained += 1;
            }
            Drained::default()
        })
        .unwrap();
        assert!(waited.status.success());
        // The first line arrives a second before the exit and no tick is due, so only its output
        // wake can have run a pass that found it; a wait that needs a tick would count zero. The
        // second line is written just before the exit, so the exit may be seen first and its
        // chunk is read after the wait: it counts whenever it arrives.
        assert!(drained >= 1, "no output wake ran a pass");
        for _ in drained..2 {
            // The reader ends when the pipe closes, so a missing line is an error, not a hang.
            seen.recv().expect("every line reaches the reader");
        }
    }

    #[test]
    fn a_drain_that_asks_for_it_kills_the_child() {
        let _turn = serial();
        let stops = Stops::catch();
        let mut child = sh("sleep 30");
        let waited = wait_supervised(&mut child, &stops, None, &mut || Drained {
            kill: true,
            next: None,
        })
        .unwrap();
        assert!(waited.timed_out);
    }

    #[test]
    fn a_signal_to_the_launcher_reaches_the_child() {
        let _turn = serial();
        let stops = Stops::catch();
        let mut child = sh("trap 'exit 7' INT; echo ready; while :; do sleep 0.05; done");
        // The shell is ready for the signal once it has printed: a signal sent earlier would
        // find its default disposition and end it.
        let mut ready = [0u8; 6];
        child
            .stdout
            .as_mut()
            .unwrap()
            .read_exact(&mut ready)
            .unwrap();
        // SAFETY: sends SIGINT to this process, whose disposition `Stops` replaced.
        unsafe { kill(std::process::id() as i32, SIGINT) };
        let waited = wait_supervised(&mut child, &stops, None, &mut Drained::default).unwrap();
        assert!(waited.interrupted);
        assert_eq!(waited.status.code(), Some(7));
    }

    #[test]
    fn a_ring_on_the_doorbell_wakes_the_wait() {
        let _turn = serial();
        let stops = Stops::catch();
        let bell = Doorbell::new().unwrap();
        let mut child = Command::new("/bin/sh")
            .args([
                "-c",
                "echo > /dev/fd/$MS_TEST_WAKE; sleep 1; echo > /dev/fd/$MS_TEST_WAKE",
            ])
            .env("MS_TEST_WAKE", bell.rings_as())
            .spawn()
            .unwrap();
        bell.listen(stops.wake());
        let mut passes = 0;
        let waited = wait_supervised(&mut child, &stops, None, &mut || {
            passes += 1;
            Drained::default()
        })
        .unwrap();
        assert!(waited.status.success(), "status {:?}", waited.status);
        // The pass at the start (which an early ring may share) and one for the ring a second
        // later: without the doorbell nothing else wakes this wait, and there would be one.
        assert!(passes >= 2, "passes: {passes}");
    }
}
