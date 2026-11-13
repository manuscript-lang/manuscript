//! Strings and lists: the length leaf, element reads and writes, and string bytes.

use super::{Area, Cx, Vals, block_label, held_leaves, mem_leaves};
use crate::layout::{Layouts, Leaf, mem_layout};
use crate::llvm_build::{Bin, FnBuilder, Meta, Range, Tbaa, Ty as LTy, Val};
use ms_mir::ir::{FaultKind, Func, Imm, Inst, Module, Op, Term};
use ms_mir::types::{Ty, TyKind};
use ms_rt_abi::STR_STATIC;

pub(super) const AREA: Area = Area {
    handles,
    ty_ok,
    inst_ok,
    splits,
    pure_op: |op| matches!(op, Op::ListLen | Op::StrLit | Op::BytesLit),
    pre,
    emit,
};

/// Every list is three leaves, whatever its element.
fn ty_ok(k: &TyKind) -> bool {
    matches!(k, TyKind::Str | TyKind::Bytes | TyKind::List(_))
}

fn handles(op: Op) -> bool {
    op == Op::ListLen
        || list_arg(op).is_some()
        || matches!(
            op,
            Op::StrLit
                | Op::StrByte
                | Op::StrAsciiAt
                | Op::StrLen
                | Op::ListNew
                | Op::ListLit
                | Op::ListPush
                | Op::ListDropLast
                | Op::ListRelease
                | Op::BytesLit
                | Op::ListConst
                | Op::ListAddr
                | Op::ListAddrU
        )
}

/// Whether `op` is a list access that branches to a fault when checks are on.
fn checked(op: Op) -> bool {
    matches!(
        op,
        Op::ListGet | Op::ListGetNn | Op::ListSet | Op::ListSetNn | Op::ListFill | Op::ListAddr
    )
}

/// How many times `op` splits its block: a bounds check or a string read that joins branches
/// starts a new block, and a successor's phis name the label the block ends in.
fn splits(lay: &Layouts, f: &Func, i: &Inst, checks: bool) -> usize {
    let op = i.op;
    let drops = || {
        let e = lay.m.seq_elem(f.ty(i.args[0]));
        e.map_or(0, |e| super::glue::drop_splits(lay, e))
    };
    match op {
        Op::ListSet | Op::ListSetNn | Op::ListSetU => usize::from(checks && checked(op)) + drops(),
        _ if checked(op) => usize::from(checks),
        Op::ListDropLast if i.imm != Imm::Int(1) => drops(),
        Op::StrByte | Op::StrAsciiAt | Op::ListNew | Op::ListPush | Op::ListRelease => 1,
        _ => 0,
    }
}

fn inst_ok(m: &Module, lay: &Layouts, f: &Func, i: &Inst) -> bool {
    if i.op == Op::ListConst {
        return i
            .res
            .is_some_and(|r| m.seq_elem(f.ty(r)).is_some_and(|e| plain_elem(lay, e)));
    }
    if matches!(i.op, Op::ListAddr | Op::ListAddrU) {
        return m
            .seq_elem(f.ty(i.args[0]))
            .is_some_and(|e| plain_elem(lay, e));
    }
    if matches!(i.op, Op::ListNew | Op::ListLit | Op::ListPush) {
        return build_ok(m, lay, f, i);
    }
    if matches!(i.op, Op::ListDropLast | Op::ListRelease) {
        return release_ok(m, lay, f, i);
    }
    list_arg(i.op).is_none_or(|l| elem_ok(m, lay, f, i, l))
}

