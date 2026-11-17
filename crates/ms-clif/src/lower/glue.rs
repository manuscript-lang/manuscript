//! Glue functions: drop, copy and typedesc bodies synthesized per type.

use super::*;

impl<'a, 'm> Lower<'a, 'm> {
    pub fn lower_glue(&mut self, kind: Glue, ty: Ty) {
        let entry = self.b.create_block();
        self.b.append_block_params_for_function_params(entry);
        self.b.switch_to_block(entry);
        let params = self.b.block_params(entry).to_vec();
        match kind {
            Glue::Clone => {
                if self.g.m.drop_recurses(ty) {
                    self.clone_on_new_segment(ty, &params);
                }
                let out = self.glue_copy(ty, &params);
                self.b.ins().return_(&out);
            }
            Glue::BlockClone => {
                // Interface payload block holding a `ty` value.
                let leaves = self.g.lay.leaves(ty);
                let vs = self.load_leaves(params[0], 0, &leaves);
                let copied = self.clone_value(ty, &vs);
                let blk = self.alloc(mem_layout(&leaves).size as i64);
                self.store_leaves(blk, 0, &leaves, &copied);
                self.b.ins().return_(&[blk]);
            }
            Glue::SlotCopy => {
                let leaves = self.g.lay.leaves(ty);
                let vs = self.load_leaves(params[0], 0, &leaves);
                let out = self.clone_value(ty, &vs);
                self.store_leaves(params[1], 0, &leaves, &out);
                self.b.ins().return_(&[]);
            }
            Glue::Drop
            | Glue::ClosureDrop(_)
            | Glue::ClosureDropFramed(_)
            | Glue::ClosureDropFrom(..)
            | Glue::ClosureClone(_)
            | Glue::BlockDrop
            | Glue::SlotDrop => unreachable!("MIR makes {kind:?} functions"),
            Glue::CleanupThunk(f) => {
                // `arg` points at a stack copy of the registered value.
                let fid = self.g.funcs[f as usize];
                let pty = self.g.m.funcs[f as usize].params[0].ty;
                let leaves = self.g.lay.leaves(pty);
                let vs = self.load_leaves(params[0], 0, &leaves);
                self.call_id(fid, &vs);
                self.b.ins().return_(&[]);
            }
        }
    }

    /// Whether the stack pointer is below the running segment's limit plus `headroom` bytes:
    /// the limit sits in the stack region beside the block's address, one load from the masked
    /// stack pointer. `stack.low` is the headroom-free case.
    pub(super) fn stack_below(&mut self, headroom: i64) -> Value {
        let sp = self.b.ins().get_stack_pointer(types::I64);
        let base = self.b.ins().band_imm_s(sp, !(STACK_REGION - 1));
        let mut limit = self.b.ins().load(
            types::I64,
            flags(),
            base,
            (STACK_REGION - STACK_LIMIT_CELL) as i32,
        );
        if headroom != 0 {
            limit = self.b.ins().iadd_imm_s(limit, headroom);
        }
        self.b.ins().icmp(IntCC::UnsignedLessThan, sp, limit)
    }

    /// The first thing the copy glue of recursive data does: when the stack is nearly used up,
    /// the copy runs on a new segment through the slot copy glue and the glue returns its result
    /// (`msrt_slot_copy_grown`); otherwise it carries on.
    fn clone_on_new_segment(&mut self, ty: Ty, params: &[Value]) {
        let low = self.stack_below(0);
        let grow = self.b.create_block();
        let cont = self.b.create_block();
        self.b.set_cold_block(grow);
        self.b.ins().brif(low, grow, &[], cont, &[]);
        self.b.switch_to_block(grow);
        let leaves = self.g.lay.leaves(ty);
        let size = mem_layout(&leaves).size;
        let (src, dst) = (self.new_slot(size), self.new_slot(size));
        let src = self.b.ins().stack_addr(types::I64, src, 0);
        let dst = self.b.ins().stack_addr(types::I64, dst, 0);
        self.store_leaves(src, 0, &leaves, params);
        let copy = self.g.glue(Glue::SlotCopy, ty);
        let r = self.fref(copy);
        let fa = self.b.ins().func_addr(types::I64, r);
        self.rt_call("msrt_slot_copy_grown", &[fa, src, dst]);
        let out = self.load_leaves(dst, 0, &leaves);
        self.b.ins().return_(&out);
        self.b.switch_to_block(cont);
    }

