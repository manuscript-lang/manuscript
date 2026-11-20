//! `List[T]`, `Bytes`, `StringBuilder` and the builders: owned header-less `VecVal` values.
//!
//! Every operation takes a pointer to the receiver value and the element
//! descriptor. Mutators change the receiver in place and return nothing;
//! element arguments of stores are consumed (ownership moves into the list).
//! ms: domain collection
use crate::alloc;
use crate::fault;
use crate::string::{self, from_bytes};
use ms_rt_abi::*;

// Defined in C (runtime/core); declared here for the Rust code that still calls them.
unsafe extern "C-unwind" {
    pub fn msrt_list_new(out: *mut VecVal);
    pub fn msrt_list_with_capacity(d: ElemDesc, cap: i64, out: *mut VecVal);
    pub fn msrt_list_drop(v: *mut VecVal, d: ElemDesc);
    pub fn msrt_list_copy(v: *const VecVal, d: ElemDesc, out: *mut VecVal);
    pub fn msrt_list_shadow(v: *const VecVal, d: ElemDesc, out: *mut VecVal);
    pub fn msrt_list_free_raw(v: *mut VecVal);
    pub fn msrt_list_push(v: *mut VecVal, d: ElemDesc, e: *const u8);
    pub fn msrt_list_reserve(v: *mut VecVal, d: ElemDesc, extra: i64);
    pub fn msrt_list_at(v: *const VecVal, d: ElemDesc, index: i64, default: *const u8)
    -> *const u8;
    pub fn msrt_list_get(
        v: *const VecVal,
        d: ElemDesc,
        index: i64,
        default: *const u8,
        out: *mut u8,
    );
    pub fn msrt_list_index_of(v: *const VecVal, d: ElemDesc, probe: *const u8, out: *mut i64)
    -> u8;
    pub fn msrt_list_last_index_of(
        v: *const VecVal,
        d: ElemDesc,
        probe: *const u8,
        out: *mut i64,
    ) -> u8;
    pub fn msrt_list_contains(v: *const VecVal, d: ElemDesc, probe: *const u8) -> u8;
    pub fn msrt_list_prepend(v: *mut VecVal, d: ElemDesc, e: *const u8);
    pub fn msrt_list_insert(v: *mut VecVal, d: ElemDesc, index: i64, e: *const u8);
    pub fn msrt_list_insert_copy(v: *mut VecVal, d: ElemDesc, index: i64, e: *const u8);
    pub fn msrt_list_pop(v: *mut VecVal, d: ElemDesc, out: *mut u8) -> u8;
    pub fn msrt_list_set(v: *mut VecVal, d: ElemDesc, index: i64, e: *const u8);
    pub fn msrt_list_replace(v: *mut VecVal, d: ElemDesc, index: i64, e: *mut u8, out: *mut u8);
    pub fn msrt_list_swap(v: *mut VecVal, d: ElemDesc, i: i64, j: i64);
    pub fn msrt_list_remove(v: *mut VecVal, d: ElemDesc, index: i64);
    pub fn msrt_list_reverse(v: *mut VecVal, d: ElemDesc);
    pub fn msrt_list_reversed(v: *const VecVal, d: ElemDesc, out: *mut VecVal);
    pub fn msrt_list_splice(
        v: *mut VecVal,
        d: ElemDesc,
        start: i64,
        count: i64,
        replacement: *mut VecVal,
    );
    pub fn msrt_list_fill(v: *mut VecVal, d: ElemDesc, value: *const u8, start: i64, end: i64);
    pub fn msrt_list_copy_within(v: *mut VecVal, d: ElemDesc, target: i64, start: i64, end: i64);
    pub fn msrt_list_slice(
        v: *const VecVal,
        d: ElemDesc,
        start: i64,
        end: i64,
        out: *mut VecVal,
        err: ErrSlot,
    ) -> u8;
    pub fn msrt_list_slice_view(
        v: *const VecVal,
        d: ElemDesc,
        start: i64,
        end: i64,
        out: *mut VecVal,
        err: ErrSlot,
    ) -> u8;
    pub fn msrt_list_take(v: *const VecVal, d: ElemDesc, count: i64, out: *mut VecVal);
    pub fn msrt_list_pieces(
        v: *const VecVal,
        d: ElemDesc,
        od: *const TypeDesc,
        size: i64,
        step: i64,
        short_last: u8,
        out: *mut VecVal,
    );
    pub fn msrt_list_drop_n(v: *const VecVal, d: ElemDesc, count: i64, out: *mut VecVal);
    pub fn msrt_list_concat(a: *const VecVal, b: *const VecVal, d: ElemDesc, out: *mut VecVal);
    pub fn msrt_list_repeat(v: *const VecVal, d: ElemDesc, count: i64, out: *mut VecVal);
    pub fn msrt_list_extend(v: *mut VecVal, d: ElemDesc, other: *const VecVal);
    pub fn msrt_list_distinct(v: *const VecVal, d: ElemDesc, out: *mut VecVal);
    pub fn msrt_list_keys(v: *const VecVal, out: *mut VecVal);
    pub fn msrt_list_sort_in_place(v: *mut VecVal, d: ElemDesc, cmp: CmpFn, env: *mut u8);
    pub fn msrt_list_sorted_by_difference(
        v: *const VecVal,
        d: ElemDesc,
        cmp: CmpFn,
        env: *mut u8,
        desc: i64,
        out: *mut VecVal,
    );
    pub fn msrt_list_sorted(
        v: *const VecVal,
        d: ElemDesc,
        cmp: CmpFn,
        env: *mut u8,
        out: *mut VecVal,
    );
    pub fn msrt_list_range(start: i64, end: i64, out: *mut VecVal);
    pub fn msrt_list_range_by(
        start: i64,
        end: i64,
        step: i64,
        has_max: HasRaw,
        max: i64,
        out: *mut VecVal,
    ) -> u8;
    pub fn msrt_list_to_set(v: *const VecVal, d: ElemDesc, out: *mut MapVal);
    pub fn msrt_bytes_drop(b: *mut VecVal);
    pub fn msrt_bytes_copy(b: *const VecVal, out: *mut VecVal);
    pub fn msrt_bytes_contains(b: *const VecVal, v: *const VecVal) -> u8;
    pub fn msrt_bytes_index_of(b: *const VecVal, v: *const VecVal, out: *mut i64) -> u8;
    pub fn msrt_bytes_index_of_byte(b: *const VecVal, value: i64, start: i64, out: *mut i64) -> u8;
    pub fn msrt_bytes_last_index_of(b: *const VecVal, v: *const VecVal, out: *mut i64) -> u8;
    pub fn msrt_bytes_starts_with(b: *const VecVal, v: *const VecVal) -> u8;
    pub fn msrt_bytes_ends_with(b: *const VecVal, v: *const VecVal) -> u8;
    pub fn msrt_bytes_get(b: *const VecVal, index: i64, has_default: HasRaw, default: i64) -> i64;
    pub fn msrt_bytes_slice(b: *const VecVal, start: i64, end: i64, out: *mut VecVal) -> u8;
    pub fn msrt_bytes_view(b: *const VecVal, start: i64, end: i64, out: *mut VecVal);
    pub fn msrt_bytes_eq(a: *const VecVal, b: *const VecVal) -> u8;
    pub fn msrt_bytes_reversed(b: *const VecVal, out: *mut VecVal);
    pub fn msrt_bytes_with_value(b: *const VecVal, index: i64, value: i64, out: *mut VecVal);
    pub fn msrt_bytes_concat(a: *const VecVal, b: *const VecVal, out: *mut VecVal);
    pub fn msrt_bytes_split(b: *const VecVal, sep: *const VecVal, out: *mut VecVal);
    pub fn msrt_bytes_values(b: *const VecVal, out: *mut VecVal);
    pub fn msrt_bytes_join(parts: *const VecVal, out: *mut VecVal);
    pub fn msrt_bytes_from_values(values: *const VecVal, out: *mut VecVal);
    pub fn msrt_bytes_append(b: *mut VecVal, value: i64);
    pub fn msrt_bytes_extend(b: *mut VecVal, values: *const VecVal);
    pub fn msrt_bytes_read_word(
        b: *const VecVal,
        at: i64,
        width: i64,
        little: u8,
        out: *mut i64,
    ) -> u8;
    pub fn msrt_hash_list(v: *const VecVal, d: ElemDesc) -> i64;
}

