//! `Map[K, V]` and `Set[T]`: insertion-ordered hash tables stored as `MapVal`.
//!
//! `slots` is an append-only array of entries `{ hash: u64 (top bit set = live), key, value }`
//! spaced `stride` bytes apart; `index` is an open-addressing table of `u64` entries: the
//! high word is the hash's high word (a tag, so probes skip non-matching slots without touching
//! them) and the low word is the slot number (`0` empty, `u32::MAX` removed, otherwise slot + 1). Removal leaves a hole that scans
//! skip and compaction reclaims once more than half the slots are holes.
//! ms: domain map
use crate::alloc;
use crate::desc::{needs_no_drop, slot_copy, slot_drop, slot_eq, slot_hash};
use crate::fault;
use crate::string::{self, bytes, equal, hash_bytes, hash_int};
use ms_rt_abi::record::FaultKind;
use ms_rt_abi::*;

const REMOVED: u64 = u32::MAX as u64;

/// Top bit of a slot's hash word: set for a live entry, clear for a removed one.
pub const LIVE: u64 = 1 << 63;

#[inline(always)]
fn index_of(m: &MapVal) -> *mut u64 {
    m.index as *mut u64
}

#[inline(always)]
unsafe fn slot_hash_of(p: *const u8) -> u64 {
    // SAFETY: slots start with the hash word.
    unsafe { *(p as *const u64) }
}

/// Slot of the `Int` key at `key` in a map whose values are 8 bytes, 8-aligned (stride 24), or
/// null. The shape of most counters and indexes; it needs no descriptor dispatch.
#[inline(always)]
pub unsafe fn find_w8(m: &MapVal, key: *const u8) -> *const u8 {
    if m.len == 0 {
        return core::ptr::null();
    }
    // SAFETY: caller contract; index and slots are consistent for a non-empty map.
    unsafe {
        let k = *(key as *const u64);
        let h = hash_int(k) | LIVE;
        let index = index_of(m);
        let mut pos = (h as usize ^ (h >> 32) as usize) & m.mask;
        loop {
            let e = *index.add(pos);
            if e == 0 {
                return core::ptr::null();
            }
            if (e ^ h) >> 32 == 0 {
                let p = m.slots.add((e as u32 - 1) as usize * 24);
                if *(p.add(8) as *const u64) == k {
                    return p;
                }
            }
            pos = (pos + 1) & m.mask;
        }
    }
}

/// Stride of a `String`-keyed slot with an 8-byte value: hash, key, value.
pub const SW8_STRIDE: usize = 8 + ms_rt_abi::STR_SIZE + 8;
/// Offset of the value in such a slot.
pub const SW8_VALUE: usize = 8 + ms_rt_abi::STR_SIZE;

/// [`find_w8`] for a `String` key: slot of the entry, or null.
#[inline(always)]
pub unsafe fn find_sw8(m: &MapVal, key: *const u8) -> *const u8 {
    if m.len == 0 {
        return core::ptr::null();
    }
    // SAFETY: caller contract; index and slots are consistent for a non-empty map, and the key
    // slot holds a live string.
    unsafe {
        let k = key as *const StrVal;
        let h = hash_bytes(bytes(k)) | LIVE;
        let index = index_of(m);
        let mut pos = (h as usize ^ (h >> 32) as usize) & m.mask;
        loop {
            let e = *index.add(pos);
            if e == 0 {
                return core::ptr::null();
            }
            if (e ^ h) >> 32 == 0 {
                let p = m.slots.add((e as u32 - 1) as usize * SW8_STRIDE);
                if slot_hash_of(p) == h && equal(p.add(8) as *const StrVal, k) {
                    return p;
                }
            }
            pos = (pos + 1) & m.mask;
        }
    }
}

/// `get_ptr` for a `String` key and an 8-byte, 8-aligned value: the value's address or null. The
/// descriptors are accepted for signature parity with the generic entry point and ignored.
#[unsafe(no_mangle)]
// ms: leaf pure
pub unsafe extern "C-unwind" fn msrt_map_get_ptr_sw8(
    m: *const MapVal,
    _kd: KeyDesc,
    _vd: ValDesc,
    key: *const u8,
) -> *const u8 {
    // SAFETY: caller contract.
    unsafe {
        let p = find_sw8(&*m, key);
        if p.is_null() {
            core::ptr::null()
        } else {
            p.add(SW8_VALUE)
        }
    }
}

/// `contains` for a `String` key and an 8-byte, 8-aligned value.
#[unsafe(no_mangle)]
// ms: leaf pure
pub unsafe extern "C-unwind" fn msrt_map_contains_sw8(
    m: *const MapVal,
    _kd: KeyDesc,
    _vd: ValDesc,
    key: *const u8,
) -> u8 {
    // SAFETY: caller contract.
    unsafe { !find_sw8(&*m, key).is_null() as u8 }
}

/// `get` for a `String` key and a plain 8-byte scalar value (`Int` or `Float`).
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_map_get_sw8(
    m: *const MapVal,
    _kd: KeyDesc,
    _vd: ValDesc,
    key: *const u8,
    out: *mut u8,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let p = find_sw8(&*m, key);
        if p.is_null() {
            return 0;
        }
        core::ptr::copy_nonoverlapping(p.add(SW8_VALUE), out, 8);
        1
    }
}

/// `get_ptr` for an `Int` key and an 8-byte, 8-aligned value. The call site checked the shape;
/// the descriptors are accepted for signature parity and ignored.
#[unsafe(no_mangle)]
// ms: leaf pure
pub unsafe extern "C-unwind" fn msrt_map_get_ptr_w8(
    m: *const MapVal,
    _kd: KeyDesc,
    _vd: ValDesc,
    key: *const u8,
) -> *const u8 {
    // SAFETY: caller contract.
    unsafe {
        let p = find_w8(&*m, key);
        if p.is_null() {
            core::ptr::null()
        } else {
            p.add(16)
        }
    }
}

/// `contains` for an `Int` key and an 8-byte, 8-aligned value.
#[unsafe(no_mangle)]
// ms: leaf pure
pub unsafe extern "C-unwind" fn msrt_map_contains_w8(
    m: *const MapVal,
    _kd: KeyDesc,
    _vd: ValDesc,
    key: *const u8,
) -> u8 {
    // SAFETY: caller contract.
    unsafe { !find_w8(&*m, key).is_null() as u8 }
}

/// Slot of the `Int` key at `key` in a `Set[Int]` (slots of a hash word and the key, stride 16),
/// or null: [`find_w8`] without a value.
#[inline(always)]
pub unsafe fn find_set_w(m: &MapVal, key: *const u8) -> *const u8 {
    if m.len == 0 {
        return core::ptr::null();
    }
    // SAFETY: caller contract; index and slots are consistent for a non-empty map.
    unsafe {
        let k = *(key as *const u64);
        let h = hash_int(k) | LIVE;
        let index = index_of(m);
        let mut pos = (h as usize ^ (h >> 32) as usize) & m.mask;
        loop {
            let e = *index.add(pos);
            if e == 0 {
                return core::ptr::null();
            }
            if (e ^ h) >> 32 == 0 {
                let p = m.slots.add((e as u32 - 1) as usize * 16);
                if *(p.add(8) as *const u64) == k {
                    return p;
                }
            }
            pos = (pos + 1) & m.mask;
        }
    }
}

/// `contains` for a `Set[Int]`.
#[unsafe(no_mangle)]
// ms: leaf pure domain=set
pub unsafe extern "C-unwind" fn msrt_set_contains_w(
    m: *const MapVal,
    _kd: KeyDesc,
    _vd: ValDesc,
    key: *const u8,
) -> u8 {
    // SAFETY: caller contract.
    unsafe { !find_set_w(&*m, key).is_null() as u8 }
}

/// `get` for an `Int` key and a plain 8-byte scalar value (`Int` or `Float`).
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_map_get_w8(
    m: *const MapVal,
    _kd: KeyDesc,
    _vd: ValDesc,
    key: *const u8,
    out: *mut u8,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let p = find_w8(&*m, key);
        if p.is_null() {
            return 0;
        }
        core::ptr::copy_nonoverlapping(p.add(16), out, 8);
        1
    }
}

/// `length()`: the number of live entries.
#[unsafe(no_mangle)]
// ms: leaf pure
pub unsafe extern "C-unwind" fn msrt_map_length(m: *const MapVal) -> i64 {
    // SAFETY: caller contract.
    unsafe { (*m).len as i64 }
}

/// Number of slots to scan with `msrt_map_entry_ptrs` (live entries plus holes).
#[unsafe(no_mangle)]
// ms: leaf pure
pub unsafe extern "C-unwind" fn msrt_map_slot_count(m: *const MapVal) -> i64 {
    // SAFETY: caller contract.
    unsafe { (*m).used as i64 }
}

// Slot layout from type descriptors (read-only static data)

#[derive(Clone, Copy)]
pub struct Layout {
    pub koff: usize,
    pub voff: usize,
    pub stride: usize,
    pub ksize: usize,
    pub vsize: usize,
}

pub fn align_up(n: usize, a: usize) -> usize {
    (n + a - 1) & !(a - 1)
}

/// True for an 8-byte, 8-aligned slot (one load and compare of the descriptor's size and align).
#[inline(always)]
pub fn is_word(d: &TypeDesc) -> bool {
    (u64::from(d.size) | u64::from(d.align) << 32) == 8 | 8 << 32
}

#[inline(always)]
pub fn layout(kd: &TypeDesc, vd: Option<&TypeDesc>) -> Layout {
    // 8-byte, 8-aligned keys and values (Int, Float, pointers) are the common case; a constant
    // layout spares the alignment arithmetic on every lookup.
    if is_word(kd) && vd.is_some_and(is_word) {
        return Layout {
            koff: 8,
            voff: 16,
            stride: 24,
            ksize: 8,
            vsize: 8,
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
                    ksize: ks,
                    vsize: vs,
                };
            }
            None => {
                return Layout {
                    koff: 8,
                    voff: 8 + ks,
                    stride: 8 + ks,
                    ksize: ks,
                    vsize: 0,
                };
            }
            _ => {}
        }
    }
    layout_general(kd, vd)
}

pub fn layout_general(kd: &TypeDesc, vd: Option<&TypeDesc>) -> Layout {
    let ka = (kd.align as usize).max(8);
    let koff = align_up(8, ka);
    let ksize = kd.size as usize;
    let (va, vsize) = vd.map_or((1, 0), |v| ((v.align as usize).max(1), v.size as usize));
    let voff = align_up(koff + ksize, va);
    let stride = align_up(voff + vsize, ka.max(va).max(8));
    Layout {
        koff,
        voff,
        stride,
        ksize,
        vsize,
    }
}

#[inline(always)]
pub unsafe fn slot(m: &MapVal, l: &Layout, i: usize) -> *mut u8 {
    // SAFETY: `i < used`.
    unsafe { m.slots.add(i * l.stride) }
}

/// The descriptor a map was created with, else the caller's: a collection keeps the
/// `Equal` and `Hashable` of the module that made it.
///
/// `m` is a live map, as every exported operation requires.
// Callers are the exported operations, which require a live map; the same contract as `ms-rt`'s own.
#[allow(clippy::not_unsafe_ptr_arg_deref)]
pub fn key_desc(m: *const MapVal, kd: *const TypeDesc) -> *const TypeDesc {
    // SAFETY: exported operations are only called with live maps.
    let own = unsafe { (*m).desc };
    if own.is_null() { kd } else { own }
}

/// Borrowed pointers to the key and value of slot `i`; 0 for a hole.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_map_entry_ptrs(
    m: *const MapVal,
    kd: KeyDesc,
    vd: ValDesc,
    i: i64,
    key_out: *mut *const u8,
    val_out: *mut *const u8,
) -> u8 {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract.
    unsafe {
        let m = &*m;
        let l = layout(&*kd, opt(vd));
        let p = slot(m, &l, i as usize);
        if slot_hash_of(p) & LIVE == 0 {
            return 0;
        }
        *key_out = p.add(l.koff);
        if !val_out.is_null() {
            *val_out = p.add(l.voff);
        }
        1
    }
}

#[inline(always)]
fn entry(h: u64, slot: usize) -> u64 {
    (h & !0xFFFF_FFFF) | (slot as u64 + 1)
}

