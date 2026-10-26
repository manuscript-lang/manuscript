//! Isolate identity and cross-thread wake-ups.
//!
//! Each isolate (one OS thread with its own arena and scheduler) has an [`Inbox`] in a
//! process-wide registry. A park token's id carries the owning isolate's registry slot, so a
//! post from any thread reaches the right scheduler and kicks only that isolate's poller.
use crate::fault::{Hdr, PublishedHdr};
use std::sync::atomic::{AtomicBool, AtomicU8, Ordering};
use std::sync::{Arc, Mutex};

/// Isolates addressable by a token id (12 bits).
pub const MAX_ISOLATES: usize = 1 << 12;
/// Bit position of the isolate slot in a token id.
pub const ID_SHIFT: u32 = 52;

/// Posts from other threads for one isolate, and the way to interrupt its blocked poller.
pub struct Inbox {
    posts: Mutex<Vec<(u64, u64)>>,
    /// Whether `posts` may hold entries; spares the scheduler the lock when nothing was posted.
    full: AtomicBool,
    wake: Mutex<Option<Box<dyn Fn() + Send + Sync>>>,
    /// A stop request aimed at this (worker) isolate; 0 when none.
    cancel: AtomicU8,
    /// The running task's header block, for a parent that cancels this isolate.
    cur: PublishedHdr,
    /// Whether this isolate is parked with only isolate-posted tokens pending (see [`enter_idle`]).
    /// Changed only with `IDLE` locked.
    idle: AtomicBool,
}

/// How many isolates run and how many of them are parked waiting for another isolate.
struct IdleCount {
    live: usize,
    idle: usize,
}

/// Guards `idle` flags with the counts, so a post and the poster's target agree on whether the
/// target is parked.
static IDLE: Mutex<IdleCount> = Mutex::new(IdleCount { live: 0, idle: 0 });
/// Set once every isolate waits on another and nothing can wake them; the main isolate faults.
static DEADLOCK: AtomicBool = AtomicBool::new(false);
static MAIN_INBOX: Mutex<Option<Arc<Inbox>>> = Mutex::new(None);

struct Slot {
    inbox: Option<Arc<Inbox>>,
    /// Token generations outlive an isolate so a late post cannot reach its replacement.
    token_generations: Vec<u32>,
}

static REGISTRY: Mutex<Vec<Slot>> = Mutex::new(Vec::new());

crate::isolate_static! {
    static CURRENT: Option<(usize, Arc<Inbox>)> = None;
    static MAIN: bool = false;
    static WORKER: bool = false;
}

/// Marks the calling isolate as a worker: the runtime's process-wide services (standard input
/// and output buffers, terminal state, exit hooks) belong to the main isolate, and the standard
/// allocator for Rust code leaves its arena alone.
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
    IDLE.lock().unwrap_or_else(|e| e.into_inner()).live += 1;
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
            full: AtomicBool::new(false),
            wake: Mutex::new(None),
            cancel: AtomicU8::new(0),
            cur: PublishedHdr::new(),
            idle: AtomicBool::new(false),
        });
        let mut reg = REGISTRY.lock().unwrap_or_else(|e| e.into_inner());
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
    *current().1.wake.lock().unwrap_or_else(|e| e.into_inner()) = wake;
}

/// Removes the calling isolate from the registry; later posts to its tokens are dropped.
pub fn unregister() {
    // SAFETY: this isolate's state.
    if let Some((slot, _)) = unsafe { (*CURRENT.ptr()).take() } {
        REGISTRY.lock().unwrap_or_else(|e| e.into_inner())[slot].inbox = None;
    }
}

/// Transfers the namespace's last generations to a newly initialized scheduler.
pub(crate) fn take_token_generations() -> Vec<u32> {
    let slot = id();
    let mut reg = REGISTRY.lock().unwrap_or_else(|e| e.into_inner());
    core::mem::take(&mut reg[slot].token_generations)
}

/// Retains only generation numbers when a scheduler ends; values and waiters are not retained.
pub(crate) fn save_token_generations(generations: Vec<u32>) {
    let slot = id();
    REGISTRY.lock().unwrap_or_else(|e| e.into_inner())[slot].token_generations = generations;
}

/// Queues a post for the token `id` on its isolate and interrupts that isolate's poller.
/// Callable from any thread; a post to an unregistered isolate is dropped.
pub fn post_remote(id: u64, value: u64) {
    let slot = (id >> ID_SHIFT) as usize;
    let inbox = {
        let reg = REGISTRY.lock().unwrap_or_else(|e| e.into_inner());
        match reg.get(slot).and_then(|slot| slot.inbox.as_ref()) {
            Some(i) => i.clone(),
            _ => return,
        }
    };
    // The target stops counting as parked before the post exists, so no check sees it parked
    // with a wake-up on its way.
    let mut idle = IDLE.lock().unwrap_or_else(|e| e.into_inner());
    if inbox.idle.swap(false, Ordering::Relaxed) {
        idle.idle -= 1;
    }
    inbox
        .posts
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .push((id, value));
    inbox.full.store(true, Ordering::Release);
    if let Some(wake) = &*inbox.wake.lock().unwrap_or_else(|e| e.into_inner()) {
        wake();
    }
}