    /// Splits `vs` into per-field slices for a type.
    pub(super) fn fields_of(&self, ty: Ty) -> Vec<(Ty, usize, usize)> {
        let m = self.g.m;
        let TyKind::Type(r) = m.types.kind(ty) else {
            return Vec::new();
        };
        let mut out = Vec::new();
        let mut at = 0;
        for f in &m.type_defs[r.index()].fields {
            let w = self.g.lay.width(f.1);
            out.push((f.1, at, w));
            at += w;
        }
        out
    }

    /// The block leaves of `ty` when it is an indirect type (one pointer in registers).
    pub(super) fn type_block(&self, ty: Ty) -> Option<Vec<Leaf>> {
        match self.g.m.types.kind(ty) {
            TyKind::Type(r) if self.g.m.type_defs[r.index()].indirect => {
                Some(self.g.lay.type_block(*r))
            }
            _ => None,
        }
    }

    /// The block leaf index and width of each field of the indirect type `ty`.
    pub(super) fn type_block_fields(&self, ty: Ty) -> Vec<(usize, usize)> {
        let TyKind::Type(r) = self.g.m.types.kind(ty) else {
            return Vec::new();
        };
        let mut at = 0;
        let mut out = Vec::new();
        for f in &self.g.m.type_defs[r.index()].fields {
            let n = if self.g.lay.type_field_boxed(f.1) {
                1
            } else {
                self.g.lay.width(f.1)
            };
            out.push((at, n));
            at += n;
        }
        out
    }

    /// Field `i` of the indirect type whose block is at `p`: its leaves, with a boxed
    /// collection header read through its pointer (zeros when there is none).
    pub(super) fn type_load_field(&mut self, ty: Ty, p: Value, i: usize) -> Vs {
        let block = self.type_block(ty).expect("indirect type");
        let lay = mem_layout(&block);
        let (bk, n) = self.type_block_fields(ty)[i];
        let fty = self.fields_of(ty)[i].0;
        if self.g.lay.type_field_boxed(fty) {
            let bp = self.load_leaf(Leaf::I64, p, lay.offsets[bk] as i32);
            return self.map_header_load(bp);
        }
        (bk..bk + n)
            .map(|k| self.load_leaf(block[k], p, lay.offsets[k] as i32))
            .collect()
    }

    /// The field leaves of type `vs`, loaded from its block when it is indirect.
    pub(super) fn type_expand(&mut self, ty: Ty, vs: &[Value]) -> Vs {
        if self.type_block(ty).is_none() {
            return vs.to_vec();
        }
        let n = self.fields_of(ty).len();
        (0..n)
            .flat_map(|i| self.type_load_field(ty, vs[0], i))
            .collect()
    }

    /// The register value of a type with field leaves `flat`: a fresh block when indirect.
    pub(super) fn type_pack(&mut self, ty: Ty, flat: Vs) -> Vs {
        let Some(block) = self.type_block(ty) else {
            return flat;
        };
        let lay = mem_layout(&block);
        let p = self.alloc(lay.size as i64);
        let fields = self.fields_of(ty);
        for (i, (bk, n)) in self.type_block_fields(ty).into_iter().enumerate() {
            let (fty, at, w) = fields[i];
            if self.g.lay.type_field_boxed(fty) {
                let bp = self.map_header_store(&flat[at..at + w]);
                self.store_leaf(Leaf::I64, bp, p, lay.offsets[bk] as i32);
            } else {
                for k in 0..n {
                    self.store_leaf(block[bk + k], flat[at + k], p, lay.offsets[bk + k] as i32);
                }
            }
        }
        vec![p]
    }

    /// Frees the block of the indirect type at `p` and the header blocks of its collections.
    /// The field values were dropped or moved out already.
    pub(super) fn type_free_block(&mut self, ty: Ty, p: Value) {
        let block = self.type_block(ty).expect("indirect type");
        let lay = mem_layout(&block);
        let fields = self.fields_of(ty);
        for (i, (bk, _)) in self.type_block_fields(ty).into_iter().enumerate() {
            if self.g.lay.type_field_boxed(fields[i].0) {
                let bp = self.load_leaf(Leaf::I64, p, lay.offsets[bk] as i32);
                let nn = self.b.ins().icmp_imm_s(IntCC::NotEqual, bp, 0);
                self.if_then(nn, |s| s.free(bp));
            }
        }
        self.free(p);
    }