/// The length is a leaf of the list, and a write hands back the same list: no instruction.
fn pre(
    m: &Module,
    _: &Layouts,
    _: &Func,
    inst: &Inst,
    vals: &Vals,
    b: &mut FnBuilder,
) -> Option<Vec<Val>> {
    match inst.op {
        // Only the block pointer is computed; the length and capacity are known statically.
        Op::ListNew => Some(vec![
            b.reserve(LTy::Ptr),
            Val::int(0),
            vals[&inst.args[0].index()][0].clone(),
        ]),
        // The new length is computed; the block and capacity stay.
        Op::ListDropLast => {
            let l = &vals[&inst.args[0].index()];
            Some(vec![l[0].clone(), b.reserve(LTy::I64), l[2].clone()])
        }
        // The literal's bytes are a module constant: the pointer word is a constant expression
        // and the length carries the static tag.
        Op::StrLit => {
            let Imm::Str(id) = inst.imm else { return None };
            let len = m.strings[id.0 as usize].len();
            Some(vec![
                Val::new(
                    format!("ptrtoint (ptr @\"ms.lit.{}\" to i64)", id.0),
                    LTy::I64,
                ),
                Val::int((len | STR_STATIC) as i64),
            ])
        }
        Op::BytesLit => {
            let Imm::Int(i) = inst.imm else { return None };
            let n = m.blobs[i as usize].len() as i64;
            let ptr = if n == 0 {
                Val::new("null", LTy::Ptr)
            } else {
                Val::new(format!("@\"ms.direct.blob.{i}\""), LTy::Ptr)
            };
            Some(vec![ptr, Val::int(n), Val::int(0)])
        }
        Op::ListConst => {
            let Imm::Int(i) = inst.imm else { return None };
            let n = m.list_consts[i as usize].len() as i64;
            if n == 0 {
                return Some(vec![Val::new("null", LTy::Ptr), Val::int(0), Val::int(0)]);
            }
            Some(vec![b.reserve(LTy::Ptr), Val::int(n), Val::int(n)])
        }
        Op::ListLit if inst.args.is_empty() => {
            Some(vec![Val::new("null", LTy::Ptr), Val::int(0), Val::int(0)])
        }
        Op::ListLit => {
            let n = Val::int(inst.args.len() as i64);
            Some(vec![b.reserve(LTy::Ptr), n.clone(), n])
        }
        Op::ListLen => Some(vec![vals[&inst.args[0].index()][1].clone()]),
        Op::ListSet | Op::ListSetNn | Op::ListSetU | Op::ListFill => {
            Some(vals[&inst.args[0].index()].clone())
        }
        _ => None,
    }
}

/// The operand that is the list for the list reads and writes, `None` for other ops.
fn list_arg(op: Op) -> Option<usize> {
    match op {
        Op::ListGet | Op::ListGetNn | Op::ListGetU | Op::ListTake => Some(0),
        Op::ListSet | Op::ListSetNn | Op::ListSetU | Op::ListFill => Some(0),
        _ => None,
    }
}

/// Whether the element a list access moves is made of plain `i64`, `double` and `i8` leaves,
/// which sit in memory exactly as in registers, and needs no drop when overwritten.
fn elem_ok(m: &Module, lay: &Layouts, f: &Func, i: &Inst, list: usize) -> bool {
    let Some(e) = m.seq_elem(f.ty(i.args[list])) else {
        return false;
    };
    let writes = !matches!(
        i.op,
        Op::ListGet | Op::ListGetNn | Op::ListGetU | Op::ListTake
    );
    (!writes || i.args.len() == 3 && f.ty(i.args[2]) == e)
        && (writes || i.res.is_some_and(|r| f.ty(r) == e))
        && plain_elem(lay, e)
}

fn emit(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    match inst.op {
        Op::ListLen | Op::StrLit | Op::BytesLit => {}
        Op::StrByte | Op::StrAsciiAt => str_byte(cx, inst, vals, b),
        Op::ListNew | Op::ListLit | Op::ListPush => list_build(cx, inst, vals, b),
        Op::ListDropLast => {
            let out = &vals[&inst.res.expect("list result").index()];
            let len = vals[&inst.args[0].index()][1].clone();
            b.name_next(&out[1]);
            let last = b.bin(Bin::Add, &len, &Val::int(-1));
            let elem = cx.m.seq_elem(cx.f.ty(inst.args[0])).expect("a list");
            if cx.m.needs_drop(elem) && inst.imm != Imm::Int(1) {
                let ptr = vals[&inst.args[0].index()][0].clone();
                drop_elem(cx, b, elem, &ptr, &last);
            }
        }
        Op::ListRelease => list_release(cx, inst, vals, b),
        Op::ListConst => list_const(cx, inst, vals, b),
        Op::StrLen => str_len(cx, inst, vals, b),
        _ => list_access(cx, inst, vals, b),
    }
}

