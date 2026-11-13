//! Strings and lists: the length leaf, element reads and writes, and string bytes.

use super::{Area, Cx, Vals, block_label, held_leaves, mem_leaves};
use crate::layout::{Layouts, Leaf, mem_layout};
use crate::llvm_build::{Bin, FnBuilder, Meta, Range, Tbaa, Ty as LTy, Val};
use ms_mir::ir::{Func, Imm, Inst, Module, Op};
use ms_mir::types::{Ty, TyKind};

pub(super) const AREA: Area = Area {
    handles,
    ty_ok,
    inst_ok,
    splits,
    pure_op: |op| op == Op::ListLen,
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
            Op::StrByte
                | Op::StrAsciiAt
                | Op::StrLen
                | Op::ListNew
                | Op::ListLit
                | Op::ListPush
                | Op::ListDropLast
                | Op::ListRelease
        )
}

/// Whether `op` is a list access that branches to a fault when checks are on.
fn checked(op: Op) -> bool {
    matches!(
        op,
        Op::ListGet | Op::ListGetNn | Op::ListSet | Op::ListSetNn | Op::ListFill
    )
}

/// How many times `op` splits its block: a bounds check or a string read that joins branches
/// starts a new block, and a successor's phis name the label the block ends in.
fn splits(_: &Layouts, _: &Func, i: &Inst, checks: bool) -> usize {
    let op = i.op;
    match op {
        _ if checked(op) => usize::from(checks),
        Op::StrByte | Op::StrAsciiAt | Op::ListNew | Op::ListPush | Op::ListRelease => 1,
        _ => 0,
    }
}

fn inst_ok(m: &Module, lay: &Layouts, f: &Func, i: &Inst) -> bool {
    if matches!(i.op, Op::ListNew | Op::ListLit | Op::ListPush) {
        return build_ok(m, lay, f, i);
    }
    if matches!(i.op, Op::ListDropLast | Op::ListRelease) {
        return release_ok(m, f, i);
    }
    list_arg(i.op).is_none_or(|l| elem_ok(m, lay, f, i, l))
}

/// The length is a leaf of the list, and a write hands back the same list: no instruction.
fn pre(_: &Layouts, _: &Func, inst: &Inst, vals: &Vals, b: &mut FnBuilder) -> Option<Vec<Val>> {
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
    (!writes || !m.needs_drop(e) && i.args.len() == 3 && f.ty(i.args[2]) == e)
        && (writes || i.res.is_some_and(|r| f.ty(r) == e))
        && plain_elem(lay, e)
}

