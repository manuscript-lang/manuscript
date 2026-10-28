//! The `inline` pass: bottom-up inlining of direct calls, removal of functions that
//! became unreferenced, and removal of `depth.enter`/`depth.leave` from functions that
//! cannot take part in recursion (see [`crate::opt`] for the pass contract).
//!
//! A callee is inlined when it is a plain function outside every direct-call cycle and
//! either carries [`InlineHint::Always`] or, for [`InlineHint::Auto`], is small enough
//! (see [`BASE_THRESHOLD`]) and, if it contains a loop, called from inside a loop. Never-hinted functions, closure code and method bodies are
//! never inlined. Callees are processed before callers, so a caller sees the already
//! inlined body of its callee.

use crate::ir::{
    Block, BlockData, BlockParam, Func, FuncId, FuncKind, Imm, InlineHint, Inst, Linkage, Loc,
    Mode, Module, Op, Param, Scope, Target, Term, Value,
};
use crate::types::{RecId, Ty, TyKind};
use std::collections::{HashMap, HashSet};

/// Instruction count up to which an `Auto` callee is inlined.
pub const BASE_THRESHOLD: usize = 60;
/// Extra allowance when the callee has a single call site in the module.
pub const SINGLE_CALLER_BONUS: usize = 25;
/// Extra allowance per constant argument.
pub const CONST_ARG_BONUS: usize = 5;
/// Cap on growth of one caller, as a multiple of its original size plus [`GROWTH_SLACK`].
pub const GROWTH_FACTOR: usize = 4;
/// Fixed growth allowance per caller.
pub const GROWTH_SLACK: usize = 200;
/// Largest callee copied by closure-argument specialization.
pub const SPECIALIZE_MAX_SIZE: usize = 400;
/// Instructions the whole module may gain from closure-argument specialization.
pub const SPECIALIZE_BUDGET: usize = 2000;
/// Rounds of specialization (a clone that forwards its closure to another call needs one more).
const SPECIALIZE_ROUNDS: usize = 4;

/// Runs the pass over the whole module; returns whether anything changed.
pub fn run(m: &mut Module) -> bool {
    let mut changed = specialize_sort_thunks(m);
    changed |= super::sortgen::run(m);
    changed |= specialize_closure_args(m);
    changed |= inline_calls(m);
    changed |= inline_closures(m);
    changed |= strip_depth(m);
    changed |= remove_dead(m);
    changed
}

/// Gives each runtime sort whose comparator is a known closure a private copy of the generic
/// `sort.cmp` thunk that calls the closure's code directly (and inlines it). The runtime then
/// makes one indirect call per comparison instead of three.
fn specialize_sort_thunks(m: &mut Module) -> bool {
    let mut changed = false;
    let mut made: HashMap<(FuncId, FuncId), FuncId> = HashMap::new();
    for fi in 0..m.funcs.len() {
        let mut known: HashMap<Value, FuncId> = HashMap::new();
        let mut addrs: HashMap<Value, FuncId> = HashMap::new();
        for inst in m.funcs[fi].blocks.iter().flat_map(|b| b.insts.iter()) {
            match (inst.op, inst.imm, inst.res) {
                (Op::ClosureNew, Imm::Func(g), Some(r)) => {
                    known.insert(r, g);
                }
                (Op::FuncAddr, Imm::Func(t), Some(r)) if m.funcs[t.index()].name == "sort.cmp" => {
                    addrs.insert(r, t);
                }
                _ => {}
            }
        }
        if addrs.is_empty() || known.is_empty() {
            continue;
        }
        let mut edits: Vec<(Value, FuncId, FuncId)> = Vec::new();
        for inst in m.funcs[fi].blocks.iter().flat_map(|b| b.insts.iter()) {
            if inst.op != Op::CallRt {
                continue;
            }
            for w in inst.args.windows(2) {
                if let (Some(&t), Some(&g)) = (addrs.get(&w[0]), known.get(&w[1])) {
                    edits.push((w[0], t, g));
                }
            }
        }
        for (addr, t, g) in edits {
            let spec = match made.get(&(t, g)) {
                Some(s) => *s,
                None => {
                    let Some(thunk) = specialized_thunk(m, t, g) else {
                        continue;
                    };
                    let s = m.add_func(thunk);
                    made.insert((t, g), s);
                    s
                }
            };
            for inst in m.funcs[fi]
                .blocks
                .iter_mut()
                .flat_map(|b| b.insts.iter_mut())
            {
                if inst.res == Some(addr) {
                    inst.imm = Imm::Func(spec);
                    changed = true;
                }
            }
        }
    }
    changed
}

