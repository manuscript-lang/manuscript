//! Taking waiting connections from a thread that is held up.
//!
//! A connection belongs to the thread that serves it, and a handler is not interrupted, so while
//! one computes, the requests arriving on that thread's other connections wait. This module lets
//! another thread of the same `serve` call serve them instead.
//!
//! Each server keeps the connections that wait for their next request in a shared list
//! ([`Member::idle`]): a handle and a deadline, and for a connection with state of its own (a
//! TLS session, HTTP/2 streams) that state too ([`Parked`]), which the owner leaves there while
//! the connection waits.
//!
//! Nothing looks at the threads on a clock and no thread exists to do it. Each thread owns a
//! kernel timer that every other thread of its `serve` call waits on. A thread arms its timer
//! for [`HELP_AFTER_NS`] when it leaves its rest and disarms it when it rests again: two system
//! calls per wake-up, no thread woken. The timer fires only for a thread that has stayed out of
//! rest for that long, and wakes the resting threads. If the thread's reactor has not turned
//! since the timer was armed, it is held up: the woken thread takes the listed connections with
//! a request waiting (the duplicate of each handle is made under the list's lock, and the parked
//! state is taken; the owner finds its entry marked taken at its next turn and drops its handle
//! without shutting the connection down, or puts the state back if it was not taken) and arms the
//! timer again, so a connection that becomes ready later in the same stall is found within the
//! same bound. A thread whose reactor turned is busy but healthy: its timer is armed again and
//! nobody is told.
//!
//! When every thread rests nothing is armed and nothing wakes. A server whose handlers are short
//! pays two uncontended lock operations per request and the two timer calls per wake-up.
//! Connection counts are evened out when one changes ([`Group::rebalance`]). Listed are
//! connections between requests: plain HTTP/1, TLS with HTTP/1, and HTTP/2 with no open stream.
//! A TLS session is continued on the taker's duplicate of the socket, so it needs no locking
//! while it is served.

use super::h2serve::H2Conn;
use crate::sys::{self, Raw, TIMER_TOKEN, Wake};
use crate::tls::Session;
use ms_rt::sched;
use std::cell::Cell;
use std::collections::HashMap;
use std::sync::Weak;
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, OnceLock};
use std::time::Instant;

/// How long a thread may stay out of rest before another thread looks at it (100 microseconds):
/// the longest a ready request waits for a held-up thread. A short handler finishes well inside
/// it, so its timer is disarmed before it fires; it is a latency allowance, not a period.
const HELP_AFTER_NS: i64 = 250_000;
/// The smallest difference in connections worth evening out.
const BALANCE_MIN: usize = 4;

fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

/// Every thread's share, by id, for the thread that finds a timer fired.
fn beats() -> &'static Mutex<HashMap<u64, Weak<Beat>>> {
    static BEATS: OnceLock<Mutex<HashMap<u64, Weak<Beat>>>> = OnceLock::new();
    BEATS.get_or_init(|| Mutex::new(HashMap::new()))
}

thread_local! {
    /// The share of the calling thread, for the rest hooks.
    static MINE: Cell<Option<Arc<Beat>>> = const { Cell::new(None) };
}

/// How many threads have an unarmed timer because nobody rested to hear it.
static DORMANT: AtomicUsize = AtomicUsize::new(0);
const NONE: usize = usize::MAX;

/// What a reactor shares with the other threads: one per thread.
pub struct Beat {
    id: u64,
    /// The scheduler index of the reactor's thread.
    thread: usize,
    /// How many times the reactor turned.
    turns: AtomicU64,
    /// The reactor's turns when the timer was armed or last found fired.
    seen: AtomicU64,
    /// The thread's rest count when the timer was armed.
    armed: AtomicU64,
    /// The thread whose poller hears the armed timer, if one is armed.
    armed_for: AtomicUsize,
    /// The thread has been out of rest with no thread resting to look at it.
    dormant: AtomicBool,
    /// Connections listed as waiting, over all servers of this thread: with none there is
    /// nothing to take from it, so its timer stays unarmed.
    listed: AtomicUsize,
    /// Set when a server of this thread has connections to take or to drop.
    attention: AtomicBool,
    wake: Arc<Wake>,
    /// The timer this thread arms for each peer: only that peer's poller waits on it, so a fire
    /// wakes one thread, not all.
    timers: Vec<OnceLock<sys::Timer>>,
    /// The threads that share connections with this one, as a mask.
    peers: AtomicU64,
    /// The descriptor of the reactor's poller.
    poll: sys::PollRef,
    /// The servers of this thread that share connections.
    members: Mutex<Vec<Weak<Member>>>,
}

