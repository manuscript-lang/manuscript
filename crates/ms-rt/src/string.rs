//! `String`: immutable UTF-8 text with scalar-indexed operations.
//!
//! The value is a [`StrVal`] (`{ ptr, len, cap }`, see `ms-rt-abi`): `ptr` points at the bytes,
//! which are followed by one NUL. An owned string (`cap >= 1`) is a single allocation that
//! copying duplicates and dropping frees; a static one (`cap == 0`) is never freed. Language level
//! indices and lengths count Unicode scalars; a string whose scalar count equals its byte length
//! is ASCII, which every indexing operation exploits (the count of a long string is cached for
//! the string last measured, see [`Hint`]).
use crate::alloc;
use crate::fault;
use crate::global::Global;
use crate::obj;
use crate::utf8;
use core::ptr::null_mut;
use ms_rt_abi::{
    Obj, STATUS_INVALID_INPUT, STATUS_LIMIT_EXCEEDED, STATUS_OK, STATUS_OUT_OF_RANGE, StrVal,
    VecVal,
};

/// Native allocation ceiling for built strings.
pub const MAX_BYTES: usize = 1 << 30;

/// Bytes of a string.
///
/// # Safety
/// `s` must be a live string for the lifetime `'a`.
#[inline(always)]
pub unsafe fn bytes<'a>(s: *const StrVal) -> &'a [u8] {
    // SAFETY: `ptr..ptr+len` holds the text.
    unsafe { core::slice::from_raw_parts((*s).ptr, (*s).len) }
}

/// A copy of `s` that the caller owns: a static string is shared, an owned one is duplicated.
///
/// # Safety
/// `s` must be a live string.
#[inline(always)]
pub unsafe fn cloned(s: &StrVal) -> StrVal {
    if s.cap == 0 {
        return s.alias();
    }
    // SAFETY: `s` is live and owned, so `ptr..ptr+len` is readable.
    unsafe { owned_copy(bytes(s)) }
}

/// Writes an owned copy of `s` to `out` (what `.clone()` and every implicit copy of a string do).
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_clone(s: *const StrVal, out: *mut StrVal) {
    // SAFETY: caller passes a live string and a writable `out`.
    unsafe { cloned(&*s).write_to(out) }
}

/// Frees an owned string's bytes (the drop compiled code calls when `cap != 0`).
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_str_free(ptr: *mut u8) {
    // SAFETY: `ptr` is the start of an owned string.
    unsafe { free_owned(ptr) }
}

/// Copies `len` bytes at `ptr` into a new allocation with a NUL (the copy of an owned string).
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_str_dup(ptr: *const u8, len: usize) -> *mut u8 {
    // SAFETY: `ptr..ptr+len` is readable.
    unsafe { owned_copy(core::slice::from_raw_parts(ptr, len)).ptr }
}

/// Frees an owned string.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_free(s: *const StrVal) {
    // SAFETY: caller owns `s`.
    unsafe { release(&*s) }
}

#[inline(never)]
fn owned_copy(data: &[u8]) -> StrVal {
    let s = alloc_str(data.len());
    // SAFETY: `s` has room for `len` bytes.
    unsafe { core::ptr::copy_nonoverlapping(data.as_ptr(), s.ptr, data.len()) };
    s
}

/// Frees the bytes of `s` when it is owned.
///
/// # Safety
/// `s` must be a live string that the caller owns and does not use afterwards.
#[inline(always)]
pub unsafe fn release(s: &StrVal) {
    if s.cap != 0 {
        // SAFETY: an owned string is one allocation starting at `ptr`.
        unsafe { free_owned(s.ptr) }
    }
}

#[inline(never)]
unsafe fn free_owned(ptr: *mut u8) {
    // SAFETY: `ptr` came from `alloc_str`; the hint may name its bytes.
    unsafe {
        let h = HINT.ptr();
        if core::ptr::eq((*h).s, ptr) {
            (*h).s = core::ptr::null();
        }
        alloc::free(ptr);
    }
}

/// Allocates an uninitialised string of `len` bytes (NUL terminated).
pub fn alloc_str(len: usize) -> StrVal {
    if len > MAX_BYTES {
        fault::fault(b"string: limit exceeded");
    }
    let ptr = alloc::alloc(len + 1);
    // SAFETY: the allocation holds `len + 1` bytes.
    unsafe { *ptr.add(len) = 0 };
    // Never 0: compiled code reads `cap == 0` as "static string, never freed".
    StrVal {
        ptr,
        len,
        cap: len.max(1),
    }
}

static mut EMPTY: [u8; 1] = [0];

const fn build_ascii() -> [[u8; 2]; 128] {
    let mut t = [[0u8; 2]; 128];
    let mut i = 0;
    while i < 128 {
        t[i] = [i as u8, 0];
        i += 1;
    }
    t
}

#[unsafe(export_name = "msrt_ascii_chars")]
static mut ASCII: [[u8; 2]; 128] = build_ascii();

const _: () = assert!(core::mem::size_of::<[u8; 2]>() == ms_rt_abi::ASCII_CHAR_STRIDE);

/// The null string: no bytes and no block, what an unwritten message slot holds.
pub const NO_STR: StrVal = StrVal {
    ptr: null_mut(),
    len: 0,
    cap: 0,
};

/// Releases `s` unless it is [`NO_STR`].
///
/// # Safety
/// `s` is `NO_STR` or a live string the caller owns a reference to.
pub unsafe fn release_opt(s: &StrVal) {
    if !s.ptr.is_null() {
        // SAFETY: a non-null string is live per the contract.
        unsafe { release(s) }
    }
}

/// The static empty string (a literal: no ownership to give back).
pub fn empty() -> StrVal {
    StrVal {
        ptr: core::ptr::addr_of_mut!(EMPTY) as *mut u8,
        len: 0,
        cap: 0,
    }
}

/// Writes the static empty string to `out`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_empty(out: *mut StrVal) {
    // SAFETY: caller passes a writable out.
    unsafe { (empty()).write_to(out) }
}

fn ascii_char(b: u8) -> StrVal {
    // SAFETY: as above.
    unsafe {
        StrVal {
            ptr: core::ptr::addr_of_mut!(ASCII[b as usize]) as *mut u8,
            len: 1,
            cap: 0,
        }
    }
}

/// New string from bytes (owned, rc 1). Short ASCII and empty results are the shared statics.
pub fn from_bytes(data: &[u8]) -> StrVal {
    match data.len() {
        0 => return empty(),
        1 if data[0] < 0x80 => return ascii_char(data[0]),
        _ => {}
    }
    let s = alloc_str(data.len());
    // SAFETY: `s` has room for `len` bytes.
    unsafe { core::ptr::copy_nonoverlapping(data.as_ptr(), s.ptr, data.len()) };
    s
}

/// Converts a finished buffer into a string.
pub fn from_buf(b: Vec<u8>) -> StrVal {
    from_bytes(b.as_slice())
}

/// Hash of a string's bytes (equal strings hash equally).
///
/// # Safety
/// `s` must be live.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_hash(s: *const StrVal) -> i64 {
    // SAFETY: caller contract.
    hash_bytes(unsafe { bytes(s) }) as i64
}

/// New string from raw bytes. Exported for literals built at startup and for the Rust stdlib crates.
///
/// # Safety
/// `ptr..ptr+len` must be readable; `out` writable.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_from_bytes(
    ptr: *const u8,
    len: usize,
    out: *mut StrVal,
) {
    // SAFETY: caller contract.
    unsafe { (from_bytes(core::slice::from_raw_parts(ptr, len))).write_to(out) }
}

// ---------------------------------------------------------------------------
// Scalar shape and indexing
// ---------------------------------------------------------------------------

/// Scalar count. A string of `HINT_MIN` bytes or more remembers its count in [`HINT`] while it is
/// the one last measured, so loops over one long string do not rescan it.
///
/// # Safety
/// `s` must be live.
#[inline]
pub unsafe fn scalar_count(s: *const StrVal) -> usize {
    // SAFETY: the hint is cleared when its string is freed.
    unsafe {
        let b = bytes(s);
        if b.len() < HINT_MIN {
            return utf8::count(b);
        }
        let h = HINT.ptr();
        if core::ptr::eq((*h).s, (*s).ptr) && (*h).len == b.len() && (*h).count != usize::MAX {
            return (*h).count;
        }
        let n = utf8::count(b);
        *h = Hint {
            s: (*s).ptr,
            len: b.len(),
            count: n,
            scalar: 0,
            offset: 0,
        };
        n
    }
}

