//! `ms lsp` serves the language server through the supervised worker.

use std::io::{BufRead, Read, Write};
use std::process::{Command, Stdio};

fn frame(body: &str) -> Vec<u8> {
    format!("Content-Length: {}\r\n\r\n{body}", body.len()).into_bytes()
}

#[test]
fn lsp_initializes_and_exits_cleanly() {
    let mut child = Command::new(env!("CARGO_BIN_EXE_ms"))
        .arg("lsp")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .expect("spawn ms lsp");
    let mut stdin = child.stdin.take().expect("stdin");
    let mut stdout = std::io::BufReader::new(child.stdout.take().expect("stdout"));

    let initialize =
        r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}"#;
    stdin
        .write_all(&frame(initialize))
        .expect("write initialize");
    stdin.flush().expect("flush");
    let mut header = String::new();
    stdout.read_line(&mut header).expect("header");
    let length: usize = header
        .trim()
        .strip_prefix("Content-Length: ")
        .and_then(|n| n.parse().ok())
        .expect("content length");
    stdout.read_line(&mut header).expect("blank line");
    let mut body = vec![0; length];
    stdout.read_exact(&mut body).expect("body");
    assert!(String::from_utf8_lossy(&body).contains("\"capabilities\""));

    stdin
        .write_all(&frame(r#"{"jsonrpc":"2.0","id":2,"method":"shutdown"}"#))
        .expect("write shutdown");
    stdin
        .write_all(&frame(r#"{"jsonrpc":"2.0","method":"exit"}"#))
        .expect("write exit");
    stdin.flush().expect("flush");
    drop(stdin);
    assert!(child.wait().expect("wait").success());
}
