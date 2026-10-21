//! Scripted language-server sessions run against the Go oracle (`ms lsp`) and
//! this crate's server, with the decoded messages compared.

#![allow(dead_code)]

// Links the msrt_* runtime symbols.
use ms_lsp::json::{self, Json, obj};
use ms_rt as _;
use std::io::{Cursor, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// The built Go binary (`make build`), if present.
pub fn oracle() -> Option<PathBuf> {
    if let Ok(path) = std::env::var("MS_ORACLE") {
        return Some(PathBuf::from(path));
    }
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let binary = root.join("ms");
    binary.is_file().then_some(binary)
}

/// A copy of the fixture tree in a fresh temporary directory.
pub struct Workspace {
    pub root: PathBuf,
}

impl Workspace {
    pub fn new(name: &str) -> Workspace {
        let root = std::env::temp_dir().join(format!("ms-lsp-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        copy(
            &Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures"),
            &root,
        );
        Workspace {
            root: root.canonicalize().expect("workspace"),
        }
    }

    pub fn path(&self, relative: &str) -> String {
        self.root.join(relative).to_string_lossy().into_owned()
    }

    pub fn uri(&self, relative: &str) -> String {
        ms_lsp::uri::file_uri(&self.path(relative))
    }

    pub fn read(&self, relative: &str) -> String {
        std::fs::read_to_string(self.path(relative)).expect("fixture")
    }
}

impl Drop for Workspace {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.root);
    }
}

fn copy(from: &Path, to: &Path) {
    std::fs::create_dir_all(to).expect("create");
    for entry in std::fs::read_dir(from).expect("read").flatten() {
        let target = to.join(entry.file_name());
        if entry.path().is_dir() {
            copy(&entry.path(), &target);
        } else {
            std::fs::copy(entry.path(), target).expect("copy");
        }
    }
}

/// A client script: notifications and requests in order.
#[derive(Default)]
pub struct Script {
    messages: Vec<Json>,
    next: i64,
    labels: std::collections::HashMap<i64, String>,
}

impl Script {
    pub fn new() -> Script {
        Script::default()
    }

    /// Starts a session whose client does (or does not) support snippets.
    pub fn initialize(root: &str, snippets: bool) -> Script {
        let mut s = Script::new();
        s.request(
            "initialize",
            obj([
                ("rootUri", ms_lsp::uri::file_uri(root).into()),
                (
                    "capabilities",
                    obj([(
                        "textDocument",
                        obj([(
                            "completion",
                            obj([("completionItem", obj([("snippetSupport", snippets.into())]))]),
                        )]),
                    )]),
                ),
            ]),
        );
        s.notify("initialized", obj([]));
        s
    }

    pub fn notify(&mut self, method: &str, params: Json) {
        self.messages.push(obj([
            ("jsonrpc", "2.0".into()),
            ("method", method.into()),
            ("params", params),
        ]));
    }

    pub fn request(&mut self, method: &str, params: Json) -> i64 {
        self.next += 1;
        self.labels.insert(
            self.next,
            format!("{method} {}", params.compact(ms_json::Escape::Plain)),
        );
        self.messages.push(obj([
            ("jsonrpc", "2.0".into()),
            ("id", self.next.into()),
            ("method", method.into()),
            ("params", params),
        ]));
        self.next
    }

    /// A raw frame body, for malformed input.
    pub fn raw(&mut self, body: &str) {
        self.messages.push(Json::Str(format!("\u{0}raw{body}")));
    }

    pub fn open(&mut self, uri: &str, text: &str, version: i64) {
        self.notify(
            "textDocument/didOpen",
            obj([(
                "textDocument",
                obj([
                    ("uri", uri.into()),
                    ("languageId", "manuscript".into()),
                    ("version", version.into()),
                    ("text", text.into()),
                ]),
            )]),
        );
    }

    pub fn at(&mut self, method: &str, uri: &str, line: usize, character: usize) -> i64 {
        self.request(
            method,
            obj([
                ("textDocument", obj([("uri", uri.into())])),
                (
                    "position",
                    obj([("line", line.into()), ("character", character.into())]),
                ),
            ]),
        )
    }

    fn frames(&self) -> Vec<u8> {
        let mut bytes = Vec::new();
        let mut finish = Script {
            next: self.next,
            ..Script::default()
        };
        finish.request("shutdown", Json::Null);
        finish.notify("exit", Json::Null);
        for message in self.messages.iter().chain(finish.messages.iter()) {
            let body = match message {
                Json::Str(s) if s.starts_with("\u{0}raw") => s["\u{0}raw".len()..].to_string(),
                other => other.compact(ms_json::Escape::Plain),
            };
            bytes.extend_from_slice(
                format!("Content-Length: {}\r\n\r\n{body}", body.len()).as_bytes(),
            );
        }
        bytes
    }

