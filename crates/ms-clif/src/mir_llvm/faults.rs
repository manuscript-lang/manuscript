//! Faults: the never-returning runtime calls a failed check or a `Fault` terminator makes.

use super::Cx;
use crate::llvm_build::{FnBuilder, Ty as LTy, Val};
use ms_mir::ir::FaultKind;

/// The runtime function that reports `kind`, with the arguments it takes (`None` when the
/// direct emitter does not write this fault: a message needs a string literal).
fn runtime_fn(kind: FaultKind) -> Option<(&'static str, usize)> {
    Some(match kind {
        FaultKind::IntOverflow => ("msrt_fault_int_overflow", 0),
        FaultKind::DivByZero => ("msrt_fault_div_zero", 0),
        FaultKind::IndexOutOfRange => ("msrt_index_fault", 2),
        FaultKind::NoneUnwrap => ("msrt_fault_unwrap_none", 0),
        FaultKind::Cancelled => ("msrt_cancelled", 0),
        FaultKind::CallDepth => ("msrt_fault_depth", 0),
        FaultKind::Unreachable | FaultKind::Message(_) => return None,
    })
}

/// Whether a `Fault` terminator of this kind is written directly.
pub(super) fn terminator_ok(kind: FaultKind) -> bool {
    runtime_fn(kind).is_some()
}

/// Calls the runtime function `name` (which takes `args` i64 words and never returns) and ends the
/// block.
pub(super) fn call(cx: &mut Cx, b: &mut FnBuilder, name: &'static str, args: &[Val]) {
    let actuals: Vec<(Val, &str)> = args.iter().map(|a| (a.clone(), "")).collect();
    b.call(&LTy::Void, "", name, &actuals);
    b.unreachable();
    super::rt::declare_fault(cx, name, args.len());
}

/// The body of a `Fault` terminator.
pub(super) fn terminator(cx: &mut Cx, b: &mut FnBuilder, kind: FaultKind) {
    let (name, words) = runtime_fn(kind).expect("terminator_ok checked the kind");
    call(cx, b, name, &vec![Val::int(0); words]);
}

/// Branches to a fault when `cond` holds and carries on in a new block otherwise. The check is
/// one of its instruction's splits (`Area::splits`).
pub(super) fn fault_if(
    cx: &mut Cx,
    b: &mut FnBuilder,
    cond: &Val,
    name: &'static str,
    args: &[Val],
) {
    let fault = format!("f{}_{}", cx.block, cx.split);
    cx.split += 1;
    let next = super::block_label(cx.block, cx.split);
    b.cond_br_likely(cond, &fault, &next, false);
    b.label(&fault);
    call(cx, b, name, args);
    b.label(&next);
}