impl Beat {
    pub fn new(poller: &sys::Poller) -> Arc<Beat> {
        Beat::on(poller, sched::thread())
    }

    fn on(poller: &sys::Poller, thread: usize) -> Arc<Beat> {
        static IDS: AtomicU64 = AtomicU64::new(1);
        let beat = Arc::new(Beat {
            id: IDS.fetch_add(1, Ordering::Relaxed),
            thread,
            turns: AtomicU64::new(0),
            seen: AtomicU64::new(0),
            armed: AtomicU64::new(0),
            armed_for: AtomicUsize::new(NONE),
            dormant: AtomicBool::new(false),
            listed: AtomicUsize::new(0),
            attention: AtomicBool::new(false),
            wake: poller.waker(),
            timers: (0..=sched::MAX_THREADS).map(|_| OnceLock::new()).collect(),
            peers: AtomicU64::new(0),
            poll: poller.poll_ref(),
            members: Mutex::new(Vec::new()),
        });
        lock(beats()).insert(beat.id, Arc::downgrade(&beat));
        beat
    }

    /// Notes that the reactor turned. Answers whether a server of this thread has work from
    /// another thread (see [`Member::take_orders`] and [`Member::take_dropped`]).
    #[inline]
    pub fn turn(&self) -> bool {
        // Only this thread writes it.
        self.turns
            .store(self.turns.load(Ordering::Relaxed) + 1, Ordering::Relaxed);
        self.attention.load(Ordering::Relaxed) && self.attention.swap(false, Ordering::AcqRel)
    }

    /// Makes the rest hooks of the calling thread (the reactor's) arm and disarm timers.
    pub fn install(self: &Arc<Beat>) {
        MINE.with(|m| m.set(Some(self.clone())));
    }

    fn alert(&self) {
        self.attention.store(true, Ordering::Release);
        self.wake.notify();
    }

    fn rests(&self, resting: u64) -> bool {
        resting & (1 << self.thread) != 0
    }

    /// How many times the thread began to rest.
    fn rests_count(&self) -> u64 {
        sched::rests(self.thread)
    }

    /// The live servers of this thread.
    fn servers(&self) -> Vec<Arc<Member>> {
        let mut members = lock(&self.members);
        members.retain(|m| m.strong_count() > 0);
        members.iter().filter_map(Weak::upgrade).collect()
    }

    /// Arms the timer this thread has for `helper`, whose poller hears it.
    fn arm_for(&self, helper: usize) {
        if let Some(timer) = self.timers[helper].get() {
            self.armed.store(self.rests_count(), Ordering::Relaxed);
            self.seen
                .store(self.turns.load(Ordering::Relaxed), Ordering::Relaxed);
            self.armed_for.store(helper, Ordering::Relaxed);
            timer.arm(HELP_AFTER_NS);
        }
    }

    /// The thread left its rest: starts the clock on how long it may stay out of it, for a
    /// thread that rests now and will hear it. With none, it waits for one (see [`begin_rest`]).
    fn leave_rest(&self) {
        if self.listed.load(Ordering::Relaxed) == 0 {
            return;
        }
        let helpers = sched::resting_mask() & self.peers.load(Ordering::Relaxed);
        if helpers == 0 {
            self.make_dormant();
        } else {
            self.arm_for(helpers.trailing_zeros() as usize);
        }
    }

    fn make_dormant(&self) {
        if !self.dormant.swap(true, Ordering::AcqRel) {
            DORMANT.fetch_add(1, Ordering::Relaxed);
        }
    }

    fn disarm(&self) {
        let helper = self.armed_for.swap(NONE, Ordering::Relaxed);
        if helper != NONE
            && let Some(timer) = self.timers[helper].get()
        {
            timer.disarm();
        }
    }

