//! Cranelift lowering of type, alternative, list, optional and string instructions.
//!
//! Each function handles one op family; [`Lower::lower_inst`] routes to it.

use super::*;

impl<'a, 'm> Lower<'a, 'm> {
    /// Types.
    pub(super) fn type_op(&mut self, f: &Func, inst: &Inst) -> Vs {
        let m = self.g.m;
        let res_ty = inst.res.map(|r| f.ty(r));
        match inst.op {
            Op::TypeNew => {
                let flat: Vs = (0..inst.args.len()).flat_map(|i| self.a(inst, i)).collect();
                self.type_pack(res_ty.expect("type.new result"), flat)
            }
            Op::TypeGet => {
                let Imm::Field(_, i) = inst.imm else {
                    unreachable!()
                };
                let ty = f.ty(inst.args[0]);
                let (_, at, w) = self.fields_of(ty)[i as usize];
                if self.type_block(ty).is_some() {
                    let p = self.a(inst, 0)[0];
                    self.type_load_field(ty, p, i as usize)
                } else {
                    self.a(inst, 0)[at..at + w].to_vec()
                }
            }
            Op::TypeSet | Op::TypeFill => {
                let Imm::Field(_, i) = inst.imm else {
                    unreachable!()
                };
                let ty = f.ty(inst.args[0]);
                let (fty, at, w) = self.fields_of(ty)[i as usize];
                let held = self.a(inst, 0);
                let mut obj = self.type_expand(ty, &held);
                if inst.op == Op::TypeSet && m.needs_drop(fty) {
                    let old = obj[at..at + w].to_vec();
                    self.drop_value(fty, &old);
                }
                let new = self.a(inst, 1);
                obj.splice(at..at + w, new);
                // The old value is consumed by the set: an indirect type moves its fields into a
                // fresh block and frees the old one, so no block is ever written in place.
                if self.type_block(ty).is_some() {
                    self.type_free_block(ty, held[0]);
                }
                self.type_pack(ty, obj)
            }
            _ => unreachable!("types is only called for its own ops"),
        }
    }

