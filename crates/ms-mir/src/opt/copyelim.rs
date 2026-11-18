//! The `copyelim` pass: turns copy-then-drop-the-source into a move, and unboxes dead
//! options and type fields.
//!
//! Lowering copies a value, then drops the source. When the source is dead after the copy,
//! the copy becomes a move. Debug builds rely on this to avoid rebuilding values
//! quadratically.

use crate::ir::{ExternRole, Func, Imm, Inst, Mode, Module, Op, Value};
use crate::types::TyKind;

/// Runs the pass; returns whether anything changed.
pub fn run(m: &mut Module) -> bool {
    let results = super::par_funcs(m.funcs.len(), |fi| {
        let mut f = m.funcs[fi].clone();
        run_funcs(m, &mut f).then_some(f)
    });
    super::store(m, results)
}

/// Runs the pass over one function; returns whether it changed.
pub fn run_funcs(m: &Module, f: &mut Func) -> bool {
    let mut changed = move_dead_sources(m, f);
    changed |= move_dead_sources_across_blocks(m, f);
    changed |= unbox_dead_sources(m, f);
    changed |= unbox_dead_options(m, f);
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

/// Turns `c = clone v; ...; drop v` into a move when `v` is not touched in between: the copy
/// and the drop cancel, and `c` is `v`. This is the shape of `l = More(l)` in a loop, which
/// would otherwise deep-copy the old value on every iteration.
fn move_dead_sources(m: &Module, f: &mut Func) -> bool {
    let borrows_of = borrows_of(m, f);
    let tainted = view_tainted(m, f);
    let mut rename: Vec<Option<Value>> = vec![None; f.values.len()];
    let mut touched = vec![false; f.values.len()];
    let mut dead: Vec<(usize, usize)> = Vec::new();
    let at = operand_uses(f);
    for (bi, b) in f.blocks.iter().enumerate() {
        for (i, inst) in b.insts.iter().enumerate() {
            let (Op::Clone, Some(c)) = (inst.op, inst.res) else {
                continue;
            };
            let v = inst.args[0];
            if touched[c.index()] || touched[v.index()] || tainted[v.index()] {
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

/// The values each value of function `fi` returns borrows of: results that borrow from their operands.
fn borrows_of(m: &Module, f: &Func) -> Vec<Vec<Value>> {
    let mut borrows_of: Vec<Vec<Value>> = vec![Vec::new(); f.values.len()];
    for b in &f.blocks {
        for inst in &b.insts {
            let Some(r) = inst.res else { continue };
            if !matches!(m.result_mode(f, inst), Some(Mode::Move) | None) || m.result_views(f, inst)
            {
                inst.args.iter().for_each(|a| borrows_of[a.index()].push(r));
            }
        }
    }
    borrows_of
}

/// Values of function `fi` that may be interface views (`iface.borrow`, `iface.view`, a view
/// returner's result) or hold one: an owned value whose payload is borrowed from elsewhere. A copy
/// of such a value owns its payload, so the copy is never turned into a move or a take of the
/// source; a copy's result itself is never a view.
fn view_tainted(m: &Module, f: &Func) -> Vec<bool> {
    let mut tainted = vec![false; f.values.len()];
    // A view returner that answers through a status and an out slot (`list_slice_view`): what is
    // read back from the slot is the view.
    for inst in f.blocks.iter().flat_map(|b| &b.insts) {
        if let (Op::CallRt, Imm::Ext(e)) = (inst.op, inst.imm)
            && m.externs[e.index()].role == ExternRole::ViewResult
        {
            for a in inst
                .args
                .iter()
                .filter(|a| f.ty(**a) == crate::types::Ty::PTR)
            {
                tainted[a.index()] = true;
            }
        }
    }
    loop {
        let mut changed = false;
        for b in &f.blocks {
            for inst in &b.insts {
                // A view written to memory taints the address, so what is read back through
                // it (a `for` cursor's list slot and its fields) is a view too.
                if matches!(inst.op, Op::Put | Op::Store)
                    && let [ptr, val, ..] = inst.args[..]
                    && tainted[val.index()]
                    && !tainted[ptr.index()]
                {
                    tainted[ptr.index()] = true;
                    changed = true;
                }
                let Some(r) = inst.res else { continue };
                if tainted[r.index()] {
                    continue;
                }
                let hit = m.result_views(f, inst)
                    || (!matches!(inst.op, Op::Clone)
                        && !inst.op.is_call()
                        && inst.args.iter().any(|a| tainted[a.index()]));
                if hit {
                    tainted[r.index()] = true;
                    changed = true;
                }
            }
            b.term.for_each_target(|t| {
                let params = &f.blocks[t.block.index()].params;
                for (k, a) in t.args.iter().enumerate() {
                    if tainted[a.index()]
                        && let Some(p) = params.get(k)
                        && !tainted[p.value.index()]
                    {
                        tainted[p.value.index()] = true;
                        changed = true;
                    }
                }
            });
        }
        if !changed {
            return tainted;
        }
    }
}

/// Turns `c = clone v` into a move when every path from the copy reaches `v` again only to drop
/// it: the copy is `v`'s last use, like `keys.append(key)` before a loop body ends or returns.
/// The copy and the drops cancel, and `c` is `v`. Nothing borrowed out of `v` may be read after
/// the copy, and each block on those paths is entered only from them, so a path that skipped
/// the copy keeps its drop.
fn move_dead_sources_across_blocks(m: &Module, f: &mut Func) -> bool {
    let n = f.values.len();
    let nb = f.blocks.len();
    let mut owned = vec![false; n];
    let mut home = vec![usize::MAX; n];
    let mut borrows_of: Vec<Vec<Value>> = vec![Vec::new(); n];
    for (bi, b) in f.blocks.iter().enumerate() {
        for p in &b.params {
            home[p.value.index()] = bi;
            owned[p.value.index()] = p.mode == Mode::Move;
        }
        for inst in &b.insts {
            let Some(r) = inst.res else { continue };
            home[r.index()] = bi;
            match m.result_mode(f, inst) {
                Some(Mode::Move) if m.result_views(f, inst) => {
                    owned[r.index()] = true;
                    inst.args.iter().for_each(|a| borrows_of[a.index()].push(r));
                }
                Some(Mode::Move) => owned[r.index()] = true,
                Some(_) => inst.args.iter().for_each(|a| borrows_of[a.index()].push(r)),
                None => {}
            }
        }
    }
    let tainted = view_tainted(m, f);
    let preds = f.predecessors();
    let mut touched = vec![false; n];
    let mut rename: Vec<Option<Value>> = vec![None; n];
    let mut dead: Vec<(usize, usize)> = Vec::new();
    for (bc, b) in f.blocks.iter().enumerate() {
        for (i, inst) in b.insts.iter().enumerate() {
            let (Op::Clone, Some(c)) = (inst.op, inst.res) else {
                continue;
            };
            let v = inst.args[0];
            if !owned[v.index()] || tainted[v.index()] || touched[v.index()] || touched[c.index()] {
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

/// Turns `p = opt.get v; c = clone p; ...; drop v` into `c = opt.unbox v` when `v` is not
/// touched in between and `p` has no other use: the payload moves out and the shell is freed
/// instead of the payload being deep-copied and then dropped with its source. This is the
/// shape of unwrapping a recursive result, which would otherwise copy every subtree once per
/// level.
fn unbox_dead_options(m: &Module, f: &mut Func) -> bool {
    let tainted = view_tainted(m, f);
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
                if uses[p.index()] != 1 || tainted[v.index()] {
                    continue;
                }
                let Some(ci) = idx.first_after(&b.insts, p, gi, Op::Clone) else {
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

/// Turns `p = alt.get f v; c = clone p; ...; drop v` into `c = alt.unbox f v` when `v` is
/// otherwise only read through `alt.get`s of fields that need no drop (those are hoisted
/// above it). This is the shape of `match cur: Link(_, next): cur = next` in a loop, which
/// would otherwise deep-copy the whole tail on every iteration.
fn unbox_dead_sources(m: &Module, f: &mut Func) -> bool {
    let tainted = view_tainted(m, f);
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
    let mut changed = false;
    for b in &mut f.blocks {
        'again: loop {
            let idx = BlockUses::new(&b.insts);
            for (gi, get) in b.insts.iter().enumerate() {
                let (Op::AltGet, Some(p)) = (get.op, get.res) else {
                    continue;
                };
                let v = get.args[0];
                if uses[p.index()] != 1 || !nd[p.index()] || tainted[v.index()] {
                    continue;
                }
                let Some(ci) = idx.first_after(&b.insts, p, gi, Op::Clone) else {
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

/// Turns `p = alt.get f v; c = clone p; ...; drop v` into `c = alt.take f v; ...; alt.release v`
/// for two or more payload fields that need a drop, when `v` is only read through `alt.get`s
/// until its drop. The release frees the block and drops the fields that were not taken, so
/// rebuilding a node from its children (`Node(insert(l, x), v, r)`) moves them instead of
/// deep-copying and then dropping the originals. It runs after `lastuse` has moved the drop
/// next to the loads.
pub fn run_takes(m: &mut Module) -> bool {
    let results = super::par_funcs(m.funcs.len(), |fi| {
        let mut f = m.funcs[fi].clone();
        let mut changed = false;
        while take_type_fields(m, &mut f) {
            changed = true;
        }
        changed.then_some(f)
    });
    super::store(m, results)
}

/// Turns `p = type.get f v; c = clone p; ...; drop v` into `c = type.get f v` plus drops of the
/// other droppable fields of `v`, when `v` is only read through `type.get`s until its drop. The
/// field moves out of the dying type instead of being deep-copied and then freed with it, so
/// `w.inner.clone()` on a type that is dead afterwards costs no allocation. Nothing that can
/// fault or unwind may sit between the first load and the drop, so no cleanup sees the field
/// both moved and still owned by the type.
fn take_type_fields(m: &Module, f: &mut Func) -> bool {
    let tainted = view_tainted(m, f);
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
    // (block, copy index, type drop index, moved field values) of the first site found.
    let mut site = None;
    'find: for (bi, b) in f.blocks.iter().enumerate() {
        let idx = BlockUses::new(&b.insts);
        for (di, drop) in b.insts.iter().enumerate() {
            let v = drop.args.first().copied();
            let (Op::Drop, Some(v)) = (drop.op, v) else {
                continue;
            };
            let TyKind::Type(_) = m.types.kind(f.ty(v)) else {
                continue;
            };
            if tainted[v.index()] || idx.after(v, di).next().is_some() {
                continue;
            }
            let mut gets: Vec<usize> = Vec::new();
            let mut ok = true;
            for k in 0..di {
                if !b.insts[k].args.contains(&v) {
                    continue;
                }
                if b.insts[k].op == Op::TypeGet {
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
                .any(|n| !matches!(n.op, Op::TypeGet | Op::Clone))
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
                let Some(ci) = idx.first_after(&b.insts, p, gi, Op::Clone) else {
                    continue;
                };
                let fld = field_of(gi);
                // A field taken once must not also be read through another `type.get`.
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
    let Imm::Field(tval, _) = f.blocks[bi].insts[taken[0].0].imm else {
        return false;
    };
    // The copy becomes a move out of the dying type; the release drops the other fields.
    let mut mask = 0u32;
    for &(_, ci, fld) in &taken {
        f.blocks[bi].insts[ci].op = Op::MoveOut;
        mask |= 1 << fld;
    }
    let release = &mut f.blocks[bi].insts[di];
    release.op = Op::TypeRelease;
    release.imm = Imm::TypeMask(tval, mask);
    true
}
