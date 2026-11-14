//! Runtime fast paths as inlinable MIR: map and set lookups for the common key and value shapes,
//! and `String.view`.
//!
//! `Map[Int, V]`, `Map[String, V]` and `Set[Int]` with single-word values have a fixed slot layout
//! (see `crates/ms-rt/src/map.rs`), so a lookup is a short probe loop over the index. Each probe
//! is a generated function marked `inline(always)`: the MIR inliner places it in the caller, where
//! both backends optimize the loop together with the key computation and the use of the value.
//! Anything that is not one of these shapes calls the runtime.
//!
//! `String.view` of ASCII text with bounds inside it is two words computed in the caller; the
//! rest (inline or non-ASCII text, negative bounds, a fault) calls the runtime.
//!
//! The map is read through its memory form, seven words: slots pointer, index pointer, length,
//! used, capacity, mask, descriptor. An index entry holds the hash tag in its high 32 bits and the
//! slot number plus one in its low 32 bits; zero is an empty entry.

use crate::cx::HelperKey;
use crate::eq::string_eq;
use crate::func::FnLower;
use crate::text::runtime_fn;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{Block, Cc, FuncId, Imm, InlineHint, Linkage, Mode, Op, Param, Value};
use ms_mir::types::Ty as MTy;

const SLOTS: i64 = 0;
const INDEX: i64 = 8;
const LEN: i64 = 16;
const MASK: i64 = 40;
/// Top bit of a slot's hash word: set for a live entry.
const LIVE: i64 = i64::MIN;
const K0: i64 = 0x9e37_79b9_7f4a_7c15_u64 as i64;
const K1: i64 = 0xff51_afd7_ed55_8ccd_u64 as i64;

/// The slot shape a probe walks.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub(crate) enum Shape {
    /// `Map[Int, word]`: hash, key, value (24 bytes).
    IntMap,
    /// `Map[String, word]`: hash, key (two words), value (32 bytes).
    StrMap,
    /// `Set[Int]`: hash, key (16 bytes).
    IntSet,
}

/// What a probe returns.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub(crate) enum Answer {
    /// The address of the value (of the key for a set), or null.
    Address,
    /// Whether the key is present.
    Contains,
    /// Whether the key is present, and the value copied to the `out` address when it is.
    Get,
}

/// The probe a runtime symbol stands for.
pub(crate) fn probe_of(sym: &str) -> Option<(Shape, Answer)> {
    Some(match sym {
        "msrt_map_get_ptr_w8" => (Shape::IntMap, Answer::Address),
        "msrt_map_contains_w8" => (Shape::IntMap, Answer::Contains),
        "msrt_map_get_w8" => (Shape::IntMap, Answer::Get),
        "msrt_map_get_ptr_sw8" => (Shape::StrMap, Answer::Address),
        "msrt_map_contains_sw8" => (Shape::StrMap, Answer::Contains),
        "msrt_map_get_sw8" => (Shape::StrMap, Answer::Get),
        "msrt_set_contains_w" => (Shape::IntSet, Answer::Contains),
        _ => return None,
    })
}

impl Shape {
    fn stride(self) -> i64 {
        match self {
            Shape::IntMap => 24,
            Shape::StrMap => 32,
            Shape::IntSet => 16,
        }
    }

    /// Where the result points inside a slot.
    fn value_at(self) -> i64 {
        match self {
            Shape::IntMap => 16,
            Shape::StrMap => 24,
            Shape::IntSet => 8,
        }
    }
}

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

