//! One integration-test binary for the crate: each file below is a module of it, so the
//! crate links once instead of once per file.

mod sort_guard;
mod task_deadlock;
mod trap_isolation;
