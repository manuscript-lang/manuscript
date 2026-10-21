//! The `strfuse` pass: appends a built-up string to a `StringBuilder` piece by piece.
//!
//! `b.append("{n},")` lowers to `int_to_string`, `string_concat`, `strbuilder.append` and two
//! drops: two heap strings that live for one call. When the temporaries have no other use, the
//! pieces are appended directly (`strbuilder.append_int` for integers), so the loop allocates
//! nothing. Only runtime string constructors with no effects and no faults are removed, and the
//! sealed-builder check (which stays where it was) still runs before any byte is written.

use crate::ir::{Block, ExternDef, Func, Imm, Inst, Mode, Module, Op, Param, Value};
use crate::types::Ty;
use std::collections::HashSet;

const APPEND: &str = "msrt_strbuilder_append";
const APPEND_INT: &str = "msrt_strbuilder_append_int";
const CONCAT: &str = "msrt_string_concat";
const INT_TO_STRING: &str = "msrt_int_to_string";

/// Runs the pass; returns whether anything changed.
pub fn run(m: &mut Module) -> bool {
    let mut changed = false;
    for fi in 0..m.funcs.len() {
        while fuse_one(m, fi) {
            changed = true;
        }
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
