//! Shares the stack slots of statement-scoped temporaries between blocks.
//!
//! Lowering gives every temporary (an out-parameter of a call, a spilled argument, a string
//! copy) its own slot, so a function with many such statements keeps all of them live for its
//! whole frame, and neither Cranelift nor LLVM (which needs lifetime markers) merges them.
//! A temporary whose address is only formed, offset, loaded through, stored through and passed
//! to calls inside one block cannot be live in another block, and a frame runs one block at a
//! time. The k-th such temporary of every block therefore shares one slot, sized for the
//! largest. Slots whose address is
//! stored, returned or passed along a branch, or that are used in more than one block, keep
//! their own slot.

use cranelift_codegen::ir::{self, Function, InstructionData, Opcode, StackSlot, Value};
use std::collections::{HashMap, HashSet};

/// Merges the block-confined slots of `temps` in `func`.
pub fn share(func: &mut Function, temps: &[StackSlot]) {
    if temps.len() < 2 {
        return;
    }
    let candidate: HashSet<StackSlot> = temps.iter().copied().collect();
    let mut block_of: HashMap<StackSlot, ir::Block> = HashMap::new();
    let mut order: Vec<(ir::Block, StackSlot)> = Vec::new();
    let mut bad: HashSet<StackSlot> = HashSet::new();
    // Address values and the slot each one points into.
    let mut addr: HashMap<Value, StackSlot> = HashMap::new();
    let blocks: Vec<ir::Block> = func.layout.blocks().collect();
    for &block in &blocks {
        for inst in func.layout.block_insts(block) {
            match func.dfg.insts[inst] {
                InstructionData::StackAddr { stack_slot, .. }
                    if candidate.contains(&stack_slot) =>
                {
                    let res = func.dfg.first_result(inst);
                    addr.insert(res, stack_slot);
                    match block_of.get(&stack_slot) {
                        None => {
                            block_of.insert(stack_slot, block);
                            order.push((block, stack_slot));
                        }
                        Some(b) if *b != block => {
                            bad.insert(stack_slot);
                        }
                        _ => {}
                    }
                }
                _ => {}
            }
        }
    }
    // Follow pointer arithmetic, then check every use of an address.
    loop {
        let mut grew = false;
        for &block in &blocks {
            for inst in func.layout.block_insts(block) {
                if !matches!(func.dfg.insts[inst].opcode(), Opcode::Iadd) {
                    continue;
                }
                let slot = func
                    .dfg
                    .inst_args(inst)
                    .iter()
                    .find_map(|v| addr.get(v).copied());
                if let Some(slot) = slot {
                    let res = func.dfg.first_result(inst);
                    if addr.insert(res, slot).is_none() {
                        grew = true;
                    }
                }
            }
        }
        if !grew {
            break;
        }
    }
    for &block in &blocks {
        for inst in func.layout.block_insts(block) {
            let op = func.dfg.insts[inst].opcode();
            let args = func.dfg.inst_args(inst).to_vec();
            if matches!(op, Opcode::StackAddr) {
                continue;
            }
            for (i, v) in func.dfg.inst_values(inst).enumerate() {
                let Some(slot) = addr.get(&v).copied() else {
                    continue;
                };
                let in_args = args.contains(&v);
                let ok = in_args
                    && block_of.get(&slot) == Some(&block)
                    && match op {
                        Opcode::Load | Opcode::Uload8 | Opcode::Uload16 | Opcode::Uload32 => true,
                        Opcode::Sload8 | Opcode::Sload16 | Opcode::Sload32 => true,
                        // Only the address operand (the second) may be ours.
                        Opcode::Store | Opcode::Istore8 | Opcode::Istore16 | Opcode::Istore32 => {
                            args.get(1) == Some(&v) && args.first() != Some(&v)
                        }
                        Opcode::Call | Opcode::CallIndirect => true,
                        Opcode::Iadd => true,
                        _ => false,
                    };
                let _ = i;
                if !ok {
                    bad.insert(slot);
                }
            }
        }
    }
    // The k-th confined slot of each block shares storage with the k-th of the others.
    let mut rank: HashMap<ir::Block, usize> = HashMap::new();
    let mut colors: Vec<StackSlot> = Vec::new();
    let mut remap: HashMap<StackSlot, StackSlot> = HashMap::new();
    for (block, slot) in order {
        if bad.contains(&slot) {
            continue;
        }
        let k = rank.entry(block).or_insert(0);
        let color = match colors.get(*k) {
            Some(c) => *c,
            None => {
                colors.push(slot);
                slot
            }
        };
        *k += 1;
        if color != slot {
            let (size, shift) = {
                let d = &func.sized_stack_slots[slot];
                (d.size, d.align_shift)
            };
            let c = &mut func.sized_stack_slots[color];
            c.size = c.size.max(size);
            c.align_shift = c.align_shift.max(shift);
            remap.insert(slot, color);
        }
    }
    if remap.is_empty() {
        return;
    }
    for &block in &blocks {
        let insts: Vec<_> = func.layout.block_insts(block).collect();
        for inst in insts {
            if let InstructionData::StackAddr { stack_slot, .. } = &mut func.dfg.insts[inst]
                && let Some(to) = remap.get(stack_slot)
            {
                *stack_slot = *to;
            }
        }
    }
    for slot in remap.keys() {
        func.sized_stack_slots[*slot].size = 0;
    }
}
