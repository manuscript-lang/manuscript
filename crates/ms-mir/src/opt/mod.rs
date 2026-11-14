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

pub mod bytetake;
pub mod copyelim;
pub mod ifconv;
pub mod inline;
pub mod lastuse;
pub mod loopslot;
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

/// The same limit in a program that starts tasks. The unwind pass registers a cleanup for every
/// owned value live at each place that can fault or park, so values that live to scope end make a
/// function's code and frame grow with the square of its length; a frame past a task's 512 KiB
/// stack slot overflows it. Dropping at the last use keeps the live set, and so the growth, small.
pub const TASK_LONG_FUNCTION_INSTS: usize = 300;

/// The number of instructions in `f`, excluding terminators.
pub fn instruction_count(f: &crate::ir::Func) -> usize {
    f.blocks.iter().map(|b| b.insts.len()).sum()
}

/// Computes `work(i)` for every function index below `count` on all cores and returns the results
/// in index order. `work` may only read the module: the caller applies the results afterwards, so
/// every function sees the module as it was before the pass, whatever the thread count.
pub(crate) fn par_funcs<T: Send>(count: usize, work: impl Fn(usize) -> T + Sync) -> Vec<T> {
    use std::sync::atomic::{AtomicUsize, Ordering};
    let threads = std::thread::available_parallelism()
        .map_or(1, usize::from)
        .min(count / 8);
    if threads <= 1 {
        return (0..count).map(work).collect();
    }
    let next = AtomicUsize::new(0);
    let parts: Vec<Vec<(usize, T)>> = std::thread::scope(|s| {
        let workers: Vec<_> = (0..threads)
            .map(|_| {
                s.spawn(|| {
                    let mut done = Vec::new();
                    loop {
                        let i = next.fetch_add(1, Ordering::Relaxed);
                        if i >= count {
                            return done;
                        }
                        done.push((i, work(i)));
                    }
                })
            })
            .collect();
        workers
            .into_iter()
            .map(|w| w.join().unwrap_or_else(|e| std::panic::resume_unwind(e)))
            .collect()
    });
    let mut all: Vec<(usize, T)> = parts.into_iter().flatten().collect();
    all.sort_unstable_by_key(|(i, _)| *i);
    all.into_iter().map(|(_, t)| t).collect()
}

/// Stores the functions a parallel pass changed; returns whether any was.
pub(crate) fn store(m: &mut Module, results: Vec<Option<crate::ir::Func>>) -> bool {
    let mut changed = false;
    for (i, f) in results.into_iter().enumerate() {
        if let Some(f) = f {
            m.funcs[i] = f;
            changed = true;
        }
    }
    changed
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
        let long = if crate::unwind::starts_tasks(m) {
            TASK_LONG_FUNCTION_INSTS
        } else {
            LONG_FUNCTION_INSTS
        };
        lastuse::run_where(m, |f| {
            instruction_count(f) > long
                || f.blocks
                    .iter()
                    .any(|b| b.insts.iter().any(|i| i.op == Op::AltGet))
        });
        bytetake::run(m);
        copyelim::run_takes(m);
        // After the early drops: a long function keeps the ones it moved up.
        crate::exit_drops::run(m);
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
    loopslot::run(m);
    check(m, "loopslot");
    // These passes read the module but rewrite only their own function, so each function runs
    // its own rounds (at most three, stopping at the first that changes nothing) in parallel.
    let results = par_funcs(m.funcs.len(), |i| {
        let mut f = m.funcs[i].clone();
        let mut any = false;
        for _ in 0..3 {
            let mut changed = optparam::run_func(m, &mut f);
            changed |= simplify::run_func(m, &mut f);
            changed |= copyelim::run_funcs(m, &mut f);
            changed |= range::run_func(m, &mut f);
            changed |= ifconv::run_func(m, &mut f);
            if !changed {
                break;
            }
            any = true;
        }
        any.then_some(f)
    });
    store(m, results);
    check(m, "function passes");
    crate::exit_drops::run(m);
    check(m, "exit_drops");
    reserve::run(m);
    check(m, "reserve");
    lastuse::run(m);
    check(m, "lastuse");
    bytetake::run(m);
    check(m, "bytetake");
    copyelim::run_takes(m);
    check(m, "copyelim takes");
    simplify::run(m);
    check(m, "simplify");
}