pub fn empty() -> MapVal {
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

/// `copy_nonoverlapping` with the common slot sizes (a word up to ten) inline, so a small slot
/// is a few moves instead of a `memcpy` call. A byte copy keeps the provenance of pointer slots,
/// which an integer load and store would drop.
#[inline(always)]
unsafe fn copy_slot(src: *const u8, dst: *mut u8, n: usize) {
    // SAFETY: caller contract of `copy_nonoverlapping`.
    unsafe {
        match n {
            8 => core::ptr::copy_nonoverlapping(src, dst, 8),
            16 => core::ptr::copy_nonoverlapping(src, dst, 16),
            24 => core::ptr::copy_nonoverlapping(src, dst, 24),
            32 => core::ptr::copy_nonoverlapping(src, dst, 32),
            40 => core::ptr::copy_nonoverlapping(src, dst, 40),
            48 => core::ptr::copy_nonoverlapping(src, dst, 48),
            56 => core::ptr::copy_nonoverlapping(src, dst, 56),
            64 => core::ptr::copy_nonoverlapping(src, dst, 64),
            72 => core::ptr::copy_nonoverlapping(src, dst, 72),
            80 => core::ptr::copy_nonoverlapping(src, dst, 80),
            _ => core::ptr::copy_nonoverlapping(src, dst, n),
        }
    }
}

/// [`layout`] for a key kind that is known to be a word, which skips testing the key.
#[inline(always)]
fn layout_k<K: KeyOps>(kd: &TypeDesc, vd: Option<&TypeDesc>) -> Layout {
    if K::WORD_KEY && vd.is_some_and(is_word) {
        return Layout {
            koff: 8,
            voff: 16,
            stride: 24,
            ksize: 8,
            vsize: 8,
        };
    }
    // A word-multiple key and a value aligned to at most a word: the entry is the hash word, the
    // key, then the value padded to a word (what `layout` computes, without reading the key's
    // descriptor).
    if K::KEY_SIZE != 0
        && let Some(v) = vd
        && v.align <= 8
    {
        let voff = 8 + K::KEY_SIZE;
        let vsize = v.size as usize;
        return Layout {
            koff: 8,
            voff,
            stride: (voff + vsize + 7) & !7,
            ksize: K::KEY_SIZE,
            vsize,
        };
    }
    layout(kd, vd)
}

/// Hash, equality and ownership of one key type, resolved once per call by [`keyed!`] so that
/// each key kind gets its own inlined probe loop. `Dyn` is the descriptor-driven fallback for
/// every other key type.
trait KeyOps {
    /// True when key equality is cheap enough to skip the stored full-hash comparison.
    const CHEAP_EQ: bool = false;
    /// True when the key slot is always an 8-byte, 8-aligned word.
    const WORD_KEY: bool = false;
    /// The size of a key slot that is always a multiple of 8 and 8-aligned (an `Int` word, a
    /// two-word `String`), or 0 for a key whose layout comes from its descriptor.
    const KEY_SIZE: usize = 0;
    /// Hash of the key slot (without the `LIVE` bit).
    unsafe fn hash(kd: &TypeDesc, key: *const u8) -> u64;
    /// Equality of two live key slots.
    unsafe fn eq(kd: &TypeDesc, stored: *const u8, key: *const u8) -> bool;
}

struct IntKey;
struct StrKey;
struct DynKey;
/// A key of plain bits without padding (`KIND_POD` with no `eq`/`hash` glue, see
/// `Cx::ensure_glue`): equal iff the `kd.size` bytes are equal.
struct BlobKey;

impl KeyOps for IntKey {
    const CHEAP_EQ: bool = true;
    const WORD_KEY: bool = true;
    const KEY_SIZE: usize = 8;
    #[inline(always)]
    unsafe fn hash(_: &TypeDesc, key: *const u8) -> u64 {
        // SAFETY: the key slot holds an `Int`.
        unsafe { crate::string::hash_int(*(key as *const u64)) }
    }
    #[inline(always)]
    unsafe fn eq(_: &TypeDesc, a: *const u8, b: *const u8) -> bool {
        // SAFETY: both slots hold an `Int`.
        unsafe { *(a as *const i64) == *(b as *const i64) }
    }
}

impl KeyOps for StrKey {
    const KEY_SIZE: usize = STR_SIZE;
    #[inline(always)]
    unsafe fn hash(_: &TypeDesc, key: *const u8) -> u64 {
        // SAFETY: the key slot holds a live string.
        unsafe { crate::string::hash_bytes(crate::string::bytes(key as *const StrVal)) }
    }
    #[inline(always)]
    unsafe fn eq(_: &TypeDesc, a: *const u8, b: *const u8) -> bool {
        // SAFETY: both slots hold live strings. A lookup of an inserted key hits the same object.
        unsafe { crate::string::equal(a as *const StrVal, b as *const StrVal) }
    }
}

impl KeyOps for BlobKey {
    const CHEAP_EQ: bool = true;
    #[inline(always)]
    unsafe fn hash(kd: &TypeDesc, key: *const u8) -> u64 {
        let n = kd.size as usize;
        // SAFETY: the key slot holds `n` initialized bytes.
        unsafe {
            if !n.is_multiple_of(8) {
                return crate::string::hash_bytes(core::slice::from_raw_parts(key, n));
            }
            let mut h = 0x9e37_79b9_7f4a_7c15u64;
            for i in 0..n / 8 {
                h = crate::string::mix(h ^ (key as *const u64).add(i).read_unaligned());
            }
            h
        }
    }
    #[inline(always)]
    unsafe fn eq(kd: &TypeDesc, a: *const u8, b: *const u8) -> bool {
        let n = kd.size as usize;
        // SAFETY: both slots hold `n` initialized bytes.
        unsafe { core::slice::from_raw_parts(a, n) == core::slice::from_raw_parts(b, n) }
    }
}

impl KeyOps for DynKey {
    #[inline(always)]
    unsafe fn hash(kd: &TypeDesc, key: *const u8) -> u64 {
        // SAFETY: the key slot is live. A user `hash()` is often the identity of a couple of
        // small ints (`x * 31 + y`) whose runs of consecutive values would cluster under linear
        // probing, so the table sees a mixed hash.
        unsafe { crate::string::hash_int(slot_hash(kd, key)) }
    }
    #[inline(always)]
    unsafe fn eq(kd: &TypeDesc, a: *const u8, b: *const u8) -> bool {
        // SAFETY: both are live key slots of `kd`.
        unsafe { slot_eq(kd, a, b) }
    }
}

/// Runs `$body` with `$K` bound to the [`KeyOps`] of `$kd`'s key kind.
macro_rules! keyed {
    ($kd:expr, |$K:ident| $body:expr) => {
        match $kd.kind {
            KIND_INT => {
                type $K = IntKey;
                $body
            }
            KIND_STRING => {
                type $K = StrKey;
                $body
            }
            KIND_POD if $kd.eq.is_none() && $kd.hash.is_none() => {
                type $K = BlobKey;
                $body
            }
            _ => {
                type $K = DynKey;
                $body
            }
        }
    };
}

#[inline(always)]
unsafe fn hash_key<K: KeyOps>(kd: &TypeDesc, key: *const u8) -> u64 {
    // SAFETY: the key slot is live.
    unsafe { K::hash(kd, key) | LIVE }
}

/// Finds the slot index of `key`.
#[inline(always)]
unsafe fn find<K: KeyOps>(
    m: &MapVal,
    kd: &TypeDesc,
    l: &Layout,
    key: *const u8,
    h: u64,
) -> Option<usize> {
    if m.len == 0 {
        return None;
    }
    // SAFETY: index and slots are consistent for a non-empty map.
    unsafe {
        let index = index_of(m);
        let mut pos = (h as usize ^ (h >> 32) as usize) & m.mask;
        loop {
            let e = *index.add(pos);
            if e == 0 {
                return None;
            }
            if (e ^ h) >> 32 == 0 {
                let i = (e as u32 - 1) as usize;
                let p = slot(m, l, i);
                if (K::CHEAP_EQ || slot_hash_of(p) == h) && K::eq(kd, p.add(l.koff), key) {
                    return Some(i);
                }
            }
            pos = (pos + 1) & m.mask;
        }
    }
}

/// The slot holding `key`, or null.
#[inline(always)]
unsafe fn find_slot<K: KeyOps>(
    m: &MapVal,
    kd: &TypeDesc,
    vd: Option<&TypeDesc>,
    key: *const u8,
) -> *mut u8 {
    if m.len == 0 {
        return core::ptr::null_mut();
    }
    // SAFETY: caller contract.
    unsafe {
        // Key dispatch already established the word size/alignment. Sets have no value
        // descriptor, so their slot layout is fixed without reading the key descriptor again.
        let l = if K::WORD_KEY && vd.is_none() {
            Layout {
                koff: 8,
                voff: 16,
                stride: 16,
                ksize: 8,
                vsize: 0,
            }
        } else {
            layout(kd, vd)
        };
        match find::<K>(m, kd, &l, key, hash_key::<K>(kd, key)) {
            Some(i) => slot(m, &l, i),
            None => core::ptr::null_mut(),
        }
    }
}

unsafe fn rebuild_index(m: &mut MapVal, l: &Layout, index_size: usize) {
    // SAFETY: allocates and fills a fresh zeroed index.
    unsafe {
        if !m.index.is_null() {
            alloc::free(m.index as *mut u8);
        }
        m.index = alloc::alloc_zeroed(index_size * 8) as *mut u32;
        m.mask = index_size - 1;
        for i in 0..m.used {
            let p = slot(m, l, i);
            let h = slot_hash_of(p);
            if h & LIVE == 0 {
                continue;
            }
            let mut pos = (h as usize ^ (h >> 32) as usize) & m.mask;
            while *index_of(m).add(pos) != 0 {
                pos = (pos + 1) & m.mask;
            }
            *index_of(m).add(pos) = entry(h, i);
        }
    }
}

/// Drops holes from the slot array (moving live slots down) and rebuilds the index.
unsafe fn compact(m: &mut MapVal, l: &Layout) {
    // SAFETY: moves live slots over holes in order.
    unsafe {
        let mut out = 0;
        for i in 0..m.used {
            let p = slot(m, l, i);
            if slot_hash_of(p) & LIVE != 0 {
                if out != i {
                    core::ptr::copy_nonoverlapping(p, slot(m, l, out), l.stride);
                }
                out += 1;
            }
        }
        m.used = out;
        // After a large drop (capacity at least four times what the live entries need) slots and
        // index shrink together, so the cost of the next compaction follows the working size
        // rather than the historical peak. The factor keeps a map that churns near its size from
        // shrinking and regrowing; only this path changes capacity, and the insert checks are
        // untouched.
        let cap = (m.len * 2).next_power_of_two().max(8);
        if cap <= m.cap / 4 {
            m.slots = alloc::realloc(m.slots, cap * l.stride);
            m.cap = cap;
        }
        rebuild_index(m, l, m.cap * 2);
    }
}

unsafe fn grow(m: &mut MapVal, l: &Layout) {
    // SAFETY: standard doubling of slots and index.
    unsafe {
        if m.used > 0 && m.len * 2 <= m.used && m.cap > 0 {
            compact(m, l);
            return;
        }
        let cap = if m.cap == 0 { 8 } else { m.cap * 2 };
        if cap > u32::MAX as usize / 2 {
            fault::fault_kind(FaultKind::Overflow, b"map size overflow");
        }
        m.slots = if m.slots.is_null() {
            alloc::alloc(cap * l.stride)
        } else {
            alloc::realloc(m.slots, cap * l.stride)
        };
        m.cap = cap;
        rebuild_index(m, l, cap * 2);
    }
}

/// Number of live entries.
pub fn len(m: &MapVal) -> usize {
    m.len
}

/// True if `key` is present (`key` borrowed).
pub unsafe fn contains_key(
    m: &MapVal,
    kd: &TypeDesc,
    vd: Option<&TypeDesc>,
    key: *const u8,
) -> bool {
    // SAFETY: key slot live.
    unsafe { !keyed!(kd, |K| find_slot::<K>(m, kd, vd, key)).is_null() }
}

/// Inserts a new entry, consuming `key` and `val` (both slots are moved bitwise). If the key
/// exists the supplied key is dropped and the value replaced in place (position kept).
/// Returns true when the entry is new.
///
/// # Safety
/// Slots are live values of the descriptors; `val` may be null for sets.
#[inline(never)]
pub unsafe fn insert(
    m: &mut MapVal,
    kd: &TypeDesc,
    vd: Option<&TypeDesc>,
    key: *mut u8,
    val: *mut u8,
) -> bool {
    // SAFETY: caller contract.
    unsafe { keyed!(kd, |K| insert_k::<K>(m, kd, vd, key, val)) }
}

#[inline(always)]
unsafe fn insert_k<K: KeyOps>(
    m: &mut MapVal,
    kd: &TypeDesc,
    vd: Option<&TypeDesc>,
    key: *mut u8,
    val: *mut u8,
) -> bool {
    // SAFETY: caller contract.
    unsafe { upsert_k::<K>(m, kd, vd, key, val, true).1 }
}

/// Finds `key` or appends it with `val`, consuming `key` (and `val` unless an existing value is
/// kept). Returns the value slot and whether the entry is new. With `replace` an existing value
/// is overwritten by `val`; without it the existing value stays and `val` is not consumed.
#[inline(always)]
unsafe fn upsert_k<K: KeyOps>(
    m: &mut MapVal,
    kd: &TypeDesc,
    vd: Option<&TypeDesc>,
    key: *mut u8,
    val: *mut u8,
    replace: bool,
) -> (*mut u8, bool) {
    // SAFETY: caller contract.
    unsafe {
        let l = layout_k::<K>(kd, vd);
        let h = hash_key::<K>(kd, key);
        if let Some(i) = find::<K>(m, kd, &l, key, h) {
            let p = slot(m, &l, i);
            if !needs_no_drop(kd) {
                slot_drop(kd, key);
            }
            if replace && let Some(vd) = vd {
                if !needs_no_drop(vd) {
                    slot_drop(vd, p.add(l.voff));
                }
                copy_slot(val, p.add(l.voff), l.vsize);
            }
            return (p.add(l.voff), false);
        }
        if m.used == m.cap {
            grow(m, &l);
        }
        let p = slot(m, &l, m.used);
        *(p as *mut u64) = h;
        copy_slot(key, p.add(l.koff), l.ksize);
        if vd.is_some() {
            copy_slot(val, p.add(l.voff), l.vsize);
        }
        let mut pos = (h as usize ^ (h >> 32) as usize) & m.mask;
        loop {
            let e = *index_of(m).add(pos);
            if e == 0 || e == REMOVED {
                break;
            }
            pos = (pos + 1) & m.mask;
        }
        *index_of(m).add(pos) = entry(h, m.used);
        m.used += 1;
        m.len += 1;
        (p.add(l.voff), true)
    }
}

/// The layout of a map of string keys and `vd` values, for [`fill_strings`].
pub fn string_map_layout(vd: &TypeDesc) -> Layout {
    layout(&crate::desc::msrt_desc_string, Some(vd))
}

/// Fills the empty map `m` with `n` members whose keys are `keys[i]` (strings) and whose values sit
/// `stride` bytes apart from `vals`, consuming them all. It is `n` inserts of fresh keys with the
/// layout given once, room for exactly `n` allocated up front, and one probe per member that finds
/// a repeated key and the free index entry together. On a repeated key at position `i`, members
/// `0..i` are in the map and the caller still owns members `i..n`; the position is returned.
///
/// # Safety
/// `m` is an empty map with no storage; `l` is [`string_map_layout`] of the value type;
/// `keys[..n]` and the values are live slots of `msrt_desc_string` and that type.
pub unsafe fn fill_strings(
    m: &mut MapVal,
    l: &Layout,
    keys: *mut StrVal,
    vals: *mut u8,
    stride: usize,
    n: usize,
) -> Result<(), usize> {
    if n == 0 {
        return Ok(());
    }
    let kd = &crate::desc::msrt_desc_string;
    // SAFETY: `m` is a map of string keys; slots are live per the contract.
    unsafe {
        let cap = n.next_power_of_two().max(2);
        m.slots = alloc::alloc(cap * l.stride);
        m.cap = cap;
        m.index = alloc::alloc_zeroed(cap * 2 * 8) as *mut u32;
        m.mask = cap * 2 - 1;
        let index = index_of(m);
        for i in 0..n {
            let key = keys.add(i);
            let val = vals.add(i * stride);
            let h = hash_key::<StrKey>(kd, key.cast());
            let mut pos = (h as usize ^ (h >> 32) as usize) & m.mask;
            loop {
                let e = *index.add(pos);
                if e == 0 {
                    break;
                }
                if (e ^ h) >> 32 == 0 {
                    let p = slot(m, l, (e as u32 - 1) as usize);
                    if slot_hash_of(p) == h && StrKey::eq(kd, p.add(l.koff), key.cast()) {
                        return Err(i);
                    }
                }
                pos = (pos + 1) & m.mask;
            }
            let p = slot(m, l, m.used);
            *(p as *mut u64) = h;
            copy_slot(key.cast(), p.add(l.koff), l.ksize);
            copy_slot(val, p.add(l.voff), l.vsize);
            *index.add(pos) = entry(h, m.used);
            m.used += 1;
            m.len += 1;
        }
    }
    Ok(())
}

/// Inserts only if the key is absent (`key`/`val` consumed either way); returns true when inserted.
pub unsafe fn insert_unique(
    m: &mut MapVal,
    kd: &TypeDesc,
    vd: Option<&TypeDesc>,
    key: *mut u8,
    val: *mut u8,
) -> bool {
    // SAFETY: caller contract.
    unsafe {
        if contains_key(m, kd, vd, key) {
            slot_drop(kd, key);
            if let Some(vd) = vd {
                slot_drop(vd, val);
            }
            return false;
        }
        insert(m, kd, vd, key, val)
    }
}

/// Removes `key` (borrowed); drops the stored key and value. Returns true if present.
pub unsafe fn remove(m: &mut MapVal, kd: &TypeDesc, vd: Option<&TypeDesc>, key: *const u8) -> bool {
    // SAFETY: caller contract.
    unsafe { keyed!(kd, |K| remove_k::<K>(m, kd, vd, key)) }
}

#[inline(always)]
unsafe fn remove_k<K: KeyOps>(
    m: &mut MapVal,
    kd: &TypeDesc,
    vd: Option<&TypeDesc>,
    key: *const u8,
) -> bool {
    // SAFETY: caller contract.
    unsafe {
        let l = layout(kd, vd);
        let h = hash_key::<K>(kd, key);
        let Some(i) = find::<K>(m, kd, &l, key, h) else {
            return false;
        };
        let p = slot(m, &l, i);
        // Mark the index entry removed.
        let mut pos = (h as usize ^ (h >> 32) as usize) & m.mask;
        while *index_of(m).add(pos) != entry(h, i) {
            pos = (pos + 1) & m.mask;
        }
        *index_of(m).add(pos) = REMOVED;
        slot_drop(kd, p.add(l.koff));
        if let Some(vd) = vd {
            slot_drop(vd, p.add(l.voff));
        }
        *(p as *mut u64) = 0;
        m.len -= 1;
        if m.used > 32 && m.len < m.used / 2 {
            compact(m, &l);
        }
        true
    }
}

unsafe fn lookup(
    m: &MapVal,
    kd: &TypeDesc,
    vd: Option<&TypeDesc>,
    key: *const u8,
) -> Option<*mut u8> {
    // SAFETY: caller contract.
    unsafe {
        let p = keyed!(kd, |K| find_slot::<K>(m, kd, vd, key));
        (!p.is_null()).then_some(p)
    }
}

/// Drops all entries and storage.
///
/// # Safety
/// `m` is a live map of the descriptors.
pub unsafe fn drop_map(m: *mut MapVal, kd: &TypeDesc, vd: Option<&TypeDesc>) {
    // SAFETY: caller contract.
    unsafe {
        let m = &mut *m;
        if m.slots.is_null() {
            return;
        }
        let l = layout(kd, vd);
        let plain = crate::desc::needs_no_drop(kd) && vd.is_none_or(crate::desc::needs_no_drop);
        if !plain {
            // String keys are the common case: release them without descriptor dispatch.
            let strings = kd.kind == KIND_STRING;
            for i in 0..m.used {
                let p = slot(m, &l, i);
                if slot_hash_of(p) & LIVE != 0 {
                    if strings {
                        crate::string::release(&*(p.add(l.koff) as *const StrVal));
                    } else {
                        slot_drop(kd, p.add(l.koff));
                    }
                    if let Some(vd) = vd {
                        slot_drop(vd, p.add(l.voff));
                    }
                }
            }
        }
        alloc::free(m.slots);
        if !m.index.is_null() {
            alloc::free(m.index as *mut u8);
        }
        let desc = m.desc;
        *m = empty();
        m.desc = desc;
    }
}

/// Deep copy keeping order (holes dropped).
///
/// # Safety
/// `src` is a live map; `out` is uninitialised.
pub unsafe fn copy_map(src: *const MapVal, kd: &TypeDesc, vd: Option<&TypeDesc>, out: *mut MapVal) {
    // SAFETY: caller contract.
    unsafe {
        let s = &*src;
        let l = layout(kd, vd);
        let mut m = empty();
        m.desc = s.desc;
        if s.len > 0 {
            m.slots = alloc::alloc(s.len.next_power_of_two().max(8) * l.stride);
            m.cap = s.len.next_power_of_two().max(8);
            for i in 0..s.used {
                let p = slot(s, &l, i);
                let h = slot_hash_of(p);
                if h & LIVE == 0 {
                    continue;
                }
                let q = slot(&m, &l, m.used);
                *(q as *mut u64) = h;
                slot_copy(kd, p.add(l.koff), q.add(l.koff));
                if let Some(vd) = vd {
                    slot_copy(vd, p.add(l.voff), q.add(l.voff));
                }
                m.used += 1;
            }
            m.len = m.used;
            let isz = m.cap * 2;
            rebuild_index(&mut m, &l, isz);
        }
        *out = m;
    }
}

/// Order independent equality.
///
/// # Safety
/// Both are live maps of the descriptors.
pub unsafe fn eq_map(
    a: *const MapVal,
    b: *const MapVal,
    kd: &TypeDesc,
    vd: Option<&TypeDesc>,
) -> bool {
    // SAFETY: caller contract.
    unsafe {
        let (x, y) = (&*a, &*b);
        if x.len != y.len {
            return false;
        }
        // Probe the right-hand index with the identity that built it. A caller outside the
        // creator's module may have a different implementation, or no hashing glue at all.
        let kd = &*key_desc(b, kd);
        let l = layout(kd, vd);
        for i in 0..x.used {
            let p = slot(x, &l, i);
            if slot_hash_of(p) & LIVE == 0 {
                continue;
            }
            let Some(q) = lookup(y, kd, vd, p.add(l.koff)) else {
                return false;
            };
            if let Some(vd) = vd
                && !slot_eq(vd, p.add(l.voff), q.add(l.voff))
            {
                return false;
            }
        }
        true
    }
}

// ---------------------------------------------------------------------------
// Exported operations
// ---------------------------------------------------------------------------

fn opt<'a>(p: *const TypeDesc) -> Option<&'a TypeDesc> {
    // SAFETY: descriptors are static read-only data (or null).
    unsafe { p.as_ref() }
}

#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_map_new(out: *mut MapVal) {
    // SAFETY: `out` is writable.
    unsafe { *out = empty() }
}

