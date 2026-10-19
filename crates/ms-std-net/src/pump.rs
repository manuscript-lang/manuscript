//! A service hook for the ms thread. Servers are event-driven on the ms thread
//! itself: every blocking wait also polls the installed service's descriptor
//! and lets it run (accept, read, dispatch handlers), so a program that serves
//! and requests in one process, or blocks in `server.wait()`, keeps making
//! progress the way Go's goroutines would.

use std::cell::RefCell;
use std::os::fd::BorrowedFd;
use std::rc::Rc;

/// Event-driven work that shares the ms thread with blocking operations.
pub trait Service {
    /// Descriptor that becomes readable when `service` has work.
    fn fd(&self) -> BorrowedFd<'_>;
    /// Handles whatever is ready without blocking.
    fn service(&self);
}

thread_local! {
    static CURRENT: RefCell<Option<Rc<dyn Service>>> = const { RefCell::new(None) };
}

/// Installs the service of this thread (the first call wins).
pub fn install(service: Rc<dyn Service>) {
    CURRENT.with(|c| {
        let mut c = c.borrow_mut();
        if c.is_none() {
            *c = Some(service);
        }
    });
}

/// The installed service, if any.
pub fn current() -> Option<Rc<dyn Service>> {
    CURRENT.with(|c| c.borrow().clone())
}
