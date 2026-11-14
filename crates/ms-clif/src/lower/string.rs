//! String equality and string-builder lowering.

use super::*;

impl<'a, 'm> Lower<'a, 'm> {
    /// Calls a runtime function with the ABI mapping of `ms-rt`: aggregates by pointer
    /// to a spilled copy, aggregate results through a trailing out pointer.
    /// `s == "lit"` for a literal of one to eight bytes without a NUL, compared inline: the
    /// length word, then the bytes in power-of-two chunks (read only once the length matches,
    /// so no load passes the object's NUL terminator).
    pub(super) fn string_eq_literal(&mut self, inst: &Inst) -> Option<Vs> {
        let (lit, other) = match (
            self.str_lits.get(&inst.args[0].index()),
            self.str_lits.get(&inst.args[1].index()),
        ) {
            (_, Some(l)) => (*l, self.a(inst, 0)),
            (Some(l), None) => (*l, self.a(inst, 1)),
            (None, None) => return None,
        };
        let bytes = self.g.m.strings[lit as usize].as_bytes().to_vec();
        if bytes.is_empty() || bytes.len() > 8 || bytes.contains(&0) {
            return None;
        }
        let unaligned = MemFlagsData::new().with_notrap();
        // The literal as an inline string: equal words. Another kind of string compares its
        // masked length (never the literal's for an inline string) and then its bytes.
        let mut word = [0u8; 8];
        word[..bytes.len()].copy_from_slice(&bytes);
        let inline_tag = (STR_INLINE | (bytes.len() << STR_INLINE_LEN_SHIFT)) as i64;
        let same_tag = self.b.ins().icmp_imm_s(IntCC::Equal, other[1], inline_tag);
        let same_word = self
            .b
            .ins()
            .icmp_imm_s(IntCC::Equal, other[0], i64::from_le_bytes(word));
        let inline_eq = self.b.ins().band(same_tag, same_word);
        let len = self.b.ins().band_imm_s(other[1], STR_LEN_MASK as i64);
        let same_len = self
            .b
            .ins()
            .icmp_imm_s(IntCC::Equal, len, bytes.len() as i64);
        let check = self.b.create_block();
        let join = self.b.create_block();
        self.b.append_block_param(join, types::I8);
        let no = self.b.ins().iconst(types::I8, 0);
        self.b
            .ins()
            .brif(same_len, check, &[], join, &[BlockArg::Value(inline_eq)]);
        let _ = no;
        self.b.switch_to_block(check);
        let mut all = None;
        let mut at = 0;
        while at < bytes.len() {
            let n = [8, 4, 2, 1]
                .into_iter()
                .find(|n| bytes.len() - at >= *n)
                .unwrap();
            let ty = match n {
                8 => types::I64,
                4 => types::I32,
                2 => types::I16,
                _ => types::I8,
            };
            let mut word = [0u8; 8];
            word[..n].copy_from_slice(&bytes[at..at + n]);
            let shift = 64 - 8 * n as u32;
            let want = (i64::from_le_bytes(word) << shift) >> shift;
            let got = self.b.ins().load(ty, unaligned, other[0], at as i32);
            let eq = self.b.ins().icmp_imm_s(IntCC::Equal, got, want);
            all = Some(match all {
                Some(a) => self.b.ins().band(a, eq),
                None => eq,
            });
            at += n;
        }
        self.b
            .ins()
            .jump(join, &[BlockArg::Value(all.expect("non-empty literal"))]);
        self.b.switch_to_block(join);
        Some(vec![self.b.block_params(join)[0]])
    }

