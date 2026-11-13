//! Direct emission of LLVM IR from MIR (`proposals/mir-to-llvm-direct.md`, stage 1).
//!
//! Release builds translate Cranelift IR to LLVM. This module emits a function straight from MIR
//! instead, so LLVM sees MIR's structure rather than a bag of scalars. Stage 1 covers only
//! functions made of scalar (`Int`, `Bool`, `Float`) values, arithmetic, comparisons, branches and
//! direct calls between such functions; every other function falls back to the translation. Both
//! paths use the same leaf calling convention, so they call each other freely.

use crate::llvm_build::{Bin, FnBuilder, Ty as LTy, Types, Val};
use ms_mir::ir::{Cc, Func, Imm, Inst, Mode, Module, Op, Target, Term};
use ms_mir::types::Ty;
use std::collections::HashMap;

/// A finished function: pieces of the `define` line, the body, and the callees it declares.
pub struct Emitted {
    /// Return type with its attributes (`void` for `Unit`).
    pub ret: String,
    /// Parameter list.
    pub params: String,
    /// Entry label through the closing brace.
    pub body: String,
    /// `(symbol, declare line)` of each callee.
    pub decls: Vec<(String, String)>,
}

/// LLVM type and parameter attribute of a scalar MIR type; `None` for anything this stage cannot
/// emit. `Bool` is an `i8` that is zero-extended across calls, like the Cranelift ABI.
fn scalar(ty: Ty) -> Option<(&'static str, &'static str)> {
    match ty {
        Ty::INT => Some(("i64", "")),
        Ty::FLOAT => Some(("double", "")),
        Ty::BOOL => Some(("i8", " zeroext")),
        _ => None,
    }
}

fn ret_text(ty: Ty) -> Option<String> {
    if ty == Ty::UNIT {
        return Some("void".into());
    }
    let (t, a) = scalar(ty)?;
    Some(if a.is_empty() {
        t.into()
    } else {
        format!("zeroext {t}")
    })
}

fn signature_ok(params: &[ms_mir::ir::Param], ret: Ty) -> bool {
    ret_text(ret).is_some()
        && params
            .iter()
            .all(|p| p.mode != Mode::Var && scalar(p.ty).is_some())
}

fn supported_op(op: Op) -> bool {
    matches!(
        op,
        Op::IConst
            | Op::FConst
            | Op::BConst
            | Op::UnitConst
            | Op::IAdd
            | Op::ISub
            | Op::IMul
            | Op::INeg
            | Op::And
            | Op::Or
            | Op::Xor
            | Op::Not
            | Op::ICmp
            | Op::UICmp
            | Op::FCmp
            | Op::FAdd
            | Op::FSub
            | Op::FMul
            | Op::FDiv
            | Op::FNeg
            | Op::Select
            | Op::B2I
            | Op::Call
    )
}

/// Whether stage 1 can emit `f`.
pub fn supports(m: &Module, f: &Func) -> bool {
    if !matches!(f.kind, ms_mir::ir::FuncKind::Normal)
        || !f.scopes.is_empty()
        || !f.noalias.is_empty()
        || !signature_ok(&f.params, f.ret)
    {
        return false;
    }
    let scalar_or_unit = |v| f.ty(v) == Ty::UNIT || scalar(f.ty(v)).is_some();
    let rpo = f.rpo();
    // The entry block must have no predecessors (LLVM forbids a branch to it).
    let mut entry_target = false;
    for b in &rpo {
        let bd = &f.blocks[b.index()];
        if bd.params.iter().any(|p| !scalar_or_unit(p.value)) {
            return false;
        }
        for i in &bd.insts {
            if !supported_op(i.op) || i.res.is_some_and(|r| !scalar_or_unit(r)) {
                return false;
            }
            if i.op == Op::Call {
                let Imm::Func(c) = i.imm else { return false };
                let callee = &m.funcs[c.index()];
                if !signature_ok(&callee.params, callee.ret) {
                    return false;
                }
            }
        }
        let ok = match &bd.term {
            Term::Br(t) => !is_entry(t),
            Term::CondBr { then, els, .. } => {
                then.block != els.block && !is_entry(then) && !is_entry(els)
            }
            Term::Ret(_) | Term::Unreachable => true,
            Term::Switch { .. } | Term::Fault(_) => false,
        };
        if !ok {
            return false;
        }
        bd.term.for_each_target(|t| entry_target |= is_entry(t));
    }
    !entry_target
}

fn is_entry(t: &Target) -> bool {
    t.block.index() == 0
}

