//! Pure runtime helpers that release builds inline into compiled programs.
//!
//! `ms build` links this crate's bitcode into the program module before LLVM optimizes it, so a
//! map probe or string compare becomes part of the caller. That only works for functions that are
//! safe to duplicate: **pure** ones. A hot function must
//!
//! - read only its arguments and the memory they point to (and write only an output argument),
//! - own no `static`, thread-local, atomic or lock, and call nothing that does (no allocation,
//!   no fault, no I/O, no descriptor callback that could run user code),
//! - use no `global_asm!`, `#[link_section]` or other symbol the archive must define once.
//!
//! The build step marks every function of the bitcode `alwaysinline`: LLVM's cost model would
//! otherwise leave the probe loops as calls, which is most of what linking the bitcode removes.
//!
//! Exported functions take and return integers only (`usize` for pointers): the generated code
//! declares every runtime symbol with integer types, and LLVM inlines only a call whose callee has
//! the same signature.
//!
//! Everything stateful stays in `ms-rt` and links as an opaque archive. `ms-rt` itself calls these
//! functions too, so the archive and the bitcode come from one source. See `crates/DESIGN.md`.
//! ms: domain map
#![no_std]
#![allow(clippy::missing_safety_doc)]
// Raw views of the runtime's memory, as in `ms-rt`.
#![allow(unsafe_code)]

use ms_rt_abi::{MapVal, StrVal, TypeDesc};

/// Top bit of a slot's hash word: set for a live entry, clear for a removed one.
pub const LIVE: u64 = 1 << 63;

// ---------------------------------------------------------------------------
// Strings
// ---------------------------------------------------------------------------

/// Bytes of a string.
///
/// # Safety
/// `s` must be a live string for the lifetime `'a`.
#[inline(always)]
pub unsafe fn bytes<'a>(s: *const StrVal) -> &'a [u8] {
    // SAFETY: `ptr..ptr+len` holds the text.
    unsafe { core::slice::from_raw_parts((*s).data(), (*s).len()) }
}

/// Content equality.
///
/// # Safety
/// Both strings live.
#[inline]
pub unsafe fn equal(a: *const StrVal, b: *const StrVal) -> bool {
    // SAFETY: caller contract.
    unsafe { ((*a).ptr_word == (*b).ptr_word && (*a).tagged == (*b).tagged) || bytes_eq(a, b) }
}

/// C view: `msrt_string_eq(a: *const StrVal, b: *const StrVal) -> u8`
#[unsafe(no_mangle)]
// ms: leaf pure domain=string
pub unsafe extern "C-unwind" fn msrt_string_eq(a: usize, b: usize) -> u8 {
    // SAFETY: caller passes live strings.
    unsafe { equal(a as *const StrVal, b as *const StrVal) as u8 }
}

unsafe extern "C-unwind" {
    /// The general substring search, in the runtime archive.
    fn msrt_string_contains_long(a: usize, v: usize) -> u8;
}

/// C view: `msrt_string_contains(a: *const StrVal, v: *const StrVal) -> u8`
///
/// A one-byte needle in a short text is a scan the caller inlines (`"+-*/".contains(op)`); every
/// other search calls the runtime.
#[unsafe(no_mangle)]
// ms: leaf pure domain=string
pub unsafe extern "C-unwind" fn msrt_string_contains(a: usize, v: usize) -> u8 {
    // SAFETY: caller passes live strings.
    unsafe {
        let hay = bytes(a as *const StrVal);
        match bytes(v as *const StrVal) {
            [] => 1,
            [c] if hay.len() < 32 => hay.contains(c) as u8,
            _ => msrt_string_contains_long(a, v),
        }
    }
}

/// Haystacks shorter than this are scanned byte by byte: the vector searchers' setup costs more
/// than the scan.
pub const SHORT_HAY: usize = 32;

/// Haystacks shorter than this (a line of a log or a record) are also scanned directly for a
/// needle of two or more bytes: building a `memmem` searcher per call costs several times the
/// scan of so few bytes.
pub const MEDIUM_HAY: usize = 128;

