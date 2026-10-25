//! `Map[K, V]` and `Set[T]`: insertion-ordered hash tables stored as `MapVal`.
//!
//! `slots` is an append-only array of entries `{ hash: u64 (top bit set = live), key, value }`
//! spaced `stride` bytes apart; `index` is an open-addressing table of `u64` entries: the
//! high word is the hash's high word (a tag, so probes skip non-matching slots without touching
//! them) and the low word is the slot number (`0` empty, `u32::MAX` removed, otherwise slot + 1). Removal leaves a hole that scans
//! skip and compaction reclaims once more than half the slots are holes.
use crate::alloc;
use crate::desc::{needs_no_drop, slot_copy, slot_drop, slot_eq, slot_hash};
use crate::fault;
use ms_rt_abi::*;

use ms_rt_hot::{LIVE, Layout, is_word, key_desc, layout, slot};
const REMOVED: u64 = u32::MAX as u64;

#[inline(always)]
fn entry(h: u64, slot: usize) -> u64 {
    (h & !0xFFFF_FFFF) | (slot as u64 + 1)
}

#[inline(always)]
fn index_of(m: &MapVal) -> *mut u64 {
    m.index as *mut u64
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
    layout(kd, vd)
}

#[inline(always)]
unsafe fn slot_hash_of(p: *mut u8) -> u64 {
    // SAFETY: slots start with the hash word.
    unsafe { *(p as *const u64) }
}