/// LLVM type of a scalar MIR type.
fn llty(ty: Ty) -> LTy {
    match ty {
        Ty::INT => LTy::I64,
        Ty::FLOAT => LTy::F64,
        Ty::BOOL => LTy::I8,
        _ => unreachable!("supports rejects other types"),
    }
}

/// LLVM result type: `void` for `Unit`.
fn ret_ty(ty: Ty) -> LTy {
    if ty == Ty::UNIT { LTy::Void } else { llty(ty) }
}

/// Emits `f`, which `supports` accepted. `symbol_of` names the function with MIR index `i`;
/// `loc` is the `DILocation` node every instruction carries.
pub fn emit(m: &Module, f: &Func, loc: usize, symbol_of: &dyn Fn(usize) -> String) -> Emitted {
    let types = Types::default();
    let mut b = FnBuilder::new(&types, Some(loc));
    let rpo = f.rpo();
    // Name every value before emitting anything: a phi names values a later block defines (the
    // back edge of a loop), and a constant is its own text.
    let mut vals: HashMap<usize, Val> = HashMap::new();
    let mut params = Vec::new();
    for (i, p) in f.params.iter().enumerate() {
        let t = llty(p.ty);
        params.push(format!("{}{} %a{i}", types.text(&t), param_attr(p.ty)));
        vals.insert(
            f.blocks[0].params[i].value.index(),
            Val::new(format!("%a{i}"), t),
        );
    }
    for bb in &rpo {
        let bd = &f.blocks[bb.index()];
        if bb.index() != 0 {
            for p in &bd.params {
                if f.ty(p.value) != Ty::UNIT {
                    vals.insert(p.value.index(), b.reserve(llty(f.ty(p.value))));
                }
            }
        }
        for inst in &bd.insts {
            let Some(res) = inst.res.filter(|r| f.ty(*r) != Ty::UNIT) else {
                continue;
            };
            let v = match (inst.op, inst.imm) {
                (Op::IConst, Imm::Int(v)) => Val::int(v),
                (Op::FConst, Imm::Float(bits)) => Val::double(bits),
                (Op::BConst, Imm::Bool(v)) => Val::byte(v as u8),
                _ => b.reserve(llty(f.ty(res))),
            };
            vals.insert(res.index(), v);
        }
    }
    // Incoming edges of every block, for the phis.
    let mut incoming: HashMap<usize, Vec<(usize, Vec<ms_mir::ir::Value>)>> = HashMap::new();
    for bb in &rpo {
        f.blocks[bb.index()].term.for_each_target(|t| {
            incoming
                .entry(t.block.index())
                .or_default()
                .push((bb.index(), t.args.clone()))
        });
    }
    let mut decls = Vec::new();
    for bb in &rpo {
        let bd = &f.blocks[bb.index()];
        b.label(&format!("b{}", bb.index()));
        if bb.index() != 0 {
            for (j, p) in bd.params.iter().enumerate() {
                let Some(dst) = vals.get(&p.value.index()) else {
                    continue;
                };
                let edges: Vec<(Val, String)> = incoming
                    .get(&bb.index())
                    .map(Vec::as_slice)
                    .unwrap_or(&[])
                    .iter()
                    .map(|(from, args)| (vals[&args[j].index()].clone(), format!("b{from}")))
                    .collect();
                b.phi(dst, &edges);
            }
        }
        for inst in &bd.insts {
            inst_text(m, inst, symbol_of, &vals, &mut decls, &mut b);
        }
        match &bd.term {
            Term::Br(t) => b.br(&format!("b{}", t.block.index())),
            Term::CondBr { cond, then, els } => {
                let c = b.icmp("ne", &vals[&cond.index()], &Val::byte(0));
                b.cond_br(
                    &c,
                    &format!("b{}", then.block.index()),
                    &format!("b{}", els.block.index()),
                );
            }
            Term::Ret(Some(v)) if f.ret != Ty::UNIT => b.ret(Some(&vals[&v.index()])),
            Term::Ret(_) => b.ret(None),
            _ => b.unreachable(),
        }
    }
    Emitted {
        ret: ret_text(f.ret).expect("supported"),
        params: params.join(", "),
        body: b.finish(),
        decls,
    }
}

/// The attribute of a parameter or result of type `ty`: `Bool` bytes are zero-extended across
/// calls, like the Cranelift ABI.
fn param_attr(ty: Ty) -> &'static str {
    scalar(ty).map_or("", |s| s.1)
}

