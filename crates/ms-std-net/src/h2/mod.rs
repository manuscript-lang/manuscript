//! Sans-io HTTP/2 (RFC 7540) with HPACK (RFC 7541).
//!
//! [`Connection`] is a pure state machine: callers push received bytes into
//! [`Connection::feed`], drain bytes to write with [`Connection::take_output`],
//! and drive streams through the send methods. It owns no sockets, threads or
//! clocks, so it can sit under any transport (TLS with ALPN `h2`, cleartext
//! prior knowledge, or an in-memory pipe in tests).
//!
//! # Flow control
//!
//! Sending honors the peer's connection and stream windows:
//! [`Connection::send_data`] returns how many bytes it accepted and the caller
//! retries the rest after [`Event::WindowOpened`]. Receiving is explicit: every
//! DATA byte handed out in [`Event::Data`] stays charged against the peer's
//! windows until the caller returns it with [`Connection::release`], which
//! queues the WINDOW_UPDATE frames. Padding is released automatically.
//!
//! # Errors
//!
//! Connection errors make [`Connection::feed`] return `Err`; a GOAWAY carrying
//! the code is queued in the output (drain it before closing) and every later
//! `feed` repeats the error. Stream errors are answered with RST_STREAM and
//! surface as [`Event::Reset`]. Misuse of the send API returns a non-fatal
//! [`H2Error`] (`fatal == false`) and leaves the connection untouched.

pub mod frame;
pub mod hpack;

use std::collections::HashMap;

use frame::{
    DEFAULT_MAX_FRAME_SIZE, Frame, MAX_MAX_FRAME_SIZE, MAX_WINDOW, PREFACE, parse_frame,
    write_data, write_goaway, write_header_block, write_ping, write_rst_stream, write_settings,
    write_settings_ack, write_window_update,
};
use hpack::{DEFAULT_TABLE_SIZE, Decoder, Encoder};

pub use hpack::Header;

/// HTTP/2 stream identifier. Stream 0 is the connection.
pub type StreamId = u32;

/// RFC 7540 section 7 error codes.
pub mod error_code {
    pub const NO_ERROR: u32 = 0x0;
    pub const PROTOCOL_ERROR: u32 = 0x1;
    pub const INTERNAL_ERROR: u32 = 0x2;
    pub const FLOW_CONTROL_ERROR: u32 = 0x3;
    pub const SETTINGS_TIMEOUT: u32 = 0x4;
    pub const STREAM_CLOSED: u32 = 0x5;
    pub const FRAME_SIZE_ERROR: u32 = 0x6;
    pub const REFUSED_STREAM: u32 = 0x7;
    pub const CANCEL: u32 = 0x8;
    pub const COMPRESSION_ERROR: u32 = 0x9;
    pub const CONNECT_ERROR: u32 = 0xa;
    pub const ENHANCE_YOUR_CALM: u32 = 0xb;
    pub const INADEQUATE_SECURITY: u32 = 0xc;
    pub const HTTP_1_1_REQUIRED: u32 = 0xd;
}

use error_code::{
    COMPRESSION_ERROR, ENHANCE_YOUR_CALM, FLOW_CONTROL_ERROR, INTERNAL_ERROR, PROTOCOL_ERROR,
    REFUSED_STREAM, STREAM_CLOSED,
};

/// An HTTP/2 error: a connection error from the peer's bytes (`fatal`), or a
/// refused local request (`!fatal`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct H2Error {
    pub code: u32,
    pub reason: String,
    pub fatal: bool,
}

impl H2Error {
    pub(crate) fn connection(code: u32, reason: impl Into<String>) -> Self {
        H2Error {
            code,
            reason: reason.into(),
            fatal: true,
        }
    }

    fn usage(reason: impl Into<String>) -> Self {
        H2Error {
            code: INTERNAL_ERROR,
            reason: reason.into(),
            fatal: false,
        }
    }
}

impl std::fmt::Display for H2Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "http2 error code {:#x}: {}", self.code, self.reason)
    }
}

impl std::error::Error for H2Error {}

fn proto(reason: &str) -> H2Error {
    H2Error::connection(PROTOCOL_ERROR, reason)
}

/// Local settings, advertised in the initial SETTINGS frame.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Settings {
    /// `SETTINGS_HEADER_TABLE_SIZE` (largest table the peer's encoder may use).
    pub header_table_size: u32,
    /// `SETTINGS_MAX_CONCURRENT_STREAMS` for peer-initiated streams; `None`
    /// leaves it unlimited and unadvertised.
    pub max_concurrent_streams: Option<u32>,
    /// `SETTINGS_INITIAL_WINDOW_SIZE` for each stream we receive on.
    pub initial_window_size: u32,
    /// `SETTINGS_MAX_FRAME_SIZE`: largest frame payload we accept.
    pub max_frame_size: u32,
    /// `SETTINGS_MAX_HEADER_LIST_SIZE`; `None` is unlimited and unadvertised.
    pub max_header_list_size: Option<u32>,
    /// Target connection-level receive window; anything above 65535 is
    /// granted with a WINDOW_UPDATE on stream 0 at startup.
    pub connection_window: u32,
}

const DEFAULT_WINDOW: i64 = 65_535;

impl Default for Settings {
    fn default() -> Self {
        Settings {
            header_table_size: DEFAULT_TABLE_SIZE as u32,
            max_concurrent_streams: None,
            initial_window_size: DEFAULT_WINDOW as u32,
            max_frame_size: DEFAULT_MAX_FRAME_SIZE,
            max_header_list_size: None,
            connection_window: DEFAULT_WINDOW as u32,
        }
    }
}