struct Hint {
    /// Bytes of the string the figures belong to.
    s: *const u8,
    len: usize,
    /// Scalar count of the string, or `usize::MAX` when not counted.
    count: usize,
    /// A remembered position: scalar index and its byte offset.
    scalar: usize,
    offset: usize,
}
static HINT: Global<Hint> = Global::new(Hint {
    s: core::ptr::null(),
    len: 0,
    count: usize::MAX,
    scalar: 0,
    offset: 0,
});
const HINT_MIN: usize = 256;

/// Byte offset of scalar `n` (0..=count) with a remembered position for sequential access.
unsafe fn scalar_offset(s: *const StrVal, n: usize) -> usize {
    // SAFETY: `s` live; the hint is cleared when its string dies.
    unsafe {
        let b = bytes(s);
        if b.len() < HINT_MIN {
            return utf8::offset_of(b, n);
        }
        let h = HINT.ptr();
        let (mut sc, mut off) = (0usize, 0usize);
        if std::ptr::eq((*h).s, (*s).ptr) && (*h).scalar.abs_diff(n) < n {
            sc = (*h).scalar;
            off = (*h).offset;
        }
        while sc < n && off < b.len() {
            off += utf8::decode(&b[off..]).1;
            sc += 1;
        }
        while sc > n {
            off -= utf8::decode_last(&b[..off]).1;
            sc -= 1;
        }
        if !core::ptr::eq((*h).s, (*s).ptr) || (*h).len != b.len() {
            (*h).count = usize::MAX;
        }
        (*h).s = (*s).ptr;
        (*h).len = b.len();
        (*h).scalar = sc;
        (*h).offset = off;
        off
    }
}

