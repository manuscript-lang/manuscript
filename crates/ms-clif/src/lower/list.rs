//! Lowering of list element access and list-valued instructions.

use super::*;

impl<'a, 'm> Lower<'a, 'm> {
    pub(super) fn elem_info(&self, list_ty: Ty) -> (Ty, Vec<Leaf>, i64) {
        let e = self.g.m.seq_elem(list_ty).unwrap_or(Ty::INT);
        let leaves = self.g.lay.leaves(e);
        let size = mem_layout(&leaves).size as i64;
        (e, leaves, size)
    }

    /// Normalizes `i` (negative counts from the end) and bounds-checks it; returns the element address.
    pub(super) fn elem_addr(
        &mut self,
        ptr: Value,
        len: Value,
        i: Value,
        size: i64,
        mode: Op,
    ) -> Value {
        let idx = match mode {
            Op::ListGet | Op::ListSet | Op::ListFill => {
                let neg = self.b.ins().icmp_imm_s(IntCC::SignedLessThan, i, 0);
                let wrapped = self.b.ins().iadd(i, len);
                self.b.ins().select(neg, wrapped, i)
            }
            _ => i,
        };
        if self.g.opts.checks && !matches!(mode, Op::ListGetU | Op::ListSetU) {
            let oob = self
                .b
                .ins()
                .icmp(IntCC::UnsignedGreaterThanOrEqual, idx, len);
            self.fault_if(oob, "msrt_index_fault", vec![i, len]);
        }
        let off = self.b.ins().imul_imm_s(idx, size);
        self.b.ins().iadd(ptr, off)
    }

