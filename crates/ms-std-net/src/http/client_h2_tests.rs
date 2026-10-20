//! HTTP/2 client tests: a std-thread server built on the sans-io core, reached
//! over cleartext prior knowledge, plus one real TLS exchange negotiated by
//! ALPN.

use super::*;
use crate::conn::{Io, Step};
use crate::h2::{self, Event, Settings, error_code};
use crate::http::url;
use crate::wait::{Interest, Wait, wait_fd};
use std::io::Read;
use std::net::{Shutdown, TcpListener, TcpStream};
use std::sync::Mutex;
use std::sync::atomic::{AtomicUsize, Ordering};

type Fields = Vec<(String, String)>;

#[derive(Clone, Debug, Default)]
struct Req {
    headers: Fields,
    body: Vec<u8>,
}

impl Req {
    fn get(&self, name: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(n, _)| n == name)
            .map(|(_, v)| v.as_str())
    }

    fn path(&self) -> &str {
        self.get(":path").unwrap_or("")
    }

    fn method(&self) -> &str {
        self.get(":method").unwrap_or("")
    }

    /// Every header as `name: value` lines.
    fn dump(&self) -> String {
        self.headers
            .iter()
            .map(|(n, v)| format!("{n}: {v}\n"))
            .collect()
    }
}

enum Reply {
    Respond {
        status: u16,
        headers: Fields,
        body: Vec<u8>,
    },
    /// Status 200 and a body prefix, then a reset, or a stall without one.
    Partial {
        body: Vec<u8>,
        reset: Option<u32>,
    },
    Reset(u32),
    /// GOAWAY, then close the connection.
    GoAway,
    Silent,
}

fn ok(body: impl Into<Vec<u8>>) -> Reply {
    Reply::Respond {
        status: 200,
        headers: Vec::new(),
        body: body.into(),
    }
}

fn redirect(status: u16, location: &str) -> Reply {
    Reply::Respond {
        status,
        headers: vec![("location".into(), location.into())],
        body: Vec::new(),
    }
}

trait Pipe {
    fn recv(&mut self, buf: &mut [u8]) -> usize;
    fn send_all(&mut self, data: &[u8]) -> bool;
    /// Ends the connection politely.
    fn finish(&mut self);
}

impl Pipe for TcpStream {
    fn recv(&mut self, buf: &mut [u8]) -> usize {
        Read::read(self, buf).unwrap_or(0)
    }

    fn send_all(&mut self, data: &[u8]) -> bool {
        Write::write_all(self, data).is_ok()
    }

    fn finish(&mut self) {
        let _ = self.shutdown(Shutdown::Write);
        let _ = self.set_read_timeout(Some(Duration::from_millis(300)));
        let mut buf = [0u8; 4096];
        while self.recv(&mut buf) > 0 {}
    }
}

type Route = Arc<dyn Fn(&Req, usize) -> Reply + Send + Sync>;
type Log = Arc<Mutex<Vec<String>>>;

fn text_of(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).into_owned()
}

