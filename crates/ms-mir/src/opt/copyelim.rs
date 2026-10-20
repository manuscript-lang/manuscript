//! The `copyelim` pass: removes deep copies that only feed read-only uses.
//!
//! Lowering copies a value when it binds a pattern payload or a field out of a borrowed
//! parameter, then drops the copy at scope end. When every use of the copy is a borrowing
//! operand, the copy is the same value as its source for the whole function, provided the
//! source cannot change or die before the copy would: a borrowed parameter is neither
//! mutated nor released by its callee, and neither is anything projected out of one.

use crate::ir::{Func, Inst, Mode, Module, Op, Value};
use crate::verify::arg_modes;

/// Runs the pass; returns whether anything changed.
pub fn run(m: &mut Module) -> bool {
    let mut changed = false;
    for fi in 0..m.funcs.len() {
        changed |= run_func(m, fi);
        changed |= move_dead_sources(&mut m.funcs[fi]);
        changed |= unbox_dead_sources(m, fi);
    }
    changed
}

/// Turns `c = copy v; ...; drop v` into a move when `v` is not touched in between: the copy
/// and the drop cancel, and `c` is `v`. This is the shape of `l = More(l)` in a loop, which
/// would otherwise deep-copy the old value on every iteration.
fn move_dead_sources(f: &mut Func) -> bool {
    let mut rename: Vec<Option<Value>> = vec![None; f.values.len()];
    let mut touched = vec![false; f.values.len()];
    let mut dead: Vec<(usize, usize)> = Vec::new();
    for (bi, b) in f.blocks.iter().enumerate() {
        for (i, inst) in b.insts.iter().enumerate() {
            let (Op::Copy, Some(c)) = (inst.op, inst.res) else {
                continue;
            };
            let v = inst.args[0];
            if touched[c.index()] || touched[v.index()] {
                continue;
            }
            let Some(j) = b.insts[i + 1..]
                .iter()
                .position(|n| n.op == Op::Drop && n.args[0] == v)
                .map(|k| i + 1 + k)
            else {
                continue;
            };
            if b.insts[i + 1..j].iter().any(|n| n.args.contains(&v)) {
                continue;
            }
            touched[c.index()] = true;
            touched[v.index()] = true;
            rename[c.index()] = Some(v);
            dead.push((bi, i));
            dead.push((bi, j));
        }
    }
    if dead.is_empty() {
        return false;
    }
    for (bi, b) in f.blocks.iter_mut().enumerate() {
        let mut k = 0;
        b.insts.retain(|_| {
            let drop_it = dead.contains(&(bi, k));
            k += 1;
            !drop_it
        });
    }
    for b in &mut f.blocks {
        for i in &mut b.insts {
            for a in &mut i.args {
                if let Some(s) = rename[a.index()] {
                    *a = s;
                }
            }
        }
        b.term.for_each_use_mut(|a| {
            if let Some(s) = rename[a.index()] {
                *a = s;
            }
        });
    }
    true
}

