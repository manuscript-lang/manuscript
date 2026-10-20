//! A WebSocket message session over a [`Connection`].
//!
//! Everything runs on the ms thread. Reads and writes go through `Connection::read` and
//! `Connection::write`, which wait while serving queued HTTP handlers, so a nested call on the
//! same socket is possible; a second receive on a busy socket fails and a send queued behind a
//! running write is written by it, in order.
//!
//! Error texts: peer close frames and transport failures
//! are `Failed("websocket: close 1006 (abnormal closure): unexpected EOF")` and the like, and
//! anything that goes wrong after the first frame of a message was accepted reads
//! `connection closed before the exchange completed`, because message bodies are read through
//! a reader whose errors cannot be told apart.

use super::frame::{
    self, DecodeError, Decoder, Event, OP_BINARY, OP_CLOSE, OP_PING, OP_PONG, OP_TEXT, code,
};
use crate::conn::Connection;
use crate::error::{IoErr, WsErr};
use crate::wait::Deadline;
use std::cell::{Cell, RefCell};
use std::collections::VecDeque;
use std::rc::Rc;

/// Wording of a failure inside a message body (`describeTransportError` of
/// `io.ErrUnexpectedEOF`).
pub const TRUNCATED: &str = "connection closed before the exchange completed";

/// gorilla's `writeWait`, used for pongs and close replies.
const CONTROL_WRITE_NANOS: i64 = 1_000_000_000;
/// The deadline of `ping` in `websocket.ms`.
const PING_WRITE_NANOS: i64 = 1_000_000_000;
/// The deadline of the close frame `close()` sends.
const CLOSE_WRITE_NANOS: i64 = 100_000_000;
/// Longest close reason that fits a control frame next to the two code bytes.
const MAX_CLOSE_REASON: usize = 123;

/// Which end of the connection this socket is; clients mask outgoing frames.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Role {
    Client,
    Server,
}

/// Negotiated and requested settings of a session.
#[derive(Clone, Debug)]
pub struct Config {
    /// Largest message accepted or sent; `u64::MAX` for no limit.
    pub max_message_bytes: u64,
    /// permessage-deflate (no context takeover) was negotiated.
    pub compress: bool,
    /// The subprotocol selected in the handshake, empty when none.
    pub subprotocol: String,
}

impl Config {
    /// `max_message_bytes` of `None` means no limit; callers reject non-positive limits.
    pub fn new(max_message_bytes: Option<u64>, compress: bool, subprotocol: String) -> Config {
        Config {
            max_message_bytes: max_message_bytes.unwrap_or(u64::MAX),
            compress,
            subprotocol,
        }
    }
}

impl Default for Config {
    fn default() -> Config {
        Config::new(None, false, String::new())
    }
}

/// A received message.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Message {
    pub data: Vec<u8>,
    /// True for a text frame, which guarantees `data` is valid UTF-8.
    pub text: bool,
}

/// A WebSocket session.
pub struct Socket {
    conn: Rc<Connection>,
    role: Role,
    config: Config,
    decoder: RefCell<Decoder>,
    reading: Cell<bool>,
    queue: RefCell<VecDeque<Vec<u8>>>,
    flushing: Cell<bool>,
    /// gorilla's sticky `writeErr`: a failed write or a sent close frame.
    write_error: RefCell<Option<WsErr>>,
    /// `close()` ran.
    closed: Cell<bool>,
    /// An earlier read failure ended the session (`osWebSocket.failed`).
    failed: Cell<bool>,
}

fn nanos_left(deadline: Deadline) -> Option<i64> {
    deadline
        .remaining()
        .map(|d| d.as_nanos().min(i64::MAX as u128) as i64)
}

fn is_local_timeout(e: &IoErr) -> bool {
    matches!(e, IoErr::Failed(m) if m == "operation timed out")
}

