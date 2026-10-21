//! Spills values that are live across a loop but never used in one.
//!
//! The register allocator keeps a value in a register for its whole live range unless
//! pressure forces a split, and it splits badly around loops: a few values that are only
//! needed after a loop (a timestamp, the capacity of a list) end up shuffled through
//! registers or reloaded from and stored to the stack on every iteration. Storing such a
//! value once after its definition and loading it before each use outside every loop keeps
//! the loop body to the values it computes with.
//!
//! A value qualifies when it is live into a loop header, is neither defined nor used in
//! that loop, and the header has more live values than the callee-saved registers can
//! hold. Every use outside a loop that contains the definition becomes a load. A value
//! defined by an earlier loop (a list that was just built) is stored in that loop after
//! each definition; uses inside that loop keep the register. Constants and addresses are
//! skipped because they are rematerialized.

use cranelift_codegen::cursor::{Cursor, FuncCursor};
use cranelift_codegen::dominator_tree::DominatorTree;
use cranelift_codegen::entity::EntityRef;
use cranelift_codegen::flowgraph::ControlFlowGraph;
use cranelift_codegen::ir::{
    self, Block, Function, Inst, InstBuilder, Opcode, StackSlotData, StackSlotKind, Value, ValueDef,
};
use cranelift_codegen::loop_analysis::LoopAnalysis;
use std::collections::HashMap;

/// A loop header with fewer live values than this stays as the register allocator left it.
const MIN_LIVE_AT_HEADER: usize = 4;

/// Whether `inst` is cheap to recompute, so the allocator rematerializes its result.
fn rematerialized(func: &Function, inst: Inst) -> bool {
    matches!(
        func.dfg.insts[inst].opcode(),
        Opcode::Iconst
            | Opcode::F32const
            | Opcode::F64const
            | Opcode::SymbolValue
            | Opcode::StackAddr
            | Opcode::FuncAddr
    )
}

struct Bits {
    words: Vec<u64>,
}

impl Bits {
    fn new(n: usize) -> Bits {
        Bits {
            words: vec![0; n.div_ceil(64)],
        }
    }

    fn set(&mut self, i: usize) {
        self.words[i / 64] |= 1 << (i % 64);
    }

    fn get(&self, i: usize) -> bool {
        (self.words[i / 64] >> (i % 64)) & 1 != 0
    }

    fn count(&self) -> usize {
        self.words.iter().map(|w| w.count_ones() as usize).sum()
    }

    /// ORs `other & !mask` into `self`, returning whether `self` changed.
    fn union_without(&mut self, other: &Bits, mask: &Bits) -> bool {
        let mut changed = false;
        for ((a, b), m) in self.words.iter_mut().zip(&other.words).zip(&mask.words) {
            let n = *a | (*b & !*m);
            changed |= n != *a;
            *a = n;
        }
        changed
    }
}