    /// The seven words of the collection header behind `bp`, or the all-zero empty value.
    fn map_header_load(&mut self, bp: Value) -> Vs {
        let words = ms_rt_abi::MAP_SIZE / 8;
        let (some, none, cont) = (
            self.b.create_block(),
            self.b.create_block(),
            self.b.create_block(),
        );
        for _ in 0..words {
            self.b.append_block_param(cont, types::I64);
        }
        self.b.ins().brif(bp, some, &[], none, &[]);
        self.b.switch_to_block(some);
        let loaded: Vec<BlockArg> = (0..words)
            .map(|k| BlockArg::Value(self.load_leaf(Leaf::I64, bp, (k * 8) as i32)))
            .collect();
        self.b.ins().jump(cont, &loaded);
        self.b.switch_to_block(none);
        let zero = self.iconst(0);
        let zeros = vec![BlockArg::Value(zero); words];
        self.b.ins().jump(cont, &zeros);
        self.b.switch_to_block(cont);
        self.b.block_params(cont).to_vec()
    }

    /// The header block of the collection field at `slot`, created empty when the field holds
    /// null: the address a native call or an in-place update works on.
    pub(super) fn map_header_ensure(&mut self, slot: Value) -> Value {
        let (make, cont) = (self.b.create_block(), self.b.create_block());
        self.b.append_block_param(cont, types::I64);
        let have = self.load_leaf(Leaf::I64, slot, 0);
        self.b
            .ins()
            .brif(have, cont, &[BlockArg::Value(have)], make, &[]);
        self.b.switch_to_block(make);
        let bp = self.alloc(ms_rt_abi::MAP_SIZE as i64);
        let zero = self.iconst(0);
        for k in 0..ms_rt_abi::MAP_SIZE / 8 {
            self.store_leaf(Leaf::I64, zero, bp, (k * 8) as i32);
        }
        self.store_leaf(Leaf::I64, bp, slot, 0);
        self.b.ins().jump(cont, &[BlockArg::Value(bp)]);
        self.b.switch_to_block(cont);
        self.b.block_params(cont)[0]
    }

    /// A header block holding `words`, or null for the all-zero empty collection. A stamped
    /// empty collection (descriptor word set) keeps its block.
    fn map_header_store(&mut self, words: &[Value]) -> Value {
        let (some, none, cont) = (
            self.b.create_block(),
            self.b.create_block(),
            self.b.create_block(),
        );
        self.b.append_block_param(cont, types::I64);
        let used = self.b.ins().bor(words[0], words[words.len() - 1]);
        self.b.ins().brif(used, some, &[], none, &[]);
        self.b.switch_to_block(some);
        let bp = self.alloc(ms_rt_abi::MAP_SIZE as i64);
        for (k, w) in words.iter().enumerate() {
            self.store_leaf(Leaf::I64, *w, bp, (k * 8) as i32);
        }
        self.b.ins().jump(cont, &[BlockArg::Value(bp)]);
        self.b.switch_to_block(none);
        let zero = self.iconst(0);
        self.b.ins().jump(cont, &[BlockArg::Value(zero)]);
        self.b.switch_to_block(cont);
        self.b.block_params(cont)[0]
    }

    /// Per-case, per-field `(type, leaf indices into the alt's leaf/block list)`.
    pub(super) fn alt_fields(
        &self,
        a: ms_mir::types::AltId,
    ) -> std::rc::Rc<crate::layout::AltFields> {
        self.g.lay.alt_fields(a)
    }