impl Settings {
    fn sanitized(mut self) -> Self {
        self.max_frame_size = self
            .max_frame_size
            .clamp(DEFAULT_MAX_FRAME_SIZE, MAX_MAX_FRAME_SIZE);
        self.initial_window_size = self.initial_window_size.min(MAX_WINDOW as u32);
        self.connection_window = self
            .connection_window
            .clamp(DEFAULT_WINDOW as u32, MAX_WINDOW as u32);
        self
    }
}

/// What the application observes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Event {
    /// A complete, validated header block: request, response (including 1xx
    /// interim responses) or trailers.
    Headers {
        id: StreamId,
        headers: Vec<Header>,
        end_stream: bool,
    },
    /// Body bytes. Return them with [`Connection::release`] once consumed.
    Data {
        id: StreamId,
        data: Vec<u8>,
        end_stream: bool,
    },
    /// The stream was reset by the peer, by a stream error we raised, or
    /// refused because of a GOAWAY.
    Reset { id: StreamId, code: u32 },
    /// The peer is shutting the connection down.
    GoAway {
        last_stream_id: StreamId,
        code: u32,
        debug: Vec<u8>,
    },
    /// Send window grew. `id == 0` means the connection window; retry any
    /// stream blocked on flow control.
    WindowOpened { id: StreamId },
    /// The peer acknowledged our SETTINGS.
    SettingsAcked,
    /// A PING we sent was answered.
    PingAck { data: [u8; 8] },
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
enum Role {
    Client,
    Server,
}

#[derive(Debug)]
struct PeerSettings {
    max_concurrent_streams: Option<u32>,
    initial_window_size: i64,
    max_frame_size: u32,
    max_header_list_size: Option<u32>,
}

#[derive(Debug)]
struct Stream {
    send_window: i64,
    recv_window: i64,
    /// Received DATA bytes the application has not released yet.
    unreleased: i64,
    /// Final (non-1xx) header blocks received; the first is the request or
    /// response, later ones are trailers.
    headers_received: u8,
    headers_sent: bool,
    local_end: bool,
    remote_end: bool,
}

#[derive(Debug)]
struct PendingHeaders {
    id: StreamId,
    block: Vec<u8>,
    end_stream: bool,
}

/// One endpoint of an HTTP/2 connection.
#[derive(Debug)]
pub struct Connection {
    role: Role,
    local: Settings,
    peer: PeerSettings,
    encoder: Encoder,
    decoder: Decoder,
    out: Vec<u8>,
    inbuf: Vec<u8>,
    preface_done: bool,
    got_settings: bool,
    settings_unacked: u32,
    /// Stream receive window the peer is using for us right now (65535 until
    /// it acknowledges our SETTINGS).
    recv_initial: i64,
    streams: HashMap<StreamId, Stream>,
    local_open: u32,
    peer_open: u32,
    next_local_id: StreamId,
    highest_peer_id: StreamId,
    conn_send_window: i64,
    conn_recv_window: i64,
    conn_unreleased: i64,
    pending: Option<PendingHeaders>,
    goaway_received: Option<StreamId>,
    goaway_sent: bool,
    failed: Option<H2Error>,
}

impl Connection {
    /// A client endpoint. The connection preface and SETTINGS are queued.
    pub fn client(settings: Settings) -> Self {
        Self::new(Role::Client, settings)
    }

    /// A server endpoint. SETTINGS are queued; the client preface is expected
    /// as the first bytes fed.
    pub fn server(settings: Settings) -> Self {
        Self::new(Role::Server, settings)
    }

    fn new(role: Role, settings: Settings) -> Self {
        let local = settings.sanitized();
        let mut c = Connection {
            role,
            decoder: Decoder::new(local.header_table_size as usize),
            encoder: Encoder::new(DEFAULT_TABLE_SIZE, true),
            peer: PeerSettings {
                max_concurrent_streams: None,
                initial_window_size: DEFAULT_WINDOW,
                max_frame_size: DEFAULT_MAX_FRAME_SIZE,
                max_header_list_size: None,
            },
            local,
            out: Vec::new(),
            inbuf: Vec::new(),
            preface_done: role == Role::Client,
            got_settings: false,
            settings_unacked: 1,
            recv_initial: DEFAULT_WINDOW,
            streams: HashMap::new(),
            local_open: 0,
            peer_open: 0,
            next_local_id: if role == Role::Client { 1 } else { 2 },
            highest_peer_id: 0,
            conn_send_window: DEFAULT_WINDOW,
            conn_recv_window: DEFAULT_WINDOW,
            conn_unreleased: 0,
            pending: None,
            goaway_received: None,
            goaway_sent: false,
            failed: None,
        };
        if role == Role::Client {
            c.out.extend_from_slice(PREFACE);
        }
        c.write_initial_settings();
        c
    }

