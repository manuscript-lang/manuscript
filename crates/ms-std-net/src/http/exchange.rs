//! Streaming server exchanges: the handler reads the request body and writes
//! the response itself, in blocking calls on the ms thread.

use super::h1::{self, BodyDecoder, Decoded};
use super::headers::{self, Headers};
use super::server::{self, Conn, DRAIN_LIMIT, Outcome, Pending, Reactor, Server};
use super::sniff;
use crate::conn::SharedIo;
use crate::conn::{Io, Step};
use crate::error::{HttpErr, IoErr, WsErr};
use crate::wait::{Deadline, Interest, Wait, wait_fd};
use crate::ws::handshake::{self, Rejected};
use crate::ws::socket::{Config, Role, Socket};
use std::cell::RefCell;
use std::rc::Rc;
use std::time::Instant;

const CHUNK: usize = 65536;

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
    /// A read ran past the body limit; a handler failing with no response out answers 413.
    pub body_over_limit: bool,
    /// The request body is not valid chunked framing.
    pub body_malformed: bool,
    pub remaining_write: usize,
    pub expect_continue: bool,
    pub minor: u8,
    pub is_head: bool,
    pub sent: bool,
    /// A successful whole-response send forbids later streaming writes.
    pub response_complete: bool,
    pub status: i64,
    /// Staged response headers (handler headers), written with the first body bytes.
    pub staged: Headers,
    pub head_written: bool,
    pub chunked: bool,
    pub close_conn: bool,
    pub closed: bool,
    pub upgraded: bool,
    pub rejected: bool,
    pub websocket: Option<Rc<Socket>>,
    pub deadline: Option<Instant>,
    /// The HTTP/2 stream this exchange answers; `None` on HTTP/1.
    pub h2: Option<u32>,
}

/// One request being handled.
pub struct Exchange {
    pub(super) server: Rc<Server>,
    pub(super) conn: Rc<Conn>,
    pub(super) reactor: Rc<Reactor>,
    pub(super) st: RefCell<ExSt>,
}

/// Runs the streaming handler for a queued request.
pub(super) fn run(server: &Server, conn: &Rc<Conn>, pending: Box<Pending>) {
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
            body_over_limit: false,
            body_malformed: false,
            remaining_write: server.limits.response,
            expect_continue,
            minor: head.minor,
            sent: false,
            response_complete: false,
            status: 0,
            staged: Headers::new(),
            head_written: false,
            chunked: false,
            close_conn: !keep_alive || head.minor == 0,
            closed: false,
            upgraded: false,
            rejected: false,
            websocket: None,
            deadline: timeout.map(|t| started + t),
            h2: None,
        }),
    });
    crate::rt::limit_current_until(timeout.map(|t| started + t));
    let outcome = server.dispatch.streaming(exchange.clone());
    crate::rt::limit_current_until(None);
    let late = timeout.is_some_and(|t| started.elapsed() > t);
    exchange.finish(outcome, late);
}

impl Exchange {
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

