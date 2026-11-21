//! Runtime fast paths as inlinable MIR: `String.view`, byte reads and searches. Map and set
//! lookups are inlined by the C `probe` pass (`compiler/src/opt/opt_probe.c`).
//!
//! `String.view` of ASCII text with bounds inside it is two words computed in the caller; the
//! rest (inline or non-ASCII text, negative bounds, a fault) calls the runtime.

use crate::cx::HelperKey;
use crate::func::FnLower;
use crate::text::runtime_fn;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{Block, Cc, FuncId, Imm, Mode, Op, Param, Value};
use ms_mir::types::Ty as MTy;

fn load(b: &mut FuncBuilder<'_>, p: Value, at: i64, ty: MTy) -> Value {
    let p = add(b, p, at);
    b.emit(Op::Load, &[p], Imm::Ty(ty), Some(ty)).expect("load")
}

fn add(b: &mut FuncBuilder<'_>, p: Value, at: i64) -> Value {
    if at == 0 {
        return p;
    }
    let off = b.iconst(at);
    b.emit(Op::PtrAdd, &[p, off], Imm::None, Some(MTy::PTR))
        .expect("ptr.add")
}

fn int(b: &mut FuncBuilder<'_>, op: Op, x: Value, y: i64) -> Value {
    let y = b.iconst(y);
    b.binop(op, x, y)
}

/// The one way a generated fast path is made: an internal function marked `inline(always)` that
/// does the common case itself and calls the runtime for the rest, built once per `HelperKey`.
/// Every inlinable runtime call (`inline_probe`, `inline_str`) goes through these three steps.
impl<'a> FnLower<'a> {
    pub(crate) fn fast_path_cached(&self, key: &HelperKey) -> Option<FuncId> {
        self.cx.helpers.get(key).copied()
    }

    pub(crate) fn fast_path_builder(
        &mut self,
        name: &str,
        params: Vec<Param>,
        ret: MTy,
    ) -> FuncBuilder<'_> {
        FuncBuilder::fast_path(self.b.m, name, params, ret)
    }

    pub(crate) fn fast_path_add(&mut self, key: HelperKey, func: ms_mir::ir::Func) -> FuncId {
        let fid = self.b.m.add_func(func);
        self.cx.helpers.insert(key, fid);
        fid
    }
}

impl FnLower<'_> {
    /// Calls the generated probe for the runtime symbol `sym` when it has one: `args` are the map,
    /// the key and value descriptors (unused), the address of the key, and for a `get` the
    /// address to copy the value to.
    pub(crate) fn inline_probe(&mut self, sym: &str, args: &[Value], ret: MTy) -> Option<Value> {
        if sym == "msrt_bytes_read_word" && args.len() == 5 {
            let f = self.read_word_fn();
            return Some(self.b.call(f, args));
        }
        if sym == "msrt_bytes_index_of_byte" && args.len() == 4 {
            let f = self.index_of_byte_fn();
            let mut args = args.to_vec();
            if self.ty_of(args[1]) != MTy::INT {
                args[1] = self.b.conv(args[1], MTy::INT);
            }
            return Some(self.b.call(f, &args));
        }
        if let Some(which) = self.str_fast(sym, args) {
            let f = self.str_fn(which);
            return Some(self.b.call(f, args));
        }
        // A literal needle of two or more bytes skips the dispatch on the needle's length.
        if sym == "msrt_string_contains"
            && let Some(id) = self.b.str_lit_of(args[1])
            && self.b.m.strings[id.0 as usize].len() >= 2
        {
            let ext = crate::text::runtime_fn(
                self.b.m,
                "msrt_string_contains_multi",
                &[MTy::STR, MTy::STR],
                MTy::BOOL,
            );
            return Some(self.b.call_rt(ext, args));
        }
        if sym == "msrt_string_view" {
            let f = self.view_fn(false);
            return Some(self.b.call(f, args));
        }
        if sym == "msrt_string_slice" && args.len() == 3 && ret == MTy::STR {
            // The runtime returns the copy; the generated twin writes it through a slot.
            let f = self.view_fn(true);
            let slot = self
                .b
                .emit(Op::Slot, &[], Imm::Ty(MTy::STR), Some(MTy::PTR))
                .expect("slot");
            self.b.call(f, &[args[0], args[1], args[2], slot]);
            return self
                .b
                .emit(Op::Take, &[slot], Imm::Ty(MTy::STR), Some(MTy::STR));
        }
        if sym == "msrt_bytes_view" && args.len() == 4 {
            let f = self.bytes_view_fn(self.ty_of(args[0]));
            return Some(self.b.call(f, args));
        }
        // Map and set lookups stay runtime calls: the `probe` pass inlines them.
        None
    }
}