/// Takes the posts queued for the calling isolate.
pub fn take_posts() -> Vec<(u64, u64)> {
    let (_, inbox) = current();
    // Switches check this even when all work is local. Avoid an unnecessary read-modify-write
    // on the common empty path; the swap still claims any observed pending batch.
    if !inbox.full.load(Ordering::Acquire) || !inbox.full.swap(false, Ordering::Acquire) {
        return Vec::new();
    }
    std::mem::take(&mut *inbox.posts.lock().unwrap_or_else(|e| e.into_inner()))
}

/// Drops queued posts (isolate teardown).
pub fn clear_posts() {
    let (_, inbox) = current();
    inbox.full.store(false, Ordering::Relaxed);
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
    let inbox = {
        let reg = REGISTRY.lock().unwrap_or_else(|e| e.into_inner());
        match reg.get(slot).and_then(|slot| slot.inbox.as_ref()) {
            Some(i) => i.clone(),
            _ => return,
        }
    };
    inbox.cancel.store(sig, Ordering::Relaxed);
    {
        let mut idle = IDLE.lock().unwrap_or_else(|e| e.into_inner());
        if inbox.idle.swap(false, Ordering::Relaxed) {
            idle.idle -= 1;
        }
    }
    inbox.cur.cancel(sig);
    if let Some(wake) = &*inbox.wake.lock().unwrap_or_else(|e| e.into_inner()) {
        wake();
    }
}

/// Counts a worker isolate before its thread starts, so the main isolate does not look alone
/// while the worker is still being set up.
pub fn count_worker() {
    IDLE.lock().unwrap_or_else(|e| e.into_inner()).live += 1;
}

/// Ends the count of a worker isolate (also when its thread never started). Its last posts
/// were made first, so a parked isolate is already awake by now; if the rest are all parked,
/// nothing is left to wake them.
pub fn retire_worker() {
    let mut idle = IDLE.lock().unwrap_or_else(|e| e.into_inner());
    idle.live -= 1;
    declare_if_stuck(&idle);
}

/// Flags a deadlock when every isolate is parked, and wakes the main isolate to report it. A
/// stop request in flight (a signal handler cannot take the lock) is not a deadlock.
fn declare_if_stuck(idle: &IdleCount) {
    if idle.live == 0 || idle.idle != idle.live {
        return;
    }
    if crate::fault::PENDING_SIGNAL.load(Ordering::Relaxed) != 0 {
        return;
    }
    DEADLOCK.store(true, Ordering::Release);
    let main = MAIN_INBOX.lock().unwrap_or_else(|e| e.into_inner()).clone();
    if let Some(main) = main
        && let Some(wake) = &*main.wake.lock().unwrap_or_else(|e| e.into_inner())
    {
        wake();
    }
}

/// Marks the calling isolate parked on tokens that only other isolates can post. Returns true
/// on the main isolate when every isolate is now parked, so the process is stuck. Not parked (false) when a post
/// already waits in the inbox.
pub fn enter_idle() -> bool {
    let (_, inbox) = current();
    let mut idle = IDLE.lock().unwrap_or_else(|e| e.into_inner());
    if inbox.full.load(Ordering::Acquire) {
        return false;
    }
    if !inbox.idle.swap(true, Ordering::Relaxed) {
        idle.idle += 1;
    }
    declare_if_stuck(&idle);
    take_deadlock(&mut idle, inbox)
}

/// Marks the calling isolate awake again. Returns true on the main isolate when a deadlock was
/// declared meanwhile.
pub fn leave_idle() -> bool {
    let (_, inbox) = current();
    let mut idle = IDLE.lock().unwrap_or_else(|e| e.into_inner());
    if inbox.idle.swap(false, Ordering::Relaxed) {
        idle.idle -= 1;
    }
    take_deadlock(&mut idle, inbox)
}

/// Whether the main isolate is to report the declared deadlock; it reports it once. The
/// reporting isolate stops counting as parked, since its cleanup may wait again.
fn take_deadlock(idle: &mut IdleCount, inbox: &Inbox) -> bool {
    if !is_main() || !DEADLOCK.swap(false, Ordering::AcqRel) {
        return false;
    }
    if inbox.idle.swap(false, Ordering::Relaxed) {
        idle.idle -= 1;
    }
    true
}