/// `thunk` with its closure parameter replaced by the raw environment pointer and the indirect
/// call replaced by a direct call (inlined when small) of closure code `g`.
fn specialized_thunk(m: &Module, thunk: FuncId, g: FuncId) -> Option<Func> {
    let code = &m.funcs[g.index()];
    let FuncKind::Closure { captures } = &code.kind else {
        return None;
    };
    if code.inline == InlineHint::Never {
        return None;
    }
    let mut t = m.funcs[thunk.index()].clone();
    t.name = format!("sort.cmp.{}", code.name);
    t.params[0].ty = Ty::PTR;
    let env = t.blocks[0].params[0].value;
    t.values[env.index()] = Ty::PTR;
    let (bi, ii) = t.blocks.iter().enumerate().find_map(|(bi, b)| {
        b.insts
            .iter()
            .position(|i| i.op == Op::CallInd && i.args[0] == env)
            .map(|ii| (bi, ii))
    })?;
    let call = &mut t.blocks[bi].insts[ii];
    call.op = Op::Call;
    call.imm = Imm::Func(g);
    // A `closure.cap` reads the environment through the function's own capture layout, which
    // the thunk does not have: code that captures is called, not inlined.
    if code.inst_count() <= BASE_THRESHOLD && captures.is_empty() {
        let ret_own = m.needs_drop(code.ret) && !code.ret_borrowed;
        inline_at(&mut t, bi, ii, code, ret_own);
    }
    Some(t)
}

/// Strongly connected components of the graph `adj`, callees (successors) first.
fn sccs(adj: &[Vec<usize>]) -> Vec<Vec<usize>> {
    let n = adj.len();
    let mut index = vec![usize::MAX; n];
    let mut low = vec![0usize; n];
    let mut on = vec![false; n];
    let mut stack = Vec::new();
    let mut next = 0usize;
    let mut out = Vec::new();
    for root in 0..n {
        if index[root] != usize::MAX {
            continue;
        }
        index[root] = next;
        low[root] = next;
        next += 1;
        stack.push(root);
        on[root] = true;
        let mut work: Vec<(usize, usize)> = vec![(root, 0)];
        while let Some(&(v, k)) = work.last() {
            if k < adj[v].len() {
                work.last_mut().expect("nonempty").1 += 1;
                let w = adj[v][k];
                if index[w] == usize::MAX {
                    index[w] = next;
                    low[w] = next;
                    next += 1;
                    stack.push(w);
                    on[w] = true;
                    work.push((w, 0));
                } else if on[w] {
                    low[v] = low[v].min(index[w]);
                }
                continue;
            }
            work.pop();
            if let Some(&(p, _)) = work.last() {
                low[p] = low[p].min(low[v]);
            }
            if low[v] == index[v] {
                let mut comp = Vec::new();
                while let Some(w) = stack.pop() {
                    on[w] = false;
                    comp.push(w);
                    if w == v {
                        break;
                    }
                }
                out.push(comp);
            }
        }
    }
    out
}

/// Per node: whether it lies on a cycle of `adj`.
fn cyclic(adj: &[Vec<usize>]) -> Vec<bool> {
    let mut out = vec![false; adj.len()];
    for comp in sccs(adj) {
        if comp.len() > 1 || adj[comp[0]].contains(&comp[0]) {
            for v in comp {
                out[v] = true;
            }
        }
    }
    out
}

/// Direct-call adjacency (`call` only).
fn direct_graph(m: &Module) -> Vec<Vec<usize>> {
    m.funcs
        .iter()
        .map(|f| {
            f.blocks
                .iter()
                .flat_map(|b| b.insts.iter())
                .filter_map(|i| match (i.op, i.imm) {
                    (Op::Call, Imm::Func(g)) => Some(g.index()),
                    _ => None,
                })
                .collect()
        })
        .collect()
}

fn inline_calls(m: &mut Module) -> bool {
    let adj = direct_graph(m);
    let cyc = cyclic(&adj);
    let mut sites = vec![0usize; m.funcs.len()];
    for a in &adj {
        for &g in a {
            sites[g] += 1;
        }
    }
    let mut changed = false;
    for comp in sccs(&adj) {
        for fi in comp {
            changed |= inline_into(m, fi, &cyc, &sites);
        }
    }
    changed
}

/// Whether the function has a loop: an edge to a block at or before its source in
/// reverse post-order.
fn has_loop(f: &Func) -> bool {
    let mut pos = vec![usize::MAX; f.blocks.len()];
    let order = f.rpo();
    for (i, b) in order.iter().enumerate() {
        pos[b.index()] = i;
    }
    order.iter().any(|b| {
        f.blocks[b.index()]
            .term
            .successors()
            .iter()
            .any(|s| pos[s.index()] <= pos[b.index()])
    })
}