/// Records creator evidence only for an unstamped collection. Native operations may already
/// return a copy or derived collection retaining its original creator.
/// `kd` and its nested descriptors and callbacks must be static.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_map_stamp(m: *mut MapVal, kd: KeyDesc) {
    // SAFETY: `m` is a live map; descriptors are static.
    unsafe {
        if (*m).desc.is_null() {
            (*m).desc = kd;
        }
    }
}

#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_map_drop(m: *mut MapVal, kd: KeyDesc, vd: ValDesc) {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract.
    unsafe { drop_map(m, &*kd, opt(vd)) }
}

#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_map_copy(
    m: *const MapVal,
    kd: KeyDesc,
    vd: ValDesc,
    out: *mut MapVal,
) {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract.
    unsafe { copy_map(m, &*kd, opt(vd), out) }
}

/// Makes room for `n` entries so that inserting that many never regrows the map.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_map_reserve(m: *mut MapVal, kd: KeyDesc, vd: ValDesc, n: i64) {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract.
    unsafe {
        let m = &mut *m;
        let n = usize::try_from(n).unwrap_or(0);
        if n <= m.cap || n > u32::MAX as usize / 2 {
            return;
        }
        let l = layout(&*kd, opt(vd));
        // Exact room: small objects dominate parsed documents, and `grow` doubles from here.
        let cap = n.next_power_of_two().max(2);
        m.slots = if m.slots.is_null() {
            alloc::alloc(cap * l.stride)
        } else {
            alloc::realloc(m.slots, cap * l.stride)
        };
        m.cap = cap;
        rebuild_index(m, &l, cap * 2);
    }
}

/// `add(key, value)` / `Set.add`: `key` and `val` are consumed.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_map_add(
    m: *mut MapVal,
    kd: KeyDesc,
    vd: ValDesc,
    key: *mut u8,
    val: *mut u8,
) {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract.
    unsafe {
        insert(&mut *m, &*kd, opt(vd), key, val);
    }
}

/// [`upsert_k`] for an `Int` (`ksize` 8) or `String` (`ksize` 16) key and a plain 8-byte scalar
/// value: the layout is fixed and a replaced value needs no drop, so the call site skips
/// descriptor dispatch.
#[inline(always)]
unsafe fn insert_word<K: KeyOps>(m: &mut MapVal, key: *mut u8, val: *mut u8, ksize: usize) {
    // SAFETY: caller contract; the key slot is a live key and `val` an 8-byte scalar.
    unsafe {
        let l = Layout {
            koff: 8,
            voff: 8 + ksize,
            stride: 16 + ksize,
            ksize,
            vsize: 8,
        };
        let kd = &crate::desc::msrt_desc_string; // ignored by the word key kinds
        let h = hash_key::<K>(kd, key);
        if let Some(i) = find::<K>(m, kd, &l, key, h) {
            let p = slot(m, &l, i);
            if !K::CHEAP_EQ {
                crate::string::release(&*(key as *const StrVal));
            }
            copy_slot(val, p.add(l.voff), 8);
            return;
        }
        if m.used == m.cap {
            grow(m, &l);
        }
        let p = slot(m, &l, m.used);
        *(p as *mut u64) = h;
        copy_slot(key, p.add(8), ksize);
        copy_slot(val, p.add(l.voff), 8);
        let mut pos = (h as usize ^ (h >> 32) as usize) & m.mask;
        loop {
            let e = *index_of(m).add(pos);
            if e == 0 || e == REMOVED {
                break;
            }
            pos = (pos + 1) & m.mask;
        }
        *index_of(m).add(pos) = entry(h, m.used);
        m.used += 1;
        m.len += 1;
    }
}

/// [`msrt_map_add`] for an `Int` key and a plain 8-byte scalar value (`Int` or `Float`).
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_map_add_w8(
    m: *mut MapVal,
    _kd: KeyDesc,
    _vd: ValDesc,
    key: *mut u8,
    val: *mut u8,
) {
    // SAFETY: caller contract.
    unsafe {
        // A map stamped with its module's key behaviour keeps the general path.
        if !(*m).desc.is_null() {
            return msrt_map_add(m, _kd, _vd, key, val);
        }
        insert_word::<IntKey>(&mut *m, key, val, 8)
    }
}

/// [`msrt_map_add`] for a `String` key and a plain 8-byte scalar value (`Int` or `Float`).
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_map_add_sw8(
    m: *mut MapVal,
    _kd: KeyDesc,
    _vd: ValDesc,
    key: *mut u8,
    val: *mut u8,
) {
    // SAFETY: caller contract.
    unsafe {
        // A map stamped with its module's key behaviour keeps the general path.
        if !(*m).desc.is_null() {
            return msrt_map_add(m, _kd, _vd, key, val);
        }
        insert_word::<StrKey>(&mut *m, key, val, STR_SIZE)
    }
}

/// The value slot of `key`, appending the entry with `default` when it is absent. `key` is only
/// borrowed: it is copied into the map when the entry is new, so a lookup that hits never allocates
/// a key. `default` is consumed either way: stored when the entry is new, dropped when it exists.
/// One hash and probe serve a read-modify-write: the caller reads and writes through the returned
/// pointer before the map is used again.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_map_slot_lent(
    m: *mut MapVal,
    kd: KeyDesc,
    vd: ValDesc,
    key: *const u8,
    default: *mut u8,
) -> *mut u8 {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract; the value type is an 8-byte scalar.
    unsafe {
        let (m, kd, vd) = (&mut *m, &*kd, &*vd);
        keyed!(kd, |K| {
            let l = layout(kd, Some(vd));
            let h = hash_key::<K>(kd, key);
            if let Some(i) = find::<K>(m, kd, &l, key, h) {
                if !needs_no_drop(vd) {
                    slot_drop(vd, default);
                }
                return slot(m, &l, i).add(l.voff);
            }
            // Absent: own a copy of the key and insert it.
            let owned = alloc::alloc((kd.size as usize).max(8));
            slot_copy(kd, key, owned);
            let at = upsert_k::<K>(m, kd, Some(vd), owned, default, false).0;
            alloc::free(owned);
            at
        })
    }
}

