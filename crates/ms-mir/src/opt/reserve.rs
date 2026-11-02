//! The `reserve` pass: sizes a fresh list for the loop that fills it.
//!
//! A list built one `append` per iteration of a counted loop grows by doubling, so it is
//! copied about `log2(n)` times. When the loop's trip count is known before it starts,
//! the list can be allocated at its final size instead:
//!
//! ```text
//! l0 = list.lit                      cap = <clamped trip count + k>
//! l1 = list.push l0, x               l0 = list.new cap
//! br head(i0, l1)            =>      l1 = list.push l0, x
//! head(i, l):                        br head(i0, l1)
//!   br_if (icmp.lt i, n), body, out
//! ```
//!
//! The rewrite applies when the empty literal reaches the loop entry through `k` pushes
//! in one block, the loop's only exit is the header's false edge, every back edge passes
//! `i + 1`, and every path from the header to a back edge pushes the list at least once.
//! Then the loop pushes at least `max(0, n - i0)` items (one more for `icmp.le`). Capacity
//! is not observable, so a loop that faults early only allocated sooner; the trip count is
//! clamped to [`MAX_RESERVE`] items so a huge bound never allocates more than that up front.

use crate::ir::*;
use crate::types::Ty;
use crate::verify::dominators;

/// The most items reserved ahead of the loop; a longer loop grows from there.
pub const MAX_RESERVE: i64 = 1 << 20;

/// Runs the pass; returns whether anything changed.
pub fn run(m: &mut Module) -> bool {
    let mut changed = false;
    for fi in 0..m.funcs.len() {
        while let Some(plan) = find(&m.funcs[fi]) {
            apply(&mut m.funcs[fi], plan);
            changed = true;
        }
    }
    changed
}

/// Where a value is defined.
#[derive(Clone, Copy)]
enum Def {
    Inst(usize, usize),
    Param(usize),
}

/// A literal to replace with a sized `list.new`.
struct Plan {
    /// The block and index of the literal.
    at: (usize, usize),
    lit: Value,
    /// Pushes between the literal and the loop.
    pushed: i64,
    /// Loop start and bound, and whether the bound is inclusive.
    start: Source,
    bound: Source,
    inclusive: bool,
}

/// How to obtain a value at the literal.
#[derive(Clone, Copy)]
enum Source {
    /// Already available there.
    Value(Value),
    /// A constant to materialize.
    Const(i64),
    /// The length of an available list.
    Len(Value),
}

struct Cfg {
    preds: Vec<Vec<Block>>,
    idom: Vec<usize>,
    defs: Vec<Option<Def>>,
    uses: Vec<u32>,
}

impl Cfg {
    fn new(f: &Func) -> Cfg {
        let rpo = f.rpo();
        let preds = f.predecessors();
        let idom = dominators(f, &rpo, &preds);
        let mut defs = vec![None; f.values.len()];
        for (bi, b) in f.blocks.iter().enumerate() {
            for p in &b.params {
                defs[p.value.index()] = Some(Def::Param(bi));
            }
            for (ii, i) in b.insts.iter().enumerate() {
                if let Some(r) = i.res {
                    defs[r.index()] = Some(Def::Inst(bi, ii));
                }
            }
        }
        for v in f.param_values() {
            defs[v.index()] = Some(Def::Param(0));
        }
        Cfg {
            preds,
            idom,
            defs,
            uses: f.use_counts(),
        }
    }

    /// Whether block `a` dominates block `b`.
    fn dominates(&self, a: usize, mut b: usize) -> bool {
        if self.idom[b] == usize::MAX {
            return false;
        }
        while b != a {
            if b == 0 {
                return false;
            }
            b = self.idom[b];
        }
        true
    }

    /// Whether `v` is defined before instruction `at`.
    fn available(&self, v: Value, at: (usize, usize)) -> bool {
        match self.defs[v.index()] {
            Some(Def::Param(b)) => self.dominates(b, at.0),
            Some(Def::Inst(b, i)) if b == at.0 => i < at.1,
            Some(Def::Inst(b, _)) => self.dominates(b, at.0),
            None => false,
        }
    }

    fn inst<'f>(&self, f: &'f Func, v: Value) -> Option<&'f Inst> {
        let Some(Def::Inst(b, i)) = self.defs[v.index()] else {
            return None;
        };
        Some(&f.blocks[b].insts[i])
    }
}

/// The first literal in `f` that the pass can size.
fn find(f: &Func) -> Option<Plan> {
    // Only empty list literals can be replaced. Avoid building and querying
    // the CFG when the function contains no candidate allocation.
    if !f.blocks.iter().any(|b| {
        b.insts
            .iter()
            .any(|i| i.op == Op::ListLit && i.args.is_empty())
    }) {
        return None;
    }
    let cfg = Cfg::new(f);
    (1..f.blocks.len()).find_map(|h| plan_loop(f, &cfg, h))
}

