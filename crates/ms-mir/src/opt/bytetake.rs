//! The `bytetake` pass: `decode_utf8` of a `Bytes` that dies at the call reuses its buffer.
//!
//! `r = bytes_decode_utf8(b, out); ...; drop b` copies the whole buffer into a new string and then
//! frees it. When `b` is owned and nothing reads it between the call and its drop, the call
//! becomes `bytes_decode_utf8_take`, which moves `b` in and turns the same allocation into the
//! string, so the drop disappears. A take of a dying value is a move, so nothing observable
//! changes.

use crate::ir::{ExternRole, Imm, Mode, Module, Op};
use std::collections::HashSet;

/// Runs the pass; returns whether any call became a take.
pub fn run(m: &mut Module) -> bool {
    let mut changed = false;
    let mut take = None;
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
                    && m.externs[e.index()].role == ExternRole::BytesDecodeUtf8
                    && owned[a.index()]
                    && inst.args[1] != a
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
        let ext = *take.get_or_insert_with(|| {
            let (_, _, e) = sites[0];
            let mut def = m.externs[e.index()].clone();
            def.name = "msrt_bytes_decode_utf8_take".to_string();
            def.params[0].mode = Mode::Move;
            def.role = ExternRole::None;
            m.add_extern(def)
        });
        let f = &mut m.funcs[fi];
        let drops: HashSet<(usize, usize)> = sites.iter().map(|&((bi, _), j, _)| (bi, j)).collect();
        for &((bi, ii), _, _) in &sites {
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
