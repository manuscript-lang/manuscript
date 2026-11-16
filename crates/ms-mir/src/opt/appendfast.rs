//! The `appendfast` pass: `s += piece` on an owned string with room left runs as a few
//! instructions in the caller instead of a runtime call.
//!
//! [`strfuse`](super::strfuse) turns a concatenation whose left side dies into
//! `string_append`, which grows the block in place. The runtime call decodes both strings,
//! asks the allocator how much room the block has, and copies. An owned string records its
//! spare room in its second word (see `STR_SPARE_MASK`), so the common case is decided from the
//! two words: an owned receiver, a piece of 1 to 16 bytes (inline, or flat not inside the
//! receiver), room for it, and an ASCII flag that stays true. That case writes the piece, the NUL
//! and the new length word, and nothing else. Every other case calls the runtime.
//!
//! The fast path is one generated function marked `inline(always)`, shared by every call site.

use crate::builder::FuncBuilder;
use crate::ir::*;
use crate::types::Ty;

use ms_rt_abi::{
    STR_ASCII, STR_INLINE_LEN_SHIFT, STR_INLINE_MAX, STR_LEN_MASK, STR_SPARE_MASK, STR_SPARE_SHIFT,
};

/// Longest piece the fast path copies.
const MAX_PIECE: i64 = 16;

/// Rewrites every `string_append` call into a call of the generated fast path; returns whether
/// anything changed. The caller runs the inliner afterwards.
pub fn run(m: &mut Module) -> bool {
    let sites: Vec<(usize, usize, usize, ExtId)> = m
        .funcs
        .iter()
        .enumerate()
        .flat_map(|(fi, f)| {
            f.blocks.iter().enumerate().flat_map(move |(bi, b)| {
                b.insts
                    .iter()
                    .enumerate()
                    .filter_map(move |(ii, i)| match (i.op, i.imm) {
                        (Op::CallRt, Imm::Ext(e)) => Some((fi, bi, ii, e)),
                        _ => None,
                    })
            })
        })
        .filter(|&(_, _, _, e)| m.externs[e.index()].role == ExternRole::StringAppend)
        .collect();
    if sites.is_empty() {
        return false;
    }
    let ext = sites[0].3;
    let helper = build(m, ext);
    for (fi, bi, ii, _) in sites {
        let inst = &mut m.funcs[fi].blocks[bi].insts[ii];
        inst.op = Op::Call;
        inst.imm = Imm::Func(helper);
    }
    true
}

fn load(b: &mut FuncBuilder<'_>, p: Value, at: i64, ty: Ty) -> Value {
    let p = add(b, p, at);
    b.emit(Op::Load, &[p], Imm::Ty(ty), Some(ty)).expect("load")
}

fn add(b: &mut FuncBuilder<'_>, p: Value, at: i64) -> Value {
    if at == 0 {
        return p;
    }
    let off = b.iconst(at);
    b.emit(Op::PtrAdd, &[p, off], Imm::None, Some(Ty::PTR))
        .expect("ptr.add")
}

fn int(b: &mut FuncBuilder<'_>, op: Op, x: Value, y: i64) -> Value {
    let y = b.iconst(y);
    b.binop(op, x, y)
}

fn loadu(b: &mut FuncBuilder<'_>, p: Value, w: i64) -> Value {
    b.emit(Op::PtrLoadU, &[p], Imm::Int(w), Some(Ty::INT))
        .expect("ptr.loadu")
}

fn storeu(b: &mut FuncBuilder<'_>, p: Value, v: Value, w: i64) {
    b.emit(Op::PtrStoreU, &[p, v], Imm::Int(w), None);
}