/// A list element access: normalize a negative index, branch to the fault when it is out of
/// range, then load or store each leaf of the element. The element type is an LLVM type, so the
/// address is a typed `getelementptr` and LLVM sees a strided access it can vectorize.
fn list_access(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    let l = &vals[&inst.args[0].index()];
    let i = vals[&inst.args[1].index()][0].clone();
    let elem = cx.m.seq_elem(cx.f.ty(inst.args[0])).expect("a list");
    let (ptr, len) = (l[0].clone(), l[1].clone());
    let wraps = matches!(
        inst.op,
        Op::ListGet | Op::ListSet | Op::ListFill | Op::ListAddr
    );
    let idx = if wraps {
        let neg = b.icmp("slt", &i, &Val::int(0));
        let wrapped = b.bin(Bin::Add, &i, &len);
        b.select(&neg, &wrapped, &i)
    } else {
        i.clone()
    };
    if cx.checks && checked(inst.op) {
        let oob = b.icmp("uge", &idx, &len);
        super::faults::fault_if(cx, b, &oob, "msrt_index_fault", &[i.clone(), len]);
    }
    let whole = elem_whole(b.types(), cx.lay, elem);
    debug_assert_eq!(
        b.types().size_align(&whole).0,
        u64::from(mem_layout(&cx.lay.leaves(elem)).size)
    );
    if matches!(inst.op, Op::ListAddr | Op::ListAddrU) {
        let out = &vals[&inst.res.expect("address result").index()][0];
        b.name_next(out);
        b.elem_ptr(&whole, &ptr, &idx);
        return;
    }
    let at = b.elem_ptr(&whole, &ptr, &idx);
    if matches!(inst.op, Op::ListSet | Op::ListSetNn | Op::ListSetU) && cx.m.needs_drop(elem) {
        drop_elem(cx, b, elem, &ptr, &idx);
    }
    if matches!(
        inst.op,
        Op::ListGet | Op::ListGetNn | Op::ListGetU | Op::ListTake
    ) {
        let out = &vals[&inst.res.expect("list read result").index()];
        load_at(cx, b, elem, &whole, &at, Some(out));
    } else {
        store_at(cx, b, elem, &whole, &at, &vals[&inst.args[2].index()]);
    }
}

/// The LLVM type of one element in a list block.
fn elem_whole(types: &crate::llvm_build::Types, lay: &Layouts, elem: Ty) -> LTy {
    let tys = mem_leaves(lay, elem);
    match tys.as_slice() {
        [one] => one.clone(),
        _ => super::aggregate(types, lay, elem),
    }
}

/// Loads the element at `at`. With `out` each result leaf takes its reserved name and a type
/// held in memory is copied into a fresh slot; without it the leaves are fresh values and such a
/// type is the pointer itself (what its drop glue takes).
fn load_at(
    cx: &Cx,
    b: &mut FnBuilder,
    elem: Ty,
    whole: &LTy,
    at: &Val,
    out: Option<&[Val]>,
) -> Vec<Val> {
    if super::types::is_mem(cx.lay, elem) {
        let Some(out) = out else {
            return vec![at.clone()];
        };
        super::types::load_value(b, cx.lay, elem, at, out);
        return out.to_vec();
    }
    let tys = mem_leaves(cx.lay, elem);
    let held = held_leaves(cx.lay, elem);
    let mut got = Vec::new();
    for (k, t) in tys.iter().enumerate() {
        let to = if tys.len() == 1 {
            at.clone()
        } else {
            b.leaf_ptr(whole, at, k)
        };
        let align = b.types().size_align(t).1;
        let meta = elem_meta(cx.m.types.kind(elem), k);
        let dst = out.map(|o| &o[k]);
        let named = |b: &mut FnBuilder| {
            if let Some(d) = dst {
                b.name_next(d);
            }
        };
        // A boolean is a byte in memory and a narrow integer its own width.
        let v = if *t == held[k] {
            named(b);
            b.load_with(t, &to, align, meta)
        } else {
            let w = b.load_with(t, &to, align, meta);
            named(b);
            super::types::widen(b, &w, &held[k])
        };
        got.push(v);
    }
    got
}