    fn write_initial_settings(&mut self) {
        let s = &self.local;
        let mut params = Vec::new();
        if s.header_table_size as usize != DEFAULT_TABLE_SIZE {
            params.push((frame::SETTINGS_HEADER_TABLE_SIZE, s.header_table_size));
        }
        if self.role == Role::Client {
            params.push((frame::SETTINGS_ENABLE_PUSH, 0));
        }
        if let Some(n) = s.max_concurrent_streams {
            params.push((frame::SETTINGS_MAX_CONCURRENT_STREAMS, n));
        }
        if s.initial_window_size as i64 != DEFAULT_WINDOW {
            params.push((frame::SETTINGS_INITIAL_WINDOW_SIZE, s.initial_window_size));
        }
        if s.max_frame_size != DEFAULT_MAX_FRAME_SIZE {
            params.push((frame::SETTINGS_MAX_FRAME_SIZE, s.max_frame_size));
        }
        if let Some(n) = s.max_header_list_size {
            params.push((frame::SETTINGS_MAX_HEADER_LIST_SIZE, n));
        }
        write_settings(&mut self.out, &params);
        let extra = s.connection_window as i64 - DEFAULT_WINDOW;
        if extra > 0 {
            write_window_update(&mut self.out, 0, extra as u32);
            self.conn_recv_window += extra;
        }
    }

    /// Bytes queued for the transport. Call after every `feed` and send.
    pub fn take_output(&mut self) -> Vec<u8> {
        std::mem::take(&mut self.out)
    }

    /// True once a connection error occurred; only `take_output` (the queued
    /// GOAWAY) remains useful.
    pub fn is_failed(&self) -> bool {
        self.failed.is_some()
    }

    /// Streams currently open in either direction.
    pub fn open_streams(&self) -> usize {
        self.streams.len()
    }

    /// Send window usable right now: `min(connection, stream)`, or just the
    /// connection window for `id == 0` or an unknown stream.
    pub fn window_available(&self, id: StreamId) -> usize {
        let conn = self.conn_send_window;
        let w = self
            .streams
            .get(&id)
            .map_or(conn, |s| s.send_window.min(conn));
        w.max(0) as usize
    }

    // -----------------------------------------------------------------------
    // Receiving
    // -----------------------------------------------------------------------

    /// Consume bytes from the transport and return what happened.
    ///
    /// Events produced before a connection error in the same call are dropped
    /// with the error; the connection is unusable afterwards anyway.
    pub fn feed(&mut self, bytes: &[u8]) -> Result<Vec<Event>, H2Error> {
        if let Some(e) = &self.failed {
            return Err(e.clone());
        }
        self.inbuf.extend_from_slice(bytes);
        let mut events = Vec::new();
        match self.process(&mut events) {
            Ok(()) => Ok(events),
            Err(e) => {
                self.fail(&e);
                Err(e)
            }
        }
    }

    fn fail(&mut self, e: &H2Error) {
        write_goaway(
            &mut self.out,
            self.highest_peer_id,
            e.code,
            e.reason.as_bytes(),
        );
        self.goaway_sent = true;
        self.failed = Some(e.clone());
    }

    fn process(&mut self, ev: &mut Vec<Event>) -> Result<(), H2Error> {
        if !self.preface_done {
            let n = self.inbuf.len().min(PREFACE.len());
            if self.inbuf[..n] != PREFACE[..n] {
                return Err(proto("invalid connection preface"));
            }
            if n < PREFACE.len() {
                return Ok(());
            }
            self.inbuf.drain(..PREFACE.len());
            self.preface_done = true;
        }
        let mut pos = 0;
        let result = loop {
            let parsed = parse_frame(&self.inbuf[pos..], self.local.max_frame_size);
            let (frame, used) = match parsed {
                Ok(Some(p)) => p,
                Ok(None) => break Ok(()),
                Err(e) => break Err(e),
            };
            pos += used;
            if let Err(e) = self.handle(frame, ev) {
                break Err(e);
            }
        };
        self.inbuf.drain(..pos);
        result
    }

    fn handle(&mut self, frame: Frame, ev: &mut Vec<Event>) -> Result<(), H2Error> {
        self.check_sequence(&frame)?;
        match frame {
            Frame::Data {
                id,
                data,
                pad,
                flow_len,
                end_stream,
            } => self.on_data(id, data, pad, flow_len, end_stream, ev),
            Frame::Headers {
                id,
                block,
                end_stream,
                end_headers,
            } => self.on_headers(id, block, end_stream, end_headers, ev),
            Frame::Priority { .. } | Frame::Unknown { .. } => Ok(()),
            Frame::RstStream { id, code } => self.on_rst(id, code, ev),
            Frame::Settings { ack, params } => self.on_settings(ack, &params, ev),
            Frame::PushPromise { .. } => Err(proto("PUSH_PROMISE but push is disabled")),
            Frame::Ping { ack, data } => self.on_ping(ack, data, ev),
            Frame::GoAway {
                last_stream_id,
                code,
                debug,
            } => self.on_goaway(last_stream_id, code, debug, ev),
            Frame::WindowUpdate { id, increment } => self.on_window_update(id, increment, ev),
            Frame::Continuation {
                id,
                block,
                end_headers,
            } => self.on_continuation(id, block, end_headers, ev),
        }
    }

    /// Frame-order rules: SETTINGS first, and a header block is contiguous.
    fn check_sequence(&self, frame: &Frame) -> Result<(), H2Error> {
        if !self.got_settings && !matches!(frame, Frame::Settings { ack: false, .. }) {
            return Err(proto("first frame must be SETTINGS"));
        }
        let Some(p) = &self.pending else {
            if matches!(frame, Frame::Continuation { .. }) {
                return Err(proto("CONTINUATION without HEADERS"));
            }
            return Ok(());
        };
        if matches!(frame, Frame::Continuation { id, .. } if *id == p.id) {
            return Ok(());
        }
        Err(proto("header block interrupted by another frame"))
    }

    fn is_local_id(&self, id: StreamId) -> bool {
        (id % 2 == 1) == (self.role == Role::Client)
    }

