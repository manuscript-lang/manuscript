//! Crash isolation. The workspace builds with `panic = "abort"`, so a checker
//! fault cannot be caught in-process; instead the language server runs as a
//! worker process behind this supervisor. When the worker dies, requests it
//! had not answered fail with an internal error, a new worker starts, and the
//! open documents are replayed so the session continues.

use crate::analysis::Document;
use crate::json::{Json, obj};
use crate::text;
use crate::transport::{FrameError, read_frame};
use std::collections::{BTreeMap, VecDeque};
use std::io::{BufReader, Read, Write};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::mpsc::{Sender, channel};
use std::time::{Duration, Instant};

const REPLAY_ID: &str = "ms-lsp-replay";
const RESTART_LIMIT: usize = 5;
const RESTART_WINDOW: Duration = Duration::from_secs(30);

enum Event {
    Client(Result<Vec<u8>, FrameError>),
    Worker(usize, Option<Vec<u8>>),
}

struct Worker {
    child: Child,
    stdin: Option<ChildStdin>,
}

struct Supervisor<'a, W: Write> {
    output: W,
    spawn: Box<dyn FnMut() -> Command + 'a>,
    events: Sender<Event>,
    worker: Option<Worker>,
    generation: usize,
    inflight: BTreeMap<String, Json>,
    initialize: Option<Json>,
    initialized: bool,
    docs: BTreeMap<String, Document>,
    restarts: VecDeque<Instant>,
    exiting: bool,
}

/// Serves a session through restartable worker processes made by `spawn`.
pub fn supervise(
    input: impl Read + Send + 'static,
    output: impl Write,
    spawn: impl FnMut() -> Command,
) -> Result<(), String> {
    let (events, receiver) = channel();
    let client = events.clone();
    std::thread::spawn(move || {
        let mut reader = BufReader::with_capacity(8192, input);
        loop {
            let frame = read_frame(&mut reader);
            let end = frame.is_err();
            if client.send(Event::Client(frame)).is_err() || end {
                return;
            }
        }
    });
    let mut s = Supervisor {
        output,
        spawn: Box::new(spawn),
        events,
        worker: None,
        generation: 0,
        inflight: BTreeMap::new(),
        initialize: None,
        initialized: false,
        docs: BTreeMap::new(),
        restarts: VecDeque::new(),
        exiting: false,
    };
    s.start()?;
    while let Ok(event) = receiver.recv() {
        match event {
            Event::Client(Ok(frame)) => s.client(&frame)?,
            Event::Client(Err(FrameError::Eof)) => return s.finish(),
            Event::Client(Err(FrameError::Failed(message))) => {
                let _ = s.finish();
                return Err(message);
            }
            Event::Worker(generation, frame) if generation == s.generation => match frame {
                Some(frame) => s.reply(&frame)?,
                None if s.exiting => return s.finish(),
                None => s.crashed()?,
            },
            Event::Worker(..) => {}
        }
    }
    s.finish()
}

