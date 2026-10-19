//! Manuscript syntax: positions, diagnostics, the typed AST, the lexer with
//! layout, the strict and recovering parsers, and the formatter.
//!
//! The Go implementation in `pkg/{syntax,lexer,parser,tooling/format}` is the
//! behavioural authority; diagnostics (message, position, phase) and formatter
//! output are byte-identical to it.

pub mod ast;
pub mod diag;
pub mod pos;
pub mod symbol;
pub mod visit;

pub use ast::*;
pub use diag::{Diagnostic, DiagnosticFix, Phase};
pub use pos::{Pos, Span};
pub use symbol::Symbol;
