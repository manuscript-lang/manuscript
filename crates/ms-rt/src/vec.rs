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

/// Limit on native list sizes.
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

/// Copies a borrowed range into disjoint, uninitialised slots. Plain values copy in bulk;
/// values with ownership or custom copy behaviour keep their element order.
unsafe fn copy_range(d: &TypeDesc, src: *const u8, dst: *mut u8, count: usize) {
    if count == 0 {
        return;
    }
    let size = d.size as usize;
    // SAFETY: both ranges hold `count` slots and do not overlap. Empty ranges may be null;
    // zero-sized plain slots require no memory access, but custom copy hooks still run.
    unsafe {
        if is_plain(d) {
            if size != 0 {
                core::ptr::copy_nonoverlapping(src, dst, count * size);
            }
        } else {
            for i in 0..count {
                slot_copy(d, src.add(i * size), dst.add(i * size));
            }
        }
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
        #[cfg(feature = "stats")]
        crate::string::count_copy(0, s.len * size);
        copy_range(d, s.ptr, p, s.len);
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
        if d.kind == KIND_INT && v.len > 0 {
            let items = core::slice::from_raw_parts(v.ptr as *const i64, v.len);
            return match find_int(items, *(probe as *const i64)) {
                Some(i) => {
                    *out = i as i64;
                    1
                }
                None => 0,
            };
        }
        for i in 0..v.len {
            if slot_eq(d, elem(v, d, i), probe) {
                *out = i as i64;
                return 1;
            }
        }
        0
    }
}

/// Index of the first `target` in `items`; 8 elements are compared per step so the scan vectorizes.
fn find_int(items: &[i64], target: i64) -> Option<usize> {
    let (chunks, rest) = items.as_chunks::<8>();
    let mut base = 0;
    for chunk in chunks {
        if chunk.iter().fold(false, |hit, &x| hit | (x == target)) {
            return chunk.iter().position(|&x| x == target).map(|j| base + j);
        }
        base += 8;
    }
    rest.iter().position(|&x| x == target).map(|j| base + j)
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

/// `insert` of a lent element: the list stores its own copy, and the caller keeps `e`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_insert_copy(
    v: *mut VecVal,
    d: *const TypeDesc,
    index: i64,
    e: *const u8,
) {
    // SAFETY: caller contract; the copy is a fresh slot that the insert takes over.
    unsafe {
        let mut copy = core::mem::MaybeUninit::<[u64; 8]>::uninit();
        let size = (*d).size as usize;
        let dst = if size <= 64 {
            copy.as_mut_ptr() as *mut u8
        } else {
            alloc::alloc(size)
        };
        slot_copy(&*d, e, dst);
        msrt_list_insert(v, d, index, dst);
        if size > 64 {
            alloc::free(dst);
        }
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

/// Moves the element at `index` into `out` and stores `e` (consumed) in its place; nothing is copied or dropped.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_replace(
    v: *mut VecVal,
    d: *const TypeDesc,
    index: i64,
    e: *mut u8,
    out: *mut u8,
) {
    // SAFETY: caller contract.
    unsafe {
        let (v, d) = (&mut *v, &*d);
        let i = relative(v.len, index);
        if i < 0 || i as usize >= v.len {
            index_fault("List.replace", v.len, index);
        }
        let p = elem(v, d, i as usize);
        core::ptr::copy_nonoverlapping(p, out, d.size as usize);
        core::ptr::copy_nonoverlapping(e, p, d.size as usize);
    }
}

/// Exchanges the elements at `i` and `j` in place; nothing is copied or dropped.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_swap(v: *mut VecVal, d: *const TypeDesc, i: i64, j: i64) {
    // SAFETY: caller contract.
    unsafe {
        let (v, d) = (&mut *v, &*d);
        let (a, b) = (relative(v.len, i), relative(v.len, j));
        if a < 0 || a as usize >= v.len {
            index_fault("List.swap", v.len, i);
        }
        if b < 0 || b as usize >= v.len {
            index_fault("List.swap", v.len, j);
        }
        if a != b {
            swap_slots(
                elem(v, d, a as usize),
                elem(v, d, b as usize),
                d.size as usize,
            );
        }
    }
}