fn icc(cc: Cc, unsigned: bool) -> &'static str {
    match (cc, unsigned) {
        (Cc::Eq, _) => "eq",
        (Cc::Ne, _) => "ne",
        (Cc::Lt, false) => "slt",
        (Cc::Le, false) => "sle",
        (Cc::Gt, false) => "sgt",
        (Cc::Ge, false) => "sge",
        (Cc::Lt, true) => "ult",
        (Cc::Le, true) => "ule",
        (Cc::Gt, true) => "ugt",
        (Cc::Ge, true) => "uge",
    }
}

/// Ordered comparison, except `ne`, which holds for NaN (the MIR rule, `Cc`).
fn fcc(cc: Cc) -> &'static str {
    match cc {
        Cc::Eq => "oeq",
        Cc::Ne => "une",
        Cc::Lt => "olt",
        Cc::Le => "ole",
        Cc::Gt => "ogt",
        Cc::Ge => "oge",
    }
}

/// Writes one instruction. Its result, when it has one, is renamed to the value reserved for it
/// in `vals`, which a phi may already name.
fn inst_text(
    m: &Module,
    inst: &Inst,
    symbol_of: &dyn Fn(usize) -> String,
    vals: &HashMap<usize, Val>,
    decls: &mut Vec<(String, String)>,
    b: &mut FnBuilder,
) {
    let arg = |i: usize| vals[&inst.args[i].index()].clone();
    let result = match inst.op {
        Op::IConst | Op::FConst | Op::BConst | Op::UnitConst => return,
        Op::IAdd => b.bin(Bin::Add, &arg(0), &arg(1)),
        Op::ISub => b.bin(Bin::Sub, &arg(0), &arg(1)),
        Op::IMul => b.bin(Bin::Mul, &arg(0), &arg(1)),
        Op::And => b.bin(Bin::And, &arg(0), &arg(1)),
        Op::Or => b.bin(Bin::Or, &arg(0), &arg(1)),
        Op::Xor => b.bin(Bin::Xor, &arg(0), &arg(1)),
        Op::FAdd => b.bin(Bin::FAdd, &arg(0), &arg(1)),
        Op::FSub => b.bin(Bin::FSub, &arg(0), &arg(1)),
        Op::FMul => b.bin(Bin::FMul, &arg(0), &arg(1)),
        Op::FDiv => b.bin(Bin::FDiv, &arg(0), &arg(1)),
        Op::INeg => b.bin(Bin::Sub, &Val::int(0), &arg(0)),
        Op::FNeg => b.fneg(&arg(0)),
        Op::Not => b.bin(Bin::Xor, &arg(0), &Val::byte(1)),
        Op::ICmp | Op::UICmp | Op::FCmp => {
            let Imm::Cc(cc) = inst.imm else { return };
            let c = if inst.op == Op::FCmp {
                b.fcmp(fcc(cc), &arg(0), &arg(1))
            } else {
                b.icmp(icc(cc, inst.op == Op::UICmp), &arg(0), &arg(1))
            };
            b.zext(&c, LTy::I8)
        }
        Op::Select => {
            let c = b.icmp("ne", &arg(0), &Val::byte(0));
            b.select(&c, &arg(1), &arg(2))
        }
        Op::B2I => b.zext(&arg(0), LTy::I64),
        Op::Call => {
            let Imm::Func(c) = inst.imm else { return };
            let callee = &m.funcs[c.index()];
            let sym = symbol_of(c.index());
            let ret = ret_ty(callee.ret);
            let attr = if callee.ret == Ty::BOOL {
                "zeroext "
            } else {
                ""
            };
            let args: Vec<(Val, &str)> = callee
                .params
                .iter()
                .zip(&inst.args)
                .map(|(p, a)| (vals[&a.index()].clone(), param_attr(p.ty)))
                .collect();
            let formals: Vec<String> = args
                .iter()
                .map(|(v, a)| format!("{}{a}", Types::default().text(&v.ty)))
                .collect();
            decls.push((
                sym.clone(),
                format!(
                    "declare {attr}{} @\"{sym}\"({})",
                    Types::default().text(&ret),
                    formals.join(", ")
                ),
            ));
            match b.call(&ret, attr, &sym, &args) {
                Some(v) => v,
                None => return,
            }
        }
        _ => unreachable!("supports rejects other ops"),
    };
    // The builder named the result itself; bind the name MIR users were given.
    if let Some(res) = inst.res
        && let Some(want) = vals.get(&res.index())
    {
        b.alias(want, &result);
    }
}
