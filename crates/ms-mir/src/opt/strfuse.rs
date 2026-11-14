//! The `strfuse` pass: appends a built-up string to a `StringBuilder` piece by piece.
//!
//! `b.append("{n},")` lowers to `int_to_string`, `string_concat`, `strbuilder.append` and two
//! drops: two heap strings that live for one call. When the temporaries have no other use, the
//! pieces are appended directly (`strbuilder.append_int` for integers), so the loop allocates
//! nothing. Only runtime string constructors with no effects and no faults are removed, and the
//! sealed-builder check (which stays where it was) still runs before any byte is written.
//!
//! A chain of concatenations (`"{a}:{b}-{c}"` lowers to nested `string_concat`s) becomes one
//! `string_concatN` call, so the result is allocated once instead of once per link. When a piece
//! is a single-use `int_to_string`, the integer itself is passed to `string_fmtN`, which writes
//! its digits into the result: `f"w{i}"` builds no temporary string.
//!
//! `s = s.concat(piece)` lowers to a concat and a drop of the old `s`. When the drop follows
//! with no use of `s` in between, `string_append` moving_params `s` and grows it in place.

use crate::ir::{
    Block, ExternDef, ExternRole, Func, Imm, Inst, Loc, Mode, Module, Op, Param, Value,
};
use crate::types::Ty;
use std::collections::{HashMap, HashSet};

/// Only the in-place `s = s + piece` append, which an unoptimized build needs to keep a loop that
/// grows a string linear.
pub fn run_append(m: &mut Module) -> bool {
    let mut changed = false;
    for fi in 0..m.funcs.len() {
        changed |= append_in_place(m, fi);
    }
    changed
}

/// Runs the pass; returns whether anything changed.
pub fn run(m: &mut Module) -> bool {
    let mut changed = false;
    for fi in 0..m.funcs.len() {
        while fuse_one(m, fi) {
            changed = true;
        }
        while fuse_concat(m, fi) {
            changed = true;
        }
        changed |= append_in_place(m, fi);
    }
    changed
}

enum Piece {
    Int(Value),
    Str(Value),
}

struct Info {
    defs: Vec<Option<(usize, usize)>>,
    uses: Vec<u32>,
    /// Every `drop v`: its position, and how many there are.
    drops: Vec<Vec<(usize, usize)>>,
    preds: Vec<u32>,
    /// Successor blocks, for asking whether a drop can run before a position.
    succs: Vec<Vec<u32>>,
}

impl Info {
    /// Whether `leaf` may be dropped before the instruction at `at` runs. A drop in another block
    /// counts only when that block reaches `at`'s block without redefining the leaf: a drop on a
    /// sibling path, or after the join, does not.
    fn dropped_before(&self, leaf: Value, at: (usize, usize)) -> bool {
        let redefined = self.defs[leaf.index()].map(|(b, _)| b);
        self.drops[leaf.index()].iter().any(|&(db, di)| {
            if db == at.0 {
                return di < at.1;
            }
            let mut seen = vec![false; self.succs.len()];
            let mut work = vec![db];
            seen[db] = true;
            while let Some(b) = work.pop() {
                for &n in &self.succs[b] {
                    let n = n as usize;
                    if n == at.0 {
                        return true;
                    }
                    if !seen[n] && Some(n) != redefined {
                        seen[n] = true;
                        work.push(n);
                    }
                }
            }
            false
        })
    }
}

fn info(f: &Func) -> Info {
    let n = f.values.len();
    let mut d = Info {
        defs: vec![None; n],
        uses: vec![0; n],
        drops: vec![Vec::new(); n],
        preds: vec![0; f.blocks.len()],
        succs: vec![Vec::new(); f.blocks.len()],
    };
    for (bi, b) in f.blocks.iter().enumerate() {
        for (ii, i) in b.insts.iter().enumerate() {
            if let Some(r) = i.res {
                d.defs[r.index()] = Some((bi, ii));
            }
            for a in &i.args {
                d.uses[a.index()] += 1;
            }
            if i.op == Op::Drop {
                d.drops[i.args[0].index()].push((bi, ii));
            }
        }
        b.term.for_each_use(|v| d.uses[v.index()] += 1);
        b.term.for_each_target(|t| {
            d.preds[t.block.index()] += 1;
            d.succs[bi].push(t.block.0);
        });
    }
    d
}

fn ext_role(m: &Module, i: &Inst) -> Option<ExternRole> {
    match (i.op, i.imm) {
        (Op::CallRt, Imm::Ext(e)) => Some(m.externs[e.index()].role),
        _ => None,
    }
}