/// Serves HTTP/2 on `pipe`, answering each complete request through `route`
/// (with the connection's index). Resets from the client are logged.
fn serve_h2(mut pipe: impl Pipe, route: Route, index: usize, log: Log) {
    let mut core = h2::Connection::server(Settings::default());
    let mut reqs: HashMap<u32, Req> = HashMap::new();
    let mut sending: Vec<(u32, Vec<u8>, usize)> = Vec::new();
    let mut buf = vec![0u8; 65536];
    loop {
        let out = core.take_output();
        if !out.is_empty() && !pipe.send_all(&out) {
            return;
        }
        let n = pipe.recv(&mut buf);
        if n == 0 {
            return;
        }
        let Ok(events) = core.feed(&buf[..n]) else {
            let out = core.take_output();
            pipe.send_all(&out);
            return;
        };
        let mut done = Vec::new();
        for event in events {
            match event {
                Event::Headers {
                    id,
                    headers,
                    end_stream,
                } => {
                    let headers = headers
                        .iter()
                        .map(|(n, v)| (text_of(n), text_of(v)))
                        .collect();
                    reqs.insert(
                        id,
                        Req {
                            headers,
                            body: Vec::new(),
                        },
                    );
                    if end_stream {
                        done.push(id);
                    }
                }
                Event::Data {
                    id,
                    data,
                    end_stream,
                } => {
                    core.release(id, data.len());
                    if let Some(req) = reqs.get_mut(&id) {
                        req.body.extend_from_slice(&data);
                    }
                    if end_stream {
                        done.push(id);
                    }
                }
                Event::Reset { code, .. } => log.lock().unwrap().push(format!("reset:{code}")),
                _ => {}
            }
        }
        for id in done {
            let Some(req) = reqs.remove(&id) else {
                continue;
            };
            log.lock()
                .unwrap()
                .push(format!("{} {}", req.method(), req.path()));
            match route(&req, index) {
                Reply::Respond {
                    status,
                    headers,
                    body,
                } => {
                    let mut block = vec![(b":status".to_vec(), status.to_string().into_bytes())];
                    block.extend(
                        headers
                            .into_iter()
                            .map(|(n, v)| (n.into_bytes(), v.into_bytes())),
                    );
                    core.send_response_headers(id, block, body.is_empty())
                        .unwrap();
                    if !body.is_empty() {
                        sending.push((id, body, 0));
                    }
                }
                Reply::Partial { body, reset } => {
                    let block = vec![(b":status".to_vec(), b"200".to_vec())];
                    core.send_response_headers(id, block, false).unwrap();
                    core.send_data(id, &body, false);
                    if let Some(code) = reset {
                        core.send_rst(id, code);
                    }
                }
                Reply::Reset(code) => core.send_rst(id, code),
                Reply::GoAway => {
                    core.shutdown(error_code::NO_ERROR);
                    let out = core.take_output();
                    pipe.send_all(&out);
                    pipe.finish();
                    return;
                }
                Reply::Silent => {}
            }
        }
        sending.retain_mut(|(id, body, off)| {
            *off += core.send_data(*id, &body[*off..], true);
            *off < body.len()
        });
    }
}

/// A loopback HTTP/2 server; returns its address, accept counter and log.
fn serve(
    route: impl Fn(&Req, usize) -> Reply + Send + Sync + 'static,
) -> (String, Arc<AtomicUsize>, Log) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let address = listener.local_addr().unwrap().to_string();
    let accepted = Arc::new(AtomicUsize::new(0));
    let log: Log = Arc::default();
    let route: Route = Arc::new(route);
    let (counter, shared) = (accepted.clone(), log.clone());
    std::thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(stream) = stream else { break };
            let _ = stream.set_read_timeout(Some(Duration::from_secs(10)));
            let index = counter.fetch_add(1, Ordering::SeqCst);
            let (route, log) = (route.clone(), shared.clone());
            std::thread::spawn(move || serve_h2(stream, route, index, log));
        }
    });
    (address, accepted, log)
}

fn h2_client(opts: ClientOptions, settings: Settings) -> (Rc<Network>, Rc<Client>) {
    let net = Network::new_root();
    let client = Client::new(&net, opts).unwrap();
    *client.h2_prior.borrow_mut() = Some(settings);
    (net, client)
}

/// A client with large windows.
fn client(opts: ClientOptions) -> (Rc<Network>, Rc<Client>) {
    h2_client(opts, h2client::client_settings(None))
}

fn request(method: &str, address: &str, path: &str) -> Request {
    Request {
        method: method.into(),
        url: url::parse(&format!("http://{address}{path}")).unwrap(),
        headers: Vec::new(),
        body: Body::Bytes(Rc::new(Vec::new())),
        max_response: u64::MAX,
        deadline: Deadline::after(Duration::from_secs(10)),
    }
}