/// Per block: whether it lies on a cycle of the control-flow graph.
fn blocks_in_loops(f: &Func) -> Vec<bool> {
    let adj: Vec<Vec<usize>> = f
        .blocks
        .iter()
        .map(|b| b.term.successors().iter().map(|s| s.index()).collect())
        .collect();
    cyclic(&adj)
}

fn const_values(blocks: &[BlockData]) -> impl Iterator<Item = Value> + '_ {
    blocks
        .iter()
        .flat_map(|b| b.insts.iter())
        .filter(|i| matches!(i.op, Op::IConst | Op::FConst | Op::BConst))
        .filter_map(|i| i.res)
}

fn inline_into(m: &mut Module, fi: usize, cyc: &[bool], sites: &[usize]) -> bool {
    let budget = m.funcs[fi].inst_count() * GROWTH_FACTOR + GROWTH_SLACK;
    let mut consts: HashSet<Value> = const_values(&m.funcs[fi].blocks).collect();
    let mut grown = 0usize;
    let mut changed = false;
    let mut work: Vec<usize> = (0..m.funcs[fi].blocks.len()).collect();
    while let Some(bi) = work.pop() {
        // Choose every site in the block first, then inline from the last: each split moves
        // only the instructions up to the previous split, not the whole remaining tail.
        // Callee constants never reach a later call's arguments, so the choices match
        // inlining one site at a time.
        let mut picks: Vec<(usize, usize)> = Vec::new();
        for ii in 0..m.funcs[fi].blocks[bi].insts.len() {
            let inst = &m.funcs[fi].blocks[bi].insts[ii];
            let (Op::Call, Imm::Func(g)) = (inst.op, inst.imm) else {
                continue;
            };
            let gi = g.index();
            let callee = &m.funcs[gi];
            if gi == fi || cyc[gi] || !matches!(callee.kind, FuncKind::Normal) {
                continue;
            }
            let size = callee.inst_count();
            let ok = match callee.inline {
                InlineHint::Never => false,
                InlineHint::Always => true,
                // A callee with a loop only pays for the call when the call itself repeats.
                InlineHint::Auto if has_loop(callee) && !blocks_in_loops(&m.funcs[fi])[bi] => false,
                InlineHint::Auto => {
                    let mut limit = BASE_THRESHOLD;
                    if sites[gi] == 1 {
                        limit += SINGLE_CALLER_BONUS;
                    }
                    limit +=
                        CONST_ARG_BONUS * inst.args.iter().filter(|a| consts.contains(a)).count();
                    size <= limit && grown + size <= budget
                }
            };
            if ok {
                grown += size;
                picks.push((ii, gi));
            }
        }
        for (ii, gi) in picks.into_iter().rev() {
            let callee = m.funcs[gi].clone();
            let ret_own = m.needs_drop(callee.ret) && !callee.ret_borrowed;
            let cont = inline_at(&mut m.funcs[fi], bi, ii, &callee, ret_own);
            // Only the call definition is replaced; existing constants keep their IDs when
            // the tail moves. Fresh callee definitions follow the continuation block.
            consts.extend(const_values(&m.funcs[fi].blocks[cont + 1..]));
            changed = true;
        }
    }
    changed
}

