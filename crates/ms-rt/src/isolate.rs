//! Isolate identity and cross-thread wake-ups.
//!
//! Each isolate (one OS thread with its own heap and scheduler) has an [`Inbox`] in a
//! process-wide registry. A park token's id carries the owning isolate's registry slot, so a
//! post from any thread reaches the right scheduler and kicks only that isolate's poller.
use crate::fault::{Hdr, PublishedHdr};
use std::sync::atomic::{AtomicBool, AtomicIsize, AtomicU8, AtomicUsize, Ordering, fence};
use std::sync::{Arc, Mutex, RwLock};

/// Isolates addressable by a token id (12 bits).
pub const MAX_ISOLATES: usize = 1 << 12;
/// Bit position of the isolate slot in a token id.
pub const ID_SHIFT: u32 = 52;

/// Posts from other threads for one isolate, and the way to interrupt its blocked poller.
pub struct Inbox {
    posts: Mutex<Vec<(u64, u64)>>,
    /// [`FULL`] while `posts` may hold entries (spares the scheduler the lock when nothing was
    /// posted), [`PARKED`] while the isolate counts as parked (see [`enter_idle`]). One word, so
    /// "parked unless a post waits" and "unparked by a post" are single atomic steps.
    state: AtomicU8,
    wake: RwLock<Option<Box<dyn Fn() + Send + Sync>>>,
    /// Whether the isolate is about to block in its poller, or blocks there: only then does a poster
    /// pay for the system call that interrupts it (see [`set_sleeping`]).
    sleeping: AtomicBool,
    /// A stop request aimed at this (worker) isolate; 0 when none.
    cancel: AtomicU8,
    /// The running task's header block, for a parent that cancels this isolate.
    cur: PublishedHdr,
}

const FULL: u8 = 1;
const PARKED: u8 = 2;

/// How many isolates run, and how many of them are parked waiting for another isolate. A flip of
/// an inbox's `PARKED` bit is followed by the matching step on `PARKED_COUNT`, which may therefore
/// dip below zero for a moment; a check that sees the two differ simply does not declare, and the
/// isolate that finishes the pair checks again.
static LIVE_COUNT: AtomicUsize = AtomicUsize::new(0);
static PARKED_COUNT: AtomicIsize = AtomicIsize::new(0);

/// Set once every isolate waits on another and nothing can wake them; the main isolate faults.
static DEADLOCK: AtomicBool = AtomicBool::new(false);
static MAIN_INBOX: Mutex<Option<Arc<Inbox>>> = Mutex::new(None);

struct Slot {
    inbox: Option<Arc<Inbox>>,
    /// Token generations outlive an isolate so a late post cannot reach its replacement.
    token_generations: Vec<u32>,
}

/// Read by every cross-thread post, written only when an isolate starts, ends or saves its token
/// generations.
static REGISTRY: RwLock<Vec<Slot>> = RwLock::new(Vec::new());

crate::isolate_static! {
    static CURRENT: Option<(usize, Arc<Inbox>)> = None;
    static MAIN: bool = false;
    static WORKER: bool = false;
}

/// Marks the calling isolate as a worker: the runtime's process-wide services (standard input
/// and output buffers, terminal state, exit hooks) belong to the main isolate.
pub fn mark_worker() {
    // SAFETY: this isolate's state.
    unsafe { *WORKER.ptr() = true };
}

/// Whether the calling isolate is a worker.
#[inline(always)]
pub fn is_worker() -> bool {
    // SAFETY: this isolate's state.
    unsafe { *WORKER.ptr() }
}

/// Marks the calling isolate as the main one, the target of signal-driven wake-ups.
pub fn set_main() {
    // SAFETY: this isolate's state.
    if unsafe { core::mem::replace(&mut *MAIN.ptr(), true) } {
        return;
    }
    *MAIN_INBOX.lock().unwrap_or_else(|e| e.into_inner()) = Some(current().1.clone());
    LIVE_COUNT.fetch_add(1, Ordering::SeqCst);
}

/// Whether signal handlers should wake the calling isolate's poller.
pub fn is_main() -> bool {
    // SAFETY: this isolate's state.
    unsafe { *MAIN.ptr() }
}

/// The calling isolate's registry slot, registering it on first use.
pub fn id() -> usize {
    current().0
}

