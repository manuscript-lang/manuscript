//! String fast paths as inlinable MIR: `parse_int`, a one-byte `contains`, `scalar_at` and
//! the affix tests.
//!
//! The runtime functions of the same names stay as fallbacks. Each helper is an `inline(always)`
//! generated function, so both backends see the loop in the caller. A string is two words: an
//! inline string (tag `01`, up to 15 bytes) holds its bytes in the words themselves, any other
//! string holds a data pointer and a length (see `crates/ms-rt-abi`).

use crate::cx::HelperKey;
use crate::func::FnLower;
use crate::text::runtime_fn;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{Cc, FuncId, Imm, InlineHint, Linkage, Mode, Op, Param, Value};
use ms_mir::types::Ty as MTy;

/// The kinds of string helper.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub(crate) enum StrFn {
    ParseInt,
    ContainsByte,
    ScalarAt,
    ScalarStep,
    StartsWith,
    EndsWith,
    Compare,
}

fn int(b: &mut FuncBuilder<'_>, op: Op, x: Value, y: i64) -> Value {
    let y = b.iconst(y);
    b.binop(op, x, y)
}

fn load(b: &mut FuncBuilder<'_>, p: Value, at: i64, ty: MTy) -> Value {
    let p = if at == 0 {
        p
    } else {
        let off = b.iconst(at);
        b.emit(Op::PtrAdd, &[p, off], Imm::None, Some(MTy::PTR))
            .expect("ptr.add")
    };
    b.emit(Op::Load, &[p], Imm::Ty(ty), Some(ty)).expect("load")
}

/// The byte at `p + i`, zero-extended.
fn byte_at(b: &mut FuncBuilder<'_>, p: Value, i: Value) -> Value {
    let at = b
        .emit(Op::PtrAdd, &[p, i], Imm::None, Some(MTy::PTR))
        .expect("ptr.add");
    b.emit(Op::PtrLoadU, &[at], Imm::Int(1), Some(MTy::INT))
        .expect("ptr.loadu")
}

/// The data pointer and byte length of the string held in slot `s`.
fn bytes_of(b: &mut FuncBuilder<'_>, s: Value) -> (Value, Value) {
    let w0 = load(b, s, 0, MTy::PTR);
    let w1 = load(b, s, 8, MTy::INT);
    let tag = int(b, Op::Ushr, w1, 62);
    let one = b.iconst(1);
    let inline = b.icmp(Cc::Eq, tag, one);
    let short = int(b, Op::Ushr, w1, 56);
    let short = int(b, Op::And, short, 15);
    let long = int(b, Op::And, w1, ms_rt_abi::STR_LEN_MASK as i64);
    let len = b.select(inline, short, long);
    let data = b.select(inline, s, w0);
    (data, len)
}

fn param(ty: MTy) -> Param {
    Param {
        ty,
        mode: Mode::Borrow,
    }
}

fn slot_of(b: &mut FuncBuilder<'_>, text: Value) -> Value {
    let s = b
        .emit(Op::Slot, &[], Imm::Ty(MTy::STR), Some(MTy::PTR))
        .expect("slot");
    b.emit(Op::Store, &[s, text], Imm::None, None);
    s
}

