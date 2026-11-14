//! Lowering of closure creation and the call forms: closures, methods and runtime externs.

use super::*;

impl<'a, 'm> Lower<'a, 'm> {
    pub(super) fn closure_new(&mut self, inst: &Inst) -> Vs {
        let Imm::Func(c) = inst.imm else {
            unreachable!()
        };
        let caps = match &self.g.m.funcs[c.index()].kind {
            ms_mir::ir::FuncKind::Closure { captures } => captures.clone(),
            _ => Vec::new(),
        };
        let mut layouts = Vec::new();
        let mut off = CLOSURE_CAPTURES as i64;
        for cty in &caps {
            let leaves = self.g.lay.leaves(*cty);
            let lay = mem_layout(&leaves);
            off = (off + lay.align as i64 - 1) / lay.align as i64 * lay.align as i64;
            layouts.push((off, leaves));
            off += lay.size as i64;
        }
        let total = (off + 7) / 8 * 8;
        // Only calls borrow it, so the object lives in this frame and nothing is freed.
        let framed = inst
            .res
            .is_some_and(|r| self.framed_closures.contains(&r.index()));
        let obj = if framed {
            let slot = self.b.create_sized_stack_slot(StackSlotData::new(
                StackSlotKind::ExplicitSlot,
                total as u32,
                3,
            ));
            self.b.ins().stack_addr(types::I64, slot, 0)
        } else {
            self.alloc(total)
        };
        let clone = self.g.glue(Glue::ClosureClone(c.0), Ty::UNIT);
        let cr = self.fref(clone);
        let ca = self.b.ins().func_addr(types::I64, cr);
        self.b.ins().store(flags(), ca, obj, 0);
        let drop = self.g.glue(
            if framed {
                Glue::ClosureDropFramed(c.0)
            } else {
                Glue::ClosureDrop(c.0)
            },
            Ty::UNIT,
        );
        let dr = self.fref(drop);
        let da = self.b.ins().func_addr(types::I64, dr);
        self.b.ins().store(flags(), da, obj, 8);
        let code = self.g.funcs[c.index()];
        let cr = self.fref(code);
        let ca = self.b.ins().func_addr(types::I64, cr);
        self.b.ins().store(flags(), ca, obj, CLOSURE_CODE);
        for (i, (off, leaves)) in layouts.iter().enumerate() {
            let v = self.a(inst, i);
            self.store_leaves(obj, *off, leaves, &v);
        }
        vec![obj]
    }

    pub(super) fn call_closure(&mut self, f: &Func, inst: &Inst) -> Vs {
        let clo = self.a(inst, 0)[0];
        let TyKind::Fn(ps, r) = self.g.m.types.kind(f.ty(inst.args[0])).clone() else {
            unreachable!()
        };
        let mut params = vec![Leaf::I64];
        for p in &ps {
            params.extend(self.g.lay.leaves(*p));
        }
        let rets = self.g.lay.leaves(r);
        let sig = self.g.sig(&params, &rets);
        let sr = self.b.import_signature(sig);
        let code = self.b.ins().load(types::I64, flags(), clo, CLOSURE_CODE);
        let mut args = vec![clo];
        for i in 1..inst.args.len() {
            args.extend(self.a(inst, i));
        }
        let c = self.b.ins().call_indirect(sr, code, &args);
        self.b.inst_results(c).to_vec()
    }

    pub(super) fn call_method(&mut self, inst: &Inst) -> Vs {
        let Imm::Method(iface, k) = inst.imm else {
            unreachable!()
        };
        let recv = self.a(inst, 0);
        let sig = self.g.m.ifaces[iface.index()].methods[k as usize].clone();
        let mut params = vec![Leaf::I64];
        for p in &sig.params {
            params.extend(self.g.lay.leaves(*p));
        }
        let rets = self.g.lay.leaves(sig.ret);
        let csig = self.g.sig(&params, &rets);
        let sr = self.b.import_signature(csig);
        let vt = self.b.ins().band_imm_s(recv[1], !3);
        let code = self
            .b
            .ins()
            .load(types::I64, flags(), vt, 8 * (1 + k as i32));
        let mut args = vec![recv[0]];
        for i in 1..inst.args.len() {
            args.extend(self.a(inst, i));
        }
        let c = self.b.ins().call_indirect(sr, code, &args);
        self.b.inst_results(c).to_vec()
    }

    pub(super) fn call_extern(&mut self, f: &Func, inst: &Inst) -> Vs {
        let Imm::Ext(e) = inst.imm else {
            unreachable!()
        };
        if self.g.m.externs[e.index()].role == ExternRole::MapNew {
            // `ms_rt::map::empty()` is all zero words (a unit test pins it).
            let zero = self.iconst(0);
            return vec![zero; ms_rt_abi::MAP_SIZE / 8];
        }
        if self.g.m.externs[e.index()].role == ExternRole::CleanupDiscard {
            // Handle 0 is a registration skipped for lack of a guard.
            let h = self.a(inst, 0)[0];
            self.if_then(h, |s| {
                s.call_extern_plain(f, inst);
            });
            return vec![];
        }
        self.call_extern_plain(f, inst)
    }