    /// Alternatives.
    pub(super) fn alternatives(&mut self, f: &Func, inst: &Inst) -> Vs {
        let m = self.g.m;
        let res_ty = inst.res.map(|r| f.ty(r));
        match inst.op {
            Op::AltNew | Op::AltView => self.alt_new(inst, res_ty.expect("alt.new result")),
            Op::AltPlain => self.a(inst, 0),
            Op::AltOwn => {
                // Every case copied: the result is the ordinary alternative.
                let ty = res_ty.expect("alt.own result");
                let v = self.a(inst, 0);
                self.clone_value(ty, &v)
            }
            Op::AltTag => {
                let ty = f.ty(inst.args[0]);
                let v = self.a(inst, 0);
                match &self.g.lay.shape(ty).alt {
                    Some(AltRepr::Boxed { .. }) => {
                        vec![self.b.ins().load(types::I64, flags(), v[0], 0)]
                    }
                    _ => vec![v[0]],
                }
            }
            Op::AltGet | Op::AltTake => {
                let Imm::AltField(a, c, i) = inst.imm else {
                    unreachable!()
                };
                let ty = f.ty(inst.args[0]);
                let (_, idx) = self.alt_fields(a)[c as usize][i as usize].clone();
                let v = self.a(inst, 0);
                match &self.g.lay.shape(ty).alt {
                    Some(AltRepr::Boxed { block, .. }) => {
                        let lay = mem_layout(block);
                        idx.iter()
                            .map(|k| {
                                self.b.ins().load(
                                    leaf_type(block[*k]),
                                    flags(),
                                    v[0],
                                    lay.offsets[*k] as i32,
                                )
                            })
                            .collect()
                    }
                    _ => idx.iter().map(|k| v[*k]).collect(),
                }
            }
            Op::TypeRelease => {
                let Imm::TypeMask(_, mask) = inst.imm else {
                    unreachable!()
                };
                let ty = f.ty(inst.args[0]);
                let held = self.a(inst, 0);
                if self.type_block(ty).is_some() {
                    self.type_release(ty, held[0], mask as u64);
                    return vec![];
                }
                for (k, (fty, at, w)) in self.fields_of(ty).into_iter().enumerate() {
                    if mask >> k & 1 == 0 {
                        self.drop_value(fty, &held[at..at + w]);
                    }
                }
                vec![]
            }
            Op::AltRelease => {
                let Imm::AltMask(a, c, mask) = inst.imm else {
                    unreachable!()
                };
                let ty = f.ty(inst.args[0]);
                let case = self.alt_fields(a)[c as usize].clone();
                let v = self.a(inst, 0);
                let boxed = match &self.g.lay.shape(ty).alt {
                    Some(AltRepr::Boxed { block, .. }) => Some(block.clone()),
                    _ => None,
                };
                // Drop the payload fields that were not moved out, then free the block.
                for (k, (fty, idx)) in case.iter().enumerate() {
                    if mask >> k & 1 == 1 || !m.needs_drop(*fty) {
                        continue;
                    }
                    let fv: Vs = match &boxed {
                        Some(block) => {
                            let lay = mem_layout(block);
                            idx.iter()
                                .map(|j| {
                                    self.b.ins().load(
                                        leaf_type(block[*j]),
                                        flags(),
                                        v[0],
                                        lay.offsets[*j] as i32,
                                    )
                                })
                                .collect()
                        }
                        None => idx.iter().map(|j| v[*j]).collect(),
                    };
                    self.drop_value(*fty, &fv);
                }
                if boxed.is_some() {
                    self.free(v[0]);
                }
                vec![]
            }
            Op::AltUnbox => {
                let Imm::AltField(a, c, i) = inst.imm else {
                    unreachable!()
                };
                let ty = f.ty(inst.args[0]);
                let case = self.alt_fields(a)[c as usize].clone();
                let v = self.a(inst, 0);
                let boxed = match &self.g.lay.shape(ty).alt {
                    Some(AltRepr::Boxed { block, .. }) => Some(block.clone()),
                    _ => None,
                };
                // Read every payload leaf of the case, drop all fields but `i`, free the block.
                let fields: Vec<Vs> = case
                    .iter()
                    .map(|(_, idx)| match &boxed {
                        Some(block) => {
                            let lay = mem_layout(block);
                            idx.iter()
                                .map(|k| {
                                    self.b.ins().load(
                                        leaf_type(block[*k]),
                                        flags(),
                                        v[0],
                                        lay.offsets[*k] as i32,
                                    )
                                })
                                .collect()
                        }
                        None => idx.iter().map(|k| v[*k]).collect(),
                    })
                    .collect();
                for (k, ((fty, _), fv)) in case.iter().zip(&fields).enumerate() {
                    if k != i as usize {
                        self.drop_value(*fty, fv);
                    }
                }
                if boxed.is_some() {
                    self.free(v[0]);
                }
                fields[i as usize].clone()
            }
            _ => unreachable!("alternatives is only called for its own ops"),
        }
    }

    /// Lists.
    pub(super) fn lists(&mut self, f: &Func, inst: &Inst) -> Vs {
        match inst.op {
            Op::ListNew
            | Op::ListLit
            | Op::ListConst
            | Op::ListLen
            | Op::ListGet
            | Op::ListGetNn
            | Op::ListGetU
            | Op::ListSet
            | Op::ListSetNn
            | Op::ListSetU
            | Op::ListFill
            | Op::ListPush
            | Op::ListDropLast => self.lower_list(f, inst),
            Op::ListTake => {
                let lt = f.ty(inst.args[0]);
                let (_, leaves, size) = self.elem_info(lt);
                let l = self.a(inst, 0);
                let i = self.a(inst, 1)[0];
                let at = self.elem_addr(l[0], l[1], i, size, Op::ListGetU);
                self.load_leaves(at, 0, &leaves)
            }
            Op::ListRelease => {
                let lt = f.ty(inst.args[0]);
                let l = self.a(inst, 0);
                let from = self.a(inst, 1)[0];
                // A view (`cap == 0`, from `slice` of a lent list) owns nothing to release.
                let owned = self.b.ins().icmp_imm_s(IntCC::NotEqual, l[2], 0);
                self.if_then(owned, |s| s.drop_list_from(lt, l[0], l[1], Some(from)));
                vec![]
            }
            _ => unreachable!("lists is only called for its own ops"),
        }
    }

