//! Scope-owned launcher state. Spawn never waits for application readiness;
//! independent control tasks report progress to the coordinator's bounded inbox.
use super::Bootstrap;
use crate::error::HttpErr;
use crate::net::{Network, Resource};
use crate::rt;
use ms_rt::start::EntrySnapshot;
use ms_std_process::{command, ipc};
use socket2::Socket;
use std::cell::{Cell, RefCell};
use std::collections::{HashMap, VecDeque};
use std::rc::Rc;
use std::sync::{
    Mutex,
    atomic::{AtomicU64, Ordering},
};

struct WorkerBoot {
    listener: Socket,
    link: ipc::Link,
    entry: EntrySnapshot,
}

static NEXT_BOOT: AtomicU64 = AtomicU64::new(1);
static BOOTS: std::sync::LazyLock<Mutex<HashMap<u64, WorkerBoot>>> =
    std::sync::LazyLock::new(|| Mutex::new(HashMap::new()));
thread_local! {
    static MEMBER: RefCell<Option<WorkerBoot>> = const { RefCell::new(None) };
}

unsafe extern "C-unwind" fn clear_boot(_: *mut u8) {
    MEMBER.with(|boot| boot.borrow_mut().take());
}

unsafe extern "C-unwind" fn worker_entry(arg: *mut u8) {
    let mut value = ms_rt::string::NO_STR;
    // SAFETY: spawn allocated this system byte block; the destination takes it once.
    unsafe {
        ms_rt::worker::msrt_worker_arg_take(arg, &mut value);
    }
    // SAFETY: arg_take initialized an owned runtime string containing eight bytes.
    let id = unsafe { u64::from_ne_bytes(ms_rt::string::bytes(&value).try_into().unwrap()) };
    // SAFETY: value is no longer needed after copying its identity.
    unsafe {
        ms_rt::string::release_opt(&value);
    }
    let boot = BOOTS
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .remove(&id)
        .unwrap();
    let entry = boot.entry;
    MEMBER.with(|slot| *slot.borrow_mut() = Some(boot));
    // SAFETY: thread-local boot remains valid through invocation, including longjmp.
    let cleanup = unsafe { rt::cleanup_push(clear_boot, std::ptr::null_mut()) };
    // SAFETY: this initialized isolate belongs to the executable that captured the entry.
    unsafe {
        entry.invoke();
    }
    rt::cleanup_discard(cleanup);
    // SAFETY: clears any boot not taken by the source runner.
    unsafe {
        clear_boot(std::ptr::null_mut());
    }
}

enum Running {
    Worker(u64),
    Process(command::Subprocess),
    Joined,
}

struct Slot {
    running: RefCell<Running>,
    bootstrap: Bootstrap,
    metadata: String,
}

/// The public source scope owns this state before starting any members.
pub struct Coordinator {
    listener: Socket,
    address: String,
    count: usize,
    processes: bool,
    entry: EntrySnapshot,
    config: String,
    cleanup_ns: i64,
    slots: RefCell<Vec<Rc<Slot>>>,
    events: RefCell<VecDeque<i64>>,
    token: rt::Token,
    closed: Cell<bool>,
    aborted: Cell<bool>,
}