struct Plan {
    pieces: Vec<Piece>,
    /// Instructions to delete: the constructors and their drops.
    remove: HashSet<(usize, usize)>,
    /// Leaf strings that must stay alive until the append.
    leaves: Vec<Value>,
}

/// Whether the definition block `from` reaches `to` through blocks that each have one predecessor.
fn straight_line(f: &Func, info: &Info, from: usize, to: usize) -> bool {
    let mut cur = to;
    while cur != from {
        if info.preds[cur] != 1 {
            return false;
        }
        let Some(p) = (0..f.blocks.len()).find(|&p| {
            let mut hit = false;
            f.blocks[p]
                .term
                .for_each_target(|t| hit |= t.block == Block(cur as u32));
            hit
        }) else {
            return false;
        };
        cur = p;
    }
    true
}

fn collect(
    m: &Module,
    f: &Func,
    info: &Info,
    v: Value,
    at: usize,
    top: bool,
    plan: &mut Plan,
) -> bool {
    let fused = info.defs[v.index()].and_then(|(db, di)| {
        let inst = &f.blocks[db].insts[di];
        let role = ext_role(m, inst)?;
        let single = info.uses[v.index()] == 2 && info.drops[v.index()].len() == 1;
        (single && fusable(f, inst, role) && straight_line(f, info, db, at)).then_some((
            db,
            di,
            role == ExternRole::StringConcat,
        ))
    });
    let Some((db, di, concat)) = fused else {
        if top {
            return false;
        }
        plan.pieces.push(Piece::Str(v));
        plan.leaves.push(v);
        return true;
    };
    let inst = &f.blocks[db].insts[di];
    plan.remove.insert((db, di));
    plan.remove.insert(info.drops[v.index()][0]);
    if concat {
        collect(m, f, info, inst.args[0], at, false, plan)
            && collect(m, f, info, inst.args[1], at, false, plan)
    } else {
        plan.pieces.push(Piece::Int(inst.args[0]));
        true
    }
}

/// Fuses every builder append that can be fused independently of the others in one scan. Each
/// fusion would otherwise cost a rescan and rewrite of the function, and a function with many
/// interpolated appends would be quadratic.
fn fuse_one(m: &mut Module, fi: usize) -> bool {
    let f = &m.funcs[fi];
    let info = info(f);
    let mut claimed: HashSet<(usize, usize)> = HashSet::new();
    let mut plans = Vec::new();
    for (bi, b) in f.blocks.iter().enumerate() {
        for (ii, inst) in b.insts.iter().enumerate() {
            if ext_role(m, inst) != Some(ExternRole::StrBuilderAppend) {
                continue;
            }
            let mut plan = Plan {
                pieces: Vec::new(),
                remove: HashSet::new(),
                leaves: Vec::new(),
            };
            if !collect(m, f, &info, inst.args[1], bi, true, &mut plan) {
                continue;
            }
            // A leaf string dropped before the append would be used after its drop.
            let early = plan
                .leaves
                .iter()
                .any(|&l| info.dropped_before(l, (bi, ii)));
            if early || plan.pieces.len() > 8 || plan.remove.iter().any(|r| claimed.contains(r)) {
                continue;
            }
            claimed.extend(plan.remove.iter().copied());
            plans.push((bi, ii, plan));
        }
    }
    if plans.is_empty() {
        return false;
    }
    apply(m, fi, plans);
    true
}

