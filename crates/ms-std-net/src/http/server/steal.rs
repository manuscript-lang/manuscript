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
//! The watcher thread (`ms_rt::watch`) looks at the threads from outside. When a server's thread
//! has run one task since before the watcher's last look (its reactor did not turn and the
//! thread is not resting) and it has waiting connections, the watcher tells a resting thread of
//! the same `serve` call to take the ones with a request waiting. The taker duplicates each
//! handle under the list's lock, takes the parked state, and serves the connection as its own;
//! the owner finds its entry marked taken at its next turn and drops its handle without
//! shutting the connection down. An owner that finds its entry not taken puts the state back.
//!
//! While handlers compute for a millisecond or more the watcher looks every 100 microseconds,
//! so a request waits behind one for about two looks at most. A server whose handlers are
//! short pays two uncontended lock operations per request and nothing else. Listed are
//! connections between requests: plain HTTP/1, TLS with HTTP/1, and HTTP/2 with no open
//! stream. A TLS session is continued on the taker's duplicate of the socket, so it needs no
//! locking while it is served.

use super::h2serve::H2Conn;
use crate::sys::{self, Raw, Wake};
use crate::tls::Session;
use ms_rt::watch::{self, Look};
use std::sync::atomic::{AtomicBool, AtomicI64, AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Duration, Instant};

/// How often the watcher compares how many connections each server of a group has. Taking
/// from a held-up thread moves every connection with a request waiting, which can leave one
/// thread with most of them; the server with the fewest then takes half the difference back.
const BALANCE_EVERY: Duration = Duration::from_millis(10);
/// Ticks a thread is held up before the watcher looks often (a millisecond): a handler that
/// computes this long is worth finding within a tick next time, while a thread the operating
/// system set aside for a moment is not worth the watcher's own time.
const LONG: u64 = 10;
/// The smallest difference in connections worth evening out.
const BALANCE_MIN: usize = 4;
/// When the watcher last compared connection counts (monotonic ns).
static BALANCED: AtomicI64 = AtomicI64::new(0);
/// The groups with at least two servers: the ones the watcher looks at.
static GROUPS: Mutex<Vec<Arc<Group>>> = Mutex::new(Vec::new());

fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

/// What a reactor shares with the watcher: one per thread.
pub struct Beat {
    /// The scheduler index of the reactor's thread.
    thread: usize,
    /// The epoch at the reactor's last turn.
    seen: AtomicU64,
    /// Set when a server of this thread has connections to take or to drop.
    attention: AtomicBool,
    wake: Arc<Wake>,
}

impl Beat {
    pub fn new(wake: Arc<Wake>) -> Arc<Beat> {
        Arc::new(Beat {
            thread: ms_rt::sched::thread(),
            seen: AtomicU64::new(watch::epoch()),
            attention: AtomicBool::new(false),
            wake,
        })
    }

    /// Notes that the reactor turned. Answers whether a server of this thread has work from
    /// another thread (see [`Member::take_orders`] and [`Member::take_dropped`]).
    #[inline]
    pub fn turn(&self) -> bool {
        self.seen.store(watch::epoch(), Ordering::Relaxed);
        self.attention.load(Ordering::Relaxed) && self.attention.swap(false, Ordering::AcqRel)
    }

    fn alert(&self) {
        self.attention.store(true, Ordering::Release);
        self.wake.notify();
    }

    fn rests(&self, resting: u64) -> bool {
        resting & (1 << self.thread) != 0
    }

    /// How many ticks the thread has run one task, if it has since before the watcher's last
    /// look. A thread that just woke has an old turn too, so it must also have been awake since.
    fn held_up(&self, look: Look, resting: u64) -> Option<u64> {
        let since = self
            .seen
            .load(Ordering::Relaxed)
            .max(watch::stirred(self.thread));
        (!self.rests(resting) && since < look.last).then(|| look.now - since)
    }
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
    idle: Mutex<Vec<Entry>>,
    /// Entries of `idle` not taken, readable without the lock.
    waiting: AtomicUsize,
    /// Every connection of the server, waiting or not.
    conns: AtomicUsize,
    /// What the watcher asked this member to take.
    orders: Mutex<Vec<Order>>,
    /// Whether `idle` holds taken entries the owner has not dropped yet.
    dropped: AtomicBool,
    /// Lets a test wait for `waiting` to change instead of polling it.
    #[cfg(test)]
    changed: (Mutex<()>, std::sync::Condvar),
}

