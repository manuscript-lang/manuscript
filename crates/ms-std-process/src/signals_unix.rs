//! `watch_signals`: observers of operating-system signals.
//!
//! Each observer owns a non-blocking pipe. A process-wide handler (installed on a signal's first
//! observer and removed with its last) writes the signal number to the pipe of every observer of
//! that signal, then calls the handler that was installed before, so the runtime's SIGINT and
//! SIGTERM cancellation still runs. `next` waits for pipe data in short slices and polls for
//! cancellation between them.
use alloc::collections::VecDeque;
use core::sync::atomic::{AtomicI32, AtomicU64, AtomicUsize, Ordering};
use ms_rt_abi::{STATUS_CLOSED, STATUS_INVALID_INPUT, STATUS_LIMIT_EXCEEDED};
use ms_std_fs::err::{Fail, Res};
use ms_std_fs::sys;
use ms_std_rt::poll_cancel;

const SLOTS: usize = 32;
const MAX_SIGNAL: i64 = 64;
const MAX_CAPACITY: i64 = 1_048_576;
const DEFAULT_CAPACITY: i64 = 128;

static WRITE_FD: [AtomicI32; SLOTS] = [const { AtomicI32::new(-1) }; SLOTS];
static MASK: [AtomicU64; SLOTS] = [const { AtomicU64::new(0) }; SLOTS];
/// The handler in place before ours, per signal (`0` is `SIG_DFL`, `1` is `SIG_IGN`).
static PREVIOUS: [AtomicUsize; 65] = [const { AtomicUsize::new(0) }; 65];
static OBSERVERS: [AtomicUsize; 65] = [const { AtomicUsize::new(0) }; 65];

extern "C" fn on_signal(sig: i32) {
    let saved = sys::errno();
    let byte = sig as u8;
    let bit = 1u64 << (sig - 1);
    for i in 0..SLOTS {
        let fd = WRITE_FD[i].load(Ordering::Acquire);
        if fd >= 0 && MASK[i].load(Ordering::Acquire) & bit != 0 {
            // SAFETY: `write` is async-signal-safe; a full pipe drops the signal.
            unsafe { libc::write(fd, (&raw const byte).cast(), 1) };
        }
    }
    let prev = PREVIOUS[sig as usize].load(Ordering::Acquire);
    if prev > 1 {
        // SAFETY: the previous handler was a plain `fn(int)` registered with `sigaction`.
        let f: extern "C" fn(i32) =
            unsafe { core::mem::transmute::<usize, extern "C" fn(i32)>(prev) };
        f(sig);
    }
    sys::set_errno(saved);
}

fn install(sig: i32) -> Res<()> {
    // SAFETY: zeroed `sigaction` is a valid starting value.
    let mut act: libc::sigaction = unsafe { core::mem::zeroed() };
    act.sa_sigaction = on_signal as *const () as usize;
    act.sa_flags = libc::SA_RESTART;
    // SAFETY: zeroed `sigaction` is a valid out buffer.
    let mut old: libc::sigaction = unsafe { core::mem::zeroed() };
    // SAFETY: `act` is initialised and `old` writable.
    if unsafe { libc::sigaction(sig, &act, &mut old) } != 0 {
        return Err(Fail::raw(sys::errno()));
    }
    PREVIOUS[sig as usize].store(old.sa_sigaction, Ordering::Release);
    Ok(())
}

fn restore(sig: i32) {
    // SAFETY: zeroed `sigaction` with the saved handler.
    let mut act: libc::sigaction = unsafe { core::mem::zeroed() };
    act.sa_sigaction = PREVIOUS[sig as usize].load(Ordering::Acquire);
    // SAFETY: restoring the handler captured by `install`.
    unsafe { libc::sigaction(sig, &act, core::ptr::null_mut()) };
}

ms_std_core::abi_handle!(Watcher);

/// One `SignalStream`.
pub struct Watcher {
    read: i32,
    slot: usize,
    mask: u64,
    capacity: usize,
    queue: VecDeque<u8>,
    closed: bool,
}

