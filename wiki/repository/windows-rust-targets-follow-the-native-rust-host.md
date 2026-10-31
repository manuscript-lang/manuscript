[Wiki](../index.md) › [Repository maintenance](index.md)

# Windows Rust targets follow the native Rust host

Verified: an emulated MSYS shell on Windows ARM64 reports `x86_64` from `uname -m`, while
CI selects an `aarch64-pc-windows-msvc` Rust host and installs its matching gnullvm target.
Derive a wrapper's Windows runtime architecture from `rustc -vV`, as target setup does,
rather than the shell architecture. The target and bundled clang prefix must agree.


Apply when: shell wrappers build a Windows runtime or select an architecture-specific tool.
Evidence: [target setup](../../.github/actions/native-toolchain/action.yml), [runtime build](../../crates/xtask/src/main.rs), [stats runtime helper](../../tools/lib.ms).
Verify: an x64 MSYS shell with an ARM64 Rust host selects the ARM64 target and clang; the native x64 case still selects x64. The mock stops at the first Cargo invocation without building or running an allocation-check program.