    /// Never opened by either side yet.
    fn is_idle(&self, id: StreamId) -> bool {
        if self.is_local_id(id) {
            id >= self.next_local_id
        } else {
            id > self.highest_peer_id
        }
    }

    fn insert_stream(&mut self, id: StreamId, headers_sent: bool) {
        let s = Stream {
            send_window: self.peer.initial_window_size,
            recv_window: self.recv_initial,
            unreleased: 0,
            headers_received: 0,
            headers_sent,
            local_end: false,
            remote_end: false,
        };
        self.streams.insert(id, s);
        if self.is_local_id(id) {
            self.local_open += 1;
        } else {
            self.peer_open += 1;
        }
    }

    /// Drop a stream. After a reset its unread bytes can never be released by
    /// the application in a useful way, so they are returned to the connection
    /// window here.
    fn remove_stream(&mut self, id: StreamId, reset: bool) {
        let Some(s) = self.streams.remove(&id) else {
            return;
        };
        if self.is_local_id(id) {
            self.local_open -= 1;
        } else {
            self.peer_open -= 1;
        }
        if reset && s.unreleased > 0 {
            self.release_connection(s.unreleased);
        }
    }

    fn finish_if_done(&mut self, id: StreamId) {
        let done = self
            .streams
            .get(&id)
            .is_some_and(|s| s.local_end && s.remote_end);
        if done {
            self.remove_stream(id, false);
        }
    }

    fn release_connection(&mut self, n: i64) {
        let n = n.min(self.conn_unreleased);
        if n <= 0 {
            return;
        }
        self.conn_unreleased -= n;
        self.conn_recv_window += n;
        write_window_update(&mut self.out, 0, n as u32);
    }

    /// Reset a stream because of a stream error.
    fn stream_error(&mut self, id: StreamId, code: u32, ev: &mut Vec<Event>) {
        write_rst_stream(&mut self.out, id, code);
        if self.streams.contains_key(&id) {
            self.remove_stream(id, true);
            ev.push(Event::Reset { id, code });
        }
    }

    fn on_data(
        &mut self,
        id: StreamId,
        data: Vec<u8>,
        pad: u32,
        flow_len: u32,
        end_stream: bool,
        ev: &mut Vec<Event>,
    ) -> Result<(), H2Error> {
        let flow = flow_len as i64;
        if flow > self.conn_recv_window {
            return Err(H2Error::connection(
                FLOW_CONTROL_ERROR,
                "DATA exceeds connection window",
            ));
        }
        let len = data.len() as i64;
        // Padding is never delivered, so give it back immediately.
        if pad > 0 {
            write_window_update(&mut self.out, 0, pad);
        }
        if !self.streams.contains_key(&id) {
            self.conn_recv_window -= len;
            self.conn_unreleased += len;
            self.release_connection(len);
            if self.is_idle(id) {
                return Err(proto("DATA on idle stream"));
            }
            return Ok(());
        }
        if let Some(code) = self.data_stream_error(id, flow) {
            self.conn_recv_window -= len;
            self.conn_unreleased += len;
            self.release_connection(len);
            self.stream_error(id, code, ev);
            return Ok(());
        }
        self.conn_recv_window -= len;
        self.conn_unreleased += len;
        let Some(s) = self.streams.get_mut(&id) else {
            return Ok(());
        };
        s.recv_window -= flow - pad as i64;
        s.unreleased += len;
        if pad > 0 {
            write_window_update(&mut self.out, id, pad);
        }
        if end_stream {
            s.remote_end = true;
        }
        ev.push(Event::Data {
            id,
            data,
            end_stream,
        });
        if end_stream {
            self.finish_if_done(id);
        }
        Ok(())
    }

    /// Stream-scoped reasons to reject DATA.
    fn data_stream_error(&self, id: StreamId, flow: i64) -> Option<u32> {
        let s = self.streams.get(&id)?;
        if s.remote_end {
            return Some(STREAM_CLOSED);
        }
        if s.headers_received == 0 {
            return Some(PROTOCOL_ERROR);
        }
        if flow > s.recv_window {
            return Some(FLOW_CONTROL_ERROR);
        }
        None
    }

    fn header_block_cap(&self) -> usize {
        let list = self
            .local
            .max_header_list_size
            .map_or(1 << 20, |m| m as usize);
        list.saturating_mul(2).max(16 * 1024)
    }

    fn on_headers(
        &mut self,
        id: StreamId,
        block: Vec<u8>,
        end_stream: bool,
        end_headers: bool,
        ev: &mut Vec<Event>,
    ) -> Result<(), H2Error> {
        if block.len() > self.header_block_cap() {
            return Err(H2Error::connection(
                ENHANCE_YOUR_CALM,
                "header block too large",
            ));
        }
        let p = PendingHeaders {
            id,
            block,
            end_stream,
        };
        if end_headers {
            return self.finish_headers(p, ev);
        }
        self.pending = Some(p);
        Ok(())
    }

    fn on_continuation(
        &mut self,
        _id: StreamId,
        block: Vec<u8>,
        end_headers: bool,
        ev: &mut Vec<Event>,
    ) -> Result<(), H2Error> {
        let cap = self.header_block_cap();
        let Some(mut p) = self.pending.take() else {
            return Err(proto("CONTINUATION without HEADERS"));
        };
        if p.block.len() + block.len() > cap {
            return Err(H2Error::connection(
                ENHANCE_YOUR_CALM,
                "header block too large",
            ));
        }
        p.block.extend_from_slice(&block);
        if end_headers {
            return self.finish_headers(p, ev);
        }
        self.pending = Some(p);
        Ok(())
    }

