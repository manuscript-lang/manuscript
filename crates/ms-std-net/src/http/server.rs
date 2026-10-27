//! The HTTP server: an event loop that runs on the ms thread.
//!
//! Listeners and connections are nonblocking sockets in one readiness set.
//! A reactor task serves that set (see [`Reactor::spawn_task`]) and each request runs in its own task,
//! so accepting, reading and parsing happen while the program waits, and a
//! complete request runs its handler right there on the ms thread: no thread
//! hop, no locks. One handler runs at a time. While it blocks, other
//! connections keep being read and parsed, and their requests queue up.

pub mod buffered;
mod h2serve;

use super::exchange::Exchange;
use super::h1::{self, BodyDecoder, Framing, Parsed, RequestHead};
use super::headers::{self, Headers};
use super::sniff;
use super::target;
use crate::conn::{Io, Plain, Step};
use crate::error::{HttpErr, NetErr};
use crate::idmap::IdMap;
use crate::net::{Network, Resource};
use crate::rt;
use crate::sys::{AsSock, Borrowed, Ev, Poller};
use crate::tls::{Handshake, TlsIo};
use std::cell::{Cell, RefCell};
use std::collections::{HashMap, VecDeque};
use std::rc::{Rc, Weak};
use std::sync::Arc;
use std::time::{Duration, Instant};

const UNLIMITED: usize = usize::MAX;
/// Per-connection input kept while a request waits for the handler.
const INPUT_HOLD: usize = 256 * 1024;
/// Request bodies the server skips to reuse a connection.
pub const DRAIN_LIMIT: usize = 256 * 1024;

/// How long accepting pauses after the process runs out of descriptors or memory.
const ACCEPT_BACKOFF: Duration = Duration::from_millis(50);

/// Whether `accept` failed for lack of descriptors, buffers, or memory.
fn is_resource_exhaustion(e: &std::io::Error) -> bool {
    #[cfg(unix)]
    {
        // EMFILE, ENFILE, ENOBUFS (Linux/macOS), ENOMEM
        matches!(e.raw_os_error(), Some(24 | 23 | 105 | 55 | 12))
    }
    #[cfg(not(unix))]
    {
        let _ = e;
        false
    }
}

/// Server limits; `UNLIMITED` means none.
#[derive(Clone, Debug)]
pub struct Limits {
    pub admission: usize,
    pub body: usize,
    pub response: usize,
    pub header: usize,
    pub timeout: Option<Duration>,
    pub grace: Option<Duration>,
}

impl Default for Limits {
    fn default() -> Limits {
        Limits {
            admission: UNLIMITED,
            body: UNLIMITED,
            response: UNLIMITED,
            header: UNLIMITED,
            timeout: None,
            grace: None,
        }
    }
}

/// How a handler call ended.
pub enum Outcome<T> {
    Done(T),
    /// The handler faulted; the text goes to the diagnostics.
    Fault(String),
    /// The request was cancelled.
    Cancelled,
}

/// The program's handler, called on the ms thread.
pub trait Dispatch {
    fn streaming(&self, exchange: Rc<Exchange>) -> Outcome<Result<(), HttpErr>>;
}

/// Server construction options.
pub struct Options {
    pub limits: Limits,
    pub tls: Option<Arc<rustls::ServerConfig>>,
    /// Share the listening socket with every other server of this process that serves the same
    /// address text with `shared` set, so isolates on several threads accept from one port.
    pub shared: bool,
}

/// Listening sockets shared between the servers (and so the threads) of the process, by address text:
/// the first server binds, later ones duplicate the descriptor. Duplicating works the same on
/// Linux, macOS and Windows, where `SO_REUSEPORT` is not available.
static SHARED_LISTENERS: std::sync::Mutex<Vec<SharedListener>> = std::sync::Mutex::new(Vec::new());

struct SharedListener {
    address: String,
    /// Keeps the port bound while any server uses it.
    socket: socket2::Socket,
    users: usize,
}

fn shared_listeners() -> std::sync::MutexGuard<'static, Vec<SharedListener>> {
    SHARED_LISTENERS.lock().unwrap_or_else(|e| e.into_inner())
}

/// A duplicate of the shared listener for `address`, bound by `bind` when no server holds it.
fn shared_listener(
    address: &str,
    bind: impl FnOnce() -> Result<socket2::Socket, NetErr>,
) -> Result<socket2::Socket, NetErr> {
    let mut all = shared_listeners();
    if let Some(entry) = all.iter_mut().find(|e| e.address == address) {
        let copy = entry
            .socket
            .try_clone()
            .map_err(|e| NetErr::failed(e.to_string()))?;
        entry.users += 1;
        return Ok(copy);
    }
    let socket = bind()?;
    let copy = socket
        .try_clone()
        .map_err(|e| NetErr::failed(e.to_string()))?;
    all.push(SharedListener {
        address: address.to_string(),
        socket,
        users: 1,
    });
    Ok(copy)
}

/// Drops one user of the shared listener for `address`; true when it was the last, which
/// owns shutting the port down.
fn release_shared_listener(address: &str) -> bool {
    let mut all = shared_listeners();
    let Some(at) = all.iter().position(|e| e.address == address) else {
        return true;
    };
    all[at].users -= 1;
    if all[at].users == 0 {
        all.remove(at);
        return true;
    }
    false
}

// ---------------------------------------------------------------- connections

pub(super) enum Phase {
    Handshake,
    Head,
    Body(Box<Pending>),
    Queued(Box<Pending>),
    Busy,
    Writing,
    /// An HTTP/2 connection: streams are tracked in [`ConnSt::h2`].
    H2,
    Closed,
}

/// A parsed request on its way to the handler.
pub(super) struct Pending {
    pub head: RequestHead,
    pub target: target::Target,
    pub decoder: BodyDecoder,
    pub keep_alive: bool,
    pub expect_continue: bool,
    pub started: Instant,
}

pub(super) struct ConnSt {
    /// Boxed so a connection without TLS, and an exchange keeping one alive, stay small.
    pub tls_pending: Option<Box<TlsIo>>,
    pub io: Option<Rc<dyn Io>>,
    pub inbuf: Vec<u8>,
    pub pos: usize,
    pub outbuf: Vec<u8>,
    pub out_pos: usize,
    pub phase: Phase,
    pub close_after: bool,
    pub flush_pending: bool,
    pub eof: bool,
    pub deadline: Option<Instant>,
    /// The deadline bounds an idle wait for the next request, not a request in progress.
    pub idle_deadline: bool,
    pub interest: Ev,
    pub registered: bool,
    pub h2: Option<Box<h2serve::H2Conn>>,
    /// The task running this connection's HTTP/1 request (`0`: none).
    pub task: u64,
}

pub struct Conn {
    pub(super) token: u64,
    pub(super) server: Weak<Server>,
    pub(super) st: RefCell<ConnSt>,
}

impl ConnSt {
    pub(super) fn fd(&self) -> Borrowed<'_> {
        match (&self.io, &self.tls_pending) {
            (Some(io), _) => io.fd(),
            (None, Some(tls)) => tls.socket().as_sock(),
            (None, None) => unreachable!("connection without a stream"),
        }
    }

    pub(super) fn unread(&self) -> &[u8] {
        &self.inbuf[self.pos..]
    }

    pub(super) fn consume(&mut self, n: usize) {
        self.pos += n;
        if self.pos == self.inbuf.len() {
            self.inbuf.clear();
            self.pos = 0;
        } else if self.pos > 64 * 1024 {
            self.inbuf.drain(..self.pos);
            self.pos = 0;
        }
    }
}

// -------------------------------------------------------------------- reactor

enum Target {
    Listener(Weak<Server>),
    Conn(Weak<Conn>),
}

