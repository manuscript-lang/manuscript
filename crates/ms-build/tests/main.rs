//! One integration-test binary for the crate: each file below is a module of it, so the
//! crate links once instead of once per file.

mod close_error_ownership;
mod debug_artifacts;
mod fault_assertion;
mod lower;
mod pinned_build;
#[path = "../../ms-clif/tests/support/mod.rs"]
mod support;
