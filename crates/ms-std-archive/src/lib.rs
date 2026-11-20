//! `@std/io/archive.ms` compression natives: gzip, zlib and raw deflate encoders and decoders.
//! Zip and tar packing live in Manuscript (`stdlib/internal/{zip,tar,archive_codec}.ms`).
//! Zip members are compressed with miniz_oxide.
#![no_std]

// Links the msrt_* runtime symbols into this crate's test binaries.
#[cfg(test)]
use ms_rt as _;

extern crate alloc;

pub mod compress;
