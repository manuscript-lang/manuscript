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

const LIVE: u64 = 1 << 63;
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
        slots: core::ptr::null_mut(),
        index: core::ptr::null_mut(),
        len: 0,
        used: 0,
        cap: 0,
        mask: 0,
    }
}

#[derive(Clone, Copy)]
struct Layout {
    koff: usize,
    voff: usize,
    stride: usize,
    ksize: usize,
    vsize: usize,
}

/// `copy_nonoverlapping` with the 8-byte case (Int/Float/pointer slots) inline. A byte copy keeps
/// the provenance of pointer slots, which an integer load and store would drop.
#[inline(always)]
unsafe fn copy_slot(src: *const u8, dst: *mut u8, n: usize) {
    // SAFETY: caller contract of `copy_nonoverlapping`.
    unsafe {
        if n == 8 {
            core::ptr::copy_nonoverlapping(src, dst, 8);
        } else {
            core::ptr::copy_nonoverlapping(src, dst, n);
        }
    }
}

fn align_up(n: usize, a: usize) -> usize {
    (n + a - 1) & !(a - 1)
}

#[inline(always)]
fn layout(kd: &TypeDesc, vd: Option<&TypeDesc>) -> Layout {
    // 8-byte, 8-aligned keys and values (Int, Float, pointers) are the common case; a constant
    // layout spares the alignment arithmetic on every lookup.
    if kd.size == 8 && kd.align == 8 && vd.is_some_and(|v| v.size == 8 && v.align == 8) {
        return Layout {
            koff: 8,
            voff: 16,
            stride: 24,
            ksize: 8,
            vsize: 8,
        };
    }
    layout_general(kd, vd)
}

