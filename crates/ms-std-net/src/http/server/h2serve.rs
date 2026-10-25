//! HTTP/2 connections of the server.
//!
//! A connection that negotiated `h2` through ALPN keeps one sans-io
//! [`h2::Connection`] in [`ConnSt::h2`] and stays registered in the reactor for
//! its whole life: frames for every stream arrive on it, also while a handler
//! blocks. Requests are assembled per stream, admitted like HTTP/1 requests and
//! queued for the handler, which runs in its own task on the ms thread.
//!
//! Buffered responses are handed to the stream state and flushed by the reactor
//! as the peer's windows open. Streaming exchanges write response bodies
//! themselves and, when a window or the socket is full, park (`h2_wait`) until
//! the reactor makes progress on the connection. The reactor is the socket's only
//! reader and waiter, so any number of streams can wait at once.

use super::*;
use crate::error::{IoErr, WsErr};
use crate::h2::{self, Event, Header, error_code};
use crate::http::exchange::ExSt;
use crate::sys::Ev;
use crate::wait::{Deadline, Wait, wait_token};
use crate::ws::handshake;

/// Receive window per stream and for the connection.
const STREAM_WINDOW: u32 = 256 * 1024;
const CONN_WINDOW: u32 = 1 << 20;
const MAX_STREAMS: u32 = 250;
/// Output a streaming writer may leave unsent before it waits for the socket.
const OUT_HOLD: usize = 512 * 1024;
/// Hard queued-output cutoff, including headers and peer-provoked control frames.
/// DATA production is bounded below this ceiling before encoding, independently
/// of the peer's advertised window. Tests exercise the production limit.
const OUT_ABUSE: usize = 1 << 20;
/// One minimum-sized DATA frame per stream per pump keeps streams interleaved.
const DATA_QUANTUM: usize = 16 * 1024;
const FRAME_HEADER: usize = 9;
/// Bytes read per reactor turn before yielding to other connections.
const READ_ROUND: usize = 1 << 20;

const CONNECTION_SPECIFIC: [&str; 5] = [
    "connection",
    "proxy-connection",
    "keep-alive",
    "transfer-encoding",
    "upgrade",
];