/// Stores the held leaves `vs` of one element at `at`.
fn store_at(cx: &Cx, b: &mut FnBuilder, elem: Ty, whole: &LTy, at: &Val, vs: &[Val]) {
    if super::types::is_mem(cx.lay, elem) {
        let (size, align) = b.types().size_align(whole);
        b.copy_bytes(at, &vs[0], size, align);
        return;
    }
    let tys = mem_leaves(cx.lay, elem);
    for (k, (t, v)) in tys.iter().zip(vs).enumerate() {
        let to = if tys.len() == 1 {
            at.clone()
        } else {
            b.leaf_ptr(whole, at, k)
        };
        let v = super::types::to_mem(b, v, t);
        let align = b.types().size_align(t).1;
        b.store_with(&v, &to, align, elem_meta(cx.m.types.kind(elem), k));
    }
}

/// Element `idx` of the block at `ptr` as its held leaves (a type in memory as its address).
fn load_elem(cx: &Cx, b: &mut FnBuilder, elem: Ty, ptr: &Val, idx: &Val) -> Vec<Val> {
    let whole = elem_whole(b.types(), cx.lay, elem);
    let at = b.elem_ptr(&whole, ptr, idx);
    load_at(cx, b, elem, &whole, &at, None)
}

/// Drops element `idx` of the block at `ptr`. A string element takes one split.
fn drop_elem(cx: &mut Cx, b: &mut FnBuilder, elem: Ty, ptr: &Val, idx: &Val) {
    let old = load_elem(cx, b, elem, ptr, idx);
    let (bb, at) = (cx.block, cx.split);
    let free = format!("b{bb}.df{at}");
    let cont = block_label(bb, at + 1);
    if super::glue::drop_leaves(cx, b, elem, &old, (&free, &cont)) {
        cx.split += 1;
    }
}

/// What LLVM may assume about leaf `k` of a list element of kind `elem`. A buffer holds one
/// element type, so a scalar element never lies where a list or string header does; only element
/// accesses are tagged, since a type field or inner header is also read through borrowed
/// pointers that carry no tag. A `Bool` is 0 or 1 and an inner list's length is not negative.
fn elem_meta(elem: &TyKind, k: usize) -> Meta {
    let mut meta = Meta::default();
    match elem {
        TyKind::Bool => {
            meta.tbaa = Some(Tbaa::ScalarElem);
            meta.range = Some(Range::Bool);
        }
        TyKind::Int
        | TyKind::Float
        | TyKind::Int8
        | TyKind::Int16
        | TyKind::Int32
        | TyKind::Float32
        | TyKind::UInt8
        | TyKind::UInt16
        | TyKind::UInt32
        | TyKind::UInt64 => meta.tbaa = Some(Tbaa::ScalarElem),
        TyKind::List(_) | TyKind::Bytes => {
            meta.tbaa = Some(Tbaa::HeaderElem);
            if k == 1 {
                meta.range = Some(Range::Len);
            }
        }
        TyKind::Str => meta.tbaa = Some(Tbaa::HeaderElem),
        _ => {}
    }
    meta
}

/// Bytes in one word of an inline string, which holds its bytes in two words.
const WORD_BYTES: i64 = 8;