/// `find` for a short haystack and a non-empty needle.
#[inline]
pub fn find_short(hay: &[u8], needle: &[u8]) -> Option<usize> {
    let (&first, rest) = needle.split_first()?;
    let last = hay.len().checked_sub(needle.len())?;
    let mut i = 0;
    while i <= last {
        i += memchr_short(first, &hay[i..=last])?;
        if hay[i + 1..i + needle.len()] == *rest {
            return Some(i);
        }
        i += 1;
    }
    None
}

/// `memchr` for a short haystack: eight bytes per step, testing each word for a byte equal to
/// `c` with the zero-byte trick.
#[inline]
pub fn memchr_short(c: u8, hay: &[u8]) -> Option<usize> {
    const LO: u64 = 0x0101_0101_0101_0101;
    const HI: u64 = 0x8080_8080_8080_8080;
    let pat = LO * c as u64;
    let (chunks, rest) = hay.as_chunks::<8>();
    let mut at = 0;
    for w in chunks {
        let x = u64::from_le_bytes(*w) ^ pat;
        let hit = x.wrapping_sub(LO) & !x & HI;
        if hit != 0 {
            return Some(at + hit.trailing_zeros() as usize / 8);
        }
        at += 8;
    }
    rest.iter().position(|&b| b == c).map(|p| at + p)
}

unsafe extern "C-unwind" {
    /// The general search and the scalar index of a match in a non-ASCII text, in the archive.
    fn msrt_string_index_of_long(a: usize, v: usize, out: usize) -> u8;
}

/// C view: `msrt_string_index_of(a: *const StrVal, v: *const StrVal, out: *mut i64) -> u8`
///
/// A search in an ASCII text of under [`MEDIUM_HAY`] bytes (a line, a record, a field) is a scan
/// the caller inlines; every other search calls the runtime.
#[unsafe(no_mangle)]
// ms: leaf pure domain=string
pub unsafe extern "C-unwind" fn msrt_string_index_of(a: usize, v: usize, out: usize) -> u8 {
    // SAFETY: caller passes live strings and a writable out.
    unsafe {
        let (sa, sv) = (a as *const StrVal, v as *const StrVal);
        let (hay, needle) = (bytes(sa), bytes(sv));
        if hay.len() < MEDIUM_HAY && hay.is_ascii() {
            let found = match needle {
                [] => Some(0),
                [c] => memchr_short(*c, hay),
                _ => find_short(hay, needle),
            };
            return match found {
                Some(i) => {
                    *(out as *mut i64) = i as i64;
                    1
                }
                None => 0,
            };
        }
        msrt_string_index_of_long(a, v, out)
    }
}

unsafe extern "C-unwind" {
    /// The general view: non-ASCII text, long unflagged text and out-of-range bounds (a fault).
    fn msrt_string_view_slow(s: usize, start: i64, end: i64, out: usize);
}

/// C view: `msrt_string_view(s: *const StrVal, start: i64, end: i64, out: *mut StrVal)`
///
/// `String.view` of an ASCII text with bounds inside it is two words computed by the caller: the
/// scalar bounds are byte offsets, and a short piece is copied inline. Everything else, including
/// the fault for bounds outside the text, is the runtime's.
#[unsafe(no_mangle)]
// ms: leaf pure domain=string
pub unsafe extern "C-unwind" fn msrt_string_view(s: usize, start: i64, end: i64, out: usize) {
    // SAFETY: caller passes a live string and a writable `out`.
    unsafe {
        let sv = s as *const StrVal;
        let text = bytes(sv);
        let n = text.len() as i64;
        let (a, b) = (
            if start < 0 { n + start } else { start },
            if end < 0 { n + end } else { end },
        );
        let ascii = (*sv).flagged_ascii() || (text.len() < MEDIUM_HAY && text.is_ascii());
        if !ascii || a < 0 || b < a || b > n {
            return msrt_string_view_slow(s, start, end, out);
        }
        let piece = &text[a as usize..b as usize];
        let view = if piece.len() <= ms_rt_abi::STR_INLINE_MAX {
            StrVal::inline(piece)
        } else {
            StrVal::view(piece.as_ptr().cast_mut(), piece.len())
        };
        view.write_to(out as *mut StrVal)
    }
}