/// Exchanges two distinct slots of `size` bytes, a word at a time when the size allows: a byte-wise swap of a runtime length costs tens of instructions per slot.
#[inline]
unsafe fn swap_slots(a: *mut u8, b: *mut u8, size: usize) {
    // SAFETY: caller contract; the slots are distinct, so they do not overlap.
    unsafe {
        if !size.is_multiple_of(8) {
            core::ptr::swap_nonoverlapping(a, b, size);
            return;
        }
        let (a, b) = (a as *mut u64, b as *mut u64);
        for k in 0..size / 8 {
            let t = a.add(k).read_unaligned();
            a.add(k).write_unaligned(b.add(k).read_unaligned());
            b.add(k).write_unaligned(t);
        }
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
pub unsafe extern "C-unwind" fn msrt_list_reverse(v: *mut VecVal, d: *const TypeDesc) {
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
        msrt_list_reverse(out, d);
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
        if is_plain(d) {
            if d.size != 0 {
                core::ptr::copy(
                    elem(v, d, start as usize),
                    elem(v, d, target as usize),
                    count * d.size as usize,
                );
            }
            return;
        }
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

/// `chunks(size)` and `windows(size)`: lists of copies of `size` consecutive elements, starting
/// every `step` elements. `short_last` keeps a final shorter piece (chunks); otherwise only full
/// pieces are produced (windows). `od` describes the outer list's element (a list).
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_pieces(
    v: *const VecVal,
    d: *const TypeDesc,
    od: *const TypeDesc,
    size: i64,
    step: i64,
    short_last: u8,
    out: *mut VecVal,
) {
    // SAFETY: caller contract.
    unsafe {
        if size <= 0 {
            fault::fault_fmt(format_args!(
                "List.{}: size must be positive, found {size}",
                if short_last != 0 { "chunks" } else { "windows" }
            ));
        }
        let (src, d, od) = (&*v, &*d, &*od);
        let (size, step) = (size as usize, step.max(1) as usize);
        let mut res = EMPTY;
        let mut start = 0usize;
        while start < src.len && (short_last != 0 || src.len - start >= size) {
            let n = size.min(src.len - start);
            let view = VecVal {
                ptr: elem(src, d, start),
                len: n,
                cap: n,
            };
            reserve(&mut res, od, 1);
            copy_list(&view, d, elem(&res, od, res.len) as *mut VecVal);
            res.len += 1;
            start += step;
        }
        *out = res;
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
        let (a, b, d) = (&*a, &*b, &*d);
        let len = a
            .len
            .checked_add(b.len)
            .unwrap_or_else(|| fault::fault(b"list size overflow"));
        if len == 0 {
            *out = EMPTY;
            return;
        }
        // Keep the spare capacity the previous copy-then-extend path provided, without
        // allocating A's exact buffer first and relocating it when B is appended.
        let cap = if b.len == 0 {
            a.len
        } else if a.len == 0 {
            len.max(4)
        } else {
            a.len
                .checked_mul(2)
                .unwrap_or_else(|| fault::fault(b"list size overflow"))
                .max(len)
        };
        let size = d.size as usize;
        let bytes = cap
            .checked_mul(size.max(1))
            .unwrap_or_else(|| fault::fault(b"list size overflow"));
        let ptr = alloc::alloc(bytes);
        copy_range(d, a.ptr, ptr, a.len);
        copy_range(d, b.ptr, ptr.add(a.len * size), b.len);
        *out = VecVal { ptr, len, cap };
    }
}

unsafe fn extend_copy(v: &mut VecVal, d: &TypeDesc, other: &VecVal) {
    // SAFETY: `other` is a distinct live list of `d`.
    unsafe {
        if other.len == 0 {
            return;
        }
        reserve(v, d, other.len);
        let size = d.size as usize;
        copy_range(d, other.ptr, v.ptr.add(v.len * size), other.len);
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
    sep: *const StrVal,
    out: *mut StrVal,
) {
    // SAFETY: caller contract.
    unsafe {
        let v = &*v;
        *out = string::join_strings(v.ptr as *const StrVal, v.len, string::bytes(sep));
    }
}

/// `join` on `List[Int]`: decimal text of each element.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_join_int(
    v: *const VecVal,
    sep: *const StrVal,
    out: *mut StrVal,
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
            b.extend_from_slice((*(v.ptr as *const i64).add(i)).to_string().as_bytes());
        }
        *out = string::from_buf(b);
    }
}

// ---- sorting ----

/// Comparator thunk: `env` is the closure, `a` and `b` point at element slots.
pub type CmpFn = unsafe extern "C-unwind" fn(env: *mut u8, a: *const u8, b: *const u8) -> i64;

/// [`merge_sort`] for slots that are plain machine words (`Int`, `Float`, pointers): the same
/// stable result, with typed moves instead of calls to `memcpy` and a bidirectional merge.
unsafe fn merge_sort_word<T: Copy>(items: *mut T, buf: *mut T, n: usize, cmp: CmpFn, env: *mut u8) {
    // SAFETY: `items` and `buf` hold `n` slots each.
    unsafe {
        let less = |a: *const T, b: *const T| cmp(env, a as *const u8, b as *const u8) < 0;
        if n <= 12 {
            for i in 1..n {
                let x = *items.add(i);
                let mut j = i;
                while j > 0 && less(&x, items.add(j - 1)) {
                    *items.add(j) = *items.add(j - 1);
                    j -= 1;
                }
                *items.add(j) = x;
            }
            return;
        }
        let mid = n / 2;
        merge_sort_word(items, buf, mid, cmp, env);
        merge_sort_word(items.add(mid), buf.add(mid), n - mid, cmp, env);
        if !less(items.add(mid), items.add(mid - 1)) {
            return;
        }
        // Merge from both ends at once: two independent chains hide the load-to-compare
        // latency that limits a single merge. Every element is consumed exactly once whatever
        // the comparator answers, because each step only takes from a cursor range that is
        // still non-empty; a comparator that is not a total order just gives a poor order.
        core::ptr::copy_nonoverlapping(items, buf, n);
        let (mut l, mut le, mut r, mut re) = (0usize, mid, mid, n);
        for k in 0..n / 2 {
            let take_r = l == le || (r < re && less(buf.add(r), buf.add(l)));
            *items.add(k) = *buf.add(if take_r { r } else { l });
            r += take_r as usize;
            l += !take_r as usize;
            let take_l = re == r || (l < le && less(buf.add(re - 1), buf.add(le - 1)));
            *items.add(n - 1 - k) = *buf.add(if take_l { le - 1 } else { re - 1 });
            le -= take_l as usize;
            re -= !take_l as usize;
        }
        if n % 2 == 1 {
            *items.add(n / 2) = *buf.add(if l < le { l } else { r });
        }
    }
}

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
        let bytes = v.len * size.max(1);
        let guarded = (*fault::msrt_isolate_hdr())
            .guarded
            .load(core::sync::atomic::Ordering::Relaxed)
            != 0;
        // A comparator can leave a guarded task through a fault or cancellation while a
        // merge holds moved slots in scratch. Keep an immutable byte snapshot for that exit;
        // it has no ownership of its own and must never run element copy/drop hooks.
        let storage = if guarded {
            bytes
                .checked_mul(2)
                .unwrap_or_else(|| fault::fault(b"list size overflow"))
        } else {
            bytes
        };
        let buf = alloc::alloc(storage);
        // Slots of a few words move as typed copies instead of `memcpy` calls of a run-time size.
        macro_rules! words {
            ($n:literal) => {
                merge_sort_word(
                    v.ptr as *mut [u64; $n],
                    buf as *mut [u64; $n],
                    v.len,
                    cmp,
                    env,
                )
            };
        }
        let sort = || match size {
            8 => words!(1),
            16 => words!(2),
            24 => words!(3),
            32 => words!(4),
            40 => words!(5),
            48 => words!(6),
            _ => merge_sort(v.ptr, buf, v.len, size, cmp, env),
        };
        if guarded {
            let original = buf.add(bytes);
            core::ptr::copy_nonoverlapping(v.ptr, original, v.len * size);
            fault::with_cleanup(
                &mut || {
                    // Restore a valid owned list before the caller's drop cleanup runs.
                    core::ptr::copy_nonoverlapping(original, v.ptr, v.len * size);
                    alloc::free(buf);
                },
                sort,
            );
        } else {
            sort();
        }
        alloc::free(buf);
    }
}

