//! The stack-depth check of a recursive function (`depth.enter`).
//!
//! The first thing the function does is compare the stack pointer with the task's limit, which sits
//! in the stack region beside the block's address. Below it, the function runs again on a new stack
//! segment: `msrt_task_grow` calls the function's grow shim there with the entry parameters, stored
//! one cell each in a heap block followed by room for the results, and the function returns what
//! that run produced. It is the check `Lower::depth_enter` writes for the Cranelift path.

use super::{Area, Cx, Emitted, Vals, block_label, call_ret_ty, ret_attr};
use crate::abi_llvm::{Pass, Reg, Ret, Signature};
use crate::layout::Layouts;
use crate::llvm_build::Types;
use crate::llvm_build::{Bin, FnBuilder, Ty as LTy, Val};
use ms_mir::ir::{Func, Inst, Op};
use ms_rt_abi::symbols::{ISOLATE_HDR_CANCEL, STACK_LIMIT_CELL, STACK_REGION};

pub(super) const AREA: Area = Area {
    handles: |op| matches!(op, Op::DepthEnter | Op::DepthLeave | Op::Poll),
    splits: |_, _, i, _| usize::from(matches!(i.op, Op::DepthEnter | Op::Poll)),
    emit,
    ..Area::NONE
};

fn emit(cx: &mut Cx, inst: &Inst, _: &Vals, b: &mut FnBuilder) {
    match inst.op {
        Op::DepthEnter => enter(cx, b),
        Op::Poll => poll(cx, b),
        _ => {}
    }
}

/// The address of the running task's header block: the last word of the stack region.
pub(super) fn task_hdr(b: &mut FnBuilder) -> Val {
    let frame = b
        .call(
            &LTy::Ptr,
            "",
            "llvm.frameaddress.p0",
            &[(Val::new("0", LTy::I32), "")],
        )
        .expect("a pointer");
    let sp = b.ptr_to_int(&frame);
    let base = b.bin(Bin::And, &sp, &Val::int(!(STACK_REGION - 1)));
    let cell = b.bin(Bin::Add, &base, &Val::int(STACK_REGION - 16));
    let cell = b.int_to_ptr(&cell);
    b.load(&LTy::I64, &cell, 8)
}

/// Faults when the running task was cancelled: its flag is a byte in the task's header block,
/// whose address is the last word of the stack region.
fn poll(cx: &mut Cx, b: &mut FnBuilder) {
    let hdr = task_hdr(b);
    let flag = b.bin(Bin::Add, &hdr, &Val::int(ISOLATE_HDR_CANCEL));
    let flag = b.int_to_ptr(&flag);
    let cancelled = b.load_flag(&flag);
    let on = b.icmp("ne", &cancelled, &Val::byte(0));
    super::faults::fault_if(cx, b, &on, "msrt_cancelled", &[]);
}

/// Alignment of a leaf in its 8-byte cell.
fn align(t: &LTy) -> u64 {
    if *t == LTy::I8 { 1 } else { 8 }
}

/// Writes the check; `cx.entry_abi` holds the entry parameters as they arrive.
pub(super) fn enter(cx: &mut Cx, b: &mut FnBuilder) {
    let frame = b
        .call(
            &LTy::Ptr,
            "",
            "llvm.frameaddress.p0",
            &[(Val::new("0", LTy::I32), "")],
        )
        .expect("a pointer");
    let sp = b.ptr_to_int(&frame);
    let base = b.bin(Bin::And, &sp, &Val::int(!(STACK_REGION - 1)));
    let cell = b.bin(Bin::Add, &base, &Val::int(STACK_REGION - STACK_LIMIT_CELL));
    let cell = b.int_to_ptr(&cell);
    let limit = b.load(&LTy::I64, &cell, 8);
    let over = b.icmp("ult", &sp, &limit);
    let grow = format!("d{}_{}", cx.block, cx.split);
    cx.split += 1;
    let next = block_label(cx.block, cx.split);
    b.cond_br_likely(&over, &grow, &next, false);
    b.label(&grow);
    let params = cx.entry_abi.clone();
    let rets = cx.ret_abi.clone();
    let block = b
        .call(
            &LTy::Ptr,
            "noalias align 16 ",
            "msrt_alloc",
            &[(Val::int(((params.len() + rets.len()) * 8) as i64), "")],
        )
        .expect("a block");
    for (i, p) in params.iter().enumerate() {
        let at = b.elem_ptr(&LTy::I64, &block, &Val::int(i as i64));
        // A native function's pointers (its result slot and aggregate parameters) cross as words.
        let p = if p.ty == LTy::Ptr {
            b.ptr_to_int(p)
        } else {
            p.clone()
        };
        b.store(&p, &at, align(&p.ty));
    }
    let shim = cx
        .grow_shim
        .clone()
        .expect("a function with a depth check has a grow shim");
    let shim_addr = b.ptr_to_int(&Val::new(format!("@\"{shim}\""), LTy::Ptr));
    let block_addr = b.ptr_to_int(&block);
    b.call(
        &LTy::Void,
        "",
        "msrt_task_grow",
        &[(shim_addr, ""), (block_addr.clone(), "")],
    );
    let results: Vec<Val> = rets
        .iter()
        .enumerate()
        .map(|(j, t)| {
            let at = b.elem_ptr(&LTy::I64, &block, &Val::int((params.len() + j) as i64));
            b.load(t, &at, align(t))
        })
        .collect();
    b.call(&LTy::Void, "", "msrt_free", &[(block_addr, "")]);
    match results.as_slice() {
        [] => b.ret(None),
        [one] => b.ret(Some(one)),
        many => {
            let t = b.tuple(many);
            b.ret(Some(&t));
        }
    }
    b.label(&next);
    for name in ["msrt_alloc", "msrt_free", "msrt_task_grow"] {
        super::rt::declare(cx, name);
    }
    cx.decls
        .push((shim.clone(), format!("declare void @\"{shim}\"(i64)")));
}

