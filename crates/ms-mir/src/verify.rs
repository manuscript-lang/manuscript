//! The MIR verifier: structure, SSA dominance, operand types and ownership.
//!
//! # Ownership rules
//!
//! Ownership is checked as a linear-type property on values whose type
//! needs a drop:
//!
//! * A value is *owned* when it is defined by an instruction that returns an
//!   owned value (see [`Module::result_mode`]), is a parameter with [`Mode::Own`],
//!   or is a block parameter with [`Mode::Own`]. Everything else is *borrowed*.
//! * Consuming positions (see [`arg_modes`]) require an owned operand and
//!   remove it from the live set. Borrowing positions accept either kind but
//!   an owned value must still be live.
//! * The live set must be identical on every edge into a block (after the
//!   edge's arguments are consumed) and empty at `ret`. `fault` and
//!   `unreachable` end the program, so values held at that point are ignored.

use crate::ir::*;
use crate::types::{Ty, TyKind};
use std::collections::BTreeSet;
use std::fmt;

/// A verification failure.
#[derive(Debug, Clone, PartialEq)]
pub struct VerifyError {
    /// Function name.
    pub func: String,
    /// Block index, when the error is local to a block.
    pub block: Option<u32>,
    /// Description.
    pub message: String,
}

impl fmt::Display for VerifyError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self.block {
            Some(b) => write!(f, "{}: b{}: {}", self.func, b, self.message),
            None => write!(f, "{}: {}", self.func, self.message),
        }
    }
}

impl std::error::Error for VerifyError {}

/// Verifier options.
#[derive(Clone, Copy, Debug, Default)]
pub struct VerifyOptions {
    /// Require a known source location on every instruction.
    pub require_locs: bool,
}

/// Verifies a whole module with default options.
pub fn verify_module(m: &Module) -> Result<(), Vec<VerifyError>> {
    verify_module_with(m, VerifyOptions::default())
}

/// Verifies a whole module.
pub fn verify_module_with(m: &Module, opts: VerifyOptions) -> Result<(), Vec<VerifyError>> {
    let mut errs = Vec::new();
    verify_decls(m, &mut errs);
    for f in &m.funcs {
        if let Err(e) = verify_func_with(m, f, opts) {
            errs.extend(e);
        }
    }
    if errs.is_empty() { Ok(()) } else { Err(errs) }
}

fn verify_decls(m: &Module, errs: &mut Vec<VerifyError>) {
    let mut bad = |msg: String| {
        errs.push(VerifyError {
            func: "<module>".into(),
            block: None,
            message: msg,
        })
    };
    for (i, vt) in m.vtables.iter().enumerate() {
        let iface = &m.ifaces[vt.iface.index()];
        if vt.methods.len() != iface.methods.len() {
            bad(format!(
                "vtable {} has {} methods, interface {} has {}",
                vt.name,
                vt.methods.len(),
                iface.name,
                iface.methods.len()
            ));
            continue;
        }
        for (mf, ms) in vt.methods.iter().zip(&iface.methods) {
            let f = &m.funcs[mf.index()];
            let ok = f.kind == FuncKind::Method
                && f.params.len() == ms.params.len() + 1
                && f.params[1..]
                    .iter()
                    .zip(&ms.params)
                    .all(|(p, t)| p.ty == *t)
                && f.ret == ms.ret;
            if !ok {
                bad(format!(
                    "vtable {} (#{i}): function {} does not implement method {}",
                    vt.name, f.name, ms.name
                ));
            }
        }
    }
    if let Some(e) = m.entry {
        let f = &m.funcs[e.index()];
        if !f.params.is_empty() || f.ret != Ty::INT {
            bad(format!("entry {} must be fn() -> int", f.name));
        }
    }
}

/// Verifies one function.
pub fn verify_func(m: &Module, f: &Func) -> Result<(), Vec<VerifyError>> {
    verify_func_with(m, f, VerifyOptions::default())
}

/// Verifies one function.
pub fn verify_func_with(m: &Module, f: &Func, opts: VerifyOptions) -> Result<(), Vec<VerifyError>> {
    let mut v = Verifier {
        m,
        f,
        opts,
        errs: Vec::new(),
    };
    v.run();
    if v.errs.is_empty() {
        Ok(())
    } else {
        Err(v.errs)
    }
}

/// For each argument of `inst`, whether the position consumes an owned value.
pub fn arg_modes(m: &Module, inst: &Inst) -> Vec<Mode> {
    let n = inst.args.len();
    let all = |mode: Mode| vec![mode; n];
    let one = |i: usize| {
        let mut v = vec![Mode::Borrow; n];
        if i < n {
            v[i] = Mode::Own;
        }
        v
    };
    match inst.op {
        Op::RecNew | Op::AltNew | Op::ListLit | Op::ClosureNew => all(Mode::Own),
        Op::RecSet
        | Op::RecFill
        | Op::ListPush
        | Op::ListDropLast
        | Op::ListSet
        | Op::ListSetNn
        | Op::ListSetU
        | Op::ListFill => all(Mode::Own),
        Op::OptSome
        | Op::IfaceNew
        | Op::Drop
        | Op::GlobalSet
        | Op::SharedNew
        | Op::AltUnbox
        | Op::OptUnbox => one(0),
        Op::Put => one(1),
        Op::DropIf => one(1),
        Op::Call => match inst.imm {
            Imm::Func(g) => m.funcs[g.index()].params.iter().map(|p| p.mode).collect(),
            _ => all(Mode::Borrow),
        },
        Op::CallRt => match inst.imm {
            Imm::Ext(e) => m.externs[e.index()].params.iter().map(|p| p.mode).collect(),
            _ => all(Mode::Borrow),
        },
        _ => all(Mode::Borrow),
    }
}

struct Verifier<'a> {
    m: &'a Module,
    f: &'a Func,
    opts: VerifyOptions,
    errs: Vec<VerifyError>,
}

