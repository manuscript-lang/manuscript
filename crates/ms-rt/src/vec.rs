//! `List[T]`, `Bytes`, `StringBuilder` and the builders: owned header-less `VecVal` values.
//!
//! Every operation takes a pointer to the receiver value and the element
//! descriptor. Mutators change the receiver in place and return nothing;
//! element arguments of stores are consumed (ownership moves into the list).
//! ms: domain collection
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

/// Comparator thunk: `env` is the closure, `a` and `b` point at element slots.
pub type CmpFn = unsafe extern "C-unwind" fn(env: *mut u8, a: *const u8, b: *const u8) -> i64;
