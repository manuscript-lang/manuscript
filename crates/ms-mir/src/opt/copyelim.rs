//! The `copyelim` pass: removes deep copies that only feed read-only uses.
//!
//! Lowering copies a value when it binds a pattern payload or a field out of a borrowed
//! parameter, then drops the copy at scope end. When every use of the copy is a borrowing
//! operand, the copy is the same value as its source for the whole function, provided the
//! source cannot change or die before the copy would: a borrowed parameter is neither
//! mutated nor released by its callee, and neither is anything projected out of one.

use crate::ir::{Func, Imm, Inst, Mode, Module, Op, Value};
use crate::types::TyKind;
use crate::verify::arg_modes;

/// Runs the pass; returns whether anything changed.
pub fn run(m: &mut Module) -> bool {
    let mut changed = false;
    for fi in 0..m.funcs.len() {
        changed |= run_func(m, fi);
        changed |= move_dead_sources(m, fi);
        changed |= move_dead_sources_across_blocks(m, fi);
        changed |= borrow_local_copies(m, fi);
        changed |= borrow_str_copies_across_blocks(m, fi);
        changed |= borrow_str_phis(m, fi);
        changed |= unbox_dead_sources(m, fi);
        changed |= unbox_dead_options(&mut m.funcs[fi]);
    }
    changed
}

/// Every instruction operand use of each value as `(block, instruction)` in program order (a
/// value used twice by one instruction appears twice). Terminator uses are not listed.
fn operand_uses(f: &Func) -> Vec<Vec<(usize, usize)>> {
    let mut at: Vec<Vec<(usize, usize)>> = vec![Vec::new(); f.values.len()];
    for (bi, b) in f.blocks.iter().enumerate() {
        for (ii, inst) in b.insts.iter().enumerate() {
            for a in &inst.args {
                at[a.index()].push((bi, ii));
            }
        }
    }
    at
}

/// The first use in `uses` after instruction `i` of block `bi`.
fn next_use(uses: &[(usize, usize)], bi: usize, i: usize) -> Option<&(usize, usize)> {
    uses.get(uses.partition_point(|u| *u <= (bi, i)))
}

/// Operand uses of each value within one block's instructions, sorted by value then position.
struct BlockUses(Vec<(usize, usize)>);

impl BlockUses {
    fn new(insts: &[Inst]) -> BlockUses {
        let mut v: Vec<(usize, usize)> = Vec::new();
        for (ii, inst) in insts.iter().enumerate() {
            for a in &inst.args {
                v.push((a.index(), ii));
            }
        }
        v.sort_unstable();
        BlockUses(v)
    }

    /// Positions of the uses of `v` after instruction `i`, ascending.
    fn after(&self, v: Value, i: usize) -> impl Iterator<Item = usize> + '_ {
        let lo = self.0.partition_point(|u| *u <= (v.index(), i));
        self.0[lo..]
            .iter()
            .take_while(move |u| u.0 == v.index())
            .map(|u| u.1)
    }

    /// The first use of `v` after instruction `i` that is an `op`.
    fn first_after(&self, insts: &[Inst], v: Value, i: usize, op: Op) -> Option<usize> {
        self.after(v, i).find(|&k| insts[k].op == op)
    }
}