impl Verifier<'_> {
    fn err(&mut self, block: Option<usize>, msg: impl Into<String>) {
        self.errs.push(VerifyError {
            func: self.f.name.clone(),
            block: block.map(|b| b as u32),
            message: msg.into(),
        });
    }

    fn tn(&self, t: Ty) -> String {
        crate::print::ty_str(self.m, t)
    }

    fn run(&mut self) {
        let f = self.f;
        if f.blocks.is_empty() {
            self.err(None, "function has no blocks");
            return;
        }
        // Entry parameters mirror the signature.
        let entry = &f.blocks[0];
        if entry.params.len() != f.params.len() {
            self.err(
                Some(0),
                "entry block parameters do not match the function signature",
            );
            return;
        }
        for (bp, p) in entry.params.iter().zip(&f.params) {
            if bp.value.index() >= f.values.len()
                || f.ty(bp.value) != p.ty
                || (self.m.needs_drop(p.ty) && bp.mode != p.mode)
            {
                self.err(Some(0), "entry block parameter differs from the signature");
                return;
            }
        }
        match &f.kind {
            FuncKind::Normal => {}
            FuncKind::Closure { .. } | FuncKind::Method => {
                if f.params.first().map(|p| p.ty) != Some(Ty::PTR) {
                    self.err(None, "closure and method functions take the erased environment/receiver as parameter 0 (ptr)");
                }
                if f.params
                    .iter()
                    .any(|p| p.mode == Mode::Own && self.m.needs_drop(p.ty))
                {
                    self.err(
                        None,
                        "closure and method functions take all parameters borrowed",
                    );
                }
            }
        }
        // Definitions: every value defined exactly once.
        let nvals = f.values.len();
        let mut def: Vec<Option<(usize, i64)>> = vec![None; nvals];
        let mut dup = Vec::new();
        for (bi, b) in f.blocks.iter().enumerate() {
            for p in &b.params {
                if p.value.index() >= nvals {
                    dup.push(format!("block parameter {:?} out of range", p.value));
                } else if def[p.value.index()].replace((bi, -1)).is_some() {
                    dup.push(format!("%{} defined twice", p.value.0));
                }
            }
            for (ii, i) in b.insts.iter().enumerate() {
                if let Some(r) = i.res {
                    if r.index() >= nvals {
                        dup.push(format!("result {:?} out of range", r));
                    } else if def[r.index()].replace((bi, ii as i64)).is_some() {
                        dup.push(format!("%{} defined twice", r.0));
                    }
                }
            }
        }
        for d in dup {
            self.err(None, d);
        }
        if !self.errs.is_empty() {
            return;
        }
        let rpo = f.rpo();
        let preds = f.predecessors();
        if !preds[0].is_empty() {
            self.err(Some(0), "the entry block must not have predecessors");
        }
        let idom = dominators(f, &rpo, &preds);
        let mut reachable = vec![false; f.blocks.len()];
        for b in &rpo {
            reachable[b.index()] = true;
        }
        // Per-block checks.
        for &b in &rpo {
            self.check_block(b.index(), &def, &idom);
        }
        if self.errs.is_empty() {
            self.check_ownership(&rpo);
        }
    }

    fn dominates(&self, idom: &[usize], a: usize, mut b: usize) -> bool {
        loop {
            if a == b {
                return true;
            }
            if b == 0 || idom[b] == usize::MAX || idom[b] == b {
                return false;
            }
            b = idom[b];
        }
    }

    fn use_ok(
        &mut self,
        v: Value,
        at: (usize, i64),
        def: &[Option<(usize, i64)>],
        idom: &[usize],
        what: &str,
    ) -> bool {
        let Some(Some((db, di))) = def.get(v.index()) else {
            self.err(
                Some(at.0),
                format!("{what}: use of undefined value %{}", v.0),
            );
            return false;
        };
        let ok = if *db == at.0 {
            *di < at.1
        } else {
            self.dominates(idom, *db, at.0)
        };
        if !ok {
            self.err(
                Some(at.0),
                format!("{what}: %{} does not dominate its use", v.0),
            );
        }
        ok
    }

    fn check_block(&mut self, bi: usize, def: &[Option<(usize, i64)>], idom: &[usize]) {
        let f = self.f;
        let b = &f.blocks[bi];
        for (ii, inst) in b.insts.iter().enumerate() {
            let name = inst.op.info().name;
            if self.opts.require_locs && inst.loc.is_none() {
                self.err(Some(bi), format!("{name}: missing source location"));
            }
            let mut ok = true;
            for a in &inst.args {
                ok &= self.use_ok(*a, (bi, ii as i64), def, idom, name);
            }
            if inst.op.info().has_result != inst.res.is_some() {
                self.err(
                    Some(bi),
                    format!("{name}: result presence does not match the opcode"),
                );
                continue;
            }
            if let (true, Err(msg)) = (ok, self.check_types(inst)) {
                self.err(Some(bi), format!("{name}: {msg}"));
            }
        }
        let at = (bi, b.insts.len() as i64);
        b.term.for_each_use(|_| {});
        let mut uses = Vec::new();
        b.term.for_each_use(|v| uses.push(v));
        let mut ok = true;
        for v in uses {
            ok &= self.use_ok(v, at, def, idom, "terminator");
        }
        if !ok {
            return;
        }
        let mut targets = Vec::new();
        b.term.for_each_target(|t| targets.push(t.clone()));
        for t in targets {
            let Some(dest) = f.blocks.get(t.block.index()) else {
                self.err(Some(bi), "branch to a nonexistent block");
                continue;
            };
            if t.args.len() != dest.params.len() {
                self.err(
                    Some(bi),
                    format!(
                        "branch to b{} passes {} arguments for {} parameters",
                        t.block.0,
                        t.args.len(),
                        dest.params.len()
                    ),
                );
                continue;
            }
            for (a, p) in t.args.iter().zip(&dest.params) {
                if f.ty(*a) != f.ty(p.value) {
                    self.err(
                        Some(bi),
                        format!(
                            "branch to b{}: argument %{} has type {} but the parameter has {}",
                            t.block.0,
                            a.0,
                            self.tn(f.ty(*a)),
                            self.tn(f.ty(p.value))
                        ),
                    );
                }
            }
        }
        match &b.term {
            Term::CondBr { cond, .. } if f.ty(*cond) != Ty::BOOL => {
                self.err(Some(bi), "condition must be bool")
            }
            Term::Switch { value, .. } if f.ty(*value) != Ty::INT => {
                self.err(Some(bi), "switch value must be int")
            }
            Term::Ret(v) => {
                let ty = v.map(|v| f.ty(v)).unwrap_or(Ty::UNIT);
                if ty != f.ret {
                    self.err(
                        Some(bi),
                        format!(
                            "returns {} but the function returns {}",
                            self.tn(ty),
                            self.tn(f.ret)
                        ),
                    );
                }
            }
            Term::Fault(FaultKind::Message(s)) if s.index() >= self.m.strings.len() => {
                self.err(Some(bi), "fault message literal out of range")
            }
            _ => {}
        }
    }

    fn check_types(&self, inst: &Inst) -> Result<(), String> {
        let (m, f) = (self.m, self.f);
        let t = |i: usize| f.ty(inst.args[i]);
        let res = inst.res.map(|r| f.ty(r));
        let n = inst.args.len();
        let want = |cond: bool, msg: &str| if cond { Ok(()) } else { Err(msg.to_string()) };
        let arity = |k: usize| {
            if n == k {
                Ok(())
            } else {
                Err(format!("expected {k} operands, found {n}"))
            }
        };
        let mismatch = |what: &str, got: Ty, exp: Ty| {
            format!(
                "{what} has type {} but {} is expected",
                self.tn(got),
                self.tn(exp)
            )
        };
        match inst.op {
            Op::IConst => {
                arity(0)?;
                want(
                    matches!(inst.imm, Imm::Int(_)) && res.is_some_and(|r| m.types.is_int(r)),
                    "iconst yields an int type",
                )
            }
            Op::FConst => {
                arity(0)?;
                want(
                    matches!(inst.imm, Imm::Float(_)) && res.is_some_and(|r| m.types.is_float(r)),
                    "fconst yields a float type",
                )
            }
            Op::BConst => {
                arity(0)?;
                want(
                    matches!(inst.imm, Imm::Bool(_)) && res == Some(Ty::BOOL),
                    "bconst yields bool",
                )
            }
            Op::UnitConst => {
                arity(0)?;
                want(res == Some(Ty::UNIT), "unit yields unit")
            }
            Op::StrLit => {
                arity(0)?;
                match inst.imm {
                    Imm::Str(s) if s.index() < m.strings.len() => {
                        want(res == Some(Ty::STR), "str yields string")
                    }
                    _ => Err("bad string literal".into()),
                }
            }
            Op::IAdd
            | Op::ISub
            | Op::IMul
            | Op::IAddChk
            | Op::ISubChk
            | Op::IMulChk
            | Op::SDivChk
            | Op::SRemChk
            | Op::SDiv
            | Op::SRem
            | Op::Shl
            | Op::Sshr => {
                arity(2)?;
                want(
                    m.types.is_int(t(0)) && t(1) == t(0) && res == Some(t(0)),
                    "operands and result must be one int type",
                )
            }
            Op::IAddOverflow | Op::IMulOverflow => {
                arity(2)?;
                want(
                    t(0) == Ty::INT && t(1) == Ty::INT && res == Some(Ty::BOOL),
                    "overflow flag takes two ints and yields bool",
                )
            }
            Op::IntOverflowIf => {
                arity(1)?;
                want(
                    t(0) == Ty::BOOL && res.is_none(),
                    "overflow guard takes bool and has no result",
                )
            }
            Op::NarrowChk => {
                arity(1)?;
                want(
                    matches!(m.types.int_bits(t(0)), Some(b) if b < 64) && res == Some(t(0)),
                    "narrow.chk takes a sized int and yields the same type",
                )
            }
            Op::Conv => {
                arity(1)?;
                let to = res;
                want(
                    to.is_some_and(|r| {
                        (m.types.is_int(t(0)) && m.types.is_int(r))
                            || (m.types.is_float(t(0)) && m.types.is_float(r))
                    }),
                    "conv takes an int or float and yields another type of the same kind",
                )
            }
            Op::INarrowOpt => {
                arity(1)?;
                let inner = res.and_then(|r| m.opt_inner(r));
                want(
                    m.types.is_int(t(0)) && inner.is_some_and(|i| m.types.is_int(i)),
                    "inarrow.opt takes an int and yields an optional int",
                )
            }
            Op::F32Round => {
                arity(1)?;
                want(
                    t(0) == Ty::FLOAT32 && res == Some(Ty::FLOAT32),
                    "operand and result must be float32",
                )
            }
            Op::INeg | Op::INegChk => {
                arity(1)?;
                want(
                    m.types.is_int(t(0)) && res == Some(t(0)),
                    "operand and result must be one int type",
                )
            }
            Op::And | Op::Or | Op::Xor => {
                arity(2)?;
                want(
                    (m.types.is_int(t(0)) || t(0) == Ty::BOOL) && t(0) == t(1) && res == Some(t(0)),
                    "operands and result must be both int or both bool",
                )
            }
            Op::Not => {
                arity(1)?;
                want(
                    t(0) == Ty::BOOL && res == Some(Ty::BOOL),
                    "operand and result must be bool",
                )
            }
            Op::ICmp => {
                arity(2)?;
                let Imm::Cc(cc) = inst.imm else {
                    return Err("missing condition".into());
                };
                let ok = t(0) == t(1)
                    && (m.types.is_int(t(0))
                        || (t(0) == Ty::BOOL && matches!(cc, Cc::Eq | Cc::Ne)));
                want(
                    ok && res == Some(Ty::BOOL),
                    "icmp compares two ints (or bools for eq/ne) and yields bool",
                )
            }
            Op::FCmp => {
                arity(2)?;
                want(
                    matches!(inst.imm, Imm::Cc(_))
                        && m.types.is_float(t(0))
                        && t(1) == t(0)
                        && res == Some(Ty::BOOL),
                    "fcmp compares two floats and yields bool",
                )
            }
            Op::FAdd | Op::FSub | Op::FMul | Op::FDiv => {
                arity(2)?;
                want(
                    m.types.is_float(t(0)) && t(1) == t(0) && res == Some(t(0)),
                    "operands and result must be one float type",
                )
            }
            Op::FNeg | Op::FSqrt | Op::FAbs | Op::FFloor | Op::FCeil | Op::FTrunc => {
                arity(1)?;
                want(
                    m.types.is_float(t(0)) && res == Some(t(0)),
                    "operand and result must be one float type",
                )
            }
            Op::I2F => {
                arity(1)?;
                want(
                    m.types.is_int(t(0)) && res.is_some_and(|r| m.types.is_float(r)),
                    "i2f converts an int type to a float type",
                )
            }
            Op::F2IOpt => {
                arity(1)?;
                let opt = res.and_then(|r| m.opt_inner(r));
                want(
                    m.types.is_float(t(0)) && opt == Some(Ty::INT),
                    "f2i.opt converts float to opt<int>",
                )
            }
            Op::B2I => {
                arity(1)?;
                want(
                    t(0) == Ty::BOOL && res == Some(Ty::INT),
                    "b2i converts bool to int",
                )
            }
            Op::Select => {
                arity(3)?;
                want(
                    t(0) == Ty::BOOL && t(1) == t(2) && res == Some(t(1)) && !m.needs_drop(t(1)),
                    "select takes bool, two equal non-reference values",
                )
            }
            Op::RecNew => {
                let Imm::Rec(r) = inst.imm else {
                    return Err("missing record".into());
                };
                let fields = m.field_types(inst.imm).ok_or("bad record")?;
                if n != fields.len() {
                    return Err(format!(
                        "record {} has {} fields, found {n} operands",
                        m.records[r.index()].name,
                        fields.len()
                    ));
                }
                for (i, ft) in fields.iter().enumerate() {
                    if t(i) != *ft {
                        return Err(mismatch(
                            &format!("field {}", m.records[r.index()].fields[i].0),
                            t(i),
                            *ft,
                        ));
                    }
                }
                want(
                    res.map(|r| matches!(m.types.kind(r), TyKind::Rec(x) if *x == r_id(inst)))
                        .unwrap_or(false),
                    "rec.new yields the record type",
                )
            }
            Op::RecGet | Op::RecSet | Op::RecFill => {
                let Imm::Field(r, i) = inst.imm else {
                    return Err("missing field".into());
                };
                let rec = m.records.get(r.index()).ok_or("bad record")?;
                let fty = rec.fields.get(i as usize).ok_or("bad field index")?.1;
                if !matches!(m.types.kind(t(0)), TyKind::Rec(x) if *x == r) {
                    return Err(format!("operand 0 must be record {}", rec.name));
                }
                if inst.op == Op::RecGet {
                    arity(1)?;
                    want(res == Some(fty), "rec.get yields the field type")
                } else {
                    arity(2)?;
                    want(
                        t(1) == fty && res == Some(t(0)),
                        "stored value must have the field type; yields the updated record",
                    )
                }
            }
            Op::AltNew => {
                let Imm::Case(a, c) = inst.imm else {
                    return Err("missing case".into());
                };
                let fields = m.field_types(inst.imm).ok_or("bad case")?;
                if n != fields.len() {
                    return Err(format!(
                        "case {} has {} fields, found {n} operands",
                        m.alts[a.index()].cases[c as usize].name,
                        fields.len()
                    ));
                }
                for (i, ft) in fields.iter().enumerate() {
                    if t(i) != *ft {
                        return Err(mismatch(&format!("field {i}"), t(i), *ft));
                    }
                }
                want(
                    res.map(|r| matches!(m.types.kind(r), TyKind::Alt(x) if *x == a))
                        .unwrap_or(false),
                    "alt.new yields the alternative type",
                )
            }
            Op::AltTag => {
                arity(1)?;
                want(
                    matches!(m.types.kind(t(0)), TyKind::Alt(_)) && res == Some(Ty::INT),
                    "alt.tag takes an alternative and yields int",
                )
            }
            Op::AltGet | Op::AltUnbox => {
                arity(1)?;
                let Imm::AltField(a, c, i) = inst.imm else {
                    return Err("missing case field".into());
                };
                let case = m
                    .alts
                    .get(a.index())
                    .and_then(|x| x.cases.get(c as usize))
                    .ok_or("bad case")?;
                let fty = case.fields.get(i as usize).ok_or("bad field index")?.1;
                want(
                    matches!(m.types.kind(t(0)), TyKind::Alt(x) if *x == a) && res == Some(fty),
                    "alt.get yields the payload field type",
                )
            }
            Op::ListNew => {
                arity(1)?;
                want(
                    t(0) == Ty::INT && res.and_then(|r| m.list_elem(r)).is_some(),
                    "list.new takes a capacity and yields a list",
                )
            }
            Op::ListLit => {
                let elem = res
                    .and_then(|r| m.list_elem(r))
                    .ok_or("list.lit yields a list")?;
                for i in 0..n {
                    if t(i) != elem {
                        return Err(mismatch("element", t(i), elem));
                    }
                }
                Ok(())
            }
            Op::ListLen => {
                arity(1)?;
                want(
                    (m.list_elem(t(0)).is_some() || t(0) == Ty::BYTES) && res == Some(Ty::INT),
                    "list.len takes a list (or bytes) and yields int",
                )
            }
            Op::ListGet | Op::ListGetNn | Op::ListGetU => {
                arity(2)?;
                let elem = m.list_elem(t(0)).ok_or("operand 0 must be a list")?;
                want(
                    t(1) == Ty::INT && res == Some(elem),
                    "index must be int; result is the element type",
                )
            }
            Op::ListSet | Op::ListSetNn | Op::ListSetU | Op::ListFill => {
                arity(3)?;
                let elem = m.list_elem(t(0)).ok_or("operand 0 must be a list")?;
                want(
                    t(1) == Ty::INT && t(2) == elem && res == Some(t(0)),
                    "index must be int; value must be the element type; yields the updated list",
                )
            }
            Op::ListPush => {
                arity(2)?;
                let elem = m.list_elem(t(0)).ok_or("operand 0 must be a list")?;
                want(
                    t(1) == elem && res == Some(t(0)),
                    "value must be the element type; yields the updated list",
                )
            }
            Op::ListDropLast => {
                arity(1)?;
                m.list_elem(t(0)).ok_or("operand 0 must be a list")?;
                want(res == Some(t(0)), "yields the shortened list")
            }
            Op::OptSome | Op::OptView => {
                arity(1)?;
                want(
                    res.and_then(|r| m.opt_inner(r)) == Some(t(0)),
                    "optional constructors wrap their operand",
                )?;
                // A boxed optional holds its payload in a heap block, which a borrow cannot own.
                want(
                    inst.op == Op::OptSome || !m.opt_is_boxed(t(0)),
                    "opt.view cannot lend a boxed optional",
                )
            }
            Op::OptNone => {
                arity(0)?;
                want(
                    res.and_then(|r| m.opt_inner(r)).is_some(),
                    "opt.none yields an optional",
                )
            }
            Op::OptIsSome => {
                arity(1)?;
                want(
                    m.opt_inner(t(0)).is_some() && res == Some(Ty::BOOL),
                    "opt.is_some takes an optional and yields bool",
                )
            }
            Op::OptGet | Op::OptUnwrap | Op::OptUnbox => {
                arity(1)?;
                want(
                    m.opt_inner(t(0)).is_some() && res == m.opt_inner(t(0)),
                    "yields the payload type",
                )
            }
            Op::StrLen => {
                arity(1)?;
                want(
                    t(0) == Ty::STR && res == Some(Ty::INT),
                    "str.len takes a string and yields int",
                )
            }
            Op::StrByte => {
                arity(2)?;
                want(
                    t(0) == Ty::STR && t(1) == Ty::INT && res == Some(Ty::INT),
                    "str.byte takes a string and a byte offset and yields int",
                )
            }
            Op::StrAscii => {
                arity(1)?;
                want(
                    t(0) == Ty::INT && res == Some(Ty::STR),
                    "str.ascii takes an ASCII byte and yields the shared one-character string",
                )
            }
            Op::ClosureNew => {
                let Imm::Func(g) = inst.imm else {
                    return Err("missing function".into());
                };
                let callee = m.funcs.get(g.index()).ok_or("bad function")?;
                let FuncKind::Closure { captures } = &callee.kind else {
                    return Err(format!("{} is not a closure function", callee.name));
                };
                if n != captures.len() {
                    return Err(format!(
                        "{} captures {} values, found {n}",
                        callee.name,
                        captures.len()
                    ));
                }
                for (i, c) in captures.iter().enumerate() {
                    if t(i) != *c {
                        return Err(mismatch("capture", t(i), *c));
                    }
                }
                let ps: Vec<Ty> = callee.params[1..].iter().map(|p| p.ty).collect();
                match res.map(|r| m.types.kind(r)) {
                    Some(TyKind::Fn(fp, fr)) if *fp == ps && *fr == callee.ret => Ok(()),
                    _ => Err("closure.new yields a function type matching the closure code".into()),
                }
            }
            Op::ClosureCap => {
                arity(1)?;
                let Imm::Idx(i) = inst.imm else {
                    return Err("missing index".into());
                };
                let FuncKind::Closure { captures } = &f.kind else {
                    return Err("closure.cap outside a closure function".into());
                };
                let c = captures
                    .get(i as usize)
                    .ok_or("capture index out of range")?;
                want(
                    t(0) == Ty::PTR && res == Some(*c),
                    "closure.cap reads the environment (ptr) and yields the capture type",
                )
            }
            Op::IfaceNew => {
                arity(1)?;
                let Imm::Vtable(v) = inst.imm else {
                    return Err("missing vtable".into());
                };
                let vt = m.vtables.get(v.index()).ok_or("bad vtable")?;
                want(
                    t(0) == vt.data_ty
                        && res
                            .map(|r| matches!(m.types.kind(r), TyKind::Iface(i) if *i == vt.iface))
                            .unwrap_or(false),
                    "iface.new wraps the vtable's data type",
                )
            }
            Op::IfaceIs => {
                arity(1)?;
                let Imm::Vtable(v) = inst.imm else {
                    return Err("missing vtable".into());
                };
                let vt = m.vtables.get(v.index()).ok_or("bad vtable")?;
                want(
                    matches!(m.types.kind(t(0)), TyKind::Iface(i) if *i == vt.iface)
                        && res == Some(Ty::BOOL),
                    "iface.is tests an interface value of the vtable's interface and yields bool",
                )
            }
            Op::IfaceData => {
                arity(1)?;
                want(
                    matches!(m.types.kind(t(0)), TyKind::Iface(_)) && res == Some(Ty::PTR),
                    "iface.data takes an interface and yields ptr",
                )
            }
            Op::Call => {
                let Imm::Func(g) = inst.imm else {
                    return Err("missing callee".into());
                };
                let callee = m.funcs.get(g.index()).ok_or("bad callee")?;
                if n != callee.params.len() {
                    return Err(format!(
                        "{} takes {} arguments, found {n}",
                        callee.name,
                        callee.params.len()
                    ));
                }
                for (i, p) in callee.params.iter().enumerate() {
                    if t(i) != p.ty {
                        return Err(mismatch(&format!("argument {i}"), t(i), p.ty));
                    }
                }
                want(
                    res == Some(callee.ret),
                    "call yields the callee's result type",
                )
            }
            Op::CallInd => {
                if n == 0 {
                    return Err("call.ind needs a closure".into());
                }
                let TyKind::Fn(ps, r) = m.types.kind(t(0)) else {
                    return Err("operand 0 must be a closure".into());
                };
                if n - 1 != ps.len() {
                    return Err(format!(
                        "closure takes {} arguments, found {}",
                        ps.len(),
                        n - 1
                    ));
                }
                for (i, p) in ps.iter().enumerate() {
                    if t(i + 1) != *p {
                        return Err(mismatch(&format!("argument {i}"), t(i + 1), *p));
                    }
                }
                want(res == Some(*r), "call.ind yields the closure's result type")
            }
            Op::CallRt => {
                let Imm::Ext(e) = inst.imm else {
                    return Err("missing runtime function".into());
                };
                let ext = m.externs.get(e.index()).ok_or("bad runtime function")?;
                if n != ext.params.len() {
                    return Err(format!(
                        "{} takes {} arguments, found {n}",
                        ext.name,
                        ext.params.len()
                    ));
                }
                for (i, p) in ext.params.iter().enumerate() {
                    if t(i) != p.ty {
                        return Err(mismatch(&format!("argument {i}"), t(i), p.ty));
                    }
                }
                want(
                    res == Some(ext.ret),
                    "call.rt yields the declared result type",
                )
            }
            Op::CallMethod => {
                let Imm::Method(i, k) = inst.imm else {
                    return Err("missing method".into());
                };
                let sig = m
                    .ifaces
                    .get(i.index())
                    .and_then(|x| x.methods.get(k as usize))
                    .ok_or("bad method")?;
                if n == 0 || !matches!(m.types.kind(t(0)), TyKind::Iface(x) if *x == i) {
                    return Err("operand 0 must be the interface value".into());
                }
                if n - 1 != sig.params.len() {
                    return Err(format!(
                        "{} takes {} arguments, found {}",
                        sig.name,
                        sig.params.len(),
                        n - 1
                    ));
                }
                for (j, p) in sig.params.iter().enumerate() {
                    if t(j + 1) != *p {
                        return Err(mismatch(&format!("argument {j}"), t(j + 1), *p));
                    }
                }
                want(
                    res == Some(sig.ret),
                    "call.method yields the method's result type",
                )
            }
            Op::SharedNew => {
                arity(1)?;
                let ok = matches!(res.map(|r| m.types.kind(r)), Some(TyKind::Obj(n, a)) if n == "Shared" && a.as_slice() == [t(0)]);
                want(ok, "shared.new wraps a value into Shared[T]")
            }
            Op::SharedGet => {
                arity(1)?;
                let ok = matches!(m.types.kind(t(0)), TyKind::Obj(n, a) if n == "Shared" && a.as_slice() == [res.unwrap_or(Ty::UNIT)]);
                want(ok, "shared.get reads the payload of a Shared[T]")
            }
            Op::SharedAddr => {
                arity(1)?;
                let ok = matches!(m.types.kind(t(0)), TyKind::Obj(n, _) if n == "Shared")
                    && res == Some(Ty::PTR);
                want(ok, "shared.addr yields a ptr to the payload of a Shared[T]")
            }
            Op::Copy => {
                arity(1)?;
                want(
                    res == Some(t(0)) && m.needs_drop(t(0)),
                    "copy duplicates a droppable value",
                )
            }
            Op::MoveOut => {
                arity(1)?;
                want(
                    res == Some(t(0)) && m.needs_drop(t(0)),
                    "move.out takes ownership of a droppable value",
                )
            }
            Op::Drop => {
                arity(1)?;
                want(m.needs_drop(t(0)), "drop takes a droppable value")
            }
            Op::DropIf => {
                arity(2)?;
                want(
                    t(0) == Ty::BOOL && m.needs_drop(t(1)),
                    "drop.if takes a flag and a droppable value",
                )
            }
            Op::Slot => {
                arity(0)?;
                want(
                    matches!(inst.imm, Imm::Ty(_)) && res == Some(Ty::PTR),
                    "slot yields ptr",
                )
            }
            Op::ListAddr | Op::ListAddrU => {
                arity(2)?;
                want(
                    m.list_elem(t(0)).is_some() && t(1) == Ty::INT && res == Some(Ty::PTR),
                    "list.addr takes a list and an index and yields a ptr to the element",
                )
            }
            Op::PtrIsNull => {
                arity(1)?;
                want(
                    t(0) == Ty::PTR && res == Some(Ty::BOOL),
                    "ptr.is_null tests a ptr and yields bool",
                )
            }
            Op::PtrField => {
                arity(1)?;
                let Imm::Field(r, i) = inst.imm else {
                    return Err("missing field".into());
                };
                let rec = m.records.get(r.index()).ok_or("bad record")?;
                if rec.fields.get(i as usize).is_none() {
                    return Err("bad field index".into());
                }
                want(
                    t(0) == Ty::PTR && res == Some(Ty::PTR),
                    "ptr.field takes a ptr and yields a ptr",
                )
            }
            Op::Load => {
                arity(1)?;
                let Imm::Ty(ty) = inst.imm else {
                    return Err("missing type".into());
                };
                want(
                    t(0) == Ty::PTR && res == Some(ty),
                    "load reads a value through a ptr; a droppable result is a borrow",
                )
            }
            Op::Take => {
                arity(1)?;
                let Imm::Ty(ty) = inst.imm else {
                    return Err("missing type".into());
                };
                want(
                    t(0) == Ty::PTR && res == Some(ty),
                    "take moves a value out of memory through a ptr; the result is owned",
                )
            }
            Op::Put => {
                arity(2)?;
                want(
                    t(0) == Ty::PTR,
                    "put moves an owned value into memory through a ptr",
                )
            }
            Op::Store => {
                arity(2)?;
                want(
                    t(0) == Ty::PTR,
                    "store writes a value through a ptr; the memory does not own a droppable value, it lends the borrow",
                )
            }
            Op::FuncAddr => {
                arity(0)?;
                let Imm::Func(g) = inst.imm else {
                    return Err("missing function".into());
                };
                want(
                    g.index() < m.funcs.len() && res == Some(Ty::PTR),
                    "func.addr yields the ptr of a function",
                )
            }
            Op::TypeDesc => {
                arity(0)?;
                want(
                    matches!(inst.imm, Imm::Ty(_)) && res == Some(Ty::PTR),
                    "typedesc yields ptr",
                )
            }
            Op::Poll | Op::DepthEnter | Op::DepthLeave => arity(0),
            Op::CleanupRun => {
                arity(1)?;
                want(
                    t(0) == Ty::INT,
                    "cleanup.run takes the handle returned by cleanup.push",
                )
            }
            Op::CleanupPush => {
                arity(1)?;
                let Imm::Func(g) = inst.imm else {
                    return Err("missing closer".into());
                };
                let callee = m.funcs.get(g.index()).ok_or("bad closer")?;
                want(
                    callee.params.len() == 1 && callee.params[0].ty == t(0) && res == Some(Ty::INT),
                    "closer takes the registered value; cleanup.push yields an int handle",
                )
            }
            Op::GlobalGet | Op::GlobalSet => {
                let Imm::Global(g) = inst.imm else {
                    return Err("missing global".into());
                };
                let gd = m.globals.get(g.index()).ok_or("bad global")?;
                if inst.op == Op::GlobalGet {
                    arity(0)?;
                    want(res == Some(gd.ty), "global.get yields the global's type")
                } else {
                    arity(1)?;
                    want(t(0) == gd.ty, "stored value must have the global's type")
                }
            }
        }
    }

    fn check_ownership(&mut self, rpo: &[Block]) {
        let (m, f) = (self.m, self.f);
        let rc = |v: Value| m.needs_drop(f.ty(v));
        // Ownership mode of every value from its definition.
        let mut owned_def = vec![false; f.values.len()];
        for b in &f.blocks {
            for p in &b.params {
                owned_def[p.value.index()] = rc(p.value) && p.mode == Mode::Own;
            }
            for i in &b.insts {
                if let (Some(r), Some(Mode::Own)) = (i.res, m.result_mode(f, i)) {
                    owned_def[r.index()] = true;
                }
            }
        }
        let from_owned = if f.ret_borrowed {
            borrows_from_owned(m, f)
        } else {
            Vec::new()
        };
        let mut entry_state: Vec<Option<BTreeSet<u32>>> = vec![None; f.blocks.len()];
        for &b in rpo {
            let bi = b.index();
            let blk = &f.blocks[bi];
            let mut live: BTreeSet<u32> = match (&entry_state[bi], bi) {
                (Some(s), _) => s.clone(),
                (None, 0) => BTreeSet::new(),
                (None, _) => continue,
            };
            for p in &blk.params {
                if owned_def[p.value.index()] {
                    live.insert(p.value.0);
                }
            }
            for inst in &blk.insts {
                let modes = arg_modes(m, inst);
                let mut consumed_here: Vec<Value> = Vec::new();
                for (a, mode) in inst.args.iter().zip(&modes) {
                    if !rc(*a) {
                        continue;
                    }
                    if owned_def[a.index()] && !live.contains(&a.0) {
                        self.err(
                            Some(bi),
                            format!(
                                "{}: %{} used after it was consumed",
                                inst.op.info().name,
                                a.0
                            ),
                        );
                        continue;
                    }
                    if *mode == Mode::Own {
                        if !owned_def[a.index()] {
                            self.err(Some(bi), format!("{}: consuming position needs an owned value, %{} is borrowed (retain it first)", inst.op.info().name, a.0));
                        } else if consumed_here.contains(a) {
                            self.err(
                                Some(bi),
                                format!("{}: %{} consumed twice", inst.op.info().name, a.0),
                            );
                        } else {
                            consumed_here.push(*a);
                        }
                    }
                }
                for (a, mode) in inst.args.iter().zip(&modes) {
                    if *mode == Mode::Borrow && consumed_here.contains(a) {
                        self.err(
                            Some(bi),
                            format!(
                                "{}: %{} is consumed and borrowed by the same instruction",
                                inst.op.info().name,
                                a.0
                            ),
                        );
                    }
                }
                for a in consumed_here {
                    live.remove(&a.0);
                }
                if let Some(r) = inst.res.filter(|r| owned_def[r.index()]) {
                    live.insert(r.0);
                }
            }
            // Terminator.
            let mut edges: Vec<Target> = Vec::new();
            blk.term.for_each_target(|t| edges.push(t.clone()));
            if let Term::Ret(v) = &blk.term {
                if let Some(v) = v.filter(|v| rc(*v)) {
                    if f.ret_borrowed {
                        if owned_def[v.index()] {
                            self.err(
                                Some(bi),
                                format!(
                                    "ret: %{} is owned; a function that lends returns a borrow",
                                    v.0
                                ),
                            );
                        } else if from_owned[v.index()] {
                            self.err(
                                Some(bi),
                                format!(
                                    "ret: %{} borrows from a value this function owns; a function that lends returns part of a parameter",
                                    v.0
                                ),
                            );
                        }
                    } else if !owned_def[v.index()] {
                        self.err(
                            Some(bi),
                            format!(
                                "ret: %{} is borrowed; return an owned value (retain it first)",
                                v.0
                            ),
                        );
                    } else if !live.remove(&v.0) {
                        self.err(
                            Some(bi),
                            format!("ret: %{} used after it was consumed", v.0),
                        );
                    }
                }
                if let Some(leak) = live.iter().next() {
                    self.err(
                        Some(bi),
                        format!("ret: owned value %{leak} is never released"),
                    );
                }
            }
            for t in edges {
                let dest = &f.blocks[t.block.index()];
                let mut after = live.clone();
                let mut seen = Vec::new();
                for (a, p) in t.args.iter().zip(&dest.params) {
                    if !rc(*a) {
                        continue;
                    }
                    if owned_def[a.index()] && !live.contains(&a.0) {
                        self.err(
                            Some(bi),
                            format!("branch: %{} used after it was consumed", a.0),
                        );
                        continue;
                    }
                    if p.mode == Mode::Own {
                        if !owned_def[a.index()] {
                            self.err(Some(bi), format!("branch to b{}: parameter %{} takes ownership but %{} is borrowed", t.block.0, p.value.0, a.0));
                        } else if seen.contains(a) {
                            self.err(
                                Some(bi),
                                format!(
                                    "branch to b{}: %{} passed to two owning parameters",
                                    t.block.0, a.0
                                ),
                            );
                        } else {
                            seen.push(*a);
                            after.remove(&a.0);
                        }
                    }
                }
                // A condition or scrutinee never needs a drop, so `live` is unchanged.
                match &entry_state[t.block.index()] {
                    None => entry_state[t.block.index()] = Some(after),
                    Some(prev) if *prev == after => {}
                    Some(prev) => {
                        let diff: Vec<String> = prev
                            .symmetric_difference(&after)
                            .map(|v| format!("%{v}"))
                            .collect();
                        self.err(
                            Some(bi),
                            format!(
                                "branch to b{}: owned values differ between incoming edges ({})",
                                t.block.0,
                                diff.join(", ")
                            ),
                        );
                    }
                }
            }
        }
    }
}

