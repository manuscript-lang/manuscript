//! Streaming server exchanges: the handler reads the request body and writes
//! the response itself, in blocking calls on the ms thread.

use super::h1::{self, BodyDecoder, Decoded};
use super::headers::{self, Headers};
use super::server::{self, Conn, DRAIN_LIMIT, Outcome, Pending, Reactor, Server};
use super::sniff;
use crate::conn::SharedIo;
use crate::conn::{Io, Step};
use crate::error::{HttpErr, IoErr, WsErr};
use crate::rt::ScopeOwned;
use crate::wait::{Deadline, Interest, Wait, wait_fd};
use crate::ws::handshake::{self, Rejected};
use crate::ws::socket::{Config, Role, Socket};
use std::cell::RefCell;
use std::rc::{Rc, Weak};
use std::time::Instant;

const CHUNK: usize = 65536;

fn validate_upgrade_headers(fields: &headers::Headers) -> Result<(), WsErr> {
    server::check_response_headers(fields).map_err(|_| WsErr::InvalidInput)?;
    if fields.entries().iter().any(|field| {
        field.name.eq_ignore_ascii_case("upgrade")
            || field
                .name
                .to_ascii_lowercase()
                .starts_with("sec-websocket-")
    }) {
        return Err(WsErr::InvalidInput);
    }
    Ok(())
}

/// Validate the complete size before extending the handshake, so a refusal writes no prefix.
fn append_upgrade_headers(
    response: &mut Vec<u8>,
    fields: &headers::Headers,
    limit: usize,
) -> Result<(), WsErr> {
    let mut size = response.len();
    for field in fields.entries() {
        for value in &field.values {
            size = size.saturating_add(
                field
                    .name
                    .len()
                    .saturating_add(value.len())
                    .saturating_add(4),
            );
            if size > limit {
                return Err(WsErr::LimitExceeded);
            }
        }
    }
    if size > limit {
        return Err(WsErr::LimitExceeded);
    }
    response.truncate(response.len().saturating_sub(2));
    for field in fields.entries() {
        for value in &field.values {
            h1::header_line(response, &field.name, value);
        }
    }
    response.extend_from_slice(b"\r\n");
    Ok(())
}

pub(super) struct ExSt {
    pub method: String,
    pub path: String,
    pub query: String,
    pub protocol: &'static str,
    pub headers: headers::Shared,
    pub decoder: BodyDecoder,
    /// Decoded body bytes not yet handed to the handler.
    pub decoded: Vec<u8>,
    pub remaining_read: usize,
    pub remaining_write: usize,
    pub content_length: Option<usize>,
    pub written: usize,
    pub expect_continue: bool,
    pub minor: u8,
    pub is_head: bool,
    pub sent: bool,
    pub status: i64,
    /// Staged response headers (handler headers), written with the first body bytes.
    pub staged: Headers,
    pub head_written: bool,
    /// HTTP/1 bytes were accepted but the current send/flush did not complete.
    pub output_incomplete: bool,
    pub chunked: bool,
    pub close_conn: bool,
    pub closed: bool,
    pub upgraded: bool,
    pub upgrade_attempted: bool,
    pub websocket: Option<Rc<Socket>>,
    pub deadline: Option<Instant>,
    /// The HTTP/2 stream this exchange answers; `None` on HTTP/1.
    pub h2: Option<u32>,
}

/// One request being handled.
pub struct Exchange {
    pub(super) trace: Weak<super::server::observe::Trace>,
    pub(super) server: Rc<Server>,
    pub(super) conn: Rc<Conn>,
    pub(super) reactor: Rc<Reactor>,
    pub(super) st: RefCell<ExSt>,
}

/// Runs the streaming handler for a queued request.
pub(super) fn run(server: &Server, conn: &Rc<Conn>, reactor: &Reactor, pending: Box<Pending>) {
    let Some(server_rc) = server.rc() else { return };
    let reactor_rc = Reactor::get();
    let Pending {
        head,
        target,
        decoder,
        keep_alive,
        expect_continue,
        started,
        ..
    } = *pending;
    let mut fields = head.fields;
    fields.retain(|(n, _)| !n.eq_ignore_ascii_case("Transfer-Encoding"));
    if let Some(host) = &target.host {
        fields.retain(|(n, _)| !n.eq_ignore_ascii_case("Host"));
        fields.push(("Host".into(), host.clone().into_bytes()));
    }
    let timeout = server.limits.timeout;
    let exchange = Rc::new(Exchange {
        trace: conn
            .st
            .borrow()
            .trace
            .as_ref()
            .map(Rc::downgrade)
            .unwrap_or_default(),
        server: server_rc,
        conn: conn.clone(),
        reactor: reactor_rc,
        st: RefCell::new(ExSt {
            is_head: head.method == "HEAD",
            method: head.method,
            path: target.path,
            query: target.query,
            protocol: if head.minor == 1 {
                "HTTP/1.1"
            } else {
                "HTTP/1.0"
            },
            headers: Rc::new(RefCell::new(Headers::from_received(fields))),
            decoder,
            decoded: Vec::new(),
            remaining_read: server.limits.body,
            remaining_write: server.limits.response,
            content_length: None,
            written: 0,
            expect_continue,
            minor: head.minor,
            sent: false,
            status: 0,
            staged: Headers::new(),
            head_written: false,
            output_incomplete: false,
            chunked: false,
            close_conn: !keep_alive || head.minor == 0,
            closed: false,
            upgraded: false,
            upgrade_attempted: false,
            websocket: None,
            deadline: timeout.map(|t| started + t),
            h2: None,
        }),
    });
    server.enter_handler(reactor);
    let _trace = conn.st.borrow().trace.clone();
    let admission = conn.st.borrow().admission.clone();
    let outcome = server.dispatch.streaming(exchange.clone());
    server.leave_handler(reactor);
    drop(admission);
    let late = timeout.is_some_and(|t| started.elapsed() > t);
    let mut outcome = Some(outcome);
    if !crate::ffi::handler::finish_guarded(|| {
        exchange.finish(outcome.take().expect("one finalization"), late)
    }) {
        server.close_conn(conn, reactor);
    }
}

