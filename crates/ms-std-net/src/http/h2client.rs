//! HTTP/2 client transport: one [`Session`] per origin multiplexes request
//! streams over a single connection, driven by the sans-io [`crate::h2`] core.
//!
//! The ms thread is single threaded, so nothing pumps in the background: every
//! waiter (a request waiting for its head, a body waiting for data, an upload
//! waiting for window) calls [`Session::pump`], which writes queued output,
//! reads once, feeds the core and files the resulting events into per-stream
//! queues. A waiter then looks at its own queue; data that arrived for other
//! streams stays queued until their readers ask.
//!
//! Tasks share a session, and the runtime allows one waiter per descriptor, so one
//! task at a time owns the socket (`driving`): it is the driver, parked in a read or a
//! blocking write. Another task that needs a pump parks on a token until the driver has
//! filed events, then looks at its queue again and drives if it is still empty. A task that
//! only has output (a new request) hands the bytes to the socket without waiting, and keeps
//! what does not fit for the driver's next write.

use crate::conn::Connection;
use crate::error::IoErr;
use crate::h2::{self, Event, Header, Settings, StreamId, error_code};
use crate::rt::{self, Token};
use crate::wait::{Deadline, Wait, wait_token};
use std::cell::{Cell, RefCell};
use std::collections::{HashMap, VecDeque};
use std::rc::Rc;
use std::time::{Duration, Instant};

const READ_BUF: usize = 64 * 1024;
/// Longest the best-effort flush of a cancellation may block.
const CANCEL_FLUSH: Duration = Duration::from_millis(200);

/// Local settings, sized so a slow reader of one stream
/// does not starve the others.
pub(crate) fn client_settings(max_header_bytes: Option<u64>) -> Settings {
    Settings {
        initial_window_size: 4 << 20,
        connection_window: 1 << 30,
        max_header_list_size: max_header_bytes.map(|n| n.min(u32::MAX as u64) as u32),
        ..Settings::default()
    }
}

/// The name of an HTTP/2 error code.
pub(crate) fn code_name(code: u32) -> String {
    let name = match code {
        error_code::NO_ERROR => "NO_ERROR",
        error_code::PROTOCOL_ERROR => "PROTOCOL_ERROR",
        error_code::INTERNAL_ERROR => "INTERNAL_ERROR",
        error_code::FLOW_CONTROL_ERROR => "FLOW_CONTROL_ERROR",
        error_code::SETTINGS_TIMEOUT => "SETTINGS_TIMEOUT",
        error_code::STREAM_CLOSED => "STREAM_CLOSED",
        error_code::FRAME_SIZE_ERROR => "FRAME_SIZE_ERROR",
        error_code::REFUSED_STREAM => "REFUSED_STREAM",
        error_code::CANCEL => "CANCEL",
        error_code::COMPRESSION_ERROR => "COMPRESSION_ERROR",
        error_code::CONNECT_ERROR => "CONNECT_ERROR",
        error_code::ENHANCE_YOUR_CALM => "ENHANCE_YOUR_CALM",
        error_code::INADEQUATE_SECURITY => "INADEQUATE_SECURITY",
        error_code::HTTP_1_1_REQUIRED => "HTTP_1_1_REQUIRED",
        other => return format!("unknown error code {other:#x}"),
    };
    name.to_string()
}

/// The message of a stream the peer reset.
pub(crate) fn reset_text(id: StreamId, code: u32) -> String {
    format!(
        "stream error: stream ID {id}; {}; received from peer",
        code_name(code)
    )
}

/// Why a pump failed.
pub(crate) enum PumpErr {
    Timeout,
    Closed,
    Failed(String),
}

/// Why a stream could not be opened.
pub(crate) enum OpenErr {
    /// The session is closed, failed or shutting down.
    Unavailable,
    /// The peer's concurrent stream limit is reached; pump and retry.
    Full,
    Invalid(String),
}

/// What a stream's reader finds in its queue.
pub(crate) enum Poll {
    Head(Vec<Header>),
    Data(Vec<u8>),
    End,
    Reset(u32),
    /// The server did not process the request (REFUSED_STREAM or beyond the
    /// GOAWAY's last stream), so it is safe to replay.
    Refused,
    /// The connection ended without finishing the stream.
    Dead,
    Pending,
}

