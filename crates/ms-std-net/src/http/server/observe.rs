//! Per-member accounting. No user code runs here; event slots include in-flight
//! reservations, so queued events and their metadata have a fixed memory bound.
use std::cell::{Cell, RefCell};
use std::collections::VecDeque;
use std::rc::Rc;
use std::time::Instant;

#[derive(Clone, Default, Debug)]
pub struct Stats {
    pub requests: i64,
    pub admitted: i64,
    pub rejected: i64,
    pub completed: i64,
    pub aborted: i64,
    pub timed_out: i64,
    pub faulted: i64,
    pub active_requests: i64,
    pub active_connections: i64,
    pub request_body_bytes: i64,
    pub response_body_bytes: i64,
    pub dropped_events: i64,
    pub connections: i64,
    pub rejected_connections: i64,
    pub accept_errors: i64,
    pub protocol_errors: i64,
    pub tls_failures: i64,
    pub connection_timeouts: i64,
}

#[derive(Clone, Debug)]
pub struct Event {
    pub method: String,
    pub path: String,
    pub route: String,
    pub peer_address: String,
    pub scheme: String,
    pub status: i64,
    pub elapsed: i64,
    pub request_body_bytes: i64,
    pub response_body_bytes: i64,
    pub outcome: String,
    pub rejected: bool,
}

#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum End {
    Completed,
    Aborted,
    TimedOut,
    Faulted,
}

pub struct Observer {
    stats: RefCell<Stats>,
    events: RefCell<VecDeque<Event>>,
    capacity: usize,
    reserved: Cell<usize>,
}

fn add(value: &mut i64, amount: usize) {
    *value = value.saturating_add(i64::try_from(amount).unwrap_or(i64::MAX));
}

fn bounded(s: &str, limit: usize) -> String {
    let mut end = s.len().min(limit);
    while !s.is_char_boundary(end) {
        end -= 1;
    }
    s[..end].to_owned()
}

impl Observer {
    pub fn new(capacity: usize) -> Rc<Self> {
        Rc::new(Self {
            stats: RefCell::new(Stats::default()),
            events: RefCell::new(VecDeque::new()),
            capacity,
            reserved: Cell::new(0),
        })
    }

    pub fn connection(&self, rejected: bool) {
        let mut stats = self.stats.borrow_mut();
        add(&mut stats.connections, 1);
        if rejected {
            add(&mut stats.rejected_connections, 1);
        }
    }

    pub fn accept_error(&self) {
        add(&mut self.stats.borrow_mut().accept_errors, 1);
    }
    pub fn protocol_error(&self) {
        add(&mut self.stats.borrow_mut().protocol_errors, 1);
    }
    pub fn tls_failure(&self) {
        add(&mut self.stats.borrow_mut().tls_failures, 1);
    }
    pub fn connection_timeout(&self) {
        add(&mut self.stats.borrow_mut().connection_timeouts, 1);
    }

    pub fn stats(&self, connections: usize) -> Stats {
        let mut result = self.stats.borrow().clone();
        result.active_connections = i64::try_from(connections).unwrap_or(i64::MAX);
        result
    }

    pub fn take_events(&self) -> Vec<Event> {
        self.events.borrow_mut().drain(..).collect()
    }

    pub fn begin(
        self: &Rc<Self>,
        method: &str,
        path: &str,
        peer: &str,
        scheme: &str,
        started: Instant,
    ) -> Rc<Trace> {
        let mut stats = self.stats.borrow_mut();
        add(&mut stats.requests, 1);
        add(&mut stats.active_requests, 1);
        let event = if self.capacity
            > self
                .events
                .borrow()
                .len()
                .saturating_add(self.reserved.get())
        {
            self.reserved.set(self.reserved.get() + 1);
            Some(Event {
                method: bounded(method, 32),
                path: bounded(path.split('?').next().unwrap_or(""), 2048),
                route: String::new(),
                peer_address: bounded(peer, 128),
                scheme: bounded(scheme, 8),
                status: 0,
                elapsed: 0,
                request_body_bytes: 0,
                response_body_bytes: 0,
                outcome: String::new(),
                rejected: false,
            })
        } else {
            None
        };
        Rc::new(Trace {
            owner: self.clone(),
            started,
            event: RefCell::new(event),
            end: Cell::new(End::Completed),
            finished: Cell::new(false),
            rejected: Cell::new(false),
        })
    }
}

