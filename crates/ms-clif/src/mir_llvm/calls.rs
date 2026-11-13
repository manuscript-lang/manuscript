//! Direct calls between functions emitted from MIR.

use super::attrs::pure_attrs;
use super::{Area, Cx, Vals, leaves, ret_attr, ret_ty};
use crate::llvm_build::{FnBuilder, Types, Val};
use ms_mir::ir::{Imm, Inst, Op};

pub(super) const AREA: Area = Area {
    handles,
    emit,
    ..Area::NONE
};

fn handles(op: Op) -> bool {
    op == Op::Call
}

fn emit(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    let (m, lay) = (cx.m, cx.lay);
    let out = inst
        .res
        .map(|r| vals[&r.index()].clone())
        .unwrap_or_default();
    // A single-leaf result is named in place.
    if let [r] = out.as_slice() {
        b.name_next(r);
    }
    let Imm::Func(c) = inst.imm else { return };
    let callee = &m.funcs[c.index()];
    let sym = (cx.symbol_of)(c.index());
    let ret = ret_ty(lay, callee.ret);
    let attr = ret_attr(lay, callee.ret);
    let mut args: Vec<(Val, &str)> = Vec::new();
    for (p, a) in callee.params.iter().zip(&inst.args) {
        for (v, (_, at)) in vals[&a.index()].iter().zip(leaves(lay, p.ty)) {
            args.push((v.clone(), at));
        }
    }
    let formals: Vec<String> = args
        .iter()
        .map(|(v, a)| format!("{}{a}", Types::default().text(&v.ty)))
        .collect();
    cx.decls.push((
        sym.clone(),
        format!(
            "declare {attr}{} @\"{sym}\"({}){}",
            Types::default().text(&ret),
            formals.join(", "),
            pure_attrs(m, lay, c.index(), &mut cx.memo).unwrap_or("")
        ),
    ));
    // A pure callee cannot fault, so its call sites need no fault frame of their own.
    let pure = pure_attrs(m, lay, c.index(), &mut cx.memo).is_some();
    let call = |b: &mut FnBuilder| {
        if pure {
            b.call_pure(&ret, attr, &sym, &args)
        } else {
            b.call(&ret, attr, &sym, &args)
        }
    };
    if out.len() <= 1 {
        call(b);
    } else {
        let t = call(b).expect("a tuple result");
        for (k, dst) in out.iter().enumerate() {
            b.name_next(dst);
            b.extract(&t, k);
        }
    }
}