fn plan_loop(f: &Func, cfg: &Cfg, h: usize) -> Option<Plan> {
    let head = &f.blocks[h];
    let Term::CondBr { cond, then, els } = &head.term else {
        return None;
    };
    let latches: Vec<usize> = cfg.preds[h]
        .iter()
        .map(|b| b.index())
        .filter(|&p| cfg.dominates(h, p))
        .collect();
    if latches.is_empty() {
        return None;
    }
    let body = natural_loop(cfg, h, &latches);
    if body.contains(&els.block.index()) || !body.contains(&then.block.index()) {
        return None;
    }
    // The header's false edge is the only way out.
    for &b in &body {
        let term = &f.blocks[b].term;
        if matches!(term, Term::Ret(_) | Term::Unreachable) {
            return None;
        }
        if b != h && term.successors().iter().any(|s| !body.contains(&s.index())) {
            return None;
        }
    }
    let entries: Vec<usize> = cfg.preds[h]
        .iter()
        .map(|b| b.index())
        .filter(|p| !body.contains(p))
        .collect();
    let [entry] = entries[..] else {
        return None;
    };
    let Term::Br(enter) = &f.blocks[entry].term else {
        return None;
    };
    let test = cfg.inst(f, *cond)?;
    let (Op::ICmp, Imm::Cc(cc @ (Cc::Lt | Cc::Le))) = (test.op, test.imm) else {
        return None;
    };
    let (i, n) = (test.args[0], test.args[1]);
    let ip = head.params.iter().position(|p| p.value == i)?;
    let backs: Vec<Vec<Value>> = latches.iter().map(|&l| back_args(f, l, h)).collect();
    if !backs.iter().all(|a| is_increment(f, cfg, a[ip], i)) {
        return None;
    }
    (0..head.params.len()).find_map(|lp| {
        let l = head.params[lp].value;
        if lp == ip || !backs.iter().all(|a| grows(f, cfg, &body, a[lp], l)) {
            return None;
        }
        let (at, lit, pushed) = literal_chain(f, cfg, entry, enter.args[lp])?;
        let start = source(f, cfg, &body, enter.args[ip], at)?;
        let bound = source(f, cfg, &body, n, at)?;
        Some(Plan {
            at,
            lit,
            pushed,
            start,
            bound,
            inclusive: cc == Cc::Le,
        })
    })
}

/// Blocks of the natural loop of `h` with back edges from `latches`.
fn natural_loop(cfg: &Cfg, h: usize, latches: &[usize]) -> Vec<usize> {
    let mut body = vec![h];
    let mut work: Vec<usize> = latches.to_vec();
    while let Some(b) = work.pop() {
        if body.contains(&b) {
            continue;
        }
        body.push(b);
        work.extend(cfg.preds[b].iter().map(|p| p.index()));
    }
    body
}

/// The arguments latch `l` passes to header `h`.
fn back_args(f: &Func, l: usize, h: usize) -> Vec<Value> {
    let mut args = Vec::new();
    f.blocks[l].term.for_each_target(|t| {
        if t.block.index() == h {
            args = t.args.clone();
        }
    });
    args
}

/// Whether `v` is `i + 1`.
fn is_increment(f: &Func, cfg: &Cfg, v: Value, i: Value) -> bool {
    let Some(add) = cfg.inst(f, v) else {
        return false;
    };
    if !matches!(add.op, Op::IAdd | Op::IAddChk) || add.args[0] != i {
        return false;
    }
    cfg.inst(f, add.args[1])
        .is_some_and(|c| c.op == Op::IConst && c.imm == Imm::Int(1))
}

/// Whether every path from the header to `v` pushed onto the list `l` at least once.
fn grows(f: &Func, cfg: &Cfg, body: &[usize], v: Value, l: Value) -> bool {
    let mut seen = Vec::new();
    reach(f, cfg, body, v, l, true, &mut seen)
}

/// Whether `v` is `l` after pushes only (at least one with `once`). Loop parameters met
/// again are assumed to hold `l` unchanged, which never proves a push.
fn reach(
    f: &Func,
    cfg: &Cfg,
    body: &[usize],
    v: Value,
    l: Value,
    once: bool,
    seen: &mut Vec<Value>,
) -> bool {
    if v == l {
        return !once;
    }
    if seen.contains(&v) {
        return !once;
    }
    seen.push(v);
    let ok = match cfg.defs[v.index()] {
        Some(Def::Inst(b, i)) if body.contains(&b) => {
            let inst = &f.blocks[b].insts[i];
            inst.op == Op::ListPush && reach(f, cfg, body, inst.args[0], l, false, seen)
        }
        Some(Def::Param(b)) if body.contains(&b) => {
            let k = f.blocks[b].params.iter().position(|p| p.value == v);
            let Some(k) = k else {
                return false;
            };
            cfg.preds[b].iter().all(|p| {
                let args = back_args(f, p.index(), b);
                reach(f, cfg, body, args[k], l, once, seen)
            })
        }
        _ => false,
    };
    seen.pop();
    ok
}