    fn finish_headers(&mut self, p: PendingHeaders, ev: &mut Vec<Event>) -> Result<(), H2Error> {
        let max_list = self
            .local
            .max_header_list_size
            .map_or(usize::MAX, |m| m as usize);
        // Always decode: HPACK state must advance even for rejected streams.
        let (headers, size) = self
            .decoder
            .decode(&p.block, max_list)
            .map_err(|e| H2Error::connection(COMPRESSION_ERROR, e.to_string()))?;
        let too_large = size > max_list;
        if self.streams.contains_key(&p.id) {
            return self.headers_on_stream(p.id, headers, too_large, p.end_stream, ev);
        }
        self.headers_on_new_stream(p.id, headers, too_large, p.end_stream, ev)
    }

    fn headers_on_new_stream(
        &mut self,
        id: StreamId,
        headers: Vec<Header>,
        too_large: bool,
        end_stream: bool,
        ev: &mut Vec<Event>,
    ) -> Result<(), H2Error> {
        if self.is_local_id(id) {
            if id >= self.next_local_id {
                return Err(proto("HEADERS on idle stream with our parity"));
            }
            return Ok(()); // a stream we already closed or reset
        }
        if self.role == Role::Client {
            return Err(proto("server-initiated stream but push is disabled"));
        }
        if id <= self.highest_peer_id {
            return Err(H2Error::connection(
                STREAM_CLOSED,
                "HEADERS on closed stream",
            ));
        }
        self.highest_peer_id = id;
        if self.goaway_sent {
            return Ok(());
        }
        let over_limit = self
            .local
            .max_concurrent_streams
            .is_some_and(|max| self.peer_open >= max);
        if over_limit {
            write_rst_stream(&mut self.out, id, REFUSED_STREAM);
            return Ok(());
        }
        if too_large {
            write_rst_stream(&mut self.out, id, ENHANCE_YOUR_CALM);
            return Ok(());
        }
        if validate_headers(HeaderKind::Request, &headers).is_err() {
            write_rst_stream(&mut self.out, id, PROTOCOL_ERROR);
            return Ok(());
        }
        self.insert_stream(id, false);
        if let Some(s) = self.streams.get_mut(&id) {
            s.headers_received = 1;
            s.remote_end = end_stream;
        }
        ev.push(Event::Headers {
            id,
            headers,
            end_stream,
        });
        self.finish_if_done(id);
        Ok(())
    }

    fn headers_on_stream(
        &mut self,
        id: StreamId,
        headers: Vec<Header>,
        too_large: bool,
        end_stream: bool,
        ev: &mut Vec<Event>,
    ) -> Result<(), H2Error> {
        let Some(s) = self.streams.get(&id) else {
            return Ok(());
        };
        if s.remote_end {
            return Err(H2Error::connection(
                STREAM_CLOSED,
                "HEADERS after END_STREAM",
            ));
        }
        let kind = match (s.headers_received, self.role) {
            (0, Role::Client) => HeaderKind::Response,
            (0, Role::Server) => HeaderKind::Request,
            _ => HeaderKind::Trailers,
        };
        let interim = kind == HeaderKind::Response && is_informational(&headers);
        let invalid = too_large
            || validate_headers(kind, &headers).is_err()
            || (kind == HeaderKind::Trailers && !end_stream)
            || (interim && end_stream);
        if invalid {
            let code = if too_large {
                ENHANCE_YOUR_CALM
            } else {
                PROTOCOL_ERROR
            };
            self.stream_error(id, code, ev);
            return Ok(());
        }
        if let Some(s) = self.streams.get_mut(&id) {
            if !interim {
                s.headers_received = s.headers_received.saturating_add(1);
            }
            s.remote_end = end_stream;
        }
        ev.push(Event::Headers {
            id,
            headers,
            end_stream,
        });
        if end_stream {
            self.finish_if_done(id);
        }
        Ok(())
    }

    fn on_rst(&mut self, id: StreamId, code: u32, ev: &mut Vec<Event>) -> Result<(), H2Error> {
        if self.streams.contains_key(&id) {
            self.remove_stream(id, true);
            ev.push(Event::Reset { id, code });
            return Ok(());
        }
        if self.is_idle(id) {
            return Err(proto("RST_STREAM on idle stream"));
        }
        Ok(())
    }

    fn on_ping(&mut self, ack: bool, data: [u8; 8], ev: &mut Vec<Event>) -> Result<(), H2Error> {
        if ack {
            ev.push(Event::PingAck { data });
        } else {
            write_ping(&mut self.out, true, data);
        }
        Ok(())
    }

    fn on_goaway(
        &mut self,
        last: StreamId,
        code: u32,
        debug: Vec<u8>,
        ev: &mut Vec<Event>,
    ) -> Result<(), H2Error> {
        self.goaway_received = Some(last);
        ev.push(Event::GoAway {
            last_stream_id: last,
            code,
            debug,
        });
        let mut refused: Vec<StreamId> = self
            .streams
            .keys()
            .copied()
            .filter(|&id| self.is_local_id(id) && id > last)
            .collect();
        refused.sort_unstable();
        for id in refused {
            self.remove_stream(id, true);
            ev.push(Event::Reset {
                id,
                code: REFUSED_STREAM,
            });
        }
        Ok(())
    }

