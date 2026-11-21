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
pub mod lower;
pub mod native;

pub use lower::{Lower, Native, Unavailable};
pub use ms_clif::link::debug_companion_path;
pub use ms_clif::{BuildOptions, CopyProbe};
pub use ms_mir::ir::Module;
pub use native::{
    Backend, Profile, backend_name, build_executable, native_inputs, publish, runtime_override,
};