#[derive(Default)]
struct Queue {
    head: Option<Vec<Header>>,
    head_seen: bool,
    data: VecDeque<Vec<u8>>,
    ended: bool,
    reset: Option<u32>,
    unprocessed: bool,
    /// The request was HEAD, so a `content-length` describes a body that is not sent.
    head_request: bool,
    /// The declared body length, once the response head arrived.
    expected: Option<u64>,
    /// Body bytes received so far.
    received: u64,
    /// The body does not match its `content-length` (RFC 9113 section 8.1.1).
    malformed: bool,
}

impl Queue {
    /// Flags a body that is longer than declared, or ended shorter than declared.
    fn check_length(&mut self) {
        if let Some(n) = self.expected
            && (self.received > n || (self.ended && self.received != n))
        {
            self.malformed = true;
        }
    }
}

/// The `content-length` a response declares: none when absent or when the message has no body,
/// an error when the values are not one number.
fn declared_length(headers: &[Header], head_request: bool) -> Result<Option<u64>, ()> {
    let status = headers
        .iter()
        .find(|(n, _)| n == b":status")
        .and_then(|(_, v)| std::str::from_utf8(v).ok()?.parse::<u16>().ok())
        .unwrap_or(0);
    let mut found: Option<u64> = None;
    for (_, value) in headers.iter().filter(|(n, _)| n == b"content-length") {
        if value.is_empty() || !value.iter().all(u8::is_ascii_digit) {
            return Err(());
        }
        let n: u64 = std::str::from_utf8(value)
            .ok()
            .and_then(|v| v.parse().ok())
            .ok_or(())?;
        if found.is_some_and(|f| f != n) {
            return Err(());
        }
        found = Some(n);
    }
    if head_request || matches!(status, 204 | 304) {
        return Ok(None);
    }
    Ok(found)
}

struct State {
    core: h2::Connection,
    streams: HashMap<StreamId, Queue>,
    dead: bool,
    goaway: bool,
}

/// One HTTP/2 connection shared by the requests to an origin.
pub(crate) struct Session {
    conn: Rc<Connection>,
    state: RefCell<State>,
    /// Taken out for the driver's read; see the module notes.
    scratch: Cell<Vec<u8>>,
    used: Cell<Instant>,
    /// A task owns the socket, parked in a read or a blocking write.
    driving: Cell<bool>,
    /// Which turn owns the socket, so a late release of an earlier one is ignored.
    turn_id: Cell<u64>,
    /// Tokens of the tasks waiting for the driver.
    waiters: RefCell<Vec<u64>>,
    /// Output the core produced that the socket has not taken yet.
    pending: RefCell<Vec<u8>>,
}

fn map_io(e: IoErr) -> PumpErr {
    match e {
        IoErr::Closed => PumpErr::Closed,
        IoErr::Failed(m) if m == "operation timed out" => PumpErr::Timeout,
        IoErr::Failed(m) => PumpErr::Failed(m),
        _ => PumpErr::Failed("i/o error".into()),
    }
}

/// Ownership of the socket for one drive; ending it wakes the waiting tasks. A fault or
/// cancellation that leaves the task's guard skips destructors, so the same release is
/// also registered on the task's cleanup stack.
struct Turn<'a> {
    session: &'a Session,
    id: u64,
    cleanup: usize,
    /// What the cleanup action reads; freed with the turn, leaked with abandoned frames.
    _release: Box<Release>,
}

impl Session {
    /// Ends turn `id` unless it already ended.
    fn release(&self, id: u64) {
        if !self.driving.get() || self.turn_id.get() != id {
            return;
        }
        self.driving.set(false);
        let waiters = std::mem::take(&mut *self.waiters.borrow_mut());
        for token in waiters {
            rt::post(token);
        }
    }
}

/// What the cleanup action needs to end a turn.
struct Release {
    session: *const Session,
    id: u64,
}

