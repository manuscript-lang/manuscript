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

use crate::ir::{Module, Op};

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

/// Instructions in one function above which an unoptimized build treats it as long: owned values
/// drop at their last use and the Cranelift backend allocates registers in a single pass.
pub const LONG_FUNCTION_INSTS: usize = 4000;

/// The number of instructions in `f`, excluding terminators.
pub fn instruction_count(f: &crate::ir::Func) -> usize {
    f.blocks.iter().map(|b| b.insts.len()).sum()
}

/// Runs the pipeline. With `verify`, the module is re-verified after every pass and
/// the first failure panics with the pass name (used by tests and debug builds).
pub fn optimize(m: &mut Module, level: Level, verify: bool) {
    if level == Level::None {
        // A copy whose source dies right after it is a move; keeping the copies makes rebuilding a
        // value from itself, or unwrapping a nested `try` result, quadratic in the depth.
        simplify::run_phis(m);
        strfuse::run_append(m);
        copyelim::run(m);
        // Owned values otherwise live to scope end, and register allocation grows with the number
        // that are live at once, so only a long function pays for the earlier drops.
        // A function that reads alternative payloads also drops early, so that the payloads it
        // copies out of a dying value can be moved (`copyelim::run_takes`).
        lastuse::run_where(m, |f| {
            instruction_count(f) > LONG_FUNCTION_INSTS
                || f.blocks
                    .iter()
                    .any(|b| b.insts.iter().any(|i| i.op == Op::AltGet))
        });
        copyelim::run_takes(m);
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
    copyelim::run_takes(m);
    check(m, "copyelim takes");
    simplify::run(m);
    check(m, "simplify");
}