    fn on_window_update(
        &mut self,
        id: StreamId,
        increment: u32,
        ev: &mut Vec<Event>,
    ) -> Result<(), H2Error> {
        let inc = increment as i64;
        if id == 0 {
            if inc == 0 {
                return Err(proto("WINDOW_UPDATE increment of 0"));
            }
            let new = self.conn_send_window + inc;
            if new > MAX_WINDOW {
                return Err(H2Error::connection(
                    FLOW_CONTROL_ERROR,
                    "connection window overflow",
                ));
            }
            self.conn_send_window = new;
            ev.push(Event::WindowOpened { id: 0 });
            return Ok(());
        }
        let Some(s) = self.streams.get_mut(&id) else {
            if self.is_idle(id) {
                return Err(proto("WINDOW_UPDATE on idle stream"));
            }
            return Ok(());
        };
        let new = s.send_window + inc;
        if inc == 0 || new > MAX_WINDOW {
            let code = if inc == 0 {
                PROTOCOL_ERROR
            } else {
                FLOW_CONTROL_ERROR
            };
            self.stream_error(id, code, ev);
            return Ok(());
        }
        s.send_window = new;
        ev.push(Event::WindowOpened { id });
        Ok(())
    }

    fn on_settings(
        &mut self,
        ack: bool,
        params: &[(u16, u32)],
        ev: &mut Vec<Event>,
    ) -> Result<(), H2Error> {
        if ack {
            if self.settings_unacked > 0 {
                self.settings_unacked -= 1;
                self.apply_local_settings();
                ev.push(Event::SettingsAcked);
            }
            return Ok(());
        }
        self.got_settings = true;
        for &(key, value) in params {
            self.apply_peer_setting(key, value, ev)?;
        }
        write_settings_ack(&mut self.out);
        Ok(())
    }

    fn apply_peer_setting(
        &mut self,
        key: u16,
        value: u32,
        ev: &mut Vec<Event>,
    ) -> Result<(), H2Error> {
        match key {
            frame::SETTINGS_HEADER_TABLE_SIZE => {
                let size = (value as usize).min(DEFAULT_TABLE_SIZE);
                self.encoder.set_max_table_size(size);
            }
            frame::SETTINGS_ENABLE_PUSH if value > 1 => {
                return Err(proto("SETTINGS_ENABLE_PUSH out of range"));
            }
            frame::SETTINGS_MAX_CONCURRENT_STREAMS => {
                self.peer.max_concurrent_streams = Some(value);
            }
            frame::SETTINGS_INITIAL_WINDOW_SIZE => self.set_peer_initial_window(value, ev)?,
            frame::SETTINGS_MAX_FRAME_SIZE => {
                if !(DEFAULT_MAX_FRAME_SIZE..=MAX_MAX_FRAME_SIZE).contains(&value) {
                    return Err(proto("SETTINGS_MAX_FRAME_SIZE out of range"));
                }
                self.peer.max_frame_size = value;
            }
            frame::SETTINGS_MAX_HEADER_LIST_SIZE => {
                self.peer.max_header_list_size = Some(value);
            }
            _ => {}
        }
        Ok(())
    }

    fn set_peer_initial_window(&mut self, value: u32, ev: &mut Vec<Event>) -> Result<(), H2Error> {
        if value as i64 > MAX_WINDOW {
            return Err(H2Error::connection(
                FLOW_CONTROL_ERROR,
                "SETTINGS_INITIAL_WINDOW_SIZE too large",
            ));
        }
        let delta = value as i64 - self.peer.initial_window_size;
        self.peer.initial_window_size = value as i64;
        let mut opened = Vec::new();
        for (&id, s) in self.streams.iter_mut() {
            let before = s.send_window;
            s.send_window += delta;
            if s.send_window > MAX_WINDOW {
                return Err(H2Error::connection(
                    FLOW_CONTROL_ERROR,
                    "stream window overflow after SETTINGS",
                ));
            }
            if before <= 0 && s.send_window > 0 {
                opened.push(id);
            }
        }
        opened.sort_unstable();
        ev.extend(opened.into_iter().map(|id| Event::WindowOpened { id }));
        Ok(())
    }

    /// The peer acknowledged our SETTINGS, so it now applies our receive
    /// window to every stream.
    fn apply_local_settings(&mut self) {
        let new = self.local.initial_window_size as i64;
        let delta = new - self.recv_initial;
        self.recv_initial = new;
        for s in self.streams.values_mut() {
            s.recv_window += delta;
        }
    }

    // -----------------------------------------------------------------------
    // Sending
    // -----------------------------------------------------------------------

    fn check_can_open(&self) -> Result<(), H2Error> {
        if let Some(e) = &self.failed {
            return Err(H2Error::usage(format!("connection failed: {}", e.reason)));
        }
        if self.goaway_received.is_some() || self.goaway_sent {
            return Err(H2Error::usage("connection is shutting down"));
        }
        Ok(())
    }

    fn check_header_list(&self, headers: &[Header]) -> Result<(), H2Error> {
        let Some(max) = self.peer.max_header_list_size else {
            return Ok(());
        };
        let size: usize = headers.iter().map(|(n, v)| n.len() + v.len() + 32).sum();
        if size > max as usize {
            return Err(H2Error::usage(
                "headers exceed peer SETTINGS_MAX_HEADER_LIST_SIZE",
            ));
        }
        Ok(())
    }

    fn write_headers(&mut self, id: StreamId, headers: &[Header], end_stream: bool) {
        let mut block = Vec::new();
        self.encoder.encode(headers, &mut block);
        write_header_block(
            &mut self.out,
            id,
            &block,
            end_stream,
            self.peer.max_frame_size,
        );
    }

