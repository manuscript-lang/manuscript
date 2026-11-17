//! The stack-depth primitive (`stack.low`) and the cancellation poll.
//! `ms_mir::depth` expands the check of a recursive function (`depth.enter`) into `stack.low`, a
//! branch and the grow call, so this file only reads the limit the runtime keeps beside the stack
//! region's end.

use super::{Area, Cx, Vals};
use crate::llvm_build::{Bin, FnBuilder, Ty as LTy, Val};
use ms_mir::ir::{Imm, Inst, Op};
use ms_rt_abi::symbols::{ISOLATE_HDR_CANCEL, STACK_LIMIT_CELL, STACK_REGION};

pub(super) const AREA: Area = Area {
    handles: |op| {
        matches!(
            op,
            Op::DepthEnter | Op::DepthLeave | Op::StackLow | Op::StackNear | Op::Poll
        )
    },
    splits: |_, _, i, _| usize::from(i.op == Op::Poll),
    emit,
    ..Area::NONE
};

fn emit(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    match inst.op {
        Op::StackLow => {
            let out = &vals[&inst.res.expect("stack.low has a result").index()][0];
            low(b, out);
        }
        Op::StackNear => {
            let out = &vals[&inst.res.expect("stack.near has a result").index()][0];
            let Imm::Int(headroom) = inst.imm else {
                unreachable!("stack.near takes a headroom")
            };
            near(b, out, headroom);
        }
        Op::Poll => poll(cx, b),
        Op::DepthEnter => unreachable!("ms_mir::depth lowers depth.enter before code generation"),
        _ => {}
    }
}

/// The frame address and the stack-region cell `offset` bytes before the region's end: the
/// region base is the frame address with the low bits masked (`llvm.ptrmask` keeps the pointer's
/// provenance), so the cell is one `getelementptr` from it.
fn region_cell(b: &mut FnBuilder, offset: i64) -> (Val, Val) {
    let frame = b
        .call(
            &LTy::Ptr,
            "",
            "llvm.frameaddress.p0",
            &[(Val::new("0", LTy::I32), "")],
        )
        .expect("a pointer");
    let base = b.ptrmask(&frame, !(STACK_REGION - 1));
    let cell = b.gep_bytes(&base, (STACK_REGION - offset) as u64);
    (frame, cell)
}

/// Whether the stack pointer is within `headroom` bytes of the running segment's limit, named `out`.
fn near(b: &mut FnBuilder, out: &Val, headroom: i64) {
    let (frame, cell) = region_cell(b, STACK_LIMIT_CELL);
    let sp = b.ptr_to_int(&frame);
    let limit = b.load(&LTy::I64, &cell, 8);
    let limit = b.bin(Bin::Add, &limit, &Val::int(headroom));
    b.name_next(out);
    b.icmp("ult", &sp, &limit);
}

/// Whether the stack pointer is below the running segment's limit, named `out`.
fn low(b: &mut FnBuilder, out: &Val) {
    let (frame, cell) = region_cell(b, STACK_LIMIT_CELL);
    let sp = b.ptr_to_int(&frame);
    let limit = b.load(&LTy::I64, &cell, 8);
    b.name_next(out);
    b.icmp("ult", &sp, &limit);
}

/// The address of the running task's header block: the last word of the stack region.
pub(super) fn task_hdr(b: &mut FnBuilder) -> Val {
    b.task_hdr()
}

/// Faults when the running task was cancelled: its flag is a byte in the task's header block,
/// whose address is the last word of the stack region.
fn poll(cx: &mut Cx, b: &mut FnBuilder) {
    let hdr = task_hdr(b);
    let flag = b.gep_bytes(&hdr, ISOLATE_HDR_CANCEL as u64);
    let cancelled = b.load_flag(&flag);
    let on = b.icmp("ne", &cancelled, &Val::byte(0));
    super::faults::fault_if(cx, b, &on, "msrt_cancelled", &[]);
}