/// Replaces each planned append with its piece calls and deletes the constructors and drops the
/// plans absorb, rewriting every block once.
fn apply(m: &mut Module, fi: usize, plans: Vec<(usize, usize, Plan)>) {
    let mut removed: HashSet<(usize, usize)> = HashSet::new();
    let mut replace: HashMap<(usize, usize), Vec<Inst>> = HashMap::new();
    for (bi, ii, plan) in plans {
        let app = m.funcs[fi].blocks[bi].insts[ii].clone();
        let Imm::Ext(append_ext) = app.imm else {
            continue;
        };
        let sb = app.args[0];
        let sb_ty = m.funcs[fi].ty(sb);
        let int_ext = m.add_extern(ExternDef {
            name: "msrt_strbuilder_append_int".to_string(),
            params: vec![
                Param {
                    ty: sb_ty,
                    mode: Mode::Borrow,
                },
                Param {
                    ty: Ty::INT,
                    mode: Mode::Borrow,
                },
            ],
            ret: Ty::UNIT,
            noreturn: false,
            pure_: false,
            fresh: false,
            role: ExternRole::StrBuilderAppendInt,
            leaf: true,
            reads: false,
        });
        let f = &mut m.funcs[fi];
        let last = plan.pieces.len() - 1;
        let mut calls = Vec::new();
        for (k, p) in plan.pieces.iter().enumerate() {
            let res = if k == last {
                app.res
            } else {
                Some(f.new_value(Ty::UNIT))
            };
            let (ext, arg) = match p {
                Piece::Int(x) => (int_ext, *x),
                Piece::Str(s) => (append_ext, *s),
            };
            calls.push(Inst {
                op: Op::CallRt,
                args: vec![sb, arg],
                imm: Imm::Ext(ext),
                res,
                loc: app.loc,
            });
        }
        replace.insert((bi, ii), calls);
        removed.extend(plan.remove);
    }
    let f = &mut m.funcs[fi];
    for (b, blk) in f.blocks.iter_mut().enumerate() {
        let old = std::mem::take(&mut blk.insts);
        let mut insts = Vec::with_capacity(old.len());
        for (k, inst) in old.into_iter().enumerate() {
            if let Some(calls) = replace.remove(&(b, k)) {
                insts.extend(calls);
            } else if !removed.contains(&(b, k)) {
                insts.push(inst);
            }
        }
        blk.insts = insts;
    }
}

/// Most pieces one `string_concatN` or `string_fmtN` joins.
const MAX_JOIN: usize = 6;

fn concat_name(n: usize) -> String {
    format!("msrt_string_concat{n}")
}

/// `msrt_string_fmtN(mask, parts...)`: part `k` is an integer written in decimal when bit `k` of
/// `mask` is set, otherwise a string.
fn fmt_name(n: usize) -> String {
    format!("msrt_string_fmt{n}")
}

/// Whether a call with this role can join a fused chain: a concatenation, or the text of a plain
/// `Int` (a sized integer is declared with its own width, which `string_fmtN` does not take).
fn fusable(f: &Func, inst: &Inst, role: ExternRole) -> bool {
    match role {
        ExternRole::StringConcat => true,
        ExternRole::IntToString => inst.args.first().is_some_and(|a| f.ty(*a) == Ty::INT),
        _ => false,
    }
}

/// What `chain` has gathered for one root: the leaves, the inner links and drops it absorbs, and
/// how many concats (the root included) the join spans.
struct Gather {
    leaves: Vec<Piece>,
    remove: HashSet<(usize, usize)>,
    links: usize,
}

/// Gathers the leaves of the concat chain rooted at `v` into `leaves` and the chain's inner
/// links into `remove`. A leaf that is a single-use `int_to_string` becomes the integer itself.
fn chain(m: &Module, f: &Func, info: &Info, v: Value, at: (usize, usize), g: &mut Gather) {
    // A join takes at most MAX_JOIN leaves, so descend into at most MAX_JOIN - 1 links and keep a
    // deeper concat as a leaf: it is a root of its own, fused in the same scan. Rejecting the whole
    // chain instead fuses one group per scan, which is quadratic in the length of a long
    // interpolation. The value must stay a leaf, not vanish: the join is built from `leaves`.
    let capped = g.links >= MAX_JOIN - 1;
    let inner = info.defs[v.index()].and_then(|(db, di)| {
        let single = info.uses[v.index()] == 2 && info.drops[v.index()].len() == 1;
        let (dbi, ddi) = info.drops[v.index()].first().copied()?;
        let inst = &f.blocks[db].insts[di];
        let role = ext_role(m, inst)?;
        let ok = fusable(f, inst, role)
            && single
            && straight_line(f, info, db, at.0)
            && (dbi != at.0 || ddi > at.1 || db != at.0 || di < at.1);
        ok.then_some((db, di, role == ExternRole::StringConcat))
    });
    // At the cap a deeper concat stays a leaf, but an integer's text still becomes the integer.
    let Some((db, di, concat)) = inner.filter(|&(_, _, concat)| !(capped && concat)) else {
        g.leaves.push(Piece::Str(v));
        return;
    };
    g.remove.insert((db, di));
    g.remove.insert(info.drops[v.index()][0]);
    let args = f.blocks[db].insts[di].args.clone();
    if !concat {
        g.leaves.push(Piece::Int(args[0]));
        return;
    }
    g.links += 1;
    chain(m, f, info, args[0], at, g);
    chain(m, f, info, args[1], at, g);
}

/// One fused root: the concat at `at` becomes a join of `leaves`, and `remove` holds the links
/// and drops it absorbs.
struct Fusion {
    at: (usize, usize),
    leaves: Vec<Piece>,
    remove: HashSet<(usize, usize)>,
}

