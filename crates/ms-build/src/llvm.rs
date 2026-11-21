//! Whether the pinned LLVM tools the C back end drives (`opt`, `llc`) can be used.

use crate::BuildOptions;
use crate::link::llvm_tools;

/// Whether builds can use LLVM: the tools are fetched or named by `build.llvm_tools`.
pub fn available(build: &BuildOptions) -> bool {
    llvm_tools(build).is_ok_and(|tools| tools.is_some())
}
