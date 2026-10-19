//! The Manuscript build driver: source to native executable.
//!
//! ```text
//! load (ms-project, ms-syntax) -> check (ms-check) -> lower (seam) -> optimize (ms-mir)
//!   -> ms-clif -> link with ms-rt
//! ```
//!
//! The command line (`ms-cli`) owns arguments, output formats and exit
//! statuses; this crate owns everything between a file name and an executable.

pub mod compile;
pub mod load;
pub mod lower;
pub mod native;

pub use compile::{CheckRequest, Checked, check_graph, check_graph_at};
pub use load::{EditorOptions, Graph, LoadOptions, load_editor_file, load_file};
pub use lower::{Lower, LowerOptions, Native, Unavailable};
pub use ms_mir::ir::Module;
pub use native::{Profile, build_executable, runtime_override};

/// The syntax types diagnostics are made of.
pub use ms_syntax::{Diagnostic, Phase, Pos};