unsafe extern "C-unwind" fn release_turn(arg: *mut u8) {
    // SAFETY: `arg` is the `Release` a live `Turn` owns, or one its abandoned frame leaked; the
    // session outlives it, since abandoned frames keep their `Rc` (nothing frees them).
    let r = unsafe { &*arg.cast::<Release>() };
    // SAFETY: as above, the session is alive.
    unsafe { (*r.session).release(r.id) };
}

impl Drop for Turn<'_> {
    fn drop(&mut self) {
        rt::cleanup_discard(self.cleanup);
        self.session.release(self.id);
    }
}

impl Session {
    pub(crate) fn new(conn: Rc<Connection>, settings: Settings) -> Rc<Session> {
        Rc::new(Session {
            conn,
            state: RefCell::new(State {
                core: h2::Connection::client(settings),
                streams: HashMap::new(),
                dead: false,
                goaway: false,
            }),
            scratch: Cell::new(Vec::new()),
            used: Cell::new(Instant::now()),
            driving: Cell::new(false),
            turn_id: Cell::new(0),
            waiters: RefCell::new(Vec::new()),
            pending: RefCell::new(Vec::new()),
        })
    }

    pub(crate) fn conn(&self) -> &Rc<Connection> {
        &self.conn
    }

    /// Whether new requests may start on this session.
    pub(crate) fn usable(&self) -> bool {
        let st = self.state.borrow();
        !self.conn.is_closed() && !st.dead && !st.goaway && !st.core.is_failed()
    }

    /// How long the session has had no open stream; `None` while busy.
    pub(crate) fn idle_for(&self) -> Option<Duration> {
        let busy = !self.state.borrow().streams.is_empty();
        (!busy).then(|| self.used.get().elapsed())
    }

    /// Queues a GOAWAY and closes the connection.
    pub(crate) fn close(&self) {
        self.state.borrow_mut().core.shutdown(error_code::NO_ERROR);
        let _ = self.flush(Deadline::after(CANCEL_FLUSH));
        self.conn.close();
    }

    fn mark_dead(&self) {
        self.state.borrow_mut().dead = true;
    }

    /// Writes everything the core queued. While another task owns the socket, writes what
    /// the socket takes at once and leaves the rest to that task.
    pub(crate) fn flush(&self, deadline: Deadline) -> Result<(), PumpErr> {
        if self.driving.get() {
            return self.flush_nowait();
        }
        let _turn = self.turn();
        self.flush_owned(deadline)
    }