    pub fn protocol(&self) -> &'static str {
        self.st.borrow().protocol
    }

    pub fn headers(&self) -> headers::Shared {
        self.st.borrow().headers.clone()
    }

    pub fn is_closed(&self) -> bool {
        let st = self.st.borrow();
        st.closed || st.upgraded || st.rejected
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
        let io = self.io()?;
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
                        return Err(IoErr::failed("operation timed out"));
                    }
                }
            }
        }
    }

    /// Writes all of `bytes` and flushes, blocking.
    fn send(&self, bytes: &[u8], deadline: Deadline) -> Result<(), IoErr> {
        let io = self.io()?;
        let mut rest = bytes;
        while !rest.is_empty() {
            match io.write(rest) {
                Step::Done(n) => rest = &rest[n..],
                Step::Eof => return Err(IoErr::failed("connection closed")),
                Step::Err(e) => return Err(IoErr::Failed(crate::error::describe_io_error(&e))),
                Step::WantRead | Step::WantWrite => {
                    if wait_fd(io.fd(), Interest::Write, deadline) == Wait::TimedOut {
                        return Err(IoErr::failed("operation timed out"));
                    }
                }
            }
        }
        loop {
            match io.flush() {
                Step::Done(_) => return Ok(()),
                Step::Err(e) => return Err(IoErr::Failed(crate::error::describe_io_error(&e))),
                _ => {
                    if wait_fd(io.fd(), Interest::Write, deadline) == Wait::TimedOut {
                        return Err(IoErr::failed("operation timed out"));
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
        {
            self.send(b"HTTP/1.1 100 Continue\r\n\r\n", deadline)?;
        }
        loop {
            {
                let mut st = self.st.borrow_mut();
                let want = max.min(st.remaining_read.saturating_add(1));
                if !st.decoded.is_empty() {
                    let n = st.decoded.len().min(want);
                    let chunk: Vec<u8> = st.decoded.drain(..n).collect();
                    if chunk.len() > st.remaining_read {
                        st.body_over_limit = true;
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
                    st.decoded = out;
                    match fed {
                        Ok((used, _)) => conn.consume(used),
                        Err(m) => {
                            st.body_malformed = true;
                            return Err(IoErr::failed(m));
                        }
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
    pub fn send_headers(&self, status: i64, headers: &Headers) -> Result<(), HttpErr> {
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
        st.staged = headers.clone();
        Ok(())
    }

    /// `HttpExchange.send(status, headers, body)`: a whole response with a known length.
    /// A HEAD request or a status without a body gets the head alone.
    pub fn send_response(
        &self,
        status: i64,
        headers: &Headers,
        body: &[u8],
    ) -> Result<(), HttpErr> {
        self.send_headers(status, headers)?;
        let (bodyless, remaining) = {
            let st = self.st.borrow();
            (
                st.is_head || !server::body_allowed(st.status),
                st.remaining_write,
            )
        };
        if body.len() > remaining {
            return Err(HttpErr::LimitExceeded);
        }
        // The head alone is written when the handler returns; a HEAD answer still names the
        // length and type the body would have had.
        if body.is_empty() || bodyless {
            let mut st = self.st.borrow_mut();
            st.response_complete = true;
            if st.is_head && server::body_allowed(st.status) && !body.is_empty() {
                st.staged
                    .set("Content-Length", body.len().to_string().into_bytes());
                if st.staged.first("Content-Type").is_none() {
                    st.staged
                        .set("Content-Type", sniff::detect(body).as_bytes().to_vec());
                }
            }
            drop(st);
            return Ok(());
        }
        let result = if let Some(id) = self.h2_id() {
            self.send_head_h2(id, body, Some(body.len()), false)
                .and_then(|()| self.write(body))
        } else {
            let sent = self.write_head(body, Some(body.len()), self.deadline());
            if sent.is_err() {
                self.st.borrow_mut().close_conn = true;
            } else {
                self.st.borrow_mut().remaining_write -= body.len();
            }
            sent
        };
        result.map_err(|e| match e {
            IoErr::Closed => HttpErr::Closed,
            IoErr::Failed(m) => HttpErr::Failed(m),
            _ => HttpErr::Failed("response write failed".into()),
        })?;
        self.st.borrow_mut().response_complete = true;
        Ok(())
    }

    /// Builds and sends the response head with the first body bytes.
    fn write_head(
        &self,
        first: &[u8],
        content_length: Option<usize>,
        deadline: Deadline,
    ) -> Result<(), IoErr> {
        let mut out = Vec::with_capacity(256 + first.len());
        {
            let mut st = self.st.borrow_mut();
            h1::status_line(&mut out, st.status as u16);
            let (has_type, has_date) = server::append_handler_headers(&mut out, &st.staged);
            if !has_date {
                h1::header_line(&mut out, "Date", self.reactor_date().as_bytes());
            }
            let allowed = server::body_allowed(st.status);
            if let Some(n) = content_length
                && allowed
                && !st.is_head
            {
                h1::header_number(&mut out, "Content-Length", n);
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
            st.head_written = true;
        }
        let chunked = self.st.borrow().chunked;
        if !first.is_empty() {
            if chunked {
                h1::chunk(&mut out, first);
            } else {
                out.extend_from_slice(first);
            }
        }
        self.send(&out, deadline)
    }

    fn reactor_date(&self) -> String {
        self.reactor.date_text()
    }

    /// `HttpExchange.write_bytes(data)`.
    pub fn write(&self, data: &[u8]) -> Result<(), IoErr> {
        if self.is_closed() {
            return Err(IoErr::Closed);
        }
        let (sent, status, is_head, remaining) = {
            let st = self.st.borrow();
            (st.sent, st.status, st.is_head, st.remaining_write)
        };
        if !sent || self.st.borrow().response_complete {
            return Err(IoErr::InvalidInput);
        }
        if data.len() > remaining {
            return Err(IoErr::failed("response body limit exceeded"));
        }
        if !server::body_allowed(status) {
            return Err(IoErr::InvalidInput);
        }
        // A HEAD answer has no body: the bytes are dropped, so a handler written for GET
        // streams unchanged. The head alone goes out when the handler returns.
        if is_head {
            return Ok(());
        }
        let deadline = self.deadline();
        let result = if let Some(id) = self.h2_id() {
            self.write_h2(id, data, deadline)
        } else if !self.st.borrow().head_written {
            self.write_head(data, None, deadline)
        } else {
            let mut out = Vec::with_capacity(data.len() + 16);
            if self.st.borrow().chunked {
                h1::chunk(&mut out, data);
            } else {
                out.extend_from_slice(data);
            }
            if out.is_empty() {
                Ok(())
            } else {
                self.send(&out, deadline)
            }
        };
        match result {
            Ok(()) => {
                self.st.borrow_mut().remaining_write -= data.len();
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
    ) -> Result<Rc<Socket>, WsErr> {
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
            if st.closed || st.sent || st.upgraded || st.rejected {
                return Err(WsErr::InvalidInput);
            }
        }
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
        let deadline = self.deadline();
        match handshake::accept(&request, &options) {
            Err(rejected) => Err(self.reject(rejected, deadline)),
            Ok(accepted) => {
                self.send(&accepted.response, deadline)
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
                let config = Config::new(max, accepted.compress, accepted.subprotocol);
                let socket = Rc::new(Socket::new(conn, leftover, Role::Server, config));
                // A WebSocket outlives the request timeout.
                crate::rt::limit_current_until(None);
                let mut st = self.st.borrow_mut();
                st.upgraded = true;
                st.websocket = Some(socket.clone());
                Ok(socket)
            }
        }
    }

    /// Answers a refused upgrade and marks the exchange.
    fn reject(&self, rejected: Rejected, deadline: Deadline) -> WsErr {
        let response = rejected.response(unix_now(), false);
        let _ = self.send(&response, deadline);
        let mut st = self.st.borrow_mut();
        st.rejected = true;
        st.close_conn = true;
        rejected.error()
    }

    /// Completes the request after the handler returned.
    pub(super) fn finish(&self, outcome: Outcome<Result<(), HttpErr>>, late: bool) {
        let server = &self.server;
        let reactor = &self.reactor;
        let conn = &self.conn;
        let (failed, fault, cancelled) = match outcome {
            Outcome::Done(Ok(())) => (late, None, false),
            Outcome::Done(Err(_)) => (true, None, false),
            Outcome::Fault(m) => (true, Some(m), false),
            Outcome::Cancelled => (true, None, true),
        };
        if let Some(m) = &fault {
            eprintln!("HTTP stream handler fault: {m}");
        }
        if fault.is_some() {
            self.release_request_state();
        }
        if let Some(id) = self.h2_id() {
            self.finish_h2(id, failed, cancelled, late);
            return;
        }
        let (sent, upgraded, rejected, head_written, chunked, status, is_head, minor) = {
            let st = self.st.borrow();
            (
                st.sent,
                st.upgraded,
                st.rejected,
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
            return;
        }
        let mut out = Vec::new();
        let mut close = self.st.borrow().close_conn || server.is_closing();
        if rejected {
            // The upgrade attempt already answered.
            close = true;
        } else if failed {
            if !head_written {
                let over = self.st.borrow().body_over_limit;
                let malformed = self.st.borrow().body_malformed;
                if malformed && !(late || cancelled) {
                    server::error_bytes(&mut out, reactor, 400, "malformed request body", true);
                    close = true;
                } else if over && !(late || cancelled) {
                    server::error_bytes(
                        &mut out,
                        reactor,
                        413,
                        "invalid or oversized request body",
                        false,
                    );
                } else {
                    let status = if late || cancelled { 504 } else { 500 };
                    server::error_bytes(&mut out, reactor, status, "request failed", false);
                }
            } else {
                // Part of the response is out: abort the connection.
                server.close_conn(conn, reactor);
                return;
            }
        } else if !sent {
            h1::status_line(&mut out, 204);
            h1::header_line(&mut out, "Date", reactor.date_text().as_bytes());
            if close {
                h1::header_line(&mut out, "Connection", b"close");
            }
            out.extend_from_slice(b"\r\n");
        } else if !head_written {
            // Headers only: an empty body.
            let _ = (status, is_head, minor);
            let mut buf = Vec::new();
            std::mem::swap(&mut buf, &mut out);
            if self.write_head(&[], Some(0), Deadline::none()).is_err() {
                server.close_conn(conn, reactor);
                return;
            }
        } else if chunked {
            out.extend_from_slice(h1::LAST_CHUNK);
        }
        // Reuse the connection only when the request body is gone.
        if !close {
            close = !self.drain_request_body();
        }
        server.queue_output(conn, reactor, out, close);
    }

    /// Empties what the request holds. The frames a fault abandons keep their reference to this
    /// exchange for good, so everything it owns would otherwise stay allocated with it.
    fn release_request_state(&self) {
        let mut st = self.st.borrow_mut();
        st.method = String::new();
        st.path = String::new();
        st.query = String::new();
        st.decoded = Vec::new();
        st.staged = Headers::new();
        *st.headers.borrow_mut() = Headers::new();
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
    use super::server::{Dispatch, Limits, Options, Outcome, Server};
    use super::*;
    use crate::net::Network;

    struct Streamer;

    impl Dispatch for Streamer {
        fn streaming(&self, ex: Rc<Exchange>) -> Outcome<Result<(), HttpErr>> {
            let result = (|| {
                match ex.path().as_str() {
                    "/ws" => {
                        let socket = ex
                            .upgrade(&[], &["chat".to_string()], Some(1024))
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
                            ex.upgrade(&[], &[], None),
                            Err(WsErr::Failed(m)) if m == "websocket: 'Connection' header lacks the 'upgrade' token"
                        ));
                        return Ok(());
                    }
                    "/nobody" => return Ok(()),
                    "/whole" | "/whole-empty" => {
                        let body = if ex.path() == "/whole" {
                            &b"done"[..]
                        } else {
                            &[][..]
                        };
                        ex.send_response(200, &Headers::new(), body)?;
                        assert_eq!(ex.write(b"extra"), Err(IoErr::InvalidInput));
                        assert_eq!(ex.write(b""), Err(IoErr::InvalidInput));
                        return Ok(());
                    }
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
                ex.send_headers(200, &h)?;
                assert_eq!(ex.send_headers(200, &h), Err(HttpErr::InvalidInput));
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
        let options = Options { limits, tls: None };
        let server = Server::start(&net, "127.0.0.1:0", Box::new(Streamer), options).unwrap();
        (net, server)
    }

    #[test]
    fn whole_response_rejects_subsequent_writes() {
        let (_net, server) = start(Limits::default());
        for path in ["/whole", "/whole-empty"] {
            let addr = server.address().to_string();
            let text = with_client(move || {
                raw(
                    &addr,
                    format!("GET {path} HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")
                        .as_bytes(),
                )
            });
            assert!(text.starts_with("HTTP/1.1 200 OK"), "{text}");
            let body = text.split_once("\r\n\r\n").unwrap().1;
            assert_eq!(body, if path == "/whole" { "done" } else { "" });
        }
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
        // A declared length over the limit is refused before the handler runs.
        let over = with_client(move || {
            raw(&a, b"POST /x HTTP/1.1\r\nHost: t\r\nContent-Length: 9\r\nConnection: close\r\n\r\n123456789")
        });
        assert!(over.starts_with("HTTP/1.1 413"), "{over}");
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