impl FnLower<'_> {
    /// The generated helper for `which`, built on first use.
    pub(crate) fn str_fn(&mut self, which: StrFn) -> FuncId {
        let key = HelperKey::StrFast(which);
        if let Some(f) = self.cx.helpers.get(&key) {
            return *f;
        }
        let (name, params, ret) = match which {
            StrFn::ParseInt => (
                "parse_int",
                vec![param(MTy::STR), param(MTy::PTR)],
                MTy::BOOL,
            ),
            StrFn::ContainsByte => (
                "contains_byte",
                vec![param(MTy::STR), param(MTy::STR)],
                MTy::BOOL,
            ),
            StrFn::StartsWith => (
                "starts_with",
                vec![param(MTy::STR), param(MTy::STR)],
                MTy::BOOL,
            ),
            StrFn::EndsWith => (
                "ends_with",
                vec![param(MTy::STR), param(MTy::STR)],
                MTy::BOOL,
            ),
            StrFn::Compare => (
                "string_compare",
                vec![param(MTy::STR), param(MTy::STR)],
                MTy::INT,
            ),
            StrFn::ScalarStep => (
                "scalar_step",
                vec![param(MTy::STR), param(MTy::INT)],
                MTy::INT,
            ),
            StrFn::ScalarAt => (
                "scalar_at",
                vec![
                    param(MTy::STR),
                    param(MTy::INT),
                    param(MTy::BOOL),
                    param(MTy::INT),
                ],
                MTy::INT,
            ),
        };
        let mut b = FuncBuilder::new(self.b.m, name, params, ret);
        b.func_mut().linkage = Linkage::Internal;
        b.func_mut().inline = InlineHint::Always;
        match which {
            StrFn::ParseInt => parse_int(&mut b),
            StrFn::ContainsByte => contains_byte(&mut b),
            StrFn::ScalarAt => scalar_at(&mut b),
            StrFn::ScalarStep => scalar_step(&mut b),
            StrFn::StartsWith => affix(&mut b, false),
            StrFn::EndsWith => affix(&mut b, true),
            StrFn::Compare => compare(&mut b),
        }
        let func = b.into_func();
        let fid = self.b.m.add_func(func);
        self.cx.helpers.insert(key, fid);
        fid
    }

    /// The inline form of a runtime string call, when one applies.
    pub(crate) fn inline_str(&mut self, sym: &str, args: &[Value]) -> Option<Value> {
        match sym {
            "msrt_string_parse_int" => {
                let f = self.str_fn(StrFn::ParseInt);
                Some(self.b.call(f, args))
            }
            "msrt_string_contains" => {
                // A literal needle of two or more bytes skips the one-byte dispatch.
                if let Some(id) = self.b.str_lit_of(args[1])
                    && self.b.m.strings[id.0 as usize].len() >= 2
                {
                    return None;
                }
                let f = self.str_fn(StrFn::ContainsByte);
                Some(self.b.call(f, args))
            }
            "msrt_string_compare" => {
                let f = self.str_fn(StrFn::Compare);
                Some(self.b.call(f, args))
            }
            "msrt_string_starts_with" => {
                let f = self.str_fn(StrFn::StartsWith);
                Some(self.b.call(f, args))
            }
            "msrt_string_ends_with" => {
                let f = self.str_fn(StrFn::EndsWith);
                Some(self.b.call(f, args))
            }
            "msrt_string_scalar_step" => {
                let f = self.str_fn(StrFn::ScalarStep);
                Some(self.b.call(f, args))
            }
            "msrt_string_scalar_at" => {
                let f = self.str_fn(StrFn::ScalarAt);
                Some(self.b.call(f, args))
            }
            _ => None,
        }
    }
}

