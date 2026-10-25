//! HTTP/1.1 client: pooled keep-alive connections, redirects, cookies, gzip and
//! streaming response bodies, as configured by
//! `@std/http`.

use super::cookies::Jar;
use super::h1::{self, BodyDecoder, Decoded, Framing, Parsed, ResponseHead};
use super::h2client::{self, H2Stream, OpenErr, Poll, PumpErr, Session};
use super::headers::{self, Headers, Shared};
use super::url::Url;
use crate::conn::Connection;
use crate::error::{HttpErr, IoErr};
use crate::h2::Header;
use crate::net::{Network, Resource};
use crate::rt;
use crate::tls::{self, TlsOptions};
use crate::wait::Deadline;
use flate2::write::GzDecoder;
use ms_rt::fault::with_cleanup;
use rustls::ClientConfig;
use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::io::Write;
use std::rc::{Rc, Weak};
use std::sync::Arc;
use std::time::{Duration, Instant};

/// `User-Agent` of requests that name none.
pub const USER_AGENT: &str = "ms-http";
/// `User-Agent` over HTTP/2.
const USER_AGENT_H2: &str = USER_AGENT;

/// Largest read from a connection and from a request-body source.
const READ_BUF: usize = 64 * 1024;
/// Response bytes read from a redirect's body so its connection can be reused.
const SLURP: usize = 2 << 10;
/// Idle connections kept per host when the caller sets no cap.
const DEFAULT_IDLE_PER_HOST: usize = 2;

// -------------------------------------------------------------------- requests

/// A request body supplied piece by piece.
pub trait Source {
    /// The next chunk of at most `max` bytes, `None` at the end. An `Err` text
    /// becomes the request's failure message.
    fn next(&mut self, max: usize) -> Result<Option<Vec<u8>>, String>;
}

pub enum Body {
    Bytes(Rc<Vec<u8>>),
    Stream(Box<dyn Source>),
}

/// A validated request.
pub struct Request {
    pub method: String,
    pub url: Url,
    /// Canonical names with raw values, in the caller's order.
    pub headers: Vec<(String, Vec<u8>)>,
    pub body: Body,
    /// Bytes a reader may take from the response; `u64::MAX` is unlimited.
    pub max_response: u64,
    pub deadline: Deadline,
}

/// Validates caller headers for an outgoing request: names are tokens, values
/// are text, and the transport-managed names are refused.
pub fn outgoing_headers(source: &Headers, managed: &[&str]) -> Option<Vec<(String, Vec<u8>)>> {
    let mut out = Vec::new();
    for entry in source.entries() {
        if !headers::valid_name(&entry.name)
            || managed.iter().any(|m| entry.name.eq_ignore_ascii_case(m))
        {
            return None;
        }
        let name = headers::canonical(&entry.name);
        for value in &entry.values {
            if !headers::valid_value(value) {
                return None;
            }
            out.push((name.clone(), value.clone()));
        }
    }
    Some(out)
}

/// Whether `method` is a token.
pub fn valid_method(method: &str) -> bool {
    headers::valid_name(method)
}

// --------------------------------------------------------------------- options

#[derive(Clone, Debug, Default)]
pub struct ClientOptions {
    /// `None` follows without a cap; `Some(0)` returns redirects unfollowed.
    pub max_redirects: Option<u64>,
    /// Idle connections kept; `None` or `0` leaves the total uncapped.
    pub max_idle: Option<u64>,
    pub max_header_bytes: Option<u64>,
    pub idle_timeout: Option<Duration>,
    pub decompress: bool,
    pub cookies: bool,
    pub tls: TlsOptions,
}

// ------------------------------------------------------------------------ pool

struct Wire {
    conn: Rc<Connection>,
    /// Bytes read but not yet consumed.
    rbuf: Vec<u8>,
    rpos: usize,
    reused: bool,
    /// The HTTP/2 stream this wire stands for; `conn` is then the session's.
    h2: Option<H2Stream>,
}

thread_local! {
    static SCRATCH: Cell<Vec<u8>> = const { Cell::new(Vec::new()) };
}

impl Wire {
    fn new(conn: Rc<Connection>) -> Wire {
        Wire {
            conn,
            rbuf: Vec::new(),
            rpos: 0,
            reused: false,
            h2: None,
        }
    }

    fn for_stream(stream: H2Stream) -> Wire {
        let mut wire = Wire::new(stream.session().conn().clone());
        wire.h2 = Some(stream);
        wire
    }

    /// Gives up the wire: an HTTP/1 connection is closed, an HTTP/2 stream is
    /// cancelled by dropping it while the session lives on.
    fn discard(self) {
        if self.h2.is_none() {
            self.conn.close();
        }
    }

    fn pending(&self) -> &[u8] {
        &self.rbuf[self.rpos..]
    }

    fn consume(&mut self, n: usize) {
        self.rpos += n;
        if self.rpos == self.rbuf.len() {
            self.rbuf.clear();
            self.rpos = 0;
        }
    }

    /// Reads more input; `0` is end of stream. The read can park, so the shared scratch
    /// buffer is taken out for its duration: a request in another task that reads meanwhile
    /// gets a fresh buffer instead of finding this one borrowed.
    fn fill(&mut self, deadline: Deadline) -> Result<usize, IoErr> {
        let mut scratch = SCRATCH.take();
        scratch.resize(READ_BUF, 0);
        let got = self.conn.read_into(&mut scratch, deadline);
        if let Ok(n) = got {
            if self.rpos > 0 && self.rpos == self.rbuf.len() {
                self.rbuf.clear();
                self.rpos = 0;
            }
            self.rbuf.extend_from_slice(&scratch[..n]);
        }
        SCRATCH.set(scratch);
        got
    }
}

struct Idle {
    wire: Wire,
    since: Instant,
}

#[derive(Default)]
struct Pool {
    hosts: HashMap<String, Vec<Idle>>,
}

impl Pool {
    fn total(&self) -> usize {
        self.hosts.values().map(Vec::len).sum()
    }
}

// ---------------------------------------------------------------------- client

/// Internal failure kinds of one exchange.
enum Fail {
    Err(HttpErr),
    /// A reused connection died before any response byte.
    Stale,
    /// The server declined the stream without processing it.
    Refused,
}

/// A response head with the wire that carries its body, and whether the
/// request added `Accept-Encoding: gzip`.
type Exchanged = (ResponseHead, Wire, bool);

fn pump_fail(e: PumpErr) -> Fail {
    Fail::Err(match e {
        PumpErr::Timeout => HttpErr::Timeout,
        PumpErr::Closed => HttpErr::Closed,
        PumpErr::Failed(m) => HttpErr::Failed(m),
    })
}

/// Request names HTTP/2 forbids or the transport sets itself.
const H2_SKIPPED: [&str; 8] = [
    "host",
    "user-agent",
    "content-length",
    "connection",
    "proxy-connection",
    "keep-alive",
    "transfer-encoding",
    "upgrade",
];

/// The pseudo-headers and lowercase regular headers of an HTTP/2 request.
fn h2_request_headers(hop: &Hop<'_>, length: Option<usize>, gzip: bool) -> Vec<Header> {
    let mut out: Vec<Header> = vec![
        (b":method".to_vec(), hop.method.as_bytes().to_vec()),
        (b":scheme".to_vec(), hop.url.scheme.as_bytes().to_vec()),
        (
            b":authority".to_vec(),
            hop.url.authority.as_bytes().to_vec(),
        ),
        (b":path".to_vec(), hop.url.request_uri().into_bytes()),
    ];
    let agent = hop
        .headers
        .iter()
        .find(|(n, _)| n == "User-Agent")
        .map_or(USER_AGENT_H2.as_bytes(), |(_, v)| v.as_slice());
    out.push((b"user-agent".to_vec(), trim_value(agent).to_vec()));
    if let Some(n) = length
        && (n > 0 || matches!(hop.method, "POST" | "PUT" | "PATCH"))
    {
        out.push((b"content-length".to_vec(), n.to_string().into_bytes()));
    }
    let mut rest: Vec<(String, &[u8])> = hop
        .headers
        .iter()
        .map(|(n, v)| (n.to_ascii_lowercase(), trim_value(v)))
        .filter(|(n, v)| !H2_SKIPPED.contains(&n.as_str()) && (n != "te" || *v == b"trailers"))
        .collect();
    rest.sort_by(|a, b| a.0.cmp(&b.0));
    out.extend(rest.into_iter().map(|(n, v)| (n.into_bytes(), v.to_vec())));
    if gzip {
        out.push((b"accept-encoding".to_vec(), b"gzip".to_vec()));
    }
    out
}

/// The response head of an HTTP/2 header block.
fn h2_head(fields: Vec<Header>) -> Result<ResponseHead, Fail> {
    let mut status = None;
    let mut out = Vec::new();
    for (name, value) in fields {
        if name == b":status" {
            status = std::str::from_utf8(&value)
                .ok()
                .and_then(|t| t.parse::<u16>().ok());
        } else if !name.starts_with(b":") {
            out.push((String::from_utf8_lossy(&name).into_owned(), value));
        }
    }
    let Some(status) = status else {
        return Err(Fail::Err(HttpErr::Failed(
            "malformed HTTP status code".into(),
        )));
    };
    Ok(ResponseHead {
        status,
        minor: 0,
        fields: out,
        length: 0,
    })
}

impl From<HttpErr> for Fail {
    fn from(e: HttpErr) -> Fail {
        Fail::Err(e)
    }
}

