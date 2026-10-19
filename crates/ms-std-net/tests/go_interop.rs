//! Interop with a real Go `net/http` peer, in both directions, over HTTP/1.1,
//! TLS with HTTP/1.1 and TLS with HTTP/2. Skipped when `go` is not installed.
extern crate ms_rt;

use ms_std_net::error::HttpErr;
use ms_std_net::http::client::{Body, Client, ClientOptions, Request};
use ms_std_net::http::exchange::Exchange;
use ms_std_net::http::headers::Headers;
use ms_std_net::http::server::{
    Dispatch, Limits, Options, Outcome, Reply, Request as Incoming, Server,
};
use ms_std_net::http::url;
use ms_std_net::net::Network;
use ms_std_net::tls::{self, TlsOptions};
use ms_std_net::wait::{self, Deadline};
use ms_std_net::ws::dial::{Dial, connect};
use std::io::{BufRead, BufReader, Read};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::rc::Rc;
use std::sync::Mutex;
use std::time::Duration;

/// The task scheduler is process-global; tests take turns.
static SERIAL: Mutex<()> = Mutex::new(());

fn manifest() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn cert() -> String {
    std::fs::read_to_string(manifest().join("testdata/stdlib.test.crt.pem")).unwrap()
}

fn key() -> String {
    std::fs::read_to_string(manifest().join("testdata/stdlib.test.key.pem")).unwrap()
}

/// Builds the Go peer once; `None` when Go is unavailable.
fn peer() -> Option<PathBuf> {
    static BUILT: std::sync::OnceLock<Option<PathBuf>> = std::sync::OnceLock::new();
    BUILT
        .get_or_init(|| {
            let out = PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join("ms-net-peer");
            let src = manifest().join("testdata/interop/main.go");
            let status = Command::new("go")
                .args(["build", "-o"])
                .arg(&out)
                .arg(&src)
                .status()
                .ok()?;
            status.success().then_some(out)
        })
        .clone()
}

fn pattern(n: usize) -> Vec<u8> {
    (0..n).map(|i| b'a' + (i % 26) as u8).collect()
}

// ------------------------------------------------------------- Rust client, Go server

struct GoServer {
    child: std::process::Child,
    address: String,
}

