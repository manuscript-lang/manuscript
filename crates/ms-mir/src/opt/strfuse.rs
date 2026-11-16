//! The `strfuse` pass: grows a string in place for `s = s + piece`.
//!
//! `s = s.concat(piece)` lowers to a concat and a drop of the old `s`. When the drop follows
//! with no use of `s` in between, `string_append` moving_params `s` and grows it in place, so a loop
//! that builds a string stays linear even in an unoptimized build. Joining the pieces of a text
//! and appending them to a builder are decided at lowering, not recovered here.

use crate::ir::{ExternDef, ExternRole, Imm, Inst, Mode, Module, Op, Param};
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
