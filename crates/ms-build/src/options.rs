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
    /// How many objects LLVM compiles a release program into, in parallel; `None` picks one per
    /// core for programs big enough to repay it, and 1 keeps the whole program in one module.
    pub llvm_units: Option<usize>,
    /// LLVM vectorizes loops (loop and SLP vectorizers).
    pub vectorize: bool,
    /// Tell LLVM the heap functions are an allocator (`MS_HEAP_FACTS=off` turns it off): it then
    /// deletes blocks nothing reads and pairs frees with allocations. The ownership-count gate
    /// turns it off so every block the compiler asks for is counted.
    pub heap_facts: bool,
    /// Fill each stack slot that holds a statement-scoped temporary with a pattern where its
    /// use ends (`MS_POISON_SLOTS=1`), so a pointer that outlives the slot reads garbage in
    /// every build instead of depending on what the code generator reuses the slot for.
    pub poison_slots: bool,
    /// Run LLVM's verifier after every optimizer pass (`opt -verify-each`).
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
            llvm_units: None,
            vectorize: true,
            heap_facts: true,
            poison_slots: false,
            llvm_verify: false,
            keep_ll: false,
            llvm_tools: None,
            lld: None,
            runtime: None,
            static_musl: false,
            timings: false,
            copy_probe: CopyProbe::Off,
            count_ops: false,
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