impl Socket {
    /// Wraps an upgraded connection. `leftover` holds the bytes the HTTP layer already read
    /// past the handshake head.
    pub fn new(conn: Rc<Connection>, leftover: Vec<u8>, role: Role, config: Config) -> Socket {
        let mut decoder = Decoder::new(
            role == Role::Server,
            config.compress,
            config.max_message_bytes,
        );
        decoder.push(&leftover);
        Socket {
            conn,
            role,
            config,
            decoder: RefCell::new(decoder),
            reading: Cell::new(false),
            queue: RefCell::new(VecDeque::new()),
            flushing: Cell::new(false),
            write_error: RefCell::new(None),
            closed: Cell::new(false),
            failed: Cell::new(false),
        }
    }

    pub fn connection(&self) -> &Rc<Connection> {
        &self.conn
    }

    pub fn role(&self) -> Role {
        self.role
    }

    /// The subprotocol selected in the handshake; empty when none (valid after close).
    pub fn subprotocol(&self) -> &str {
        &self.config.subprotocol
    }

    pub fn local_address(&self) -> &str {
        self.conn.local_address()
    }

    pub fn peer_address(&self) -> &str {
        self.conn.peer_address()
    }

    /// Whether the session ended: closed locally, failed by a read error, or its connection
    /// (or network) was closed.
    pub fn is_closed(&self) -> bool {
        self.closed.get() || self.failed.get() || self.conn.is_closed()
    }

    fn admit(&self) -> Result<(), WsErr> {
        if self.is_closed() {
            Err(WsErr::Closed)
        } else {
            Ok(())
        }
    }

    /// Ends the session after a read failure.
    fn fail(&self) {
        self.failed.set(true);
        self.conn.close();
    }

    /// Ends the session with `err`, unless the session was closed locally meanwhile.
    fn finish(&self, err: WsErr) -> WsErr {
        let local = self.closed.get() || self.conn.is_closed();
        self.fail();
        if local { WsErr::Closed } else { err }
    }

    fn failed_text(text: String, body: bool) -> WsErr {
        WsErr::Failed(if body { TRUNCATED.to_string() } else { text })
    }

    fn masked(&self) -> bool {
        self.role == Role::Client
    }

    fn map_write(e: IoErr, on_timeout: &WsErr) -> WsErr {
        match e {
            IoErr::Closed => WsErr::Closed,
            IoErr::InvalidInput => WsErr::InvalidInput,
            e if is_local_timeout(&e) => on_timeout.clone(),
            IoErr::Failed(m) => WsErr::Failed(m),
            IoErr::Unavailable => WsErr::Failed("operation unavailable".into()),
            IoErr::InvalidData => WsErr::Failed("invalid data".into()),
            IoErr::LimitExceeded => WsErr::Failed("limit exceeded".into()),
        }
    }

    /// Writes one encoded frame (or message). A failure is sticky, as in gorilla; a nested
    /// call while a write is running only queues its bytes behind it.
    fn write(&self, bytes: Vec<u8>, timeout: Option<i64>, on_timeout: WsErr) -> Result<(), WsErr> {
        if let Some(e) = self.write_error.borrow().clone() {
            return Err(e);
        }
        self.queue.borrow_mut().push_back(bytes);
        if self.flushing.replace(true) {
            return Ok(());
        }
        let result = self.flush(timeout, &on_timeout);
        self.flushing.set(false);
        result
    }

    fn flush(&self, timeout: Option<i64>, on_timeout: &WsErr) -> Result<(), WsErr> {
        loop {
            let next = self.queue.borrow_mut().pop_front();
            let Some(bytes) = next else {
                return Ok(());
            };
            if let Err(e) = self.conn.write(&bytes, timeout) {
                let err = Self::map_write(e, on_timeout);
                *self.write_error.borrow_mut() = Some(err.clone());
                self.queue.borrow_mut().clear();
                return Err(err);
            }
        }
    }

    fn write_control(
        &self,
        opcode: u8,
        payload: &[u8],
        timeout: i64,
        on_timeout: WsErr,
    ) -> Result<(), WsErr> {
        let Some(frame) = frame::encode_control(opcode, payload, self.masked()) else {
            return Err(WsErr::InvalidInput);
        };
        self.write(frame, Some(timeout), on_timeout)?;
        if opcode == OP_CLOSE {
            *self.write_error.borrow_mut() = Some(WsErr::Failed("websocket: close sent".into()));
        }
        Ok(())
    }

