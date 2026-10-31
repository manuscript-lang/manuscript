//! Error types of the network modules and their diagnostics.
//!
//! The status byte a fallible native returns is `1 + the case's declaration
//! index` in the corresponding `stdlib/*.ms` error type (`0` is success).
//! The `Failed` case carries its message through a trailing `*mut StrVal`.

use std::fmt;
use std::io;

/// `NetworkError` of `@std/net.ms`.
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

/// `IoError` of `@std/io.ms`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum IoErr {
    Closed,
    InvalidInput,
    Unavailable,
    InvalidData,
    LimitExceeded,
    Failed(String),
}

/// `HttpError` of `@std/http.ms`.
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

/// `WebSocketError` of `@std/net.ms`.
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

/// `TlsError` of `@std/net.ms`.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TlsErr {
    InvalidInput,
    InvalidData,
    LimitExceeded,
    AuthenticationFailed,
}

/// A status code and the optional message of a `Failed` case.
pub trait Status {
    /// Status byte (`1 + declaration index`).
    fn code(&self) -> u8;
    /// Message of the `Failed` case.
    fn failed_message(&self) -> Option<&str>;
}

impl Status for NetErr {
    fn code(&self) -> u8 {
        match self {
            NetErr::InvalidInput => 1,
            NetErr::InvalidData => 2,
            NetErr::LimitExceeded => 3,
            NetErr::PermissionDenied => 4,
            NetErr::Unsupported => 5,
            NetErr::Closed => 6,
            NetErr::Timeout => 7,
            NetErr::Failed(_) => 8,
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
            IoErr::Closed => 1,
            IoErr::InvalidInput => 2,
            IoErr::Unavailable => 3,
            IoErr::InvalidData => 4,
            IoErr::LimitExceeded => 5,
            IoErr::Failed(_) => 6,
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
            HttpErr::InvalidInput => 1,
            HttpErr::InvalidData => 2,
            HttpErr::LimitExceeded => 3,
            HttpErr::PermissionDenied => 4,
            HttpErr::Closed => 5,
            HttpErr::Timeout => 6,
            HttpErr::Failed(_) => 7,
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
            WsErr::InvalidInput => 1,
            WsErr::InvalidData => 2,
            WsErr::LimitExceeded => 3,
            WsErr::PermissionDenied => 4,
            WsErr::Closed => 5,
            WsErr::Timeout => 6,
            WsErr::Failed(_) => 7,
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
            TlsErr::InvalidInput => 1,
            TlsErr::InvalidData => 2,
            TlsErr::LimitExceeded => 3,
            TlsErr::AuthenticationFailed => 4,
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
    format!("cannot resolve host {}", quote_text(name))
}

/// Quotes the characters host names can hold.
pub fn quote_text(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 || c as u32 == 0x7f => {
                out.push_str(&format!("\\x{:02x}", c as u32))
            }
            c => out.push(c),
        }
    }
    out.push('"');
    out
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
    fn status_codes_follow_declaration_order() {
        assert_eq!(NetErr::InvalidInput.code(), 1);
        assert_eq!(NetErr::Failed("x".into()).code(), 8);
        assert_eq!(IoErr::Failed("x".into()).code(), 6);
        assert_eq!(HttpErr::Failed("x".into()).code(), 7);
        assert_eq!(WsErr::Closed.code(), 5);
        assert_eq!(TlsErr::AuthenticationFailed.code(), 4);
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
    fn quoting_matches_oracle() {
        assert_eq!(quote_text("a\"b"), "\"a\\\"b\"");
        assert_eq!(cannot_resolve("no.such"), "cannot resolve host \"no.such\"");
    }
}