/// A reusable HTTP client owned by a network.
pub struct Client {
    owner: Rc<Network>,
    opts: ClientOptions,
    tls: Option<Arc<ClientConfig>>,
    jar: RefCell<Option<Jar>>,
    pool: RefCell<Pool>,
    /// HTTP/2 sessions by origin; they multiplex and are never idle-pooled.
    sessions: RefCell<HashMap<String, Rc<Session>>>,
    /// Test only: speak HTTP/2 on cleartext connections, with these settings.
    #[cfg(test)]
    h2_prior: RefCell<Option<crate::h2::Settings>>,
    closed: Cell<bool>,
    bodies: RefCell<Vec<Weak<ResponseBody>>>,
    /// One-shot clients send `Connection: close` and never pool.
    single_use: bool,
}

impl Resource for Client {
    fn close_resource(&self) {
        self.close();
    }
}

impl Client {
    /// A pooled client. Option errors are `InvalidInput`.
    pub fn new(owner: &Rc<Network>, opts: ClientOptions) -> Result<Rc<Client>, HttpErr> {
        if opts.max_header_bytes == Some(0) {
            return Err(HttpErr::InvalidInput);
        }
        let mut tls_options = opts.tls.clone();
        let h2 = tls_options.alpn.iter().any(|p| p == "h2");
        tls_options.alpn = if h2 {
            vec!["h2".to_string(), "http/1.1".to_string()]
        } else {
            vec!["http/1.1".to_string()]
        };
        let config = tls::client_config(&tls_options, false).map_err(|_| HttpErr::InvalidInput)?;
        let client = Rc::new(Client {
            owner: owner.clone(),
            jar: RefCell::new(opts.cookies.then(Jar::new)),
            opts,
            tls: Some(config),
            pool: RefCell::new(Pool::default()),
            sessions: RefCell::new(HashMap::new()),
            #[cfg(test)]
            h2_prior: RefCell::new(None),
            closed: Cell::new(false),
            bodies: RefCell::new(Vec::new()),
            single_use: false,
        });
        let as_resource: Rc<dyn Resource> = client.clone();
        if !owner.own(&as_resource) {
            return Err(HttpErr::Closed);
        }
        Ok(client)
    }

    /// The client behind `Network.request`: no pool, redirects, cookies,
    /// proxies or compression.
    pub fn one_shot(owner: &Rc<Network>) -> Result<Rc<Client>, HttpErr> {
        let tls_options = TlsOptions {
            alpn: vec!["http/1.1".to_string()],
            ..TlsOptions::default()
        };
        let config = tls::client_config(&tls_options, false).map_err(|_| HttpErr::InvalidInput)?;
        Ok(Rc::new(Client {
            owner: owner.clone(),
            opts: ClientOptions {
                max_redirects: Some(0),
                ..ClientOptions::default()
            },
            tls: Some(config),
            jar: RefCell::new(None),
            pool: RefCell::new(Pool::default()),
            sessions: RefCell::new(HashMap::new()),
            #[cfg(test)]
            h2_prior: RefCell::new(None),
            closed: Cell::new(false),
            bodies: RefCell::new(Vec::new()),
            single_use: true,
        }))
    }

    pub fn network(&self) -> &Rc<Network> {
        &self.owner
    }

    pub fn is_closed(&self) -> bool {
        self.closed.get() || self.owner.is_closed()
    }

    /// Cancels open response bodies and drops idle connections. Idempotent.
    pub fn close(&self) {
        if self.closed.replace(true) {
            return;
        }
        let bodies: Vec<_> = self.bodies.borrow_mut().drain(..).collect();
        for body in bodies.iter().filter_map(Weak::upgrade) {
            body.close();
        }
        self.drop_idle();
        let sessions: Vec<_> = self.sessions.borrow_mut().drain().collect();
        for (_, session) in sessions {
            session.close();
        }
    }

    fn drop_idle(&self) {
        let hosts: Vec<_> = self.pool.borrow_mut().hosts.drain().collect();
        for (_, list) in hosts {
            for idle in list {
                idle.wire.conn.close();
            }
        }
    }

    fn pool_key(url: &Url) -> String {
        format!(
            "{}://{}",
            url.scheme,
            url.dial_address().to_ascii_lowercase()
        )
    }

    fn take_idle(&self, key: &str) -> Option<Wire> {
        let mut pool = self.pool.borrow_mut();
        let list = pool.hosts.get_mut(key)?;
        while let Some(idle) = list.pop() {
            let expired = self
                .opts
                .idle_timeout
                .is_some_and(|t| !t.is_zero() && idle.since.elapsed() > t);
            if expired || idle.wire.conn.is_stale() || !idle.wire.pending().is_empty() {
                idle.wire.conn.close();
                continue;
            }
            let mut wire = idle.wire;
            wire.reused = true;
            return Some(wire);
        }
        None
    }

    fn put_idle(&self, key: String, wire: Wire) {
        if self.single_use || self.is_closed() || wire.conn.is_closed() {
            wire.conn.close();
            return;
        }
        let total_cap = self.opts.max_idle.filter(|&n| n > 0).map(|n| n as usize);
        let host_cap = total_cap.unwrap_or(DEFAULT_IDLE_PER_HOST);
        let mut pool = self.pool.borrow_mut();
        let list = pool.hosts.entry(key).or_default();
        list.push(Idle {
            wire,
            since: Instant::now(),
        });
        while list.len() > host_cap {
            list.remove(0).wire.conn.close();
        }
        if let Some(cap) = total_cap {
            while pool.total() > cap {
                let oldest = pool
                    .hosts
                    .iter()
                    .filter_map(|(k, l)| l.first().map(|i| (k.clone(), i.since)))
                    .min_by_key(|(_, since)| *since);
                let Some((key, _)) = oldest else { break };
                if let Some(list) = pool.hosts.get_mut(&key) {
                    list.remove(0).wire.conn.close();
                }
            }
        }
        pool.hosts.retain(|_, l| !l.is_empty());
    }

    /// Maps a failure to the error a request reports.
    fn describe(&self, deadline: Deadline, e: HttpErr) -> HttpErr {
        rt::check_cancel();
        if self.is_closed() {
            return HttpErr::Closed;
        }
        if deadline.expired() {
            return HttpErr::Timeout;
        }
        e
    }

    // ------------------------------------------------------------------ sending

    /// Sends `request`, following redirects as configured, and returns the
    /// streaming response.
    pub fn send(self: &Rc<Self>, request: Request) -> Result<Rc<ResponseBody>, HttpErr> {
        let deadline = request.deadline;
        self.send_inner(request)
            .map_err(|e| self.describe(deadline, e))
    }

    fn send_inner(self: &Rc<Self>, request: Request) -> Result<Rc<ResponseBody>, HttpErr> {
        let Request {
            mut method,
            url: first_url,
            headers: initial,
            mut body,
            max_response,
            deadline,
        } = request;
        let mut url = first_url.clone();
        let mut previous = first_url.clone();
        let mut sent = 0u64;
        let mut hop_headers = initial.clone();
        loop {
            if self.is_closed() {
                return Err(HttpErr::Closed);
            }
            let mut hop = Hop {
                method: &method,
                url: &url,
                headers: self.with_cookies(&url, &hop_headers),
                body: &mut body,
            };
            let (head, wire, key, added_gzip) = self.roundtrip(&mut hop, deadline)?;
            self.store_cookies(&url, &head);
            let redirect = self.redirect_target(&method, &url, &head, &body, sent)?;
            let Some((next_method, next_url, keep_body)) = redirect else {
                return self.deliver(head, wire, key, &method, max_response, deadline, added_gzip);
            };
            // Read a little of the body so a small one lets the connection be
            // reused, then drop it.
            self.discard(head, wire, key, &method, deadline);
            sent += 1;
            let mut next_headers = self.redirect_headers(&initial, &previous, &url, &next_url);
            if let Some(referer) = referer_for(&url, &next_url, &initial) {
                set_header(&mut next_headers, "Referer", referer.into_bytes());
            }
            if !keep_body {
                body = Body::Bytes(Rc::new(Vec::new()));
            }
            hop_headers = next_headers;
            method = next_method;
            previous = url;
            url = next_url;
        }
    }

    fn with_cookies(&self, url: &Url, headers: &[(String, Vec<u8>)]) -> Vec<(String, Vec<u8>)> {
        let mut out = headers.to_vec();
        let mut jar = self.jar.borrow_mut();
        let Some(jar) = jar.as_mut() else { return out };
        let cookies = jar.cookies(&url.scheme, &url.host, &url.path);
        if cookies.is_empty() {
            return out;
        }
        let joined = cookies.join("; ");
        match out.iter().position(|(n, _)| n == "Cookie") {
            Some(at) => {
                let mut value = out[at].1.clone();
                value.extend_from_slice(b"; ");
                value.extend_from_slice(joined.as_bytes());
                out.retain(|(n, _)| n != "Cookie");
                out.insert(at.min(out.len()), ("Cookie".into(), value));
            }
            None => out.push(("Cookie".into(), joined.into_bytes())),
        }
        out
    }

    fn store_cookies(&self, url: &Url, head: &ResponseHead) {
        let mut jar = self.jar.borrow_mut();
        let Some(jar) = jar.as_mut() else { return };
        let lines: Vec<String> = head
            .fields
            .iter()
            .filter(|(n, _)| n.eq_ignore_ascii_case("Set-Cookie"))
            .filter_map(|(_, v)| String::from_utf8(v.clone()).ok())
            .collect();
        if !lines.is_empty() {
            jar.set_cookies(&url.scheme, &url.host, &url.path, &lines);
        }
    }