/// `String.view(start, end)` on the text at `s` (a slot holding the string): a flagged-ASCII text
/// with `0 <= start <= end <= len` continues in a fresh block; anything else branches to `slow`.
fn inline_view_guard(
    b: &mut FuncBuilder<'_>,
    s: Value,
    w1: Value,
    start: Value,
    end: Value,
    slow: Block,
) {
    let len = int(b, Op::Ushr, w1, 56);
    let len = int(b, Op::And, len, 15);
    let zero = b.iconst(0);
    let (a, c, d) = (
        b.icmp(Cc::Ge, start, zero),
        b.icmp(Cc::Le, start, end),
        b.icmp(Cc::Le, end, len),
    );
    // Every byte below 0x80: no scalar boundary to test.
    let lo = load(b, s, 0, MTy::INT);
    let hi = int(b, Op::And, w1, (1 << 56) - 1);
    let any = b.binop(Op::Or, lo, hi);
    let high = int(b, Op::And, any, 0x8080_8080_8080_8080_u64 as i64);
    let ascii = b.icmp(Cc::Eq, high, zero);
    let mut ok = b.binop(Op::And, a, c);
    for cond in [d, ascii] {
        ok = b.binop(Op::And, ok, cond);
    }
    let fast = b.new_block();
    b.br_if(ok, fast, &[], slow, &[]);
    b.seal_block(fast);
    b.switch_to(fast);
}

fn view_guard(b: &mut FuncBuilder<'_>, s: Value, start: Value, end: Value, slow: Block) {
    let w1 = load(b, s, 8, MTy::INT);
    let tag = int(b, Op::Ushr, w1, 62);
    let one = b.iconst(1);
    let flat = b.icmp(Cc::Ne, tag, one);
    let ascii = int(b, Op::And, w1, 1 << 61);
    let zero = b.iconst(0);
    let flagged = b.icmp(Cc::Ne, ascii, zero);
    let len = int(b, Op::And, w1, ms_rt_abi::STR_LEN_MASK as i64);
    let (a, c, d) = (
        b.icmp(Cc::Ge, start, zero),
        b.icmp(Cc::Le, start, end),
        b.icmp(Cc::Le, end, len),
    );
    let mut ok = flat;
    for cond in [a, c, d] {
        ok = b.binop(Op::And, ok, cond);
    }
    let (fast, bounded, scan) = (b.new_block(), b.new_block(), b.new_block());
    b.br_if(ok, bounded, &[], slow, &[]);
    b.seal_block(bounded);
    b.switch_to(bounded);
    b.br_if(flagged, fast, &[], scan, &[]);
    b.seal_block(scan);
    // Text not flagged ASCII (a literal, or a producer that does not scan): both ends must start
    // a scalar. Every string is followed by a NUL, so the byte at `end` is readable and a boundary
    // at the very end.
    b.switch_to(scan);
    let w0 = load(b, s, 0, MTy::PTR);
    let boundary = |b: &mut FuncBuilder<'_>, at: Value| {
        let p = b
            .emit(Op::PtrAdd, &[w0, at], Imm::None, Some(MTy::PTR))
            .expect("ptr.add");
        let byte = b
            .emit(Op::PtrLoadU, &[p], Imm::Int(1), Some(MTy::INT))
            .expect("ptr.loadu");
        let cont = int(b, Op::And, byte, 0xC0);
        let cm = b.iconst(0x80);
        b.icmp(Cc::Ne, cont, cm)
    };
    let first = boundary(b, start);
    let last = boundary(b, end);
    let both = b.binop(Op::And, first, last);
    b.br_if(both, fast, &[], slow, &[]);
    b.seal_block(fast);
    b.switch_to(fast);
}