    /// Sends a close frame, best effort.
    fn send_close(&self, payload: &[u8], timeout: i64) {
        let _ = self.write_control(OP_CLOSE, payload, timeout, WsErr::Timeout);
    }

    /// Sends `data` as one text or binary message. Errors in order: closed, over the message
    /// limit, invalid UTF-8 text, negative `timeout` (InvalidInput), then the write.
    pub fn send(&self, data: &[u8], text: bool, timeout: Option<i64>) -> Result<(), WsErr> {
        self.admit()?;
        if data.len() as u64 > self.config.max_message_bytes {
            return Err(WsErr::LimitExceeded);
        }
        if text && std::str::from_utf8(data).is_err() {
            return Err(WsErr::InvalidData);
        }
        Deadline::from_nanos(timeout).map_err(|_| WsErr::InvalidInput)?;
        let opcode = if text { OP_TEXT } else { OP_BINARY };
        let wire = frame::encode_message(opcode, data, self.masked(), self.config.compress, 0);
        self.write(wire, timeout, WsErr::Timeout)
    }

    /// Sends a text message.
    pub fn send_text(&self, text: &str, timeout: Option<i64>) -> Result<(), WsErr> {
        self.send(text.as_bytes(), true, timeout)
    }

    /// Sends a ping with a one-second write deadline and does not wait for the pong. More
    /// than 125 bytes is InvalidInput.
    pub fn ping(&self, data: &[u8]) -> Result<(), WsErr> {
        self.admit()?;
        let timed_out = WsErr::Failed("i/o timeout".into());
        self.write_control(OP_PING, data, PING_WRITE_NANOS, timed_out)
    }

    /// Closes the session: a normal-closure frame within about 100 ms, then the connection.
    /// Idempotent.
    pub fn close(&self) {
        self.close_with(code::NORMAL, "");
    }

    /// Like [`close`](Self::close) with a status code and reason (cut to 123 bytes).
    pub fn close_with(&self, status: u16, reason: &str) {
        if self.closed.replace(true) {
            return;
        }
        if !self.conn.is_closed() {
            let mut end = reason.len().min(MAX_CLOSE_REASON);
            while !reason.is_char_boundary(end) {
                end -= 1;
            }
            let payload = frame::format_close(status, &reason[..end]);
            self.send_close(&payload, CLOSE_WRITE_NANOS);
        }
        self.conn.close();
    }

    /// Waits for the next message. `Ok(None)` is a normal end of the session: the peer sent
    /// close 1000 or 1001. Pings are answered, pongs dropped.
    ///
    /// After any failure other than [`WsErr::Timeout`] the session is over and later calls
    /// return Closed. A timeout (`timeout` in nanoseconds, none for no limit) leaves it intact
    /// and the next call resumes where this one stopped.
    pub fn receive(&self, timeout: Option<i64>) -> Result<Option<Message>, WsErr> {
        self.admit()?;
        let deadline = Deadline::from_nanos(timeout).map_err(|_| WsErr::InvalidInput)?;
        if self.reading.replace(true) {
            return Err(WsErr::Failed("websocket: concurrent receive".into()));
        }
        let result = self.receive_loop(deadline, timeout.is_some());
        self.reading.set(false);
        result
    }

    fn receive_loop(&self, deadline: Deadline, bounded: bool) -> Result<Option<Message>, WsErr> {
        loop {
            let step = self.decoder.borrow_mut().poll();
            let event = match step {
                Ok(Some(event)) => event,
                Ok(None) => {
                    self.fill(deadline, bounded)?;
                    continue;
                }
                Err(e) => return Err(self.decode_failure(e)),
            };
            if let Some(result) = self.on_event(event) {
                return result;
            }
        }
    }

    /// Reads more bytes into the decoder.
    fn fill(&self, deadline: Deadline, bounded: bool) -> Result<(), WsErr> {
        let read = self.conn.read(None, nanos_left(deadline));
        let body = self.decoder.borrow().in_message();
        let err = match read {
            Ok(Some(bytes)) => {
                self.decoder.borrow_mut().push(&bytes);
                return Ok(());
            }
            Ok(None) => Self::failed_text(
                frame::close_error_text(code::ABNORMAL, "unexpected EOF"),
                body,
            ),
            Err(e) if bounded && is_local_timeout(&e) => return Err(WsErr::Timeout),
            Err(IoErr::Closed) => WsErr::Closed,
            Err(IoErr::Failed(m)) => Self::failed_text(m, body),
            Err(_) => Self::failed_text(TRUNCATED.to_string(), true),
        };
        Err(self.finish(err))
    }

