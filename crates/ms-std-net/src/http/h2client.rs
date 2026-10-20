//! HTTP/2 client transport: one [`Session`] per origin multiplexes request
//! streams over a single connection, driven by the sans-io [`crate::h2`] core.
//!
//! The ms thread is single threaded, so nothing pumps in the background: every
//! waiter (a request waiting for its head, a body waiting for data, an upload
//! waiting for window) calls [`Session::pump`], which writes queued output,
//! reads once, feeds the core and files the resulting events into per-stream
//! queues. A waiter then looks at its own queue; data that arrived for other
//! streams stays queued until their readers ask.

use crate::conn::Connection;
use crate::error::IoErr;
use crate::h2::{self, Event, Header, Settings, StreamId, error_code};
use crate::wait::Deadline;
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
    scratch: RefCell<Vec<u8>>,
    used: Cell<Instant>,
}

fn map_io(e: IoErr) -> PumpErr {
    match e {
        IoErr::Closed => PumpErr::Closed,
        IoErr::Failed(m) if m == "operation timed out" => PumpErr::Timeout,
        IoErr::Failed(m) => PumpErr::Failed(m),
        _ => PumpErr::Failed("i/o error".into()),
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
            scratch: RefCell::new(vec![0; READ_BUF]),
            used: Cell::new(Instant::now()),
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

    /// Writes everything the core queued.
    pub(crate) fn flush(&self, deadline: Deadline) -> Result<(), PumpErr> {
        let out = self.state.borrow_mut().core.take_output();
        if out.is_empty() {
            return Ok(());
        }
        self.conn.write_until(&out, deadline).map_err(|e| {
            let e = map_io(e);
            if matches!(e, PumpErr::Failed(_)) {
                self.mark_dead();
            }
            e
        })
    }

    /// Writes pending output, reads once and files the events. The caller
    /// inspects its own queue afterwards.
    pub(crate) fn pump(&self, deadline: Deadline) -> Result<(), PumpErr> {
        self.flush(deadline)?;
        if self.state.borrow().dead {
            return Ok(());
        }
        let mut buf = self.scratch.borrow_mut();
        let n = self
            .conn
            .read_into(&mut buf, deadline)
            .map_err(map_io)
            .inspect_err(|e| {
                if matches!(e, PumpErr::Failed(_)) {
                    self.mark_dead();
                }
            })?;
        if n == 0 {
            self.mark_dead();
            return Ok(());
        }
        let fed = self.state.borrow_mut().core.feed(&buf[..n]);
        drop(buf);
        let Ok(events) = fed else {
            // The core queued a GOAWAY; push it out, then give up.
            let _ = self.flush(Deadline::after(CANCEL_FLUSH));
            self.mark_dead();
            self.conn.close();
            return Ok(());
        };
        self.dispatch(events);
        self.flush(deadline)
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
                        continue;
                    }
                    q.head_seen = true;
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
        let mut st = self.state.borrow_mut();
        let opened = st.core.open_stream(headers, end_stream);
        let id = match opened {
            Ok(id) => id,
            Err(e) if e.code == error_code::REFUSED_STREAM && !st.streams.is_empty() => {
                return Err(OpenErr::Full);
            }
            Err(e) => return Err(OpenErr::Invalid(e.reason)),
        };
        st.streams.insert(id, Queue::default());
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
            .is_some_and(|q| q.ended && q.data.is_empty())
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
        if q.ended {
            return Poll::End;
        }
        Self::failure(q, st.dead)
    }
}
