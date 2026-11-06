//! Error types of the network modules and their diagnostics.
//!
//! The status byte a fallible native returns is the shared `ms_rt_abi::STATUS_*` number of the
//! case (`0` is success). The `Failed` case carries its message through a trailing `*mut StrVal`.

use std::fmt;
use std::io;

use ms_rt_abi::{
    STATUS_AUTHENTICATION_FAILED, STATUS_CLOSED, STATUS_FAILED, STATUS_INVALID_DATA,
    STATUS_INVALID_INPUT, STATUS_LIMIT_EXCEEDED, STATUS_PERMISSION_DENIED, STATUS_TIMEOUT,
    STATUS_UNAVAILABLE, STATUS_UNSUPPORTED,
};

/// The `NetworkError` status group of `@std/net/net.ms`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum NetErr {
    InvalidInput,
    InvalidData,
    LimitExceeded,
    PermissionDenied,
    Unsupported,
    Closed,
    Timeout,
    Failed(String),
}

/// Failures of `@std/io/io.ms`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum IoErr {
    Closed,
    InvalidInput,
    Unavailable,
    InvalidData,
    LimitExceeded,
    Failed(String),
}

/// Failures of `@std/net/http.ms`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum HttpErr {
    InvalidInput,
    InvalidData,
    LimitExceeded,
    PermissionDenied,
    Closed,
    Timeout,
    Failed(String),
}

/// The `WebSocketError` status group of `@std/net/websocket.ms`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum WsErr {
    InvalidInput,
    InvalidData,
    LimitExceeded,
    PermissionDenied,
    Closed,
    Timeout,
    Failed(String),
}

/// The `TlsError` status group of `@std/net/tls.ms`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TlsErr {
    InvalidInput,
    InvalidData,
    LimitExceeded,
    AuthenticationFailed,
}

/// A status code and the optional message of a `Failed` case.
pub trait Status {
    /// Status byte (`ms_rt_abi::STATUS_*`).
    fn code(&self) -> u8;
    /// Message of the `Failed` case.
    fn failed_message(&self) -> Option<&str>;
}

impl Status for NetErr {
    fn code(&self) -> u8 {
        match self {
            NetErr::InvalidInput => STATUS_INVALID_INPUT,
            NetErr::InvalidData => STATUS_INVALID_DATA,
            NetErr::LimitExceeded => STATUS_LIMIT_EXCEEDED,
            NetErr::PermissionDenied => STATUS_PERMISSION_DENIED,
            NetErr::Unsupported => STATUS_UNSUPPORTED,
            NetErr::Closed => STATUS_CLOSED,
            NetErr::Timeout => STATUS_TIMEOUT,
            NetErr::Failed(_) => STATUS_FAILED,
        }
    }
    fn failed_message(&self) -> Option<&str> {
        match self {
            NetErr::Failed(m) => Some(m),
            _ => None,
        }
    }
}

impl Status for IoErr {
    fn code(&self) -> u8 {
        match self {
            IoErr::Closed => STATUS_CLOSED,
            IoErr::InvalidInput => STATUS_INVALID_INPUT,
            IoErr::Unavailable => STATUS_UNAVAILABLE,
            IoErr::InvalidData => STATUS_INVALID_DATA,
            IoErr::LimitExceeded => STATUS_LIMIT_EXCEEDED,
            IoErr::Failed(_) => STATUS_FAILED,
        }
    }
    fn failed_message(&self) -> Option<&str> {
        match self {
            IoErr::Failed(m) => Some(m),
            _ => None,
        }
    }
}

impl Status for HttpErr {
    fn code(&self) -> u8 {
        match self {
            HttpErr::InvalidInput => STATUS_INVALID_INPUT,
            HttpErr::InvalidData => STATUS_INVALID_DATA,
            HttpErr::LimitExceeded => STATUS_LIMIT_EXCEEDED,
            HttpErr::PermissionDenied => STATUS_PERMISSION_DENIED,
            HttpErr::Closed => STATUS_CLOSED,
            HttpErr::Timeout => STATUS_TIMEOUT,
            HttpErr::Failed(_) => STATUS_FAILED,
        }
    }
    fn failed_message(&self) -> Option<&str> {
        match self {
            HttpErr::Failed(m) => Some(m),
            _ => None,
        }
    }
}

