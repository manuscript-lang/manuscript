//! The Manuscript front-end driver: file name to checked program.
//!
//! ```text
//! load (project, ms-syntax) -> check (ms-check)
//! ```
//!
//! Lowering, optimization, code generation and linking live in `ms-build`, so
//! tools that only read programs (the language server) do not link a code
//! generator. The command line (`ms-cli`) owns arguments, output formats and
//! exit statuses.

pub mod compile;
pub mod load;
pub mod project;

pub use compile::{CheckRequest, Checked, check_graph, check_graph_at};
pub use load::{EditorOptions, Graph, LoadOptions, load_editor_file, load_file};

/// The syntax types diagnostics are made of.
pub use ms_syntax::{Diagnostic, Phase, Pos};
