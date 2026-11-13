//! Direct emission of LLVM IR from MIR (`proposals/mir-to-llvm-direct.md`, stage 1).
//!
//! Release builds translate Cranelift IR to LLVM. This module emits a function straight from MIR
//! instead, so LLVM sees MIR's structure rather than a bag of scalars. Stage 1 covers only
//! functions made of scalar (`Int`, `Bool`, `Float`) values, arithmetic, comparisons, branches and
//! direct calls between such functions; every other function falls back to the translation. Both
//! paths use the same leaf calling convention, so they call each other freely.

use crate::layout::{Layouts, Leaf};
use crate::llvm_build::{Bin, FnBuilder, Ty as LTy, Types, Val, overflow_intrinsic};
use ms_mir::ir::{Cc, FaultKind, Func, Imm, Inst, Mode, Module, Op, Target, Term};
use ms_mir::types::{Ty, TyKind};
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

/// LLVM type and parameter attribute of one register leaf. `I8` leaves (`Bool`, flags) are
/// zero-extended across calls, like the Cranelift ABI; narrow integers live in `i64` registers.
fn leaf(l: Leaf) -> (LTy, &'static str) {
    match l {
        Leaf::F64 | Leaf::F32 => (LTy::F64, ""),
        Leaf::I8 => (LTy::I8, " zeroext"),
        _ => (LTy::I64, ""),
    }
}

/// The leaves of a value of type `ty`, in calling-convention order.
fn leaves(lay: &Layouts, ty: Ty) -> Vec<(LTy, &'static str)> {
    lay.leaves(ty).into_iter().map(leaf).collect()
}

/// Whether this stage handles values of `ty`: scalars (sized integers are `i64` registers), strings and lists (every list is three
/// leaves, whatever its element).
fn supported_ty(lay: &Layouts, ty: Ty) -> bool {
    matches!(
        lay.m.types.kind(ty),
        TyKind::Unit
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
            | TyKind::Bool
            | TyKind::Str
            | TyKind::Bytes
            | TyKind::List(_)
    )
}

/// The result type: `void` for no leaves, the leaf itself for one, a tuple for several.
fn ret_ty(lay: &Layouts, ty: Ty) -> LTy {
    let mut ls = leaves(lay, ty);
    match ls.len() {
        0 => LTy::Void,
        1 => ls.remove(0).0,
        _ => LTy::Tuple(ls.into_iter().map(|l| l.0).collect()),
    }
}

/// The result attribute: only a single `Bool`-like leaf carries one.
fn ret_attr(lay: &Layouts, ty: Ty) -> &'static str {
    match leaves(lay, ty).as_slice() {
        [(_, a)] if !a.is_empty() => "zeroext ",
        _ => "",
    }
}

fn ret_text(lay: &Layouts, ty: Ty) -> String {
    format!(
        "{}{}",
        ret_attr(lay, ty),
        Types::default().text(&ret_ty(lay, ty))
    )
}

fn signature_ok(lay: &Layouts, params: &[ms_mir::ir::Param], ret: Ty) -> bool {
    supported_ty(lay, ret)
        && params
            .iter()
            .all(|p| p.mode != Mode::Var && supported_ty(lay, p.ty))
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
            | Op::ListLen
            | Op::IAddChk
            | Op::ISubChk
            | Op::IMulChk
            | Op::INegChk
            | Op::SDivChk
            | Op::SRemChk
            | Op::UAddChk
            | Op::USubChk
            | Op::UMulChk
            | Op::NarrowChk
            | Op::F32Round
            | Op::Conv
            | Op::Shl
            | Op::Sshr
            | Op::Ushr
            | Op::Rotl
            | Op::Rotr
            | Op::Clz
            | Op::Ctz
            | Op::Popcnt
            | Op::Call
    )
}

