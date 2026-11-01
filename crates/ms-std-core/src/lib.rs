//! Small standard-library natives that share one crate: `@std/math` (`msstd_math_*`),
//! `@std/os/random.ms` (`msstd_random_*`) and Base64 for `@std/data/encoding.ms`
//! (`msstd_encoding_*`).

extern crate alloc;

// Links the msrt_* runtime symbols into this crate's test binaries.
#[cfg(test)]
use ms_rt as _;

pub mod encoding;
pub mod math;
pub mod random;
