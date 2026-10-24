//! The seam between the checker and the code generator.
//!
//! The command line builds against [`Lower`], so tests can inject MIR and the
//! pipeline does not depend on the lowering crate's API.

use ms_check::Program;
use ms_mir::ir::Module;

/// Lowers a checked, diagnostic-free program to a verified MIR module.
pub trait Lower {
    /// A program whose `entry` is the process entry (`fn() -> Int`, the exit
    /// status). `entry` is the logical path of the entry module.
    fn lower(&self, program: &Program, entry: &str) -> Result<Module, String>;

    /// A test executable and its test names, in index order. Its entry runs the
    /// test whose index is the first program argument; see `ms_cli::engine::testing`.
    fn lower_tests(
        &self,
        _program: &Program,
        _entry: &str,
    ) -> Result<(Module, Vec<String>), String> {
        Err("this lowering does not build tests".to_string())
    }
}

/// HIR to MIR lowering by `ms-lower`.
pub struct Native;

impl Lower for Native {
    fn lower(&self, program: &Program, entry: &str) -> Result<Module, String> {
        let options = ms_lower::Options {
            entry: entry.to_string(),
        };
        ms_lower::lower_program(program, &options).map_err(|e| e.to_string())
    }

    fn lower_tests(&self, program: &Program, entry: &str) -> Result<(Module, Vec<String>), String> {
        let options = ms_lower::Options {
            entry: entry.to_string(),
        };
        ms_lower::lower_tests(program, &options).map_err(|e| e.to_string())
    }
}

/// A lowering that always fails, for tests of the stages before it.
pub struct Unavailable;

/// The message [`Unavailable`] reports.
pub const UNAVAILABLE: &str = "lowering is not available";

impl Lower for Unavailable {
    fn lower(&self, _: &Program, _: &str) -> Result<Module, String> {
        Err(UNAVAILABLE.to_string())
    }
}
