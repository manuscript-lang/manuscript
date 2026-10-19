//! Developer tooling over a checked program: a port of `pkg/tooling`. The Go
//! implementation is the oracle; text and JSON output is byte-identical.

pub mod collect;
pub mod diagram;
pub mod diff;
pub mod facts;
pub mod flow;
pub mod gosort;
pub mod inspect;
pub mod json;
pub mod labels;
pub mod lint;
pub mod mark;
pub mod report;
pub mod review;
pub mod sha256;
pub mod tree;
pub mod views;
mod walk;
