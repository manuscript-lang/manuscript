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

use cranelift_codegen::entity::EntityRef;
use cranelift_codegen::ir::{self, Function, InstructionData, Opcode, StackSlot};

/// Merges the block-confined slots of `temps` in `func`. Facts about slots, values and blocks sit
/// in vectors indexed by their entity numbers: the pass visits every instruction, so a lookup is
/// one bounds check rather than a hash.
pub fn share(func: &mut Function, temps: &[StackSlot]) {
    if temps.len() < 2 {
        return;
    }
    let slots = func.sized_stack_slots.len();
    let mut candidate = vec![false; slots];
    for t in temps {
        candidate[t.index()] = true;
    }
    let mut block_of: Vec<Option<ir::Block>> = vec![None; slots];
    let mut order: Vec<(ir::Block, StackSlot)> = Vec::new();
    let mut bad = vec![false; slots];
    // Address values and the slot each one points into.
    let mut addr: Vec<Option<StackSlot>> = vec![None; func.dfg.num_values()];
    let blocks: Vec<ir::Block> = func.layout.blocks().collect();
    for &block in &blocks {
        for inst in func.layout.block_insts(block) {
            if let InstructionData::StackAddr { stack_slot, .. } = func.dfg.insts[inst]
                && candidate[stack_slot.index()]
            {
                addr[func.dfg.first_result(inst).index()] = Some(stack_slot);
                match block_of[stack_slot.index()] {
                    None => {
                        block_of[stack_slot.index()] = Some(block);
                        order.push((block, stack_slot));
                    }
                    Some(b) if b != block => bad[stack_slot.index()] = true,
                    _ => {}
                }
            }
        }
    }
    if order.is_empty() {
        return;
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
                    .find_map(|v| addr[v.index()]);
                if let Some(slot) = slot {
                    let res = func.dfg.first_result(inst);
                    if addr[res.index()].replace(slot).is_none() {
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
            if matches!(op, Opcode::StackAddr) {
                continue;
            }
            let args = func.dfg.inst_args(inst);
            for v in func.dfg.inst_values(inst) {
                let Some(slot) = addr[v.index()] else {
                    continue;
                };
                let in_args = args.contains(&v);
                let ok = in_args
                    && block_of[slot.index()] == Some(block)
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
                if !ok {
                    bad[slot.index()] = true;
                }
            }
        }
    }
    // The k-th confined slot of each block shares storage with the k-th of the others.
    let mut rank = vec![0usize; func.dfg.num_blocks()];
    let mut colors: Vec<StackSlot> = Vec::new();
    let mut remap: Vec<Option<StackSlot>> = vec![None; slots];
    let mut merged: Vec<StackSlot> = Vec::new();
    for (block, slot) in order {
        if bad[slot.index()] {
            continue;
        }
        let k = &mut rank[block.index()];
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
            remap[slot.index()] = Some(color);
            merged.push(slot);
        }
    }
    if merged.is_empty() {
        return;
    }
    let mut insts: Vec<ir::Inst> = Vec::new();
    for &block in &blocks {
        insts.clear();
        insts.extend(func.layout.block_insts(block));
        for &inst in &insts {
            if let InstructionData::StackAddr { stack_slot, .. } = &mut func.dfg.insts[inst]
                && let Some(to) = remap[stack_slot.index()]
            {
                *stack_slot = to;
            }
        }
    }
    for slot in merged {
        func.sized_stack_slots[slot].size = 0;
    }
}