/// `String.parse_int`: an optional sign and up to eighteen ASCII digits, which cannot overflow;
/// anything longer calls the runtime.
fn parse_int(b: &mut FuncBuilder<'_>) {
    let ps = b.params();
    let (text, out) = (ps[0], ps[1]);
    let ext = runtime_fn(
        b.m,
        "msrt_string_parse_int",
        &[MTy::STR, MTy::PTR],
        MTy::BOOL,
    );
    let (fail, slow, scan, header, body, step, done) = (
        b.new_block(),
        b.new_block(),
        b.new_block(),
        b.new_block(),
        b.new_block(),
        b.new_block(),
        b.new_block(),
    );
    let s = slot_of(b, text);
    let (data, len) = bytes_of(b, s);
    let zero = b.iconst(0);
    let one = b.iconst(1);
    let empty = b.icmp(Cc::Eq, len, zero);
    let first = b.new_block();
    b.br_if(empty, fail, &[], first, &[]);
    b.seal_block(first);
    b.switch_to(first);
    let c0 = byte_at(b, data, zero);
    let minus_c = b.iconst(45);
    let plus_c = b.iconst(43);
    let minus = b.icmp(Cc::Eq, c0, minus_c);
    let plus = b.icmp(Cc::Eq, c0, plus_c);
    let yes = b.bconst(true);
    let signed = b.select(minus, yes, plus);
    let start = b.select(signed, one, zero);
    let n = b.binop(Op::ISub, len, start);
    let no_digits = b.icmp(Cc::Le, n, zero);
    let (long_check, _) = (b.new_block(), ());
    b.br_if(no_digits, fail, &[], long_check, &[]);
    b.seal_block(long_check);
    b.switch_to(long_check);
    let c18 = b.iconst(18);
    let many = b.icmp(Cc::Gt, n, c18);
    b.br_if(many, slow, &[], scan, &[]);
    b.seal_block(slow);
    b.seal_block(scan);
    b.switch_to(scan);
    let acc = b.declare_var(MTy::INT, Mode::Borrow);
    let at = b.declare_var(MTy::INT, Mode::Borrow);
    b.def_var(acc, zero);
    b.def_var(at, start);
    b.br(header, &[]);
    b.switch_to(header);
    let i = b.use_var(at);
    let more = b.icmp(Cc::Lt, i, len);
    b.br_if(more, body, &[], done, &[]);
    b.seal_block(body);
    b.seal_block(done);
    b.switch_to(body);
    let c = byte_at(b, data, i);
    let d = int(b, Op::ISub, c, 48);
    let below = b.icmp(Cc::Lt, d, zero);
    let c9 = b.iconst(9);
    let above = b.icmp(Cc::Gt, d, c9);
    let bad = b.select(below, yes, above);
    b.br_if(bad, fail, &[], step, &[]);
    b.seal_block(step);
    b.switch_to(step);
    let a = b.use_var(acc);
    let a = int(b, Op::IMul, a, 10);
    let a = b.binop(Op::IAdd, a, d);
    b.def_var(acc, a);
    let next = int(b, Op::IAdd, i, 1);
    b.def_var(at, next);
    b.br(header, &[]);
    b.seal_block(header);
    b.seal_block(fail);
    b.switch_to(fail);
    let no = b.bconst(false);
    b.ret(Some(no));
    b.switch_to(slow);
    let r = b.call_rt(ext, &[text, out]);
    b.ret(Some(r));
    b.switch_to(done);
    let a = b.use_var(acc);
    let neg = b.unop(Op::INeg, a);
    let v = b.select(minus, neg, a);
    b.emit(Op::Store, &[out, v], Imm::None, None);
    let ok = b.bconst(true);
    b.ret(Some(ok));
}

/// `hay.contains(needle)` for a needle of one byte and a text of under 32 bytes: a scan (the
/// character-class test `"#.SE".contains(c)`); every other case calls the runtime.
fn contains_byte(b: &mut FuncBuilder<'_>) {
    let ps = b.params();
    let (hay, needle) = (ps[0], ps[1]);
    let ext = runtime_fn(
        b.m,
        "msrt_string_contains",
        &[MTy::STR, MTy::STR],
        MTy::BOOL,
    );
    let (slow, header, body, step, hit, miss, one_byte) = (
        b.new_block(),
        b.new_block(),
        b.new_block(),
        b.new_block(),
        b.new_block(),
        b.new_block(),
        b.new_block(),
    );
    let s = slot_of(b, hay);
    let n = slot_of(b, needle);
    let (data, len) = bytes_of(b, s);
    let (ndata, nlen) = bytes_of(b, n);
    let c32 = b.iconst(32);
    let one = b.iconst(1);
    let short = b.icmp(Cc::Lt, len, c32);
    let single = b.icmp(Cc::Eq, nlen, one);
    let no = b.bconst(false);
    let both = b.select(short, single, no);
    b.br_if(both, one_byte, &[], slow, &[]);
    b.seal_block(one_byte);
    b.seal_block(slow);
    b.switch_to(one_byte);
    let zero = b.iconst(0);
    let c = byte_at(b, ndata, zero);
    let at = b.declare_var(MTy::INT, Mode::Borrow);
    b.def_var(at, zero);
    b.br(header, &[]);
    b.switch_to(header);
    let i = b.use_var(at);
    let more = b.icmp(Cc::Lt, i, len);
    b.br_if(more, body, &[], miss, &[]);
    b.seal_block(body);
    b.seal_block(miss);
    b.switch_to(body);
    let x = byte_at(b, data, i);
    let found = b.icmp(Cc::Eq, x, c);
    b.br_if(found, hit, &[], step, &[]);
    b.seal_block(hit);
    b.seal_block(step);
    b.switch_to(step);
    let next = int(b, Op::IAdd, i, 1);
    b.def_var(at, next);
    b.br(header, &[]);
    b.seal_block(header);
    b.switch_to(hit);
    let yes = b.bconst(true);
    b.ret(Some(yes));
    b.switch_to(miss);
    let f = b.bconst(false);
    b.ret(Some(f));
    b.switch_to(slow);
    let r = b.call_rt(ext, &[hay, needle]);
    b.ret(Some(r));
}

