//! Cranelift lowering of ownership and raw-memory instructions.
//!
//! Each function handles one op family; [`Lower::lower_inst`] routes to it.

use super::*;

impl<'a, 'm> Lower<'a, 'm> {
    /// Ownership: move, clone, drop.
    pub(super) fn ownership(&mut self, f: &Func, inst: &Inst) -> Vs {
        match inst.op {
            Op::MoveOut => self.a(inst, 0),
            Op::Clone => {
                let ty = f.ty(inst.args[0]);
                let v = self.a(inst, 0);
                self.clone_value(ty, &v)
            }
            Op::Drop => {
                let ty = f.ty(inst.args[0]);
                let v = self.a(inst, 0);
                self.drop_value(ty, &v);
                vec![]
            }
            Op::DropIf => {
                let ty = f.ty(inst.args[1]);
                let flag = self.a(inst, 0)[0];
                let v = self.a(inst, 1);
                self.if_then(flag, |s| s.drop_value(ty, &v));
                vec![]
            }
            _ => unreachable!("ownership is only called for its own ops"),
        }
    }

    /// Raw memory: stack slots, pointers, loads and stores.
    pub(super) fn memory(&mut self, f: &Func, inst: &Inst) -> Vs {
        let m = self.g.m;
        match inst.op {
            Op::Slot => {
                let Imm::Ty(ty) = inst.imm else {
                    unreachable!()
                };
                let lay = self.g.lay.mem(ty);
                let slot = self.b.create_sized_stack_slot(StackSlotData::new(
                    StackSlotKind::ExplicitSlot,
                    lay.size.max(8),
                    3,
                ));
                if let Some(r) = inst.res {
                    self.slot_of.insert(r.index(), slot);
                    self.slot_blk.insert(r.index(), self.cur);
                }
                vec![self.b.ins().stack_addr(types::I64, slot, 0)]
            }
            Op::ListAddr | Op::ListAddrU => {
                let lt = f.ty(inst.args[0]);
                let (_, _, size) = self.elem_info(lt);
                let l = self.a(inst, 0);
                let i = self.a(inst, 1)[0];
                let mode = if inst.op == Op::ListAddr {
                    Op::ListGet
                } else {
                    Op::ListGetU
                };
                vec![self.elem_addr(l[0], l[1], i, size, mode)]
            }
            Op::PtrIsNull => {
                let p = self.a(inst, 0)[0];
                vec![self.b.ins().icmp_imm_s(IntCC::Equal, p, 0)]
            }
            Op::PtrField => {
                let Imm::Field(r, i) = inst.imm else {
                    unreachable!()
                };
                let rty = m.types.find(&TyKind::Type(r)).expect("type interned");
                let (fty, at, _) = self.fields_of(rty)[i as usize];
                if let Some(block) = self.type_block(rty) {
                    // The argument addresses the type's pointer.
                    let held = self.a(inst, 0)[0];
                    let p = self.b.ins().load(types::I64, flags(), held, 0);
                    let (bk, _) = self.type_block_fields(rty)[i as usize];
                    let off = mem_layout(&block).offsets[bk] as i64;
                    let slot = self.add_imm(p, off);
                    if self.g.lay.type_field_boxed(fty) {
                        return vec![self.map_header_ensure(slot)];
                    }
                    return vec![slot];
                }
                let lay = mem_layout(&self.g.lay.leaves(rty));
                let off = lay.offsets.get(at).copied().unwrap_or(0) as i64;
                // The result is read and written with the field's own layout, so each of its
                // leaves must sit at the same distance from the field's address as in the field.
                debug_assert!(
                    {
                        let own = mem_layout(&self.g.lay.leaves(fty));
                        own.offsets
                            .iter()
                            .enumerate()
                            .all(|(k, o)| lay.offsets[at + k] - lay.offsets[at] == *o)
                    },
                    "field {i} of type {r:?} is laid out differently inside the type"
                );
                let p = self.a(inst, 0)[0];
                vec![self.add_imm(p, off)]
            }
            Op::Load | Op::Take => {
                let Imm::Ty(ty) = inst.imm else {
                    unreachable!()
                };
                let leaves = self.g.lay.leaves(ty);
                let p = self.a(inst, 0)[0];
                let out = self.load_leaves(p, 0, &leaves);
                if inst.op == Op::Take
                    && self.is_wide(ty)
                    && let Some(r) = inst.res
                {
                    self.homes[r.index()] = Some(Home {
                        addr: p,
                        slot: self.slot_of.get(&inst.args[0].index()).copied(),
                        blk: Some(self.cur),
                    });
                }
                out
            }
            Op::Store | Op::Put => {
                let ty = f.ty(inst.args[1]);
                let (dst, src) = (inst.args[0].index(), inst.args[1]);
                // A wide value moving into a fresh slot just adopts the memory it already lives in.
                if inst.op == Op::Put
                    && self.is_wide(ty)
                    && !self.used[dst]
                    && self.slot_blk.get(&dst) == Some(&self.cur)
                    && let Some(h) = self.home_of(src)
                {
                    self.vals[dst] = vec![h.addr];
                    match h.slot {
                        Some(s) => self.slot_of.insert(dst, s),
                        None => self.slot_of.remove(&dst),
                    };
                    return vec![];
                }
                let leaves = self.g.lay.leaves(ty);
                let (p, v) = (self.a(inst, 0)[0], self.a(inst, 1));
                self.store_leaves(p, 0, &leaves, &v);
                vec![]
            }
            _ => unreachable!("memory is only called for its own ops"),
        }
    }
}
