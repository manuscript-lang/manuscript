//! Native implementations of `@std/net.ms`, `@std/tls.ms`, `@std/http.ms` and
//! `@std/websocket.ms` behind the `ms-rt` C ABI (see `ABI.md`).
//!
//! The logic is ordinary Rust over `&str`/`&[u8]`; the `ffi` module holds the
//! `extern "C"` shims.
#![allow(unsafe_code)]

pub mod addr;
pub mod conn;
pub mod dn;
pub mod dns;
pub mod error;
pub mod ffi;
pub mod h2;
pub mod http;
pub mod ip;
pub mod net;
pub mod policy;
pub mod rt;
pub mod sys;
pub mod tls;
pub mod wait;
pub mod ws;

#[cfg(test)]
extern crate ms_rt;
