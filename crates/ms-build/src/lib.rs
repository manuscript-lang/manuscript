//! The Manuscript back end: checked program to native executable.
//!
//! ```text
//! lower (seam) -> optimize (ms-mir) -> ms-clif -> link with ms-rt
//! ```
//!
//! `ms-driver` owns everything before lowering.

// Links the msrt_* runtime symbols that the standard-library crates reference.
#[cfg(test)]
use ms_rt as _;
pub mod lower;
pub mod native;

pub use lower::{Lower, Native, Unavailable};
pub use ms_lower::{FAILURE_MARKER, SKIP_MARKER};
pub use ms_mir::ir::Module;
pub use native::{Profile, build_executable, runtime_override};