/// Copies `n` (1 to 16) bytes from `src` to `dst` with overlapping fixed-width moves; every load
/// happens before the stores, so the ranges may even touch.
fn copy_short(b: &mut FuncBuilder<'_>, src: Value, dst: Value, n: Value) {
    let (big, rest, mid, small, done) = (
        b.new_block(),
        b.new_block(),
        b.new_block(),
        b.new_block(),
        b.new_block(),
    );
    let c8 = b.iconst(8);
    let ge8 = b.icmp(Cc::Ge, n, c8);
    b.br_if(ge8, big, &[], rest, &[]);
    b.seal_block(big);
    b.seal_block(rest);
    // Eight to sixteen: the first eight bytes and the last eight.
    b.switch_to(big);
    let back = int(b, Op::ISub, n, 8);
    let (s_hi, d_hi) = (past(b, src, back), past(b, dst, back));
    let (lo, hi) = (loadu(b, src, 8), loadu(b, s_hi, 8));
    storeu(b, dst, lo, 8);
    storeu(b, d_hi, hi, 8);
    b.br(done, &[]);
    b.switch_to(rest);
    let c4 = b.iconst(4);
    let ge4 = b.icmp(Cc::Ge, n, c4);
    b.br_if(ge4, mid, &[], small, &[]);
    b.seal_block(mid);
    b.seal_block(small);
    // Four to seven: the first four and the last four.
    b.switch_to(mid);
    let back = int(b, Op::ISub, n, 4);
    let (s_hi, d_hi) = (past(b, src, back), past(b, dst, back));
    let (lo, hi) = (loadu(b, src, 4), loadu(b, s_hi, 4));
    storeu(b, dst, lo, 4);
    storeu(b, d_hi, hi, 4);
    b.br(done, &[]);
    // One to three: the first, middle and last byte.
    b.switch_to(small);
    let half = int(b, Op::Ushr, n, 1);
    let last = int(b, Op::ISub, n, 1);
    let (s_mid, s_last) = (past(b, src, half), past(b, src, last));
    let (d_mid, d_last) = (past(b, dst, half), past(b, dst, last));
    let (x0, x1, x2) = (loadu(b, src, 1), loadu(b, s_mid, 1), loadu(b, s_last, 1));
    storeu(b, dst, x0, 1);
    storeu(b, d_mid, x1, 1);
    storeu(b, d_last, x2, 1);
    b.br(done, &[]);
    b.seal_block(done);
    b.switch_to(done);
}

fn past(b: &mut FuncBuilder<'_>, p: Value, by: Value) -> Value {
    b.emit(Op::PtrAdd, &[p, by], Imm::None, Some(Ty::PTR))
        .expect("ptr.add")
}

