//! Cranelift lowering of runtime-service instructions: polling, cleanup stack, globals.
//!
//! Each function handles one op family; [`Lower::lower_inst`] routes to it.

use super::*;

impl<'a, 'm> Lower<'a, 'm> {
    /// Pushes the cleanup `action(arg)` on the task's stack and returns its handle: a store pair and
    /// a length bump while the buffer has room, `msrt_cleanup_push` (which grows it) when full.
    pub(super) fn cleanup_push(&mut self, action: Value, arg: Value) -> Vs {
        let hdr = self.task_hdr();
        let len = self
            .b
            .ins()
            .load(types::I64, flags(), hdr, ISOLATE_HDR_CLEANUPS_LEN as i32);
        let cap = self
            .b
            .ins()
            .load(types::I64, flags(), hdr, ISOLATE_HDR_CLEANUPS_CAP as i32);
        let full = self.b.ins().icmp(IntCC::Equal, len, cap);
        let fast = self.b.create_block();
        let slow = self.b.create_block();
        let join = self.b.create_block();
        self.b.append_block_param(join, types::I64);
        self.b.set_cold_block(slow);
        self.b.ins().brif(full, slow, &[], fast, &[]);
        self.b.switch_to_block(fast);
        let buf = self
            .b
            .ins()
            .load(types::I64, flags(), hdr, ISOLATE_HDR_CLEANUPS as i32);
        let off = self.b.ins().ishl_imm_s(len, 4);
        let at = self.b.ins().iadd(buf, off);
        self.b.ins().store(flags(), action, at, 0);
        self.b.ins().store(flags(), arg, at, 8);
        let next = self.b.ins().iadd_imm_s(len, 1);
        self.b
            .ins()
            .store(flags(), next, hdr, ISOLATE_HDR_CLEANUPS_LEN as i32);
        self.b.ins().jump(join, &[next.into()]);
        self.b.switch_to_block(slow);
        let h = self.rt_call("msrt_cleanup_push", &[action, arg])[0];
        self.b.ins().jump(join, &[h.into()]);
        self.b.switch_to_block(join);
        self.b.block_params(join).to_vec()
    }

    /// Discards the entries from `handle` up: a length store when the entry below is live, the
    /// runtime call (which also prunes retired entries) otherwise.
    pub(super) fn cleanup_discard(&mut self, handle: Value) {
        let hdr = self.task_hdr();
        let len = self
            .b
            .ins()
            .load(types::I64, flags(), hdr, ISOLATE_HDR_CLEANUPS_LEN as i32);
        let slow = self.b.create_block();
        let check = self.b.create_block();
        let fast = self.b.create_block();
        let done = self.b.create_block();
        self.b.set_cold_block(slow);
        let enough = self
            .b
            .ins()
            .icmp(IntCC::UnsignedGreaterThanOrEqual, len, handle);
        self.b.ins().brif(enough, check, &[], slow, &[]);
        self.b.switch_to_block(check);
        // The entry below the handle must not be a retired one (action 0), which the runtime prunes.
        let one = self.iconst(1);
        let first = self.b.ins().icmp(IntCC::Equal, handle, one);
        let below = self.b.create_block();
        self.b.ins().brif(first, fast, &[], below, &[]);
        self.b.switch_to_block(below);
        let buf = self
            .b
            .ins()
            .load(types::I64, flags(), hdr, ISOLATE_HDR_CLEANUPS as i32);
        let idx = self.b.ins().iadd_imm_s(handle, -2);
        let off = self.b.ins().ishl_imm_s(idx, 4);
        let at = self.b.ins().iadd(buf, off);
        let action = self.b.ins().load(types::I64, flags(), at, 0);
        self.b.ins().brif(action, fast, &[], slow, &[]);
        self.b.switch_to_block(fast);
        let new_len = self.b.ins().iadd_imm_s(handle, -1);
        self.b
            .ins()
            .store(flags(), new_len, hdr, ISOLATE_HDR_CLEANUPS_LEN as i32);
        self.b.ins().jump(done, &[]);
        self.b.switch_to_block(slow);
        self.rt_call("msrt_cleanup_discard", &[handle]);
        self.b.ins().jump(done, &[]);
        self.b.switch_to_block(done);
    }

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
                unreachable!("ms_mir::depth lowers depth.enter before code generation")
            }
            Op::DepthLeave => vec![],
            Op::StackLow => vec![self.stack_below(0)],
            Op::StackNear => {
                let Imm::Int(h) = inst.imm else {
                    unreachable!()
                };
                vec![self.stack_below(h)]
            }
            Op::CleanupPush => {
                let Imm::Func(c) = inst.imm else {
                    unreachable!()
                };
                let ty = f.ty(inst.args[0]);
                let leaves = self.g.lay.leaves(ty);
                let v = self.a(inst, 0);
                let thunk = self.g.glue(Glue::CleanupThunk(c.0), Ty::VOID);
                if !self.g.m.funcs[c.index()].unwind_only {
                    let slot = self.spill(&v, &leaves);
                    let r = self.fref(thunk);
                    let fa = self.b.ins().func_addr(types::I64, r);
                    self.cleanup_push(fa, slot)
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
                    let h = self.cleanup_push(fa, slot)[0];
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