    /// Optionals.
    pub(super) fn optionals(&mut self, f: &Func, inst: &Inst) -> Vs {
        let checks = self.g.opts.checks;
        let res_ty = inst.res.map(|r| f.ty(r));
        match inst.op {
            Op::OptSome | Op::OptView => {
                let ty = res_ty.expect("opt.some result");
                let v = self.a(inst, 0);
                if self.opt_boxed(ty) {
                    assert!(
                        inst.op == Op::OptSome,
                        "a borrowed optional cannot have a boxed layout"
                    );
                    let TyKind::Opt(inner) = self.g.m.types.kind(ty).clone() else {
                        unreachable!()
                    };
                    let leaves = self.g.lay.leaves(inner);
                    let p = self.alloc(mem_layout(&leaves).size as i64);
                    self.store_leaves(p, 0, &leaves, &v);
                    vec![p]
                } else if self.opt_niche(ty) {
                    v
                } else {
                    let one = self.b.ins().iconst(types::I8, 1);
                    let mut out = vec![one];
                    out.extend(v);
                    out
                }
            }
            Op::OptNone => {
                let ty = res_ty.expect("opt.none result");
                self.zeros(ty)
            }
            Op::OptIsSome => {
                let ty = f.ty(inst.args[0]);
                let v = self.a(inst, 0);
                if self.opt_niche(ty) {
                    vec![self.opt_present(ty, &v)]
                } else {
                    vec![v[0]]
                }
            }
            Op::OptGet | Op::OptUnwrap => {
                let ty = f.ty(inst.args[0]);
                let v = self.a(inst, 0);
                let nullable = self.opt_niche(ty);
                if inst.op == Op::OptUnwrap && checks {
                    // Every layout keeps the presence word (null pointer or tag) first; an
                    // optional string also needs its tag.
                    let none = if self.g.lay.is_str_like(ty) {
                        let some = self.opt_present(ty, &v);
                        self.b.ins().icmp_imm_s(IntCC::Equal, some, 0)
                    } else {
                        self.b.ins().icmp_imm_s(IntCC::Equal, v[0], 0)
                    };
                    self.fault_if(none, "msrt_fault_unwrap_none", vec![]);
                }
                let TyKind::Opt(inner) = self.g.m.types.kind(ty).clone() else {
                    unreachable!()
                };
                let payload = if self.opt_boxed(ty) {
                    let leaves = self.g.lay.leaves(inner);
                    self.load_leaves(v[0], 0, &leaves)
                } else if nullable {
                    v
                } else {
                    v[1..].to_vec()
                };
                // `unwrap` returns an owned value; `get` borrows.
                if inst.op == Op::OptUnwrap {
                    self.clone_value(inner, &payload)
                } else {
                    payload
                }
            }
            Op::OptAddr => {
                // The payload of a boxed optional lies at the box; no other layout has an address.
                assert!(
                    self.opt_boxed(f.ty(inst.args[0])),
                    "opt.addr of an optional that is not boxed"
                );
                self.a(inst, 0)
            }
            Op::OptUnbox => {
                // Moves the payload out of a some: the box (if any) is freed, the payload lives on.
                let ty = f.ty(inst.args[0]);
                let v = self.a(inst, 0);
                let TyKind::Opt(inner) = self.g.m.types.kind(ty).clone() else {
                    unreachable!()
                };
                if self.opt_boxed(ty) {
                    let leaves = self.g.lay.leaves(inner);
                    let payload = self.load_leaves(v[0], 0, &leaves);
                    self.free(v[0]);
                    payload
                } else if self.opt_niche(ty) {
                    v
                } else {
                    v[1..].to_vec()
                }
            }
            _ => unreachable!("optionals is only called for its own ops"),
        }
    }