/// `add(key, value)` with a borrowed `key`: it is copied into the map only when the entry is
/// absent, so replacing the value of an existing key allocates nothing. `val` is consumed.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_map_add_lent(
    m: *mut MapVal,
    kd: KeyDesc,
    vd: ValDesc,
    key: *const u8,
    val: *mut u8,
) {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract.
    unsafe {
        let (m, kd, vd) = (&mut *m, &*kd, &*vd);
        keyed!(kd, |K| {
            let l = layout(kd, Some(vd));
            let h = hash_key::<K>(kd, key);
            if let Some(i) = find::<K>(m, kd, &l, key, h) {
                let p = slot(m, &l, i).add(l.voff);
                if !needs_no_drop(vd) {
                    slot_drop(vd, p);
                }
                copy_slot(val, p, l.vsize);
                return;
            }
            let owned = alloc::alloc((kd.size as usize).max(8));
            slot_copy(kd, key, owned);
            upsert_k::<K>(m, kd, Some(vd), owned, val, true);
            alloc::free(owned);
        })
    }
}

/// `add_default(key, value)` with a borrowed `key`: nothing is copied or stored when the entry
/// exists. `val` is consumed.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_map_add_default_lent(
    m: *mut MapVal,
    kd: KeyDesc,
    vd: ValDesc,
    key: *const u8,
    val: *mut u8,
) {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract.
    unsafe {
        let (m, kd, vd) = (&mut *m, &*kd, &*vd);
        keyed!(kd, |K| {
            let l = layout(kd, Some(vd));
            let h = hash_key::<K>(kd, key);
            if find::<K>(m, kd, &l, key, h).is_some() {
                if !needs_no_drop(vd) {
                    slot_drop(vd, val);
                }
                return;
            }
            let owned = alloc::alloc((kd.size as usize).max(8));
            slot_copy(kd, key, owned);
            upsert_k::<K>(m, kd, Some(vd), owned, val, true);
            alloc::free(owned);
        })
    }
}

/// `add_default(key, value)`: stores only when absent; both consumed.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_map_add_default(
    m: *mut MapVal,
    kd: KeyDesc,
    vd: ValDesc,
    key: *mut u8,
    val: *mut u8,
) {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract.
    unsafe {
        insert_unique(&mut *m, &*kd, opt(vd), key, val);
    }
}

#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_map_remove(
    m: *mut MapVal,
    kd: KeyDesc,
    vd: ValDesc,
    key: *const u8,
) {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract.
    unsafe {
        remove(&mut *m, &*kd, opt(vd), key);
    }
}

#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_map_contains(
    m: *const MapVal,
    kd: KeyDesc,
    vd: ValDesc,
    key: *const u8,
) -> u8 {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract.
    unsafe { contains_key(&*m, &*kd, opt(vd), key) as u8 }
}

/// Borrowed pointer to the value of `key`, or null.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_map_get_ptr(
    m: *const MapVal,
    kd: KeyDesc,
    vd: ValDesc,
    key: *const u8,
) -> *const u8 {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract.
    unsafe { value_ptr(&*m, &*kd, opt(vd), key) }
}

/// Borrowed pointer to the value of `key`, or null. Each key kind gets its own out-of-line probe
/// loop, so the hot Int and String paths keep a small frame.
#[inline(always)]
unsafe fn value_ptr(m: &MapVal, kd: &TypeDesc, vd: Option<&TypeDesc>, key: *const u8) -> *const u8 {
    // SAFETY: caller contract.
    unsafe { keyed!(kd, |K| value_ptr_k::<K>(m, kd, vd, key)) }
}

#[inline(never)]
unsafe fn value_ptr_k<K: KeyOps>(
    m: &MapVal,
    kd: &TypeDesc,
    vd: Option<&TypeDesc>,
    key: *const u8,
) -> *const u8 {
    if m.len == 0 {
        return core::ptr::null();
    }
    // SAFETY: caller contract; index and slots are consistent for a non-empty map.
    unsafe {
        let l = layout_k::<K>(kd, vd);
        match find::<K>(m, kd, &l, key, hash_key::<K>(kd, key)) {
            Some(i) => slot(m, &l, i).add(l.voff),
            None => core::ptr::null(),
        }
    }
}

/// `get(key)`: copies the value into `out`; 0 when absent.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_map_get(
    m: *const MapVal,
    kd: KeyDesc,
    vd: ValDesc,
    key: *const u8,
    out: *mut u8,
) -> u8 {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract.
    unsafe {
        let (kd, vd) = (&*kd, &*vd);
        let p = value_ptr(&*m, kd, Some(vd), key);
        if p.is_null() {
            return 0;
        }
        if vd.kind <= KIND_BOOL && vd.size == 8 {
            // Scalar values are plain 8-byte words: copy without the descriptor dispatch.
            core::ptr::copy_nonoverlapping(p, out, 8);
        } else {
            slot_copy(vd, p, out);
        }
        1
    }
}

/// Removes every entry, keeping nothing allocated.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_map_clear(m: *mut MapVal, kd: KeyDesc, vd: ValDesc) {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract.
    unsafe { drop_map(m, &*kd, opt(vd)) }
}

/// `Set.values()`: a set's elements are its map's keys, as a fresh list of copies.
#[unsafe(no_mangle)]
// ms: leaf domain=set
pub unsafe extern "C-unwind" fn msrt_set_values(
    m: *const MapVal,
    kd: KeyDesc,
    vd: ValDesc,
    out: *mut VecVal,
) {
    // SAFETY: caller contract.
    unsafe { msrt_map_keys(m, kd, vd, out) }
}

/// `keys()` as a fresh list of copies.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_map_keys(
    m: *const MapVal,
    kd: KeyDesc,
    vd: ValDesc,
    out: *mut VecVal,
) {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract.
    unsafe { collect(m, &*kd, opt(vd), true, out) }
}

#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_map_values(
    m: *const MapVal,
    kd: KeyDesc,
    vd: ValDesc,
    out: *mut VecVal,
) {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract.
    unsafe { collect(m, &*kd, opt(vd), false, out) }
}

/// `for k in m.keys()` over a map that outlives the loop unchanged: string keys come back as
/// views of the map's own strings, so nothing is copied. Other keys are copied as by `keys`.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_map_keys_view(
    m: *const MapVal,
    kd: KeyDesc,
    vd: ValDesc,
    out: *mut VecVal,
) {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract.
    unsafe { collect_view(m, &*kd, opt(vd), true, out) }
}

/// `for v in m.values()` over a map that outlives the loop unchanged (see [`msrt_map_keys_view`]).
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_map_values_view(
    m: *const MapVal,
    kd: KeyDesc,
    vd: ValDesc,
    out: *mut VecVal,
) {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract.
    unsafe { collect_view(m, &*kd, opt(vd), false, out) }
}

unsafe fn collect_view(
    m: *const MapVal,
    kd: &TypeDesc,
    vd: Option<&TypeDesc>,
    keys: bool,
    out: *mut VecVal,
) {
    let d = if keys { kd } else { vd.unwrap_or(kd) };
    // SAFETY: caller contract.
    unsafe {
        if d.kind != ms_rt_abi::KIND_STRING {
            return collect(m, kd, vd, keys, out);
        }
        let m = &*m;
        let l = layout(kd, vd);
        let mut v = VecVal {
            ptr: core::ptr::null_mut(),
            len: 0,
            cap: 0,
        };
        if m.len > 0 {
            v.ptr = alloc::alloc(m.len * STR_SIZE);
            v.cap = m.len;
        }
        for i in 0..m.used {
            let p = slot(m, &l, i);
            if slot_hash_of(p) & LIVE == 0 {
                continue;
            }
            let s = &*(p.add(if keys { l.koff } else { l.voff }) as *const StrVal);
            let view = if s.owns() {
                crate::string::view_of(s.data(), s.len())
            } else {
                s.alias()
            };
            view.write_to((v.ptr as *mut StrVal).add(v.len));
            v.len += 1;
        }
        *out = v;
    }
}

unsafe fn collect(
    m: *const MapVal,
    kd: &TypeDesc,
    vd: Option<&TypeDesc>,
    keys: bool,
    out: *mut VecVal,
) {
    // SAFETY: caller contract.
    unsafe {
        let m = &*m;
        let l = layout(kd, vd);
        let d = if keys { kd } else { vd.unwrap_or(kd) };
        let size = d.size as usize;
        let mut v = VecVal {
            ptr: core::ptr::null_mut(),
            len: 0,
            cap: 0,
        };
        if m.len > 0 {
            v.ptr = alloc::alloc(m.len * size.max(1));
            v.cap = m.len;
        }
        for i in 0..m.used {
            let p = slot(m, &l, i);
            if slot_hash_of(p) & LIVE == 0 {
                continue;
            }
            slot_copy(
                d,
                p.add(if keys { l.koff } else { l.voff }),
                v.ptr.add(v.len * size),
            );
            v.len += 1;
        }
        *out = v;
    }
}

/// `merge(other)`: entries of `other` (borrowed, copied) replace or append.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_map_merge(
    m: *mut MapVal,
    other: *const MapVal,
    kd: KeyDesc,
    vd: ValDesc,
) {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract.
    unsafe {
        let (kd, vdo) = (&*kd, opt(vd));
        let l = layout(kd, vdo);
        let o = &*other;
        if o.len == 0 {
            return;
        }
        // Each insertion moving_params the copied values, so their scratch slots can be reused.
        // Wide records need one temporary allocation per merge, rather than per entry.
        let mut kb = [0u64; 8];
        let mut vb = [0u64; 8];
        let kp = if l.ksize <= 64 {
            kb.as_mut_ptr() as *mut u8
        } else {
            alloc::alloc(l.ksize)
        };
        let vp = if l.vsize <= 64 {
            vb.as_mut_ptr() as *mut u8
        } else {
            alloc::alloc(l.vsize)
        };
        for i in 0..o.used {
            let p = slot(o, &l, i);
            if slot_hash_of(p) & LIVE == 0 {
                continue;
            }
            slot_copy(kd, p.add(l.koff), kp);
            if let Some(v) = vdo {
                slot_copy(v, p.add(l.voff), vp);
            }
            insert(&mut *m, kd, vdo, kp, vp);
        }
        if l.ksize > 64 {
            alloc::free(kp);
        }
        if l.vsize > 64 {
            alloc::free(vp);
        }
    }
}

/// Adds the entries of a packed table of constants, in order, so a later entry replaces an
/// earlier one with an equal key. The compiler emits the table for a literal whose keys and
/// values are all constants, which keeps the code per entry at nothing.
///
/// `table` is a borrowed `Bytes` of items, key then value for each entry: tag `0` and an
/// 8-byte little-endian word (`Int`, `Float` bits, `Bool` as 0 or 1), or tag `1`, a `u32`
/// length and that many bytes (`String`). An item must fit its slot (word keys are `Int`,
/// string keys `String`), as the call site's types guarantee.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_map_add_table(
    m: *mut MapVal,
    kd: KeyDesc,
    vd: ValDesc,
    table: *const StrVal,
) {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract.
    unsafe {
        let (kd, vdo) = (&*kd, opt(vd));
        let l = layout(kd, vdo);
        let mut kb = [0u64; 2];
        let mut vb = [0u64; 2];
        let mut rest = string::bytes(table);
        while !rest.is_empty() {
            rest = table_item(rest, kb.as_mut_ptr().cast(), l.ksize);
            rest = table_item(rest, vb.as_mut_ptr().cast(), l.vsize);
            insert(
                &mut *m,
                kd,
                vdo,
                kb.as_mut_ptr().cast(),
                vb.as_mut_ptr().cast(),
            );
        }
    }
}

/// Decodes one [`msrt_map_add_table`] item into `out`, a slot of `size` bytes, and returns the
/// bytes after it.
unsafe fn table_item(rest: &[u8], out: *mut u8, size: usize) -> &[u8] {
    // SAFETY: `out` is a writable slot of `size` bytes; the table was written by the compiler.
    unsafe {
        let (tag, rest) = (rest[0], &rest[1..]);
        if tag == 0 {
            let n = size.min(8);
            core::ptr::copy_nonoverlapping(rest.as_ptr(), out, n);
            return &rest[8..];
        }
        let len = u32::from_le_bytes([rest[0], rest[1], rest[2], rest[3]]) as usize;
        let (text, rest) = rest[4..].split_at(len);
        debug_assert_eq!(size, core::mem::size_of::<StrVal>());
        string::from_bytes(text).write_to(out.cast());
        rest
    }
}

// ---- Set algebra (all produce fresh sets in left order) ----

/// Copies a key, checking for a duplicate unless its caller already knows the output is unique.
unsafe fn add_copy<const CHECK: bool>(m: &mut MapVal, kd: &TypeDesc, p: *const u8) {
    // SAFETY: `p` is a live key slot; insert moving_params its fresh copy.
    unsafe {
        if CHECK && contains_key(m, kd, None, p) {
            return;
        }
        let mut buf = [0u64; 8];
        let k = if kd.size as usize <= 64 {
            buf.as_mut_ptr() as *mut u8
        } else {
            alloc::alloc(kd.size as usize)
        };
        slot_copy(kd, p, k);
        let mut ins = || insert(m, kd, None, k, core::ptr::null_mut());
        // The copy is unowned until `insert` stores it, and hash or equality callbacks can exit.
        if !needs_no_drop(kd) && fault::rollback_needed() {
            fault::with_cleanup(
                &mut || {
                    slot_drop(kd, k);
                    if kd.size as usize > 64 {
                        alloc::free(k);
                    }
                },
                ins,
            );
        } else {
            ins();
        }
        if kd.size as usize > 64 {
            alloc::free(k);
        }
    }
}