impl FnLower<'_> {
    /// The generated `String.view`: parameters the string, `start` and `end`.
    /// `Bytes.view(start, end)` with `0 < end - start` and `0 <= start <= end <= len`: a view
    /// `{ptr + start, end - start, 0}` stored to `out` with no call; an empty range, a negative
    /// bound or a fault continues in the runtime.
    fn bytes_view_fn(&mut self, bytes_ty: MTy) -> FuncId {
        let key = HelperKey::BytesView(bytes_ty);
        if let Some(f) = self.fast_path_cached(&key) {
            return f;
        }
        let param = |ty| Param {
            ty,
            mode: Mode::Borrow,
        };
        let params = vec![
            param(bytes_ty),
            param(MTy::INT),
            param(MTy::INT),
            param(MTy::PTR),
        ];
        let ext = runtime_fn(
            self.b.m,
            "msrt_bytes_view",
            &[bytes_ty, MTy::INT, MTy::INT, MTy::PTR],
            MTy::VOID,
        );
        let mut b = self.fast_path_builder("bytes_view", params, MTy::VOID);
        let ps = b.params();
        let (bytes, start, end, out) = (ps[0], ps[1], ps[2], ps[3]);
        let (fast, slow, join) = (b.new_block(), b.new_block(), b.new_block());
        // A `Bytes` held in memory arrives as its address; a value is stored to a slot to be
        // read through its memory form.
        let s = if bytes_ty == MTy::PTR {
            bytes
        } else {
            let slot = b
                .emit(Op::Slot, &[], Imm::Ty(bytes_ty), Some(MTy::PTR))
                .expect("slot");
            b.emit(Op::Store, &[slot, bytes], Imm::None, None);
            slot
        };
        let len = load(&mut b, s, 8, MTy::INT);
        let zero = b.iconst(0);
        let (a, c, d) = (
            b.icmp(Cc::Ge, start, zero),
            b.icmp(Cc::Lt, start, end),
            b.icmp(Cc::Le, end, len),
        );
        let mut ok = b.binop(Op::And, a, c);
        ok = b.binop(Op::And, ok, d);
        b.br_if(ok, fast, &[], slow, &[]);
        b.seal_block(fast);
        b.seal_block(slow);
        b.switch_to(fast);
        let data = load(&mut b, s, 0, MTy::PTR);
        let p = b
            .emit(Op::PtrAdd, &[data, start], Imm::None, Some(MTy::PTR))
            .expect("ptr.add");
        let n = b.binop(Op::ISub, end, start);
        b.emit(Op::Store, &[out, p], Imm::None, None);
        let out8 = add(&mut b, out, 8);
        b.emit(Op::Store, &[out8, n], Imm::None, None);
        let out16 = add(&mut b, out, 16);
        b.emit(Op::Store, &[out16, zero], Imm::None, None);
        b.br(join, &[]);
        b.switch_to(slow);
        b.call_rt(ext, &[bytes, start, end, out]);
        b.br(join, &[]);
        b.seal_block(join);
        b.switch_to(join);
        let unit = b.unit();
        b.ret(Some(unit));
        let func = b.into_func();
        self.fast_path_add(key, func)
    }

    /// The generated `String.view` (`slice` false) or `String.slice` (true). They share the
    /// guard and the inline form of a piece of up to fifteen bytes. A longer view borrows the
    /// receiver's bytes, while a longer slice is an owned copy, which the runtime makes.
    fn view_fn(&mut self, slice: bool) -> FuncId {
        let key = if slice {
            HelperKey::StringSlice
        } else {
            HelperKey::StringView
        };
        if let Some(f) = self.fast_path_cached(&key) {
            return f;
        }
        let param = |ty| Param {
            ty,
            mode: Mode::Borrow,
        };
        let params = vec![
            param(MTy::STR),
            param(MTy::INT),
            param(MTy::INT),
            param(MTy::PTR),
        ];
        let ext = runtime_fn(
            self.b.m,
            if slice {
                "msrt_string_slice"
            } else {
                "msrt_string_view"
            },
            &[MTy::STR, MTy::INT, MTy::INT, MTy::PTR],
            MTy::VOID,
        );
        let mut b = self.fast_path_builder(
            if slice { "string_slice" } else { "string_view" },
            params,
            MTy::VOID,
        );
        let ps = b.params();
        let (text, start, end, out) = (ps[0], ps[1], ps[2], ps[3]);
        let (slow, join, flat_block, inl) =
            (b.new_block(), b.new_block(), b.new_block(), b.new_block());
        let s = b
            .emit(Op::Slot, &[], Imm::Ty(MTy::STR), Some(MTy::PTR))
            .expect("slot");
        b.emit(Op::Store, &[s, text], Imm::None, None);
        let w1 = load(&mut b, s, 8, MTy::INT);
        let tag = int(&mut b, Op::Ushr, w1, 62);
        let one = b.iconst(1);
        let is_inline = b.icmp(Cc::Eq, tag, one);
        b.br_if(is_inline, inl, &[], flat_block, &[]);
        b.seal_block(inl);
        b.seal_block(flat_block);
        let (short, long) = (b.new_block(), b.new_block());
        let sp = b.add_block_param(short, MTy::PTR, Mode::Borrow);
        let sn = b.add_block_param(short, MTy::INT, Mode::Borrow);
        // An inline text: its bytes sit in the slot, so an ASCII range of it is packed straight
        // from there, with no call.
        b.switch_to(inl);
        inline_view_guard(&mut b, s, w1, start, end, slow);
        let p = b
            .emit(Op::PtrAdd, &[s, start], Imm::None, Some(MTy::PTR))
            .expect("ptr.add");
        let n = b.binop(Op::ISub, end, start);
        b.br(short, &[p, n]);
        b.switch_to(flat_block);
        view_guard(&mut b, s, start, end, slow);
        let w0 = load(&mut b, s, 0, MTy::PTR);
        let p = b
            .emit(Op::PtrAdd, &[w0, start], Imm::None, Some(MTy::PTR))
            .expect("ptr.add");
        let n = b.binop(Op::ISub, end, start);
        let c15 = b.iconst(15);
        let fits = b.icmp(Cc::Le, n, c15);
        // A longer slice is copied by the runtime.
        b.br_if(fits, short, &[p, n], if slice { slow } else { long }, &[]);
        b.seal_block(short);
        b.seal_block(long);
        // Longer text: a view over the bytes.
        b.switch_to(long);
        if slice {
            b.unreachable();
        } else {
            let tagged = int(&mut b, Op::Or, n, 3 << 62);
            b.emit(Op::Store, &[out, p], Imm::None, None);
            let out8 = add(&mut b, out, 8);
            b.emit(Op::Store, &[out8, tagged], Imm::None, None);
            b.br(join, &[]);
        }
        // A piece of up to fifteen bytes is copied into the two words of an inline string.
        b.switch_to(short);
        let (lo, hi) = pack_short(&mut b, sp, sn);
        let len_bits = int(&mut b, Op::Shl, sn, 56);
        let tagged = int(&mut b, Op::Or, len_bits, 1 << 62);
        let tagged = b.binop(Op::Or, tagged, hi);
        b.emit(Op::Store, &[out, lo], Imm::None, None);
        let out8 = add(&mut b, out, 8);
        b.emit(Op::Store, &[out8, tagged], Imm::None, None);
        b.br(join, &[]);
        // The runtime handles the rest.
        b.seal_block(slow);
        b.switch_to(slow);
        b.call_rt(ext, &[text, start, end, out]);
        b.br(join, &[]);
        b.seal_block(join);
        b.switch_to(join);
        let unit = b.unit();
        b.ret(Some(unit));
        let func = b.into_func();
        self.fast_path_add(key, func)
    }
}