fn hv(name: &str, value: impl AsRef<[u8]>) -> Header {
    (name.as_bytes().to_vec(), value.as_ref().to_vec())
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Stage {
    /// Headers seen, the request is not complete (buffered mode).
    Collecting,
    /// Admitted; waiting for the handler.
    Queued,
    /// The handler owns the stream.
    Running,
    /// The response body is flushed by the reactor.
    Sending,
}

/// The request line and fields of a stream.
pub(in crate::http) struct Head {
    pub method: String,
    pub path: String,
    pub query: String,
    pub fields: Vec<(String, Vec<u8>)>,
    pub expect_continue: bool,
}

struct Outgoing {
    data: Vec<u8>,
    pos: usize,
}

struct H2Stream {
    trace: Option<Rc<Trace>>,
    admission: Option<Rc<Admission>>,
    response_started: bool,
    is_head: bool,
    head: Option<Head>,
    /// Buffered mode: the body so far. Streaming: unread bytes.
    body: Vec<u8>,
    remote_done: bool,
    reset: bool,
    stage: Stage,
    out: Option<Outgoing>,
    started: Instant,
    deadline: Option<Instant>,
    write_deadline: Option<Instant>,
}

impl H2Stream {
    fn new(remote_done: bool, timeout: Option<Duration>, started: Instant) -> H2Stream {
        H2Stream {
            trace: None,
            admission: None,
            response_started: false,
            is_head: false,
            head: None,
            body: Vec::new(),
            remote_done,
            reset: false,
            stage: Stage::Collecting,
            out: None,
            started,
            deadline: timeout.and_then(|t| started.checked_add(t)),
            write_deadline: None,
        }
    }
}

struct Retiring {
    id: u32,
    end: u128,
    trace: Option<Rc<Trace>>,
    _admission: Option<Rc<Admission>>,
    deadline: Option<Instant>,
    write_deadline: Option<Instant>,
    resetting: bool,
}

struct H2Waiter {
    token: rt::Token,
    conn: Weak<Conn>,
}

impl Drop for H2Waiter {
    fn drop(&mut self) {
        if let Some(conn) = self.conn.upgrade() {
            with_h2(&conn, |h| h.waiters.retain(|&w| w != self.token.id()));
        }
    }
}

pub(in crate::http) struct H2Conn {
    core: h2::Connection,
    clock_origin: Instant,
    header_starts: HashMap<u32, Instant>,
    header_deadline: Option<Instant>,
    header_timeout: Option<Duration>,
    emitted: u128,
    submitted: u128,
    confirmed: u128,
    retiring: VecDeque<Retiring>,
    wire: VecDeque<(u128, u128, u32)>,
    write_timeout: Option<Duration>,
    failed_write: bool,
    streams: HashMap<u32, H2Stream>,
    queue: VecDeque<u32>,
    send_cursor: u32,
    goaway: bool,
    /// Tokens of handlers parked in `h2_wait`, posted when the reactor serves the connection.
    waiters: Vec<u64>,
}

impl H2Conn {
    pub(in crate::http) fn new(limits: &Limits) -> H2Conn {
        let settings = h2::Settings {
            max_concurrent_streams: Some(MAX_STREAMS),
            initial_window_size: STREAM_WINDOW,
            connection_window: CONN_WINDOW,
            max_header_list_size: u32::try_from(limits.header).ok().filter(|&n| n < u32::MAX),
            ..h2::Settings::default()
        };
        H2Conn {
            core: h2::Connection::server(settings),
            clock_origin: Instant::now(),
            header_starts: HashMap::new(),
            header_deadline: None,
            header_timeout: [limits.header_timeout, limits.timeout]
                .into_iter()
                .flatten()
                .min(),
            emitted: 0,
            submitted: 0,
            confirmed: 0,
            retiring: VecDeque::new(),
            wire: VecDeque::new(),
            write_timeout: limits.write_timeout,
            failed_write: false,
            streams: HashMap::new(),
            queue: VecDeque::new(),
            send_cursor: 0,
            goaway: false,
            waiters: Vec::new(),
        }
    }

    fn feed(&mut self, bytes: &[u8]) -> Result<Vec<Event>, h2::H2Error> {
        let marker = self.clock_origin.elapsed().as_nanos().min(u64::MAX as u128) as u64;
        let events = self.core.feed_marked(bytes, marker);
        for (id, marker) in self.core.take_header_starts() {
            if !self.streams.contains_key(&id) {
                self.header_starts
                    .entry(id)
                    .or_insert(self.clock_origin + Duration::from_nanos(marker));
            }
        }
        self.header_deadline = self.core.pending_header_marker().and_then(|marker| {
            self.header_timeout.and_then(|limit| {
                (self.clock_origin + Duration::from_nanos(marker)).checked_add(limit)
            })
        });
        events
    }

    fn is_idle(&self) -> bool {
        self.streams.is_empty() && self.retiring.is_empty() && self.core.open_streams() == 0
    }

    fn take_next(&mut self) -> Option<(u32, Head, Instant)> {
        while let Some(id) = self.queue.pop_front() {
            let Some(s) = self.streams.get_mut(&id) else {
                continue;
            };
            if s.stage != Stage::Queued {
                continue;
            }
            let Some(head) = s.head.take() else { continue };
            s.stage = Stage::Running;
            return Some((id, head, s.started));
        }
        None
    }

    /// Forgets a stream whose response is complete, stopping an unfinished upload.
    fn close_stream(&mut self, id: u32) {
        let Some(s) = self.streams.remove(&id) else {
            return;
        };
        if !s.body.is_empty() {
            self.core.release(id, s.body.len());
        }
        if !s.remote_done {
            self.core.send_rst(id, error_code::NO_ERROR);
        }
        if s.remote_done && !s.response_started {
            return;
        }
        let end = self.emitted + self.core.pending_output_len() as u128;
        if end <= self.confirmed {
            if let Some(trace) = &s.trace {
                trace.finish();
            }
            return;
        }
        self.retiring.push_back(Retiring {
            id,
            end,
            trace: s.trace,
            _admission: s.admission,
            deadline: s.deadline,
            write_deadline: s.write_deadline.or_else(|| {
                self.write_timeout
                    .and_then(|t| Instant::now().checked_add(t))
            }),
            resetting: false,
        });
    }

    fn reset_and_retire(&mut self, id: u32, code: u32) {
        if let Some(trace) = self.streams.get(&id).and_then(|s| s.trace.as_ref()) {
            trace.fail(End::Aborted);
        }
        self.core.reset_encoded_stream(id, code);
        if let Some(stream) = self.streams.get_mut(&id) {
            stream.remote_done = true;
            stream.response_started = true;
        }
        self.close_stream(id);
        let end = self.emitted + self.core.pending_output_len() as u128;
        let now = Instant::now();
        for entry in &mut self.retiring {
            if entry.id == id {
                entry.end = end;
                entry.deadline = None;
                entry.write_deadline =
                    now.checked_add(self.write_timeout.unwrap_or(Duration::ZERO));
                entry.resetting = true;
            }
        }
    }

    fn begin_write(&mut self, id: u32) {
        if let Some(stream) = self.streams.get_mut(&id) {
            stream.response_started = true;
            if stream.write_deadline.is_none() {
                stream.write_deadline = self
                    .write_timeout
                    .and_then(|t| Instant::now().checked_add(t));
            }
        }
    }

    /// Frame ownership is retained alongside the ordered encoded bytes. Header
    /// compression state and partial frames prohibit deleting arbitrary output.
    fn record_output(&mut self, out: &[u8]) {
        let mut at = 0;
        while at + 9 <= out.len() {
            let length =
                ((out[at] as usize) << 16) | ((out[at + 1] as usize) << 8) | out[at + 2] as usize;
            let end = at + 9 + length;
            assert!(end <= out.len(), "HTTP/2 core emits complete frames");
            let id = u32::from_be_bytes(out[at + 5..at + 9].try_into().unwrap()) & 0x7fffffff;
            if id != 0 {
                self.wire
                    .push_back((self.emitted + at as u128, self.emitted + end as u128, id));
            }
            at = end;
        }
        assert_eq!(at, out.len());
        self.emitted += out.len() as u128;
    }

    /// Called only after a bounded plaintext batch has also flushed its TLS
    /// records. Activity on other streams never refreshes this stream's timer.
    fn flushed(&mut self) {
        self.confirmed = self.submitted;
        let now = Instant::now();
        while let Some(&(start, end, id)) = self.wire.front() {
            if start >= self.submitted {
                break;
            }
            let next = self.write_timeout.and_then(|t| now.checked_add(t));
            if let Some(stream) = self.streams.get_mut(&id) {
                stream.write_deadline = next;
            }
            for retiring in &mut self.retiring {
                if retiring.id == id {
                    retiring.write_deadline = if retiring.resetting {
                        now.checked_add(self.write_timeout.unwrap_or(Duration::ZERO))
                    } else {
                        next
                    };
                }
            }
            if end > self.submitted {
                self.wire.front_mut().unwrap().0 = self.submitted;
                break;
            }
            self.wire.pop_front();
        }
        self.retiring.retain(|entry| {
            if entry.end > self.submitted {
                return true;
            }
            if let Some(trace) = &entry.trace {
                trace.finish();
            }
            false
        });
    }

    /// Sends the response head and leaves the body to the reactor.
    fn respond(&mut self, id: u32, headers: Vec<Header>, body: Vec<u8>) {
        self.begin_write(id);
        if let Some(trace) = self.streams.get(&id).and_then(|s| s.trace.as_ref()) {
            let status = headers
                .iter()
                .find(|(n, _)| n == b":status")
                .and_then(|(_, v)| std::str::from_utf8(v).ok())
                .and_then(|s| s.parse().ok())
                .unwrap_or(0);
            trace.status(status);
            trace.response_bytes(body.len());
        }
        let end = body.is_empty();
        if self.core.send_response_headers(id, headers, end).is_err() {
            self.reset_and_retire(id, error_code::INTERNAL_ERROR);
            return;
        }
        if end {
            self.close_stream(id);
            return;
        }
        if let Some(s) = self.streams.get_mut(&id) {
            s.stage = Stage::Sending;
            s.out = Some(Outgoing { data: body, pos: 0 });
        }
    }

    /// An error response like `http.Error`.
    fn error_response(&mut self, reactor: &Reactor, id: u32, status: u16, message: &str) {
        if let Some(s) = self.streams.get(&id)
            && s.stage != Stage::Running
            && let Some(trace) = &s.trace
        {
            trace.reject();
        }
        let mut body = format!("{message}\n").into_bytes();
        let headers = vec![
            hv(":status", status.to_string()),
            hv("content-type", "text/plain; charset=utf-8"),
            hv("x-content-type-options", "nosniff"),
            hv("date", reactor.date_text()),
            hv("content-length", body.len().to_string()),
        ];
        if self.streams.get(&id).is_some_and(|s| s.is_head) {
            body.clear();
        }
        self.respond(id, headers, body);
    }

    fn data_budget(&self, queued: usize) -> usize {
        OUT_HOLD
            .saturating_sub(queued.saturating_add(self.core.pending_output_len()))
            .saturating_sub(FRAME_HEADER)
            .min(DATA_QUANTUM)
    }

    /// Encodes bounded DATA, counting both transport and core staging. Returns
    /// whether progress was made; a writable turn can resume remaining bodies.
    fn send_pending(&mut self, queued: usize) -> bool {
        let mut ids: Vec<u32> = self
            .streams
            .iter()
            .filter(|(_, s)| s.out.is_some())
            .map(|(id, _)| *id)
            .collect();
        ids.sort_unstable();
        if !ids.is_empty() {
            let start = ids.partition_point(|id| *id <= self.send_cursor) % ids.len();
            ids.rotate_left(start);
        }
        let mut progressed = false;
        for id in ids {
            let budget = self.data_budget(queued);
            if budget == 0 {
                break;
            }
            let Some(out) = self.streams.get_mut(&id).and_then(|s| s.out.as_mut()) else {
                continue;
            };
            let end = out.pos.saturating_add(budget).min(out.data.len());
            let sent = self
                .core
                .send_data(id, &out.data[out.pos..end], end == out.data.len());
            out.pos += sent;
            progressed |= sent != 0;
            if sent != 0 {
                self.send_cursor = id;
            }
            if out.pos == out.data.len() {
                self.close_stream(id);
            }
        }
        progressed
    }

    /// Sends at most one bounded streaming DATA frame; None means reset/closed.
    fn send_body(&mut self, id: u32, data: &[u8], queued: usize) -> Option<usize> {
        let alive = self.streams.get(&id).is_some_and(|s| !s.reset);
        let count = data.len().min(self.data_budget(queued));
        alive.then(|| self.core.send_data(id, &data[..count], false))
    }

    /// Expiry discards unencoded payload only. Already encoded frames stay in
    /// order, followed by RST; admission remains held until that reset flushes.
    fn expire(&mut self, now: Instant) -> bool {
        let late: Vec<u32> = self
            .streams
            .iter()
            .filter(|(_, s)| {
                s.stage != Stage::Running
                    && [s.deadline, s.write_deadline]
                        .into_iter()
                        .flatten()
                        .any(|d| d <= now)
            })
            .map(|(id, _)| *id)
            .collect();
        let retiring_late: Vec<u32> = self
            .retiring
            .iter()
            .filter(|s| {
                [s.deadline, s.write_deadline]
                    .into_iter()
                    .flatten()
                    .any(|d| d <= now)
            })
            .map(|s| s.id)
            .collect();
        let mut changed = !late.is_empty();
        for id in late {
            if let Some(trace) = self.streams.get(&id).and_then(|s| s.trace.as_ref()) {
                trace.fail(End::TimedOut);
            }
            self.reset_and_retire(id, error_code::CANCEL);
        }
        for id in retiring_late {
            for entry in &self.retiring {
                if entry.id == id
                    && let Some(trace) = &entry.trace
                {
                    trace.fail(End::TimedOut);
                }
            }
            let resetting = self.retiring.iter().any(|s| s.id == id && s.resetting);
            if resetting {
                self.failed_write = true;
                continue;
            }
            self.reset_and_retire(id, error_code::CANCEL);
            changed = true;
        }
        changed || self.failed_write
    }
}

fn with_h2<R>(conn: &Conn, f: impl FnOnce(&mut H2Conn) -> R) -> Option<R> {
    let mut st = conn.st.borrow_mut();
    st.h2.as_mut().map(|h| f(h))
}

/// Wakes the handlers parked in `h2_wait` on this connection.
pub(super) fn wake_waiters(conn: &Conn) {
    let waiters = with_h2(conn, |h| std::mem::take(&mut h.waiters)).unwrap_or_default();
    for id in waiters {
        rt::post(id);
    }
}

// -------------------------------------------------------------------- output

enum Drain {
    Gone,
    Failed,
    Blocked,
    Empty,
}

/// Moves the core's output into the connection buffer and writes what the
/// socket takes.
fn drain(conn: &Conn) -> Drain {
    let mut guard = conn.st.borrow_mut();
    let st = &mut *guard;
    let (Some(h2), Some(io)) = (st.h2.as_mut(), st.io.clone()) else {
        return Drain::Gone;
    };
    let out = h2.core.take_output();
    h2.record_output(&out);
    if st.out_pos > 64 * 1024 {
        st.outbuf.drain(..st.out_pos);
        st.out_pos = 0;
    }
    st.outbuf.extend_from_slice(&out);
    if st.outbuf.len() - st.out_pos > OUT_ABUSE {
        return Drain::Failed;
    }
    drain_io(&*io, st)
}

fn drain_io(io: &dyn Io, st: &mut ConnSt) -> Drain {
    loop {
        if st.flush_pending {
            match io.flush() {
                Step::Done(_) => {
                    st.flush_pending = false;
                    if let Some(h) = &mut st.h2 {
                        h.flushed();
                    }
                }
                Step::WantRead | Step::WantWrite => return Drain::Blocked,
                Step::Eof | Step::Err(_) => return Drain::Failed,
            }
        }
        if st.out_pos == st.outbuf.len() {
            if let Some(h) = &mut st.h2 {
                h.flushed();
            }
            st.outbuf.clear();
            st.out_pos = 0;
            return Drain::Empty;
        }
        let end = (st.out_pos + 16 * 1024).min(st.outbuf.len());
        match io.write(&st.outbuf[st.out_pos..end]) {
            Step::Done(0) => return Drain::Blocked,
            Step::Done(n) => {
                st.out_pos += n;
                if let Some(h) = &mut st.h2 {
                    h.submitted += n as u128;
                }
                st.flush_pending = true;
            }
            Step::WantRead | Step::WantWrite => return Drain::Blocked,
            Step::Eof | Step::Err(_) => return Drain::Failed,
        }
    }
}

enum Pull {
    Events(Vec<Event>, usize),
    Blocked,
    Eof,
    Failed,
}

fn feed_result(r: Result<Vec<Event>, h2::H2Error>, n: usize) -> Pull {
    match r {
        Ok(events) => Pull::Events(events, n),
        Err(_) => Pull::Failed,
    }
}

impl Server {
    /// Reads and handles what is available, then writes. Returns whether more
    /// input is left for another turn.
    pub(super) fn h2_serve(&self, conn: &Rc<Conn>, reactor: &Reactor) -> bool {
        self.h2_serve_counted(conn, reactor).0
    }

    /// [`Self::h2_serve`], also reporting whether any bytes were consumed.
    fn h2_serve_counted(&self, conn: &Rc<Conn>, reactor: &Reactor) -> (bool, bool) {
        let mut total = 0usize;
        let mut more = false;
        loop {
            match self.h2_pull(conn, reactor) {
                Pull::Events(events, n) => {
                    total += n;
                    self.h2_events(conn, reactor, events);
                    if total >= READ_ROUND {
                        more = true;
                        break;
                    }
                }
                Pull::Blocked => break,
                Pull::Eof => {
                    self.close_conn(conn, reactor);
                    return (false, total > 0);
                }
                Pull::Failed => {
                    self.observer.protocol_error();
                    // The GOAWAY with the error code goes out before closing.
                    let _ = drain(conn);
                    self.close_conn(conn, reactor);
                    return (false, total > 0);
                }
            }
        }
        self.h2_pump_out(conn, reactor);
        wake_waiters(conn);
        (more, total > 0)
    }

    fn h2_pull(&self, conn: &Conn, reactor: &Reactor) -> Pull {
        let mut guard = conn.st.borrow_mut();
        let st = &mut *guard;
        let (Some(h2), Some(io)) = (st.h2.as_mut(), st.io.clone()) else {
            return Pull::Eof;
        };
        let mut scratch = reactor.scratch.borrow_mut();
        match io.read(&mut scratch) {
            Step::Done(n) => feed_result(h2.feed(&scratch[..n]), n),
            Step::Eof | Step::Err(_) => Pull::Eof,
            Step::WantRead | Step::WantWrite => Pull::Blocked,
        }
    }

    /// Queues the core's output and bufferd bodies, writes, and settles the
    /// interest set and a pending close.
    pub(in crate::http) fn h2_pump_out(&self, conn: &Rc<Conn>, reactor: &Reactor) {
        // Drain first: a previously full transport queue must not be mistaken
        // for exhausted flow-control credit after the socket becomes writable.
        let mut state = drain(conn);
        let mut resume = false;
        if matches!(state, Drain::Empty) {
            resume = with_h2(conn, |h| {
                h.send_pending(0) && h.streams.values().any(|s| s.out.is_some())
            })
            .unwrap_or(false);
            state = drain(conn);
        }
        match state {
            Drain::Gone => {}
            Drain::Failed => self.close_conn(conn, reactor),
            Drain::Blocked => self.set_interest(conn, reactor, Ev::IN | Ev::OUT),
            Drain::Empty => {
                self.set_interest(conn, reactor, Ev::IN);
                if resume {
                    // Toggle the logical interest to queue the remembered
                    // writable readiness edge on Unix and rearm it on Windows.
                    self.set_interest(conn, reactor, Ev::IN | Ev::OUT);
                }
                self.h2_settle(conn, reactor);
            }
        }
        let idle = with_h2(conn, |h| {
            h.is_idle() && h.core.pending_header_marker().is_none()
        })
        .unwrap_or(false);
        {
            let mut st = conn.st.borrow_mut();
            if idle {
                if st.deadline.is_none() {
                    st.deadline = self
                        .limits
                        .idle_timeout
                        .and_then(|t| Instant::now().checked_add(t));
                    reactor.note_deadline(st.deadline);
                }
            } else {
                st.deadline = None;
            }
        }
    }

    /// Closes a connection that was told to wind down once its streams are done.
    fn h2_settle(&self, conn: &Rc<Conn>, reactor: &Reactor) {
        let idle = with_h2(conn, |h| h.goaway && h.is_idle()).unwrap_or(false);
        if idle {
            self.close_conn(conn, reactor);
        }
    }

    pub(super) fn h2_begin_close(&self, conn: &Rc<Conn>, reactor: &Reactor) {
        with_h2(conn, |h| {
            if !h.goaway {
                h.goaway = true;
                h.core.shutdown(error_code::NO_ERROR);
            }
        });
        self.h2_pump_out(conn, reactor);
    }

    pub(super) fn h2_sweep(&self, conn: &Rc<Conn>, reactor: &Reactor, now: Instant) {
        if with_h2(conn, |h| h.header_deadline.is_some_and(|at| at <= now)).unwrap_or(false) {
            self.observer.connection_timeout();
            self.close_conn(conn, reactor);
            return;
        }
        if with_h2(conn, |h| h.expire(now)).unwrap_or(false) {
            if with_h2(conn, |h| h.failed_write).unwrap_or(false) {
                self.close_conn(conn, reactor);
                return;
            }
            self.h2_pump_out(conn, reactor);
            wake_waiters(conn);
        }
    }

    /// Parks until the reactor next serves the connection: frames arrived, output
    /// drained, a stream expired, or the connection closed. `false` when the deadline
    /// passed or the connection is gone.
    pub(in crate::http) fn h2_wait(&self, conn: &Rc<Conn>, deadline: Deadline) -> bool {
        let waiter = rt::ScopeOwned::new(H2Waiter {
            token: rt::Token::new(),
            conn: Rc::downgrade(conn),
        });
        if with_h2(conn, |h| h.waiters.push(waiter.token.id())).is_none() {
            return false;
        }
        let got = wait_token(&waiter.token, deadline);
        got == Wait::Ready
    }

    // ----------------------------------------------------------------- events

    fn h2_events(&self, conn: &Rc<Conn>, reactor: &Reactor, events: Vec<Event>) {
        for event in events {
            match event {
                Event::Headers {
                    id,
                    headers,
                    end_stream,
                } => self.h2_headers(conn, reactor, id, headers, end_stream),
                Event::Data {
                    id,
                    data,
                    end_stream,
                } => self.h2_data(conn, reactor, id, data, end_stream),
                Event::Reset { id, .. } => self.h2_reset(conn, id),
                _ => {}
            }
        }
    }

    fn h2_headers(
        &self,
        conn: &Rc<Conn>,
        reactor: &Reactor,
        id: u32,
        headers: Vec<Header>,
        end_stream: bool,
    ) {
        let known = with_h2(conn, |h| h.streams.contains_key(&id)).unwrap_or(false);
        if known {
            // Trailers end the request body.
            self.h2_remote_end(conn, reactor, id, end_stream);
            return;
        }
        let method = headers
            .iter()
            .find(|(n, _)| n == b":method")
            .map(|(_, v)| String::from_utf8_lossy(v).into_owned())
            .unwrap_or_default();
        let path = headers
            .iter()
            .find(|(n, _)| n == b":path")
            .and_then(|(_, v)| std::str::from_utf8(v).ok())
            .and_then(|s| target::parse(s).ok())
            .map(|t| t.path)
            .unwrap_or_default();
        let timeout = self.limits.timeout;
        with_h2(conn, |h| {
            let started = h.header_starts.remove(&id).unwrap_or_else(Instant::now);
            let mut stream = H2Stream::new(end_stream, timeout, started);
            stream.is_head = method == "HEAD";
            stream.trace = Some(self.observer.begin(
                &method,
                &path,
                &conn.peer_address,
                if self.tls.is_some() { "https" } else { "http" },
                started,
            ));
            h.streams.insert(id, stream);
        });
        let head = match self.h2_head(headers) {
            Ok(head) => head,
            Err((status, message)) => {
                with_h2(conn, |h| h.error_response(reactor, id, status, message));
                return;
            }
        };
        let admission = match self.admit() {
            Ok(lease) => lease,
            Err((status, message)) => {
                with_h2(conn, |h| h.error_response(reactor, id, status, message));
                return;
            }
        };
        with_h2(conn, |h| {
            if let Some(s) = h.streams.get_mut(&id) {
                if let Some(trace) = &s.trace {
                    trace.admitted();
                }
                s.admission = Some(admission);
                s.head = Some(head);
            }
        });
        if self.streaming || end_stream {
            self.h2_queue(conn, reactor, id);
        }
    }

    /// Turns a validated header block into the request head.
    fn h2_head(&self, headers: Vec<Header>) -> Result<Head, (u16, &'static str)> {
        let text = |v: Vec<u8>| String::from_utf8(v).map_err(|_| (400, "invalid UTF-8 request"));
        let (mut method, mut path, mut authority, mut host) = (None, None, None, None);
        let mut fields: Vec<(String, Vec<u8>)> = Vec::new();
        let mut cookies: Vec<Vec<u8>> = Vec::new();
        for (name, value) in headers {
            let name = String::from_utf8(name).map_err(|_| (400, "invalid UTF-8 request"))?;
            match name.as_str() {
                ":method" => method = Some(text(value)?),
                ":path" => path = Some(text(value)?),
                ":authority" => authority = Some(text(value)?),
                ":scheme" => {}
                "host" => host = Some(text(value)?),
                "cookie" => cookies.push(value),
                _ => fields.push((name, value)),
            }
        }
        if !cookies.is_empty() {
            fields.push(("cookie".into(), cookies.join(&b"; "[..])));
        }
        let (Some(method), Some(path)) = (method, path) else {
            return Err((400, "Bad Request"));
        };
        let target = target::parse(&path).map_err(|e| (400, e.0))?;
        if let Some(host) = target.host.or(authority).or(host) {
            fields.push(("Host".into(), host.into_bytes()));
        }
        if self.streaming && !Headers::from_received(fields.iter().cloned()).is_text() {
            return Err((400, "invalid UTF-8 request"));
        }
        let declared = fields
            .iter()
            .find(|(n, _)| n == "content-length")
            .and_then(|(_, v)| std::str::from_utf8(v).ok()?.trim().parse::<u64>().ok());
        if !self.streaming && declared.is_some_and(|n| n > self.limits.body as u64) {
            return Err((413, "invalid or oversized request body"));
        }
        let expect_continue = h1::has_token(&fields, "expect", "100-continue");
        Ok(Head {
            method,
            path: target.path,
            query: target.query,
            fields,
            expect_continue,
        })
    }

    /// Admits a request for the handler, or answers 503.
    fn h2_queue(&self, conn: &Rc<Conn>, reactor: &Reactor, id: u32) {
        let queued = with_h2(conn, |h| {
            let Some(s) = h.streams.get_mut(&id) else {
                return false;
            };
            s.stage = Stage::Queued;
            h.queue.push_back(id);
            true
        })
        .unwrap_or(false);
        if queued {
            reactor.ready.borrow_mut().push_back(conn.clone());
        }
    }

    fn h2_remote_end(&self, conn: &Rc<Conn>, reactor: &Reactor, id: u32, end: bool) {
        let complete = with_h2(conn, |h| {
            h.streams.get_mut(&id).is_some_and(|s| {
                s.remote_done |= end;
                end && s.stage == Stage::Collecting
            })
        })
        .unwrap_or(false);
        if complete {
            self.h2_queue(conn, reactor, id);
        }
    }

    fn h2_data(&self, conn: &Rc<Conn>, reactor: &Reactor, id: u32, data: Vec<u8>, end: bool) {
        enum Next {
            Nothing,
            Queue,
            TooBig,
        }
        let limit = self.limits.body;
        let streaming = self.streaming;
        let next = with_h2(conn, |h| {
            let n = data.len();
            let Some(s) = h.streams.get_mut(&id) else {
                h.core.release(id, n);
                return Next::Nothing;
            };
            if let Some(trace) = &s.trace {
                trace.request_bytes(n);
            }
            s.remote_done |= end;
            let collecting = s.stage == Stage::Collecting && !streaming;
            let streamed = streaming && matches!(s.stage, Stage::Queued | Stage::Running);
            if streamed {
                // The handler returns the credit as it reads.
                s.body.extend_from_slice(&data);
                return Next::Nothing;
            }
            h.core.release(id, n);
            if !collecting {
                return Next::Nothing;
            }
            s.body.extend_from_slice(&data);
            if s.body.len() > limit {
                return Next::TooBig;
            }
            if end { Next::Queue } else { Next::Nothing }
        })
        .unwrap_or(Next::Nothing);
        match next {
            Next::Nothing => {}
            Next::Queue => self.h2_queue(conn, reactor, id),
            Next::TooBig => {
                with_h2(conn, |h| {
                    h.error_response(reactor, id, 413, "invalid or oversized request body");
                });
            }
        }
    }

    fn h2_reset(&self, conn: &Rc<Conn>, id: u32) {
        with_h2(conn, |h| {
            h.header_starts.remove(&id);
            let Some(s) = h.streams.get_mut(&id) else {
                return;
            };
            if let Some(trace) = &s.trace {
                trace.fail(End::Aborted);
            }
            s.reset = true;
            s.remote_done = true;
            if s.stage != Stage::Running {
                // The peer reset stops application work, but already encoded
                // bytes still own capacity until the transport has flushed them.
                h.close_stream(id);
            }
        });
    }

    // --------------------------------------------------------------- dispatch

    pub(super) fn h2_dispatch(&self, conn: &Rc<Conn>, reactor: &Reactor) {
        let Some((id, head, started)) = with_h2(conn, H2Conn::take_next).flatten() else {
            return;
        };
        let _trace = with_h2(conn, |h| h.streams.get(&id).and_then(|s| s.trace.clone()));
        let _admission = with_h2(conn, |h| {
            h.streams.get(&id).and_then(|s| s.admission.clone())
        });
        if self.streaming {
            run_streaming(self, conn, reactor, id, head, started);
        } else {
            self.h2_buffered(conn, reactor, id, head, started);
        }
        self.h2_pump_out(conn, reactor);
    }

    fn h2_buffered(
        &self,
        conn: &Rc<Conn>,
        reactor: &Reactor,
        id: u32,
        head: Head,
        started: Instant,
    ) {
        let body = with_h2(conn, |h| {
            h.streams.get_mut(&id).map(|s| std::mem::take(&mut s.body))
        })
        .flatten();
        let Some(body) = body else { return };
        let is_head = head.method == "HEAD";
        let is_connect = head.method == "CONNECT";
        let request = Request {
            peer_address: conn.peer_address.clone(),
            scheme: if self.tls.is_some() { "https" } else { "http" },
            deadline: self.limits.timeout.and_then(|t| started.checked_add(t)),
            method: head.method,
            path: head.path,
            query: head.query,
            headers: Headers::from_received(head.fields),
            body,
            protocol: "HTTP/2.0",
        };
        self.enter_handler(reactor);
        let outcome = self.dispatch.buffered(request);
        self.leave_handler(reactor);
        let late = self.limits.timeout.is_some_and(|t| started.elapsed() > t);
        with_h2(conn, |h| {
            if let Some(trace) = h.streams.get(&id).and_then(|s| s.trace.as_ref()) {
                match &outcome {
                    Outcome::Fault(_) => trace.fail(End::Faulted),
                    Outcome::Cancelled if late => trace.fail(End::TimedOut),
                    Outcome::Cancelled => trace.fail(End::Aborted),
                    _ if late => trace.fail(End::TimedOut),
                    _ => {}
                }
            }
        });
        let result = match outcome {
            Outcome::Cancelled => Err((504, "request cancelled")),
            Outcome::Fault(message) => {
                eprintln!("HTTP handler fault: {message}");
                Err((500, "handler fault"))
            }
            Outcome::Done(_) if late => Err((504, "request cancelled")),
            Outcome::Done(reply) if is_connect && (200..300).contains(&reply.status) => {
                Err((500, "CONNECT tunnels are not supported"))
            }
            Outcome::Done(reply) => self.h2_validate(reply),
        };
        with_h2(conn, |h| match result {
            Ok(reply) => h.reply(reactor, id, reply, is_head),
            Err((status, message)) => h.error_response(reactor, id, status, message),
        });
    }

    fn h2_validate(&self, reply: Reply) -> Result<Reply, (u16, &'static str)> {
        if !(200..=599).contains(&reply.status) || reply.body.len() > self.limits.response {
            return Err((500, "invalid response"));
        }
        check_response_headers(&reply.headers).map_err(|m| (500, m))?;
        Ok(reply)
    }
}

impl H2Conn {
    fn reply(&mut self, reactor: &Reactor, id: u32, reply: Reply, is_head: bool) {
        let allowed = body_allowed(reply.status);
        let length = if reply.status == 205 {
            Some(0)
        } else {
            allowed.then_some(reply.body.len())
        };
        let headers = response_head(
            reactor,
            reply.status as u16,
            &reply.headers,
            length,
            &reply.body,
        );
        let body = if allowed && !is_head {
            reply.body
        } else {
            Vec::new()
        };
        self.respond(id, headers, body);
    }
}

/// The response header block: handler headers lowercased and sorted without
/// the connection-specific ones, then `date`, `content-length` and the sniffed
/// `content-type`.
fn response_head(
    reactor: &Reactor,
    status: u16,
    handler: &Headers,
    content_length: Option<usize>,
    sniff_from: &[u8],
) -> Vec<Header> {
    let mut out = vec![hv(":status", status.to_string())];
    let mut sorted: Vec<(String, &Vec<Vec<u8>>)> = handler
        .entries()
        .iter()
        .map(|e| (e.name.to_ascii_lowercase(), &e.values))
        .collect();
    sorted.sort_by(|a, b| a.0.cmp(&b.0));
    let (mut has_type, mut has_date) = (false, false);
    for (name, values) in sorted {
        if CONNECTION_SPECIFIC.contains(&name.as_str()) {
            continue;
        }
        has_type |= name == "content-type";
        has_date |= name == "date";
        out.extend(values.iter().map(|v| hv(&name, v)));
    }
    if !has_date {
        out.push(hv("date", reactor.date_text()));
    }
    if let Some(n) = content_length {
        out.push(hv("content-length", n.to_string()));
        if !has_type && !sniff_from.is_empty() {
            out.push(hv("content-type", sniff::detect(sniff_from)));
        }
    }
    out
}

// ----------------------------------------------------------------- exchanges

/// Runs the streaming handler for a queued stream.
fn run_streaming(
    server: &Server,
    conn: &Rc<Conn>,
    reactor: &Reactor,
    id: u32,
    head: Head,
    started: Instant,
) {
    let Some(server_rc) = server.rc() else { return };
    let timeout = server.limits.timeout;
    let exchange = Rc::new(Exchange {
        trace: with_h2(conn, |h| {
            h.streams
                .get(&id)
                .and_then(|s| s.trace.as_ref().map(Rc::downgrade))
        })
        .flatten()
        .unwrap_or_default(),
        server: server_rc,
        conn: conn.clone(),
        reactor: Reactor::get(),
        st: RefCell::new(ExSt {
            is_head: head.method == "HEAD",
            method: head.method,
            path: head.path,
            query: head.query,
            protocol: "HTTP/2.0",
            headers: Rc::new(RefCell::new(Headers::from_received(head.fields))),
            decoder: h1::BodyDecoder::new(h1::Framing::None),
            decoded: Vec::new(),
            remaining_read: server.limits.body,
            remaining_write: server.limits.response,
            content_length: None,
            written: 0,
            expect_continue: head.expect_continue,
            minor: 1,
            sent: false,
            status: 0,
            staged: Headers::new(),
            head_written: false,
            output_incomplete: false,
            chunked: false,
            close_conn: false,
            closed: false,
            upgraded: false,
            upgrade_attempted: false,
            websocket: None,
            deadline: timeout.map(|t| started + t),
            h2: Some(id),
        }),
    });
    server.enter_handler(reactor);
    let outcome = server.dispatch.streaming(exchange.clone());
    server.leave_handler(reactor);
    let late = timeout.is_some_and(|t| started.elapsed() > t);
    exchange.finish(outcome, late);
}

impl Exchange {
    fn wait_h2(&self, deadline: Deadline) -> Result<(), IoErr> {
        if self.server.h2_wait(&self.conn, deadline) {
            return Ok(());
        }
        if deadline.expired() {
            return Err(self.timed_out());
        }
        Err(IoErr::Closed)
    }

    pub(in crate::http) fn h2_id(&self) -> Option<u32> {
        self.st.borrow().h2
    }

    /// `HttpExchange.read` on an HTTP/2 stream.
    pub(in crate::http) fn read_h2(
        &self,
        id: u32,
        max: usize,
        deadline: Deadline,
    ) -> Result<Option<Vec<u8>>, IoErr> {
        enum Got {
            Data(Vec<u8>),
            End,
            Wait,
            Broken,
        }
        if std::mem::take(&mut self.st.borrow_mut().expect_continue) {
            let interim = vec![hv(":status", "100")];
            with_h2(&self.conn, |h| {
                h.core.send_response_headers(id, interim, false)
            });
            self.server.h2_pump_out(&self.conn, &self.reactor);
        }
        loop {
            let want = max.min(self.st.borrow().remaining_read.saturating_add(1));
            let got = with_h2(&self.conn, |h| {
                let Some(s) = h.streams.get_mut(&id) else {
                    return Got::Broken;
                };
                if s.reset {
                    return Got::Broken;
                }
                if !s.body.is_empty() {
                    let n = s.body.len().min(want);
                    let chunk: Vec<u8> = s.body.drain(..n).collect();
                    h.core.release(id, n);
                    return Got::Data(chunk);
                }
                if s.remote_done { Got::End } else { Got::Wait }
            })
            .unwrap_or(Got::Broken);
            match got {
                Got::Data(chunk) => {
                    let mut st = self.st.borrow_mut();
                    if chunk.len() > st.remaining_read {
                        return Err(IoErr::failed("request body limit exceeded"));
                    }
                    st.remaining_read -= chunk.len();
                    drop(st);
                    self.server.h2_pump_out(&self.conn, &self.reactor);
                    return Ok(Some(chunk));
                }
                Got::End => return Ok(None),
                Got::Broken => return Err(IoErr::failed("unexpected EOF")),
                Got::Wait => {
                    self.wait_h2(deadline)?;
                }
            }
        }
    }

    /// Sends the response head of a streaming exchange.
    fn send_head_h2(
        &self,
        id: u32,
        first: &[u8],
        content_length: Option<usize>,
        end: bool,
    ) -> Result<(), IoErr> {
        let headers = {
            let st = self.st.borrow();
            let allowed = body_allowed(st.status);
            let length = st
                .content_length
                .or_else(|| content_length.filter(|_| allowed && !st.is_head));
            let length = if st.status == 205 { Some(0) } else { length };
            let sniffed = if allowed { first } else { &[] };
            response_head(&self.reactor, st.status as u16, &st.staged, length, sniffed)
        };
        let sent = with_h2(&self.conn, |h| {
            h.begin_write(id);
            h.core.send_response_headers(id, headers, end).is_ok()
        });
        if sent != Some(true) {
            return Err(IoErr::failed("stream closed"));
        }
        self.st.borrow_mut().head_written = true;
        Ok(())
    }

    /// Bytes of output the socket has not taken yet.
    fn h2_unsent(&self) -> usize {
        let st = self.conn.st.borrow();
        st.outbuf
            .len()
            .saturating_sub(st.out_pos)
            .saturating_add(st.h2.as_ref().map_or(0, |h| h.core.pending_output_len()))
    }

    fn write_deadline_h2(&self, id: u32, absolute: Deadline) -> Deadline {
        let at = with_h2(&self.conn, |h| {
            h.streams.get(&id).and_then(|s| s.write_deadline)
        })
        .flatten();
        let progress = at.map_or(Deadline::none(), |at| {
            Deadline::after(at.saturating_duration_since(Instant::now()))
        });
        absolute.earliest(progress)
    }

    /// `HttpExchange.write` on an HTTP/2 stream: honors the peer's windows.
    pub(in crate::http) fn write_h2(
        &self,
        id: u32,
        data: &[u8],
        deadline: Deadline,
    ) -> Result<(), IoErr> {
        if !self.st.borrow().head_written {
            self.send_head_h2(id, data, None, false)?;
        }
        self.server.h2_pump_out(&self.conn, &self.reactor);
        let mut rest = data;
        let mut round = 0;
        while !rest.is_empty() {
            if self.write_deadline_h2(id, deadline).expired() {
                return Err(self.timed_out());
            }
            while self.h2_unsent() >= OUT_HOLD - FRAME_HEADER {
                self.wait_h2(self.write_deadline_h2(id, deadline))?;
            }
            let sent = {
                let mut st = self.conn.st.borrow_mut();
                let queued = st.outbuf.len().saturating_sub(st.out_pos);
                st.h2.as_mut().and_then(|h| h.send_body(id, rest, queued))
            };
            let Some(n) = sent else {
                return Err(IoErr::failed("stream closed"));
            };
            rest = &rest[n..];
            self.server.h2_pump_out(&self.conn, &self.reactor);
            if !rest.is_empty() && n == 0 {
                self.wait_h2(self.write_deadline_h2(id, deadline))?;
            }
            round += n;
            if round >= READ_ROUND {
                crate::wait::sleep(Duration::ZERO);
                round = 0;
            }
        }
        Ok(())
    }

    /// An upgrade is HTTP/1 only: report what a plain upgrade refusal reports for a request
    /// that is not a WebSocket handshake.
    pub(in crate::http) fn upgrade_h2(
        &self,
        request: &handshake::Request<'_>,
        options: &handshake::ServerOptions<'_>,
    ) -> WsErr {
        match handshake::accept(request, options) {
            Err(rejected) => rejected.error(),
            Ok(_) => WsErr::InvalidInput,
        }
    }

    /// Completes an HTTP/2 stream after the handler returned.
    pub(in crate::http) fn finish_h2(&self, id: u32, failed: bool, cancelled: bool, late: bool) {
        let (sent, head_written, status, is_head) = {
            let mut st = self.st.borrow_mut();
            st.closed = true;
            (st.sent, st.head_written, st.status, st.is_head)
        };
        let reactor = &self.reactor;
        with_h2(&self.conn, |h| {
            if failed && head_written {
                // Part of the response is out: abort only this stream.
                h.reset_and_retire(id, error_code::INTERNAL_ERROR);
            } else if failed {
                let code = if late || cancelled { 504 } else { 500 };
                h.error_response(reactor, id, code, "request failed");
            } else if !sent {
                let headers = vec![hv(":status", "204"), hv("date", reactor.date_text())];
                h.respond(id, headers, Vec::new());
            } else if !head_written {
                let allowed = body_allowed(status);
                let st = self.st.borrow();
                let length = st
                    .content_length
                    .or_else(|| (allowed && !is_head || status == 205).then_some(0));
                let headers = response_head(reactor, status as u16, &st.staged, length, &[]);
                h.respond(id, headers, Vec::new());
            } else {
                h.core.send_data(id, &[], true);
                h.close_stream(id);
            }
        });
        self.server.h2_pump_out(&self.conn, reactor);
    }
}

#[cfg(test)]
mod tests;
