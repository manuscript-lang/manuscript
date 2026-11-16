//! Taking waiting connections from a thread that is held up.
//!
//! A connection belongs to the thread that serves it, and a handler is not interrupted, so while
//! one computes, the requests arriving on that thread's other connections wait. This module lets
//! another thread of the same `serve` call serve them instead.
//!
//! Each server keeps the connections that wait for their next request in a shared list
//! ([`Member::idle`]): only a handle and a deadline, since such a connection has no other state.
//! Nothing looks at the threads on a clock. One thread, the rescuer, blocks in a poll until an
//! event says that a thread may hold a request it has not read:
//!
//! * the kernel reports readiness on the thread's poller (see [`sys::Lender`]), or
//! * the thread's reactor read a batch of ready connections and is about to run a handler while
//!   another thread rests ([`Beat::stranded`]): the kernel has nothing more to report for those.
//!
//! Each event arms one deadline, [`HELP_AFTER_NS`]: the longest a ready request waits for its
//! owner. If the thread has not rested since the event ([`ms_rt::sched::rests`] counts) and is
//! not resting now, it has run that whole time and the rescuer tells a resting thread of the same `serve` call to take the
//! listed connections with a request waiting. The taker duplicates each handle under the list's
//! lock and serves the connection as its own; the owner finds its entry marked taken at its next
//! turn and drops its handle without shutting the connection down. With no thread resting, the
//! rescuer waits for the next one to rest ([`ms_rt::sched::watch_rests`]) instead of looking.
//!
//! A server whose handlers are short pays two uncontended lock operations per request, and the
//! rescuer's wake-up per readiness event. Connection counts are evened out when one changes
//! ([`Group::rebalance`]). Only unencrypted HTTP/1 connections between requests are listed: a
//! TLS session or an HTTP/2 connection has state that stays with its thread.

use crate::sys::{self, Raw, Wake};
use mio::{Events, Poll, Registry, Token, Waker};
use ms_rt::sched;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, OnceLock, Weak};
use std::time::{Duration, Instant};

/// The longest a request that is ready on a connection waits for its owner before another
/// thread takes the connection (100 microseconds). A short handler finishes well inside it, so
/// nothing moves; it is a latency allowance armed by an event, not a period.
const HELP_AFTER_NS: i64 = 100_000;
/// The smallest difference in connections worth evening out.
const BALANCE_MIN: usize = 4;

fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

/// What a reactor shares with the rescuer: one per thread.
pub struct Beat {
    id: u64,
    /// The scheduler index of the reactor's thread.
    thread: usize,
    /// Set when a server of this thread has connections to take or to drop.
    attention: AtomicBool,
    wake: Arc<Wake>,
    lender: sys::Lender,
    /// The servers of this thread that share connections.
    members: Mutex<Vec<Weak<Member>>>,
    /// Whether the rescuer listens to this thread.
    watched: AtomicBool,
}

impl Beat {
    pub fn new(poller: &sys::Poller) -> Arc<Beat> {
        Beat::on(poller, sched::thread())
    }

    fn on(poller: &sys::Poller, thread: usize) -> Arc<Beat> {
        static IDS: AtomicU64 = AtomicU64::new(1);
        Arc::new(Beat {
            id: IDS.fetch_add(1, Ordering::Relaxed),
            thread,
            attention: AtomicBool::new(false),
            wake: poller.waker(),
            lender: poller.lender(),
            members: Mutex::new(Vec::new()),
            watched: AtomicBool::new(false),
        })
    }

    /// Notes that the reactor turned. Answers whether a server of this thread has work from
    /// another thread (see [`Member::take_orders`] and [`Member::take_dropped`]).
    #[inline]
    pub fn turn(&self) -> bool {
        self.attention.load(Ordering::Relaxed) && self.attention.swap(false, Ordering::AcqRel)
    }

