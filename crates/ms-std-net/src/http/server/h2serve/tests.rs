//! HTTP/2 server tests: a std-thread TLS client drives the sans-io client core
//! against the reactor on the test thread.

use super::*;
use crate::error::HttpErr;
use crate::h2::{Connection, Event, Settings};
use crate::http::server::tests::with_client;
use crate::net::Network;
use crate::tls::{self, TlsOptions};
use std::io::{Read, Write};
use std::net::TcpStream;

const CERT: &str = include_str!("../../../../testdata/stdlib.test.crt.pem");
const KEY: &str = include_str!("../../../../testdata/stdlib.test.key.pem");

fn server_tls() -> Arc<rustls::ServerConfig> {
    tls::server_config(&TlsOptions {
        certificate_pem: CERT.into(),
        private_key_pem: KEY.into(),
        alpn: vec!["h2".into(), "http/1.1".into()],
        ..TlsOptions::default()
    })
    .unwrap()
}

fn client_tls(alpn: &[&str]) -> Arc<rustls::ClientConfig> {
    tls::client_config(
        &TlsOptions {
            server_name: "stdlib.test".into(),
            roots_pem: CERT.into(),
            alpn: alpn.iter().map(|p| p.to_string()).collect(),
            ..TlsOptions::default()
        },
        true,
    )
    .unwrap()
}

/// Buffered handler.
struct App;

impl Dispatch for App {
    fn buffered(&self, r: Request) -> Outcome<Reply> {
        let mut headers = Headers::new();
        let body = match r.path.as_str() {
            "/fault" => return Outcome::Fault("boom".into()),
            "/cancel" => return Outcome::Cancelled,
            "/size" => format!("{}", r.body.len()).into_bytes(),
            "/big" => vec![b'x'; 300_000],
            "/cookie" => {
                let cookie = r.headers.text("cookie").unwrap().unwrap();
                format!(
                    "{}|{:?}",
                    r.headers.first("Host").map_or(0, <[u8]>::len),
                    cookie
                )
                .into_bytes()
            }
            "/headers" => {
                headers.append("X-Thing", b"1").unwrap();
                headers.append("Keep-Alive", b"timeout=5").unwrap();
                b"<html>ok</html>".to_vec()
            }
            p => format!("{}|{}|{}|{}", r.method, p, r.query, r.protocol).into_bytes(),
        };
        let status = if r.path == "/empty" { 204 } else { 200 };
        Outcome::Done(Reply {
            status,
            headers,
            body,
        })
    }

    fn streaming(&self, _: Rc<Exchange>) -> Outcome<Result<(), HttpErr>> {
        Outcome::Cancelled
    }
}

/// Streaming handler.
struct Streamer;

impl Dispatch for Streamer {
    fn buffered(&self, _: Request) -> Outcome<Reply> {
        Outcome::Cancelled
    }

    fn streaming(&self, ex: Rc<Exchange>) -> Outcome<Result<(), HttpErr>> {
        let result = (|| {
            match ex.path().as_str() {
                "/fault" => return Err(HttpErr::Failed("nope".into())),
                "/ws" => {
                    let upgrade = ex.upgrade(&[], &[], None);
                    assert!(matches!(upgrade, Err(WsErr::Failed(_))));
                    return Ok(());
                }
                "/stream" => {
                    ex.send_headers(200, &Headers::new())?;
                    let chunk = vec![b'y'; 4096];
                    for _ in 0..100 {
                        ex.write(&chunk).map_err(|_| HttpErr::Closed)?;
                    }
                    return Ok(());
                }
                "/upload" => {
                    let mut total = 0;
                    while let Some(chunk) = ex.read(None).map_err(|_| HttpErr::Closed)? {
                        total += chunk.len();
                    }
                    ex.send_headers(200, &Headers::new())?;
                    ex.write(total.to_string().as_bytes())
                        .map_err(|_| HttpErr::Closed)?;
                    return Ok(());
                }
                "/nobody" => return Ok(()),
                _ => {}
            }
            ex.send_headers(200, &Headers::new())?;
            ex.write(ex.protocol().as_bytes())
                .map_err(|_| HttpErr::Closed)?;
            Ok(())
        })();
        Outcome::Done(result)
    }
}