/// Whether `root` is `s = s + piece` on a loop-carried owned `s` that dies right after: a fused
/// join would copy the whole prefix every iteration, so the root is left for `append_in_place`
/// (which grows `s` in place) and only `piece` fuses, as a root of its own.
fn accumulator_append(f: &Func, root: &Inst, at: (usize, usize)) -> bool {
    let (Some(&a), Some(&b)) = (root.args.first(), root.args.get(1)) else {
        return false;
    };
    let carried = f.blocks[1..]
        .iter()
        .flat_map(|blk| &blk.params)
        .any(|p| p.value == a && p.mode == Mode::Move);
    if !carried || b == a {
        return false;
    }
    // The first use of `a` after the root is a drop in the same block.
    let rest = &f.blocks[at.0].insts[at.1 + 1..];
    rest.iter()
        .find(|i| i.args.contains(&a))
        .is_some_and(|i| i.op == Op::Drop)
}

/// Fuses every chain that can be fused independently of the others in one scan. Each fusion
/// would otherwise cost a rescan of the function, and a function with many interpolated
/// strings would be quadratic.
fn fuse_concat(m: &mut Module, fi: usize) -> bool {
    let f = &m.funcs[fi];
    let info = info(f);
    let mut claimed: HashSet<(usize, usize)> = HashSet::new();
    let mut fusions = Vec::new();
    for (bi, b) in f.blocks.iter().enumerate() {
        for (ii, inst) in b.insts.iter().enumerate().rev() {
            if ext_role(m, inst) != Some(ExternRole::StringConcat) || claimed.contains(&(bi, ii)) {
                continue;
            }
            if accumulator_append(f, inst, (bi, ii)) {
                continue;
            }
            let mut g = Gather {
                leaves: Vec::new(),
                remove: HashSet::new(),
                links: 1,
            };
            for &a in &inst.args {
                chain(m, f, &info, a, (bi, ii), &mut g);
            }
            let Gather { leaves, remove, .. } = g;
            let ints = leaves.iter().any(|p| matches!(p, Piece::Int(_)));
            // Two strings are what `concat` already does; two parts with an integer save the
            // temporary string.
            if remove.is_empty() || (leaves.len() < 3 && !ints) || leaves.len() > MAX_JOIN {
                continue;
            }
            // A leaf dropped before the join would be used after its drop.
            let early = leaves.iter().any(|l| match l {
                Piece::Str(l) => info.dropped_before(*l, (bi, ii)),
                Piece::Int(_) => false,
            });
            if early || remove.iter().any(|r| claimed.contains(r)) {
                continue;
            }
            claimed.insert((bi, ii));
            claimed.extend(remove.iter().copied());
            fusions.push(Fusion {
                at: (bi, ii),
                leaves,
                remove,
            });
        }
    }
    if fusions.is_empty() {
        return false;
    }
    apply_concats(m, fi, fusions);
    true
}

