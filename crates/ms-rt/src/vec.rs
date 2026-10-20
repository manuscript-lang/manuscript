//! `List[T]`, `Bytes`, `StringBuilder` and the builders: owned header-less `VecVal` values.
//!
//! Every operation takes a pointer to the receiver value and the element
//! descriptor. Mutators change the receiver in place and return nothing;
//! element arguments of stores are consumed (ownership moves into the list).
use crate::alloc;
use crate::desc::{self, is_plain, needs_no_drop, slot_copy, slot_drop, slot_eq, slot_hash};
use crate::fault;
use crate::string::{self, from_bytes};
use ms_rt_abi::*;

/// Limit on native list sizes (as the Go runtime).
pub const MAX_ITEMS: usize = 1 << 28;

const EMPTY: VecVal = VecVal {
    ptr: core::ptr::null_mut(),
    len: 0,
    cap: 0,
};

#[inline(always)]
unsafe fn elem(v: &VecVal, d: &TypeDesc, i: usize) -> *mut u8 {
    // SAFETY: `i < len` by the callers.
    unsafe { v.ptr.add(i * d.size as usize) }
}

/// Ensures room for `extra` more elements.
unsafe fn reserve(v: &mut VecVal, d: &TypeDesc, extra: usize) {
    let need = v
        .len
        .checked_add(extra)
        .unwrap_or_else(|| fault::fault(b"list size overflow"));
    if need <= v.cap {
        return;
    }
    let size = d.size as usize;
    let mut cap = if v.cap == 0 { 4 } else { v.cap * 2 };
    if cap < need {
        cap = need;
    }
    let bytes = cap
        .checked_mul(size.max(1))
        .unwrap_or_else(|| fault::fault(b"list size overflow"));
    // SAFETY: standard growth of an owned buffer.
    unsafe {
        v.ptr = if v.ptr.is_null() {
            alloc::alloc(bytes)
        } else {
            alloc::realloc(v.ptr, bytes)
        };
    }
    v.cap = cap;
}

/// Drops the elements and the buffer of a list.
///
/// # Safety
/// `v` is a live list of `d`.
pub unsafe fn drop_list(v: *mut VecVal, d: &TypeDesc) {
    // SAFETY: caller contract.
    unsafe {
        let v = &mut *v;
        if v.ptr.is_null() {
            return;
        }
        if !needs_no_drop(d) {
            for i in 0..v.len {
                slot_drop(d, elem(v, d, i));
            }
        }
        alloc::free(v.ptr);
        *v = EMPTY;
    }
}

/// Deep copy of a list into `out`.
///
/// # Safety
/// `src` is a live list of `d`; `out` is uninitialised.
pub unsafe fn copy_list(src: *const VecVal, d: &TypeDesc, out: *mut VecVal) {
    // SAFETY: caller contract.
    unsafe {
        let s = &*src;
        if s.len == 0 {
            *out = EMPTY;
            return;
        }
        let size = d.size as usize;
        let p = alloc::alloc(s.len * size.max(1));
        if is_plain(d) {
            core::ptr::copy_nonoverlapping(s.ptr, p, s.len * size);
        } else {
            for i in 0..s.len {
                slot_copy(d, elem(s, d, i), p.add(i * size));
            }
        }
        *out = VecVal {
            ptr: p,
            len: s.len,
            cap: s.len,
        };
    }
}

/// Duplicates a byte buffer into `out`.
///
/// # Safety
/// `src` is live bytes; `out` is uninitialised.
pub unsafe fn copy_bytes(src: *const VecVal, out: *mut VecVal) {
    // SAFETY: caller contract.
    unsafe {
        let s = &*src;
        if s.len == 0 {
            *out = EMPTY;
            return;
        }
        let p = alloc::alloc(s.len);
        core::ptr::copy_nonoverlapping(s.ptr, p, s.len);
        *out = VecVal {
            ptr: p,
            len: s.len,
            cap: s.len,
        };
    }
}

/// Element-wise equality.
///
/// # Safety
/// Both are live lists of `d`.
pub unsafe fn eq_list(a: *const VecVal, b: *const VecVal, d: &TypeDesc) -> bool {
    // SAFETY: caller contract.
    unsafe {
        let (x, y) = (&*a, &*b);
        if x.len != y.len {
            return false;
        }
        for i in 0..x.len {
            if !slot_eq(d, elem(x, d, i), elem(y, d, i)) {
                return false;
            }
        }
        true
    }
}

/// Moves `elem` (a slot of `d.size` bytes) onto the end.
unsafe fn push(v: &mut VecVal, d: &TypeDesc, e: *const u8) {
    // SAFETY: the list owns `size`-byte slots; `e` is a distinct slot.
    unsafe {
        if v.len == v.cap {
            reserve(v, d, 1);
        }
        core::ptr::copy_nonoverlapping(e, elem(v, d, v.len), d.size as usize);
        v.len += 1;
    }
}

fn relative(len: usize, index: i64) -> i64 {
    if index < 0 { len as i64 + index } else { index }
}

