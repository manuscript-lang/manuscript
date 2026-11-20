//! Small standard-library natives that share one crate: Base64 for `@std/data/encoding.ms`
//! (`msstd_encoding_*`) and the checksums ms-std-archive still calls. `@std/math`, `@std/random.ms` and
//! `@std/data/checksum.ms` are C (runtime/std/stdmath.c, random.c, checksum.c).
//! Unicode properties and bounded UTF-8 scalars use `msstd_unicode_*` and `msstd_utf8_*`.

extern crate alloc;

// Links the msrt_* runtime symbols into this crate's test binaries.
#[cfg(test)]
use ms_rt as _;

pub mod checksum;
pub mod encoding;
pub mod unicode;