pub struct Reactor {
    poller: Poller,
    next: Cell<u64>,
    targets: RefCell<IdMap<u64, Target>>,
    ready: RefCell<VecDeque<Rc<Conn>>>,
    retry: RefCell<Vec<Rc<Conn>>>,
    task_started: Cell<bool>,
    /// Task running the reactor loop (`0`: none).
    task: Cell<u64>,
    scratch: RefCell<Vec<u8>>,
    date: RefCell<(i64, String)>,
    /// When `sweep_timeouts` next has work: the earliest deadline it knows of.
    next_sweep: Cell<Option<Instant>>,
}

thread_local! {
    static REACTOR: RefCell<Option<Rc<Reactor>>> = const { RefCell::new(None) };
}

impl Reactor {
    /// The reactor of this thread, created and installed on first use.
    pub fn get() -> Rc<Reactor> {
        REACTOR.with(|r| {
            let mut slot = r.borrow_mut();
            if let Some(r) = &*slot {
                return r.clone();
            }
            let reactor = Rc::new(Reactor {
                poller: Poller::new(),
                next: Cell::new(1),
                targets: RefCell::new(IdMap::default()),
                ready: RefCell::new(VecDeque::new()),
                retry: RefCell::new(Vec::new()),
                task_started: Cell::new(false),
                task: Cell::new(0),
                scratch: RefCell::new(vec![0; 64 * 1024]),
                date: RefCell::new((0, String::new())),
                next_sweep: Cell::new(None),
            });
            *slot = Some(reactor.clone());
            reactor
        })
    }

    /// Makes sure the sweep runs by `at`.
    fn note_deadline(&self, at: Option<Instant>) {
        if let Some(at) = at
            && self.next_sweep.get().is_none_or(|n| at < n)
        {
            self.next_sweep.set(Some(at));
            // A parked reactor computed its timeout from the old deadline.
            self.poller.kick();
        }
    }

    fn token(&self) -> u64 {
        let t = self.next.get();
        self.next.set(t + 1);
        t
    }

    fn add(&self, sock: Borrowed<'_>, token: u64, ev: Ev) -> bool {
        self.poller.add(sock, token, ev)
    }

    fn modify(&self, sock: Borrowed<'_>, token: u64, ev: Ev) {
        self.poller.modify(sock, token, ev);
    }

    fn delete(&self, sock: Borrowed<'_>) {
        self.poller.delete(sock);
    }

    /// The value of the `Date` header, refreshed once per second.
    pub(super) fn date_text(&self) -> String {
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map_or(0, |d| d.as_secs() as i64);
        let mut cached = self.date.borrow_mut();
        if cached.0 != now || cached.1.is_empty() {
            *cached = (now, h1::http_date(now));
        }
        cached.1.clone()
    }

    /// Whether the running task is a request task of `server`.
    pub fn in_handler_of(&self, server: &Server) -> bool {
        server.scope.contains_current()
    }

    /// Whether the running task is a request task of any server.
    fn in_handler(&self) -> bool {
        rt::in_scope_task()
    }

    /// Whether the running task is a request task of a server owned by `network`.
    pub fn in_handler_of_network(&self, network: &Network) -> bool {
        SERVERS.with(|s| {
            s.borrow()
                .values()
                .filter_map(Weak::upgrade)
                .any(|s| s.owner.is_within(network) && s.scope.contains_current())
        })
    }

    /// Queues a connection whose request is ready, waking the reactor when a request task
    /// (not the reactor itself) found it.
    pub(super) fn enqueue(&self, conn: &Rc<Conn>) {
        self.ready.borrow_mut().push_back(conn.clone());
        if rt::current_task() != self.task.get() {
            self.poller.kick();
        }
    }

    /// Starts a task for each request that became ready. The reactor task only serves I/O.
    fn run_handlers(&self) {
        loop {
            let next = self.ready.borrow_mut().pop_front();
            let Some(conn) = next else { break };
            let Some(server) = conn.server.upgrade() else {
                continue;
            };
            let limit = -1;
            let job = Box::into_raw(Box::new(Job { conn }));
            // SAFETY: `request_task` takes back the boxed job leaked here.
            let started = unsafe { server.scope.spawn(request_task, job.cast(), limit) };
            if started.is_none() {
                // SAFETY: the scope is closed, so the task never runs; the job is still ours.
                drop(unsafe { Box::from_raw(job) });
            }
        }
    }

    /// Starts the task that serves I/O events and timeouts. Called once, by the
    /// first server.
    fn spawn_task(&self) {
        crate::wait::use_tasks();
        #[cfg(test)]
        serialize_tests();
        if !self.task_started.replace(true) {
            let arg = Box::into_raw(Box::new(Reactor::get())).cast::<u8>();
            // SAFETY: `reactor_task` takes back the boxed reactor leaked above.
            unsafe { rt::spawn_detached(reactor_task, arg) };
        }
    }

    fn handle_event(&self, token: u64, flags: Ev) {
        let target = match self.targets.borrow().get(&token) {
            Some(Target::Listener(s)) => Target::Listener(s.clone()),
            Some(Target::Conn(c)) => Target::Conn(c.clone()),
            None => return,
        };
        match target {
            Target::Listener(server) => {
                if let Some(server) = server.upgrade() {
                    server.accept_all(self);
                }
            }
            Target::Conn(conn) => {
                if let Some(conn) = conn.upgrade()
                    && let Some(server) = conn.server.upgrade()
                {
                    server.on_ready(&conn, flags, self);
                }
            }
        }
    }
}

/// The scheduler is process-global while test threads are many: servers of
/// different tests take turns, each holding the lock until its thread ends.
#[cfg(test)]
pub(crate) fn serialize_tests() {
    use std::sync::{Mutex, MutexGuard};
    static LOCK: Mutex<()> = Mutex::new(());
    thread_local! {
        static HELD: RefCell<Option<MutexGuard<'static, ()>>> = const { RefCell::new(None) };
    }
    HELD.with(|held| {
        let mut held = held.borrow_mut();
        if held.is_none() {
            *held = Some(LOCK.lock().unwrap_or_else(|e| e.into_inner()));
        }
    });
}

/// A request that became ready, on its way to its task.
struct Job {
    conn: Rc<Conn>,
}

/// Body of a request task: serves the one request that became ready on a connection. While the
/// server drains on a stop it is shielded, so the request finishes within the grace period.
unsafe extern "C-unwind" fn request_task(arg: *mut u8) {
    // SAFETY: `arg` is the `Box<Job>` leaked by `run_handlers`.
    let Job { conn } = *unsafe { Box::from_raw(arg.cast::<Job>()) };
    let Some(server) = conn.server.upgrade() else {
        return;
    };
    let shield = server.limits.grace.is_some_and(|g| !g.is_zero());
    if shield {
        rt::stop_shield();
    }
    server.dispatch_conn(&conn, &Reactor::get());
    if shield {
        rt::stop_unshield();
    }
}

/// Body of the reactor task: serve events until the program is cancelled.
unsafe extern "C-unwind" fn reactor_task(arg: *mut u8) {
    // SAFETY: `arg` is the `Box<Rc<Reactor>>` leaked by `spawn_task` for this task.
    let reactor = unsafe { *Box::from_raw(arg.cast::<Rc<Reactor>>()) };
    reactor.task.set(rt::current_task());
    let mut drain = DrainShield::default();
    loop {
        reactor.service();
        // No servers left: end; the next server starts a new reactor task.
        if reactor.targets.borrow().is_empty() {
            reactor.task.set(0);
            reactor.task_started.set(false);
            return;
        }
        drain.set(reactor.drains());
        let timeout = reactor.next_sweep.get().map_or(-1, |at| {
            at.saturating_duration_since(Instant::now()).as_nanos() as i64
        });
        let got = reactor.poller.park(timeout);
        if got & 16 != 0 {
            return;
        }
    }
}

/// Shields the reactor task from SIGINT/SIGTERM while a server with a
/// nonzero `grace` is open, so in-flight requests finish within the grace period.
#[derive(Default)]
struct DrainShield(bool);

impl DrainShield {
    fn set(&mut self, want: bool) {
        if want == self.0 {
            return;
        }
        self.0 = want;
        if want {
            rt::shield();
        } else {
            rt::unshield();
        }
    }
}