fn post(address: &str, path: &str, body: Vec<u8>) -> Request {
    let mut r = request("POST", address, path);
    r.body = Body::Bytes(Rc::new(body));
    r
}

fn text(body: &ResponseBody) -> String {
    text_of(&body.read_all().unwrap())
}

fn pattern(len: usize) -> Vec<u8> {
    (0..len).map(|i| (i % 251) as u8).collect()
}

fn wait_for(log: &Log, entry: &str) -> bool {
    for _ in 0..200 {
        if log.lock().unwrap().iter().any(|e| e == entry) {
            return true;
        }
        std::thread::sleep(Duration::from_millis(10));
    }
    false
}

#[test]
fn gets_with_http2_headers() {
    let (address, accepted, _) = serve(|req, _| ok(req.dump()));
    let (_net, c) = client(ClientOptions::default());
    let mut r = request("GET", &address, "/p?x=1");
    r.headers = vec![
        ("X-Zed".into(), b"1".to_vec()),
        ("Accept".into(), b"*/*".to_vec()),
        ("Connection".into(), b"close".to_vec()),
        ("Keep-Alive".into(), b"timeout=5".to_vec()),
        ("Transfer-Encoding".into(), b"chunked".to_vec()),
    ];
    let body = c.send(r).unwrap();
    assert_eq!(body.status, 200);
    assert_eq!(body.protocol, "HTTP/2.0");
    let seen = text(&body);
    for line in [
        ":method: GET\n",
        ":scheme: http\n",
        &format!(":authority: {address}\n"),
        ":path: /p?x=1\n",
        "user-agent: ms-http\n",
        "x-zed: 1\n",
        "accept: */*\n",
    ] {
        assert!(seen.contains(line), "{line:?} missing from {seen}");
    }
    for absent in [
        "connection",
        "keep-alive",
        "transfer-encoding",
        "host:",
        "content-length",
    ] {
        assert!(!seen.contains(absent), "{absent:?} sent: {seen}");
    }

    // The session is reused.
    assert!(!text(&c.send(request("GET", &address, "/")).unwrap()).is_empty());
    assert_eq!(accepted.load(Ordering::SeqCst), 1);
}

#[test]
fn response_headers_are_canonical() {
    let (address, _, _) = serve(|_, _| Reply::Respond {
        status: 201,
        headers: vec![
            ("x-out".into(), "a".into()),
            ("x-out".into(), "b".into()),
            ("content-type".into(), "text/plain".into()),
        ],
        body: b"hi".to_vec(),
    });
    let (_net, c) = client(ClientOptions::default());
    let body = c.send(request("GET", &address, "/")).unwrap();
    assert_eq!(body.status, 201);
    let headers = body.headers.borrow();
    assert_eq!(
        headers.values("X-Out").unwrap(),
        &[b"a".to_vec(), b"b".to_vec()]
    );
    assert!(headers.values("Content-Type").is_some());
    drop(headers);
    assert_eq!(text(&body), "hi");
}

#[test]
fn posts_bodies_larger_than_the_window() {
    let (address, _, _) = serve(|req, _| {
        let cl = req.get("content-length").unwrap_or("none").to_string();
        let same = req.body == pattern(200_000);
        ok(format!("cl={cl} len={} same={same}", req.body.len()))
    });
    // Default windows: the upload stalls until the server releases data.
    let (_net, c) = h2_client(ClientOptions::default(), Settings::default());
    let echoed = text(&c.send(post(&address, "/up", pattern(200_000))).unwrap());
    assert_eq!(echoed, "cl=200000 len=200000 same=true");

    let empty = text(&c.send(post(&address, "/up", Vec::new())).unwrap());
    assert_eq!(empty, "cl=0 len=0 same=false");
}

struct Pieces(Vec<Vec<u8>>);

impl Source for Pieces {
    fn next(&mut self, _: usize) -> Result<Option<Vec<u8>>, String> {
        Ok((!self.0.is_empty()).then(|| self.0.remove(0)))
    }
}