/// Spills loop-cold values of `func` (see the module documentation).
pub fn spill_loop_cold(func: &mut Function) {
    let cfg = ControlFlowGraph::with_function(func);
    let domtree = DominatorTree::with_function(func, &cfg);
    let mut loops = LoopAnalysis::new();
    loops.compute(func, &cfg, &domtree);
    if loops.loops().next().is_none() {
        return;
    }
    let blocks: Vec<Block> = func.layout.blocks().collect();
    let index: HashMap<Block, usize> = blocks.iter().enumerate().map(|(i, b)| (*b, i)).collect();
    let nvals = func.dfg.num_values();

    // Definitions per block, and which results are cheap to recompute.
    let mut defs: Vec<Bits> = Vec::with_capacity(blocks.len());
    let mut remat = vec![false; nvals];
    let mut def_block = vec![0usize; nvals];
    for (i, &b) in blocks.iter().enumerate() {
        let mut bits = Bits::new(nvals);
        for &p in func.dfg.block_params(b) {
            bits.set(p.index());
            def_block[p.index()] = i;
        }
        for inst in func.layout.block_insts(b) {
            let cheap = rematerialized(func, inst);
            for &r in func.dfg.inst_results(inst) {
                bits.set(r.index());
                remat[r.index()] = cheap;
                def_block[r.index()] = i;
            }
        }
        defs.push(bits);
    }

    // Liveness: upward-exposed uses per block, propagated to a fixpoint.
    let mut live_in: Vec<Bits> = Vec::with_capacity(blocks.len());
    let mut use_blocks: Vec<Vec<usize>> = vec![Vec::new(); nvals];
    for (i, &b) in blocks.iter().enumerate() {
        let mut bits = Bits::new(nvals);
        for inst in func.layout.block_insts(b) {
            for v in func.dfg.inst_values(inst) {
                if use_blocks[v.index()].last() != Some(&i) {
                    use_blocks[v.index()].push(i);
                }
                if !defs[i].get(v.index()) {
                    bits.set(v.index());
                }
            }
        }
        live_in.push(bits);
    }
    let mut changed = true;
    while changed {
        changed = false;
        for (i, &b) in blocks.iter().enumerate().rev() {
            for succ in cfg.succ_iter(b) {
                let j = index[&succ];
                if j == i {
                    continue;
                }
                let (src, dst) = if j < i {
                    let (lo, hi) = live_in.split_at_mut(i);
                    (&lo[j], &mut hi[0])
                } else {
                    let (lo, hi) = live_in.split_at_mut(j);
                    (&hi[0], &mut lo[i])
                };
                changed |= dst.union_without(src, &defs[i]);
            }
        }
    }

    // Values live into a crowded loop header and untouched by that loop. Uses that sit in
    // a loop not containing the definition would turn into per-iteration loads, so such a
    // value is left alone.
    let enclosing = |b: Block| {
        let mut chain = Vec::new();
        let mut next = loops.innermost_loop(b);
        while let Some(l) = next {
            chain.push(l);
            next = loops.loop_parent(l);
        }
        chain
    };
    let mut spill = vec![false; nvals];
    let mut any = false;
    for l in loops.loops() {
        let h = loops.loop_header(l);
        let live = &live_in[index[&h]];
        if live.count() < MIN_LIVE_AT_HEADER {
            continue;
        }
        for v in 0..nvals {
            if !live.get(v) || remat[v] || spill[v] {
                continue;
            }
            if loops.is_in_loop(blocks[def_block[v]], l) {
                continue;
            }
            let around_def = enclosing(blocks[def_block[v]]);
            let cold = use_blocks[v].iter().all(|&u| {
                let ub = blocks[u];
                !loops.is_in_loop(ub, l) && enclosing(ub).iter().all(|x| around_def.contains(x))
            });
            if cold {
                spill[v] = true;
                any = true;
            }
        }
    }
    if !any {
        return;
    }

    // Rewrite uses first (so the stores below keep the original value), then store after
    // each definition.
    let mut slots: HashMap<Value, ir::StackSlot> = HashMap::new();
    for &b in &blocks {
        let insts: Vec<Inst> = func.layout.block_insts(b).collect();
        for inst in insts {
            let used: Vec<Value> = {
                let mut seen = Vec::new();
                for v in func.dfg.inst_values(inst) {
                    let direct = loops
                        .innermost_loop(blocks[def_block[v.index()]])
                        .is_some_and(|dl| loops.is_in_loop(b, dl));
                    if spill[v.index()] && !direct && !seen.contains(&v) {
                        seen.push(v);
                    }
                }
                seen
            };
            if used.is_empty() {
                continue;
            }
            let loc = func.srcloc(inst);
            let mut replace: HashMap<Value, Value> = HashMap::new();
            for v in used {
                let ty = func.dfg.value_type(v);
                let slot = *slots.entry(v).or_insert_with(|| {
                    func.create_sized_stack_slot(StackSlotData::new(
                        StackSlotKind::ExplicitSlot,
                        ty.bytes().max(8),
                        3,
                    ))
                });
                let mut pos = FuncCursor::new(func).at_inst(inst);
                pos.set_srcloc(loc);
                replace.insert(v, pos.ins().stack_load(ir::types::I64, ty, slot, 0));
            }
            func.dfg
                .map_inst_values(inst, |v| *replace.get(&v).unwrap_or(&v));
        }
    }
    let mut stored: Vec<(Value, ir::StackSlot)> = slots.into_iter().collect();
    stored.sort_by_key(|(v, _)| v.index());
    for (v, slot) in stored {
        let def = func.dfg.value_def(v);
        let loc = match def {
            ValueDef::Result(inst, _) => func.srcloc(inst),
            _ => ir::SourceLoc::default(),
        };
        let mut pos = match def {
            ValueDef::Result(inst, _) => FuncCursor::new(func).after_inst(inst),
            ValueDef::Param(block, _) => FuncCursor::new(func).at_first_insertion_point(block),
            ValueDef::Union(..) => continue,
        };
        pos.set_srcloc(loc);
        pos.ins().stack_store(ir::types::I64, v, slot, 0);
    }
}