    /// `a == b` for two strings: differing lengths are unequal and identical pointers equal without
    /// a call; only same-length distinct blocks reach the runtime.
    pub(super) fn string_eq_inline(&mut self, f: &Func, inst: &Inst) -> Vs {
        let (a, b) = (self.a(inst, 0), self.a(inst, 1));
        let join = self.b.create_block();
        self.b.append_block_param(join, types::I8);
        let no = self.b.ins().iconst(types::I8, 0);
        let (same_hi, other_kind, slow) = (
            self.b.create_block(),
            self.b.create_block(),
            self.b.create_block(),
        );
        // `x = a.tagged ^ b.tagged`. With `0 < x < 1 << 62` both have one kind and the low bits
        // differ: different lengths, or for inline strings different bytes. Either way unequal.
        // The ASCII flag may differ between equal strings, so it is masked out.
        let x = self.b.ins().bxor(a[1], b[1]);
        let x = self.b.ins().band_imm_s(x, !(STR_ASCII as i64));
        let below = self.b.ins().iadd_imm_s(x, -1);
        let differ =
            self.b
                .ins()
                .icmp_imm_u(IntCC::UnsignedLessThan, below, (STR_INLINE - 1) as i64);
        let undecided = self.b.create_block();
        self.b
            .ins()
            .brif(differ, join, &[BlockArg::Value(no)], undecided, &[]);
        self.b.switch_to_block(undecided);
        let is_same = self.b.ins().icmp_imm_s(IntCC::Equal, x, 0);
        self.b.ins().brif(is_same, same_hi, &[], other_kind, &[]);
        // Same second word: the same first word is the same string. Otherwise inline strings
        // differ, and other kinds of one length compare their bytes.
        self.b.switch_to_block(same_hi);
        let same_ptr = self.b.ins().icmp(IntCC::Equal, a[0], b[0]);
        let inline = self.str_is_inline(a[1]);
        let known = self.b.ins().bor(same_ptr, inline);
        self.b
            .ins()
            .brif(known, join, &[BlockArg::Value(same_ptr)], slow, &[]);
        // Different kinds are equal only with the same byte length; the runtime compares bytes.
        self.b.switch_to_block(other_kind);
        let (la, lb) = (self.str_byte_len(a[1]), self.str_byte_len(b[1]));
        let same_len = self.b.ins().icmp(IntCC::Equal, la, lb);
        self.b
            .ins()
            .brif(same_len, slow, &[], join, &[BlockArg::Value(no)]);
        self.b.switch_to_block(slow);
        let r = self.call_extern_plain(f, inst);
        self.b.ins().jump(join, &[BlockArg::Value(r[0])]);
        self.b.switch_to_block(join);
        vec![self.b.block_params(join)[0]]
    }

    /// `StringBuilder.append` of a literal of 1 to 16 bytes with room to spare is a few constant
    /// stores and a length bump. The bytes are known here, so no length decode or copy loop
    /// remains; a full buffer calls the runtime.
    pub(super) fn strbuilder_append_literal(
        &mut self,
        id: FuncId,
        builder: Value,
        text: Value,
        bytes: &[u8],
    ) -> Vs {
        let n = bytes.len();
        let len = self
            .b
            .ins()
            .load(types::I64, flags(), builder, VEC_LEN_OFFSET as i32);
        let cap = self
            .b
            .ins()
            .load(types::I64, flags(), builder, VEC_CAP_OFFSET as i32);
        let next = self.b.ins().iadd_imm_s(len, n as i64);
        let room = self.b.ins().icmp(IntCC::UnsignedLessThanOrEqual, next, cap);
        let store = self.b.create_block();
        let slow = self.b.create_block();
        self.b.set_cold_block(slow);
        let join = self.b.create_block();
        self.b.ins().brif(room, store, &[], slow, &[]);
        self.b.switch_to_block(store);
        let data = self
            .b
            .ins()
            .load(types::I64, flags(), builder, VEC_PTR_OFFSET as i32);
        let at = self.b.ins().iadd(data, len);
        // Overlapping stores of the widest width that fits cover every length without a loop.
        let unaligned = MemFlagsData::new().with_notrap();
        let word = |from: usize, w: usize| {
            let mut x = 0u64;
            for (i, b) in bytes[from..from + w].iter().enumerate() {
                x |= (*b as u64) << (8 * i);
            }
            x as i64
        };
        let (w, ty) = match n {
            8..=16 => (8, types::I64),
            4..=7 => (4, types::I32),
            2..=3 => (2, types::I16),
            _ => (1, types::I8),
        };
        let first = self.b.ins().iconst(ty, word(0, w));
        self.b.ins().store(unaligned, first, at, 0);
        if n > w {
            let last = self.b.ins().iconst(ty, word(n - w, w));
            self.b.ins().store(unaligned, last, at, (n - w) as i32);
        }
        self.b
            .ins()
            .store(flags(), next, builder, VEC_LEN_OFFSET as i32);
        self.b.ins().jump(join, &[]);
        self.b.switch_to_block(slow);
        self.call_id(id, &[builder, text]);
        self.b.ins().jump(join, &[]);
        self.b.switch_to_block(join);
        Vec::new()
    }

