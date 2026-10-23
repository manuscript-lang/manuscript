//! The `copyelim` pass: removes deep copies that only feed read-only uses.
//!
//! Lowering copies a value when it binds a pattern payload or a field out of a borrowed
//! parameter, then drops the copy at scope end. When every use of the copy is a borrowing
//! operand, the copy is the same value as its source for the whole function, provided the
//! source cannot change or die before the copy would: a borrowed parameter is neither
//! mutated nor released by its callee, and neither is anything projected out of one.

use crate::ir::{Func, Inst, Mode, Module, Op, Value};
use crate::types::TyKind;
use crate::verify::arg_modes;

/// Runs the pass; returns whether anything changed.
pub fn run(m: &mut Module) -> bool {
    let mut changed = false;
    for fi in 0..m.funcs.len() {
        changed |= run_func(m, fi);
        changed |= move_dead_sources(&mut m.funcs[fi]);
        changed |= borrow_local_copies(m, fi);
        changed |= borrow_str_copies_across_blocks(m, fi);
        changed |= borrow_str_phis(m, fi);
        changed |= unbox_dead_sources(m, fi);
        changed |= unbox_dead_options(&mut m.funcs[fi]);
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

/// Removes `c = copy v; ...; drop c` when the span only borrows the copy and its
/// source stays alive. Composite values additionally require a span without writes
/// that could change or release a projection's owner. String length may cache its
/// result, but cannot release or replace data. This includes read-only iteration
/// over a list of records, which otherwise copies every record on every visit.
fn borrow_local_copies(m: &mut Module, fi: usize) -> bool {
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
    let mut defs: Vec<Option<(usize, usize)>> = vec![None; f.values.len()];
    for (bi, b) in f.blocks.iter().enumerate() {
        for (ii, inst) in b.insts.iter().enumerate() {
            if let Some(r) = inst.res {
                defs[r.index()] = Some((bi, ii));
            }
        }
    }
    let mut alias: Vec<Option<Value>> = vec![None; f.values.len()];
    let mut dead: Vec<(usize, usize)> = Vec::new();
    for (bi, b) in f.blocks.iter().enumerate() {
        for (i, inst) in b.insts.iter().enumerate() {
            let (Op::Copy, Some(c)) = (inst.op, inst.res) else {
                continue;
            };
            let v = inst.args[0];
            let kind = m.types.kind(f.ty(v));
            let is_str = matches!(kind, TyKind::Str);
            let composite = matches!(
                kind,
                TyKind::Rec(_) | TyKind::Alt(_) | TyKind::Opt(_) | TyKind::List(_) | TyKind::Bytes
            );
            if !(matches!(kind, TyKind::Fn(..)) || is_str || composite)
                || alias[v.index()].is_some()
            {
                continue;
            }
            let Some(j) = b.insts[i + 1..]
                .iter()
                .position(|n| n.op == Op::Drop && n.args[0] == c)
                .map(|k| i + 1 + k)
            else {
                continue;
            };
            let span = &b.insts[i + 1..j];
            if is_str && !str_source_stable(m, f, &defs, v, span) {
                continue;
            }
            if composite
                && span.iter().any(|n| {
                    let e = n.op.info().effects;
                    (e.writes && n.op != Op::StrLen) || (e.rc && n.op != Op::Copy)
                })
            {
                continue;
            }
            let c_uses = span
                .iter()
                .map(|n| n.args.iter().filter(|a| **a == c).count() as u32)
                .sum::<u32>();
            if c_uses + 1 != uses[c.index()] {
                continue;
            }
            let consumed = span.iter().any(|n| {
                n.args
                    .iter()
                    .zip(arg_modes(m, n))
                    .any(|(a, mode)| (*a == v || *a == c) && mode != Mode::Borrow)
            });
            if consumed {
                continue;
            }
            alias[c.index()] = Some(v);
            dead.push((bi, i));
            dead.push((bi, j));
        }
    }
    if dead.is_empty() {
        return false;
    }
    let f = &mut m.funcs[fi];
    for (bi, b) in f.blocks.iter_mut().enumerate() {
        let mut k = 0;
        b.insts.retain(|_| {
            let drop_it = dead.contains(&(bi, k));
            k += 1;
            !drop_it
        });
        for i in &mut b.insts {
            for a in &mut i.args {
                if let Some(s) = alias[a.index()] {
                    *a = s;
                }
            }
        }
    }
    true
}

/// Removes `c = copy v; ...; drop c` for a string `v` read out of a list when the copy lives
/// across several blocks (a loop body with an `if`), which the single-block pass cannot see.
/// Every instruction that can run between the copy and the drop must only borrow `c`, `v`
/// and the list; the paths from the copy reach the list's release only through the drop.
fn borrow_str_copies_across_blocks(m: &mut Module, fi: usize) -> bool {
    let f = &m.funcs[fi];
    let nb = f.blocks.len();
    let mut defs: Vec<Option<(usize, usize)>> = vec![None; f.values.len()];
    let mut uses = vec![0u32; f.values.len()];
    for (bi, b) in f.blocks.iter().enumerate() {
        for (ii, inst) in b.insts.iter().enumerate() {
            if let Some(r) = inst.res {
                defs[r.index()] = Some((bi, ii));
            }
            for a in &inst.args {
                uses[a.index()] += 1;
            }
        }
        b.term.for_each_use(|v| uses[v.index()] += 1);
    }
    let mut dead: Vec<(usize, usize)> = Vec::new();
    let mut alias: Vec<Option<Value>> = vec![None; f.values.len()];
    for (bc, b) in f.blocks.iter().enumerate() {
        for (i, inst) in b.insts.iter().enumerate() {
            let (Op::Copy, Some(c)) = (inst.op, inst.res) else {
                continue;
            };
            let v = inst.args[0];
            if !matches!(m.types.kind(f.ty(v)), TyKind::Str) || alias[v.index()].is_some() {
                continue;
            }
            // The one drop of `c`, in a later block (the same-block case is handled elsewhere).
            let mut drops = f.blocks.iter().enumerate().flat_map(|(bd, blk)| {
                blk.insts
                    .iter()
                    .enumerate()
                    .filter(move |(_, n)| n.op == Op::Drop && n.args[0] == c)
                    .map(move |(jd, _)| (bd, jd))
            });
            let (Some((bd, jd)), None) = (drops.next(), drops.next()) else {
                continue;
            };
            if bd == bc {
                continue;
            }
            // The list `v` is read from, or none for a parameter or literal.
            let root = match defs[v.index()] {
                None => None,
                Some((db, di)) => {
                    let def = &f.blocks[db].insts[di];
                    match def.op {
                        Op::StrLit => None,
                        Op::ListGet | Op::ListGetU | Op::ListGetNn => Some(def.args[0]),
                        _ => continue,
                    }
                }
            };
            // Blocks reachable from the copy without passing through the drop's block.
            let mut seen = vec![false; nb];
            let mut stack: Vec<usize> = Vec::new();
            let mut reaches_copy_again = false;
            f.blocks[bc]
                .term
                .for_each_target(|t| stack.push(t.block.index()));
            while let Some(x) = stack.pop() {
                if x == bc {
                    reaches_copy_again = true;
                    continue;
                }
                if x == bd || seen[x] {
                    continue;
                }
                seen[x] = true;
                f.blocks[x]
                    .term
                    .for_each_target(|t| stack.push(t.block.index()));
            }
            if reaches_copy_again {
                continue;
            }
            // Instructions that may run while the copy is alive.
            let mut ok = true;
            let mut c_borrows = 0u32;
            let mut visit = |insts: &[Inst], term: Option<&crate::ir::Term>| {
                for n in insts {
                    for (a, mode) in n.args.iter().zip(arg_modes(m, n)) {
                        if *a == c {
                            if mode != Mode::Borrow {
                                ok = false;
                            }
                            c_borrows += 1;
                        } else if (*a == v || Some(*a) == root) && mode != Mode::Borrow {
                            ok = false;
                        }
                    }
                }
                if let Some(t) = term {
                    t.for_each_use(|a| {
                        if a == c || a == v || Some(a) == root {
                            ok = false;
                        }
                    });
                }
            };
            visit(&b.insts[i + 1..], Some(&b.term));
            for (x, blk) in f.blocks.iter().enumerate() {
                if seen[x] {
                    visit(&blk.insts, Some(&blk.term));
                }
            }
            visit(&f.blocks[bd].insts[..jd], None);
            if !ok || c_borrows + 1 != uses[c.index()] {
                continue;
            }
            alias[c.index()] = Some(v);
            dead.push((bc, i));
            dead.push((bd, jd));
        }
    }
    if dead.is_empty() {
        return false;
    }
    let f = &mut m.funcs[fi];
    for (bi, b) in f.blocks.iter_mut().enumerate() {
        let mut k = 0;
        b.insts.retain(|_| {
            let drop_it = dead.contains(&(bi, k));
            k += 1;
            !drop_it
        });
        for i in &mut b.insts {
            for a in &mut i.args {
                if let Some(s) = alias[a.index()] {
                    *a = s;
                }
            }
        }
    }
    true
}

/// Removes string copies that only meet at a block parameter which is borrowed and dropped:
/// `b1: c1 = copy s1; br b3(c1)`, `b2: c2 = copy s2; br b3(c2)`, `b3(p): ... borrow p ...; drop p`.
/// This is the shape of an inlined `xs.get(i, default: "")` compared and discarded. When every
/// source stays alive and unchanged until the drop, `p` borrows the sources instead.
fn borrow_str_phis(m: &mut Module, fi: usize) -> bool {
    let f = &m.funcs[fi];
    let nv = f.values.len();
    let mut defs: Vec<Option<(usize, usize)>> = vec![None; nv];
    let mut uses = vec![0u32; nv];
    for (bi, b) in f.blocks.iter().enumerate() {
        for (ii, inst) in b.insts.iter().enumerate() {
            if let Some(r) = inst.res {
                defs[r.index()] = Some((bi, ii));
            }
            for a in &inst.args {
                uses[a.index()] += 1;
            }
        }
        b.term.for_each_use(|v| uses[v.index()] += 1);
    }
    // Per change: the block, the parameter index, the edges' (pred, copy index, source), the drop.
    type Edge = (usize, usize, Value);
    type Plan = (usize, usize, Vec<Edge>, (usize, usize));
    let mut plans: Vec<Plan> = Vec::new();
    let mut taken = vec![false; nv];
    for (bb, b) in f.blocks.iter().enumerate() {
        'param: for (pi, param) in b.params.iter().enumerate() {
            let p = param.value;
            if param.mode != Mode::Own || !matches!(m.types.kind(f.ty(p)), TyKind::Str) {
                continue;
            }
            // Incoming copies, one per edge.
            let mut edges: Vec<Edge> = Vec::new();
            for (x, blk) in f.blocks.iter().enumerate() {
                let mut bad = false;
                blk.term.for_each_target(|t| {
                    if t.block.index() != bb {
                        return;
                    }
                    let a = t.args[pi];
                    match defs[a.index()] {
                        Some((db, di))
                            if db == x
                                && blk.insts[di].op == Op::Copy
                                && uses[a.index()] == 1
                                && !taken[a.index()] =>
                        {
                            edges.push((x, di, blk.insts[di].args[0]));
                        }
                        _ => bad = true,
                    }
                });
                if bad {
                    continue 'param;
                }
            }
            if edges.is_empty() {
                continue;
            }
            // Values the sources depend on: each source and the chain of lists and records it
            // was read out of.
            let mut chain: Vec<Value> = Vec::new();
            for &(_, _, src) in &edges {
                chain.push(src);
                let Some((db, di)) = defs[src.index()] else {
                    continue;
                };
                let def = &f.blocks[db].insts[di];
                match def.op {
                    Op::StrLit => continue,
                    Op::ListGet | Op::ListGetU | Op::ListGetNn => {}
                    _ => continue 'param,
                }
                let mut at = def.args[0];
                loop {
                    chain.push(at);
                    match defs[at.index()] {
                        Some((rb, ri)) if f.blocks[rb].insts[ri].op == Op::RecGet => {
                            at = f.blocks[rb].insts[ri].args[0];
                        }
                        _ => break,
                    }
                }
            }
            // The one drop of `p`; every other use borrows it.
            let mut drop_at = None;
            let mut borrows = 0u32;
            for (x, blk) in f.blocks.iter().enumerate() {
                for (j, n) in blk.insts.iter().enumerate() {
                    if n.op == Op::Drop && n.args[0] == p {
                        if drop_at.replace((x, j)).is_some() {
                            continue 'param;
                        }
                        continue;
                    }
                    for (a, mode) in n.args.iter().zip(arg_modes(m, n)) {
                        if *a == p {
                            if mode != Mode::Borrow {
                                continue 'param;
                            }
                            borrows += 1;
                        }
                    }
                }
            }
            let Some((bd, jd)) = drop_at else {
                continue;
            };
            if borrows + 1 != uses[p.index()] {
                continue;
            }
            // Blocks that run between `b` and the drop; a path back to `b` is a loop: give up.
            let nb = f.blocks.len();
            let mut seen = vec![false; nb];
            let mut stack: Vec<usize> = Vec::new();
            if bd != bb {
                b.term.for_each_target(|t| stack.push(t.block.index()));
            }
            while let Some(x) = stack.pop() {
                if x == bb {
                    continue 'param;
                }
                if x == bd || seen[x] {
                    continue;
                }
                seen[x] = true;
                f.blocks[x]
                    .term
                    .for_each_target(|t| stack.push(t.block.index()));
            }
            let mut ok = true;
            let mut check = |insts: &[Inst], term: Option<&crate::ir::Term>| {
                for n in insts {
                    for (a, mode) in n.args.iter().zip(arg_modes(m, n)) {
                        if chain.contains(a) && mode != Mode::Borrow {
                            ok = false;
                        }
                    }
                }
                if let Some(t) = term {
                    t.for_each_target(|t| {
                        if t.args.iter().any(|a| chain.contains(a)) {
                            ok = false;
                        }
                    });
                    if let crate::ir::Term::Ret(Some(v)) = t
                        && chain.contains(v)
                    {
                        ok = false;
                    }
                }
            };
            for &(x, di, _) in &edges {
                check(&f.blocks[x].insts[di + 1..], Some(&f.blocks[x].term));
            }
            if bd == bb {
                check(&b.insts[..jd], None);
            } else {
                check(&b.insts, Some(&b.term));
                for (x, blk) in f.blocks.iter().enumerate() {
                    if seen[x] {
                        check(&blk.insts, Some(&blk.term));
                    }
                }
                check(&f.blocks[bd].insts[..jd], None);
            }
            if !ok {
                continue;
            }
            for &(x, di, _) in &edges {
                if let Some(c) = f.blocks[x].insts[di].res {
                    taken[c.index()] = true;
                }
            }
            plans.push((bb, pi, edges, (bd, jd)));
        }
    }
    if plans.is_empty() {
        return false;
    }
    let f = &mut m.funcs[fi];
    let mut dead: Vec<(usize, usize)> = Vec::new();
    for (bb, pi, edges, drop_at) in plans {
        f.blocks[bb].params[pi].mode = Mode::Borrow;
        dead.push(drop_at);
        for (x, di, src) in edges {
            dead.push((x, di));
            f.blocks[x].term.for_each_target_mut(|t| {
                if t.block.index() == bb {
                    t.args[pi] = src;
                }
            });
        }
    }
    for (bi, b) in f.blocks.iter_mut().enumerate() {
        let mut k = 0;
        b.insts.retain(|_| {
            let drop_it = dead.contains(&(bi, k));
            k += 1;
            !drop_it
        });
    }
    true
}

/// Whether a string `v` stays alive and unchanged across `span`: a parameter or literal, or an
/// element read out of a list that the span only borrows. Strings are immutable, so the only
/// way the copy could differ from `v` is `v`'s owner releasing or replacing it.
fn str_source_stable(
    m: &Module,
    f: &Func,
    defs: &[Option<(usize, usize)>],
    v: Value,
    span: &[Inst],
) -> bool {
    let Some((db, di)) = defs[v.index()] else {
        return true;
    };
    let def = &f.blocks[db].insts[di];
    match def.op {
        Op::StrLit => true,
        Op::ListGet | Op::ListGetU | Op::ListGetNn => {
            let root = def.args[0];
            span.iter().all(|n| {
                n.args
                    .iter()
                    .zip(arg_modes(m, n))
                    .all(|(a, mode)| *a != root || mode == Mode::Borrow)
            })
        }
        _ => false,
    }
}

/// Turns `p = opt.get v; c = copy p; ...; drop v` into `c = opt.unbox v` when `v` is not
/// touched in between and `p` has no other use: the payload moves out and the shell is freed
/// instead of the payload being deep-copied and then dropped with its source. This is the
/// shape of unwrapping a recursive result, which would otherwise copy every subtree once per
/// level.
fn unbox_dead_options(f: &mut Func) -> bool {
    let mut uses = vec![0u32; f.values.len()];
    for b in &f.blocks {
        for i in &b.insts {
            for a in &i.args {
                uses[a.index()] += 1;
            }
        }
        b.term.for_each_use(|v| uses[v.index()] += 1);
    }
    let mut changed = false;
    for b in &mut f.blocks {
        'again: loop {
            let term_uses_of = |v: Value| {
                let mut hit = false;
                b.term.for_each_use(|u| hit |= u == v);
                hit
            };
            for (gi, get) in b.insts.iter().enumerate() {
                let (Op::OptGet, Some(p)) = (get.op, get.res) else {
                    continue;
                };
                let v = get.args[0];
                if uses[p.index()] != 1 {
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
                let term_uses = term_uses_of(v);
                if b.insts[gi + 1..di]
                    .iter()
                    .enumerate()
                    .any(|(k, n)| gi + 1 + k != ci && n.args.contains(&v))
                    || b.insts[di + 1..].iter().any(|n| n.args.contains(&v))
                    || term_uses
                {
                    continue;
                }
                b.insts[ci].op = Op::OptUnbox;
                b.insts[ci].args = vec![v];
                b.insts.remove(di);
                b.insts.remove(gi);
                changed = true;
                continue 'again;
            }
            break;
        }
    }
    changed
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