    /// The next request when `head` redirects and the client follows it.
    fn redirect_target(
        &self,
        method: &str,
        url: &Url,
        head: &ResponseHead,
        body: &Body,
        followed: u64,
    ) -> Result<Option<(String, Url, bool)>, HttpErr> {
        let (next_method, keep_body) = match head.status {
            301..=303 => (
                if method == "HEAD" { "HEAD" } else { "GET" }.to_string(),
                false,
            ),
            307 | 308 => (method.to_string(), true),
            _ => return Ok(None),
        };
        let Some((_, location)) = head
            .fields
            .iter()
            .find(|(n, _)| n.eq_ignore_ascii_case("Location"))
        else {
            return Ok(None);
        };
        if keep_body && matches!(body, Body::Stream(_)) {
            return Ok(None);
        }
        // A streamed upload cannot be replayed, and zero redirects returns the
        // response itself.
        if self.opts.max_redirects == Some(0) || matches!(body, Body::Stream(_)) {
            return Ok(None);
        }
        let text = String::from_utf8_lossy(location).into_owned();
        let Some(next) = url.resolve(&text) else {
            return Err(location_error(&text));
        };
        if self.opts.max_redirects.is_some_and(|max| followed >= max) {
            return Err(HttpErr::Failed("redirect limit exceeded".into()));
        }
        if url.is_https() && !next.is_https() {
            return Err(HttpErr::Failed("TLS downgrade redirect rejected".into()));
        }
        if !self.owner.host_allowed(&next.host) {
            return Err(HttpErr::Failed("network policy denied redirect".into()));
        }
        Ok(Some((next_method, next, keep_body)))
    }

    /// Headers of a redirected request: the caller's own, minus the credentials
    /// that must not leave the origin.
    fn redirect_headers(
        &self,
        initial: &[(String, Vec<u8>)],
        previous: &Url,
        old: &Url,
        next: &Url,
    ) -> Vec<(String, Vec<u8>)> {
        let subdomain = is_domain_or_subdomain(&next.host, &previous.host);
        let same_origin = next.same_origin(old);
        initial
            .iter()
            .filter(|(name, _)| {
                let sensitive = matches!(
                    name.as_str(),
                    "Authorization" | "Www-Authenticate" | "Cookie" | "Cookie2"
                );
                !(sensitive && !subdomain)
            })
            .filter(|(name, _)| {
                !(!same_origin
                    && matches!(
                        name.as_str(),
                        "Authorization" | "Cookie" | "Proxy-Authorization"
                    ))
            })
            .cloned()
            .collect()
    }

    fn discard(
        self: &Rc<Self>,
        head: ResponseHead,
        wire: Wire,
        key: String,
        method: &str,
        deadline: Deadline,
    ) {
        let mut state = BodyState::start(head, wire, key, method, false, u64::MAX);
        let mut taken = 0;
        while taken < SLURP {
            match state.next_raw(deadline, 4096) {
                Ok(Some(chunk)) => taken += chunk.len(),
                _ => break,
            }
        }
        state.finish(self);
    }

    #[allow(clippy::too_many_arguments)]
    fn deliver(
        self: &Rc<Self>,
        head: ResponseHead,
        wire: Wire,
        key: String,
        method: &str,
        max_response: u64,
        deadline: Deadline,
        added_gzip: bool,
    ) -> Result<Rc<ResponseBody>, HttpErr> {
        let status = head.status;
        let protocol = if wire.h2.is_some() {
            "HTTP/2.0".to_string()
        } else {
            format!("HTTP/1.{}", head.minor)
        };
        let gzip = added_gzip
            && head
                .fields
                .iter()
                .find(|(n, _)| n.eq_ignore_ascii_case("Content-Encoding"))
                .is_some_and(|(_, v)| v.eq_ignore_ascii_case(b"gzip"));
        let mut fields = head.fields.clone();
        let mut state = BodyState::start(head, wire, key, method, gzip, max_response);
        let gzip = state.gzip.is_some();
        if gzip {
            fields.retain(|(n, _)| {
                !n.eq_ignore_ascii_case("Content-Encoding")
                    && !n.eq_ignore_ascii_case("Content-Length")
            });
        }
        let received = Headers::from_received(fields);
        if !received.is_text() {
            state.abandon();
            return Err(HttpErr::InvalidData);
        }
        let state = if state.done {
            state.finish(self);
            None
        } else {
            Some(state)
        };
        let body = Rc::new(ResponseBody {
            client: Rc::downgrade(self),
            status,
            headers: Rc::new(RefCell::new(received)),
            protocol,
            state: RefCell::new(state),
            reading: Cell::new(false),
            deadline,
            closed: Cell::new(false),
        });
        if self.is_closed() {
            body.close();
            return Err(HttpErr::Closed);
        }
        let as_resource: Rc<dyn Resource> = body.clone();
        if !self.owner.own(&as_resource) {
            body.close();
            return Err(HttpErr::Closed);
        }
        let mut bodies = self.bodies.borrow_mut();
        if bodies.len() >= 64 && bodies.len().is_power_of_two() {
            bodies.retain(|w| w.strong_count() > 0);
        }
        bodies.push(Rc::downgrade(&body));
        Ok(body)
    }

    // --------------------------------------------------------------- one request

    /// Sends one request on a pooled or new connection and reads the final
    /// response head.
    fn roundtrip(
        &self,
        hop: &mut Hop<'_>,
        deadline: Deadline,
    ) -> Result<(ResponseHead, Wire, String, bool), HttpErr> {
        let key = Self::pool_key(hop.url);
        let replayable = matches!(hop.body, Body::Bytes(_))
            && matches!(hop.method, "GET" | "HEAD" | "OPTIONS" | "TRACE");
        let mut retried = false;
        loop {
            if deadline.expired() {
                return Err(HttpErr::Timeout);
            }
            let (outcome, reused) = self.attempt(&key, hop, deadline)?;
            match outcome {
                Ok((head, wire, added_gzip)) => return Ok((head, wire, key, added_gzip)),
                Err(Fail::Stale) if reused && !retried && replayable => retried = true,
                // The server did not process a refused stream: any request
                // whose body can be sent again may follow.
                Err(Fail::Refused) if !retried && matches!(hop.body, Body::Bytes(_)) => {
                    retried = true;
                }
                Err(Fail::Stale | Fail::Refused) => {
                    return Err(HttpErr::Failed(
                        "connection closed before the exchange completed".into(),
                    ));
                }
                Err(Fail::Err(e)) => return Err(e),
            }
        }
    }

    /// One try on a live session, a pooled connection or a new one; whether
    /// the connection had served before comes second.
    fn attempt(
        &self,
        key: &str,
        hop: &mut Hop<'_>,
        deadline: Deadline,
    ) -> Result<(Result<Exchanged, Fail>, bool), HttpErr> {
        if let Some(session) = self.live_session(key) {
            return Ok((self.exchange_h2(&session, hop, deadline), true));
        }
        let wire = match self.take_idle(key) {
            Some(wire) => wire,
            None => self.dial(hop.url, deadline)?,
        };
        if let Some(session) = self.h2_session(key, &wire, hop.url) {
            return Ok((self.exchange_h2(&session, hop, deadline), false));
        }
        let reused = wire.reused;
        Ok((self.exchange_h1(wire, hop, deadline), reused))
    }

    fn exchange_h1(
        &self,
        mut wire: Wire,
        hop: &mut Hop<'_>,
        deadline: Deadline,
    ) -> Result<Exchanged, Fail> {
        // A cancellation leaves by a jump that skips `wire`'s drop; close its connection so the
        // descriptor is released.
        let conn = wire.conn.clone();
        match with_cleanup(&mut || conn.close(), || {
            self.exchange(&mut wire, hop, deadline)
        }) {
            Ok((head, added_gzip)) => Ok((head, wire, added_gzip)),
            Err(fail) => {
                wire.discard();
                Err(fail)
            }
        }
    }

    fn dial(&self, url: &Url, deadline: Deadline) -> Result<Wire, HttpErr> {
        let address = url.dial_address();
        let tls = match (&self.tls, url.is_https()) {
            (Some(config), true) => Some((config, url.host.as_str())),
            _ => None,
        };
        let conn = self
            .owner
            .dial_stream(&address, tls, deadline)
            .map_err(HttpErr::from)?;
        Ok(Wire::new(conn))
    }

    // ------------------------------------------------------------------- HTTP/2

    /// The session for `key` while it can take new requests.
    fn live_session(&self, key: &str) -> Option<Rc<Session>> {
        let mut sessions = self.sessions.borrow_mut();
        let session = sessions.get(key)?;
        let expired = self
            .opts
            .idle_timeout
            .is_some_and(|t| !t.is_zero() && session.idle_for().is_some_and(|idle| idle > t));
        if session.usable() && !expired {
            return Some(session.clone());
        }
        let stale = sessions.remove(key)?;
        drop(sessions);
        stale.close();
        None
    }

    /// Settings for a session over cleartext (tests) or ALPN-negotiated TLS.
    fn h2_settings(&self, wire: &Wire, url: &Url) -> Option<crate::h2::Settings> {
        #[cfg(test)]
        if !url.is_https() {
            return self.h2_prior.borrow().clone();
        }
        let negotiated = url.is_https() && wire.conn.tls_info().is_ok_and(|info| info.alpn == "h2");
        negotiated.then(|| h2client::client_settings(self.opts.max_header_bytes))
    }

    /// Turns a freshly dialed connection into a session when it speaks h2.
    fn h2_session(&self, key: &str, wire: &Wire, url: &Url) -> Option<Rc<Session>> {
        let settings = self.h2_settings(wire, url)?;
        let session = Session::new(wire.conn.clone(), settings);
        self.sessions
            .borrow_mut()
            .insert(key.to_string(), session.clone());
        Some(session)
    }