fn current() -> &'static (usize, Arc<Inbox>) {
    // SAFETY: this isolate's state; the reference lasts until the isolate unregisters.
    let cur = unsafe { &mut *CURRENT.ptr() };
    cur.get_or_insert_with(|| {
        let inbox = Arc::new(Inbox {
            posts: Mutex::new(Vec::new()),
            state: AtomicU8::new(0),
            wake: RwLock::new(None),
            sleeping: AtomicBool::new(false),
            cancel: AtomicU8::new(0),
            cur: PublishedHdr::new(),
        });
        let mut reg = REGISTRY.write().unwrap_or_else(|e| e.into_inner());
        let slot = match reg.iter().position(|slot| slot.inbox.is_none()) {
            Some(i) => i,
            None => {
                if reg.len() >= MAX_ISOLATES {
                    crate::fault::fatal(b"too many isolates");
                }
                reg.push(Slot {
                    inbox: None,
                    token_generations: Vec::new(),
                });
                reg.len() - 1
            }
        };
        reg[slot].inbox = Some(inbox.clone());
        (slot, inbox)
    })
}

/// Sets how to interrupt this isolate's poller; `None` when it closes.
pub fn set_wake(wake: Option<Box<dyn Fn() + Send + Sync>>) {
    *current().1.wake.write().unwrap_or_else(|e| e.into_inner()) = wake;
}

/// Removes the calling isolate from the registry; later posts to its tokens are dropped.
pub fn unregister() {
    // SAFETY: this isolate's state.
    if let Some((slot, _)) = unsafe { (*CURRENT.ptr()).take() } {
        REGISTRY.write().unwrap_or_else(|e| e.into_inner())[slot].inbox = None;
    }
}

/// Transfers the namespace's last generations to a newly initialized scheduler.
pub(crate) fn take_token_generations() -> Vec<u32> {
    let slot = id();
    let mut reg = REGISTRY.write().unwrap_or_else(|e| e.into_inner());
    core::mem::take(&mut reg[slot].token_generations)
}

/// Retains only generation numbers when a scheduler ends; values and waiters are not retained.
pub(crate) fn save_token_generations(generations: Vec<u32>) {
    let slot = id();
    REGISTRY.write().unwrap_or_else(|e| e.into_inner())[slot].token_generations = generations;
}

/// The inbox registered in `slot`, if any. Cloned out of the registry so the caller holds no lock.
fn lookup(slot: usize) -> Option<Arc<Inbox>> {
    let reg = REGISTRY.read().unwrap_or_else(|e| e.into_inner());
    reg.get(slot)?.inbox.clone()
}

/// Stops `inbox` counting as parked, if it did.
fn unpark(inbox: &Inbox) {
    if inbox.state.load(Ordering::SeqCst) & PARKED != 0
        && inbox.state.fetch_and(!PARKED, Ordering::SeqCst) & PARKED != 0
    {
        PARKED_COUNT.fetch_sub(1, Ordering::SeqCst);
    }
}

/// Interrupts the poller of `inbox` if its isolate sleeps or is about to; a running isolate looks
/// at its work before it sleeps, so it needs no system call. The caller has published its work.
fn wake_if_sleeping(inbox: &Inbox) {
    fence(Ordering::SeqCst);
    if inbox.sleeping.load(Ordering::SeqCst) {
        wake(inbox);
    }
}

/// Interrupts the poller of `inbox`, asleep or not.
fn wake(inbox: &Inbox) {
    if let Some(wake) = &*inbox.wake.read().unwrap_or_else(|e| e.into_inner()) {
        wake();
    }
}

/// Says the calling isolate is about to block in its poller (`true`) or has left it. After setting
/// it the isolate must look once more for work before it blocks: a poster that saw it awake did
/// not interrupt it. Only the poller sleeps on the wake-up, so only its callers set this.
pub fn set_sleeping(on: bool) {
    let (_, inbox) = current();
    inbox.sleeping.store(on, Ordering::SeqCst);
}

/// Queues a post for the token `id` on its isolate and interrupts that isolate's poller.
/// Callable from any thread; a post to an unregistered isolate is dropped.
pub fn post_remote(id: u64, value: u64) {
    let Some(inbox) = lookup((id >> ID_SHIFT) as usize) else {
        return;
    };
    inbox
        .posts
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .push((id, value));
    // One step marks the post and ends any parked state, so an isolate cannot park after this
    // without seeing the post, nor stay counted as parked with the post on its way.
    let before = inbox.state.fetch_or(FULL, Ordering::SeqCst);
    if before & PARKED != 0 {
        unpark(&inbox);
    }
    wake_if_sleeping(&inbox);
}

/// Interrupts the poller of the isolate in registry slot `slot` so it looks at its mail.
/// Callable from any thread; an unregistered slot is ignored.
pub fn kick(slot: usize) {
    let Some(inbox) = lookup(slot) else {
        return;
    };
    unpark(&inbox);
    wake_if_sleeping(&inbox);
}