/// The bytes `p[..n]` (`n <= 15`) as the two words of an inline string: the first eight bytes, and
/// the rest, zero past the end. Overlapping loads cover every length without reading past `p + n`.
fn pack_short(b: &mut FuncBuilder<'_>, p: Value, n: Value) -> (Value, Value) {
    let loadu = |b: &mut FuncBuilder<'_>, at: Value, w: i64| {
        b.emit(Op::PtrLoadU, &[at], Imm::Int(w), Some(MTy::INT))
            .expect("ptr.loadu")
    };
    let past = |b: &mut FuncBuilder<'_>, p: Value, by: Value| {
        b.emit(Op::PtrAdd, &[p, by], Imm::None, Some(MTy::PTR))
            .expect("ptr.add")
    };
    let (big, rest, mid, tiny, small, join) = (
        b.new_block(),
        b.new_block(),
        b.new_block(),
        b.new_block(),
        b.new_block(),
        b.new_block(),
    );
    let lo_v = b.declare_var(MTy::INT, Mode::Borrow);
    let hi_v = b.declare_var(MTy::INT, Mode::Borrow);
    let zero = b.iconst(0);
    b.def_var(lo_v, zero);
    b.def_var(hi_v, zero);
    let c8 = b.iconst(8);
    let ge8 = b.icmp(Cc::Ge, n, c8);
    b.br_if(ge8, big, &[], rest, &[]);
    b.seal_block(big);
    b.seal_block(rest);
    // Eight to fifteen bytes: the first word, and the last eight shifted down to the tail.
    b.switch_to(big);
    let a = loadu(b, p, 8);
    let back = int(b, Op::ISub, n, 8);
    let at = past(b, p, back);
    let t = loadu(b, at, 8);
    let t = int(b, Op::Ushr, t, 8);
    let c15 = b.iconst(15);
    let sh = b.binop(Op::ISub, c15, n);
    let sh = int(b, Op::Shl, sh, 3);
    let hi = b.binop(Op::Ushr, t, sh);
    b.def_var(lo_v, a);
    b.def_var(hi_v, hi);
    b.br(join, &[]);
    b.switch_to(rest);
    let c4 = b.iconst(4);
    let ge4 = b.icmp(Cc::Ge, n, c4);
    b.br_if(ge4, mid, &[], tiny, &[]);
    b.seal_block(mid);
    b.seal_block(tiny);
    // Four to seven: the first four bytes and the last four.
    b.switch_to(mid);
    let a = loadu(b, p, 4);
    let back = int(b, Op::ISub, n, 4);
    let at = past(b, p, back);
    let t = loadu(b, at, 4);
    let sh = int(b, Op::Shl, back, 3);
    let t = b.binop(Op::Shl, t, sh);
    let lo = b.binop(Op::Or, a, t);
    b.def_var(lo_v, lo);
    b.br(join, &[]);
    b.switch_to(tiny);
    let some = b.icmp(Cc::Gt, n, zero);
    b.br_if(some, small, &[], join, &[]);
    b.seal_block(small);
    // One to three: the first, middle and last byte.
    b.switch_to(small);
    let first = loadu(b, p, 1);
    let half = int(b, Op::Ushr, n, 1);
    let at = past(b, p, half);
    let middle = loadu(b, at, 1);
    let last_at = int(b, Op::ISub, n, 1);
    let at = past(b, p, last_at);
    let last = loadu(b, at, 1);
    let sh = int(b, Op::Shl, half, 3);
    let middle = b.binop(Op::Shl, middle, sh);
    let sh = int(b, Op::Shl, last_at, 3);
    let last = b.binop(Op::Shl, last, sh);
    let lo = b.binop(Op::Or, first, middle);
    let lo = b.binop(Op::Or, lo, last);
    b.def_var(lo_v, lo);
    b.br(join, &[]);
    b.seal_block(join);
    b.switch_to(join);
    (b.use_var(lo_v), b.use_var(hi_v))
}

