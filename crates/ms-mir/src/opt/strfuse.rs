//! The `strfuse` pass: grows a string in place for `s = s + piece`.
//!
//! `s = s.concat(piece)` lowers to a concat and a drop of the old `s`. When the drop follows
//! with no use of `s` in between, `string_append` moving_params `s` and grows it in place, so a loop
//! that builds a string stays linear even in an unoptimized build. A join whose first part is
//! such an `s` (`s += f"{k}={n};"`) becomes `string_append_fmtN`, which writes the other parts
//! straight onto `s`. Joining the pieces of a text and appending them to a builder are decided
//! at lowering, not recovered here.

use crate::ir::{ExternDef, ExternRole, Func, Imm, Inst, Mode, Module, Op, Param, Value};
use crate::types::Ty;
use std::collections::HashSet;

/// Runs the pass; returns whether anything changed.
pub fn run(m: &mut Module) -> bool {
    let mut changed = false;
    for fi in 0..m.funcs.len() {
        changed |= append_in_place(m, fi);
    }
    changed
}

fn ext_role(m: &Module, i: &Inst) -> Option<ExternRole> {
    match (i.op, i.imm) {
        (Op::CallRt, Imm::Ext(e)) => Some(m.externs[e.index()].role),
        _ => None,
    }
}

/// The growing twin of the call `inst` and where its string to grow sits among the arguments:
/// `string_append` for a concat, `string_append_fmtN` for a join of `N + 1` parts.
fn twin(m: &Module, f: &Func, inst: &Inst) -> Option<(usize, String)> {
    match ext_role(m, inst)? {
        ExternRole::StringConcat => Some((0, "msrt_string_append".to_string())),
        ExternRole::StringJoin => {
            let masked = f.ty(inst.args[0]) == Ty::INT;
            let at = masked as usize;
            Some((
                at,
                format!("msrt_string_append_fmt{}", inst.args.len() - at - 1),
            ))
        }
        _ => None,
    }
}

/// Rewrites `r = string_concat(a, b); ...; drop a` to `r = string_append(a, b)` when `a` is an
/// owned value that nothing reads between the concat and its drop, and a join whose first part is
/// such an `a` to `string_append_fmtN(a, mask, parts...)` (the join's own mask; a zero for a join
/// of strings).
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
    // Each site: the call, the drop of its grown string, where that string sits, the twin's name.
    let mut sites = Vec::new();
    // `next[v]` is `(block, index)` of the first use of `v` after the instruction being visited.
    // One backward scan per block finds every site's next use, where searching forward from each
    // site is quadratic when the drops all sit at the end of a long block.
    let mut next: Vec<(usize, usize)> = vec![(usize::MAX, 0); f.values.len()];
    for (bi, b) in f.blocks.iter().enumerate() {
        for (ii, inst) in b.insts.iter().enumerate().rev() {
            let site = twin(m, f, inst).filter(|(at, _)| {
                let a = inst.args[*at];
                f.ty(a) == Ty::STR
                    && owned[a.index()]
                    && inst.args.iter().filter(|x| **x == a).count() == 1
            });
            if let Some((at, name)) = site {
                let (nb, j) = next[inst.args[at].index()];
                if nb == bi && b.insts[j].op == Op::Drop {
                    sites.push(((bi, ii), (bi, j), at, name));
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
    let remove: HashSet<(usize, usize)> = sites.iter().map(|s| s.1).collect();
    // A join of strings has no mask: its twin takes a zero, placed right before the call.
    let mut zeros: Vec<(usize, usize, Value)> = Vec::new();
    for ((bi, ii), _, at, name) in sites {
        let f = &mut m.funcs[fi];
        let mut args = f.blocks[bi].insts[ii].args.clone();
        let appends = args.len() == 2;
        if at == 0 && !appends {
            let zero = f.new_value(Ty::INT);
            args.insert(1, zero);
            zeros.push((bi, ii, zero));
        } else if at == 1 {
            args.swap(0, 1);
        }
        let params = args.iter().enumerate().map(|(k, a)| Param {
            ty: m.funcs[fi].ty(*a),
            mode: if k == 0 { Mode::Move } else { Mode::Borrow },
        });
        let ext = m.add_extern(ExternDef {
            name,
            params: params.collect(),
            ret: Ty::STR,
            noreturn: false,
            pure_: false,
            fresh: true,
            retains: false,
            role: if appends {
                ExternRole::StringAppend
            } else {
                ExternRole::None
            },
            leaf: true,
            reads: false,
        });
        let inst = &mut m.funcs[fi].blocks[bi].insts[ii];
        inst.args = args;
        inst.imm = Imm::Ext(ext);
    }
    let f = &mut m.funcs[fi];
    for (b, blk) in f.blocks.iter_mut().enumerate() {
        let old = std::mem::take(&mut blk.insts);
        blk.insts.reserve(old.len());
        for (k, inst) in old.into_iter().enumerate() {
            if let Some(&(.., zero)) = zeros.iter().find(|z| (z.0, z.1) == (b, k)) {
                blk.insts.push(Inst {
                    op: Op::IConst,
                    args: Vec::new(),
                    imm: Imm::Int(0),
                    res: Some(zero),
                    loc: inst.loc,
                });
            }
            if !remove.contains(&(b, k)) {
                blk.insts.push(inst);
            }
        }
    }
    true
}
