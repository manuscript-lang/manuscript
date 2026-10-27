//! Natives for `@std/net.ms`, `Network.web_socket` and `HttpExchange.upgrade`.

use super::tls::tls_options;
use super::{ExchH, HeadersH, NetH, SocketH, opt, report};
use crate::error::WsErr;
use crate::http::headers::Headers;
use crate::ws::dial::{self, Dial};
use ms_rt::ffi::{
    Bytes, ErrOut, ObjRef, Object, OptInt, Out, StatusCode, Str, StringList, abi_record, native,
};
use ms_rt_abi::STATUS_NONE;

abi_record! {
    /// `WebSocketOptions` as the compiler lays it out for natives.
    pub struct WebSocketOptionsWire {
        pub max_message_bytes: OptInt,
        pub timeout: OptInt,
        // `tls` inline, then `compression` right behind it (see `tls_options`).
        pub tls_server_name: Str,
        pub tls_roots_pem: Str,
        pub tls_certificate_pem: Str,
        pub tls_private_key_pem: Str,
        pub tls_alpn: StringList,
        pub tls_require_client_certificate: u8,
        pub compression: u8,
    }
}

abi_record! {
    /// `WebSocketMessage` at its natural layout.
    pub struct WebSocketMessageRec {
        pub data: Bytes,
        pub text: u8,
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
        let tls = tls_options(
            &opts.tls_server_name,
            &opts.tls_roots_pem,
            &opts.tls_certificate_pem,
            &opts.tls_private_key_pem,
            &opts.tls_alpn,
            opts.tls_require_client_certificate,
        );
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

    /// `WebSocket.receive()`; the peer's normal close is `STATUS_NONE`.
    fn msrt_websocket_receive(
        s: ObjRef<SocketH>,
        out: Out<WebSocketMessageRec>,
        err: ErrOut,
    ) -> Result<(), StatusCode> {
        match report(s.receive(None), &err)? {
            Some(m) => out.write(WebSocketMessageRec {
                data: Bytes::new(&m.data),
                text: u8::from(m.text),
            }),
            None => return Err(StatusCode(STATUS_NONE)),
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use core::mem::offset_of;

    /// The compiler packs a record's leaves with no padding after a nested record: after two
    /// `Optional[Int]` (16 bytes each), four strings, the ALPN list (24 bytes) and one byte for
    /// `require_client_certificate`, `compression` is the next byte.
    #[test]
    fn compression_follows_the_inline_tls_options_byte() {
        assert_eq!(offset_of!(WebSocketOptionsWire, tls_server_name), 32);
        assert_eq!(
            offset_of!(WebSocketOptionsWire, tls_require_client_certificate),
            120
        );
        assert_eq!(offset_of!(WebSocketOptionsWire, compression), 121);
    }
}