/// Substring by scalar range (callers validated `0 <= a <= b <= count`).
unsafe fn sub_scalars(s: *const StrVal, a: usize, b: usize) -> StrVal {
    // SAFETY: `s` live; range validated.
    unsafe {
        let text = bytes(s);
        if a == 0 && b == scalar_count(s) {
            return cloned(&*s);
        }
        if scalar_count(s) == text.len() {
            return from_bytes(&text[a..b]);
        }
        let (ao, bo) = (scalar_offset(s, a), scalar_offset(s, b));
        from_bytes(&text[ao..bo])
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_length(s: *const StrVal) -> i64 {
    // SAFETY: caller passes a live string.
    unsafe { scalar_count(s) as i64 }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_scalar_length(s: *const StrVal) -> i64 {
    // SAFETY: caller passes a live string.
    unsafe { scalar_count(s) as i64 }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_byte_length(s: *const StrVal) -> i64 {
    // SAFETY: caller passes a live string.
    unsafe { (*s).len as i64 }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_is_empty(s: *const StrVal) -> u8 {
    // SAFETY: caller passes a live string.
    unsafe { ((*s).len == 0) as u8 }
}

/// Resolves a possibly negative index against `count`; `None` when out of range.
fn relative(count: usize, index: i64) -> Option<usize> {
    let i = if index < 0 {
        count as i64 + index
    } else {
        index
    };
    if i < 0 || i as usize >= count {
        None
    } else {
        Some(i as usize)
    }
}

/// `String.get(index, default)`: a one-scalar string. `default` is borrowed and may be absent.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_get(
    s: *const StrVal,
    index: i64,
    has_default: u8,
    default: *const StrVal,
    out: *mut StrVal,
) {
    // SAFETY: caller passes a writable `out` and live arguments.
    unsafe { (string_get(s, index, has_default != 0, default)).write_to(out) }
}

unsafe fn string_get(
    s: *const StrVal,
    index: i64,
    has_default: bool,
    default: *const StrVal,
) -> StrVal {
    // SAFETY: caller passes live strings (default may be absent).
    unsafe {
        let n = scalar_count(s);
        let Some(i) = relative(n, index) else {
            if !has_default {
                fault::msrt_index_fault(index, n as i64);
            }
            return cloned(&*default);
        };
        let text = bytes(s);
        if scalar_count(s) == text.len() {
            return from_bytes(&text[i..i + 1]);
        }
        let off = scalar_offset(s, i);
        let (c, w) = utf8::decode(&text[off..]);
        if c == 0xFFFD && w == 1 {
            return from_bytes("\u{FFFD}".as_bytes());
        }
        from_bytes(&text[off..off + w])
    }
}

/// `String.scalar_at(index, default)`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_scalar_at(
    s: *const StrVal,
    index: i64,
    has_default: u8,
    default: i64,
) -> i64 {
    // SAFETY: caller passes a live string.
    unsafe {
        let n = scalar_count(s);
        let Some(i) = relative(n, index) else {
            if has_default == 0 {
                fault::msrt_index_fault(index, n as i64);
            }
            return default;
        };
        let text = bytes(s);
        if scalar_count(s) == text.len() {
            return text[i] as i64;
        }
        utf8::decode(&text[scalar_offset(s, i)..]).0 as i64
    }
}

// ---------------------------------------------------------------------------
// Comparison, hashing
// ---------------------------------------------------------------------------

/// Content equality.
///
/// # Safety
/// Both strings live.
#[inline]
pub unsafe fn equal(a: *const StrVal, b: *const StrVal) -> bool {
    // SAFETY: caller contract.
    unsafe {
        if (*a).ptr == (*b).ptr && (*a).len == (*b).len {
            return true;
        }
        let n = (*a).len;
        if n != (*b).len {
            return false;
        }
        let (x, y) = (bytes(a), bytes(b));
        if n < 4 {
            // One-character comparisons and tiny keys: skip the memcmp call.
            return (0..n).all(|i| *x.get_unchecked(i) == *y.get_unchecked(i));
        }
        if n <= 8 {
            // Two overlapping words cover 4..=8 bytes.
            let (p, q) = (x.as_ptr(), y.as_ptr());
            let head = (p as *const u32).read_unaligned() == (q as *const u32).read_unaligned();
            let tail = (p.add(n - 4) as *const u32).read_unaligned()
                == (q.add(n - 4) as *const u32).read_unaligned();
            return head && tail;
        }
        if n <= 16 {
            // Two overlapping words cover 9..=16 bytes.
            let (p, q) = (x.as_ptr(), y.as_ptr());
            let head = (p as *const u64).read_unaligned() == (q as *const u64).read_unaligned();
            let tail = (p.add(n - 8) as *const u64).read_unaligned()
                == (q.add(n - 8) as *const u64).read_unaligned();
            return head && tail;
        }
        x == y
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_eq(a: *const StrVal, b: *const StrVal) -> u8 {
    // SAFETY: caller passes live strings.
    unsafe { equal(a, b) as u8 }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_compare(a: *const StrVal, b: *const StrVal) -> i64 {
    // SAFETY: caller passes live strings.
    unsafe {
        match bytes(a).cmp(bytes(b)) {
            core::cmp::Ordering::Less => -1,
            core::cmp::Ordering::Equal => 0,
            core::cmp::Ordering::Greater => 1,
        }
    }
}

/// Deterministic 64-bit hash of bytes: eight bytes per multiply-fold step, with the tail read as
/// one overlapping word, then a final avalanche. Hashes are lookup aids, not stable identifiers.
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
    mix(fold(h ^ tail, K0))
}

#[inline]
pub fn mix(mut h: u64) -> u64 {
    h ^= h >> 32;
    h = h.wrapping_mul(0x9e37_79b9_7f4a_7c15);
    h ^ (h >> 29)
}

// ---------------------------------------------------------------------------
// Searching
// ---------------------------------------------------------------------------

/// First occurrence of `needle` in `hay` (empty matches at 0).
pub fn find(hay: &[u8], needle: &[u8]) -> Option<usize> {
    if needle.is_empty() {
        return Some(0);
    }
    if needle.len() > hay.len() {
        return None;
    }
    if needle.len() == 1 {
        return memchr(needle[0], hay);
    }
    find_from(hay, needle, 0)
}

/// First index of `c` in `hay`, 16 bytes at a time where SSE2 is available.
fn memchr(c: u8, hay: &[u8]) -> Option<usize> {
    #[cfg(target_arch = "x86_64")]
    {
        use core::arch::x86_64::*;
        let mut i = 0;
        // SAFETY: SSE2 is part of the x86_64 baseline; every load stays inside `hay`.
        unsafe {
            let needle = _mm_set1_epi8(c as i8);
            while i + 16 <= hay.len() {
                let chunk = _mm_loadu_si128(hay.as_ptr().add(i) as *const __m128i);
                let mask = _mm_movemask_epi8(_mm_cmpeq_epi8(chunk, needle)) as u32;
                if mask != 0 {
                    return Some(i + mask.trailing_zeros() as usize);
                }
                i += 16;
            }
        }
        hay[i..].iter().position(|&b| b == c).map(|j| i + j)
    }
    #[cfg(not(target_arch = "x86_64"))]
    {
        hay.iter().position(|&b| b == c)
    }
}

/// First occurrence of `needle` (two bytes or more, no longer than `hay`) at or after `start`.
fn find_from(hay: &[u8], needle: &[u8], start: usize) -> Option<usize> {
    let n = needle.len();
    let last = hay.len() - n;
    let mut i = start;
    #[cfg(target_arch = "x86_64")]
    {
        use core::arch::x86_64::*;
        // Compare the first and last needle byte of 16 candidate positions at once, then verify
        // the middle of each survivor.
        // SAFETY: SSE2 is part of the x86_64 baseline; both loads end at or before `hay.len()`.
        unsafe {
            let (first, tail) = (
                _mm_set1_epi8(needle[0] as i8),
                _mm_set1_epi8(needle[n - 1] as i8),
            );
            while i + 15 <= last {
                let a = _mm_loadu_si128(hay.as_ptr().add(i) as *const __m128i);
                let b = _mm_loadu_si128(hay.as_ptr().add(i + n - 1) as *const __m128i);
                let hits = _mm_and_si128(_mm_cmpeq_epi8(a, first), _mm_cmpeq_epi8(b, tail));
                let mut mask = _mm_movemask_epi8(hits) as u32;
                while mask != 0 {
                    let at = i + mask.trailing_zeros() as usize;
                    if hay[at + 1..at + n - 1] == needle[1..n - 1] {
                        return Some(at);
                    }
                    mask &= mask - 1;
                }
                i += 16;
            }
        }
    }
    while i <= last {
        i += hay[i..=last].iter().position(|&c| c == needle[0])?;
        if &hay[i..i + n] == needle {
            return Some(i);
        }
        i += 1;
    }
    None
}

pub fn rfind(hay: &[u8], needle: &[u8]) -> Option<usize> {
    if needle.is_empty() {
        return Some(hay.len());
    }
    if needle.len() > hay.len() {
        return None;
    }
    (0..=hay.len() - needle.len())
        .rev()
        .find(|&i| &hay[i..i + needle.len()] == needle)
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_contains(a: *const StrVal, v: *const StrVal) -> u8 {
    // SAFETY: caller passes live strings.
    unsafe { find(bytes(a), bytes(v)).is_some() as u8 }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_starts_with(a: *const StrVal, v: *const StrVal) -> u8 {
    // SAFETY: caller passes live strings.
    unsafe { bytes(a).starts_with(bytes(v)) as u8 }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_ends_with(a: *const StrVal, v: *const StrVal) -> u8 {
    // SAFETY: caller passes live strings.
    unsafe { bytes(a).ends_with(bytes(v)) as u8 }
}

/// Optional[Int] result: present flag, value through `out`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_index_of(
    a: *const StrVal,
    v: *const StrVal,
    out: *mut i64,
) -> u8 {
    // SAFETY: caller passes live strings and a writable out.
    unsafe {
        let text = bytes(a);
        match find(text, bytes(v)) {
            None => 0,
            Some(i) => {
                *out = utf8::count(&text[..i]) as i64;
                1
            }
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_last_index_of(
    a: *const StrVal,
    v: *const StrVal,
    out: *mut i64,
) -> u8 {
    // SAFETY: caller passes live strings and a writable out.
    unsafe {
        let text = bytes(a);
        match rfind(text, bytes(v)) {
            None => 0,
            Some(i) => {
                *out = utf8::count(&text[..i]) as i64;
                1
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Building
// ---------------------------------------------------------------------------

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_concat(
    a: *const StrVal,
    b: *const StrVal,
    out: *mut StrVal,
) {
    // SAFETY: caller passes a writable `out` and live arguments.
    unsafe { (msrt_string_concat_val(a, b)).write_to(out) }
}

#[inline(always)]
unsafe fn msrt_string_concat_val(a: *const StrVal, b: *const StrVal) -> StrVal {
    // SAFETY: caller passes live strings.
    unsafe {
        let (la, lb) = ((*a).len, (*b).len);
        if lb == 0 {
            return cloned(&*a);
        }
        if la == 0 {
            return cloned(&*b);
        }
        let s = alloc_str(la + lb);
        core::ptr::copy_nonoverlapping(bytes(a).as_ptr(), s.ptr, la);
        core::ptr::copy_nonoverlapping(bytes(b).as_ptr(), s.ptr.add(la), lb);
        s
    }
}

/// A growable byte buffer the text formatters append to, so building a long text is linear.
pub struct StrBuf(Vec<u8>);

/// Starts an empty string builder (finish it with [`msrt_strbuf_finish`]).
#[unsafe(no_mangle)]
pub extern "C-unwind" fn msrt_strbuf_new() -> *mut StrBuf {
    Box::into_raw(Box::new(StrBuf(Vec::new())))
}

/// Appends a string's bytes to the builder.
///
/// # Safety
/// `buf` must come from `msrt_strbuf_new` and `s` must be live.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_strbuf_push(buf: *mut StrBuf, s: *const StrVal) {
    // SAFETY: the caller passes a live builder and string.
    unsafe {
        let text = bytes(s);
        let out = &mut (*buf).0;
        if out.len() + text.len() > MAX_BYTES {
            fault::fault(b"string: limit exceeded");
        }
        out.extend_from_slice(text);
    }
}

/// Consumes the builder and returns its text.
///
/// # Safety
/// `buf` must come from `msrt_strbuf_new` and is not used afterwards.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_strbuf_finish(buf: *mut StrBuf, out: *mut StrVal) {
    // SAFETY: caller passes a writable `out` and live arguments.
    unsafe { (msrt_strbuf_finish_val(buf)).write_to(out) }
}

unsafe fn msrt_strbuf_finish_val(buf: *mut StrBuf) -> StrVal {
    // SAFETY: the builder was boxed by `msrt_strbuf_new` and is consumed once.
    let buf = unsafe { Box::from_raw(buf) };
    from_bytes(&buf.0)
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_reverse(a: *const StrVal, out: *mut StrVal) {
    // SAFETY: caller passes a writable `out` and live arguments.
    unsafe { (msrt_string_reverse_val(a)).write_to(out) }
}

#[inline(always)]
unsafe fn msrt_string_reverse_val(a: *const StrVal) -> StrVal {
    // SAFETY: caller passes a live string.
    unsafe {
        let text = bytes(a);
        let mut out = Vec::with_capacity(text.len());
        let mut end = text.len();
        let mut tmp = [0u8; 4];
        while end > 0 {
            let (c, w) = utf8::decode_last(&text[..end]);
            let n = utf8::encode(c, &mut tmp);
            out.extend_from_slice(&tmp[..n]);
            end -= w;
        }
        from_buf(out)
    }
}

fn trim_range(text: &[u8], start: bool, end: bool) -> (usize, usize) {
    let (mut a, mut b) = (0, text.len());
    // ASCII White_Space is \t \n \v \f \r and the space; anything else below 0x80 ends the scan
    // without decoding.
    let ascii_space = |b: u8| b == b' ' || (9..=13).contains(&b);
    if start {
        while a < b {
            if text[a] < 0x80 {
                if !ascii_space(text[a]) {
                    break;
                }
                a += 1;
                continue;
            }
            let (c, w) = utf8::decode(&text[a..b]);
            if !utf8::is_space(c) {
                break;
            }
            a += w;
        }
    }
    if end {
        while b > a {
            if text[b - 1] < 0x80 {
                if !ascii_space(text[b - 1]) {
                    break;
                }
                b -= 1;
                continue;
            }
            let (c, w) = utf8::decode_last(&text[a..b]);
            if !utf8::is_space(c) {
                break;
            }
            b -= w;
        }
    }
    (a, b)
}

#[inline(always)]
unsafe fn trimmed(s: *const StrVal, start: bool, end: bool) -> StrVal {
    // SAFETY: caller passes a live string.
    unsafe {
        let text = bytes(s);
        let (a, b) = trim_range(text, start, end);
        if a == 0 && b == text.len() {
            cloned(&*s)
        } else {
            from_bytes(&text[a..b])
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_trim(s: *const StrVal, out: *mut StrVal) {
    // SAFETY: caller passes a writable `out` and live arguments.
    unsafe { (msrt_string_trim_val(s)).write_to(out) }
}

#[inline(always)]
unsafe fn msrt_string_trim_val(s: *const StrVal) -> StrVal {
    // SAFETY: forwarded contract.
    unsafe { trimmed(s, true, true) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_trim_start(s: *const StrVal, out: *mut StrVal) {
    // SAFETY: caller passes a writable `out` and live arguments.
    unsafe { (msrt_string_trim_start_val(s)).write_to(out) }
}

#[inline(always)]
unsafe fn msrt_string_trim_start_val(s: *const StrVal) -> StrVal {
    // SAFETY: forwarded contract.
    unsafe { trimmed(s, true, false) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_trim_end(s: *const StrVal, out: *mut StrVal) {
    // SAFETY: caller passes a writable `out` and live arguments.
    unsafe { (msrt_string_trim_end_val(s)).write_to(out) }
}

#[inline(always)]
unsafe fn msrt_string_trim_end_val(s: *const StrVal) -> StrVal {
    // SAFETY: forwarded contract.
    unsafe { trimmed(s, false, true) }
}

fn is_cased(c: char) -> bool {
    // Titlecase letters (Lt) are neither `is_lowercase` nor `is_uppercase` in Rust.
    c.is_lowercase()
        || c.is_uppercase()
        || matches!(
            c,
            '\u{1C5}' | '\u{1C8}' | '\u{1CB}' | '\u{1F2}' | '\u{1FBC}' | '\u{1FCC}' | '\u{1FFC}'
        )
        || ('\u{1F88}'..='\u{1F8F}').contains(&c)
        || ('\u{1F98}'..='\u{1F9F}').contains(&c)
        || ('\u{1FA8}'..='\u{1FAF}').contains(&c)
}

fn map_case(text: &[u8], upper: bool) -> Vec<u8> {
    if text.is_ascii() {
        let mut out = text.to_vec();
        if upper {
            out.make_ascii_uppercase();
        } else {
            out.make_ascii_lowercase();
        }
        return out;
    }
    let mut out = Vec::with_capacity(text.len());
    let mut chars: Vec<char> = Vec::new();
    let mut i = 0;
    while i < text.len() {
        let (c, w) = utf8::decode(&text[i..]);
        chars.push(char::from_u32(c).unwrap_or('\u{FFFD}'));
        i += w;
    }
    let cs = chars.as_slice();
    let mut tmp = [0u8; 4];
    for (k, &c) in cs.iter().enumerate() {
        if upper {
            for u in c.to_uppercase() {
                out.extend_from_slice(u.encode_utf8(&mut tmp).as_bytes());
            }
        } else if c == '\u{3A3}' {
            // Final sigma: preceded by a cased letter and not followed by one.
            let before = cs[..k]
                .iter()
                .rev()
                .find(|&&x| !is_case_ignorable(x))
                .is_some_and(|&x| is_cased(x));
            let after = cs[k + 1..]
                .iter()
                .find(|&&x| !is_case_ignorable(x))
                .is_some_and(|&x| is_cased(x));
            out.extend_from_slice(
                if before && !after {
                    "\u{3C2}"
                } else {
                    "\u{3C3}"
                }
                .as_bytes(),
            );
        } else {
            for u in c.to_lowercase() {
                out.extend_from_slice(u.encode_utf8(&mut tmp).as_bytes());
            }
        }
    }
    out
}

fn is_case_ignorable(c: char) -> bool {
    matches!(
        c,
        '\'' | '.'
            | ':'
            | '^'
            | '`'
            | '\u{A8}'
            | '\u{AD}'
            | '\u{AF}'
            | '\u{B4}'
            | '\u{B7}'
            | '\u{B8}'
            | '\u{2019}'
    ) || ('\u{300}'..='\u{36F}').contains(&c)
        || ('\u{2B0}'..='\u{2FF}').contains(&c)
        || ('\u{200B}'..='\u{200F}').contains(&c)
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_upper(s: *const StrVal, out: *mut StrVal) {
    // SAFETY: caller passes a writable `out` and live arguments.
    unsafe { (msrt_string_upper_val(s)).write_to(out) }
}

#[inline(always)]
unsafe fn msrt_string_upper_val(s: *const StrVal) -> StrVal {
    // SAFETY: caller passes a live string.
    unsafe { from_buf(map_case(bytes(s), true)) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_lower(s: *const StrVal, out: *mut StrVal) {
    // SAFETY: caller passes a writable `out` and live arguments.
    unsafe { (msrt_string_lower_val(s)).write_to(out) }
}

#[inline(always)]
unsafe fn msrt_string_lower_val(s: *const StrVal) -> StrVal {
    // SAFETY: caller passes a live string.
    unsafe { from_buf(map_case(bytes(s), false)) }
}

/// `repeat` with `has_max`/`max`; status protocol, ok through `out`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_repeat(
    s: *const StrVal,
    count: i64,
    has_max: u8,
    max: i64,
    out: *mut StrVal,
) -> u8 {
    // SAFETY: caller passes a live string and a writable out.
    unsafe {
        let limit = if has_max != 0 { max } else { i64::MAX };
        if count < 0 || limit < 0 {
            return STATUS_INVALID_INPUT;
        }
        let text = bytes(s);
        if text.is_empty() {
            *out = empty();
            return STATUS_OK;
        }
        let limit = (limit as usize).min(MAX_BYTES);
        if count as usize > limit / text.len() {
            return STATUS_LIMIT_EXCEEDED;
        }
        let r = alloc_str(text.len() * count as usize);
        let d = r.ptr;
        for i in 0..count as usize {
            core::ptr::copy_nonoverlapping(text.as_ptr(), d.add(i * text.len()), text.len());
        }
        *out = r;
        STATUS_OK
    }
}

fn count_matches(text: &[u8], old: &[u8]) -> usize {
    let mut n = 0;
    let mut i = 0;
    while let Some(p) = find(&text[i..], old) {
        n += 1;
        i += p + old.len();
    }
    n
}

/// Replace the first `n` occurrences (n < 0 means all).
fn replace_n_bytes(text: &[u8], old: &[u8], new: &[u8], n: i64) -> Vec<u8> {
    let mut out = Vec::with_capacity(text.len());
    if old.is_empty() {
        // Insert `new` before every scalar and at the end, up to n times.
        let mut done = 0i64;
        let mut i = 0;
        loop {
            if n >= 0 && done >= n {
                break;
            }
            out.extend_from_slice(new);
            done += 1;
            if i >= text.len() {
                return out;
            }
            let w = utf8::decode(&text[i..]).1;
            out.extend_from_slice(&text[i..i + w]);
            i += w;
        }
        out.extend_from_slice(&text[i..]);
        return out;
    }
    let mut i = 0;
    let mut done = 0i64;
    while n < 0 || done < n {
        match find(&text[i..], old) {
            None => break,
            Some(p) => {
                out.extend_from_slice(&text[i..i + p]);
                out.extend_from_slice(new);
                i += p + old.len();
                done += 1;
            }
        }
    }
    out.extend_from_slice(&text[i..]);
    out
}

unsafe fn replace_limited(
    s: *const StrVal,
    old: *const StrVal,
    new: *const StrVal,
    n: i64,
    op: &str,
) -> StrVal {
    // SAFETY: caller passes live strings.
    unsafe {
        if n < 0 {
            fault::fault_fmt(format_args!(
                "{op}: max_replacements must be nonnegative, found {n}"
            ));
        }
        let (text, o) = (bytes(s), bytes(old));
        let bound = if o.is_empty() {
            utf8::count(text) as i64 + 1
        } else {
            text.len() as i64
        };
        let out = replace_n_bytes(text, o, bytes(new), n.min(bound));
        from_buf(out)
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_replace_first(
    s: *const StrVal,
    old: *const StrVal,
    new: *const StrVal,
    has_max: u8,
    max: i64,
    out: *mut StrVal,
) {
    // SAFETY: caller passes a writable `out` and live arguments.
    unsafe { (msrt_string_replace_first_val(s, old, new, has_max, max)).write_to(out) }
}

#[inline(always)]
unsafe fn msrt_string_replace_first_val(
    s: *const StrVal,
    old: *const StrVal,
    new: *const StrVal,
    has_max: u8,
    max: i64,
) -> StrVal {
    // SAFETY: forwarded contract.
    unsafe { replace_limited(s, old, new, if has_max != 0 { max } else { 1 }, "replace") }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_replace(
    s: *const StrVal,
    old: *const StrVal,
    new: *const StrVal,
    has_max: u8,
    max: i64,
    out: *mut StrVal,
) {
    // SAFETY: caller passes a writable `out` and live arguments.
    unsafe { (msrt_string_replace_val(s, old, new, has_max, max)).write_to(out) }
}

#[inline(always)]
unsafe fn msrt_string_replace_val(
    s: *const StrVal,
    old: *const StrVal,
    new: *const StrVal,
    has_max: u8,
    max: i64,
) -> StrVal {
    // SAFETY: forwarded contract.
    unsafe { msrt_string_replace_first_val(s, old, new, has_max, max) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_replace_n(
    s: *const StrVal,
    old: *const StrVal,
    new: *const StrVal,
    max: i64,
    out: *mut StrVal,
) {
    // SAFETY: caller passes a writable `out` and live arguments.
    unsafe { (msrt_string_replace_n_val(s, old, new, max)).write_to(out) }
}

#[inline(always)]
unsafe fn msrt_string_replace_n_val(
    s: *const StrVal,
    old: *const StrVal,
    new: *const StrVal,
    max: i64,
) -> StrVal {
    // SAFETY: forwarded contract.
    unsafe { replace_limited(s, old, new, max, "replace") }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_replace_all(
    s: *const StrVal,
    old: *const StrVal,
    new: *const StrVal,
    has_max: u8,
    max: i64,
    out: *mut StrVal,
) -> u8 {
    // SAFETY: caller passes live strings and a writable out.
    unsafe {
        let limit = if has_max != 0 { max } else { i64::MAX };
        if limit < 0 {
            return STATUS_INVALID_INPUT;
        }
        let (text, o, n) = (bytes(s), bytes(old), bytes(new));
        // Size check before building.
        let count = if o.is_empty() {
            utf8::count(text) + 1
        } else {
            count_matches(text, o)
        };
        let total = text.len() as i128 + count as i128 * (n.len() as i128 - o.len() as i128);
        if total > limit as i128 || total > MAX_BYTES as i128 {
            return STATUS_LIMIT_EXCEEDED;
        }
        *out = from_buf(replace_n_bytes(text, o, n, -1));
        STATUS_OK
    }
}

unsafe fn pad(
    atstart: bool,
    s: *const StrVal,
    target: i64,
    padding: *const StrVal,
    has_max: u8,
    max: i64,
    out: *mut StrVal,
) -> u8 {
    // SAFETY: caller passes live strings and a writable out.
    unsafe {
        let limit = if has_max != 0 { max } else { i64::MAX };
        if target < 0 || limit < 0 {
            return STATUS_INVALID_INPUT;
        }
        let limit = (limit as u64).min(MAX_BYTES as u64) as usize;
        let text = bytes(s);
        if text.len() > limit {
            return STATUS_LIMIT_EXCEEDED;
        }
        let needed = target - scalar_count(s) as i64;
        let padb = bytes(padding);
        if needed <= 0 || padb.is_empty() {
            *out = cloned(&*s);
            return STATUS_OK;
        }
        let needed = needed as usize;
        if needed > limit - text.len() {
            return STATUS_LIMIT_EXCEEDED;
        }
        let pcount = scalar_count(padding);
        let (cycles, rem) = (needed / pcount, needed % pcount);
        let prefix_end = if rem > 0 {
            utf8::offset_of(padb, rem)
        } else {
            0
        };
        let remaining = limit as i128 - text.len() as i128 - prefix_end as i128;
        if remaining < 0 || cycles as i128 > remaining / padb.len() as i128 {
            return STATUS_LIMIT_EXCEEDED;
        }
        let mut b = Vec::with_capacity(text.len() + cycles * padb.len() + prefix_end);
        if !atstart {
            b.extend_from_slice(text);
        }
        for _ in 0..cycles {
            b.extend_from_slice(padb);
        }
        b.extend_from_slice(&padb[..prefix_end]);
        if atstart {
            b.extend_from_slice(text);
        }
        *out = from_buf(b);
        STATUS_OK
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_pad_start(
    s: *const StrVal,
    target: i64,
    padding: *const StrVal,
    has_max: u8,
    max: i64,
    out: *mut StrVal,
) -> u8 {
    // SAFETY: forwarded contract.
    unsafe { pad(true, s, target, padding, has_max, max, out) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_pad_end(
    s: *const StrVal,
    target: i64,
    padding: *const StrVal,
    has_max: u8,
    max: i64,
    out: *mut StrVal,
) -> u8 {
    // SAFETY: forwarded contract.
    unsafe { pad(false, s, target, padding, has_max, max, out) }
}

// ---------------------------------------------------------------------------
// Slicing
// ---------------------------------------------------------------------------

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_slice_scalars(
    s: *const StrVal,
    start: i64,
    end: i64,
    out: *mut StrVal,
) -> u8 {
    // SAFETY: caller passes a live string and a writable out.
    unsafe {
        let n = scalar_count(s) as i64;
        if start < 0 || end < start || end > n {
            return STATUS_OUT_OF_RANGE;
        }
        *out = sub_scalars(s, start as usize, end as usize);
        STATUS_OK
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_slice(
    s: *const StrVal,
    start: i64,
    end: i64,
    out: *mut StrVal,
) -> u8 {
    // SAFETY: caller passes a live string and a writable out.
    unsafe {
        let n = scalar_count(s) as i64;
        let (a, b) = (
            if start < 0 { n + start } else { start },
            if end < 0 { n + end } else { end },
        );
        if a < 0 || b < a || b > n {
            return STATUS_OUT_OF_RANGE;
        }
        *out = sub_scalars(s, a as usize, b as usize);
        STATUS_OK
    }
}

// ---------------------------------------------------------------------------
// Lists produced from strings (List[String] = VecVal of 8-byte string pointers)
// ---------------------------------------------------------------------------

/// Bytes of a `List[String]` element.
const ELEM: usize = core::mem::size_of::<StrVal>();

/// Appends a string (owned) to a `List[String]` being built.
unsafe fn push_str(v: &mut VecVal, p: StrVal) {
    // SAFETY: elements are `StrVal`s stored inline.
    unsafe {
        if v.len == v.cap {
            let cap = if v.cap == 0 { 4 } else { v.cap * 2 };
            v.ptr = if v.ptr.is_null() {
                alloc::alloc(cap * ELEM)
            } else {
                alloc::realloc(v.ptr, cap * ELEM)
            };
            v.cap = cap;
        }
        *(v.ptr as *mut StrVal).add(v.len) = p;
        v.len += 1;
    }
}

const EMPTY_VEC: VecVal = VecVal {
    ptr: null_mut(),
    len: 0,
    cap: 0,
};

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_chars(s: *const StrVal, out: *mut VecVal) {
    // SAFETY: caller passes a live string and a writable out.
    unsafe {
        let text = bytes(s);
        if !text.is_empty() && text.is_ascii() {
            // One shared static per ASCII character, so the list is filled without allocating
            // or counting references (static objects have a huge count).
            let n = text.len();
            let p = alloc::alloc(n * ELEM) as *mut StrVal;
            let base = core::ptr::addr_of_mut!(ASCII) as *mut u8;
            for (k, &b) in text.iter().enumerate() {
                let q = p.add(k);
                (*q).ptr = base.add((b as usize) * ms_rt_abi::ASCII_CHAR_STRIDE);
                (*q).len = 1;
                (*q).cap = 0;
            }
            *out = VecVal {
                ptr: p as _,
                len: n,
                cap: n,
            };
            return;
        }
        let mut v = EMPTY_VEC;
        let mut i = 0;
        while i < text.len() {
            let (c, w) = utf8::decode(&text[i..]);
            let p = if c == 0xFFFD && w == 1 {
                from_bytes("\u{FFFD}".as_bytes())
            } else {
                from_bytes(&text[i..i + w])
            };
            push_str(&mut v, p);
            i += w;
        }
        *out = v;
    }
}

/// The character that starts at byte `at`, which `for c in text.chars()` reaches for a non-ASCII
/// lead byte (or a stray byte, which reads as U+FFFD): an owned one-character string.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_char_at(s: *const StrVal, at: i64, out: *mut StrVal) {
    // SAFETY: caller passes a writable `out` and live arguments.
    unsafe { (msrt_string_char_at_val(s, at)).write_to(out) }
}

#[inline(always)]
unsafe fn msrt_string_char_at_val(s: *const StrVal, at: i64) -> StrVal {
    // SAFETY: caller passes a live string and an offset inside it.
    unsafe {
        let text = &bytes(s)[at as usize..];
        let (c, w) = utf8::decode(text);
        if c == 0xFFFD && w == 1 {
            from_bytes("\u{FFFD}".as_bytes())
        } else {
            from_bytes(&text[..w])
        }
    }
}

/// Byte width of the character that starts at byte `at`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_char_width(s: *const StrVal, at: i64) -> i64 {
    // SAFETY: caller passes a live string and an offset inside it.
    unsafe { utf8::decode(&bytes(s)[at as usize..]).1 as i64 }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_lines(s: *const StrVal, out: *mut VecVal) {
    // SAFETY: caller passes a live string and a writable out.
    unsafe {
        let text = bytes(s);
        let mut v = EMPTY_VEC;
        let mut start = 0;
        while let Some(p) = text[start..].iter().position(|&c| c == b'\n') {
            let mut end = start + p;
            if end > start && text[end - 1] == b'\r' {
                end -= 1;
            }
            push_str(&mut v, from_bytes(&text[start..end]));
            start += p + 1;
        }
        if start < text.len() {
            push_str(&mut v, from_bytes(&text[start..]));
        }
        *out = v;
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_split(
    s: *const StrVal,
    sep: *const StrVal,
    has_max: u8,
    max: i64,
    out: *mut VecVal,
) {
    // SAFETY: caller passes live strings and a writable out.
    unsafe {
        let (text, sepb) = (bytes(s), bytes(sep));
        let mut limit = usize::MAX;
        if has_max != 0 {
            if max < 0 {
                fault::fault_fmt(format_args!(
                    "split: max_parts must be nonnegative, found {max}"
                ));
            }
            limit = max as usize;
        }
        let mut v = EMPTY_VEC;
        if limit == 0 {
            *out = v;
            return;
        }
        if sepb.is_empty() {
            // Split after each scalar.
            let mut i = 0;
            while i < text.len() && v.len < limit {
                let w = utf8::decode(&text[i..]).1;
                push_str(&mut v, from_bytes(&text[i..i + w]));
                i += w;
            }
            *out = v;
            return;
        }
        let mut start = 0;
        while v.len < limit {
            match find(&text[start..], sepb) {
                Some(p) => {
                    push_str(&mut v, from_bytes(&text[start..start + p]));
                    start += p + sepb.len();
                }
                None => {
                    push_str(&mut v, from_bytes(&text[start..]));
                    break;
                }
            }
        }
        *out = v;
    }
}

/// The state of `for piece in text.split(separator)` that does not build the list.
///
/// The piece handed to the loop is owned by the iterator and lent to the body, which copies it
/// to keep it; the iterator rewrites it in place for the next one.
#[repr(C)]
pub struct SplitIter {
    hdr: Obj,
    /// Borrowed from the loop's operands, which outlive the iterator.
    src: StrVal,
    sep: StrVal,
    /// The current piece (a shared static for short ones), or [`NO_STR`] before the first.
    cur: StrVal,
    /// Byte capacity of `cur` when it is a private allocation, else 0.
    cap: usize,
    pos: usize,
    /// Pieces still allowed (`max_parts`).
    left: usize,
    done: bool,
}

unsafe extern "C" fn split_iter_drop(o: *mut Obj) {
    // SAFETY: `o` is a dead iterator that owns one reference to each string it holds.
    unsafe {
        let it = o as *mut SplitIter;
        release_opt(&(*it).cur);
        alloc::free(o as *mut u8);
    }
}

/// Starts a split loop; the same fault as `split` for a negative `max_parts`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_split_iter(
    s: *const StrVal,
    sep: *const StrVal,
    has_max: u8,
    max: i64,
) -> *mut SplitIter {
    // SAFETY: caller passes live strings.
    unsafe {
        let mut left = usize::MAX;
        if has_max != 0 {
            if max < 0 {
                fault::fault_fmt(format_args!(
                    "split: max_parts must be nonnegative, found {max}"
                ));
            }
            left = max as usize;
        }
        let it = obj::new_obj(core::mem::size_of::<SplitIter>(), split_iter_drop) as *mut SplitIter;
        // The loop keeps both strings alive until it ends, so the iterator only borrows them.
        (*it).src = (*s).alias();
        (*it).sep = (*sep).alias();
        (*it).cur = NO_STR;
        (*it).cap = 0;
        (*it).pos = 0;
        (*it).left = left;
        (*it).done = false;
        it
    }
}

/// Makes the next piece current and writes a borrow of it to `out` (the iterator owns the bytes
/// until the next call); returns 0 when the pieces are used up.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_split_next(it: *mut SplitIter, out: *mut StrVal) -> u8 {
    // SAFETY: caller passes a live iterator and a writable `out`.
    unsafe {
        match split_next(it) {
            Some(value) => {
                value.write_to(out);
                1
            }
            None => 0,
        }
    }
}

unsafe fn split_next(it: *mut SplitIter) -> Option<StrVal> {
    // SAFETY: `it` is a live iterator.
    unsafe {
        let st = &mut *it;
        if st.done || st.left == 0 {
            return None;
        }
        let (text, sepb) = (bytes(&st.src), bytes(&st.sep));
        let piece: &[u8] = if sepb.is_empty() {
            // Split after each scalar.
            if st.pos >= text.len() {
                st.done = true;
                return None;
            }
            let w = utf8::decode(&text[st.pos..]).1;
            let p = &text[st.pos..st.pos + w];
            st.pos += w;
            p
        } else {
            let at = if let [c] = sepb {
                memchr(*c, &text[st.pos..])
            } else {
                find(&text[st.pos..], sepb)
            };
            match at {
                Some(n) => {
                    let p = &text[st.pos..st.pos + n];
                    st.pos += n + sepb.len();
                    p
                }
                None => {
                    st.done = true;
                    &text[st.pos..]
                }
            }
        };
        st.left -= 1;
        set_piece(st, piece);
        Some(st.cur.alias())
    }
}

/// Copies `n` bytes; short copies avoid the call to `memcpy`.
///
/// # Safety
/// The ranges must be valid for `n` bytes and must not overlap.
#[inline(always)]
unsafe fn copy_short(src: *const u8, dst: *mut u8, n: usize) {
    // SAFETY: each branch reads and writes only inside the `n` bytes.
    unsafe {
        if (8..=16).contains(&n) {
            let head = (src as *const u64).read_unaligned();
            let tail = (src.add(n - 8) as *const u64).read_unaligned();
            (dst as *mut u64).write_unaligned(head);
            (dst.add(n - 8) as *mut u64).write_unaligned(tail);
        } else if (4..8).contains(&n) {
            let head = (src as *const u32).read_unaligned();
            let tail = (src.add(n - 4) as *const u32).read_unaligned();
            (dst as *mut u32).write_unaligned(head);
            (dst.add(n - 4) as *mut u32).write_unaligned(tail);
        } else if n > 16 || n == 0 {
            core::ptr::copy_nonoverlapping(src, dst, n);
        } else {
            for i in 0..n {
                *dst.add(i) = *src.add(i);
            }
        }
    }
}

/// Stores `piece` as the iterator's current string.
unsafe fn set_piece(st: &mut SplitIter, piece: &[u8]) {
    // SAFETY: `st.cur` is [`NO_STR`] or a live string this iterator holds a reference to.
    unsafe {
        if piece.len() <= 1 && piece.first().is_none_or(|&b| b < 0x80) {
            // Empty and one-byte ASCII pieces are shared statics.
            release_opt(&st.cur);
            st.cap = 0;
            st.cur = from_bytes(piece);
            return;
        }
        if st.cap >= piece.len() && !st.cur.ptr.is_null() && st.cur.cap != 0 {
            // The loop only borrows the piece: rewrite it in place.
            let h = HINT.ptr();
            if core::ptr::eq((*h).s, st.cur.ptr) {
                (*h).s = core::ptr::null();
            }
            st.cur.len = piece.len();
            copy_short(piece.as_ptr(), st.cur.ptr, piece.len());
            *st.cur.ptr.add(piece.len()) = 0;
            return;
        }
        release_opt(&st.cur);
        let cap = piece.len().max(24);
        let mut fresh = alloc_str(cap);
        fresh.len = piece.len();
        copy_short(piece.as_ptr(), fresh.ptr, piece.len());
        *fresh.ptr.add(piece.len()) = 0;
        st.cur = fresh;
        st.cap = cap;
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_scalar_values(s: *const StrVal, out: *mut VecVal) {
    // SAFETY: caller passes a live string and a writable out; 8-byte elements.
    unsafe {
        let text = bytes(s);
        let n = scalar_count(s);
        let p = if n == 0 {
            null_mut()
        } else {
            alloc::alloc(n * 8)
        } as *mut i64;
        let (mut i, mut k) = (0, 0);
        while i < text.len() {
            let (c, w) = utf8::decode(&text[i..]);
            *p.add(k) = c as i64;
            k += 1;
            i += w;
        }
        *out = VecVal {
            ptr: p as *mut u8,
            len: n,
            cap: n,
        };
    }
}

/// `String.from_scalars(values: List[Int])`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_from_scalars(
    values: *const VecVal,
    out: *mut StrVal,
) -> u8 {
    // SAFETY: caller passes a live list of Int and a writable out.
    unsafe {
        let v = &*values;
        let mut b = Vec::with_capacity(v.len);
        let mut tmp = [0u8; 4];
        for i in 0..v.len {
            let n = *(v.ptr as *const i64).add(i);
            if !(0..=0x10FFFF).contains(&n) || (0xD800..=0xDFFF).contains(&n) {
                return STATUS_INVALID_INPUT;
            }
            let w = utf8::encode(n as u32, &mut tmp);
            b.extend_from_slice(&tmp[..w]);
        }
        *out = from_buf(b);
        STATUS_OK
    }
}

/// `String.to_bytes()`: a Bytes value (VecVal of u8).
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_to_bytes(s: *const StrVal, out: *mut VecVal) {
    // SAFETY: caller passes a live string and a writable out.
    unsafe {
        let text = bytes(s);
        let p = if text.is_empty() {
            null_mut()
        } else {
            alloc::alloc(text.len())
        };
        if !text.is_empty() {
            core::ptr::copy_nonoverlapping(text.as_ptr(), p, text.len());
        }
        *out = VecVal {
            ptr: p,
            len: text.len(),
            cap: text.len(),
        };
    }
}

/// `String.parse_int()`: present flag, value through `out`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_parse_int(s: *const StrVal, out: *mut i64) -> u8 {
    // SAFETY: caller passes a live string and a writable out.
    unsafe {
        match crate::num::parse_int_decimal(bytes(s)) {
            Some(v) => {
                *out = v;
                1
            }
            None => 0,
        }
    }
}

/// Normalization forms by the spelling `String.normalize` takes.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_normalize(
    s: *const StrVal,
    form: *const StrVal,
    has_max: u8,
    max: i64,
    out: *mut StrVal,
) -> u8 {
    // SAFETY: caller passes live strings and a writable out.
    unsafe {
        if has_max != 0 && max < 0 {
            return STATUS_INVALID_INPUT;
        }
        let kind = match bytes(form) {
            b"NFC" => 0,
            b"NFD" => 1,
            b"NFKC" => 2,
            b"NFKD" => 3,
            _ => return STATUS_INVALID_INPUT,
        };
        normalize_kind(s, kind, has_max, max, out)
    }
}

/// `NormalizationForm.normalize`: `kind` is the case index (Nfc 0, Nfd 1, Nfkc 2, Nfkd 3).
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_normalize_kind(
    s: *const StrVal,
    kind: i64,
    has_max: u8,
    max: i64,
    out: *mut StrVal,
) -> u8 {
    // SAFETY: forwarded contract.
    unsafe { normalize_kind(s, kind, has_max, max, out) }
}

unsafe fn normalize_kind(
    s: *const StrVal,
    kind: i64,
    has_max: u8,
    max: i64,
    out: *mut StrVal,
) -> u8 {
    use unicode_normalization::UnicodeNormalization;
    if has_max != 0 && max < 0 {
        return STATUS_INVALID_INPUT;
    }
    // SAFETY: caller passes a live string and a writable out.
    unsafe {
        let limit = if has_max != 0 {
            max as usize
        } else {
            usize::MAX
        };
        let text = bytes(s);
        let mut chars: Vec<char> = Vec::new();
        let mut i = 0;
        while i < text.len() {
            let (c, w) = utf8::decode(&text[i..]);
            chars.push(char::from_u32(c).unwrap_or('\u{FFFD}'));
            i += w;
        }
        let mut b = Vec::new();
        let mut tmp = [0u8; 4];
        let mut push = |c: char| -> bool {
            let e = c.encode_utf8(&mut tmp).as_bytes();
            if e.len() > limit.saturating_sub(b.len()) {
                return false;
            }
            b.extend_from_slice(e);
            true
        };
        let it = chars.as_slice().iter().copied();
        let ok = match kind {
            0 => it.nfc().all(&mut push),
            1 => it.nfd().all(&mut push),
            2 => it.nfkc().all(&mut push),
            _ => it.nfkd().all(&mut push),
        };
        if !ok {
            return STATUS_LIMIT_EXCEEDED;
        }
        *out = from_buf(b);
        STATUS_OK
    }
}

// ---------------------------------------------------------------------------
// Conversions to string (Int, Float, Bool)
// ---------------------------------------------------------------------------

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_int_to_string(v: i64, out: *mut StrVal) {
    // SAFETY: caller passes a writable `out` and live arguments.
    unsafe { (msrt_int_to_string_val(v)).write_to(out) }
}

unsafe fn msrt_int_to_string_val(v: i64) -> StrVal {
    let mut tmp = [0u8; 20];
    from_bytes(crate::num::format_i64(v, &mut tmp))
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_float_to_string(v: f64, out: *mut StrVal) {
    // SAFETY: caller passes a writable `out` and live arguments.
    unsafe { (msrt_float_to_string_val(v)).write_to(out) }
}

unsafe fn msrt_float_to_string_val(v: f64) -> StrVal {
    from_buf(crate::num::float_to_string(v))
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_bool_to_string(v: u8, out: *mut StrVal) {
    // SAFETY: caller passes a writable `out` and live arguments.
    unsafe { (msrt_bool_to_string_val(v)).write_to(out) }
}

unsafe fn msrt_bool_to_string_val(v: u8) -> StrVal {
    from_bytes(if v != 0 { b"true" } else { b"false" })
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_int_to_string_radix(v: i64, radix: i64, out: *mut StrVal) {
    // SAFETY: caller passes a writable `out` and live arguments.
    unsafe { (msrt_int_to_string_radix_val(v, radix)).write_to(out) }
}

unsafe fn msrt_int_to_string_radix_val(v: i64, radix: i64) -> StrVal {
    if !(2..=36).contains(&radix) {
        fault::fault_fmt(format_args!(
            "to_string_radix: radix must be between 2 and 36, found {radix}"
        ));
    }
    let mut b = Vec::new();
    crate::num::format_radix(v, radix as u32, &mut b);
    from_buf(b)
}

/// The double-quoted, escaped spelling of a string (as `%q` writes it).
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_quote(s: *const StrVal, out: *mut StrVal) {
    // SAFETY: caller passes a writable `out` and live arguments.
    unsafe { (msrt_string_quote_val(s)).write_to(out) }
}

#[inline(always)]
unsafe fn msrt_string_quote_val(s: *const StrVal) -> StrVal {
    // SAFETY: caller passes a live string.
    let text = unsafe { bytes(s) };
    let mut out = Vec::with_capacity(text.len() + 2);
    out.push(b'"');
    let mut i = 0;
    while i < text.len() {
        let c = text[i];
        match c {
            b'"' => out.extend_from_slice(b"\\\""),
            b'\\' => out.extend_from_slice(b"\\\\"),
            b'\n' => out.extend_from_slice(b"\\n"),
            b'\t' => out.extend_from_slice(b"\\t"),
            b'\r' => out.extend_from_slice(b"\\r"),
            0..=0x1f | 0x7f => {
                const HEX: &[u8; 16] = b"0123456789abcdef";
                out.extend_from_slice(b"\\x");
                out.push(HEX[(c >> 4) as usize]);
                out.push(HEX[(c & 15) as usize]);
            }
            _ => out.push(c),
        }
        i += 1;
    }
    out.push(b'"');
    from_buf(out)
}

/// Dynamic string copies and drops, `[drop static, drop owned, copy static, copy owned]`, counted when
/// the program was compiled with `MS_COUNT_STR` set (see `ms-clif`); printed at exit by the `stats` runtime.
pub static STR_COUNTS: Global<[u64; 4]> = Global::new([0; 4]);

/// Records one executed string drop (`kind` 0) or copy (1) of a string whose capacity word is `cap`.
#[unsafe(no_mangle)]
pub extern "C" fn msrt_str_count(kind: i64, cap: i64) {
    // SAFETY: single threaded access to the counters.
    unsafe { (*STR_COUNTS.ptr())[(kind as usize) * 2 + (cap != 0) as usize] += 1 };
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hash_bytes_separates_lengths_and_contents() {
        let mut seen = std::collections::HashSet::new();
        for len in 0..40usize {
            for fill in [0u8, b'a', 0xff]
                .into_iter()
                .take(if len == 0 { 1 } else { 3 })
            {
                let v = std::vec![fill; len];
                assert_eq!(hash_bytes(&v), hash_bytes(&v.clone()));
                assert!(
                    seen.insert(hash_bytes(&v)),
                    "collision at len {len} fill {fill}"
                );
            }
        }
        for at in 0..24usize {
            let mut a = std::vec![b'x'; 24];
            let b = a.clone();
            a[at] = b'y';
            assert_ne!(hash_bytes(&a), hash_bytes(&b), "byte {at} ignored");
        }
    }

    #[test]
    fn find_matches_naive_search() {
        let mut seed = 0x2545_f491_4f6c_dd1du64;
        let mut next = || {
            seed ^= seed << 13;
            seed ^= seed >> 7;
            seed ^= seed << 17;
            seed
        };
        for _ in 0..4000 {
            let hay_len = (next() % 90) as usize;
            let needle_len = (next() % 6) as usize;
            let hay: Vec<u8> = (0..hay_len).map(|_| b'a' + (next() % 3) as u8).collect();
            let needle: Vec<u8> = (0..needle_len).map(|_| b'a' + (next() % 3) as u8).collect();
            let naive = if needle.is_empty() {
                Some(0)
            } else {
                hay.windows(needle.len()).position(|w| w == &needle[..])
            };
            assert_eq!(find(&hay, &needle), naive, "{hay:?} {needle:?}");
        }
    }
    use crate::testutil;
    use std::string::String as S;

    /// A string argument that lives for the rest of the test run.
    fn st(t: &str) -> *const StrVal {
        Box::leak(Box::new(from_bytes(t.as_bytes())))
    }
    fn txt(s: &StrVal) -> S {
        // SAFETY: tests pass live strings.
        S::from_utf8_lossy(unsafe { bytes(s) }).into_owned()
    }
    /// Calls a string-returning function on a fresh output slot and reads the result.
    fn ret(f: impl FnOnce(*mut StrVal)) -> S {
        let mut o = NO_STR;
        f(&mut o);
        txt(&o)
    }
    fn list(v: VecVal) -> std::vec::Vec<S> {
        (0..v.len)
            // SAFETY: the list holds `v.len` inline strings.
            .map(|i| txt(unsafe { &*(v.ptr as *const StrVal).add(i) }))
            .collect()
    }

    #[test]
    fn length_and_get_follow_scalars() {
        let _g = testutil::lock();
        unsafe {
            let s = st("héllo");
            assert_eq!(msrt_string_length(s), 5);
            assert_eq!(msrt_string_byte_length(s), 6);
            assert_eq!(ret(|o| msrt_string_get(s, 1, 0, st(""), o)), "é");
            assert_eq!(ret(|o| msrt_string_get(s, -1, 0, st(""), o)), "o");
            assert_eq!(msrt_string_scalar_at(s, 1, 0, 0), 0xE9);
            testutil::assert_fault(
                "index 9 out of range for length 5; pass a default: get(index:, default: ...)",
                || {
                    ret(|o| msrt_string_get(s, 9, 0, st(""), o));
                },
            );
        }
    }

    #[test]
    fn split_replace_trim() {
        let _g = testutil::lock();
        unsafe {
            let mut v = EMPTY_VEC;
            msrt_string_split(st("a,b,c"), st(","), 1, 2, &mut v);
            assert_eq!(list(v), ["a", "b"]);
            msrt_string_split(st("héy"), st(""), 0, 0, &mut v);
            assert_eq!(list(v), ["h", "é", "y"]);
            assert_eq!(
                ret(|o| msrt_string_replace_n(st("aaa"), st("a"), st("b"), 2, o)),
                "bba"
            );
            assert_eq!(
                ret(|o| msrt_string_replace_n(st("ab"), st(""), st("-"), 5, o)),
                "-a-b-"
            );
            assert_eq!(ret(|o| msrt_string_trim(st("  \t x y \n"), o)), "x y");
            assert_eq!(
                ret(|o| msrt_string_trim(st("\u{0b}\u{0c}\r\n ok \u{1c}"), o)),
                "ok \u{1c}"
            );
            assert_eq!(ret(|o| msrt_string_trim(st("\u{a0}é\u{2003} \t"), o)), "é");
            assert_eq!(
                ret(|o| msrt_string_trim_start(st(" \u{85}x \u{85}"), o)),
                "x \u{85}"
            );
            assert_eq!(ret(|o| msrt_string_trim_end(st(" x\u{3000} "), o)), " x");
            assert_eq!(ret(|o| msrt_string_trim(st("   "), o)), "");
            let mut o = NO_STR;
            assert_eq!(
                msrt_string_replace_all(st("abc"), st("b"), st("xyz"), 1, 4, &mut o),
                STATUS_LIMIT_EXCEEDED
            );
            assert_eq!(
                msrt_string_replace_all(st("abc"), st("b"), st("xy"), 1, 4, &mut o),
                STATUS_OK
            );
            assert_eq!(txt(&o), "axyc");
        }
    }

    #[test]
    fn case_pad_slice() {
        let _g = testutil::lock();
        unsafe {
            assert_eq!(ret(|o| msrt_string_upper(st("straße"), o)), "STRASSE");
            assert_eq!(ret(|o| msrt_string_lower(st("ΟΔΟΣ"), o)), "οδος");
            let mut o = NO_STR;
            assert_eq!(
                msrt_string_pad_start(st("7"), 3, st("ab"), 0, 0, &mut o),
                STATUS_OK
            );
            assert_eq!(txt(&o), "ab7");
            assert_eq!(msrt_string_slice(st("héllo"), 1, -1, &mut o), STATUS_OK);
            assert_eq!(txt(&o), "éll");
            assert_eq!(
                msrt_string_slice(st("abc"), 2, 1, &mut o),
                STATUS_OUT_OF_RANGE
            );
            assert_eq!(ret(|o| msrt_string_reverse(st("aé"), o)), "éa");
        }
    }

    #[test]
    fn normalize_nfd() {
        let _g = testutil::lock();
        unsafe {
            let mut o = NO_STR;
            assert_eq!(
                msrt_string_normalize(st("é"), st("NFD"), 0, 0, &mut o),
                STATUS_OK
            );
            assert_eq!(txt(&o), "e\u{301}");
            assert_eq!(
                msrt_string_normalize(st("é"), st("NFD"), 1, 2, &mut o),
                STATUS_LIMIT_EXCEEDED
            );
        }
    }
}
