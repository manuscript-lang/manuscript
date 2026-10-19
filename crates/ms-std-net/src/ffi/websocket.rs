//! Shims for `@std/websocket.ms`, `Network.web_socket` and `HttpExchange.upgrade`.

use super::http::OptWire;
use super::net::network;
use super::tls::TlsOptionsWire;
use super::{finish, handle_ref, new_handle, opt};
use crate::error::WsErr;
use crate::http::exchange::Exchange;
use crate::http::headers::{Headers, Shared};
use crate::tls::TlsOptions;
use crate::ws::dial::{self, Dial};
use crate::ws::socket::Socket;
use ms_rt_abi::{Obj, StrObj, VecVal};
use ms_std_core::{bytes_ref, new_string, read_string_list, str_ref, write_bytes};
use std::rc::Rc;

type SocketRef = Rc<Socket>;

/// `WebSocketOptions` as the compiler lays it out for natives.
#[repr(C)]
pub struct WebSocketOptionsWire {
    pub max_message_bytes: OptWire,
    pub timeout: OptWire,
    pub tls: TlsOptionsWire,
    pub compression: u8,
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

/// `Error.message()` of `WebSocketError`.
///
/// # Safety
/// `failed` is null or a live string.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_websocket_error_message(
    status: u8,
    failed: *const StrObj,
) -> *mut StrObj {
    let text = if failed.is_null() {
        String::new()
    } else {
        // SAFETY: caller contract.
        unsafe { str_ref(failed) }.to_string()
    };
    new_string(&ws_from_code(status, text).message())
}

/// Caller headers of a client handshake: tokens with text values, none of the
/// names the handshake owns.
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

/// `Network.web_socket(url, headers, subprotocols, options)`.
///
/// # Safety
/// Pointers per `ABI.md`; `opts` is a live `WebSocketOptionsWire`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_net_network_web_socket(
    net: *const Obj,
    address: *const StrObj,
    headers: *const Obj,
    subprotocols: *const VecVal,
    opts: *const WebSocketOptionsWire,
    out: *mut *mut Obj,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let w = &*opts;
        let shared = handle_ref::<Shared>(headers);
        let protocols: Vec<String> = read_string_list(subprotocols)
            .into_iter()
            .map(str::to_string)
            .collect();
        let tls = TlsOptions {
            server_name: str_ref(w.tls.server_name).to_string(),
            roots_pem: str_ref(w.tls.roots_pem).to_string(),
            certificate_pem: str_ref(w.tls.certificate_pem).to_string(),
            private_key_pem: str_ref(w.tls.private_key_pem).to_string(),
            alpn: read_string_list(&raw const w.tls.alpn)
                .into_iter()
                .map(str::to_string)
                .collect(),
            require_client_certificate: w.tls.require_client_certificate != 0,
        };
        let result = match handshake_headers(&shared.borrow()) {
            None => Err(WsErr::InvalidInput),
            Some(fields) => dial::connect(
                network(net),
                &Dial {
                    address: str_ref(address),
                    headers: &fields,
                    subprotocols: &protocols,
                    max_message_bytes: w.max_message_bytes.present_value(),
                    timeout: w.timeout.present_value(),
                    tls: &tls,
                    compression: w.compression != 0,
                },
            ),
        };
        finish(result, err, |s| *out = new_handle::<SocketRef>(s))
    }
}

/// `HttpExchange.upgrade(allowed_origins, subprotocols, max_message_bytes)`.
///
/// # Safety
/// Pointers per `ABI.md`; the lists are live `List[String]` values.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_http_exchange_upgrade(
    x: *const Obj,
    origins: *const VecVal,
    subprotocols: *const VecVal,
    has_max: u8,
    max: i64,
    out: *mut *mut Obj,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let exchange = handle_ref::<Rc<Exchange>>(x);
        let origins: Vec<String> = read_string_list(origins)
            .into_iter()
            .map(str::to_string)
            .collect();
        let protocols: Vec<String> = read_string_list(subprotocols)
            .into_iter()
            .map(str::to_string)
            .collect();
        finish(
            exchange.upgrade(&origins, &protocols, opt(has_max, max)),
            err,
            |s| *out = new_handle::<SocketRef>(s),
        )
    }
}

/// # Safety
/// `s` is a live socket handle.
unsafe fn socket<'a>(s: *const Obj) -> &'a SocketRef {
    // SAFETY: caller contract.
    unsafe { handle_ref::<SocketRef>(s) }
}

/// `WebSocket.close()`.
///
/// # Safety
/// `s` is a live socket handle.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_websocket_close(s: *const Obj) {
    // SAFETY: caller contract.
    unsafe { socket(s).close() }
}

/// `WebSocket.subprotocol() -> String`.
///
/// # Safety
/// `s` is a live socket handle.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_websocket_subprotocol(s: *const Obj) -> *mut StrObj {
    // SAFETY: caller contract.
    unsafe { new_string(socket(s).subprotocol()) }
}

/// `WebSocket.ping(data: String)`.
///
/// # Safety
/// Pointers per `ABI.md`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_websocket_ping(
    s: *const Obj,
    data: *const StrObj,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe { finish(socket(s).ping(str_ref(data).as_bytes()), err, |()| {}) }
}

/// `WebSocket.ping_bytes(data: Bytes)`.
///
/// # Safety
/// Pointers per `ABI.md`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_websocket_ping_bytes(
    s: *const Obj,
    data: *const VecVal,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe { finish(socket(s).ping(bytes_ref(data)), err, |()| {}) }
}

/// `WebSocket.send(data: String)`: a text message.
///
/// # Safety
/// Pointers per `ABI.md`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_websocket_send(
    s: *const Obj,
    data: *const StrObj,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe { finish(socket(s).send_text(str_ref(data), None), err, |()| {}) }
}

/// `WebSocket.send_bytes(data: Bytes, text: Bool)`.
///
/// # Safety
/// Pointers per `ABI.md`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_websocket_send_bytes(
    s: *const Obj,
    data: *const VecVal,
    text: u8,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        finish(
            socket(s).send(bytes_ref(data), text != 0, None),
            err,
            |()| {},
        )
    }
}

/// `WebSocket.receive() -> Result[Optional[WebSocketMessage], WebSocketError]`:
/// `present` is set when a message arrived, with its payload and text flag.
///
/// # Safety
/// Pointers per `ABI.md`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_websocket_receive(
    s: *const Obj,
    data: *mut VecVal,
    text: *mut u8,
    present: *mut u8,
    err: *mut *mut StrObj,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        finish(socket(s).receive(None), err, |message| match message {
            Some(m) => {
                *present = 1;
                *text = u8::from(m.text);
                write_bytes(data, &m.data);
            }
            None => *present = 0,
        })
    }
}
