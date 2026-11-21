//! Knobs that change the generated code or the link, gathered in one value. The command line
//! parses them once (flags and environment); every crate below reads fields and never the
//! environment, and the build cache keys on the whole struct, so a new knob is in the key by
//! construction.

use std::path::PathBuf;

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
    /// LLVM vectorizes loops (loop and SLP vectorizers).
    pub vectorize: bool,
    /// Fill each stack slot that lives in one block with a pattern where that block ends
    /// (`MS_POISON_SLOTS=1`), so a pointer that outlives the slot reads garbage in every build
    /// instead of depending on what LLVM reuses the slot for.
    pub poison_slots: bool,
    /// Run LLVM's verifier after every optimizer pass (`MS_LLVM_VERIFY=1`, `opt -verify-each`).
    pub llvm_verify: bool,
    /// Copy the LLVM IR of a release build to `ms-keep.ll`.
    pub keep_ll: bool,
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
    /// Count the MIR operations the program executes (`ms bench --ops`, `MS_COUNT_OPS`).
    pub count_ops: bool,
}

impl Default for BuildOptions {
    fn default() -> Self {
        BuildOptions {
            vectorize: true,
            keep_ll: false,
            llvm_tools: None,
            lld: None,
            runtime: None,
            static_musl: false,
            timings: false,
            copy_probe: CopyProbe::Off,
            count_ops: false,
            poison_slots: false,
            llvm_verify: false,
        }
    }
}

/// A link or object-writing failure.
#[derive(Debug)]
pub struct Error(pub String);

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for Error {}

impl From<String> for Error {
    fn from(s: String) -> Self {
        Error(s)
    }
}