#[test]
fn streams_uploads() {
    let (address, _, _) = serve(|req, _| {
        let cl = req.get("content-length").unwrap_or("none").to_string();
        ok(format!("cl={cl} len={}", req.body.len()))
    });
    let (_net, c) = h2_client(ClientOptions::default(), Settings::default());
    let mut r = request("PUT", &address, "/s");
    r.body = Body::Stream(Box::new(Pieces(vec![pattern(40_000); 5])));
    assert_eq!(text(&c.send(r).unwrap()), "cl=none len=200000");

    let mut failing = request("PUT", &address, "/s");
    struct Broken;
    impl Source for Broken {
        fn next(&mut self, _: usize) -> Result<Option<Vec<u8>>, String> {
            Err("boom".into())
        }
    }
    failing.body = Body::Stream(Box::new(Broken));
    assert!(matches!(c.send(failing), Err(HttpErr::Failed(m)) if m == "boom"));
    // The session survives a failed upload.
    assert!(!text(&c.send(request("GET", &address, "/")).unwrap()).is_empty());
}

#[test]
fn reads_responses_larger_than_the_window() {
    let (address, _, _) = serve(|_, _| ok(pattern(300_000)));
    let (_net, c) = h2_client(ClientOptions::default(), Settings::default());
    let body = c.send(request("GET", &address, "/big")).unwrap();
    assert_eq!(body.read_all().unwrap(), pattern(300_000));

    let mut limited = request("GET", &address, "/big");
    limited.max_response = 1000;
    assert_eq!(c.send(limited).unwrap().read_all(), Err(ReadAll::Limit));
    // Abandoning the over-budget body leaves the session usable.
    assert_eq!(
        c.send(request("GET", &address, "/big"))
            .unwrap()
            .read_all()
            .unwrap()
            .len(),
        300_000
    );
}

#[test]
fn decompresses_gzip() {
    let gz = {
        let mut e = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
        e.write_all(&vec![b'a'; 100_000]).unwrap();
        e.finish().unwrap()
    };
    let (address, _, _) = serve(move |req, _| {
        if req.get("accept-encoding") != Some("gzip") {
            return ok("plain");
        }
        Reply::Respond {
            status: 200,
            headers: vec![
                ("content-encoding".into(), "gzip".into()),
                ("content-length".into(), gz.len().to_string()),
            ],
            body: gz.clone(),
        }
    });
    let (_net, c) = client(ClientOptions {
        decompress: true,
        ..ClientOptions::default()
    });
    let body = c.send(request("GET", &address, "/")).unwrap();
    assert!(body.headers.borrow().values("Content-Encoding").is_none());
    assert!(body.headers.borrow().values("Content-Length").is_none());
    assert_eq!(body.read_all().unwrap().len(), 100_000);

    let mut limited = request("GET", &address, "/");
    limited.max_response = 99_999;
    assert_eq!(c.send(limited).unwrap().read_all(), Err(ReadAll::Limit));

    let (_net, plain) = client(ClientOptions::default());
    assert_eq!(
        text(&plain.send(request("GET", &address, "/")).unwrap()),
        "plain"
    );
}

