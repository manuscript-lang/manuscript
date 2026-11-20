//! `Map[K, V]` and `Set[T]`: insertion-ordered hash tables stored as `MapVal`.
//!
//! `slots` is an append-only array of entries `{ hash: u64 (top bit set = live), key, value }`
//! spaced `stride` bytes apart; `index` is an open-addressing table of `u64` entries: the
//! high word is the hash's high word (a tag, so probes skip non-matching slots without touching
//! them) and the low word is the slot number (`0` empty, `u32::MAX` removed, otherwise slot + 1). Removal leaves a hole that scans
//! skip and compaction reclaims once more than half the slots are holes.
//! ms: domain map
use ms_rt_abi::*;

// Defined in C (runtime/core); declared here for the Rust code that still calls them.
unsafe extern "C-unwind" {
    pub fn msrt_map_get_ptr_sw8(
        m: *const MapVal,
        _kd: KeyDesc,
        _vd: ValDesc,
        key: *const u8,
    ) -> *const u8;
    pub fn msrt_map_contains_sw8(
        m: *const MapVal,
        _kd: KeyDesc,
        _vd: ValDesc,
        key: *const u8,
    ) -> u8;
    pub fn msrt_map_get_sw8(
        m: *const MapVal,
        _kd: KeyDesc,
        _vd: ValDesc,
        key: *const u8,
        out: *mut u8,
    ) -> u8;
    pub fn msrt_map_get_ptr_w8(
        m: *const MapVal,
        _kd: KeyDesc,
        _vd: ValDesc,
        key: *const u8,
    ) -> *const u8;
    pub fn msrt_map_contains_w8(m: *const MapVal, _kd: KeyDesc, _vd: ValDesc, key: *const u8)
    -> u8;
    pub fn msrt_set_contains_w(m: *const MapVal, _kd: KeyDesc, _vd: ValDesc, key: *const u8) -> u8;
    pub fn msrt_map_get_w8(
        m: *const MapVal,
        _kd: KeyDesc,
        _vd: ValDesc,
        key: *const u8,
        out: *mut u8,
    ) -> u8;
    pub fn msrt_map_fill_strings(
        m: *mut MapVal,
        vd: ValDesc,
        keys: *mut StrVal,
        vals: *mut u8,
        stride: i64,
        n: i64,
    ) -> i64;
    pub fn msrt_map_length(m: *const MapVal) -> i64;
    pub fn msrt_map_slot_count(m: *const MapVal) -> i64;
    pub fn msrt_map_entry_ptrs(
        m: *const MapVal,
        kd: KeyDesc,
        vd: ValDesc,
        i: i64,
        key_out: *mut *const u8,
        val_out: *mut *const u8,
    ) -> u8;
    pub fn msrt_map_new(out: *mut MapVal);
    pub fn msrt_map_stamp(m: *mut MapVal, kd: KeyDesc);
    pub fn msrt_map_drop(m: *mut MapVal, kd: KeyDesc, vd: ValDesc);
    pub fn msrt_map_copy(m: *const MapVal, kd: KeyDesc, vd: ValDesc, out: *mut MapVal);
    pub fn msrt_map_reserve(m: *mut MapVal, kd: KeyDesc, vd: ValDesc, n: i64);
    pub fn msrt_map_add(m: *mut MapVal, kd: KeyDesc, vd: ValDesc, key: *mut u8, val: *mut u8);
    pub fn msrt_map_add_w8(m: *mut MapVal, _kd: KeyDesc, _vd: ValDesc, key: *mut u8, val: *mut u8);
    pub fn msrt_map_add_sw8(m: *mut MapVal, _kd: KeyDesc, _vd: ValDesc, key: *mut u8, val: *mut u8);
    pub fn msrt_map_slot_lent(
        m: *mut MapVal,
        kd: KeyDesc,
        vd: ValDesc,
        key: *const u8,
        default: *mut u8,
    ) -> *mut u8;
    pub fn msrt_map_add_lent(
        m: *mut MapVal,
        kd: KeyDesc,
        vd: ValDesc,
        key: *const u8,
        val: *mut u8,
    );
    pub fn msrt_map_add_default_lent(
        m: *mut MapVal,
        kd: KeyDesc,
        vd: ValDesc,
        key: *const u8,
        val: *mut u8,
    );
    pub fn msrt_map_add_default(
        m: *mut MapVal,
        kd: KeyDesc,
        vd: ValDesc,
        key: *mut u8,
        val: *mut u8,
    );
    pub fn msrt_map_remove(m: *mut MapVal, kd: KeyDesc, vd: ValDesc, key: *const u8);
    pub fn msrt_map_contains(m: *const MapVal, kd: KeyDesc, vd: ValDesc, key: *const u8) -> u8;
    pub fn msrt_map_get_ptr(
        m: *const MapVal,
        kd: KeyDesc,
        vd: ValDesc,
        key: *const u8,
    ) -> *const u8;
    pub fn msrt_map_get(
        m: *const MapVal,
        kd: KeyDesc,
        vd: ValDesc,
        key: *const u8,
        out: *mut u8,
    ) -> u8;
    pub fn msrt_map_clear(m: *mut MapVal, kd: KeyDesc, vd: ValDesc);
    pub fn msrt_set_values(m: *const MapVal, kd: KeyDesc, vd: ValDesc, out: *mut VecVal);
    pub fn msrt_map_keys(m: *const MapVal, kd: KeyDesc, vd: ValDesc, out: *mut VecVal);
    pub fn msrt_map_values(m: *const MapVal, kd: KeyDesc, vd: ValDesc, out: *mut VecVal);
    pub fn msrt_map_keys_view(m: *const MapVal, kd: KeyDesc, vd: ValDesc, out: *mut VecVal);
    pub fn msrt_map_values_view(m: *const MapVal, kd: KeyDesc, vd: ValDesc, out: *mut VecVal);
    pub fn msrt_map_merge(m: *mut MapVal, other: *const MapVal, kd: KeyDesc, vd: ValDesc);
    pub fn msrt_map_add_table(m: *mut MapVal, kd: KeyDesc, vd: ValDesc, table: *const StrVal);
    pub fn msrt_set_add_copy(m: *mut MapVal, kd: KeyDesc, key: *const u8);
    pub fn msrt_set_add_copy_w(m: *mut MapVal, kd: KeyDesc, key: *const u8);
    pub fn msrt_set_union(a: *const MapVal, b: *const MapVal, kd: KeyDesc, out: *mut MapVal);
    pub fn msrt_set_intersection(a: *const MapVal, b: *const MapVal, kd: KeyDesc, out: *mut MapVal);
    pub fn msrt_set_difference(a: *const MapVal, b: *const MapVal, kd: KeyDesc, out: *mut MapVal);
    pub fn msrt_set_symmetric_difference(
        a: *const MapVal,
        b: *const MapVal,
        kd: KeyDesc,
        out: *mut MapVal,
    );
    pub fn msrt_set_is_subset_of(a: *const MapVal, b: *const MapVal, kd: KeyDesc) -> u8;
    pub fn msrt_set_is_superset_of(a: *const MapVal, b: *const MapVal, kd: KeyDesc) -> u8;
    pub fn msrt_set_is_disjoint_from(a: *const MapVal, b: *const MapVal, kd: KeyDesc) -> u8;
}

