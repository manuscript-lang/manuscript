//! Developer tooling over a checked program: text and JSON output is stable and
//! covered by golden tests.

pub mod collect;
pub mod diagram;
pub mod diff;
pub mod facts;
pub mod flow;
pub mod guide;
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
