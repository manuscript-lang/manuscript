//! The Manuscript language server.
//!
//! [`serve`] speaks LSP over framed JSON-RPC. Every feature reads a checked
//! [`ms_check::Program`] built by `ms-driver` from the open documents and the
//! files they import; the Go server in `pkg/tooling/lsp` is the behavioural
//! authority.

pub mod actions;
pub mod analysis;
pub mod completion;
pub mod editor;
pub mod features;
pub mod index;
pub mod json;
pub mod lexical;
pub mod lint;
pub mod nav;
pub mod query;
pub mod rename;
pub mod semantic;
pub mod server;
pub mod supervise;
pub mod symbols;
pub mod text;
pub mod transport;
pub mod uri;
pub mod workspace;

pub use server::{serve, serve_with};
pub use supervise::supervise;