/// Hash, equality and ownership of one key type, resolved once per call by [`keyed!`] so that
/// each key kind gets its own inlined probe loop. `Dyn` is the descriptor-driven fallback for
/// every other key type.
trait KeyOps {
    /// True when key equality is cheap enough to skip the stored full-hash comparison.
    const CHEAP_EQ: bool = false;
    /// True when the key slot is always an 8-byte, 8-aligned word.
    const WORD_KEY: bool = false;
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
        // SAFETY: the key slot is live.
        unsafe { slot_hash(kd, key) }
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
        let l = layout(kd, vd);
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
        let size = m.mask + 1;
        rebuild_index(m, l, size);
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
            fault::fault(b"map size overflow");
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
pub unsafe extern "C-unwind" fn msrt_map_new(out: *mut MapVal) {
    // SAFETY: `out` is writable.
    unsafe { *out = empty() }
}

/// Records creator evidence only for an unstamped collection. Native operations may already
/// return a copy or derived collection retaining its original creator.
/// `kd` and its nested descriptors and callbacks must be static.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_map_stamp(m: *mut MapVal, kd: *const TypeDesc) {
    // SAFETY: `m` is a live map; descriptors are static.
    unsafe {
        if (*m).desc.is_null() {
            (*m).desc = kd;
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_map_drop(
    m: *mut MapVal,
    kd: *const TypeDesc,
    vd: *const TypeDesc,
) {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract.
    unsafe { drop_map(m, &*kd, opt(vd)) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_map_copy(
    m: *const MapVal,
    kd: *const TypeDesc,
    vd: *const TypeDesc,
    out: *mut MapVal,
) {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract.
    unsafe { copy_map(m, &*kd, opt(vd), out) }
}

/// Makes room for `n` entries so that inserting that many never regrows the map.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_map_reserve(
    m: *mut MapVal,
    kd: *const TypeDesc,
    vd: *const TypeDesc,
    n: i64,
) {
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
pub unsafe extern "C-unwind" fn msrt_map_add(
    m: *mut MapVal,
    kd: *const TypeDesc,
    vd: *const TypeDesc,
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
pub unsafe extern "C-unwind" fn msrt_map_add_w8(
    m: *mut MapVal,
    _kd: *const TypeDesc,
    _vd: *const TypeDesc,
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
pub unsafe extern "C-unwind" fn msrt_map_add_sw8(
    m: *mut MapVal,
    _kd: *const TypeDesc,
    _vd: *const TypeDesc,
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

/// The value slot of `key`, appending the entry with the 8-byte scalar at `default` when it is
/// absent; `key` is consumed. One hash and probe serve a read-modify-write such as `m[k] += 1`:
/// the caller loads, changes and stores through the returned pointer before the map is used again.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_map_slot(
    m: *mut MapVal,
    kd: *const TypeDesc,
    vd: *const TypeDesc,
    key: *mut u8,
    default: *mut u8,
) -> *mut u8 {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract; the value type is an 8-byte scalar.
    unsafe {
        let (m, kd, vd) = (&mut *m, &*kd, &*vd);
        keyed!(kd, |K| upsert_k::<K>(m, kd, Some(vd), key, default, false)
            .0)
    }
}

/// Like [`msrt_map_slot`] but `key` is only borrowed: it is copied into the map when the entry is
/// absent, so a lookup that hits never allocates a key.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_map_slot_lent(
    m: *mut MapVal,
    kd: *const TypeDesc,
    vd: *const TypeDesc,
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
pub unsafe extern "C-unwind" fn msrt_map_add_lent(
    m: *mut MapVal,
    kd: *const TypeDesc,
    vd: *const TypeDesc,
    key: *const u8,
    val: *mut u8,
) {
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
pub unsafe extern "C-unwind" fn msrt_map_add_default_lent(
    m: *mut MapVal,
    kd: *const TypeDesc,
    vd: *const TypeDesc,
    key: *const u8,
    val: *mut u8,
) {
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
pub unsafe extern "C-unwind" fn msrt_map_add_default(
    m: *mut MapVal,
    kd: *const TypeDesc,
    vd: *const TypeDesc,
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
pub unsafe extern "C-unwind" fn msrt_map_remove(
    m: *mut MapVal,
    kd: *const TypeDesc,
    vd: *const TypeDesc,
    key: *const u8,
) {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract.
    unsafe {
        remove(&mut *m, &*kd, opt(vd), key);
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_map_contains(
    m: *const MapVal,
    kd: *const TypeDesc,
    vd: *const TypeDesc,
    key: *const u8,
) -> u8 {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract.
    unsafe { contains_key(&*m, &*kd, opt(vd), key) as u8 }
}

/// Borrowed pointer to the value of `key`, or null.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_map_get_ptr(
    m: *const MapVal,
    kd: *const TypeDesc,
    vd: *const TypeDesc,
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
pub unsafe extern "C-unwind" fn msrt_map_get(
    m: *const MapVal,
    kd: *const TypeDesc,
    vd: *const TypeDesc,
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
pub unsafe extern "C-unwind" fn msrt_map_clear(
    m: *mut MapVal,
    kd: *const TypeDesc,
    vd: *const TypeDesc,
) {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract.
    unsafe { drop_map(m, &*kd, opt(vd)) }
}

/// `keys()` / `Set.values()` as a fresh list of copies.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_map_keys(
    m: *const MapVal,
    kd: *const TypeDesc,
    vd: *const TypeDesc,
    out: *mut VecVal,
) {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract.
    unsafe { collect(m, &*kd, opt(vd), true, out) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_map_values(
    m: *const MapVal,
    kd: *const TypeDesc,
    vd: *const TypeDesc,
    out: *mut VecVal,
) {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract.
    unsafe { collect(m, &*kd, opt(vd), false, out) }
}

/// `for k in m.keys()` over a map that outlives the loop unchanged: string keys come back as
/// views of the map's own strings, so nothing is copied. Other keys are copied as by `keys`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_map_keys_view(
    m: *const MapVal,
    kd: *const TypeDesc,
    vd: *const TypeDesc,
    out: *mut VecVal,
) {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract.
    unsafe { collect_view(m, &*kd, opt(vd), true, out) }
}

/// `for v in m.values()` over a map that outlives the loop unchanged (see [`msrt_map_keys_view`]).
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_map_values_view(
    m: *const MapVal,
    kd: *const TypeDesc,
    vd: *const TypeDesc,
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
pub unsafe extern "C-unwind" fn msrt_map_merge(
    m: *mut MapVal,
    other: *const MapVal,
    kd: *const TypeDesc,
    vd: *const TypeDesc,
) {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract.
    unsafe {
        let (kd, vdo) = (&*kd, opt(vd));
        let l = layout(kd, vdo);
        let o = &*other;
        for i in 0..o.used {
            let p = slot(o, &l, i);
            if slot_hash_of(p) & LIVE == 0 {
                continue;
            }
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
            slot_copy(kd, p.add(l.koff), kp);
            if let Some(v) = vdo {
                slot_copy(v, p.add(l.voff), vp);
            }
            insert(&mut *m, kd, vdo, kp, vp);
            if l.ksize > 64 {
                alloc::free(kp);
            }
            if l.vsize > 64 {
                alloc::free(vp);
            }
        }
    }
}

// ---- Set algebra (all produce fresh sets in left order) ----

unsafe fn add_copy(m: &mut MapVal, kd: &TypeDesc, p: *const u8) {
    // SAFETY: `p` is a live key slot.
    unsafe {
        if contains_key(m, kd, None, p) {
            return;
        }
        let mut buf = [0u64; 8];
        let k = if kd.size as usize <= 64 {
            buf.as_mut_ptr() as *mut u8
        } else {
            alloc::alloc(kd.size as usize)
        };
        slot_copy(kd, p, k);
        insert(m, kd, None, k, core::ptr::null_mut());
        if kd.size as usize > 64 {
            alloc::free(k);
        }
    }
}

unsafe fn each_key(m: &MapVal, kd: &TypeDesc, mut f: impl FnMut(*const u8)) {
    // SAFETY: slots are consistent.
    unsafe {
        let l = layout(kd, None);
        for i in 0..m.used {
            let p = slot(m, &l, i);
            if slot_hash_of(p) & LIVE != 0 {
                f(p.add(l.koff));
            }
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_set_add_copy(
    m: *mut MapVal,
    kd: *const TypeDesc,
    key: *const u8,
) {
    let kd = key_desc(m, kd);
    // SAFETY: caller contract.
    unsafe { add_copy(&mut *m, &*kd, key) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_set_union(
    a: *const MapVal,
    b: *const MapVal,
    kd: *const TypeDesc,
    out: *mut MapVal,
) {
    let kd = key_desc(a, kd);
    // SAFETY: caller contract.
    unsafe {
        let kd = &*kd;
        copy_map(a, kd, None, out);
        each_key(&*b, kd, |k| add_copy(&mut *out, kd, k));
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
                add_copy(&mut *out, kd, k);
            }
        });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_set_intersection(
    a: *const MapVal,
    b: *const MapVal,
    kd: *const TypeDesc,
    out: *mut MapVal,
) {
    let kd = key_desc(a, kd);
    // SAFETY: caller contract.
    unsafe {
        let kd = &*kd;
        filter_into(&*a, kd, out, |k| contains_key(&*b, kd, None, k));
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_set_difference(
    a: *const MapVal,
    b: *const MapVal,
    kd: *const TypeDesc,
    out: *mut MapVal,
) {
    let kd = key_desc(a, kd);
    // SAFETY: caller contract.
    unsafe {
        let kd = &*kd;
        filter_into(&*a, kd, out, |k| !contains_key(&*b, kd, None, k));
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_set_symmetric_difference(
    a: *const MapVal,
    b: *const MapVal,
    kd: *const TypeDesc,
    out: *mut MapVal,
) {
    let kd = key_desc(a, kd);
    // SAFETY: caller contract.
    unsafe {
        let kd = &*kd;
        filter_into(&*a, kd, out, |k| !contains_key(&*b, kd, None, k));
        each_key(&*b, kd, |k| {
            if !contains_key(&*a, kd, None, k) {
                add_copy(&mut *out, kd, k);
            }
        });
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_set_is_subset_of(
    a: *const MapVal,
    b: *const MapVal,
    kd: *const TypeDesc,
) -> u8 {
    let kd = key_desc(a, kd);
    // SAFETY: caller contract.
    unsafe {
        let kd = &*kd;
        let mut ok = true;
        each_key(&*a, kd, |k| ok &= contains_key(&*b, kd, None, k));
        ok as u8
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_set_is_superset_of(
    a: *const MapVal,
    b: *const MapVal,
    kd: *const TypeDesc,
) -> u8 {
    let kd = key_desc(a, kd);
    // SAFETY: caller contract.
    unsafe { msrt_set_is_subset_of(b, a, kd) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_set_is_disjoint_from(
    a: *const MapVal,
    b: *const MapVal,
    kd: *const TypeDesc,
) -> u8 {
    let kd = key_desc(a, kd);
    // SAFETY: caller contract.
    unsafe {
        let kd = &*kd;
        let mut ok = true;
        each_key(&*a, kd, |k| ok &= !contains_key(&*b, kd, None, k));
        ok as u8
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::desc::{msrt_desc_int, msrt_desc_string};
    use crate::string::{self, from_bytes};
    use crate::testutil;
    use crate::testutil::hot::*;

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
            let slot = msrt_map_slot(&mut cloned, foreign, foreign, kp, vp);
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
                    let p = msrt_map_slot(
                        &mut m,
                        d,
                        d,
                        &mut k as *mut i64 as *mut u8,
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
