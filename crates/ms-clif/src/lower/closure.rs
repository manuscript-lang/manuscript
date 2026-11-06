//! Cranelift lowering of closure, interface view and call instructions.
//!
//! Each function handles one op family; [`Lower::lower_inst`] routes to it.

use super::*;

impl<'a, 'm> Lower<'a, 'm> {
    /// Closures and interface views.
    pub(super) fn closures_and_interfaces(&mut self, f: &Func, inst: &Inst) -> Vs {
        match inst.op {
            Op::ClosureNew => self.closure_new(inst),
            Op::ClosureCap => {
                let Imm::Idx(i) = inst.imm else {
                    unreachable!()
                };
                let ms_mir::ir::FuncKind::Closure { captures } = &f.kind else {
                    unreachable!()
                };
                let mut off = CLOSURE_CAPTURES as i64;
                let mut found = (0, Vec::new());
                for (k, c) in captures.iter().enumerate() {
                    let leaves = self.g.lay.leaves(*c);
                    let lay = mem_layout(&leaves);
                    off = (off + lay.align as i64 - 1) / lay.align as i64 * lay.align as i64;
                    if k == i as usize {
                        found = (off, leaves);
                    }
                    off += lay.size as i64;
                }
                let env = self.a(inst, 0)[0];
                self.load_leaves(env, found.0, &found.1)
            }
            Op::ClosureCapAddr => {
                let Imm::Idx(i) = inst.imm else {
                    unreachable!()
                };
                let ms_mir::ir::FuncKind::Closure { captures } = &f.kind else {
                    unreachable!()
                };
                let mut off = CLOSURE_CAPTURES as i64;
                let mut found = 0;
                for (k, c) in captures.iter().enumerate() {
                    let leaves = self.g.lay.leaves(*c);
                    let lay = mem_layout(&leaves);
                    off = (off + lay.align as i64 - 1) / lay.align as i64 * lay.align as i64;
                    if k == i as usize {
                        found = off;
                    }
                    off += lay.size as i64;
                }
                let env = self.a(inst, 0)[0];
                vec![self.b.ins().iadd_imm_s(env, found)]
            }
            Op::IfaceNew => {
                let Imm::Vtable(vt) = inst.imm else {
                    unreachable!()
                };
                let ty = f.ty(inst.args[0]);
                let leaves = self.g.lay.leaves(ty);
                let size = mem_layout(&leaves).size as i64;
                let blk = self.alloc(size);
                let v = self.a(inst, 0);
                self.store_leaves(blk, 0, &leaves, &v);
                let id = self.g.vtables[vt.index()];
                let addr = self.data_addr(id);
                vec![blk, addr]
            }
            Op::IfaceBorrow => {
                // A box holding the borrowed leaves as they are; the tag says only the box is
                // freed.
                let Imm::Vtable(vt) = inst.imm else {
                    unreachable!()
                };
                let ty = f.ty(inst.args[0]);
                let leaves = self.g.lay.leaves(ty);
                let size = mem_layout(&leaves).size as i64;
                let blk = self.alloc(size);
                let v = self.a(inst, 0);
                self.store_leaves(blk, 0, &leaves, &v);
                let id = self.g.vtables[vt.index()];
                let addr = self.data_addr(id);
                vec![blk, self.b.ins().bor_imm_s(addr, 1)]
            }
            Op::IfaceView => {
                let v = self.a(inst, 0);
                let vt = self.b.ins().band_imm_s(v[1], !3);
                vec![v[0], self.b.ins().bor_imm_s(vt, 2)]
            }
            Op::IfaceData => vec![self.a(inst, 0)[0]],
            Op::IfaceIs => {
                let Imm::Vtable(vt) = inst.imm else {
                    unreachable!()
                };
                let have = self.a(inst, 0)[1];
                let have = self.b.ins().band_imm_s(have, !3);
                let id = self.g.vtables[vt.index()];
                let want = self.data_addr(id);
                vec![self.b.ins().icmp(IntCC::Equal, have, want)]
            }
            _ => unreachable!("closures_and_interfaces is only called for its own ops"),
        }
    }

    /// Calls.
    pub(super) fn calls(&mut self, f: &Func, inst: &Inst) -> Vs {
        match inst.op {
            Op::Call => {
                let Imm::Func(c) = inst.imm else {
                    unreachable!()
                };
                let args: Vs = (0..inst.args.len()).flat_map(|i| self.a(inst, i)).collect();
                let id = self.g.funcs[c.index()];
                self.call_id(id, &args)
            }
            Op::CallInd => self.call_closure(f, inst),
            Op::CallMethod => self.call_method(inst),
            Op::CallRt => self.call_extern(f, inst),
            _ => unreachable!("calls is only called for its own ops"),
        }
    }
}