    fn exchange_h2(
        &self,
        session: &Rc<Session>,
        hop: &mut Hop<'_>,
        deadline: Deadline,
    ) -> Result<Exchanged, Fail> {
        let wants_gzip = self.wants_gzip(hop);
        let length = match &*hop.body {
            Body::Bytes(bytes) => Some(bytes.len()),
            Body::Stream(_) => None,
        };
        let headers = h2_request_headers(hop, length, wants_gzip);
        let end = length == Some(0);
        let stream = loop {
            if deadline.expired() {
                return Err(Fail::Err(HttpErr::Timeout));
            }
            match session.open(headers.clone(), end) {
                Ok(stream) => break stream,
                Err(OpenErr::Unavailable) => return Err(Fail::Stale),
                Err(OpenErr::Invalid(m)) => return Err(Fail::Err(HttpErr::Failed(m))),
                Err(OpenErr::Full) => session.pump(deadline).map_err(pump_fail)?,
            }
        };
        stream.session().flush(deadline).map_err(pump_fail)?;
        if !end {
            self.upload_h2(&stream, hop.body, deadline)?;
        }
        let head = loop {
            match stream.poll_head() {
                Poll::Head(fields) => break h2_head(fields)?,
                Poll::Refused => return Err(Fail::Refused),
                Poll::Reset(code) => {
                    let text = h2client::reset_text(stream.id, code);
                    return Err(Fail::Err(HttpErr::Failed(text)));
                }
                Poll::Dead => return Err(Fail::Stale),
                _ => stream.pump(deadline).map_err(pump_fail)?,
            }
        };
        Ok((head, Wire::for_stream(stream), wants_gzip))
    }

    fn upload_h2(
        &self,
        stream: &H2Stream,
        body: &mut Body,
        deadline: Deadline,
    ) -> Result<(), Fail> {
        let source = match body {
            Body::Bytes(bytes) => {
                self.send_h2(stream, bytes, true, deadline)?;
                return Ok(());
            }
            Body::Stream(source) => source,
        };
        loop {
            rt::check_cancel();
            let piece = source
                .next(32 * 1024)
                .map_err(|m| Fail::Err(HttpErr::Failed(m)))?;
            let Some(data) = piece else {
                self.send_h2(stream, &[], true, deadline)?;
                return Ok(());
            };
            if data.is_empty() {
                return Err(Fail::Err(HttpErr::Failed(
                    "source stream violated chunk bound".into(),
                )));
            }
            if !self.send_h2(stream, &data, false, deadline)? {
                return Ok(());
            }
        }
    }

    /// Sends `data` as flow control allows; `false` when the stream went away
    /// first (the response, or its failure, is then read as usual).
    fn send_h2(
        &self,
        stream: &H2Stream,
        data: &[u8],
        end: bool,
        deadline: Deadline,
    ) -> Result<bool, Fail> {
        if data.is_empty() {
            if end {
                stream.send(&[], true);
                stream.session().flush(deadline).map_err(pump_fail)?;
            }
            return Ok(true);
        }
        let mut sent = 0;
        while sent < data.len() {
            if !stream.alive() {
                return Ok(false);
            }
            let n = stream.send(&data[sent..], end);
            sent += n;
            stream.session().flush(deadline).map_err(pump_fail)?;
            if n == 0 {
                stream.pump(deadline).map_err(pump_fail)?;
            }
        }
        Ok(true)
    }

    fn wants_gzip(&self, hop: &Hop<'_>) -> bool {
        self.opts.decompress
            && hop.method != "HEAD"
            && !has_header(&hop.headers, "Accept-Encoding")
            && !has_header(&hop.headers, "Range")
    }

    fn exchange(
        &self,
        wire: &mut Wire,
        hop: &mut Hop<'_>,
        deadline: Deadline,
    ) -> Result<(ResponseHead, bool), Fail> {
        let wants_gzip = self.wants_gzip(hop);
        let mut out = Vec::with_capacity(512);
        let length = match &*hop.body {
            Body::Bytes(bytes) => Some(bytes.len()),
            Body::Stream(_) => None,
        };
        encode_head(
            &mut out,
            hop.method,
            hop.url,
            &hop.headers,
            length,
            wants_gzip,
            self.single_use,
        );
        match &mut *hop.body {
            Body::Bytes(bytes) => {
                if bytes.len() <= READ_BUF {
                    out.extend_from_slice(bytes);
                    self.write(wire, &out, deadline)?;
                } else {
                    self.write(wire, &out, deadline)?;
                    self.write(wire, bytes, deadline)?;
                }
            }
            Body::Stream(source) => {
                self.write(wire, &out, deadline)?;
                self.stream_body(wire, &mut **source, deadline)?;
            }
        }
        let head = self.read_head(wire, deadline)?;
        Ok((head, wants_gzip))
    }

    fn write(&self, wire: &mut Wire, data: &[u8], deadline: Deadline) -> Result<(), Fail> {
        wire.conn.write_until(data, deadline).map_err(|e| match e {
            IoErr::Closed => Fail::Err(HttpErr::Closed),
            IoErr::Failed(m) if m == "operation timed out" => Fail::Err(HttpErr::Timeout),
            other => Fail::Err(HttpErr::Failed(io_text(other))),
        })
    }

    fn stream_body(
        &self,
        wire: &mut Wire,
        source: &mut dyn Source,
        deadline: Deadline,
    ) -> Result<(), Fail> {
        loop {
            rt::check_cancel();
            let piece = source
                .next(32 * 1024)
                .map_err(|m| Fail::Err(HttpErr::Failed(m)))?;
            let mut out = Vec::new();
            match piece {
                Some(data) if !data.is_empty() => h1::chunk(&mut out, &data),
                Some(_) => {
                    return Err(Fail::Err(HttpErr::Failed(
                        "source stream violated chunk bound".into(),
                    )));
                }
                None => {
                    out.extend_from_slice(h1::LAST_CHUNK);
                    return self.write(wire, &out, deadline);
                }
            }
            self.write(wire, &out, deadline)?;
        }
    }

    fn read_head(&self, wire: &mut Wire, deadline: Deadline) -> Result<ResponseHead, Fail> {
        let limit = self
            .opts
            .max_header_bytes
            .map_or(usize::MAX, |n| n.min(usize::MAX as u64) as usize);
        let mut read_any = false;
        loop {
            match h1::parse_response(wire.pending(), limit) {
                Parsed::Complete(head) => {
                    wire.consume(head.length);
                    if (100..200).contains(&head.status) && head.status != 101 {
                        continue;
                    }
                    return Ok(head);
                }
                Parsed::Bad(bad) => {
                    let text = if bad.reason == "too many response header fields" {
                        format!(
                            "http: server response has more than {} header fields; aborted",
                            h1::MAX_FIELDS
                        )
                    } else if bad.reason == "response headers too large" {
                        format!("http: server response headers exceeded {limit} bytes; aborted")
                    } else {
                        let line = wire
                            .pending()
                            .split(|&b| b == b'\n')
                            .next()
                            .unwrap_or_default();
                        let line = String::from_utf8_lossy(line);
                        format!(
                            "malformed HTTP response {}",
                            crate::error::go_quote(line.trim_end())
                        )
                    };
                    return Err(Fail::Err(HttpErr::Failed(text)));
                }
                Parsed::Partial => {}
            }
            let n = wire.fill(deadline).map_err(|e| match e {
                IoErr::Closed => Fail::Err(HttpErr::Closed),
                IoErr::Failed(m) if m == "operation timed out" => Fail::Err(HttpErr::Timeout),
                other => Fail::Err(HttpErr::Failed(io_text(other))),
            })?;
            if n == 0 {
                if !read_any && wire.pending().is_empty() {
                    return Err(Fail::Stale);
                }
                return Err(Fail::Err(HttpErr::Failed(
                    "connection closed before the exchange completed".into(),
                )));
            }
            read_any = true;
        }
    }
}

fn io_text(e: IoErr) -> String {
    match e {
        IoErr::Failed(m) => m,
        _ => "i/o error".to_string(),
    }
}

/// One request on the wire: the pieces that vary per redirect hop.
struct Hop<'a> {
    method: &'a str,
    url: &'a Url,
    headers: Vec<(String, Vec<u8>)>,
    body: &'a mut Body,
}

fn has_header(headers: &[(String, Vec<u8>)], name: &str) -> bool {
    headers.iter().any(|(n, _)| n.eq_ignore_ascii_case(name))
}

fn set_header(headers: &mut Vec<(String, Vec<u8>)>, name: &str, value: Vec<u8>) {
    headers.retain(|(n, _)| !n.eq_ignore_ascii_case(name));
    headers.push((name.to_string(), value));
}

fn trim_value(value: &[u8]) -> &[u8] {
    let start = value
        .iter()
        .position(|&b| b != b' ' && b != b'\t')
        .unwrap_or(value.len());
    let end = value
        .iter()
        .rposition(|&b| b != b' ' && b != b'\t')
        .map_or(start, |i| i + 1);
    &value[start..end]
}