/// Replaces the call at instruction `ii` of block `bi` with a copy of `callee`;
/// returns the continuation block holding everything after the call.
fn inline_at(f: &mut Func, bi: usize, ii: usize, callee: &Func, ret_own: bool) -> usize {
    let call = f.blocks[bi].insts[ii].clone();
    let tail: Vec<Inst> = f.blocks[bi].insts.split_off(ii + 1);
    f.blocks[bi].insts.pop();
    let old_term = std::mem::replace(&mut f.blocks[bi].term, Term::Unreachable);
    let old_term_loc = f.blocks[bi].term_loc;

    let res = call.res.expect("call defines a result");
    let cont = f.new_block();
    f.blocks[cont.index()] = BlockData {
        params: vec![BlockParam {
            value: res,
            mode: if ret_own { Mode::Own } else { Mode::Borrow },
        }],
        insts: tail,
        term: old_term,
        term_loc: old_term_loc,
    };

    // The callee's positions become a scope called from the call's position; scopes the
    // callee already carries (its own inlined callees) nest beneath it.
    let base = f.scopes.len() as u32;
    f.scopes.push(Scope {
        name: callee.name.clone(),
        file: callee.loc.file,
        parent: call.loc.scope,
        call_line: call.loc.line,
    });
    f.scopes.extend(callee.scopes.iter().map(|s| Scope {
        name: s.name.clone(),
        file: s.file,
        parent: base + 1 + s.parent,
        call_line: s.call_line,
    }));
    let ml = |l: Loc| Loc {
        scope: base + 1 + l.scope,
        ..l
    };

    let vmap: Vec<Value> = callee.values.iter().map(|t| f.new_value(*t)).collect();
    let bmap: Vec<Block> = callee.blocks.iter().map(|_| f.new_block()).collect();
    let mv = |v: Value| vmap[v.index()];
    let mt = |t: &Target| Target {
        block: bmap[t.block.index()],
        args: t.args.iter().map(|a| mv(*a)).collect(),
    };
    for (k, cb) in callee.blocks.iter().enumerate() {
        let params = cb
            .params
            .iter()
            .map(|p| BlockParam {
                value: mv(p.value),
                mode: p.mode,
            })
            .collect();
        let mut insts: Vec<Inst> = cb
            .insts
            .iter()
            .map(|i| Inst {
                op: i.op,
                args: i.args.iter().map(|a| mv(*a)).collect(),
                imm: i.imm,
                res: i.res.map(mv),
                loc: ml(i.loc),
            })
            .collect();
        let term = match &cb.term {
            Term::Br(t) => Term::Br(mt(t)),
            Term::CondBr { cond, then, els } => Term::CondBr {
                cond: mv(*cond),
                then: mt(then),
                els: mt(els),
            },
            Term::Switch {
                value,
                cases,
                default,
            } => Term::Switch {
                value: mv(*value),
                cases: cases.iter().map(|(c, t)| (*c, mt(t))).collect(),
                default: mt(default),
            },
            Term::Ret(v) => {
                let arg = match v {
                    Some(v) => mv(*v),
                    None => {
                        let u = f.new_value(Ty::UNIT);
                        insts.push(Inst {
                            op: Op::UnitConst,
                            args: Vec::new(),
                            imm: Imm::None,
                            res: Some(u),
                            loc: ml(cb.term_loc),
                        });
                        u
                    }
                };
                Term::Br(Target {
                    block: cont,
                    args: vec![arg],
                })
            }
            Term::Fault(k) => Term::Fault(*k),
            Term::Unreachable => Term::Unreachable,
        };
        f.blocks[bmap[k].index()] = BlockData {
            params,
            insts,
            term,
            term_loc: ml(cb.term_loc),
        };
    }
    f.blocks[bi].term = Term::Br(Target {
        block: bmap[0],
        args: call.args,
    });
    f.blocks[bi].term_loc = call.loc;
    cont.index()
}

/// Inlines `call.ind` of a closure built in the same function by `closure.new` when every
/// capture is plain data: the body is copied in with `closure.cap` replaced by the captured
/// value, and a closure left with no use but drops is deleted with them (a plain-data
/// environment owns nothing, so ownership stays linear). Closures that capture owned
/// values keep their indirect call.
fn inline_closures(m: &mut Module) -> bool {
    let mut changed = false;
    let fields = constant_closure_fields(m);
    for fi in 0..m.funcs.len() {
        changed |= inline_closures_in(m, fi, &fields);
    }
    changed
}

/// The closure code held by each record field that every construction in the module sets to the
/// same capture-free closure and that nothing else ever writes, so reading the field always
/// yields that closure whichever record it is read from.
fn constant_closure_fields(m: &Module) -> HashMap<(RecId, u32), FuncId> {
    // `None` marks a field with two different closures or a write the analysis cannot see.
    let mut seen: HashMap<(RecId, u32), Option<FuncId>> = HashMap::new();
    for f in &m.funcs {
        let mut defs: HashMap<Value, &Inst> = HashMap::new();
        for inst in f.blocks.iter().flat_map(|b| b.insts.iter()) {
            if let Some(r) = inst.res {
                defs.insert(r, inst);
            }
        }
        for inst in f.blocks.iter().flat_map(|b| b.insts.iter()) {
            match (inst.op, inst.imm) {
                (Op::RecSet | Op::RecFill | Op::PtrField, Imm::Field(r, k)) => {
                    seen.insert((r, k), None);
                }
                (Op::RecNew, Imm::Rec(r)) => {
                    for (k, a) in inst.args.iter().enumerate() {
                        if !matches!(m.types.kind(f.ty(*a)), TyKind::Fn(..)) {
                            continue;
                        }
                        let mut v = *a;
                        while let Some(d) = defs.get(&v)
                            && d.op == Op::Copy
                        {
                            v = d.args[0];
                        }
                        let code = defs.get(&v).and_then(|d| match (d.op, d.imm) {
                            (Op::ClosureNew, Imm::Func(g)) if d.args.is_empty() => Some(g),
                            _ => None,
                        });
                        let entry = seen.entry((r, k as u32)).or_insert(code);
                        if *entry != code {
                            *entry = None;
                        }
                    }
                }
                _ => {}
            }
        }
    }
    seen.into_iter()
        .filter_map(|(key, g)| g.map(|g| (key, g)))
        .collect()
}