    /// Handles one event; `Some` ends the receive.
    fn on_event(&self, event: Event) -> Option<Result<Option<Message>, WsErr>> {
        match event {
            Event::Message { text, data } => Some(self.deliver(text, data)),
            Event::Ping(payload) => self.answer_ping(&payload).err().map(Err),
            Event::Pong(_) => None,
            Event::Close { code, reason } => Some(self.peer_closed(code, &reason)),
        }
    }

    fn deliver(&self, text: bool, data: Vec<u8>) -> Result<Option<Message>, WsErr> {
        if text && std::str::from_utf8(&data).is_err() {
            // RFC 6455 section 8.1: fail the connection with 1007.
            self.failed.set(true);
            let payload = frame::format_close(code::INVALID_PAYLOAD, "");
            self.send_close(&payload, CLOSE_WRITE_NANOS);
            self.conn.close();
            return Err(WsErr::InvalidData);
        }
        Ok(Some(Message { data, text }))
    }

    /// gorilla's default ping handler: a pong with the same payload. A sent close frame and
    /// a timeout are ignored; any other write failure ends the session.
    fn answer_ping(&self, payload: &[u8]) -> Result<(), WsErr> {
        let timed_out = WsErr::Timeout;
        let result = self.write_control(OP_PONG, payload, CONTROL_WRITE_NANOS, timed_out);
        let Err(err) = result else {
            return Ok(());
        };
        let close_sent = err == WsErr::Failed("websocket: close sent".into());
        if close_sent || err == WsErr::Timeout {
            return Ok(());
        }
        let body = self.decoder.borrow().in_message();
        let text = match &err {
            WsErr::Failed(m) => m.clone(),
            other => other.message(),
        };
        Err(self.finish(Self::failed_text(text, body)))
    }

    /// gorilla's default close handler echoes the code; the receive then ends with the close
    /// error, which is a normal end for 1000 and 1001.
    fn peer_closed(&self, status: u16, reason: &str) -> Result<Option<Message>, WsErr> {
        let echo = frame::format_close(status, "");
        self.send_close(&echo, CONTROL_WRITE_NANOS);
        let body = self.decoder.borrow().in_message();
        if !body && (status == code::NORMAL || status == code::GOING_AWAY) {
            self.fail();
            return Ok(None);
        }
        let err = Self::failed_text(frame::close_error_text(status, reason), body);
        Err(self.finish(err))
    }

    fn decode_failure(&self, e: DecodeError) -> WsErr {
        let err = match e {
            DecodeError::Protocol { text, body } => {
                self.send_close(&frame::protocol_error_payload(&text), CONTROL_WRITE_NANOS);
                Self::failed_text(format!("websocket: {text}"), body)
            }
            DecodeError::Limit { reply_close, body } => {
                if reply_close {
                    let payload = frame::format_close(code::MESSAGE_TOO_BIG, "");
                    self.send_close(&payload, CONTROL_WRITE_NANOS);
                }
                if body {
                    WsErr::Failed(TRUNCATED.to_string())
                } else {
                    WsErr::LimitExceeded
                }
            }
            DecodeError::Overflow => WsErr::LimitExceeded,
            DecodeError::Corrupt => WsErr::Failed(TRUNCATED.to_string()),
        };
        self.finish(err)
    }