    /// The timer of `held` fired and the calling thread (`me`) heard it. Answers whether `me`
    /// was sent to take connections from it.
    fn fired(me: &Beat, held: &Beat, timer: &sys::Timer, resting: u64) -> bool {
        timer.consume();
        // It was armed for another thread, rested since, or rests: the fire is stale.
        if held.armed_for.load(Ordering::Relaxed) != me.thread
            || held.rests_count() != held.armed.load(Ordering::Relaxed)
            || held.rests(resting)
        {
            return false;
        }
        held.armed_for.store(NONE, Ordering::Relaxed);
        // Whatever happens, the next look is armed by a rest: this thread's, once it is done.
        held.make_dormant();
        let turns = held.turns.load(Ordering::Relaxed);
        if turns != held.seen.swap(turns, Ordering::Relaxed) {
            // The reactor turned: busy but healthy.
            return false;
        }
        let mut sent = false;
        for server in held.servers() {
            if server.waiting.load(Ordering::Relaxed) == 0 {
                continue;
            }
            let Some(group) = server.group.upgrade() else {
                continue;
            };
            let Some(mine) = group.member_of(me) else {
                continue;
            };
            mine.order_here(Order {
                from: server,
                limit: usize::MAX,
                ready_only: true,
            });
            sent = true;
        }
        sent
    }
}

/// Arms the calling thread's timer: it has left its rest.
fn leave_rest() {
    let _ = MINE.try_with(|m| {
        let mine = m.take();
        if let Some(beat) = mine.as_ref() {
            beat.leave_rest();
        }
        m.set(mine);
    });
}

/// The calling thread begins to rest: disarms its own timer, and arms, for itself to hear, the
/// timers of threads that stayed out of rest with nobody to look at them.
fn begin_rest() {
    let _ = MINE.try_with(|m| {
        let mine = m.take();
        if let Some(me) = mine.as_ref() {
            rest_of(me);
        }
        m.set(mine);
    });
}

fn rest_of(me: &Beat) {
    me.disarm();
    if DORMANT.load(Ordering::Relaxed) == 0 {
        return;
    }
    let resting = sched::resting_mask();
    let peers = me.peers.load(Ordering::Relaxed) & !(1 << me.thread);
    for held in lock(beats()).values().filter_map(Weak::upgrade) {
        if peers & (1 << held.thread) != 0
            && held.dormant.load(Ordering::Relaxed)
            && held.dormant.swap(false, Ordering::AcqRel)
        {
            DORMANT.fetch_sub(1, Ordering::Relaxed);
            if !held.rests(resting) {
                held.arm_for(me.thread);
            }
        }
    }
}

/// A reactor heard timers (`tokens`, from its poller) of other threads fire. Answers whether it
/// was sent to take connections.
pub fn heard(me: &Beat, tokens: &[u64]) -> bool {
    let resting = sched::resting_mask();
    let mut sent = false;
    for token in tokens {
        let held = lock(beats())
            .get(&(token & !TIMER_TOKEN))
            .and_then(Weak::upgrade);
        if let Some(held) = held
            && held.id != me.id
            && let Some(timer) = held.timers[me.thread].get()
        {
            sent |= Beat::fired(me, &held, timer, resting);
        }
    }
    sent
}

/// What an idle connection with a state of its own (TLS session, HTTP/2 streams) leaves in the
/// list while waiting, so a taker can continue it. The owner puts it back when it finds the
/// connection not taken.
pub struct Parked {
    pub session: Option<Session>,
    pub h2: Option<Box<H2Conn>>,
}

/// What the owner finds when it unlists a connection.
pub enum Back {
    /// Another thread took it.
    Taken,
    /// Still the owner's, with what it parked.
    Mine(Option<Parked>),
}

/// A connection waiting for its next request.
struct Entry {
    /// The connection's token in its owner's reactor.
    token: u64,
    sock: Raw,
    deadline: Option<Instant>,
    parked: Option<Parked>,
    /// Another thread serves it now; the owner drops its handle when it next looks.
    taken: bool,
}

/// A connection taken from another thread: a handle of its own on the same connection.
pub struct Taken {
    pub sock: socket2::Socket,
    pub deadline: Option<Instant>,
    pub parked: Option<Parked>,
}

/// A request to take connections from another member.
pub struct Order {
    pub from: Arc<Member>,
    /// The most connections to take.
    pub limit: usize,
    /// Take only connections with a request waiting (the owner is held up); otherwise any
    /// waiting connection will do (the owner has too many).
    pub ready_only: bool,
}