/// Request line and headers in wire order: `Host`, `User-Agent`, body framing,
/// the caller's headers sorted by name, then the transport's own.
fn encode_head(
    out: &mut Vec<u8>,
    method: &str,
    url: &Url,
    headers: &[(String, Vec<u8>)],
    length: Option<usize>,
    gzip: bool,
    close: bool,
) {
    out.extend_from_slice(method.as_bytes());
    out.push(b' ');
    out.extend_from_slice(url.request_uri().as_bytes());
    out.extend_from_slice(b" HTTP/1.1\r\n");
    h1::header_line(out, "Host", url.authority.as_bytes());
    let agent = headers
        .iter()
        .find(|(n, _)| n == "User-Agent")
        .map_or(USER_AGENT.as_bytes(), |(_, v)| v.as_slice());
    h1::header_line(out, "User-Agent", trim_value(agent));
    match length {
        Some(n) if n > 0 || matches!(method, "POST" | "PUT" | "PATCH") => {
            h1::header_line(out, "Content-Length", n.to_string().as_bytes());
        }
        Some(_) => {}
        None => h1::header_line(out, "Transfer-Encoding", b"chunked"),
    }
    let mut rest: Vec<&(String, Vec<u8>)> = headers
        .iter()
        .filter(|(n, _)| n != "Host" && n != "User-Agent")
        .collect();
    rest.sort_by(|a, b| a.0.cmp(&b.0));
    for (name, value) in rest {
        h1::header_line(out, name, trim_value(value));
    }
    if gzip {
        h1::header_line(out, "Accept-Encoding", b"gzip");
    }
    if close {
        h1::header_line(out, "Connection", b"close");
    }
    out.extend_from_slice(b"\r\n");
}

fn is_domain_or_subdomain(sub: &str, parent: &str) -> bool {
    let (sub, parent) = (sub.to_ascii_lowercase(), parent.to_ascii_lowercase());
    if sub == parent {
        return true;
    }
    // An IP literal only matches itself.
    if sub.parse::<std::net::IpAddr>().is_ok() || parent.parse::<std::net::IpAddr>().is_ok() {
        return false;
    }
    sub.len() > parent.len()
        && sub.ends_with(&parent)
        && sub.as_bytes()[sub.len() - parent.len() - 1] == b'.'
}

/// `Referer` for a redirected request; none when leaving HTTPS for HTTP.
fn referer_for(last: &Url, next: &Url, initial: &[(String, Vec<u8>)]) -> Option<String> {
    if last.is_https() && !next.is_https() {
        return None;
    }
    if let Some((_, explicit)) = initial.iter().find(|(n, _)| n == "Referer")
        && !explicit.is_empty()
    {
        return Some(String::from_utf8_lossy(explicit).into_owned());
    }
    Some(last.text())
}

fn location_error(location: &str) -> HttpErr {
    HttpErr::Failed(format!(
        "failed to parse Location header {}: invalid redirect target",
        crate::error::go_quote(location)
    ))
}

// ----------------------------------------------------------------- response body

/// Bounded gzip output: writing past the cap fails.
struct Sink {
    buf: Vec<u8>,
    room: usize,
}

impl Write for Sink {
    fn write(&mut self, data: &[u8]) -> std::io::Result<usize> {
        if data.len() > self.room {
            return Err(std::io::Error::other("response body limit exceeded"));
        }
        self.room -= data.len();
        self.buf.extend_from_slice(data);
        Ok(data.len())
    }

    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}

struct BodyState {
    wire: Option<Wire>,
    key: String,
    decoder: BodyDecoder,
    keep_alive: bool,
    gzip: Option<GzDecoder<Sink>>,
    /// Compressed bytes not yet fed to the decoder.
    gz_in: Vec<u8>,
    /// Decoded bytes not yet delivered.
    ready: Vec<u8>,
    ready_pos: usize,
    remaining: u64,
    done: bool,
    wire_eof: bool,
}

impl BodyState {
    /// Starts a body; `None` for a message without one (the connection goes
    /// back to the caller's pool through `finish`).
    fn start(
        head: ResponseHead,
        wire: Wire,
        key: String,
        method: &str,
        gzip: bool,
        remaining: u64,
    ) -> BodyState {
        let framing = match &wire.h2 {
            Some(stream) => h2_framing(&head, method, stream),
            None => h1::response_framing(&head, method).unwrap_or(Framing::UntilClose),
        };
        let keep_alive = wire.h2.is_none()
            && h1::keep_alive(head.minor, &head.fields)
            && framing != Framing::UntilClose;
        let empty = matches!(framing, Framing::None | Framing::Length(0));
        let gzip = gzip && !empty;
        BodyState {
            wire: Some(wire),
            key,
            decoder: BodyDecoder::new(framing),
            keep_alive,
            gzip: gzip.then(|| {
                GzDecoder::new(Sink {
                    buf: Vec::new(),
                    room: 0,
                })
            }),
            gz_in: Vec::new(),
            ready: Vec::new(),
            ready_pos: 0,
            remaining,
            done: empty,
            wire_eof: false,
        }
    }

    fn abandon(&mut self) {
        if let Some(wire) = self.wire.take() {
            wire.discard();
        }
    }

    /// Returns the connection to the pool when the exchange ended cleanly.
    fn finish(mut self, client: &Client) {
        let Some(wire) = self.wire.take() else { return };
        if self.done && self.keep_alive && wire.pending().is_empty() && !self.wire_eof {
            client.put_idle(self.key.clone(), wire);
        } else {
            wire.discard();
        }
    }

    /// Decodes up to `max` raw body bytes (no decompression, no budget).
    fn next_raw(&mut self, deadline: Deadline, max: usize) -> Result<Option<Vec<u8>>, IoErr> {
        let mut out = Vec::new();
        loop {
            if !out.is_empty() {
                return Ok(Some(out));
            }
            if self.done {
                return Ok(None);
            }
            let Some(wire) = self.wire.as_mut() else {
                return Err(IoErr::Closed);
            };
            if let Some(stream) = &wire.h2 {
                let (chunk, done) = h2_next(stream, deadline, max)?;
                self.done = done;
                return Ok(chunk);
            }
            if wire.pending().is_empty() {
                let n = wire.fill(deadline).map_err(|e| match e {
                    IoErr::Failed(m) if m == "operation timed out" => {
                        IoErr::Failed("context deadline exceeded".into())
                    }
                    other => other,
                })?;
                if n == 0 {
                    self.wire_eof = true;
                    if self.decoder.finish_on_eof() {
                        self.done = true;
                        return Ok(None);
                    }
                    return Err(IoErr::Failed(
                        "connection closed before the exchange completed".into(),
                    ));
                }
            }
            let take = wire.pending().len().min(max.max(1));
            let (used, progress) = self
                .decoder
                .feed(&wire.pending()[..take], &mut out)
                .map_err(|m| IoErr::Failed(m.to_string()))?;
            wire.consume(used);
            if progress == Decoded::Done {
                self.done = true;
            }
        }
    }

    /// Fills `ready` with at least one decoded byte, or leaves it empty at the
    /// end of the body.
    fn produce(&mut self, deadline: Deadline) -> Result<(), IoErr> {
        if self.gzip.is_none() {
            if let Some(chunk) = self.next_raw(deadline, READ_BUF)? {
                self.ready = chunk;
                self.ready_pos = 0;
            }
            return Ok(());
        }
        loop {
            if self.gz_in.is_empty() {
                match self.next_raw(deadline, READ_BUF)? {
                    Some(chunk) => self.gz_in = chunk,
                    None => {
                        let room = self.room();
                        let dec = self.gzip.as_mut().expect("gzip state");
                        dec.get_mut().room = room;
                        dec.try_finish().map_err(gzip_error)?;
                        self.ready = std::mem::take(&mut dec.get_mut().buf);
                        self.ready_pos = 0;
                        self.gzip = None;
                        return Ok(());
                    }
                }
            }
            let step = self.gz_in.len().min(4096);
            let room = self.room();
            let input: Vec<u8> = self.gz_in.drain(..step).collect();
            let dec = self.gzip.as_mut().expect("gzip state");
            dec.get_mut().room = room;
            dec.write_all(&input).map_err(gzip_error)?;
            self.ready = std::mem::take(&mut dec.get_mut().buf);
            self.ready_pos = 0;
            if !self.ready.is_empty() {
                return Ok(());
            }
        }
    }

    /// Decoded bytes one more step may add before the budget is exceeded.
    fn room(&self) -> usize {
        let pending = self.ready.len() - self.ready_pos.min(self.ready.len());
        (self.remaining.saturating_add(1) as usize).saturating_sub(pending)
    }
}

/// Takes body bytes from an HTTP/2 stream, pumping its session as needed; the
/// flag says the body is complete.
fn h2_next(
    stream: &H2Stream,
    deadline: Deadline,
    max: usize,
) -> Result<(Option<Vec<u8>>, bool), IoErr> {
    loop {
        match stream.poll_data(max.max(1)) {
            Poll::Data(chunk) => return Ok((Some(chunk), stream.drained())),
            Poll::End => return Ok((None, true)),
            Poll::Reset(code) => {
                return Err(IoErr::Failed(h2client::reset_text(stream.id, code)));
            }
            Poll::Pending => stream.pump(deadline).map_err(|e| match e {
                PumpErr::Timeout => IoErr::Failed("context deadline exceeded".into()),
                PumpErr::Closed => IoErr::Closed,
                PumpErr::Failed(m) => IoErr::Failed(m),
            })?,
            _ => {
                return Err(IoErr::Failed(
                    "connection closed before the exchange completed".into(),
                ));
            }
        }
    }
}

/// Body framing of an HTTP/2 response: it ends with the stream.
fn h2_framing(head: &ResponseHead, method: &str, stream: &H2Stream) -> Framing {
    let bodiless = method.eq_ignore_ascii_case("HEAD") || matches!(head.status, 204 | 304);
    if bodiless || stream.drained() {
        Framing::None
    } else {
        Framing::UntilClose
    }
}