fn start(
    dispatch: Box<dyn Dispatch>,
    streaming: bool,
    limits: Limits,
) -> (Rc<Network>, Rc<Server>) {
    let net = Network::new_root();
    let options = Options {
        limits,
        streaming,
        tls: Some(server_tls()),
    };
    let server = Server::start(&net, "127.0.0.1:0", dispatch, options).unwrap();
    (net, server)
}

fn limits() -> Limits {
    Limits {
        timeout: Some(Duration::from_secs(10)),
        grace: Some(Duration::from_secs(1)),
        ..Limits::default()
    }
}

type Tls = rustls::StreamOwned<rustls::ClientConnection, TcpStream>;

fn tls_connect(addr: &str, alpn: &[&str]) -> Tls {
    let sock = TcpStream::connect(addr).unwrap();
    sock.set_read_timeout(Some(Duration::from_secs(10)))
        .unwrap();
    let name = rustls::pki_types::ServerName::try_from("stdlib.test").unwrap();
    let conn = rustls::ClientConnection::new(client_tls(alpn), name).unwrap();
    rustls::StreamOwned::new(conn, sock)
}

struct Client {
    tls: Tls,
    core: Connection,
    events: Vec<Event>,
}

struct Response {
    status: String,
    headers: Vec<(String, String)>,
    body: Vec<u8>,
}

impl Response {
    fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(n, _)| n == name)
            .map(|(_, v)| v.as_str())
    }

    fn text(&self) -> String {
        String::from_utf8_lossy(&self.body).into_owned()
    }
}

fn request(method: &str, path: &str, extra: &[(&str, &str)]) -> Vec<h2::Header> {
    let mut headers = vec![
        hv(":method", method),
        hv(":scheme", "https"),
        hv(":path", path),
        hv(":authority", "stdlib.test"),
    ];
    headers.extend(extra.iter().map(|(n, v)| hv(n, v)));
    headers
}

impl Client {
    fn connect(addr: &str, settings: Settings) -> Client {
        let mut tls = tls_connect(addr, &["h2", "http/1.1"]);
        let mut core = Connection::client(settings);
        tls.write_all(&core.take_output()).unwrap();
        tls.flush().unwrap();
        // Finish the handshake and check what was negotiated.
        let mut client = Client {
            tls,
            core,
            events: Vec::new(),
        };
        assert!(client.pull(), "server closed during setup");
        assert_eq!(client.tls.conn.alpn_protocol(), Some(&b"h2"[..]));
        client
    }

    fn flush(&mut self) {
        let out = self.core.take_output();
        if !out.is_empty() {
            self.tls.write_all(&out).unwrap();
            self.tls.flush().unwrap();
        }
    }

    /// Reads once and feeds the core; `false` at end of stream.
    fn pull(&mut self) -> bool {
        self.flush();
        let mut buf = [0u8; 16 * 1024];
        let n = self.tls.read(&mut buf).unwrap_or_default();
        if n == 0 {
            return false;
        }
        let events = self.core.feed(&buf[..n]).expect("server frames");
        self.events.extend(events);
        self.flush();
        true
    }

    fn get(&mut self, path: &str) -> u32 {
        self.core
            .open_stream(request("GET", path, &[]), true)
            .unwrap()
    }

    /// Sends `body` as a POST, honoring the server's flow control.
    fn post(&mut self, path: &str, body: &[u8], extra: &[(&str, &str)]) -> u32 {
        let id = self
            .core
            .open_stream(request("POST", path, extra), false)
            .unwrap();
        self.send_body(id, body);
        id
    }

    fn send_body(&mut self, id: u32, body: &[u8]) {
        let mut rest = body;
        loop {
            let n = self.core.send_data(id, rest, true);
            rest = &rest[n..];
            self.flush();
            if rest.is_empty() {
                return;
            }
            assert!(self.pull(), "server closed during upload");
        }
    }