impl Exchange {
    pub(super) fn timed_out(&self) -> IoErr {
        if let Some(trace) = self.trace.upgrade() {
            trace.fail(super::server::observe::End::TimedOut);
        }
        IoErr::failed("operation timed out")
    }

    pub fn set_route(&self, route: &str) {
        if let Some(trace) = self.trace.upgrade() {
            trace.route(route);
        }
    }

    pub(crate) fn absolute_deadline(&self) -> Option<Instant> {
        self.st.borrow().deadline
    }

    pub(super) fn deadline(&self) -> Deadline {
        match self.st.borrow().deadline {
            Some(at) => Deadline::after(at.saturating_duration_since(Instant::now())),
            None => Deadline::none(),
        }
    }

    pub fn method(&self) -> String {
        self.st.borrow().method.clone()
    }

    pub fn path(&self) -> String {
        self.st.borrow().path.clone()
    }

    pub fn query(&self) -> String {
        self.st.borrow().query.clone()
    }

    pub fn peer_address(&self) -> String {
        self.conn.peer_address.clone()
    }

    pub fn scheme(&self) -> &'static str {
        if self.server.tls_enabled() {
            "https"
        } else {
            "http"
        }
    }

    pub fn protocol(&self) -> &'static str {
        self.st.borrow().protocol
    }

    pub fn headers(&self) -> headers::Shared {
        self.st.borrow().headers.clone()
    }

    pub fn is_closed(&self) -> bool {
        let st = self.st.borrow();
        st.closed || st.upgraded || st.upgrade_attempted
    }

    /// `HttpExchange.close()`: later calls report `Closed`.
    pub fn close(&self) {
        let socket = {
            let mut st = self.st.borrow_mut();
            st.closed = true;
            st.websocket.take()
        };
        if let Some(socket) = socket {
            socket.close();
        }
    }

    fn io(&self) -> Result<Rc<dyn Io>, IoErr> {
        self.conn.st.borrow().io.clone().ok_or(IoErr::Closed)
    }

    /// Reads more bytes from the socket into the connection's input buffer.
    fn fill(&self, deadline: Deadline) -> Result<bool, IoErr> {
        let io = ScopeOwned::new(self.io()?);
        let mut scratch = [0u8; 16 * 1024];
        loop {
            match io.read(&mut scratch) {
                Step::Done(n) => {
                    self.conn
                        .st
                        .borrow_mut()
                        .inbuf
                        .extend_from_slice(&scratch[..n]);
                    return Ok(true);
                }
                Step::Eof => return Ok(false),
                Step::Err(e) => return Err(IoErr::Failed(crate::error::describe_io_error(&e))),
                Step::WantRead | Step::WantWrite => {
                    if wait_fd(io.fd(), Interest::Read, deadline) == Wait::TimedOut {
                        return Err(self.timed_out());
                    }
                }
            }
        }
    }

    /// Writes all of `bytes` and flushes, blocking.
    fn send(&self, bytes: &[u8], deadline: Deadline, final_response: bool) -> Result<(), IoErr> {
        if self.st.borrow().output_incomplete {
            return Err(IoErr::Closed);
        }
        let io = ScopeOwned::new(self.io()?);
        let mut rest = bytes;
        let write_timeout = self.server.limits.write_timeout;
        let mut progress = write_timeout.map_or(Deadline::none(), Deadline::after);
        let mut flush_pending = rest.is_empty();
        loop {
            if deadline.earliest(progress).expired() {
                return Err(self.timed_out());
            }
            if flush_pending {
                match io.flush() {
                    Step::Done(_) => {
                        if rest.is_empty() {
                            self.st.borrow_mut().output_incomplete = false;
                            return Ok(());
                        }
                        flush_pending = false;
                        progress = write_timeout.map_or(Deadline::none(), Deadline::after);
                    }
                    Step::Err(e) => return Err(IoErr::Failed(crate::error::describe_io_error(&e))),
                    Step::Eof => return Err(IoErr::Closed),
                    _ => {
                        if wait_fd(io.fd(), Interest::Write, deadline.earliest(progress))
                            == Wait::TimedOut
                        {
                            return Err(self.timed_out());
                        }
                        continue;
                    }
                }
            }
            // Flush each bounded TLS plaintext chunk before crediting progress.
            match io.write(&rest[..rest.len().min(16 * 1024)]) {
                Step::Done(0) => return Err(IoErr::failed("connection made no write progress")),
                Step::Done(n) => {
                    let mut st = self.st.borrow_mut();
                    st.output_incomplete = true;
                    if final_response {
                        st.sent = true;
                        st.head_written = true;
                    }
                    drop(st);
                    rest = &rest[n..];
                    flush_pending = true;
                }
                Step::Eof => return Err(IoErr::Closed),
                Step::Err(e) => return Err(IoErr::Failed(crate::error::describe_io_error(&e))),
                Step::WantRead | Step::WantWrite => {
                    if wait_fd(io.fd(), Interest::Write, deadline.earliest(progress))
                        == Wait::TimedOut
                    {
                        return Err(self.timed_out());
                    }
                }
            }
        }
    }

    /// `HttpExchange.read(max_bytes)`.
    pub fn read(&self, max_bytes: Option<i64>) -> Result<Option<Vec<u8>>, IoErr> {
        let max = match max_bytes {
            None => CHUNK,
            Some(m) if m <= 0 => return Err(IoErr::InvalidInput),
            Some(m) => (m as usize).min(CHUNK),
        };
        if self.is_closed() {
            return Err(IoErr::Closed);
        }
        let deadline = self.deadline();
        if let Some(id) = self.h2_id() {
            return self.read_h2(id, max, deadline);
        }
        if std::mem::take(&mut self.st.borrow_mut().expect_continue)
            && !self.st.borrow().decoder.is_done()
            && !self.st.borrow().head_written
        {
            self.send(b"HTTP/1.1 100 Continue\r\n\r\n", deadline, false)?;
        }
        loop {
            {
                let mut st = self.st.borrow_mut();
                let want = max.min(st.remaining_read.saturating_add(1));
                if !st.decoded.is_empty() {
                    let n = st.decoded.len().min(want);
                    let chunk: Vec<u8> = st.decoded.drain(..n).collect();
                    if chunk.len() > st.remaining_read {
                        return Err(IoErr::failed("request body limit exceeded"));
                    }
                    st.remaining_read -= chunk.len();
                    return Ok(Some(chunk));
                }
                if st.decoder.is_done() {
                    return Ok(None);
                }
                // Decode what the connection already holds before reading more.
                let mut conn = self.conn.st.borrow_mut();
                if !conn.unread().is_empty() {
                    let mut out = std::mem::take(&mut st.decoded);
                    let fed = st.decoder.feed(conn.unread(), &mut out);
                    if let Some(trace) = self.trace.upgrade() {
                        trace.request_bytes(out.len());
                    }
                    st.decoded = out;
                    match fed {
                        Ok((used, _)) => conn.consume(used),
                        Err(m) => return Err(IoErr::failed(m)),
                    }
                    if !st.decoded.is_empty() || st.decoder.is_done() {
                        continue;
                    }
                }
            }
            if !self.fill(deadline)? {
                let st = self.st.borrow();
                if st.decoder.finish_on_eof() {
                    return Ok(None);
                }
                return Err(IoErr::failed("unexpected EOF"));
            }
        }
    }

    /// `HttpExchange.send_headers(status, headers)`.
    pub fn send_headers(
        &self,
        status: i64,
        headers: &Headers,
        content_length: Option<i64>,
    ) -> Result<(), HttpErr> {
        let length = content_length
            .map(usize::try_from)
            .transpose()
            .map_err(|_| HttpErr::InvalidInput)?;
        if status == 204 && length.is_some() || status == 205 && length.is_some_and(|n| n != 0) {
            return Err(HttpErr::InvalidInput);
        }
        if (200..300).contains(&status) && self.st.borrow().method == "CONNECT" {
            return Err(HttpErr::InvalidInput);
        }
        if !self.st.borrow().is_head
            && server::body_allowed(status)
            && length.is_some_and(|n| n > self.server.limits.response)
        {
            return Err(HttpErr::LimitExceeded);
        }
        if self.is_closed() {
            return Err(HttpErr::Closed);
        }
        if self.st.borrow().sent || !(200..=599).contains(&status) {
            return Err(HttpErr::InvalidInput);
        }
        let limit = self.server.limits.header;
        let mut bytes = 0usize;
        for entry in headers.entries() {
            let name = entry.name.as_str();
            if !headers::valid_name(name)
                || name.eq_ignore_ascii_case("Content-Length")
                || name.eq_ignore_ascii_case("Transfer-Encoding")
                || name.eq_ignore_ascii_case("Connection")
            {
                return Err(HttpErr::InvalidInput);
            }
            for v in &entry.values {
                bytes = bytes.saturating_add(name.len() + v.len() + 4);
                if bytes > limit {
                    return Err(HttpErr::LimitExceeded);
                }
                if !headers::valid_value(v) {
                    return Err(HttpErr::InvalidInput);
                }
            }
        }
        let mut st = self.st.borrow_mut();
        st.sent = true;
        st.status = status;
        st.content_length = length;
        if !st.is_head && server::body_allowed(status) {
            st.remaining_write = st.remaining_write.min(length.unwrap_or(usize::MAX));
        }
        if let Some(trace) = self.trace.upgrade() {
            trace.status(status);
        }
        st.staged = headers.clone();
        Ok(())
    }

    /// Builds and sends the response head with the first body bytes.
    fn write_head(
        &self,
        first: &[u8],
        content_length: Option<usize>,
        deadline: Deadline,
    ) -> Result<(), IoErr> {
        let mut out = ScopeOwned::new(Vec::with_capacity(256 + first.len()));
        {
            let mut st = self.st.borrow_mut();
            h1::status_line(&mut out, st.status as u16);
            let (has_type, has_date) = server::append_handler_headers(&mut out, &st.staged);
            if !has_date {
                h1::header_line(&mut out, "Date", self.reactor_date().as_bytes());
            }
            let allowed = server::body_allowed(st.status);
            let content_length = st.content_length.or_else(|| {
                if st.is_head || st.status == 304 {
                    None
                } else {
                    content_length
                }
            });
            let content_length = if st.status == 205 {
                Some(0)
            } else {
                content_length
            };
            if let Some(n) = content_length
                && (allowed || st.status == 304 || st.status == 205)
            {
                h1::header_line(&mut out, "Content-Length", n.to_string().as_bytes());
            }
            if allowed && !has_type && !first.is_empty() {
                h1::header_line(&mut out, "Content-Type", sniff::detect(first).as_bytes());
            }
            if st.close_conn {
                h1::header_line(&mut out, "Connection", b"close");
            }
            st.chunked = content_length.is_none() && allowed && !st.is_head && st.minor == 1;
            if st.chunked {
                h1::header_line(&mut out, "Transfer-Encoding", b"chunked");
            }
            out.extend_from_slice(b"\r\n");
        }
        let chunked = self.st.borrow().chunked;
        if !first.is_empty() {
            if chunked {
                h1::chunk(&mut out, first);
            } else {
                out.extend_from_slice(first);
            }
        }
        self.send(&out, deadline, true)
    }

    fn reactor_date(&self) -> String {
        self.reactor.date_text()
    }

    /// `HttpExchange.write_bytes(data)`.
    pub fn write(&self, data: &[u8]) -> Result<(), IoErr> {
        if self.st.borrow().output_incomplete {
            return Err(IoErr::Closed);
        }
        if self.is_closed() {
            return Err(IoErr::Closed);
        }
        let (sent, status, is_head, remaining) = {
            let st = self.st.borrow();
            (st.sent, st.status, st.is_head, st.remaining_write)
        };
        if !sent {
            return Err(IoErr::InvalidInput);
        }
        if data.len() > remaining {
            return Err(IoErr::failed("response body limit exceeded"));
        }
        if is_head || !server::body_allowed(status) {
            return Err(IoErr::InvalidInput);
        }
        if let Some(trace) = self.trace.upgrade() {
            trace.response_bytes(data.len());
        }
        let deadline = self.deadline();
        let result = if let Some(id) = self.h2_id() {
            self.write_h2(id, data, deadline)
        } else if !self.st.borrow().head_written {
            self.write_head(data, None, deadline)
        } else {
            let mut out = ScopeOwned::new(Vec::with_capacity(data.len() + 16));
            if self.st.borrow().chunked {
                h1::chunk(&mut out, data);
            } else {
                out.extend_from_slice(data);
            }
            if out.is_empty() {
                Ok(())
            } else {
                self.send(&out, deadline, true)
            }
        };
        match result {
            Ok(()) => {
                let mut st = self.st.borrow_mut();
                st.remaining_write -= data.len();
                st.written += data.len();
                Ok(())
            }
            Err(e) => {
                self.st.borrow_mut().close_conn = true;
                Err(e)
            }
        }
    }

    /// `HttpExchange.upgrade(allowed_origins, subprotocols, max_message_bytes)`:
    /// answers the handshake and turns the connection into a WebSocket that
    /// lives until the handler returns.
    pub fn upgrade(
        &self,
        allowed_origins: &[String],
        subprotocols: &[String],
        max_message_bytes: Option<i64>,
        response_headers: &headers::Headers,
    ) -> Result<Rc<Socket>, WsErr> {
        validate_upgrade_headers(response_headers)?;
        let max = match max_message_bytes {
            Some(n) if n <= 0 => return Err(WsErr::InvalidInput),
            Some(n) => Some(n as u64),
            None => None,
        };
        if subprotocols.iter().any(|p| !headers::valid_name(p)) {
            return Err(WsErr::InvalidInput);
        }
        {
            let st = self.st.borrow();
            if st.closed || st.sent || st.upgraded || st.upgrade_attempted || st.output_incomplete {
                return Err(WsErr::InvalidInput);
            }
        }
        let accepted = {
            let fields: Vec<(String, Vec<u8>)> = {
                let st = self.st.borrow();
                let headers = st.headers.borrow();
                headers
                    .entries()
                    .iter()
                    .flat_map(|e| e.values.iter().map(|v| (e.name.clone(), v.clone())))
                    .collect()
            };
            let host = {
                let st = self.st.borrow();
                let headers = st.headers.borrow();
                headers
                    .first("Host")
                    .map(|h| String::from_utf8_lossy(h).into_owned())
                    .unwrap_or_default()
            };
            let method = self.method();
            let request = handshake::Request {
                method: &method,
                host: &host,
                tls: self.server.tls_enabled(),
                fields: &fields,
            };
            let options = handshake::ServerOptions {
                allowed_origins,
                subprotocols,
                compression: false,
            };
            if self.h2_id().is_some() {
                return Err(self.upgrade_h2(&request, &options));
            }
            handshake::accept(&request, &options)
        };
        let deadline = self.deadline();
        match accepted {
            Err(rejected) => Err(self.reject(rejected, deadline)),
            Ok(accepted) => {
                let mut accepted = ScopeOwned::new(accepted);
                append_upgrade_headers(
                    &mut accepted.response,
                    response_headers,
                    self.server.limits.header,
                )?;
                {
                    let mut st = self.st.borrow_mut();
                    st.upgrade_attempted = true;
                    st.close_conn = true;
                    st.status = 101;
                }
                if let Some(trace) = self.trace.upgrade() {
                    trace.status(101);
                }
                self.send(&accepted.response, deadline, true)
                    .map_err(|e| WsErr::Failed(io_text(e)))?;
                let (io, leftover) = self
                    .server
                    .hijack(&self.conn, &self.reactor)
                    .ok_or(WsErr::Closed)?;
                let (local, peer) = socket_texts(&*io);
                let conn = self
                    .server
                    .owner
                    .adopt_io(Box::new(SharedIo(io)), local, peer)
                    .map_err(WsErr::from)?;
                let accepted = accepted.into_inner();
                let config = Config::new(max, accepted.compress, accepted.subprotocol);
                let socket = Rc::new(Socket::new(conn, leftover, Role::Server, config));
                let mut st = self.st.borrow_mut();
                st.upgraded = true;
                st.websocket = Some(socket.clone());
                Ok(socket)
            }
        }
    }

    /// Answers a refused upgrade and marks the exchange.
    fn reject(&self, rejected: Rejected, deadline: Deadline) -> WsErr {
        {
            let mut st = self.st.borrow_mut();
            st.upgrade_attempted = true;
            st.close_conn = true;
            st.status = rejected.status as i64;
        }
        if let Some(trace) = self.trace.upgrade() {
            trace.status(rejected.status as i64);
            trace.response_bytes(h1::status_text(rejected.status).len() + 1);
        }
        let rejected = ScopeOwned::new(rejected);
        let response = ScopeOwned::new(rejected.response(unix_now(), false));
        let _ = self.send(&response, deadline, true);
        rejected.error()
    }

    /// Completes the request after the handler returned.
    pub(super) fn finish(&self, outcome: Outcome<Result<(), HttpErr>>, late: bool) {
        let server = &self.server;
        let reactor = &self.reactor;
        let conn = &self.conn;
        let (mut failed, fault, cancelled) = match outcome {
            Outcome::Done(Ok(())) => (late, None, false),
            Outcome::Done(Err(_)) => (true, None, false),
            Outcome::Fault(m) => (true, Some(m), false),
            Outcome::Cancelled => (true, None, true),
        };
        {
            let st = self.st.borrow();
            failed |=
                st.output_incomplete || st.upgrade_attempted && !st.upgraded && !st.head_written;
            if st.sent
                && !st.is_head
                && server::body_allowed(st.status)
                && st.content_length.is_some_and(|n| n != st.written)
            {
                failed = true;
            }
        }
        if let Some(m) = &fault {
            eprintln!("HTTP stream handler fault: {m}");
        }
        if let Some(trace) = self.trace.upgrade() {
            use super::server::observe::End;
            if fault.is_some() {
                trace.fail(End::Faulted);
            } else if late {
                trace.fail(End::TimedOut);
            } else if failed || cancelled {
                trace.fail(End::Aborted);
            }
        }
        drop(fault);
        if let Some(id) = self.h2_id() {
            self.finish_h2(id, failed, cancelled, late);
            return;
        }
        let (sent, upgraded, upgrade_attempted, head_written, chunked, status, is_head, minor) = {
            let st = self.st.borrow();
            (
                st.sent,
                st.upgraded,
                st.upgrade_attempted,
                st.head_written,
                st.chunked,
                st.status,
                st.is_head,
                st.minor,
            )
        };
        self.st.borrow_mut().closed = true;
        if upgraded {
            // The WebSocket lives as long as the handler.
            let socket = self.st.borrow_mut().websocket.take();
            if let Some(socket) = socket {
                socket.close();
            }
            if let Some(trace) = self.trace.upgrade() {
                trace.finish();
            }
            server.close_conn(conn, reactor);
            return;
        }
        if self.st.borrow().output_incomplete {
            server.close_conn(conn, reactor);
            return;
        }
        let mut out = ScopeOwned::new(Vec::new());
        let mut close = self.st.borrow().close_conn || server.is_closing();
        if upgrade_attempted && (!failed || head_written) {
            // A terminal upgrade attempt cannot fall back to an empty response.
            close = true;
        } else if failed {
            if !head_written {
                self.failure_bytes(&mut out, late, cancelled);
            } else {
                // Part of the response is out: abort the connection.
                server.close_conn(conn, reactor);
                return;
            }
        } else if !sent {
            if let Some(trace) = self.trace.upgrade() {
                trace.status(204);
            }
            h1::status_line(&mut out, 204);
            h1::header_line(&mut out, "Date", reactor.date_text().as_bytes());
            if close {
                h1::header_line(&mut out, "Connection", b"close");
            }
            out.extend_from_slice(b"\r\n");
        } else if !head_written {
            // Headers only: an empty body.
            let _ = (status, is_head, minor);
            out.clear();
            if self.write_head(&[], Some(0), self.deadline()).is_err() {
                if self.st.borrow().head_written {
                    server.close_conn(conn, reactor);
                } else {
                    self.failure_bytes(&mut out, false, false);
                    server.queue_output(conn, reactor, out.into_inner(), true);
                }
                return;
            }
        } else if chunked {
            out.extend_from_slice(h1::LAST_CHUNK);
        }
        // Reuse the connection only when the request body is gone.
        if !close {
            close = !self.drain_request_body();
        }
        server.queue_output(conn, reactor, out.into_inner(), close);
    }

    fn failure_bytes(&self, out: &mut Vec<u8>, late: bool, cancelled: bool) {
        use super::server::observe::End;
        let is_head = self.st.borrow().is_head;
        let timed_out = late || self.deadline().expired();
        let status = if timed_out || cancelled { 504 } else { 500 };
        if let Some(trace) = self.trace.upgrade() {
            trace.fail(if timed_out {
                End::TimedOut
            } else {
                End::Aborted
            });
            trace.status(status as i64);
            if !is_head {
                trace.response_bytes("request failed\n".len());
            }
        }
        server::error_bytes(out, &self.reactor, status, "request failed", false, is_head);
    }

    /// Skips what is left of the request body that is already buffered.
    fn drain_request_body(&self) -> bool {
        let mut st = self.st.borrow_mut();
        let mut sink = Vec::new();
        if st.decoder.is_done() {
            return true;
        }
        let mut conn = self.conn.st.borrow_mut();
        let mut total = 0usize;
        while !conn.unread().is_empty() && total < DRAIN_LIMIT {
            sink.clear();
            let n = conn.unread().len().min(DRAIN_LIMIT - total);
            match st.decoder.feed(&conn.unread()[..n], &mut sink) {
                Ok((used, state)) => {
                    if let Some(trace) = self.trace.upgrade() {
                        trace.request_bytes(sink.len());
                    }
                    conn.consume(used);
                    total += used;
                    if state == Decoded::Done {
                        return true;
                    }
                    if used == 0 {
                        break;
                    }
                }
                Err(_) => return false,
            }
        }
        st.decoder.is_done()
    }
}

