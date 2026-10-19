//! Streaming server exchanges: the handler reads the request body and writes
//! the response itself, in blocking calls on the ms thread.

use super::h1::{self, BodyDecoder, Decoded};
use super::headers::{self, Headers};
use super::server::{self, Conn, DRAIN_LIMIT, Outcome, Pending, Reactor, Server};
use super::sniff;
use crate::conn::{Io, Step};
use crate::error::{HttpErr, IoErr};
use crate::wait::{Deadline, Interest, Wait, wait_fd};
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
    pub remaining_write: usize,
    pub expect_continue: bool,
    pub minor: u8,
    pub is_head: bool,
    pub sent: bool,
    pub status: i64,
    /// Staged response headers (handler headers), written with the first body bytes.
    pub staged: Headers,
    pub head_written: bool,
    pub chunked: bool,
    pub close_conn: bool,
    pub closed: bool,
    pub upgraded: bool,
    pub rejected: bool,
    pub deadline: Option<Instant>,
}

/// One request being handled.
pub struct Exchange {
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
            expect_continue,
            minor: head.minor,
            sent: false,
            status: 0,
            staged: Headers::new(),
            head_written: false,
            chunked: false,
            close_conn: !keep_alive || head.minor == 0,
            closed: false,
            upgraded: false,
            rejected: false,
            deadline: timeout.map(|t| started + t),
        }),
    });
    server.enter_handler(reactor);
    let outcome = server.dispatch.streaming(exchange.clone());
    server.leave_handler(reactor);
    let late = timeout.is_some_and(|t| started.elapsed() > t);
    exchange.finish(outcome, late);
}

impl Exchange {
    fn deadline(&self) -> Deadline {
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
        self.st.borrow_mut().closed = true;
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
        if !sent {
            return Err(IoErr::InvalidInput);
        }
        if data.len() > remaining {
            return Err(IoErr::failed("response body limit exceeded"));
        }
        if is_head || !server::body_allowed(status) {
            return Err(IoErr::InvalidInput);
        }
        let deadline = self.deadline();
        let result = if !self.st.borrow().head_written {
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

    /// Completes the request after the handler returned.
    fn finish(&self, outcome: Outcome<Result<(), HttpErr>>, late: bool) {
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
            return;
        }
        let mut out = Vec::new();
        let mut close = self.st.borrow().close_conn || server.is_closing();
        if rejected {
            // The upgrade attempt already answered.
            close = true;
        } else if failed {
            if !sent {
                let status = if late || cancelled { 504 } else { 500 };
                server::error_bytes(&mut out, reactor, status, "request failed", false);
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

#[cfg(test)]
mod tests {
    use super::server::tests::{exchange as raw, with_client};
    use super::server::{Dispatch, Limits, Options, Outcome, Reply, Request, Server};
    use super::*;
    use crate::net::Network;

    struct Streamer;

    impl Dispatch for Streamer {
        fn buffered(&self, _: Request) -> Outcome<Reply> {
            Outcome::Cancelled
        }

        fn streaming(&self, ex: Rc<Exchange>) -> Outcome<Result<(), HttpErr>> {
            let result = (|| {
                match ex.path().as_str() {
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
}