    /// Collects the response of `id`, returning data credit as it arrives.
    fn response(&mut self, id: u32) -> Response {
        let mut response = Response {
            status: String::new(),
            headers: Vec::new(),
            body: Vec::new(),
        };
        let mut seen = 0;
        loop {
            while seen < self.events.len() {
                let event = self.events[seen].clone();
                seen += 1;
                match event {
                    Event::Headers {
                        id: sid,
                        headers,
                        end_stream,
                    } if sid == id => {
                        for (n, v) in headers {
                            let (n, v) =
                                (String::from_utf8(n).unwrap(), String::from_utf8(v).unwrap());
                            if n == ":status" {
                                response.status = v;
                            } else {
                                response.headers.push((n, v));
                            }
                        }
                        if end_stream {
                            return response;
                        }
                    }
                    Event::Data {
                        id: sid,
                        data,
                        end_stream,
                    } if sid == id => {
                        self.core.release(id, data.len());
                        response.body.extend_from_slice(&data);
                        if end_stream {
                            return response;
                        }
                    }
                    Event::Reset { id: sid, code } if sid == id => {
                        panic!("stream reset with code {code}")
                    }
                    _ => {}
                }
            }
            assert!(self.pull(), "connection closed before the response");
        }
    }
}

fn big_window() -> Settings {
    Settings {
        initial_window_size: 1 << 20,
        connection_window: 4 << 20,
        ..Settings::default()
    }
}

#[test]
fn serves_get_and_reports_the_protocol() {
    let (_net, server) = start(Box::new(App), false, limits());
    let addr = server.address().to_string();
    let (r, head) = with_client(move || {
        let mut c = Client::connect(&addr, big_window());
        let id = c.get("/a%20b/../hello?x=1");
        let r = c.response(id);
        let id = c
            .core
            .open_stream(request("HEAD", "/hello", &[]), true)
            .unwrap();
        (r, c.response(id))
    });
    assert_eq!(r.status, "200");
    assert_eq!(r.text(), "GET|/hello|x=1|HTTP/2.0");
    assert_eq!(r.header("content-type"), Some("text/plain; charset=utf-8"));
    assert_eq!(r.header("content-length"), Some("23"));
    assert!(r.header("date").is_some());
    assert!(r.header("transfer-encoding").is_none());
    assert_eq!(head.status, "200");
    assert!(head.body.is_empty());
    assert_eq!(head.header("content-length"), Some("21"));
}

#[test]
fn response_headers_are_lowercase_and_not_connection_specific() {
    let (_net, server) = start(Box::new(App), false, limits());
    let addr = server.address().to_string();
    let (html, empty) = with_client(move || {
        let mut c = Client::connect(&addr, big_window());
        let a = c.get("/headers");
        let html = c.response(a);
        let b = c.get("/empty");
        (html, c.response(b))
    });
    assert_eq!(html.header("x-thing"), Some("1"));
    assert!(html.header("keep-alive").is_none());
    assert_eq!(
        html.header("content-type"),
        Some("text/html; charset=utf-8")
    );
    assert_eq!(empty.status, "204");
    assert!(empty.header("content-length").is_none());
    assert!(empty.body.is_empty());
}

#[test]
fn request_fields_are_assembled() {
    let (_net, server) = start(Box::new(App), false, limits());
    let addr = server.address().to_string();
    let r = with_client(move || {
        let mut c = Client::connect(&addr, big_window());
        let id = c
            .core
            .open_stream(
                request("GET", "/cookie", &[("cookie", "a=1"), ("cookie", "b=2")]),
                true,
            )
            .unwrap();
        c.response(id)
    });
    // `:authority` became Host (11 bytes) and the cookies were joined.
    assert_eq!(r.text(), "11|[\"a=1; b=2\"]");
}

#[test]
fn large_upload_honors_flow_control() {
    let (_net, server) = start(Box::new(App), false, limits());
    let addr = server.address().to_string();
    let body = vec![7u8; 300_000];
    let r = with_client(move || {
        // The default 65535-byte windows force the upload to wait for credit.
        let mut c = Client::connect(&addr, Settings::default());
        let id = c.post("/size", &body, &[]);
        c.response(id)
    });
    assert_eq!(r.text(), "300000");
}