#[test]
fn follows_redirects() {
    let (address, accepted, _) = serve(|req, _| match req.path() {
        "/r302" => redirect(302, "/dump"),
        "/r307" => redirect(307, "/dump"),
        "/loop" => redirect(302, "/loop"),
        _ => ok(format!(
            "{} {} body={}",
            req.method(),
            req.path(),
            text_of(&req.body)
        )),
    });
    let (_net, c) = client(ClientOptions::default());
    let echoed = text(&c.send(post(&address, "/r302", b"hello".to_vec())).unwrap());
    assert_eq!(echoed, "GET /dump body=");
    let echoed = text(&c.send(post(&address, "/r307", b"hello".to_vec())).unwrap());
    assert_eq!(echoed, "POST /dump body=hello");
    assert_eq!(accepted.load(Ordering::SeqCst), 1);

    let (_net, capped) = client(ClientOptions {
        max_redirects: Some(2),
        ..ClientOptions::default()
    });
    match capped.send(request("GET", &address, "/loop")) {
        Err(HttpErr::Failed(m)) => assert_eq!(m, "redirect limit exceeded"),
        other => panic!("{:?}", other.map(|b| b.status)),
    }
    let (_net, none) = client(ClientOptions {
        max_redirects: Some(0),
        ..ClientOptions::default()
    });
    assert_eq!(
        none.send(request("GET", &address, "/r302")).unwrap().status,
        302
    );
}

#[test]
fn closing_a_body_resets_its_stream() {
    let (address, _, log) = serve(|_, _| ok(pattern(1_000_000)));
    let (_net, c) = h2_client(ClientOptions::default(), Settings::default());
    let body = c.send(request("GET", &address, "/")).unwrap();
    assert_eq!(body.read(10).unwrap().unwrap().len(), 10);
    body.close();
    assert!(wait_for(&log, "reset:8"), "{:?}", log.lock().unwrap());
    assert_eq!(body.read(10), Err(IoErr::Closed));

    // Dropping an open body does the same.
    log.lock().unwrap().clear();
    let body = c.send(request("GET", &address, "/")).unwrap();
    assert_eq!(body.read(10).unwrap().unwrap().len(), 10);
    drop(body);
    assert!(wait_for(&log, "reset:8"), "{:?}", log.lock().unwrap());

    // The session carries on.
    let again = c.send(request("GET", &address, "/")).unwrap();
    assert_eq!(again.read(5).unwrap().unwrap().len(), 5);
}

#[test]
fn multiplexes_open_bodies() {
    let (address, accepted, _) = serve(|req, _| match req.path() {
        "/a" => ok(vec![b'a'; 200_000]),
        _ => ok(vec![b'b'; 200_000]),
    });
    let (_net, c) = client(ClientOptions::default());
    let a = c.send(request("GET", &address, "/a")).unwrap();
    let b = c.send(request("GET", &address, "/b")).unwrap();
    assert_eq!(a.read(10).unwrap().unwrap(), vec![b'a'; 10]);
    let all_b = b.read_all().unwrap();
    assert_eq!(all_b.len(), 200_000);
    assert!(all_b.iter().all(|&x| x == b'b'));
    let rest_a = a.read_all().unwrap();
    assert_eq!(rest_a.len(), 200_000 - 10);
    assert!(rest_a.iter().all(|&x| x == b'a'));
    assert_eq!(accepted.load(Ordering::SeqCst), 1);
}

#[test]
fn retries_after_goaway_once() {
    let (address, accepted, _) = serve(|req, index| {
        if index == 0 && req.path() == "/bye" {
            Reply::GoAway
        } else {
            ok(format!("conn {index}"))
        }
    });
    let (_net, c) = client(ClientOptions::default());
    assert_eq!(
        text(&c.send(request("GET", &address, "/")).unwrap()),
        "conn 0"
    );
    // The second request meets a GOAWAY on the reused session and replays.
    assert_eq!(
        text(&c.send(request("GET", &address, "/bye")).unwrap()),
        "conn 1"
    );
    assert_eq!(accepted.load(Ordering::SeqCst), 2);

    // A request that may not be replayed fails instead.
    let (address, _, _) = serve(|req, _| {
        if req.method() == "POST" {
            Reply::GoAway
        } else {
            ok("fine")
        }
    });
    let (_net, c) = client(ClientOptions::default());
    assert_eq!(
        text(&c.send(request("GET", &address, "/")).unwrap()),
        "fine"
    );
    match c.send(post(&address, "/", b"x".to_vec())) {
        Err(HttpErr::Failed(m)) => assert_eq!(m, "connection closed before the exchange completed"),
        other => panic!("{:?}", other.map(|b| b.status)),
    }
}

