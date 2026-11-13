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
pub mod cache;
pub mod llvm;
pub use llvm::available as llvm_available;
pub mod lower;
pub mod native;

pub use lower::{Lower, Native, Unavailable};
pub use ms_clif::link::debug_companion_path;
pub use ms_clif::{BuildOptions, CopyProbe, RtHot};
pub use ms_lower::SKIP_MARKER;
pub use ms_mir::ir::Module;
pub use native::{
    Backend, Profile, backend_name, build_executable, build_executable_pinned, native_inputs,
    publish, runtime_override,
};