impl Drop for GoServer {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

fn go_server(peer: &Path, mode: &str) -> GoServer {
    let dir = manifest().join("testdata");
    let mut child = Command::new(peer)
        .args(["server", mode, "127.0.0.1:0"])
        .arg(dir.join("stdlib.test.crt.pem"))
        .arg(dir.join("stdlib.test.key.pem"))
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut line = String::new();
    BufReader::new(child.stdout.take().unwrap())
        .read_line(&mut line)
        .unwrap();
    let address = line.trim().strip_prefix("ready ").unwrap().to_string();
    GoServer { child, address }
}

fn client(net: &Rc<Network>, alpn: &[&str]) -> Rc<Client> {
    let tls = TlsOptions {
        roots_pem: cert(),
        alpn: alpn.iter().map(|s| s.to_string()).collect(),
        ..TlsOptions::default()
    };
    Client::new(
        net,
        ClientOptions {
            tls,
            cookies: true,
            decompress: true,
            ..ClientOptions::default()
        },
    )
    .unwrap()
}

fn request(method: &str, url_text: &str, body: Vec<u8>) -> Request {
    Request {
        method: method.into(),
        url: url::parse(url_text).unwrap(),
        headers: Vec::new(),
        body: Body::Bytes(Rc::new(body)),
        max_response: u64::MAX,
        deadline: Deadline::after(Duration::from_secs(10)),
    }
}

fn run_client_against_go(mode: &str, scheme: &str, alpn: &[&str], protocol: &str) {
    let Some(peer) = peer() else { return };
    let _turn = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
    let server = go_server(&peer, mode);
    let base = format!("{scheme}://{}", server.address.replace("[::]", "127.0.0.1"));
    let net = Network::new_root();
    let c = client(&net, alpn);
    let send = |method: &str, path: &str, body: Vec<u8>| {
        // Dial by IP; the certificate carries 127.0.0.1.
        let body = c
            .send(request(method, &format!("{base}{path}"), body))
            .unwrap();
        let status = body.status;
        let proto = body.protocol.clone();
        let headers = body.headers.clone();
        (status, proto, headers, body.read_all().unwrap())
    };

    let (status, proto, _, data) = send("GET", "/proto", Vec::new());
    assert_eq!((status, proto.as_str()), (200, protocol));
    assert_eq!(data, protocol.as_bytes());

    let upload = pattern(300_000);
    let (status, _, headers, data) = send("POST", "/echo", upload.clone());
    assert_eq!(status, 200);
    assert_eq!(data, upload);
    assert_eq!(headers.borrow().first("X-Seen-Method"), Some(&b"POST"[..]));
    let agent = if protocol == "HTTP/2.0" {
        "Go-http-client/2.0"
    } else {
        "Go-http-client/1.1"
    };
    assert_eq!(
        headers.borrow().first("X-Seen-Agent"),
        Some(agent.as_bytes())
    );

    let (_, _, _, data) = send("GET", "/big", Vec::new());
    assert_eq!(data, pattern(1 << 20));

    // The client follows the redirect to /proto.
    let (status, _, _, data) = send("GET", "/redirect", Vec::new());
    assert_eq!((status, data), (200, protocol.as_bytes().to_vec()));

    let (status, _, _, data) = send("GET", "/missing", Vec::new());
    assert_eq!(status, 404);
    assert!(String::from_utf8_lossy(&data).contains("404 page not found"));

    let (status, _, _, data) = send("HEAD", "/proto", Vec::new());
    assert_eq!((status, data.len()), (200, 0));

    // A streamed response arrives whole.
    let (_, _, _, data) = send("GET", "/stream", Vec::new());
    assert_eq!(data, b"chunk0;chunk1;chunk2;chunk3;chunk4;");

    // Cookies set by the server come back.
    let (_, _, _, first) = send("GET", "/cookie", Vec::new());
    let (_, _, _, second) = send("GET", "/cookie", Vec::new());
    assert_eq!((first, second), (Vec::new(), b"k=v".to_vec()));
}

fn ws_dial<'a>(address: &'a str, tls: &'a TlsOptions, protocols: &'a [String]) -> Dial<'a> {
    Dial {
        address,
        headers: &[],
        subprotocols: protocols,
        max_message_bytes: None,
        timeout: Some(10_000_000_000),
        tls,
        compression: false,
    }
}

fn run_ws_client_against_go(mode: &str, scheme: &str) {
    let Some(peer) = peer() else { return };
    let _turn = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
    let server = go_server(&peer, mode);
    let net = Network::new_root();
    let tls = TlsOptions {
        roots_pem: cert(),
        ..TlsOptions::default()
    };
    let protocols = vec!["other".to_string(), "chat".to_string()];
    let address = format!("{scheme}://{}/ws", server.address);
    let socket = connect(&net, &ws_dial(&address, &tls, &protocols)).unwrap();
    assert_eq!(socket.subprotocol(), "chat");
    socket.send(b"hello", true, None).unwrap();
    socket.send(&[1, 2, 3], false, None).unwrap();
    let big = vec![b'z'; 100_000];
    socket.send(&big, true, None).unwrap();
    let first = socket.receive(None).unwrap().unwrap();
    assert_eq!(
        (first.data.as_slice(), first.text),
        (&b"chat:hello"[..], true)
    );
    let second = socket.receive(None).unwrap().unwrap();
    assert_eq!(
        (second.data.as_slice(), second.text),
        (&b"chat:\x01\x02\x03"[..], false)
    );
    let third = socket.receive(None).unwrap().unwrap();
    assert_eq!(third.data.len(), 100_005);
    socket.close();
}

