//! The native surface, declared with `native!` over safe Rust signatures. See `ABI.md`.
//!
//! - Status: fallible natives return `0` on success and `1 + case index` of the
//!   error type otherwise; `Failed(message)` is stored through the trailing
//!   `err` slot (`ErrOut`, which may be null) by [`report`].
//! - Optional parameters flatten to `has: bool, value`; optional results use a
//!   `present` out or `STATUS_NONE`.
//! - Handles (`Network`, `Connection`, ...) are reference-counted runtime
//!   objects holding the newtypes below, dropped by the runtime when the count
//!   reaches zero. Only `handler` calls back into compiled code and keeps raw
//!   pointers.

pub mod handler;
pub mod http_client;
pub mod http_server;
pub mod net;
pub mod tls;
pub mod websocket;

use crate::error::Status;

/// Records the `Failed` message of `r`'s error and turns it into its status byte.
pub fn report<T, E: Status>(
    r: Result<T, E>,
    err: &ms_std_core::ErrOut,
) -> Result<T, ms_std_core::StatusCode> {
    r.map_err(|e| {
        if let Some(m) = e.failed_message() {
            err.set(m);
        }
        ms_std_core::StatusCode(e.code())
    })
}

/// Flattened `Optional[Int]`/`Optional[Duration]` parameter.
fn opt(has: bool, v: i64) -> Option<i64> {
    has.then_some(v)
}

/// The status byte of a std error.
pub fn code<E: Status>(e: E) -> ms_std_core::StatusCode {
    ms_std_core::StatusCode(e.code())
}

macro_rules! handle_newtype {
    ($($(#[$m:meta])* $name:ident($t:ty);)*) => {$(
        $(#[$m])*
        #[repr(transparent)]
        pub struct $name(pub $t);
        ms_std_core::abi_handle!($name);
        impl std::ops::Deref for $name {
            type Target = $t;
            fn deref(&self) -> &$t {
                &self.0
            }
        }
    )*};
}

handle_newtype! {
    /// A `Network` handle.
    NetH(std::rc::Rc<crate::net::Network>);
    /// A `Connection` handle.
    ConnH(std::rc::Rc<crate::conn::Connection>);
    /// A `Listener` handle.
    ListenerH(std::rc::Rc<crate::conn::Listener>);
    /// A `DatagramSocket` handle.
    DgramH(std::rc::Rc<crate::conn::Datagrams>);
    /// An `HttpHeaders` handle.
    HeadersH(crate::http::headers::Shared);
    /// An `HttpServer` handle.
    ServerH(std::rc::Rc<crate::http::server::Server>);
    /// An `HttpClient` handle.
    ClientH(std::rc::Rc<crate::http::client::Client>);
    /// An `HttpResponseBody` handle.
    BodyH(std::rc::Rc<crate::http::client::ResponseBody>);
    /// An `HttpExchange` handle.
    ExchH(std::rc::Rc<crate::http::exchange::Exchange>);
    /// A `WebSocket` handle.
    SocketH(std::rc::Rc<crate::ws::socket::Socket>);
    /// An `IpAddress` handle.
    IpH(std::net::IpAddr);
}