impl Coordinator {
    pub fn new(
        net: &Rc<Network>,
        address: &str,
        count: i64,
        processes: bool,
        entry: EntrySnapshot,
        config: String,
        cleanup_ns: i64,
    ) -> Result<Rc<Self>, HttpErr> {
        if count <= 0 || cleanup_ns < 0 {
            return Err(HttpErr::InvalidInput);
        }
        let count = usize::try_from(count).map_err(|_| HttpErr::InvalidInput)?;
        if config.len() > 16 * 1024 * 1024 {
            return Err(HttpErr::LimitExceeded);
        }
        if net.is_closed() {
            return Err(HttpErr::Closed);
        }
        if !net.listen_allowed(address) {
            return Err(HttpErr::PermissionDenied);
        }
        let listener = net.listen_tcp(address).map_err(HttpErr::from)?;
        let address = listener
            .local_addr()
            .map(|a| crate::conn::socket_addr_text(&a))
            .map_err(|e| HttpErr::Failed(e.to_string()))?;
        let group = Rc::new(Self {
            listener,
            address,
            count,
            processes,
            entry,
            config,
            cleanup_ns,
            slots: RefCell::new(Vec::new()),
            events: RefCell::new(VecDeque::new()),
            token: rt::Token::new(),
            closed: Cell::new(false),
            aborted: Cell::new(false),
        });
        let resource: Rc<dyn Resource> = group.clone();
        if !net.own_server(&resource) {
            return Err(HttpErr::Closed);
        }
        Ok(group)
    }

    pub fn address(&self) -> &str {
        &self.address
    }
    pub fn count(&self) -> usize {
        self.count
    }

    /// Only the coordinator task spawns, in index order. No application code or
    /// cancellable wait runs before the resulting member is stored in this scope.
    pub fn spawn(&self, index: usize) -> Result<(), HttpErr> {
        if self.closed.get() {
            return Err(HttpErr::Closed);
        }
        if index != self.slots.borrow().len() || index >= self.count {
            return Err(HttpErr::InvalidInput);
        }
        let (link, end) = ipc::pair()
            .map_err(|_| HttpErr::Failed("cannot open member control channel".into()))?;
        let (running, bootstrap) = if self.processes {
            let exe = std::env::current_exe().map_err(|e| HttpErr::Failed(e.to_string()))?;
            let entry = self.entry.environment_value();
            let grace = self.cleanup_ns.to_string();
            let child = command::spawn_isolated(
                exe.as_os_str().as_encoded_bytes(),
                &[],
                [
                    command::STDIO_NULL,
                    command::STDIO_INHERIT,
                    command::STDIO_INHERIT,
                ],
                Some(&end),
                &[
                    (ms_rt::start::ENTRY_ENV, entry.as_bytes()),
                    ("MS_HTTP_CLEANUP", grace.as_bytes()),
                ],
            )
            .map_err(|_| HttpErr::Failed(format!("member {index}: process spawn failed")))?;
            drop(end);
            (Running::Process(child), Bootstrap::new(link))
        } else {
            let listener = self
                .listener
                .try_clone()
                .map_err(|e| HttpErr::Failed(e.to_string()))?;
            let bootstrap = Bootstrap::local(link, None)?;
            let id = NEXT_BOOT.fetch_add(1, Ordering::Relaxed);
            BOOTS.lock().unwrap_or_else(|e| e.into_inner()).insert(
                id,
                WorkerBoot {
                    listener,
                    link: end.into_local(),
                    entry: self.entry,
                },
            );
            let bytes = id.to_ne_bytes();
            // SAFETY: worker_entry consumes this exact eight-byte system allocation.
            let handle = unsafe {
                let arg = ms_rt::worker::msrt_worker_arg_new(bytes.as_ptr(), bytes.len());
                ms_rt::worker::msrt_worker_spawn(worker_entry, arg, 0)
            };
            if handle == 0 {
                BOOTS.lock().unwrap_or_else(|e| e.into_inner()).remove(&id);
                return Err(HttpErr::Failed(format!(
                    "member {index}: worker spawn failed"
                )));
            }
            (Running::Worker(handle), bootstrap)
        };
        self.slots.borrow_mut().push(Rc::new(Slot {
            running: RefCell::new(running),
            bootstrap,
            metadata: format!("{index}:{}", self.count),
        }));
        Ok(())
    }

    fn slot(&self, index: usize) -> Result<&Slot, HttpErr> {
        let slots = self.slots.borrow();
        let slot = slots.get(index).ok_or(HttpErr::InvalidInput)?;
        let ptr = Rc::as_ptr(slot);
        // SAFETY: slots are append-only and their Rc allocations remain owned until Self drops.
        // Returning a borrow of Self prevents destruction while this reference is used.
        Ok(unsafe { &*ptr })
    }