// ---- construction and lifetime ----

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_new(out: *mut VecVal) {
    // SAFETY: `out` is writable.
    unsafe { *out = EMPTY }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_with_capacity(
    d: *const TypeDesc,
    cap: i64,
    out: *mut VecVal,
) {
    // SAFETY: caller contract.
    unsafe {
        let mut v = EMPTY;
        if cap > 0 {
            reserve(&mut v, &*d, cap as usize);
        }
        *out = v;
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_drop(v: *mut VecVal, d: *const TypeDesc) {
    // SAFETY: caller contract.
    unsafe { drop_list(v, &*d) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_copy(
    v: *const VecVal,
    d: *const TypeDesc,
    out: *mut VecVal,
) {
    // SAFETY: caller contract.
    unsafe { copy_list(v, &*d, out) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_push(v: *mut VecVal, d: *const TypeDesc, e: *const u8) {
    // SAFETY: caller contract.
    unsafe { push(&mut *v, &*d, e) }
}

/// Grows capacity for at least `extra` more elements.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_reserve(v: *mut VecVal, d: *const TypeDesc, extra: i64) {
    // SAFETY: caller contract.
    unsafe { reserve(&mut *v, &*d, extra.max(0) as usize) }
}

// ---- reads ----

/// Borrowed pointer to the element at a possibly negative index; `default` (borrowed, may be null)
/// is returned when out of range.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_at(
    v: *const VecVal,
    d: *const TypeDesc,
    index: i64,
    default: *const u8,
) -> *const u8 {
    // SAFETY: caller contract.
    unsafe {
        let v = &*v;
        let i = relative(v.len, index);
        if i >= 0 && (i as usize) < v.len {
            return elem(v, &*d, i as usize);
        }
        if default.is_null() {
            fault::msrt_index_fault(index, v.len as i64);
        }
        default
    }
}

/// `get`: copies the element (or the default) into `out`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_get(
    v: *const VecVal,
    d: *const TypeDesc,
    index: i64,
    default: *const u8,
    out: *mut u8,
) {
    // SAFETY: caller contract.
    unsafe {
        let p = msrt_list_at(v, d, index, default);
        slot_copy(&*d, p, out);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_first(
    v: *const VecVal,
    d: *const TypeDesc,
    out: *mut u8,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        if (*v).len == 0 {
            return 0;
        }
        slot_copy(&*d, (*v).ptr, out);
        1
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_last(
    v: *const VecVal,
    d: *const TypeDesc,
    out: *mut u8,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let v = &*v;
        if v.len == 0 {
            return 0;
        }
        slot_copy(&*d, elem(v, &*d, v.len - 1), out);
        1
    }
}

/// `index_of`: present flag; index through `out`. `probe` is borrowed.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_index_of(
    v: *const VecVal,
    d: *const TypeDesc,
    probe: *const u8,
    out: *mut i64,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let (v, d) = (&*v, &*d);
        for i in 0..v.len {
            if slot_eq(d, elem(v, d, i), probe) {
                *out = i as i64;
                return 1;
            }
        }
        0
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_last_index_of(
    v: *const VecVal,
    d: *const TypeDesc,
    probe: *const u8,
    out: *mut i64,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let (v, d) = (&*v, &*d);
        for i in (0..v.len).rev() {
            if slot_eq(d, elem(v, d, i), probe) {
                *out = i as i64;
                return 1;
            }
        }
        0
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_contains(
    v: *const VecVal,
    d: *const TypeDesc,
    probe: *const u8,
) -> u8 {
    let mut i = 0i64;
    // SAFETY: caller contract.
    unsafe { msrt_list_index_of(v, d, probe, &mut i) }
}

// ---- mutators ----

/// Inserts `e` (consumed) at the front.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_prepend(
    v: *mut VecVal,
    d: *const TypeDesc,
    e: *const u8,
) {
    // SAFETY: caller contract.
    unsafe { msrt_list_insert(v, d, 0, e) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_insert(
    v: *mut VecVal,
    d: *const TypeDesc,
    index: i64,
    e: *const u8,
) {
    // SAFETY: caller contract.
    unsafe {
        let (v, d) = (&mut *v, &*d);
        let n = v.len;
        let i = relative(n, index);
        if i < 0 || i > n as i64 {
            fault::fault_fmt(format_args!(
                "List.insert: index must be between {} and {} (negative indexes count from the end), found {}",
                -(n as i64),
                n,
                index
            ));
        }
        let i = i as usize;
        reserve(v, d, 1);
        let size = d.size as usize;
        core::ptr::copy(elem(v, d, i), elem(v, d, i).add(size), (n - i) * size);
        core::ptr::copy_nonoverlapping(e, elem(v, d, i), size);
        v.len += 1;
    }
}

/// Removes the last element into `out`; 0 when empty.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_pop(
    v: *mut VecVal,
    d: *const TypeDesc,
    out: *mut u8,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let (v, d) = (&mut *v, &*d);
        if v.len == 0 {
            return 0;
        }
        v.len -= 1;
        core::ptr::copy_nonoverlapping(elem(v, d, v.len), out, d.size as usize);
        1
    }
}

/// Removes the first element into `out` (`Collections.shift`).
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_shift(
    v: *mut VecVal,
    d: *const TypeDesc,
    out: *mut u8,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let (v, d) = (&mut *v, &*d);
        if v.len == 0 {
            return 0;
        }
        let size = d.size as usize;
        core::ptr::copy_nonoverlapping(v.ptr, out, size);
        core::ptr::copy(v.ptr.add(size), v.ptr, (v.len - 1) * size);
        v.len -= 1;
        1
    }
}

fn index_fault(operation: &str, len: usize, index: i64) -> ! {
    if len == 0 {
        fault::fault_fmt(format_args!(
            "{operation}: index has no valid value for an empty collection, found {index}"
        ))
    }
    fault::fault_fmt(format_args!(
        "{operation}: index must be between {} and {} (negative indexes count from the end), found {index}",
        -(len as i64),
        len as i64 - 1
    ))
}

/// Replaces the element at `index` with `e` (consumed); the old element is dropped.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_set(
    v: *mut VecVal,
    d: *const TypeDesc,
    index: i64,
    e: *const u8,
) {
    // SAFETY: caller contract.
    unsafe {
        let (v, d) = (&mut *v, &*d);
        let i = relative(v.len, index);
        if i < 0 || i as usize >= v.len {
            index_fault("List.set", v.len, index);
        }
        let p = elem(v, d, i as usize);
        slot_drop(d, p);
        core::ptr::copy_nonoverlapping(e, p, d.size as usize);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_remove(v: *mut VecVal, d: *const TypeDesc, index: i64) {
    // SAFETY: caller contract.
    unsafe {
        let (v, d) = (&mut *v, &*d);
        let i = relative(v.len, index);
        if i < 0 || i as usize >= v.len {
            index_fault("List.remove", v.len, index);
        }
        let i = i as usize;
        let size = d.size as usize;
        slot_drop(d, elem(v, d, i));
        core::ptr::copy(
            elem(v, d, i).add(size),
            elem(v, d, i),
            (v.len - i - 1) * size,
        );
        v.len -= 1;
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_reverse_in_place(v: *mut VecVal, d: *const TypeDesc) {
    // SAFETY: caller contract.
    unsafe {
        let (v, d) = (&mut *v, &*d);
        let size = d.size as usize;
        let (mut i, mut j) = (0usize, v.len);
        while i + 1 < j {
            j -= 1;
            core::ptr::swap_nonoverlapping(elem(v, d, i), elem(v, d, j), size);
            i += 1;
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_reversed(
    v: *const VecVal,
    d: *const TypeDesc,
    out: *mut VecVal,
) {
    // SAFETY: caller contract.
    unsafe {
        copy_list(v, &*d, out);
        msrt_list_reverse_in_place(out, d);
    }
}

/// `splice(start, delete_count, replacement)`; `replacement` is consumed (its buffer is freed).
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_splice(
    v: *mut VecVal,
    d: *const TypeDesc,
    start: i64,
    count: i64,
    replacement: *mut VecVal,
) {
    // SAFETY: caller contract.
    unsafe {
        let (v, d) = (&mut *v, &*d);
        let n = v.len;
        let range_fault = |p: &str, val: i64, lo: i64, hi: i64| -> ! {
            fault::fault_fmt(format_args!(
                "List.splice: {p} must be between {lo} and {hi}, found {val}"
            ))
        };
        if start < 0 || start as usize > n {
            range_fault("start", start, 0, n as i64);
        }
        let s = start as usize;
        if count < 0 || count as usize > n - s {
            range_fault("delete_count", count, 0, (n - s) as i64);
        }
        let c = count as usize;
        let r = &mut *replacement;
        let size = d.size as usize;
        for i in s..s + c {
            slot_drop(d, elem(v, d, i));
        }
        let new_len = n - c + r.len;
        if new_len > v.cap {
            reserve(v, d, new_len - n.min(new_len));
        }
        core::ptr::copy(elem(v, d, s + c), elem(v, d, s + r.len), (n - s - c) * size);
        if r.len > 0 {
            core::ptr::copy_nonoverlapping(r.ptr, elem(v, d, s), r.len * size);
        }
        v.len = new_len;
        if !r.ptr.is_null() {
            alloc::free(r.ptr);
        }
        *r = EMPTY;
    }
}

fn check_slice(op: &str, len: usize, start: i64, end: i64) {
    if start < 0 || end < start || end > len as i64 {
        fault::fault_fmt(format_args!(
            "{op}: start/end must satisfy 0 <= start <= end <= {len}; found start {start} and end {end}"
        ));
    }
}

/// `fill(value, start, end)`; `value` is borrowed and copied into each slot.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_fill(
    v: *mut VecVal,
    d: *const TypeDesc,
    value: *const u8,
    start: i64,
    end: i64,
) {
    // SAFETY: caller contract.
    unsafe {
        let (v, d) = (&mut *v, &*d);
        check_slice("List.fill", v.len, start, end);
        for i in start as usize..end as usize {
            let p = elem(v, d, i);
            slot_drop(d, p);
            slot_copy(d, value, p);
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_copy_within(
    v: *mut VecVal,
    d: *const TypeDesc,
    target: i64,
    start: i64,
    end: i64,
) {
    // SAFETY: caller contract.
    unsafe {
        let (v, d) = (&mut *v, &*d);
        let n = v.len;
        check_slice("List.copy_within", n, start, end);
        if target < 0 || target as usize > n {
            fault::fault_fmt(format_args!(
                "List.copy_within: target must be between 0 and {n}, found {target}"
            ));
        }
        if start == end || target as usize == n {
            return;
        }
        let count = ((end - start) as usize).min(n - target as usize);
        // Overwritten slots are dropped, the sources copied (overlap safe via a temporary).
        let mut tmp = EMPTY;
        let src = VecVal {
            ptr: elem(v, d, start as usize),
            len: count,
            cap: count,
        };
        copy_list(&src, d, &mut tmp);
        for k in 0..count {
            slot_drop(d, elem(v, d, target as usize + k));
        }
        core::ptr::copy_nonoverlapping(
            tmp.ptr,
            elem(v, d, target as usize),
            count * d.size as usize,
        );
        if !tmp.ptr.is_null() {
            alloc::free(tmp.ptr);
        }
    }
}

// ---- derived lists ----

/// `slice(start, end)`: status protocol.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_slice(
    v: *const VecVal,
    d: *const TypeDesc,
    start: i64,
    end: i64,
    out: *mut VecVal,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let n = (*v).len;
        let (s, e) = (relative(n, start), relative(n, end));
        if s < 0 || e < s || e > n as i64 {
            return STATUS_OUT_OF_RANGE;
        }
        let view = VecVal {
            ptr: elem(&*v, &*d, s as usize),
            len: (e - s) as usize,
            cap: (e - s) as usize,
        };
        copy_list(&view, &*d, out);
        STATUS_OK
    }
}

fn take_count(name: &str, count: i64, len: usize) -> usize {
    if count < 0 {
        fault::fault_fmt(format_args!(
            "List.{name}: count must be nonnegative, found {count}"
        ));
    }
    (count as usize).min(len)
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_take(
    v: *const VecVal,
    d: *const TypeDesc,
    count: i64,
    out: *mut VecVal,
) {
    // SAFETY: caller contract.
    unsafe {
        let n = take_count("take", count, (*v).len);
        let view = VecVal {
            ptr: (*v).ptr,
            len: n,
            cap: n,
        };
        copy_list(&view, &*d, out);
    }
}

/// `drop(count)` (named `drop_n` because `msrt_list_drop` releases a value).
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_drop_n(
    v: *const VecVal,
    d: *const TypeDesc,
    count: i64,
    out: *mut VecVal,
) {
    // SAFETY: caller contract.
    unsafe {
        let n = take_count("drop", count, (*v).len);
        let view = VecVal {
            ptr: if (*v).len == n {
                core::ptr::null_mut()
            } else {
                elem(&*v, &*d, n)
            },
            len: (*v).len - n,
            cap: (*v).len - n,
        };
        copy_list(&view, &*d, out);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_concat(
    a: *const VecVal,
    b: *const VecVal,
    d: *const TypeDesc,
    out: *mut VecVal,
) {
    // SAFETY: caller contract.
    unsafe {
        copy_list(a, &*d, out);
        extend_copy(&mut *out, &*d, &*b);
    }
}

unsafe fn extend_copy(v: &mut VecVal, d: &TypeDesc, other: &VecVal) {
    // SAFETY: `other` is a distinct live list of `d`.
    unsafe {
        reserve(v, d, other.len);
        let size = d.size as usize;
        for i in 0..other.len {
            slot_copy(d, elem(other, d, i), v.ptr.add((v.len + i) * size));
        }
        v.len += other.len;
    }
}

/// Appends the elements of `other` (consumed: its buffer is freed, elements moved).
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_extend(
    v: *mut VecVal,
    d: *const TypeDesc,
    other: *mut VecVal,
) {
    // SAFETY: caller contract.
    unsafe {
        let (v, d, o) = (&mut *v, &*d, &mut *other);
        reserve(v, d, o.len);
        if o.len > 0 {
            core::ptr::copy_nonoverlapping(o.ptr, elem(v, d, v.len), o.len * d.size as usize);
            v.len += o.len;
        }
        if !o.ptr.is_null() {
            alloc::free(o.ptr);
        }
        *o = EMPTY;
    }
}

/// `Collections.flatten`: `lists` is a list of `List[T]`, `d` describes `T`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_flatten(
    lists: *const VecVal,
    d: *const TypeDesc,
    out: *mut VecVal,
) {
    // SAFETY: caller contract.
    unsafe {
        let ls = &*lists;
        let mut res = EMPTY;
        let total: usize = (0..ls.len)
            .map(|i| (*(ls.ptr as *const VecVal).add(i)).len)
            .sum();
        reserve(&mut res, &*d, total);
        for i in 0..ls.len {
            extend_copy(&mut res, &*d, &*(ls.ptr as *const VecVal).add(i));
        }
        *out = res;
    }
}

/// `distinct`: keeps the first of equal elements.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_distinct(
    v: *const VecVal,
    d: *const TypeDesc,
    out: *mut VecVal,
) {
    // SAFETY: caller contract.
    unsafe {
        let (src, d) = (&*v, &*d);
        let mut res = EMPTY;
        if desc::hashable(d) && src.len > 16 {
            let mut seen = crate::map::empty();
            for i in 0..src.len {
                let p = elem(src, d, i);
                if crate::map::contains_key(&seen, d, None, p) {
                    continue;
                }
                crate::map::msrt_set_add_copy(&mut seen, d, p);
                reserve(&mut res, d, 1);
                slot_copy(d, p, elem(&res, d, res.len));
                res.len += 1;
            }
            crate::map::drop_map(&mut seen, d, None);
        } else {
            for i in 0..src.len {
                let p = elem(src, d, i);
                let dup = (0..res.len).any(|j| slot_eq(d, elem(&res, d, j), p));
                if !dup {
                    reserve(&mut res, d, 1);
                    slot_copy(d, p, elem(&res, d, res.len));
                    res.len += 1;
                }
            }
        }
        *out = res;
    }
}

/// `keys()`: `[0, 1, ..., len-1]`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_keys(v: *const VecVal, out: *mut VecVal) {
    // SAFETY: caller contract.
    unsafe {
        let n = (*v).len;
        let p = if n == 0 {
            core::ptr::null_mut()
        } else {
            alloc::alloc(n * 8)
        } as *mut i64;
        for i in 0..n {
            *p.add(i) = i as i64;
        }
        *out = VecVal {
            ptr: p as *mut u8,
            len: n,
            cap: n,
        };
    }
}

/// `join` on `List[String]`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_join(
    v: *const VecVal,
    sep: *const StrObj,
    out: *mut *mut StrObj,
) {
    // SAFETY: caller contract.
    unsafe {
        let v = &*v;
        let sepb = string::bytes(sep);
        let mut b = Vec::new();
        for i in 0..v.len {
            if i > 0 {
                b.extend_from_slice(sepb);
            }
            b.extend_from_slice(string::bytes(*(v.ptr as *const *const StrObj).add(i)));
        }
        *out = string::from_buf(b);
    }
}

// ---- sorting ----

/// Comparator thunk: `env` is the closure, `a` and `b` point at element slots.
pub type CmpFn = unsafe extern "C-unwind" fn(env: *mut u8, a: *const u8, b: *const u8) -> i64;

unsafe fn merge_sort(
    items: *mut u8,
    buf: *mut u8,
    n: usize,
    size: usize,
    cmp: CmpFn,
    env: *mut u8,
) {
    // SAFETY: `items` and `buf` hold `n` slots each.
    unsafe {
        let at = |base: *mut u8, i: usize| base.add(i * size);
        if n <= 12 {
            // Stable insertion sort of slots.
            for i in 1..n {
                let mut j = i;
                while j > 0 && cmp(env, at(items, j), at(items, j - 1)) < 0 {
                    core::ptr::swap_nonoverlapping(at(items, j), at(items, j - 1), size);
                    j -= 1;
                }
            }
            return;
        }
        let mid = n / 2;
        merge_sort(items, buf, mid, size, cmp, env);
        merge_sort(at(items, mid), at(buf, mid), n - mid, size, cmp, env);
        if cmp(env, at(items, mid), at(items, mid - 1)) >= 0 {
            return;
        }
        core::ptr::copy_nonoverlapping(items, buf, mid * size);
        let (mut li, mut ri, mut out) = (0usize, mid, 0usize);
        while li < mid && ri < n {
            if cmp(env, at(items, ri), at(buf, li)) < 0 {
                core::ptr::copy(at(items, ri), at(items, out), size);
                ri += 1;
            } else {
                core::ptr::copy_nonoverlapping(at(buf, li), at(items, out), size);
                li += 1;
            }
            out += 1;
        }
        if li < mid {
            core::ptr::copy_nonoverlapping(at(buf, li), at(items, out), (mid - li) * size);
        }
    }
}

/// Stable sort in place by a three-way comparator thunk (`< 0` means before).
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_sort_in_place(
    v: *mut VecVal,
    d: *const TypeDesc,
    cmp: CmpFn,
    env: *mut u8,
) {
    // SAFETY: caller contract.
    unsafe {
        let (v, d) = (&mut *v, &*d);
        if v.len < 2 {
            return;
        }
        let size = d.size as usize;
        let buf = alloc::alloc(v.len * size.max(1));
        merge_sort(v.ptr, buf, v.len, size, cmp, env);
        alloc::free(buf);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_sorted(
    v: *const VecVal,
    d: *const TypeDesc,
    cmp: CmpFn,
    env: *mut u8,
    out: *mut VecVal,
) {
    // SAFETY: caller contract.
    unsafe {
        copy_list(v, &*d, out);
        msrt_list_sort_in_place(out, d, cmp, env);
    }
}

// ---- generators ----

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_filled(
    value: *const u8,
    d: *const TypeDesc,
    count: i64,
    has_max: u8,
    max: i64,
    out: *mut VecVal,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let limit = if has_max != 0 { max } else { i64::MAX };
        if count < 0 || limit < 0 {
            return STATUS_INVALID_INPUT;
        }
        if count as u64 > (limit as u64).min(MAX_ITEMS as u64) {
            return STATUS_LIMIT_EXCEEDED;
        }
        let d = &*d;
        let mut v = EMPTY;
        reserve(&mut v, d, count as usize);
        for i in 0..count as usize {
            slot_copy(d, value, v.ptr.add(i * d.size as usize));
        }
        v.len = count as usize;
        *out = v;
        STATUS_OK
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_range(start: i64, end: i64, out: *mut VecVal) {
    // SAFETY: caller contract.
    unsafe {
        if end <= start {
            *out = EMPTY;
            return;
        }
        let n = (end as i128 - start as i128) as u128;
        if n > MAX_ITEMS as u128 {
            fault::fault(b"range: more than 268435456 items; iterate with 'for index in range(start, end)' directly or bound the list with range_by(max_items:)");
        }
        let n = n as usize;
        let p = alloc::alloc(n * 8) as *mut i64;
        for i in 0..n {
            *p.add(i) = start + i as i64;
        }
        *out = VecVal {
            ptr: p as *mut u8,
            len: n,
            cap: n,
        };
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_range_by(
    start: i64,
    end: i64,
    step: i64,
    has_max: u8,
    max: i64,
    out: *mut VecVal,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let limit = if has_max != 0 { max } else { i64::MAX };
        if step == 0 || limit < 0 {
            return STATUS_INVALID_INPUT;
        }
        let limit = (limit as u64).min(MAX_ITEMS as u64);
        let (span, size) = if step > 0 && start < end {
            ((end as i128 - start as i128) as u128, step as u128)
        } else if step < 0 && start > end {
            (
                (start as i128 - end as i128) as u128,
                (-(step as i128)) as u128,
            )
        } else {
            (0, 1)
        };
        if span == 0 {
            *out = EMPTY;
            return STATUS_OK;
        }
        let count = (span - 1) / size + 1;
        if count > limit as u128 {
            return STATUS_LIMIT_EXCEEDED;
        }
        let count = count as usize;
        let p = alloc::alloc(count * 8) as *mut i64;
        let mut n = start;
        for i in 0..count {
            *p.add(i) = n;
            if i + 1 < count {
                n = n.wrapping_add(step);
            }
        }
        *out = VecVal {
            ptr: p as *mut u8,
            len: count,
            cap: count,
        };
        STATUS_OK
    }
}

/// `to_set`: builds a set value from a list's elements (copies).
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_to_set(
    v: *const VecVal,
    d: *const TypeDesc,
    out: *mut MapVal,
) {
    // SAFETY: caller contract.
    unsafe {
        let (v, d) = (&*v, &*d);
        let mut m = crate::map::empty();
        for i in 0..v.len {
            crate::map::msrt_set_add_copy(&mut m, d, elem(v, d, i));
        }
        *out = m;
    }
}

/// Destructuring length mismatch fault.
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_fault_destructure(names: i64, elements: i64) -> ! {
    fault::fault_fmt(format_args!(
        "destructuring length mismatch; the pattern binds {names} names but the list has {elements} elements"
    ))
}

// ---- Bytes ----

unsafe fn bslice<'a>(b: *const VecVal) -> &'a [u8] {
    // SAFETY: caller contract.
    unsafe {
        let b = &*b;
        if b.len == 0 {
            &[]
        } else {
            core::slice::from_raw_parts(b.ptr, b.len)
        }
    }
}

unsafe fn bytes_from(data: &[u8], out: *mut VecVal) {
    // SAFETY: `out` is writable.
    unsafe {
        if data.is_empty() {
            *out = EMPTY;
            return;
        }
        let p = alloc::alloc(data.len());
        core::ptr::copy_nonoverlapping(data.as_ptr(), p, data.len());
        *out = VecVal {
            ptr: p,
            len: data.len(),
            cap: data.len(),
        };
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_bytes_drop(b: *mut VecVal) {
    // SAFETY: caller contract.
    unsafe {
        if !(*b).ptr.is_null() {
            alloc::free((*b).ptr);
        }
        *b = EMPTY;
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_bytes_copy(b: *const VecVal, out: *mut VecVal) {
    // SAFETY: caller contract.
    unsafe { copy_bytes(b, out) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_bytes_contains(b: *const VecVal, v: *const VecVal) -> u8 {
    // SAFETY: caller contract.
    unsafe { string::find(bslice(b), bslice(v)).is_some() as u8 }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_bytes_index_of(
    b: *const VecVal,
    v: *const VecVal,
    out: *mut i64,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        match string::find(bslice(b), bslice(v)) {
            Some(i) => {
                *out = i as i64;
                1
            }
            None => 0,
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_bytes_last_index_of(
    b: *const VecVal,
    v: *const VecVal,
    out: *mut i64,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        match string::rfind(bslice(b), bslice(v)) {
            Some(i) => {
                *out = i as i64;
                1
            }
            None => 0,
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_bytes_starts_with(b: *const VecVal, v: *const VecVal) -> u8 {
    // SAFETY: caller contract.
    unsafe { bslice(b).starts_with(bslice(v)) as u8 }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_bytes_ends_with(b: *const VecVal, v: *const VecVal) -> u8 {
    // SAFETY: caller contract.
    unsafe { bslice(b).ends_with(bslice(v)) as u8 }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_bytes_get(
    b: *const VecVal,
    index: i64,
    has_default: u8,
    default: i64,
) -> i64 {
    // SAFETY: caller contract.
    unsafe {
        let s = bslice(b);
        let i = relative(s.len(), index);
        if i >= 0 && (i as usize) < s.len() {
            return s[i as usize] as i64;
        }
        if has_default == 0 {
            fault::msrt_index_fault(index, s.len() as i64);
        }
        default
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_bytes_slice(
    b: *const VecVal,
    start: i64,
    end: i64,
    out: *mut VecVal,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let s = bslice(b);
        let (a, e) = (relative(s.len(), start), relative(s.len(), end));
        if a < 0 || e < a || e > s.len() as i64 {
            return STATUS_OUT_OF_RANGE;
        }
        bytes_from(&s[a as usize..e as usize], out);
        STATUS_OK
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_bytes_reversed(b: *const VecVal, out: *mut VecVal) {
    // SAFETY: caller contract.
    unsafe {
        copy_bytes(b, out);
        if (*out).len > 0 {
            core::slice::from_raw_parts_mut((*out).ptr, (*out).len).reverse();
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_bytes_with_value(
    b: *const VecVal,
    index: i64,
    value: i64,
    out: *mut VecVal,
) {
    // SAFETY: caller contract.
    unsafe {
        let n = (*b).len;
        let i = relative(n, index);
        if i < 0 || i as usize >= n {
            index_fault("Bytes.with_value", n, index);
        }
        if !(0..=255).contains(&value) {
            fault::fault_fmt(format_args!(
                "Bytes.with_value: value must be between 0 and 255, found {value}"
            ));
        }
        copy_bytes(b, out);
        *(*out).ptr.add(i as usize) = value as u8;
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_bytes_concat(
    a: *const VecVal,
    b: *const VecVal,
    out: *mut VecVal,
) {
    // SAFETY: caller contract.
    unsafe {
        let (x, y) = (bslice(a), bslice(b));
        let mut buf = Vec::with_capacity(x.len() + y.len());
        buf.extend_from_slice(x);
        buf.extend_from_slice(y);
        bytes_from(buf.as_slice(), out);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_bytes_split(
    b: *const VecVal,
    sep: *const VecVal,
    has_max: u8,
    max: i64,
    out: *mut VecVal,
) {
    // SAFETY: caller contract; result is a List[Bytes] (24-byte slots).
    unsafe {
        let (data, sepb) = (bslice(b), bslice(sep));
        let limit = if has_max != 0 {
            if max < 0 {
                fault::fault_fmt(format_args!(
                    "split: max_parts must be nonnegative, found {max}"
                ));
            }
            max as usize
        } else {
            usize::MAX
        };
        let d = &desc::msrt_desc_bytes;
        let mut res = EMPTY;
        let add = |part: &[u8], res: &mut VecVal| {
            let mut item = EMPTY;
            bytes_from(part, &mut item);
            push(res, d, &item as *const VecVal as *const u8);
        };
        if sepb.is_empty() {
            let mut i = 0;
            while i < data.len() && res.len < limit {
                add(&data[i..i + 1], &mut res);
                i += 1;
            }
        } else {
            let mut start = 0;
            while res.len < limit {
                match string::find(&data[start..], sepb) {
                    None => {
                        add(&data[start..], &mut res);
                        break;
                    }
                    Some(p) => {
                        add(&data[start..start + p], &mut res);
                        start += p + sepb.len();
                    }
                }
            }
        }
        *out = res;
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_bytes_values(b: *const VecVal, out: *mut VecVal) {
    // SAFETY: caller contract.
    unsafe {
        let s = bslice(b);
        let p = if s.is_empty() {
            core::ptr::null_mut()
        } else {
            alloc::alloc(s.len() * 8)
        } as *mut i64;
        for (i, &x) in s.iter().enumerate() {
            *p.add(i) = x as i64;
        }
        *out = VecVal {
            ptr: p as *mut u8,
            len: s.len(),
            cap: s.len(),
        };
    }
}

/// `Bytes(values)`: each element must be 0..=255.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_bytes_from_values(values: *const VecVal, out: *mut VecVal) {
    // SAFETY: caller contract.
    unsafe {
        let v = &*values;
        let mut buf = Vec::with_capacity(v.len);
        for i in 0..v.len {
            let x = *(v.ptr as *const i64).add(i);
            if !(0..=255).contains(&x) {
                fault::fault_fmt(format_args!(
                    "Bytes: values[{i}] must be between 0 and 255, found {x}"
                ));
            }
            buf.push(x as u8);
        }
        bytes_from(buf.as_slice(), out);
    }
}

/// `decode_utf8`: nullable owned string, null when invalid.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_bytes_decode_utf8(b: *const VecVal) -> *mut StrObj {
    // SAFETY: caller contract.
    unsafe {
        let s = bslice(b);
        if core::str::from_utf8(s).is_err() {
            return core::ptr::null_mut();
        }
        from_bytes(s)
    }
}

/// `BytesBuilder.append(value)`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_bytes_append(b: *mut VecVal, value: i64) {
    // SAFETY: caller contract.
    unsafe {
        if !(0..=255).contains(&value) {
            fault::fault_fmt(format_args!(
                "BytesBuilder.append: value must be between 0 and 255, found {value}"
            ));
        }
        let byte_desc = &desc::msrt_desc_bool;
        let x = value as u8;
        push(&mut *b, byte_desc, &x);
    }
}

/// `BytesBuilder.concat(values)`: borrowed `values`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_bytes_extend(b: *mut VecVal, values: *const VecVal) {
    // SAFETY: caller contract.
    unsafe {
        let data = bslice(values);
        let v = &mut *b;
        reserve(v, &desc::msrt_desc_bool, data.len());
        if !data.is_empty() {
            core::ptr::copy_nonoverlapping(data.as_ptr(), v.ptr.add(v.len), data.len());
        }
        v.len += data.len();
    }
}

// ---- StringBuilder (bytes) ----

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_strbuilder_append(b: *mut VecVal, s: *const StrObj) {
    // SAFETY: caller contract.
    unsafe {
        let data = string::bytes(s);
        let v = &mut *b;
        reserve(v, &desc::msrt_desc_bool, data.len());
        if !data.is_empty() {
            core::ptr::copy_nonoverlapping(data.as_ptr(), v.ptr.add(v.len), data.len());
        }
        v.len += data.len();
    }
}

/// Builds the string and consumes the builder (its buffer is freed).
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_strbuilder_freeze(b: *mut VecVal) -> *mut StrObj {
    // SAFETY: caller contract.
    unsafe {
        let s = from_bytes(bslice(b));
        msrt_bytes_drop(b);
        s
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_strbuilder_drop(b: *mut VecVal) {
    // SAFETY: caller contract.
    unsafe { msrt_bytes_drop(b) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_hash_list(v: *const VecVal, d: *const TypeDesc) -> i64 {
    // SAFETY: caller contract.
    unsafe {
        let (v, d) = (&*v, &*d);
        let mut h = v.len as u64;
        for i in 0..v.len {
            h = string::mix(h.rotate_left(5) ^ slot_hash(d, elem(v, d, i)));
        }
        h as i64
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::desc::{msrt_desc_int, msrt_desc_string};
    use crate::testutil;

    unsafe fn ints(v: &VecVal) -> std::vec::Vec<i64> {
        // SAFETY: tests build int lists.
        unsafe { (0..v.len).map(|i| *(v.ptr as *const i64).add(i)).collect() }
    }

    unsafe fn push_int(v: &mut VecVal, x: i64) {
        // SAFETY: tests build int lists.
        unsafe { msrt_list_push(v, &msrt_desc_int, &x as *const i64 as *const u8) }
    }

    unsafe extern "C-unwind" fn by_value(_: *mut u8, a: *const u8, b: *const u8) -> i64 {
        // SAFETY: int slots.
        unsafe { (*(a as *const i64)).cmp(&*(b as *const i64)) as i64 }
    }

    #[test]
    fn mutators_and_reads() {
        let _g = testutil::lock();
        unsafe {
            let d = &msrt_desc_int;
            let mut v = EMPTY;
            for x in [5, 3, 9, 1] {
                push_int(&mut v, x);
            }
            let ten = 10i64;
            msrt_list_insert(&mut v, d, -1, &ten as *const i64 as *const u8);
            assert_eq!(ints(&v), [5, 3, 9, 10, 1]);
            msrt_list_remove(&mut v, d, 0);
            assert_eq!(ints(&v), [3, 9, 10, 1]);
            let mut i = 0;
            assert_eq!(
                msrt_list_index_of(&v, d, &10i64 as *const i64 as *const u8, &mut i),
                1
            );
            assert_eq!(i, 2);
            msrt_list_sort_in_place(&mut v, d, by_value, core::ptr::null_mut());
            assert_eq!(ints(&v), [1, 3, 9, 10]);
            let mut s = EMPTY;
            assert_eq!(msrt_list_slice(&v, d, 1, -1, &mut s), STATUS_OK);
            assert_eq!(ints(&s), [3, 9]);
            assert_eq!(msrt_list_slice(&v, d, 3, 1, &mut s), STATUS_OUT_OF_RANGE);
            testutil::assert_fault(
                "index 9 out of range for length 4; pass a default: get(index:, default: ...)",
                || msrt_list_at(&v, d, 9, core::ptr::null()),
            );
            testutil::assert_fault(
                "List.remove: index must be between -4 and 3 (negative indexes count from the end), found 7",
                || msrt_list_remove(&mut v, d, 7),
            );
            let mut r = EMPTY;
            msrt_list_range_by(10, 0, -3, 0, 0, &mut r);
            assert_eq!(ints(&r), [10, 7, 4, 1]);
            drop_list(&mut v, d);
            drop_list(&mut s, d);
            drop_list(&mut r, d);
        }
    }

    #[test]
    #[cfg_attr(miri, ignore = "too slow to interpret")]
    fn stable_sort_large_and_distinct() {
        let _g = testutil::lock();
        unsafe {
            let d = &msrt_desc_int;
            let mut v = EMPTY;
            for i in 0..1000i64 {
                push_int(&mut v, (i * 7919) % 101);
            }
            let mut dv = EMPTY;
            msrt_list_distinct(&v, d, &mut dv);
            assert_eq!(dv.len, 101);
            msrt_list_sort_in_place(&mut v, d, by_value, core::ptr::null_mut());
            let got = ints(&v);
            assert!(got.windows(2).all(|w| w[0] <= w[1]));
            drop_list(&mut v, d);
            drop_list(&mut dv, d);
        }
    }

    #[test]
    fn nested_lists_copy_and_equality() {
        let _g = testutil::lock();
        unsafe {
            let inner = TypeDesc {
                size: 24,
                align: 8,
                kind: KIND_LIST,
                reserved: 0,
                inner0: &msrt_desc_string,
                inner1: core::ptr::null(),
                drop: None,
                copy: None,
                eq: None,
                hash: None,
            };
            let mut outer = EMPTY;
            let mut a = EMPTY;
            let s = string::from_bytes(b"hello world");
            msrt_list_push(&mut a, &msrt_desc_string, &s as *const _ as *const u8);
            msrt_list_push(&mut outer, &inner, &a as *const _ as *const u8);
            let mut c = EMPTY;
            copy_list(&outer, &inner, &mut c);
            assert!(eq_list(&outer, &c, &inner));
            drop_list(&mut outer, &inner);
            drop_list(&mut c, &inner);
        }
    }
}