    /// The reactor read ready connections it has not served yet and is about to run a handler:
    /// tells the rescuer when another thread rests and could take them.
    #[inline]
    pub fn stranded(&self) {
        if self.watched.load(Ordering::Relaxed) {
            rescuer().announce(self.id);
        }
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

    /// Answers what to do about a request this thread may not have read: nothing when it rested
    /// since its rest count was `rests`, or rests now; send a resting thread of each
    /// server's group when it did not; or wait for a thread to rest.
    fn judge(&self, rests: u64, resting: u64) -> Verdict {
        if self.rests_count() != rests || self.rests(resting) {
            return Verdict::Done;
        }
        let mut sent = false;
        for held in self.servers() {
            if held.waiting.load(Ordering::Relaxed) == 0 {
                continue;
            }
            let Some(group) = held.group.upgrade() else {
                continue;
            };
            let Some(helper) = group.helper(&held, resting) else {
                return Verdict::Starved;
            };
            helper.order(Order {
                from: held,
                limit: usize::MAX,
                ready_only: true,
            });
            sent = true;
        }
        if sent { Verdict::Helped } else { Verdict::Done }
    }
}

/// What the rescuer does with an event after its deadline.
#[derive(Debug, PartialEq)]
enum Verdict {
    Done,
    /// A thread was sent; look again later if the thread is still held up.
    Helped,
    /// The thread is held up and no other thread rests.
    Starved,
}

/// A connection waiting for its next request.
struct Entry {
    /// The connection's token in its owner's reactor.
    token: u64,
    sock: Raw,
    deadline: Option<Instant>,
    /// Another thread serves it now; the owner drops its handle when it next looks.
    taken: bool,
}

/// A connection taken from another thread: a handle of its own on the same connection.
pub struct Taken {
    pub sock: socket2::Socket,
    pub deadline: Option<Instant>,
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
    /// What the rescuer asked this member to take.
    orders: Mutex<Vec<Order>>,
    /// Whether `idle` holds taken entries the owner has not dropped yet.
    dropped: AtomicBool,
}

impl Member {
    fn order(&self, order: Order) {
        lock(&self.orders).push(order);
        self.beat.alert();
    }

    /// Lists a connection as waiting and answers its place in the list.
    pub fn park(&self, token: u64, sock: Raw, deadline: Option<Instant>) -> u32 {
        let mut idle = lock(&self.idle);
        idle.push(Entry {
            token,
            sock,
            deadline,
            taken: false,
        });
        self.waiting.fetch_add(1, Ordering::Relaxed);
        (idle.len() - 1) as u32
    }

    /// Removes the entry at `place`, which the owner listed for `token`. Answers whether another
    /// thread took the connection, and the token of the entry that moved into `place`, whose
    /// connection the owner must tell.
    pub fn unpark(&self, place: u32, token: u64) -> (bool, Option<u64>) {
        let mut idle = lock(&self.idle);
        let at = place as usize;
        debug_assert!(idle.get(at).is_some_and(|e| e.token == token));
        if idle.get(at).is_none_or(|e| e.token != token) {
            return (false, None);
        }
        let entry = idle.swap_remove(at);
        if !entry.taken {
            self.waiting.fetch_sub(1, Ordering::Relaxed);
        }
        (entry.taken, idle.get(at).map(|e| e.token))
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

    /// What the rescuer asked this member to take.
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
                });
            }
        }
        if !out.is_empty() {
            self.waiting.fetch_sub(out.len(), Ordering::Relaxed);
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
        members.push(member.clone());
        if members.len() > 1 {
            // With someone to take from, the rescuer listens to every thread of the group.
            let beats: Vec<_> = members.iter().map(|m| m.beat.clone()).collect();
            drop(members);
            for beat in beats {
                rescuer().watch(&beat);
            }
        }
        member
    }

    /// Removes a server that closed.
    pub fn leave(self: &Arc<Group>, member: &Arc<Member>) {
        lock(&self.members).retain(|m| !Arc::ptr_eq(m, member));
    }

    /// A member other than `held` whose thread rests, to take connections from `held`.
    fn helper(&self, held: &Arc<Member>, resting: u64) -> Option<Arc<Member>> {
        lock(&self.members)
            .iter()
            .find(|m| !Arc::ptr_eq(m, held) && m.beat.rests(resting))
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

/// The thread that listens for threads that may hold a request they have not read.
struct Rescuer {
    registry: Registry,
    waker: Waker,
    beats: Mutex<HashMap<u64, Weak<Beat>>>,
    /// Beats whose reactor announced ready connections it has not served.
    inbox: Mutex<Vec<u64>>,
}

const WAKER: Token = Token(usize::MAX);

fn rescuer() -> &'static Rescuer {
    static RESCUER: OnceLock<&'static Rescuer> = OnceLock::new();
    RESCUER.get_or_init(|| {
        let poll = Poll::new().expect("rescuer poll");
        let this: &'static Rescuer = Box::leak(Box::new(Rescuer {
            registry: poll.registry().try_clone().expect("rescuer registry"),
            waker: Waker::new(poll.registry(), WAKER).expect("rescuer waker"),
            beats: Mutex::new(HashMap::new()),
            inbox: Mutex::new(Vec::new()),
        }));
        std::thread::Builder::new()
            .name("ms-rescue".into())
            .spawn(move || this.run(poll))
            .expect("rescuer thread");
        sched::set_rest_hook(|| {
            let _ = rescuer().waker.wake();
        });
        this
    })
}