impl Drop for DrainShield {
    fn drop(&mut self) {
        self.set(false);
    }
}

impl Reactor {
    /// Whether any open server or connection asked to drain in-flight requests on a stop.
    fn drains(&self) -> bool {
        // Grace belongs to a server, not a connection. In particular, a server with no
        // grace must not revisit every idle connection before each reactor park.
        SERVERS.with(|servers| {
            servers
                .borrow()
                .values()
                .filter_map(Weak::upgrade)
                .any(|s| {
                    s.limits.grace.is_some_and(|g| !g.is_zero())
                    // Closing removes the listener before draining its connections.
                    && (self.targets.borrow().contains_key(&s.token)
                        || !s.st.borrow().conns.is_empty())
                })
        })
    }

    /// Handles whatever is ready without blocking.
    fn service(&self) {
        let mut events = Vec::new();
        loop {
            let raw = self.poller.poll(&mut events, 64);
            for &(token, flags) in &events {
                self.handle_event(token, flags);
            }
            loop {
                let retry: Vec<Rc<Conn>> = self.retry.borrow_mut().drain(..).collect();
                if retry.is_empty() {
                    break;
                }
                for conn in retry {
                    if let Some(server) = conn.server.upgrade() {
                        server.on_ready(&conn, Ev::IN, self);
                    }
                }
            }
            self.run_handlers();
            if raw < 64 {
                break;
            }
        }
        if self.next_sweep.get().is_some_and(|at| at <= Instant::now()) {
            self.sweep_timeouts();
        }
    }
}

impl Reactor {
    /// Closes connections whose read or write deadline passed.
    fn sweep_timeouts(&self) {
        let now = Instant::now();
        let mut next: Option<Instant> = None;
        let mut note = |at: Option<Instant>| {
            if let Some(at) = at
                && next.is_none_or(|n| at < n)
            {
                next = Some(at);
            }
        };
        for t in self.targets.borrow().values() {
            match t {
                Target::Conn(c) => {
                    if let Some(c) = c.upgrade() {
                        let st = c.st.borrow();
                        if st.deadline.is_some_and(|d| d > now) {
                            note(st.deadline);
                        }
                        if matches!(st.phase, Phase::H2) {
                            // HTTP/2 streams keep their own clocks; look at them often.
                            note(Some(now + Duration::from_millis(50)));
                        }
                    }
                }
                Target::Listener(s) => {
                    if let Some(s) = s.upgrade() {
                        note(s.st.borrow().accept_paused_until);
                    }
                }
            }
        }
        self.next_sweep.set(next);
        let expired: Vec<Rc<Conn>> = self
            .targets
            .borrow()
            .values()
            .filter_map(|t| match t {
                Target::Conn(c) => c.upgrade(),
                Target::Listener(_) => None,
            })
            .filter(|c| {
                let st = c.st.borrow();
                !matches!(st.phase, Phase::Busy) && st.deadline.is_some_and(|d| d <= now)
            })
            .collect();
        for conn in expired {
            if let Some(server) = conn.server.upgrade() {
                server.close_conn(&conn, self);
            }
        }
        let listeners: Vec<Rc<Server>> = self
            .targets
            .borrow()
            .values()
            .filter_map(|t| match t {
                Target::Listener(s) => s.upgrade(),
                Target::Conn(_) => None,
            })
            .collect();
        for server in listeners {
            server.resume_accept(self);
        }
        let h2_conns: Vec<Rc<Conn>> = self
            .targets
            .borrow()
            .values()
            .filter_map(|t| match t {
                Target::Conn(c) => c.upgrade(),
                Target::Listener(_) => None,
            })
            .filter(|c| matches!(c.st.borrow().phase, Phase::H2))
            .collect();
        for conn in h2_conns {
            if let Some(server) = conn.server.upgrade() {
                server.h2_sweep(&conn, self, now);
            }
        }
    }
}

thread_local! {
    static SERVERS: RefCell<HashMap<usize, Weak<Server>>> = RefCell::new(HashMap::new());
    static NEXT_ID: Cell<usize> = const { Cell::new(1) };
}

// --------------------------------------------------------------------- server

pub struct Server {
    id: usize,
    me: Weak<Server>,
    pub(super) owner: Rc<Network>,
    /// Dropped on close: macOS keeps queueing connections on a shut-down listener until the
    /// descriptor itself closes.
    listener: RefCell<Option<socket2::Socket>>,
    /// The address text under which the listener is shared with other servers, if it is.
    shared_address: Option<String>,
    address: String,
    pub(super) limits: Limits,
    tls: Option<Arc<rustls::ServerConfig>>,
    pub(super) dispatch: Box<dyn Dispatch>,
    st: RefCell<ServerSt>,
    token: u64,
    /// Owns the request tasks; closing it cancels the ones still running.
    scope: rt::Scope,
}

struct ServerSt {
    conns: IdMap<u64, Rc<Conn>>,
    closing: bool,
    closed: bool,
    /// Requests queued or running (the admission count).
    admitted: usize,
    /// Set while the listener is unwatched after accept ran out of descriptors or memory.
    accept_paused_until: Option<Instant>,
    /// Tokens of the tasks in [`Server::wait`], posted on close.
    waiters: Vec<u64>,
    /// Token of a close waiting for responses to finish, posted when a connection closes or
    /// goes idle.
    draining: Option<u64>,
}

impl Resource for Server {
    fn close_resource(&self) {
        self.close_inner();
    }
}

/// Why `close` refused.
#[derive(Debug, PartialEq, Eq)]
pub enum CloseError {
    /// Called from a handler of this server.
    FromHandler,
}

impl Server {
    /// Starts serving on `address`.
    pub fn start(
        owner: &Rc<Network>,
        address: &str,
        dispatch: Box<dyn Dispatch>,
        options: Options,
    ) -> Result<Rc<Server>, NetErr> {
        if owner.is_closed() {
            return Err(NetErr::Closed);
        }
        if !owner.listen_allowed(address) {
            return Err(NetErr::PermissionDenied);
        }
        let listener = if options.shared {
            shared_listener(address, || owner.listen_tcp(address))?
        } else {
            owner.listen_tcp(address)?
        };
        let local = listener
            .local_addr()
            .map(|a| crate::conn::socket_addr_text(&a))
            .unwrap_or_default();
        let reactor = Reactor::get();
        reactor.spawn_task();
        let id = NEXT_ID.with(|n| {
            let id = n.get();
            n.set(id + 1);
            id
        });
        let token = reactor.token();
        let server = Rc::new_cyclic(|me| Server {
            id,
            me: me.clone(),
            owner: owner.clone(),
            listener: RefCell::new(Some(listener)),
            shared_address: options.shared.then(|| address.to_string()),
            address: local,
            limits: options.limits,
            tls: options.tls,
            dispatch,
            st: RefCell::new(ServerSt {
                conns: IdMap::default(),
                closing: false,
                closed: false,
                admitted: 0,
                accept_paused_until: None,
                waiters: Vec::new(),
                draining: None,
            }),
            token,
            scope: rt::Scope::new(),
        });
        reactor
            .targets
            .borrow_mut()
            .insert(token, Target::Listener(Rc::downgrade(&server)));
        let watched = server
            .listener
            .borrow()
            .as_ref()
            .is_some_and(|l| reactor.add(l.as_sock(), token, Ev::IN));
        if !watched {
            reactor.targets.borrow_mut().remove(&token);
            return Err(NetErr::failed("cannot watch listener"));
        }
        SERVERS.with(|s| s.borrow_mut().insert(id, Rc::downgrade(&server)));
        let as_resource: Rc<dyn Resource> = server.clone();
        if !owner.own_server(&as_resource) {
            server.close_inner();
            return Err(NetErr::Closed);
        }
        Ok(server)
    }

    pub fn id(&self) -> usize {
        self.id
    }

    pub(super) fn tls_enabled(&self) -> bool {
        self.tls.is_some()
    }

    pub(super) fn rc(&self) -> Option<Rc<Server>> {
        self.me.upgrade()
    }

