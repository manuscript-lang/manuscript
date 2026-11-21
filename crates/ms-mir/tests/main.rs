//! One integration-test binary for the crate: each file below is a module of it, so the
//! crate links once instead of once per file.

mod cancel_edges;
mod copies;
mod depth;
mod elaborate;
mod exit_drops;
mod intern;
mod interp;
mod outline;
mod persist;
mod text;
mod unwind;
mod view_provenance;