/// A thread that may hold a request it has not read, and when to look at it again.
struct Pending {
    beat: u64,
    /// The thread's rest count when the event came.
    rests: u64,
    due: i64,
    /// Held up with no thread to help: waits for one to rest, not for the clock.
    starved: bool,
}

impl Rescuer {
    /// Listens to `beat`'s thread.
    fn watch(&self, beat: &Arc<Beat>) {
        if beat.watched.swap(true, Ordering::AcqRel) {
            return;
        }
        lock(&self.beats).insert(beat.id, Arc::downgrade(beat));
        if !beat.lender.register(&self.registry, beat.id) {
            beat.watched.store(false, Ordering::Release);
        }
    }

    /// A reactor tells the rescuer it holds ready connections it has not served.
    fn announce(&self, beat: u64) {
        lock(&self.inbox).push(beat);
        let _ = self.waker.wake();
    }

    fn run(&self, mut poll: Poll) {
        let mut events = Events::with_capacity(64);
        let mut pending: Vec<Pending> = Vec::new();
        let mut heard = Vec::new();
        loop {
            // The only timeout is the earliest deadline an event armed; with none, it blocks.
            let now = ms_rt::sys::monotonic_ns();
            let timeout = pending
                .iter()
                .filter(|p| !p.starved)
                .map(|p| p.due)
                .min()
                .map(|due| Duration::from_nanos((due - now).max(0) as u64));
            if let Err(e) = poll.poll(&mut events, timeout)
                && e.kind() != std::io::ErrorKind::Interrupted
            {
                return;
            }
            let now = ms_rt::sys::monotonic_ns();
            let mut rested = false;
            for e in events.iter() {
                if e.token() == WAKER {
                    rested = true;
                    heard.append(&mut lock(&self.inbox));
                } else {
                    heard.push(e.token().0 as u64);
                }
            }
            for id in heard.drain(..) {
                self.hear(id, now, &mut pending);
            }
            self.settle(now, rested, &mut pending);
        }
    }

    /// An event for `id`: arms its deadline unless one is armed.
    fn hear(&self, id: u64, now: i64, pending: &mut Vec<Pending>) {
        if pending.iter().any(|p| p.beat == id) {
            return;
        }
        let Some(beat) = lock(&self.beats).get(&id).and_then(Weak::upgrade) else {
            return;
        };
        pending.push(Pending {
            beat: id,
            rests: beat.rests_count(),
            due: now + HELP_AFTER_NS,
            starved: false,
        });
    }