    pub(super) fn is_closing(&self) -> bool {
        self.st.borrow().closing
    }

    pub fn address(&self) -> &str {
        &self.address
    }

    pub fn is_closed(&self) -> bool {
        self.st.borrow().closed
    }

    /// Blocks until the server is closed, serving requests meanwhile.
    pub fn wait(&self) {
        if self.is_closed() {
            return;
        }
        let token = rt::Token::new();
        self.st.borrow_mut().waiters.push(token.id());
        while !self.is_closed() {
            if token.park(-1) & 16 != 0 {
                rt::cancelled();
            }
        }
        self.st.borrow_mut().waiters.retain(|&id| id != token.id());
    }

    /// Stops accepting, lets in-flight responses finish within the grace period
    /// and closes the rest.
    pub fn close(&self) -> Result<(), CloseError> {
        if Reactor::get().in_handler_of(self) {
            return Err(CloseError::FromHandler);
        }
        self.close_inner();
        Ok(())
    }

    fn close_inner(&self) {
        let reactor = Reactor::get();
        {
            let mut st = self.st.borrow_mut();
            if st.closing {
                return;
            }
            st.closing = true;
        }
        if let Some(listener) = self.listener.borrow_mut().take() {
            reactor.delete(listener.as_sock());
            // Other servers still accept on a shared port: shut it down with the last one.
            let last = self
                .shared_address
                .as_deref()
                .is_none_or(release_shared_listener);
            if last {
                let _ = listener.shutdown(std::net::Shutdown::Both);
            }
        }
        reactor.targets.borrow_mut().remove(&self.token);
        // Idle connections close now; the others after their current response.
        let conns: Vec<Rc<Conn>> = self.st.borrow().conns.values().cloned().collect();
        for conn in &conns {
            let (idle, h2) = {
                let mut st = conn.st.borrow_mut();
                let idle =
                    matches!(st.phase, Phase::Head | Phase::Handshake) && st.unread().is_empty();
                st.close_after = true;
                (idle, matches!(st.phase, Phase::H2))
            };
            if idle {
                self.close_conn(conn, &reactor);
            } else if h2 {
                // GOAWAY now; the connection closes once its streams finish.
                self.h2_begin_close(conn, &reactor);
            }
        }
        let deadline =
            crate::wait::Deadline::from_nanos(self.limits.grace.map(|g| g.as_nanos() as i64))
                .unwrap_or(crate::wait::Deadline::none());
        if !reactor.in_handler() {
            // Let responses finish: the reactor and request tasks run while this parks, and
            // post the token whenever a connection closes or goes idle.
            let token = rt::Token::new();
            self.st.borrow_mut().draining = Some(token.id());
            while !self.drained() && !deadline.expired() {
                let left = deadline
                    .remaining()
                    .map_or(-1, |d| d.as_nanos().min(i64::MAX as u128) as i64);
                if token.park(left) & 16 != 0 {
                    self.st.borrow_mut().draining = None;
                    rt::cancelled();
                }
            }
            self.st.borrow_mut().draining = None;
        }
        let conns: Vec<Rc<Conn>> = self.st.borrow().conns.values().cloned().collect();
        for conn in conns {
            self.close_conn(&conn, &reactor);
        }
        let waiters = {
            let mut st = self.st.borrow_mut();
            st.closed = true;
            std::mem::take(&mut st.waiters)
        };
        for id in waiters {
            rt::post(id);
        }
        SERVERS.with(|s| s.borrow_mut().remove(&self.id));
        if !self.scope.contains_current() {
            // What outlived the grace period is cancelled; its connections are closed already.
            self.scope.close();
        }
    }

    /// Whether every connection has closed or gone idle, so a close can stop waiting.
    fn drained(&self) -> bool {
        self.st
            .borrow()
            .conns
            .values()
            .all(|c| matches!(c.st.borrow().phase, Phase::Head))
    }

    /// Wakes a close that waits for responses to finish, after a connection closed or went idle.
    fn note_drain_progress(&self) {
        if let Some(id) = self.st.borrow().draining {
            rt::post(id);
        }
    }

    // ------------------------------------------------------------- accepting

    fn accept_all(&self, reactor: &Reactor) {
        loop {
            let accepted = match self.listener.borrow().as_ref() {
                Some(listener) => listener.accept(),
                None => break,
            };
            match accepted {
                Ok((sock, _peer)) => {
                    if self.st.borrow().closing {
                        continue;
                    }
                    if sock.set_nonblocking(true).is_err() {
                        continue;
                    }
                    let _ = sock.set_tcp_nodelay(true);
                    self.add_conn(sock, reactor);
                }
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => break,
                Err(e) if e.kind() == std::io::ErrorKind::Interrupted => {}
                Err(e) => {
                    if is_resource_exhaustion(&e) {
                        self.pause_accept(reactor);
                    }
                    break;
                }
            }
        }
    }

    /// Stops watching the listener for a moment: out of descriptors it stays readable, and
    /// polling it would spin the reactor while connections it could free sit unserved.
    fn pause_accept(&self, reactor: &Reactor) {
        let mut st = self.st.borrow_mut();
        if st.accept_paused_until.is_none()
            && !st.closing
            && let Some(listener) = self.listener.borrow().as_ref()
        {
            reactor.delete(listener.as_sock());
            st.accept_paused_until = Some(Instant::now() + ACCEPT_BACKOFF);
            reactor.note_deadline(st.accept_paused_until);
        }
    }

    /// Watches the listener again once the backoff passed.
    fn resume_accept(&self, reactor: &Reactor) {
        let mut st = self.st.borrow_mut();
        if st.closing || st.accept_paused_until.is_none_or(|t| t > Instant::now()) {
            return;
        }
        st.accept_paused_until = None;
        if let Some(listener) = self.listener.borrow().as_ref() {
            reactor.add(listener.as_sock(), self.token, Ev::IN);
        }
    }

    fn add_conn(&self, sock: socket2::Socket, reactor: &Reactor) {
        let token = reactor.token();
        let (io, tls_pending, phase) = match &self.tls {
            None => (
                Some(Rc::new(Plain::new(sock)) as Rc<dyn Io>),
                None,
                Phase::Head,
            ),
            Some(config) => match rustls::ServerConnection::new(config.clone()) {
                Ok(c) => (
                    None,
                    Some(Box::new(TlsIo::new(
                        sock,
                        rustls::Connection::Server(c),
                        false,
                    ))),
                    Phase::Handshake,
                ),
                Err(_) => return,
            },
        };
        let conn = Rc::new(Conn {
            token,
            server: self.me.clone(),
            st: RefCell::new(ConnSt {
                tls_pending,
                io,
                inbuf: Vec::new(),
                pos: 0,
                outbuf: Vec::new(),
                out_pos: 0,
                phase,
                close_after: false,
                flush_pending: false,
                eof: false,
                deadline: self.limits.timeout.map(|t| Instant::now() + t),
                idle_deadline: false,
                interest: Ev::IN,
                registered: false,
                h2: None,
                task: 0,
            }),
        });
        {
            let mut st = conn.st.borrow_mut();
            // A fresh plain connection is idle until its first byte; the timeout bounds that
            // wait too, so silent connections cannot pin file descriptors.
            if self.tls.is_none() {
                st.idle_deadline = st.deadline.is_some();
            }
            if !reactor.add(st.fd(), token, Ev::IN) {
                return;
            }
            st.registered = true;
            reactor.note_deadline(st.deadline);
        }
        reactor
            .targets
            .borrow_mut()
            .insert(token, Target::Conn(Rc::downgrade(&conn)));
        self.st.borrow_mut().conns.insert(token, conn.clone());
        if self.tls.is_some() {
            self.drive_handshake(&conn, reactor);
        }
    }