    /// Drops the elements of a list or byte string from index `from` (0 when `None`; the
    /// elements before it were moved out) and frees its buffer.
    pub(super) fn drop_list_from(&mut self, ty: Ty, ptr: Value, len: Value, from: Option<Value>) {
        let m = self.g.m;
        let elem = m.list_elem(ty);
        if let Some(e) = elem.filter(|e| m.needs_drop(*e)) {
            let leaves = self.g.lay.leaves(e);
            let size = mem_layout(&leaves).size as i64;
            let head = self.b.create_block();
            let body = self.b.create_block();
            let done = self.b.create_block();
            self.b.append_block_param(head, types::I64);
            let start = match from {
                Some(from) => {
                    let zero = self.iconst(0);
                    let neg = self.b.ins().icmp_imm_s(IntCC::SignedLessThan, from, 0);
                    self.b.ins().select(neg, zero, from)
                }
                None => self.iconst(0),
            };
            self.b.ins().jump(head, &[BlockArg::Value(start)]);
            self.b.switch_to_block(head);
            let i = self.b.block_params(head)[0];
            let more = self.b.ins().icmp(IntCC::SignedLessThan, i, len);
            self.b.ins().brif(more, body, &[], done, &[]);
            self.b.switch_to_block(body);
            let off = self.b.ins().imul_imm_s(i, size);
            let at = self.b.ins().iadd(ptr, off);
            let ev = self.load_leaves(at, 0, &leaves);
            self.drop_value(e, &ev);
            let next = self.b.ins().iadd_imm_s(i, 1);
            self.b.ins().jump(head, &[BlockArg::Value(next)]);
            self.b.switch_to_block(done);
        }
        let nn = self.b.ins().icmp_imm_s(IntCC::NotEqual, ptr, 0);
        self.if_then(nn, |s| s.free(ptr));
    }

    /// For a boxed alternative with payloadless cases: whether `tag` names one (such values are the
    /// shared block, see [`Gen::unit_block`]) and that block's address. `None` when every case
    /// carries a payload.
    pub(super) fn unit_case(
        &mut self,
        a: ms_mir::types::AltId,
        tag: Value,
    ) -> Option<(Value, Value)> {
        let ty = self
            .g
            .m
            .types
            .find(&TyKind::Alt(a))
            .expect("alt type interned");
        let shape = self.g.lay.shape(ty);
        let Some(AltRepr::Boxed { block, .. }) = &shape.alt else {
            return None;
        };
        let size = mem_layout(block).size;
        let units: Vec<usize> = self.g.m.alts[a.index()]
            .cases
            .iter()
            .enumerate()
            .filter(|(_, c)| c.fields.is_empty())
            .map(|(i, _)| i)
            .collect();
        let mut acc: Option<(Value, Value)> = None;
        for c in units {
            let id = self.g.unit_block(a, c, size as usize);
            let addr = self.data_addr(id);
            let is = self.b.ins().icmp_imm_s(IntCC::Equal, tag, c as i64);
            acc = Some(match acc {
                None => (is, addr),
                Some((u, prev)) => (self.b.ins().bor(u, is), self.b.ins().select(is, addr, prev)),
            });
        }
        acc
    }

    /// The field of `case` that holds the same boxed alternative again (the "tail" of a chain
    /// such as `Cons(head, tail)`), as `(field index, leaf indices, optional)`. Drop and copy of a
    /// boxed alternative loop over this field instead of recursing, so a long chain does not
    /// overflow the stack. Other recursive fields (the left child of a tree) still recurse.
    pub(super) fn tail_field(
        &self,
        ty: Ty,
        case: &[(Ty, Vec<usize>)],
    ) -> Option<(usize, Vec<usize>, bool)> {
        let m = self.g.m;
        case.iter().enumerate().rev().find_map(|(i, (fty, idx))| {
            if *fty == ty && idx.len() == 1 {
                return Some((i, idx.clone(), false));
            }
            match m.types.kind(*fty) {
                TyKind::Opt(inner) if *inner == ty && idx.len() == 2 => {
                    Some((i, idx.clone(), true))
                }
                _ => None,
            }
        })
    }

    pub(super) fn has_tail(&self, ty: Ty, fields: &[Vec<(Ty, Vec<usize>)>]) -> bool {
        fields.iter().any(|c| self.tail_field(ty, c).is_some())
    }