/// Top bit of a slot's hash word: set for a live entry, clear for a removed one.
pub(crate) const LIVE: u64 = 1 << 63;

#[derive(Clone, Copy)]
pub(crate) struct Layout {
    pub koff: usize,
    pub voff: usize,
    pub stride: usize,
}

fn align_up(n: usize, a: usize) -> usize {
    (n + a - 1) & !(a - 1)
}

/// True for an 8-byte, 8-aligned slot (one load and compare of the descriptor's size and align).
#[inline(always)]
pub(crate) fn is_word(d: &TypeDesc) -> bool {
    (u64::from(d.size) | u64::from(d.align) << 32) == 8 | 8 << 32
}

#[inline(always)]
pub(crate) fn layout(kd: &TypeDesc, vd: Option<&TypeDesc>) -> Layout {
    // 8-byte, 8-aligned keys and values (Int, Float, pointers) are the common case; a constant
    // layout spares the alignment arithmetic on every lookup.
    if is_word(kd) && vd.is_some_and(is_word) {
        return Layout {
            koff: 8,
            voff: 16,
            stride: 24,
        };
    }
    // Word-multiple slots (a `String` is two words) need only additions.
    let (ks, ka) = (kd.size as usize, kd.align);
    if ka == 8 && ks % 8 == 0 {
        match vd {
            Some(v) if v.align == 8 && v.size % 8 == 0 => {
                let vs = v.size as usize;
                return Layout {
                    koff: 8,
                    voff: 8 + ks,
                    stride: 8 + ks + vs,
                };
            }
            None => {
                return Layout {
                    koff: 8,
                    voff: 8 + ks,
                    stride: 8 + ks,
                };
            }
            _ => {}
        }
    }
    layout_general(kd, vd)
}

pub(crate) fn layout_general(kd: &TypeDesc, vd: Option<&TypeDesc>) -> Layout {
    let ka = (kd.align as usize).max(8);
    let koff = align_up(8, ka);
    let ksize = kd.size as usize;
    let (va, vsize) = vd.map_or((1, 0), |v| ((v.align as usize).max(1), v.size as usize));
    let voff = align_up(koff + ksize, va);
    let stride = align_up(voff + vsize, ka.max(va).max(8));
    Layout { koff, voff, stride }
}

/// The layout of a map of string keys and `vd` values.
pub(crate) fn string_map_layout(vd: &TypeDesc) -> Layout {
    layout(&crate::desc::msrt_desc_string, Some(vd))
}

pub(crate) fn empty() -> MapVal {
    MapVal {
        desc: core::ptr::null(),
        slots: core::ptr::null_mut(),
        index: core::ptr::null_mut(),
        len: 0,
        used: 0,
        cap: 0,
        mask: 0,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_empty_map_is_all_zero_words() {
        // Generated code builds `ExternRole::MapNew` as zero words instead of calling the runtime.
        let m = empty();
        // SAFETY: `MapVal` is `repr(C)` plain words.
        let words: [usize; MAP_SIZE / 8] = unsafe { core::mem::transmute(m) };
        assert!(words.iter().all(|w| *w == 0));
    }
}