/// C view: `msrt_string_starts_with(a: *const StrVal, v: *const StrVal) -> u8`
#[unsafe(no_mangle)]
// ms: leaf pure domain=string
pub unsafe extern "C-unwind" fn msrt_string_starts_with(a: usize, v: usize) -> u8 {
    // SAFETY: caller passes live strings.
    unsafe { bytes(a as *const StrVal).starts_with(bytes(v as *const StrVal)) as u8 }
}

/// C view: `msrt_string_ends_with(a: *const StrVal, v: *const StrVal) -> u8`
#[unsafe(no_mangle)]
// ms: leaf pure domain=string
pub unsafe extern "C-unwind" fn msrt_string_ends_with(a: usize, v: usize) -> u8 {
    // SAFETY: caller passes live strings.
    unsafe { bytes(a as *const StrVal).ends_with(bytes(v as *const StrVal)) as u8 }
}

/// C view: `msrt_string_compare(a: *const StrVal, b: *const StrVal) -> i64`
#[unsafe(no_mangle)]
// ms: leaf pure
pub unsafe extern "C-unwind" fn msrt_string_compare(a: usize, b: usize) -> i64 {
    // SAFETY: caller passes live strings.
    unsafe {
        match bytes(a as *const StrVal).cmp(bytes(b as *const StrVal)) {
            core::cmp::Ordering::Less => -1,
            core::cmp::Ordering::Equal => 0,
            core::cmp::Ordering::Greater => 1,
        }
    }
}

/// Whether two strings hold the same bytes: overlapping word compares for up to 16 bytes, so short
/// keys need no `memcmp` call.
///
/// # Safety
/// Both must be live strings.
#[inline(always)]
pub unsafe fn bytes_eq(a: *const StrVal, b: *const StrVal) -> bool {
    // SAFETY: the bytes of a live string are `len` readable bytes.
    unsafe {
        let n = (*a).len();
        if n != (*b).len() {
            return false;
        }
        let (p, q) = ((*a).data(), (*b).data());
        let word = |x: *const u8, at: usize| (x.add(at) as *const u64).read_unaligned();
        let half = |x: *const u8, at: usize| (x.add(at) as *const u32).read_unaligned();
        if (8..=16).contains(&n) {
            return word(p, 0) == word(q, 0) && word(p, n - 8) == word(q, n - 8);
        }
        if (4..8).contains(&n) {
            return half(p, 0) == half(q, 0) && half(p, n - 4) == half(q, n - 4);
        }
        if n < 4 {
            // The first, middle and last bytes cover every byte of a string of up to three.
            return n == 0
                || (*p == *q
                    && *p.add(n >> 1) == *q.add(n >> 1)
                    && *p.add(n - 1) == *q.add(n - 1));
        }
        core::slice::from_raw_parts(p, n) == core::slice::from_raw_parts(q, n)
    }
}

/// Deterministic 64-bit hash of bytes: eight bytes per multiply-fold step, with the tail read as
/// one overlapping word, then a final avalanche. Hashes are lookup aids, not stable identifiers.
#[inline]
pub fn hash_bytes(b: &[u8]) -> u64 {
    const K0: u64 = 0x9e37_79b9_7f4a_7c15;
    const K1: u64 = 0xff51_afd7_ed55_8ccd;
    #[inline(always)]
    fn fold(a: u64, b: u64) -> u64 {
        let m = u128::from(a) * u128::from(b);
        (m as u64) ^ ((m >> 64) as u64)
    }
    #[inline(always)]
    fn word(b: &[u8], at: usize) -> u64 {
        let mut w = [0u8; 8];
        w.copy_from_slice(&b[at..at + 8]);
        u64::from_le_bytes(w)
    }
    #[inline(always)]
    fn half(b: &[u8], at: usize) -> u64 {
        let mut w = [0u8; 4];
        w.copy_from_slice(&b[at..at + 4]);
        u64::from(u32::from_le_bytes(w))
    }
    let n = b.len();
    let mut h = K0 ^ (n as u64).wrapping_mul(K1);
    let mut i = 0;
    while i + 8 <= n {
        h = fold(h ^ word(b, i), K1);
        i += 8;
    }
    let tail = if n >= 8 {
        word(b, n - 8)
    } else if n >= 4 {
        half(b, 0) << 32 | half(b, n - 4)
    } else if n > 0 {
        u64::from(b[0]) << 16 | u64::from(b[n >> 1]) << 8 | u64::from(b[n - 1])
    } else {
        0
    };
    fold(h ^ tail, K0)
}