#[test]
fn large_response_waits_for_window_updates() {
    let (_net, server) = start(Box::new(App), false, limits());
    let addr = server.address().to_string();
    let (first, total) = with_client(move || {
        let mut c = Client::connect(&addr, Settings::default());
        let id = c.get("/big");
        c.flush();
        // Without credit the server stops at the initial 65535-byte window.
        let mut seen = 0usize;
        let mut got = 0usize;
        let mut idle = 0;
        while idle < 3 {
            while seen < c.events.len() {
                if let Event::Data { data, .. } = &c.events[seen] {
                    got += data.len();
                }
                seen += 1;
            }
            c.tls
                .sock
                .set_read_timeout(Some(Duration::from_millis(300)))
                .unwrap();
            let before = c.events.len();
            let mut buf = [0u8; 16 * 1024];
            if let Ok(n) = c.tls.read(&mut buf) {
                c.events.extend(c.core.feed(&buf[..n]).unwrap());
            }
            idle = if c.events.len() == before {
                idle + 1
            } else {
                0
            };
        }
        c.tls
            .sock
            .set_read_timeout(Some(Duration::from_secs(10)))
            .unwrap();
        // Release what arrived, then read the rest normally.
        c.core.release(id, got);
        c.flush();
        let r = c.response(id);
        // `response` replays the events seen so far.
        (got, r.body.len())
    });
    assert_eq!(first, 65_535);
    assert_eq!(total, 300_000);
}

#[test]
fn streamed_response_larger_than_the_window() {
    let (_net, server) = start(Box::new(Streamer), true, limits());
    let addr = server.address().to_string();
    let r = with_client(move || {
        let mut c = Client::connect(&addr, Settings::default());
        let id = c.get("/stream");
        c.response(id)
    });
    assert_eq!(r.status, "200");
    assert_eq!(r.body.len(), 100 * 4096);
    assert!(r.body.iter().all(|&b| b == b'y'));
    assert!(r.header("content-length").is_none());
}

#[test]
fn streaming_upload_and_protocol() {
    let (_net, server) = start(Box::new(Streamer), true, limits());
    let addr = server.address().to_string();
    let body = vec![1u8; 500_000];
    let (up, plain, none) = with_client(move || {
        let mut c = Client::connect(&addr, Settings::default());
        let id = c.post("/upload", &body, &[]);
        let up = c.response(id);
        let id = c.get("/");
        let plain = c.response(id);
        let id = c.get("/nobody");
        (up, plain, c.response(id))
    });
    assert_eq!(up.text(), "500000");
    assert_eq!(plain.text(), "HTTP/2.0");
    assert_eq!(none.status, "204");
}

#[test]
fn concurrent_streams_complete() {
    let (_net, server) = start(Box::new(App), false, limits());
    let addr = server.address().to_string();
    let (a, b, c3) = with_client(move || {
        let mut c = Client::connect(&addr, big_window());
        let one = c.get("/one");
        let two = c.post("/size", &[0u8; 1000], &[]);
        let three = c.get("/big");
        (c.response(two), c.response(one), c.response(three))
    });
    assert_eq!(a.text(), "1000");
    assert_eq!(b.text(), "GET|/one||HTTP/2.0");
    assert_eq!(c3.body.len(), 300_000);
}

#[test]
fn faults_and_cancellations_answer_per_stream() {
    let (_net, server) = start(Box::new(App), false, limits());
    let addr = server.address().to_string();
    let (fault, cancel, after) = with_client(move || {
        let mut c = Client::connect(&addr, big_window());
        let a = c.get("/fault");
        let fault = c.response(a);
        let b = c.get("/cancel");
        let cancel = c.response(b);
        let d = c.get("/ok");
        (fault, cancel, c.response(d))
    });
    assert_eq!(fault.status, "500");
    assert_eq!(cancel.status, "504");
    // The connection survives.
    assert_eq!(after.status, "200");

    let (_net, server) = start(Box::new(Streamer), true, limits());
    let addr = server.address().to_string();
    let r = with_client(move || {
        let mut c = Client::connect(&addr, big_window());
        let id = c.get("/fault");
        c.response(id)
    });
    assert_eq!(r.status, "500");
}