    /// Copies a chain of boxed blocks front to back: each iteration allocates the new block,
    /// stores its address where the previous block's tail pointer lives, copies the non-tail
    /// fields, and continues with the source's tail.
    pub(super) fn copy_boxed_iter(
        &mut self,
        ty: Ty,
        fields: &[Vec<(Ty, Vec<usize>)>],
        first: Value,
    ) -> Value {
        let shape = self.g.lay.shape(ty);
        let Some(AltRepr::Boxed { block, .. }) = &shape.alt else {
            return first;
        };
        let lay = mem_layout(block);
        let result =
            self.b
                .create_sized_stack_slot(StackSlotData::new(StackSlotKind::ExplicitSlot, 8, 3));
        let result_addr = self.b.ins().stack_addr(types::I64, result, 0);
        let head = self.b.create_block();
        let exit = self.b.create_block();
        self.b.append_block_param(head, types::I64);
        self.b.append_block_param(head, types::I64);
        self.b.ins().jump(
            head,
            &[BlockArg::Value(first), BlockArg::Value(result_addr)],
        );
        self.b.switch_to_block(head);
        let (src, dst) = {
            let ps = self.b.block_params(head);
            (ps[0], ps[1])
        };
        let sv = self.load_leaves(src, 0, block);
        let tag = sv[0];
        let TyKind::Alt(a) = self.g.m.types.kind(ty).clone() else {
            unreachable!("boxed alternative")
        };
        if let Some((unit, addr)) = self.unit_case(a, tag) {
            // A payloadless case is the shared block: link it and stop.
            let shared = self.b.create_block();
            let fresh = self.b.create_block();
            self.b.ins().brif(unit, shared, &[], fresh, &[]);
            self.b.switch_to_block(shared);
            self.b.ins().store(flags(), addr, dst, 0);
            self.b.ins().jump(exit, &[]);
            self.b.switch_to_block(fresh);
        }
        let blk = self.alloc(lay.size as i64);
        self.b.ins().store(flags(), blk, dst, 0);
        for (c, case) in fields.iter().enumerate() {
            let tail = self.tail_field(ty, case);
            let droppable = case.iter().any(|(t, _)| self.g.m.needs_drop(*t));
            if !droppable {
                continue;
            }
            let this = self.b.create_block();
            let next = self.b.create_block();
            let is = self.b.ins().icmp_imm_s(IntCC::Equal, tag, c as i64);
            self.b.ins().brif(is, this, &[], next, &[]);
            self.b.switch_to_block(this);
            let mut out = sv.clone();
            for (i, (fty, idx)) in case.iter().enumerate() {
                if !self.g.m.needs_drop(*fty) || tail.as_ref().is_some_and(|t| t.0 == i) {
                    continue;
                }
                let fv: Vs = idx.iter().map(|k| sv[*k]).collect();
                let cv = self.clone_value(*fty, &fv);
                for (k, v) in idx.iter().zip(cv) {
                    out[*k] = v;
                }
            }
            self.store_leaves(blk, 0, block, &out);
            match tail {
                Some((_, idx, optional)) => {
                    let k = *idx.last().expect("tail leaf");
                    let next_dst = self.b.ins().iadd_imm_s(blk, lay.offsets[k] as i64);
                    let args = [BlockArg::Value(sv[k]), BlockArg::Value(next_dst)];
                    if optional {
                        self.b.ins().brif(sv[idx[0]], head, &args, exit, &[]);
                    } else {
                        self.b.ins().jump(head, &args);
                    }
                }
                None => {
                    self.b.ins().jump(exit, &[]);
                }
            }
            self.b.switch_to_block(next);
        }
        self.store_leaves(blk, 0, block, &sv);
        self.b.ins().jump(exit, &[]);
        self.b.switch_to_block(exit);
        self.b.ins().load(types::I64, flags(), result_addr, 0)
    }

