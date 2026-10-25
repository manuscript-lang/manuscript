//! Isolate identity and cross-thread wake-ups.
//!
//! Each isolate (one OS thread with its own arena and scheduler) has an [`Inbox`] in a
//! process-wide registry. A park token's id carries the owning isolate's registry slot, so a
//! post from any thread reaches the right scheduler and kicks only that isolate's poller.
use crate::fault::Hdr;
use std::sync::atomic::{AtomicBool, AtomicPtr, AtomicU8, Ordering};
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
    cur: AtomicPtr<Hdr>,
}

static REGISTRY: Mutex<Vec<Option<Arc<Inbox>>>> = Mutex::new(Vec::new());

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
    unsafe { *MAIN.ptr() = true };
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
            cur: AtomicPtr::new(core::ptr::null_mut()),
        });
        let mut reg = REGISTRY.lock().unwrap_or_else(|e| e.into_inner());
        let slot = match reg.iter().position(Option::is_none) {
            Some(i) => i,
            None => {
                if reg.len() >= MAX_ISOLATES {
                    crate::fault::fatal(b"too many isolates");
                }
                reg.push(None);
                reg.len() - 1
            }
        };
        reg[slot] = Some(inbox.clone());
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
        REGISTRY.lock().unwrap_or_else(|e| e.into_inner())[slot] = None;
    }
}

/// Queues a post for the token `id` on its isolate and interrupts that isolate's poller.
/// Callable from any thread; a post to an unregistered isolate is dropped.
pub fn post_remote(id: u64, value: u64) {
    let slot = (id >> ID_SHIFT) as usize;
    let inbox = {
        let reg = REGISTRY.lock().unwrap_or_else(|e| e.into_inner());
        match reg.get(slot) {
            Some(Some(i)) => i.clone(),
            _ => return,
        }
    };
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
    if !inbox.full.swap(false, Ordering::Acquire) {
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
    current().1.cur.store(hdr, Ordering::Release);
}

/// Asks the isolate in registry slot `slot` to stop: raises the flag of its running task unless
/// shielded, remembers the request for its scheduler, and wakes its poller.
pub fn raise_cancel(slot: usize, sig: u8) {
    let inbox = {
        let reg = REGISTRY.lock().unwrap_or_else(|e| e.into_inner());
        match reg.get(slot) {
            Some(Some(i)) => i.clone(),
            _ => return,
        }
    };
    inbox.cancel.store(sig, Ordering::Relaxed);
    let hdr = inbox.cur.load(Ordering::Acquire);
    if !hdr.is_null() {
        // SAFETY: a task block outlives its stack's use; `shield` is read atomically.
        unsafe {
            if (*hdr).shield.load(Ordering::Relaxed) == 0 {
                (*hdr).cancel.store(sig, Ordering::Relaxed);
            }
        }
    }
    if let Some(wake) = &*inbox.wake.lock().unwrap_or_else(|e| e.into_inner()) {
        wake();
    }
}