fn layout_general(kd: &TypeDesc, vd: Option<&TypeDesc>) -> Layout {
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
unsafe fn slot(m: &MapVal, l: &Layout, i: usize) -> *mut u8 {
    // SAFETY: `i < used`.
    unsafe { m.slots.add(i * l.stride) }
}

#[inline(always)]
unsafe fn slot_hash_of(p: *mut u8) -> u64 {
    // SAFETY: slots start with the hash word.
    unsafe { *(p as *const u64) }
}

#[inline(always)]
fn hash_key(kd: &TypeDesc, key: *const u8) -> u64 {
    // SAFETY: the key slot is live.
    unsafe {
        if kd.kind == KIND_INT {
            return crate::string::mix(*(key as *const u64) ^ 0x9e37_79b9) | LIVE;
        }
        slot_hash(kd, key) | LIVE
    }
}

/// Key equality with `Int` keys (the common case) compared inline.
#[inline(always)]
unsafe fn keys_eq(kd: &TypeDesc, a: *const u8, b: *const u8) -> bool {
    // SAFETY: both are live key slots of `kd`.
    unsafe {
        if kd.kind == KIND_INT {
            return *(a as *const i64) == *(b as *const i64);
        }
        slot_eq(kd, a, b)
    }
}

/// Finds the slot index of `key`.
unsafe fn find(m: &MapVal, kd: &TypeDesc, l: &Layout, key: *const u8, h: u64) -> Option<usize> {
    if m.len == 0 {
        return None;
    }
    // SAFETY: index and slots are consistent for a non-empty map.
    unsafe {
        let mut pos = (h as usize ^ (h >> 32) as usize) & m.mask;
        loop {
            let e = *index_of(m).add(pos);
            if e == 0 {
                return None;
            }
            if (e ^ h) >> 32 == 0 {
                let i = (e as u32 - 1) as usize;
                let p = slot(m, l, i);
                if slot_hash_of(p) == h && keys_eq(kd, p.add(l.koff), key) {
                    return Some(i);
                }
            }
            pos = (pos + 1) & m.mask;
        }
    }
}

/// True for `Int` keys with 8-byte, 8-aligned values: slots are `{ hash, key, value }` at a
/// constant 24-byte stride, so lookups need no descriptor arithmetic or equality calls.
#[inline(always)]
fn int_pair(kd: &TypeDesc, vd: Option<&TypeDesc>) -> bool {
    kd.kind == KIND_INT && vd.is_some_and(|v| v.size == 8 && v.align == 8)
}

/// `find` specialised for [`int_pair`] maps; returns the slot pointer.
#[inline(always)]
unsafe fn find_int(m: &MapVal, key: i64) -> *mut u8 {
    if m.len == 0 {
        return core::ptr::null_mut();
    }
    // SAFETY: index and slots are consistent for a non-empty map.
    unsafe {
        let h = crate::string::mix(key as u64 ^ 0x9e37_79b9) | LIVE;
        let index = index_of(m);
        let mut pos = (h as usize ^ (h >> 32) as usize) & m.mask;
        loop {
            let e = *index.add(pos);
            if e == 0 {
                return core::ptr::null_mut();
            }
            if (e ^ h) >> 32 == 0 {
                let p = m.slots.add((e as u32 - 1) as usize * 24);
                if *(p as *const u64) == h && *(p.add(8) as *const i64) == key {
                    return p;
                }
            }
            pos = (pos + 1) & m.mask;
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
    unsafe { find(m, kd, &layout(kd, vd), key, hash_key(kd, key)).is_some() }
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
    unsafe {
        let l = layout(kd, vd);
        let h = hash_key(kd, key);
        if let Some(i) = find(m, kd, &l, key, h) {
            let p = slot(m, &l, i);
            slot_drop(kd, key);
            if let Some(vd) = vd {
                slot_drop(vd, p.add(l.voff));
                copy_slot(val, p.add(l.voff), l.vsize);
            }
            return false;
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
        true
    }
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
    unsafe {
        let l = layout(kd, vd);
        let h = hash_key(kd, key);
        let Some(i) = find(m, kd, &l, key, h) else {
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
        let l = layout(kd, vd);
        let i = find(m, kd, &l, key, hash_key(kd, key))?;
        Some(slot(m, &l, i))
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
            for i in 0..m.used {
                let p = slot(m, &l, i);
                if slot_hash_of(p) & LIVE != 0 {
                    slot_drop(kd, p.add(l.koff));
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
        *m = empty();
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

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_map_drop(
    m: *mut MapVal,
    kd: *const TypeDesc,
    vd: *const TypeDesc,
) {
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
    // SAFETY: caller contract.
    unsafe { copy_map(m, &*kd, opt(vd), out) }
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
    // SAFETY: caller contract.
    unsafe {
        let (m, kd, vd) = (&mut *m, &*kd, opt(vd));
        if int_pair(kd, vd) && vd.is_some_and(needs_no_drop) {
            // Int keys and scalar values own nothing: overwrite an existing entry in place.
            let p = find_int(m, *(key as *const i64));
            if !p.is_null() {
                core::ptr::copy_nonoverlapping(val, p.add(16), 8);
                return;
            }
        }
        insert(m, kd, vd, key, val);
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
    // SAFETY: caller contract.
    unsafe {
        let (kd, m) = (&*kd, &*m);
        if int_pair(kd, opt(vd)) {
            let p = find_int(m, *(key as *const i64));
            return if p.is_null() { p } else { p.add(16) };
        }
        let l = layout(kd, opt(vd));
        match find(m, kd, &l, key, hash_key(kd, key)) {
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
    // SAFETY: caller contract.
    unsafe {
        let p = msrt_map_get_ptr(m, kd, vd, key);
        if p.is_null() {
            return 0;
        }
        slot_copy(&*vd, p, out);
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
    // SAFETY: caller contract.
    unsafe { drop_map(m, &*kd, opt(vd)) }
}

/// `length()`: the number of live entries.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_map_length(m: *const MapVal) -> i64 {
    // SAFETY: caller contract.
    unsafe { (*m).len as i64 }
}

/// Number of slots to scan with [`msrt_map_entry_ptrs`] (live entries plus holes).
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_map_slot_count(m: *const MapVal) -> i64 {
    // SAFETY: caller contract.
    unsafe { (*m).used as i64 }
}

/// Borrowed pointers to the key and value of slot `i`; 0 for a hole.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_map_entry_ptrs(
    m: *const MapVal,
    kd: *const TypeDesc,
    vd: *const TypeDesc,
    i: i64,
    key_out: *mut *const u8,
    val_out: *mut *const u8,
) -> u8 {
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

/// `keys()` / `Set.values()` as a fresh list of copies.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_map_keys(
    m: *const MapVal,
    kd: *const TypeDesc,
    vd: *const TypeDesc,
    out: *mut VecVal,
) {
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
    // SAFETY: caller contract.
    unsafe { collect(m, &*kd, opt(vd), false, out) }
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
    // SAFETY: caller contract.
    unsafe { msrt_set_is_subset_of(b, a, kd) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_set_is_disjoint_from(
    a: *const MapVal,
    b: *const MapVal,
    kd: *const TypeDesc,
) -> u8 {
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
                        *(vals.ptr as *const *const StrObj).add(i),
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
}