    fn turn(&self) -> Turn<'_> {
        self.driving.set(true);
        let id = self.turn_id.get() + 1;
        self.turn_id.set(id);
        let mut release = Box::new(Release { session: self, id });
        let arg: *mut Release = &mut *release;
        // SAFETY: the box lives as long as the turn; `Turn::drop` discards the action first.
        let cleanup = unsafe { rt::cleanup_push(release_turn, arg.cast()) };
        Turn {
            session: self,
            id,
            cleanup,
            _release: release,
        }
    }

    /// The core's output after what is still pending.
    fn output(&self) -> Vec<u8> {
        let fresh = self.state.borrow_mut().core.take_output();
        let mut out = std::mem::take(&mut *self.pending.borrow_mut());
        out.extend(fresh);
        out
    }

    fn flush_nowait(&self) -> Result<(), PumpErr> {
        let out = self.output();
        if out.is_empty() {
            return Ok(());
        }
        match self.conn.write_nowait(&out) {
            Ok(n) => {
                self.pending.borrow_mut().extend_from_slice(&out[n..]);
                Ok(())
            }
            Err(e) => Err(self.failed(e)),
        }
    }

    /// Like `flush` for the task that owns the socket (holds a [`Turn`]).
    fn flush_owned(&self, deadline: Deadline) -> Result<(), PumpErr> {
        let out = self.output();
        if out.is_empty() {
            return Ok(());
        }
        self.conn
            .write_until(&out, deadline)
            .map_err(|e| self.failed(e))
    }

    fn failed(&self, e: IoErr) -> PumpErr {
        let e = map_io(e);
        if matches!(e, PumpErr::Failed(_)) {
            self.mark_dead();
        }
        e
    }

    /// Waits until the task that owns the socket has filed what it read (or finished
    /// writing); the caller then looks at its queue again.
    fn await_driver(&self, deadline: Deadline) -> Result<(), PumpErr> {
        let token = Token::new();
        self.waiters.borrow_mut().push(token.id());
        let got = wait_token(&token, deadline);
        self.waiters.borrow_mut().retain(|&w| w != token.id());
        match got {
            Wait::Ready => Ok(()),
            Wait::TimedOut => Err(PumpErr::Timeout),
        }
    }

    /// Writes pending output, reads once and files the events. The caller
    /// inspects its own queue afterwards. Another task may be reading already; this one
    /// then waits for it instead.
    pub(crate) fn pump(&self, deadline: Deadline) -> Result<(), PumpErr> {
        if self.driving.get() {
            return self.await_driver(deadline);
        }
        let _turn = self.turn();
        self.flush_owned(deadline)?;
        if self.state.borrow().dead {
            return Ok(());
        }
        // The read parks, so nothing shared is borrowed across it.
        let mut buf = self.scratch.take();
        buf.resize(READ_BUF, 0);
        let got = self.conn.read_into(&mut buf, deadline);
        let n = match got {
            Ok(n) => n,
            Err(e) => {
                self.scratch.set(buf);
                return Err(self.failed(e));
            }
        };
        if n == 0 {
            self.scratch.set(buf);
            self.mark_dead();
            return Ok(());
        }
        let fed = self.state.borrow_mut().core.feed(&buf[..n]);
        self.scratch.set(buf);
        let Ok(events) = fed else {
            // The core queued a GOAWAY; push it out, then give up.
            let _ = self.flush_owned(Deadline::after(CANCEL_FLUSH));
            self.mark_dead();
            self.conn.close();
            return Ok(());
        };
        self.dispatch(events);
        self.flush_owned(deadline)
    }

    fn dispatch(&self, events: Vec<Event>) {
        let mut st = self.state.borrow_mut();
        let st = &mut *st;
        for event in events {
            match event {
                Event::Headers {
                    id,
                    headers,
                    end_stream,
                } => {
                    let Some(q) = st.streams.get_mut(&id) else {
                        continue;
                    };
                    q.ended |= end_stream;
                    if q.head_seen || is_interim(&headers) {
                        q.check_length();
                        continue;
                    }
                    q.head_seen = true;
                    match declared_length(&headers, q.head_request) {
                        Ok(expected) => q.expected = expected,
                        Err(()) => q.malformed = true,
                    }
                    q.check_length();
                    q.head = Some(headers);
                }
                Event::Data {
                    id,
                    data,
                    end_stream,
                } => {
                    let Some(q) = st.streams.get_mut(&id) else {
                        st.core.release(id, data.len());
                        continue;
                    };
                    q.ended |= end_stream;
                    q.received += data.len() as u64;
                    q.check_length();
                    if !data.is_empty() {
                        q.data.push_back(data);
                    }
                }
                Event::Reset { id, code } => {
                    if let Some(q) = st.streams.get_mut(&id) {
                        q.reset = Some(code);
                    }
                }
                Event::GoAway { last_stream_id, .. } => {
                    st.goaway = true;
                    for (id, q) in st.streams.iter_mut() {
                        if *id > last_stream_id && !q.head_seen {
                            q.unprocessed = true;
                        }
                    }
                }
                Event::WindowOpened { .. } | Event::SettingsAcked | Event::PingAck { .. } => {}
            }
        }
    }

    /// Starts a request stream.
    pub(crate) fn open(
        self: &Rc<Self>,
        headers: Vec<Header>,
        end_stream: bool,
    ) -> Result<H2Stream, OpenErr> {
        if !self.usable() {
            return Err(OpenErr::Unavailable);
        }
        let head_request = headers.iter().any(|(n, v)| n == b":method" && v == b"HEAD");
        let mut st = self.state.borrow_mut();
        let opened = st.core.open_stream(headers, end_stream);
        let id = match opened {
            Ok(id) => id,
            Err(e) if e.code == error_code::REFUSED_STREAM && !st.streams.is_empty() => {
                return Err(OpenErr::Full);
            }
            Err(e) => return Err(OpenErr::Invalid(e.reason)),
        };
        st.streams.insert(
            id,
            Queue {
                head_request,
                ..Queue::default()
            },
        );
        self.used.set(Instant::now());
        Ok(H2Stream {
            session: self.clone(),
            id,
        })
    }

    /// Sends what the windows allow; the count accepted.
    pub(crate) fn send(&self, id: StreamId, data: &[u8], end_stream: bool) -> usize {
        self.state.borrow_mut().core.send_data(id, data, end_stream)
    }

    fn cancel(&self, id: StreamId) {
        {
            let mut st = self.state.borrow_mut();
            let queued = st
                .streams
                .remove(&id)
                .map_or(0, |q| q.data.iter().map(Vec::len).sum());
            if queued > 0 {
                st.core.release(id, queued);
            }
            st.core.send_rst(id, error_code::CANCEL);
        }
        self.used.set(Instant::now());
        if !self.state.borrow().dead {
            let _ = self.flush(Deadline::after(CANCEL_FLUSH));
        }
    }
}

