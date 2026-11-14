//! String fast paths as inlinable MIR: `parse_int`, a one-byte `contains` and `scalar_at` of
//! ASCII text held inline.
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
    let long = int(b, Op::And, w1, (1 << 61) - 1);
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

/// `String.scalar_at(index, default)` of an ASCII inline string with the index inside it is one
/// byte; every other case calls the runtime.
fn scalar_at(b: &mut FuncBuilder<'_>) {
    let ps = b.params();
    let (text, index, has, default) = (ps[0], ps[1], ps[2], ps[3]);
    let ext = runtime_fn(
        b.m,
        "msrt_string_scalar_at",
        &[MTy::STR, MTy::INT, MTy::BOOL, MTy::INT],
        MTy::INT,
    );
    let (slow, check, read) = (b.new_block(), b.new_block(), b.new_block());
    let s = slot_of(b, text);
    let w1 = load(b, s, 8, MTy::INT);
    let tag = int(b, Op::Ushr, w1, 62);
    let one = b.iconst(1);
    let inline = b.icmp(Cc::Eq, tag, one);
    b.br_if(inline, check, &[], slow, &[]);
    b.seal_block(check);
    b.switch_to(check);
    let w0 = load(b, s, 0, MTy::INT);
    let low = int(b, Op::And, w1, (1 << 56) - 1);
    let hi0 = int(b, Op::And, w0, 0x8080_8080_8080_8080_u64 as i64);
    let hi1 = int(b, Op::And, low, 0x0080_8080_8080_8080);
    let bits = b.binop(Op::Or, hi0, hi1);
    let zero = b.iconst(0);
    let ascii = b.icmp(Cc::Eq, bits, zero);
    let n = int(b, Op::Ushr, w1, 56);
    let n = int(b, Op::And, n, 15);
    let ge0 = b.icmp(Cc::Ge, index, zero);
    let lt = b.icmp(Cc::Lt, index, n);
    let no = b.bconst(false);
    let inside = b.select(ge0, lt, no);
    let ok = b.select(ascii, inside, no);
    b.br_if(ok, read, &[], slow, &[]);
    b.seal_block(read);
    b.seal_block(slow);
    b.switch_to(read);
    let v = byte_at(b, s, index);
    b.ret(Some(v));
    b.switch_to(slow);
    let r = b.call_rt(ext, &[text, index, has, default]);
    b.ret(Some(r));
}
