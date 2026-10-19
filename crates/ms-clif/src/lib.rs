//! Native backend: lowers verified MIR to Cranelift, emits an object file, and
//! links it with the system toolchain and the runtime static library.
//!
//! Values are flattened into scalar leaves (see [`layout`]). Ownership follows
//! the MIR rules: the generated code drops owned values at their `drop`
//! instructions only; reference-counted strings are the only values with
//! compiler-visible counts. Frame pointers are always kept so the runtime can
//! walk stacks for fault traces and sampling profiles.

pub mod layout;
pub mod link;

mod gen;
mod lower;

use ms_mir::ir::Module;

/// Code generation options.
#[derive(Clone, Debug)]
pub struct Options {
    /// Emit overflow, division, bounds and unwrap checks. Turning this off is
    /// only valid for benchmarks that measure check cost.
    pub checks: bool,
    /// Poll the cancellation flag at `poll` instructions.
    pub poll: bool,
    /// Cranelift optimization level: `"speed"`, `"speed_and_size"` or `"none"`.
    pub opt_level: &'static str,
    /// Dump Cranelift IR of every function to stderr.
    pub dump_clif: bool,
}

impl Default for Options {
    fn default() -> Self {
        Options { checks: true, poll: true, opt_level: "speed", dump_clif: false }
    }
}

/// A code generation or link failure.
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

/// Compiles a verified module to a relocatable object file.
pub fn compile(m: &Module, opts: &Options) -> Result<Vec<u8>, Error> {
    gen::compile(m, opts)
}