    fn drive_handshake(&self, conn: &Rc<Conn>, reactor: &Reactor) {
        let result = {
            let st = conn.st.borrow();
            match &st.tls_pending {
                Some(tls) => tls.drive_handshake(),
                None => return,
            }
        };
        match result {
            Handshake::Done => {
                let mut st = conn.st.borrow_mut();
                let mut h2 = false;
                if let Some(tls) = st.tls_pending.take() {
                    let mut tls = *tls;
                    let verified = tls.has_peer_certificates();
                    tls.set_verified(verified);
                    h2 = tls.tls_details().is_some_and(|d| d.alpn == "h2");
                    st.io = Some(Rc::new(tls));
                }
                st.deadline = None;
                if h2 {
                    reactor.note_deadline(Some(Instant::now() + Duration::from_millis(50)));
                    st.phase = Phase::H2;
                    st.h2 = Some(Box::new(h2serve::H2Conn::new(&self.limits)));
                } else {
                    st.phase = Phase::Head;
                }
                drop(st);
                self.note_drain_progress();
                if h2 {
                    self.set_interest(conn, reactor, Ev::IN);
                    self.h2_serve(conn, reactor);
                } else {
                    // The client's first request may have arrived with its final
                    // handshake flight; rustls already holds it, so no further
                    // readiness event will announce it. Read it now.
                    self.set_interest(conn, reactor, Ev::IN);
                    self.read_in(conn, reactor);
                }
            }
            Handshake::WantRead => self.set_interest(conn, reactor, Ev::IN),
            Handshake::WantWrite => self.set_interest(conn, reactor, Ev::OUT),
            Handshake::Failed(_) => self.close_conn(conn, reactor),
        }
    }

    // ------------------------------------------------------------ connection

    pub(super) fn set_interest(&self, conn: &Rc<Conn>, reactor: &Reactor, flags: Ev) {
        let mut st = conn.st.borrow_mut();
        if st.registered && st.interest == flags {
            return;
        }
        if st.registered {
            reactor.modify(st.fd(), conn.token, flags);
        } else {
            reactor.add(st.fd(), conn.token, flags);
            st.registered = true;
        }
        st.interest = flags;
    }

    /// Takes the connection out of the event loop (a handler owns it).
    pub(super) fn detach(&self, conn: &Rc<Conn>, reactor: &Reactor) {
        // The socket stays registered; only the interest goes (no system call).
        self.set_interest(conn, reactor, Ev::NONE);
    }

    /// Takes the stream and unread input of a connection whose handler upgraded
    /// it; the server forgets the connection without closing the stream.
    pub(super) fn hijack(
        &self,
        conn: &Rc<Conn>,
        reactor: &Reactor,
    ) -> Option<(Rc<dyn Io>, Vec<u8>)> {
        let (io, leftover) = {
            let mut st = conn.st.borrow_mut();
            let io = st.io.take()?;
            let leftover = st.unread().to_vec();
            st.inbuf = Vec::new();
            st.pos = 0;
            st.outbuf = Vec::new();
            st.phase = Phase::Closed;
            if st.registered {
                reactor.delete(io.fd());
                st.registered = false;
            }
            (io, leftover)
        };
        reactor.targets.borrow_mut().remove(&conn.token);
        reactor.ready.borrow_mut().retain(|c| !Rc::ptr_eq(c, conn));
        self.st.borrow_mut().conns.remove(&conn.token);
        self.note_drain_progress();
        Some((io, leftover))
    }

    pub(super) fn close_conn(&self, conn: &Rc<Conn>, reactor: &Reactor) {
        // Handlers parked on an HTTP/2 connection wake to find their stream gone.
        h2serve::wake_waiters(conn);
        let (queued, running) = {
            let mut st = conn.st.borrow_mut();
            if matches!(st.phase, Phase::Closed) {
                return;
            }
            let mut running = st.h2.as_ref().map_or(Vec::new(), |h| h.running());
            running.push(st.task);
            let queued = usize::from(matches!(st.phase, Phase::Queued(_)))
                + st.h2.as_ref().map_or(0, |h| h.queued());
            if st.registered {
                reactor.delete(st.fd());
                st.registered = false;
            }
            if let Some(io) = &st.io {
                io.shutdown_both();
            }
            // Free the descriptor now: a handler task cancelled while parked never drops the
            // `Rc<Conn>` it holds, and nothing reads the stream of a closed connection.
            st.io = None;
            st.tls_pending = None;
            st.phase = Phase::Closed;
            st.inbuf = Vec::new();
            st.outbuf = Vec::new();
            st.h2 = None;
            (queued, running)
        };
        // Handlers still running on the connection have no one to answer.
        for task in running {
            rt::cancel_task(task);
        }
        if queued > 0 {
            let mut s = self.st.borrow_mut();
            s.admitted = s.admitted.saturating_sub(queued);
        }
        reactor.targets.borrow_mut().remove(&conn.token);
        reactor.ready.borrow_mut().retain(|c| !Rc::ptr_eq(c, conn));
        self.st.borrow_mut().conns.remove(&conn.token);
        self.note_drain_progress();
    }

    fn on_ready(&self, conn: &Rc<Conn>, flags: Ev, reactor: &Reactor) {
        if matches!(conn.st.borrow().phase, Phase::Handshake) {
            self.drive_handshake(conn, reactor);
            return;
        }
        if flags.contains(Ev::HUP) && matches!(conn.st.borrow().phase, Phase::Busy) {
            // The peer is gone while the handler runs: cancel it, and leave the stream to it.
            let task = conn.st.borrow().task;
            rt::cancel_task(task);
            return;
        }
        if matches!(conn.st.borrow().phase, Phase::H2) {
            if self.h2_serve(conn, reactor) {
                reactor.retry.borrow_mut().push(conn.clone());
            }
            return;
        }
        if flags.contains(Ev::OUT) {
            self.write_out(conn, reactor);
        }
        if matches!(conn.st.borrow().phase, Phase::Closed) {
            return;
        }
        if flags.intersects(Ev::IN | Ev::HUP) {
            self.read_in(conn, reactor);
        }
    }

    /// Reads whatever is available, then parses.
    fn read_in(&self, conn: &Rc<Conn>, reactor: &Reactor) {
        let mut more = false;
        {
            let mut scratch = reactor.scratch.borrow_mut();
            let mut st = conn.st.borrow_mut();
            let mut total = 0;
            loop {
                if st.phase_blocks_input() && st.unread().len() >= INPUT_HOLD {
                    break;
                }
                let step = match &st.io {
                    Some(io) => io.read(&mut scratch),
                    None => return,
                };
                match step {
                    Step::Done(n) => {
                        st.inbuf.extend_from_slice(&scratch[..n]);
                        total += n;
                        if total >= 1 << 20 {
                            more = true;
                            break;
                        }
                        if n < scratch.len()
                            && st.io.as_ref().is_some_and(|io| io.short_read_drains())
                        {
                            reactor.poller.consumed(st.fd(), Ev::IN);
                            break;
                        }
                    }
                    Step::Eof => {
                        st.eof = true;
                        break;
                    }
                    Step::WantRead | Step::WantWrite => {
                        reactor.poller.consumed(st.fd(), Ev::IN);
                        break;
                    }
                    Step::Err(_) => {
                        st.eof = true;
                        st.close_after = true;
                        break;
                    }
                }
            }
        }
        if more {
            reactor.retry.borrow_mut().push(conn.clone());
        }
        self.after_read(conn, reactor);
    }

    fn after_read(&self, conn: &Rc<Conn>, reactor: &Reactor) {
        self.advance(conn, reactor);
        let (closed, eof, idle_head) = {
            let st = conn.st.borrow();
            (
                matches!(st.phase, Phase::Closed),
                st.eof,
                matches!(st.phase, Phase::Head) && st.unread().is_empty(),
            )
        };
        if closed {
            return;
        }
        if idle_head && !eof {
            let mut st = conn.st.borrow_mut();
            if st.deadline.is_none() {
                st.deadline = self.limits.timeout.map(|t| Instant::now() + t);
                reactor.note_deadline(st.deadline);
                st.idle_deadline = st.deadline.is_some();
            }
        }
        if eof {
            // The peer is gone: finish a pending response, otherwise close.
            let phase_writing = matches!(conn.st.borrow().phase, Phase::Writing);
            if idle_head || !phase_writing {
                let queued = matches!(conn.st.borrow().phase, Phase::Queued(_) | Phase::Busy);
                if !queued {
                    self.close_conn(conn, reactor);
                }
            }
        }
    }

