//! The Manuscript back end: checked program to native executable.
//!
//! ```text
//! lower (seam) -> C back end (libms, LLVM) -> link with ms-rt
//! ```
//!
//! `ms-driver` owns everything before lowering.

pub mod c_backend;
pub mod llvm;
pub use llvm::available as llvm_available;
pub mod link;
pub mod lower;
pub mod native;
mod options;

pub use link::debug_companion_path;
pub use lower::{Lower, Native, Unavailable};
pub use ms_mir::ir::Module;
pub use native::{
    Backend, Profile, backend_name, build_executable, native_inputs, publish, runtime_override,
};
pub use options::{BuildOptions, CopyProbe, Error};