impl Member {
    fn order(&self, order: Order) {
        lock(&self.orders).push(order);
        self.beat.alert();
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
        self.listed_changed();
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
            self.listed_changed();
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

    /// Wakes the test waiting in [`Member::wait_listed`].
    #[inline]
    fn listed_changed(&self) {
        #[cfg(test)]
        {
            drop(lock(&self.changed.0));
            self.changed.1.notify_all();
        }
    }

    /// Blocks until exactly `n` connections are listed and not taken. The long timeout only
    /// turns a hang into a failure; the wait ends on the change itself.
    #[cfg(test)]
    pub fn wait_listed(&self, n: usize) {
        let mut guard = lock(&self.changed.0);
        while self.waiting.load(Ordering::Relaxed) != n {
            let (next, result) = self
                .changed
                .1
                .wait_timeout(guard, Duration::from_secs(30))
                .unwrap_or_else(|e| e.into_inner());
            guard = next;
            assert!(
                !result.timed_out(),
                "{} connections listed, wanted {n}",
                self.waiting.load(Ordering::Relaxed)
            );
        }
    }

    /// Counts a connection the server gained (`+1`) or lost (`-1`).
    pub fn count(&self, change: isize) {
        if change > 0 {
            self.conns.fetch_add(1, Ordering::Relaxed);
        } else {
            self.conns.fetch_sub(1, Ordering::Relaxed);
        }
    }

    /// What the watcher asked this member to take.
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
            self.listed_changed();
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
            idle: Mutex::new(Vec::new()),
            waiting: AtomicUsize::new(0),
            conns: AtomicUsize::new(0),
            orders: Mutex::new(Vec::new()),
            dropped: AtomicBool::new(false),
            #[cfg(test)]
            changed: Default::default(),
        });
        let mut members = lock(&self.members);
        members.push(member.clone());
        if members.len() == 2 {
            // The first group with someone to take from: it needs the watcher.
            drop(members);
            let mut groups = lock(&GROUPS);
            if !groups.iter().any(|g| Arc::ptr_eq(g, self)) {
                groups.push(self.clone());
            }
            drop(groups);
            watch::add_hook(tick);
        }
        member
    }

    /// Removes a server that closed.
    pub fn leave(self: &Arc<Group>, member: &Arc<Member>) {
        let mut members = lock(&self.members);
        members.retain(|m| !Arc::ptr_eq(m, member));
        if members.is_empty() {
            drop(members);
            lock(&GROUPS).retain(|g| !Arc::ptr_eq(g, self));
        }
    }

    /// Sends a resting member to each member that is held up with connections waiting.
    /// Answers whether one of them was held up for [`LONG`]: the watcher then looks often, to
    /// find the next one sooner.
    fn watch(&self, look: Look, resting: u64) -> bool {
        let members = lock(&self.members);
        let mut long = false;
        for held in members.iter() {
            let Some(ticks) = held.beat.held_up(look, resting) else {
                continue;
            };
            if held.waiting.load(Ordering::Relaxed) == 0 {
                continue;
            }
            if let Some(helper) = members.iter().find(|m| m.beat.rests(resting)) {
                helper.order(Order {
                    from: held.clone(),
                    limit: usize::MAX,
                    ready_only: true,
                });
                long |= ticks >= LONG;
            }
        }
        long
    }

    /// Has the member with the fewest connections take half its difference to the one with the
    /// most.
    fn balance(&self) {
        let members = lock(&self.members);
        let count = |m: &&Arc<Member>| m.conns.load(Ordering::Relaxed);
        let (Some(most), Some(fewest)) = (
            members.iter().max_by_key(count),
            members.iter().min_by_key(count),
        ) else {
            return;
        };
        let difference = count(&most) - count(&fewest);
        if difference >= BALANCE_MIN.max(count(&most) / 4) {
            fewest.order(Order {
                from: most.clone(),
                limit: difference / 2,
                ready_only: false,
            });
        }
    }
}

/// The watcher's hook: looks at every group, and answers whether to look often for a while.
fn tick(look: Look, resting: u64) -> bool {
    let now = ms_rt::sys::monotonic_ns();
    let balance = now - BALANCED.load(Ordering::Relaxed) >= BALANCE_EVERY.as_nanos() as i64;
    if balance {
        BALANCED.store(now, Ordering::Relaxed);
    }
    let mut often = false;
    for group in lock(&GROUPS).iter() {
        often |= group.watch(look, resting);
        if balance {
            group.balance();
        }
    }
    often
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

    fn member() -> Arc<Member> {
        let beat = Arc::new(Beat {
            thread: 0,
            seen: AtomicU64::new(0),
            attention: AtomicBool::new(false),
            wake: Arc::new(Wake::new().expect("wake")),
        });
        Arc::new(Group::default()).join(&beat)
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
        // Loopback delivery is not instant on every platform: a blocking peek returns when the
        // bytes are there, so the take below sees the connection readable.
        let mut first = [std::mem::MaybeUninit::uninit(); 1];
        assert_eq!(busy.peek(&mut first).unwrap(), 1);
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

    #[test]
    fn balancing_moves_half_the_difference() {
        let group = Arc::new(Group::default());
        let beat = |thread| {
            Arc::new(Beat {
                thread,
                seen: AtomicU64::new(0),
                attention: AtomicBool::new(false),
                wake: Arc::new(Wake::new().expect("wake")),
            })
        };
        let (full, empty) = (group.join(&beat(0)), group.join(&beat(1)));
        // Joining registered the group with the watcher, which balances every few milliseconds and
        // would add its own order between the counts below and the balance this test calls.
        lock(&GROUPS).retain(|g| !Arc::ptr_eq(g, &group));
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let socks: Vec<_> = (0..8).map(|_| pair(&listener)).collect();
        for (i, (_, s)) in socks.iter().enumerate() {
            full.park(i as u64, sys::raw(s.as_sock()), None, None);
            full.count(1);
        }
        group.balance();
        assert!(empty.beat.turn());
        let orders = empty.take_orders();
        assert_eq!(orders.len(), 1);
        let taken = orders[0].from.take(orders[0].limit, orders[0].ready_only);
        assert_eq!(taken.len(), 4);
        assert_eq!(full.waiting.load(Ordering::Relaxed), 4);
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