impl Watcher {
    /// Observes `signals` (1..=64 except SIGKILL and SIGSTOP) buffering up to `capacity` signals.
    pub fn new(signals: &[i64], capacity: Option<i64>) -> Res<Watcher> {
        let capacity = capacity.unwrap_or(DEFAULT_CAPACITY);
        if signals.is_empty() || !(1..=MAX_CAPACITY).contains(&capacity) {
            return Err(Fail::invalid());
        }
        let mut mask = 0u64;
        for &s in signals {
            if !(1..=MAX_SIGNAL).contains(&s)
                || s == libc::SIGKILL as i64
                || s == libc::SIGSTOP as i64
            {
                return Err(Fail::status(STATUS_INVALID_INPUT));
            }
            mask |= 1 << (s - 1);
        }
        let mut fds = [0i32; 2];
        // SAFETY: `fds` holds the two descriptors `pipe_cloexec` writes.
        if unsafe { sys::pipe_cloexec(&mut fds, true) } != 0 {
            return Err(Fail::raw(sys::errno()));
        }
        let slot = (0..SLOTS).find(|&i| {
            WRITE_FD[i]
                .compare_exchange(-1, fds[1], Ordering::AcqRel, Ordering::Acquire)
                .is_ok()
        });
        let Some(slot) = slot else {
            // SAFETY: both descriptors were just created.
            unsafe {
                libc::close(fds[0]);
                libc::close(fds[1]);
            }
            return Err(Fail::status(STATUS_LIMIT_EXCEEDED));
        };
        // A larger pipe holds more buffered signals; failure keeps the default size.
        #[cfg(target_os = "linux")]
        // SAFETY: plain `fcntl` on the pipe just created.
        unsafe {
            libc::fcntl(fds[1], libc::F_SETPIPE_SZ, capacity.min(65536) as i32);
        }
        let mut installed: u64 = 0;
        for sig in 1..=MAX_SIGNAL as i32 {
            if mask & (1 << (sig - 1)) == 0 {
                continue;
            }
            if OBSERVERS[sig as usize].fetch_add(1, Ordering::AcqRel) == 0
                && let Err(e) = install(sig)
            {
                OBSERVERS[sig as usize].fetch_sub(1, Ordering::AcqRel);
                for done in 1..sig {
                    if installed & (1 << (done - 1)) != 0
                        && OBSERVERS[done as usize].fetch_sub(1, Ordering::AcqRel) == 1
                    {
                        restore(done);
                    }
                }
                WRITE_FD[slot].store(-1, Ordering::Release);
                // SAFETY: both descriptors are ours.
                unsafe {
                    libc::close(fds[0]);
                    libc::close(fds[1]);
                }
                return Err(e);
            }
            installed |= 1 << (sig - 1);
        }
        MASK[slot].store(mask, Ordering::Release);
        Ok(Watcher {
            read: fds[0],
            slot,
            mask,
            capacity: capacity as usize,
            queue: VecDeque::new(),
            closed: false,
        })
    }

    fn fill(&mut self) {
        let mut buf = [0u8; 256];
        loop {
            // SAFETY: `buf` is writable for its length.
            let n = unsafe { libc::read(self.read, buf.as_mut_ptr().cast(), buf.len()) };
            if n <= 0 {
                return;
            }
            for &b in &buf[..n as usize] {
                if self.queue.len() < self.capacity {
                    self.queue.push_back(b);
                }
            }
        }
    }

    /// The next observed signal number; `Closed` after `close`.
    pub fn wait(&mut self) -> Res<i64> {
        loop {
            if self.closed {
                return Err(Fail::status(STATUS_CLOSED));
            }
            self.fill();
            if let Some(b) = self.queue.pop_front() {
                return Ok(b as i64);
            }
            poll_cancel();
            let mut p = libc::pollfd {
                fd: self.read,
                events: libc::POLLIN,
                revents: 0,
            };
            // SAFETY: one valid `pollfd`.
            unsafe { libc::poll(&mut p, 1, 50) };
        }
    }

    pub fn close(&mut self) {
        if self.closed {
            return;
        }
        self.closed = true;
        MASK[self.slot].store(0, Ordering::Release);
        for sig in 1..=MAX_SIGNAL as i32 {
            if self.mask & (1 << (sig - 1)) != 0
                && OBSERVERS[sig as usize].fetch_sub(1, Ordering::AcqRel) == 1
            {
                restore(sig);
            }
        }
        let fd = WRITE_FD[self.slot].swap(-1, Ordering::AcqRel);
        // SAFETY: both descriptors belong to this watcher.
        unsafe {
            libc::close(fd);
            libc::close(self.read);
        }
    }
}

impl Drop for Watcher {
    fn drop(&mut self) {
        self.close();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn observes_buffers_and_closes() {
        assert_eq!(
            Watcher::new(&[], None).err().map(|f| f.status),
            Some(STATUS_INVALID_INPUT)
        );
        assert!(Watcher::new(&[9], None).is_err());
        assert!(Watcher::new(&[65], None).is_err());
        assert!(Watcher::new(&[10], Some(0)).is_err());
        let mut w = Watcher::new(&[libc::SIGUSR1 as i64, libc::SIGUSR2 as i64], Some(2)).unwrap();
        // SAFETY: the handler is installed for both signals.
        unsafe {
            libc::raise(libc::SIGUSR1);
            libc::raise(libc::SIGUSR2);
            libc::raise(libc::SIGUSR1);
        }
        assert_eq!(w.wait().unwrap(), libc::SIGUSR1 as i64);
        assert_eq!(w.wait().unwrap(), libc::SIGUSR2 as i64);
        w.close();
        w.close();
        assert_eq!(w.wait().unwrap_err().status, STATUS_CLOSED);
    }
}
