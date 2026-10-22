//! Natives for `@std/net.ms`, `Network.web_socket` and `HttpExchange.upgrade`.

use super::tls::TlsOptionsWire;
use super::{ExchH, HeadersH, NetH, SocketH, report};
use crate::error::WsErr;
use crate::http::headers::Headers;
use crate::ws::dial::{self, Dial};
use ms_std_core::{ErrOut, ObjRef, Object, OptInt, Out, StatusCode, abi_record, native};

abi_record! {
    /// `WebSocketOptions` as the compiler lays it out for natives.
    pub struct WebSocketOptionsWire {
        pub max_message_bytes: OptInt,
        pub timeout: OptInt,
        pub tls: TlsOptionsWire,
        pub compression: u8,
    }
}

fn ws_from_code(status: u8, failed: String) -> WsErr {
    match status {
        1 => WsErr::InvalidInput,
        2 => WsErr::InvalidData,
        3 => WsErr::LimitExceeded,
        4 => WsErr::PermissionDenied,
        5 => WsErr::Closed,
        6 => WsErr::Timeout,
        _ => WsErr::Failed(failed),
    }
}

/// Flattened `Optional[Int]` parameter.
fn opt(has: bool, v: i64) -> Option<i64> {
    has.then_some(v)
}

fn handshake_headers(h: &Headers) -> Option<Vec<(String, Vec<u8>)>> {
    let mut out = Vec::new();
    for entry in h.entries() {
        let lower = entry.name.to_ascii_lowercase();
        if !crate::http::headers::valid_name(&entry.name)
            || lower.starts_with("sec-websocket-")
            || lower == "upgrade"
            || lower == "connection"
            || lower == "host"
        {
            return None;
        }
        let name = crate::http::headers::canonical(&entry.name);
        for v in &entry.values {
            if std::str::from_utf8(v).is_err() || v.iter().any(|&b| matches!(b, b'\r' | b'\n' | 0))
            {
                return None;
            }
            out.push((name.clone(), v.clone()));
        }
    }
    Some(out)
}

native! {
    /// `WebSocketError.message()` for a status and the `Failed` text (nullable).
    fn msrt_websocket_error_message(status: u8, has_failed: bool, failed: &str) -> String {
        ws_from_code(status, (if has_failed { failed } else { "" }).to_string()).message()
    }

    /// `Network.web_socket(address, headers, subprotocols, options)`.
    fn msrt_net_network_web_socket(
        net: ObjRef<NetH>,
        address: &str,
        headers: ObjRef<HeadersH>,
        subprotocols: Vec<&str>,
        opts: &WebSocketOptionsWire,
        out: Out<Object<SocketH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let protocols: Vec<String> = subprotocols.into_iter().map(str::to_string).collect();
        let tls = opts.tls.to_options();
        let result = match handshake_headers(&headers.borrow()) {
            None => Err(WsErr::InvalidInput),
            Some(fields) => dial::connect(
                &net,
                &Dial {
                    address,
                    headers: &fields,
                    subprotocols: &protocols,
                    max_message_bytes: opts.max_message_bytes.get(),
                    timeout: opts.timeout.get(),
                    tls: &tls,
                    compression: opts.compression != 0,
                },
            ),
        };
        out.write(Object(SocketH(report(result, &err)?)));
        Ok(())
    }

    /// `HttpExchange.upgrade(origins, subprotocols, max_message_bytes)`.
    fn msrt_http_exchange_upgrade(
        x: ObjRef<ExchH>,
        origins: Vec<&str>,
        subprotocols: Vec<&str>,
        has_max: bool,
        max: i64,
        out: Out<Object<SocketH>>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        let origins: Vec<String> = origins.into_iter().map(str::to_string).collect();
        let protocols: Vec<String> = subprotocols.into_iter().map(str::to_string).collect();
        let s = x.upgrade(&origins, &protocols, opt(has_max, max));
        out.write(Object(SocketH(report(s, &err)?)));
        Ok(())
    }

    /// `WebSocket.close()`.
    fn msrt_websocket_close(s: ObjRef<SocketH>) -> () {
        s.close();
    }

    /// `WebSocket.subprotocol()`.
    fn msrt_websocket_subprotocol(s: ObjRef<SocketH>) -> String {
        s.subprotocol().to_string()
    }

    /// `WebSocket.ping(data)`.
    fn msrt_websocket_ping(s: ObjRef<SocketH>, data: &str, err: ErrOut) -> Result<(), StatusCode> {
        report(s.ping(data.as_bytes()), &err)
    }

    /// `WebSocket.ping(data: Bytes)`.
    fn msrt_websocket_ping_bytes(s: ObjRef<SocketH>, data: &[u8], err: ErrOut) -> Result<(), StatusCode> {
        report(s.ping(data), &err)
    }

    /// `WebSocket.send(data)`.
    fn msrt_websocket_send(s: ObjRef<SocketH>, data: &str, err: ErrOut) -> Result<(), StatusCode> {
        report(s.send_text(data, None), &err)
    }

    /// `WebSocket.send(data: Bytes, text)`.
    fn msrt_websocket_send_bytes(
        s: ObjRef<SocketH>,
        data: &[u8],
        text: bool,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        report(s.send(data, text, None), &err)
    }

    /// `WebSocket.receive()`: `present` is false once the peer has closed.
    fn msrt_websocket_receive(
        s: ObjRef<SocketH>,
        data: Out<Vec<u8>>,
        text: Out<bool>,
        present: Out<bool>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        match report(s.receive(None), &err)? {
            Some(m) => {
                present.write(true);
                text.write(m.text);
                data.write(m.data);
            }
            None => present.write(false),
        }
        Ok(())
    }
}
