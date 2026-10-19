//! A worker that dies mid-session is replaced; unanswered requests fail with
//! an internal error and the open documents are replayed.

use ms_lsp::json::{self, Json, obj};
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
    let body = value.encode();
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
            ("id", 2usize.into()),
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
            m.get("id").and_then(|i| i.as_i64()) == Some(2)
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
    // The replayed initialize answer never reaches the client.
    assert!(
        !seen
            .iter()
            .any(|m| m.get("id").and_then(|i| i.as_str()) == Some("ms-lsp-replay"))
    );
}
