//! Helpers for unit tests: global-state lock and fault capture.
use std::sync::{Mutex, MutexGuard};

static LOCK: Mutex<()> = Mutex::new(());

/// Serializes tests that touch runtime globals (allocator, cleanup stack...).
pub fn lock() -> MutexGuard<'static, ()> {
    LOCK.lock().unwrap_or_else(|e| e.into_inner())
}

/// Panic payload carrying the stderr text a fault would print.
pub struct FaultPayload(pub std::string::String);

/// Runs `f` and returns the fault text it raised, or `None` when it returned.
pub fn fault_of<R>(f: impl FnOnce() -> R) -> Option<std::string::String> {
    let hook = std::panic::take_hook();
    std::panic::set_hook(std::boxed::Box::new(|_| {}));
    let r = std::panic::catch_unwind(std::panic::AssertUnwindSafe(f));
    std::panic::set_hook(hook);
    match r {
        Ok(_) => None,
        Err(e) => match e.downcast::<FaultPayload>() {
            Ok(p) => Some(p.0),
            Err(e) => std::panic::resume_unwind(e),
        },
    }
}

/// Asserts the closure faults with exactly this first line (frames ignored).
#[track_caller]
pub fn assert_fault<R>(message: &str, f: impl FnOnce() -> R) {
    let got = fault_of(f).expect("expected a fault");
    assert_eq!(got.lines().next().unwrap_or(""), message);
}