/// Hash of an `Int` key: one widening multiply folded to 64 bits.
#[inline(always)]
pub fn hash_int(x: u64) -> u64 {
    let m = u128::from(x ^ 0x9e37_79b9_7f4a_7c15) * 0xff51_afd7_ed55_8ccd;
    (m as u64) ^ ((m >> 64) as u64)
}

#[inline]
pub fn mix(mut h: u64) -> u64 {
    h ^= h >> 32;
    h = h.wrapping_mul(0x9e37_79b9_7f4a_7c15);
    h ^ (h >> 29)
}

/// Hash of a string's bytes (equal strings hash equally).
///
/// # Safety
/// `s` must be live.
/// C view: `msrt_string_hash(s: *const StrVal) -> i64`
#[unsafe(no_mangle)]
// ms: leaf pure
pub unsafe extern "C-unwind" fn msrt_string_hash(s: usize) -> i64 {
    // SAFETY: caller contract.
    hash_bytes(unsafe { bytes(s as *const StrVal) }) as i64
}

/// C view: `msrt_string_byte_length(s: *const StrVal) -> i64`
#[unsafe(no_mangle)]
// ms: leaf pure
pub unsafe extern "C-unwind" fn msrt_string_byte_length(s: usize) -> i64 {
    // SAFETY: caller passes a live string.
    unsafe { (*(s as *const StrVal)).len() as i64 }
}

/// C view: `msrt_string_is_empty(s: *const StrVal) -> u8`
#[unsafe(no_mangle)]
// ms: leaf pure domain=string
pub unsafe extern "C-unwind" fn msrt_string_is_empty(s: usize) -> u8 {
    // SAFETY: caller passes a live string.
    unsafe { (*(s as *const StrVal)).is_empty() as u8 }
}

/// C view: `msrt_hash_int(v: i64) -> i64`
#[unsafe(no_mangle)]
// ms: leaf
pub extern "C-unwind" fn msrt_hash_int(v: i64) -> i64 {
    mix(v as u64 ^ 0x9e37_79b9) as i64
}

/// C view: `msrt_hash_bytes(p: *const u8, len: usize) -> i64`
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_hash_bytes(p: usize, len: usize) -> i64 {
    // SAFETY: caller passes a readable range.
    unsafe { hash_bytes(core::slice::from_raw_parts(p as *const u8, len)) as i64 }
}

// ---------------------------------------------------------------------------
// Maps and sets
// ---------------------------------------------------------------------------

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
/// C view: `msrt_map_get_ptr_sw8(m: *const MapVal, kd: KeyDesc, vd: ValDesc, key: *const u8) -> *const u8`
#[unsafe(no_mangle)]
// ms: leaf pure
pub unsafe extern "C-unwind" fn msrt_map_get_ptr_sw8(
    m: usize,
    _kd: usize,
    _vd: usize,
    key: usize,
) -> usize {
    // SAFETY: caller contract.
    unsafe {
        let p = find_sw8(&*(m as *const MapVal), key as *const u8);
        if p.is_null() {
            0
        } else {
            p.add(SW8_VALUE) as usize
        }
    }
}

/// `contains` for a `String` key and an 8-byte, 8-aligned value.
/// C view: `msrt_map_contains_sw8(m: *const MapVal, kd: KeyDesc, vd: ValDesc, key: *const u8) -> u8`
#[unsafe(no_mangle)]
// ms: leaf pure
pub unsafe extern "C-unwind" fn msrt_map_contains_sw8(
    m: usize,
    _kd: usize,
    _vd: usize,
    key: usize,
) -> u8 {
    // SAFETY: caller contract.
    unsafe { !find_sw8(&*(m as *const MapVal), key as *const u8).is_null() as u8 }
}