/// The empty literal that reaches `v` in block `entry` through pushes, with the push count.
fn literal_chain(
    f: &Func,
    cfg: &Cfg,
    entry: usize,
    v: Value,
) -> Option<((usize, usize), Value, i64)> {
    let mut v = v;
    let mut pushed = 0;
    loop {
        if cfg.uses[v.index()] != 1 {
            return None;
        }
        let Some(Def::Inst(b, i)) = cfg.defs[v.index()] else {
            return None;
        };
        let inst = &f.blocks[b].insts[i];
        if b != entry {
            return None;
        }
        match inst.op {
            Op::ListLit if inst.args.is_empty() => return Some(((b, i), v, pushed)),
            Op::ListPush => {
                pushed += 1;
                v = inst.args[0];
            }
            _ => return None,
        }
    }
}

/// How to compute `v` at `at`: an available value, a constant, or the length of an
/// available list (a loop condition re-reads `list.len` each iteration).
fn source(f: &Func, cfg: &Cfg, body: &[usize], v: Value, at: (usize, usize)) -> Option<Source> {
    let inst = cfg.inst(f, v);
    if let Some(Imm::Int(c)) = inst.filter(|i| i.op == Op::IConst).map(|i| i.imm) {
        return Some(Source::Const(c));
    }
    if cfg.available(v, at) {
        return Some(Source::Value(v));
    }
    let len = inst.filter(|i| i.op == Op::ListLen)?;
    let Some(Def::Inst(b, _)) = cfg.defs[v.index()] else {
        return None;
    };
    (body.contains(&b) && cfg.available(len.args[0], at)).then_some(Source::Len(len.args[0]))
}

fn apply(f: &mut Func, plan: Plan) {
    let (b, i) = plan.at;
    let mut out = Emit {
        loc: f.blocks[b].insts[i].loc,
        code: Vec::new(),
    };
    let start = out.source(f, plan.start);
    let bound = out.source(f, plan.bound);
    let zero = out.int(f, 0);
    let most = out.int(f, MAX_RESERVE);
    let extra = out.int(f, plan.pushed + plan.inclusive as i64);
    // A wrapped difference lands in 0..=MAX_RESERVE and is zeroed unless the loop runs.
    let diff = out.op(f, Op::ISub, &[bound, start], Imm::None, Ty::INT);
    let neg = out.op(f, Op::ICmp, &[diff, zero], Imm::Cc(Cc::Lt), Ty::BOOL);
    let diff = out.op(f, Op::Select, &[neg, zero, diff], Imm::None, Ty::INT);
    let big = out.op(f, Op::ICmp, &[diff, most], Imm::Cc(Cc::Gt), Ty::BOOL);
    let diff = out.op(f, Op::Select, &[big, most, diff], Imm::None, Ty::INT);
    let cc = if plan.inclusive { Cc::Le } else { Cc::Lt };
    let runs = out.op(f, Op::ICmp, &[start, bound], Imm::Cc(cc), Ty::BOOL);
    let diff = out.op(f, Op::Select, &[runs, diff, zero], Imm::None, Ty::INT);
    let cap = out.op(f, Op::IAdd, &[diff, extra], Imm::None, Ty::INT);
    out.code.push(Inst {
        op: Op::ListNew,
        args: vec![cap],
        imm: Imm::None,
        res: Some(plan.lit),
        loc: out.loc,
    });
    f.blocks[b].insts.splice(i..=i, out.code);
}

/// Instructions inserted before the literal.
struct Emit {
    loc: Loc,
    code: Vec<Inst>,
}

impl Emit {
    fn op(&mut self, f: &mut Func, op: Op, args: &[Value], imm: Imm, ty: Ty) -> Value {
        let res = f.new_value(ty);
        self.code.push(Inst {
            op,
            args: args.to_vec(),
            imm,
            res: Some(res),
            loc: self.loc,
        });
        res
    }

    fn int(&mut self, f: &mut Func, c: i64) -> Value {
        self.op(f, Op::IConst, &[], Imm::Int(c), Ty::INT)
    }

    fn source(&mut self, f: &mut Func, s: Source) -> Value {
        match s {
            Source::Value(v) => v,
            Source::Const(c) => self.int(f, c),
            Source::Len(l) => self.op(f, Op::ListLen, &[l], Imm::None, Ty::INT),
        }
    }
}
