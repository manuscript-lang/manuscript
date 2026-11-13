//! Direct calls between functions emitted from MIR, calls of runtime functions and type
//! descriptors.

use super::attrs::pure_attrs;
use super::{Area, Cx, Vals, call_ret_ty, leaves, records, ret_attr};
use crate::abi_llvm::{Pass, Ret, Signature};
use crate::layout::Layouts;
use crate::llvm_build::{FnBuilder, Ty as LTy, Types, Val};
use ms_mir::ir::{ExternDef, ExternRole, Func, Imm, Inst, Mode, Module, Op};
use ms_mir::types::{Ty, TyKind};

pub(super) const AREA: Area = Area {
    handles,
    inst_ok,
    emit,
    ..Area::NONE
};

fn handles(op: Op) -> bool {
    matches!(op, Op::Call | Op::CallRt | Op::TypeDesc)
}

/// A runtime call is emitted when its operands and result are values this emitter holds. A user C
/// shim passes sized numbers as C types, a skipped cleanup registration is a conditional call and
/// an empty map has no call at all, so those stay with the translation.
fn inst_ok(m: &Module, _lay: &Layouts, _f: &Func, inst: &Inst) -> bool {
    match (inst.op, inst.imm) {
        (Op::CallRt, Imm::Ext(e)) => {
            let def = &m.externs[e.index()];
            !m.c_externs.contains(&def.name)
                && !matches!(def.role, ExternRole::CleanupDiscard | ExternRole::MapNew)
                && def.params.iter().all(|p| p.mode != Mode::Var)
        }
        (Op::TypeDesc, imm) => matches!(imm, Imm::Ty(_)),
        _ => true,
    }
}

fn emit(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    match inst.op {
        Op::CallRt => runtime_call(cx, inst, vals, b),
        Op::TypeDesc => type_desc(cx, inst, vals, b),
        _ => call(cx, inst, vals, b),
    }
}

/// Whether a runtime function takes a value of type `ty` as its leaves; any other value is passed
/// as a pointer to a copy in a stack slot (and a result comes back through a pointer).
fn passes_directly(lay: &Layouts, ty: Ty) -> bool {
    match lay.m.types.kind(ty) {
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

/// What LLVM may assume about a runtime function: it never unwinds, and one declared `pure` on
/// the runtime function (`reads`: only reads memory, cannot fault, cannot run user code) neither
/// writes memory nor fails to return. One that never returns says so.
fn extern_attrs(def: &ExternDef) -> &'static str {
    if def.noreturn {
        " nounwind noreturn cold"
    } else if def.reads {
        " nounwind willreturn nofree nosync memory(read)"
    } else {
        " nounwind"
    }
}

/// A call of a runtime function: the leaves of each direct value, a pointer to a stack copy of
/// every other, and a pointer for a result that does not come back in registers.
fn runtime_call(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    let (m, lay) = (cx.m, cx.lay);
    let Imm::Ext(e) = inst.imm else { return };
    let def = &m.externs[e.index()];
    let out = inst
        .res
        .map(|r| vals[&r.index()].clone())
        .unwrap_or_default();
    let mut args: Vec<(Val, &str)> = Vec::new();
    for (p, a) in def.params.iter().zip(&inst.args) {
        if passes_directly(lay, p.ty) {
            let abi = records::abi_leaves(b, lay, p.ty, vals, *a, false);
            for (v, (_, at)) in abi.into_iter().zip(leaves(lay, p.ty)) {
                args.push((v, at));
            }
        } else {
            let slot = records::spill(b, lay, p.ty, vals, *a);
            args.push((b.ptr_to_int(&slot), ""));
        }
    }
    let slot = if passes_directly(lay, def.ret) {
        None
    } else {
        let slot = records::result_slot(b, lay, def.ret, &out);
        args.push((b.ptr_to_int(&slot), ""));
        Some(slot)
    };
    let (ret, attr) = match &slot {
        Some(_) => (LTy::Void, ""),
        None => (call_ret_ty(lay, def.ret, false), ret_attr(lay, def.ret)),
    };
    let formals: Vec<String> = args
        .iter()
        .map(|(v, a)| format!("{}{a}", b.types().text(&v.ty)))
        .collect();
    cx.decls.push((
        def.name.clone(),
        format!(
            "declare {attr}{} @\"{}\"({}){}",
            Types::default().text(&ret),
            def.name,
            formals.join(", "),
            extern_attrs(def)
        ),
    ));
    match &slot {
        Some(slot) => {
            b.call(&ret, attr, &def.name, &args);
            records::load_result(b, lay, def.ret, slot, &out);
        }
        None => finish_call(
            b,
            lay,
            def.ret,
            (&ret, attr, def.reads && !def.noreturn),
            &def.name,
            &args,
            &out,
            false,
        ),
    }
}

/// The address of the static descriptor of a type.
fn type_desc(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    let (Some(res), Imm::Ty(t)) = (inst.res, inst.imm) else {
        return;
    };
    let sym = cx
        .descs
        .get(&t)
        .expect("the descriptor was created before emission");
    if !cx.data.contains(sym) {
        cx.data.push(sym.clone());
    }
    b.name_next(&vals[&res.index()][0]);
    b.addr_of(sym);
}

fn call(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    let (m, lay) = (cx.m, cx.lay);
    let out = inst
        .res
        .map(|r| vals[&r.index()].clone())
        .unwrap_or_default();
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
                &sym,
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
    let formals: Vec<String> = args
        .iter()
        .map(|(v, a)| format!("{}{a}", b.types().text(&v.ty)))
        .collect();
    cx.decls.push((
        sym.clone(),
        format!(
            "declare {attr}{} @\"{sym}\"({}){attrs}",
            Types::default().text(&ret),
            formals.join(", "),
        ),
    ));
    finish_call(
        b,
        lay,
        callee.ret,
        (&ret, attr, pure),
        &sym,
        &args,
        &out,
        false,
    );
}

/// Writes the call and names its results `out`.
#[allow(clippy::too_many_arguments)]
fn finish_call(
    b: &mut FnBuilder,
    lay: &crate::layout::Layouts,
    result: Ty,
    (ret, attr, pure): (&LTy, &str, bool),
    sym: &str,
    args: &[(Val, &str)],
    out: &[Val],
    native: bool,
) {
    // A pure callee cannot fault, so its call sites need no fault frame of their own.
    let call = |b: &mut FnBuilder| {
        if pure {
            b.call_pure(ret, attr, sym, args)
        } else {
            b.call(ret, attr, sym, args)
        }
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