/// One server's share of a [`Group`].
pub struct Member {
    beat: Arc<Beat>,
    group: Weak<Group>,
    idle: Mutex<Vec<Entry>>,
    /// Entries of `idle` not taken, readable without the lock.
    waiting: AtomicUsize,
    /// Every connection of the server, waiting or not.
    conns: AtomicUsize,
    /// What another thread asked this member to take.
    orders: Mutex<Vec<Order>>,
    /// Whether `idle` holds taken entries the owner has not dropped yet.
    dropped: AtomicBool,
}

impl Member {
    fn order(&self, order: Order) {
        lock(&self.orders).push(order);
        self.beat.alert();
    }

    /// Queues an order for the calling thread's own reactor, which is awake.
    fn order_here(&self, order: Order) {
        lock(&self.orders).push(order);
        self.beat.attention.store(true, Ordering::Release);
    }

    /// Lists a connection as waiting and answers its place in the list.
    pub fn park(
        &self,
        token: u64,
        sock: Raw,
        deadline: Option<Instant>,
        parked: Option<Parked>,
    ) -> u32 {
        let mut idle = lock(&self.idle);
        idle.push(Entry {
            token,
            sock,
            deadline,
            parked,
            taken: false,
        });
        self.waiting.fetch_add(1, Ordering::Relaxed);
        // The first connection listed while the thread is out of rest starts its clock: the
        // thread left rest with nothing to take, so nothing was armed.
        if self.beat.listed.fetch_add(1, Ordering::Relaxed) == 0 {
            self.beat.leave_rest();
        }
        (idle.len() - 1) as u32
    }

    /// Removes the entry at `place`, which the owner listed for `token`. Answers whether another
    /// thread took the connection (or what the owner parked), and the token of the entry that
    /// moved into `place`, whose connection the owner must tell.
    pub fn unpark(&self, place: u32, token: u64) -> (Back, Option<u64>) {
        let mut idle = lock(&self.idle);
        let at = place as usize;
        debug_assert!(idle.get(at).is_some_and(|e| e.token == token));
        if idle.get(at).is_none_or(|e| e.token != token) {
            return (Back::Mine(None), None);
        }
        let entry = idle.swap_remove(at);
        if !entry.taken {
            self.waiting.fetch_sub(1, Ordering::Relaxed);
            self.beat.listed.fetch_sub(1, Ordering::Relaxed);
        }
        let back = if entry.taken {
            Back::Taken
        } else {
            Back::Mine(entry.parked)
        };
        (back, idle.get(at).map(|e| e.token))
    }

    /// The tokens of the owner's connections that another thread took, if any were since the
    /// last call. The owner drops each (see `unpark`).
    pub fn take_dropped(&self) -> Vec<u64> {
        if !self.dropped.swap(false, Ordering::AcqRel) {
            return Vec::new();
        }
        lock(&self.idle)
            .iter()
            .filter(|e| e.taken)
            .map(|e| e.token)
            .collect()
    }

    /// How many connections are listed and not taken.
    #[cfg(test)]
    pub fn waiting_count(&self) -> usize {
        self.waiting.load(Ordering::Relaxed)
    }

    /// Counts a connection the server gained (`+1`) or lost (`-1`), and evens out the group when
    /// that left it lopsided. A connection another thread took is already counted away (see
    /// [`Member::take`]).
    pub fn count(&self, change: isize) {
        if change > 0 {
            self.conns.fetch_add(1, Ordering::Relaxed);
        } else {
            self.conns.fetch_sub(1, Ordering::Relaxed);
        }
        if let Some(group) = self.group.upgrade() {
            group.rebalance();
        }
    }

    /// What another thread asked this member to take.
    pub fn take_orders(&self) -> Vec<Order> {
        std::mem::take(&mut *lock(&self.orders))
    }