fn io_text(e: IoErr) -> String {
    match e {
        IoErr::Failed(m) => m,
        _ => "connection closed".to_string(),
    }
}

/// Local and peer address text of a stream's socket.
fn socket_texts(io: &dyn Io) -> (String, String) {
    let fd = io.fd();
    let sock = socket2::SockRef::from(&fd);
    let text = |a: std::io::Result<socket2::SockAddr>| {
        a.map(|a| crate::conn::socket_addr_text(&a))
            .unwrap_or_default()
    };
    (text(sock.local_addr()), text(sock.peer_addr()))
}

fn unix_now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |d| d.as_secs() as i64)
}

#[cfg(test)]
mod tests {
    use super::server::tests::{exchange as raw, with_client};
    use super::server::{Dispatch, Limits, Options, Outcome, Reply, Request, Server};
    use super::*;
    use crate::net::Network;

    struct PrefixThenError {
        inner: Rc<dyn Io>,
        remaining: std::cell::Cell<usize>,
        failed: std::cell::Cell<bool>,
    }

    impl Io for PrefixThenError {
        fn fd(&self) -> crate::sys::Borrowed<'_> {
            self.inner.fd()
        }
        fn read(&self, bytes: &mut [u8]) -> Step {
            self.inner.read(bytes)
        }
        fn write(&self, bytes: &[u8]) -> Step {
            let remaining = self.remaining.get();
            if remaining == 0 && !self.failed.replace(true) {
                return Step::Err(std::io::Error::from(std::io::ErrorKind::BrokenPipe));
            }
            let bytes = if remaining == 0 {
                bytes
            } else {
                &bytes[..bytes.len().min(remaining)]
            };
            let result = self.inner.write(bytes);
            if let Step::Done(n) = result {
                self.remaining.set(remaining.saturating_sub(n));
            }
            result
        }
        fn flush(&self) -> Step {
            self.inner.flush()
        }
        fn shutdown_write(&self) -> Result<(), crate::error::NetErr> {
            self.inner.shutdown_write()
        }
        fn shutdown_both(&self) {
            self.inner.shutdown_both();
        }
    }

    struct Commitment;
    impl Dispatch for Commitment {
        fn buffered(&self, _: Request) -> Outcome<Reply> {
            Outcome::Cancelled
        }
        fn streaming(&self, ex: Rc<Exchange>) -> Outcome<Result<(), HttpErr>> {
            let path = ex.path();
            if path == "/response-before-read" {
                ex.send_headers(200, &Headers::new(), None).unwrap();
                ex.write(b"first").unwrap();
                assert_eq!(ex.read(Some(1)).unwrap(), Some(vec![b'x']));
                ex.write(b"last").unwrap();
                return Outcome::Done(Ok(()));
            }
            if path.starts_with("/staged") || path == "/expired" {
                ex.send_headers(200, &Headers::new(), None).unwrap();
                if path == "/staged-fault" {
                    return Outcome::Fault("staged failure".into());
                }
                if path == "/expired" {
                    assert!(
                        ex.write_head(b"never", None, Deadline::after(std::time::Duration::ZERO))
                            .is_err()
                    );
                }
                return Outcome::Cancelled;
            }
            let prefix = if path == "/upgrade-zero" {
                0
            } else if path == "/partial-body" {
                256
            } else {
                5
            };
            let inner = ex.io().unwrap();
            ex.conn.st.borrow_mut().io = Some(Rc::new(PrefixThenError {
                inner,
                remaining: std::cell::Cell::new(prefix),
                failed: std::cell::Cell::new(false),
            }));
            if path == "/partial-interim" {
                assert!(ex.read(Some(1)).is_err());
            } else if path.contains("upgrade") {
                assert!(ex.upgrade(&[], &[], None, &Headers::new()).is_err());
                assert!(ex.is_closed(), "failed upgrades are terminal");
                assert!(ex.send_headers(200, &Headers::new(), None).is_err());
            } else {
                ex.send_headers(200, &Headers::new(), None).unwrap();
                assert!(ex.write(&[b'x'; 512]).is_err());
            }
            // Deliberately swallow the I/O error. Completion must still not
            // append another status or the final chunk to an incomplete send.
            Outcome::Done(Ok(()))
        }
    }

    #[test]
    fn response_commitment_distinguishes_staging_and_partial_output() {
        let net = Network::new_root();
        let server = Server::start(
            &net,
            "127.0.0.1:0",
            Box::new(Commitment),
            Options {
                limits: Limits::default(),
                streaming: true,
                tls: None,
            },
        )
        .unwrap();
        for (path, expected) in [
            ("/staged-fault", "500"),
            ("/staged-cancel", "504"),
            ("/expired", "504"),
        ] {
            let address = server.address().to_string();
            let reply = with_client(move || {
                raw(
                    &address,
                    format!("GET {path} HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")
                        .as_bytes(),
                )
            });
            assert!(
                reply.starts_with(&format!("HTTP/1.1 {expected}")),
                "{path}: {reply}"
            );
        }
        for path in ["/staged-fault", "/staged-cancel", "/expired"] {
            let address = server.address().to_string();
            let reply = with_client(move || {
                raw(
                    &address,
                    format!("HEAD {path} HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")
                        .as_bytes(),
                )
            });
            let expected = if path == "/staged-fault" {
                "500"
            } else {
                "504"
            };
            assert!(
                reply.starts_with(&format!("HTTP/1.1 {expected}")),
                "{reply}"
            );
            assert!(reply.contains("Content-Length: 15\r\n"), "{reply}");
            assert!(reply.ends_with("\r\n\r\n"), "HEAD error body: {reply}");
        }
        for path in [
            "/partial-interim",
            "/partial-final",
            "/partial-body",
            "/partial-upgrade",
            "/upgrade-zero",
        ] {
            let address = server.address().to_string();
            let reply = with_client(move || {
                let request = if path == "/partial-interim" {
                    format!(
                        "POST {path} HTTP/1.1\r\nHost: t\r\nConnection: close\r\nContent-Length: 1\r\nExpect: 100-continue\r\n\r\nx"
                    )
                } else {
                    format!(
                        "GET {path} HTTP/1.1\r\nHost: t\r\nConnection: Upgrade, close\r\nUpgrade: websocket\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n"
                    )
                };
                raw(&address, request.as_bytes())
            });
            if path == "/upgrade-zero" {
                assert!(reply.starts_with("HTTP/1.1 500"), "{reply}");
                continue;
            }
            let expected = if path == "/partial-body" { 256 } else { 5 };
            assert_eq!(reply.len(), expected, "{path}: {reply}");
        }
        let address = server.address().to_string();
        let reply = with_client(move || {
            raw(&address, b"POST /response-before-read HTTP/1.1\r\nHost: t\r\nConnection: close\r\nContent-Length: 1\r\nExpect: 100-continue\r\n\r\nx")
        });
        assert!(reply.starts_with("HTTP/1.1 200"), "{reply}");
        assert!(!reply.contains("100 Continue"), "{reply}");
        assert!(reply.ends_with("0\r\n\r\n"), "{reply}");
        server.close().unwrap();
    }

    #[test]
    fn upgrade_headers_preserve_repeated_fields_and_enforce_the_full_limit() {
        let mut fields = headers::Headers::new();
        fields.append("Set-Cookie", b"a=1").unwrap();
        fields.append("set-cookie", b"b=2").unwrap();
        validate_upgrade_headers(&fields).unwrap();
        let initial = b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n\r\n".to_vec();
        let expected = b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nSet-Cookie: a=1\r\nSet-Cookie: b=2\r\n\r\n";
        let mut response = initial.clone();
        append_upgrade_headers(&mut response, &fields, expected.len()).unwrap();
        assert_eq!(response, expected);
        let mut refused = initial.clone();
        assert!(matches!(
            append_upgrade_headers(&mut refused, &fields, expected.len() - 1),
            Err(WsErr::LimitExceeded)
        ));
        assert_eq!(refused, initial);
    }

    #[test]
    fn upgrade_headers_cannot_override_framing_or_handshake_fields() {
        for name in [
            "Content-Length",
            "Transfer-Encoding",
            "Connection",
            "Upgrade",
            "Sec-WebSocket-Accept",
            "sec-websocket-protocol",
            "Sec-WebSocket-Extensions",
        ] {
            let mut fields = headers::Headers::new();
            fields.append(name, b"value").unwrap();
            assert!(
                matches!(validate_upgrade_headers(&fields), Err(WsErr::InvalidInput)),
                "{name}"
            );
        }
        let fields = headers::Headers::from_received([("X-Test".into(), b"a\r\nb".to_vec())]);
        assert!(matches!(
            validate_upgrade_headers(&fields),
            Err(WsErr::InvalidInput)
        ));
    }

    struct Streamer;

    impl Dispatch for Streamer {
        fn buffered(&self, _: Request) -> Outcome<Reply> {
            Outcome::Cancelled
        }

        fn streaming(&self, ex: Rc<Exchange>) -> Outcome<Result<(), HttpErr>> {
            let result = (|| {
                match ex.path().as_str() {
                    "/ws" => {
                        let socket = ex
                            .upgrade(
                                &[],
                                &["chat".to_string()],
                                Some(1024),
                                &headers::Headers::new(),
                            )
                            .map_err(|_| HttpErr::Closed)?;
                        assert_eq!(socket.subprotocol(), "chat");
                        assert!(ex.is_closed());
                        let message = socket
                            .receive(None)
                            .map_err(|_| HttpErr::Closed)?
                            .expect("message");
                        assert!(message.text);
                        let mut echo = message.data;
                        echo.push(b'!');
                        socket
                            .send(&echo, true, None)
                            .map_err(|_| HttpErr::Closed)?;
                        return Ok(());
                    }
                    "/wsbad" => {
                        assert!(matches!(
                            ex.upgrade(&[], &[], None, &headers::Headers::new()),
                            Err(WsErr::Failed(m)) if m == "websocket: 'Connection' header lacks the 'upgrade' token"
                        ));
                        return Ok(());
                    }
                    "/nobody" => return Ok(()),
                    "/err" => return Err(HttpErr::Failed("nope".into())),
                    "/headers" => {
                        assert_eq!(
                            ex.headers().borrow().text("host").unwrap().unwrap(),
                            vec!["t"]
                        );
                        assert_eq!(ex.method(), "POST");
                        assert_eq!(ex.query(), "q=1");
                        assert_eq!(ex.protocol(), "HTTP/1.1");
                    }
                    _ => {}
                }
                let mut total = Vec::new();
                while let Some(chunk) = ex.read(Some(4)).map_err(|_| HttpErr::Closed)? {
                    assert!(chunk.len() <= 4);
                    total.extend_from_slice(&chunk);
                }
                assert_eq!(ex.read(None), Ok(None));
                assert_eq!(ex.write(b"x"), Err(IoErr::InvalidInput));
                let mut h = Headers::new();
                h.append("X-Seen", total.len().to_string().as_bytes())?;
                ex.send_headers(200, &h, None)?;
                assert_eq!(ex.send_headers(200, &h, None), Err(HttpErr::InvalidInput));
                ex.write(&total).map_err(|_| HttpErr::Closed)?;
                ex.write(b"|done").map_err(|_| HttpErr::Closed)?;
                if ex.path() == "/partial" {
                    return Err(HttpErr::Closed);
                }
                Ok(())
            })();
            Outcome::Done(result)
        }
    }

    fn start(limits: Limits) -> (Rc<Network>, Rc<Server>) {
        let net = Network::new_root();
        let options = Options {
            limits,
            streaming: true,
            tls: None,
        };
        let server = Server::start(&net, "127.0.0.1:0", Box::new(Streamer), options).unwrap();
        (net, server)
    }

    #[test]
    fn streams_request_and_response() {
        let (_net, server) = start(Limits::default());
        let addr = server.address().to_string();
        let a = addr.clone();
        let text = with_client(move || {
            raw(&a, b"POST /headers?q=1 HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\nExpect: 100-continue\r\nConnection: close\r\n\r\n5\r\nhello\r\n6\r\n world\r\n0\r\n\r\n")
        });
        assert!(
            text.starts_with("HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 200 OK"),
            "{text}"
        );
        assert!(text.contains("X-Seen: 11\r\n"), "{text}");
        assert!(text.contains("Transfer-Encoding: chunked\r\n"));
        assert!(
            text.contains("b\r\nhello world\r\n5\r\n|done\r\n0\r\n\r\n"),
            "{text}"
        );

        let a = addr.clone();
        let none = with_client(move || {
            raw(
                &a,
                b"GET /nobody HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n",
            )
        });
        assert!(none.starts_with("HTTP/1.1 204 No Content"), "{none}");
        let a = addr.clone();
        let err = with_client(move || {
            raw(
                &a,
                b"GET /err HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n",
            )
        });
        assert!(err.starts_with("HTTP/1.1 500"), "{err}");
        let a = addr.clone();
        let partial = with_client(move || {
            raw(
                &a,
                b"GET /partial HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n",
            )
        });
        assert!(partial.starts_with("HTTP/1.1 200 OK"), "{partial}");
        assert!(
            !partial.ends_with("0\r\n\r\n"),
            "aborted responses are not terminated: {partial}"
        );
    }

    #[test]
    fn enforces_body_limit_and_reuses_connections() {
        let (_net, server) = start(Limits {
            body: 4,
            ..Limits::default()
        });
        let addr = server.address().to_string();
        let a = addr.clone();
        // The handler fails on a body over the limit, answering 500 through its error.
        let over = with_client(move || {
            raw(&a, b"POST /x HTTP/1.1\r\nHost: t\r\nContent-Length: 9\r\nConnection: close\r\n\r\n123456789")
        });
        assert!(over.starts_with("HTTP/1.1 500"), "{over}");
        let a = addr.clone();
        let two = with_client(move || {
            raw(&a, b"POST /x HTTP/1.1\r\nHost: t\r\nContent-Length: 2\r\n\r\nabGET /nobody HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")
        });
        assert_eq!(two.matches("HTTP/1.1").count(), 2, "{two}");
        assert!(two.contains("X-Seen: 2"));
        assert!(two.contains("204 No Content"));
    }

    #[test]
    fn upgrades_to_a_websocket() {
        let (_net, server) = start(Limits::default());
        let addr = server.address().to_string();
        let a = addr.clone();
        let (head, frames) = with_client(move || {
            use std::io::{Read, Write};
            let mut s = std::net::TcpStream::connect(&a).unwrap();
            s.set_read_timeout(Some(std::time::Duration::from_secs(5)))
                .unwrap();
            s.write_all(b"GET /ws HTTP/1.1\r\nHost: t\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Protocol: chat\r\n\r\n").unwrap();
            // "hi" masked with 01 02 03 04
            s.write_all(&[0x81, 0x82, 1, 2, 3, 4, b'h' ^ 1, b'i' ^ 2])
                .unwrap();
            let mut all = Vec::new();
            let mut buf = [0u8; 1024];
            loop {
                match s.read(&mut buf) {
                    Ok(0) | Err(_) => break,
                    Ok(n) => all.extend_from_slice(&buf[..n]),
                }
            }
            let at = all.windows(4).position(|w| w == b"\r\n\r\n").unwrap() + 4;
            (
                String::from_utf8_lossy(&all[..at]).into_owned(),
                all[at..].to_vec(),
            )
        });
        assert!(
            head.starts_with("HTTP/1.1 101 Switching Protocols\r\n"),
            "{head}"
        );
        assert!(
            head.contains("Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n"),
            "{head}"
        );
        assert!(head.contains("Sec-WebSocket-Protocol: chat\r\n"), "{head}");
        // The echo, then the normal-closure frame sent when the handler returned.
        assert_eq!(&frames[..5], &[0x81, 3, b'h', b'i', b'!']);
        assert_eq!(&frames[5..], &[0x88, 2, 0x03, 0xe8]);
    }

    #[test]
    fn refuses_a_plain_request_to_upgrade() {
        let (_net, server) = start(Limits::default());
        let addr = server.address().to_string();
        let text = with_client(move || {
            raw(
                &addr,
                b"GET /wsbad HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n",
            )
        });
        assert!(text.starts_with("HTTP/1.1 400 Bad Request\r\n"), "{text}");
    }
}
