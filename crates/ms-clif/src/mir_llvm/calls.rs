//! Direct calls between functions emitted from MIR.

use super::attrs::pure_attrs;
use super::{Area, Cx, Vals, call_ret_ty, leaves, ret_attr, types};
use crate::abi_llvm::{Pass, Ret, Signature};
use crate::layout::{Layouts, Leaf};
use crate::llvm_build::{FnBuilder, Ty as LTy, Types, Val};
use ms_mir::ir::{ExternDef, ExternRole, Func, Imm, Inst, Mode, Module, Op, Value};
use ms_mir::types::{Ty, TyKind};

pub(super) const AREA: Area = Area {
    handles,
    inst_ok,
    splits,
    pre,
    emit,
    ..Area::NONE
};

fn inst_ok(m: &Module, lay: &Layouts, _: &Func, inst: &Inst) -> bool {
    match (inst.op, inst.imm) {
        (Op::CallRt, Imm::Ext(e)) => is_map_new(m, inst) || extern_ok(lay, &m.externs[e.index()]),
        (Op::CallRt, _) => false,
        _ => true,
    }
}

/// Discarding a cleanup handle branches: handle 0 is a registration that was skipped.
fn splits(lay: &Layouts, _: &Func, inst: &Inst, _: bool) -> usize {
    usize::from(is_discard(lay.m, inst))
}

fn is_discard(m: &Module, inst: &Inst) -> bool {
    matches!((inst.op, inst.imm), (Op::CallRt, Imm::Ext(e)) if m.externs[e.index()].role == ExternRole::CleanupDiscard)
}

/// `map_new` (and `set_new`): an empty map is seven zero words (`ms_rt::map::empty()`, pinned by
/// a runtime test), so it is constants and no call.
fn is_map_new(m: &Module, inst: &Inst) -> bool {
    matches!((inst.op, inst.imm), (Op::CallRt, Imm::Ext(e)) if m.externs[e.index()].role == ExternRole::MapNew)
}

fn pre(
    _: &Module,
    lay: &Layouts,
    f: &Func,
    inst: &Inst,
    _: &Vals,
    _: &mut FnBuilder,
) -> Option<Vec<Val>> {
    let res = inst.res?;
    is_map_new(lay.m, inst).then(|| vec![Val::int(0); lay.width(f.ty(res))])
}

fn handles(op: Op) -> bool {
    matches!(op, Op::Call | Op::CallRt)
}

/// The values the runtime takes by value: scalars, pointers and the small optionals of them.
/// Anything else crosses as the address of a copy.
fn passes_directly(lay: &Layouts, t: Ty) -> bool {
    match lay.m.types.kind(t) {
        TyKind::Unit
        | TyKind::Bool
        | TyKind::Int
        | TyKind::Int8
        | TyKind::Int16
        | TyKind::Int32
        | TyKind::UInt8
        | TyKind::UInt16
        | TyKind::UInt32
        | TyKind::UInt64
        | TyKind::Float
        | TyKind::Float32
        | TyKind::Ptr
        | TyKind::Fn(..)
        | TyKind::Iface(_) => true,
        TyKind::Obj(n, _) => !n.is_map_or_set(),
        TyKind::Opt(inner) => lay.opt_is_nullable(*inner) || lay.m.types.is_scalar(*inner),
        _ => false,
    }
}

/// Whether a call of the runtime function `def` is within what this module emits: the types
/// either pass directly or have a memory shape, and it is not
/// a function the lowering treats as a guarded or constant case.
fn extern_ok(lay: &Layouts, def: &ExternDef) -> bool {
    let crosses = |t: Ty| passes_directly(lay, t) || types::shape_ok(lay, t);
    def.role != ExternRole::MapNew && def.params.iter().all(|p| crosses(p.ty)) && crosses(def.ret)
}