fn inline_closures_in(m: &mut Module, fi: usize, fields: &HashMap<(RecId, u32), FuncId>) -> bool {
    let budget = m.funcs[fi].inst_count() * GROWTH_FACTOR + GROWTH_SLACK;
    let mut grown = 0usize;
    let mut changed = false;
    let mut work: Vec<usize> = (0..m.funcs[fi].blocks.len()).collect();
    let roots = known_closures(m, fi);
    let mut known: HashMap<Value, (FuncId, Vec<Value>)> = HashMap::new();
    for (v, root) in closure_aliases(&m.funcs[fi], &roots) {
        known.insert(v, roots[&root].clone());
    }
    for inst in m.funcs[fi].blocks.iter().flat_map(|b| b.insts.iter()) {
        if let (Op::RecGet, Imm::Field(r, k), Some(v)) = (inst.op, inst.imm, inst.res)
            && let Some(g) = fields.get(&(r, k))
        {
            known.insert(v, (*g, Vec::new()));
        }
    }
    if known.is_empty() {
        return false;
    }
    while let Some(bi) = work.pop() {
        for ii in 0..m.funcs[fi].blocks[bi].insts.len() {
            let inst = &m.funcs[fi].blocks[bi].insts[ii];
            if inst.op != Op::CallInd {
                continue;
            }
            let Some((g, caps)) = known.get(&inst.args[0]).cloned() else {
                continue;
            };
            let gi = g.index();
            let callee = &m.funcs[gi];
            let size = callee.inst_count();
            if gi == fi || callee.inline == InlineHint::Never || size > BASE_THRESHOLD {
                continue;
            }
            if grown + size > budget {
                continue;
            }
            let Some(body) = closure_body(&m.funcs[gi]) else {
                continue;
            };
            grown += size;
            let ret_own = m.needs_drop(body.ret) && !body.ret_borrowed;
            let call = &mut m.funcs[fi].blocks[bi].insts[ii];
            call.op = Op::Call;
            call.imm = Imm::Func(g);
            call.args = caps.into_iter().chain(call.args.drain(1..)).collect();
            let cont = inline_at(&mut m.funcs[fi], bi, ii, &body, ret_own);
            work.push(cont);
            changed = true;
            break;
        }
    }
    changed |= delete_unused_closures(m, fi);
    changed
}

/// A copy of closure code `f` as a plain function taking the captures before the
/// arguments, or `None` when the environment is used in any way besides `closure.cap`.
fn closure_body(f: &Func) -> Option<Func> {
    let FuncKind::Closure { captures } = &f.kind else {
        return None;
    };
    let mut c = f.clone();
    let env = c.blocks[0].params[0].value;
    let cap_params: Vec<Value> = captures.iter().map(|t| c.new_value(*t)).collect();
    let mut subst: HashMap<Value, Value> = HashMap::new();
    for b in &mut c.blocks {
        b.insts.retain(|i| {
            let (Op::ClosureCap, Imm::Idx(k), Some(r)) = (i.op, i.imm, i.res) else {
                return true;
            };
            subst.insert(r, cap_params[k as usize]);
            false
        });
    }
    let mut env_used = false;
    for b in &mut c.blocks {
        for i in &mut b.insts {
            for a in &mut i.args {
                *a = subst.get(a).copied().unwrap_or(*a);
                env_used |= *a == env;
            }
        }
        b.term.for_each_use_mut(|v| {
            *v = subst.get(v).copied().unwrap_or(*v);
            env_used |= *v == env;
        });
    }
    if env_used {
        return None;
    }
    let rest = c.blocks[0].params.split_off(1);
    c.blocks[0].params = cap_params
        .into_iter()
        .map(|value| BlockParam {
            value,
            mode: Mode::Borrow,
        })
        .chain(rest)
        .collect();
    Some(c)
}

/// The closures built in function `fi` by `closure.new` whose captures are all plain data, as
/// result value -> (closure code, captured values).
fn known_closures(m: &Module, fi: usize) -> HashMap<Value, (FuncId, Vec<Value>)> {
    let f = &m.funcs[fi];
    let mut known = HashMap::new();
    for inst in f.blocks.iter().flat_map(|b| b.insts.iter()) {
        if let (Op::ClosureNew, Imm::Func(g), Some(r)) = (inst.op, inst.imm, inst.res)
            && inst.args.iter().all(|a| !m.needs_drop(f.ty(*a)))
            && m.funcs[g.index()].capture_closers.is_empty()
        {
            known.insert(r, (g, inst.args.clone()));
        }
    }
    known
}

