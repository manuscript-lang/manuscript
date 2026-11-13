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

/// What the build does with a `copy` of an object value, which one-owner lowering must not emit.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Default)]
pub enum CopyProbe {
    /// Nothing.
    #[default]
    Off,
    /// Print each copy to standard error and build on.
    Report,
    /// Fail the build.
    Strict,
}

/// Build settings shared by code generation, linking and the build cache.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct BuildOptions {
    /// Release builds use Cranelift even when the LLVM tools are available.
    pub cranelift_only: bool,
    /// How many objects LLVM compiles a release program into, in parallel; `None` picks one per
    /// core for programs big enough to repay it, and 1 keeps the whole program in one module.
    pub llvm_units: Option<usize>,
    /// LLVM vectorizes loops (loop and SLP vectorizers).
    pub vectorize: bool,
    /// Run LLVM's verifier after every optimizer pass (`opt -verify-each`).
    pub llvm_verify: bool,
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
    /// Report or reject copies of object values in the lowered code.
    pub copy_probe: CopyProbe,
}

impl Default for BuildOptions {
    fn default() -> Self {
        BuildOptions {
            cranelift_only: false,
            llvm_units: None,
            vectorize: true,
            llvm_verify: false,
            keep_ll: false,
            rt_hot: RtHot::Embedded,
            llvm_tools: None,
            lld: None,
            runtime: None,
            static_musl: false,
            timings: false,
            copy_probe: CopyProbe::Off,
        }
    }
}