#[test]
fn rust_websocket_client_to_gorilla_server() {
    run_ws_client_against_go("h1", "ws");
}

#[test]
fn rust_websocket_client_to_gorilla_server_tls() {
    run_ws_client_against_go("tls-h1", "wss");
}

#[test]
fn rust_client_to_go_server_http1() {
    run_client_against_go("h1", "http", &[], "HTTP/1.1");
}

#[test]
fn rust_client_to_go_server_tls_http1() {
    run_client_against_go("tls-h1", "https", &["http/1.1"], "HTTP/1.1");
}

#[test]
fn rust_client_to_go_server_http2() {
    run_client_against_go("tls-h2", "https", &["h2", "http/1.1"], "HTTP/2.0");
}

// ------------------------------------------------------------- Go client, Rust server

struct App;

impl Dispatch for App {
    fn buffered(&self, r: Incoming) -> Outcome<Reply> {
        let mut headers = Headers::new();
        let mut status = 200;
        let body = match r.path.as_str() {
            "/proto" => r.protocol.as_bytes().to_vec(),
            "/echo" => {
                headers.add("X-Seen-Method", r.method.as_bytes().to_vec());
                let agent = r.headers.first("User-Agent").unwrap_or_default().to_vec();
                headers.add("X-Seen-Agent", agent);
                r.body.clone()
            }
            "/big" => pattern(1 << 20),
            "/redirect" => {
                status = 302;
                headers.add("Location", b"/proto".to_vec());
                Vec::new()
            }
            _ => {
                status = 404;
                b"404 page not found\n".to_vec()
            }
        };
        Outcome::Done(Reply {
            status,
            headers,
            body,
        })
    }

    fn streaming(&self, _: Rc<Exchange>) -> Outcome<Result<(), HttpErr>> {
        Outcome::Done(Ok(()))
    }
}

fn run_go_client(mode: &str, scheme: &str, alpn: &[&str], protocol: &str) {
    let Some(peer) = peer() else { return };
    let _turn = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
    let net = Network::new_root();
    let tls = (scheme == "https").then(|| {
        tls::server_config(&TlsOptions {
            certificate_pem: cert(),
            private_key_pem: key(),
            alpn: alpn.iter().map(|s| s.to_string()).collect(),
            ..TlsOptions::default()
        })
        .unwrap()
    });
    let options = Options {
        limits: Limits::default(),
        streaming: false,
        tls,
    };
    let server = Server::start(&net, "127.0.0.1:0", Box::new(App), options).unwrap();
    let base = format!("{scheme}://{}", server.address());
    let dir = manifest().join("testdata");
    let mut child = Command::new(&peer)
        .args(["client", mode, &base])
        .arg(dir.join("stdlib.test.crt.pem"))
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    // Serve while the Go client runs.
    let mut waited = 0;
    while child.try_wait().unwrap().is_none() {
        wait::sleep(Duration::from_millis(5));
        waited += 1;
        assert!(waited < 4000, "go client did not finish");
    }
    let mut out = String::new();
    child
        .stdout
        .take()
        .unwrap()
        .read_to_string(&mut out)
        .unwrap();
    let lines: Vec<&str> = out.lines().collect();
    assert_eq!(lines.len(), 6, "{out}");
    assert!(
        lines[0].starts_with(&format!(
            "GET {base}/proto 200 {protocol} len={}",
            protocol.len()
        )),
        "{out}"
    );
    let agent = if protocol == "HTTP/2.0" {
        "Go-http-client/2.0"
    } else {
        "Go-http-client/1.1"
    };
    assert!(
        lines[1].contains(&format!("POST {base}/echo 200 {protocol} len=200000")),
        "{out}"
    );
    assert!(lines[1].ends_with(&format!("agent={agent}")), "{out}");
    assert!(
        lines[2].contains(&format!("{base}/big 200 {protocol} len=1048576")),
        "{out}"
    );
    // The redirect landed on /proto.
    assert!(
        lines[3].contains(&format!("/redirect 200 {protocol} len={}", protocol.len())),
        "{out}"
    );
    assert!(
        lines[4].contains(&format!("HEAD {base}/proto 200 {protocol} len=0")),
        "{out}"
    );
    assert!(
        lines[5].contains(&format!("/missing 404 {protocol}")),
        "{out}"
    );
}

