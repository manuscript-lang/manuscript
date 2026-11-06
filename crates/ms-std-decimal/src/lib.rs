//! `@std/math/decimal.ms` natives: the C ABI shims over the pure arithmetic in `ms-decimal`.
#![no_std]

extern crate alloc;

pub mod ffi;

pub use ms_decimal::*;