unsafe fn each_key(m: &MapVal, kd: &TypeDesc, mut f: impl FnMut(*const u8)) {
    // SAFETY: forwarded slot contract.
    unsafe {
        each_key_while(m, kd, |k| {
            f(k);
            true
        });
    }
}

/// Returns false when the visitor stops before the end of the set.
unsafe fn each_key_while(m: &MapVal, kd: &TypeDesc, mut f: impl FnMut(*const u8) -> bool) -> bool {
    // SAFETY: slots are consistent.
    unsafe {
        let l = layout(kd, None);
        for i in 0..m.used {
            let p = slot(m, &l, i);
            if slot_hash_of(p) & LIVE != 0 && !f(p.add(l.koff)) {
                return false;
            }
        }
        true
    }
}

#[unsafe(no_mangle)]
// ms: leaf domain=set
pub unsafe extern "C-unwind" fn msrt_set_add_copy(m: *mut MapVal, kd: KeyDesc, key: *const u8) {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract.
    unsafe { add_copy::<true>(&mut *m, &*kd, key) }
}

/// `Set.add` for an `Int` element: the layout is fixed (hash word, key), so the call site skips
/// descriptor dispatch. A set stamped with its module's key behaviour keeps the general path.
#[unsafe(no_mangle)]
// ms: leaf domain=set
pub unsafe extern "C-unwind" fn msrt_set_add_copy_w(m: *mut MapVal, kd: KeyDesc, key: *const u8) {
    // SAFETY: caller contract; `key` is a live `Int` slot.
    unsafe {
        if !(*m).desc.is_null() {
            return msrt_set_add_copy(m, kd, key);
        }
        if !find_set_w(&*m, key).is_null() {
            return;
        }
        let m = &mut *m;
        let l = Layout {
            koff: 8,
            voff: 16,
            stride: 16,
            ksize: 8,
            vsize: 0,
        };
        let h = hash_key::<IntKey>(&crate::desc::msrt_desc_string, key);
        if m.used == m.cap {
            grow(m, &l);
        }
        let p = slot(m, &l, m.used);
        *(p as *mut u64) = h;
        copy_slot(key, p.add(8), 8);
        let mut pos = (h as usize ^ (h >> 32) as usize) & m.mask;
        loop {
            let e = *index_of(m).add(pos);
            if e == 0 || e == REMOVED {
                break;
            }
            pos = (pos + 1) & m.mask;
        }
        *index_of(m).add(pos) = entry(h, m.used);
        m.used += 1;
        m.len += 1;
    }
}

#[unsafe(no_mangle)]
// ms: leaf domain=set
pub unsafe extern "C-unwind" fn msrt_set_union(
    a: *const MapVal,
    b: *const MapVal,
    kd: KeyDesc,
    out: *mut MapVal,
) {
    let kd = key_desc(a, kd);
    // SAFETY: caller contract.
    unsafe {
        let kd = &*kd;
        copy_map(a, kd, None, out);
        each_key(&*b, kd, |k| add_copy::<true>(&mut *out, kd, k));
    }
}

unsafe fn filter_into(
    a: &MapVal,
    kd: &TypeDesc,
    out: *mut MapVal,
    mut keep: impl FnMut(*const u8) -> bool,
) {
    // SAFETY: caller contract.
    unsafe {
        *out = empty();
        (*out).desc = a.desc;
        each_key(a, kd, |k| {
            if keep(k) {
                // A is already unique, and this output starts empty.
                add_copy::<false>(&mut *out, kd, k);
            }
        });
    }
}

#[unsafe(no_mangle)]
// ms: leaf domain=set
pub unsafe extern "C-unwind" fn msrt_set_intersection(
    a: *const MapVal,
    b: *const MapVal,
    kd: KeyDesc,
    out: *mut MapVal,
) {
    let right_kd = key_desc(b, kd);
    let kd = key_desc(a, kd);
    // SAFETY: caller contract.
    unsafe {
        if (*b).len == 0 {
            *out = empty();
            (*out).desc = (*a).desc;
            return;
        }
        let kd = &*kd;
        filter_into(&*a, kd, out, |k| contains_key(&*b, &*right_kd, None, k));
    }
}

#[unsafe(no_mangle)]
// ms: leaf domain=set
pub unsafe extern "C-unwind" fn msrt_set_difference(
    a: *const MapVal,
    b: *const MapVal,
    kd: KeyDesc,
    out: *mut MapVal,
) {
    let right_kd = key_desc(b, kd);
    let kd = key_desc(a, kd);
    // SAFETY: caller contract.
    unsafe {
        let kd = &*kd;
        filter_into(&*a, kd, out, |k| !contains_key(&*b, &*right_kd, None, k));
    }
}

#[unsafe(no_mangle)]
// ms: leaf domain=set
pub unsafe extern "C-unwind" fn msrt_set_symmetric_difference(
    a: *const MapVal,
    b: *const MapVal,
    kd: KeyDesc,
    out: *mut MapVal,
) {
    let right_kd = key_desc(b, kd);
    let kd = key_desc(a, kd);
    // SAFETY: caller contract.
    unsafe {
        let kd = &*kd;
        filter_into(&*a, kd, out, |k| !contains_key(&*b, &*right_kd, None, k));
        each_key(&*b, kd, |k| {
            if !contains_key(&*a, kd, None, k) {
                add_copy::<true>(&mut *out, kd, k);
            }
        });
    }
}

#[unsafe(no_mangle)]
// ms: leaf domain=set
pub unsafe extern "C-unwind" fn msrt_set_is_subset_of(
    a: *const MapVal,
    b: *const MapVal,
    kd: KeyDesc,
) -> u8 {
    let right_kd = key_desc(b, kd);
    let kd = key_desc(a, kd);
    // SAFETY: caller contract.
    unsafe {
        let kd = &*kd;
        each_key_while(&*a, kd, |k| contains_key(&*b, &*right_kd, None, k)) as u8
    }
}

#[unsafe(no_mangle)]
// ms: leaf domain=set
pub unsafe extern "C-unwind" fn msrt_set_is_superset_of(
    a: *const MapVal,
    b: *const MapVal,
    kd: KeyDesc,
) -> u8 {
    let kd = key_desc(a, kd);
    // SAFETY: caller contract.
    unsafe { msrt_set_is_subset_of(b, a, kd) }
}