/// The leaf types a function returns, as they cross a call.
pub(super) fn ret_abi(
    lay: &crate::layout::Layouts,
    ret: ms_mir::types::Ty,
    native: bool,
) -> Vec<LTy> {
    match call_ret_ty(lay, ret, native) {
        LTy::Void => Vec::new(),
        LTy::Tuple(ts) => ts,
        one => vec![one],
    }
}

/// The grow shim of a function in the native convention: it reads the cells `enter` filled (the
/// result pointer if any, then each parameter as scalars or a pointer), calls the function, and
/// writes the scalar results after them.
pub(super) fn shim(types: &Types, lay: &Layouts, f: &Func, sym: &str, dbg: usize) -> Emitted {
    shim_in(types, lay, f, sym, dbg, true)
}

/// The grow shim of a function in the leaf convention: each parameter leaf is a cell, and the
/// result leaves follow them.
pub(super) fn leaf_shim(types: &Types, lay: &Layouts, f: &Func, sym: &str, dbg: usize) -> Emitted {
    shim_in(types, lay, f, sym, dbg, false)
}

fn shim_in(types: &Types, lay: &Layouts, f: &Func, sym: &str, dbg: usize, native: bool) -> Emitted {
    if !native {
        return leaf_shim_body(types, lay, f, sym, dbg);
    }
    let sig = Signature::of(types, lay, &f.params, &f.noalias, f.ret);
    let mut b = FnBuilder::new(types, Some(dbg));
    b.label("entry");
    let block = b.int_to_ptr(&Val::new("%a0", LTy::I64));
    let mut cell = 0;
    let mut read = |b: &mut FnBuilder, ty: &LTy| {
        let at = b.elem_ptr(&LTy::I64, &block, &Val::int(cell));
        cell += 1;
        b.load(ty, &at, align(ty))
    };
    let mut args: Vec<(Val, &str)> = Vec::new();
    if matches!(sig.result, Ret::Sret(_)) {
        let w = read(&mut b, &LTy::I64);
        args.push((b.int_to_ptr(&w), ""));
    }
    for pass in &sig.passes {
        match pass {
            Pass::Scalars(regs) => {
                for r in regs {
                    let (ty, attr) = match r {
                        Reg::I8 => (LTy::I8, " zeroext"),
                        Reg::F64 => (LTy::F64, ""),
                        Reg::I64 => (LTy::I64, ""),
                        Reg::Ptr => (LTy::Ptr, ""),
                    };
                    args.push((read(&mut b, &ty), attr));
                }
            }
            Pass::Indirect(..) => {
                let w = read(&mut b, &LTy::I64);
                args.push((b.int_to_ptr(&w), ""));
            }
        }
    }
    let first_result = cell;
    let ret = call_ret_ty(lay, f.ret, true);
    let attr = ret_attr(lay, f.ret);
    let (ret, attr) = match sig.result {
        Ret::Sret(_) => (LTy::Void, ""),
        Ret::Scalars(_) => (ret, attr),
    };
    let result = b.call_keep(&ret, attr, sym, &args);
    if let Some(r) = result {
        let leaves = match &ret {
            LTy::Tuple(ts) => (0..ts.len()).map(|k| b.extract(&r, k)).collect(),
            _ => vec![r],
        };
        for (j, v) in leaves.iter().enumerate() {
            let at = b.elem_ptr(&LTy::I64, &block, &Val::int(first_result + j as i64));
            b.store(v, &at, align(&v.ty));
        }
    }
    b.ret(None);
    Emitted {
        ret: "void".to_string(),
        params: "i64 %a0".to_string(),
        attrs: String::new(),
        body: b.finish(),
        decls: vec![(sym.to_string(), sig.declare(sym, ""))],
        data: Vec::new(),
        consts: Vec::new(),
    }
}

fn leaf_shim_body(types: &Types, lay: &Layouts, f: &Func, sym: &str, dbg: usize) -> Emitted {
    let mut b = FnBuilder::new(types, Some(dbg));
    b.label("entry");
    let block = b.int_to_ptr(&Val::new("%a0", LTy::I64));
    let mut cell = 0;
    let mut args: Vec<(Val, &str)> = Vec::new();
    for p in &f.params {
        for (ty, attr) in super::leaves(lay, p.ty) {
            let at = b.elem_ptr(&LTy::I64, &block, &Val::int(cell));
            cell += 1;
            args.push((b.load(&ty, &at, align(&ty)), attr));
        }
    }
    let ret = call_ret_ty(lay, f.ret, false);
    let result = b.call_keep(&ret, ret_attr(lay, f.ret), sym, &args);
    if let Some(r) = result {
        let leaves: Vec<Val> = match &ret {
            LTy::Tuple(ts) => (0..ts.len()).map(|k| b.extract(&r, k)).collect(),
            _ => vec![r],
        };
        for (j, v) in leaves.iter().enumerate() {
            let at = b.elem_ptr(&LTy::I64, &block, &Val::int(cell + j as i64));
            b.store(v, &at, align(&v.ty));
        }
    }
    b.ret(None);
    Emitted {
        ret: "void".to_string(),
        params: "i64 %a0".to_string(),
        attrs: String::new(),
        body: b.finish(),
        decls: vec![(
            sym.to_string(),
            super::calls::declare_leaf(types, lay, f, sym, ""),
        )],
        data: Vec::new(),
        consts: Vec::new(),
    }
}
