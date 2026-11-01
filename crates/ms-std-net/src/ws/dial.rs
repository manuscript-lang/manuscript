//! The client side of the opening handshake: `Network.web_socket`.

use super::handshake::{self, ClientRequest};
use super::socket::{Config, Role, Socket};
use crate::error::{IoErr, WsErr};
use crate::http::h1::{self, Parsed};
use crate::http::headers;
use crate::http::url;
use crate::net::Network;
use crate::tls::{self, TlsOptions};
use crate::wait::Deadline;
use std::rc::Rc;

/// Settings of `WebSocketOptions` plus the caller's headers and subprotocols.
pub struct Dial<'a> {
    pub address: &'a str,
    /// Validated caller headers (no `Host`, `Upgrade`, `Connection`, `Sec-WebSocket-*`).
    pub headers: &'a [(String, Vec<u8>)],
    pub subprotocols: &'a [String],
    pub max_message_bytes: Option<i64>,
    pub timeout: Option<i64>,
    pub tls: &'a TlsOptions,
    pub compression: bool,
}

/// Longest response head accepted during the handshake.
const HEAD_LIMIT: usize = 1 << 20;

fn io_error(e: IoErr) -> WsErr {
    match e {
        IoErr::Closed => WsErr::Closed,
        IoErr::Failed(m) if m == "operation timed out" => WsErr::Timeout,
        IoErr::Failed(m) => WsErr::Failed(m),
        _ => WsErr::Failed("i/o error".into()),
    }
}

/// Opens a client connection to a `ws` or `wss` URL.
pub fn connect(owner: &Rc<Network>, dial: &Dial<'_>) -> Result<Rc<Socket>, WsErr> {
    let max = match dial.max_message_bytes {
        Some(n) if n <= 0 => return Err(WsErr::InvalidInput),
        Some(n) => Some(n as u64),
        None => None,
    };
    let deadline = Deadline::from_nanos(dial.timeout).map_err(|_| WsErr::InvalidInput)?;
    // The URL parser knows http and https; the handshake itself is HTTP/1.1.
    let (secure, rest) = match dial.address.split_once(':') {
        Some((scheme, rest)) if scheme.eq_ignore_ascii_case("ws") => (false, rest),
        Some((scheme, rest)) if scheme.eq_ignore_ascii_case("wss") => (true, rest),
        _ => return Err(WsErr::InvalidInput),
    };
    let http = format!("{}:{rest}", if secure { "https" } else { "http" });
    let target = url::parse(&http).ok_or(WsErr::InvalidInput)?;
    if !owner.host_allowed(&target.host) {
        return Err(WsErr::PermissionDenied);
    }
    let mut tls_options = dial.tls.clone();
    tls_options.alpn = vec!["http/1.1".to_string()];
    let config = tls::client_config(&tls_options, false).map_err(|_| WsErr::InvalidInput)?;
    if dial.subprotocols.iter().any(|p| !headers::valid_name(p)) {
        return Err(WsErr::InvalidInput);
    }
    if owner.is_closed() {
        return Err(WsErr::Closed);
    }
    let result = handshake_on(owner, dial, &target, &config, deadline, max);
    match result {
        Err(_) if owner.is_closed() => Err(WsErr::Closed),
        Err(_) if deadline.expired() => Err(WsErr::Timeout),
        other => other,
    }
}

