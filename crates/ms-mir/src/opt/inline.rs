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
    Mode, Module, Op, Scope, Target, Term, Value,
};
use crate::types::Ty;
use std::collections::HashSet;

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

/// Runs the pass over the whole module; returns whether anything changed.
pub fn run(m: &mut Module) -> bool {
    let mut changed = inline_calls(m);
    changed |= strip_depth(m);
    changed |= remove_dead(m);
    changed
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

fn const_values(f: &Func) -> HashSet<Value> {
    f.blocks
        .iter()
        .flat_map(|b| b.insts.iter())
        .filter(|i| matches!(i.op, Op::IConst | Op::FConst | Op::BConst))
        .filter_map(|i| i.res)
        .collect()
}

fn inline_into(m: &mut Module, fi: usize, cyc: &[bool], sites: &[usize]) -> bool {
    let budget = m.funcs[fi].inst_count() * GROWTH_FACTOR + GROWTH_SLACK;
    let mut grown = 0usize;
    let mut changed = false;
    let mut work: Vec<usize> = (0..m.funcs[fi].blocks.len()).collect();
    while let Some(bi) = work.pop() {
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
                    let consts = const_values(&m.funcs[fi]);
                    limit +=
                        CONST_ARG_BONUS * inst.args.iter().filter(|a| consts.contains(a)).count();
                    size <= limit && grown + size <= budget
                }
            };
            if !ok {
                continue;
            }
            grown += size;
            let callee = m.funcs[gi].clone();
            let ret_own = m.needs_drop(callee.ret);
            let cont = inline_at(&mut m.funcs[fi], bi, ii, &callee, ret_own);
            work.push(cont);
            changed = true;
            // The rest of this block now lives in `cont`.
            break;
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
    for g in m.vtables.iter_mut().flat_map(|v| v.methods.iter_mut()) {
        *g = FuncId(map[g.index()]);
    }
    for (_, eq, hash) in &mut m.desc_glue {
        *eq = FuncId(map[eq.index()]);
        *hash = FuncId(map[hash.index()]);
    }
    m.entry = m.entry.map(|e| FuncId(map[e.index()]));
    true
}