    /// Strings.
    pub(super) fn strings(&mut self, inst: &Inst) -> Vs {
        match inst.op {
            Op::StrByte => {
                // An inline string's bytes are its two words, little-endian.
                let (s, i) = (self.a(inst, 0), self.a(inst, 1)[0]);
                let inline = self.str_is_inline(s[1]);
                let (word, mem, join) = (
                    self.b.create_block(),
                    self.b.create_block(),
                    self.b.create_block(),
                );
                self.b.append_block_param(join, types::I64);
                self.b.ins().brif(inline, word, &[], mem, &[]);
                self.b.switch_to_block(word);
                let high = self
                    .b
                    .ins()
                    .icmp_imm_s(IntCC::SignedGreaterThanOrEqual, i, 8);
                let w = self.b.ins().select(high, s[1], s[0]);
                let shift = self.b.ins().band_imm_s(i, 7);
                let shift = self.b.ins().ishl_imm_u(shift, 3);
                let w = self.b.ins().ushr(w, shift);
                let w = self.b.ins().band_imm_s(w, 0xff);
                self.b.ins().jump(join, &[BlockArg::Value(w)]);
                self.b.switch_to_block(mem);
                let at = self.b.ins().iadd(s[0], i);
                let byte = self.b.ins().load(types::I8, flags(), at, 0);
                let byte = self.b.ins().uextend(types::I64, byte);
                self.b.ins().jump(join, &[BlockArg::Value(byte)]);
                self.b.switch_to_block(join);
                vec![self.b.block_params(join)[0]]
            }
            Op::StrAsciiAt => {
                // The byte at a scalar index when the string is flagged all ASCII and the index
                // is in range, else -1 (the caller then takes the general path).
                let (s, i) = (self.a(inst, 0), self.a(inst, 1)[0]);
                let flag = self.b.ins().ushr_imm_u(s[1], 61);
                let flag = self.b.ins().band_imm_s(flag, 3);
                let ascii = self.b.ins().icmp_imm_s(IntCC::Equal, flag, 1);
                let len = self.b.ins().band_imm_s(s[1], STR_LEN_MASK as i64);
                let below = self.b.ins().icmp(IntCC::UnsignedLessThan, i, len);
                let ok = self.b.ins().band(ascii, below);
                let (load, join) = (self.b.create_block(), self.b.create_block());
                self.b.append_block_param(join, types::I64);
                let miss = self.iconst(-1);
                self.b
                    .ins()
                    .brif(ok, load, &[], join, &[BlockArg::Value(miss)]);
                self.b.switch_to_block(load);
                let at = self.b.ins().iadd(s[0], i);
                let byte = self.b.ins().load(types::I8, flags(), at, 0);
                let byte = self.b.ins().uextend(types::I64, byte);
                self.b.ins().jump(join, &[BlockArg::Value(byte)]);
                self.b.switch_to_block(join);
                vec![self.b.block_params(join)[0]]
            }
            Op::StrAsciiLen => {
                // The byte length of an inline string with no byte at or above 0x80, or of a
                // string flagged ASCII; else -1.
                let s = self.a(inst, 0);
                let (miss, zero) = (self.iconst(-1), self.iconst(0));
                let tag = self.b.ins().ushr_imm_u(s[1], 62);
                let inline = self.b.ins().icmp_imm_s(IntCC::Equal, tag, 1);
                let high0 = self
                    .b
                    .ins()
                    .band_imm_s(s[0], 0x8080_8080_8080_8080u64 as i64);
                let high1 = self.b.ins().band_imm_s(s[1], 0x0080_8080_8080_8080);
                let high = self.b.ins().bor(high0, high1);
                let low = self.b.ins().icmp(IntCC::Equal, high, zero);
                let shifted = self.b.ins().ushr_imm_u(s[1], STR_INLINE_LEN_SHIFT as i64);
                let inline_len = self.b.ins().band_imm_s(shifted, STR_INLINE_MAX as i64);
                let inline_len = self.b.ins().select(low, inline_len, miss);
                let flag = self.b.ins().ushr_imm_u(s[1], 61);
                let flag = self.b.ins().band_imm_s(flag, 3);
                let flagged = self.b.ins().icmp_imm_s(IntCC::Equal, flag, 1);
                let len = self.b.ins().band_imm_s(s[1], STR_LEN_MASK as i64);
                let other = self.b.ins().select(flagged, len, miss);
                vec![self.b.ins().select(inline, inline_len, other)]
            }
            Op::StrAscii => {
                let b = self.a(inst, 0)[0];
                let d = self.g.rt_data("msrt_ascii_chars");
                let base = self.data_addr(d);
                let off = self.b.ins().imul_imm_s(b, ASCII_CHAR_STRIDE as i64);
                let ptr = self.b.ins().iadd(base, off);
                let tagged = self.iconst(1 | STR_STATIC as i64);
                vec![ptr, tagged]
            }
            Op::StrLen => {
                // Scalar count: computed by the runtime (long strings are remembered there).
                let s = self.a(inst, 0);
                let at = match self.home_of(inst.args[0]) {
                    Some(h) => h.addr,
                    None => self.spill_temp(&s, &[Leaf::I64; 2]),
                };
                vec![self.rt_call("msrt_string_length", &[at])[0]]
            }
            _ => unreachable!("strings is only called for its own ops"),
        }
    }
}