/// `hash_bytes` of the key string at `key` (`k` is the same string as a value): short inline
/// strings are hashed from their two words, which is what lets a lookup run without a call;
/// anything else calls the runtime, which computes the same hash.
fn string_hash(b: &mut FuncBuilder<'_>, key: Value, k: Value) -> Value {
    let w0 = load(b, key, 0, MTy::INT);
    let w1 = load(b, key, 8, MTy::INT);
    let tag = int(b, Op::Ushr, w1, 62);
    let one = b.iconst(1);
    let inline = b.icmp(Cc::Eq, tag, one);
    let (short, long, done) = (b.new_block(), b.new_block(), b.new_block());
    let hash = b.declare_var(MTy::INT, Mode::Borrow);
    b.br_if(inline, short, &[], long, &[]);
    b.seal_block(short);
    b.seal_block(long);
    b.switch_to(long);
    // A text of sixteen bytes or more is folded here, eight bytes at a time; the rare short text
    // that is not inline calls the runtime, which hashes it the same way.
    let fold = |b: &mut FuncBuilder<'_>, x: Value, m: i64| {
        let m = b.iconst(m);
        let lo = b.binop(Op::IMul, x, m);
        let hi = b.binop(Op::UMulHi, x, m);
        b.binop(Op::Xor, lo, hi)
    };
    let size = int(b, Op::And, w1, (1 << 61) - 1);
    let c16 = b.iconst(16);
    let wide = b.icmp(Cc::Ge, size, c16);
    let (fold_in, call, header, body, tail) = (
        b.new_block(),
        b.new_block(),
        b.new_block(),
        b.new_block(),
        b.new_block(),
    );
    b.br_if(wide, fold_in, &[], call, &[]);
    b.seal_block(fold_in);
    b.seal_block(call);
    b.switch_to(call);
    let ext = runtime_fn(b.m, "msrt_string_hash", &[MTy::STR], MTy::INT);
    let called = b.call_rt(ext, &[k]);
    b.def_var(hash, called);
    b.br(done, &[]);
    b.switch_to(fold_in);
    let data = load(b, key, 0, MTy::PTR);
    let seed = int(b, Op::IMul, size, K1);
    let h0 = int(b, Op::Xor, seed, K0);
    let acc = b.declare_var(MTy::INT, Mode::Borrow);
    let at = b.declare_var(MTy::INT, Mode::Borrow);
    b.def_var(acc, h0);
    let zero = b.iconst(0);
    b.def_var(at, zero);
    b.br(header, &[]);
    b.switch_to(header);
    let i = b.use_var(at);
    let end = int(b, Op::IAdd, i, 8);
    let more = b.icmp(Cc::Le, end, size);
    b.br_if(more, body, &[], tail, &[]);
    b.seal_block(body);
    b.seal_block(tail);
    b.switch_to(body);
    let word_at = b
        .emit(Op::PtrAdd, &[data, i], Imm::None, Some(MTy::PTR))
        .expect("ptr.add");
    let word = b
        .emit(Op::PtrLoadU, &[word_at], Imm::Int(8), Some(MTy::INT))
        .expect("ptr.loadu");
    let h = b.use_var(acc);
    let mixed = b.binop(Op::Xor, h, word);
    let h = fold(b, mixed, K1);
    b.def_var(acc, h);
    b.def_var(at, end);
    b.br(header, &[]);
    b.seal_block(header);
    b.switch_to(tail);
    let back = int(b, Op::ISub, size, 8);
    let last_at = b
        .emit(Op::PtrAdd, &[data, back], Imm::None, Some(MTy::PTR))
        .expect("ptr.add");
    let last = b
        .emit(Op::PtrLoadU, &[last_at], Imm::Int(8), Some(MTy::INT))
        .expect("ptr.loadu");
    let h = b.use_var(acc);
    let mixed = b.binop(Op::Xor, h, last);
    let hashed = fold(b, mixed, K0);
    b.def_var(hash, hashed);
    b.br(done, &[]);
    b.switch_to(short);
    // Length, and the bytes past the eighth (the string keeps the rest of its words zero).
    let len = int(b, Op::Ushr, w1, 56);
    let n = int(b, Op::And, len, 15);
    let high = int(b, Op::And, w1, (1 << 56) - 1);
    // The seed is the length; the two words are folded in turn (see `hash_bytes`).
    let seed = int(b, Op::IMul, n, K1);
    let h0 = int(b, Op::Xor, seed, K0);
    let first = b.binop(Op::Xor, h0, w0);
    let h1 = fold(b, first, K1);
    let mixed = b.binop(Op::Xor, h1, high);
    let hashed = fold(b, mixed, K0);
    b.def_var(hash, hashed);
    b.br(done, &[]);
    b.seal_block(done);
    b.switch_to(done);
    b.use_var(hash)
}