fn r_id(inst: &Inst) -> crate::types::RecId {
    match inst.imm {
        Imm::Rec(r) | Imm::Field(r, _) => r,
        _ => crate::types::RecId(u32::MAX),
    }
}

/// Immediate dominators by the Cooper-Harvey-Kennedy algorithm; unreachable blocks get `usize::MAX`.
pub fn dominators(f: &Func, rpo: &[Block], preds: &[Vec<Block>]) -> Vec<usize> {
    let n = f.blocks.len();
    let mut order = vec![usize::MAX; n];
    for (i, b) in rpo.iter().enumerate() {
        order[b.index()] = i;
    }
    let mut idom = vec![usize::MAX; n];
    idom[0] = 0;
    let mut changed = true;
    while changed {
        changed = false;
        for &b in rpo.iter().skip(1) {
            let mut new = usize::MAX;
            for p in &preds[b.index()] {
                if idom[p.index()] == usize::MAX || order[p.index()] == usize::MAX {
                    continue;
                }
                new = if new == usize::MAX {
                    p.index()
                } else {
                    let (mut a, mut c) = (p.index(), new);
                    while a != c {
                        while order[a] > order[c] {
                            a = idom[a];
                        }
                        while order[c] > order[a] {
                            c = idom[c];
                        }
                    }
                    a
                };
            }
            if new != idom[b.index()] {
                idom[b.index()] = new;
                changed = true;
            }
        }
    }
    idom
}