/// Builds `string_append_fast(a: owned str, b: str) -> str`, which calls `slow` when the fast
/// path does not apply.
fn build(m: &mut Module, slow: ExtId) -> FuncId {
    let params = vec![
        Param {
            ty: Ty::STR,
            mode: Mode::Move,
        },
        Param {
            ty: Ty::STR,
            mode: Mode::Borrow,
        },
    ];
    let mut b = FuncBuilder::new(m, "string_append_fast", params, Ty::STR);
    b.func_mut().linkage = Linkage::Internal;
    b.func_mut().inline = InlineHint::Always;
    let ps = b.params();
    let (a, piece) = (ps[0], ps[1]);
    let (fast, slow_block) = (b.new_block(), b.new_block());
    // `a` sits in a slot while its words are read and rewritten; `piece` is read from a copy.
    let sa = b
        .emit(Op::Slot, &[], Imm::Ty(Ty::STR), Some(Ty::PTR))
        .expect("slot");
    b.emit(Op::Put, &[sa, a], Imm::None, None);
    let sb = b
        .emit(Op::Slot, &[], Imm::Ty(Ty::STR), Some(Ty::PTR))
        .expect("slot");
    b.emit(Op::Store, &[sb, piece], Imm::None, None);
    // The addresses are read as integers to compare and again as pointers to write through.
    let (aw0, aw1) = (load(&mut b, sa, 0, Ty::INT), load(&mut b, sa, 8, Ty::INT));
    let (bw0, bw1) = (load(&mut b, sb, 0, Ty::INT), load(&mut b, sb, 8, Ty::INT));
    let zero = b.iconst(0);
    let one = b.iconst(1);
    // An owned receiver of some length, and a non-empty piece of at most 16 bytes: an inline
    // string (its bytes are in its own words) or a flat one.
    let atag = int(&mut b, Op::Ushr, aw1, 62);
    let owned = b.icmp(Cc::Eq, atag, zero);
    let la = int(&mut b, Op::And, aw1, STR_LEN_MASK as i64);
    let has_text = b.icmp(Cc::Gt, la, zero);
    let btag = int(&mut b, Op::Ushr, bw1, 62);
    let inline = b.icmp(Cc::Eq, btag, one);
    let inline_len = int(&mut b, Op::Ushr, bw1, i64::from(STR_INLINE_LEN_SHIFT));
    let inline_len = int(&mut b, Op::And, inline_len, STR_INLINE_MAX as i64);
    let flat_len = int(&mut b, Op::And, bw1, STR_LEN_MASK as i64);
    let lb = b.select(inline, inline_len, flat_len);
    let some = b.icmp(Cc::Gt, lb, zero);
    let max = b.iconst(MAX_PIECE);
    let short = b.icmp(Cc::Le, lb, max);
    // Room recorded for the piece.
    let spare = int(&mut b, Op::Ushr, aw1, i64::from(STR_SPARE_SHIFT));
    let spare = int(
        &mut b,
        Op::And,
        spare,
        (STR_SPARE_MASK >> STR_SPARE_SHIFT) as i64,
    );
    let room = b.icmp(Cc::Ge, spare, lb);
    // A flat piece does not lie inside the receiver's text (it could not be copied in place).
    let end = b.binop(Op::IAdd, aw0, la);
    let (outside_lo, outside_hi) = (b.icmp(Cc::Lt, bw0, aw0), b.icmp(Cc::Gt, bw0, end));
    let outside = b.binop(Op::Or, outside_lo, outside_hi);
    let apart = b.binop(Op::Or, inline, outside);
    // A flagged receiver stays flagged only with an ASCII piece; an unflagged one never is.
    let a_flag = int(&mut b, Op::And, aw1, STR_ASCII as i64);
    let b_flag = int(&mut b, Op::And, bw1, STR_ASCII as i64);
    let a_plain = b.icmp(Cc::Eq, a_flag, zero);
    let b_flagged = b.icmp(Cc::Ne, b_flag, zero);
    let high0 = int(&mut b, Op::And, bw0, 0x8080_8080_8080_8080_u64 as i64);
    let high1 = int(&mut b, Op::And, bw1, 0x0080_8080_8080_8080);
    let high = b.binop(Op::Or, high0, high1);
    let bits_ascii = b.icmp(Cc::Eq, high, zero);
    let b_ascii = b.select(inline, bits_ascii, b_flagged);
    let ascii = b.binop(Op::Or, a_plain, b_ascii);
    let mut ok = owned;
    for c in [has_text, some, short, room, apart, ascii] {
        ok = b.binop(Op::And, ok, c);
    }
    b.br_if(ok, fast, &[], slow_block, &[]);
    b.seal_block(fast);
    b.seal_block(slow_block);
    b.switch_to(fast);
    let (text, flat_from) = (load(&mut b, sa, 0, Ty::PTR), load(&mut b, sb, 0, Ty::PTR));
    let from = b.select(inline, sb, flat_from);
    let dst = past(&mut b, text, la);
    copy_short(&mut b, from, dst, lb);
    // The NUL after the text, then the length word: longer by the piece, with that much less room.
    let nul_at = past(&mut b, dst, lb);
    storeu(&mut b, nul_at, zero, 1);
    let grown = b.binop(Op::IAdd, aw1, lb);
    let used = int(&mut b, Op::Shl, lb, i64::from(STR_SPARE_SHIFT));
    let tagged = b.binop(Op::ISub, grown, used);
    let slot_len = add(&mut b, sa, 8);
    b.emit(Op::Store, &[slot_len, tagged], Imm::None, None);
    let r = b
        .emit(Op::Take, &[sa], Imm::Ty(Ty::STR), Some(Ty::STR))
        .expect("take");
    b.ret(Some(r));
    b.switch_to(slow_block);
    let a2 = b
        .emit(Op::Take, &[sa], Imm::Ty(Ty::STR), Some(Ty::STR))
        .expect("take");
    let r = b.call_rt(slow, &[a2, piece]);
    b.ret(Some(r));
    let func = b.into_func();
    m.add_func(func)
}
