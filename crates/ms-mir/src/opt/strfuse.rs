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
//! with no use of `s` in between, `string_append` consumes `s` and grows it in place.

use crate::ir::{Block, ExternDef, Func, Imm, Inst, Mode, Module, Op, Param, Value};
use crate::types::Ty;
use std::collections::HashSet;

const APPEND: &str = "msrt_strbuilder_append";
const APPEND_INT: &str = "msrt_strbuilder_append_int";
const CONCAT: &str = "msrt_string_concat";
const APPEND_STR: &str = "msrt_string_append";
const INT_TO_STRING: &str = "msrt_int_to_string";

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
}

fn info(f: &Func) -> Info {
    let n = f.values.len();
    let mut d = Info {
        defs: vec![None; n],
        uses: vec![0; n],
        drops: vec![Vec::new(); n],
        preds: vec![0; f.blocks.len()],
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
        b.term.for_each_target(|t| d.preds[t.block.index()] += 1);
    }
    d
}

fn ext_name<'a>(m: &'a Module, i: &Inst) -> Option<&'a str> {
    match (i.op, i.imm) {
        (Op::CallRt, Imm::Ext(e)) => Some(m.externs[e.index()].name.as_str()),
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
        let name = ext_name(m, inst)?;
        let single = info.uses[v.index()] == 2 && info.drops[v.index()].len() == 1;
        (single && matches!(name, CONCAT | INT_TO_STRING) && straight_line(f, info, db, at))
            .then_some((db, di, name == CONCAT))
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

fn fuse_one(m: &mut Module, fi: usize) -> bool {
    let f = &m.funcs[fi];
    let info = info(f);
    for (bi, b) in f.blocks.iter().enumerate() {
        for (ii, inst) in b.insts.iter().enumerate() {
            if ext_name(m, inst) != Some(APPEND) {
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
            let early = plan.leaves.iter().any(|l| {
                info.drops[l.index()]
                    .iter()
                    .any(|&(db, di)| db != bi || di < ii)
            });
            if early || plan.pieces.len() > 8 {
                continue;
            }
            apply(m, fi, bi, ii, plan);
            return true;
        }
    }
    false
}

fn apply(m: &mut Module, fi: usize, bi: usize, ii: usize, plan: Plan) {
    let app = m.funcs[fi].blocks[bi].insts[ii].clone();
    let Imm::Ext(append_ext) = app.imm else {
        return;
    };
    let sb = app.args[0];
    let sb_ty = m.funcs[fi].ty(sb);
    let int_ext = m.add_extern(ExternDef {
        name: APPEND_INT.to_string(),
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
    f.blocks[bi].insts.splice(ii..=ii, calls);
    // Deleting shifts later positions in the append's own block; the splice grew it by
    // `pieces - 1`, and removals there are all positions other than the replaced one.
    let grown = plan.pieces.len() - 1;
    for (b, blk) in f.blocks.iter_mut().enumerate() {
        let mut k = 0usize;
        blk.insts.retain(|_| {
            let orig = if b == bi && k > ii + grown {
                k - grown
            } else {
                k
            };
            let drop_it = (b != bi || k < ii || k > ii + grown) && plan.remove.contains(&(b, orig));
            k += 1;
            !drop_it
        });
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

/// Gathers the leaves of the concat chain rooted at `v` into `leaves` and the chain's inner
/// links into `remove`. A leaf that is a single-use `int_to_string` becomes the integer itself.
fn chain(
    m: &Module,
    f: &Func,
    info: &Info,
    v: Value,
    at: (usize, usize),
    leaves: &mut Vec<Piece>,
    remove: &mut HashSet<(usize, usize)>,
) {
    // A chain with more leaves than one call joins is rejected whatever its shape, so stop
    // descending once it has more inner links than that (each link adds itself and its drop to
    // `remove`) and keep `v` as a leaf: otherwise every link of a long chain walks the whole
    // chain below it, and the pass, which restarts after each fusion, is cubic in the chain's
    // length. The value must stay a leaf, not vanish: the join is built from `leaves`.
    if remove.len() > 2 * MAX_JOIN {
        leaves.push(v);
        return;
    }
    let inner = info.defs[v.index()].and_then(|(db, di)| {
        let single = info.uses[v.index()] == 2 && info.drops[v.index()].len() == 1;
        let (dbi, ddi) = info.drops[v.index()].first().copied()?;
        let name = ext_name(m, &f.blocks[db].insts[di])?;
        let ok = matches!(name, CONCAT | INT_TO_STRING)
            && single
            && straight_line(f, info, db, at.0)
            && (dbi != at.0 || ddi > at.1 || db != at.0 || di < at.1);
        ok.then_some((db, di, name == CONCAT))
    });
    let Some((db, di, concat)) = inner else {
        leaves.push(Piece::Str(v));
        return;
    };
    remove.insert((db, di));
    remove.insert(info.drops[v.index()][0]);
    let args = f.blocks[db].insts[di].args.clone();
    if !concat {
        leaves.push(Piece::Int(args[0]));
        return;
    }
    chain(m, f, info, args[0], at, leaves, remove);
    chain(m, f, info, args[1], at, leaves, remove);
}

fn fuse_concat(m: &mut Module, fi: usize) -> bool {
    let f = &m.funcs[fi];
    let info = info(f);
    for (bi, b) in f.blocks.iter().enumerate() {
        for (ii, inst) in b.insts.iter().enumerate().rev() {
            if ext_name(m, inst) != Some(CONCAT) {
                continue;
            }
            let mut leaves = Vec::new();
            let mut remove = HashSet::new();
            for &a in &inst.args {
                chain(m, f, &info, a, (bi, ii), &mut leaves, &mut remove);
            }
            let ints = leaves.iter().any(|p| matches!(p, Piece::Int(_)));
            // Two strings are what `concat` already does; two parts with an integer save the
            // temporary string.
            if remove.is_empty() || (leaves.len() < 3 && !ints) || leaves.len() > MAX_JOIN {
                continue;
            }
            // A leaf dropped before the join would be used after its drop.
            let early = leaves.iter().any(|l| match l {
                Piece::Str(l) => info.drops[l.index()]
                    .iter()
                    .any(|&(db, di)| db != bi || di < ii),
                Piece::Int(_) => false,
            });
            if early {
                continue;
            }
            apply_concat(m, fi, (bi, ii), leaves, &remove);
            return true;
        }
    }
    false
}

fn apply_concat(
    m: &mut Module,
    fi: usize,
    (bi, ii): (usize, usize),
    leaves: Vec<Piece>,
    remove: &HashSet<(usize, usize)>,
) {
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
    let mask_val = ints.then(|| f.new_value(Ty::INT));
    if let Some(mv) = mask_val {
        args.insert(0, mv);
    }
    let root = &mut f.blocks[bi].insts[ii];
    root.args = args;
    root.imm = Imm::Ext(ext);
    // The root moves up by the removals before it in its block; the mask constant goes right
    // before it afterwards.
    let shift = (0..ii).filter(|&k| remove.contains(&(bi, k))).count();
    for (b, blk) in f.blocks.iter_mut().enumerate() {
        let mut k = 0usize;
        blk.insts.retain(|_| {
            let keep = !remove.contains(&(b, k));
            k += 1;
            keep
        });
    }
    if let Some(mv) = mask_val {
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
            owned[p.value.index()] = p.mode == Mode::Own;
        }
    }
    for b in &f.blocks {
        for i in &b.insts {
            if let Some(r) = i.res {
                owned[r.index()] = m.result_mode(f, i) == Some(Mode::Own);
            }
        }
    }
    let mut sites = Vec::new();
    for (bi, b) in f.blocks.iter().enumerate() {
        for (ii, inst) in b.insts.iter().enumerate() {
            let a = inst.args.first().copied();
            let Some(a) = a.filter(|a| ext_name(m, inst) == Some(CONCAT) && owned[a.index()])
            else {
                continue;
            };
            if inst.args[1] == a {
                continue;
            }
            let next = b.insts[ii + 1..]
                .iter()
                .position(|n| n.args.contains(&a))
                .map(|k| ii + 1 + k);
            if let Some(j) = next.filter(|&j| b.insts[j].op == Op::Drop) {
                sites.push(((bi, ii), (bi, j)));
            }
        }
    }
    if sites.is_empty() {
        return false;
    }
    let ext = m.add_extern(ExternDef {
        name: APPEND_STR.to_string(),
        params: vec![
            Param {
                ty: Ty::STR,
                mode: Mode::Own,
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