impl<W: Write> Supervisor<'_, W> {
    fn start(&mut self) -> Result<(), String> {
        let mut command = (self.spawn)();
        command
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit());
        let mut child = command.spawn().map_err(|e| format!("start worker: {e}"))?;
        let stdin = child.stdin.take();
        let stdout = child.stdout.take().ok_or("worker has no stdout")?;
        self.generation += 1;
        let (generation, events) = (self.generation, self.events.clone());
        std::thread::spawn(move || {
            let mut reader = BufReader::with_capacity(8192, stdout);
            while let Ok(frame) = read_frame(&mut reader) {
                if events.send(Event::Worker(generation, Some(frame))).is_err() {
                    return;
                }
            }
            let _ = events.send(Event::Worker(generation, None));
        });
        self.worker = Some(Worker { child, stdin });
        Ok(())
    }

    fn send_worker(&mut self, body: &[u8]) {
        if let Some(Worker {
            stdin: Some(stdin), ..
        }) = &mut self.worker
        {
            let framed = [
                format!("Content-Length: {}\r\n\r\n", body.len()).as_bytes(),
                body,
            ]
            .concat();
            // A dead worker is noticed through its closed output.
            let _ = stdin.write_all(&framed).and_then(|()| stdin.flush());
        }
    }

    fn send_client(&mut self, body: &str) -> Result<(), String> {
        write!(
            self.output,
            "Content-Length: {}\r\n\r\n{}",
            body.len(),
            body
        )
        .and_then(|()| self.output.flush())
        .map_err(|e| e.to_string())
    }

    /// Records what a restart must replay, then forwards the frame.
    fn client(&mut self, frame: &[u8]) -> Result<(), String> {
        if let Ok(message) = crate::json::parse(frame) {
            let method = message.get("method").and_then(|m| m.as_str()).unwrap_or("");
            let params = message.get("params");
            if let Some(id) = message.get("id").filter(|_| !method.is_empty()) {
                self.inflight.insert(id.encode(), id.clone());
            }
            match method {
                "initialize" => self.initialize = Some(message.clone()),
                "initialized" => self.initialized = true,
                "exit" => self.exiting = true,
                "textDocument/didOpen" | "textDocument/didChange" | "textDocument/didClose" => {
                    self.track(method, params);
                }
                _ => {}
            }
        }
        self.send_worker(frame);
        Ok(())
    }

    fn track(&mut self, method: &str, params: Option<&Json>) {
        let Some(document) = params.and_then(|p| p.get("textDocument")) else {
            return;
        };
        let Some(uri) = document.get("uri").and_then(|u| u.as_str()) else {
            return;
        };
        let version = document
            .get("version")
            .and_then(|v| v.as_i64())
            .unwrap_or(0);
        match method {
            "textDocument/didClose" => {
                self.docs.remove(uri);
            }
            "textDocument/didOpen" => {
                let text = document.get("text").and_then(|t| t.as_str()).unwrap_or("");
                self.docs.insert(
                    uri.to_string(),
                    Document {
                        uri: uri.to_string(),
                        text: text.to_string(),
                        version,
                    },
                );
            }
            _ => {
                let Some(current) = self.docs.get_mut(uri) else {
                    return;
                };
                if version <= current.version {
                    return;
                }
                let changes = params
                    .and_then(|p| p.get("contentChanges"))
                    .and_then(|c| c.as_array())
                    .unwrap_or(&[]);
                let mut next = current.text.clone();
                for change in changes {
                    let replacement = change.get("text").and_then(|t| t.as_str()).unwrap_or("");
                    let Some(range) = change.get("range").and_then(text::Range::from_json) else {
                        next = replacement.to_string();
                        continue;
                    };
                    let (Ok(start), Ok(end)) = (
                        text::edit_offset(&next, range.start),
                        text::edit_offset(&next, range.end),
                    ) else {
                        return;
                    };
                    if end < start {
                        return;
                    }
                    next = format!("{}{}{}", &next[..start], replacement, &next[end..]);
                }
                current.text = next;
                current.version = version;
            }
        }
    }

    /// Passes a worker message to the client, dropping replay answers.
    fn reply(&mut self, frame: &[u8]) -> Result<(), String> {
        if let Ok(message) = crate::json::parse(frame) {
            let answered = message
                .get("id")
                .filter(|_| message.get("method").is_none())
                .cloned();
            if let Some(id) = answered {
                if id.as_str() == Some(REPLAY_ID) {
                    return Ok(());
                }
                self.inflight.remove(&id.encode());
            }
        }
        self.send_client(&String::from_utf8_lossy(frame))
    }

    /// Fails the unanswered requests, starts a new worker and replays state.
    fn crashed(&mut self) -> Result<(), String> {
        if let Some(mut worker) = self.worker.take() {
            let _ = worker.child.wait();
        }
        let now = Instant::now();
        self.restarts.push_back(now);
        while self
            .restarts
            .front()
            .is_some_and(|t| now.duration_since(*t) > RESTART_WINDOW)
        {
            self.restarts.pop_front();
        }
        for (_, id) in std::mem::take(&mut self.inflight) {
            let failure = obj([
                ("jsonrpc", "2.0".into()),
                ("id", id),
                (
                    "error",
                    obj([
                        ("code", (-32603i64).into()),
                        (
                            "message",
                            "language server crashed and was restarted".into(),
                        ),
                    ]),
                ),
            ]);
            self.send_client(&failure.encode())?;
        }
        if self.restarts.len() > RESTART_LIMIT {
            return Err("language server keeps crashing".to_string());
        }
        self.start()?;
        if let Some(mut initialize) = self.initialize.clone() {
            initialize.set("id", REPLAY_ID.into());
            self.send_worker(initialize.encode().as_bytes());
            if self.initialized {
                let notice = obj([
                    ("jsonrpc", "2.0".into()),
                    ("method", "initialized".into()),
                    ("params", obj([])),
                ]);
                self.send_worker(notice.encode().as_bytes());
            }
            let docs: Vec<Document> = self.docs.values().cloned().collect();
            for d in docs {
                let open = obj([
                    ("jsonrpc", "2.0".into()),
                    ("method", "textDocument/didOpen".into()),
                    (
                        "params",
                        obj([(
                            "textDocument",
                            obj([
                                ("uri", d.uri.into()),
                                ("languageId", "manuscript".into()),
                                ("version", d.version.into()),
                                ("text", d.text.into()),
                            ]),
                        )]),
                    ),
                ]);
                self.send_worker(open.encode().as_bytes());
            }
        }
        Ok(())
    }

    /// Closes the worker's input and waits for it to end.
    fn finish(&mut self) -> Result<(), String> {
        if let Some(mut worker) = self.worker.take() {
            drop(worker.stdin.take());
            let _ = worker.child.wait();
        }
        Ok(())
    }
}
