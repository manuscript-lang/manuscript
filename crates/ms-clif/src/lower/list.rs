//! Lowering of list element access and list-valued instructions.

use super::*;

impl<'a, 'm> Lower<'a, 'm> {
    pub(super) fn elem_info(&self, list_ty: Ty) -> (Ty, Vec<Leaf>, i64) {
        let e = self.g.m.seq_elem(list_ty).unwrap_or(Ty::INT);
        let leaves = self.g.lay.leaves(e);
        let size = mem_layout(&leaves).size as i64;
        (e, leaves, size)
    }

    /// The address of element `i` of a list block. The index is in range: `ms_mir::expand`
    /// wrapped a negative one and branched to the fault.
    pub(super) fn elem_addr(&mut self, ptr: Value, i: Value, size: i64) -> Value {
        let off = self.b.ins().imul_imm_s(i, size);
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
            Op::ListConstView => {
                let Imm::Int(i) = inst.imm else {
                    unreachable!()
                };
                let (e, _, _) = self.elem_info(res_ty);
                let n = self.g.m.list_consts[i as usize].len() as i64;
                let data = self.g.list_const(i as usize, e);
                let ptr = self.data_addr(data);
                // Capacity zero marks the elements as borrowed: nothing frees them.
                let (len, cap) = (self.iconst(n), self.iconst(0));
                vec![ptr, len, cap]
            }
            Op::ListLen => vec![self.a(inst, 0)[1]],
            Op::ListGetU => {
                let lt = f.ty(inst.args[0]);
                let (_, leaves, size) = self.elem_info(lt);
                let l = self.a(inst, 0);
                let i = self.a(inst, 1)[0];
                let at = self.elem_addr(l[0], i, size);
                self.load_leaves(at, 0, &leaves)
            }
            Op::ListSetU | Op::ListFillU => {
                let lt = f.ty(inst.args[0]);
                let (e, leaves, size) = self.elem_info(lt);
                let l = self.a(inst, 0);
                let i = self.a(inst, 1)[0];
                let v = self.a(inst, 2);
                let at = self.elem_addr(l[0], i, size);
                if inst.op != Op::ListFillU && self.g.m.needs_drop(e) {
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
            Op::ListCap => vec![self.a(inst, 0)[2]],
            // The list has room for `ncap` elements: a fresh block for an empty list, the old
            // block resized otherwise. `ms_mir::expand` chose the capacity.
            Op::ListGrow => {
                let lt = f.ty(inst.args[0]);
                let (_, _, size) = self.elem_info(lt);
                let l = self.a(inst, 0);
                let ncap = self.a(inst, 1)[0];
                let bytes = self.b.ins().imul_imm_s(ncap, size.max(1));
                let empty = self.b.ins().icmp_imm_s(IntCC::Equal, l[2], 0);
                let first = self.b.create_block();
                let again = self.b.create_block();
                let joined = self.b.create_block();
                self.b.append_block_param(joined, types::I64);
                self.b.ins().brif(empty, first, &[], again, &[]);
                self.b.switch_to_block(first);
                let np = self.rt_call("msrt_alloc", &[bytes])[0];
                self.b.ins().jump(joined, &[BlockArg::Value(np)]);
                self.b.switch_to_block(again);
                let rp = self.rt_call("msrt_realloc", &[l[0], bytes])[0];
                self.b.ins().jump(joined, &[BlockArg::Value(rp)]);
                self.b.switch_to_block(joined);
                let p = self.b.block_params(joined)[0];
                vec![p, l[1], ncap]
            }
            Op::ListPushU => {
                let lt = f.ty(inst.args[0]);
                let (_, leaves, size) = self.elem_info(lt);
                let l = self.a(inst, 0);
                let v = self.a(inst, 1);
                let at = self.elem_addr(l[0], l[1], size);
                self.store_leaves(at, 0, &leaves, &v);
                let nl = self.b.ins().iadd_imm_s(l[1], 1);
                vec![l[0], nl, l[2]]
            }
            _ => unreachable!(),
        }
    }
}