    pub(super) fn lower_list(&mut self, f: &Func, inst: &Inst) -> Vs {
        let res_ty = inst.res.map(|r| f.ty(r)).expect("list op result");
        match inst.op {
            Op::ListNew => {
                let (_, _, size) = self.elem_info(res_ty);
                let cap = self.a(inst, 0)[0];
                let join = self.b.create_block();
                self.b.append_block_param(join, types::I64);
                let some = self.b.create_block();
                let null = self.iconst(0);
                self.b
                    .ins()
                    .brif(cap, some, &[], join, &[BlockArg::Value(null)]);
                self.b.switch_to_block(some);
                let bytes = self.b.ins().imul_imm_s(cap, size.max(1));
                let p = self.rt_call("msrt_alloc", &[bytes])[0];
                self.b.ins().jump(join, &[BlockArg::Value(p)]);
                self.b.switch_to_block(join);
                let p = self.b.block_params(join)[0];
                let zero = self.iconst(0);
                vec![p, zero, cap]
            }
            Op::ListLit => {
                let (_, leaves, size) = self.elem_info(res_ty);
                let n = inst.args.len() as i64;
                if n == 0 {
                    let z = self.iconst(0);
                    return vec![z, z, z];
                }
                let p = self.alloc(n * size);
                for i in 0..inst.args.len() {
                    let v = self.a(inst, i);
                    self.store_leaves(p, i as i64 * size, &leaves, &v);
                }
                let nn = self.iconst(n);
                vec![p, nn, nn]
            }
            Op::ListConst => {
                let Imm::Int(i) = inst.imm else {
                    unreachable!()
                };
                let (e, leaves, size) = self.elem_info(res_ty);
                let n = self.g.m.list_consts[i as usize].len() as i64;
                if n == 0 {
                    let z = self.iconst(0);
                    return vec![z, z, z];
                }
                debug_assert_eq!(leaves.len(), 1);
                let data = self.g.list_const(i as usize, e);
                let src = self.data_addr(data);
                let p = self.alloc(n * size);
                let bytes = self.iconst(n * size);
                self.b
                    .call_memcpy(self.g.module.target_config(), p, src, bytes);
                let nn = self.iconst(n);
                vec![p, nn, nn]
            }
            Op::ListLen => vec![self.a(inst, 0)[1]],
            Op::ListGet | Op::ListGetNn | Op::ListGetU => {
                let lt = f.ty(inst.args[0]);
                let (_, leaves, size) = self.elem_info(lt);
                let l = self.a(inst, 0);
                let i = self.a(inst, 1)[0];
                let at = self.elem_addr(l[0], l[1], i, size, inst.op);
                self.load_leaves(at, 0, &leaves)
            }
            Op::ListSet | Op::ListSetNn | Op::ListSetU | Op::ListFill => {
                let lt = f.ty(inst.args[0]);
                let (e, leaves, size) = self.elem_info(lt);
                let l = self.a(inst, 0);
                let i = self.a(inst, 1)[0];
                let v = self.a(inst, 2);
                let at = self.elem_addr(l[0], l[1], i, size, inst.op);
                if inst.op != Op::ListFill && self.g.m.needs_drop(e) {
                    let old = self.load_leaves(at, 0, &leaves);
                    self.drop_value(e, &old);
                }
                self.store_leaves(at, 0, &leaves, &v);
                l
            }
            Op::ListDropLast => {
                let lt = f.ty(inst.args[0]);
                let (e, leaves, size) = self.elem_info(lt);
                let l = self.a(inst, 0);
                let nl = self.b.ins().iadd_imm_s(l[1], -1);
                // `list.droplast 1` follows a `list.take` of that element: nothing to drop.
                if self.g.m.needs_drop(e) && inst.imm != Imm::Int(1) {
                    let off = self.b.ins().imul_imm_s(nl, size);
                    let at = self.b.ins().iadd(l[0], off);
                    let old = self.load_leaves(at, 0, &leaves);
                    self.drop_value(e, &old);
                }
                vec![l[0], nl, l[2]]
            }
            Op::ListPush => {
                let lt = f.ty(inst.args[0]);
                let (_, leaves, size) = self.elem_info(lt);
                let l = self.a(inst, 0);
                let v = self.a(inst, 1);
                let (ptr, len, cap) = (l[0], l[1], l[2]);
                let full = self.b.ins().icmp(IntCC::Equal, len, cap);
                let ready = self.b.create_block();
                self.b.append_block_param(ready, types::I64);
                self.b.append_block_param(ready, types::I64);
                let grow = self.b.create_block();
                self.b.set_cold_block(grow);
                self.b.ins().brif(
                    full,
                    grow,
                    &[],
                    ready,
                    &[BlockArg::Value(ptr), BlockArg::Value(cap)],
                );
                self.b.switch_to_block(grow);
                let empty = self.b.ins().icmp_imm_s(IntCC::Equal, cap, 0);
                let four = self.iconst(4);
                let doubled = self.b.ins().ishl_imm_s(cap, 1);
                let ncap = self.b.ins().select(empty, four, doubled);
                let bytes = self.b.ins().imul_imm_s(ncap, size.max(1));
                let first = self.b.create_block();
                let again = self.b.create_block();
                let joined = self.b.create_block();
                self.b.append_block_param(joined, types::I64);
                self.b.ins().brif(empty, first, &[], again, &[]);
                self.b.switch_to_block(first);
                let np = self.rt_call("msrt_alloc", &[bytes])[0];
                self.b.ins().jump(joined, &[BlockArg::Value(np)]);
                self.b.switch_to_block(again);
                let rp = self.rt_call("msrt_realloc", &[ptr, bytes])[0];
                self.b.ins().jump(joined, &[BlockArg::Value(rp)]);
                self.b.switch_to_block(joined);
                let np = self.b.block_params(joined)[0];
                self.b
                    .ins()
                    .jump(ready, &[BlockArg::Value(np), BlockArg::Value(ncap)]);
                self.b.switch_to_block(ready);
                let (p, c) = (self.b.block_params(ready)[0], self.b.block_params(ready)[1]);
                let off = self.b.ins().imul_imm_s(len, size);
                let at = self.b.ins().iadd(p, off);
                self.store_leaves(at, 0, &leaves, &v);
                let nl = self.b.ins().iadd_imm_s(len, 1);
                vec![p, nl, c]
            }
            _ => unreachable!(),
        }
    }
}