    /// Client: start a request. `headers` must hold the pseudo-headers
    /// (`:method`, `:scheme`, `:path`, and `:authority` when known) first.
    pub fn open_stream(
        &mut self,
        headers: Vec<Header>,
        end_stream: bool,
    ) -> Result<StreamId, H2Error> {
        if self.role != Role::Client {
            return Err(H2Error::usage("only a client opens streams"));
        }
        self.check_can_open()?;
        validate_headers(HeaderKind::Request, &headers).map_err(H2Error::usage)?;
        self.check_header_list(&headers)?;
        if let Some(max) = self.peer.max_concurrent_streams
            && self.local_open >= max
        {
            return Err(H2Error {
                code: REFUSED_STREAM,
                reason: "peer SETTINGS_MAX_CONCURRENT_STREAMS reached".into(),
                fatal: false,
            });
        }
        let id = self.next_local_id;
        if id as i64 > MAX_WINDOW {
            return Err(H2Error::usage("stream ids exhausted"));
        }
        self.next_local_id += 2;
        self.insert_stream(id, true);
        if let Some(s) = self.streams.get_mut(&id) {
            s.local_end = end_stream;
        }
        self.write_headers(id, &headers, end_stream);
        Ok(id)
    }

    /// Server: send a response header block. A `1xx` status is an interim
    /// response and may be repeated; the final response must come before any
    /// DATA.
    pub fn send_response_headers(
        &mut self,
        id: StreamId,
        headers: Vec<Header>,
        end_stream: bool,
    ) -> Result<(), H2Error> {
        if self.role != Role::Server {
            return Err(H2Error::usage("only a server sends responses"));
        }
        let headers_sent = self.sendable_stream(id)?.headers_sent;
        validate_headers(HeaderKind::Response, &headers).map_err(H2Error::usage)?;
        self.check_header_list(&headers)?;
        let interim = is_informational(&headers);
        if interim && end_stream {
            return Err(H2Error::usage("interim response cannot end the stream"));
        }
        if headers_sent && !interim {
            return Err(H2Error::usage(
                "final response already sent; use send_trailers",
            ));
        }
        self.write_headers(id, &headers, end_stream);
        self.after_send(id, !interim, end_stream);
        Ok(())
    }

    /// Either side: send trailers, which end the stream.
    pub fn send_trailers(&mut self, id: StreamId, headers: Vec<Header>) -> Result<(), H2Error> {
        if !self.sendable_stream(id)?.headers_sent {
            return Err(H2Error::usage("trailers before the header block"));
        }
        validate_headers(HeaderKind::Trailers, &headers).map_err(H2Error::usage)?;
        self.check_header_list(&headers)?;
        self.write_headers(id, &headers, true);
        self.after_send(id, false, true);
        Ok(())
    }

    fn sendable_stream(&self, id: StreamId) -> Result<&Stream, H2Error> {
        let Some(s) = self.streams.get(&id) else {
            return Err(H2Error::usage("unknown or closed stream"));
        };
        if s.local_end {
            return Err(H2Error::usage("stream already ended locally"));
        }
        Ok(s)
    }

    fn after_send(&mut self, id: StreamId, final_headers: bool, end_stream: bool) {
        if let Some(s) = self.streams.get_mut(&id) {
            s.headers_sent |= final_headers;
            s.local_end |= end_stream;
        }
        if end_stream {
            self.finish_if_done(id);
        }
    }

    /// Send as much of `data` as the windows and frame size allow and return
    /// the byte count accepted. `end_stream` takes effect only when everything
    /// was accepted. Returns 0 for an unknown stream, before the header block
    /// was sent, after the stream ended, or when no window is available (retry
    /// after [`Event::WindowOpened`]). `send_data(id, &[], true)` ends the
    /// stream without a window.
    pub fn send_data(&mut self, id: StreamId, data: &[u8], end_stream: bool) -> usize {
        let conn_window = self.conn_send_window;
        let max_frame = self.peer.max_frame_size as usize;
        let Some(s) = self.streams.get_mut(&id) else {
            return 0;
        };
        if !s.headers_sent || s.local_end {
            return 0;
        }
        let allowed = s.send_window.min(conn_window).max(0) as usize;
        let n = data.len().min(allowed);
        let fin = end_stream && n == data.len();
        if n == 0 && !fin {
            return 0;
        }
        let mut rest = &data[..n];
        if rest.is_empty() {
            write_data(&mut self.out, id, &[], true);
        }
        while !rest.is_empty() {
            let (chunk, tail) = rest.split_at(rest.len().min(max_frame));
            write_data(&mut self.out, id, chunk, fin && tail.is_empty());
            rest = tail;
        }
        s.send_window -= n as i64;
        s.local_end = fin;
        self.conn_send_window -= n as i64;
        if fin {
            self.finish_if_done(id);
        }
        n
    }

    /// Abort a stream with RST_STREAM. Unknown streams are ignored.
    pub fn send_rst(&mut self, id: StreamId, code: u32) {
        if self.streams.contains_key(&id) {
            write_rst_stream(&mut self.out, id, code);
            self.remove_stream(id, true);
        }
    }

    /// Return `n` consumed bytes of received DATA to the peer's windows. The
    /// connection window is always credited; the stream window only while the
    /// peer may still send on the stream.
    pub fn release(&mut self, id: StreamId, n: usize) {
        let n = n.min(MAX_WINDOW as usize) as i64;
        let mut stream_credit = 0;
        if let Some(s) = self.streams.get_mut(&id) {
            let credit = n.min(s.unreleased);
            s.unreleased -= credit;
            if !s.remote_end {
                s.recv_window += credit;
                stream_credit = credit;
            }
        }
        if stream_credit > 0 {
            write_window_update(&mut self.out, id, stream_credit as u32);
        }
        self.release_connection(n);
    }