fn emit(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    let (m, lay) = (cx.m, cx.lay);
    let out = inst
        .res
        .map(|r| vals[&r.index()].clone())
        .unwrap_or_default();
    if is_map_new(m, inst) {
        return;
    }
    if is_discard(m, inst) {
        let on = b.icmp("ne", &vals[&inst.args[0].index()][0], &Val::int(0));
        let then = format!("c{}_{}", cx.block, cx.split);
        cx.split += 1;
        let next = super::block_label(cx.block, cx.split);
        b.cond_br_likely(&on, &then, &next, false);
        b.label(&then);
        call_rt(cx, inst, vals, &out, b);
        b.br(&next);
        b.label(&next);
        return;
    }
    if inst.op == Op::CallRt {
        return call_rt(cx, inst, vals, &out, b);
    }
    let Imm::Func(c) = inst.imm else { return };
    let callee = &m.funcs[c.index()];
    let sym = (cx.symbol_of)(c.index());
    let attrs = pure_attrs(m, lay, cx.native, c.index(), &mut cx.memo).unwrap_or("");
    let pure = !attrs.is_empty();
    if cx.native.contains(&c.index()) {
        let sig = Signature::of(b.types(), lay, &callee.params, &callee.noalias, callee.ret);
        // A result larger than two registers comes back through a slot the caller owns.
        let slot = match sig.result {
            Ret::Sret(_) => Some(types::result_slot(b, lay, callee.ret, &out)),
            Ret::Scalars(_) => None,
        };
        let mut args: Vec<(Val, &str)> = slot.iter().map(|s| (s.clone(), "")).collect();
        for ((p, a), pass) in callee.params.iter().zip(&inst.args).zip(&sig.passes) {
            match pass {
                Pass::Scalars(_) => {
                    let abi = types::abi_leaves(b, lay, p.ty, vals, *a, true);
                    for (v, (_, at)) in abi.into_iter().zip(leaves(lay, p.ty)) {
                        args.push((v, at));
                    }
                }
                Pass::Indirect(..) => args.push((types::spill(b, lay, p.ty, vals, *a), "")),
            }
        }
        cx.decls.push((sym.clone(), sig.declare(&sym, attrs)));
        let ret = match &slot {
            Some(_) => LTy::Void,
            None => call_ret_ty(lay, callee.ret, true),
        };
        let attr = if slot.is_some() {
            ""
        } else {
            ret_attr(lay, callee.ret)
        };
        match &slot {
            Some(slot) => {
                b.call_keep(&ret, attr, &sym, &args);
                types::load_result(b, lay, callee.ret, slot, &out);
            }
            None => finish_call(
                b,
                lay,
                callee.ret,
                (&ret, attr, pure),
                Callee::Symbol(&sym),
                &args,
                &out,
                true,
            ),
        }
        return;
    }
    let mut args: Vec<(Val, &str)> = Vec::new();
    for (p, a) in callee.params.iter().zip(&inst.args) {
        let abi = types::abi_leaves(b, lay, p.ty, vals, *a, false);
        for (v, (_, at)) in abi.into_iter().zip(leaves(lay, p.ty)) {
            args.push((v, at));
        }
    }
    let ret = call_ret_ty(lay, callee.ret, false);
    let attr = ret_attr(lay, callee.ret);
    cx.decls.push((
        sym.clone(),
        declare_leaf(b.types(), lay, callee, &sym, attrs),
    ));
    finish_call(
        b,
        lay,
        callee.ret,
        (&ret, attr, pure),
        Callee::Symbol(&sym),
        &args,
        &out,
        false,
    );
}