    pub(super) fn call_extern_plain(&mut self, f: &Func, inst: &Inst) -> Vs {
        let Imm::Ext(e) = inst.imm else {
            unreachable!()
        };
        let def = self.g.m.externs[e.index()].clone();
        let id = match self.g.ext.get(&e) {
            Some(id) => *id,
            None => {
                let direct =
                    |lay: &crate::layout::Layouts, t: Ty| -> bool { Self::passes_directly(lay, t) };
                let mut params: Vec<Leaf> = Vec::new();
                for p in &def.params {
                    if direct(&self.g.lay, p.ty) {
                        params.extend(self.g.lay.leaves(p.ty));
                    } else {
                        params.push(Leaf::I64);
                    }
                }
                let rets: Vec<Leaf> = if direct(&self.g.lay, def.ret) {
                    self.g.lay.leaves(def.ret)
                } else {
                    params.push(Leaf::I64);
                    Vec::new()
                };
                let sig = if self.g.m.c_externs.contains(&def.name) {
                    // A user shim takes and returns sized numbers as their C types.
                    let mut sig = self.g.module.make_signature();
                    sig.params.extend(params.iter().map(|l| c_param(*l)));
                    // Results carry no extension attribute: AAPCS64 leaves the upper bits of a
                    // narrow result undefined, and LLVM would trust a `signext` result. The
                    // caller extends it (`call_c_extern`).
                    sig.returns.extend(
                        rets.iter()
                            .map(|l| ir::AbiParam::new(c_param(*l).value_type)),
                    );
                    sig
                } else {
                    // Runtime natives take and return a `Float32` as `f64`.
                    let wide = |ls: &mut Vec<Leaf>| {
                        for l in ls.iter_mut().filter(|l| **l == Leaf::F32) {
                            *l = Leaf::F64;
                        }
                    };
                    wide(&mut params);
                    let mut rets = rets;
                    wide(&mut rets);
                    self.g.sig(&params, &rets)
                };
                let id = self
                    .g
                    .module
                    .declare_function(&def.name, cranelift_module::Linkage::Import, &sig)
                    .expect("declare extern");
                self.g.ext.insert(e, id);
                id
            }
        };
        let mut args: Vs = Vec::new();
        for (i, p) in def.params.iter().enumerate() {
            let v = self.a(inst, i);
            if Self::passes_directly(&self.g.lay, p.ty) {
                args.extend(v);
            } else if let Some(h) = self.home_of(inst.args[i]) {
                args.push(h.addr);
            } else {
                let leaves = self.g.lay.leaves(p.ty);
                args.push(self.spill_temp(&v, &leaves));
            }
        }
        let ret_ty = def.ret;
        let _ = f;
        if def.role == ExternRole::StrBuilderAppend
            && args.len() == 2
            && self.g.lay.leaves(ret_ty).is_empty()
        {
            if let Some(&lit) = self.str_lits.get(&inst.args[1].index()) {
                let bytes = self.g.m.strings[lit as usize].as_bytes().to_vec();
                if (1..=16).contains(&bytes.len()) {
                    return self.strbuilder_append_literal(id, args[0], args[1], &bytes);
                }
            }
            return self.strbuilder_append(id, args[0], args[1]);
        }
        if self.g.m.c_externs.contains(&def.name) {
            return self.call_c_extern(id, &args, ret_ty);
        }
        if Self::passes_directly(&self.g.lay, ret_ty) {
            self.call_id(id, &args)
        } else {
            let leaves = self.g.lay.leaves(ret_ty);
            let lay = mem_layout(&leaves);
            let slot = self.temp_slot(lay.size);
            let out = self.b.ins().stack_addr(types::I64, slot, 0);
            args.push(out);
            self.call_id(id, &args);
            if self.is_wide(ret_ty)
                && let Some(r) = inst.res
            {
                self.homes[r.index()] = Some(Home {
                    addr: out,
                    slot: Some(slot),
                    blk: Some(self.cur),
                });
            }
            self.load_leaves(out, 0, &leaves)
        }
    }

    pub(super) fn passes_directly(lay: &crate::layout::Layouts, t: Ty) -> bool {
        match lay.m.types.kind(t) {
            TyKind::Unit
            | TyKind::Bool
            | TyKind::Int
            | TyKind::Int8
            | TyKind::Int16
            | TyKind::Int32
            | TyKind::UInt8
            | TyKind::UInt16
            | TyKind::UInt32
            | TyKind::UInt64
            | TyKind::Float
            | TyKind::Float32
            | TyKind::Ptr
            | TyKind::Fn(..)
            | TyKind::Iface(_) => true,
            TyKind::Obj(n, _) => !n.is_map_or_set(),
            TyKind::Opt(inner) => lay.opt_is_nullable(*inner) || lay.m.types.is_scalar(*inner),
            _ => false,
        }
    }
}
