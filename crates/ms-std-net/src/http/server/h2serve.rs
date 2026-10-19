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
//! themselves and, when a window or the socket is full, pump the connection
//! (`h2_wait`) until it drains.

use super::*;
use crate::error::{IoErr, WsErr};
use crate::h2::{self, Event, Header, error_code};
use crate::http::exchange::ExSt;
use crate::wait::{Deadline, Interest, Wait, wait_fd};
use crate::ws::handshake;

/// Receive window per stream and for the connection.
const STREAM_WINDOW: u32 = 256 * 1024;
const CONN_WINDOW: u32 = 1 << 20;
const MAX_STREAMS: u32 = 250;
/// Output a streaming writer may leave unsent before it waits for the socket.
const OUT_HOLD: usize = 512 * 1024;
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
    head: Option<Head>,
    /// Buffered mode: the body so far. Streaming: unread bytes.
    body: Vec<u8>,
    remote_done: bool,
    reset: bool,
    stage: Stage,
    out: Option<Outgoing>,
    started: Instant,
    deadline: Option<Instant>,
}

impl H2Stream {
    fn new(remote_done: bool, timeout: Option<Duration>) -> H2Stream {
        let started = Instant::now();
        H2Stream {
            head: None,
            body: Vec::new(),
            remote_done,
            reset: false,
            stage: Stage::Collecting,
            out: None,
            started,
            deadline: timeout.map(|t| started + t),
        }
    }
}

pub(in crate::http) struct H2Conn {
    core: h2::Connection,
    streams: HashMap<u32, H2Stream>,
    queue: VecDeque<u32>,
    goaway: bool,
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
            streams: HashMap::new(),
            queue: VecDeque::new(),
            goaway: false,
        }
    }

    /// Streams admitted and waiting for the handler.
    pub(in crate::http) fn queued(&self) -> usize {
        self.streams
            .values()
            .filter(|s| s.stage == Stage::Queued)
            .count()
    }

    fn is_idle(&self) -> bool {
        self.streams.is_empty() && self.core.open_streams() == 0
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
    }

    /// Sends the response head and leaves the body to the reactor.
    fn respond(&mut self, id: u32, headers: Vec<Header>, body: Vec<u8>) {
        let end = body.is_empty();
        if self.core.send_response_headers(id, headers, end).is_err() {
            self.core.send_rst(id, error_code::INTERNAL_ERROR);
            self.streams.remove(&id);
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
        let body = format!("{message}\n").into_bytes();
        let headers = vec![
            hv(":status", status.to_string()),
            hv("content-type", "text/plain; charset=utf-8"),
            hv("x-content-type-options", "nosniff"),
            hv("date", reactor.date_text()),
            hv("content-length", body.len().to_string()),
        ];
        self.respond(id, headers, body);
    }

    /// Flushes buffered response bodies as far as the windows allow.
    fn send_pending(&mut self) {
        let ids: Vec<u32> = self
            .streams
            .iter()
            .filter(|(_, s)| s.out.is_some())
            .map(|(id, _)| *id)
            .collect();
        for id in ids {
            let Some(out) = self.streams.get_mut(&id).and_then(|s| s.out.as_mut()) else {
                continue;
            };
            out.pos += self.core.send_data(id, &out.data[out.pos..], true);
            if out.pos == out.data.len() {
                self.close_stream(id);
            }
        }
    }

    /// Sends response body bytes of a streaming exchange; `None` when the
    /// stream is gone or was reset.
    fn send_body(&mut self, id: u32, data: &[u8]) -> Option<usize> {
        let alive = self.streams.get(&id).is_some_and(|s| !s.reset);
        alive.then(|| self.core.send_data(id, data, false))
    }

    /// Resets the streams that waited too long for the rest of their request.
    fn expire(&mut self, now: Instant) -> bool {
        let late: Vec<u32> = self
            .streams
            .iter()
            .filter(|(_, s)| s.stage == Stage::Collecting && s.deadline.is_some_and(|d| d <= now))
            .map(|(id, _)| *id)
            .collect();
        for id in &late {
            self.core.send_rst(*id, error_code::CANCEL);
            self.streams.remove(id);
        }
        !late.is_empty()
    }
}

