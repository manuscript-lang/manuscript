//! The native watcher on macOS: a kqueue holds one `EVFILT_VNODE` registration per tracked path,
//! and a wake-up is turned into events by comparing snapshots, as the polling watcher does.
//! `kevent` is polled without blocking between short sleeps, so a pending `next` stays
//! cancellable.
use super::{Event, Stamp, diff, sleep_slice, snapshot, valid_native};
use crate::err::{Fail, Res};
use crate::sys::{self, CPath};
use alloc::collections::{BTreeMap, VecDeque};
use alloc::vec::Vec;
use core::sync::atomic::{AtomicBool, Ordering};
use ms_rt::glue::poll_cancel;
use ms_rt_abi::{STATUS_CLOSED, STATUS_LIMIT_EXCEEDED, STATUS_NOT_FOUND};

const FFLAGS: u32 = (libc::NOTE_WRITE
    | libc::NOTE_DELETE
    | libc::NOTE_EXTEND
    | libc::NOTE_ATTRIB
    | libc::NOTE_RENAME
    | libc::NOTE_LINK
    | libc::NOTE_REVOKE) as u32;

pub struct Native {
    kq: i32,
    root: Vec<u8>,
    recursive: bool,
    ignore_overflow: bool,
    capacity: usize,
    before: BTreeMap<Vec<u8>, Stamp>,
    /// The descriptor registered for each tracked path.
    fds: BTreeMap<Vec<u8>, i32>,
    queue: VecDeque<Event>,
}

impl Native {
    /// `overflow` is `error` or `ignore`; `max` bounds the paths under the root at start, `events` queued events.
    pub fn new(
        root: &[u8],
        recursive: bool,
        max: i64,
        events: i64,
        overflow: &[u8],
    ) -> Res<Native> {
        valid_native(root, recursive, max, events, overflow)?;
        // SAFETY: plain system call.
        let kq = unsafe { libc::kqueue() };
        if kq < 0 {
            return Err(Fail::raw(sys::errno()));
        }
        // SAFETY: `kq` is a descriptor we own.
        unsafe { libc::fcntl(kq, libc::F_SETFD, libc::FD_CLOEXEC) };
        let mut n = Native {
            kq,
            root: root.to_vec(),
            recursive,
            ignore_overflow: overflow == b"ignore",
            capacity: events as usize,
            before: BTreeMap::new(),
            fds: BTreeMap::new(),
            queue: VecDeque::new(),
        };
        n.before = snapshot(root, recursive, i64::MAX)?;
        n.register()?;
        Ok(n)
    }

    /// Brings the registrations in line with `before`: new paths gain one, vanished paths lose it.
    fn register(&mut self) -> Res<()> {
        let gone: Vec<Vec<u8>> = self
            .fds
            .keys()
            .filter(|p| !self.before.contains_key(*p))
            .cloned()
            .collect();
        for p in gone {
            if let Some(fd) = self.fds.remove(&p) {
                // SAFETY: the descriptor is ours; closing it drops its kqueue registration.
                unsafe { libc::close(fd) };
            }
        }
        let fresh: Vec<Vec<u8>> = self
            .before
            .keys()
            .filter(|p| !self.fds.contains_key(*p))
            .cloned()
            .collect();
        for p in fresh {
            let Some(c) = CPath::new(&p) else { continue };
            // SAFETY: `c` is NUL-terminated.
            let fd = unsafe { libc::open(c.as_ptr(), libc::O_EVTONLY | libc::O_CLOEXEC) };
            if fd < 0 {
                // The path went away since the snapshot; the next comparison reports it.
                if sys::errno() == libc::ENOENT {
                    continue;
                }
                return Err(Fail::errno(sys::errno(), "open", &p));
            }
            let change = libc::kevent {
                ident: fd as usize,
                filter: libc::EVFILT_VNODE,
                flags: libc::EV_ADD | libc::EV_CLEAR,
                fflags: FFLAGS,
                data: 0,
                udata: core::ptr::null_mut(),
            };
            // SAFETY: `change` is one valid change record and no events are requested.
            let added = unsafe {
                libc::kevent(
                    self.kq,
                    &change,
                    1,
                    core::ptr::null_mut(),
                    0,
                    core::ptr::null(),
                )
            };
            if added < 0 {
                let e = sys::errno();
                // SAFETY: the descriptor is ours.
                unsafe { libc::close(fd) };
                return Err(Fail::errno(e, "kevent", &p));
            }
            self.fds.insert(p, fd);
        }
        Ok(())
    }

    /// Whether a registered path changed since the last call; consumes what is pending.
    fn woken(&mut self) -> bool {
        let none = libc::timespec {
            tv_sec: 0,
            tv_nsec: 0,
        };
        let mut woke = false;
        loop {
            // SAFETY: a zeroed `kevent` is a valid out buffer.
            let mut event: libc::kevent = unsafe { core::mem::zeroed() };
            // SAFETY: one event is requested into `event`, with no changes and a zero timeout.
            let got = unsafe { libc::kevent(self.kq, core::ptr::null(), 0, &mut event, 1, &none) };
            if got <= 0 {
                return woke;
            }
            woke = true;
        }
    }

    /// Compares a fresh snapshot with the last one and queues what differs.
    fn refresh(&mut self) -> Res<()> {
        let now = match snapshot(&self.root, self.recursive, i64::MAX) {
            Ok(s) => s,
            Err(f) if f.status == STATUS_NOT_FOUND => BTreeMap::new(),
            Err(f) => return Err(f),
        };
        let mut events = diff(&self.before, &now);
        // A directory's own change is implied by the entries that appeared or vanished in it.
        let paths: Vec<Vec<u8>> = events.iter().map(|e| e.path.clone()).collect();
        events.retain(|e| {
            let is_dir = now
                .get(&e.path)
                .is_some_and(|s| s.0 & sys::S_IFMT == sys::S_IFDIR);
            let mut prefix = e.path.clone();
            prefix.push(b'/');
            e.rename || !is_dir || !paths.iter().any(|p| p.starts_with(&prefix))
        });
        self.before = now;
        self.register()?;
        for e in events {
            if self.queue.len() >= self.capacity {
                if self.ignore_overflow {
                    break;
                }
                return Err(Fail::status(STATUS_LIMIT_EXCEEDED));
            }
            self.queue.push_back(e);
        }
        Ok(())
    }

    pub fn wait(&mut self, closed: &AtomicBool) -> Res<Vec<Event>> {
        loop {
            if let Some(e) = self.queue.pop_front() {
                return Ok(alloc::vec![e]);
            }
            poll_cancel();
            if closed.load(Ordering::Relaxed) {
                return Err(Fail::status(STATUS_CLOSED));
            }
            if self.woken() {
                self.refresh()?;
            } else {
                sleep_slice();
            }
        }
    }
}

impl Drop for Native {
    fn drop(&mut self) {
        for fd in self.fds.values() {
            // SAFETY: the descriptors are ours.
            unsafe { libc::close(*fd) };
        }
        // SAFETY: the descriptor is ours.
        unsafe { libc::close(self.kq) };
    }
}
