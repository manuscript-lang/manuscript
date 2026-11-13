//! Direct calls between functions emitted from MIR.

use super::attrs::pure_attrs;
use super::{Area, Cx, Vals, leaves, records, ret_attr, ret_ty};
use crate::abi_llvm::{Pass, Ret, Signature};
use crate::llvm_build::{FnBuilder, Ty as LTy, Types, Val};
use ms_mir::ir::{Imm, Inst, Op};
use ms_mir::types::Ty;

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
    let Imm::Func(c) = inst.imm else { return };
    let callee = &m.funcs[c.index()];
    let sym = (cx.symbol_of)(c.index());
    let attrs = pure_attrs(m, lay, cx.native, c.index(), &mut cx.memo).unwrap_or("");
    if cx.native.contains(&c.index()) {
        let sig = Signature::of(lay, &callee.params, callee.ret);
        // A result larger than two registers comes back through a slot the caller owns.
        let slot = match sig.result {
            Ret::Sret(_) => Some(records::result_slot(b, lay, callee.ret, &out)),
            Ret::Scalars(_) => None,
        };
        let mut args: Vec<(Val, &str)> = slot.iter().map(|s| (s.clone(), "")).collect();
        for ((p, a), pass) in callee.params.iter().zip(&inst.args).zip(&sig.passes) {
            match pass {
                Pass::Scalars(_) => {
                    let abi = records::abi_leaves(b, lay, p.ty, vals, *a);
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
            None => ret_ty(lay, callee.ret),
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
            None => finish_call(b, lay, callee.ret, &ret, attr, &sym, &args, &out),
        }
        return;
    }
    let mut args: Vec<(Val, &str)> = Vec::new();
    for (p, a) in callee.params.iter().zip(&inst.args) {
        let abi = records::abi_leaves(b, lay, p.ty, vals, *a);
        for (v, (_, at)) in abi.into_iter().zip(leaves(lay, p.ty)) {
            args.push((v, at));
        }
    }
    let ret = ret_ty(lay, callee.ret);
    let attr = ret_attr(lay, callee.ret);
    let formals: Vec<String> = args
        .iter()
        .map(|(v, a)| format!("{}{a}", Types::default().text(&v.ty)))
        .collect();
    cx.decls.push((
        sym.clone(),
        format!(
            "declare {attr}{} @\"{sym}\"({}){attrs}",
            Types::default().text(&ret),
            formals.join(", "),
        ),
    ));
    finish_call(b, lay, callee.ret, &ret, attr, &sym, &args, &out);
}

/// Writes the call and names its results `out`.
#[allow(clippy::too_many_arguments)]
fn finish_call(
    b: &mut FnBuilder,
    lay: &crate::layout::Layouts,
    result: Ty,
    ret: &LTy,
    attr: &str,
    sym: &str,
    args: &[(Val, &str)],
    out: &[Val],
) {
    if result == Ty::PTR || records::is_mem(lay, result) {
        // The result is a `ptr` or a record in memory, rebuilt from the call's result.
        let r = b.call(ret, attr, sym, args).expect("a result");
        records::call_result(b, lay, result, r, out);
    } else if out.len() <= 1 {
        if let [r] = out {
            b.name_next(r);
        }
        b.call(ret, attr, sym, args);
    } else {
        let t = b.call(ret, attr, sym, args).expect("a tuple result");
        for (k, dst) in out.iter().enumerate() {
            b.name_next(dst);
            b.extract(&t, k);
        }
    }
}