/// `StrByte` and `StrAsciiAt`: the byte at an index of a string. An inline string keeps its
/// bytes in its two words, little-endian, so the byte is a shift and mask; any other string loads
/// it from memory. `StrAsciiAt` yields -1 unless the string is flagged ASCII and the index is in
/// range, and the caller then takes the general path.
fn str_byte(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    use ms_rt_abi::{STR_ASCII, STR_INLINE, STR_LEN_MASK};
    let s = &vals[&inst.args[0].index()];
    let i = vals[&inst.args[1].index()][0].clone();
    let out = vals[&inst.res.expect("string byte result").index()][0].clone();
    let (bb, split) = (cx.block, cx.split);
    let load = format!("l{bb}_{split}");
    let join = block_label(bb, split + 1);
    cx.split += 1;
    let load_byte = |b: &mut FnBuilder, i: &Val| {
        let ptr = b.int_to_ptr(&s[0]);
        let at = b.elem_ptr(&LTy::I8, &ptr, i);
        let byte = b.load(&LTy::I8, &at, 1);
        b.zext(&byte, LTy::I64)
    };
    if inst.op == Op::StrAsciiAt {
        // Flagged ASCII and not inline: the ASCII bit is set and the inline bit is clear.
        let flags = b.bin(Bin::And, &s[1], &Val::int((STR_INLINE | STR_ASCII) as i64));
        let ascii = b.icmp("eq", &flags, &Val::int(STR_ASCII as i64));
        let len = b.bin(Bin::And, &s[1], &Val::int(STR_LEN_MASK as i64));
        let below = b.icmp("ult", &i, &len);
        let ok = b.bin(Bin::And, &ascii, &below);
        let head = block_label(bb, split);
        b.cond_br(&ok, &load, &join);
        b.label(&load);
        let byte = load_byte(b, &i);
        b.br(&join);
        b.label(&join);
        b.phi(&out, &[(Val::int(-1), head), (byte, load)]);
        return;
    }
    // The top two bits are `01` for an inline string (`STR_INLINE` set, `STR_BORROWED` clear).
    let tag = b.bin(Bin::And, &s[1], &Val::int((3usize << 62) as i64));
    let inline = b.icmp("eq", &tag, &Val::int(STR_INLINE as i64));
    let word = format!("w{bb}_{split}");
    b.cond_br(&inline, &word, &load);
    b.label(&word);
    let high = b.icmp("sge", &i, &Val::int(WORD_BYTES));
    let w = b.select(&high, &s[1], &s[0]);
    let shift = b.bin(Bin::And, &i, &Val::int(WORD_BYTES - 1));
    let shift = b.bin(Bin::Shl, &shift, &Val::int(3));
    let w = b.bin(Bin::LShr, &w, &shift);
    let inline_byte = b.bin(Bin::And, &w, &Val::int(0xff));
    b.br(&join);
    b.label(&load);
    let mem_byte = load_byte(b, &i);
    b.br(&join);
    b.label(&join);
    b.phi(&out, &[(inline_byte, word), (mem_byte, load)]);
}

/// Whether the elements a list is built from are plain `i64`, `double` and `i8` leaves (a
/// `ListNew` stores none, so any element will do).
fn build_ok(m: &Module, lay: &Layouts, f: &Func, i: &Inst) -> bool {
    let list = if i.op == Op::ListPush {
        f.ty(i.args[0])
    } else {
        match i.res {
            Some(r) => f.ty(r),
            None => return false,
        }
    };
    let Some(e) = m.seq_elem(list) else {
        return false;
    };
    let args_ok = match i.op {
        Op::ListNew => i.args.len() == 1,
        Op::ListLit => i.args.iter().all(|a| f.ty(*a) == e),
        _ => i.args.len() == 2 && f.ty(i.args[1]) == e,
    };
    args_ok && plain_elem(lay, e)
}

/// A call to a runtime allocator; its result is a fresh block of memory. Arguments cross as
/// `i64` words, like every other runtime call, so the declaration agrees with the one the
/// translated path writes for the same symbol.
fn rt_alloc(cx: &mut Cx, b: &mut FnBuilder, name: &str, args: &[Val], dst: Option<&Val>) -> Val {
    super::rt::declare(cx, name);
    let actuals: Vec<(Val, &str)> = args.iter().map(|a| (a.clone(), "")).collect();
    if let Some(d) = dst {
        b.name_next(d);
    }
    b.call(&LTy::Ptr, "noalias align 16 ", name, &actuals)
        .expect("a pointer")
}