    /// Queue a PING; the answer arrives as [`Event::PingAck`].
    pub fn send_ping(&mut self, data: [u8; 8]) {
        write_ping(&mut self.out, false, data);
    }

    /// Start graceful shutdown: queue GOAWAY and refuse new peer streams.
    pub fn shutdown(&mut self, code: u32) {
        write_goaway(&mut self.out, self.highest_peer_id, code, &[]);
        self.goaway_sent = true;
    }
}

// ---------------------------------------------------------------------------
// Header validation
// ---------------------------------------------------------------------------

/// Which kind of header block is being validated.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HeaderKind {
    Request,
    Response,
    Trailers,
}

fn is_informational(headers: &[Header]) -> bool {
    headers
        .iter()
        .find(|(n, _)| n == b":status")
        .is_some_and(|(_, v)| v.len() == 3 && v[0] == b'1')
}

fn is_token_byte(b: u8) -> bool {
    b.is_ascii_lowercase() || b.is_ascii_digit() || b"!#$%&'*+-.^_`|~".contains(&b)
}

fn check_name(name: &[u8]) -> Result<(), String> {
    if name.is_empty() {
        return Err("empty header name".into());
    }
    let body = name.strip_prefix(b":").unwrap_or(name);
    if body.is_empty() || !body.iter().all(|&b| is_token_byte(b)) {
        return Err(format!(
            "invalid header name {:?} (must be lowercase token)",
            String::from_utf8_lossy(name)
        ));
    }
    Ok(())
}

fn check_value(name: &[u8], value: &[u8]) -> Result<(), String> {
    if value.iter().any(|&b| b == 0 || b == b'\r' || b == b'\n') {
        return Err(format!(
            "invalid value for header {:?}",
            String::from_utf8_lossy(name)
        ));
    }
    Ok(())
}

const CONNECTION_SPECIFIC: [&[u8]; 5] = [
    b"connection",
    b"proxy-connection",
    b"keep-alive",
    b"transfer-encoding",
    b"upgrade",
];

/// Validate a header block as HTTP/2 requires: lowercase names,
/// pseudo-headers first and unique, no connection-specific headers, the
/// required pseudo-headers for the block kind, and no pseudo-headers in
/// trailers.
pub fn validate_headers(kind: HeaderKind, headers: &[Header]) -> Result<(), String> {
    let mut seen_regular = false;
    let mut method: Option<&[u8]> = None;
    let (mut scheme, mut path, mut authority, mut status) = (None, None, None, None);
    for (name, value) in headers {
        check_name(name)?;
        check_value(name, value)?;
        if name[0] != b':' {
            seen_regular = true;
            if CONNECTION_SPECIFIC.contains(&name.as_slice()) {
                return Err(format!(
                    "connection-specific header {:?}",
                    String::from_utf8_lossy(name)
                ));
            }
            if name == b"te" && value != b"trailers" {
                return Err("te header may only be \"trailers\"".into());
            }
            continue;
        }
        if kind == HeaderKind::Trailers {
            return Err("pseudo-header in trailers".into());
        }
        if seen_regular {
            return Err("pseudo-header after regular header".into());
        }
        let slot = match (kind, name.as_slice()) {
            (HeaderKind::Request, b":method") => &mut method,
            (HeaderKind::Request, b":scheme") => &mut scheme,
            (HeaderKind::Request, b":path") => &mut path,
            (HeaderKind::Request, b":authority") => &mut authority,
            (HeaderKind::Response, b":status") => &mut status,
            _ => {
                return Err(format!(
                    "unexpected pseudo-header {:?}",
                    String::from_utf8_lossy(name)
                ));
            }
        };
        if slot.replace(value.as_slice()).is_some() {
            return Err(format!(
                "duplicate pseudo-header {:?}",
                String::from_utf8_lossy(name)
            ));
        }
    }
    match kind {
        HeaderKind::Trailers => Ok(()),
        HeaderKind::Response => validate_status(status),
        HeaderKind::Request => validate_request(method, scheme, path, authority.is_some()),
    }
}

fn validate_status(status: Option<&[u8]>) -> Result<(), String> {
    let Some(s) = status else {
        return Err("response missing :status".into());
    };
    let ok = s.len() == 3 && s.iter().all(u8::is_ascii_digit) && (b'1'..=b'5').contains(&s[0]);
    if ok {
        Ok(())
    } else {
        Err("invalid :status".into())
    }
}

fn validate_request(
    method: Option<&[u8]>,
    scheme: Option<&[u8]>,
    path: Option<&[u8]>,
    has_authority: bool,
) -> Result<(), String> {
    let Some(method) = method.filter(|m| !m.is_empty()) else {
        return Err("request missing :method".into());
    };
    if method == b"CONNECT" {
        if scheme.is_some() || path.is_some() {
            return Err("CONNECT must not carry :scheme or :path".into());
        }
        if !has_authority {
            return Err("CONNECT requires :authority".into());
        }
        return Ok(());
    }
    if scheme.is_none_or(<[u8]>::is_empty) {
        return Err("request missing :scheme".into());
    }
    if path.is_none_or(<[u8]>::is_empty) {
        return Err("request missing :path".into());
    }
    Ok(())
}

#[cfg(test)]
mod tests;