    /// Takes up to `limit` waiting connections of this member for the calling thread to
    /// serve: with `ready_only`, those with a request waiting. The owner is not asked: its
    /// thread may be held up.
    pub fn take(&self, limit: usize, ready_only: bool) -> Vec<Taken> {
        let mut out = Vec::new();
        {
            let mut idle = lock(&self.idle);
            let open: Vec<usize> = (0..idle.len()).filter(|&i| !idle[i].taken).collect();
            let ready = if ready_only {
                let socks: Vec<Raw> = open.iter().map(|&i| idle[i].sock).collect();
                sys::readable(&socks)
            } else {
                vec![true; open.len()]
            };
            for (&i, ready) in open.iter().zip(ready) {
                if out.len() == limit {
                    break;
                }
                if !ready {
                    continue;
                }
                // The lock keeps the owner from closing the handle while it is duplicated.
                let Some(sock) = sys::duplicate(idle[i].sock) else {
                    continue;
                };
                idle[i].taken = true;
                out.push(Taken {
                    sock,
                    deadline: idle[i].deadline,
                    parked: idle[i].parked.take(),
                });
            }
        }
        if !out.is_empty() {
            self.waiting.fetch_sub(out.len(), Ordering::Relaxed);
            self.beat.listed.fetch_sub(out.len(), Ordering::Relaxed);
            // Counted away now, not when the owner drops its handle, so that balancing sees
            // where the connections are.
            self.conns.fetch_sub(out.len(), Ordering::Relaxed);
            self.dropped.store(true, Ordering::Release);
            self.beat.alert();
        }
        out
    }
}

/// The servers of one `serve` call, one per thread: they may take each other's connections.
#[derive(Default)]
pub struct Group {
    members: Mutex<Vec<Arc<Member>>>,
}

impl Group {
    /// Adds a server on the calling thread, whose reactor shares `beat`.
    pub fn join(self: &Arc<Group>, beat: &Arc<Beat>) -> Arc<Member> {
        let member = Arc::new(Member {
            beat: beat.clone(),
            group: Arc::downgrade(self),
            idle: Mutex::new(Vec::new()),
            waiting: AtomicUsize::new(0),
            conns: AtomicUsize::new(0),
            orders: Mutex::new(Vec::new()),
            dropped: AtomicBool::new(false),
        });
        lock(&beat.members).push(Arc::downgrade(&member));
        let mut members = lock(&self.members);
        for other in members.iter() {
            if !Arc::ptr_eq(&other.beat, beat) {
                watch_each_other(&other.beat, beat);
            }
        }
        members.push(member.clone());
        if members.len() > 1 {
            sched::set_rest_hooks(begin_rest, leave_rest);
            sched::enable_hooks();
        }
        member
    }

    /// Removes a server that closed.
    pub fn leave(self: &Arc<Group>, member: &Arc<Member>) {
        lock(&self.members).retain(|m| !Arc::ptr_eq(m, member));
    }

    /// The member of the thread whose share is `beat`.
    fn member_of(&self, beat: &Beat) -> Option<Arc<Member>> {
        lock(&self.members)
            .iter()
            .find(|m| m.beat.id == beat.id)
            .cloned()
    }

    /// Has the member with the fewest connections take half its difference to the one with the
    /// most, when that is worth moving and the fewest has not been asked already.
    fn rebalance(&self) {
        let members = lock(&self.members);
        let count = |m: &&Arc<Member>| m.conns.load(Ordering::Relaxed);
        let (Some(most), Some(fewest)) = (
            members.iter().max_by_key(count),
            members.iter().min_by_key(count),
        ) else {
            return;
        };
        let difference = count(&most).saturating_sub(count(&fewest));
        if difference >= BALANCE_MIN.max(count(&most) / 4) && lock(&fewest.orders).is_empty() {
            fewest.order(Order {
                from: most.clone(),
                limit: difference / 2,
                ready_only: false,
            });
        }
    }
}

/// Has each of two threads' pollers report the timer the other arms for it.
fn watch_each_other(a: &Beat, b: &Beat) {
    a.peers.fetch_or(1 << b.thread, Ordering::Relaxed);
    b.peers.fetch_or(1 << a.thread, Ordering::Relaxed);
    for (held, helper) in [(a, b), (b, a)] {
        held.timers[helper.thread].get_or_init(|| {
            sys::Timer::between(helper.poll.clone(), TIMER_TOKEN | held.id).expect("timer")
        });
    }
}