fn is_interim(headers: &[Header]) -> bool {
    headers
        .iter()
        .find(|(n, _)| n == b":status")
        .is_some_and(|(_, v)| v.len() == 3 && v[0] == b'1')
}

/// One request stream. Dropping it cancels the stream unless it finished.
pub(crate) struct H2Stream {
    session: Rc<Session>,
    pub(crate) id: StreamId,
}

impl Drop for H2Stream {
    fn drop(&mut self) {
        self.session.cancel(self.id);
    }
}

impl H2Stream {
    pub(crate) fn session(&self) -> &Rc<Session> {
        &self.session
    }

    pub(crate) fn pump(&self, deadline: Deadline) -> Result<(), PumpErr> {
        self.session.pump(deadline)
    }

    pub(crate) fn send(&self, data: &[u8], end_stream: bool) -> usize {
        self.session.send(self.id, data, end_stream)
    }

    /// Whether the stream can still carry an upload.
    pub(crate) fn alive(&self) -> bool {
        let st = self.session.state.borrow();
        !st.dead
            && st
                .streams
                .get(&self.id)
                .is_some_and(|q| q.reset.is_none() && !q.unprocessed)
    }

    /// The whole response arrived and was read.
    pub(crate) fn drained(&self) -> bool {
        let st = self.session.state.borrow();
        st.streams
            .get(&self.id)
            .is_some_and(|q| q.ended && q.data.is_empty() && !q.malformed)
    }

    fn failure(q: &Queue, dead: bool) -> Poll {
        match q.reset {
            Some(error_code::REFUSED_STREAM) => Poll::Refused,
            Some(code) => Poll::Reset(code),
            None if q.unprocessed => Poll::Refused,
            None if dead => Poll::Dead,
            None => Poll::Pending,
        }
    }

    /// The response head once it arrived.
    pub(crate) fn poll_head(&self) -> Poll {
        let mut st = self.session.state.borrow_mut();
        let dead = st.dead;
        let Some(q) = st.streams.get_mut(&self.id) else {
            return Poll::Dead;
        };
        match q.head.take() {
            Some(head) => Poll::Head(head),
            None => Self::failure(q, dead),
        }
    }

    /// Up to `max` bytes of body, returning their window to the peer.
    pub(crate) fn poll_data(&self, max: usize) -> Poll {
        let mut st = self.session.state.borrow_mut();
        let st = &mut *st;
        let Some(q) = st.streams.get_mut(&self.id) else {
            return Poll::Dead;
        };
        if let Some(mut chunk) = q.data.pop_front() {
            if chunk.len() > max {
                let rest = chunk.split_off(max);
                q.data.push_front(rest);
            }
            st.core.release(self.id, chunk.len());
            return Poll::Data(chunk);
        }
        if q.malformed {
            return Poll::Reset(error_code::PROTOCOL_ERROR);
        }
        if q.ended {
            return Poll::End;
        }
        Self::failure(q, st.dead)
    }
}
