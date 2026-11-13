//! Direct calls between functions emitted from MIR.

use super::attrs::pure_attrs;
use super::{Area, Cx, Vals, call_ret_ty, leaves, records, ret_attr};
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