/// Stores the leaves `vs` of one element at index `idx` of the list block at `ptr`.
fn store_elem(cx: &Cx, b: &mut FnBuilder, list: Ty, ptr: &Val, idx: &Val, vs: &[Val]) {
    let elem = cx.m.seq_elem(list).expect("a list");
    let whole = elem_whole(b.types(), cx.lay, elem);
    let at = b.elem_ptr(&whole, ptr, idx);
    store_at(cx, b, elem, &whole, &at, vs);
}

/// `ListNew` (a block of `cap` elements, none when `cap` is zero), `ListLit` (a block holding
/// the arguments) and `ListPush` (append, growing the block when it is full). A list is `(ptr,
/// len, cap)`; `ListNew` and `ListLit` know the last two statically.
fn list_build(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    let out = &vals[&inst.res.expect("list result").index()];
    let list = cx.f.ty(inst.res.expect("list result"));
    let elem = cx.m.seq_elem(list).expect("a list");
    let size = i64::from(mem_layout(&cx.lay.leaves(elem)).size).max(1);
    let (bb, split) = (cx.block, cx.split);
    let head = block_label(bb, split);
    match inst.op {
        Op::ListLit => {
            if inst.args.is_empty() {
                return;
            }
            let bytes = Val::int(inst.args.len() as i64 * size);
            let ptr = rt_alloc(cx, b, "msrt_alloc", &[bytes], Some(&out[0]));
            for (i, a) in inst.args.iter().enumerate() {
                store_elem(cx, b, list, &ptr, &Val::int(i as i64), &vals[&a.index()]);
            }
        }
        Op::ListNew => {
            let cap = vals[&inst.args[0].index()][0].clone();
            let (some, join) = (format!("n{bb}_{split}"), block_label(bb, split + 1));
            cx.split += 1;
            let nz = b.icmp("ne", &cap, &Val::int(0));
            b.cond_br(&nz, &some, &join);
            b.label(&some);
            let bytes = b.bin(Bin::Mul, &cap, &Val::int(size));
            let p = rt_alloc(cx, b, "msrt_alloc", &[bytes], None);
            b.br(&join);
            b.label(&join);
            b.phi(&out[0], &[(Val::new("null", LTy::Ptr), head), (p, some)]);
        }
        _ => {
            let l = &vals[&inst.args[0].index()];
            let (ptr0, len, cap) = (l[0].clone(), l[1].clone(), l[2].clone());
            let (grow, first, again, joined) = (
                format!("g{bb}_{split}"),
                format!("p{bb}_{split}"),
                format!("r{bb}_{split}"),
                format!("j{bb}_{split}"),
            );
            let ready = block_label(bb, split + 1);
            cx.split += 1;
            let full = b.icmp("eq", &len, &cap);
            b.cond_br_likely(&full, &grow, &ready, false);
            b.label(&grow);
            let empty = b.icmp("eq", &cap, &Val::int(0));
            let doubled = b.bin(Bin::Shl, &cap, &Val::int(1));
            let ncap = b.select(&empty, &Val::int(4), &doubled);
            let bytes = b.bin(Bin::Mul, &ncap, &Val::int(size));
            b.cond_br(&empty, &first, &again);
            b.label(&first);
            let fresh = rt_alloc(cx, b, "msrt_alloc", std::slice::from_ref(&bytes), None);
            b.br(&joined);
            b.label(&again);
            let moved = rt_alloc(cx, b, "msrt_realloc", &[ptr0.clone(), bytes], None);
            b.br(&joined);
            b.label(&joined);
            let np = b.reserve(LTy::Ptr);
            b.phi(&np, &[(fresh, first), (moved, again)]);
            b.br(&ready);
            b.label(&ready);
            b.phi(&out[0], &[(ptr0, head.clone()), (np, joined.clone())]);
            b.phi(&out[2], &[(cap, head), (ncap, joined)]);
            store_elem(cx, b, list, &out[0], &len, &vals[&inst.args[1].index()]);
            b.name_next(&out[1]);
            b.bin(Bin::Add, &len, &Val::int(1));
        }
    }
}

