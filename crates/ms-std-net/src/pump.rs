//! Server handlers run on the ms thread. A background thread queues work and
//! signals [`wake_fd`]; every blocking wait of the ms thread calls
//! [`service`] so a program that serves and requests in one process (or blocks
//! in `server.wait()`) keeps making progress, in the way Go's goroutines do.

use std::cell::{Cell, RefCell};
use std::collections::VecDeque;
use std::os::fd::BorrowedFd;
use std::sync::{Arc, Mutex, OnceLock};

/// A unit of work for the ms thread.
pub type Job = Box<dyn FnOnce() + Send>;

struct Queue {
    jobs: Mutex<VecDeque<Job>>,
    wake: rustix::fd::OwnedFd,
}

static QUEUE: OnceLock<Arc<Queue>> = OnceLock::new();

fn queue() -> &'static Arc<Queue> {
    QUEUE.get_or_init(|| {
        let wake = rustix::event::eventfd(
            0,
            rustix::event::EventfdFlags::CLOEXEC | rustix::event::EventfdFlags::NONBLOCK,
        )
        .expect("eventfd");
        Arc::new(Queue {
            jobs: Mutex::new(VecDeque::new()),
            wake,
        })
    })
}

thread_local! {
    /// Set once the ms thread has registered interest (a server exists).
    static ACTIVE: Cell<bool> = const { Cell::new(false) };
    static DEPTH: Cell<usize> = const { Cell::new(0) };
    static HOOKS: RefCell<Vec<Box<dyn Fn()>>> = const { RefCell::new(Vec::new()) };
}

/// Marks the pump as needed by the ms thread (a server was started).
pub fn activate() {
    queue();
    ACTIVE.with(|a| a.set(true));
}

/// Descriptor that becomes readable when jobs are queued, if the pump is active.
pub fn wake_fd() -> Option<BorrowedFd<'static>> {
    if ACTIVE.with(Cell::get) {
        use std::os::fd::AsFd;
        Some(queue().wake.as_fd())
    } else {
        None
    }
}

/// Queues `job` for the ms thread; callable from any thread.
pub fn submit(job: Job) {
    let q = queue();
    q.jobs.lock().expect("pump queue").push_back(job);
    let _ = rustix::io::write(&q.wake, &1u64.to_ne_bytes());
}

/// Clears the wake signal after it was observed.
pub fn acknowledge() {
    let mut buf = [0u8; 8];
    let _ = rustix::io::read(&queue().wake, &mut buf);
    service();
}

/// Runs queued jobs on the calling (ms) thread.
pub fn service() {
    if !ACTIVE.with(Cell::get) {
        return;
    }
    let q = queue();
    loop {
        let job = q.jobs.lock().expect("pump queue").pop_front();
        let Some(job) = job else { break };
        DEPTH.with(|d| d.set(d.get() + 1));
        job();
        DEPTH.with(|d| d.set(d.get() - 1));
    }
}

/// Whether the ms thread is currently inside a pumped job.
pub fn in_job() -> bool {
    DEPTH.with(Cell::get) > 0
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    #[test]
    fn jobs_run_on_service() {
        activate();
        static N: AtomicUsize = AtomicUsize::new(0);
        std::thread::spawn(|| {
            submit(Box::new(|| {
                N.fetch_add(1, Ordering::SeqCst);
            }))
        })
        .join()
        .unwrap();
        // Wake observed by a wait.
        crate::wait::sleep(std::time::Duration::from_millis(80));
        service();
        assert_eq!(N.load(Ordering::SeqCst), 1);
    }
}
