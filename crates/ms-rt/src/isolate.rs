//! Isolate identity and cross-thread wake-ups.
//!
//! Each isolate (one OS thread with its own arena and scheduler) has an [`Inbox`] in a
//! process-wide registry. A park token's id carries the owning isolate's registry slot, so a
//! post from any thread reaches the right scheduler and kicks only that isolate's poller.
use std::sync::atomic::{AtomicBool, Ordering};
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
}

static REGISTRY: Mutex<Vec<Option<Arc<Inbox>>>> = Mutex::new(Vec::new());

crate::isolate_static! {
    static CURRENT: Option<(usize, Arc<Inbox>)> = None;
    static MAIN: bool = false;
}

/// Marks the calling isolate as the main one, the target of signal-driven wake-ups.
pub fn set_main() {
    // SAFETY: this isolate's state.
    unsafe { *MAIN.ptr() = true };
}

/// Whether signal handlers should wake the calling isolate's poller.
pub fn is_main() -> bool {
    // SAFETY: this isolate's state.
    cfg!(test) || unsafe { *MAIN.ptr() }
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

/// Drops queued posts (test reset).
#[cfg(any(test, feature = "stats"))]
pub fn clear_posts() {
    let (_, inbox) = current();
    inbox.full.store(false, Ordering::Relaxed);
    inbox
        .posts
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .clear();
}