/// Emits the decode of the multi-byte scalar whose lead byte `b0` (at least 0x80) is at `offset`
/// of `text`, and ends each path with `finish(scalar, width)`. A string is valid UTF-8, so the
/// lead byte fixes the width and every continuation byte is in bounds; a continuation byte in
/// the lead position goes to `slow`.
fn decode_multibyte(
    b: &mut FuncBuilder<'_>,
    text: Value,
    offset: Value,
    b0: Value,
    slow: ms_mir::ir::Block,
    finish: &dyn Fn(&mut FuncBuilder<'_>, Value, i64),
) {
    let (lead_ok, two, wide, three, four) = (
        b.new_block(),
        b.new_block(),
        b.new_block(),
        b.new_block(),
        b.new_block(),
    );
    let byte_at = |b: &mut FuncBuilder<'_>, k: i64| {
        let at = int(b, Op::IAdd, offset, k);
        b.emit(Op::StrByte, &[text, at], Imm::None, Some(MTy::INT))
            .expect("byte")
    };
    // 0x80..0xBF is a continuation byte: the offset is inside a scalar.
    let c0 = b.iconst(0xC0);
    let lead = b.icmp(Cc::Ge, b0, c0);
    b.br_if(lead, lead_ok, &[], slow, &[]);
    b.seal_block(lead_ok);
    b.switch_to(lead_ok);
    let e0 = b.iconst(0xE0);
    let is_two = b.icmp(Cc::Lt, b0, e0);
    b.br_if(is_two, two, &[], wide, &[]);
    b.seal_block(two);
    b.seal_block(wide);
    b.switch_to(two);
    let b1 = byte_at(b, 1);
    let hi = int(b, Op::And, b0, 0x1F);
    let hi = int(b, Op::Shl, hi, 6);
    let lo = int(b, Op::And, b1, 0x3F);
    let r = b.binop(Op::Or, hi, lo);
    finish(b, r, 2);
    b.switch_to(wide);
    let f0 = b.iconst(0xF0);
    let is_three = b.icmp(Cc::Lt, b0, f0);
    b.br_if(is_three, three, &[], four, &[]);
    b.seal_block(three);
    b.seal_block(four);
    b.switch_to(three);
    let b1 = byte_at(b, 1);
    let b2 = byte_at(b, 2);
    let x = int(b, Op::And, b0, 0x0F);
    let x = int(b, Op::Shl, x, 12);
    let y = int(b, Op::And, b1, 0x3F);
    let y = int(b, Op::Shl, y, 6);
    let z = int(b, Op::And, b2, 0x3F);
    let r = b.binop(Op::Or, x, y);
    let r = b.binop(Op::Or, r, z);
    finish(b, r, 3);
    b.switch_to(four);
    let b1 = byte_at(b, 1);
    let b2 = byte_at(b, 2);
    let b3 = byte_at(b, 3);
    let w = int(b, Op::And, b0, 0x07);
    let w = int(b, Op::Shl, w, 18);
    let x = int(b, Op::And, b1, 0x3F);
    let x = int(b, Op::Shl, x, 12);
    let y = int(b, Op::And, b2, 0x3F);
    let y = int(b, Op::Shl, y, 6);
    let z = int(b, Op::And, b3, 0x3F);
    let r = b.binop(Op::Or, w, x);
    let r = b.binop(Op::Or, r, y);
    let r = b.binop(Op::Or, r, z);
    finish(b, r, 4);
}

