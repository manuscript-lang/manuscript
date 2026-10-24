//! MIR optimizer: a fixed pipeline of independent passes over a verified module.
//!
//! Every pass takes `&mut Module`, keeps the module verifying, and returns whether it
//! changed anything. Passes must preserve observable behavior: output, exit status,
//! the first fault and its message, and cleanup order. Concretely:
//!
//! * An instruction with [`Effects::faults`](crate::ir::Effects) may only be removed
//!   or weakened (for example `iadd.chk` to `iadd`) when the pass has proven it cannot
//!   fault, and may not be moved across an instruction with `writes` or `io` effects or
//!   past another faulting instruction (the first fault decides the message).
//! * Pure instructions (no effects) can be moved, merged and duplicated freely.
//! * Ownership stays linear: a pass may delete a `drop` only together with the
//!   allocation it pairs with, and must never duplicate a consumed owned value.
//! * `poll` instructions are not inserted on loop back edges (the stop signal is observed
//!   at runtime calls and I/O); a pass must keep any `poll` that is present.

use crate::ir::Module;

pub mod copyelim;
pub mod ifconv;
pub mod inline;
pub mod lastuse;
pub mod optparam;
pub mod range;
pub mod reserve;
pub mod simplify;
pub mod slotfuse;
pub mod sortgen;
pub mod strfuse;

/// Optimization level.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Level {
    /// No optimization.
    None,
    /// The full pipeline.
    Speed,
}

/// Runs the pipeline. With `verify`, the module is re-verified after every pass and
/// the first failure panics with the pass name (used by tests and debug builds).
pub fn optimize(m: &mut Module, level: Level, verify: bool) {
    if level == Level::None {
        return;
    }
    let check = |m: &Module, pass: &str| {
        if !verify {
            return;
        }
        if let Err(errs) = crate::verify::verify_module(m) {
            let text = errs
                .iter()
                .map(|e| e.to_string())
                .collect::<Vec<_>>()
                .join("\n");
            panic!(
                "module does not verify after {pass}:\n{text}\n{}",
                crate::print::print_module(m)
            );
        }
    };
    simplify::run(m);
    check(m, "simplify");
    copyelim::run(m);
    check(m, "copyelim");
    inline::run(m);
    check(m, "inline");
    strfuse::run(m);
    check(m, "strfuse");
    slotfuse::run(m);
    check(m, "slotfuse");
    for round in 0..3 {
        let mut changed = optparam::run(m);
        check(m, "optparam");
        changed |= simplify::run(m);
        check(m, "simplify");
        changed |= copyelim::run(m);
        check(m, "copyelim");
        changed |= range::run(m);
        check(m, "range");
        changed |= ifconv::run(m);
        check(m, "ifconv");
        if !changed && round > 0 {
            break;
        }
    }
    reserve::run(m);
    check(m, "reserve");
    lastuse::run(m);
    check(m, "lastuse");
    simplify::run(m);
    check(m, "simplify");
}
