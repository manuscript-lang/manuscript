//! HIR to MIR lowering for the Rust/Cranelift pipeline.
//!
//! `ms-check` answers what every node of a checked program means; this crate
//! turns the executable bodies into monomorphic MIR (`ms-mir`): generics are
//! instantiated per type argument list, values follow the linear ownership
//! rules of the MIR verifier, and standard-library natives become runtime
//! calls (`ms-rt`) or small MIR sequences.

// Links the msrt_* runtime symbols into this crate's test binaries.
#[cfg(test)]
use ms_rt as _;

mod alias;
mod bound_alias;
mod builder;
mod call;
mod category;
mod close;
mod closure;
mod codecstream;
mod cx;
mod eq;
mod expr;
mod external;
mod fixture;
mod fsinfo;
mod fswalk;
mod func;
mod html;
mod httpserve;
mod iface;
mod iterate;
mod json;
mod lend;
mod lock;
mod mapset;
mod matching;
mod mathops;
mod messages;
mod mutation;
mod natiface;
mod native;
mod random;
mod rtcall;
mod runner;
mod scope;
mod stmt;
mod streamloop;
mod testing;
mod text;

use ms_check::Program;
use ms_mir::ir::Module;
use std::fmt;

/// A lowering failure.
#[derive(Debug, Clone)]
pub struct Error(pub String);

impl Error {
    /// A failure with a message.
    pub fn new(message: impl Into<String>) -> Error {
        Error(message.into())
    }
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for Error {}

/// What to lower.
#[derive(Clone, Debug, Default)]
pub struct Options {
    /// Module file whose `main` is the program entry.
    pub entry: String,
}

/// Lowers the tests of the entry module under a runner entry; returns the module and test names.
pub fn lower_tests(program: &Program, options: &Options) -> Result<(Module, Vec<String>), Error> {
    func::lower_tests(program, options, false)
}

/// Lowers the `bench` blocks of the entry module under a runner entry, like [`lower_tests`]; each
/// block runs under the `@std/bench.ms` driver.
pub fn lower_benches(program: &Program, options: &Options) -> Result<(Module, Vec<String>), Error> {
    func::lower_tests(program, options, true)
}

/// The marker a failed test writes to stderr ahead of its message.
pub use runner::{FAILURE_MARKER, SKIP_MARKER};

/// Lowers a checked program (no diagnostics) to a MIR module with `main` as the entry.
pub fn lower_program(program: &Program, options: &Options) -> Result<Module, Error> {
    func::lower_program(program, options)
}