/// `String.scalar_at(offset, default)`: an offset inside the text decodes in place (see
/// [`decode_multibyte`]); an offset outside the text, or a continuation byte, calls the runtime
/// for the default or the fault.
fn scalar_at(b: &mut FuncBuilder<'_>) {
    let ps = b.params();
    let (text, offset, has, default) = (ps[0], ps[1], ps[2], ps[3]);
    let ext = runtime_fn(
        b.m,
        "msrt_string_scalar_at",
        &[MTy::STR, MTy::INT, MTy::BOOL, MTy::INT],
        MTy::INT,
    );
    let (slow, read, ascii, multi) = (b.new_block(), b.new_block(), b.new_block(), b.new_block());
    let n = b.str_bytes(text);
    let zero = b.iconst(0);
    let ge0 = b.icmp(Cc::Ge, offset, zero);
    let lt = b.icmp(Cc::Lt, offset, n);
    let no = b.bconst(false);
    let inside = b.select(ge0, lt, no);
    b.br_if(inside, read, &[], slow, &[]);
    b.seal_block(read);
    b.switch_to(read);
    let b0 = b
        .emit(Op::StrByte, &[text, offset], Imm::None, Some(MTy::INT))
        .expect("byte");
    let limit = b.iconst(128);
    let is_ascii = b.icmp(Cc::Lt, b0, limit);
    b.br_if(is_ascii, ascii, &[], multi, &[]);
    b.seal_block(ascii);
    b.seal_block(multi);
    b.switch_to(ascii);
    b.ret(Some(b0));
    b.switch_to(multi);
    decode_multibyte(b, text, offset, b0, slow, &|b, scalar, _| {
        b.ret(Some(scalar))
    });
    b.seal_block(slow);
    b.switch_to(slow);
    let r = b.call_rt(ext, &[text, offset, has, default]);
    b.ret(Some(r));
}

/// The scalar at byte `offset` (inside the text, on a scalar boundary) and its width as
/// `scalar << 3 | width`: one step of a scalar walk, with no runtime call.
fn scalar_step(b: &mut FuncBuilder<'_>) {
    let ps = b.params();
    let (text, offset) = (ps[0], ps[1]);
    let ext = runtime_fn(
        b.m,
        "msrt_string_scalar_step",
        &[MTy::STR, MTy::INT],
        MTy::INT,
    );
    let (slow, ascii, multi) = (b.new_block(), b.new_block(), b.new_block());
    let b0 = b
        .emit(Op::StrByte, &[text, offset], Imm::None, Some(MTy::INT))
        .expect("byte");
    let limit = b.iconst(128);
    let is_ascii = b.icmp(Cc::Lt, b0, limit);
    b.br_if(is_ascii, ascii, &[], multi, &[]);
    b.seal_block(ascii);
    b.seal_block(multi);
    b.switch_to(ascii);
    let r = int(b, Op::Shl, b0, 3);
    let r = int(b, Op::Or, r, 1);
    b.ret(Some(r));
    b.switch_to(multi);
    decode_multibyte(b, text, offset, b0, slow, &|b, scalar, width| {
        let r = int(b, Op::Shl, scalar, 3);
        let r = int(b, Op::Or, r, width);
        b.ret(Some(r));
    });
    b.seal_block(slow);
    b.switch_to(slow);
    let r = b.call_rt(ext, &[text, offset]);
    b.ret(Some(r));
}