    // ----------------------------------------------------------- state machine

    /// Parses buffered input as far as the phase allows.
    fn advance(&self, conn: &Rc<Conn>, reactor: &Reactor) {
        loop {
            let phase = {
                let st = conn.st.borrow();
                match &st.phase {
                    Phase::Head => 0,
                    Phase::Body(_) => 1,
                    _ => return,
                }
            };
            let progressed = if phase == 0 {
                self.advance_head(conn, reactor)
            } else {
                self.advance_body(conn, reactor)
            };
            if !progressed {
                return;
            }
        }
    }

    fn respond_error(
        &self,
        conn: &Rc<Conn>,
        reactor: &Reactor,
        status: u16,
        message: &str,
        close: bool,
    ) {
        let mut out = Vec::with_capacity(256);
        let body = format!("{message}\n");
        h1::status_line(&mut out, status);
        h1::header_line(&mut out, "Content-Type", b"text/plain; charset=utf-8");
        h1::header_line(&mut out, "X-Content-Type-Options", b"nosniff");
        h1::header_line(&mut out, "Date", reactor.date_text().as_bytes());
        h1::header_line(
            &mut out,
            "Content-Length",
            body.len().to_string().as_bytes(),
        );
        if close {
            h1::header_line(&mut out, "Connection", b"close");
        }
        out.extend_from_slice(b"\r\n");
        out.extend_from_slice(body.as_bytes());
        self.queue_output(conn, reactor, out, close);
    }

    /// Returns whether the head phase made progress (a request was taken).
    fn advance_head(&self, conn: &Rc<Conn>, reactor: &Reactor) -> bool {
        let parsed = {
            let mut st = conn.st.borrow_mut();
            if st.unread().is_empty() {
                return false;
            }
            match h1::parse_request(st.unread(), self.limits.header.min(1 << 30)) {
                Parsed::Partial => {
                    if st.deadline.is_none() || st.idle_deadline {
                        st.deadline = self.limits.timeout.map(|t| Instant::now() + t);
                        reactor.note_deadline(st.deadline);
                        st.idle_deadline = false;
                    }
                    return false;
                }
                Parsed::Complete(head) => {
                    st.consume(head.length);
                    st.deadline = None;
                    st.idle_deadline = false;
                    Ok(head)
                }
                Parsed::Bad(bad) => Err(bad),
            }
        };
        let head = match parsed {
            Ok(head) => head,
            Err(bad) => {
                self.respond_error(conn, reactor, bad.status, bad.reason, true);
                return false;
            }
        };
        match self.begin_request(conn, reactor, head) {
            Ok(pending) => {
                let mut st = conn.st.borrow_mut();
                st.phase = Phase::Body(pending);
                true
            }
            Err((status, message)) => {
                self.respond_error(conn, reactor, status, message, true);
                false
            }
        }
    }

    fn begin_request(
        &self,
        conn: &Rc<Conn>,
        reactor: &Reactor,
        head: RequestHead,
    ) -> Result<Box<Pending>, (u16, &'static str)> {
        let _ = (conn, reactor);
        if head.minor == 1
            && !head
                .fields
                .iter()
                .any(|(n, _)| n.eq_ignore_ascii_case("Host"))
        {
            return Err((400, "missing required Host header"));
        }
        if head
            .fields
            .iter()
            .filter(|(n, _)| n.eq_ignore_ascii_case("Host"))
            .count()
            > 1
        {
            return Err((400, "too many Host headers"));
        }
        let framing = h1::request_framing(&head).map_err(|b| (b.status, b.reason))?;
        let target = target::parse(&head.target).map_err(|e| (400, e.0))?;
        if !head.fields.iter().all(|(n, v)| {
            std::str::from_utf8(n.as_bytes()).is_ok() && std::str::from_utf8(v).is_ok()
        }) {
            return Err((400, "invalid UTF-8 request"));
        }
        let expect = h1::has_token(&head.fields, "Expect", "100-continue");
        let keep_alive = h1::keep_alive(head.minor, &head.fields);
        if let Framing::Length(n) = framing
            && n > self.limits.body as u64
        {
            return Err((413, "invalid or oversized request body"));
        }
        Ok(Box::new(Pending {
            decoder: BodyDecoder::new(framing),
            head,
            target,
            keep_alive,
            expect_continue: expect,
            started: Instant::now(),
        }))
    }

    /// Returns whether the body phase finished (so parsing may continue).
    fn advance_body(&self, conn: &Rc<Conn>, reactor: &Reactor) -> bool {
        let mut st = conn.st.borrow_mut();
        let Phase::Body(pending) = std::mem::replace(&mut st.phase, Phase::Head) else {
            return false;
        };
        // The handler reads the body itself.
        drop(st);
        self.queue(conn, reactor, pending)
    }

    /// Admits a complete request for the handler.
    fn queue(&self, conn: &Rc<Conn>, reactor: &Reactor, pending: Box<Pending>) -> bool {
        {
            let mut s = self.st.borrow_mut();
            if s.closing {
                drop(s);
                self.respond_error(conn, reactor, 503, "server closed", true);
                return false;
            }
            if s.admitted >= self.limits.admission {
                drop(s);
                self.respond_error(conn, reactor, 503, "server busy", !pending.keep_alive);
                return false;
            }
            s.admitted += 1;
        }
        {
            let mut st = conn.st.borrow_mut();
            st.deadline = None;
            st.phase = Phase::Queued(pending);
        }
        // Stop reading while the request waits; the handler owns the stream next.
        self.set_interest(conn, reactor, Ev::NONE);
        reactor.enqueue(conn);
        false
    }

    // ----------------------------------------------------------------- output

    /// Appends a finished response and starts writing.
    pub(super) fn queue_output(
        &self,
        conn: &Rc<Conn>,
        reactor: &Reactor,
        bytes: Vec<u8>,
        close: bool,
    ) {
        {
            let mut st = conn.st.borrow_mut();
            if matches!(st.phase, Phase::Closed) {
                return;
            }
            if st.outbuf.is_empty() {
                st.outbuf = bytes;
                st.out_pos = 0;
            } else {
                st.outbuf.extend_from_slice(&bytes);
            }
            st.phase = Phase::Writing;
            st.close_after = st.close_after || close;
            st.deadline = None;
        }
        self.write_out(conn, reactor);
    }

    /// Writes pending output; on completion continues with the next request.
    pub(super) fn write_out(&self, conn: &Rc<Conn>, reactor: &Reactor) {
        enum Next {
            Blocked,
            Failed,
            Finished(bool),
        }
        let next = {
            let mut guard = conn.st.borrow_mut();
            let st = &mut *guard;
            let Some(io) = &st.io else { return };
            let mut next = None;
            while st.out_pos < st.outbuf.len() {
                match io.write(&st.outbuf[st.out_pos..]) {
                    Step::Done(n) => st.out_pos += n,
                    Step::WantWrite | Step::WantRead => {
                        reactor.poller.consumed(io.fd(), Ev::OUT);
                        next = Some(Next::Blocked);
                        break;
                    }
                    Step::Eof | Step::Err(_) => {
                        next = Some(Next::Failed);
                        break;
                    }
                }
            }
            match next {
                Some(n) => n,
                None => match io.flush() {
                    Step::Done(_) => {
                        st.outbuf.clear();
                        st.out_pos = 0;
                        st.flush_pending = false;
                        Next::Finished(st.close_after)
                    }
                    Step::WantWrite | Step::WantRead => {
                        st.flush_pending = true;
                        Next::Blocked
                    }
                    _ => Next::Failed,
                },
            }
        };
        match next {
            Next::Failed => self.close_conn(conn, reactor),
            Next::Blocked => {
                if !matches!(conn.st.borrow().phase, Phase::Busy) {
                    self.set_interest(conn, reactor, Ev::OUT);
                }
            }
            Next::Finished(close) => {
                let busy = matches!(conn.st.borrow().phase, Phase::Busy);
                if busy {
                    return;
                }
                if close || self.st.borrow().closing {
                    self.close_conn(conn, reactor);
                    return;
                }
                {
                    let mut st = conn.st.borrow_mut();
                    if matches!(st.phase, Phase::Writing) {
                        st.phase = Phase::Head;
                    }
                }
                self.note_drain_progress();
                self.set_interest(conn, reactor, Ev::IN);
                // Pipelined requests may already be buffered.
                self.after_read(conn, reactor);
            }
        }
    }