/// Turns `p = alt.get f v; c = copy p; ...; drop v` into `c = alt.unbox f v` when `v` is
/// otherwise only read through `alt.get`s of fields that need no drop (those are hoisted
/// above it). This is the shape of `match cur: Link(_, next): cur = next` in a loop, which
/// would otherwise deep-copy the whole tail on every iteration.
fn unbox_dead_sources(m: &mut Module, fi: usize) -> bool {
    let f = &m.funcs[fi];
    let mut uses = vec![0u32; f.values.len()];
    for b in &f.blocks {
        for i in &b.insts {
            for a in &i.args {
                uses[a.index()] += 1;
            }
        }
        b.term.for_each_use(|v| uses[v.index()] += 1);
    }
    let nd: Vec<bool> = f.values.iter().map(|v| m.needs_drop(*v)).collect();
    let f = &mut m.funcs[fi];
    let mut changed = false;
    for b in &mut f.blocks {
        'again: loop {
            for (gi, get) in b.insts.iter().enumerate() {
                let (Op::AltGet, Some(p)) = (get.op, get.res) else {
                    continue;
                };
                let v = get.args[0];
                if uses[p.index()] != 1 || !nd[p.index()] {
                    continue;
                }
                let Some(ci) = b.insts[gi + 1..]
                    .iter()
                    .position(|n| n.op == Op::Copy && n.args[0] == p)
                    .map(|k| gi + 1 + k)
                else {
                    continue;
                };
                let Some(di) = b.insts[ci + 1..]
                    .iter()
                    .position(|n| n.op == Op::Drop && n.args[0] == v)
                    .map(|k| ci + 1 + k)
                else {
                    continue;
                };
                let mut hoist = Vec::new();
                let mut ok = true;
                for (k, n) in b.insts.iter().enumerate().take(di).skip(gi + 1) {
                    if k == ci || !n.args.contains(&v) {
                        continue;
                    }
                    if n.op == Op::AltGet && n.res.is_some_and(|r| !nd[r.index()]) {
                        hoist.push(k);
                    } else {
                        ok = false;
                    }
                }
                if !ok || b.insts[di + 1..].iter().any(|n| n.args.contains(&v)) {
                    continue;
                }
                let mut insts = std::mem::take(&mut b.insts);
                let imm = insts[gi].imm;
                insts[ci].op = Op::AltUnbox;
                insts[ci].args = vec![v];
                insts[ci].imm = imm;
                // Hoisted loads go where the original `alt.get` was: the unbox frees the block.
                let mut out = Vec::with_capacity(insts.len());
                let mut loads: Vec<Option<Inst>> = vec![None; insts.len()];
                for &k in &hoist {
                    loads[k] = Some(insts[k].clone());
                }
                for (k, n) in insts.into_iter().enumerate() {
                    if k == gi {
                        out.extend(hoist.iter().filter_map(|&h| loads[h].take()));
                    } else if k != di && !hoist.contains(&k) {
                        out.push(n);
                    }
                }
                b.insts = out;
                changed = true;
                continue 'again;
            }
            break;
        }
    }
    changed
}

fn run_func(m: &mut Module, fi: usize) -> bool {
    let f = &m.funcs[fi];
    let stable = stable_values(f);
    // `copy` results that can be replaced by their source.
    let mut alias: Vec<Option<Value>> = vec![None; f.values.len()];
    let mut any = false;
    for b in &f.blocks {
        for i in &b.insts {
            if let (Op::Copy, Some(res)) = (i.op, i.res)
                && stable[i.args[0].index()]
            {
                alias[res.index()] = Some(i.args[0]);
                any = true;
            }
        }
    }
    if !any {
        return false;
    }
    // A copy stays unless every use is a read-only operand or one of its drops.
    for b in &f.blocks {
        for i in &b.insts {
            let modes = arg_modes(m, i);
            for (a, mode) in i.args.iter().zip(&modes) {
                if alias[a.index()].is_some() && *mode != Mode::Borrow && i.op != Op::Drop {
                    alias[a.index()] = None;
                }
            }
            if i.op == Op::DropIf
                && let Some(a) = i.args.get(1)
            {
                alias[a.index()] = None;
            }
        }
        let mut uses = Vec::new();
        b.term.for_each_use(|v| uses.push(v));
        for v in uses {
            alias[v.index()] = None;
        }
    }
    let f = &mut m.funcs[fi];
    let mut changed = false;
    for b in &mut f.blocks {
        b.insts.retain(|i| {
            let dead = match i.op {
                Op::Copy => i.res.is_some_and(|r| alias[r.index()].is_some()),
                Op::Drop => alias[i.args[0].index()].is_some(),
                _ => false,
            };
            changed |= dead;
            !dead
        });
        for i in &mut b.insts {
            for a in &mut i.args {
                if let Some(s) = alias[a.index()] {
                    *a = s;
                }
            }
        }
    }
    changed
}

/// Values that stay valid and unchanged for the whole function: borrowed parameters and
/// borrowed projections of them.
fn stable_values(f: &Func) -> Vec<bool> {
    let mut stable = vec![false; f.values.len()];
    for p in &f.blocks[0].params {
        stable[p.value.index()] = p.mode == Mode::Borrow;
    }
    // Definitions precede uses in reverse post-order, so one sweep suffices.
    for b in f.rpo() {
        for i in &f.blocks[b.index()].insts {
            let projection = matches!(
                i.op,
                Op::RecGet | Op::AltGet | Op::OptGet | Op::ListGet | Op::ListGetNn | Op::ListGetU
            );
            if let (true, Some(res)) = (projection, i.res)
                && stable[i.args[0].index()]
            {
                stable[res.index()] = true;
            }
        }
    }
    stable
}