    pub(super) fn glue_copy(&mut self, ty: Ty, vs: &[Value]) -> Vs {
        let m = self.g.m;
        match m.types.kind(ty).clone() {
            TyKind::Bytes | TyKind::List(_) => self.list_copy(ty, vs),
            TyKind::Type(_) => {
                let flat = self.type_expand(ty, vs);
                let mut out = Vec::new();
                for (fty, at, w) in self.fields_of(ty) {
                    out.extend(self.clone_value(fty, &flat[at..at + w]));
                }
                self.type_pack(ty, out)
            }
            TyKind::Opt(inner) if self.g.lay.opt_is_boxed(inner) => {
                // Null stays null; otherwise copy the payload into a fresh block.
                let p = vs[0];
                let leaves = self.g.lay.leaves(inner);
                let size = mem_layout(&leaves).size as i64;
                let join = self.b.create_block();
                self.b.append_block_param(join, types::I64);
                let yes = self.b.create_block();
                self.b.ins().brif(p, yes, &[], join, &[BlockArg::Value(p)]);
                self.b.switch_to_block(yes);
                let payload = self.load_leaves(p, 0, &leaves);
                let c = self.clone_value(inner, &payload);
                let q = self.alloc(size);
                self.store_leaves(q, 0, &leaves, &c);
                self.b.ins().jump(join, &[BlockArg::Value(q)]);
                self.b.switch_to_block(join);
                vec![self.b.block_params(join)[0]]
            }
            TyKind::Opt(_) if self.g.lay.is_str_like(ty) => self.clone_value(ty, vs),
            TyKind::Opt(inner) => {
                if self.g.lay.opt_is_nullable(inner) {
                    // A `none` is null, which the clone entry call passes through.
                    vec![self.clone_obj(vs[0])]
                } else {
                    // Copy the payload only when present; otherwise the zero payload is returned.
                    let present = vs[0];
                    let payload = vs[1..].to_vec();
                    let leaves = self.g.lay.leaves(inner);
                    let join = self.b.create_block();
                    for l in &leaves {
                        self.b.append_block_param(join, leaf_type(*l));
                    }
                    let yes = self.b.create_block();
                    self.b.ins().brif(present, yes, &[], join, &bargs(&payload));
                    self.b.switch_to_block(yes);
                    let c = self.clone_value(inner, &payload);
                    self.b.ins().jump(join, &bargs(&c));
                    self.b.switch_to_block(join);
                    let mut out = vec![present];
                    out.extend(self.b.block_params(join).to_vec());
                    out
                }
            }
            TyKind::Alt(_) => self.alt_copy(ty, vs),
            TyKind::Obj(..) => {
                let leaves = self.g.lay.leaves(ty);
                let src = self.spill_temp(vs, &leaves);
                let dst = self.spill_temp(vs, &leaves);
                let d = self.typedesc_addr(ty);
                self.rt_call("msrt_slot_copy", &[d, src, dst]);
                self.load_leaves(dst, 0, &leaves)
            }
            TyKind::Iface(i) => {
                // The payload copier sits after the methods in the vtable. The copy owns its
                // payload whatever the source owned, so the tag bits come off.
                let (data, vt) = (vs[0], self.b.ins().band_imm_s(vs[1], !3));
                let slot = 8 * (1 + self.g.m.ifaces[i.index()].methods.len()) as i32;
                let f = self.b.ins().load(types::I64, flags(), vt, slot);
                let mut sig = self.g.module.make_signature();
                sig.params.push(ir::AbiParam::new(types::I64));
                sig.returns.push(ir::AbiParam::new(types::I64));
                let sr = self.b.import_signature(sig);
                let c = self.b.ins().call_indirect(sr, f, &[data]);
                vec![self.b.inst_results(c)[0], vt]
            }
            _ => vs.to_vec(),
        }
    }

