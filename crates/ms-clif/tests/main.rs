//! One integration-test binary for the crate: each file below is a module of it, so the
//! crate links once instead of once per file.

mod dwarf;
mod llvm_direct;
mod llvm_direct_data;
mod native;
mod support;