#[test]
fn replays_refused_streams() {
    let seen = AtomicUsize::new(0);
    let (address, accepted, _) = serve(move |_, _| {
        if seen.fetch_add(1, Ordering::SeqCst) == 0 {
            Reply::Reset(error_code::REFUSED_STREAM)
        } else {
            ok("second")
        }
    });
    let (_net, c) = client(ClientOptions::default());
    assert_eq!(
        text(&c.send(post(&address, "/", b"x".to_vec())).unwrap()),
        "second"
    );
    assert_eq!(accepted.load(Ordering::SeqCst), 1);
}

#[test]
fn reports_reset_streams() {
    let (address, _, _) = serve(|req, _| match req.path() {
        "/mid" => Reply::Partial {
            body: b"abc".to_vec(),
            reset: Some(error_code::INTERNAL_ERROR),
        },
        _ => Reply::Reset(error_code::PROTOCOL_ERROR),
    });
    let (_net, c) = client(ClientOptions::default());
    match c.send(request("GET", &address, "/")) {
        Err(HttpErr::Failed(m)) => {
            assert_eq!(
                m,
                "stream error: stream ID 1; PROTOCOL_ERROR; received from peer"
            )
        }
        other => panic!("{:?}", other.map(|b| b.status)),
    }
    let body = c.send(request("GET", &address, "/mid")).unwrap();
    assert_eq!(body.read(100).unwrap().unwrap(), b"abc");
    assert_eq!(
        body.read(100),
        Err(IoErr::Failed(
            "stream error: stream ID 3; INTERNAL_ERROR; received from peer".into()
        ))
    );
    assert_eq!(h2client::code_name(0x99), "unknown error code 0x99");
}

#[test]
fn honors_deadlines() {
    let (address, _, _) = serve(|req, _| match req.path() {
        "/stall" => Reply::Partial {
            body: b"abc".to_vec(),
            reset: None,
        },
        _ => Reply::Silent,
    });
    let (_net, c) = client(ClientOptions::default());
    let mut silent = request("GET", &address, "/");
    silent.deadline = Deadline::after(Duration::from_millis(150));
    assert!(matches!(c.send(silent), Err(HttpErr::Timeout)));

    let mut stall = request("GET", &address, "/stall");
    stall.deadline = Deadline::after(Duration::from_millis(300));
    let body = c.send(stall).unwrap();
    assert_eq!(body.read(100).unwrap().unwrap(), b"abc");
    assert_eq!(
        body.read(100),
        Err(IoErr::Failed("context deadline exceeded".into()))
    );
}

#[test]
fn close_cancels_open_bodies_and_sessions() {
    let (address, _, log) = serve(|_, _| Reply::Partial {
        body: b"abc".to_vec(),
        reset: None,
    });
    let (_net, c) = client(ClientOptions::default());
    let body = c.send(request("GET", &address, "/")).unwrap();
    assert_eq!(body.read(100).unwrap().unwrap(), b"abc");
    c.close();
    assert_eq!(body.read(100), Err(IoErr::Closed));
    assert!(wait_for(&log, "reset:8"), "{:?}", log.lock().unwrap());
    assert!(matches!(
        c.send(request("GET", &address, "/")),
        Err(HttpErr::Closed)
    ));
}

#[test]
fn replaces_idle_sessions() {
    let (address, accepted, _) = serve(|_, _| ok("ok"));
    let (_net, c) = client(ClientOptions {
        idle_timeout: Some(Duration::from_millis(50)),
        ..ClientOptions::default()
    });
    assert_eq!(text(&c.send(request("GET", &address, "/")).unwrap()), "ok");
    assert_eq!(text(&c.send(request("GET", &address, "/")).unwrap()), "ok");
    assert_eq!(accepted.load(Ordering::SeqCst), 1);
    std::thread::sleep(Duration::from_millis(120));
    assert_eq!(text(&c.send(request("GET", &address, "/")).unwrap()), "ok");
    assert_eq!(accepted.load(Ordering::SeqCst), 2);
}