/// Maps every value that always holds the same known closure to that closure's `closure.new`
/// result: the result itself, `copy` of such a value, and a block parameter each of whose
/// incoming arguments is such a value (or the parameter itself, on a loop back edge).
fn closure_aliases(
    f: &Func,
    roots: &HashMap<Value, (FuncId, Vec<Value>)>,
) -> HashMap<Value, Value> {
    let mut alias: HashMap<Value, Value> = roots.keys().map(|v| (*v, *v)).collect();
    let mut incoming: HashMap<(usize, usize), Vec<Value>> = HashMap::new();
    for b in &f.blocks {
        b.term.for_each_target(|t| {
            for (j, a) in t.args.iter().enumerate() {
                incoming.entry((t.block.index(), j)).or_default().push(*a);
            }
        });
    }
    loop {
        let mut grew = false;
        for inst in f.blocks.iter().flat_map(|b| b.insts.iter()) {
            if let (Op::Copy, Some(r)) = (inst.op, inst.res)
                && !alias.contains_key(&r)
                && let Some(&root) = alias.get(&inst.args[0])
            {
                alias.insert(r, root);
                grew = true;
            }
        }
        for (bi, b) in f.blocks.iter().enumerate().skip(1) {
            for (j, p) in b.params.iter().enumerate() {
                if alias.contains_key(&p.value) {
                    continue;
                }
                let mut root = None;
                let ok = incoming.get(&(bi, j)).is_some_and(|args| {
                    args.iter().all(|a| {
                        if *a == p.value {
                            return true;
                        }
                        let Some(&r) = alias.get(a) else {
                            return false;
                        };
                        *root.get_or_insert(r) == r
                    })
                });
                if let (true, Some(r)) = (ok, root) {
                    alias.insert(p.value, r);
                    grew = true;
                }
            }
        }
        if !grew {
            return alias;
        }
    }
}

/// Deletes each known closure whose aliases are only copied, dropped and carried through block
/// parameters, together with those copies, drops and parameters (and the arguments feeding
/// them). A plain-data environment owns nothing, so ownership stays linear. Returns whether
/// anything was deleted.
fn delete_unused_closures(m: &mut Module, fi: usize) -> bool {
    let roots = known_closures(m, fi);
    if roots.is_empty() {
        return false;
    }
    let f = &mut m.funcs[fi];
    let alias = closure_aliases(f, &roots);
    let mut live: HashSet<Value> = HashSet::new();
    let note = |v: Value, live: &mut HashSet<Value>| {
        if let Some(r) = alias.get(&v) {
            live.insert(*r);
        }
    };
    for b in &f.blocks {
        for i in &b.insts {
            let class_only = match i.op {
                Op::Drop => true,
                Op::Copy => i.res.is_some_and(|r| alias.contains_key(&r)),
                _ => false,
            };
            if !class_only {
                i.args.iter().for_each(|a| note(*a, &mut live));
            }
        }
        match &b.term {
            Term::CondBr { cond, .. } => note(*cond, &mut live),
            Term::Switch { value, .. } => note(*value, &mut live),
            Term::Ret(Some(v)) => note(*v, &mut live),
            _ => {}
        }
        // An argument into a block parameter outside the class keeps the closure alive.
        let mut targets: Vec<(usize, usize, Value)> = Vec::new();
        b.term.for_each_target(|t| {
            for (j, a) in t.args.iter().enumerate() {
                targets.push((t.block.index(), j, *a));
            }
        });
        for (bk, j, a) in targets {
            if !alias.contains_key(&f.blocks[bk].params[j].value) {
                note(a, &mut live);
            }
        }
    }
    let dead = |v: &Value| alias.get(v).is_some_and(|r| !live.contains(r));
    let mut dead_params: HashSet<(usize, usize)> = HashSet::new();
    for (bi, b) in f.blocks.iter().enumerate() {
        for (j, p) in b.params.iter().enumerate() {
            if bi > 0 && dead(&p.value) {
                dead_params.insert((bi, j));
            }
        }
    }
    let mut changed = !dead_params.is_empty();
    for b in &mut f.blocks {
        let before = b.insts.len();
        b.insts.retain(|i| match i.op {
            Op::ClosureNew | Op::Copy => !i.res.is_some_and(|r| dead(&r)),
            Op::Drop => !dead(&i.args[0]),
            _ => true,
        });
        changed |= b.insts.len() != before;
        b.term.for_each_target_mut(|t| {
            let mut j = 0;
            t.args.retain(|_| {
                j += 1;
                !dead_params.contains(&(t.block.index(), j - 1))
            });
        });
    }
    for (bi, b) in f.blocks.iter_mut().enumerate() {
        let mut j = 0;
        b.params.retain(|_| {
            j += 1;
            !dead_params.contains(&(bi, j - 1))
        });
    }
    changed
}

