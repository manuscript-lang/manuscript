//! The `extern "C"` surface: thin shims that marshal runtime values into the
//! safe Rust API and back. See `ABI.md` for the conventions.
//!
//! - Status: fallible natives return `0` on success and `1 + case index` of the
//!   error type otherwise; `Failed(message)` is stored through the trailing
//!   `err: *mut *mut StrObj` (which may be null).
//! - Optional parameters flatten to `has: u8, value`; optional results use a
//!   `present: *mut u8` out pointer.
//! - Handles (`Network`, `Connection`, ...) are reference-counted runtime
//!   objects: an `Obj` header followed by the Rust value, dropped by the runtime
//!   when the count reaches zero.

pub mod http;
pub mod net;
pub mod tls;
pub mod websocket;

use crate::error::Status;
use ms_rt_abi::{Obj, StrObj};
use ms_std_core::new_string;

unsafe extern "C" {
    fn msrt_alloc(size: usize) -> *mut u8;
    fn msrt_free(p: *mut u8);
}

/// An object header followed by a Rust value.
#[repr(C)]
pub struct Handle<T> {
    hdr: Obj,
    value: T,
}

unsafe extern "C" fn drop_handle<T>(o: *mut Obj) {
    let h = o.cast::<Handle<T>>();
    // SAFETY: the runtime calls the drop entry once, with the count at zero, on an object
    // that `new_handle::<T>` built; the value is dropped in place before the block is freed.
    unsafe {
        std::ptr::drop_in_place(&raw mut (*h).value);
        msrt_free(o.cast());
    }
}

/// Allocates a runtime object holding `value` (count 1).
pub fn new_handle<T>(value: T) -> *mut Obj {
    assert!(std::mem::align_of::<T>() <= 16, "handle alignment");
    // SAFETY: `msrt_alloc` returns 16-aligned memory of the requested size; the header and
    // value are initialised before the pointer escapes.
    unsafe {
        let p = msrt_alloc(std::mem::size_of::<Handle<T>>()).cast::<Handle<T>>();
        p.write(Handle {
            hdr: Obj {
                rc: 1,
                drop: Some(drop_handle::<T>),
            },
            value,
        });
        p.cast()
    }
}

/// Borrows the value of a handle created by [`new_handle`].
///
/// # Safety
/// `o` is a live object built by `new_handle::<T>` that outlives `'a`.
pub unsafe fn handle_ref<'a, T>(o: *const Obj) -> &'a T {
    // SAFETY: caller contract.
    unsafe { &(*o.cast::<Handle<T>>()).value }
}

/// Writes the status of `r`, running `ok` on success and storing a `Failed` message.
///
/// # Safety
/// `err` is null or writable.
pub unsafe fn finish<T, E: Status>(
    r: Result<T, E>,
    err: *mut *mut StrObj,
    ok: impl FnOnce(T),
) -> u8 {
    match r {
        Ok(v) => {
            ok(v);
            0
        }
        Err(e) => {
            if let Some(m) = e.failed_message()
                && !err.is_null()
            {
                // SAFETY: `err` is writable per the contract.
                unsafe { *err = new_string(m) };
            }
            e.code()
        }
    }
}

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
    /// An `HttpExchange` handle.
    ExchH(std::rc::Rc<crate::http::exchange::Exchange>);
    /// A `WebSocket` handle.
    SocketH(std::rc::Rc<crate::ws::socket::Socket>);
    /// An `IpAddress` handle.
    IpH(std::net::IpAddr);
}

/// Flattened `Optional[Int]`/`Optional[Duration]` parameter.
pub fn opt(has: u8, v: i64) -> Option<i64> {
    ms_std_core::opt(has, v)
}
