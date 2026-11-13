//! MIR: the typed SSA/CFG intermediate representation between the checker's
//! typed program and the native backend.

pub mod builder;
pub mod copies;
pub mod elaborate;
pub mod exit_drops;
pub mod fault_tables;
pub mod frames;
/// The reference interpreter, used by tests as an oracle; compiled only for them.
#[cfg(feature = "test-support")]
pub mod interp;
pub mod ir;
pub mod layout;
pub mod opt;
pub mod parse;
pub mod print;
pub mod types;
pub mod unwind;
pub mod verify;
pub mod vmap;