/// The function a call goes to.
pub(super) enum Callee<'a> {
    /// A function by its symbol.
    Symbol(&'a str),
    /// The code a pointer holds.
    Pointer(&'a Val),
}

/// Writes the call and names its results `out`.
#[allow(clippy::too_many_arguments)]
pub(super) fn finish_call(
    b: &mut FnBuilder,
    lay: &crate::layout::Layouts,
    result: Ty,
    (ret, attr, pure): (&LTy, &str, bool),
    callee: Callee,
    args: &[(Val, &str)],
    out: &[Val],
    native: bool,
) {
    // A pure callee cannot fault, so its call sites need no fault frame of their own.
    let call = |b: &mut FnBuilder| match callee {
        Callee::Pointer(code) => b.call_ptr(ret, attr, code, args),
        Callee::Symbol(sym) if pure => b.call_pure(ret, attr, sym, args),
        Callee::Symbol(sym) => b.call_keep(ret, attr, sym, args),
    };
    if types::is_mem(lay, result) {
        // The result is a type in memory, rebuilt from the call's result.
        let r = call(b).expect("a result");
        types::call_result(b, lay, result, r, out);
    } else if out
        .iter()
        .any(|d| d.ty == LTy::I1 || (!native && d.ty == LTy::Ptr))
    {
        // Booleans come back as bytes and, in the leaf convention, pointers as addresses.
        let r = call(b).expect("a result");
        types::name_leaves(b, r, out, native);
    } else if out.len() <= 1 {
        if let [r] = out {
            b.name_next(r);
        }
        call(b);
    } else {
        let t = call(b).expect("a tuple result");
        for (k, dst) in out.iter().enumerate() {
            b.name_next(dst);
            b.extract(&t, k);
        }
    }
}

/// `declare` of `callee` in the leaf convention, the one the runtime and the translated functions
/// use: one parameter per leaf, pointers as addresses.
pub(super) fn declare_leaf(
    types: &Types,
    lay: &Layouts,
    callee: &Func,
    sym: &str,
    attrs: &str,
) -> String {
    let formals: Vec<String> = callee
        .params
        .iter()
        .flat_map(|p| leaves(lay, p.ty))
        .map(|(t, a)| format!("{}{a}", types.text(&t)))
        .collect();
    format!(
        "declare {}{} @\"{sym}\"({}){attrs}",
        ret_attr(lay, callee.ret),
        types.text(&call_ret_ty(lay, callee.ret, false)),
        formals.join(", ")
    )
}

/// A call in the leaf convention to `callee`, a closure's code or a method: `first` is the
/// object or receiver address as an `i64`, then `args` of types `params`. Its results are `out`.
#[allow(clippy::too_many_arguments)]
pub(super) fn leaf_call(
    b: &mut FnBuilder,
    lay: &Layouts,
    vals: &Vals,
    callee: Callee,
    first: Val,
    (params, args): (&[Ty], &[Value]),
    ret: Ty,
    out: &[Val],
) {
    let mut actuals = vec![(first, "")];
    for (p, a) in params.iter().zip(args) {
        let abi = types::abi_leaves(b, lay, *p, vals, *a, false);
        for (v, (_, at)) in abi.into_iter().zip(leaves(lay, *p)) {
            actuals.push((v, at));
        }
    }
    let rt = call_ret_ty(lay, ret, false);
    let attr = ret_attr(lay, ret);
    finish_call(
        b,
        lay,
        ret,
        (&rt, attr, false),
        callee,
        &actuals,
        out,
        false,
    );
}

/// Parameter attributes of the address of a copy the runtime reads: a borrowed value is only
/// read, and a value the callee keeps is read as it is consumed.
const BORROWED: &str = " readonly";
/// The hidden last parameter of a result that does not pass directly: a slot the callee fills.
const OUT: &str = " noalias writeonly";

/// A call of the runtime function in `inst`: values that pass directly go as leaves, any other as
/// the address of a copy, and a result that does not pass directly comes back through a hidden last
/// pointer.
/// The call of a user's C function `def` with its result in the extended `out`: C leaves the upper
/// bits of a narrow result undefined, so the result carries no attribute and is extended here.
fn c_call(cx: &mut Cx, def: &ExternDef, args: &[(Val, &str)], out: &[Val], b: &mut FnBuilder) {
    let lay = cx.lay;
    let ret_leaf = lay.leaves(def.ret).first().copied();
    let ret = match (ret_leaf, out.first()) {
        (None, _) => LTy::Void,
        (Some(l), Some(o)) if o.ty == LTy::Ptr => {
            debug_assert!(l == Leaf::I64);
            LTy::Ptr
        }
        (Some(l), _) => c_leaf(l).0,
    };
    let types = b.types();
    let formals: Vec<String> = args
        .iter()
        .map(|(v, a)| format!("{}{a}", types.text(&v.ty)))
        .collect();
    cx.decls.push((
        def.name.clone(),
        format!(
            "declare {} @\"{}\"({})",
            types.text(&ret),
            def.name,
            formals.join(", ")
        ),
    ));
    let (Some(l), Some(dst)) = (ret_leaf, out.first()) else {
        b.call_keep(&ret, "", &def.name, args);
        return;
    };
    if ret == dst.ty {
        b.name_next(dst);
        b.call_keep(&ret, "", &def.name, args);
        return;
    }
    let r = b.call_keep(&ret, "", &def.name, args).expect("a result");
    b.name_next(dst);
    match (l, &dst.ty) {
        (Leaf::N8 | Leaf::N16 | Leaf::N32, _) => b.sext(&r, dst.ty.clone()),
        (Leaf::F32, _) => b.fpext(&r),
        (_, LTy::I1) => b.trunc(&r, LTy::I1),
        _ => b.zext(&r, dst.ty.clone()),
    };
}

/// A leaf as a C function takes it: sized integers at their own width, extended by the caller,
/// and a `Float32` as `float`.
fn c_leaf(l: Leaf) -> (LTy, &'static str) {
    match l {
        Leaf::N8 => (LTy::I8, " signext"),
        Leaf::N16 => (LTy::I16, " signext"),
        Leaf::N32 => (LTy::I32, " signext"),
        Leaf::U8 | Leaf::I8 => (LTy::I8, " zeroext"),
        Leaf::U16 => (LTy::I16, " zeroext"),
        Leaf::U32 => (LTy::I32, " zeroext"),
        Leaf::F32 => (LTy::F32, ""),
        Leaf::F64 => (LTy::F64, ""),
        Leaf::I64 => (LTy::I64, ""),
    }
}

/// The scalar `v`, held as an `i64` or `f64`, as the C type of leaf `l`.
fn to_c(b: &mut FnBuilder, v: Val, l: Leaf) -> Val {
    let (ty, _) = c_leaf(l);
    match (&v.ty, &ty) {
        (LTy::I64, LTy::I8 | LTy::I16 | LTy::I32) => b.trunc(&v, ty),
        (LTy::F64, LTy::F32) => b.fptrunc(&v),
        _ => v,
    }
}

fn call_rt(cx: &mut Cx, inst: &Inst, vals: &Vals, out: &[Val], b: &mut FnBuilder) {
    let (m, lay) = (cx.m, cx.lay);
    let Imm::Ext(e) = inst.imm else { return };
    let def = &m.externs[e.index()];
    let c_shim = m.c_externs.contains(&def.name);
    let mut args: Vec<(Val, &str)> = Vec::new();
    for (p, a) in def.params.iter().zip(&inst.args) {
        if passes_directly(lay, p.ty) {
            let abi = types::abi_leaves(b, lay, p.ty, vals, *a, true);
            for (v, (l, (_, at))) in abi
                .into_iter()
                .zip(lay.leaves(p.ty).into_iter().zip(leaves(lay, p.ty)))
            {
                if c_shim {
                    args.push((to_c(b, v, l), c_leaf(l).1));
                } else {
                    args.push((v, at));
                }
            }
        } else {
            let slot = types::spill(b, lay, p.ty, vals, *a);
            args.push((slot, if p.mode == Mode::Borrow { BORROWED } else { "" }));
        }
    }
    let direct = passes_directly(lay, def.ret);
    let slot = (!direct).then(|| types::result_slot(b, lay, def.ret, out));
    if let Some(slot) = &slot {
        args.push((slot.clone(), OUT));
    }
    if c_shim && direct {
        return c_call(cx, def, &args, out, b);
    }
    let attrs = crate::llvm_ir::runtime_attrs(&def.name, def.reads);
    let types = b.types();
    let formals: Vec<String> = args
        .iter()
        .map(|(v, a)| format!("{}{a}", types.text(&v.ty)))
        .collect();
    let (ret, attr) = match &slot {
        Some(_) => (LTy::Void, ""),
        None if crate::llvm_ir::returns_fresh_block(&def.name) => (LTy::Ptr, "noalias align 16 "),
        None => (call_ret_ty(lay, def.ret, true), ret_attr(lay, def.ret)),
    };
    cx.decls.push((
        def.name.clone(),
        format!(
            "declare {attr}{} @\"{}\"({}){attrs}",
            types.text(&ret),
            def.name,
            formals.join(", ")
        ),
    ));
    match &slot {
        Some(slot) => {
            b.call_keep(&ret, attr, &def.name, &args);
            types::load_result(b, lay, def.ret, slot, out);
        }
        None => finish_call(
            b,
            lay,
            def.ret,
            (&ret, attr, false),
            Callee::Symbol(&def.name),
            &args,
            out,
            true,
        ),
    }
}