// Defined in C (runtime/core); declared here for the Rust code that still calls them.
unsafe extern "C" {
    pub fn msrt_list_sort_ints(v: *mut VecVal, desc: i64);
}

/// Drops the elements and the buffer of a list.
///
/// # Safety
/// `v` is a live list of `d`.
pub unsafe fn drop_list(v: *mut VecVal, d: &TypeDesc) {
    // SAFETY: caller contract; `msrt_list_drop` is defined in C.
    unsafe { msrt_list_drop(v, d) }
}

const EMPTY: VecVal = VecVal {
    ptr: core::ptr::null_mut(),
    len: 0,
    cap: 0,
};

/// Moves `e` (a slot of `d.size` bytes) onto the end.
///
/// # Safety
/// `e` is a live slot of `d`, distinct from the list's storage.
pub(crate) unsafe fn push(v: &mut VecVal, d: &TypeDesc, e: *const u8) {
    // SAFETY: caller contract; `msrt_list_push` is defined in C.
    unsafe { msrt_list_push(v, d, e) }
}

// ---- construction and lifetime ----

// ---- reads ----

// ---- mutators ----

// ---- derived lists ----

// ---- sorting ----

/// Comparator thunk: `env` is the closure, `a` and `b` point at element slots.
pub type CmpFn = unsafe extern "C-unwind" fn(env: *mut u8, a: *const u8, b: *const u8) -> i64;

