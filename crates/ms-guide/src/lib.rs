//! Agent guide, standard-library search and API documentation: a port of
//! `pkg/tooling/guide`, `pkg/tooling/docgen`, `scripts/docgen` and the
//! documentation snapshot in `pkg/checker`. The Go implementation is the
//! oracle; output is byte-identical.
//!
//! The documentation snapshot ([`api`]) reads the bundled standard library
//! through `ms-check`, or the exports of a checked [`ms_check::Program`]; the
//! rest renders from that snapshot only.

pub mod api;
pub mod docgen;
pub mod guide;
pub mod json;
pub mod render;
pub mod search;
pub mod source;

pub use api::{ApiDeclaration, ApiMember, ApiModule, module_documentation, standard_library};
pub use guide::{cheatsheet, index, module_names, page};
pub use search::{Match, format_matches, search};