/// For each value of `f`, whether it is, or borrows from, a value `f` owns: an owned
/// instruction result or an owned block parameter. A lent result must not, since the owner is
/// dropped before the caller reads it.
fn borrows_from_owned(m: &Module, f: &Func) -> Vec<bool> {
    let masks = lent_masks(m, f);
    sources(m, f, &masks)
        .into_iter()
        .map(|s| s & OWNED != 0)
        .collect()
}

/// Source bit of a value the function owns; bit `i + 1` is entry parameter `i`, and the last
/// bit stands for every parameter past the others.
const OWNED: u128 = 1;
const EVERY_PARAM: u128 = !OWNED;

fn param_bit(i: usize) -> u128 {
    if i < 126 { 1 << (i + 1) } else { 1 << 127 }
}

/// What the storage of each value of `f` comes from, as source bits.
fn sources(m: &Module, f: &Func, masks: &std::collections::HashMap<usize, u128>) -> Vec<u128> {
    let rc = |v: Value| m.needs_drop(f.ty(v));
    let mut src = vec![0u128; f.values.len()];
    for (bi, b) in f.blocks.iter().enumerate() {
        for (i, p) in b.params.iter().enumerate() {
            if !rc(p.value) {
                continue;
            }
            // An owned parameter (one the function consumes) is dropped at return, like a local.
            let own = if p.mode == Mode::Own { OWNED } else { 0 };
            src[p.value.index()] = own | if bi == 0 { param_bit(i) } else { 0 };
        }
    }
    loop {
        let mut changed = false;
        for b in &f.blocks {
            for i in &b.insts {
                let Some(r) = i.res else { continue };
                let x = match m.result_mode(f, i) {
                    None | Some(Mode::Var) => 0,
                    Some(Mode::Own) => OWNED,
                    Some(Mode::Borrow) => match (i.op, i.imm) {
                        // A lending call's result comes from the arguments its callee lends from.
                        (Op::Call, Imm::Func(g)) => {
                            let mask = masks.get(&g.index()).copied().unwrap_or(EVERY_PARAM);
                            i.args
                                .iter()
                                .enumerate()
                                .filter(|(j, a)| mask & param_bit(*j) != 0 && rc(**a))
                                .fold(0, |acc, (_, a)| acc | src[a.index()])
                        }
                        // A lending interface operation may lend from any of its operands.
                        (Op::CallMethod, _) => i
                            .args
                            .iter()
                            .filter(|a| rc(**a))
                            .fold(0, |acc, a| acc | src[a.index()]),
                        (
                            Op::RecGet
                            | Op::AltGet
                            | Op::ListGet
                            | Op::ListGetNn
                            | Op::ListGetU
                            | Op::OptGet
                            | Op::OptView,
                            _,
                        ) => i.args.first().map_or(0, |a| src[a.index()]),
                        _ => 0,
                    },
                };
                if x & !src[r.index()] != 0 {
                    src[r.index()] |= x;
                    changed = true;
                }
            }
            b.term.for_each_target(|t| {
                let params = &f.blocks[t.block.index()].params;
                for (p, a) in params.iter().zip(&t.args) {
                    let x = src[a.index()];
                    if p.mode == Mode::Borrow && rc(p.value) && x & !src[p.value.index()] != 0 {
                        src[p.value.index()] |= x;
                        changed = true;
                    }
                }
            });
        }
        if !changed {
            return src;
        }
    }
}