/// Sorts a list of `Int` in place, ascending or (when `desc != 0`) descending. Equal integers are
/// indistinguishable, so the unstable sort gives the same list as the stable one.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn msrt_list_sort_ints(v: *mut VecVal, desc: i64) {
    // SAFETY: caller contract: `v` holds `len` words.
    unsafe {
        let v = &mut *v;
        if v.len < 2 {
            return;
        }
        let s = core::slice::from_raw_parts_mut(v.ptr as *mut i64, v.len);
        if desc != 0 {
            s.sort_unstable_by(|a, b| b.cmp(a));
        } else {
            s.sort_unstable();
        }
    }
}

/// `sorted` over `Int`s by a comparator that returns `left - right` (or `right - left` when
/// `desc != 0`). When no two elements differ by more than an `Int` holds, every difference has
/// the sign of the integer order, so this is the integer sort. Otherwise the comparator runs as
/// written, faulting where a subtraction overflows.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_list_sorted_by_difference(
    v: *const VecVal,
    d: *const TypeDesc,
    cmp: CmpFn,
    env: *mut u8,
    desc: i64,
    out: *mut VecVal,
) {
    // SAFETY: caller contract: `v` holds `len` words.
    unsafe {
        copy_list(v, &*d, out);
        let o = &mut *out;
        if o.len < 2 {
            return;
        }
        let s = core::slice::from_raw_parts_mut(o.ptr as *mut i64, o.len);
        let (lo, hi) = s
            .iter()
            .fold((i64::MAX, i64::MIN), |(lo, hi), &x| (lo.min(x), hi.max(x)));
        if hi.checked_sub(lo).is_none() {
            msrt_list_sort_in_place(out, d, cmp, env);
        } else if desc != 0 {
            s.sort_unstable_by(|a, b| b.cmp(a));
        } else {
            s.sort_unstable();
        }
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
            fault::fault(b"range: more than 268435456 items; iterate with 'for index in start..end' directly or bound the list with range_by(max_items:)");
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

/// `index_of_byte(value, start)`: first offset at or after `start` holding `value`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_bytes_index_of_byte(
    b: *const VecVal,
    value: i64,
    start: i64,
    out: *mut i64,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let s = bslice(b);
        let from = start.max(0) as usize;
        if !(0..=255).contains(&value) || from >= s.len() {
            return 0;
        }
        let tail = &s[from..];
        // Keep the first hit cheap, then scan nearby fields a word at a time.
        if tail[0] as i64 == value {
            *out = from as i64;
            return 1;
        }
        let (near, rest) = tail[1..].split_at((tail.len() - 1).min(16));
        let found = string::memchr_short(value as u8, near).or_else(|| {
            if rest.is_empty() {
                return None;
            }
            memchr::memchr(value as u8, rest).map(|i| near.len() + i)
        });
        match found {
            Some(i) => {
                *out = (from + 1 + i) as i64;
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
        // A `List[UInt8]` stores one byte per element, the layout of the bytes themselves.
        let p = if s.is_empty() {
            core::ptr::null_mut()
        } else {
            alloc::alloc(s.len())
        };
        if !s.is_empty() {
            core::ptr::copy_nonoverlapping(s.as_ptr(), p, s.len());
        }
        *out = VecVal {
            ptr: p,
            len: s.len(),
            cap: s.len(),
        };
    }
}

/// `bytes.join(parts)`: the parts end to end in one allocation.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_bytes_join(parts: *const VecVal, out: *mut VecVal) {
    // SAFETY: caller contract; the list holds `Bytes` values inline.
    unsafe {
        let list = &*parts;
        let items: &[VecVal] = if list.len == 0 {
            &[]
        } else {
            core::slice::from_raw_parts(list.ptr.cast::<VecVal>(), list.len)
        };
        let total = items.iter().fold(0usize, |sum, part| {
            sum.checked_add(part.len)
                .unwrap_or_else(|| fault::fault(b"bytes size overflow"))
        });
        if total == 0 {
            *out = EMPTY;
            return;
        }
        let p = alloc::alloc(total);
        let mut at = 0;
        for part in items {
            if part.len > 0 {
                core::ptr::copy_nonoverlapping(part.ptr, p.add(at), part.len);
                at += part.len;
            }
        }
        *out = VecVal {
            ptr: p,
            len: total,
            cap: total,
        };
    }
}

/// `Bytes(values)`: a `List[UInt8]` already holds one byte per element, so this copies it.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_bytes_from_values(values: *const VecVal, out: *mut VecVal) {
    // SAFETY: caller contract.
    unsafe {
        let v = &*values;
        if v.len == 0 {
            bytes_from(&[], out);
        } else {
            bytes_from(core::slice::from_raw_parts(v.ptr, v.len), out);
        }
    }
}