/// The probe loop: the value address of the key at `key` in the map at `m`, or null.
fn find(b: &mut FuncBuilder<'_>, shape: Shape, m: Value, key: Value) -> Value {
    let null = b
        .emit(Op::PtrNull, &[], Imm::None, Some(MTy::PTR))
        .expect("ptr.null");
    let (go, hit, miss) = (b.new_block(), b.new_block(), b.new_block());
    let len = load(b, m, LEN, MTy::INT);
    let zero = b.iconst(0);
    let empty = b.icmp(Cc::Eq, len, zero);
    b.br_if(empty, miss, &[], go, &[]);
    b.seal_block(go);
    b.switch_to(go);
    // The key and its hash.
    let k = if shape == Shape::StrMap {
        load(b, key, 0, MTy::STR)
    } else {
        load(b, key, 0, MTy::INT)
    };
    let h = if shape == Shape::StrMap {
        string_hash(b, key, k)
    } else {
        let x = int(b, Op::Xor, k, K0);
        let lo = int(b, Op::IMul, x, K1);
        let k1 = b.iconst(K1);
        let hi = b.binop(Op::UMulHi, x, k1);
        b.binop(Op::Xor, lo, hi)
    };
    let h = int(b, Op::Or, h, LIVE);
    let index = load(b, m, INDEX, MTy::PTR);
    let slots = load(b, m, SLOTS, MTy::PTR);
    let mask = load(b, m, MASK, MTy::INT);
    let fold = int(b, Op::Ushr, h, 32);
    let start = b.binop(Op::Xor, h, fold);
    let start = b.binop(Op::And, start, mask);
    let pos = b.declare_var(MTy::INT, Mode::Borrow);
    b.def_var(pos, start);
    let (header, tagged, check, next) =
        (b.new_block(), b.new_block(), b.new_block(), b.new_block());
    b.br(header, &[]);
    b.switch_to(header);
    let at = b.use_var(pos);
    let off = int(b, Op::Shl, at, 3);
    let ep = b
        .emit(Op::PtrAdd, &[index, off], Imm::None, Some(MTy::PTR))
        .expect("ptr.add");
    let e = b
        .emit(Op::Load, &[ep], Imm::Ty(MTy::INT), Some(MTy::INT))
        .expect("load");
    let zero = b.iconst(0);
    let vacant = b.icmp(Cc::Eq, e, zero);
    b.br_if(vacant, miss, &[], tagged, &[]);
    b.seal_block(tagged);
    b.switch_to(tagged);
    let diff = b.binop(Op::Xor, e, h);
    let tag = int(b, Op::Ushr, diff, 32);
    let zero = b.iconst(0);
    let same = b.icmp(Cc::Eq, tag, zero);
    b.br_if(same, check, &[], next, &[]);
    b.seal_block(check);
    b.switch_to(check);
    let low = int(b, Op::And, e, 0xffff_ffff);
    let n = int(b, Op::ISub, low, 1);
    let at_slot = int(b, Op::IMul, n, shape.stride());
    let slot = b
        .emit(Op::PtrAdd, &[slots, at_slot], Imm::None, Some(MTy::PTR))
        .expect("ptr.add");
    let found = if shape == Shape::StrMap {
        // The hashes agree, so the strings almost always do: equal words (an inline string, or
        // the very same block) decide it, and the general comparison handles the rest.
        let stored = load(b, slot, 0, MTy::INT);
        let (words, compare, matched) = (b.new_block(), b.new_block(), b.new_block());
        let verdict = b.declare_var(MTy::BOOL, Mode::Borrow);
        let no = b.bconst(false);
        b.def_var(verdict, no);
        let hashes = b.icmp(Cc::Eq, stored, h);
        b.br_if(hashes, words, &[], matched, &[]);
        b.seal_block(words);
        b.switch_to(words);
        let (s0, s1) = (load(b, slot, 8, MTy::INT), load(b, slot, 16, MTy::INT));
        let (k0, k1) = (load(b, key, 0, MTy::INT), load(b, key, 8, MTy::INT));
        let (e0, e1) = (b.icmp(Cc::Eq, s0, k0), b.icmp(Cc::Eq, s1, k1));
        let same = b.binop(Op::And, e0, e1);
        let yes = b.bconst(true);
        b.def_var(verdict, yes);
        b.br_if(same, matched, &[], compare, &[]);
        b.seal_block(compare);
        b.switch_to(compare);
        // Two blocks of 16 to 32 bytes: four overlapping word compares cover every byte.
        let (s1, k1) = (load(b, slot, 16, MTy::INT), load(b, key, 8, MTy::INT));
        let mask = (1 << 61) - 1;
        let (sn, kn) = (int(b, Op::And, s1, mask), int(b, Op::And, k1, mask));
        let (st, kt) = (int(b, Op::Ushr, s1, 62), int(b, Op::Ushr, k1, 62));
        let one = b.iconst(1);
        let (sf, kf) = (b.icmp(Cc::Ne, st, one), b.icmp(Cc::Ne, kt, one));
        let same_len = b.icmp(Cc::Eq, sn, kn);
        let c16 = b.iconst(16);
        let c32 = b.iconst(32);
        let (lo, hi) = (b.icmp(Cc::Ge, sn, c16), b.icmp(Cc::Le, sn, c32));
        let mut wide = b.binop(Op::And, sf, kf);
        for cond in [same_len, lo, hi] {
            wide = b.binop(Op::And, wide, cond);
        }
        let (blocks, general) = (b.new_block(), b.new_block());
        b.br_if(wide, blocks, &[], general, &[]);
        b.seal_block(blocks);
        b.seal_block(general);
        b.switch_to(blocks);
        let (sp, kp) = (load(b, slot, 8, MTy::PTR), load(b, key, 0, MTy::PTR));
        let back = int(b, Op::ISub, sn, 8);
        let back2 = int(b, Op::ISub, sn, 16);
        let eight = b.iconst(8);
        let mut all = b.bconst(true);
        for off in [None, Some(eight), Some(back2), Some(back)] {
            let (x, y) = match off {
                None => (sp, kp),
                Some(off) => (
                    b.emit(Op::PtrAdd, &[sp, off], Imm::None, Some(MTy::PTR))
                        .expect("ptr.add"),
                    b.emit(Op::PtrAdd, &[kp, off], Imm::None, Some(MTy::PTR))
                        .expect("ptr.add"),
                ),
            };
            let (u, v) = (
                b.emit(Op::PtrLoadU, &[x], Imm::Int(8), Some(MTy::INT))
                    .expect("ptr.loadu"),
                b.emit(Op::PtrLoadU, &[y], Imm::Int(8), Some(MTy::INT))
                    .expect("ptr.loadu"),
            );
            let e = b.icmp(Cc::Eq, u, v);
            all = b.binop(Op::And, all, e);
        }
        b.def_var(verdict, all);
        b.br(matched, &[]);
        b.switch_to(general);
        let stored_key = load(b, slot, 8, MTy::STR);
        let eq = string_eq(b, stored_key, k);
        b.def_var(verdict, eq);
        b.br(matched, &[]);
        b.seal_block(matched);
        b.switch_to(matched);
        b.use_var(verdict)
    } else {
        let stored = load(b, slot, 8, MTy::INT);
        b.icmp(Cc::Eq, stored, k)
    };
    b.br_if(found, hit, &[], next, &[]);
    b.seal_block(next);
    b.switch_to(next);
    let more = int(b, Op::IAdd, at, 1);
    let more = b.binop(Op::And, more, mask);
    b.def_var(pos, more);
    b.br(header, &[]);
    b.seal_block(header);
    // The answer: the slot's value address, or null.
    b.seal_block(hit);
    b.seal_block(miss);
    let out = b.declare_var(MTy::PTR, Mode::Borrow);
    let done = b.new_block();
    b.switch_to(miss);
    b.def_var(out, null);
    b.br(done, &[]);
    b.switch_to(hit);
    // The slot is rebuilt here from the loop's last `slot`: it dominates `hit`.
    let hit_slot = add(b, slot, shape.value_at());
    b.def_var(out, hit_slot);
    b.br(done, &[]);
    b.seal_block(done);
    b.switch_to(done);
    b.use_var(out)
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
        if sym == "msrt_string_view" {
            let f = self.view_fn();
            return Some(self.b.call(f, args));
        }
        let (shape, result) = probe_of(sym)?;
        let f = self.probe_fn(shape, result);
        let map = args[0];
        // A map held in memory is passed as its address (`update`); a map value is stored to
        // a slot to be read through its memory form.
        let mt = self.ty_of(map);
        let slot = if mt == MTy::PTR {
            map
        } else {
            let slot = self
                .b
                .emit(Op::Slot, &[], Imm::Ty(mt), Some(MTy::PTR))
                .expect("slot");
            self.b.emit(Op::Store, &[slot, map], Imm::None, None);
            slot
        };
        let mut call = vec![slot, args[3]];
        if result == Answer::Get {
            call.push(args[4]);
        }
        let v = self.b.call(f, &call);
        debug_assert_eq!(self.ty_of(v), ret);
        Some(v)
    }

    fn probe_fn(&mut self, shape: Shape, result: Answer) -> FuncId {
        let key = HelperKey::MapProbe(shape, result);
        if let Some(f) = self.cx.helpers.get(&key) {
            return *f;
        }
        let ptr = || Param {
            ty: MTy::PTR,
            mode: Mode::Borrow,
        };
        let mut params = vec![ptr(), ptr()];
        if result == Answer::Get {
            params.push(ptr());
        }
        let ret = match result {
            Answer::Address => MTy::PTR,
            _ => MTy::BOOL,
        };
        let mut b = FuncBuilder::new(self.b.m, "map_probe", params, ret);
        b.func_mut().linkage = Linkage::Internal;
        b.func_mut().inline = InlineHint::Always;
        let ps = b.params();
        let p = find(&mut b, shape, ps[0], ps[1]);
        let out = match result {
            Answer::Address => p,
            Answer::Contains => {
                let missing = b
                    .emit(Op::PtrIsNull, &[p], Imm::None, Some(MTy::BOOL))
                    .expect("is_null");
                b.unop(Op::Not, missing)
            }
            Answer::Get => {
                let missing = b
                    .emit(Op::PtrIsNull, &[p], Imm::None, Some(MTy::BOOL))
                    .expect("is_null");
                let (copy, done): (Block, Block) = (b.new_block(), b.new_block());
                let verdict = b.declare_var(MTy::BOOL, Mode::Borrow);
                let no = b.bconst(false);
                b.def_var(verdict, no);
                b.br_if(missing, done, &[], copy, &[]);
                b.seal_block(copy);
                b.switch_to(copy);
                let v = load(&mut b, p, 0, MTy::INT);
                b.emit(Op::Store, &[ps[2], v], Imm::None, None);
                let yes = b.bconst(true);
                b.def_var(verdict, yes);
                b.br(done, &[]);
                b.seal_block(done);
                b.switch_to(done);
                b.use_var(verdict)
            }
        };
        b.ret(Some(out));
        let func = b.into_func();
        let fid = self.b.m.add_func(func);
        self.cx.helpers.insert(key, fid);
        fid
    }
}

