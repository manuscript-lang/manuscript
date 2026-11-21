//! MIR: the typed SSA/CFG intermediate representation between the checker's
//! typed program and the native backend.

pub mod builder;
pub mod cancel_edges;
pub mod cancel_exit;
pub mod copies;
pub mod count_ops;
pub mod debug_files;
pub mod debug_types;
pub mod depth;
pub mod elaborate;
pub mod exit_drops;
pub mod expand;
pub mod expand_owned;
pub mod fault_tables;
pub mod frames;
pub mod glue;
/// The reference interpreter, used by tests as an oracle; compiled only for them.
#[cfg(feature = "test-support")]
pub mod interp;
pub mod ir;
pub mod layout;
pub mod parse;
pub mod persist;
pub mod print;
pub mod slot_scope;
pub mod statics;
pub mod types;
pub mod unwind;
pub mod verify;
pub mod vmap;
