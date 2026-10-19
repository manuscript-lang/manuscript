//! The `range` pass (see [`crate::opt`] for the pass contract).

use crate::ir::Module;

/// Runs the pass over every function; returns whether anything changed.
pub fn run(_m: &mut Module) -> bool {
    false
}