fn gzip_error(e: std::io::Error) -> IoErr {
    if e.to_string() == "response body limit exceeded" {
        return IoErr::Failed("response body limit exceeded".into());
    }
    match e.kind() {
        std::io::ErrorKind::UnexpectedEof => {
            IoErr::Failed("connection closed before the exchange completed".into())
        }
        _ => IoErr::Failed("gzip: invalid header".into()),
    }
}

/// A streaming response body with a byte budget.
pub struct ResponseBody {
    client: Weak<Client>,
    pub status: u16,
    pub headers: Shared,
    pub protocol: String,
    state: RefCell<Option<BodyState>>,
    /// A read is parked on the state, which that read has taken out of the cell.
    reading: Cell<bool>,
    deadline: Deadline,
    closed: Cell<bool>,
}

/// State owned by one read. Both ordinary drop and runtime cleanup return it here.
struct ReadState<'a> {
    body: &'a ResponseBody,
    state: Option<BodyState>,
}

impl Drop for ReadState<'_> {
    fn drop(&mut self) {
        self.body.reading.set(false);
        let Some(mut state) = self.state.take() else {
            return;
        };
        if self.body.closed.get() {
            state.abandon();
        } else {
            *self.body.state.borrow_mut() = Some(state);
        }
    }
}

/// The guard owns the allocation until ordinary drop, or transfers it to runtime cleanup
/// when cancellation/fault skips Rust destructors. The interrupted decoder cannot be resumed.
struct Held<'a> {
    state: *mut ReadState<'a>,
    cleanup: usize,
}

