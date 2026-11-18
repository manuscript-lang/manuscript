//! Which stack slots of a function live in one block only.
//!
//! A `slot` whose address is formed, offset, loaded through, stored through and passed to calls
//! inside one block, and whose first access there writes it, holds nothing before that block's
//! first access and nothing after its terminator. The backends may give such a slot's storage
//! to another block's temporary: Cranelift shares by rank, LLVM brackets the block with
//! lifetime markers. Any other slot (its address stored, returned, passed to a block, kept by
//! the runtime, a view result pointing into it, or used in several blocks) keeps its place for
//! the whole function. The answer is a fact about MIR, so both backends take the same slots.

use std::collections::HashMap;

use crate::ir::{Block, Func, Imm, Module, Op, Value};

/// How an instruction touches the slot behind one of its operands.
#[derive(Clone, Copy, PartialEq)]
enum Access {
    /// Reads what the slot holds.
    Read,
    /// Writes the slot; the callee of a call is assumed to fill it.
    Write,
    /// The result is another address into the slot.
    Derive,
    /// The address is kept, returned or handed on: the slot is not confined.
    Escape,
}

fn access(m: &Module, op: Op, imm: Imm, arg: usize) -> Access {
    match (op, arg) {
        (Op::Load | Op::Take | Op::PtrLoadU | Op::BytesPush, 0) => Access::Read,
        (Op::Store | Op::Put | Op::PtrStoreU, 0) => Access::Write,
        (Op::PtrField | Op::PtrAdd, 0) => Access::Derive,
        (Op::Call | Op::CallInd | Op::CallMethod, _) => Access::Write,
        (Op::CallRt, _) => match imm {
            Imm::Ext(e) if !m.pins_slot_argument(&m.externs[e.index()]) => Access::Write,
            _ => Access::Escape,
        },
        _ => Access::Escape,
    }
}

/// The `slot`s of `f` confined to one block, with that block.
pub fn confined(m: &Module, f: &Func) -> HashMap<Value, Block> {
    // Every address derived from a slot maps to it. Blocks need not be in dominance order, so
    // collect the slots first and derive until nothing is new.
    let mut owner: HashMap<Value, Value> = HashMap::new();
    for inst in f.blocks.iter().flat_map(|b| &b.insts) {
        if let (Op::Slot, Some(r)) = (inst.op, inst.res) {
            owner.insert(r, r);
        }
    }
    if owner.is_empty() {
        return HashMap::new();
    }
    loop {
        let before = owner.len();
        for inst in f.blocks.iter().flat_map(|b| &b.insts) {
            let (Some(r), Some(&slot)) = (inst.res, inst.args.first().and_then(|a| owner.get(a)))
            else {
                continue;
            };
            if access(m, inst.op, inst.imm, 0) == Access::Derive {
                owner.entry(r).or_insert(slot);
            }
        }
        if owner.len() == before {
            break;
        }
    }
    struct State {
        block: Block,
        confined: bool,
        written: bool,
    }
    let mut seen: HashMap<Value, State> = HashMap::new();
    for (bi, bd) in f.blocks.iter().enumerate() {
        let here = Block(bi as u32);
        for inst in &bd.insts {
            for (i, a) in inst.args.iter().enumerate() {
                let Some(&slot) = owner.get(a) else { continue };
                let how = match access(m, inst.op, inst.imm, i) {
                    // An address in the value position of an operation is kept or handed on.
                    Access::Derive if i > 0 => Access::Escape,
                    how => how,
                };
                let st = seen.entry(slot).or_insert(State {
                    block: here,
                    confined: true,
                    written: false,
                });
                st.confined &= st.block == here;
                match how {
                    Access::Escape => st.confined = false,
                    // The first access sees whatever the slot held before.
                    Access::Read => st.confined &= st.written,
                    Access::Write => st.written = true,
                    Access::Derive => {}
                }
            }
        }
        bd.term.for_each_use(|v| {
            if let Some(st) = owner.get(&v).and_then(|s| seen.get_mut(s)) {
                st.confined = false;
            }
        });
    }
    seen.into_iter()
        .filter(|(_, st)| st.confined)
        .map(|(slot, st)| (slot, st.block))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::parse::parse_module;

    /// The names of the confined slots of `@t`, as `%n`.
    fn confined_in(body: &str) -> Vec<String> {
        let src = format!("module \"t\"\nfn @t(%p: ptr) -> void export {{\n{body}}}\n");
        let m = parse_module(&src).unwrap();
        let f = &m.funcs[0];
        let mut slots: Vec<String> = confined(&m, f)
            .keys()
            .map(|v| format!("%{}", v.0))
            .collect();
        slots.sort();
        slots
    }

    #[test]
    fn a_slot_written_then_read_in_one_block_is_confined() {
        let got = confined_in(
            "b0:\n  %1: ptr = slot int\n  %2: int = iconst 1\n  store %1, %2\n  %3: int = load int %1\n  ret\n",
        );
        assert_eq!(got, ["%1"]);
    }

    #[test]
    fn a_slot_read_first_is_not_confined() {
        let got = confined_in("b0:\n  %1: ptr = slot int\n  %3: int = load int %1\n  ret\n");
        assert!(got.is_empty());
    }

    #[test]
    fn a_slot_used_in_two_blocks_is_not_confined() {
        let got = confined_in(
            "b0:\n  %1: ptr = slot int\n  %2: int = iconst 1\n  store %1, %2\n  br b1()\nb1():\n  %3: int = load int %1\n  ret\n",
        );
        assert!(got.is_empty());
    }

    #[test]
    fn a_slot_whose_address_is_stored_or_passed_on_is_not_confined() {
        let stored = confined_in(
            "b0:\n  %1: ptr = slot int\n  %2: int = iconst 1\n  store %1, %2\n  store %p, %1\n  ret\n",
        );
        assert!(stored.is_empty());
        let passed = confined_in(
            "b0:\n  %1: ptr = slot int\n  %2: int = iconst 1\n  store %1, %2\n  br b1(%1)\nb1(%4: ptr):\n  ret\n",
        );
        assert!(passed.is_empty());
    }
}
