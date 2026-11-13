//! Direct calls between functions emitted from MIR.

use super::attrs::pure_attrs;
use super::{Area, Cx, Vals, call_ret_ty, leaves, records, ret_attr};
use crate::abi_llvm::{Pass, Ret, Signature};
use crate::layout::Layouts;
use crate::llvm_build::{FnBuilder, Ty as LTy, Types, Val};
use ms_mir::ir::{ExternDef, ExternRole, Func, Imm, Inst, Mode, Module, Op, Value};
use ms_mir::types::{Ty, TyKind};

pub(super) const AREA: Area = Area {
    handles,
    inst_ok,
    pre,
    emit,
    ..Area::NONE
};

fn inst_ok(m: &Module, lay: &Layouts, _: &Func, inst: &Inst) -> bool {
    match (inst.op, inst.imm) {
        (Op::CallRt, Imm::Ext(e)) => {
            is_map_new(m, inst) || extern_ok(m, lay, &m.externs[e.index()])
        }
        (Op::CallRt, _) => false,
        _ => true,
    }
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
/// either pass directly or have a memory shape, no parameter is updated in place, and it is not
/// a C shim (its narrow results are extended by the caller) or a function the lowering treats as
/// a guarded or constant case.
fn extern_ok(m: &Module, lay: &Layouts, def: &ExternDef) -> bool {
    let crosses = |t: Ty| passes_directly(lay, t) || records::shape_ok(lay, t);
    !m.c_externs.contains(&def.name)
        && !matches!(def.role, ExternRole::MapNew | ExternRole::CleanupDiscard)
        && def
            .params
            .iter()
            .all(|p| p.mode != Mode::Var && crosses(p.ty))
        && crosses(def.ret)
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
    if inst.op == Op::CallRt {
        return call_rt(cx, inst, vals, &out, b);
    }
    let Imm::Func(c) = inst.imm else { return };
    let callee = &m.funcs[c.index()];
    let sym = (cx.symbol_of)(c.index());
    let attrs = pure_attrs(m, lay, cx.native, c.index(), &mut cx.memo).unwrap_or("");
    let pure = !attrs.is_empty();
    if cx.native.contains(&c.index()) {
        let sig = Signature::of(b.types(), lay, &callee.params, callee.ret);
        // A result larger than two registers comes back through a slot the caller owns.
        let slot = match sig.result {
            Ret::Sret(_) => Some(records::result_slot(b, lay, callee.ret, &out)),
            Ret::Scalars(_) => None,
        };
        let mut args: Vec<(Val, &str)> = slot.iter().map(|s| (s.clone(), "")).collect();
        for ((p, a), pass) in callee.params.iter().zip(&inst.args).zip(&sig.passes) {
            match pass {
                Pass::Scalars(_) => {
                    let abi = records::abi_leaves(b, lay, p.ty, vals, *a, true);
                    for (v, (_, at)) in abi.into_iter().zip(leaves(lay, p.ty)) {
                        args.push((v, at));
                    }
                }
                Pass::Indirect(..) => args.push((records::spill(b, lay, p.ty, vals, *a), "")),
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
                b.call(&ret, attr, &sym, &args);
                records::load_result(b, lay, callee.ret, slot, &out);
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
        let abi = records::abi_leaves(b, lay, p.ty, vals, *a, false);
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
        Callee::Symbol(sym) => b.call(ret, attr, sym, args),
    };
    if records::is_mem(lay, result) {
        // The result is a record in memory, rebuilt from the call's result.
        let r = call(b).expect("a result");
        records::call_result(b, lay, result, r, out);
    } else if out
        .iter()
        .any(|d| d.ty == LTy::I1 || (!native && d.ty == LTy::Ptr))
    {
        // Booleans come back as bytes and, in the leaf convention, pointers as addresses.
        let r = call(b).expect("a result");
        records::name_leaves(b, r, out);
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
        let abi = records::abi_leaves(b, lay, *p, vals, *a, false);
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
fn call_rt(cx: &mut Cx, inst: &Inst, vals: &Vals, out: &[Val], b: &mut FnBuilder) {
    let (m, lay) = (cx.m, cx.lay);
    let Imm::Ext(e) = inst.imm else { return };
    let def = &m.externs[e.index()];
    let mut args: Vec<(Val, &str)> = Vec::new();
    for (p, a) in def.params.iter().zip(&inst.args) {
        if passes_directly(lay, p.ty) {
            let abi = records::abi_leaves(b, lay, p.ty, vals, *a, true);
            for (v, (_, at)) in abi.into_iter().zip(leaves(lay, p.ty)) {
                args.push((v, at));
            }
        } else {
            let slot = records::spill(b, lay, p.ty, vals, *a);
            args.push((slot, if p.mode == Mode::Borrow { BORROWED } else { "" }));
        }
    }
    let direct = passes_directly(lay, def.ret);
    let slot = (!direct).then(|| records::result_slot(b, lay, def.ret, out));
    if let Some(slot) = &slot {
        args.push((slot.clone(), OUT));
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
            b.call(&ret, attr, &def.name, &args);
            records::load_result(b, lay, def.ret, slot, out);
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