    /// Judges what is due, and what waited for a thread to rest when one did.
    fn settle(&self, now: i64, rested: bool, pending: &mut Vec<Pending>) {
        pending.retain_mut(|p| {
            if !(if p.starved { rested } else { p.due <= now }) {
                return true;
            }
            let Some(beat) = lock(&self.beats).get(&p.beat).and_then(Weak::upgrade) else {
                return false;
            };
            let verdict = beat.judge(p.rests, sched::resting_mask());
            p.starved = verdict == Verdict::Starved;
            if verdict == Verdict::Helped {
                // The thread is still held up and more may arrive behind what was taken:
                // look once more, a deadline at a time, until it rests.
                p.due = now + HELP_AFTER_NS;
                return true;
            }
            p.starved
        });
        let starved = pending.iter().any(|p| p.starved);
        sched::watch_rests(starved);
        if starved {
            // A thread that rested before the hook was on did not call it: look once more.
            let resting = sched::resting_mask();
            pending.retain(|p| {
                if !p.starved {
                    return true;
                }
                let beat = lock(&self.beats).get(&p.beat).and_then(Weak::upgrade);
                beat.is_some_and(|b| b.judge(p.rests, resting) == Verdict::Starved)
            });
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sys::AsSock;
    use std::io::Write;
    use std::net::{TcpListener, TcpStream};

    /// A reactor's share on a made-up scheduler thread.
    fn beat(thread: usize) -> Arc<Beat> {
        Beat::on(&sys::Poller::new(), thread)
    }

    fn member() -> Arc<Member> {
        Arc::new(Group::default()).join(&beat(0))
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
            .map(|(i, (_, s))| m.park(10 + i as u64, sys::raw(s.as_sock()), None))
            .collect();
        assert_eq!(places, [0, 1, 2]);
        assert_eq!(m.unpark(0, 10), (false, Some(12)));
        assert_eq!(m.unpark(0, 12), (false, Some(11)));
        assert_eq!(m.unpark(0, 11), (false, None));
        assert_eq!(m.waiting.load(Ordering::Relaxed), 0);
    }

    #[test]
    fn taking_ready_connections_leaves_the_quiet_ones() {
        let m = member();
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let (mut busy_client, busy) = pair(&listener);
        let (_quiet_client, quiet) = pair(&listener);
        m.park(1, sys::raw(quiet.as_sock()), None);
        m.park(2, sys::raw(busy.as_sock()), None);
        busy_client.write_all(b"GET / HTTP/1.1\r\n\r\n").unwrap();
        // Loopback delivery is not instant on every platform.
        await_input(&busy);
        let taken = m.take(usize::MAX, true);
        assert_eq!(taken.len(), 1);
        assert_eq!(taken[0].sock.peer_addr().ok(), busy.peer_addr().ok());
        // The owner learns of it, finds the entry taken, and keeps the quiet one.
        assert!(m.beat.turn());
        assert_eq!(m.take_dropped(), [2]);
        assert_eq!(m.unpark(1, 2), (true, None));
        assert_eq!(m.unpark(0, 1), (false, None));
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
            full.park(i as u64, sys::raw(s.as_sock()), None);
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
    fn a_held_up_thread_is_helped_by_a_resting_one_and_a_turning_thread_is_not() {
        let (_group, full, empty, _socks) = lopsided(2);
        let (held, helper) = (&full.beat, 1u64 << 62);
        let rests = held.rests_count();
        // Nobody rests: wait for a thread to rest instead of looking.
        assert_eq!(held.judge(rests, 0), Verdict::Starved);
        assert!(empty.take_orders().is_empty());
        // The helper rests, the held-up thread did not turn: it is sent.
        assert_eq!(held.judge(rests, helper), Verdict::Helped);
        assert_eq!(empty.take_orders().len(), 1);
        // A thread that rested since the event, or rests, needs no help.
        sched::count_rest(61);
        assert_eq!(held.judge(rests, helper), Verdict::Done);
        assert_eq!(
            held.judge(held.rests_count(), helper | 1 << 61),
            Verdict::Done
        );
        assert!(empty.take_orders().is_empty());
    }
}