/// Turns `c = copy v; ...; drop v` into a move when `v` is not touched in between: the copy
/// and the drop cancel, and `c` is `v`. This is the shape of `l = More(l)` in a loop, which
/// would otherwise deep-copy the old value on every iteration.
fn move_dead_sources(m: &mut Module, fi: usize) -> bool {
    let borrows_of = borrows_of(m, fi);
    let f = &mut m.funcs[fi];
    let mut rename: Vec<Option<Value>> = vec![None; f.values.len()];
    let mut touched = vec![false; f.values.len()];
    let mut dead: Vec<(usize, usize)> = Vec::new();
    let at = operand_uses(f);
    for (bi, b) in f.blocks.iter().enumerate() {
        for (i, inst) in b.insts.iter().enumerate() {
            let (Op::Copy, Some(c)) = (inst.op, inst.res) else {
                continue;
            };
            let v = inst.args[0];
            if touched[c.index()] || touched[v.index()] {
                continue;
            }
            // The copy is a move when the next use of `v` in the block is its drop.
            let Some(&(jb, j)) = next_use(&at[v.index()], bi, i) else {
                continue;
            };
            if jb != bi || b.insts[j].op != Op::Drop {
                continue;
            }
            // What was borrowed out of `v` before the copy (a projection another pass merged
            // into an earlier one) must not be read once the copy's drop frees `v`.
            let mut held = vec![false; f.values.len()];
            let mut stack = vec![v];
            while let Some(x) = stack.pop() {
                if !std::mem::replace(&mut held[x.index()], true) {
                    stack.extend(borrows_of[x.index()].iter().copied());
                }
            }
            if b.insts[i + 1..j]
                .iter()
                .any(|n| n.args.iter().any(|a| *a != v && held[a.index()]))
            {
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
    remove_insts(f, &dead);
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

/// The values each value of function `fi` lends out: results that borrow from their operands.
fn borrows_of(m: &Module, fi: usize) -> Vec<Vec<Value>> {
    let f = &m.funcs[fi];
    let mut borrows_of: Vec<Vec<Value>> = vec![Vec::new(); f.values.len()];
    for b in &f.blocks {
        for inst in &b.insts {
            let Some(r) = inst.res else { continue };
            if !matches!(m.result_mode(f, inst), Some(Mode::Own) | None) {
                inst.args.iter().for_each(|a| borrows_of[a.index()].push(r));
            }
        }
    }
    borrows_of
}

/// Turns `c = copy v` into a move when every path from the copy reaches `v` again only to drop
/// it: the copy is `v`'s last use, like `keys.append(key)` before a loop body ends or returns.
/// The copy and the drops cancel, and `c` is `v`. Nothing borrowed out of `v` may be read after
/// the copy, and each block on those paths is entered only from them, so a path that skipped
/// the copy keeps its drop.
fn move_dead_sources_across_blocks(m: &mut Module, fi: usize) -> bool {
    let f = &m.funcs[fi];
    let n = f.values.len();
    let nb = f.blocks.len();
    let mut owned = vec![false; n];
    let mut home = vec![usize::MAX; n];
    let mut borrows_of: Vec<Vec<Value>> = vec![Vec::new(); n];
    for (bi, b) in f.blocks.iter().enumerate() {
        for p in &b.params {
            home[p.value.index()] = bi;
            owned[p.value.index()] = p.mode == Mode::Own;
        }
        for inst in &b.insts {
            let Some(r) = inst.res else { continue };
            home[r.index()] = bi;
            match m.result_mode(f, inst) {
                Some(Mode::Own) => owned[r.index()] = true,
                Some(_) => inst.args.iter().for_each(|a| borrows_of[a.index()].push(r)),
                None => {}
            }
        }
    }
    let preds = f.predecessors();
    let mut touched = vec![false; n];
    let mut rename: Vec<Option<Value>> = vec![None; n];
    let mut dead: Vec<(usize, usize)> = Vec::new();
    for (bc, b) in f.blocks.iter().enumerate() {
        for (i, inst) in b.insts.iter().enumerate() {
            let (Op::Copy, Some(c)) = (inst.op, inst.res) else {
                continue;
            };
            let v = inst.args[0];
            if !owned[v.index()] || touched[v.index()] || touched[c.index()] {
                continue;
            }
            // `v` and every value borrowed out of it.
            let mut held = vec![false; n];
            let mut stack = vec![v];
            while let Some(x) = stack.pop() {
                if !std::mem::replace(&mut held[x.index()], true) {
                    stack.extend(borrows_of[x.index()].iter().copied());
                }
            }
            // The drop of `v` that ends a path, or none when the block passes it on untouched.
            let scan = |insts: &[Inst], from: usize| -> Result<Option<usize>, ()> {
                for (k, n) in insts.iter().enumerate().skip(from) {
                    if n.op == Op::Drop && n.args[0] == v {
                        return Ok(Some(k));
                    }
                    if n.args.iter().any(|a| held[a.index()]) {
                        return Err(());
                    }
                }
                Ok(None)
            };
            let mut drops = Vec::new();
            let mut seen = vec![false; nb];
            let mut work = vec![(bc, i + 1)];
            let mut ok = true;
            while let Some((x, from)) = work.pop() {
                let blk = &f.blocks[x];
                match scan(&blk.insts, from) {
                    Err(()) => ok = false,
                    Ok(Some(k)) => drops.push((x, k)),
                    Ok(None) => {
                        let mut uses = false;
                        blk.term.for_each_use(|a| uses |= held[a.index()]);
                        ok &= !uses && !matches!(blk.term, crate::ir::Term::Ret(_));
                        for s in blk.term.successors() {
                            let s = s.index();
                            ok &= s != bc && s != home[v.index()];
                            if !std::mem::replace(&mut seen[s], true) {
                                work.push((s, 0));
                            }
                        }
                    }
                }
                if !ok {
                    break;
                }
            }
            let entered_elsewhere = (0..nb)
                .any(|x| seen[x] && preds[x].iter().any(|p| p.index() != bc && !seen[p.index()]));
            if !ok || drops.is_empty() || entered_elsewhere {
                continue;
            }
            touched[v.index()] = true;
            touched[c.index()] = true;
            rename[c.index()] = Some(v);
            dead.push((bc, i));
            dead.extend(drops);
        }
    }
    if dead.is_empty() {
        return false;
    }
    let f = &mut m.funcs[fi];
    remove_insts(f, &dead);
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
    // Operand uses of each value as (block, index), in order.
    let mut at: Vec<Vec<(usize, usize)>> = vec![Vec::new(); f.values.len()];
    let mut defs: Vec<Option<(usize, usize)>> = vec![None; f.values.len()];
    for (bi, b) in f.blocks.iter().enumerate() {
        for (ii, inst) in b.insts.iter().enumerate() {
            if let Some(r) = inst.res {
                defs[r.index()] = Some((bi, ii));
            }
            for a in &inst.args {
                uses[a.index()] += 1;
                at[a.index()].push((bi, ii));
            }
        }
        b.term.for_each_use(|v| uses[v.index()] += 1);
    }
    // Per block, how many of the first `k` instructions write memory or touch reference
    // counts (other than `str.len` and `copy`), so a span is checked without a scan.
    let unstable: Vec<Vec<u32>> = f
        .blocks
        .iter()
        .map(|b| {
            let mut n = 0u32;
            std::iter::once(0)
                .chain(b.insts.iter().map(|i| {
                    let e = i.op.info().effects;
                    if (e.writes && i.op != Op::StrLen) || (e.rc && i.op != Op::Copy) {
                        n += 1;
                    }
                    n
                }))
                .collect()
        })
        .collect();
    // Whether an instruction of block `bi` strictly between `lo` and `hi` takes `x` other
    // than by borrow.
    let consumes = |x: Value, bi: usize, lo: usize, hi: usize| -> bool {
        at[x.index()].iter().any(|&(bx, k)| {
            bx == bi && k > lo && k < hi && {
                let n = &f.blocks[bi].insts[k];
                n.args
                    .iter()
                    .zip(arg_modes(m, n))
                    .any(|(a, mode)| *a == x && mode != Mode::Borrow)
            }
        })
    };
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
            // The first drop of `c` after the copy in this block.
            let Some(j) = at[c.index()]
                .iter()
                .find(|&&(bx, k)| bx == bi && k > i && b.insts[k].op == Op::Drop)
                .map(|&(_, k)| k)
            else {
                continue;
            };
            if is_str {
                // Strings are immutable, so the copy can only differ from `v` once `v`'s
                // owner releases or replaces it.
                let Some(root) = str_source(f, &defs, v) else {
                    continue;
                };
                if root.is_some_and(|r| consumes(r, bi, i, j)) {
                    continue;
                }
            }
            if composite && unstable[bi][j] > unstable[bi][i + 1] {
                continue;
            }
            if matches!(kind, TyKind::Fn(..))
                && field_root(f, &defs, v).is_some_and(|r| consumes(r, bi, i, j))
            {
                // A closure read out of a record dies with the record.
                continue;
            }
            let c_uses = at[c.index()]
                .iter()
                .filter(|&&(bx, k)| bx == bi && k > i && k < j)
                .count() as u32;
            if c_uses + 1 != uses[c.index()] {
                continue;
            }
            if consumes(v, bi, i, j) || consumes(c, bi, i, j) {
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
    remove_insts(f, &dead);
    for b in &mut f.blocks {
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
    // The drops of each value as (block, index).
    let mut drops: Vec<Vec<(usize, usize)>> = vec![Vec::new(); f.values.len()];
    for (bi, b) in f.blocks.iter().enumerate() {
        for (ii, inst) in b.insts.iter().enumerate() {
            if let Some(r) = inst.res {
                defs[r.index()] = Some((bi, ii));
            }
            for a in &inst.args {
                uses[a.index()] += 1;
            }
            if inst.op == Op::Drop {
                drops[inst.args[0].index()].push((bi, ii));
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
            let [(bd, jd)] = drops[c.index()][..] else {
                continue;
            };
            if bd == bc {
                continue;
            }
            // The list `v` is read from, or none for a parameter or literal.
            let Some(root) = str_source(f, &defs, v) else {
                continue;
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
    remove_insts(f, &dead);
    for b in &mut f.blocks {
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
    remove_insts(f, &dead);
    true
}

/// What a string copy of `v` may borrow instead of copying: `Some(None)` when `v` is a
/// parameter or a literal, `Some(Some(list))` when `v` is an element read out of `list`,
/// which stays valid while the list is only borrowed, `None` for any other source.
fn str_source(f: &Func, defs: &[Option<(usize, usize)>], v: Value) -> Option<Option<Value>> {
    let Some((db, di)) = defs[v.index()] else {
        return Some(None);
    };
    let def = &f.blocks[db].insts[di];
    match def.op {
        Op::StrLit => Some(None),
        Op::ListGet | Op::ListGetU | Op::ListGetNn => Some(Some(def.args[0])),
        _ => None,
    }
}

/// The owner at the end of the field projections that produced `v`, or `None` when `v` is not
/// a projection.
fn field_root(f: &Func, defs: &[Option<(usize, usize)>], mut v: Value) -> Option<Value> {
    let mut root = None;
    while let Some((db, di)) = defs[v.index()] {
        let def = &f.blocks[db].insts[di];
        if def.op != Op::RecGet {
            break;
        }
        v = def.args[0];
        root = Some(v);
    }
    root
}

/// Removes the instructions at the (block, index) positions in `dead`.
fn remove_insts(f: &mut Func, dead: &[(usize, usize)]) {
    let mut per_block: Vec<Vec<usize>> = vec![Vec::new(); f.blocks.len()];
    for &(bi, k) in dead {
        per_block[bi].push(k);
    }
    for (b, mut ks) in f.blocks.iter_mut().zip(per_block) {
        if ks.is_empty() {
            continue;
        }
        ks.sort_unstable();
        ks.dedup();
        let mut k = 0;
        let mut next = 0;
        b.insts.retain(|_| {
            let drop_it = next < ks.len() && ks[next] == k;
            if drop_it {
                next += 1;
            }
            k += 1;
            !drop_it
        });
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
            let idx = BlockUses::new(&b.insts);
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
                let Some(ci) = idx.first_after(&b.insts, p, gi, Op::Copy) else {
                    continue;
                };
                let Some(di) = idx.first_after(&b.insts, v, ci, Op::Drop) else {
                    continue;
                };
                // The drop must be the only use of `v` after the load (`ci` reads `p`).
                if idx.after(v, gi).any(|k| k != di) || term_uses_of(v) {
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
            let idx = BlockUses::new(&b.insts);
            for (gi, get) in b.insts.iter().enumerate() {
                let (Op::AltGet, Some(p)) = (get.op, get.res) else {
                    continue;
                };
                let v = get.args[0];
                if uses[p.index()] != 1 || !nd[p.index()] {
                    continue;
                }
                let Some(ci) = idx.first_after(&b.insts, p, gi, Op::Copy) else {
                    continue;
                };
                let Some(di) = idx.first_after(&b.insts, v, ci, Op::Drop) else {
                    continue;
                };
                let mut hoist = Vec::new();
                let mut ok = true;
                let mut after_drop = false;
                let mut last = None;
                for k in idx.after(v, gi) {
                    if last == Some(k) {
                        continue;
                    }
                    last = Some(k);
                    if k > di {
                        after_drop = true;
                        break;
                    }
                    if k == ci || k == di {
                        continue;
                    }
                    let n = &b.insts[k];
                    if n.op == Op::AltGet && n.res.is_some_and(|r| !nd[r.index()]) {
                        hoist.push(k);
                    } else {
                        ok = false;
                    }
                }
                if !ok || after_drop {
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

/// Turns `p = alt.get f v; c = copy p; ...; drop v` into `c = alt.take f v; ...; alt.release v`
/// for two or more payload fields that need a drop, when `v` is only read through `alt.get`s
/// until its drop. The release frees the block and drops the fields that were not taken, so
/// rebuilding a node from its children (`Node(insert(l, x), v, r)`) moves them instead of
/// deep-copying and then dropping the originals. It runs after `lastuse` has moved the drop
/// next to the loads.
pub fn run_takes(m: &mut Module) -> bool {
    let mut changed = false;
    for fi in 0..m.funcs.len() {
        changed |= take_dead_sources(m, fi);
        while take_record_fields(m, fi) {
            changed = true;
        }
    }
    changed
}

/// Turns `p = rec.get f v; c = copy p; ...; drop v` into `c = rec.get f v` plus drops of the
/// other droppable fields of `v`, when `v` is only read through `rec.get`s until its drop. The
/// field moves out of the dying record instead of being deep-copied and then freed with it, so
/// `w.inner.clone()` on a record that is dead afterwards costs no allocation. Nothing that can
/// fault or unwind may sit between the first load and the drop, so no cleanup sees the field
/// both moved and still owned by the record.
fn take_record_fields(m: &mut Module, fi: usize) -> bool {
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
    // (block, copy index, record drop index, moved field values) of the first site found.
    let mut site = None;
    'find: for (bi, b) in f.blocks.iter().enumerate() {
        let idx = BlockUses::new(&b.insts);
        for (di, drop) in b.insts.iter().enumerate() {
            let v = drop.args.first().copied();
            let (Op::Drop, Some(v)) = (drop.op, v) else {
                continue;
            };
            let TyKind::Rec(_) = m.types.kind(f.ty(v)) else {
                continue;
            };
            if idx.after(v, di).next().is_some() {
                continue;
            }
            let mut gets: Vec<usize> = Vec::new();
            let mut ok = true;
            for k in 0..di {
                if !b.insts[k].args.contains(&v) {
                    continue;
                }
                if b.insts[k].op == Op::RecGet {
                    gets.push(k);
                } else {
                    ok = false;
                    break;
                }
            }
            let Some(&first) = gets.first() else { continue };
            if !ok {
                continue;
            }
            // Between the first load and the drop there is nothing that can fault or unwind.
            if b.insts[first..di]
                .iter()
                .any(|n| !matches!(n.op, Op::RecGet | Op::Copy))
            {
                continue;
            }
            let field_of = |k: usize| match b.insts[k].imm {
                Imm::Field(_, i) => i,
                _ => u32::MAX,
            };
            let mut taken: Vec<(usize, usize, u32)> = Vec::new();
            for &gi in &gets {
                let Some(p) = b.insts[gi].res else { continue };
                if uses[p.index()] != 1 || !nd[p.index()] {
                    continue;
                }
                let Some(ci) = idx.first_after(&b.insts, p, gi, Op::Copy) else {
                    continue;
                };
                let fld = field_of(gi);
                // A field taken once must not also be read through another `rec.get`.
                if ci < di && gets.iter().filter(|&&g| field_of(g) == fld).count() == 1 {
                    taken.push((gi, ci, fld));
                }
            }
            if taken.is_empty() {
                continue;
            }
            site = Some((bi, di, taken));
            break 'find;
        }
    }
    let Some((bi, di, taken)) = site else {
        return false;
    };
    let f = &mut m.funcs[fi];
    let Imm::Field(rec, _) = f.blocks[bi].insts[taken[0].0].imm else {
        return false;
    };
    // The copy becomes a move out of the dying record; the release drops the other fields.
    let mut mask = 0u32;
    for &(_, ci, fld) in &taken {
        f.blocks[bi].insts[ci].op = Op::MoveOut;
        mask |= 1 << fld;
    }
    let release = &mut f.blocks[bi].insts[di];
    release.op = Op::RecRelease;
    release.imm = Imm::RecMask(rec, mask);
    true
}

fn take_dead_sources(m: &mut Module, fi: usize) -> bool {
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
        let idx = BlockUses::new(&b.insts);
        let mut remove: Vec<usize> = Vec::new();
        let mut rewrites: Vec<(usize, Value, Op, Imm)> = Vec::new();
        for (di, drop) in b.insts.iter().enumerate() {
            if drop.op != Op::Drop {
                continue;
            }
            let v = drop.args[0];
            let mut gets: Vec<usize> = Vec::new();
            let mut ok = true;
            let mut shape = None;
            for k in 0..di {
                if !b.insts[k].args.contains(&v) {
                    continue;
                }
                let Imm::AltField(a, c, _) = b.insts[k].imm else {
                    ok = false;
                    break;
                };
                if b.insts[k].op != Op::AltGet || shape.is_some_and(|s| s != (a, c)) {
                    ok = false;
                    break;
                }
                shape = Some((a, c));
                gets.push(k);
            }
            let (true, Some((a, c)), Some(&first)) = (ok, shape, gets.first()) else {
                continue;
            };
            if m.alts[a.index()].cases[c as usize].fields.len() > 32 {
                continue;
            }
            // `v` is not used again in the block after its drop (it is owned, so not elsewhere).
            if idx.after(v, di).next().is_some() {
                continue;
            }
            // Between the first load and the drop there is nothing that can fault or unwind.
            if b.insts[first..di]
                .iter()
                .any(|n| !matches!(n.op, Op::AltGet | Op::Copy))
            {
                continue;
            }
            let mut taken: Vec<(usize, usize, usize, u32)> = Vec::new();
            for &gi in &gets {
                let get = &b.insts[gi];
                let (Some(p), Imm::AltField(_, _, fld)) = (get.res, get.imm) else {
                    continue;
                };
                if uses[p.index()] != 1 || !nd[p.index()] {
                    continue;
                }
                let Some(ci) = idx.first_after(&b.insts, p, gi, Op::Copy) else {
                    continue;
                };
                if ci < di {
                    taken.push((gi, ci, di, fld));
                }
            }
            // A field taken once must not also be read through another `alt.get`.
            taken.retain(|t| {
                gets.iter()
                    .filter(|&&g| matches!(b.insts[g].imm, Imm::AltField(_, _, x) if x == t.3))
                    .count()
                    == 1
            });
            if taken.len() < 2 {
                continue;
            }
            let mut mask = 0u32;
            for &(gi, ci, _, fld) in &taken {
                mask |= 1 << fld;
                remove.push(gi);
                rewrites.push((ci, v, Op::AltTake, Imm::AltField(a, c, fld)));
            }
            rewrites.push((di, v, Op::AltRelease, Imm::AltMask(a, c, mask)));
        }
        if rewrites.is_empty() {
            continue;
        }
        for (i, v, op, imm) in rewrites {
            let n = &mut b.insts[i];
            n.op = op;
            n.imm = imm;
            n.args = vec![v];
        }
        changed = true;
        let mut at = 0;
        b.insts.retain(|_| {
            at += 1;
            !remove.contains(&(at - 1))
        });
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
