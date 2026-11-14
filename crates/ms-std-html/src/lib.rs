//! `@std/data/html.ms` natives: HTML escaping and character-reference decoding.
#![no_std]

// Links the msrt_* runtime symbols into this crate's test binaries.
#[cfg(test)]
use ms_rt as _;

extern crate alloc;

mod entity;
pub mod escape;
pub mod ffi;

pub use escape::{escape_string as escape, unescape_string as unescape};