    pub fn go(&self, binary: &Path) -> Vec<Json> {
        let mut child = Command::new(binary)
            .arg("lsp")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null())
            .spawn()
            .expect("spawn oracle");
        let mut stdin = child.stdin.take().expect("stdin");
        let input = self.frames();
        let writer = std::thread::spawn(move || {
            let _ = stdin.write_all(&input);
        });
        let output = child.wait_with_output().expect("oracle output");
        let _ = writer.join();
        decode(&output.stdout)
    }

    pub fn rust(&self) -> Vec<Json> {
        let mut out = Vec::new();
        let _ = ms_lsp::serve(Cursor::new(self.frames()), &mut out);
        decode(&out)
    }
}

/// Splits framed output into messages.
pub fn decode(mut bytes: &[u8]) -> Vec<Json> {
    let mut out = Vec::new();
    while !bytes.is_empty() {
        let text = String::from_utf8_lossy(&bytes[..bytes.len().min(64)]).into_owned();
        let Some(header_end) = find(bytes, b"\r\n\r\n") else {
            panic!("bad frame header: {text:?}");
        };
        let header = String::from_utf8_lossy(&bytes[..header_end]).into_owned();
        let length: usize = header
            .strip_prefix("Content-Length: ")
            .and_then(|n| n.trim().parse().ok())
            .unwrap_or_else(|| panic!("bad header {header:?}"));
        let body = &bytes[header_end + 4..header_end + 4 + length];
        out.push(json::parse(body).expect("frame is JSON"));
        bytes = &bytes[header_end + 4 + length..];
    }
    out
}

fn find(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    haystack.windows(needle.len()).position(|w| w == needle)
}

/// Canonical text of a value: object keys sorted.
pub fn canonical(value: &Json) -> String {
    match value {
        Json::Obj(fields) => {
            let mut fields: Vec<_> = fields.iter().collect();
            fields.sort_by(|a, b| a.0.cmp(&b.0));
            let inner: Vec<String> = fields
                .into_iter()
                .map(|(k, v)| {
                    format!(
                        "{}:{}",
                        Json::Str(k.clone()).compact(ms_json::Escape::Plain),
                        canonical(v)
                    )
                })
                .collect();
            format!("{{{}}}", inner.join(","))
        }
        Json::Arr(items) => {
            let inner: Vec<String> = items.iter().map(canonical).collect();
            format!("[{}]", inner.join(","))
        }
        other => other.compact(ms_json::Escape::Plain),
    }
}

/// Runs the script on both servers and compares every message; panics with the
/// first difference. Returns the Rust messages.
pub fn compare(name: &str, script: &Script) -> Vec<Json> {
    let Some(binary) = oracle() else {
        assert!(
            std::env::var("MS_ORACLE_REQUIRED").is_err(),
            "{name}: Go oracle missing; run `make build`"
        );
        eprintln!("{name}: skipped (no Go oracle; run `make build`)");
        return script.rust();
    };
    let expected: Vec<Json> = script.go(&binary);
    let actual: Vec<Json> = script.rust();
    if let Ok(dir) = std::env::var("MS_LSP_DUMP") {
        let write = |side: &str, messages: &[Json]| {
            let text: Vec<String> = messages.iter().map(canonical).collect();
            let _ = std::fs::write(format!("{dir}/{name}.{side}.jsonl"), text.join("\n"));
        };
        write("go", &expected);
        write("rust", &actual);
    }
    let mut differences = Vec::new();
    for index in 0..expected.len().max(actual.len()) {
        let go = expected.get(index).map(canonical).unwrap_or_default();
        let rust = actual.get(index).map(canonical).unwrap_or_default();
        if go != rust {
            let label = expected
                .get(index)
                .and_then(|m| m.get("id"))
                .and_then(|id| id.as_i64())
                .and_then(|id| script.labels.get(&id))
                .cloned()
                .unwrap_or_default();
            differences.push(format!(
                "message {index} <- {label}\n  go:   {go}\n  rust: {rust}"
            ));
        }
    }
    assert!(
        differences.is_empty(),
        "{name}: {} of {} messages differ\n{}",
        differences.len(),
        expected.len(),
        differences
            .iter()
            .take(6)
            .cloned()
            .collect::<Vec<_>>()
            .join("\n")
    );
    actual
}
