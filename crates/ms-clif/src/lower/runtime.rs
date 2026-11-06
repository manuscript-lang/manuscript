//! Cranelift lowering of runtime-service instructions: polling, cleanup stack, globals.
//!
//! Each function handles one op family; [`Lower::lower_inst`] routes to it.

use super::*;

impl<'a, 'm> Lower<'a, 'm> {
    /// Runtime services: polling, cleanup stack, globals.
    pub(super) fn runtime_services(&mut self, f: &Func, inst: &Inst) -> Vs {
        let m = self.g.m;
        match inst.op {
            Op::FuncAddr => {
                let Imm::Func(g) = inst.imm else {
                    unreachable!()
                };
                let r = self.fref(self.g.funcs[g.index()]);
                vec![self.b.ins().func_addr(types::I64, r)]
            }
            Op::TypeDesc => {
                let Imm::Ty(t) = inst.imm else { unreachable!() };
                vec![self.typedesc_addr(t)]
            }
            Op::Poll => {
                if self.g.opts.poll {
                    let hdr = self.task_hdr();
                    let addr = self.add_imm(hdr, ISOLATE_HDR_CANCEL);
                    let v = self.b.ins().atomic_load(types::I8, flags(), addr);
                    self.fault_if(v, "msrt_cancelled", vec![]);
                }
                vec![]
            }
            Op::DepthEnter => {
                self.depth_enter();
                vec![]
            }
            Op::DepthLeave => vec![],
            Op::CleanupPush => {
                let Imm::Func(c) = inst.imm else {
                    unreachable!()
                };
                let ty = f.ty(inst.args[0]);
                let leaves = self.g.lay.leaves(ty);
                let v = self.a(inst, 0);
                let thunk = self.g.glue(Glue::CleanupThunk(c.0), Ty::UNIT);
                if !self.g.m.funcs[c.index()].unwind_only {
                    let slot = self.spill(&v, &leaves);
                    let r = self.fref(thunk);
                    let fa = self.b.ins().func_addr(types::I64, r);
                    self.rt_call("msrt_cleanup_push", &[fa, slot])
                } else {
                    // A closer that only acts while a guarded task unwinds: with no guard open the
                    // registration is skipped, and its handle 0 makes the discard a no-op.
                    let hdr = self.task_hdr();
                    let guarded =
                        self.b
                            .ins()
                            .load(types::I8, flags(), hdr, ISOLATE_HDR_GUARDED as i32);
                    let none = self.iconst(0);
                    let push = self.b.create_block();
                    let join = self.b.create_block();
                    self.b.append_block_param(join, types::I64);
                    self.b.ins().brif(guarded, push, &[], join, &[none.into()]);
                    self.b.switch_to_block(push);
                    let slot = self.spill(&v, &leaves);
                    let r = self.fref(thunk);
                    let fa = self.b.ins().func_addr(types::I64, r);
                    let h = self.rt_call("msrt_cleanup_push", &[fa, slot])[0];
                    self.b.ins().jump(join, &[h.into()]);
                    self.b.switch_to_block(join);
                    self.b.block_params(join).to_vec()
                }
            }
            Op::CleanupRun => {
                let h = self.a(inst, 0)[0];
                self.rt_call("msrt_cleanup_run", &[h]);
                vec![]
            }
            Op::GlobalGet | Op::GlobalSet => {
                let Imm::Global(gi) = inst.imm else {
                    unreachable!()
                };
                let ty = m.globals[gi.index()].ty;
                let leaves = self.g.lay.leaves(ty);
                let addr = self.data_addr(self.g.globals[gi.index()]);
                if inst.op == Op::GlobalGet {
                    self.load_leaves(addr, 0, &leaves)
                } else {
                    if m.needs_drop(ty) {
                        let old = self.load_leaves(addr, 0, &leaves);
                        self.drop_value(ty, &old);
                    }
                    let v = self.a(inst, 0);
                    self.store_leaves(addr, 0, &leaves, &v);
                    vec![]
                }
            }
            _ => unreachable!("runtime_services is only called for its own ops"),
        }
    }
}
