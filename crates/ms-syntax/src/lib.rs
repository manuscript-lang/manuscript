//! Manuscript syntax: positions, diagnostics, the typed AST, the lexer with
//! layout, the strict and recovering parsers, and the formatter.
//!

pub mod ast;
pub mod diag;
pub mod dump;
pub mod format;
pub mod lexer;
pub mod parser;
pub mod partial;
pub mod pos;
pub mod symbol;
pub mod token;
pub mod visit;

pub use ast::*;
pub use diag::{Diagnostic, DiagnosticFix, Phase};
pub use format::format;
pub use partial::parse_partial;
pub use pos::{Pos, Span};
pub use symbol::Symbol;
