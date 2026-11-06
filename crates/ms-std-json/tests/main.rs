//! One integration-test binary for the crate: each file below is a module of it, so the
//! crate links once instead of once per file.

mod failure;
mod oracle;
mod roundtrip;
mod writer;