/// `decode_utf8`: presence flag (0 when the bytes are not valid UTF-8), the string through `out`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_bytes_decode_utf8(b: *const VecVal, out: *mut StrVal) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let s = bslice(b);
        if core::str::from_utf8(s).is_err() {
            return 0;
        }
        out.write(from_bytes(s));
        1
    }
}

/// `decode_utf8_range(start, end)`: like `decode_utf8` over `[start, end)` without copying the range
/// first; bounds outside `0 <= start <= end <= length()` fault.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_bytes_decode_utf8_range(
    b: *const VecVal,
    start: i64,
    end: i64,
    out: *mut StrVal,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let s = bslice(b);
        if start < 0 || end < start || end > s.len() as i64 {
            fault::fault_fmt(format_args!(
                "Bytes.decode_utf8_range: bounds {start}..{end} are outside 0..{}",
                s.len()
            ));
        }
        let part = &s[start as usize..end as usize];
        if core::str::from_utf8(part).is_err() {
            return 0;
        }
        out.write(from_bytes(part));
        1
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

/// `BytesBuilder.append_bytes(values)`: borrowed `values`.
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

// ---- Bytes fixed-width codecs ----

/// `msrt_bytes_read_word(data, at, width, little)`: the `width` bytes (1, 2, 4 or 8) at `at` as an unsigned
/// number, or all eight bytes as the `i64` with that bit pattern. `@std/bytes.ms` builds every
/// `Bytes.int32_le(at)` style read on it. Missing bytes are `STATUS_OUT_OF_RANGE`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_bytes_read_word(
    b: *const VecVal,
    at: i64,
    width: i64,
    little: u8,
    out: *mut i64,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let s = bslice(b);
        let n = width as usize;
        let Some(raw) = usize::try_from(at)
            .ok()
            .and_then(|start| s.get(start..start.checked_add(n)?))
        else {
            return STATUS_OUT_OF_RANGE;
        };
        let mut word = [0u8; 8];
        word[..n].copy_from_slice(raw);
        if little == 0 {
            word[..n].reverse();
        }
        out.write(i64::from_le_bytes(word));
        STATUS_OK
    }
}

