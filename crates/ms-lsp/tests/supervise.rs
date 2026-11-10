//! A worker that dies mid-session is replaced; unanswered requests fail with
//! an internal error and the open documents are replayed.

// Links the msrt_* runtime symbols that the standard-library crates reference.
use ms_lsp::json::{self, Json, obj};
use ms_rt as _;
use std::io::Read;
use std::process::Command;
use std::sync::mpsc::{Receiver, Sender, channel};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

struct Pipe(Receiver<Vec<u8>>, Vec<u8>);

impl Read for Pipe {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        if self.1.is_empty() {
            match self.0.recv() {
                Ok(chunk) => self.1 = chunk,
                Err(_) => return Ok(0),
            }
        }
        let n = buf.len().min(self.1.len());
        buf[..n].copy_from_slice(&self.1[..n]);
        self.1.drain(..n);
        Ok(n)
    }
}

#[derive(Clone)]
struct Sink(Arc<Mutex<Vec<u8>>>);

impl std::io::Write for Sink {
    fn write(&mut self, data: &[u8]) -> std::io::Result<usize> {
        self.0.lock().unwrap().extend_from_slice(data);
        Ok(data.len())
    }
    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

fn frame(value: &Json) -> Vec<u8> {
    let body = value.compact(ms_json::Escape::Plain);
    format!("Content-Length: {}\r\n\r\n{body}", body.len()).into_bytes()
}

fn messages(bytes: &[u8]) -> Vec<Json> {
    let mut out = Vec::new();
    let mut rest = bytes;
    while let Some(at) = rest.windows(4).position(|w| w == b"\r\n\r\n") {
        let header = String::from_utf8_lossy(&rest[..at]).into_owned();
        let Some(length) = header
            .strip_prefix("Content-Length: ")
            .and_then(|n| n.parse::<usize>().ok())
        else {
            break;
        };
        if rest.len() < at + 4 + length {
            break;
        }
        out.push(json::parse(&rest[at + 4..at + 4 + length]).unwrap());
        rest = &rest[at + 4 + length..];
    }
    out
}

fn wait_for(sink: &Sink, found: impl Fn(&[Json]) -> bool) {
    let deadline = Instant::now() + Duration::from_secs(20);
    while Instant::now() < deadline {
        if found(&messages(&sink.0.lock().unwrap())) {
            return;
        }
        std::thread::sleep(Duration::from_millis(20));
    }
    panic!("timed out; saw {:?}", messages(&sink.0.lock().unwrap()));
}

fn send(input: &Sender<Vec<u8>>, value: Json) {
    input.send(frame(&value)).unwrap();
}

#[test]
fn crashed_worker_is_replaced_and_state_replayed() {
    let (input, receiver) = channel();
    let sink = Sink(Arc::default());
    let output = sink.clone();
    let mut spawned = 0;
    let supervisor = std::thread::spawn(move || {
        ms_lsp::supervise(Pipe(receiver, Vec::new()), output, move || {
            spawned += 1;
            if spawned == 1 {
                // Reads one line and dies, like a checker fault.
                let mut command = Command::new("sh");
                command.args(["-c", "read -r line; exit 3"]);
                command
            } else {
                let mut command = Command::new(env!("CARGO_BIN_EXE_ms-lsp"));
                command.env("MS_LSP_WORKER", "1");
                command
            }
        })
    });
    let uri = "file:///tmp/ms-lsp-supervise/main.ms";
    send(
        &input,
        obj([
            ("jsonrpc", "2.0".into()),
            ("id", 1usize.into()),
            ("method", "initialize".into()),
            ("params", obj([])),
        ]),
    );
    wait_for(&sink, |m| {
        m.iter().any(|m| {
            m.get("id").and_then(|i| i.as_i64()) == Some(1)
                && m.get("error")
                    .and_then(|e| e.get("code"))
                    .and_then(|c| c.as_i64())
                    == Some(-32603)
        })
    });
    send(
        &input,
        obj([
            ("jsonrpc", "2.0".into()),
            ("method", "initialized".into()),
            ("params", obj([])),
        ]),
    );
    send(
        &input,
        obj([
            ("jsonrpc", "2.0".into()),
            ("method", "textDocument/didOpen".into()),
            (
                "params",
                obj([(
                    "textDocument",
                    obj([
                        ("uri", uri.into()),
                        ("version", 1usize.into()),
                        ("text", "fn answer() Int:\n    return 1\n".into()),
                    ]),
                )]),
            ),
        ]),
    );
    send(
        &input,
        obj([
            ("jsonrpc", "2.0".into()),
            ("id", "ms-lsp-replay".into()),
            ("method", "textDocument/hover".into()),
            (
                "params",
                obj([
                    ("textDocument", obj([("uri", uri.into())])),
                    (
                        "position",
                        obj([("line", 0usize.into()), ("character", 4usize.into())]),
                    ),
                ]),
            ),
        ]),
    );
    wait_for(&sink, |m| {
        m.iter().any(|m| {
            m.get("id").and_then(Json::as_str) == Some("ms-lsp-replay")
                && m.get("result").is_some_and(|r| !r.is_null())
        })
    });
    send(
        &input,
        obj([
            ("jsonrpc", "2.0".into()),
            ("id", 3usize.into()),
            ("method", "shutdown".into()),
        ]),
    );
    send(
        &input,
        obj([("jsonrpc", "2.0".into()), ("method", "exit".into())]),
    );
    drop(input);
    supervisor.join().unwrap().unwrap();
    let seen = messages(&sink.0.lock().unwrap());
    // Only the client's hover reaches it, never the replayed initialize answer.
    let replay_ids: Vec<_> = seen
        .iter()
        .filter(|message| message.get("id").and_then(Json::as_str) == Some("ms-lsp-replay"))
        .collect();
    assert_eq!(replay_ids.len(), 1);
    assert!(
        replay_ids[0]
            .get("result")
            .unwrap()
            .get("contents")
            .is_some()
    );
}

#[test]
fn client_request_can_use_replay_id_without_a_restart() {
    let (input, receiver) = channel();
    let sink = Sink(Arc::default());
    let output = sink.clone();
    let supervisor = std::thread::spawn(move || {
        ms_lsp::supervise(Pipe(receiver, Vec::new()), output, || {
            let mut command = Command::new(env!("CARGO_BIN_EXE_ms-lsp"));
            command.env("MS_LSP_WORKER", "1");
            command
        })
    });
    for (id, method) in [("ms-lsp-replay", "initialize"), ("barrier", "shutdown")] {
        send(
            &input,
            obj([
                ("jsonrpc", "2.0".into()),
                ("id", id.into()),
                ("method", method.into()),
                ("params", obj([])),
            ]),
        );
    }
    wait_for(&sink, |messages| {
        messages
            .iter()
            .any(|message| message.get("id").and_then(Json::as_str) == Some("barrier"))
    });
    send(
        &input,
        obj([("jsonrpc", "2.0".into()), ("method", "exit".into())]),
    );
    drop(input);
    supervisor.join().unwrap().unwrap();
    let seen = messages(&sink.0.lock().unwrap());
    let response = seen
        .iter()
        .find(|message| message.get("id").and_then(Json::as_str) == Some("ms-lsp-replay"))
        .expect("the client's initialize response must not be hidden as a replay");
    assert!(response.get("result").is_some());
    assert!(response.get("error").is_none());
}

#[test]
fn rejected_edits_do_not_change_documents_replayed_after_a_crash() {
    let (input, receiver) = channel();
    let sink = Sink(Arc::default());
    let output = sink.clone();
    let mut spawned = 0;
    let supervisor = std::thread::spawn(move || {
        ms_lsp::supervise(Pipe(receiver, Vec::new()), output, move || {
            spawned += 1;
            if spawned == 1 {
                // Hold the first worker until the supervisor has tracked every
                // edit. The next frame's header terminates the trigger's line.
                let mut command = Command::new("sh");
                command.args([
                    "-c",
                    "while IFS= read -r line; do case \"$line\" in *crash_after_edits*) exit 3;; esac; done",
                ]);
                command
            } else {
                let mut command = Command::new(env!("CARGO_BIN_EXE_ms-lsp"));
                command.env("MS_LSP_WORKER", "1");
                command
            }
        })
    });
    let uri = "file:///tmp/ms-lsp-supervise/recovery.ms";
    let notice = |method: &str, params| {
        obj([
            ("jsonrpc", "2.0".into()),
            ("method", method.into()),
            ("params", params),
        ])
    };
    let request = |id: usize, method: &str, params| {
        let mut message = notice(method, params);
        message.set("id", id.into());
        message
    };
    send(&input, request(1, "initialize", obj([])));
    send(&input, notice("initialized", obj([])));
    send(
        &input,
        notice(
            "textDocument/didOpen",
            obj([(
                "textDocument",
                obj([
                    ("uri", uri.into()),
                    ("version", 1usize.into()),
                    ("text", include_str!("supervise/recovery.ms").into()),
                ]),
            )]),
        ),
    );
    send(
        &input,
        notice(
            "textDocument/didChange",
            obj([
                (
                    "textDocument",
                    obj([("uri", uri.into()), ("version", 2usize.into())]),
                ),
                (
                    "contentChanges",
                    Json::Arr(vec![obj([
                        ("range", "invalid".into()),
                        ("text", "corrupted".into()),
                    ])]),
                ),
            ]),
        ),
    );
    send(&input, notice("test/crash_after_edits", obj([])));
    send(
        &input,
        request(
            2,
            "textDocument/documentSymbol",
            obj([("textDocument", obj([("uri", uri.into())]))]),
        ),
    );
    wait_for(&sink, |messages| {
        messages.iter().any(|message| {
            message.get("method").and_then(Json::as_str) == Some("textDocument/publishDiagnostics")
                && message.get("params").is_some_and(|params| {
                    params.get("uri").and_then(Json::as_str) == Some(uri)
                        && params.get("version").and_then(Json::as_i64) == Some(1)
                })
        })
    });
    send(
        &input,
        request(
            3,
            "textDocument/documentSymbol",
            obj([("textDocument", obj([("uri", uri.into())]))]),
        ),
    );
    wait_for(&sink, |messages| {
        messages.iter().any(|message| {
            message.get("id").and_then(Json::as_i64) == Some(3)
                && message
                    .get("result")
                    .and_then(Json::as_array)
                    .is_some_and(|symbols| {
                        symbols.iter().any(|symbol| {
                            symbol.get("name").and_then(Json::as_str) == Some("answer")
                        })
                    })
        })
    });
    send(&input, request(4, "shutdown", obj([])));
    send(&input, notice("exit", obj([])));
    drop(input);
    supervisor.join().unwrap().unwrap();
}
