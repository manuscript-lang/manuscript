//! Crash isolation. The workspace builds with `panic = "abort"`, so a checker
//! fault cannot be caught in-process; instead the language server runs as a
//! worker process behind this supervisor. When the worker dies, requests it
//! had not answered fail with an internal error, a new worker starts, and the
//! open documents are replayed so the session continues.

use crate::analysis::Document;
use crate::json::{Json, obj};
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
    /// The next initialize answer belongs to this worker's private state replay.
    replay_pending: bool,
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
        replay_pending: false,
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
                self.inflight
                    .insert(id.compact(ms_json::Escape::Plain), id.clone());
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
        let Ok(params) = crate::server::Params::decode(params.unwrap_or(&Json::Null)) else {
            return;
        };
        let uri = &params.document.uri;
        match method {
            "textDocument/didClose" => {
                self.docs.remove(uri);
            }
            "textDocument/didOpen" => {
                self.docs.insert(uri.clone(), params.document);
            }
            _ => {
                let Some(current) = self.docs.get(uri) else {
                    return;
                };
                let Some(next) = params.changed_document(current) else {
                    return;
                };
                self.docs.insert(uri.clone(), next);
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
                if self.replay_pending && id.as_str() == Some(REPLAY_ID) {
                    self.replay_pending = false;
                    return Ok(());
                }
                self.inflight.remove(&id.compact(ms_json::Escape::Plain));
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
            self.send_client(&failure.compact(ms_json::Escape::Plain))?;
        }
        if self.restarts.len() > RESTART_LIMIT {
            return Err("language server keeps crashing".to_string());
        }
        self.start()?;
        if let Some(mut initialize) = self.initialize.clone() {
            initialize.set("id", REPLAY_ID.into());
            self.replay_pending = true;
            self.send_worker(initialize.compact(ms_json::Escape::Plain).as_bytes());
            if self.initialized {
                let notice = obj([
                    ("jsonrpc", "2.0".into()),
                    ("method", "initialized".into()),
                    ("params", obj([])),
                ]);
                self.send_worker(notice.compact(ms_json::Escape::Plain).as_bytes());
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
                self.send_worker(open.compact(ms_json::Escape::Plain).as_bytes());
            }
        }
        Ok(())
    }

    /// Closes the worker's input and waits for it to end. After the client's `exit` the worker's
    /// failure status is the session's: `exit` without `shutdown` must not end with success.
    fn finish(&mut self) -> Result<(), String> {
        let Some(mut worker) = self.worker.take() else {
            return Ok(());
        };
        drop(worker.stdin.take());
        match worker.child.wait() {
            Ok(status) if self.exiting && !status.success() => {
                Err(format!("worker exited with {status}"))
            }
            _ => Ok(()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn snapshot() -> Supervisor<'static, Vec<u8>> {
        let (events, _) = channel();
        let mut supervisor = Supervisor {
            output: Vec::new(),
            spawn: Box::new(|| Command::new("unused")),
            events,
            worker: None,
            generation: 0,
            inflight: BTreeMap::new(),
            initialize: None,
            initialized: false,
            replay_pending: false,
            docs: BTreeMap::new(),
            restarts: VecDeque::new(),
            exiting: false,
        };
        supervisor.track(
            "textDocument/didOpen",
            Some(&obj([(
                "textDocument",
                obj([
                    ("uri", "file:///snapshot.ms".into()),
                    ("text", "a😀b\r\nlast\n".into()),
                    ("version", 1i64.into()),
                ]),
            )])),
        );
        supervisor
    }

    fn change(supervisor: &mut Supervisor<'_, Vec<u8>>, version: i64, changes: &str) {
        let params = obj([
            (
                "textDocument",
                obj([
                    ("uri", "file:///snapshot.ms".into()),
                    ("version", version.into()),
                ]),
            ),
            (
                "contentChanges",
                crate::json::parse(changes.as_bytes()).unwrap(),
            ),
        ]);
        supervisor.track("textDocument/didChange", Some(&params));
    }

    #[test]
    fn recovery_snapshots_reject_malformed_and_partial_edit_transactions() {
        for changes in [
            r#"[{"range":"invalid","text":"corrupted"}]"#,
            r#"[{"text":42}]"#,
            r#"[{"text":"discarded"},{"range":false,"text":"corrupted"}]"#,
            r#"[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":1}},"text":"z"},{"range":{"start":{"line":0,"character":2},"end":{"line":0,"character":3}},"text":"split surrogate"}]"#,
            r#"[{"range":{"start":{"line":0,"character":3},"end":{"line":0,"character":1}},"text":"reversed"}]"#,
            r#"[]"#,
            r#"{}"#,
        ] {
            let mut supervisor = snapshot();
            let original = supervisor.docs.clone();
            change(&mut supervisor, 2, changes);
            assert_eq!(supervisor.docs, original, "{changes}");
            // A rejected notification must not consume the next accepted version.
            change(&mut supervisor, 2, r#"[{"text":"accepted"}]"#);
            assert_eq!(supervisor.docs["file:///snapshot.ms"].text, "accepted");
            assert_eq!(supervisor.docs["file:///snapshot.ms"].version, 2);
        }
    }

    #[test]
    fn recovery_snapshots_apply_the_workers_utf16_and_replacement_rules() {
        let mut supervisor = snapshot();
        change(
            &mut supervisor,
            2,
            r#"[{"range":{"start":{"line":0,"character":1},"end":{"line":0,"character":3}},"text":"é"},{"range":{"start":{"line":0,"character":2},"end":{"line":0,"character":3}},"text":"β"}]"#,
        );
        assert_eq!(supervisor.docs["file:///snapshot.ms"].text, "aéβ\r\nlast\n");
        change(&mut supervisor, 2, r#"[{"text":"stale"}]"#);
        assert_eq!(supervisor.docs["file:///snapshot.ms"].text, "aéβ\r\nlast\n");
        change(
            &mut supervisor,
            3,
            r#"[{"range":null,"text":"new"},{"range":{"start":{"line":0,"character":999},"end":{"line":0,"character":1000}},"text":"!"}]"#,
        );
        assert_eq!(supervisor.docs["file:///snapshot.ms"].text, "new!");
        // Keep the worker's defaults for missing coordinates and negative clamping.
        change(
            &mut supervisor,
            4,
            r#"[{"range":{"start":{},"end":{"line":0,"character":1}},"text":"d"}]"#,
        );
        assert_eq!(supervisor.docs["file:///snapshot.ms"].text, "dew!");
        change(
            &mut supervisor,
            5,
            r#"[{"range":{"start":{"line":0,"character":-1},"end":{"line":0,"character":-1}},"text":"?"}]"#,
        );
        assert_eq!(supervisor.docs["file:///snapshot.ms"].text, "dew!?");
        assert_eq!(supervisor.docs["file:///snapshot.ms"].version, 5);
    }
}
