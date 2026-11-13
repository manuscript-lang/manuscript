//! Direct emission of LLVM IR from MIR (`proposals/mir-to-llvm-direct.md`, stage 1).
//!
//! Release builds translate Cranelift IR to LLVM. This module emits a function straight from MIR
//! instead, so LLVM sees MIR's structure rather than a bag of scalars. Stage 1 covers only
//! functions made of scalar (`Int`, `Bool`, `Float`) values, arithmetic, comparisons, branches and
//! direct calls between such functions; every other function falls back to the translation. Both
//! paths use the same leaf calling convention, so they call each other freely.

use ms_mir::ir::{Cc, Func, Imm, Inst, Mode, Module, Op, Target, Term};
use ms_mir::types::Ty;
use std::collections::HashMap;
use std::fmt::Write as _;

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

/// Emits `f`, which `supports` accepted. `symbol_of` names the function with MIR index `i`;
/// `loc` is the `DILocation` node every call carries.
pub fn emit(m: &Module, f: &Func, loc: usize, symbol_of: &dyn Fn(usize) -> String) -> Emitted {
    let rpo = f.rpo();
    let mut names: HashMap<usize, String> = HashMap::new();
    let mut decls = Vec::new();
    let mut params = Vec::new();
    for (i, p) in f.params.iter().enumerate() {
        let (t, a) = scalar(p.ty).expect("supported");
        params.push(format!("{t}{a} %a{i}"));
        names.insert(f.blocks[0].params[i].value.index(), format!("%a{i}"));
    }
    // Incoming edges of every block, for the phis.
    let mut incoming: HashMap<usize, Vec<(usize, Vec<ms_mir::ir::Value>)>> = HashMap::new();
    for b in &rpo {
        f.blocks[b.index()].term.for_each_target(|t| {
            incoming
                .entry(t.block.index())
                .or_default()
                .push((b.index(), t.args.clone()))
        });
    }
    let mut out = String::new();
    for b in &rpo {
        let bd = &f.blocks[b.index()];
        let _ = writeln!(out, "b{}:", b.index());
        if b.index() != 0 {
            for (j, p) in bd.params.iter().enumerate() {
                let Some((t, _)) = scalar(f.ty(p.value)) else {
                    continue;
                };
                let name = format!("%v{}", p.value.index());
                let edges: Vec<String> = incoming
                    .get(&b.index())
                    .map(Vec::as_slice)
                    .unwrap_or(&[])
                    .iter()
                    .map(|(from, args)| format!("[ {}, %b{from} ]", names[&args[j].index()]))
                    .collect();
                let _ = writeln!(out, "  {name} = phi {t} {}", edges.join(", "));
                names.insert(p.value.index(), name);
            }
        }
        for inst in &bd.insts {
            inst_text(m, f, inst, loc, symbol_of, &mut names, &mut decls, &mut out);
        }
        match &bd.term {
            Term::Br(t) => {
                let _ = writeln!(out, "  br label %b{}", t.block.index());
            }
            Term::CondBr { cond, then, els } => {
                let _ = writeln!(
                    out,
                    "  %c{0} = icmp ne i8 {1}, 0\n  br i1 %c{0}, label %b{2}, label %b{3}",
                    b.index(),
                    names[&cond.index()],
                    then.block.index(),
                    els.block.index()
                );
            }
            Term::Ret(Some(v)) if f.ret != Ty::UNIT => {
                let (t, _) = scalar(f.ret).expect("supported");
                let _ = writeln!(out, "  ret {t} {}", names[&v.index()]);
            }
            Term::Ret(_) => out.push_str("  ret void\n"),
            _ => out.push_str("  unreachable\n"),
        }
    }
    out.push_str("}\n\n");
    Emitted {
        ret: ret_text(f.ret).expect("supported"),
        params: params.join(", "),
        body: out,
        decls,
    }
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

#[allow(clippy::too_many_arguments)]
fn inst_text(
    m: &Module,
    f: &Func,
    inst: &Inst,
    loc: usize,
    symbol_of: &dyn Fn(usize) -> String,
    names: &mut HashMap<usize, String>,
    decls: &mut Vec<(String, String)>,
    out: &mut String,
) {
    let arg = |names: &HashMap<usize, String>, i: usize| names[&inst.args[i].index()].clone();
    let ty_of = |i: usize| scalar(f.ty(inst.args[i])).map_or("i64", |t| t.0);
    let Some(res) = inst.res else {
        // A call with a `Unit` result has none; any other op without a result is `unit`.
        if inst.op == Op::Call {
            call_text(m, inst, loc, symbol_of, names, decls, None, out);
        }
        return;
    };
    let r = format!("%v{}", res.index());
    let bin = |names: &HashMap<usize, String>, op: &str, out: &mut String| {
        let _ = writeln!(
            out,
            "  {r} = {op} {} {}, {}",
            ty_of(0),
            arg(names, 0),
            arg(names, 1)
        );
    };
    let cmp = |names: &HashMap<usize, String>, kind: &str, cc: &str, out: &mut String| {
        let _ = writeln!(
            out,
            "  {r}.c = {kind} {cc} {} {}, {}\n  {r} = zext i1 {r}.c to i8",
            ty_of(0),
            arg(names, 0),
            arg(names, 1)
        );
    };
    match inst.op {
        Op::IConst => {
            let Imm::Int(v) = inst.imm else { return };
            names.insert(res.index(), v.to_string());
            return;
        }
        Op::FConst => {
            let Imm::Float(bits) = inst.imm else { return };
            names.insert(res.index(), format!("0x{bits:016X}"));
            return;
        }
        Op::BConst => {
            let Imm::Bool(v) = inst.imm else { return };
            names.insert(res.index(), (v as u8).to_string());
            return;
        }
        Op::UnitConst => return,
        Op::IAdd | Op::FAdd => bin(names, if inst.op == Op::IAdd { "add" } else { "fadd" }, out),
        Op::ISub => bin(names, "sub", out),
        Op::FSub => bin(names, "fsub", out),
        Op::IMul => bin(names, "mul", out),
        Op::FMul => bin(names, "fmul", out),
        Op::FDiv => bin(names, "fdiv", out),
        Op::And => bin(names, "and", out),
        Op::Or => bin(names, "or", out),
        Op::Xor => bin(names, "xor", out),
        Op::INeg => {
            let _ = writeln!(out, "  {r} = sub i64 0, {}", arg(names, 0));
        }
        Op::FNeg => {
            let _ = writeln!(out, "  {r} = fneg double {}", arg(names, 0));
        }
        Op::Not => {
            let _ = writeln!(out, "  {r} = xor i8 {}, 1", arg(names, 0));
        }
        Op::ICmp | Op::UICmp => {
            let Imm::Cc(cc) = inst.imm else { return };
            cmp(names, "icmp", icc(cc, inst.op == Op::UICmp), out);
        }
        Op::FCmp => {
            let Imm::Cc(cc) = inst.imm else { return };
            cmp(names, "fcmp", fcc(cc), out);
        }
        Op::Select => {
            let t = ty_of(1);
            let _ = writeln!(
                out,
                "  {r}.c = icmp ne i8 {}, 0\n  {r} = select i1 {r}.c, {t} {}, {t} {}",
                arg(names, 0),
                arg(names, 1),
                arg(names, 2)
            );
        }
        Op::B2I => {
            let _ = writeln!(out, "  {r} = zext i8 {} to i64", arg(names, 0));
        }
        Op::Call => {
            call_text(m, inst, loc, symbol_of, names, decls, Some(&r), out);
            names.insert(res.index(), r);
            return;
        }
        _ => unreachable!("supports rejects other ops"),
    }
    names.insert(res.index(), r);
}

#[allow(clippy::too_many_arguments)]
fn call_text(
    m: &Module,
    inst: &Inst,
    loc: usize,
    symbol_of: &dyn Fn(usize) -> String,
    names: &HashMap<usize, String>,
    decls: &mut Vec<(String, String)>,
    result: Option<&str>,
    out: &mut String,
) {
    let Imm::Func(c) = inst.imm else { return };
    let callee = &m.funcs[c.index()];
    let sym = symbol_of(c.index());
    let ret = ret_text(callee.ret).expect("supported");
    let mut formals = Vec::new();
    let mut actuals = Vec::new();
    for (p, a) in callee.params.iter().zip(&inst.args) {
        let (t, attr) = scalar(p.ty).expect("supported");
        formals.push(format!("{t}{attr}"));
        actuals.push(format!("{t}{attr} {}", names[&a.index()]));
    }
    decls.push((
        sym.clone(),
        format!("declare {ret} @\"{sym}\"({})", formals.join(", ")),
    ));
    let lhs = result.map(|r| format!("{r} = ")).unwrap_or_default();
    let _ = writeln!(
        out,
        "  {lhs}call {ret} @\"{sym}\"({}), !dbg !{loc}",
        actuals.join(", ")
    );
}
