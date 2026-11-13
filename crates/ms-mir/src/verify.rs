//! The MIR verifier: structure, SSA dominance, operand types and ownership.
//!
//! # Ownership rules
//!
//! Ownership is checked as a linear-type property on values whose type
//! needs a drop:
//!
//! * A value is *owned* when it is defined by an instruction that returns an
//!   owned value (see [`Module::result_mode`]), is a parameter with [`Mode::Move`],
//!   or is a block parameter with [`Mode::Move`]. Everything else is *borrowed*.
//! * Consuming positions (see [`arg_modes`]) require an owned operand and
//!   remove it from the live set. Borrowing positions accept either kind but
//!   an owned value must still be live.
//! * The live set must be identical on every edge into a block (after the
//!   edge's arguments are consumed) and empty at `ret`. `fault` and
//!   `unreachable` end the program, so values held at that point are ignored.

use crate::ir::*;
use crate::types::Ty;
use std::collections::BTreeSet;
use std::fmt;

mod types;

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
    let drops = drop_table(m);
    for f in &m.funcs {
        if let Err(e) = verify_func_in(m, f, opts, &drops) {
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

/// [`Module::needs_drop`] of every type, indexed by [`Ty`].
fn drop_table(m: &Module) -> Vec<bool> {
    (0..m.types.len() as u32)
        .map(|i| m.needs_drop(Ty(i)))
        .collect()
}

fn verify_func_in(
    m: &Module,
    f: &Func,
    opts: VerifyOptions,
    drops: &[bool],
) -> Result<(), Vec<VerifyError>> {
    let mut v = Verifier {
        m,
        f,
        opts,
        errs: Vec::new(),
        drops,
    };
    v.run();
    if v.errs.is_empty() {
        v.scoped_closures();
    }
    if v.errs.is_empty() {
        Ok(())
    } else {
        Err(v.errs)
    }
}

/// Whether `f` still carries scope markers: it is in the Raw phase until `elaborate` runs.
pub fn is_raw(f: &Func) -> bool {
    f.blocks.iter().flat_map(|b| &b.insts).any(|i| {
        matches!(
            i.op,
            Op::ScopeBegin | Op::ScopeOwn | Op::ScopeEnd | Op::ScopeDisown | Op::ScopeMark
        )
    })
}

/// For each argument of `inst`, whether the position moving_params an owned value.
pub fn arg_modes(m: &Module, inst: &Inst) -> Vec<Mode> {
    let n = inst.args.len();
    let all = |mode: Mode| vec![mode; n];
    let one = |i: usize| {
        let mut v = vec![Mode::Borrow; n];
        if i < n {
            v[i] = Mode::Move;
        }
        v
    };
    match inst.op {
        Op::TypeNew | Op::AltNew | Op::ListLit | Op::ClosureNew => all(Mode::Move),
        Op::TypeSet
        | Op::TypeFill
        | Op::ListPush
        | Op::ListDropLast
        | Op::ListSet
        | Op::ListSetNn
        | Op::ListSetU
        | Op::ListFill => all(Mode::Move),
        Op::OptSome
        | Op::IfaceNew
        | Op::Drop
        | Op::ListRelease
        | Op::GlobalSet
        | Op::AltUnbox
        | Op::AltRelease
        | Op::TypeRelease
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
    /// [`Module::needs_drop`] of every type, indexed by [`Ty`] and built once per module: it
    /// scans every case of an enum, so asking per instruction made a function over a large enum
    /// quadratic.
    drops: &'a [bool],
}

impl Verifier<'_> {
    fn needs_drop(&self, ty: Ty) -> bool {
        self.drops[ty.index()]
    }

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

    /// A closure that points into its maker's frame must not outlive it: follow each one
    /// through copies and block arguments, and reject a use that keeps or returns it.
    fn scoped_closures(&mut self) {
        let f = self.f;
        let mut family: BTreeSet<Value> = BTreeSet::new();
        for b in &f.blocks {
            for inst in &b.insts {
                if let (Op::ClosureNew, Imm::Func(g), Some(r)) = (inst.op, inst.imm, inst.res)
                    && self.m.funcs.get(g.index()).is_some_and(|c| c.scoped)
                {
                    family.insert(r);
                }
            }
        }
        if family.is_empty() {
            return;
        }
        loop {
            let before = family.len();
            for b in &f.blocks {
                for inst in &b.insts {
                    if inst.op == Op::Clone
                        && let (Some(a), Some(r)) = (inst.args.first(), inst.res)
                        && family.contains(a)
                    {
                        family.insert(r);
                    }
                }
                b.term.for_each_target(|t| {
                    let params = &f.blocks[t.block.index()].params;
                    for (a, p) in t.args.iter().zip(params) {
                        if family.contains(a) {
                            family.insert(p.value);
                        }
                    }
                });
            }
            if family.len() == before {
                break;
            }
        }
        let frame_slots: BTreeSet<Value> = f
            .blocks
            .iter()
            .flat_map(|b| &b.insts)
            .filter(|i| i.op == Op::Slot)
            .filter_map(|i| i.res)
            .collect();
        for (bi, b) in f.blocks.iter().enumerate() {
            for inst in &b.insts {
                let modes = arg_modes(self.m, inst);
                for (i, a) in inst.args.iter().enumerate() {
                    if !family.contains(a) {
                        continue;
                    }
                    // A call to a function that keeps its closures, or the closure such a
                    // function builds around one (it can be inlined into this frame), is held by
                    // the checker until the promise is dropped.
                    let promise_entry = matches!(inst.op, Op::Call | Op::ClosureNew)
                        && matches!(inst.imm, Imm::Func(g) if self.m.funcs[g.index()].keeps_scoped);
                    let keeps = match inst.op {
                        _ if promise_entry => false,
                        Op::Drop | Op::DropIf | Op::Clone | Op::CallInd => false,
                        // A stack slot of this frame cannot outlive it: a closure that reads
                        // another one through a borrowed capture stores it there.
                        Op::Store => i == 1 && !frame_slots.contains(&inst.args[0]),
                        _ => modes.get(i) == Some(&Mode::Move),
                    };
                    if keeps {
                        self.err(
                            Some(bi),
                            format!(
                                "a closure that borrows its maker's variables is kept by {}",
                                inst.op.info().name
                            ),
                        );
                    }
                }
            }
            if let Term::Ret(Some(v)) = &b.term
                && family.contains(v)
            {
                self.err(
                    Some(bi),
                    "a closure that borrows its maker's variables is returned",
                );
            }
        }
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
                || (self.needs_drop(p.ty) && bp.mode != p.mode)
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
                    .any(|p| p.mode == Mode::Move && self.needs_drop(p.ty))
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
        // A Raw function leaves its drops to `elaborate`, so its ownership is checked after it.
        if self.errs.is_empty() && !is_raw(self.f) {
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
            // The lowering re-invokes the function from the check on a new stack segment with
            // the entry block's parameters, so nothing may run before it.
            if inst.op == Op::DepthEnter && (bi != 0 || ii != 0) {
                self.err(
                    Some(bi),
                    format!("{name}: must be the first instruction of the entry block"),
                );
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

    fn check_ownership(&mut self, rpo: &[Block]) {
        let (m, f) = (self.m, self.f);
        let drops = self.drops;
        let rc = |v: Value| drops[f.ty(v).index()];
        // Ownership mode of every value from its definition.
        let mut owned_def = vec![false; f.values.len()];
        for b in &f.blocks {
            for p in &b.params {
                owned_def[p.value.index()] = rc(p.value) && p.mode == Mode::Move;
            }
            for i in &b.insts {
                if let (Some(r), Some(Mode::Move)) = (i.res, m.result_mode(f, i)) {
                    owned_def[r.index()] = true;
                }
            }
        }
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
                    if *mode == Mode::Move {
                        if !owned_def[a.index()] {
                            self.err(Some(bi), format!("{}: moving position needs an owned value, %{} is borrowed (retain it first)", inst.op.info().name, a.0));
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
                                    "ret: %{} is owned, but this function returns a borrow; it would leak",
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
                    if p.mode == Mode::Move {
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

fn r_id(inst: &Inst) -> crate::types::TypeId {
    match inst.imm {
        Imm::Type(r) | Imm::Field(r, _) => r,
        _ => crate::types::TypeId(u32::MAX),
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
