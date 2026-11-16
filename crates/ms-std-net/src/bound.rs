//! Thread-bound values: a handle made of `Rc` and `RefCell` is not safe to touch from another
//! thread, and `promise(fn:)` may run its entry on any scheduler thread (#3047). [`Bound`]
//! remembers the thread that created the value and faults, naming the cause, when any other
//! thread dereferences or clones it. `PromiseOptions(placement: Placement.Here)` keeps a promise's entry on the creating thread.

use std::cell::Cell;
use std::ops::Deref;
use std::sync::atomic::{AtomicU64, Ordering};

/// A number for the calling thread, never reused. `std::thread::current()` clones and drops an
/// `Arc` on every call, and every native handle use asks.
fn this_thread() -> u64 {
    static NEXT: AtomicU64 = AtomicU64::new(1);
    thread_local! {
        static ID: Cell<u64> = const { Cell::new(0) };
    }
    ID.with(|id| {
        if id.get() == 0 {
            id.set(NEXT.fetch_add(1, Ordering::Relaxed));
        }
        id.get()
    })
}

pub struct Bound<T> {
    value: T,
    owner: u64,
}

impl<T> Bound<T> {
    /// Binds `value` to the calling thread.
    pub fn new(value: T) -> Bound<T> {
        Bound {
            value,
            owner: this_thread(),
        }
    }

    fn check(&self) {
        if this_thread() != self.owner {
            ms_rt::fault::fault(
                b"a native handle was used on a different thread than the one that created it; \
                  use `PromiseOptions(placement: Placement.Here)` to keep work that captures a network, connection, listener, \
                  socket or client on the creating thread",
            );
        }
    }
}

impl<T> Deref for Bound<T> {
    type Target = T;
    fn deref(&self) -> &T {
        self.check();
        &self.value
    }
}

impl<T: Clone> Clone for Bound<T> {
    fn clone(&self) -> Bound<T> {
        self.check();
        Bound {
            value: self.value.clone(),
            owner: self.owner,
        }
    }
}