// ------------------------------------------------------------------------- TLS

const CERT: &str = include_str!("../../testdata/stdlib.test.crt.pem");
const KEY: &str = include_str!("../../testdata/stdlib.test.key.pem");

struct TlsPipe(Box<dyn Io>);

impl TlsPipe {
    fn wait(&self, interest: Interest) -> bool {
        let deadline = Deadline::after(Duration::from_secs(10));
        wait_fd(self.0.fd(), interest, deadline) != Wait::TimedOut
    }
}

impl Pipe for TlsPipe {
    fn recv(&mut self, buf: &mut [u8]) -> usize {
        loop {
            let ready = match self.0.read(buf) {
                Step::Done(n) => return n,
                Step::WantRead => self.wait(Interest::Read),
                Step::WantWrite => self.wait(Interest::Write),
                Step::Eof | Step::Err(_) => return 0,
            };
            if !ready {
                return 0;
            }
        }
    }

    fn send_all(&mut self, data: &[u8]) -> bool {
        let mut sent = 0;
        while sent < data.len() {
            let ready = match self.0.write(&data[sent..]) {
                Step::Done(n) => {
                    sent += n;
                    true
                }
                Step::WantRead => self.wait(Interest::Read),
                Step::WantWrite => self.wait(Interest::Write),
                Step::Eof | Step::Err(_) => return false,
            };
            if !ready {
                return false;
            }
        }
        loop {
            let ready = match self.0.flush() {
                Step::Done(_) => return true,
                Step::WantRead => self.wait(Interest::Read),
                Step::WantWrite => self.wait(Interest::Write),
                Step::Eof | Step::Err(_) => return false,
            };
            if !ready {
                return false;
            }
        }
    }

    fn finish(&mut self) {
        self.0.shutdown_both();
    }
}

#[test]
fn negotiates_http2_through_alpn() {
    let server_tls = TlsOptions {
        certificate_pem: CERT.into(),
        private_key_pem: KEY.into(),
        alpn: vec!["h2".into(), "http/1.1".into()],
        ..TlsOptions::default()
    };
    let config = tls::server_config(&server_tls).unwrap();
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let address = listener.local_addr().unwrap().to_string();
    let route: Route = Arc::new(|req, _| {
        if req.method() == "POST" {
            ok(format!("tls post {}", req.body.len()))
        } else {
            ok("tls ok")
        }
    });
    let log: Log = Arc::default();
    std::thread::spawn(move || {
        let (stream, _) = listener.accept().unwrap();
        stream.set_nonblocking(true).unwrap();
        let sock = socket2::Socket::from(stream);
        let deadline = Deadline::after(Duration::from_secs(10));
        let io = tls::accept(sock, config, deadline, false).unwrap();
        serve_h2(TlsPipe(io), route, 0, log);
    });

    let client_tls = TlsOptions {
        roots_pem: CERT.into(),
        alpn: vec!["h2".into()],
        ..TlsOptions::default()
    };
    let net = Network::new_root();
    let c = Client::new(
        &net,
        ClientOptions {
            tls: client_tls,
            ..ClientOptions::default()
        },
    )
    .unwrap();
    let mut get = request("GET", &address, "/");
    get.url = url::parse(&format!("https://{address}/")).unwrap();
    let body = c.send(get).unwrap();
    assert_eq!(body.protocol, "HTTP/2.0");
    assert_eq!(text(&body), "tls ok");

    let mut upload = post(&address, "/", pattern(150_000));
    upload.url = url::parse(&format!("https://{address}/up")).unwrap();
    let body = c.send(upload).unwrap();
    assert_eq!(body.protocol, "HTTP/2.0");
    assert_eq!(text(&body), "tls post 150000");
}