    // ---------------------------------------------------------------- dispatch

    fn dispatch_conn(&self, conn: &Rc<Conn>, reactor: &Reactor) {
        if matches!(conn.st.borrow().phase, Phase::H2) {
            self.h2_dispatch(conn, reactor);
            return;
        }
        let pending = {
            let mut st = conn.st.borrow_mut();
            match std::mem::replace(&mut st.phase, Phase::Busy) {
                Phase::Queued(p) => p,
                other => {
                    st.phase = other;
                    return;
                }
            }
        };
        self.detach(conn, reactor);
        conn.st.borrow_mut().task = rt::current_task();
        super::exchange::run(self, conn, pending);
        conn.st.borrow_mut().task = 0;
        {
            let mut s = self.st.borrow_mut();
            s.admitted = s.admitted.saturating_sub(1);
        }
    }
}

impl ConnSt {
    /// Whether input should stop accumulating (the request is waiting or running).
    fn phase_blocks_input(&self) -> bool {
        matches!(self.phase, Phase::Queued(_) | Phase::Busy | Phase::Writing)
    }
}

/// Writes an error response like `http.Error`; returns whether it closes.
pub(super) fn error_bytes(
    out: &mut Vec<u8>,
    reactor: &Reactor,
    status: u16,
    message: &str,
    close: bool,
) -> bool {
    let body = format!("{message}\n");
    h1::status_line(out, status);
    h1::header_line(out, "Content-Type", b"text/plain; charset=utf-8");
    h1::header_line(out, "X-Content-Type-Options", b"nosniff");
    h1::header_line(out, "Date", reactor.date_text().as_bytes());
    h1::header_line(out, "Content-Length", body.len().to_string().as_bytes());
    if close {
        h1::header_line(out, "Connection", b"close");
    }
    out.extend_from_slice(b"\r\n");
    out.extend_from_slice(body.as_bytes());
    false
}

/// Whether a response to `status` may carry a body.
pub(super) fn body_allowed(status: i64) -> bool {
    !((100..200).contains(&status) || status == 204 || status == 304)
}

/// Appends handler headers with canonical names, sorted.
pub(super) fn append_handler_headers(out: &mut Vec<u8>, headers: &Headers) -> (bool, bool) {
    let mut sorted: Vec<(String, &Vec<Vec<u8>>)> = headers
        .entries()
        .iter()
        .map(|e| (headers::canonical(&e.name), &e.values))
        .collect();
    sorted.sort_by(|a, b| a.0.cmp(&b.0));
    let (mut has_type, mut has_date) = (false, false);
    for (name, values) in &sorted {
        has_type |= name == "Content-Type";
        has_date |= name == "Date";
        for v in *values {
            h1::header_line(out, name, v);
        }
    }
    (has_type, has_date)
}

#[cfg(test)]
pub(crate) mod tests {
    use super::buffered::{Buffered, Handle, Reply, Request};
    use super::*;
    use std::io::{Read, Write};
    use std::net::TcpStream;