pub struct Trace {
    owner: Rc<Observer>,
    started: Instant,
    event: RefCell<Option<Event>>,
    end: Cell<End>,
    finished: Cell<bool>,
    rejected: Cell<bool>,
}

impl Trace {
    pub fn admitted(&self) {
        add(&mut self.owner.stats.borrow_mut().admitted, 1);
    }
    pub fn reject(&self) {
        if !self.rejected.replace(true) {
            add(&mut self.owner.stats.borrow_mut().rejected, 1);
        }
    }
    pub fn finish(&self) {
        self.finished.set(true);
    }
    pub fn fail(&self, end: End) {
        self.end.set(self.end.get().max(end));
    }
    pub fn status(&self, status: i64) {
        if let Some(event) = self.event.borrow_mut().as_mut() {
            event.status = status;
        }
    }
    pub fn route(&self, route: &str) {
        if let Some(event) = self.event.borrow_mut().as_mut() {
            event.route = bounded(route, 2048);
        }
    }
    pub fn request_bytes(&self, bytes: usize) {
        add(&mut self.owner.stats.borrow_mut().request_body_bytes, bytes);
        if let Some(event) = self.event.borrow_mut().as_mut() {
            add(&mut event.request_body_bytes, bytes);
        }
    }
    pub fn response_bytes(&self, bytes: usize) {
        add(
            &mut self.owner.stats.borrow_mut().response_body_bytes,
            bytes,
        );
        if let Some(event) = self.event.borrow_mut().as_mut() {
            add(&mut event.response_body_bytes, bytes);
        }
    }
}

impl Drop for Trace {
    fn drop(&mut self) {
        let end = if !self.finished.get() {
            self.end.get().max(End::Aborted)
        } else {
            self.end.get()
        };
        let mut stats = self.owner.stats.borrow_mut();
        stats.active_requests = stats.active_requests.saturating_sub(1);
        let (counter, name) = match end {
            End::Completed => (&mut stats.completed, "completed"),
            End::Aborted => (&mut stats.aborted, "aborted"),
            End::TimedOut => (&mut stats.timed_out, "timed_out"),
            End::Faulted => (&mut stats.faulted, "faulted"),
        };
        add(counter, 1);
        if let Some(mut event) = self.event.get_mut().take() {
            event.elapsed = self.started.elapsed().as_nanos().min(i64::MAX as u128) as i64;
            event.outcome = name.into();
            event.rejected = self.rejected.get();
            self.owner.reserved.set(self.owner.reserved.get() - 1);
            self.owner.events.borrow_mut().push_back(event);
        } else if self.owner.capacity > 0 {
            add(&mut stats.dropped_events, 1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn saturation_keeps_exact_aggregates_and_bounds_inflight_metadata() {
        let observer = Observer::new(1);
        let first = observer.begin(
            "GET",
            "/ok?secret=yes",
            "127.0.0.1:1",
            "http",
            Instant::now(),
        );
        let second = observer.begin("POST", "/busy", "", "http", Instant::now());
        first.admitted();
        first.response_bytes(4);
        first.finish();
        second.reject();
        second.status(503);
        second.finish();
        drop(second);
        drop(first);
        let stats = observer.stats(2);
        assert_eq!(
            (
                stats.requests,
                stats.completed,
                stats.rejected,
                stats.active_requests,
                stats.dropped_events
            ),
            (2, 2, 1, 0, 1)
        );
        let events = observer.take_events();
        assert_eq!(events.len(), 1);
        assert_eq!(events[0].path, "/ok");
        assert_eq!(events[0].response_body_bytes, 4);
        assert_eq!(observer.reserved.get(), 0);
    }
    #[test]
    fn terminal_precedence_and_disabled_delivery() {
        let observer = Observer::new(0);
        let trace = observer.begin("GET", "/", "", "http", Instant::now());
        trace.fail(End::TimedOut);
        trace.fail(End::Faulted);
        trace.finish();
        drop(trace);
        let trace = observer.begin("GET", "/", "", "http", Instant::now());
        drop(trace);
        let stats = observer.stats(0);
        assert_eq!(
            (
                stats.requests,
                stats.faulted,
                stats.aborted,
                stats.dropped_events
            ),
            (2, 1, 1, 0)
        );
        assert!(observer.take_events().is_empty());
        assert_eq!(bounded("ééé", 3), "é");
    }
}