#[unsafe(no_mangle)]
// ms: leaf domain=set
pub unsafe extern "C-unwind" fn msrt_set_is_disjoint_from(
    a: *const MapVal,
    b: *const MapVal,
    kd: KeyDesc,
) -> u8 {
    let right_kd = key_desc(b, kd);
    let kd = key_desc(a, kd);
    // SAFETY: caller contract.
    unsafe {
        if (*b).len == 0 {
            return 1;
        }
        let kd = &*kd;
        each_key_while(&*a, kd, |k| !contains_key(&*b, &*right_kd, None, k)) as u8
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::desc::{msrt_desc_int, msrt_desc_string};
    use crate::string::{self, from_bytes};

    #[test]
    fn int_set_membership_keeps_collisions_holes_and_order() {
        let _g = testutil::lock();
        // SAFETY: all slots and queries are live i64 values of the Int descriptor.
        unsafe {
            let kd = &msrt_desc_int;
            let before = alloc::live_blocks();
            let mut m = empty();
            // Ninety-six keys share one bucket in the final 256-entry index.
            let mut keys: Vec<i64> = (0..100_000i64)
                .filter(|key| {
                    let h = string::hash_int(*key as u64) | LIVE;
                    (h ^ (h >> 32)) & 255 == 0
                })
                .take(96)
                .collect();
            assert_eq!(keys.len(), 96);
            keys.extend([i64::MIN, -1, i64::MAX]);
            let check = |m: &MapVal, live: &[i64]| {
                for key in keys.iter().chain([-2i64, -3, -4].iter()) {
                    let actual =
                        msrt_map_contains(m, kd, core::ptr::null(), (key as *const i64).cast())
                            != 0;
                    assert_eq!(actual, live.contains(key), "query {key}");
                }
                let mut order = Vec::new();
                each_key(m, kd, |p| order.push(*p.cast::<i64>()));
                assert_eq!(order, live);
            };
            check(&m, &[]);
            for key in &keys {
                let mut value = *key;
                insert(
                    &mut m,
                    kd,
                    None,
                    (&raw mut value).cast(),
                    core::ptr::null_mut(),
                );
            }
            check(&m, &keys);
            for (i, key) in keys.iter().take(60).enumerate() {
                assert!(remove(&mut m, kd, None, (key as *const i64).cast()));
                // Check both tombstones and the compaction triggered by a majority of holes.
                check(&m, &keys[i + 1..]);
            }
            msrt_map_clear(&mut m, kd, core::ptr::null());
            check(&m, &[]);
            let mut key = i64::MIN;
            insert(
                &mut m,
                kd,
                None,
                (&raw mut key).cast(),
                core::ptr::null_mut(),
            );
            check(&m, &[i64::MIN]);
            drop_map(&mut m, kd, None);
            assert_eq!(alloc::live_blocks(), before);
        }
    }

    fn merge_plain_desc(size: u32) -> TypeDesc {
        TypeDesc {
            size,
            align: 8,
            kind: KIND_POD,
            reserved: 0,
            inner0: core::ptr::null(),
            inner1: core::ptr::null(),
            drop: None,
            copy: None,
            eq: None,
            hash: None,
        }
    }

    unsafe extern "C" fn merge_copy_strings(src: *const u8, dst: *mut u8) {
        // SAFETY: both slots hold five strings; the destination is uninitialised.
        unsafe {
            for i in 0..5 {
                (dst as *mut StrVal)
                    .add(i)
                    .write(string::cloned(&*(src as *const StrVal).add(i)));
            }
        }
    }

    unsafe extern "C" fn merge_drop_strings(src: *mut u8) {
        // SAFETY: the slot owns five live strings.
        unsafe {
            for i in 0..5 {
                string::release(&*(src as *const StrVal).add(i));
            }
        }
    }

    #[test]
    fn merge_wide_slots_preserves_order_holes_and_owned_values() {
        let _g = testutil::lock();
        let before = alloc::live_blocks();
        let kd = merge_plain_desc(80);
        let vd = TypeDesc {
            kind: KIND_CUSTOM,
            copy: Some(merge_copy_strings),
            drop: Some(merge_drop_strings),
            ..merge_plain_desc(core::mem::size_of::<[StrVal; 5]>() as u32)
        };
        assert!(kd.size > 64 && vd.size > 64);
        // SAFETY: maps own wide integer-array keys and five-string values.
        unsafe {
            let mut source = empty();
            let mut target = empty();
            for (m, keys) in [
                (&mut source, (0..12).collect::<Vec<i64>>()),
                (&mut target, vec![-1, 2, 99]),
            ] {
                for k in keys {
                    let mut key = [k; 10];
                    let text = format!("long independently owned value for key {k}");
                    let mut values =
                        core::array::from_fn::<_, 5, _>(|_| from_bytes(text.as_bytes()));
                    insert(
                        m,
                        &kd,
                        Some(&vd),
                        key.as_mut_ptr().cast(),
                        values.as_mut_ptr().cast(),
                    );
                }
            }
            for k in [1i64, 5, 9] {
                let key = [k; 10];
                assert!(remove(&mut source, &kd, Some(&vd), key.as_ptr().cast()));
            }
            for _ in 0..2 {
                msrt_map_merge(&mut target, &source, &kd, &vd);
                let mut keys = core::mem::MaybeUninit::uninit();
                msrt_map_keys(&target, &kd, &vd, keys.as_mut_ptr());
                let mut keys = keys.assume_init();
                let got: Vec<i64> = (0..keys.len)
                    .map(|i| *(keys.ptr as *const [i64; 10]).add(i).cast::<i64>())
                    .collect();
                assert_eq!(got, [-1, 2, 99, 0, 3, 4, 6, 7, 8, 10, 11]);
                crate::vec::drop_list(&mut keys, &kd);
                let key = [2i64; 10];
                let a = msrt_map_get_ptr(&source, &kd, &vd, key.as_ptr().cast()) as *const StrVal;
                let b = msrt_map_get_ptr(&target, &kd, &vd, key.as_ptr().cast()) as *const StrVal;
                for i in 0..5 {
                    assert_eq!(string::bytes(a.add(i)), string::bytes(b.add(i)));
                    assert_ne!(
                        string::bytes(a.add(i)).as_ptr(),
                        string::bytes(b.add(i)).as_ptr()
                    );
                }
            }
            drop_map(&mut source, &kd, Some(&vd));
            for k in [-1i64, 2, 99, 0, 3, 4, 6, 7, 8, 10, 11] {
                let key = [k; 10];
                let p = msrt_map_get_ptr(&target, &kd, &vd, key.as_ptr().cast()) as *const StrVal;
                let text = format!("long independently owned value for key {k}");
                for i in 0..5 {
                    assert_eq!(string::bytes(p.add(i)), text.as_bytes());
                }
            }
            drop_map(&mut target, &kd, Some(&vd));
        }
        assert_eq!(alloc::live_blocks(), before);
    }

    #[test]
    #[cfg(feature = "stats")]
    fn merge_scratch_allocations_are_bounded_by_slot_types() {
        let _g = testutil::lock();
        let before = alloc::live_blocks();
        for ksize in [8, 64, 72, 128] {
            for vsize in [0, 8, 64, 72, 128] {
                let kd = merge_plain_desc(ksize);
                let vd = merge_plain_desc(vsize);
                // SAFETY: each array provides enough storage for the descriptor's slots.
                unsafe {
                    let mut source = empty();
                    for i in 0..32u64 {
                        let mut key = [i; 16];
                        let mut value = [i + 1; 16];
                        insert(
                            &mut source,
                            &kd,
                            Some(&vd),
                            key.as_mut_ptr().cast(),
                            value.as_mut_ptr().cast(),
                        );
                    }
                    let mut target = core::mem::MaybeUninit::uninit();
                    copy_map(&source, &kd, Some(&vd), target.as_mut_ptr());
                    let mut target = target.assume_init();
                    let counts = alloc::requested();
                    msrt_map_merge(&mut target, &source, &kd, &vd);
                    let after = alloc::requested();
                    assert_eq!(
                        after[0] - counts[0],
                        u64::from(ksize > 64) + u64::from(vsize > 64)
                    );
                    assert_eq!(
                        after[1] - counts[1],
                        u64::from(if ksize > 64 { ksize } else { 0 })
                            + u64::from(if vsize > 64 { vsize } else { 0 })
                    );
                    assert!(eq_map(&source, &target, &kd, Some(&vd)));
                    drop_map(&mut source, &kd, Some(&vd));
                    let counts = alloc::requested();
                    msrt_map_merge(&mut target, &source, &kd, &vd);
                    assert_eq!(alloc::requested(), counts);
                    assert_eq!(target.len, 32);
                    drop_map(&mut target, &kd, Some(&vd));
                }
            }
        }
        assert_eq!(alloc::live_blocks(), before);
    }
    use crate::testutil;
    use core::sync::atomic::{AtomicUsize, Ordering};

    #[test]
    fn an_empty_map_is_all_zero_words() {
        // Generated code builds `ExternRole::MapNew` as zero words instead of calling the runtime.
        let m = empty();
        // SAFETY: `MapVal` is `repr(C)` plain words.
        let words: [usize; MAP_SIZE / 8] = unsafe { core::mem::transmute(m) };
        assert!(words.iter().all(|w| *w == 0));
    }

    #[test]
    fn empty_set_relations_do_not_hash_members() {
        let _g = testutil::lock();
        // SAFETY: all set slots hold live i64 values of the static descriptor.
        unsafe {
            let kd = &COUNTED_KEY;
            let mut nonempty = empty();
            let mut vacant = empty();
            for i in 0..128i64 {
                let mut key = i;
                insert(
                    &mut nonempty,
                    kd,
                    None,
                    (&mut key as *mut i64).cast(),
                    core::ptr::null_mut(),
                );
            }
            HASH_CALLS.store(0, Ordering::Relaxed);
            assert_eq!(msrt_set_is_subset_of(&vacant, &nonempty, kd), 1);
            assert_eq!(msrt_set_is_subset_of(&nonempty, &vacant, kd), 0);
            assert_eq!(msrt_set_is_subset_of(&vacant, &vacant, kd), 1);
            assert_eq!(msrt_set_is_superset_of(&vacant, &vacant, kd), 1);
            assert_eq!(msrt_set_is_superset_of(&nonempty, &vacant, kd), 1);
            assert_eq!(msrt_set_is_superset_of(&vacant, &nonempty, kd), 0);
            assert_eq!(msrt_set_is_disjoint_from(&vacant, &nonempty, kd), 1);
            assert_eq!(msrt_set_is_disjoint_from(&nonempty, &vacant, kd), 1);
            assert_eq!(msrt_set_is_disjoint_from(&vacant, &vacant, kd), 1);
            assert_eq!(HASH_CALLS.load(Ordering::Relaxed), 0);
            drop_map(&mut nonempty, kd, None);
            drop_map(&mut vacant, kd, None);
        }
    }

    unsafe extern "C" fn modulo_eq(a: *const u8, b: *const u8) -> u8 {
        // SAFETY: the test descriptor describes i64 slots.
        unsafe { (*(a as *const i64) % 10 == *(b as *const i64) % 10) as u8 }
    }

    unsafe extern "C" fn modulo_hash(a: *const u8) -> i64 {
        // SAFETY: the test descriptor describes an i64 slot.
        unsafe { *(a as *const i64) % 10 }
    }

    static MODULO_KEY: TypeDesc = TypeDesc {
        size: 8,
        align: 8,
        kind: KIND_CUSTOM,
        reserved: 0,
        inner0: core::ptr::null(),
        inner1: core::ptr::null(),
        drop: None,
        copy: None,
        eq: Some(modulo_eq),
        hash: Some(modulo_hash),
    };

    unsafe extern "C" fn shifted_modulo_hash(a: *const u8) -> i64 {
        // SAFETY: the test descriptor describes an i64 slot.
        unsafe { modulo_hash(a) + 1000 }
    }

    static SHIFTED_MODULO_KEY: TypeDesc = TypeDesc {
        hash: Some(shifted_modulo_hash),
        ..MODULO_KEY
    };

    #[test]
    fn set_operations_probe_each_operands_creator_hash() {
        let _g = testutil::lock();
        let before = alloc::live_blocks();
        for stamped in [false, true] {
            let caller = if stamped {
                &msrt_desc_int
            } else {
                &SHIFTED_MODULO_KEY
            };
            // SAFETY: all descriptors describe live i64 key slots, with the same equality
            // but different valid hashes. Stamped creators outlive the sets and their copies.
            unsafe {
                let mut a = empty();
                let mut b = empty();
                msrt_map_stamp(&mut a, &MODULO_KEY);
                if stamped {
                    msrt_map_stamp(&mut b, &SHIFTED_MODULO_KEY);
                }
                for (m, kd, values) in [
                    (&mut a, &MODULO_KEY, [1i64, 2]),
                    (&mut b, &SHIFTED_MODULO_KEY, [11i64, 3]),
                ] {
                    for mut value in values {
                        insert(m, kd, None, (&raw mut value).cast(), core::ptr::null_mut());
                    }
                }
                let mut actual = Vec::new();
                for operation in [
                    msrt_set_union,
                    msrt_set_intersection,
                    msrt_set_difference,
                    msrt_set_symmetric_difference,
                ] {
                    let mut out = empty();
                    operation(&a, &b, caller, &mut out);
                    let mut values = Vec::new();
                    each_key(&out, &MODULO_KEY, |p| values.push(*p.cast::<i64>()));
                    actual.push(values);
                    assert_eq!(out.desc, &raw const MODULO_KEY);
                    drop_map(&mut out, &MODULO_KEY, None);
                }
                let mut shared = empty();
                if stamped {
                    msrt_map_stamp(&mut shared, &SHIFTED_MODULO_KEY);
                }
                let mut value = 11i64;
                insert(
                    &mut shared,
                    &SHIFTED_MODULO_KEY,
                    None,
                    (&raw mut value).cast(),
                    core::ptr::null_mut(),
                );
                let relations = [
                    msrt_set_is_subset_of(&shared, &a, caller),
                    msrt_set_is_superset_of(&a, &shared, caller),
                    msrt_set_is_disjoint_from(&a, &shared, caller),
                    msrt_set_is_disjoint_from(&shared, &a, caller),
                ];
                drop_map(&mut shared, &SHIFTED_MODULO_KEY, None);
                drop_map(&mut a, &MODULO_KEY, None);
                drop_map(&mut b, &SHIFTED_MODULO_KEY, None);
                assert_eq!(alloc::live_blocks(), before);
                assert_eq!(actual, [vec![1, 2, 3], vec![1], vec![2], vec![2, 3]]);
                assert_eq!(relations, [1, 1, 0, 0]);
            }
        }
    }

    static HASH_CALLS: AtomicUsize = AtomicUsize::new(0);

    unsafe extern "C" fn counted_hash(a: *const u8) -> i64 {
        HASH_CALLS.fetch_add(1, Ordering::Relaxed);
        // SAFETY: the test descriptor describes an i64 slot.
        unsafe { *(a as *const i64) }
    }

    unsafe extern "C" fn counted_eq(a: *const u8, b: *const u8) -> u8 {
        // SAFETY: the test descriptor describes i64 slots.
        unsafe { (*(a as *const i64) == *(b as *const i64)) as u8 }
    }

    static COUNTED_KEY: TypeDesc = TypeDesc {
        size: 8,
        align: 8,
        kind: KIND_CUSTOM,
        reserved: 0,
        inner0: core::ptr::null(),
        inner1: core::ptr::null(),
        drop: None,
        copy: None,
        eq: Some(counted_eq),
        hash: Some(counted_hash),
    };

    static ALGEBRA_CALLBACKS: AtomicUsize = AtomicUsize::new(0);

    unsafe extern "C" fn algebra_hash(p: *const u8) -> i64 {
        ALGEBRA_CALLBACKS.fetch_add(1, Ordering::Relaxed);
        // SAFETY: the test descriptor describes an i64 slot.
        unsafe { *p.cast::<i64>() }
    }

    unsafe extern "C" fn algebra_eq(a: *const u8, b: *const u8) -> u8 {
        ALGEBRA_CALLBACKS.fetch_add(1, Ordering::Relaxed);
        // SAFETY: the test descriptor describes i64 slots.
        unsafe { (*a.cast::<i64>() == *b.cast::<i64>()) as u8 }
    }

    unsafe extern "C" fn algebra_copy(src: *const u8, dst: *mut u8) {
        ALGEBRA_CALLBACKS.fetch_add(1, Ordering::Relaxed);
        // SAFETY: source is live and destination is an uninitialised i64 slot.
        unsafe { dst.cast::<i64>().write(*src.cast::<i64>()) };
    }

    unsafe extern "C" fn algebra_drop(_: *mut u8) {
        ALGEBRA_CALLBACKS.fetch_add(1, Ordering::Relaxed);
    }

    static ALGEBRA_KEY: TypeDesc = TypeDesc {
        hash: Some(algebra_hash),
        eq: Some(algebra_eq),
        copy: Some(algebra_copy),
        drop: Some(algebra_drop),
        ..COUNTED_KEY
    };

    #[test]
    fn empty_intersection_keeps_creator_identity_for_later_adds() {
        let _g = testutil::lock();
        let before = alloc::live_blocks();
        // SAFETY: every descriptor describes i64 slots and outlives the sets.
        unsafe {
            let mut a = empty();
            let mut b = empty();
            msrt_map_stamp(&mut a, &MODULO_KEY);
            msrt_map_stamp(&mut b, &SHIFTED_MODULO_KEY);
            let value = 1i64;
            msrt_set_add_copy(&mut a, &msrt_desc_int, (&raw const value).cast());
            let mut out = empty();
            msrt_set_intersection(&a, &b, &msrt_desc_int, &mut out);
            assert_eq!(out.desc, &raw const MODULO_KEY);
            for value in [1i64, 11, 2] {
                msrt_set_add_copy(&mut out, &msrt_desc_int, (&raw const value).cast());
            }
            let mut values = Vec::new();
            each_key(&out, &MODULO_KEY, |p| values.push(*p.cast::<i64>()));
            assert_eq!(values, [1, 2]);
            assert_eq!(a.len, 1);
            assert_eq!(b.len, 0);
            drop_map(&mut out, &MODULO_KEY, None);
            drop_map(&mut a, &MODULO_KEY, None);
            drop_map(&mut b, &SHIFTED_MODULO_KEY, None);
        }
        assert_eq!(alloc::live_blocks(), before);
    }

    #[test]
    fn empty_intersection_preserves_inputs_creator_and_callback_behavior() {
        let _g = testutil::lock();
        let before = alloc::live_blocks();
        for stamped in [false, true] {
            for holes in [false, true] {
                for retained_right in [false, true] {
                    // SAFETY: all descriptors describe i64 slots and outlive the sets.
                    unsafe {
                        let mut a = empty();
                        let mut b = empty();
                        if stamped {
                            msrt_map_stamp(&mut a, &ALGEBRA_KEY);
                        }
                        msrt_map_stamp(&mut b, &msrt_desc_int);
                        for mut value in 0..16i64 {
                            insert(
                                &mut a,
                                &ALGEBRA_KEY,
                                None,
                                (&raw mut value).cast(),
                                core::ptr::null_mut(),
                            );
                        }
                        if holes {
                            for value in [1i64, 3, 5] {
                                assert!(remove(
                                    &mut a,
                                    &ALGEBRA_KEY,
                                    None,
                                    (&raw const value).cast()
                                ));
                            }
                        }
                        if retained_right {
                            let mut value = 42i64;
                            insert(
                                &mut b,
                                &msrt_desc_int,
                                None,
                                (&raw mut value).cast(),
                                core::ptr::null_mut(),
                            );
                            assert!(remove(
                                &mut b,
                                &msrt_desc_int,
                                None,
                                (&raw const value).cast()
                            ));
                            assert!(!b.slots.is_null());
                        }
                        let blocks = alloc::live_blocks();
                        let mut out = empty();
                        ALGEBRA_CALLBACKS.store(0, Ordering::Relaxed);
                        let caller = if stamped {
                            &msrt_desc_int
                        } else {
                            &ALGEBRA_KEY
                        };
                        msrt_set_intersection(&a, &b, caller, &mut out);
                        assert_eq!(ALGEBRA_CALLBACKS.load(Ordering::Relaxed), 0);
                        assert_eq!(alloc::live_blocks(), blocks);
                        assert_eq!(out.desc, a.desc);
                        assert_eq!(out.len, 0);
                        assert!(out.slots.is_null() && out.index.is_null());
                        let mut values = Vec::new();
                        each_key(&a, &ALGEBRA_KEY, |p| values.push(*p.cast::<i64>()));
                        assert_eq!(
                            values,
                            (0..16i64)
                                .filter(|v| !holes || ![1, 3, 5].contains(v))
                                .collect::<Vec<_>>()
                        );
                        assert_eq!(b.len, 0);
                        // The reversed operands also produce an empty result with the left creator.
                        msrt_set_intersection(&b, &a, caller, &mut out);
                        assert_eq!(out.desc, b.desc);
                        assert_eq!(out.len, 0);
                        assert_eq!(ALGEBRA_CALLBACKS.load(Ordering::Relaxed), 0);
                        drop_map(&mut out, &msrt_desc_int, None);
                        drop_map(&mut a, &ALGEBRA_KEY, None);
                        drop_map(&mut b, &msrt_desc_int, None);
                    }
                    assert_eq!(alloc::live_blocks(), before);
                }
            }
        }
    }

    #[test]
    fn set_algebra_does_not_recheck_unique_output_keys() {
        let _g = testutil::lock();
        // SAFETY: sets contain live i64 keys of the counted descriptor.
        unsafe {
            let before = alloc::live_blocks();
            let kd = &COUNTED_KEY;
            let mut a = empty();
            let mut b = empty();
            for i in 0..32i64 {
                let mut x = i;
                let mut y = i + 32;
                insert(
                    &mut a,
                    kd,
                    None,
                    (&mut x as *mut i64).cast(),
                    core::ptr::null_mut(),
                );
                insert(
                    &mut b,
                    kd,
                    None,
                    (&mut y as *mut i64).cast(),
                    core::ptr::null_mut(),
                );
            }
            let mut output = empty();
            HASH_CALLS.store(0, Ordering::Relaxed);
            msrt_set_intersection(&a, &a, kd, &mut output);
            assert_eq!(output.len, 32);
            assert_eq!(HASH_CALLS.load(Ordering::Relaxed), 64);
            drop_map(&mut output, kd, None);
            HASH_CALLS.store(0, Ordering::Relaxed);
            msrt_set_difference(&a, &b, kd, &mut output);
            assert_eq!(output.len, 32);
            assert_eq!(HASH_CALLS.load(Ordering::Relaxed), 64);
            drop_map(&mut output, kd, None);
            HASH_CALLS.store(0, Ordering::Relaxed);
            msrt_set_symmetric_difference(&a, &b, kd, &mut output);
            assert_eq!(output.len, 64);
            assert_eq!(HASH_CALLS.load(Ordering::Relaxed), 160);
            drop_map(&mut output, kd, None);
            drop_map(&mut a, kd, None);
            drop_map(&mut b, kd, None);
            assert_eq!(alloc::live_blocks(), before);
        }
    }

    #[test]
    fn compaction_after_a_large_drop_shrinks_to_the_live_size() {
        let _g = testutil::lock();
        // SAFETY: all set slots hold live i64 values of the static descriptor.
        unsafe {
            let kd = &COUNTED_KEY;
            let mut m = empty();
            let put = |m: &mut MapVal, i: i64| {
                let mut k = i;
                insert(
                    m,
                    kd,
                    None,
                    (&mut k as *mut i64).cast(),
                    core::ptr::null_mut(),
                );
            };
            let has = |m: &MapVal, i: i64| contains_key(m, kd, None, (&i as *const i64).cast());
            for i in 0..4096 {
                put(&mut m, i);
            }
            assert_eq!(m.cap, 4096);
            for i in 0..4096i64 - 62 {
                let k = i;
                assert!(remove(&mut m, kd, None, (&k as *const i64).cast()));
            }
            assert_eq!(m.len, 62);
            assert!(m.cap <= 256, "capacity {} kept the peak", m.cap);
            assert_eq!(m.mask + 1, m.cap * 2);
            for i in 4096 - 62..4096 {
                assert!(has(&m, i));
            }
            assert!(!has(&m, 0));
            // Growing again after the shrink keeps every entry reachable.
            for i in 4096..8192 {
                put(&mut m, i);
            }
            assert_eq!(m.len, 62 + 4096);
            assert!((4096 - 62..8192).all(|i| has(&m, i)));
            drop_map(&mut m, kd, None);
        }
    }

    #[test]
    fn set_relations_stop_at_first_decisive_key() {
        let _g = testutil::lock();
        // SAFETY: all set slots hold live i64 values of the static descriptor.
        unsafe {
            let kd = &COUNTED_KEY;
            let mut a = empty();
            let mut b = empty();
            for i in 0..100i64 {
                let mut x = i;
                let mut y = i + 100;
                insert(
                    &mut a,
                    kd,
                    None,
                    (&mut x as *mut i64).cast(),
                    core::ptr::null_mut(),
                );
                insert(
                    &mut b,
                    kd,
                    None,
                    (&mut y as *mut i64).cast(),
                    core::ptr::null_mut(),
                );
            }
            HASH_CALLS.store(0, Ordering::Relaxed);
            assert_eq!(msrt_set_is_subset_of(&a, &b, kd), 0);
            assert_eq!(HASH_CALLS.load(Ordering::Relaxed), 1);
            HASH_CALLS.store(0, Ordering::Relaxed);
            assert_eq!(msrt_set_is_superset_of(&b, &a, kd), 0);
            assert_eq!(HASH_CALLS.load(Ordering::Relaxed), 1);
            HASH_CALLS.store(0, Ordering::Relaxed);
            assert_eq!(msrt_set_is_disjoint_from(&a, &a, kd), 0);
            assert_eq!(HASH_CALLS.load(Ordering::Relaxed), 1);
            assert_eq!(msrt_set_is_subset_of(&a, &a, kd), 1);
            assert_eq!(msrt_set_is_disjoint_from(&a, &b, kd), 1);
            drop_map(&mut a, kd, None);
            drop_map(&mut b, kd, None);
        }
    }

    #[test]
    fn equality_uses_the_probed_collections_creator_evidence() {
        let _g = testutil::lock();
        let unavailable = TypeDesc {
            size: 8,
            align: 8,
            kind: KIND_CUSTOM,
            reserved: 0,
            inner0: core::ptr::null(),
            inner1: core::ptr::null(),
            drop: None,
            copy: None,
            eq: None,
            hash: None,
        };
        let before = alloc::live_blocks();
        for map_values in [false, true] {
            let vd = map_values.then_some(&msrt_desc_int);
            // SAFETY: both collections hold i64 slots with the same creator's modulo identity;
            // only the caller's descriptor deliberately lacks that identity's implementations.
            unsafe {
                let mut left = empty();
                let mut right = empty();
                msrt_map_stamp(&mut left, &MODULO_KEY);
                msrt_map_stamp(&mut right, &MODULO_KEY);
                let put = |m: &mut MapVal, mut key: i64, mut value: i64| {
                    insert(
                        m,
                        &MODULO_KEY,
                        vd,
                        (&raw mut key).cast(),
                        (&raw mut value).cast(),
                    );
                };
                put(&mut left, 1, 5);
                put(&mut left, 2, 6);
                put(&mut right, 12, 6);
                put(&mut right, 11, 5);
                for caller in [&unavailable, &msrt_desc_int] {
                    assert!(eq_map(&left, &right, caller, vd));
                    assert!(eq_map(&right, &left, caller, vd));
                }
                let mut copied = empty();
                copy_map(&right, &MODULO_KEY, vd, &mut copied);
                assert!(eq_map(&left, &copied, &unavailable, vd));
                drop_map(&mut copied, &MODULO_KEY, vd);
                if map_values {
                    put(&mut right, 22, 99);
                    assert!(!eq_map(&left, &right, &unavailable, vd));
                    assert!(!eq_map(&right, &left, &unavailable, vd));
                    put(&mut right, 32, 6);
                }
                assert!(remove(
                    &mut right,
                    &MODULO_KEY,
                    vd,
                    (&11i64 as *const i64).cast()
                ));
                put(&mut right, 3, 5);
                assert!(!eq_map(&left, &right, &unavailable, vd));
                assert!(!eq_map(&right, &left, &unavailable, vd));
                drop_map(&mut left, &MODULO_KEY, vd);
                drop_map(&mut right, &MODULO_KEY, vd);
            }
        }
        assert_eq!(alloc::live_blocks(), before);
    }

    #[test]
    fn creator_evidence_survives_foreign_operations_copy_and_clear() {
        let _g = testutil::lock();
        // SAFETY: descriptors are static and all key/value slots hold live i64 values.
        unsafe {
            let before = crate::alloc::live_blocks();
            let foreign = &msrt_desc_int;
            let mut m = empty();
            msrt_map_stamp(&mut m, &MODULO_KEY);
            msrt_map_stamp(&mut m, foreign);
            let mut cloned = empty();
            copy_map(&m, foreign, Some(foreign), &mut cloned);
            let (mut k, mut v) = (1i64, 5i64);
            let (kp, vp) = (&mut k as *mut i64 as *mut u8, &mut v as *mut i64 as *mut u8);
            msrt_map_add(&mut cloned, foreign, foreign, kp, vp);
            kp.cast::<i64>().write(11);
            assert_eq!(msrt_map_contains(&cloned, foreign, foreign, kp), 1);
            assert_eq!(
                *(msrt_map_get_ptr(&cloned, foreign, foreign, kp) as *const i64),
                5
            );
            let slot = msrt_map_slot_lent(&mut cloned, foreign, foreign, kp, vp);
            *(slot as *mut i64) = 9;
            assert_eq!(cloned.len, 1);
            let slot = msrt_map_slot_lent(&mut cloned, foreign, foreign, kp, vp);
            assert_eq!(*(slot as *const i64), 9);
            kp.cast::<i64>().write(21);
            msrt_map_add_default(&mut cloned, foreign, foreign, kp, vp);
            assert_eq!(cloned.len, 1);
            msrt_map_clear(&mut cloned, foreign, foreign);
            msrt_map_add(&mut cloned, foreign, foreign, kp, vp);
            kp.cast::<i64>().write(31);
            msrt_map_remove(&mut cloned, foreign, foreign, kp);
            assert_eq!(cloned.len, 0);
            // Read through the original variable as well as the raw pointer in this test.
            assert_eq!(k, 31);
            drop_map(&mut cloned, foreign, Some(foreign));
            drop_map(&mut m, foreign, Some(foreign));
            assert_eq!(crate::alloc::live_blocks(), before);
        }
    }

    #[test]
    fn borrowed_adds_keep_creator_identity_and_release_owned_values() {
        let _g = testutil::lock();
        let before = alloc::live_blocks();
        let unavailable = TypeDesc {
            eq: None,
            hash: None,
            ..MODULO_KEY
        };
        for default in [false, true] {
            for caller in [&msrt_desc_int, &unavailable] {
                // SAFETY: keys are i64 slots, values are owned strings, and the stamped
                // modulo descriptor supplies the creator's identity in both caller scopes.
                unsafe {
                    let mut m = empty();
                    msrt_map_stamp(&mut m, &MODULO_KEY);
                    let add = if default {
                        msrt_map_add_default_lent
                    } else {
                        msrt_map_add_lent
                    };
                    let mut value = from_bytes(b"first independently owned value for the map");
                    let key = 11i64;
                    add(
                        &mut m,
                        caller,
                        &msrt_desc_string,
                        (&raw const key).cast(),
                        (&raw mut value).cast(),
                    );
                    assert_eq!(key, 11);
                    let probe = 1i64;
                    let p =
                        msrt_map_get_ptr(&m, caller, &msrt_desc_string, (&raw const probe).cast());
                    assert!(
                        !p.is_null(),
                        "borrowed insertion must remain reachable through creator hashing"
                    );
                    assert_eq!(
                        string::bytes(p.cast()),
                        b"first independently owned value for the map"
                    );

                    let key = 21i64;
                    let mut value =
                        from_bytes(b"replacement independently owned value for the map");
                    add(
                        &mut m,
                        caller,
                        &msrt_desc_string,
                        (&raw const key).cast(),
                        (&raw mut value).cast(),
                    );
                    assert_eq!(key, 21);
                    assert_eq!(
                        m.len, 1,
                        "equal borrowed keys must not create duplicate entries"
                    );
                    let p =
                        msrt_map_get_ptr(&m, caller, &msrt_desc_string, (&raw const probe).cast());
                    assert_eq!(
                        string::bytes(p.cast()),
                        if default {
                            b"first independently owned value for the map".as_slice()
                        } else {
                            b"replacement independently owned value for the map".as_slice()
                        }
                    );
                    let mut keys = core::mem::MaybeUninit::uninit();
                    msrt_map_keys(&m, caller, &msrt_desc_string, keys.as_mut_ptr());
                    let mut keys = keys.assume_init();
                    assert_eq!(
                        *(keys.ptr as *const i64),
                        11,
                        "replacement keeps the original key"
                    );
                    crate::vec::drop_list(&mut keys, &MODULO_KEY);

                    let key = 12i64;
                    let mut value = from_bytes(b"second independently owned value for the map");
                    add(
                        &mut m,
                        caller,
                        &msrt_desc_string,
                        (&raw const key).cast(),
                        (&raw mut value).cast(),
                    );
                    assert_eq!(m.len, 2);
                    let probe = 2i64;
                    let p =
                        msrt_map_get_ptr(&m, caller, &msrt_desc_string, (&raw const probe).cast());
                    assert!(!p.is_null());
                    assert_eq!(
                        string::bytes(p.cast()),
                        b"second independently owned value for the map"
                    );
                    drop_map(&mut m, &MODULO_KEY, Some(&msrt_desc_string));
                }
                assert_eq!(alloc::live_blocks(), before);
            }
        }
    }

    #[test]
    fn borrowed_adds_without_creator_evidence_use_the_caller_identity() {
        let _g = testutil::lock();
        let before = alloc::live_blocks();
        for default in [false, true] {
            // SAFETY: these unstamped maps have i64 keys and values, described by the caller.
            unsafe {
                let mut m = empty();
                let add = if default {
                    msrt_map_add_default_lent
                } else {
                    msrt_map_add_lent
                };
                for (key, mut value) in [(1i64, 10i64), (11, 20), (1, 30)] {
                    add(
                        &mut m,
                        &msrt_desc_int,
                        &msrt_desc_int,
                        (&raw const key).cast(),
                        (&raw mut value).cast(),
                    );
                }
                assert!(m.desc.is_null());
                assert_eq!(m.len, 2);
                for (key, expected) in [(1i64, if default { 10 } else { 30 }), (11, 20)] {
                    let p = msrt_map_get_ptr(
                        &m,
                        &msrt_desc_int,
                        &msrt_desc_int,
                        (&raw const key).cast(),
                    );
                    assert!(!p.is_null());
                    assert_eq!(*(p as *const i64), expected);
                }
                drop_map(&mut m, &msrt_desc_int, Some(&msrt_desc_int));
            }
            assert_eq!(alloc::live_blocks(), before);
        }
    }

    /// Inserts a mixed stream of new and repeated keys through the general and the word `add`.
    #[test]
    fn word_add_matches_the_general_add() {
        let _g = testutil::lock();
        unsafe {
            let (sd, id) = (
                &msrt_desc_string as *const TypeDesc,
                &msrt_desc_int as *const TypeDesc,
            );
            let (mut gs, mut ws) = (empty(), empty());
            let (mut gi, mut wi) = (empty(), empty());
            for i in 0..2000i64 {
                let n = (i * 7919) % 300;
                for (m, word) in [(&mut gs, false), (&mut ws, true)] {
                    let mut k = from_bytes(format!("key-{n}").as_bytes());
                    let mut v = i;
                    let (kp, vp) = (&mut k as *mut _ as *mut u8, &mut v as *mut i64 as *mut u8);
                    if word {
                        msrt_map_add_sw8(m, sd, id, kp, vp);
                    } else {
                        msrt_map_add(m, sd, id, kp, vp);
                    }
                }
                for (m, word) in [(&mut gi, false), (&mut wi, true)] {
                    let (mut k, mut v) = (n * 31, i);
                    let (kp, vp) = (&mut k as *mut i64 as *mut u8, &mut v as *mut i64 as *mut u8);
                    if word {
                        msrt_map_add_w8(m, id, id, kp, vp);
                    } else {
                        msrt_map_add(m, id, id, kp, vp);
                    }
                }
            }
            assert_eq!((gs.len, gs.used), (ws.len, ws.used));
            assert_eq!((gi.len, gi.used), (wi.len, wi.used));
            for n in 0..320i64 {
                let k = from_bytes(format!("key-{n}").as_bytes());
                let (a, b) = (
                    msrt_map_get_ptr(&gs, sd, id, &k as *const _ as *const u8),
                    msrt_map_get_ptr(&ws, sd, id, &k as *const _ as *const u8),
                );
                assert_eq!(a.is_null(), b.is_null(), "string key {n}");
                if !a.is_null() {
                    assert_eq!(*(a as *const i64), *(b as *const i64), "string key {n}");
                }
                let ki = n * 31;
                let (a, b) = (
                    msrt_map_get_ptr(&gi, id, id, &ki as *const i64 as *const u8),
                    msrt_map_get_ptr(&wi, id, id, &ki as *const i64 as *const u8),
                );
                assert_eq!(a.is_null(), b.is_null(), "int key {n}");
                if !a.is_null() {
                    assert_eq!(*(a as *const i64), *(b as *const i64), "int key {n}");
                }
            }
            for (m, d) in [(&mut gs, sd), (&mut ws, sd), (&mut gi, id), (&mut wi, id)] {
                drop_map(m, &*d, Some(&*id));
            }
        }
    }

    #[test]
    fn string_word_entry_points_match_the_general_ones() {
        let _g = testutil::lock();
        unsafe {
            let (kd, vd) = (
                &msrt_desc_string as *const TypeDesc,
                &msrt_desc_int as *const TypeDesc,
            );
            let mut m = empty();
            for i in 0..200i64 {
                let mut k = from_bytes(format!("key-{}", i * 3).as_bytes());
                let mut v = i;
                msrt_map_add(
                    &mut m,
                    kd,
                    vd,
                    &mut k as *mut _ as *mut u8,
                    &mut v as *mut i64 as *mut u8,
                );
            }
            for i in 0..50i64 {
                let k = from_bytes(format!("key-{}", i * 6).as_bytes());
                remove(&mut m, &*kd, Some(&*vd), &k as *const _ as *const u8);
            }
            for i in -3..700i64 {
                let k = from_bytes(format!("key-{i}").as_bytes());
                let kp = &k as *const _ as *const u8;
                assert_eq!(
                    msrt_map_get_ptr(&m, kd, vd, kp),
                    msrt_map_get_ptr_sw8(&m, kd, vd, kp),
                    "key {i}"
                );
                assert_eq!(
                    msrt_map_contains(&m, kd, vd, kp),
                    msrt_map_contains_sw8(&m, kd, vd, kp)
                );
                let (mut a, mut b) = (0i64, 0i64);
                let ga = msrt_map_get(&m, kd, vd, kp, &mut a as *mut i64 as *mut u8);
                let gb = msrt_map_get_sw8(&m, kd, vd, kp, &mut b as *mut i64 as *mut u8);
                assert_eq!((ga, a), (gb, b));
            }
            drop_map(&mut m, &*kd, Some(&*vd));
        }
    }

    #[test]
    fn word_entry_points_match_the_general_ones() {
        let _g = testutil::lock();
        unsafe {
            let d = &msrt_desc_int as *const TypeDesc;
            let mut m = empty();
            for i in 0..300i64 {
                let (mut k, mut v) = (i * 31, i);
                msrt_map_add(
                    &mut m,
                    d,
                    d,
                    &mut k as *mut i64 as *mut u8,
                    &mut v as *mut i64 as *mut u8,
                );
            }
            for i in 0..100i64 {
                remove(&mut m, &*d, Some(&*d), &(i * 62) as *const i64 as *const u8);
            }
            for i in -5..1000i64 {
                let k = &i as *const i64 as *const u8;
                let general = msrt_map_get_ptr(&m, d, d, k);
                let word = msrt_map_get_ptr_w8(&m, d, d, k);
                assert_eq!(general, word, "key {i}");
                assert_eq!(
                    msrt_map_contains(&m, d, d, k),
                    msrt_map_contains_w8(&m, d, d, k)
                );
                let (mut a, mut b) = (0i64, 0i64);
                let (ga, gb) = (
                    msrt_map_get(&m, d, d, k, &mut a as *mut i64 as *mut u8),
                    msrt_map_get_w8(&m, d, d, k, &mut b as *mut i64 as *mut u8),
                );
                assert_eq!((ga, a), (gb, b));
            }
            let mut empty_map = empty();
            let k = 1i64;
            assert!(msrt_map_get_ptr_w8(&empty_map, d, d, &k as *const i64 as *const u8).is_null());
            drop_map(&mut empty_map, &*d, Some(&*d));
            drop_map(&mut m, &*d, Some(&*d));
        }
    }

    #[test]
    fn int_pair_fast_paths() {
        let _g = testutil::lock();
        unsafe {
            let d = &msrt_desc_int as *const TypeDesc;
            let mut m = empty();
            for round in 0..3i64 {
                for i in 0..50i64 {
                    let (mut k, mut v) = (i, round);
                    msrt_map_add(
                        &mut m,
                        d,
                        d,
                        &mut k as *mut i64 as *mut u8,
                        &mut v as *mut i64 as *mut u8,
                    );
                }
            }
            assert_eq!(m.len, 50);
            let mut k = 7i64;
            let p = msrt_map_get_ptr(&m, d, d, &k as *const i64 as *const u8);
            assert_eq!(*(p as *const i64), 2);
            assert!(remove(
                &mut m,
                &*d,
                Some(&*d),
                &k as *const i64 as *const u8
            ));
            assert!(msrt_map_get_ptr(&m, d, d, &k as *const i64 as *const u8).is_null());
            let mut v = 9i64;
            msrt_map_add(
                &mut m,
                d,
                d,
                &mut k as *mut i64 as *mut u8,
                &mut v as *mut i64 as *mut u8,
            );
            assert_eq!(m.len, 50);
            let p = msrt_map_get_ptr(&m, d, d, &k as *const i64 as *const u8);
            assert_eq!(*(p as *const i64), 9);
            drop_map(&mut m, &*d, Some(&*d));
        }
    }

    #[test]
    fn slot_finds_or_creates_with_the_default() {
        let _g = testutil::lock();
        unsafe {
            let d = &msrt_desc_int as *const TypeDesc;
            let mut m = empty();
            for round in 0..3i64 {
                for i in 0..40i64 {
                    let (mut k, mut def) = (i, 10i64);
                    let p = msrt_map_slot_lent(
                        &mut m,
                        d,
                        d,
                        &mut k as *mut i64 as *const u8,
                        &mut def as *mut i64 as *mut u8,
                    ) as *mut i64;
                    assert_eq!(*p, 10 + round);
                    *p += 1;
                }
            }
            assert_eq!(m.len, 40);
            let k = 5i64;
            let p = msrt_map_get_ptr(&m, d, d, &k as *const i64 as *const u8);
            assert_eq!(*(p as *const i64), 13);
            drop_map(&mut m, &*d, Some(&*d));
        }
    }

    #[test]
    fn insertion_order_replace_remove_compact() {
        let _g = testutil::lock();
        unsafe {
            let (kd, vd) = (&msrt_desc_int, &msrt_desc_int);
            let mut m = empty();
            for i in 0..100i64 {
                let (mut k, mut v) = (i, i * 10);
                insert(
                    &mut m,
                    kd,
                    Some(vd),
                    &mut k as *mut i64 as *mut u8,
                    &mut v as *mut i64 as *mut u8,
                );
            }
            // Replacing keeps position.
            let (mut k, mut v) = (5i64, -1i64);
            assert!(!insert(
                &mut m,
                kd,
                Some(vd),
                &mut k as *mut i64 as *mut u8,
                &mut v as *mut i64 as *mut u8
            ));
            for i in 0..90i64 {
                let k = i;
                assert!(remove(&mut m, kd, Some(vd), &k as *const i64 as *const u8));
            }
            assert_eq!(m.len, 10);
            let mut keys = VecVal {
                ptr: core::ptr::null_mut(),
                len: 0,
                cap: 0,
            };
            msrt_map_keys(&m, kd, vd, &mut keys);
            let ks: std::vec::Vec<i64> = (0..keys.len)
                .map(|i| *(keys.ptr as *const i64).add(i))
                .collect();
            assert_eq!(ks, (90..100).collect::<std::vec::Vec<_>>());
            let k = 95i64;
            let p = msrt_map_get_ptr(&m, kd, vd, &k as *const i64 as *const u8);
            assert_eq!(*(p as *const i64), 950);
            drop_map(&mut m, kd, Some(vd));
            crate::vec::drop_list(&mut keys, kd);
        }
    }

    #[test]
    fn string_keys_and_set_algebra() {
        let _g = testutil::lock();
        unsafe {
            let kd = &msrt_desc_string;
            let before = crate::alloc::live_blocks();
            let mut a = empty();
            let mut b = empty();
            for (set, items) in [(&mut a, ["x", "y", "z"]), (&mut b, ["y", "w", "z"])] {
                for it in items {
                    let mut k = from_bytes(it.as_bytes());
                    insert(
                        set,
                        kd,
                        None,
                        &mut k as *mut _ as *mut u8,
                        core::ptr::null_mut(),
                    );
                }
            }
            let mut out = empty();
            msrt_set_symmetric_difference(&a, &b, kd, &mut out);
            let mut vals = VecVal {
                ptr: core::ptr::null_mut(),
                len: 0,
                cap: 0,
            };
            msrt_map_keys(&out, kd, core::ptr::null(), &mut vals);
            let got: std::vec::Vec<_> = (0..vals.len)
                .map(|i| {
                    std::string::String::from_utf8_lossy(string::bytes(
                        (vals.ptr as *const StrVal).add(i),
                    ))
                    .into_owned()
                })
                .collect();
            assert_eq!(got, ["x", "w"]);
            assert_eq!(msrt_set_is_subset_of(&out, &a, kd), 0);
            crate::vec::drop_list(&mut vals, kd);
            drop_map(&mut out, kd, None);
            drop_map(&mut a, kd, None);
            drop_map(&mut b, kd, None);
            assert_eq!(crate::alloc::live_blocks(), before);
        }
    }
    #[test]
    fn string_to_int_fast_paths_overwrite_and_release() {
        let _g = testutil::lock();
        unsafe {
            let (kd, vd) = (&msrt_desc_string, &msrt_desc_int);
            let before = crate::alloc::live_blocks();
            let mut m = empty();
            for round in 0..3i64 {
                for i in 0..200 {
                    let mut k = from_bytes(std::format!("key-{i}").as_bytes());
                    let mut v = round * 1000 + i;
                    msrt_map_add(
                        &mut m,
                        kd,
                        vd,
                        &mut k as *mut _ as *mut u8,
                        &mut v as *mut i64 as *mut u8,
                    );
                }
            }
            assert_eq!(m.len, 200);
            for i in [0i64, 77, 199] {
                // A different object with equal bytes finds the stored key.
                let k = from_bytes(std::format!("key-{i}").as_bytes());
                let kp = &k as *const _ as *const u8;
                assert_eq!(msrt_map_contains(&m, kd, vd, kp), 1);
                let mut out = 0i64;
                assert_eq!(
                    msrt_map_get(&m, kd, vd, kp, &mut out as *mut i64 as *mut u8),
                    1
                );
                assert_eq!(out, 2000 + i);
                slot_drop(kd, kp as *mut u8);
            }
            let missing = from_bytes(b"absent");
            let mp = &missing as *const _ as *const u8;
            assert_eq!(msrt_map_contains(&m, kd, vd, mp), 0);
            let mut out = 0i64;
            assert_eq!(
                msrt_map_get(&m, kd, vd, mp, &mut out as *mut i64 as *mut u8),
                0
            );
            slot_drop(kd, mp as *mut u8);
            drop_map(&mut m, kd, Some(vd));
            assert_eq!(crate::alloc::live_blocks(), before);
        }
    }
}
