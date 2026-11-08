//! Thread-bound values: a handle made of `Rc` and `RefCell` is not safe to touch from another
//! thread, and `promise(fn:)` may run its entry on any scheduler thread (#3047). [`Bound`]
//! remembers the thread that created the value and faults, naming the cause, when any other
//! thread dereferences or clones it. `owned_promise` keeps its entry on the creating thread.

use std::ops::Deref;
use std::thread::{self, ThreadId};

pub struct Bound<T> {
    value: T,
    owner: ThreadId,
}

impl<T> Bound<T> {
    /// Binds `value` to the calling thread.
    pub fn new(value: T) -> Bound<T> {
        Bound {
            value,
            owner: thread::current().id(),
        }
    }

    fn check(&self) {
        if thread::current().id() != self.owner {
            ms_rt::fault::fault(
                b"a native handle was used on a different thread than the one that created it; \
                  use owned_promise to keep work that captures a network, connection, listener, \
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