impl Status for WsErr {
    fn code(&self) -> u8 {
        match self {
            WsErr::InvalidInput => STATUS_INVALID_INPUT,
            WsErr::InvalidData => STATUS_INVALID_DATA,
            WsErr::LimitExceeded => STATUS_LIMIT_EXCEEDED,
            WsErr::PermissionDenied => STATUS_PERMISSION_DENIED,
            WsErr::Closed => STATUS_CLOSED,
            WsErr::Timeout => STATUS_TIMEOUT,
            WsErr::Failed(_) => STATUS_FAILED,
        }
    }
    fn failed_message(&self) -> Option<&str> {
        match self {
            WsErr::Failed(m) => Some(m),
            _ => None,
        }
    }
}

impl Status for TlsErr {
    fn code(&self) -> u8 {
        match self {
            TlsErr::InvalidInput => STATUS_INVALID_INPUT,
            TlsErr::InvalidData => STATUS_INVALID_DATA,
            TlsErr::LimitExceeded => STATUS_LIMIT_EXCEEDED,
            TlsErr::AuthenticationFailed => STATUS_AUTHENTICATION_FAILED,
        }
    }
    fn failed_message(&self) -> Option<&str> {
        None
    }
}

const REASON_INVALID_INPUT: &str = "invalid input";
const REASON_INVALID_DATA: &str = "invalid data";
const REASON_LIMIT: &str = "limit exceeded";
const REASON_DENIED: &str = "permission denied";
const REASON_UNSUPPORTED: &str = "operation not supported";
const REASON_CLOSED: &str = "resource is closed";
const REASON_TIMEOUT: &str = "operation timed out";
const REASON_AUTH: &str = "authentication failed";

fn diagnostic(domain: &str, reason: &str) -> String {
    format!("{domain}: {reason}")
}

impl NetErr {
    /// `Error.message()`: the `Failed` text verbatim, else `network: <reason>`.
    pub fn message(&self) -> String {
        let reason = match self {
            NetErr::Failed(m) => return m.clone(),
            NetErr::InvalidInput => REASON_INVALID_INPUT,
            NetErr::InvalidData => REASON_INVALID_DATA,
            NetErr::LimitExceeded => REASON_LIMIT,
            NetErr::PermissionDenied => REASON_DENIED,
            NetErr::Unsupported => REASON_UNSUPPORTED,
            NetErr::Closed => REASON_CLOSED,
            NetErr::Timeout => REASON_TIMEOUT,
        };
        diagnostic("network", reason)
    }

    pub fn failed(message: impl Into<String>) -> Self {
        NetErr::Failed(message.into())
    }
}

impl HttpErr {
    /// `Error.message()`: the `Failed` text verbatim, else `HTTP: <reason>`.
    pub fn message(&self) -> String {
        let reason = match self {
            HttpErr::Failed(m) => return m.clone(),
            HttpErr::InvalidInput => REASON_INVALID_INPUT,
            HttpErr::InvalidData => REASON_INVALID_DATA,
            HttpErr::LimitExceeded => REASON_LIMIT,
            HttpErr::PermissionDenied => REASON_DENIED,
            HttpErr::Closed => REASON_CLOSED,
            HttpErr::Timeout => REASON_TIMEOUT,
        };
        diagnostic("HTTP", reason)
    }
}

impl WsErr {
    /// `Error.message()`: the `Failed` text verbatim, else `WebSocket: <reason>`.
    pub fn message(&self) -> String {
        let reason = match self {
            WsErr::Failed(m) => return m.clone(),
            WsErr::InvalidInput => REASON_INVALID_INPUT,
            WsErr::InvalidData => REASON_INVALID_DATA,
            WsErr::LimitExceeded => REASON_LIMIT,
            WsErr::PermissionDenied => REASON_DENIED,
            WsErr::Closed => REASON_CLOSED,
            WsErr::Timeout => REASON_TIMEOUT,
        };
        diagnostic("WebSocket", reason)
    }
}