fn handshake_on(
    owner: &Rc<Network>,
    dial: &Dial<'_>,
    target: &url::Url,
    config: &std::sync::Arc<rustls::ClientConfig>,
    deadline: Deadline,
    max: Option<u64>,
) -> Result<Rc<Socket>, WsErr> {
    let tls = target.is_https().then_some((config, target.host.as_str()));
    let conn = owner
        .dial_stream(&target.dial_address(), tls, deadline)
        .map_err(WsErr::from)?;
    let key = handshake::generate_key();
    let request = handshake::client_request(&ClientRequest {
        target: &target.request_uri(),
        host: &target.authority,
        key: &key,
        subprotocols: dial.subprotocols,
        headers: dial.headers,
        compression: dial.compression,
    });
    let outcome = (|| {
        conn.write_until(&request, deadline).map_err(io_error)?;
        let mut buf: Vec<u8> = Vec::new();
        let mut chunk = vec![0u8; 8192];
        loop {
            match h1::parse_response(&buf, HEAD_LIMIT) {
                Parsed::Complete(head) => {
                    let accepted = handshake::check_response_head(&head, &key, dial.subprotocols)
                        .map_err(|f| f.error())?;
                    return Ok((accepted, buf.split_off(head.length)));
                }
                Parsed::Bad(_) => return Err(WsErr::Failed("malformed HTTP response".into())),
                Parsed::Partial => {}
            }
            let n = conn.read_into(&mut chunk, deadline).map_err(io_error)?;
            if n == 0 {
                return Err(WsErr::Failed(
                    "connection closed before the exchange completed".into(),
                ));
            }
            buf.extend_from_slice(&chunk[..n]);
        }
    })();
    match outcome {
        Ok((accepted, leftover)) => {
            let config = Config::new(max, accepted.compress, accepted.subprotocol);
            Ok(Rc::new(Socket::new(conn, leftover, Role::Client, config)))
        }
        Err(e) => {
            conn.close();
            Err(e)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read, Write};
    use std::net::TcpListener;

    /// A server that completes the handshake (answering `chat`), sends "hello",
    /// and returns the unmasked payload of the first client frame.
    fn server(status_line: &'static str) -> (String, std::thread::JoinHandle<Vec<u8>>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap().to_string();
        let handle = std::thread::spawn(move || {
            let (mut s, _) = listener.accept().unwrap();
            let mut request = Vec::new();
            let mut buf = [0u8; 2048];
            while !request.windows(4).any(|w| w == b"\r\n\r\n") {
                let n = s.read(&mut buf).unwrap();
                request.extend_from_slice(&buf[..n]);
            }
            let text = String::from_utf8_lossy(&request).into_owned();
            assert!(text.starts_with("GET /chat?x=1 HTTP/1.1\r\n"), "{text}");
            assert!(
                text.contains("Sec-WebSocket-Protocol: chat, other\r\n"),
                "{text}"
            );
            assert!(text.contains("X-Token: abc\r\n"), "{text}");
            let key = text
                .lines()
                .find_map(|l| l.strip_prefix("Sec-WebSocket-Key: "))
                .unwrap();
            let accept = handshake::accept_key(key);
            let head = format!(
                "{status_line}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {accept}\r\nSec-WebSocket-Protocol: chat\r\n\r\n"
            );
            s.write_all(head.as_bytes()).unwrap();
            if !status_line.contains("101") {
                return Vec::new();
            }
            s.write_all(&[0x81, 5, b'h', b'e', b'l', b'l', b'o'])
                .unwrap();
            let mut frame = [0u8; 64];
            let mut got = 0;
            while got < 2 || got < 6 + (frame[1] & 0x7f) as usize {
                let n = s.read(&mut frame[got..]).unwrap();
                if n == 0 {
                    break;
                }
                got += n;
            }
            let len = (frame[1] & 0x7f) as usize;
            let mask = [frame[2], frame[3], frame[4], frame[5]];
            (0..len).map(|i| frame[6 + i] ^ mask[i % 4]).collect()
        });
        (address, handle)
    }

    fn dial<'a>(
        address: &'a str,
        tls: &'a TlsOptions,
        headers: &'a [(String, Vec<u8>)],
        protocols: &'a [String],
    ) -> Dial<'a> {
        Dial {
            address,
            headers,
            subprotocols: protocols,
            max_message_bytes: None,
            timeout: Some(5_000_000_000),
            tls,
            compression: false,
        }
    }

    #[test]
    fn opens_a_client_session() {
        let (address, peer) = server("HTTP/1.1 101 Switching Protocols");
        let net = Network::new_root();
        let tls = TlsOptions::default();
        let headers = vec![("X-Token".to_string(), b"abc".to_vec())];
        let protocols = vec!["chat".to_string(), "other".to_string()];
        let url = format!("ws://{address}/chat?x=1");
        let socket = connect(&net, &dial(&url, &tls, &headers, &protocols)).unwrap();
        assert_eq!(socket.subprotocol(), "chat");
        let message = socket.receive(None).unwrap().unwrap();
        assert_eq!(
            (message.data.as_slice(), message.text),
            (&b"hello"[..], true)
        );
        socket.send(b"reply", true, None).unwrap();
        assert_eq!(peer.join().unwrap(), b"reply");
    }

    #[test]
    fn reports_a_rejected_handshake_and_bad_input() {
        let (address, peer) = server("HTTP/1.1 403 Forbidden");
        let net = Network::new_root();
        let tls = TlsOptions::default();
        let headers = vec![("X-Token".to_string(), b"abc".to_vec())];
        let protocols = vec!["chat".to_string(), "other".to_string()];
        let url = format!("ws://{address}/chat?x=1");
        assert_eq!(
            connect(&net, &dial(&url, &tls, &headers, &protocols)).err(),
            Some(WsErr::Failed("websocket: bad handshake".into()))
        );
        peer.join().unwrap();
        for bad in ["http://h/", "ws:///x", "nonsense"] {
            assert_eq!(
                connect(&net, &dial(bad, &tls, &[], &[])).err(),
                Some(WsErr::InvalidInput),
                "{bad}"
            );
        }
        let mut limited = dial("ws://127.0.0.1:1/", &tls, &[], &[]);
        limited.max_message_bytes = Some(0);
        assert_eq!(connect(&net, &limited).err(), Some(WsErr::InvalidInput));
        assert_eq!(
            connect(&net, &dial("ws://127.0.0.1:1/", &tls, &[], &[])).err(),
            Some(WsErr::Failed("connection refused".into()))
        );
    }
}
