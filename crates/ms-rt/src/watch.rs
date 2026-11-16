//! The watcher: one thread that looks at the scheduler threads from outside.
//!
//! A task is not interrupted, so a thread that runs one task for a long time does none of its
//! other duties meanwhile. The watcher ticks while any thread is busy and runs the hooks other
//! crates register ([`add_hook`]), which do for a held-up thread what cannot wait: the HTTP
//! server's hook sends a resting thread to take the waiting connections of a held-up one.
//!
//! It looks every two milliseconds, or every [`TICK`] for a tenth of a second after a hook asked
//! for that, and sleeps when every thread has rested for [`QUIET_LOOKS`] looks; a thread that
//! leaves its rest wakes it ([`stir`]). It reads atomics only and never touches a task.

use crate::sched::{self, MAX_THREADS};
use core::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::Duration;

/// How often the watcher looks while a hook wants it to look often, and the unit of its clock.
pub const TICK: Duration = Duration::from_micros(100);
/// Ticks between looks otherwise (two milliseconds).
const SLOW: u64 = 20;
/// Ticks it keeps looking often after a hook last asked for it (a tenth of a second).
const OFTEN_FOR: u64 = 1_000;
/// Looks with every thread resting after which it sleeps until a thread stirs: long enough that
/// steady traffic does not wake it (a wake is a system call on the thread that leaves its rest),
/// short enough that a quiet server wakes nothing for long (40 ms).
const QUIET_LOOKS: u32 = 20;

/// The watcher's clock at one look, in ticks: `now`, and `last` at the look before. A thread
/// that copies [`epoch`] at each turn of a loop has not turned since before the last look when
/// its copy is below `last`, so for a whole interval between looks.
#[derive(Clone, Copy)]
pub struct Look {
    pub now: u64,
    pub last: u64,
}

/// Called at every look with the clock and the resting threads (bit `i` for scheduler thread
/// `i`, see `sched::resting_mask`). Answers whether the watcher should look often for a while.
pub type Hook = fn(Look, u64) -> bool;

static EPOCH: AtomicU64 = AtomicU64::new(0);
static ASLEEP: AtomicBool = AtomicBool::new(false);
/// For each scheduler thread, the tick at which it last left its rest.
static STIRRED: [AtomicU64; MAX_THREADS] = [const { AtomicU64::new(0) }; MAX_THREADS];
static HOOKS: Mutex<Vec<Hook>> = Mutex::new(Vec::new());
static WATCHER: OnceLock<std::thread::Thread> = OnceLock::new();

/// The watcher's clock as of its last look, in ticks (see [`Look`]).
#[inline]
pub fn epoch() -> u64 {
    EPOCH.load(Ordering::Relaxed)
}

/// Adds `hook` (once) and starts the watcher.
pub fn add_hook(hook: Hook) {
    let mut hooks = HOOKS.lock().unwrap_or_else(|e| e.into_inner());
    if !hooks.iter().any(|&h| core::ptr::fn_addr_eq(h, hook)) {
        hooks.push(hook);
    }
    drop(hooks);
    start();
}

/// The clock when scheduler thread `thread` last left its rest. A thread found busy has run
/// since before the last look when this is below [`Look::last`]; otherwise it may only just
/// have woken.
#[inline]
pub fn stirred(thread: usize) -> u64 {
    STIRRED[thread].load(Ordering::Relaxed)
}

/// Starts the watcher if it does not run yet.
pub fn start() {
    if WATCHER.get().is_some() {
        return;
    }
    WATCHER.get_or_init(|| {
        std::thread::Builder::new()
            .name("ms-watch".into())
            .spawn(run)
            .expect("watcher thread")
            .thread()
            .clone()
    });
}

/// Notes that scheduler thread `thread` leaves its rest, and wakes a sleeping watcher.
#[inline]
pub fn stir(thread: usize) {
    STIRRED[thread].store(epoch(), Ordering::Relaxed);
    if ASLEEP.load(Ordering::SeqCst) {
        wake();
    }
}

#[cold]
fn wake() {
    if ASLEEP.swap(false, Ordering::AcqRel)
        && let Some(watcher) = WATCHER.get()
    {
        watcher.unpark();
    }
}

fn run() {
    let (mut quiet, mut often_until) = (0u32, 0u64);
    loop {
        if ASLEEP.load(Ordering::Acquire) {
            std::thread::park();
            continue;
        }
        let last = epoch();
        let step = if last < often_until { 1 } else { SLOW };
        std::thread::sleep(TICK * step as u32);
        let look = Look {
            now: last + step,
            last,
        };
        EPOCH.store(look.now, Ordering::Relaxed);
        let resting = sched::resting_mask();
        // Hooks only read and post; none registers a hook, so the lock is not re-entered.
        for hook in HOOKS.lock().unwrap_or_else(|e| e.into_inner()).iter() {
            if hook(look, resting) {
                often_until = look.now + OFTEN_FOR;
            }
        }
        quiet = if all_rest(resting) { quiet + 1 } else { 0 };
        if quiet >= QUIET_LOOKS {
            quiet = 0;
            ASLEEP.store(true, Ordering::SeqCst);
            // A thread that left its rest just before the store saw the watcher awake and did
            // not wake it: look once more.
            if !all_rest(sched::resting_mask()) {
                ASLEEP.store(false, Ordering::SeqCst);
            }
        }
    }
}

/// Whether every started scheduler thread is in `resting`.
fn all_rest(resting: u64) -> bool {
    let threads = u64::MAX >> (64 - sched::started());
    resting & threads == threads
}

#[cfg(test)]
mod tests {
    use super::*;
    use core::sync::atomic::AtomicU32;

    static CALLS: AtomicU32 = AtomicU32::new(0);

    fn count(_: Look, _: u64) -> bool {
        CALLS.fetch_add(1, Ordering::Relaxed);
        false
    }

    #[test]
    fn a_hook_is_added_once_and_runs_while_the_watcher_is_awake() {
        add_hook(count);
        add_hook(count);
        assert_eq!(
            HOOKS
                .lock()
                .unwrap()
                .iter()
                .filter(|&&h| core::ptr::fn_addr_eq(h, count as Hook))
                .count(),
            1
        );
        // A thread that leaves its rest wakes a sleeping watcher, and the hook runs again.
        for _ in 0..5000 {
            stir(0);
            if CALLS.load(Ordering::Relaxed) >= 2 {
                break;
            }
            std::thread::sleep(Duration::from_millis(1));
        }
        assert!(CALLS.load(Ordering::Relaxed) >= 2);
        assert!(stirred(0) <= epoch());
    }
}
