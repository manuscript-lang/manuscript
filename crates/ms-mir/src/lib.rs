//! MIR: the typed SSA/CFG intermediate representation between the checker's
//! typed program and the native backend.

pub mod builder;
pub mod ir;
pub mod parse;
pub mod print;
pub mod types;
pub mod verify;