impl FnLower<'_> {
    /// The generated `Bytes` fixed-width read (`msrt_bytes_read_word`): with the offset in range
    /// and a little-endian read (or one byte), one unaligned load into `out` and a zero status;
    /// big-endian reads and a bad width call the runtime.
    fn read_word_fn(&mut self) -> FuncId {
        let key = HelperKey::BytesReadWord;
        if let Some(f) = self.fast_path_cached(&key) {
            return f;
        }
        let param = |ty| Param {
            ty,
            mode: Mode::Borrow,
        };
        let tys = [MTy::BYTES, MTy::INT, MTy::INT, MTy::BOOL, MTy::PTR];
        let ext = runtime_fn(self.b.m, "msrt_bytes_read_word", &tys, MTy::INT);
        let mut b = self.fast_path_builder(
            "bytes_read_word",
            tys.iter().map(|t| param(*t)).collect(),
            MTy::INT,
        );
        let ps = b.params();
        let (bytes, at, width, little, out) = (ps[0], ps[1], ps[2], ps[3], ps[4]);
        let (check, fast, slow, fail, store) = (
            b.new_block(),
            b.new_block(),
            b.new_block(),
            b.new_block(),
            b.new_block(),
        );
        let loaded = b.add_block_param(store, MTy::INT, Mode::Borrow);
        // The byte list through its memory form: data pointer, then length.
        let vec = b
            .emit(Op::Slot, &[], Imm::Ty(MTy::BYTES), Some(MTy::PTR))
            .expect("slot");
        b.emit(Op::Store, &[vec, bytes], Imm::None, None);
        let len = load(&mut b, vec, 8, MTy::INT);
        let zero = b.iconst(0);
        let rest = b.binop(Op::ISub, len, at);
        let (a, c, d) = (
            b.icmp(Cc::Ge, at, zero),
            b.icmp(Cc::Le, at, len),
            b.icmp(Cc::Ge, rest, width),
        );
        let ok = b.binop(Op::And, a, c);
        let ok = b.binop(Op::And, ok, d);
        b.br_if(ok, check, &[], fail, &[]);
        b.seal_block(check);
        b.switch_to(check);
        let one = b.iconst(1);
        let single = b.icmp(Cc::Eq, width, one);
        let direct = b.binop(Op::Or, little, single);
        b.br_if(direct, fast, &[], slow, &[]);
        b.seal_block(fast);
        b.seal_block(slow);
        b.switch_to(fast);
        let data = load(&mut b, vec, 0, MTy::PTR);
        let p = b
            .emit(Op::PtrAdd, &[data, at], Imm::None, Some(MTy::PTR))
            .expect("ptr.add");
        let blocks: Vec<(i64, Block)> = [1, 2, 4, 8].iter().map(|w| (*w, b.new_block())).collect();
        b.switch(width, &blocks, slow);
        for (w, blk) in blocks {
            b.seal_block(blk);
            b.switch_to(blk);
            let x = b
                .emit(Op::PtrLoadU, &[p], Imm::Int(w), Some(MTy::INT))
                .expect("ptr.loadu");
            b.br(store, &[x]);
        }
        b.seal_block(store);
        b.switch_to(store);
        b.emit(Op::Store, &[out, loaded], Imm::None, None);
        let ok = b.iconst(0);
        b.ret(Some(ok));
        b.seal_block(slow);
        b.switch_to(slow);
        let status = b.call_rt(ext, &[bytes, at, width, little, out]);
        b.ret(Some(status));
        b.seal_block(fail);
        b.switch_to(fail);
        let oor = b.iconst(2);
        b.ret(Some(oor));
        let func = b.into_func();
        self.fast_path_add(key, func)
    }

    /// The generated `Bytes.index_of_byte` (`msrt_bytes_index_of_byte`): the next sixteen bytes
    /// are searched two words at a time (the zero-byte trick on the XOR with the byte repeated),
    /// so a field or line end a few bytes away is found without a call. Less than sixteen bytes
    /// left, a byte outside 0..=255 and a miss in the window go to the runtime, which continues
    /// from where the window ended.
    fn index_of_byte_fn(&mut self) -> FuncId {
        let key = HelperKey::BytesIndexOfByte;
        if let Some(f) = self.fast_path_cached(&key) {
            return f;
        }
        let param = |ty| Param {
            ty,
            mode: Mode::Borrow,
        };
        let tys = [MTy::BYTES, MTy::INT, MTy::INT, MTy::PTR];
        let ext = runtime_fn(self.b.m, "msrt_bytes_index_of_byte", &tys, MTy::BOOL);
        let mut b = self.fast_path_builder(
            "bytes_index_of_byte",
            tys.iter().map(|t| param(*t)).collect(),
            MTy::BOOL,
        );
        let ps = b.params();
        let (bytes, value, start, out) = (ps[0], ps[1], ps[2], ps[3]);
        let (window, second, slow, found) =
            (b.new_block(), b.new_block(), b.new_block(), b.new_block());
        let at = b.add_block_param(found, MTy::INT, Mode::Borrow);
        let resume = b.add_block_param(slow, MTy::INT, Mode::Borrow);
        let vec = b
            .emit(Op::Slot, &[], Imm::Ty(MTy::BYTES), Some(MTy::PTR))
            .expect("slot");
        b.emit(Op::Store, &[vec, bytes], Imm::None, None);
        let len = load(&mut b, vec, 8, MTy::INT);
        let zero = b.iconst(0);
        let negative = b.icmp(Cc::Lt, start, zero);
        let from = b.select(negative, zero, start);
        let rest = b.binop(Op::ISub, len, from);
        let c16 = b.iconst(16);
        let room = b.icmp(Cc::Ge, rest, c16);
        let c255 = b.iconst(255);
        let low = b.icmp(Cc::Ge, value, zero);
        let high = b.icmp(Cc::Le, value, c255);
        let byte = b.binop(Op::And, low, high);
        let ok = b.binop(Op::And, room, byte);
        b.br_if(ok, window, &[], slow, &[start]);
        b.seal_block(window);
        b.switch_to(window);
        let data = load(&mut b, vec, 0, MTy::PTR);
        let p = b
            .emit(Op::PtrAdd, &[data, from], Imm::None, Some(MTy::PTR))
            .expect("ptr.add");
        let repeated = int(&mut b, Op::IMul, value, 0x0101_0101_0101_0101);
        // The offset of the first byte of the word at `p + off` equal to the value, or a miss.
        let probe =
            |b: &mut FuncBuilder<'_>, off: i64, hit: Block, miss: Block, miss_args: &[Value]| {
                let q = add(b, p, off);
                let w = b
                    .emit(Op::PtrLoadU, &[q], Imm::Int(8), Some(MTy::INT))
                    .expect("ptr.loadu");
                let x = b.binop(Op::Xor, w, repeated);
                // The high bit of each byte of `y` is set unless that byte of `x` is zero.
                let low7 = int(b, Op::And, x, 0x7f7f_7f7f_7f7f_7f7f);
                let y = int(b, Op::IAdd, low7, 0x7f7f_7f7f_7f7f_7f7f);
                let y = b.binop(Op::Or, y, x);
                let y = int(b, Op::And, y, 0x8080_8080_8080_8080_u64 as i64);
                let t = int(b, Op::Xor, y, 0x8080_8080_8080_8080_u64 as i64);
                let none = b.icmp(Cc::Eq, t, zero);
                let tz = b
                    .emit(Op::Ctz, &[t], Imm::None, Some(MTy::INT))
                    .expect("ctz");
                let idx = int(b, Op::Ushr, tz, 3);
                let idx = int(b, Op::IAdd, idx, off);
                let found_at = b.binop(Op::IAdd, from, idx);
                b.br_if(none, miss, miss_args, hit, &[found_at]);
            };
        let after = b.binop(Op::IAdd, from, c16);
        probe(&mut b, 0, found, second, &[]);
        b.seal_block(second);
        b.switch_to(second);
        probe(&mut b, 8, found, slow, &[after]);
        b.seal_block(found);
        b.switch_to(found);
        b.emit(Op::Store, &[out, at], Imm::None, None);
        let yes = b.bconst(true);
        b.ret(Some(yes));
        // The runtime takes over from the end of the window, or from `from` when there was none.
        b.seal_block(slow);
        b.switch_to(slow);
        let status = b.call_rt(ext, &[bytes, value, resume, out]);
        b.ret(Some(status));
        let func = b.into_func();
        self.fast_path_add(key, func)
    }
}
