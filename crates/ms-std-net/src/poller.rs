//! Readiness set of the server reactor: epoll on Linux, kqueue elsewhere.
//!
//! Both are level-triggered. A registration carries a caller token that comes back
//! with each ready descriptor.

use rustix::io;
use std::os::fd::{AsRawFd, BorrowedFd, OwnedFd, RawFd};

/// Readiness a descriptor is watched for, or reports.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Readiness(u8);

impl Readiness {
    pub const IN: Readiness = Readiness(1);
    pub const OUT: Readiness = Readiness(2);
    /// Reported only: the peer hung up.
    pub const HUP: Readiness = Readiness(4);
    /// Reported only: the descriptor failed.
    pub const ERR: Readiness = Readiness(8);

    pub const fn empty() -> Readiness {
        Readiness(0)
    }

    pub const fn contains(self, other: Readiness) -> bool {
        self.0 & other.0 == other.0
    }

    pub const fn intersects(self, other: Readiness) -> bool {
        self.0 & other.0 != 0
    }
}

impl std::ops::BitOr for Readiness {
    type Output = Readiness;

    fn bitor(self, other: Readiness) -> Readiness {
        Readiness(self.0 | other.0)
    }
}

/// One ready descriptor.
#[derive(Clone, Copy, Debug)]
pub struct Ready {
    pub token: u64,
    pub flags: Readiness,
}

pub use imp::Poller;

#[cfg(any(target_os = "linux", target_os = "android"))]
mod imp {
    use super::*;
    use rustix::event::epoll;

    pub struct Poller {
        epoll: OwnedFd,
    }

    fn native(interest: Readiness) -> epoll::EventFlags {
        let mut flags = epoll::EventFlags::empty();
        if interest.contains(Readiness::IN) {
            flags |= epoll::EventFlags::IN;
        }
        if interest.contains(Readiness::OUT) {
            flags |= epoll::EventFlags::OUT;
        }
        flags
    }

    fn portable(flags: epoll::EventFlags) -> Readiness {
        let mut out = Readiness::empty();
        if flags.contains(epoll::EventFlags::IN) {
            out = out | Readiness::IN;
        }
        if flags.contains(epoll::EventFlags::OUT) {
            out = out | Readiness::OUT;
        }
        if flags.intersects(epoll::EventFlags::HUP | epoll::EventFlags::RDHUP) {
            out = out | Readiness::HUP;
        }
        if flags.contains(epoll::EventFlags::ERR) {
            out = out | Readiness::ERR;
        }
        out
    }

    impl Poller {
        pub fn new() -> io::Result<Poller> {
            Ok(Poller {
                epoll: epoll::create(epoll::CreateFlags::CLOEXEC)?,
            })
        }

        pub fn raw(&self) -> RawFd {
            self.epoll.as_raw_fd()
        }

        pub fn add(&self, fd: BorrowedFd<'_>, token: u64, interest: Readiness) -> bool {
            let flags = native(interest);
            epoll::add(&self.epoll, fd, epoll::EventData::new_u64(token), flags).is_ok()
        }

        pub fn modify(&self, fd: BorrowedFd<'_>, token: u64, interest: Readiness) {
            let flags = native(interest);
            let _ = epoll::modify(&self.epoll, fd, epoll::EventData::new_u64(token), flags);
        }

        pub fn delete(&self, fd: BorrowedFd<'_>) {
            let _ = epoll::delete(&self.epoll, fd);
        }

        /// Appends what is ready now, up to the capacity of `out`.
        pub fn poll(&self, out: &mut Vec<Ready>, max: usize) {
            let mut buf = vec![
                epoll::Event {
                    flags: epoll::EventFlags::empty(),
                    data: epoll::EventData::new_u64(0),
                };
                max
            ];
            let timeout = rustix::time::Timespec {
                tv_sec: 0,
                tv_nsec: 0,
            };
            let n = epoll::wait(&self.epoll, &mut buf, Some(&timeout)).unwrap_or_default();
            out.extend(buf[..n].iter().map(|ev| Ready {
                token: ev.data.u64(),
                flags: portable(ev.flags),
            }));
        }
    }
}

#[cfg(not(any(target_os = "linux", target_os = "android")))]
mod imp {
    use super::*;
    use rustix::event::kqueue::{self, Event, EventFilter};
    use std::cell::RefCell;

    pub struct Poller {
        queue: OwnedFd,
        events: RefCell<Vec<Event>>,
    }

    impl Poller {
        pub fn new() -> io::Result<Poller> {
            Ok(Poller {
                queue: kqueue::kqueue()?,
                events: RefCell::new(Vec::new()),
            })
        }

        pub fn raw(&self) -> RawFd {
            self.queue.as_raw_fd()
        }

        /// Applies the changes for one descriptor: each direction is enabled when
        /// wanted and removed otherwise.
        fn apply(&self, fd: BorrowedFd<'_>, token: u64, interest: Readiness) -> bool {
            let raw = fd.as_raw_fd();
            let udata = token as usize as *mut std::ffi::c_void;
            let mut ok = true;
            for (filter, wanted) in [
                (EventFilter::Read(raw), interest.contains(Readiness::IN)),
                (EventFilter::Write(raw), interest.contains(Readiness::OUT)),
            ] {
                let flags = if wanted {
                    kqueue::EventFlags::ADD | kqueue::EventFlags::ENABLE
                } else {
                    kqueue::EventFlags::DELETE
                };
                let change = [Event::new(filter, flags, udata)];
                // SAFETY: `fd` stays open while it is registered; the caller deletes
                // it before closing it (closing also drops the registration).
                let sent =
                    unsafe { kqueue::kevent(&self.queue, &change, &mut Vec::<Event>::new(), None) };
                // Deleting a direction that was never added is not a failure.
                if sent.is_err() && wanted {
                    ok = false;
                }
            }
            ok
        }

        pub fn add(&self, fd: BorrowedFd<'_>, token: u64, interest: Readiness) -> bool {
            self.apply(fd, token, interest)
        }

        pub fn modify(&self, fd: BorrowedFd<'_>, token: u64, interest: Readiness) {
            self.apply(fd, token, interest);
        }

        pub fn delete(&self, fd: BorrowedFd<'_>) {
            self.apply(fd, 0, Readiness::empty());
        }

        /// Appends what is ready now, up to `max` events.
        pub fn poll(&self, out: &mut Vec<Ready>, max: usize) {
            let mut events = self.events.borrow_mut();
            events.clear();
            events.reserve(max);
            let none = std::time::Duration::ZERO;
            // SAFETY: no change list is passed, so no descriptor is referenced.
            let got = unsafe { kqueue::kevent(&self.queue, &[], &mut *events, Some(none)) };
            if got.is_err() {
                return;
            }
            for ev in events.iter() {
                let mut flags = match ev.filter() {
                    EventFilter::Read(_) => Readiness::IN,
                    EventFilter::Write(_) => Readiness::OUT,
                    _ => Readiness::empty(),
                };
                if ev.flags().contains(kqueue::EventFlags::EOF) {
                    flags = flags | Readiness::HUP;
                }
                if ev.flags().contains(kqueue::EventFlags::ERROR) {
                    flags = flags | Readiness::ERR;
                }
                out.push(Ready {
                    token: ev.udata() as usize as u64,
                    flags,
                });
            }
        }
    }
}