/// The parameters each lending function that `f` reaches can return storage from, as source
/// bits: every parameter for a function without a body. Masks start at no parameters and grow
/// together until stable, so recursion gets the least mask its paths support.
fn lent_masks(m: &Module, f: &Func) -> std::collections::HashMap<usize, u128> {
    let lending = |func: &Func| {
        let mut out = Vec::new();
        for b in &func.blocks {
            for i in &b.insts {
                if let (Op::Call, Imm::Func(g), Some(Mode::Borrow)) =
                    (i.op, i.imm, m.result_mode(func, i))
                {
                    out.push(g.index());
                }
            }
        }
        out
    };
    let mut masks = std::collections::HashMap::new();
    let mut work = lending(f);
    while let Some(g) = work.pop() {
        if masks.contains_key(&g) {
            continue;
        }
        let callee = &m.funcs[g];
        if callee.blocks.is_empty() {
            masks.insert(g, EVERY_PARAM);
            continue;
        }
        masks.insert(g, 0);
        work.extend(lending(callee));
    }
    let bodies: Vec<usize> = masks
        .keys()
        .copied()
        .filter(|g| !m.funcs[*g].blocks.is_empty())
        .collect();
    loop {
        let mut changed = false;
        for &g in &bodies {
            let callee = &m.funcs[g];
            let src = sources(m, callee, &masks);
            let mut mask = masks[&g];
            for b in &callee.blocks {
                if let Term::Ret(Some(v)) = &b.term {
                    mask |= src[v.index()] & EVERY_PARAM;
                }
            }
            if mask != masks[&g] {
                masks.insert(g, mask);
                changed = true;
            }
        }
        if !changed {
            return masks;
        }
    }
}