    /// Each member's control task completes transfer/configuration independently,
    /// so a later member failure can be observed while an earlier one initializes.
    pub fn connect(&self, index: usize) -> Result<(), HttpErr> {
        let slot = self.slot(index)?;
        let pid = match &*slot.running.borrow() {
            Running::Process(child) => Some(child.child.id()),
            Running::Worker(_) => None,
            Running::Joined => return Err(HttpErr::Closed),
        };
        if let Some(pid) = pid {
            slot.bootstrap.send_listener(&self.listener, pid)?;
        }
        slot.bootstrap.write(slot.metadata.as_bytes())?;
        slot.bootstrap.write(self.config.as_bytes())
    }

    pub fn read(&self, index: usize) -> Result<Vec<u8>, HttpErr> {
        self.slot(index)?.bootstrap.read()
    }
    pub fn write(&self, index: usize, data: &[u8]) -> Result<(), HttpErr> {
        self.slot(index)?.bootstrap.write(data)
    }

    /// A member has at most READY, STOP, and terminal events. Overflow is a
    /// protocol error, never an unbounded queue or a blocking producer.
    pub fn post(&self, index: usize, kind: i64) -> Result<(), HttpErr> {
        if index >= self.count || !(0..16).contains(&kind) {
            return Err(HttpErr::InvalidInput);
        }
        let mut events = self.events.borrow_mut();
        if events.len() >= self.count.saturating_mul(4) {
            return Err(HttpErr::LimitExceeded);
        }
        let value = i64::try_from(index)
            .ok()
            .and_then(|i| i.checked_mul(16))
            .and_then(|i| i.checked_add(kind))
            .ok_or(HttpErr::InvalidInput)?;
        events.push_back(value);
        drop(events);
        rt::post(self.token.id());
        Ok(())
    }

    /// Returns -1 on timeout. The source supervisor supplies its remaining
    /// absolute startup/drain budget rather than restarting that budget per event.
    pub fn next(&self, timeout_ns: i64) -> i64 {
        let started = std::time::Instant::now();
        loop {
            if let Some(event) = self.events.borrow_mut().pop_front() {
                return event;
            }
            let remaining = if timeout_ns < 0 {
                -1
            } else {
                timeout_ns.saturating_sub(started.elapsed().as_nanos().min(i64::MAX as u128) as i64)
            };
            let flags = self.token.park(remaining);
            if flags & 16 != 0 {
                rt::cancelled();
            }
            if flags & 8 != 0 {
                return -1;
            }
            // A previous queued event may have been consumed before its posted
            // token. Treat that wake as stale, never as a readiness timeout.
        }
    }

    /// Collects a member only after DONE and after its control task has returned.
    /// The cleanup scope still owns every handle if a process wait is cancelled.
    pub fn join(&self, index: usize, timeout_ns: i64) -> Result<(), HttpErr> {
        let slot = self.slot(index)?;
        // SAFETY: only the supervisor calls join, after the member's control task
        // returned. The value stays in its scope-owned slot across a cancellable wait.
        let running = unsafe { &mut *slot.running.as_ptr() };
        match running {
            Running::Worker(handle) => {
                // SAFETY: this live handle belongs exclusively to this slot.
                let status =
                    unsafe { ms_rt::worker::msrt_worker_join(*handle, std::ptr::null_mut()) };
                *running = Running::Joined;
                if status != 0 {
                    return Err(HttpErr::Failed(format!(
                        "member {index}: worker outcome {status}"
                    )));
                }
            }
            Running::Process(child) => {
                let status = child.wait(Some(timeout_ns)).map_err(|_| HttpErr::Timeout)?;
                child.closed = true;
                *running = Running::Joined;
                if status != 0 {
                    return Err(HttpErr::Failed(format!(
                        "member {index}: process exit {status}"
                    )));
                }
            }
            Running::Joined => {}
        }
        Ok(())
    }