/// `ListConst`: a fresh block holding a copy of the constant's elements.
fn list_const(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    let Imm::Int(i) = inst.imm else { return };
    let out = &vals[&inst.res.expect("list result").index()];
    let elem =
        cx.m.seq_elem(cx.f.ty(inst.res.expect("list result")))
            .expect("a list");
    let size = i64::from(mem_layout(&cx.lay.leaves(elem)).size);
    let bytes = Val::int(cx.m.list_consts[i as usize].len() as i64 * size);
    let p = rt_alloc(
        cx,
        b,
        "msrt_alloc",
        std::slice::from_ref(&bytes),
        Some(&out[0]),
    );
    let src = Val::new(format!("@\"ms.direct.list.{i}\""), LTy::Ptr);
    b.memcpy((&p, 16), (&src, 16), &bytes);
}

/// `ListDropLast` and `ListRelease`; `list.droplast 1` follows a `list.take` of that element, so
/// it drops nothing.
fn release_ok(m: &Module, lay: &Layouts, f: &Func, i: &Inst) -> bool {
    let Some(e) = m.seq_elem(f.ty(i.args[0])) else {
        return false;
    };
    !m.needs_drop(e) || (i.op == Op::ListDropLast && i.imm == Imm::Int(1)) || plain_elem(lay, e)
}

/// `ListRelease`: drop the elements from index `from` on (the ones before it were moved out), then
/// free the block of an owned list (`cap != 0`; a view owns nothing) that has one.
fn list_release(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    let l = &vals[&inst.args[0].index()];
    let (bb, split) = (cx.block, cx.split);
    let (free, join) = (format!("e{bb}_{split}"), block_label(bb, split + 1));
    cx.split += 1;
    let owned = b.icmp("ne", &l[2], &Val::int(0));
    let some = b.icmp("ne", &l[0], &Val::new("null", LTy::Ptr));
    let both = b.bin(Bin::And, &owned, &some);
    b.cond_br(&both, &free, &join);
    b.label(&free);
    let elem = cx.m.seq_elem(cx.f.ty(inst.args[0])).expect("a list");
    if cx.m.needs_drop(elem) {
        drop_loop(cx, b, elem, l, &vals[&inst.args[1].index()][0], &free);
    }
    super::rt::declare(cx, "msrt_free");
    b.call(&LTy::Void, "", "msrt_free", &[(l[0].clone(), "")]);
    b.br(&join);
    b.label(&join);
}

/// Drops the elements of the list `l` from index `from` (a negative one counts from the start)
/// to its end, entered from block `entry`, and leaves the code in a fresh block after the loop.
fn drop_loop(cx: &mut Cx, b: &mut FnBuilder, elem: Ty, l: &[Val], from: &Val, entry: &str) {
    let bb = cx.block;
    let at = cx.split;
    let tag = |s: &str| format!("b{bb}.r{at}{s}");
    let (head, body, latch, done) = (tag("h"), tag("b"), tag("l"), tag("d"));
    let neg = b.icmp("slt", from, &Val::int(0));
    let start = b.select(&neg, &Val::int(0), from);
    b.br(&head);
    b.label(&head);
    let (i, next) = (b.reserve(LTy::I64), b.reserve(LTy::I64));
    // `i` is the loop variable: `start` on entry, `next` on the back edge.
    b.phi(
        &i,
        &[(start, entry.to_string()), (next.clone(), latch.clone())],
    );
    let more = b.icmp("slt", &i, &l[1]);
    b.cond_br(&more, &body, &done);
    b.label(&body);
    let old = load_elem(cx, b, elem, &l[0], &i);
    let (free, cont) = (tag("f"), latch.clone());
    super::glue::drop_leaves(cx, b, elem, &old, (&free, &cont));
    // A string drop ends in `latch`; any other drop is straight-line, so enter it.
    if super::glue::drop_splits(cx.lay, elem) == 0 {
        b.br(&latch);
        b.label(&latch);
    }
    b.name_next(&next);
    b.bin(Bin::Add, &i, &Val::int(1));
    b.br(&head);
    b.label(&done);
}