// ---- StringBuilder (bytes) ----

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_strbuilder_append(b: *mut VecVal, s: *const StrVal) {
    // SAFETY: caller contract.
    unsafe {
        // One byte (a character or punctuation) is the common append and needs no call:
        // this path keeps no registers live across a call, so it has no frame.
        let v = &mut *b;
        let n = (*s).len();
        if n == 1 && v.len < v.cap {
            *v.ptr.add(v.len) = *string::bytes(s).as_ptr();
            v.len += 1;
            return;
        }
        // Text that fits is copied in place: a short word as overlapping word moves, longer
        // text with a single `memcpy`. Only a full buffer reaches the growth path.
        if v.cap - v.len >= n {
            let src = string::bytes(s).as_ptr();
            let dst = v.ptr.add(v.len);
            // The length moves first so that the copy is the last thing the function does: a
            // long copy is then a tail call to `memcpy`, and the function needs no frame.
            v.len += n;
            if n <= 16 {
                copy_short(src, dst, n);
            } else {
                core::ptr::copy_nonoverlapping(src, dst, n);
            }
            return;
        }
        append_slow(b, s);
    }
}

/// Copies `n <= 16` bytes with at most two overlapping loads and stores, so the compiler cannot
/// turn it into a vector loop or a `memcpy` call. The ranges must not overlap.
#[inline(always)]
pub(crate) unsafe fn copy_short(src: *const u8, dst: *mut u8, n: usize) {
    // SAFETY: caller guarantees `n` readable and writable bytes; each access stays within them.
    unsafe {
        if n >= 8 {
            let head = src.cast::<u64>().read_unaligned();
            let tail = src.add(n - 8).cast::<u64>().read_unaligned();
            dst.cast::<u64>().write_unaligned(head);
            dst.add(n - 8).cast::<u64>().write_unaligned(tail);
        } else if n >= 4 {
            let head = src.cast::<u32>().read_unaligned();
            let tail = src.add(n - 4).cast::<u32>().read_unaligned();
            dst.cast::<u32>().write_unaligned(head);
            dst.add(n - 4).cast::<u32>().write_unaligned(tail);
        } else if n > 0 {
            let first = *src;
            let mid = *src.add(n / 2);
            let last = *src.add(n - 1);
            *dst = first;
            *dst.add(n / 2) = mid;
            *dst.add(n - 1) = last;
        }
    }
}

#[inline(never)]
unsafe fn append_slow(b: *mut VecVal, s: *const StrVal) {
    // SAFETY: caller contract.
    unsafe {
        let data = string::bytes(s);
        let v = &mut *b;
        if v.len + data.len() > v.cap {
            reserve(v, &desc::msrt_desc_bool, data.len());
        }
        if !data.is_empty() {
            core::ptr::copy_nonoverlapping(data.as_ptr(), v.ptr.add(v.len), data.len());
        }
        v.len += data.len();
    }
}

/// Appends the decimal text of `n`; the same bytes as appending `n.to_string()` without the
/// temporary string.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_strbuilder_append_int(b: *mut VecVal, n: i64) {
    // SAFETY: caller contract.
    unsafe {
        let mut tmp = [0u8; 20];
        let digits = crate::num::format_i64(n, &mut tmp);
        let v = &mut *b;
        if v.len + digits.len() > v.cap {
            reserve(v, &desc::msrt_desc_bool, digits.len());
        }
        core::ptr::copy_nonoverlapping(digits.as_ptr(), v.ptr.add(v.len), digits.len());
        v.len += digits.len();
    }
}

