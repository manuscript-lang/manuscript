//! Agent guide, standard-library search and API documentation, including the
//! documentation snapshot behind them.
//!
//! The documentation snapshot ([`api`]) reads the bundled standard library
//! through `ms-check`, or the exports of a checked [`ms_check::Program`]; the
//! rest renders from that snapshot only.

pub mod api;
pub mod docgen;
pub mod json;
pub mod pages;
pub mod render;
pub mod search;
pub mod source;

pub use api::{ApiDeclaration, ApiMember, ApiModule, module_documentation, standard_library};
pub use pages::{Mistake, cheatsheet, index, mistake_entries, mistakes, module_names, page};
pub use search::{Match, format_matches, search};