// ---- generators ----

/// Destructuring length mismatch fault.
#[unsafe(no_mangle)]
// ms: leaf
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

pub(crate) unsafe fn bytes_from(data: &[u8], out: *mut VecVal) {
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

/// `decode_utf8`: presence flag (0 when the bytes are not valid UTF-8), the string through `out`.
#[unsafe(no_mangle)]
// ms: leaf fresh takes_self domain=binary
pub unsafe extern "C-unwind" fn msrt_bytes_decode_utf8(b: *const VecVal, out: *mut StrVal) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let s = bslice(b);
        if !s.is_ascii() && core::str::from_utf8(s).is_err() {
            return 0;
        }
        out.write(from_bytes(s));
        1
    }
}

/// `decode_utf8` of a `Bytes` that dies at the call (the optimizer rewrites a call whose receiver
/// drops right after it): the string reuses the buffer instead of copying it, and an invalid or
/// short input frees it. Same presence flag and `out` as `msrt_bytes_decode_utf8`.
///
/// # Safety
/// `b` holds an owned `Bytes` that the callee takes; `out` is writable.
#[unsafe(no_mangle)]
// ms: leaf domain=binary
pub unsafe extern "C-unwind" fn msrt_bytes_decode_utf8_take(
    b: *mut VecVal,
    out: *mut StrVal,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let v = &*b;
        let s = bslice(b);
        let ascii = s.is_ascii();
        // A view (`cap == 0`) borrows its bytes, so there is no buffer to free or reuse.
        let release = |v: &VecVal| {
            if v.cap != 0 {
                alloc::free(v.ptr);
            }
        };
        if !ascii && core::str::from_utf8(s).is_err() {
            release(v);
            return 0;
        }
        if v.cap == 0 || v.len <= STR_INLINE_MAX {
            out.write(from_bytes(s));
            release(v);
            return 1;
        }
        // The string is the same allocation plus a NUL terminator.
        let ptr = if v.cap > v.len {
            v.ptr
        } else {
            alloc::realloc(v.ptr, v.len + 1)
        };
        *ptr.add(v.len) = 0;
        let r = StrVal::owned(ptr, v.len);
        out.write(if ascii { r.with_ascii() } else { r });
        1
    }
}