/// What an idle connection leaves in the list crosses threads: a compile-time check that it is
/// `Send` without an `unsafe impl`.
const _: fn() = || {
    fn send<T: Send>() {}
    send::<Parked>();
};

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sys::AsSock;
    use std::io::Write;
    use std::net::{TcpListener, TcpStream};
    use std::time::Duration;

    /// A reactor's share on a made-up scheduler thread.
    fn beat(thread: usize) -> Arc<Beat> {
        Beat::on(&sys::Poller::new(), thread)
    }

    fn member() -> Arc<Member> {
        Arc::new(Group::default()).join(&beat(0))
    }

    /// `unpark`, with whether the connection was taken.
    fn unparked(m: &Member, place: u32, token: u64) -> (bool, Option<u64>) {
        let (back, moved) = m.unpark(place, token);
        (matches!(back, Back::Taken), moved)
    }

    /// A connected pair: the client's end and the server's.
    fn pair(listener: &TcpListener) -> (TcpStream, socket2::Socket) {
        let client = TcpStream::connect(listener.local_addr().unwrap()).unwrap();
        let (server, _) = listener.accept().unwrap();
        (client, socket2::Socket::from(server))
    }

    /// Blocks until `sock` has input, as the kernel reports it.
    fn await_input(sock: &socket2::Socket) {
        while !sys::poll_one(sock.as_sock(), false, Duration::from_secs(5)) {}
    }

    #[test]
    fn unparking_moves_the_last_entry_into_the_place() {
        let m = member();
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let socks: Vec<_> = (0..3).map(|_| pair(&listener)).collect();
        let places: Vec<u32> = socks
            .iter()
            .enumerate()
            .map(|(i, (_, s))| m.park(10 + i as u64, sys::raw(s.as_sock()), None, None))
            .collect();
        assert_eq!(places, [0, 1, 2]);
        assert_eq!(unparked(&m, 0, 10), (false, Some(12)));
        assert_eq!(unparked(&m, 0, 12), (false, Some(11)));
        assert_eq!(unparked(&m, 0, 11), (false, None));
        assert_eq!(m.waiting.load(Ordering::Relaxed), 0);
    }

    #[test]
    fn taking_ready_connections_leaves_the_quiet_ones() {
        let m = member();
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let (mut busy_client, busy) = pair(&listener);
        let (_quiet_client, quiet) = pair(&listener);
        m.park(1, sys::raw(quiet.as_sock()), None, None);
        m.park(2, sys::raw(busy.as_sock()), None, None);
        busy_client.write_all(b"GET / HTTP/1.1\r\n\r\n").unwrap();
        // Loopback delivery is not instant on every platform.
        await_input(&busy);
        let taken = m.take(usize::MAX, true);
        assert_eq!(taken.len(), 1);
        assert_eq!(taken[0].sock.peer_addr().ok(), busy.peer_addr().ok());
        // The owner learns of it, finds the entry taken, and keeps the quiet one.
        assert!(m.beat.turn());
        assert_eq!(m.take_dropped(), [2]);
        assert_eq!(unparked(&m, 1, 2), (true, None));
        assert_eq!(unparked(&m, 0, 1), (false, None));
        // The taker's handle outlives the owner's.
        drop(busy);
        let mut buf = [std::mem::MaybeUninit::uninit(); 32];
        assert_eq!(taken[0].sock.recv(&mut buf).unwrap(), 18);
    }

    type Lopsided = (
        Arc<Group>,
        Arc<Member>,
        Arc<Member>,
        Vec<(TcpStream, socket2::Socket)>,
    );

    /// A group of two servers on made-up threads 61 and 62, the first listing `n` connections.
    fn lopsided(n: usize) -> Lopsided {
        let group = Arc::new(Group::default());
        let (full, empty) = (group.join(&beat(61)), group.join(&beat(62)));
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let socks: Vec<_> = (0..n).map(|_| pair(&listener)).collect();
        for (i, (_, s)) in socks.iter().enumerate() {
            full.park(i as u64, sys::raw(s.as_sock()), None, None);
            full.conns.fetch_add(1, Ordering::Relaxed);
        }
        (group, full, empty, socks)
    }

    #[test]
    fn balancing_moves_half_the_difference() {
        let (group, full, empty, _socks) = lopsided(8);
        group.rebalance();
        assert!(empty.beat.turn());
        let orders = empty.take_orders();
        assert_eq!(orders.len(), 1);
        let taken = orders[0].from.take(orders[0].limit, orders[0].ready_only);
        assert_eq!(taken.len(), 4);
        assert_eq!(full.waiting.load(Ordering::Relaxed), 4);
        // Counted away at the take and onto the taker as it serves them: the group is even.
        assert_eq!(full.conns.load(Ordering::Relaxed), 4);
        for _ in &taken {
            empty.count(1);
        }
        group.rebalance();
        assert!(empty.take_orders().is_empty());
    }

    #[test]
    fn a_change_in_the_count_asks_for_balance_once() {
        let (_group, full, empty, _socks) = lopsided(8);
        full.count(1);
        full.count(1);
        assert_eq!(empty.take_orders().len(), 1);
    }

    #[test]
    fn a_timer_that_fires_on_a_held_up_thread_sends_the_hearer_and_a_turning_thread_is_left() {
        let (_group, full, empty, _socks) = lopsided(2);
        let (held, me) = (&full.beat, &empty.beat);
        let timer = held.timers[me.thread].get().expect("timer of the pair");
        let resting = 0;
        // The held-up thread armed its timer for the hearer and did not turn: it is sent.
        held.arm_for(me.thread);
        assert!(Beat::fired(me, held, timer, resting));
        assert_eq!(empty.take_orders().len(), 1);
        // The reactor turned since: busy but healthy, nobody is sent.
        held.arm_for(me.thread);
        held.turn();
        assert!(!Beat::fired(me, held, timer, resting));
        assert!(empty.take_orders().is_empty());
        // The thread rested since the timer was armed: the fire is stale.
        held.arm_for(me.thread);
        sched::count_rest(61);
        assert!(!Beat::fired(me, held, timer, resting));
        // A thread that rests now is not held up; one armed for another thread is left alone.
        held.arm_for(me.thread);
        assert!(!Beat::fired(me, held, timer, 1 << 61));
        held.armed_for.store(60, Ordering::Relaxed);
        assert!(!Beat::fired(me, held, timer, resting));
        assert!(empty.take_orders().is_empty());
    }

    /// The tokens of timers the poller has reported by the time `until` is among them.
    fn heard_until(poller: &sys::Poller, until: u64) -> Vec<u64> {
        let (mut heard, mut out) = (Vec::new(), Vec::new());
        let start = std::time::Instant::now();
        while !heard.contains(&until) {
            assert!(
                start.elapsed() < Duration::from_secs(10),
                "timer never fired"
            );
            poller.poll(&mut out, 16);
            heard.extend(poller.fired());
            std::thread::yield_now();
        }
        heard
    }

    #[test]
    fn an_armed_timer_is_reported_by_the_poller_it_was_made_for() {
        let poller = sys::Poller::new();
        let timer = sys::Timer::between(poller.poll_ref(), TIMER_TOKEN | 7).unwrap();
        timer.arm(HELP_AFTER_NS);
        assert_eq!(heard_until(&poller, TIMER_TOKEN | 7), [TIMER_TOKEN | 7]);
        timer.consume();
    }

    #[test]
    fn a_disarmed_timer_reports_nothing() {
        let poller = sys::Poller::new();
        let (gone, kept) = (TIMER_TOKEN | 1, TIMER_TOKEN | 2);
        let a = sys::Timer::between(poller.poll_ref(), gone).unwrap();
        let b = sys::Timer::between(poller.poll_ref(), kept).unwrap();
        // A fires first if it is armed; the later one reports once it has had the time.
        a.arm(HELP_AFTER_NS);
        a.disarm();
        b.arm(30_000_000);
        assert_eq!(heard_until(&poller, kept), [kept]);
    }

    #[test]
    fn parked_state_goes_to_the_taker_or_back_to_the_owner() {
        let m = member();
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let parked = || {
            Some(Parked {
                session: None,
                h2: None,
            })
        };
        let (_kept_client, kept) = pair(&listener);
        let (_taken_client, taken) = pair(&listener);
        m.park(1, sys::raw(kept.as_sock()), None, parked());
        m.park(2, sys::raw(taken.as_sock()), None, parked());
        // Not ready, so the owner finds its entry untouched and gets the state back.
        assert!(m.take(1, true).is_empty());
        assert!(matches!(m.unpark(0, 1).0, Back::Mine(Some(_))));
        // Taking without a request waiting moves the state with the connection.
        let took = m.take(1, false);
        assert_eq!(took.len(), 1);
        assert!(took[0].parked.is_some());
        assert!(matches!(m.unpark(0, 2).0, Back::Taken));
    }
}