/// Whether stage 1 can emit `f`.
pub fn supports(m: &Module, lay: &Layouts, f: &Func) -> bool {
    if !matches!(f.kind, ms_mir::ir::FuncKind::Normal)
        || !f.scopes.is_empty()
        || !f.noalias.is_empty()
        || !signature_ok(lay, &f.params, f.ret)
    {
        return false;
    }
    let ty_ok = |v| supported_ty(lay, f.ty(v));
    let rpo = f.rpo();
    // The entry block must have no predecessors (LLVM forbids a branch to it).
    let mut entry_target = false;
    for b in &rpo {
        let bd = &f.blocks[b.index()];
        if bd.params.iter().any(|p| !ty_ok(p.value)) {
            return false;
        }
        for i in &bd.insts {
            if !supported_op(i.op) || i.res.is_some_and(|r| !ty_ok(r)) {
                return false;
            }
            if i.op == Op::Call {
                let Imm::Func(c) = i.imm else { return false };
                let callee = &m.funcs[c.index()];
                if !signature_ok(lay, &callee.params, callee.ret) {
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
            Term::Fault(k) => fault_entry(*k).is_some(),
            Term::Switch {
                value,
                cases,
                default,
            } => {
                // One edge per successor block: a phi then needs one entry per predecessor.
                let mut seen: Vec<usize> = vec![default.block.index()];
                let distinct = cases.iter().all(|(_, t)| {
                    let new = !seen.contains(&t.block.index());
                    seen.push(t.block.index());
                    new
                });
                distinct
                    && leaves(lay, f.ty(*value)).len() == 1
                    && !is_entry(default)
                    && cases.iter().all(|(_, t)| !is_entry(t))
            }
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

/// The values of one MIR value: one per register leaf.
type Vals = HashMap<usize, Vec<Val>>;

/// Emits `f`, which `supports` accepted. `symbol_of` names the function with MIR index `i`;
/// `loc` is the `DILocation` node every instruction carries.
pub fn emit(
    m: &Module,
    lay: &Layouts,
    f: &Func,
    loc: usize,
    checks: bool,
    symbol_of: &dyn Fn(usize) -> String,
) -> Emitted {
    let types = Types::default();
    let mut b = FnBuilder::new(&types, Some(loc));
    let rpo = f.rpo();
    // Name every value before emitting anything: a phi names values a later block defines (the
    // back edge of a loop), and a constant is its own text.
    let mut vals: Vals = HashMap::new();
    let mut params = Vec::new();
    for (i, p) in f.params.iter().enumerate() {
        let mut own = Vec::new();
        for (j, (t, attr)) in leaves(lay, p.ty).into_iter().enumerate() {
            params.push(format!("{}{attr} %a{i}_{j}", types.text(&t)));
            own.push(Val::new(format!("%a{i}_{j}"), t));
        }
        vals.insert(f.blocks[0].params[i].value.index(), own);
    }
    let reserve_all = |b: &mut FnBuilder, ty: Ty| -> Vec<Val> {
        leaves(lay, ty)
            .into_iter()
            .map(|l| b.reserve(l.0))
            .collect()
    };
    for bb in &rpo {
        let bd = &f.blocks[bb.index()];
        if bb.index() != 0 {
            for p in &bd.params {
                let own = reserve_all(&mut b, f.ty(p.value));
                vals.insert(p.value.index(), own);
            }
        }
        for inst in &bd.insts {
            let Some(res) = inst.res else { continue };
            let own = match (inst.op, inst.imm) {
                (Op::IConst, Imm::Int(v)) => vec![Val::int(v)],
                (Op::FConst, Imm::Float(bits)) => vec![Val::double(bits)],
                (Op::BConst, Imm::Bool(v)) => vec![Val::byte(v as u8)],
                // The length is a leaf of the list: no instruction.
                (Op::ListLen, _) => vec![vals[&inst.args[0].index()][1].clone()],
                // The same register: a conversion between integer types, or a narrowing whose
                // check is all there is to do.
                _ if is_identity(lay, f, inst) => vals[&inst.args[0].index()].clone(),
                _ => reserve_all(&mut b, f.ty(res)),
            };
            vals.insert(res.index(), own);
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
    // A check splits its block: the fault goes to a block of its own, and the rest of the block
    // continues under `b<N>.<k>`. A phi names the block an edge leaves from, the last one.
    let last_label = |bb: usize| -> String {
        let n: usize = f.blocks[bb]
            .insts
            .iter()
            .map(|i| if checks { check_splits(i.op) } else { 0 })
            .sum();
        seg_label(bb, n)
    };
    let mut decls = Vec::new();
    for bb in &rpo {
        let bd = &f.blocks[bb.index()];
        b.label(&format!("b{}", bb.index()));
        let mut seg = Seg {
            block: bb.index(),
            n: 0,
        };
        if bb.index() != 0 {
            for (j, p) in bd.params.iter().enumerate() {
                for (k, dst) in vals[&p.value.index()].iter().enumerate() {
                    let edges: Vec<(Val, String)> = incoming
                        .get(&bb.index())
                        .map(Vec::as_slice)
                        .unwrap_or(&[])
                        .iter()
                        .map(|(from, args)| (vals[&args[j].index()][k].clone(), last_label(*from)))
                        .collect();
                    b.phi(dst, &edges);
                }
            }
        }
        for inst in &bd.insts {
            let env = Env {
                m,
                f,
                lay,
                symbol_of,
                vals: &vals,
                checks,
            };
            inst_text(env, inst, &mut decls, &mut b, &mut seg);
        }
        match &bd.term {
            Term::Br(t) => b.br(&format!("b{}", t.block.index())),
            Term::CondBr { cond, then, els } => {
                let c = b.icmp("ne", &vals[&cond.index()][0], &Val::byte(0));
                b.cond_br(
                    &c,
                    &format!("b{}", then.block.index()),
                    &format!("b{}", els.block.index()),
                );
            }
            Term::Ret(Some(v)) => match vals[&v.index()].as_slice() {
                [] => b.ret(None),
                [one] => b.ret(Some(one)),
                many => {
                    let t = b.tuple(many);
                    b.ret(Some(&t));
                }
            },
            Term::Ret(None) => b.ret(None),
            Term::Switch {
                value,
                cases,
                default,
            } => {
                let cases: Vec<(i64, String)> = cases
                    .iter()
                    .map(|(k, t)| (*k, format!("b{}", t.block.index())))
                    .collect();
                b.switch(
                    &vals[&value.index()][0],
                    &format!("b{}", default.block.index()),
                    &cases,
                );
            }
            Term::Fault(k) => {
                let (name, zeros) = fault_entry(*k).expect("supports checked the kind");
                let formals = vec!["i64"; zeros].join(", ");
                decls.push((
                    name.to_string(),
                    format!("declare void @\"{name}\"({formals}) cold noreturn"),
                ));
                let args: Vec<(Val, &str)> = (0..zeros).map(|_| (Val::int(0), "")).collect();
                b.call(&LTy::Void, "", name, &args);
                b.unreachable();
            }
            _ => b.unreachable(),
        }
    }
    Emitted {
        ret: ret_text(lay, f.ret),
        params: params.join(", "),
        body: b.finish(),
        decls,
    }
}

/// Where a block's check blocks stand: the MIR block and how many checks came before.
struct Seg {
    block: usize,
    n: usize,
}

/// The label of the `n`th piece of MIR block `bb`; the first is the block's own label.
fn seg_label(bb: usize, n: usize) -> String {
    if n == 0 {
        format!("b{bb}")
    } else {
        format!("b{bb}.{n}")
    }
}

/// How many blocks an op's checks split its block into.
fn check_splits(op: Op) -> usize {
    match op {
        Op::IAddChk
        | Op::ISubChk
        | Op::IMulChk
        | Op::INegChk
        | Op::SRemChk
        | Op::UAddChk
        | Op::USubChk
        | Op::UMulChk
        | Op::NarrowChk => 1,
        Op::SDivChk => 2,
        _ => 0,
    }
}

/// Branches to a block of its own that calls the fault `name` with `args` when `cond` holds, and
/// continues in a new piece of the current block. The fault call is `noreturn`, so LLVM treats the
/// branch as unlikely.
fn fault_if(
    b: &mut FnBuilder,
    decls: &mut Vec<(String, String)>,
    seg: &mut Seg,
    cond: &Val,
    name: &str,
    args: &[Val],
) {
    let formals = vec!["i64"; args.len()].join(", ");
    decls.push((
        name.to_string(),
        format!("declare void @\"{name}\"({formals}) cold noreturn"),
    ));
    let (fault, next) = (
        format!("b{}.f{}", seg.block, seg.n),
        seg_label(seg.block, seg.n + 1),
    );
    b.cond_br(cond, &fault, &next);
    b.label(&fault);
    let args: Vec<(Val, &str)> = args.iter().map(|a| (a.clone(), "")).collect();
    b.call(&LTy::Void, "", name, &args);
    b.unreachable();
    b.label(&next);
    seg.n += 1;
}

/// The runtime entry point of a fault and how many zero `Int` arguments it takes, as the Cranelift
/// lowering calls it (`fault_term`). `None` for kinds that need data (a message) or are not yet
/// emitted. The declaration is `cold noreturn`, so LLVM lays the fault out of line and drops
/// whatever follows it.
fn fault_entry(k: FaultKind) -> Option<(&'static str, usize)> {
    match k {
        FaultKind::IntOverflow => Some(("msrt_fault_int_overflow", 0)),
        FaultKind::DivByZero => Some(("msrt_fault_div_zero", 0)),
        FaultKind::IndexOutOfRange => Some(("msrt_index_fault", 2)),
        FaultKind::NoneUnwrap => Some(("msrt_fault_unwrap_none", 0)),
        FaultKind::Cancelled => Some(("msrt_cancelled", 0)),
        FaultKind::CallDepth => Some(("msrt_fault_depth", 0)),
        FaultKind::Unreachable | FaultKind::Message(_) => None,
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

/// Whether the result of `inst` is its operand's register unchanged: `Conv` between types that
/// share a register (anything but a `Float` rounded to `Float32`), and `NarrowChk`, whose check
/// is emitted but whose value is its operand.
fn is_identity(lay: &Layouts, f: &Func, inst: &Inst) -> bool {
    let kind = |v: ms_mir::ir::Value| lay.m.types.kind(f.ty(v));
    match (inst.op, inst.res) {
        (Op::NarrowChk, _) => true,
        (Op::Conv, Some(r)) => {
            !(matches!(kind(r), TyKind::Float32) && !matches!(kind(inst.args[0]), TyKind::Float32))
        }
        _ => false,
    }
}

/// What the instructions of one function share.
#[derive(Clone, Copy)]
struct Env<'a> {
    m: &'a Module,
    f: &'a Func,
    lay: &'a Layouts<'a>,
    symbol_of: &'a dyn Fn(usize) -> String,
    vals: &'a Vals,
    checks: bool,
}

/// Writes one instruction. Each result leaf takes the name reserved for it in `vals`, which a phi
/// may already use.
fn inst_text(
    env: Env,
    inst: &Inst,
    decls: &mut Vec<(String, String)>,
    b: &mut FnBuilder,
    seg: &mut Seg,
) {
    let Env {
        m,
        f,
        lay,
        symbol_of,
        vals,
        checks,
    } = env;
    let arg = |i: usize| vals[&inst.args[i].index()][0].clone();
    let out = inst
        .res
        .filter(|_| !is_identity(lay, f, inst))
        .map(|r| vals[&r.index()].clone())
        .unwrap_or_default();
    if matches!(
        inst.op,
        Op::IConst | Op::FConst | Op::BConst | Op::UnitConst | Op::ListLen
    ) {
        return;
    }
    // A single-leaf result is named in place; `Select` and `Call` handle several.
    if let [r] = out.as_slice() {
        b.name_next(r);
    }
    match inst.op {
        Op::IAdd => drop(b.bin(Bin::Add, &arg(0), &arg(1))),
        Op::ISub => drop(b.bin(Bin::Sub, &arg(0), &arg(1))),
        Op::IMul => drop(b.bin(Bin::Mul, &arg(0), &arg(1))),
        Op::And => drop(b.bin(Bin::And, &arg(0), &arg(1))),
        Op::Or => drop(b.bin(Bin::Or, &arg(0), &arg(1))),
        Op::Xor => drop(b.bin(Bin::Xor, &arg(0), &arg(1))),
        Op::FAdd => drop(b.bin(Bin::FAdd, &arg(0), &arg(1))),
        Op::FSub => drop(b.bin(Bin::FSub, &arg(0), &arg(1))),
        Op::FMul => drop(b.bin(Bin::FMul, &arg(0), &arg(1))),
        Op::FDiv => drop(b.bin(Bin::FDiv, &arg(0), &arg(1))),
        Op::INeg => drop(b.bin(Bin::Sub, &Val::int(0), &arg(0))),
        Op::IAddChk | Op::ISubChk | Op::IMulChk | Op::INegChk if !checks => {
            let (op, x, y) = match inst.op {
                Op::IAddChk => (Bin::Add, arg(0), arg(1)),
                Op::ISubChk => (Bin::Sub, arg(0), arg(1)),
                Op::IMulChk => (Bin::Mul, arg(0), arg(1)),
                _ => (Bin::Sub, Val::int(0), arg(0)),
            };
            drop(b.bin(op, &x, &y));
        }
        Op::IAddChk | Op::ISubChk | Op::IMulChk | Op::INegChk => {
            let (op, x, y) = match inst.op {
                Op::IAddChk => (Bin::Add, arg(0), arg(1)),
                Op::ISubChk => (Bin::Sub, arg(0), arg(1)),
                Op::IMulChk => (Bin::Mul, arg(0), arg(1)),
                _ => (Bin::Sub, Val::int(0), arg(0)),
            };
            let intrinsic = overflow_intrinsic(op, true);
            decls.push((
                intrinsic.to_string(),
                format!("declare {{ i64, i1 }} @\"{intrinsic}\"(i64, i64)"),
            ));
            let (_, of) = b.overflow(op, true, &x, &y);
            fault_if(b, decls, seg, &of, "msrt_fault_int_overflow", &[]);
        }
        Op::UAddChk | Op::USubChk | Op::UMulChk => {
            let op = match inst.op {
                Op::UAddChk => Bin::Add,
                Op::USubChk => Bin::Sub,
                _ => Bin::Mul,
            };
            if checks {
                let intrinsic = overflow_intrinsic(op, false);
                decls.push((
                    intrinsic.to_string(),
                    format!("declare {{ i64, i1 }} @\"{intrinsic}\"(i64, i64)"),
                ));
                let (_, of) = b.overflow(op, false, &arg(0), &arg(1));
                fault_if(b, decls, seg, &of, "msrt_fault_int_range", &[]);
            } else {
                drop(b.bin(op, &arg(0), &arg(1)));
            }
        }
        Op::NarrowChk => {
            if checks {
                let x = arg(0);
                let (lo, hi) = lay
                    .m
                    .types
                    .int_range(f.ty(inst.args[0]))
                    .unwrap_or((i64::MIN.into(), i64::MAX.into()));
                let below = b.icmp("slt", &x, &Val::int(lo as i64));
                let above = b.icmp("sgt", &x, &Val::int(hi as i64));
                let bad = b.bin(Bin::Or, &below, &above);
                fault_if(b, decls, seg, &bad, "msrt_fault_int_range", &[]);
            }
        }
        Op::F32Round | Op::Conv => {
            // A `Float32` is a `double` register holding a value that fits a `float`.
            let name = b.take_name();
            let narrow = b.fptrunc(&arg(0));
            b.restore_name(name);
            drop(b.fpext(&narrow));
        }
        Op::Shl | Op::Sshr | Op::Ushr => {
            // The shift amount is taken modulo 64, as the hardware (and Cranelift) does; LLVM
            // calls a larger one poison.
            let name = b.take_name();
            let amount = b.bin(Bin::And, &arg(1), &Val::int(63));
            b.restore_name(name);
            let op = match inst.op {
                Op::Shl => Bin::Shl,
                Op::Sshr => Bin::AShr,
                _ => Bin::LShr,
            };
            drop(b.bin(op, &arg(0), &amount));
        }
        Op::Rotl | Op::Rotr | Op::Clz | Op::Ctz | Op::Popcnt => {
            let x = arg(0);
            let (name, formals, args): (&str, &str, Vec<(Val, &str)>) = match inst.op {
                Op::Rotl => (
                    "llvm.fshl.i64",
                    "i64, i64, i64",
                    vec![(x.clone(), ""), (x, ""), (arg(1), "")],
                ),
                Op::Rotr => (
                    "llvm.fshr.i64",
                    "i64, i64, i64",
                    vec![(x.clone(), ""), (x, ""), (arg(1), "")],
                ),
                Op::Clz => (
                    "llvm.ctlz.i64",
                    "i64, i1",
                    vec![(x, ""), (Val::new("false", LTy::I1), "")],
                ),
                Op::Ctz => (
                    "llvm.cttz.i64",
                    "i64, i1",
                    vec![(x, ""), (Val::new("false", LTy::I1), "")],
                ),
                _ => ("llvm.ctpop.i64", "i64", vec![(x, "")]),
            };
            decls.push((
                name.to_string(),
                format!("declare i64 @\"{name}\"({formals})"),
            ));
            drop(b.call(&LTy::I64, "", name, &args));
        }
        Op::SDivChk => {
            let (x, y) = (arg(0), arg(1));
            if checks {
                let name = b.take_name();
                let zero = b.icmp("eq", &y, &Val::int(0));
                fault_if(b, decls, seg, &zero, "msrt_fault_div_zero", &[]);
                let m1 = b.icmp("eq", &y, &Val::int(-1));
                let mn = b.icmp("eq", &x, &Val::int(i64::MIN));
                let both = b.bin(Bin::And, &m1, &mn);
                fault_if(
                    b,
                    decls,
                    seg,
                    &both,
                    "msrt_fault_div_overflow",
                    &[x.clone(), y.clone()],
                );
                b.restore_name(name);
            }
            drop(b.bin(Bin::SDiv, &x, &y));
        }
        Op::SRemChk => {
            let (x, y) = (arg(0), arg(1));
            let name = b.take_name();
            if checks {
                let zero = b.icmp("eq", &y, &Val::int(0));
                fault_if(b, decls, seg, &zero, "msrt_fault_rem_zero", &[]);
            }
            // `INT_MIN % -1` is undefined in LLVM; the result is 0, as in the Cranelift lowering.
            let m1 = b.icmp("eq", &y, &Val::int(-1));
            let safe = b.select(&m1, &Val::int(1), &y);
            let r = b.bin(Bin::SRem, &x, &safe);
            b.restore_name(name);
            drop(b.select(&m1, &Val::int(0), &r));
        }
        Op::FNeg => drop(b.fneg(&arg(0))),
        Op::Not => drop(b.bin(Bin::Xor, &arg(0), &Val::byte(1))),
        Op::ICmp | Op::UICmp | Op::FCmp => {
            let Imm::Cc(cc) = inst.imm else { return };
            // The comparison is an `i1`; the result is its zero-extension, so name only that.
            let pending = b.take_name();
            let c = if inst.op == Op::FCmp {
                b.fcmp(fcc(cc), &arg(0), &arg(1))
            } else {
                b.icmp(icc(cc, inst.op == Op::UICmp), &arg(0), &arg(1))
            };
            b.restore_name(pending);
            b.zext(&c, LTy::I8);
        }
        Op::Select => {
            b.take_name();
            let c = b.icmp("ne", &arg(0), &Val::byte(0));
            for (k, dst) in out.iter().enumerate() {
                b.name_next(dst);
                b.select(
                    &c,
                    &vals[&inst.args[1].index()][k],
                    &vals[&inst.args[2].index()][k],
                );
            }
        }
        Op::B2I => drop(b.zext(&arg(0), LTy::I64)),
        Op::Call => {
            let Imm::Func(c) = inst.imm else { return };
            let callee = &m.funcs[c.index()];
            let sym = symbol_of(c.index());
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
            decls.push((
                sym.clone(),
                format!(
                    "declare {attr}{} @\"{sym}\"({})",
                    Types::default().text(&ret),
                    formals.join(", ")
                ),
            ));
            if out.len() <= 1 {
                b.call(&ret, attr, &sym, &args);
            } else {
                let t = b.call(&ret, attr, &sym, &args).expect("a tuple result");
                for (k, dst) in out.iter().enumerate() {
                    b.name_next(dst);
                    b.extract(&t, k);
                }
            }
        }
        _ => unreachable!("supports rejects other ops"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ms_mir::builder::FuncBuilder;
    use ms_mir::ir::{Mode, Param, StrId};

    /// A function that branches to a fault block: the fault is a call to a `cold noreturn` runtime
    /// function, then `unreachable`, so LLVM lays it out of line.
    #[test]
    fn a_fault_terminator_is_a_noreturn_call_then_unreachable() {
        let mut m = Module::default();
        let mut b = FuncBuilder::new(
            &mut m,
            "check",
            vec![Param {
                ty: Ty::BOOL,
                mode: Mode::Borrow,
            }],
            Ty::INT,
        );
        let ok = b.new_block();
        let bad = b.new_block();
        let cond = b.params()[0];
        b.br_if(cond, ok, &[], bad, &[]);
        b.seal_block(ok);
        b.seal_block(bad);
        b.switch_to(bad);
        b.fault(FaultKind::IndexOutOfRange);
        b.switch_to(ok);
        let one = b.iconst(1);
        b.ret(Some(one));
        let id = b.finish();
        let lay = Layouts::new(&m);
        let f = &m.funcs[id.index()];
        assert!(supports(&m, &lay, f));
        let out = emit(&m, &lay, f, 7, true, &|_| String::new());
        assert!(
            out.body.contains(
                "call void @\"msrt_index_fault\"(i64 0, i64 0), !dbg !7\n  unreachable, !dbg !7"
            ),
            "{}",
            out.body
        );
        assert!(out.decls.iter().any(|(n, d)| n == "msrt_index_fault"
            && d == "declare void @\"msrt_index_fault\"(i64, i64) cold noreturn"));
    }

    /// `a + b`, `a / b` and `a % b` with checks: each check branches to a fault block and the rest
    /// of the block continues in `b0.<k>`; a phi on the join names the last piece.
    #[test]
    fn checked_arithmetic_splits_the_block_at_each_check() {
        let mut m = Module::default();
        let int = Param {
            ty: Ty::INT,
            mode: Mode::Borrow,
        };
        let mut b = FuncBuilder::new(&mut m, "arith", vec![int, int], Ty::INT);
        let (x, y) = (b.params()[0], b.params()[1]);
        let sum = b.binop(Op::IAddChk, x, y);
        let quo = b.binop(Op::SDivChk, sum, y);
        let rem = b.binop(Op::SRemChk, quo, y);
        let join = b.new_block();
        let r = b.add_block_param(join, Ty::INT, Mode::Move);
        b.br(join, &[rem]);
        b.seal_block(join);
        b.switch_to(join);
        b.ret(Some(r));
        let id = b.finish();
        let lay = Layouts::new(&m);
        let f = &m.funcs[id.index()];
        assert!(supports(&m, &lay, f));
        let out = emit(&m, &lay, f, 7, true, &|_| String::new());
        let t = &out.body;
        assert!(t.contains("%v1 = extractvalue { i64, i1 }"), "{t}");
        assert!(
            t.contains("call { i64, i1 } @\"llvm.sadd.with.overflow.i64\"(i64 %a0_0, i64 %a1_0)"),
            "{t}"
        );
        // add (1 check), sdiv (2), srem (1): four pieces after the first.
        for label in [
            "b0.f0:", "b0.1:", "b0.f1:", "b0.2:", "b0.f2:", "b0.3:", "b0.f3:", "b0.4:",
        ] {
            assert!(t.contains(label), "{label} in {t}");
        }
        // The phi's edge leaves from the last piece.
        assert!(t.contains("[ %v") && t.contains(", %b0.4 ]"), "{t}");
        assert!(
            t.contains("call void @\"msrt_fault_div_overflow\"(i64 %v"),
            "{t}"
        );
        assert!(out.decls.iter().any(|(n, _)| n == "msrt_fault_rem_zero"));
    }

    /// Without checks the same ops are plain wrapping arithmetic and `sdiv` in one block.
    #[test]
    fn unchecked_arithmetic_stays_in_one_block() {
        let mut m = Module::default();
        let int = Param {
            ty: Ty::INT,
            mode: Mode::Borrow,
        };
        let mut b = FuncBuilder::new(&mut m, "arith", vec![int, int], Ty::INT);
        let (x, y) = (b.params()[0], b.params()[1]);
        let sum = b.binop(Op::IAddChk, x, y);
        let quo = b.binop(Op::SDivChk, sum, y);
        b.ret(Some(quo));
        let id = b.finish();
        let lay = Layouts::new(&m);
        let out = emit(&m, &lay, &m.funcs[id.index()], 7, false, &|_| String::new());
        assert!(out.body.contains("add i64 %a0_0, %a1_0"), "{}", out.body);
        assert!(out.body.contains("sdiv i64"), "{}", out.body);
        assert!(!out.body.contains(".f0"), "{}", out.body);
    }

    /// A switch lists each case once; two cases to one block fall back to the translation.
    #[test]
    fn a_switch_is_emitted_when_every_edge_has_its_own_block() {
        let mut m = Module::default();
        let int = Param {
            ty: Ty::INT,
            mode: Mode::Borrow,
        };
        let mut b = FuncBuilder::new(&mut m, "pick", vec![int], Ty::INT);
        let n = b.params()[0];
        let (one, two, other) = (b.new_block(), b.new_block(), b.new_block());
        b.switch(n, &[(1, one), (2, two)], other);
        for blk in [one, two, other] {
            b.seal_block(blk);
            b.switch_to(blk);
            let k = b.iconst(blk.index() as i64);
            b.ret(Some(k));
        }
        let id = b.finish();
        let lay = Layouts::new(&m);
        let f = &m.funcs[id.index()];
        assert!(supports(&m, &lay, f));
        let out = emit(&m, &lay, f, 7, true, &|_| String::new());
        assert!(
            out.body.contains(
                "switch i64 %a0_0, label %b3 [ i64 1, label %b1 i64 2, label %b2 ], !dbg !7"
            ),
            "{}",
            out.body
        );
    }

    /// Sized integers are `i64` registers: an unsigned add faults on carry, a narrowing checks its
    /// range and keeps its operand's register, shifts mask the amount, and bit counts and
    /// rotates are LLVM intrinsics.
    #[test]
    fn sized_integers_and_bit_operations() {
        let mut m = Module::default();
        let u8_ty = m.types.intern(TyKind::UInt8);
        let p = Param {
            ty: u8_ty,
            mode: Mode::Borrow,
        };
        let mut b = FuncBuilder::new(&mut m, "bits", vec![p, p], u8_ty);
        let (x, y) = (b.params()[0], b.params()[1]);
        let sum = b.binop(Op::UAddChk, x, y);
        let narrow = b.narrow_chk(sum);
        let shifted = b.binop(Op::Shl, narrow, y);
        let rot = b.binop(Op::Rotl, shifted, y);
        let id = {
            b.ret(Some(rot));
            b.finish()
        };
        let lay = Layouts::new(&m);
        let f = &m.funcs[id.index()];
        assert!(supports(&m, &lay, f));
        let out = emit(&m, &lay, f, 7, true, &|_| String::new());
        let t = &out.body;
        assert!(
            t.contains("@\"llvm.uadd.with.overflow.i64\"(i64 %a0_0, i64 %a1_0)"),
            "{t}"
        );
        assert!(t.contains("call void @\"msrt_fault_int_range\"()"), "{t}");
        // The narrowing names no value: the shift reads the sum.
        assert!(t.contains("icmp slt i64 %v1, 0"), "{t}");
        assert!(t.contains("icmp sgt i64 %v1, 255"), "{t}");
        assert!(t.contains("and i64 %a1_0, 63"), "{t}");
        assert!(t.contains("shl i64 %v1, %v"), "{t}");
        assert!(t.contains("@\"llvm.fshl.i64\"(i64 %v"), "{t}");
    }

    #[test]
    fn a_message_fault_stays_on_the_translation() {
        let mut m = Module::default();
        let mut b = FuncBuilder::new(&mut m, "boom", vec![], Ty::UNIT);
        b.m.strings.push("boom".into());
        b.fault(FaultKind::Message(StrId(0)));
        let id = b.finish();
        let lay = Layouts::new(&m);
        assert!(!supports(&m, &lay, &m.funcs[id.index()]));
    }
}
