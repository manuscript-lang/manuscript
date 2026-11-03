//! Knobs that change the generated code or the link, gathered in one value. The command line
//! parses them once (flags and environment); every crate below reads fields and never the
//! environment, and the build cache keys on the whole struct, so a new knob is in the key by
//! construction.

use std::path::PathBuf;

/// Which runtime helper IR release builds link in so the helpers inline.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub enum RtHot {
    /// The IR embedded in `ms`.
    Embedded,
    /// None, to compare against a build without inlined helpers.
    Off,
    /// Another helper library, for experiments.
    File(PathBuf),
}

/// Build settings shared by code generation, linking and the build cache.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct BuildOptions {
    /// Release builds use Cranelift even when the LLVM tools are available.
    pub cranelift_only: bool,
    /// Count string allocations in generated code.
    pub count_str: bool,
    /// LLVM vectorizes loops and builds AVX2 copies of them.
    pub vectorize: bool,
    /// Copy the LLVM IR of a release build to `ms-keep.ll`.
    pub keep_ll: bool,
    /// The runtime helper IR linked into release programs.
    pub rt_hot: RtHot,
    /// A directory holding `opt`, `llc` and `llvm-link`, instead of the pinned release.
    pub llvm_tools: Option<PathBuf>,
    /// An `lld` to link with, instead of the pinned release.
    pub lld: Option<PathBuf>,
    /// A runtime archive that replaces the one embedded in `ms`.
    pub runtime: Option<PathBuf>,
    /// Link static musl (`--static`) instead of glibc on Linux.
    pub static_musl: bool,
    /// Print the time at which each build phase finished.
    pub timings: bool,
}

impl Default for BuildOptions {
    fn default() -> Self {
        BuildOptions {
            cranelift_only: false,
            count_str: false,
            vectorize: true,
            keep_ll: false,
            rt_hot: RtHot::Embedded,
            llvm_tools: None,
            lld: None,
            runtime: None,
            static_musl: false,
            timings: false,
        }
    }
}