#[test]
fn body_limit_is_enforced() {
    let (_net, server) = start(
        Box::new(App),
        false,
        Limits {
            body: 1000,
            ..limits()
        },
    );
    let addr = server.address().to_string();
    let (declared, streamed, fine) = with_client(move || {
        let mut c = Client::connect(&addr, big_window());
        let id = c
            .core
            .open_stream(
                request("POST", "/size", &[("content-length", "5000")]),
                false,
            )
            .unwrap();
        let declared = c.response(id);
        let id = c
            .core
            .open_stream(request("POST", "/size", &[]), false)
            .unwrap();
        c.send_body(id, &[0u8; 1500]);
        let streamed = c.response(id);
        let id = c.post("/size", &[0u8; 900], &[]);
        (declared, streamed, c.response(id))
    });
    assert_eq!(declared.status, "413");
    assert_eq!(streamed.status, "413");
    assert_eq!(fine.text(), "900");
}

#[test]
fn admission_limit_answers_503() {
    let (_net, server) = start(
        Box::new(App),
        false,
        Limits {
            admission: 0,
            ..limits()
        },
    );
    let addr = server.address().to_string();
    let r = with_client(move || {
        let mut c = Client::connect(&addr, big_window());
        let id = c.get("/");
        c.response(id)
    });
    assert_eq!(r.status, "503");
}

#[test]
fn upgrade_is_not_available_over_http2() {
    let (_net, server) = start(Box::new(Streamer), true, limits());
    let addr = server.address().to_string();
    let r = with_client(move || {
        let mut c = Client::connect(&addr, big_window());
        let id = c.get("/ws");
        c.response(id)
    });
    assert_eq!(r.status, "204");
}

#[test]
fn http1_clients_share_the_listener() {
    let (_net, server) = start(Box::new(App), false, limits());
    let addr = server.address().to_string();
    let text = with_client(move || {
        let mut tls = tls_connect(&addr, &["http/1.1"]);
        tls.write_all(b"GET /hi HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")
            .unwrap();
        let mut out = Vec::new();
        let _ = tls.read_to_end(&mut out);
        assert_eq!(tls.conn.alpn_protocol(), Some(&b"http/1.1"[..]));
        String::from_utf8_lossy(&out).into_owned()
    });
    assert!(text.starts_with("HTTP/1.1 200 OK\r\n"), "{text}");
    assert!(text.ends_with("GET|/hi||HTTP/1.1"), "{text}");
}

#[test]
fn close_sends_goaway_and_finishes_streams() {
    let (net, server) = start(Box::new(App), false, limits());
    let addr = server.address().to_string();
    let handle = std::thread::spawn(move || {
        let mut c = Client::connect(&addr, big_window());
        let id = c.get("/done");
        let r = c.response(id);
        // The server winds the idle connection down with a GOAWAY.
        let mut goaway = false;
        for _ in 0..50 {
            goaway |= c.events.iter().any(|e| matches!(e, Event::GoAway { .. }));
            if goaway || !c.pull() {
                break;
            }
        }
        goaway |= c.events.iter().any(|e| matches!(e, Event::GoAway { .. }));
        (r.text(), goaway)
    });
    // Serve the request, then close with the client still connected.
    let started = Instant::now();
    while !handle.is_finished() && started.elapsed() < Duration::from_millis(400) {
        crate::wait::sleep(Duration::from_millis(5));
    }
    server.close().unwrap();
    let (text, goaway) = handle.join().unwrap();
    assert_eq!(text, "GET|/done||HTTP/2.0");
    assert!(goaway);
    net.close();
}

#[test]
fn drops_a_peer_that_floods_pings_without_reading() {
    let (_net, server) = start(Box::new(App), false, limits());
    let addr = server.address().to_string();
    let closed_after = with_client(move || {
        let mut c = Client::connect(&addr, big_window());
        // PING frame: 8-byte payload, type 6, no flags, stream 0.
        let mut ping = vec![0, 0, 8, 6, 0, 0, 0, 0, 0];
        ping.extend_from_slice(b"flooding");
        let burst = ping.repeat(2000);
        // Every ping is answered; this client never reads, so the answers pile up server side.
        for sent in 0..2000 {
            if c.tls.write_all(&burst).is_err() || c.tls.flush().is_err() {
                return Some(sent * burst.len());
            }
        }
        None
    });
    let bytes = closed_after.expect("server kept answering pings it could not deliver");
    assert!(bytes < 32 << 20, "closed only after {bytes} bytes");
}