/// `get` for a `String` key and a plain 8-byte scalar value (`Int` or `Float`).
/// C view: `msrt_map_get_sw8(m: *const MapVal, kd: KeyDesc, vd: ValDesc, key: *const u8, out: *mut u8) -> u8`
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_map_get_sw8(
    m: usize,
    _kd: usize,
    _vd: usize,
    key: usize,
    out: usize,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let p = find_sw8(&*(m as *const MapVal), key as *const u8);
        if p.is_null() {
            return 0;
        }
        core::ptr::copy_nonoverlapping(p.add(SW8_VALUE), out as *mut u8, 8);
        1
    }
}

/// `get_ptr` for an `Int` key and an 8-byte, 8-aligned value. The call site checked the shape;
/// the descriptors are accepted for signature parity and ignored.
/// C view: `msrt_map_get_ptr_w8(m: *const MapVal, kd: KeyDesc, vd: ValDesc, key: *const u8) -> *const u8`
#[unsafe(no_mangle)]
// ms: leaf pure
pub unsafe extern "C-unwind" fn msrt_map_get_ptr_w8(
    m: usize,
    _kd: usize,
    _vd: usize,
    key: usize,
) -> usize {
    // SAFETY: caller contract.
    unsafe {
        let p = find_w8(&*(m as *const MapVal), key as *const u8);
        if p.is_null() { 0 } else { p.add(16) as usize }
    }
}

/// `contains` for an `Int` key and an 8-byte, 8-aligned value.
/// C view: `msrt_map_contains_w8(m: *const MapVal, kd: KeyDesc, vd: ValDesc, key: *const u8) -> u8`
#[unsafe(no_mangle)]
// ms: leaf pure
pub unsafe extern "C-unwind" fn msrt_map_contains_w8(
    m: usize,
    _kd: usize,
    _vd: usize,
    key: usize,
) -> u8 {
    // SAFETY: caller contract.
    unsafe { !find_w8(&*(m as *const MapVal), key as *const u8).is_null() as u8 }
}

/// `get` for an `Int` key and a plain 8-byte scalar value (`Int` or `Float`).
/// C view: `msrt_map_get_w8(m: *const MapVal, kd: KeyDesc, vd: ValDesc, key: *const u8, out: *mut u8) -> u8`
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_map_get_w8(
    m: usize,
    _kd: usize,
    _vd: usize,
    key: usize,
    out: usize,
) -> u8 {
    // SAFETY: caller contract.
    unsafe {
        let p = find_w8(&*(m as *const MapVal), key as *const u8);
        if p.is_null() {
            return 0;
        }
        core::ptr::copy_nonoverlapping(p.add(16), out as *mut u8, 8);
        1
    }
}

/// `length()`: the number of live entries.
/// C view: `msrt_map_length(m: *const MapVal) -> i64`
#[unsafe(no_mangle)]
// ms: leaf pure
pub unsafe extern "C-unwind" fn msrt_map_length(m: usize) -> i64 {
    // SAFETY: caller contract.
    unsafe { (*(m as *const MapVal)).len as i64 }
}

/// Number of slots to scan with `msrt_map_entry_ptrs` (live entries plus holes).
/// C view: `msrt_map_slot_count(m: *const MapVal) -> i64`
#[unsafe(no_mangle)]
// ms: leaf pure
pub unsafe extern "C-unwind" fn msrt_map_slot_count(m: usize) -> i64 {
    // SAFETY: caller contract.
    unsafe { (*(m as *const MapVal)).used as i64 }
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
/// C view: `msrt_map_entry_ptrs(m: *const MapVal, kd: KeyDesc, vd: ValDesc, i: i64, key_out: *mut *const u8, val_out: *mut *const u8) -> u8`
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_map_entry_ptrs(
    m: usize,
    kd: usize,
    vd: usize,
    i: i64,
    key_out: usize,
    val_out: usize,
) -> u8 {
    let (m, vd) = (m as *const MapVal, vd as *const TypeDesc);
    let kd = key_desc(m, kd as *const TypeDesc);
    // SAFETY: caller contract.
    unsafe {
        let m = &*m;
        let l = layout(&*kd, vd.as_ref());
        let p = slot(m, &l, i as usize);
        if slot_hash_of(p) & LIVE == 0 {
            return 0;
        }
        *(key_out as *mut *const u8) = p.add(l.koff);
        if val_out != 0 {
            *(val_out as *mut *const u8) = p.add(l.voff);
        }
        1
    }
}