unsafe extern "C-unwind" fn cancel_read(arg: *mut u8) {
    // SAFETY: the runtime only runs this action when abandoning the read's frames. Held's
    // destructor will not run, and the body outlives the read. This takes its allocation once.
    let state = unsafe { Box::from_raw(arg.cast::<ReadState<'_>>()) };
    state.body.closed.set(true);
    drop(state);
}

impl<'a> Held<'a> {
    fn new(body: &'a ResponseBody, state: BodyState) -> Self {
        // The cleanup stack is process-global, including in otherwise polling-only tests.
        #[cfg(test)]
        crate::http::server::serialize_tests();
        let state = Box::into_raw(Box::new(ReadState {
            body,
            state: Some(state),
        }));
        // SAFETY: the allocation stays live until this action runs or Held discards it.
        let cleanup = unsafe { rt::cleanup_push(cancel_read, state.cast()) };
        Self { state, cleanup }
    }

    fn state(&mut self) -> &mut Option<BodyState> {
        // SAFETY: Held exclusively owns the state while the read runs. Runtime cleanup
        // takes ownership only on a non-returning cancellation/fault path.
        unsafe { &mut (*self.state).state }
    }
}

impl Drop for Held<'_> {
    fn drop(&mut self) {
        rt::cleanup_discard(self.cleanup);
        // SAFETY: the cleanup was discarded, so this is the allocation's sole owner.
        drop(unsafe { Box::from_raw(self.state) });
    }
}

impl Resource for ResponseBody {
    fn close_resource(&self) {
        self.close();
    }
}

impl ResponseBody {
    pub fn is_closed(&self) -> bool {
        self.closed.get()
    }

    /// Cancels the rest of the response. A fully read body lets its connection
    /// be reused. Idempotent.
    pub fn close(&self) {
        if self.closed.replace(true) {
            return;
        }
        let state = self.state.borrow_mut().take();
        let Some(mut state) = state else { return };
        match self.client.upgrade() {
            Some(client) if state.done => state.finish(&client),
            _ => state.abandon(),
        }
    }

    /// The next chunk of at most `max` (1 to 65536) bytes, `None` at the end.
    pub fn read(&self, max: usize) -> Result<Option<Vec<u8>>, IoErr> {
        if self.closed.get() {
            return Err(IoErr::Closed);
        }
        if self.reading.get() {
            return Err(IoErr::Failed(
                "response body is being read by another task".into(),
            ));
        }
        rt::check_cancel();
        // The read can park, so the state is out of the cell meanwhile; the cell is never
        // borrowed across the park.
        let Some(taken) = self.state.borrow_mut().take() else {
            return Ok(None);
        };
        self.reading.set(true);
        let mut held = Held::new(self, taken);
        let state = held.state().as_mut().expect("state");
        let max = max.clamp(1, READ_BUF);
        if state.ready_pos >= state.ready.len() {
            state.ready.clear();
            state.ready_pos = 0;
            if let Err(e) = self.produce(state) {
                if self.closed.get() {
                    return Err(IoErr::Closed);
                }
                state.abandon();
                return Err(e);
            }
        }
        if state.ready_pos < state.ready.len() {
            let n = max.min(state.ready.len() - state.ready_pos);
            if n as u64 > state.remaining {
                state.abandon();
                return Err(IoErr::Failed("response body limit exceeded".into()));
            }
            state.remaining -= n as u64;
            let chunk = state.ready[state.ready_pos..state.ready_pos + n].to_vec();
            state.ready_pos += n;
            return Ok(Some(chunk));
        }
        // End of body: release the connection.
        let done = held.state().take().expect("state");
        drop(held);
        match self.client.upgrade() {
            Some(client) if !self.closed.get() => done.finish(&client),
            _ => {
                let mut done = done;
                done.abandon();
            }
        }
        Ok(None)
    }

    fn produce(&self, state: &mut BodyState) -> Result<(), IoErr> {
        if self.deadline.expired() {
            return Err(IoErr::Failed("context deadline exceeded".into()));
        }
        state.produce(self.deadline)
    }

    /// Reads everything within the budget (the buffered response path).
    pub fn read_all(&self) -> Result<Vec<u8>, ReadAll> {
        let mut out = Vec::new();
        loop {
            match self.read(READ_BUF) {
                Ok(Some(chunk)) => out.extend_from_slice(&chunk),
                Ok(None) => return Ok(out),
                Err(IoErr::Failed(m)) if m == "response body limit exceeded" => {
                    return Err(ReadAll::Limit);
                }
                Err(IoErr::Closed) => return Err(ReadAll::Closed),
                Err(IoErr::Failed(m)) if m == "context deadline exceeded" => {
                    return Err(ReadAll::Timeout);
                }
                Err(_) => return Err(ReadAll::Invalid),
            }
        }
    }
}

/// Why a buffered read stopped.
#[derive(Debug, PartialEq, Eq)]
pub enum ReadAll {
    Limit,
    Closed,
    /// The request deadline passed while the body was still arriving.
    Timeout,
    Invalid,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::http::url;
    use std::io::Read;
    use std::net::{TcpListener, TcpStream};
    use std::sync::atomic::{AtomicUsize, Ordering};

    /// Reads one request (head plus Content-Length or chunked body) as text.
    fn read_request(s: &mut TcpStream) -> Option<String> {
        let mut data = Vec::new();
        let mut buf = [0u8; 4096];
        loop {
            let at = data.windows(4).position(|w| w == b"\r\n\r\n");
            if let Some(at) = at {
                let head = String::from_utf8_lossy(&data[..at]).to_ascii_lowercase();
                let body = &data[at + 4..];
                let want = head
                    .lines()
                    .find_map(|l| l.strip_prefix("content-length: "))
                    .and_then(|v| v.parse::<usize>().ok());
                let done = if let Some(n) = want {
                    body.len() >= n
                } else if head.contains("transfer-encoding: chunked") {
                    body.ends_with(b"0\r\n\r\n")
                } else {
                    true
                };
                if done {
                    return Some(String::from_utf8_lossy(&data).into_owned());
                }
            }
            match s.read(&mut buf) {
                Ok(0) | Err(_) => return None,
                Ok(n) => data.extend_from_slice(&buf[..n]),
            }
        }
    }

    type Handler = dyn Fn(&mut TcpStream, usize) + Send + Sync + 'static;

    /// A loopback server running `handler` once per connection (connection
    /// index second); returns its address and the accept counter.
    fn serve(
        handler: impl Fn(&mut TcpStream, usize) + Send + Sync + 'static,
    ) -> (String, Arc<AtomicUsize>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap().to_string();
        let accepted = Arc::new(AtomicUsize::new(0));
        let counter = accepted.clone();
        let handler: Arc<Handler> = Arc::new(handler);
        std::thread::spawn(move || {
            for stream in listener.incoming() {
                let Ok(mut stream) = stream else { break };
                let index = counter.fetch_add(1, Ordering::SeqCst);
                let handler = handler.clone();
                std::thread::spawn(move || handler(&mut stream, index));
            }
        });
        (address, accepted)
    }

    fn reply(s: &mut TcpStream, text: &str) {
        s.write_all(text.as_bytes()).unwrap();
    }

    fn request(method: &str, address: &str, path: &str) -> Request {
        Request {
            method: method.into(),
            url: url::parse(&format!("http://{address}{path}")).unwrap(),
            headers: Vec::new(),
            body: Body::Bytes(Rc::new(Vec::new())),
            max_response: u64::MAX,
            deadline: Deadline::none(),
        }
    }

    fn client(options: ClientOptions) -> (Rc<Network>, Rc<Client>) {
        let net = Network::new_root();
        let client = Client::new(&net, options).unwrap();
        (net, client)
    }

    fn text(body: &ResponseBody) -> String {
        String::from_utf8(body.read_all().unwrap()).unwrap()
    }

    /// Requests in separate tasks overlap: each read parks with its own buffer, so five
    /// responses that each take 100 ms arrive together instead of one after another.
    #[test]
    fn requests_in_separate_tasks_overlap() {
        let (address, _) = serve(|s, _| {
            read_request(s).unwrap();
            std::thread::sleep(Duration::from_millis(100));
            reply(s, "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok");
        });
        crate::wait::use_tasks();
        let (_net, c) = client(ClientOptions::default());
        struct Job {
            client: Rc<Client>,
            request: Request,
            done: Rc<Cell<usize>>,
        }
        unsafe extern "C-unwind" fn run(arg: *mut u8) {
            // SAFETY: `arg` came from `Box::into_raw` below and this task owns it.
            let job = unsafe { Box::from_raw(arg.cast::<Job>()) };
            let body = job.client.send(job.request).unwrap();
            assert_eq!(text(&body), "ok");
            job.done.set(job.done.get() + 1);
        }
        let done = Rc::new(Cell::new(0));
        let started = Instant::now();
        for _ in 0..5 {
            let job = Box::new(Job {
                client: c.clone(),
                request: request("GET", &address, "/"),
                done: done.clone(),
            });
            // SAFETY: `run` takes ownership of the boxed job.
            unsafe { rt::spawn_detached(run, Box::into_raw(job).cast()) };
        }
        while done.get() < 5 {
            rt::sleep(1_000_000);
        }
        let took = started.elapsed();
        assert!(took < Duration::from_millis(300), "took {took:?}");
    }

    /// A second task reading a body that another task is parked on gets a failure, not a
    /// borrow panic, and the first read still completes.
    #[test]
    fn concurrent_reads_of_one_body_fail_cleanly() {
        let (address, _) = serve(|s, _| {
            read_request(s).unwrap();
            reply(s, "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\no");
            std::thread::sleep(Duration::from_millis(100));
            reply(s, "k");
        });
        crate::wait::use_tasks();
        let (_net, c) = client(ClientOptions::default());
        let body = c.send(request("GET", &address, "/")).unwrap();
        type Chunk = Result<Option<Vec<u8>>, IoErr>;
        struct Job {
            body: Rc<ResponseBody>,
            out: Rc<RefCell<Option<Chunk>>>,
        }
        unsafe extern "C-unwind" fn run(arg: *mut u8) {
            // SAFETY: `arg` came from `Box::into_raw` below and this task owns it.
            let job = unsafe { Box::from_raw(arg.cast::<Job>()) };
            // Drain the first chunk so the next read parks on the socket.
            let first = job.body.read(1);
            assert_eq!(first.unwrap().unwrap(), b"o");
            let r = job.body.read(1);
            *job.out.borrow_mut() = Some(r);
        }
        let out = Rc::new(RefCell::new(None));
        let job = Box::new(Job {
            body: body.clone(),
            out: out.clone(),
        });
        // SAFETY: `run` takes ownership of the boxed job.
        unsafe { rt::spawn_detached(run, Box::into_raw(job).cast()) };
        rt::sleep(30_000_000);
        match body.read(1) {
            Err(IoErr::Failed(m)) => assert!(m.contains("another task"), "{m}"),
            other => panic!("expected a failure, got {other:?}"),
        }
        while out.borrow().is_none() {
            rt::sleep(1_000_000);
        }
        assert_eq!(out.borrow_mut().take().unwrap().unwrap().unwrap(), b"k");
    }

    /// The dependency uses the production guard jump, which skips Rust destructors.
    #[test]
    fn cancelled_body_read_closes_the_body_and_connection() {
        crate::wait::use_tasks();
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap().to_string();
        let peer = std::thread::spawn(move || {
            let (mut socket, _) = listener.accept().unwrap();
            socket
                .set_read_timeout(Some(Duration::from_secs(5)))
                .unwrap();
            read_request(&mut socket).unwrap();
            reply(&mut socket, "HTTP/1.1 200 OK\r\nContent-Length: 1\r\n\r\n");
            let mut byte = [0];
            socket.read(&mut byte)
        });
        let (_net, c) = client(ClientOptions::default());
        let mut req = request("GET", &address, "/");
        req.deadline = Deadline::after(Duration::from_secs(5));
        let body = c.send(req).unwrap();
        struct Job<'a> {
            body: &'a ResponseBody,
            unwound: Cell<bool>,
        }
        struct Unwound<'a>(&'a Cell<bool>);
        impl Drop for Unwound<'_> {
            fn drop(&mut self) {
                self.0.set(true);
            }
        }
        unsafe extern "C-unwind" fn read(arg: *mut u8) {
            // SAFETY: the caller retains the job until this task has joined.
            let job = unsafe { &*arg.cast::<Job<'_>>() };
            let _sentinel = Unwound(&job.unwound);
            let _ = job.body.read(1);
        }
        let mut job = Job {
            body: &body,
            unwound: Cell::new(false),
        };
        // SAFETY: serialized runtime access; the job outlives the joined task.
        let task = unsafe { ms_rt::task::msrt_task_spawn(read, (&raw mut job).cast(), 0, 0) };
        rt::sleep(0);
        assert!(
            body.reading.get(),
            "the reader must park before cancellation"
        );
        // SAFETY: serialized runtime access to the live joinable task.
        unsafe {
            ms_rt::task::msrt_task_cancel(task);
            assert_eq!(ms_rt::task::msrt_task_join(task, std::ptr::null_mut()), 2);
        }
        assert!(
            !job.unwound.get(),
            "cancellation must skip Rust destructors"
        );
        assert!(body.is_closed());
        assert!(!body.reading.get());
        assert!(body.state.borrow().is_none());
        assert!(matches!(body.read(1), Err(IoErr::Closed)));
        body.close();
        assert_eq!(peer.join().unwrap().unwrap(), 0, "peer must observe EOF");
    }

    /// The request line and headers the client sends:
    /// `GET /p?x=1` with `Accept-Encoding: gzip` only when decompress is on.
    #[test]
    fn writes_requests_like_go() {
        let (address, _) = serve(|s, _| {
            let request = read_request(s).unwrap();
            reply(
                s,
                &format!(
                    "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{request}",
                    request.len()
                ),
            );
        });
        let (_net, c) = client(ClientOptions::default());
        let mut r = request("GET", &address, "/p?x=1");
        r.headers = vec![
            ("X-Zed".into(), b"1".to_vec()),
            ("Accept".into(), b"*/*".to_vec()),
            ("X-Zed".into(), b"2".to_vec()),
        ];
        let body = c.send(r).unwrap();
        assert_eq!(body.status, 200);
        assert_eq!(body.protocol, "HTTP/1.1");
        assert_eq!(
            text(&body),
            format!(
                "GET /p?x=1 HTTP/1.1\r\nHost: {address}\r\nUser-Agent: ms-http\r\nAccept: */*\r\nX-Zed: 1\r\nX-Zed: 2\r\n\r\n"
            )
        );

        let (_net, c) = client(ClientOptions {
            decompress: true,
            ..ClientOptions::default()
        });
        let body = c.send(request("GET", &address, "/")).unwrap();
        assert!(text(&body).contains("Accept-Encoding: gzip\r\n"));
    }

    #[test]
    fn body_framing_follows_go() {
        let (address, _) = serve(|s, _| {
            let request = read_request(s).unwrap();
            reply(
                s,
                &format!(
                    "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{request}",
                    request.len()
                ),
            );
        });
        let (_net, c) = client(ClientOptions::default());
        let mut post = request("POST", &address, "/");
        post.body = Body::Bytes(Rc::new(b"hello".to_vec()));
        let echoed = text(&c.send(post).unwrap());
        assert!(echoed.contains("Content-Length: 5\r\n"), "{echoed}");
        assert!(echoed.ends_with("\r\n\r\nhello"));
        let empty = text(&c.send(request("POST", &address, "/")).unwrap());
        assert!(empty.contains("Content-Length: 0\r\n"), "{empty}");
        let get = text(&c.send(request("GET", &address, "/")).unwrap());
        assert!(!get.contains("Content-Length"), "{get}");

        struct Pieces(Vec<&'static [u8]>);
        impl Source for Pieces {
            fn next(&mut self, _: usize) -> Result<Option<Vec<u8>>, String> {
                Ok((!self.0.is_empty()).then(|| self.0.remove(0).to_vec()))
            }
        }
        let mut upload = request("PUT", &address, "/");
        upload.body = Body::Stream(Box::new(Pieces(vec![b"ab", b"cde"])));
        let echoed = text(&c.send(upload).unwrap());
        assert!(
            echoed.contains("Transfer-Encoding: chunked\r\n"),
            "{echoed}"
        );
        assert!(
            echoed.ends_with("2\r\nab\r\n3\r\ncde\r\n0\r\n\r\n"),
            "{echoed}"
        );
    }

    #[test]
    fn reuses_keep_alive_connections() {
        let (address, accepted) = serve(|s, _| {
            while let Some(_request) = read_request(s) {
                reply(s, "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok");
            }
        });
        let (_net, c) = client(ClientOptions::default());
        for _ in 0..3 {
            assert_eq!(text(&c.send(request("GET", &address, "/")).unwrap()), "ok");
        }
        assert_eq!(accepted.load(Ordering::SeqCst), 1);
        c.close();
        assert!(matches!(
            c.send(request("GET", &address, "/")),
            Err(HttpErr::Closed)
        ));
    }

    #[test]
    fn replaces_connections_the_server_closed() {
        let (address, accepted) = serve(|s, _| {
            if read_request(s).is_some() {
                reply(s, "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok");
            }
        });
        let (_net, c) = client(ClientOptions::default());
        assert_eq!(text(&c.send(request("GET", &address, "/")).unwrap()), "ok");
        std::thread::sleep(Duration::from_millis(50));
        assert_eq!(text(&c.send(request("GET", &address, "/")).unwrap()), "ok");
        assert_eq!(accepted.load(Ordering::SeqCst), 2);
    }

    #[test]
    fn reads_chunked_and_gzip_bodies_within_the_budget() {
        let gz = {
            let mut e = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
            e.write_all(&vec![b'a'; 100_000]).unwrap();
            e.finish().unwrap()
        };
        let (address, _) = serve(move |s, _| {
            let request = read_request(s).unwrap();
            if request.starts_with("GET /gz") {
                let head = format!(
                    "HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
                    gz.len()
                );
                s.write_all(head.as_bytes()).unwrap();
                s.write_all(&gz).unwrap();
            } else {
                reply(
                    s,
                    "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n3\r\nabc\r\n2\r\nde\r\n0\r\n\r\n",
                );
            }
        });
        let (_net, c) = client(ClientOptions {
            decompress: true,
            ..ClientOptions::default()
        });
        assert_eq!(
            text(&c.send(request("GET", &address, "/c")).unwrap()),
            "abcde"
        );

        let body = c.send(request("GET", &address, "/gz")).unwrap();
        assert!(body.headers.borrow().values("Content-Encoding").is_none());
        assert!(body.headers.borrow().values("Content-Length").is_none());
        assert_eq!(body.read_all().unwrap().len(), 100_000);

        let mut limited = request("GET", &address, "/gz");
        limited.max_response = 99_999;
        assert_eq!(c.send(limited).unwrap().read_all(), Err(ReadAll::Limit));
        let mut exact = request("GET", &address, "/gz");
        exact.max_response = 100_000;
        assert_eq!(c.send(exact).unwrap().read_all().unwrap().len(), 100_000);

        // Without decompression the bytes arrive as sent.
        let (_net, plain) = client(ClientOptions::default());
        let body = plain.send(request("GET", &address, "/gz")).unwrap();
        assert!(body.headers.borrow().values("Content-Encoding").is_some());
    }

    #[test]
    fn follows_redirects_like_go() {
        let (address, _) = serve(|s, _| {
            while let Some(request) = read_request(s) {
                let line = request.lines().next().unwrap().to_string();
                let r = if line.contains("/r302") {
                    "HTTP/1.1 302 Found\r\nLocation: /dump\r\nContent-Length: 0\r\n\r\n".to_string()
                } else if line.contains("/r307") {
                    "HTTP/1.1 307 Temporary Redirect\r\nLocation: /dump\r\nContent-Length: 0\r\n\r\n".to_string()
                } else if line.contains("/loop") {
                    "HTTP/1.1 302 Found\r\nLocation: /loop\r\nContent-Length: 0\r\n\r\n".to_string()
                } else if line.contains("/nolocation") {
                    "HTTP/1.1 302 Found\r\nContent-Length: 0\r\n\r\n".to_string()
                } else {
                    format!(
                        "HTTP/1.1 200 OK\r\nContent-Length: {}\r\n\r\n{request}",
                        request.len()
                    )
                };
                s.write_all(r.as_bytes()).unwrap();
            }
        });
        let (_net, c) = client(ClientOptions::default());
        let mut post = request("POST", &address, "/r302");
        post.body = Body::Bytes(Rc::new(b"hello".to_vec()));
        post.headers = vec![
            ("Authorization".into(), b"secret".to_vec()),
            ("Content-Type".into(), b"text/plain".to_vec()),
        ];
        let echoed = text(&c.send(post).unwrap());
        assert!(echoed.starts_with("GET /dump HTTP/1.1\r\n"), "{echoed}");
        assert!(
            echoed.contains(&format!("Referer: http://{address}/r302\r\n")),
            "{echoed}"
        );
        assert!(echoed.contains("Authorization: secret\r\n"));
        assert!(echoed.contains("Content-Type: text/plain\r\n"));
        assert!(!echoed.contains("Content-Length"));

        let mut post = request("POST", &address, "/r307");
        post.body = Body::Bytes(Rc::new(b"hello".to_vec()));
        let echoed = text(&c.send(post).unwrap());
        assert!(echoed.starts_with("POST /dump HTTP/1.1\r\n"), "{echoed}");
        assert!(echoed.ends_with("\r\n\r\nhello"));

        // No Location: the redirect response itself.
        let body = c.send(request("GET", &address, "/nolocation")).unwrap();
        assert_eq!(body.status, 302);

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
    fn keeps_cookies_when_enabled() {
        let (address, _) = serve(|s, _| {
            while let Some(request) = read_request(s) {
                let r = if request.starts_with("GET /set") {
                    "HTTP/1.1 200 OK\r\nSet-Cookie: a=1; Path=/\r\nContent-Length: 0\r\n\r\n"
                        .to_string()
                } else {
                    format!(
                        "HTTP/1.1 200 OK\r\nContent-Length: {}\r\n\r\n{request}",
                        request.len()
                    )
                };
                s.write_all(r.as_bytes()).unwrap();
            }
        });
        let (_net, c) = client(ClientOptions {
            cookies: true,
            ..ClientOptions::default()
        });
        c.send(request("GET", &address, "/set")).unwrap();
        let echoed = text(&c.send(request("GET", &address, "/x")).unwrap());
        assert!(echoed.contains("Cookie: a=1\r\n"), "{echoed}");
        let (_net, plain) = client(ClientOptions::default());
        plain.send(request("GET", &address, "/set")).unwrap();
        assert!(!text(&plain.send(request("GET", &address, "/x")).unwrap()).contains("Cookie"));
    }

    /// A deadline that passes while the body is still arriving is a timeout, not bad data.
    #[test]
    fn body_deadline_is_a_timeout() {
        let (address, _) = serve(|s, _| {
            let _ = read_request(s);
            reply(s, "HTTP/1.1 200 OK\r\nContent-Length: 1000\r\n\r\nx");
            std::thread::sleep(Duration::from_millis(500));
        });
        let (_net, c) = client(ClientOptions::default());
        let mut slow = request("GET", &address, "/");
        slow.deadline = Deadline::after(Duration::from_millis(100));
        assert_eq!(c.send(slow).unwrap().read_all(), Err(ReadAll::Timeout));
    }

    /// The field-count cap names the count, not the unset byte limit.
    #[test]
    fn too_many_header_fields_are_reported_as_a_count() {
        let (address, _) = serve(|s, _| {
            let _ = read_request(s);
            let mut head = String::from("HTTP/1.1 200 OK\r\nContent-Length: 0\r\n");
            for i in 0..300 {
                head += &format!("H{i}: v\r\n");
            }
            head += "\r\n";
            reply(s, &head);
        });
        let (_net, c) = client(ClientOptions::default());
        match c.send(request("GET", &address, "/")) {
            Err(HttpErr::Failed(m)) => assert_eq!(
                m,
                "http: server response has more than 256 header fields; aborted"
            ),
            other => panic!("{:?}", other.map(|b| b.status)),
        }
    }

    #[test]
    fn reports_failures() {
        let (address, _) = serve(|s, i| {
            let _ = read_request(s);
            match i {
                0 => std::thread::sleep(Duration::from_millis(500)),
                1 => reply(
                    s,
                    "HTTP/1.1 200 OK\r\nX-Big: 0123456789012345678901234567890123456789\r\nContent-Length: 0\r\n\r\n",
                ),
                2 => reply(s, "garbage\r\n\r\n"),
                _ => {}
            }
        });
        let (_net, c) = client(ClientOptions {
            max_header_bytes: Some(40),
            ..ClientOptions::default()
        });
        let mut slow = request("GET", &address, "/");
        slow.deadline = Deadline::after(Duration::from_millis(100));
        assert!(matches!(c.send(slow), Err(HttpErr::Timeout)));
        match c.send(request("GET", &address, "/")) {
            Err(HttpErr::Failed(m)) => assert_eq!(
                m,
                "http: server response headers exceeded 40 bytes; aborted"
            ),
            other => panic!("{:?}", other.map(|b| b.status)),
        }
        let (_net, c) = client(ClientOptions::default());
        match c.send(request("GET", &address, "/")) {
            Err(HttpErr::Failed(m)) => assert_eq!(m, "malformed HTTP response \"garbage\""),
            other => panic!("{:?}", other.map(|b| b.status)),
        }
        match c.send(request("GET", &address, "/")) {
            Err(HttpErr::Failed(m)) => {
                assert_eq!(m, "connection closed before the exchange completed")
            }
            other => panic!("{:?}", other.map(|b| b.status)),
        }
        let refused = TcpListener::bind("127.0.0.1:0")
            .unwrap()
            .local_addr()
            .unwrap()
            .to_string();
        match c.send(request("GET", &refused, "/")) {
            Err(HttpErr::Failed(m)) => assert_eq!(m, "connection refused"),
            other => panic!("{:?}", other.map(|b| b.status)),
        }
    }

    #[test]
    fn close_interrupts_open_bodies() {
        let (address, _) = serve(|s, _| {
            let _ = read_request(s);
            reply(s, "HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nabc");
            std::thread::sleep(Duration::from_millis(300));
        });
        let (_net, c) = client(ClientOptions::default());
        let body = c.send(request("GET", &address, "/")).unwrap();
        assert_eq!(body.read(100).unwrap().unwrap(), b"abc");
        c.close();
        assert_eq!(body.read(100), Err(IoErr::Closed));
        assert_eq!(body.status, 200);
    }
}

#[cfg(test)]
#[path = "client_h2_tests.rs"]
mod h2_tests;
