//! Native implementations of `@std/net.ms`, `@std/net.ms`, `@std/http.ms` and
//! `@std/net.ms` behind the `ms-rt` C ABI (see `ABI.md`).
//!
//! The logic is ordinary Rust over `&str`/`&[u8]`; the `ffi` module holds the
//! `extern "C"` shims.
//!
//! The `http` feature (default) adds the HTTP client and server, HTTP/2 and WebSocket; without
//! it the crate is sockets, DNS and TLS only.
#![allow(unsafe_code)]

pub mod addr;
pub mod conn;
pub mod dn;
pub mod dns;
pub mod error;
pub mod ffi;
#[cfg(feature = "http")]
pub mod h2;
#[cfg(feature = "http")]
pub mod http;
pub mod ip;
pub mod net;
pub mod policy;
mod reactor;
pub mod rt;
pub mod sys;
pub mod tls;
pub mod wait;
#[cfg(feature = "http")]
pub mod ws;

#[cfg(test)]
extern crate ms_rt;