/// Gives each call that passes a closure built in the caller (plain-data captures, borrowed
/// parameter) a private copy of the callee in which that parameter is replaced by a
/// `closure.new` of the same code over captures taken as parameters. The closure inliner then
/// resolves the callee's indirect calls (see [`inline_closures`]) and deletes the closure.
fn specialize_closure_args(m: &mut Module) -> bool {
    let mut changed = false;
    let mut made: HashMap<(FuncId, FuncId, usize), FuncId> = HashMap::new();
    let mut spent = 0usize;
    for _ in 0..SPECIALIZE_ROUNDS {
        let cyc = cyclic(&direct_graph(m));
        let mut round = false;
        for fi in 0..m.funcs.len() {
            round |= specialize_in(m, fi, &cyc, &mut made, &mut spent);
        }
        changed |= round;
        if !round {
            break;
        }
    }
    changed
}

fn specialize_in(
    m: &mut Module,
    fi: usize,
    cyc: &[bool],
    made: &mut HashMap<(FuncId, FuncId, usize), FuncId>,
    spent: &mut usize,
) -> bool {
    let known = known_closures(m, fi);
    if known.is_empty() {
        return false;
    }
    let mut changed = false;
    for bi in 0..m.funcs[fi].blocks.len() {
        for ii in 0..m.funcs[fi].blocks[bi].insts.len() {
            let inst = &m.funcs[fi].blocks[bi].insts[ii];
            let (Op::Call, Imm::Func(c)) = (inst.op, inst.imm) else {
                continue;
            };
            let ci = c.index();
            let callee = &m.funcs[ci];
            if ci == fi
                || cyc.get(ci).copied().unwrap_or(false)
                || !matches!(callee.kind, FuncKind::Normal)
                || callee.inline == InlineHint::Never
                || callee.inst_count() > SPECIALIZE_MAX_SIZE
                || !callee
                    .blocks
                    .iter()
                    .flat_map(|b| b.insts.iter())
                    .any(|i| i.op == Op::CallInd)
            {
                continue;
            }
            let pick = inst.args.iter().enumerate().find_map(|(i, a)| {
                let (g, _) = known.get(a)?;
                let code = &m.funcs[g.index()];
                let ok = callee.params[i].mode == Mode::Borrow
                    && code.inline != InlineHint::Never
                    && code.inst_count() <= BASE_THRESHOLD
                    && closure_body(code).is_some();
                ok.then_some((i, *g, known[a].1.clone()))
            });
            let Some((i, g, caps)) = pick else {
                continue;
            };
            let spec = match made.get(&(c, g, i)) {
                Some(s) => *s,
                None => {
                    let clone = specialized_callee(m, c, g, i);
                    if *spent + clone.inst_count() > SPECIALIZE_BUDGET {
                        continue;
                    }
                    *spent += clone.inst_count();
                    let s = m.add_func(clone);
                    made.insert((c, g, i), s);
                    s
                }
            };
            let call = &mut m.funcs[fi].blocks[bi].insts[ii];
            call.imm = Imm::Func(spec);
            call.args.splice(i..=i, caps);
            changed = true;
        }
    }
    if changed {
        delete_unused_closures(m, fi);
    }
    changed
}

/// `callee` with parameter `i` (a borrowed closure) replaced by the captures of closure code
/// `g` and a `closure.new` of `g` over them at the top of the entry block, dropped before
/// every `ret`.
fn specialized_callee(m: &Module, callee: FuncId, g: FuncId, i: usize) -> Func {
    let FuncKind::Closure { captures } = &m.funcs[g.index()].kind else {
        unreachable!("specialization picks closure code");
    };
    let mut f = m.funcs[callee.index()].clone();
    f.name = format!("{}.{}", f.name, m.funcs[g.index()].name);
    let old = f.blocks[0].params[i].value;
    let ty = f.ty(old);
    let loc = f.loc;
    f.params.remove(i);
    f.blocks[0].params.remove(i);
    f.noalias = f
        .noalias
        .iter()
        .filter(|p| **p as usize != i)
        .map(|p| {
            if *p as usize > i {
                *p - 1 + captures.len() as u32
            } else {
                *p
            }
        })
        .collect();
    let cap_values: Vec<Value> = captures.iter().map(|t| f.new_value(*t)).collect();
    for (k, (t, v)) in captures.iter().zip(&cap_values).enumerate() {
        f.params.insert(
            i + k,
            Param {
                ty: *t,
                mode: Mode::Borrow,
            },
        );
        f.blocks[0].params.insert(
            i + k,
            BlockParam {
                value: *v,
                mode: Mode::Borrow,
            },
        );
    }
    let k = f.new_value(ty);
    for b in &mut f.blocks {
        for inst in &mut b.insts {
            inst.args
                .iter_mut()
                .filter(|a| **a == old)
                .for_each(|a| *a = k);
        }
        b.term.for_each_use_mut(|v| {
            if *v == old {
                *v = k;
            }
        });
        if matches!(b.term, Term::Ret(_)) {
            b.insts.push(Inst {
                op: Op::Drop,
                args: vec![k],
                imm: Imm::None,
                res: None,
                loc: b.term_loc,
            });
        }
    }
    f.blocks[0].insts.insert(
        0,
        Inst {
            op: Op::ClosureNew,
            args: cap_values,
            imm: Imm::Func(g),
            res: Some(k),
            loc,
        },
    );
    f
}