/// The bytes at `x` and `y` for `n` in `lo..=2 * lo` (`lo` of 1, 4 or 8 after the caller's
/// dispatch): two overlapping reads of `w` bytes, the first at 0 and the last ending at `n`.
/// Zero when every byte is equal.
fn diff_overlapping(b: &mut FuncBuilder<'_>, x: Value, y: Value, n: Value, w: i64) -> Value {
    let read = |b: &mut FuncBuilder<'_>, p: Value, at: Value| {
        let q = b
            .emit(Op::PtrAdd, &[p, at], Imm::None, Some(MTy::PTR))
            .expect("ptr.add");
        b.emit(Op::PtrLoadU, &[q], Imm::Int(w), Some(MTy::INT))
            .expect("ptr.loadu")
    };
    let zero = b.iconst(0);
    let back = int(b, Op::ISub, n, w);
    let (a0, v0) = (read(b, x, zero), read(b, y, zero));
    let (a1, v1) = (read(b, x, back), read(b, y, back));
    let d0 = b.binop(Op::Xor, a0, v0);
    let d1 = b.binop(Op::Xor, a1, v1);
    b.binop(Op::Or, d0, d1)
}

/// `text.starts_with(affix)` and `text.ends_with(affix)`: an affix of up to sixteen bytes is
/// compared with two overlapping reads (one to three bytes: three byte reads), so a short test
/// needs no call and no `memcmp`; a longer affix calls the runtime.
fn affix(b: &mut FuncBuilder<'_>, end: bool) {
    let ps = b.params();
    let (text, part) = (ps[0], ps[1]);
    let sym = if end {
        "msrt_string_ends_with"
    } else {
        "msrt_string_starts_with"
    };
    let ext = runtime_fn(b.m, sym, &[MTy::STR, MTy::STR], MTy::BOOL);
    let (slow, fits, empty, wide, mid, tiny, no) = (
        b.new_block(),
        b.new_block(),
        b.new_block(),
        b.new_block(),
        b.new_block(),
        b.new_block(),
        b.new_block(),
    );
    let s = slot_of(b, text);
    let p = slot_of(b, part);
    let (data, len) = bytes_of(b, s);
    let (pdata, plen) = bytes_of(b, p);
    let c16 = b.iconst(16);
    let longer = b.icmp(Cc::Gt, plen, len);
    let check = b.new_block();
    b.br_if(longer, no, &[], check, &[]);
    b.seal_block(no);
    b.seal_block(check);
    b.switch_to(check);
    let big = b.icmp(Cc::Gt, plen, c16);
    b.br_if(big, slow, &[], fits, &[]);
    b.seal_block(slow);
    b.seal_block(fits);
    b.switch_to(fits);
    // The window of the text to compare: its first or last `plen` bytes.
    let at = if end {
        b.binop(Op::ISub, len, plen)
    } else {
        b.iconst(0)
    };
    let window = b
        .emit(Op::PtrAdd, &[data, at], Imm::None, Some(MTy::PTR))
        .expect("ptr.add");
    let zero = b.iconst(0);
    let none = b.icmp(Cc::Eq, plen, zero);
    b.br_if(none, empty, &[], mid, &[]);
    b.seal_block(empty);
    b.seal_block(mid);
    b.switch_to(mid);
    let c8 = b.iconst(8);
    let c4 = b.iconst(4);
    let eight = b.icmp(Cc::Ge, plen, c8);
    let (four_check, four) = (b.new_block(), b.new_block());
    b.br_if(eight, wide, &[], four_check, &[]);
    b.seal_block(wide);
    b.seal_block(four_check);
    b.switch_to(four_check);
    let is_four = b.icmp(Cc::Ge, plen, c4);
    b.br_if(is_four, four, &[], tiny, &[]);
    b.seal_block(four);
    b.seal_block(tiny);
    let verdict = |b: &mut FuncBuilder<'_>, diff: Value| {
        let z = b.iconst(0);
        let same = b.icmp(Cc::Eq, diff, z);
        b.ret(Some(same));
    };
    b.switch_to(wide);
    let d = diff_overlapping(b, window, pdata, plen, 8);
    verdict(b, d);
    b.switch_to(four);
    let d = diff_overlapping(b, window, pdata, plen, 4);
    verdict(b, d);
    b.switch_to(tiny);
    // One to three bytes: the first, the middle and the last.
    let half = int(b, Op::Ushr, plen, 1);
    let last = int(b, Op::ISub, plen, 1);
    let mut diff = b.iconst(0);
    for k in [zero, half, last] {
        let (wb, pb) = (byte_at(b, window, k), byte_at(b, pdata, k));
        let x = b.binop(Op::Xor, wb, pb);
        diff = b.binop(Op::Or, diff, x);
    }
    verdict(b, diff);
    b.switch_to(empty);
    let yes = b.bconst(true);
    b.ret(Some(yes));
    b.switch_to(no);
    let f = b.bconst(false);
    b.ret(Some(f));
    b.switch_to(slow);
    let r = b.call_rt(ext, &[text, part]);
    b.ret(Some(r));
}