/// Whether posts wait for the calling isolate.
pub fn has_posts() -> bool {
    let (_, inbox) = current();
    inbox.state.load(Ordering::SeqCst) & FULL != 0
}

/// Takes the posts queued for the calling isolate.
pub fn take_posts() -> Vec<(u64, u64)> {
    let (_, inbox) = current();
    // Switches check this even when all work is local. Avoid an unnecessary read-modify-write
    // on the common empty path; the swap still claims any observed pending batch.
    if inbox.state.load(Ordering::Acquire) & FULL == 0
        || inbox.state.fetch_and(!FULL, Ordering::Acquire) & FULL == 0
    {
        return Vec::new();
    }
    std::mem::take(&mut *inbox.posts.lock().unwrap_or_else(|e| e.into_inner()))
}

/// Drops queued posts (isolate teardown).
pub fn clear_posts() {
    let (_, inbox) = current();
    inbox.state.fetch_and(!FULL, Ordering::Relaxed);
    inbox
        .posts
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .clear();
}

/// The stop request pending for the calling isolate: the process-wide signal on the main
/// isolate, the parent's request on a worker.
pub fn pending_cancel() -> u8 {
    if is_main() {
        return crate::fault::PENDING_SIGNAL.load(Ordering::Relaxed);
    }
    current().1.cancel.load(Ordering::Relaxed)
}

/// Records the running task's block so a cancel aimed at this isolate can reach its flag.
pub fn publish_hdr(hdr: *mut Hdr) {
    current().1.cur.publish(hdr);
}

/// Asks the isolate in registry slot `slot` to stop: raises the flag of its running task unless
/// shielded, remembers the request for its scheduler, and wakes its poller.
pub fn raise_cancel(slot: usize, sig: u8) {
    let Some(inbox) = lookup(slot) else {
        return;
    };
    inbox.cancel.store(sig, Ordering::SeqCst);
    unpark(&inbox);
    inbox.cur.cancel(sig);
    wake_if_sleeping(&inbox);
}

/// Counts a worker isolate before its thread starts, so the main isolate does not look alone
/// while the worker is still being set up.
pub fn count_worker() {
    LIVE_COUNT.fetch_add(1, Ordering::SeqCst);
}

/// Ends the count of a worker isolate (also when its thread never started). Its last posts
/// were made first, so a parked isolate is already awake by now; if the rest are all parked,
/// nothing is left to wake them.
pub fn retire_worker() {
    LIVE_COUNT.fetch_sub(1, Ordering::SeqCst);
    declare_if_stuck();
}

/// Flags a deadlock when every isolate is parked, and wakes the main isolate to report it. A
/// stop request in flight (a signal handler cannot take the lock) is not a deadlock.
fn declare_if_stuck() {
    let live = LIVE_COUNT.load(Ordering::SeqCst);
    if live == 0 || PARKED_COUNT.load(Ordering::SeqCst) != live as isize {
        return;
    }
    if crate::fault::PENDING_SIGNAL.load(Ordering::Relaxed) != 0 {
        return;
    }
    DEADLOCK.store(true, Ordering::Release);
    let main = MAIN_INBOX.lock().unwrap_or_else(|e| e.into_inner()).clone();
    if let Some(main) = main {
        wake(&main);
    }
}

/// Marks the calling isolate parked on tokens that only other isolates can post. Returns true
/// on the main isolate when every isolate is now parked, so the process is stuck. Not parked (false) when a post
/// already waits in the inbox.
///
/// The isolate parks only if no post waits, in one step; a poster marks its post and unparks in
/// one step, so a post and a park never miss each other.
pub fn enter_idle() -> bool {
    let (_, inbox) = current();
    let parked = inbox
        .state
        .try_update(Ordering::SeqCst, Ordering::SeqCst, |s| {
            (s & FULL == 0).then_some(s | PARKED)
        });
    match parked {
        Err(_) => return false,
        Ok(before) if before & PARKED == 0 => {
            PARKED_COUNT.fetch_add(1, Ordering::SeqCst);
        }
        Ok(_) => {}
    }
    declare_if_stuck();
    take_deadlock(inbox)
}

/// Marks the calling isolate awake again. Returns true on the main isolate when a deadlock was
/// declared meanwhile.
pub fn leave_idle() -> bool {
    let (_, inbox) = current();
    unpark(inbox);
    take_deadlock(inbox)
}

/// Whether the main isolate is to report the declared deadlock; it reports it once. The
/// reporting isolate stops counting as parked, since its cleanup may wait again.
fn take_deadlock(inbox: &Inbox) -> bool {
    if !is_main() || !DEADLOCK.swap(false, Ordering::AcqRel) {
        return false;
    }
    unpark(inbox);
    true
}