/// Removes depth accounting from functions that cannot be part of a recursive cycle.
/// Indirect calls (closures, interfaces, runtime callbacks) may reach any closure or
/// method function, so they are edges to all of them.
fn strip_depth(m: &mut Module) -> bool {
    let indirect_targets: Vec<usize> = m
        .funcs
        .iter()
        .enumerate()
        .filter(|(_, f)| !matches!(f.kind, FuncKind::Normal))
        .map(|(i, _)| i)
        .collect();
    let adj: Vec<Vec<usize>> = m
        .funcs
        .iter()
        .map(|f| {
            let mut v = Vec::new();
            let mut indirect = false;
            for i in f.blocks.iter().flat_map(|b| b.insts.iter()) {
                match (i.op, i.imm) {
                    (Op::Call, Imm::Func(g)) => v.push(g.index()),
                    (Op::CallInd | Op::CallMethod | Op::CallRt, _) => indirect = true,
                    _ => {}
                }
            }
            if indirect {
                v.extend(indirect_targets.iter().copied());
            }
            v
        })
        .collect();
    let cyc = cyclic(&adj);
    let mut changed = false;
    for (i, f) in m.funcs.iter_mut().enumerate() {
        if cyc[i] {
            continue;
        }
        for b in &mut f.blocks {
            let before = b.insts.len();
            b.insts
                .retain(|x| !matches!(x.op, Op::DepthEnter | Op::DepthLeave));
            changed |= b.insts.len() != before;
        }
    }
    changed
}

/// Removes functions no root can reach and renumbers the rest.
fn remove_dead(m: &mut Module) -> bool {
    let mut live = vec![false; m.funcs.len()];
    let mut stack: Vec<usize> = m.entry.iter().map(|e| e.index()).collect();
    stack.extend(
        m.funcs
            .iter()
            .enumerate()
            .filter(|(_, f)| f.linkage == Linkage::Export)
            .map(|(i, _)| i),
    );
    stack.extend(
        m.vtables
            .iter()
            .flat_map(|v| v.methods.iter().map(|f| f.index())),
    );
    stack.extend(
        m.desc_glue
            .iter()
            .flat_map(|(_, eq, hash)| [eq.index(), hash.index()]),
    );
    stack.extend(m.shared_close.iter().map(|(_, f)| f.index()));
    if stack.is_empty() {
        return false;
    }
    while let Some(i) = stack.pop() {
        if std::mem::replace(&mut live[i], true) {
            continue;
        }
        for inst in m.funcs[i].blocks.iter().flat_map(|b| b.insts.iter()) {
            if let Imm::Func(g) = inst.imm {
                stack.push(g.index());
            }
        }
        stack.extend(m.funcs[i].capture_closers.iter().map(|(_, g)| g.index()));
    }
    if live.iter().all(|l| *l) {
        return false;
    }
    let mut map = vec![u32::MAX; live.len()];
    let mut next = 0;
    for (i, l) in live.iter().enumerate() {
        if *l {
            map[i] = next;
            next += 1;
        }
    }
    let funcs = std::mem::take(&mut m.funcs);
    m.funcs = funcs
        .into_iter()
        .enumerate()
        .filter(|(i, _)| live[*i])
        .map(|(_, f)| f)
        .collect();
    for inst in m
        .funcs
        .iter_mut()
        .flat_map(|f| f.blocks.iter_mut())
        .flat_map(|b| b.insts.iter_mut())
    {
        if let Imm::Func(g) = inst.imm {
            inst.imm = Imm::Func(FuncId(map[g.index()]));
        }
    }
    for (_, g) in m
        .funcs
        .iter_mut()
        .flat_map(|f| f.capture_closers.iter_mut())
    {
        *g = FuncId(map[g.index()]);
    }
    for g in m.vtables.iter_mut().flat_map(|v| v.methods.iter_mut()) {
        *g = FuncId(map[g.index()]);
    }
    for (_, eq, hash) in &mut m.desc_glue {
        *eq = FuncId(map[eq.index()]);
        *hash = FuncId(map[hash.index()]);
    }
    for (_, f) in &mut m.shared_close {
        *f = FuncId(map[f.index()]);
    }
    m.entry = m.entry.map(|e| FuncId(map[e.index()]));
    true
}