/// `decode_utf8_range(start, end)`: like `decode_utf8` over `[start, end)` without copying the range
/// first; bounds outside `0 <= start <= end <= length()` fault.
#[unsafe(no_mangle)]
// ms: leaf fresh domain=binary
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
        if !part.is_ascii() && core::str::from_utf8(part).is_err() {
            return 0;
        }
        out.write(from_bytes(part));
        1
    }
}

// ---- Bytes fixed-width codecs ----

// ---- StringBuilder (bytes) ----

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

/// Appends a string to a builder.
///
/// Text that fits the builder's spare room is copied by the caller's own code (one byte, a short
/// word as overlapping moves, longer text with `memcpy`); a full buffer calls the runtime.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_strbuilder_append(b: *mut VecVal, s: *const StrVal) {
    // SAFETY: caller passes a live builder and string.
    unsafe {
        let v = &mut *b;
        let text = string::bytes(s);
        let n = text.len();
        if v.cap - v.len >= n {
            let dst = v.ptr.add(v.len);
            v.len += n;
            if n == 1 {
                *dst = text[0];
            } else if n <= 16 {
                copy_short(text.as_ptr(), dst, n);
            } else {
                core::ptr::copy_nonoverlapping(text.as_ptr(), dst, n);
            }
            return;
        }
        msrt_strbuilder_append_slow(b, s);
    }
}

/// Appends a string past the builder's spare room: grows, then copies.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_strbuilder_append_slow(b: *mut VecVal, s: *const StrVal) {
    // SAFETY: caller contract.
    unsafe {
        let data = string::bytes(s);
        let v = &mut *b;
        if v.len + data.len() > v.cap {
            msrt_list_reserve(v, &crate::desc::msrt_desc_bool, data.len() as i64);
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
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_strbuilder_append_int(b: *mut VecVal, n: i64) {
    // SAFETY: caller contract.
    unsafe {
        let mut tmp = [0u8; 20];
        let digits = crate::num::format_i64(n, &mut tmp);
        let v = &mut *b;
        if v.len + digits.len() > v.cap {
            msrt_list_reserve(v, &crate::desc::msrt_desc_bool, digits.len() as i64);
        }
        core::ptr::copy_nonoverlapping(digits.as_ptr(), v.ptr.add(v.len), digits.len());
        v.len += digits.len();
    }
}

/// Builds the string and moving_params the builder (its buffer is freed).
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_strbuilder_freeze(b: *mut VecVal, out: *mut StrVal) {
    // SAFETY: caller contract.
    unsafe {
        let v = &mut *b;
        // A long text takes over the builder's buffer (NUL terminated, trimmed when much of it
        // is spare) instead of copying it.
        if v.len > STR_INLINE_MAX && v.len <= string::MAX_BYTES {
            let mut ptr = v.ptr;
            if v.cap == v.len || v.cap > v.len + (v.len >> 2) + 1 {
                ptr = alloc::trim(ptr, v.len + 1);
            }
            *ptr.add(v.len) = 0;
            // One vector scan flags an ASCII text, so `length`, `get` and `slice` on it do not
            // count scalars on every call.
            let text = StrVal::owned(ptr, v.len);
            let ascii = core::slice::from_raw_parts(ptr, v.len).is_ascii();
            out.write(if ascii { text.with_ascii() } else { text });
            *v = EMPTY;
            return;
        }
        let s = from_bytes(bslice(b));
        msrt_bytes_drop(b);
        out.write(s);
    }
}