    /// Runs `client` on a thread while the ms thread serves.
    pub fn with_client<T: Send + 'static>(client: impl FnOnce() -> T + Send + 'static) -> T {
        let handle = std::thread::spawn(client);
        while !handle.is_finished() {
            crate::wait::sleep(Duration::from_millis(2));
        }
        handle.join().expect("client thread")
    }

    /// Sends `raw` and reads until the server closes or `want` bytes arrived.
    pub fn exchange(addr: &str, raw: &[u8]) -> String {
        let mut s = TcpStream::connect(addr).unwrap();
        s.set_read_timeout(Some(Duration::from_secs(5))).unwrap();
        s.write_all(raw).unwrap();
        let mut out = Vec::new();
        let mut buf = [0u8; 4096];
        loop {
            match s.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => out.extend_from_slice(&buf[..n]),
                Err(_) => break,
            }
        }
        String::from_utf8_lossy(&out).into_owned()
    }

    struct App;

    impl Handle for App {
        fn handle(&self, r: Request) -> Outcome<Reply> {
            let mut headers = Headers::new();
            match r.path.as_str() {
                "/fault" => return Outcome::Fault("boom".into()),
                "/cancel" => return Outcome::Cancelled,
                "/slow" => crate::wait::sleep(Duration::from_millis(300)),
                "/cookies" => {
                    headers.append("Set-Cookie", b"a=1").unwrap();
                    headers.append("set-cookie", b"b=2").unwrap();
                }
                "/badheader" => headers.append("Content-Length", b"5").unwrap(),
                "/badstatus" => {
                    return Outcome::Done(Reply {
                        status: 99,
                        headers,
                        body: vec![],
                    });
                }
                _ => {}
            }
            let body = match r.path.as_str() {
                "/big" => vec![b'x'; 5000],
                "/html" => b"<html>hi</html>".to_vec(),
                "/echo" => r.body.clone(),
                p => format!("{}|{}|{}|{}", r.method, p, r.query, r.protocol).into_bytes(),
            };
            let status = if r.path == "/empty" { 204 } else { 200 };
            Outcome::Done(Reply {
                status,
                headers,
                body,
            })
        }
    }

    pub fn start(options: Options) -> (Rc<Network>, Rc<Server>) {
        let net = Network::new_root();
        let server = Server::start(&net, "127.0.0.1:0", Box::new(Buffered(App)), options).unwrap();
        (net, server)
    }

    pub fn opts(limits: Limits) -> Options {
        Options {
            limits,
            tls: None,
            shared: false,
        }
    }

    fn get(path: &str) -> Vec<u8> {
        format!("GET {path} HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n").into_bytes()
    }

    #[test]
    fn serves_buffered_requests() {
        let (_net, server) = start(opts(Limits::default()));
        let addr = server.address().to_string();
        let text = with_client(move || exchange(&addr, &get("/a%20b/../hello?x=1")));
        assert!(text.starts_with("HTTP/1.1 200 OK\r\n"), "{text}");
        assert!(text.contains("Content-Length: 23\r\n"), "{text}");
        assert!(text.contains("Content-Type: text/plain; charset=utf-8\r\n"));
        assert!(text.contains("Connection: close\r\n"));
        assert!(text.contains("Date: "));
        assert!(text.ends_with("\r\n\r\nGET|/hello|x=1|HTTP/1.1"), "{text}");
    }

    #[test]
    fn handlers_run_concurrently() {
        let (_net, server) = start(opts(Limits::default()));
        let addr = server.address().to_string();
        let started = Instant::now();
        let texts = with_client(move || {
            let clients: Vec<_> = (0..4)
                .map(|_| {
                    let addr = addr.clone();
                    std::thread::spawn(move || exchange(&addr, &get("/slow")))
                })
                .collect();
            clients
                .into_iter()
                .map(|c| c.join().unwrap())
                .collect::<Vec<_>>()
        });
        assert!(texts.iter().all(|t| t.starts_with("HTTP/1.1 200 OK")));
        // Four 300 ms handlers overlap instead of queueing behind each other.
        assert!(
            started.elapsed() < Duration::from_millis(900),
            "{:?}",
            started.elapsed()
        );
    }

    #[test]
    fn keep_alive_and_pipelining() {
        let (_net, server) = start(opts(Limits::default()));
        let addr = server.address().to_string();
        let raw = b"GET /one HTTP/1.1\r\nHost: t\r\n\r\nGET /two HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n".to_vec();
        let text = with_client(move || exchange(&addr, &raw));
        assert_eq!(text.matches("HTTP/1.1 200 OK").count(), 2, "{text}");
        let one = text.find("GET|/one").unwrap();
        let two = text.find("GET|/two").unwrap();
        assert!(one < two);
    }

    #[test]
    fn bodies_chunked_and_sized() {
        let (_net, server) = start(opts(Limits::default()));
        let addr = server.address().to_string();
        let a2 = addr.clone();
        let chunked = with_client(move || {
            exchange(&a2, b"POST /echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n")
        });
        assert!(chunked.ends_with("hello world"), "{chunked}");
        let a3 = addr.clone();
        let sized = with_client(move || {
            exchange(&a3, b"POST /echo HTTP/1.1\r\nHost: t\r\nContent-Length: 3\r\nConnection: close\r\n\r\nabc")
        });
        assert!(sized.ends_with("abc"));
        let big = with_client(move || exchange(&addr, &get("/big")));
        assert!(big.contains("Content-Length: 5000\r\n"), "{big}");
        assert!(!big.contains("Transfer-Encoding"));
    }

    #[test]
    fn rejects_bad_requests_and_limits() {
        let limits = Limits {
            body: 4,
            ..Limits::default()
        };
        let (_net, server) = start(opts(limits));
        let addr = server.address().to_string();
        let run = |raw: &'static [u8]| {
            let a = addr.clone();
            with_client(move || exchange(&a, raw))
        };
        assert!(run(b"GET / HTTP/1.1\r\n\r\n").starts_with("HTTP/1.1 400 Bad Request"));
        assert!(run(b"POST /echo HTTP/1.1\r\nHost: t\r\nContent-Length: 10\r\nConnection: close\r\n\r\n0123456789").starts_with("HTTP/1.1 413"));
        assert!(run(b"POST /echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n8\r\n12345678\r\n0\r\n\r\n").starts_with("HTTP/1.1 413"));
        assert!(run(b"POST /echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\n\r\nZZ\r\nab\r\n0\r\n\r\n").starts_with("HTTP/1.1 400"));
        assert!(run(b"POST /echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\n\r\n3\nabc\n0\n\n").starts_with("HTTP/1.1 400"));
        assert!(run(b"POST /echo HTTP/1.1\r\nHost: t\r\nContent-Length: 3\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n").starts_with("HTTP/1.1 400"));
        assert!(run(b"GET / HTTP/1.1\nHost: t\n\n").starts_with("HTTP/1.1 400"));
        assert!(run(b"GET /a%2Fb HTTP/1.1\r\nHost: t\r\n\r\n").starts_with("HTTP/1.1 400"));
        assert!(run(b"GET /%ff HTTP/1.1\r\nHost: t\r\n\r\n").contains("invalid UTF-8 URL"));
        assert!(
            run(b"GET / HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: gzip\r\n\r\n")
                .starts_with("HTTP/1.1 501")
        );
        assert!(
            run(b"BREW / HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n").contains("BREW|/|")
        );
        assert!(
            run(b"GET /fault HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")
                .starts_with("HTTP/1.1 500")
        );
        assert!(
            run(b"GET /cancel HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")
                .starts_with("HTTP/1.1 504")
        );
        assert!(
            run(b"GET /badheader HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")
                .starts_with("HTTP/1.1 500")
        );
        assert!(
            run(b"GET /badstatus HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")
                .starts_with("HTTP/1.1 500")
        );
    }

    #[test]
    fn response_details() {
        let (_net, server) = start(opts(Limits::default()));
        let addr = server.address().to_string();
        let run = |raw: Vec<u8>| {
            let a = addr.clone();
            with_client(move || exchange(&a, &raw))
        };
        let cookies = run(get("/cookies"));
        assert!(
            cookies.contains("Set-Cookie: a=1\r\nSet-Cookie: b=2\r\n"),
            "{cookies}"
        );
        let html = run(get("/html"));
        assert!(html.contains("Content-Type: text/html; charset=utf-8"));
        let empty = run(get("/empty"));
        assert!(empty.starts_with("HTTP/1.1 204 No Content"));
        assert!(!empty.contains("Content-Length"));
        let head = run(b"HEAD /hello HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n".to_vec());
        assert!(head.contains("Content-Length: 21\r\n"), "{head}");
        assert!(head.ends_with("\r\n\r\n"));
        let old = run(b"GET /hello HTTP/1.0\r\n\r\n".to_vec());
        assert!(
            old.contains("HTTP/1.0") && old.contains("Connection: close"),
            "{old}"
        );
    }

    #[cfg(unix)]
    #[test]
    fn accept_pauses_only_for_resource_exhaustion() {
        let emfile = std::io::Error::from_raw_os_error(24);
        let reset = std::io::Error::from_raw_os_error(104);
        assert!(is_resource_exhaustion(&emfile));
        assert!(!is_resource_exhaustion(&reset));
    }

    #[test]
    fn close_stops_accepting() {
        let (net, server) = start(opts(Limits::default()));
        let addr = server.address().to_string();
        server.close().unwrap();
        assert!(server.is_closed());
        assert!(TcpStream::connect(&addr).is_err());
        net.close();
    }

    #[test]
    fn drain_policy_tracks_servers_through_connection_lifetimes() {
        // The former target traversal is an independent oracle for the shutdown policy.
        fn assert_policy(reactor: &Reactor, expected: bool) {
            let from_targets = reactor.targets.borrow().values().any(|target| {
                let grace = match target {
                    Target::Listener(server) => server.upgrade().map(|s| s.limits.grace),
                    Target::Conn(conn) => conn
                        .upgrade()
                        .and_then(|c| c.server.upgrade())
                        .map(|s| s.limits.grace),
                };
                grace.flatten().is_some_and(|g| !g.is_zero())
            });
            assert_eq!(from_targets, expected);
            assert_eq!(reactor.drains(), expected);
        }

        let (plain_net, plain) = start(opts(Limits::default()));
        let reactor = Reactor::get();
        assert_policy(&reactor, false);

        let (zero_net, zero) = start(opts(Limits {
            grace: Some(Duration::ZERO),
            ..Limits::default()
        }));
        let _plain_client = TcpStream::connect(plain.address()).unwrap();
        plain.accept_all(&reactor);
        assert_policy(&reactor, false);

        for hijack in [false, true] {
            let (net, server) = start(opts(Limits {
                grace: Some(Duration::from_secs(1)),
                ..Limits::default()
            }));
            assert_policy(&reactor, true);
            let _client = TcpStream::connect(server.address()).unwrap();
            server.accept_all(&reactor);
            let conn = server.st.borrow().conns.values().next().unwrap().clone();
            assert_policy(&reactor, true);

            // A close stops listening before it parks to drain the last connection.
            // Keep the registry entry throughout this state, just as close_inner does.
            reactor.targets.borrow_mut().remove(&server.token);
            assert_policy(&reactor, true);
            if hijack {
                let (io, _) = server.hijack(&conn, &reactor).unwrap();
                io.shutdown_both();
            } else {
                server.close_conn(&conn, &reactor);
            }
            // A registered server with no remaining targets must not shield the reactor.
            assert_policy(&reactor, false);
            server.close().unwrap();
            server.close().unwrap();
            net.close();
            assert_policy(&reactor, false);
        }

        let (net, server) = start(opts(Limits {
            grace: Some(Duration::from_secs(1)),
            ..Limits::default()
        }));
        assert_policy(&reactor, true);
        let weak = Rc::downgrade(&server);
        drop(server);
        assert!(weak.upgrade().is_none());
        // Both registries can retain dead weak entries; neither should enable draining.
        assert_policy(&reactor, false);
        net.close();
        zero.close().unwrap();
        zero_net.close();
        plain.close().unwrap();
        plain_net.close();
        assert_policy(&reactor, false);
    }
}
