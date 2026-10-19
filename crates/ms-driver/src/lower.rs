//! The seam between the checker and the code generator.
//!
//! HIR to MIR lowering is its own workstream; the driver builds against this
//! trait so the pipeline, the CLI and their tests do not depend on it landing.

use ms_check::Program;
use ms_mir::ir::Module;

/// What the lowering must produce.
#[derive(Clone, Copy, Debug, Default)]
pub struct LowerOptions {
    /// Build the test executable instead of the program: its entry follows the
    /// process protocol in `ms_cli::engine::testing` (`--list`, `--run-test=<index>`).
    pub tests: bool,
    /// Debug build: keep bindings observable.
    pub debug: bool,
}

/// Lowers a checked, diagnostic-free program to a verified MIR module whose
/// `entry` is the process entry (`fn() -> Int`, the exit status).
pub trait Lower {
    /// `entry` is the logical path of the entry module ("" for a library under test).
    fn lower(
        &self,
        program: &Program,
        entry: &str,
        options: &LowerOptions,
    ) -> Result<Module, String>;
}

/// The lowering used until HIR to MIR lowering lands: every program fails
/// with a stable message and the CLI reports it as a `lowering` diagnostic.
pub struct Unavailable;

/// The message [`Unavailable`] reports.
pub const UNAVAILABLE: &str = "lowering from the typed HIR to MIR is not available yet in the Rust implementation; use the Go ms until it lands";

impl Lower for Unavailable {
    fn lower(&self, _: &Program, _: &str, _: &LowerOptions) -> Result<Module, String> {
        Err(UNAVAILABLE.to_string())
    }
}