/// `String.view(start, end)` on the text at `s` (a slot holding the string): a flagged-ASCII text
/// with `0 <= start <= end <= len` continues in a fresh block; anything else branches to `slow`.
fn view_guard(b: &mut FuncBuilder<'_>, s: Value, start: Value, end: Value, slow: Block) {
    let w1 = load(b, s, 8, MTy::INT);
    let tag = int(b, Op::Ushr, w1, 62);
    let one = b.iconst(1);
    let flat = b.icmp(Cc::Ne, tag, one);
    let ascii = int(b, Op::And, w1, 1 << 61);
    let zero = b.iconst(0);
    let flagged = b.icmp(Cc::Ne, ascii, zero);
    let len = int(b, Op::And, w1, (1 << 61) - 1);
    let (a, c, d) = (
        b.icmp(Cc::Ge, start, zero),
        b.icmp(Cc::Le, start, end),
        b.icmp(Cc::Le, end, len),
    );
    let mut ok = b.binop(Op::And, flat, flagged);
    for cond in [a, c, d] {
        ok = b.binop(Op::And, ok, cond);
    }
    let fast = b.new_block();
    b.br_if(ok, fast, &[], slow, &[]);
    b.seal_block(fast);
    b.switch_to(fast);
}

impl FnLower<'_> {
    /// The generated `String.view`: parameters the string, `start` and `end`.
    fn view_fn(&mut self) -> FuncId {
        let key = HelperKey::StringView;
        if let Some(f) = self.cx.helpers.get(&key) {
            return *f;
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
            "msrt_string_view",
            &[MTy::STR, MTy::INT, MTy::INT, MTy::PTR],
            MTy::UNIT,
        );
        let mut b = FuncBuilder::new(self.b.m, "string_view", params, MTy::UNIT);
        b.func_mut().linkage = Linkage::Internal;
        b.func_mut().inline = InlineHint::Always;
        let ps = b.params();
        let (text, start, end, out) = (ps[0], ps[1], ps[2], ps[3]);
        let (slow, join) = (b.new_block(), b.new_block());
        let s = b
            .emit(Op::Slot, &[], Imm::Ty(MTy::STR), Some(MTy::PTR))
            .expect("slot");
        b.emit(Op::Store, &[s, text], Imm::None, None);
        view_guard(&mut b, s, start, end, slow);
        let w0 = load(&mut b, s, 0, MTy::PTR);
        let p = b
            .emit(Op::PtrAdd, &[w0, start], Imm::None, Some(MTy::PTR))
            .expect("ptr.add");
        let n = b.binop(Op::ISub, end, start);
        let (short, long) = (b.new_block(), b.new_block());
        let c15 = b.iconst(15);
        let fits = b.icmp(Cc::Le, n, c15);
        b.br_if(fits, short, &[], long, &[]);
        b.seal_block(short);
        b.seal_block(long);
        // Longer text: a view over the bytes.
        b.switch_to(long);
        let tagged = int(&mut b, Op::Or, n, 3 << 62);
        b.emit(Op::Store, &[out, p], Imm::None, None);
        let out8 = add(&mut b, out, 8);
        b.emit(Op::Store, &[out8, tagged], Imm::None, None);
        b.br(join, &[]);
        // A piece of up to fifteen bytes is copied into the two words of an inline string.
        b.switch_to(short);
        let (lo, hi) = pack_short(&mut b, p, n);
        let len_bits = int(&mut b, Op::Shl, n, 56);
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
        let fid = self.b.m.add_func(func);
        self.cx.helpers.insert(key, fid);
        fid
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
        if let Some(f) = self.cx.helpers.get(&key) {
            return *f;
        }
        let param = |ty| Param {
            ty,
            mode: Mode::Borrow,
        };
        let tys = [MTy::BYTES, MTy::INT, MTy::INT, MTy::BOOL, MTy::PTR];
        let ext = runtime_fn(self.b.m, "msrt_bytes_read_word", &tys, MTy::INT);
        let mut b = FuncBuilder::new(
            self.b.m,
            "bytes_read_word",
            tys.iter().map(|t| param(*t)).collect(),
            MTy::INT,
        );
        b.func_mut().linkage = Linkage::Internal;
        b.func_mut().inline = InlineHint::Always;
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
        let fid = self.b.m.add_func(func);
        self.cx.helpers.insert(key, fid);
        fid
    }
}
