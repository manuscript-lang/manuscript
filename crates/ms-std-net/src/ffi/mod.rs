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

pub use crate::bound::Bound;

use crate::error::Status;

/// Records the `Failed` message of `r`'s error and turns it into its status byte.
pub fn report<T, E: Status>(
    r: Result<T, E>,
    err: &ms_rt::ffi::ErrOut,
) -> Result<T, ms_rt::ffi::StatusCode> {
    r.map_err(|e| {
        if crate::rt::cancel_pending() {
            // Every frame that held values across the park has returned and dropped them;
            // the error is the last value, and the jump would skip its destructor.
            drop(e);
            crate::rt::cancelled();
        }
        if let Some(m) = e.failed_message() {
            err.set(m);
        }
        ms_rt::ffi::StatusCode(e.code())
    })
}

/// Flattened `Int?`/`Duration?` parameter.
fn opt(has: bool, v: i64) -> Option<i64> {
    has.then_some(v)
}

/// The status byte of a std error.
pub fn code<E: Status>(e: E) -> ms_rt::ffi::StatusCode {
    if crate::rt::cancel_pending() {
        drop(e);
        crate::rt::cancelled();
    }
    ms_rt::ffi::StatusCode(e.code())
}

macro_rules! handle_newtype {
    ($($(#[$m:meta])* $name:ident($t:ty) $(: $clone:ident)?;)*) => {$(
        $(#[$m])*
        #[repr(transparent)]
        pub struct $name(pub $t);
        ms_rt::ffi::abi_handle!($name $(, $clone)?);
        impl std::ops::Deref for $name {
            type Target = $t;
            fn deref(&self) -> &$t {
                &self.0
            }
        }
    )*};
}

impl Clone for HeadersH {
    /// An independent copy of the headers, not another handle on the same ones.
    fn clone(&self) -> HeadersH {
        HeadersH(Bound::new(std::rc::Rc::new(std::cell::RefCell::new(
            self.0.borrow().clone(),
        ))))
    }
}

handle_newtype! {
    /// A `Network` handle.
    NetH(std::sync::Arc<crate::net::Network>);
    /// A `Connection` handle.
    ConnH(Bound<std::rc::Rc<crate::conn::Connection>>);
    /// A `Listener` handle.
    ListenerH(Bound<std::rc::Rc<crate::conn::Listener>>);
    /// A `DatagramSocket` handle.
    DgramH(Bound<std::rc::Rc<crate::conn::Datagrams>>);
    /// An `HttpHeaders` handle; `HttpHeaders.clone` copies the headers.
    HeadersH(Bound<crate::http::headers::Shared>): clone;
    /// The settings every connection of one `serve` call shares.
    ServingH(std::rc::Rc<crate::ffi::http_server::Serving>);
    /// The server of one `serve` worker thread.
    WorkerH(Bound<std::rc::Rc<crate::http::server::Server>>);
    /// An `HttpClient` handle.
    ClientH(Bound<std::rc::Rc<crate::http::client::Client>>);
    /// An `HttpResponseBody` handle.
    BodyH(Bound<std::rc::Rc<crate::http::client::ResponseBody>>);
    /// An `HttpExchange` handle.
    ExchH(Bound<std::rc::Rc<crate::http::exchange::Exchange>>);
    /// A `WebSocket` handle.
    SocketH(Bound<std::rc::Rc<crate::ws::socket::Socket>>);
    /// An `IpAddress` handle.
    IpH(std::net::IpAddr);
}
