//! `watch_signals` on Windows: console control events delivered as the signals Go maps them to.
//!
//! Ctrl-C and Ctrl-Break are `SIGINT` (2); closing the console, logoff and shutdown are `SIGTERM`
//! (15). One process-wide handler (installed with the first observer and removed with the last)
//! counts each event for every observer of that signal, then returns `FALSE` so the handler that
//! was installed before (the runtime's cancellation) still runs.
use core::sync::atomic::{AtomicU32, AtomicUsize, Ordering};
use ms_rt_abi::{STATUS_CLOSED, STATUS_INVALID_INPUT, STATUS_LIMIT_EXCEEDED};
use ms_std_fs::err::{Fail, Res};
use ms_std_fs::sys;
use ms_std_rt::poll_cancel;
use windows_sys::Win32::System::Console::SetConsoleCtrlHandler;

const SLOTS: usize = 32;
const MAX_SIGNAL: i64 = 64;
const MAX_CAPACITY: i64 = 1_048_576;
const DEFAULT_CAPACITY: i64 = 128;
const SIGKILL: i64 = 9;
const SLICE_MS: i32 = 50;

/// Per observer slot, the signals it watches as a bit mask (`0` when the slot is free).
static MASK: [core::sync::atomic::AtomicU64; SLOTS] =
    [const { core::sync::atomic::AtomicU64::new(0) }; SLOTS];
/// Per observer slot and signal, how many events wait to be read.
static PENDING: [[AtomicU32; 16]; SLOTS] = [const { [const { AtomicU32::new(0) }; 16] }; SLOTS];
static OBSERVERS: AtomicUsize = AtomicUsize::new(0);

/// Only `SIGINT` and `SIGTERM` can arrive on Windows; they index `PENDING` as 0 and 1.
fn index(sig: i64) -> Option<usize> {
    match sig {
        2 => Some(0),
        15 => Some(1),
        _ => None,
    }
}

unsafe extern "system" fn on_event(kind: u32) -> i32 {
    let sig = match kind {
        0 | 1 => 2,
        2 | 5 | 6 => 15,
        _ => return 0,
    };
    let bit = 1u64 << (sig - 1);
    let at = index(sig).unwrap_or(0);
    for slot in 0..SLOTS {
        if MASK[slot].load(Ordering::Acquire) & bit != 0 {
            PENDING[slot][at].fetch_add(1, Ordering::AcqRel);
        }
    }
    0
}

ms_std_core::abi_handle!(Watcher);

/// One `SignalStream`.
pub struct Watcher {
    slot: usize,
    mask: u64,
    capacity: usize,
    queued: usize,
    closed: bool,
}

impl Watcher {
    /// Observes `signals` (1..=64 except SIGKILL) buffering up to `capacity` signals.
    pub fn new(signals: &[i64], capacity: Option<i64>) -> Res<Watcher> {
        let capacity = capacity.unwrap_or(DEFAULT_CAPACITY);
        if signals.is_empty() || !(1..=MAX_CAPACITY).contains(&capacity) {
            return Err(Fail::invalid());
        }
        let mut mask = 0u64;
        for &s in signals {
            if !(1..=MAX_SIGNAL).contains(&s) || s == SIGKILL {
                return Err(Fail::status(STATUS_INVALID_INPUT));
            }
            mask |= 1 << (s - 1);
        }
        let slot = (0..SLOTS).find(|&i| {
            MASK[i]
                .compare_exchange(0, mask, Ordering::AcqRel, Ordering::Acquire)
                .is_ok()
        });
        let Some(slot) = slot else {
            return Err(Fail::status(STATUS_LIMIT_EXCEEDED));
        };
        for counter in &PENDING[slot] {
            counter.store(0, Ordering::Release);
        }
        if OBSERVERS.fetch_add(1, Ordering::AcqRel) == 0 {
            // SAFETY: registers a handler with the documented signature.
            if unsafe { SetConsoleCtrlHandler(Some(on_event), 1) } == 0 {
                let e = sys::errno();
                OBSERVERS.fetch_sub(1, Ordering::AcqRel);
                MASK[slot].store(0, Ordering::Release);
                return Err(Fail::raw(e));
            }
        }
        Ok(Watcher {
            slot,
            mask,
            capacity: capacity as usize,
            queued: 0,
            closed: false,
        })
    }

    /// Takes one waiting event, `SIGINT` before `SIGTERM`.
    fn take(&mut self) -> Option<i64> {
        for sig in [2i64, 15] {
            if self.mask & (1 << (sig - 1)) == 0 {
                continue;
            }
            let counter = &PENDING[self.slot][index(sig).unwrap_or(0)];
            let mut n = counter.load(Ordering::Acquire);
            while n > 0 {
                match counter.compare_exchange(n, n - 1, Ordering::AcqRel, Ordering::Acquire) {
                    Ok(_) => return Some(sig),
                    Err(now) => n = now,
                }
            }
        }
        None
    }

    /// The next observed signal number; `Closed` after `close`.
    pub fn wait(&mut self) -> Res<i64> {
        loop {
            if self.closed {
                return Err(Fail::status(STATUS_CLOSED));
            }
            // Events beyond the buffer are dropped, as a full pipe drops them on Unix.
            self.queued = 0;
            for sig in [2usize, 15] {
                if let Some(at) = index(sig as i64) {
                    let counter = &PENDING[self.slot][at];
                    let n = counter.load(Ordering::Acquire) as usize;
                    self.queued += n;
                    if self.queued > self.capacity {
                        let excess = (self.queued - self.capacity).min(n) as u32;
                        counter.fetch_sub(excess, Ordering::AcqRel);
                        self.queued = self.capacity;
                    }
                }
            }
            if let Some(sig) = self.take() {
                return Ok(sig);
            }
            poll_cancel();
            ms_std_rt::task_sleep(i64::from(SLICE_MS) * 1_000_000);
        }
    }

    pub fn close(&mut self) {
        if self.closed {
            return;
        }
        self.closed = true;
        MASK[self.slot].store(0, Ordering::Release);
        if OBSERVERS.fetch_sub(1, Ordering::AcqRel) == 1 {
            // SAFETY: removes the handler installed with the first observer.
            unsafe { SetConsoleCtrlHandler(Some(on_event), 0) };
        }
    }
}

impl Drop for Watcher {
    fn drop(&mut self) {
        self.close();
    }
}
