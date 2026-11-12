//! The `bytetake` pass: a derived result of a value that dies at the call reuses its storage.
//!
//! `r = f(b, .., out); ...; drop b` copies `b` into a new allocation and then frees it. When `b`
//! is owned and nothing reads it between the call and its drop, and `f` declares a `<f>_take`
//! twin (`// ms: takes_self`: `decode_utf8`, `trim`, `upper`, `lower`, `replace`), the call
//! becomes the twin, which moves `b` in and builds the result in the same allocation, so the
//! drop disappears. A take of a dying value is a move, so nothing observable changes.

use crate::ir::{ExternRole, Imm, Mode, Module, Op};
use std::collections::HashSet;

/// Runs the pass; returns whether any call became a take.
pub fn run(m: &mut Module) -> bool {
    let mut changed = false;
    for fi in 0..m.funcs.len() {
        let f = &m.funcs[fi];
        let mut owned = vec![false; f.values.len()];
        for b in &f.blocks {
            for p in &b.params {
                owned[p.value.index()] = p.mode == Mode::Move;
            }
        }
        for i in f.blocks.iter().flat_map(|b| b.insts.iter()) {
            if let Some(r) = i.res {
                owned[r.index()] = m.result_mode(f, i) == Some(Mode::Move);
            }
        }
        // `next[v]` is the first use of `v` after the instruction being visited (backward scan).
        let mut next: Vec<(usize, usize)> = vec![(usize::MAX, 0); f.values.len()];
        let mut sites = Vec::new();
        for (bi, b) in f.blocks.iter().enumerate() {
            for (ii, inst) in b.insts.iter().enumerate().rev() {
                if let (Op::CallRt, Imm::Ext(e), Some(&a)) = (inst.op, inst.imm, inst.args.first())
                    && m.externs[e.index()].role == ExternRole::TakesDying
                    && owned[a.index()]
                    && inst.args[1..].iter().all(|&o| o != a)
                {
                    let (nb, j) = next[a.index()];
                    if nb == bi && b.insts[j].op == Op::Drop {
                        sites.push(((bi, ii), j, e));
                    }
                }
                for a in &inst.args {
                    next[a.index()] = (bi, ii);
                }
            }
        }
        if sites.is_empty() {
            continue;
        }
        let twins: Vec<_> = sites
            .iter()
            .map(|&(_, _, e)| {
                let mut def = m.externs[e.index()].clone();
                def.name = format!("{}_take", def.name);
                def.params[0].mode = Mode::Move;
                def.role = ExternRole::None;
                m.add_extern(def)
            })
            .collect();
        let f = &mut m.funcs[fi];
        let drops: HashSet<(usize, usize)> = sites.iter().map(|&((bi, _), j, _)| (bi, j)).collect();
        for (&((bi, ii), _, _), &ext) in sites.iter().zip(&twins) {
            f.blocks[bi].insts[ii].imm = Imm::Ext(ext);
        }
        for (bi, blk) in f.blocks.iter_mut().enumerate() {
            let mut k = 0usize;
            blk.insts.retain(|_| {
                let keep = !drops.contains(&(bi, k));
                k += 1;
                keep
            });
        }
        changed = true;
    }
    changed
}