#[test]
fn go_client_to_rust_server_http1() {
    run_go_client("h1", "http", &[], "HTTP/1.1");
}

#[test]
fn go_client_to_rust_server_tls_http1() {
    run_go_client("tls-h1", "https", &["http/1.1"], "HTTP/1.1");
}

#[test]
fn go_client_to_rust_server_http2() {
    run_go_client("tls-h2", "https", &["h2", "http/1.1"], "HTTP/2.0");
}

// ------------------------------------------------------------- WebSocket, Go client

struct EchoSockets;

impl Dispatch for EchoSockets {
    fn buffered(&self, _: Incoming) -> Outcome<Reply> {
        Outcome::Done(Reply {
            status: 404,
            headers: Headers::new(),
            body: Vec::new(),
        })
    }

    fn streaming(&self, x: Rc<Exchange>) -> Outcome<Result<(), HttpErr>> {
        let protocols = vec!["chat".to_string()];
        let Ok(socket) = x.upgrade(&[], &protocols, None) else {
            return Outcome::Done(Ok(()));
        };
        while let Ok(Some(message)) = socket.receive(None) {
            let mut reply = socket.subprotocol().as_bytes().to_vec();
            reply.push(b':');
            reply.extend_from_slice(&message.data);
            if socket.send(&reply, message.text, None).is_err() {
                break;
            }
        }
        Outcome::Done(Ok(()))
    }
}

fn run_go_ws_client(scheme: &str) {
    let Some(peer) = peer() else { return };
    let _turn = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
    let net = Network::new_root();
    let tls = (scheme == "wss").then(|| {
        tls::server_config(&TlsOptions {
            certificate_pem: cert(),
            private_key_pem: key(),
            alpn: vec!["http/1.1".into()],
            ..TlsOptions::default()
        })
        .unwrap()
    });
    let options = Options {
        limits: Limits::default(),
        streaming: true,
        tls,
    };
    let server = Server::start(&net, "127.0.0.1:0", Box::new(EchoSockets), options).unwrap();
    let base = format!("{scheme}://{}", server.address());
    let dir = manifest().join("testdata");
    let mut child = Command::new(&peer)
        .args(["ws-client", &base])
        .arg(dir.join("stdlib.test.crt.pem"))
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut waited = 0;
    while child.try_wait().unwrap().is_none() {
        wait::sleep(Duration::from_millis(5));
        waited += 1;
        assert!(waited < 4000, "go client did not finish");
    }
    let mut out = String::new();
    child
        .stdout
        .take()
        .unwrap()
        .read_to_string(&mut out)
        .unwrap();
    let lines: Vec<&str> = out.lines().collect();
    assert_eq!(lines.len(), 5, "{out}");
    assert_eq!(lines[0], "dial 101 chat", "{out}");
    assert_eq!(lines[1], "msg kind=1 len=10 head=\"chat:hello\"", "{out}");
    assert_eq!(
        lines[2], "msg kind=2 len=8 head=\"chat:\\x01\\x02\\x03\"",
        "{out}"
    );
    assert!(lines[3].starts_with("msg kind=1 len=100005"), "{out}");
    assert!(lines[4].starts_with("after close:"), "{out}");
}

#[test]
fn gorilla_client_to_rust_websocket_server() {
    run_go_ws_client("ws");
}

#[test]
fn gorilla_client_to_rust_websocket_server_tls() {
    run_go_ws_client("wss");
}