fn apply_concats(m: &mut Module, fi: usize, fusions: Vec<Fusion>) {
    // Rewrite every root first, remembering where each mask constant goes.
    let mut masks: Vec<((usize, usize), Value, i64, Loc)> = Vec::new();
    let mut removed: HashSet<(usize, usize)> = HashSet::new();
    for fusion in fusions {
        let Fusion {
            at: (bi, ii),
            leaves,
            remove,
        } = fusion;
        let ints = leaves.iter().any(|p| matches!(p, Piece::Int(_)));
        let piece_params = leaves.iter().map(|p| Param {
            ty: match p {
                Piece::Int(_) => Ty::INT,
                Piece::Str(_) => Ty::STR,
            },
            mode: Mode::Borrow,
        });
        let mut params = Vec::new();
        if ints {
            params.push(Param {
                ty: Ty::INT,
                mode: Mode::Borrow,
            });
        }
        params.extend(piece_params);
        let ext = m.add_extern(ExternDef {
            name: if ints {
                fmt_name(leaves.len())
            } else {
                concat_name(leaves.len())
            },
            params,
            ret: Ty::STR,
            noreturn: false,
            pure_: false,
            fresh: true,
            role: ExternRole::None,
            leaf: true,
            reads: false,
        });
        let f = &mut m.funcs[fi];
        let mut mask = 0i64;
        let mut args = Vec::new();
        for (k, p) in leaves.iter().enumerate() {
            match p {
                Piece::Int(v) => {
                    mask |= 1 << k;
                    args.push(*v);
                }
                Piece::Str(v) => args.push(*v),
            }
        }
        let loc = f.blocks[bi].insts[ii].loc;
        if ints {
            let mv = f.new_value(Ty::INT);
            args.insert(0, mv);
            masks.push(((bi, ii), mv, mask, loc));
        }
        let root = &mut f.blocks[bi].insts[ii];
        root.args = args;
        root.imm = Imm::Ext(ext);
        removed.extend(remove);
    }
    // The mask constant goes right before its root: positions shift by the removals before it.
    let f = &mut m.funcs[fi];
    masks.sort_by_key(|&(at, ..)| std::cmp::Reverse(at));
    let mut gone: Vec<Vec<bool>> = f
        .blocks
        .iter()
        .map(|b| vec![false; b.insts.len()])
        .collect();
    for &(b, k) in &removed {
        gone[b][k] = true;
    }
    // `before[b][k]`: removals in block `b` ahead of position `k`.
    let before: Vec<Vec<u32>> = gone
        .iter()
        .map(|g| {
            let mut n = 0;
            g.iter()
                .map(|&x| {
                    let at = n;
                    n += x as u32;
                    at
                })
                .collect()
        })
        .collect();
    let shifts: Vec<usize> = masks
        .iter()
        .map(|&((bi, ii), ..)| before[bi][ii] as usize)
        .collect();
    for (b, blk) in f.blocks.iter_mut().enumerate() {
        let mut k = 0usize;
        blk.insts.retain(|_| {
            let keep = !gone[b][k];
            k += 1;
            keep
        });
    }
    for (&((bi, ii), mv, mask, loc), shift) in masks.iter().zip(shifts) {
        f.blocks[bi].insts.insert(
            ii - shift,
            Inst {
                op: Op::IConst,
                args: Vec::new(),
                imm: Imm::Int(mask),
                res: Some(mv),
                loc,
            },
        );
    }
}

/// Rewrites `r = string_concat(a, b); ...; drop a` to `r = string_append(a, b)` when `a` is an
/// owned value that nothing reads between the concat and its drop.
fn append_in_place(m: &mut Module, fi: usize) -> bool {
    let f = &m.funcs[fi];
    let mut owned = vec![false; f.values.len()];
    for b in &f.blocks[1..] {
        for p in &b.params {
            owned[p.value.index()] = p.mode == Mode::Move;
        }
    }
    for b in &f.blocks {
        for i in &b.insts {
            if let Some(r) = i.res {
                owned[r.index()] = m.result_mode(f, i) == Some(Mode::Move);
            }
        }
    }
    let mut sites = Vec::new();
    // `next[v]` is `(block, index)` of the first use of `v` after the instruction being visited.
    // One backward scan per block finds every site's next use, where searching forward from each
    // site is quadratic when the drops all sit at the end of a long block.
    let mut next: Vec<(usize, usize)> = vec![(usize::MAX, 0); f.values.len()];
    for (bi, b) in f.blocks.iter().enumerate() {
        for (ii, inst) in b.insts.iter().enumerate().rev() {
            let site = inst
                .args
                .first()
                .copied()
                .filter(|a| ext_role(m, inst) == Some(ExternRole::StringConcat) && owned[a.index()])
                .filter(|a| inst.args[1] != *a);
            if let Some(a) = site {
                let (nb, j) = next[a.index()];
                if nb == bi && b.insts[j].op == Op::Drop {
                    sites.push(((bi, ii), (bi, j)));
                }
            }
            for a in &inst.args {
                next[a.index()] = (bi, ii);
            }
        }
    }
    if sites.is_empty() {
        return false;
    }
    let ext = m.add_extern(ExternDef {
        name: "msrt_string_append".to_string(),
        params: vec![
            Param {
                ty: Ty::STR,
                mode: Mode::Move,
            },
            Param {
                ty: Ty::STR,
                mode: Mode::Borrow,
            },
        ],
        ret: Ty::STR,
        noreturn: false,
        pure_: false,
        fresh: true,
        role: ExternRole::StringAppend,
        leaf: true,
        reads: false,
    });
    let f = &mut m.funcs[fi];
    let remove: HashSet<(usize, usize)> = sites.iter().map(|s| s.1).collect();
    for &((bi, ii), _) in &sites {
        f.blocks[bi].insts[ii].imm = Imm::Ext(ext);
    }
    for (b, blk) in f.blocks.iter_mut().enumerate() {
        let mut k = 0usize;
        blk.insts.retain(|_| {
            let keep = !remove.contains(&(b, k));
            k += 1;
            keep
        });
    }
    true
}