    pub(super) fn list_copy(&mut self, ty: Ty, vs: &[Value]) -> Vs {
        let m = self.g.m;
        let elem = m.list_elem(ty);
        let (ptr, len) = (vs[0], vs[1]);
        let size = elem.map_or(1, |e| mem_layout(&self.g.lay.leaves(e)).size.max(1) as i64);
        let join = self.b.create_block();
        self.b.append_block_param(join, types::I64);
        let some = self.b.create_block();
        let empty_ptr = self.iconst(0);
        let nonempty = self.b.ins().icmp_imm_s(IntCC::NotEqual, len, 0);
        self.b
            .ins()
            .brif(nonempty, some, &[], join, &[BlockArg::Value(empty_ptr)]);
        self.b.switch_to_block(some);
        let bytes = self.b.ins().imul_imm_s(len, size);
        let np = self.rt_call("msrt_alloc", &[bytes])[0];
        match elem.filter(|e| m.needs_drop(*e)) {
            None => {
                self.b
                    .call_memcpy(self.g.module.target_config(), np, ptr, bytes);
            }
            Some(e) => {
                let leaves = self.g.lay.leaves(e);
                let head = self.b.create_block();
                let body = self.b.create_block();
                let done = self.b.create_block();
                self.b.append_block_param(head, types::I64);
                let zero = self.iconst(0);
                self.b.ins().jump(head, &[BlockArg::Value(zero)]);
                self.b.switch_to_block(head);
                let i = self.b.block_params(head)[0];
                let more = self.b.ins().icmp(IntCC::SignedLessThan, i, len);
                self.b.ins().brif(more, body, &[], done, &[]);
                self.b.switch_to_block(body);
                let off = self.b.ins().imul_imm_s(i, size);
                let src = self.b.ins().iadd(ptr, off);
                let dst = self.b.ins().iadd(np, off);
                let ev = self.load_leaves(src, 0, &leaves);
                let cv = self.clone_value(e, &ev);
                self.store_leaves(dst, 0, &leaves, &cv);
                let next = self.b.ins().iadd_imm_s(i, 1);
                self.b.ins().jump(head, &[BlockArg::Value(next)]);
                self.b.switch_to_block(done);
            }
        }
        self.b.ins().jump(join, &[BlockArg::Value(np)]);
        self.b.switch_to_block(join);
        let p = self.b.block_params(join)[0];
        vec![p, len, len]
    }

    pub(super) fn alt_copy(&mut self, ty: Ty, vs: &[Value]) -> Vs {
        let TyKind::Alt(a) = self.g.m.types.kind(ty).clone() else {
            return vs.to_vec();
        };
        let fields = self.alt_fields(a);
        let shape = self.g.lay.shape(ty);
        let boxed = matches!(shape.alt, Some(AltRepr::Boxed { .. }));
        if boxed && self.has_tail(ty, &fields) {
            return vec![self.copy_boxed_iter(ty, &fields, vs[0])];
        }
        let leaves = match &shape.alt {
            Some(AltRepr::Boxed { block, .. }) => block.clone(),
            _ => shape.leaves.clone(),
        };
        // Source leaves: boxed values are loaded from the block.
        let src: Vs = if boxed {
            self.load_leaves(vs[0], 0, &leaves)
        } else {
            vs.to_vec()
        };
        let join = self.b.create_block();
        for l in &leaves {
            self.b.append_block_param(join, leaf_type(*l));
        }
        let tag = src[0];
        for (c, case) in fields.iter().enumerate() {
            if !case.iter().any(|(t, _)| self.g.m.needs_drop(*t)) {
                continue;
            }
            let this = self.b.create_block();
            let next = self.b.create_block();
            let is = self.b.ins().icmp_imm_s(IntCC::Equal, tag, c as i64);
            self.b.ins().brif(is, this, &[], next, &[]);
            self.b.switch_to_block(this);
            let mut out = src.clone();
            for (fty, idx) in case {
                if !self.g.m.needs_drop(*fty) {
                    continue;
                }
                let fv: Vs = idx.iter().map(|i| src[*i]).collect();
                let cv = self.clone_value(*fty, &fv);
                for (i, v) in idx.iter().zip(cv) {
                    out[*i] = v;
                }
            }
            self.b.ins().jump(join, &bargs(&out));
            self.b.switch_to_block(next);
        }
        self.b.ins().jump(join, &bargs(&src));
        self.b.switch_to_block(join);
        let out = self.b.block_params(join).to_vec();
        if boxed {
            let size = mem_layout(&leaves).size as i64;
            let Some((unit, addr)) = self.unit_case(a, out[0]) else {
                let blk = self.alloc(size);
                self.store_leaves(blk, 0, &leaves, &out);
                return vec![blk];
            };
            let fin = self.b.create_block();
            self.b.append_block_param(fin, types::I64);
            let fresh = self.b.create_block();
            self.b
                .ins()
                .brif(unit, fin, &[BlockArg::Value(addr)], fresh, &[]);
            self.b.switch_to_block(fresh);
            let blk = self.alloc(size);
            self.store_leaves(blk, 0, &leaves, &out);
            self.b.ins().jump(fin, &[BlockArg::Value(blk)]);
            self.b.switch_to_block(fin);
            vec![self.b.block_params(fin)[0]]
        } else {
            out
        }
    }
}