/// `String` order as -1, 0 or 1: the first differing byte of the common prefix decides, then the
/// lengths. A prefix of up to sixteen bytes is compared byte by byte from either string form
/// (inline, static or heap); a longer one calls the runtime's `memcmp`.
fn compare(b: &mut FuncBuilder<'_>) {
    let ps = b.params();
    let (x, y) = (ps[0], ps[1]);
    let ext = runtime_fn(b.m, "msrt_string_compare", &[MTy::STR, MTy::STR], MTy::INT);
    let (scan, slow, head, body, step, tail) = (
        b.new_block(),
        b.new_block(),
        b.new_block(),
        b.new_block(),
        b.new_block(),
        b.new_block(),
    );
    let (minus, plus) = (b.iconst(-1), b.iconst(1));
    let (sx, sy) = (slot_of(b, x), slot_of(b, y));
    // Both inline (up to 15 bytes, zero past the length): the bytes are the words themselves, so
    // the first differing byte comes from at most two word compares with no length decode.
    let (inl, inl2, general, wdiff) = (b.new_block(), b.new_block(), b.new_block(), b.new_block());
    let (dx, dy, dd) = (
        b.add_block_param(wdiff, MTy::INT, Mode::Borrow),
        b.add_block_param(wdiff, MTy::INT, Mode::Borrow),
        b.add_block_param(wdiff, MTy::INT, Mode::Borrow),
    );
    let (x0, x1) = (load(b, sx, 0, MTy::INT), load(b, sx, 8, MTy::INT));
    let (y0, y1) = (load(b, sy, 0, MTy::INT), load(b, sy, 8, MTy::INT));
    let (tx, ty) = (int(b, Op::Ushr, x1, 62), int(b, Op::Ushr, y1, 62));
    let (nx, ny) = (int(b, Op::Xor, tx, 1), int(b, Op::Xor, ty, 1));
    let not_inline = b.binop(Op::Or, nx, ny);
    let zero_t = b.iconst(0);
    let both = b.icmp(Cc::Eq, not_inline, zero_t);
    b.br_if(both, inl, &[], general, &[]);
    b.seal_block(inl);
    b.seal_block(general);
    b.switch_to(inl);
    let first = b.binop(Op::Xor, x0, y0);
    let zero_f = b.iconst(0);
    let first_same = b.icmp(Cc::Eq, first, zero_f);
    b.br_if(first_same, inl2, &[], wdiff, &[x0, y0, first]);
    b.seal_block(inl2);
    b.switch_to(inl2);
    // The second word holds seven bytes (bits 0 to 55), then the length and the tag.
    let (m1, m2) = (
        int(b, Op::And, x1, (1 << 56) - 1),
        int(b, Op::And, y1, (1 << 56) - 1),
    );
    let second = b.binop(Op::Xor, m1, m2);
    let zero_s = b.iconst(0);
    let second_same = b.icmp(Cc::Eq, second, zero_s);
    let lens = b.new_block();
    b.br_if(second_same, lens, &[], wdiff, &[m1, m2, second]);
    b.seal_block(lens);
    b.switch_to(lens);
    let (lx, ly) = (int(b, Op::Ushr, x1, 56), int(b, Op::Ushr, y1, 56));
    let (lx, ly) = (int(b, Op::And, lx, 15), int(b, Op::And, ly, 15));
    let lx_less = b.icmp(Cc::Lt, lx, ly);
    let lx_more = b.icmp(Cc::Gt, lx, ly);
    let zero_l = b.iconst(0);
    let more_or_same = b.select(lx_more, plus, zero_l);
    let r = b.select(lx_less, minus, more_or_same);
    b.ret(Some(r));
    b.switch_to(wdiff);
    let low = b.unop(Op::Ctz, dd);
    let shift = int(b, Op::And, low, -8);
    let (xs, ys) = (b.binop(Op::Ushr, dx, shift), b.binop(Op::Ushr, dy, shift));
    let (xb, yb) = (int(b, Op::And, xs, 255), int(b, Op::And, ys, 255));
    let less = b.icmp(Cc::Lt, xb, yb);
    let r = b.select(less, minus, plus);
    b.ret(Some(r));
    b.switch_to(general);
    let (xd, xn) = bytes_of(b, sx);
    let (yd, yn) = bytes_of(b, sy);
    let shorter = b.icmp(Cc::Lt, xn, yn);
    let n = b.select(shorter, xn, yn);
    let c16 = b.iconst(16);
    let big = b.icmp(Cc::Gt, n, c16);
    b.br_if(big, slow, &[], scan, &[]);
    b.seal_block(slow);
    b.seal_block(scan);
    b.switch_to(slow);
    let r = b.call_rt(ext, &[x, y]);
    b.ret(Some(r));
    b.switch_to(scan);
    // Eight bytes at a time while a whole word remains in both strings; the first differing word
    // is decided by its lowest differing byte (little endian). The rest goes byte by byte.
    let (whead, wbody, wstep) = (b.new_block(), b.new_block(), b.new_block());
    let w = b.add_block_param(whead, MTy::INT, Mode::Borrow);
    let i = b.add_block_param(head, MTy::INT, Mode::Borrow);
    let zero = b.iconst(0);
    b.br(whead, &[zero]);
    b.switch_to(whead);
    let end = int(b, Op::IAdd, w, 8);
    let room = b.icmp(Cc::Le, end, n);
    b.br_if(room, wbody, &[], head, &[w]);
    b.seal_block(wbody);
    b.switch_to(wbody);
    let word = |b: &mut FuncBuilder<'_>, p: Value| {
        let at = b
            .emit(Op::PtrAdd, &[p, w], Imm::None, Some(MTy::PTR))
            .expect("ptr.add");
        b.emit(Op::PtrLoadU, &[at], Imm::Int(8), Some(MTy::INT))
            .expect("ptr.loadu")
    };
    let (xw, yw) = (word(b, xd), word(b, yd));
    let diff = b.binop(Op::Xor, xw, yw);
    let zero_w = b.iconst(0);
    let alike = b.icmp(Cc::Eq, diff, zero_w);
    b.br_if(alike, wstep, &[], wdiff, &[xw, yw, diff]);
    b.seal_block(wstep);
    b.seal_block(wdiff);
    b.switch_to(wstep);
    b.br(whead, &[end]);
    b.seal_block(whead);
    b.switch_to(head);
    let more = b.icmp(Cc::Lt, i, n);
    b.br_if(more, body, &[], tail, &[]);
    b.seal_block(body);
    b.seal_block(tail);
    b.switch_to(body);
    let (xb, yb) = (byte_at(b, xd, i), byte_at(b, yd, i));
    let same = b.icmp(Cc::Eq, xb, yb);
    let differ = b.new_block();
    b.br_if(same, step, &[], differ, &[]);
    b.seal_block(step);
    b.seal_block(differ);
    b.switch_to(differ);
    let less = b.icmp(Cc::Lt, xb, yb);
    let r = b.select(less, minus, plus);
    b.ret(Some(r));
    b.switch_to(step);
    let one = b.iconst(1);
    let next = b.binop(Op::IAdd, i, one);
    b.br(head, &[next]);
    b.seal_block(head);
    // Equal prefixes: the shorter string is smaller.
    b.switch_to(tail);
    let longer = b.icmp(Cc::Gt, xn, yn);
    let zero = b.iconst(0);
    let tail_cmp = b.select(longer, plus, zero);
    let r = b.select(shorter, minus, tail_cmp);
    b.ret(Some(r));
}
