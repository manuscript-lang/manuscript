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
mod borrow_shape;
mod bound_alias;
mod call;
mod close;
mod closure;
mod constmap;
mod cx;
mod eq;
mod expr;
mod external;
mod fixture;
mod fsinfo;
mod fswalk;
mod func;
mod fuse;
mod hoist;
mod httpserve;
mod iface;
mod iterate;
mod json;
mod mapset;
mod matching;
mod mathops;
mod mutation;
mod natiface;
mod native;
mod nativetype;
mod rtcall;
mod rtinline;
mod rtstr;
mod runner;
mod scalar;
mod scope;
mod stdnative;
mod stmt;
mod testing;
mod text;
mod textbuilder;

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
pub fn lower_tests(
    syms: ms_check::api::Names,
    program: &Program,
    options: &Options,
) -> Result<(Module, Vec<String>), Error> {
    func::lower_tests(syms, program, options, false)
}

/// Lowers the `bench` blocks of the entry module under a runner entry, like [`lower_tests`]; each
/// block runs under the `@std/test/bench.ms` driver.
pub fn lower_benches(
    syms: ms_check::api::Names,
    program: &Program,
    options: &Options,
) -> Result<(Module, Vec<String>), Error> {
    func::lower_tests(syms, program, options, true)
}

/// Lowers a checked program (no diagnostics) to a MIR module with `main` as the entry.
pub fn lower_program(
    syms: ms_check::api::Names,
    program: &Program,
    options: &Options,
) -> Result<Module, Error> {
    func::lower_program(syms, program, options)
}