    /// Interrupts members without touching endpoints borrowed by control tasks.
    /// Their EOF wakes shielded readers; collection follows after those tasks join.
    pub fn abort(&self) {
        if self.aborted.replace(true) {
            return;
        }
        for slot in self.slots.borrow().iter() {
            match &mut *slot.running.borrow_mut() {
                Running::Worker(handle) => ms_rt::worker::msrt_worker_cancel(*handle),
                Running::Process(child) => child.child.kill_group(),
                Running::Joined => {}
            }
        }
    }

    /// Emergency rollback, called only after the source control-task scope joins.
    /// Processes are killed before their leaders are reaped; worker joins remain cooperative.
    pub fn close(&self) {
        if self.closed.replace(true) {
            return;
        }
        self.abort();
        for slot in self.slots.borrow().iter() {
            slot.bootstrap.close();
        }
        for slot in self.slots.borrow().iter() {
            let running = slot.running.replace(Running::Joined);
            match running {
                Running::Worker(handle) => {
                    // SAFETY: this scope owns the worker and collects its handle once.
                    unsafe {
                        ms_rt::worker::msrt_worker_join(handle, std::ptr::null_mut());
                    }
                }
                Running::Process(mut child) => {
                    child.child.wait();
                    child.closed = true;
                }
                Running::Joined => {}
            }
        }
    }
}

impl Resource for Coordinator {
    fn close_resource(&self) {
        self.abort();
        // Wake the source supervisor as well as its per-member readers. Slots and
        // bootstrap storage remain alive until those readers have relinquished them.
        let _ = self.post(0, 3);
    }
}

impl Drop for Coordinator {
    fn drop(&mut self) {
        self.close();
    }
}

/// The member runner takes native resources before invoking user application code.
pub struct Member {
    pub bootstrap: Bootstrap,
    worker: bool,
    #[cfg(unix)]
    watchdog: RefCell<Option<ipc::ParentWatchdog>>,
}

impl Member {
    pub fn take() -> Result<Self, HttpErr> {
        if let Some(boot) = MEMBER.with(|slot| slot.borrow_mut().take()) {
            return Ok(Self {
                bootstrap: Bootstrap::local(boot.link, Some(boot.listener))?,
                worker: true,
                #[cfg(unix)]
                watchdog: RefCell::new(None),
            });
        }
        let grace = std::env::var("MS_HTTP_CLEANUP")
            .ok()
            .and_then(|v| v.parse::<u64>().ok())
            .ok_or(HttpErr::InvalidInput)?;
        // SAFETY: entry bootstrap precedes application initialization or additional threads.
        unsafe {
            std::env::remove_var("MS_HTTP_CLEANUP");
            std::env::remove_var(ms_rt::start::ENTRY_ENV);
        }
        let link = ipc::Link::adopt()
            .map_err(|_| HttpErr::Closed)?
            .ok_or(HttpErr::Closed)?;
        #[cfg(unix)]
        let watchdog = link
            .watch_parent(std::time::Duration::from_nanos(grace))
            .map_err(|_| HttpErr::Failed("cannot start member parent monitor".into()))?;
        #[cfg(windows)]
        let _ = grace;
        Ok(Self {
            bootstrap: Bootstrap::new(link),
            worker: false,
            #[cfg(unix)]
            watchdog: RefCell::new(Some(watchdog)),
        })
    }
    pub fn connect(&self) -> Result<(), HttpErr> {
        if self.worker {
            Ok(())
        } else {
            self.bootstrap.receive_listener()
        }
    }
    /// Disarm before the source runner sends DONE. The supervisor retains its
    /// endpoint until then, and cannot race normal cleanup with parent-loss killing.
    pub fn disarm(&self) {
        #[cfg(unix)]
        self.watchdog.borrow_mut().take();
    }
    pub fn close(&self) {
        self.disarm();
        self.bootstrap.close();
    }
}
