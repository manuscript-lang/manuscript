//! One integration-test binary for the crate: each file below is a module of it, so the
//! crate links once instead of once per file.

mod copies;
mod elaborate;
mod intern;
mod interp;
mod outline;
mod persist;
mod text;
mod unwind;
mod view_provenance;