fn with_h2<R>(conn: &Conn, f: impl FnOnce(&mut H2Conn) -> R) -> Option<R> {
    let mut st = conn.st.borrow_mut();
    st.h2.as_mut().map(|h| f(h))
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
    if st.out_pos > 64 * 1024 {
        st.outbuf.drain(..st.out_pos);
        st.out_pos = 0;
    }
    st.outbuf.extend_from_slice(&out);
    drain_io(&*io, st)
}

fn drain_io(io: &dyn Io, st: &mut ConnSt) -> Drain {
    while st.out_pos < st.outbuf.len() {
        match io.write(&st.outbuf[st.out_pos..]) {
            Step::Done(0) => return Drain::Blocked,
            Step::Done(n) => st.out_pos += n,
            Step::WantRead | Step::WantWrite => return Drain::Blocked,
            Step::Eof | Step::Err(_) => return Drain::Failed,
        }
    }
    match io.flush() {
        Step::Done(_) => {
            st.outbuf.clear();
            st.out_pos = 0;
            st.flush_pending = false;
            Drain::Empty
        }
        Step::WantRead | Step::WantWrite => {
            st.flush_pending = true;
            Drain::Blocked
        }
        Step::Eof | Step::Err(_) => Drain::Failed,
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
                    // The GOAWAY with the error code goes out before closing.
                    let _ = drain(conn);
                    self.close_conn(conn, reactor);
                    return (false, total > 0);
                }
            }
        }
        self.h2_pump_out(conn, reactor);
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
            Step::Done(n) => feed_result(h2.core.feed(&scratch[..n]), n),
            Step::Eof | Step::Err(_) => Pull::Eof,
            Step::WantRead | Step::WantWrite => Pull::Blocked,
        }
    }

    /// Queues the core's output and bufferd bodies, writes, and settles the
    /// interest set and a pending close.
    pub(in crate::http) fn h2_pump_out(&self, conn: &Rc<Conn>, reactor: &Reactor) {
        with_h2(conn, H2Conn::send_pending);
        match drain(conn) {
            Drain::Gone => {}
            Drain::Failed => self.close_conn(conn, reactor),
            Drain::Blocked => self.set_interest(conn, reactor, Readiness::IN | Readiness::OUT),
            Drain::Empty => {
                self.set_interest(conn, reactor, Readiness::IN);
                self.h2_settle(conn, reactor);
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
        if with_h2(conn, |h| h.expire(now)).unwrap_or(false) {
            self.h2_pump_out(conn, reactor);
        }
    }

    /// Waits until the socket is ready, then pumps the connection. `false` when
    /// the deadline passed or the connection is gone.
    pub(in crate::http) fn h2_wait(
        &self,
        conn: &Rc<Conn>,
        reactor: &Reactor,
        deadline: Deadline,
    ) -> bool {
        let (io, write) = {
            let st = conn.st.borrow();
            (
                st.io.clone(),
                st.out_pos < st.outbuf.len() || st.flush_pending,
            )
        };
        let Some(io) = io else { return false };
        // The TLS layer may already hold frames that no readiness event will
        // announce; consume them before blocking.
        let (more, progressed) = self.h2_serve_counted(conn, reactor);
        if more || progressed {
            while self.h2_serve(conn, reactor) {}
            return true;
        }
        let interest = if write {
            Interest::Write
        } else {
            Interest::Read
        };
        if wait_fd(io.fd(), interest, deadline) == Wait::TimedOut {
            return false;
        }
        while self.h2_serve(conn, reactor) {}
        true
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
        let timeout = self.limits.timeout;
        with_h2(conn, |h| {
            h.streams.insert(id, H2Stream::new(end_stream, timeout));
        });
        let head = match self.h2_head(headers) {
            Ok(head) => head,
            Err((status, message)) => {
                with_h2(conn, |h| h.error_response(reactor, id, status, message));
                return;
            }
        };
        with_h2(conn, |h| {
            if let Some(s) = h.streams.get_mut(&id) {
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
        let refusal = {
            let mut s = self.st.borrow_mut();
            if s.closing {
                Some("server closed")
            } else if s.admitted >= self.limits.admission {
                Some("server busy")
            } else {
                s.admitted += 1;
                None
            }
        };
        if let Some(message) = refusal {
            with_h2(conn, |h| h.error_response(reactor, id, 503, message));
            return;
        }
        let queued = with_h2(conn, |h| {
            let Some(s) = h.streams.get_mut(&id) else {
                return false;
            };
            s.stage = Stage::Queued;
            s.deadline = None;
            h.queue.push_back(id);
            true
        })
        .unwrap_or(false);
        if queued {
            reactor.ready.borrow_mut().push_back(conn.clone());
        } else {
            let mut s = self.st.borrow_mut();
            s.admitted = s.admitted.saturating_sub(1);
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
        let was_queued = with_h2(conn, |h| {
            let Some(s) = h.streams.get_mut(&id) else {
                return false;
            };
            s.reset = true;
            s.remote_done = true;
            if s.stage == Stage::Running {
                // The handler notices and cleans up.
                return false;
            }
            let queued = s.stage == Stage::Queued;
            h.streams.remove(&id);
            queued
        })
        .unwrap_or(false);
        if was_queued {
            let mut s = self.st.borrow_mut();
            s.admitted = s.admitted.saturating_sub(1);
        }
    }

    // --------------------------------------------------------------- dispatch

    pub(super) fn h2_dispatch(&self, conn: &Rc<Conn>, reactor: &Reactor) {
        let Some((id, head, started)) = with_h2(conn, H2Conn::take_next).flatten() else {
            return;
        };
        if self.streaming {
            run_streaming(self, conn, reactor, id, head, started);
        } else {
            self.h2_buffered(conn, reactor, id, head, started);
        }
        {
            let mut s = self.st.borrow_mut();
            s.admitted = s.admitted.saturating_sub(1);
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
        let request = Request {
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
        let result = match outcome {
            Outcome::Cancelled => Err((504, "request cancelled")),
            Outcome::Fault(message) => {
                eprintln!("HTTP handler fault: {message}");
                Err((500, "handler fault"))
            }
            Outcome::Done(_) if late => Err((504, "request cancelled")),
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
        let length = allowed.then_some(reply.body.len());
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
            expect_continue: head.expect_continue,
            minor: 1,
            sent: false,
            status: 0,
            staged: Headers::new(),
            head_written: false,
            chunked: false,
            close_conn: false,
            closed: false,
            upgraded: false,
            rejected: false,
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

fn timed_out() -> IoErr {
    IoErr::failed("operation timed out")
}

impl Exchange {
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
                    if !self.server.h2_wait(&self.conn, &self.reactor, deadline) {
                        return Err(timed_out());
                    }
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
            let length = content_length.filter(|_| allowed && !st.is_head);
            let sniffed = if allowed { first } else { &[] };
            response_head(&self.reactor, st.status as u16, &st.staged, length, sniffed)
        };
        let sent = with_h2(&self.conn, |h| {
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
        st.outbuf.len().saturating_sub(st.out_pos)
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
        let mut rest = data;
        while !rest.is_empty() {
            while self.h2_unsent() > OUT_HOLD {
                if !self.server.h2_wait(&self.conn, &self.reactor, deadline) {
                    return Err(timed_out());
                }
            }
            let sent = with_h2(&self.conn, |h| h.send_body(id, rest)).flatten();
            let Some(n) = sent else {
                return Err(IoErr::failed("stream closed"));
            };
            rest = &rest[n..];
            self.server.h2_pump_out(&self.conn, &self.reactor);
            if !rest.is_empty() && !self.server.h2_wait(&self.conn, &self.reactor, deadline) {
                return Err(timed_out());
            }
        }
        Ok(())
    }

    /// An upgrade is HTTP/1 only: report what gorilla reports for a request
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
                h.core.send_rst(id, error_code::INTERNAL_ERROR);
                h.streams.remove(&id);
            } else if failed {
                let code = if late || cancelled { 504 } else { 500 };
                h.error_response(reactor, id, code, "request failed");
            } else if !sent {
                let headers = vec![hv(":status", "204"), hv("date", reactor.date_text())];
                h.respond(id, headers, Vec::new());
            } else if !head_written {
                let allowed = body_allowed(status);
                let st = self.st.borrow();
                let length = (allowed && !is_head).then_some(0);
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