fn emit(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    match inst.op {
        Op::ListLen => {}
        Op::StrByte | Op::StrAsciiAt => str_byte(cx, inst, vals, b),
        Op::ListNew | Op::ListLit | Op::ListPush => list_build(cx, inst, vals, b),
        Op::ListDropLast => {
            let out = &vals[&inst.res.expect("list result").index()];
            let len = vals[&inst.args[0].index()][1].clone();
            b.name_next(&out[1]);
            b.bin(Bin::Add, &len, &Val::int(-1));
        }
        Op::ListRelease => list_release(cx, inst, vals, b),
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
    let tys = mem_leaves(cx.lay, elem);
    let held = held_leaves(cx.lay, elem);
    let (ptr, len) = (l[0].clone(), l[1].clone());
    let wraps = matches!(inst.op, Op::ListGet | Op::ListSet | Op::ListFill);
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
    let types = b.types();
    let whole = match tys.as_slice() {
        [one] => one.clone(),
        _ => super::aggregate(types, cx.lay, elem),
    };
    debug_assert_eq!(
        types.size_align(&whole).0,
        u64::from(mem_layout(&cx.lay.leaves(elem)).size)
    );
    let at = b.elem_ptr(&whole, &ptr, &idx);
    let reads = matches!(
        inst.op,
        Op::ListGet | Op::ListGetNn | Op::ListGetU | Op::ListTake
    );
    let out = inst.res.map(|r| &vals[&r.index()]);
    for (k, t) in tys.iter().enumerate() {
        let to = if tys.len() == 1 {
            at.clone()
        } else {
            b.field_ptr(&whole, &at, k)
        };
        let align = types.size_align(t).1;
        let meta = elem_meta(cx.m.types.kind(elem), k);
        if reads {
            let dst = &out.expect("list read result")[k];
            if held[k] == LTy::I1 {
                // A boolean element is a byte in memory.
                let byte = b.load_with(t, &to, align, meta);
                b.name_next(dst);
                b.trunc(&byte, LTy::I1);
            } else {
                b.name_next(dst);
                b.load_with(t, &to, align, meta);
            }
        } else {
            let v = vals[&inst.args[2].index()][k].clone();
            let v = if v.ty == LTy::I1 {
                b.zext(&v, LTy::I8)
            } else {
                v
            };
            b.store_with(&v, &to, align, meta);
        }
    }
}

/// What LLVM may assume about leaf `k` of a list element of kind `elem`. A buffer holds one
/// element type, so a scalar element never lies where a list or string header does; only element
/// accesses are tagged, since a record field or inner header is also read through borrowed
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

/// `StrByte` and `StrAsciiAt`: the byte at an index of a string. An inline string keeps its
/// bytes in its two words, little-endian, so the byte is a shift and mask; any other string loads
/// it from memory. `StrAsciiAt` yields -1 unless the string is flagged ASCII and the index is in
/// range, and the caller then takes the general path.
fn str_byte(cx: &mut Cx, inst: &Inst, vals: &Vals, b: &mut FnBuilder) {
    use ms_rt_abi::STR_LEN_MASK;
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
        let flag = b.bin(Bin::LShr, &s[1], &Val::int(61));
        let flag = b.bin(Bin::And, &flag, &Val::int(3));
        let ascii = b.icmp("eq", &flag, &Val::int(1));
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
    let tag = b.bin(Bin::LShr, &s[1], &Val::int(62));
    let inline = b.icmp("eq", &tag, &Val::int(1));
    let word = format!("w{bb}_{split}");
    b.cond_br(&inline, &word, &load);
    b.label(&word);
    let high = b.icmp("sge", &i, &Val::int(8));
    let w = b.select(&high, &s[1], &s[0]);
    let shift = b.bin(Bin::And, &i, &Val::int(7));
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
    let words: Vec<Val> = args
        .iter()
        .map(|a| {
            if a.ty == LTy::Ptr {
                b.ptr_to_int(a)
            } else {
                a.clone()
            }
        })
        .collect();
    let actuals: Vec<(Val, &str)> = words.iter().map(|a| (a.clone(), "")).collect();
    if let Some(d) = dst {
        b.name_next(d);
    }
    b.call(&LTy::Ptr, "noalias align 16 ", name, &actuals)
        .expect("a pointer")
}

/// Stores the leaves `vs` of one element at index `idx` of the list block at `ptr`.
fn store_elem(cx: &Cx, b: &mut FnBuilder, list: Ty, ptr: &Val, idx: &Val, vs: &[Val]) {
    let elem = cx.m.seq_elem(list).expect("a list");
    let tys = mem_leaves(cx.lay, elem);
    let whole = match tys.as_slice() {
        [one] => one.clone(),
        _ => super::aggregate(b.types(), cx.lay, elem),
    };
    let at = b.elem_ptr(&whole, ptr, idx);
    for (k, (t, v)) in tys.iter().zip(vs).enumerate() {
        let to = if tys.len() == 1 {
            at.clone()
        } else {
            b.field_ptr(&whole, &at, k)
        };
        let v = if v.ty == LTy::I1 {
            b.zext(v, LTy::I8)
        } else {
            v.clone()
        };
        let align = b.types().size_align(t).1;
        b.store_with(&v, &to, align, elem_meta(cx.m.types.kind(elem), k));
    }
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

/// `ListDropLast` and `ListRelease` for elements that need no drop (`list.droplast 1` follows a
/// `list.take` of that element, so it drops nothing either).
fn release_ok(m: &Module, f: &Func, i: &Inst) -> bool {
    let Some(e) = m.seq_elem(f.ty(i.args[0])) else {
        return false;
    };
    !m.needs_drop(e) || (i.op == Op::ListDropLast && i.imm == Imm::Int(1))
}

/// `ListRelease`: free the block of an owned list (`cap != 0`; a view owns nothing) that has
/// one. No element needs a drop, so only the block goes.
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
    super::rt::declare(cx, "msrt_free");
    let word = b.ptr_to_int(&l[0]);
    b.call(&LTy::Void, "", "msrt_free", &[(word, "")]);
    b.br(&join);
    b.label(&join);
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

/// Whether an element is made of plain `i64`, `double` and `i8` leaves, which sit in memory
/// exactly as in registers, and is held as those leaves (a record held behind one pointer is not).
fn plain_elem(lay: &Layouts, e: Ty) -> bool {
    !super::records::is_mem(lay, e)
        && lay
            .leaves(e)
            .iter()
            .all(|l| matches!(l, Leaf::I64 | Leaf::F64 | Leaf::I8))
}