/// `StrLen`: the scalar count, computed by the runtime from the string's two words in a slot.
fn str_len(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    let s = &vals[&inst.args[0].index()];
    let out = &vals[&inst.res.expect("string length result").index()][0];
    let pair = LTy::Tuple(vec![LTy::I64, LTy::I64]);
    let slot = b.alloca(&pair);
    for (k, w) in s.iter().enumerate() {
        let at = b.field_ptr(&pair, &slot, k);
        b.store(w, &at, 8);
    }
    super::rt::declare(cx, "msrt_string_length");
    let addr = b.ptr_to_int(&slot);
    b.name_next(out);
    b.call(&LTy::I64, "", "msrt_string_length", &[(addr, "")]);
}

/// The module-level constants for the string literals `f` uses: LLVM owns the bytes, so it knows
/// their size, that they never change, and that no other symbol aliases them.
pub(super) fn consts(m: &Module, lay: &Layouts, f: &Func) -> Vec<(String, String)> {
    let mut out: Vec<(String, String)> = Vec::new();
    for inst in f.blocks.iter().flat_map(|b| &b.insts) {
        if let (Op::BytesLit | Op::ListConst, Imm::Int(i)) = (inst.op, inst.imm) {
            let (name, bytes) = if inst.op == Op::BytesLit {
                (format!("ms.direct.blob.{i}"), m.blobs[i as usize].clone())
            } else {
                let e = m
                    .seq_elem(f.ty(inst.res.expect("list result")))
                    .expect("a list");
                let width = lay.leaves(e)[0].size() as usize;
                let raw = &m.list_consts[i as usize];
                (
                    format!("ms.direct.list.{i}"),
                    raw.iter()
                        .flat_map(|v| v.to_le_bytes()[..width].to_vec())
                        .collect(),
                )
            };
            if !bytes.is_empty() && !out.iter().any(|(n, _)| *n == name) {
                let text: String = bytes.iter().map(|b| format!("\\{b:02X}")).collect();
                let def = format!(
                    "@\"{name}\" = private unnamed_addr constant [{} x i8] c\"{text}\", align 16",
                    bytes.len()
                );
                out.push((name, def));
            }
            continue;
        }
        if let (Op::StrLit, Imm::Str(id)) = (inst.op, inst.imm) {
            str_const(m, id.0, &mut out);
        }
    }
    for b in &f.blocks {
        if let Term::Fault(FaultKind::Message(id)) = b.term {
            str_const(m, id.0, &mut out);
        }
    }
    out
}

/// The constant for string literal `id`, once.
fn str_const(m: &Module, id: u32, out: &mut Vec<(String, String)>) {
    let name = format!("ms.lit.{id}");
    if out.iter().any(|(n, _)| *n == name) {
        return;
    }
    let mut text = String::new();
    let bytes = m.strings[id as usize].as_bytes();
    for &b in bytes.iter().chain(&[0u8]) {
        if (0x20..0x7f).contains(&b) && b != b'"' && b != b'\\' {
            text.push(b as char);
        } else {
            text.push_str(&format!("\\{b:02X}"));
        }
    }
    let def = format!(
        "@\"{name}\" = private unnamed_addr constant [{} x i8] c\"{text}\", align 16",
        bytes.len() + 1
    );
    out.push((name, def));
}

/// Whether an element can sit in a list block: leaves that are `i64`, `double`, `i8` or narrow
/// integers, or a type held in memory.
fn plain_elem(lay: &Layouts, e: Ty) -> bool {
    (super::types::is_mem(lay, e) && super::types::shape_ok(lay, e))
        || lay
            .leaves(e)
            .iter()
            .all(|l| matches!(l, Leaf::I64 | Leaf::F64 | Leaf::I8) || super::types::is_narrow(*l))
}