    /// Closes with a handshake: sends close `status`, then waits for the peer's close frame
    /// (discarding messages that arrive first) for at most `timeout` nanoseconds, and closes
    /// the connection either way. A peer that closes the stream without a close frame counts
    /// as answered; running out of time is [`WsErr::Timeout`].
    pub fn close_handshake(
        &self,
        status: u16,
        reason: &str,
        timeout: Option<i64>,
    ) -> Result<(), WsErr> {
        self.admit()?;
        let deadline = Deadline::from_nanos(timeout).map_err(|_| WsErr::InvalidInput)?;
        if self.reading.replace(true) {
            return Err(WsErr::Failed("websocket: concurrent receive".into()));
        }
        let mut end = reason.len().min(MAX_CLOSE_REASON);
        while !reason.is_char_boundary(end) {
            end -= 1;
        }
        let payload = frame::format_close(status, &reason[..end]);
        self.send_close(&payload, CONTROL_WRITE_NANOS);
        let result = self.await_close(deadline);
        self.reading.set(false);
        self.closed.set(true);
        self.conn.close();
        result
    }

    fn await_close(&self, deadline: Deadline) -> Result<(), WsErr> {
        loop {
            let step = self.decoder.borrow_mut().poll();
            match step {
                Ok(Some(Event::Close { .. })) => return Ok(()),
                Ok(Some(_)) => continue,
                Ok(None) => {}
                Err(_) => return Err(WsErr::Failed(TRUNCATED.to_string())),
            }
            let read = self.conn.read(None, nanos_left(deadline));
            match read {
                Ok(Some(bytes)) => self.decoder.borrow_mut().push(&bytes),
                Ok(None) => return Ok(()),
                Err(e) if is_local_timeout(&e) => return Err(WsErr::Timeout),
                Err(e) => return Err(Self::map_write(e, &WsErr::Timeout)),
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::super::frame::{OP_CONTINUATION, encode_control, encode_frame, encode_message};
    use super::super::handshake::{self, ClientRequest, Request, ServerOptions};
    use super::*;
    use crate::http::h1::{Parsed, parse_request, parse_response};
    use crate::net::Network;

    const SEC: Option<i64> = Some(2_000_000_000);
    const SHORT: Option<i64> = Some(30_000_000);

    fn read_until<T>(
        conn: &Connection,
        mut parse: impl FnMut(&[u8]) -> Option<(T, usize)>,
    ) -> (T, Vec<u8>) {
        let mut buf = Vec::new();
        loop {
            if let Some((value, used)) = parse(&buf) {
                return (value, buf.split_off(used));
            }
            buf.extend(conn.read(None, SEC).unwrap().expect("peer closed"));
        }
    }

    /// Opens a TCP pair and performs the real handshake over it, sequentially on one thread.
    fn pair(
        net: &Rc<Network>,
        compression: bool,
        server_max: Option<u64>,
        client_max: Option<u64>,
    ) -> (Socket, Socket) {
        let listener = net.listen("127.0.0.1:0").unwrap();
        let client_conn = net.connect(listener.address(), SEC).unwrap();
        let server_conn = listener.accept(SEC).unwrap();

        let key = handshake::generate_key();
        let protocols = vec!["echo".to_string()];
        let request = handshake::client_request(&ClientRequest {
            target: "/ws",
            host: listener.address(),
            key: &key,
            subprotocols: &protocols,
            headers: &[],
            compression,
        });
        client_conn.write(&request, SEC).unwrap();

        let (head, rest) = read_until(&server_conn, |b| match parse_request(b, 1 << 16) {
            Parsed::Complete(h) => {
                let used = h.length;
                Some((h, used))
            }
            _ => None,
        });
        let server_protocols = vec!["echo".to_string()];
        let accepted = handshake::accept(
            &Request {
                method: &head.method,
                host: listener.address(),
                tls: false,
                fields: &head.fields,
            },
            &ServerOptions {
                subprotocols: &server_protocols,
                compression,
                ..ServerOptions::default()
            },
        )
        .unwrap();
        server_conn.write(&accepted.response, SEC).unwrap();

        let (resp, leftover) = read_until(&client_conn, |b| match parse_response(b, 1 << 16) {
            Parsed::Complete(h) => {
                let used = h.length;
                Some((h, used))
            }
            _ => None,
        });
        let done = handshake::check_response_head(&resp, &key).unwrap();
        assert_eq!(done.compress, compression);

        let server = Socket::new(
            server_conn,
            rest,
            Role::Server,
            Config::new(server_max, accepted.compress, accepted.subprotocol),
        );
        let client = Socket::new(
            client_conn,
            leftover,
            Role::Client,
            Config::new(client_max, done.compress, done.subprotocol),
        );
        (client, server)
    }

    fn setup() -> (Rc<Network>, Socket, Socket) {
        let net = Network::new_root();
        let (c, s) = pair(&net, false, None, None);
        (net, c, s)
    }

    fn text(s: &str) -> Message {
        Message {
            data: s.as_bytes().to_vec(),
            text: true,
        }
    }

    #[test]
    fn handshake_and_echo_both_ways() {
        let (_net, client, server) = setup();
        assert_eq!(client.subprotocol(), "echo");
        assert_eq!(server.subprotocol(), "echo");
        assert_eq!(client.peer_address(), server.local_address());
        client.send_text("é🙂", None).unwrap();
        assert_eq!(server.receive(SEC).unwrap(), Some(text("é🙂")));
        server.send(&[0xff, 0x00], false, None).unwrap();
        assert_eq!(
            client.receive(SEC).unwrap(),
            Some(Message {
                data: vec![0xff, 0],
                text: false
            })
        );
        // Empty messages work in both kinds.
        client.send(b"", true, None).unwrap();
        client.send(b"", false, None).unwrap();
        assert_eq!(server.receive(SEC).unwrap(), Some(text("")));
        assert_eq!(server.receive(SEC).unwrap().map(|m| m.text), Some(false));
    }

    #[test]
    fn large_messages_cross_frame_size_boundaries() {
        let (_net, client, server) = setup();
        for size in [125usize, 126, 65_535, 65_536] {
            let data = vec![b'a'; size];
            client.send(&data, false, SEC).unwrap();
            let got = server.receive(SEC).unwrap().unwrap();
            assert_eq!(got.data, data);
        }
    }

    #[test]
    fn compression_round_trip() {
        let net = Network::new_root();
        let (client, server) = pair(&net, true, None, None);
        let big = "compress me ".repeat(500);
        client.send_text(&big, None).unwrap();
        assert_eq!(server.receive(SEC).unwrap(), Some(text(&big)));
        server.send(b"", true, None).unwrap();
        server.send(&[1, 2, 3], false, None).unwrap();
        assert_eq!(client.receive(SEC).unwrap(), Some(text("")));
        assert_eq!(client.receive(SEC).unwrap().unwrap().data, [1, 2, 3]);
    }

    #[test]
    fn send_validation_follows_go() {
        let net = Network::new_root();
        let (client, _server) = pair(&net, false, None, Some(8));
        assert_eq!(
            client.send(b"123456789", false, None),
            Err(WsErr::LimitExceeded)
        );
        assert_eq!(client.send(&[0xff], true, None), Err(WsErr::InvalidData));
        // The size is checked before the text.
        assert_eq!(
            client.send(&[0xff; 9], true, None),
            Err(WsErr::LimitExceeded)
        );
        client.send(&[0xff], false, None).unwrap();
        assert_eq!(client.ping(&[0; 126]), Err(WsErr::InvalidInput));
        client.ping(b"p").unwrap();
        assert_eq!(client.send(b"x", false, Some(-1)), Err(WsErr::InvalidInput));
        assert_eq!(client.receive(Some(-1)), Err(WsErr::InvalidInput));
    }

    #[test]
    fn pings_are_answered_and_pongs_dropped() {
        let (_net, client, server) = setup();
        client.ping(b"hi").unwrap();
        client.send_text("after", None).unwrap();
        assert_eq!(server.receive(SEC).unwrap(), Some(text("after")));
        server.send_text("reply", None).unwrap();
        // The pong the server wrote for the ping arrives first and is not a message.
        assert_eq!(client.receive(SEC).unwrap(), Some(text("reply")));
    }

    #[test]
    fn the_pong_carries_the_ping_payload() {
        let (_net, client, server) = setup();
        let conn = client.connection().clone();
        conn.write(&encode_control(OP_PING, b"abc", true).unwrap(), SEC)
            .unwrap();
        client.send_text("x", None).unwrap();
        server.receive(SEC).unwrap();
        let bytes = conn.read(None, SEC).unwrap().unwrap();
        assert_eq!(bytes, [0x8a, 0x03, b'a', b'b', b'c']);
    }

    #[test]
    fn peer_close_ends_normally_and_is_echoed() {
        let (_net, client, server) = setup();
        client.close_with(1000, "bye");
        assert!(client.is_closed());
        assert_eq!(server.receive(SEC).unwrap(), None);
        assert_eq!(server.receive(SEC), Err(WsErr::Closed));
        assert_eq!(server.send(b"x", false, None), Err(WsErr::Closed));
        assert_eq!(server.ping(b""), Err(WsErr::Closed));
        assert_eq!(client.receive(SEC), Err(WsErr::Closed));
        client.close();
        server.close();
        assert_eq!(server.subprotocol(), "echo");
    }

    #[test]
    fn going_away_is_a_normal_end_other_codes_are_errors() {
        let (_net, client, server) = setup();
        server.close_with(1001, "");
        assert_eq!(client.receive(SEC).unwrap(), None);
        let (_net2, client, server) = setup();
        server.close_with(4000, "custom");
        assert_eq!(
            client.receive(SEC),
            Err(WsErr::Failed("websocket: close 4000: custom".into()))
        );
        assert_eq!(client.receive(SEC), Err(WsErr::Closed));
        let (_net3, client, server) = setup();
        server.close_with(1011, "");
        assert_eq!(
            client.receive(SEC),
            Err(WsErr::Failed(
                "websocket: close 1011 (internal server error)".into()
            ))
        );
    }

    #[test]
    fn close_handshake_waits_for_the_echo() {
        let (_net, client, server) = setup();
        // The server's close frame is already on the wire; the client sends its own and
        // finds the peer's close.
        server.close();
        client.close_handshake(1000, "", SEC).unwrap();
        assert!(client.is_closed());
        assert_eq!(client.close_handshake(1000, "", SEC), Err(WsErr::Closed));
    }

    #[test]
    fn close_handshake_times_out_on_a_silent_peer() {
        let (_net, client, _server) = setup();
        assert_eq!(client.close_handshake(1000, "", SHORT), Err(WsErr::Timeout));
        assert!(client.is_closed());
    }

    #[test]
    fn oversize_message_closes_with_1009() {
        let net = Network::new_root();
        let (client, server) = pair(&net, false, Some(8), None);
        client.send(b"123456789", false, None).unwrap();
        assert_eq!(server.receive(SEC), Err(WsErr::LimitExceeded));
        assert_eq!(server.receive(SEC), Err(WsErr::Closed));
        assert_eq!(
            client.receive(SEC),
            Err(WsErr::Failed(
                "websocket: close 1009 (message too big)".into()
            ))
        );
        // Exactly the limit passes.
        let (client, server) = pair(&net, false, Some(8), None);
        client.send(b"12345678", false, None).unwrap();
        assert_eq!(server.receive(SEC).unwrap().unwrap().data.len(), 8);
    }

    #[test]
    fn compressed_overflow_is_a_limit_error_without_close_frame() {
        let net = Network::new_root();
        let (client, server) = pair(&net, true, None, None);
        let server_small = Socket::new(
            server.connection().clone(),
            Vec::new(),
            Role::Server,
            Config::new(Some(128), true, String::new()),
        );
        client.send(&[b'x'; 10_000], true, None).unwrap();
        assert_eq!(server_small.receive(SEC), Err(WsErr::LimitExceeded));
        assert_eq!(server_small.receive(SEC), Err(WsErr::Closed));
    }

    #[test]
    fn invalid_utf8_text_closes_with_1007() {
        let (_net, client, server) = setup();
        let wire = encode_message(OP_TEXT, &[0xff, 0xfe], true, false, 0);
        client.connection().write(&wire, SEC).unwrap();
        assert_eq!(server.receive(SEC), Err(WsErr::InvalidData));
        assert_eq!(server.receive(SEC), Err(WsErr::Closed));
        assert_eq!(
            client.receive(SEC),
            Err(WsErr::Failed(
                "websocket: close 1007 (invalid payload data)".into()
            ))
        );
    }

    #[test]
    fn protocol_errors_send_1002() {
        let (_net, client, server) = setup();
        // An unmasked frame into a server.
        let wire = encode_frame(OP_TEXT, true, false, b"x", None);
        client.connection().write(&wire, SEC).unwrap();
        assert_eq!(
            server.receive(SEC),
            Err(WsErr::Failed("websocket: bad MASK".into()))
        );
        assert_eq!(
            client.receive(SEC),
            Err(WsErr::Failed(
                "websocket: close 1002 (protocol error): bad MASK".into()
            ))
        );
    }

    #[test]
    fn protocol_error_inside_a_message_reads_as_truncated() {
        let (_net, client, server) = setup();
        let mut wire = encode_frame(OP_TEXT, false, false, b"ab", Some([1, 2, 3, 4]));
        // A continuation that is not masked.
        wire.extend(encode_frame(OP_CONTINUATION, true, false, b"cd", None));
        client.connection().write(&wire, SEC).unwrap();
        assert_eq!(server.receive(SEC), Err(WsErr::Failed(TRUNCATED.into())));
    }

    #[test]
    fn end_of_stream_wording() {
        let (_net, client, server) = setup();
        client.connection().close();
        assert_eq!(
            server.receive(SEC),
            Err(WsErr::Failed(
                "websocket: close 1006 (abnormal closure): unexpected EOF".into()
            ))
        );
        let (_net2, client, server) = setup();
        // Half a frame, then the stream ends: the first frame header was accepted.
        let wire = encode_frame(OP_BINARY, true, false, b"abcdef", Some([1, 2, 3, 4]));
        client.connection().write(&wire[..8], SEC).unwrap();
        client.connection().close();
        assert_eq!(server.receive(SEC), Err(WsErr::Failed(TRUNCATED.into())));
        assert_eq!(server.receive(SEC), Err(WsErr::Closed));
    }

    #[test]
    fn receive_timeout_keeps_the_session_and_partial_frames() {
        let (_net, client, server) = setup();
        assert_eq!(server.receive(SHORT), Err(WsErr::Timeout));
        assert!(!server.is_closed());
        let wire = encode_message(OP_TEXT, b"split", true, false, 0);
        client.connection().write(&wire[..4], SEC).unwrap();
        assert_eq!(server.receive(SHORT), Err(WsErr::Timeout));
        client.connection().write(&wire[4..], SEC).unwrap();
        assert_eq!(server.receive(SEC).unwrap(), Some(text("split")));
    }

    #[test]
    fn fragments_and_interleaved_control_frames() {
        let (_net, client, server) = setup();
        let conn = client.connection();
        let mut wire = encode_frame(OP_TEXT, false, false, b"one ", Some([9, 8, 7, 6]));
        wire.extend(encode_control(OP_PING, b"", true).unwrap());
        wire.extend(encode_frame(
            OP_CONTINUATION,
            false,
            false,
            b"two ",
            Some([1, 1, 1, 1]),
        ));
        wire.extend(encode_frame(
            OP_CONTINUATION,
            true,
            false,
            b"three",
            Some([5, 4, 3, 2]),
        ));
        conn.write(&wire, SEC).unwrap();
        assert_eq!(server.receive(SEC).unwrap(), Some(text("one two three")));
    }

    #[test]
    fn leftover_bytes_are_read_first() {
        let net = Network::new_root();
        let listener = net.listen("127.0.0.1:0").unwrap();
        let client_conn = net.connect(listener.address(), SEC).unwrap();
        let server_conn = listener.accept(SEC).unwrap();
        let frame = encode_message(OP_TEXT, b"early", false, false, 0);
        let client = Socket::new(client_conn, frame, Role::Client, Config::default());
        // No byte ever crosses the wire.
        assert_eq!(client.receive(SHORT).unwrap(), Some(text("early")));
        assert_eq!(client.receive(SHORT), Err(WsErr::Timeout));
        drop(server_conn);
    }

    #[test]
    fn closing_the_network_connection_closes_the_socket() {
        let (_net, client, _server) = setup();
        client.connection().close();
        assert!(client.is_closed());
        assert_eq!(client.send(b"x", false, None), Err(WsErr::Closed));
        assert_eq!(client.receive(None), Err(WsErr::Closed));
    }
}