impl TlsErr {
    /// `Error.message()`: `TLS: <reason>`, never echoing certificate text.
    pub fn message(&self) -> String {
        let reason = match self {
            TlsErr::InvalidInput => REASON_INVALID_INPUT,
            TlsErr::InvalidData => REASON_INVALID_DATA,
            TlsErr::LimitExceeded => REASON_LIMIT,
            TlsErr::AuthenticationFailed => REASON_AUTH,
        };
        diagnostic("TLS", reason)
    }
}

impl IoErr {
    pub fn failed(message: impl Into<String>) -> Self {
        IoErr::Failed(message.into())
    }
}

impl From<NetErr> for HttpErr {
    fn from(e: NetErr) -> Self {
        match e {
            NetErr::Closed => HttpErr::Closed,
            NetErr::Timeout => HttpErr::Timeout,
            NetErr::PermissionDenied => HttpErr::PermissionDenied,
            NetErr::Failed(m) => HttpErr::Failed(m),
            other => HttpErr::Failed(other.message()),
        }
    }
}

impl From<NetErr> for WsErr {
    fn from(e: NetErr) -> Self {
        match e {
            NetErr::Closed => WsErr::Closed,
            NetErr::Timeout => WsErr::Timeout,
            NetErr::PermissionDenied => WsErr::PermissionDenied,
            NetErr::Failed(m) => WsErr::Failed(m),
            other => WsErr::Failed(other.message()),
        }
    }
}

/// The text of a connection the peer reset or aborted (Windows reports a reset after a local
/// write as an abort).
pub const RESET_TEXT: &str = "connection reset by peer";

/// Words a transport failure without host framing (`dial tcp ...: `) or bare
/// sentinels such as `EOF`.
pub fn describe_io_error(err: &io::Error) -> String {
    use io::ErrorKind::*;
    match err.kind() {
        UnexpectedEof => "connection closed before the exchange completed".to_string(),
        ConnectionRefused => "connection refused".to_string(),
        ConnectionReset | ConnectionAborted => RESET_TEXT.to_string(),
        BrokenPipe => "broken pipe".to_string(),
        _ => lowercase_os_text(err),
    }
}

/// OS texts are lower-case (`no such file or directory`); Rust appends
/// ` (os error N)`, which is dropped.
fn lowercase_os_text(err: &io::Error) -> String {
    let text = err.to_string();
    let text = match text.rfind(" (os error ") {
        Some(at) if text.ends_with(')') => text[..at].to_string(),
        _ => text,
    };
    let mut chars = text.chars();
    match chars.next() {
        Some(first) => first.to_lowercase().collect::<String>() + chars.as_str(),
        None => text,
    }
}

/// Message for an unresolvable host name.
pub fn cannot_resolve(name: &str) -> String {
    format!("cannot resolve host {name:?}")
}

impl fmt::Display for NetErr {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.message())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn status_codes_are_the_shared_numbers() {
        assert_eq!(NetErr::InvalidInput.code(), STATUS_INVALID_INPUT);
        assert_eq!(NetErr::Failed("x".into()).code(), STATUS_FAILED);
        assert_eq!(IoErr::Failed("x".into()).code(), STATUS_FAILED);
        assert_eq!(HttpErr::Failed("x".into()).code(), STATUS_FAILED);
        assert_eq!(WsErr::Closed.code(), STATUS_CLOSED);
        assert_eq!(
            TlsErr::AuthenticationFailed.code(),
            STATUS_AUTHENTICATION_FAILED
        );
    }

    #[test]
    fn messages_redact_inputs() {
        assert_eq!(NetErr::Timeout.message(), "network: operation timed out");
        assert_eq!(NetErr::failed("boom").message(), "boom");
        assert_eq!(HttpErr::Closed.message(), "HTTP: resource is closed");
        assert_eq!(WsErr::LimitExceeded.message(), "WebSocket: limit exceeded");
        assert_eq!(
            TlsErr::AuthenticationFailed.message(),
            "TLS: authentication failed"
        );
    }

    #[test]
    fn cannot_resolve_quotes_the_host() {
        assert_eq!(cannot_resolve("no.such"), "cannot resolve host \"no.such\"");
    }
}