/// Builds the string and consumes the builder (its buffer is freed).
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_strbuilder_freeze(b: *mut VecVal, out: *mut StrVal) {
    // SAFETY: caller contract.
    unsafe {
        let v = &mut *b;
        // A long text takes over the builder's buffer (NUL terminated, trimmed when much of it
        // is spare) instead of copying it.
        if v.len > STR_INLINE_MAX && v.len <= string::MAX_BYTES {
            let mut ptr = v.ptr;
            if v.cap == v.len || v.cap > v.len + (v.len >> 2) + 1 {
                ptr = alloc::realloc(ptr, v.len + 1);
            }
            *ptr.add(v.len) = 0;
            out.write(StrVal::owned(ptr, v.len));
            *v = EMPTY;
            return;
        }
        let s = from_bytes(bslice(b));
        msrt_bytes_drop(b);
        out.write(s);
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

    #[test]
    fn copy_short_matches_slice_copy() {
        let src: Vec<u8> = (1..=16).collect();
        for n in 0..=16usize {
            let mut dst = [0u8; 20];
            // SAFETY: `src` and `dst` hold at least `n` bytes and do not overlap.
            unsafe { copy_short(src.as_ptr(), dst.as_mut_ptr().add(2), n) };
            assert_eq!(&dst[2..2 + n], &src[..n], "length {n}");
            assert!(
                dst[..2].iter().chain(&dst[2 + n..]).all(|&b| b == 0),
                "length {n} overran"
            );
        }
    }

    #[test]
    fn strbuilder_freeze_adopts_long_buffers() {
        for len in [0usize, 1, 15, 16, 17, 100, 5000] {
            for cap_extra in [0usize, 1, len, 10 * len + 7] {
                // SAFETY: the builder is a fresh owned buffer that freeze consumes.
                unsafe {
                    let mut b = EMPTY;
                    let want: Vec<u8> = (0..len).map(|i| b'a' + (i % 26) as u8).collect();
                    reserve(&mut b, &desc::msrt_desc_bool, len + cap_extra);
                    core::ptr::copy_nonoverlapping(want.as_ptr(), b.ptr, len);
                    b.len = len;
                    let mut out = core::mem::MaybeUninit::<StrVal>::uninit();
                    msrt_strbuilder_freeze(&mut b, out.as_mut_ptr());
                    let s = out.assume_init();
                    assert_eq!(string::bytes(&s), &want[..]);
                    if len > STR_INLINE_MAX {
                        assert_eq!(*string::bytes(&s).as_ptr().add(len), 0);
                    }
                    assert!(b.ptr.is_null());
                    string::release(&s);
                }
            }
        }
    }

    unsafe extern "C-unwind" fn cmp_high(_env: *mut u8, a: *const u8, b: *const u8) -> i64 {
        // SAFETY: the sort passes pointers to live word slots.
        unsafe { ((*(a as *const u64) >> 32) as i64) - ((*(b as *const u64) >> 32) as i64) }
    }

    unsafe extern "C-unwind" fn cmp_noise(env: *mut u8, _a: *const u8, _b: *const u8) -> i64 {
        // SAFETY: `env` is the test's xorshift state.
        unsafe {
            let s = &mut *(env as *mut u64);
            *s ^= *s << 13;
            *s ^= *s >> 7;
            *s ^= *s << 17;
            (*s % 3) as i64 - 1
        }
    }

    #[test]
    fn word_sort_is_stable_and_total_for_every_size() {
        let mut seed = 0x2545_f491_4f6c_dd1du64;
        let mut next = move || {
            seed ^= seed << 13;
            seed ^= seed >> 7;
            seed ^= seed << 17;
            seed
        };
        for n in 0..300usize {
            for range in [3u64, 50, 1 << 20] {
                // Key in the high half, original position in the low half.
                let mut v: Vec<u64> = (0..n as u64)
                    .map(|i| ((next() % range) << 32) | i)
                    .collect();
                let mut want = v.clone();
                want.sort_by_key(|x| x >> 32);
                let mut buf = vec![0u64; n];
                // SAFETY: both buffers hold `n` words.
                unsafe {
                    merge_sort_word(
                        v.as_mut_ptr(),
                        buf.as_mut_ptr(),
                        n,
                        cmp_high,
                        core::ptr::null_mut(),
                    );
                }
                assert_eq!(v, want, "n={n} range={range}");
            }
        }
    }

    #[test]
    fn word_sort_keeps_every_element_for_an_inconsistent_comparator() {
        for n in 0..200usize {
            let mut v: Vec<u64> = (0..n as u64).collect();
            let mut buf = vec![0u64; n];
            let mut state = 0x9e37_79b9_7f4a_7c15u64 ^ n as u64;
            // SAFETY: both buffers hold `n` words; `state` outlives the call.
            unsafe {
                merge_sort_word(
                    v.as_mut_ptr(),
                    buf.as_mut_ptr(),
                    n,
                    cmp_noise,
                    &mut state as *mut u64 as *mut u8,
                );
            }
            v.sort();
            assert_eq!(v, (0..n as u64).collect::<Vec<_>>(), "n={n}");
        }
    }

    #[test]
    fn find_int_matches_a_plain_scan() {
        for len in 0..40usize {
            let items: Vec<i64> = (0..len as i64).map(|i| i * 3 % 7).collect();
            for target in -1..8 {
                assert_eq!(
                    find_int(&items, target),
                    items.iter().position(|&x| x == target),
                    "{items:?} {target}"
                );
            }
        }
    }
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

    fn plain_desc(size: u32, kind: u32) -> TypeDesc {
        TypeDesc {
            size,
            align: if size == 1 { 1 } else { 8 },
            kind,
            reserved: 0,
            inner0: core::ptr::null(),
            inner1: core::ptr::null(),
            drop: None,
            copy: None,
            eq: None,
            hash: None,
        }
    }

    unsafe fn list_data(v: &VecVal, size: usize) -> &[u8] {
        if v.len == 0 || size == 0 {
            return &[];
        }
        // SAFETY: test values hold `len` slots of `size` bytes.
        unsafe { core::slice::from_raw_parts(v.ptr, v.len * size) }
    }

    #[test]
    fn plain_ranges_match_snapshot_model() {
        let _g = testutil::lock();
        let before = alloc::live_blocks();
        for (size, kind) in [(1, KIND_BOOL), (8, KIND_INT), (24, KIND_POD)] {
            let d = plain_desc(size as u32, kind);
            for n in [0, 1, 7, 257] {
                let data: Vec<u8> = (0..n * size)
                    .map(|i| {
                        if size == 1 {
                            (i % 2) as u8
                        } else {
                            ((i * 37 + i / size * 11) % 251) as u8
                        }
                    })
                    .collect();
                // SAFETY: the input and every result own aligned allocations of their slot sizes.
                unsafe {
                    let mut input = EMPTY;
                    reserve(&mut input, &d, n);
                    if !data.is_empty() {
                        core::ptr::copy_nonoverlapping(data.as_ptr(), input.ptr, data.len());
                    }
                    input.len = n;
                    let mut cat = EMPTY;
                    msrt_list_concat(&input, &input, &d, &mut cat);
                    let expected = [data.as_slice(), data.as_slice()].concat();
                    assert_eq!(list_data(&cat, size), expected);
                    let mut parts = [EMPTY, input, EMPTY, input, EMPTY];
                    let lists = VecVal {
                        ptr: parts.as_mut_ptr().cast(),
                        len: parts.len(),
                        cap: parts.len(),
                    };
                    let mut flat = EMPTY;
                    msrt_list_flatten(&lists, &d, &mut flat);
                    assert_eq!(list_data(&flat, size), expected);
                    drop_list(&mut cat, &d);
                    drop_list(&mut flat, &d);
                    // Exhaustive overlaps for small inputs, including truncation at the end.
                    if n <= 7 {
                        for start in 0..=n {
                            for end in start..=n {
                                for target in 0..=n {
                                    let mut copied = EMPTY;
                                    copy_list(&input, &d, &mut copied);
                                    msrt_list_copy_within(
                                        &mut copied,
                                        &d,
                                        target as i64,
                                        start as i64,
                                        end as i64,
                                    );
                                    let mut expected = data.clone();
                                    let count = (end - start).min(n - target);
                                    expected[target * size..(target + count) * size]
                                        .copy_from_slice(
                                            &data[start * size..(start + count) * size],
                                        );
                                    assert_eq!(list_data(&copied, size), expected);
                                    drop_list(&mut copied, &d);
                                }
                            }
                        }
                    }
                    assert_eq!(list_data(&input, size), data);
                    drop_list(&mut input, &d);
                }
            }
        }
        assert_eq!(alloc::live_blocks(), before);
    }

    crate::isolate_static! {
        static ZERO_COPIES: usize = 0;
    }

    unsafe extern "C" fn copy_zero(_src: *const u8, _dst: *mut u8) {
        // SAFETY: tests hold the runtime-global lock.
        unsafe { *ZERO_COPIES.ptr() += 1 };
    }

    #[test]
    fn zero_sized_ranges_preserve_custom_copy_hooks() {
        let _g = testutil::lock();
        let before = alloc::live_blocks();
        for custom in [false, true] {
            let mut d = plain_desc(0, KIND_CUSTOM);
            d.align = 1;
            d.copy = custom.then_some(copy_zero);
            // SAFETY: nonempty zero-sized lists still have owned backing allocations.
            unsafe {
                *ZERO_COPIES.ptr() = 0;
                let mut input = VecVal {
                    ptr: alloc::alloc(3),
                    len: 3,
                    cap: 3,
                };
                let mut copied = EMPTY;
                copy_list(&input, &d, &mut copied);
                let mut cat = EMPTY;
                msrt_list_concat(&input, &input, &d, &mut cat);
                let mut parts = [EMPTY, input, EMPTY, input];
                let lists = VecVal {
                    ptr: parts.as_mut_ptr().cast(),
                    len: parts.len(),
                    cap: parts.len(),
                };
                let mut flat = EMPTY;
                msrt_list_flatten(&lists, &d, &mut flat);
                msrt_list_copy_within(&mut copied, &d, 1, 0, 2);
                assert_eq!((copied.len, cat.len, flat.len), (3, 6, 6));
                assert_eq!(*ZERO_COPIES.ptr(), if custom { 17 } else { 0 });
                for v in [&mut input, &mut copied, &mut cat, &mut flat] {
                    drop_list(v, &d);
                }
            }
        }
        assert_eq!(alloc::live_blocks(), before);
    }

    unsafe extern "C-unwind" fn by_value(_: *mut u8, a: *const u8, b: *const u8) -> i64 {
        // SAFETY: int slots.
        unsafe { (*(a as *const i64)).cmp(&*(b as *const i64)) as i64 }
    }

    #[test]
    fn replace_and_swap_move_without_copying() {
        let _g = testutil::lock();
        unsafe {
            let before = alloc::live_blocks();
            let d = &msrt_desc_string;
            let mut v = EMPTY;
            for text in [&b"a"[..], b"b", b"c"] {
                let s = string::from_bytes(text);
                msrt_list_push(&mut v, d, &s as *const _ as *const u8);
            }
            let mut incoming = string::from_bytes(b"x");
            let mut outgoing = core::mem::zeroed::<StrVal>();
            msrt_list_replace(
                &mut v,
                d,
                -2,
                &mut incoming as *mut _ as *mut u8,
                &mut outgoing as *mut _ as *mut u8,
            );
            assert_eq!(string::bytes(&outgoing), b"b");
            assert_eq!(string::bytes((v.ptr as *const StrVal).add(1)), b"x");
            msrt_list_swap(&mut v, d, 0, -1);
            msrt_list_swap(&mut v, d, 1, 1);
            let got: Vec<&[u8]> = (0..3)
                .map(|i| string::bytes((v.ptr as *const StrVal).add(i)))
                .collect();
            assert_eq!(got, [&b"c"[..], b"x", b"a"]);
            testutil::assert_fault(
                "List.swap: index must be between -3 and 2 (negative indexes count from the end), found 3",
                || msrt_list_swap(&mut v, d, 0, 3),
            );
            drop_list(&mut v, d);
            slot_drop(d, &mut outgoing as *mut _ as *mut u8);
            assert_eq!(alloc::live_blocks(), before);
        }
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
    fn int_sort_accepts_empty_and_singleton_lists() {
        let _g = testutil::lock();
        let before = alloc::live_blocks();
        for desc in [0, 1] {
            let mut v = EMPTY;
            // SAFETY: the canonical empty list is a valid list of Int.
            unsafe { msrt_list_sort_ints(&mut v, desc) };
            assert_eq!(v.len, 0);
            assert!(v.ptr.is_null());
            // SAFETY: all slots and backing storage belong to this live Int list.
            unsafe {
                reserve(&mut v, &msrt_desc_int, 4);
                let ptr = v.ptr;
                let cap = v.cap;
                msrt_list_sort_ints(&mut v, desc);
                assert_eq!((v.ptr, v.len, v.cap), (ptr, 0, cap));
                push_int(&mut v, i64::MIN);
                msrt_list_sort_ints(&mut v, desc);
                assert_eq!(ints(&v), [i64::MIN]);
                assert_eq!((v.ptr, v.cap), (ptr, cap));
                drop_list(&mut v, &msrt_desc_int);
            }
        }
        assert_eq!(alloc::live_blocks(), before);
    }

    #[test]
    fn splice_accepts_unallocated_empty_lists() {
        let _g = testutil::lock();
        let mut v = EMPTY;
        let mut replacement = EMPTY;
        // SAFETY: both canonical empty lists are live lists of Int.
        unsafe { msrt_list_splice(&mut v, &msrt_desc_int, 0, 0, &mut replacement) };
        assert_eq!((v.len, replacement.len), (0, 0));
        assert!(v.ptr.is_null());
        assert!(replacement.ptr.is_null());
    }

    #[test]
    fn int_sort_orders_both_ways() {
        let _g = testutil::lock();
        unsafe {
            let d = &msrt_desc_int;
            for desc in [0i64, 1] {
                let mut v = EMPTY;
                for i in 0..300i64 {
                    push_int(&mut v, (i * 7919) % 101 - 50);
                }
                msrt_list_sort_ints(&mut v, desc);
                let got = ints(&v);
                assert!(
                    got.windows(2)
                        .all(|w| (w[0] <= w[1]) == (desc == 0) || w[0] == w[1])
                );
                drop_list(&mut v, d);
            }
        }
    }

    #[test]
    fn nested_lists_copy_and_equality() {
        let _g = testutil::lock();
        let before = alloc::live_blocks();
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
            let mut cat = EMPTY;
            msrt_list_concat(&outer, &outer, &inner, &mut cat);
            let first = cat.ptr as *mut VecVal;
            let changed = string::from_bytes(b"changed");
            msrt_list_set(first, &msrt_desc_string, 0, &changed as *const _ as _);
            assert!(eq_list(&outer, &c, &inner));
            msrt_list_copy_within(&mut cat, &inner, 1, 0, 1);
            assert_ne!((*first).ptr, (*first.add(1)).ptr);
            let mut flat = EMPTY;
            msrt_list_flatten(&cat, &msrt_desc_string, &mut flat);
            drop_list(&mut cat, &inner);
            assert_eq!(flat.len, 2);
            for i in 0..flat.len {
                assert_eq!(
                    string::bytes((flat.ptr as *const StrVal).add(i)),
                    b"changed"
                );
            }
            drop_list(&mut flat, &msrt_desc_string);
            drop_list(&mut outer, &inner);
            drop_list(&mut c, &inner);
        }
        assert_eq!(alloc::live_blocks(), before);
    }
}