    /// `StringBuilder.append` of a string with room to spare is a capacity check, a copy and a
    /// length bump: a one-byte string is a store, anything longer one `memcpy`. An inline string
    /// (whose length sits in different bits) and a full buffer call the runtime, which makes the
    /// same tests first.
    pub(super) fn strbuilder_append(&mut self, id: FuncId, builder: Value, text: Value) -> Vs {
        let len = self
            .b
            .ins()
            .load(types::I64, flags(), builder, VEC_LEN_OFFSET as i32);
        let cap = self
            .b
            .ins()
            .load(types::I64, flags(), builder, VEC_CAP_OFFSET as i32);
        let tagged = self
            .b
            .ins()
            .load(types::I64, flags(), text, STR_LEN_OFFSET as i32);
        let size = self.b.ins().band_imm_s(tagged, STR_LEN_MASK as i64);
        let tag = self.b.ins().ushr_imm_u(tagged, 62);
        let flat = self.b.ins().icmp_imm_s(IntCC::NotEqual, tag, 1);
        let next = self.b.ins().iadd(len, size);
        let room = self.b.ins().icmp(IntCC::UnsignedLessThanOrEqual, next, cap);
        let fast = self.b.ins().band(flat, room);
        let store = self.b.create_block();
        let slow = self.b.create_block();
        self.b.set_cold_block(slow);
        let join = self.b.create_block();
        self.b.ins().brif(fast, store, &[], slow, &[]);
        self.b.switch_to_block(store);
        let bytes = self
            .b
            .ins()
            .load(types::I64, flags(), text, STR_PTR_OFFSET as i32);
        let data = self
            .b
            .ins()
            .load(types::I64, flags(), builder, VEC_PTR_OFFSET as i32);
        let at = self.b.ins().iadd(data, len);
        let single = self.b.ins().icmp_imm_s(IntCC::Equal, size, 1);
        let one = self.b.create_block();
        let many = self.b.create_block();
        let done = self.b.create_block();
        self.b.ins().brif(single, one, &[], many, &[]);
        self.b.switch_to_block(one);
        let byte = self.b.ins().load(types::I8, flags(), bytes, 0);
        self.b.ins().store(flags(), byte, at, 0);
        self.b.ins().jump(done, &[]);
        self.b.switch_to_block(many);
        self.b
            .call_memcpy(self.g.module.target_config(), at, bytes, size);
        self.b.ins().jump(done, &[]);
        self.b.switch_to_block(done);
        self.b
            .ins()
            .store(flags(), next, builder, VEC_LEN_OFFSET as i32);
        self.b.ins().jump(join, &[]);
        self.b.switch_to_block(slow);
        self.call_id(id, &[builder, text]);
        self.b.ins().jump(join, &[]);
        self.b.switch_to_block(join);
        Vec::new()
    }

    /// `bytes.push`: a byte value with room to spare is a store and a length bump, and the result
    /// says so; an out-of-range value (which faults) or a full buffer leaves it to the runtime
    /// call that follows.
    pub(super) fn bytes_push(&mut self, inst: &Inst) -> Vs {
        let (builder, value) = (self.a(inst, 0)[0], self.a(inst, 1)[0]);
        let len = self
            .b
            .ins()
            .load(types::I64, flags(), builder, VEC_LEN_OFFSET as i32);
        let cap = self
            .b
            .ins()
            .load(types::I64, flags(), builder, VEC_CAP_OFFSET as i32);
        let byte = self
            .b
            .ins()
            .icmp_imm_s(IntCC::UnsignedLessThanOrEqual, value, 255);
        let room = self.b.ins().icmp(IntCC::UnsignedLessThan, len, cap);
        let fast = self.b.ins().band(byte, room);
        let (store, join) = (self.b.create_block(), self.b.create_block());
        self.b.append_block_param(join, types::I8);
        let no = self.b.ins().iconst(types::I8, 0);
        self.b
            .ins()
            .brif(fast, store, &[], join, &[BlockArg::Value(no)]);
        self.b.switch_to_block(store);
        let data = self
            .b
            .ins()
            .load(types::I64, flags(), builder, VEC_PTR_OFFSET as i32);
        let at = self.b.ins().iadd(data, len);
        let narrow = self.b.ins().ireduce(types::I8, value);
        self.b.ins().store(flags(), narrow, at, 0);
        let next = self.b.ins().iadd_imm_s(len, 1);
        self.b
            .ins()
            .store(flags(), next, builder, VEC_LEN_OFFSET as i32);
        let yes = self.b.ins().iconst(types::I8, 1);
        self.b.ins().jump(join, &[BlockArg::Value(yes)]);
        self.b.switch_to_block(join);
        vec![self.b.block_params(join)[0]]
    }
}
