//! `String`: immutable UTF-8 text with scalar-indexed operations.
//!
//! The value is a [`StrVal`] (`{ ptr, len, cap }`, see `ms-rt-abi`): `ptr` points at the bytes,
//! which are followed by one NUL. An owned string (`cap >= 1`) is a single allocation that
//! copying duplicates and dropping frees; a static one (`cap == 0`) is never freed. Language level
//! indices and lengths count Unicode scalars; a string whose scalar count equals its byte length
//! is ASCII, which every indexing operation exploits.
//! ms: domain string
use crate::alloc;
use crate::fault;
use crate::obj;
use crate::utf8;
use core::ptr::null_mut;
use ms_rt_abi::{
    FrameBuf, HasRaw, Obj, STATUS_INVALID_INPUT, STATUS_LIMIT_EXCEEDED, STATUS_OK, STR_INLINE_MAX,
    StrVal, VecVal,
};

// The moved symbols (runtime/symbols/string.txt) are defined by the C runtime; Rust callers and tests reach them here.
unsafe extern "C-unwind" {
    pub fn msrt_string_compare(a: *const StrVal, b: *const StrVal) -> i64;
    pub fn msrt_string_length(s: *const StrVal) -> i64;
    pub fn msrt_string_scalar_length(s: *const StrVal) -> i64;
    pub fn msrt_string_contains(a: *const StrVal, v: *const StrVal) -> u8;
    pub fn msrt_string_split(s: *const StrVal, sep: *const StrVal, out: *mut VecVal);
    pub fn msrt_string_split_view(s: *const StrVal, sep: *const StrVal, out: *mut VecVal);
    pub fn msrt_string_replace(
        s: *const StrVal,
        old: *const StrVal,
        new: *const StrVal,
        out: *mut StrVal,
    );
    pub fn msrt_string_replace_first(
        s: *const StrVal,
        old: *const StrVal,
        new: *const StrVal,
        out: *mut StrVal,
    );
    pub fn msrt_string_replace_take(
        s: *mut StrVal,
        old: *const StrVal,
        new: *const StrVal,
        out: *mut StrVal,
    );
    pub fn msrt_string_fmt2(mask: i64, a: usize, b: usize, out: *mut StrVal);
    pub fn msrt_string_fmt3(mask: i64, a: usize, b: usize, c: usize, out: *mut StrVal);
    pub fn msrt_string_append_fmt1(s: *const StrVal, mask: i64, a: usize, out: *mut StrVal);
    pub fn msrt_string_append_fmt2(
        s: *const StrVal,
        mask: i64,
        a: usize,
        b: usize,
        out: *mut StrVal,
    );
    pub fn msrt_string_append_fmt3(
        s: *const StrVal,
        mask: i64,
        a: usize,
        b: usize,
        c: usize,
        out: *mut StrVal,
    );
    pub fn msrt_string_from_bytes(ptr: *const u8, len: usize, out: *mut StrVal);
    pub fn msrt_string_clone(s: *const StrVal, out: *mut StrVal);
    pub fn msrt_string_free(s: *const StrVal);
    pub fn msrt_string_concat(a: *const StrVal, b: *const StrVal, out: *mut StrVal);
    pub fn msrt_string_concat3(
        a: *const StrVal,
        b: *const StrVal,
        c: *const StrVal,
        out: *mut StrVal,
    );
    pub fn msrt_string_concat4(
        a: *const StrVal,
        b: *const StrVal,
        c: *const StrVal,
        d: *const StrVal,
        out: *mut StrVal,
    );
    pub fn msrt_string_slice(s: *const StrVal, start: i64, end: i64, out: *mut StrVal);
    pub fn msrt_string_append(a: *const StrVal, b: *const StrVal, out: *mut StrVal);
    pub fn msrt_string_repeat(s: *const StrVal, count: i64, out: *mut StrVal);
    pub fn msrt_string_reverse(a: *const StrVal, out: *mut StrVal);
    pub fn msrt_string_trim(s: *const StrVal, out: *mut StrVal);
    pub fn msrt_string_trim_start(s: *const StrVal, out: *mut StrVal);
    pub fn msrt_string_trim_end(s: *const StrVal, out: *mut StrVal);
    pub fn msrt_string_trim_take(s: *mut StrVal, out: *mut StrVal);
    pub fn msrt_string_trim_start_take(s: *mut StrVal, out: *mut StrVal);
    pub fn msrt_string_trim_end_take(s: *mut StrVal, out: *mut StrVal);
    pub fn msrt_string_index_of(a: *const StrVal, v: *const StrVal, out: *mut i64) -> u8;
    pub fn msrt_string_pad_start(
        s: *const StrVal,
        target: i64,
        padding: *const StrVal,
        out: *mut StrVal,
    );
    pub fn msrt_string_pad_end(
        s: *const StrVal,
        target: i64,
        padding: *const StrVal,
        out: *mut StrVal,
    );
}

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

/// Deterministic 64-bit hash of bytes. Up to [`STR_INLINE_MAX`] bytes are the two words an inline
/// string holds (zero past the length), folded in turn with the length as the seed, which is what
/// the compiler's inline map probe computes from an inline key. Longer text takes eight bytes per
/// multiply-fold step, with the tail read as one overlapping word, then a final avalanche. Hashes
/// are lookup aids, not stable identifiers.
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
    let n = b.len();
    let mut h = K0 ^ (n as u64).wrapping_mul(K1);
    if n <= STR_INLINE_MAX {
        return hash_inline(n, StrVal::inline(b).inline_bits());
    }
    let mut i = 0;
    while i + 8 <= n {
        h = fold(h ^ word(b, i), K1);
        i += 8;
    }
    // Sixteen bytes or more: the last eight bytes, overlapping the words already folded in.
    let tail = word(b, n - 8);
    fold(h ^ tail, K0)
}

/// The hash of a string of `n <= STR_INLINE_MAX` bytes whose little-endian bits are `bits`.
#[inline(always)]
fn hash_inline(n: usize, bits: u128) -> u64 {
    const K0: u64 = 0x9e37_79b9_7f4a_7c15;
    const K1: u64 = 0xff51_afd7_ed55_8ccd;
    #[inline(always)]
    fn fold(a: u64, b: u64) -> u64 {
        let m = u128::from(a) * u128::from(b);
        (m as u64) ^ ((m >> 64) as u64)
    }
    let h = K0 ^ (n as u64).wrapping_mul(K1);
    fold(fold(h ^ bits as u64, K1) ^ (bits >> 64) as u64, K0)
}

/// `hash_bytes` of the string `s`; an inline string is hashed from its words as they are.
///
/// # Safety
/// `s` must be a live string.
#[inline(always)]
pub unsafe fn hash_str(s: *const StrVal) -> u64 {
    // SAFETY: caller contract.
    unsafe {
        if (*s).is_inline() {
            return hash_inline((*s).len(), (*s).inline_bits());
        }
        hash_bytes(bytes(s))
    }
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

/// Native allocation ceiling for built strings.
pub const MAX_BYTES: usize = 1 << 30;

/// A copy of `s` that the caller owns: a static or inline string is the same two words, an owned
/// one or a view is duplicated.
///
/// # Safety
/// `s` must be a live string.
#[inline(always)]
pub unsafe fn cloned(s: &StrVal) -> StrVal {
    if s.copies_bitwise() {
        return s.alias();
    }
    // SAFETY: `s` is live, so its bytes are readable.
    unsafe { owned_copy(bytes(s)) }
}

// The C runtime defines these; Rust callers (ffi, glue) reach them through the same symbols.

/// An owned copy of `data`: inline when it fits.
#[inline(never)]
fn owned_copy(data: &[u8]) -> StrVal {
    if data.len() <= STR_INLINE_MAX {
        return StrVal::inline(data);
    }
    heap_copy(data)
}

/// A heap copy of `data`, whatever its length.
fn heap_copy(data: &[u8]) -> StrVal {
    let s = alloc_str(data.len());
    // SAFETY: `s` has room for `len` bytes.
    unsafe { core::ptr::copy_nonoverlapping(data.as_ptr(), s.ptr_word, data.len()) };
    if data.is_ascii() { s.with_ascii() } else { s }
}

/// A string of exactly `len` bytes written by `fill`: inline when it fits, otherwise one
/// allocation with no intermediate buffer. `ascii` says that `fill` writes only ASCII bytes.
#[inline(always)]
fn build_exact(len: usize, ascii: bool, fill: impl FnOnce(&mut [u8])) -> StrVal {
    if len <= STR_INLINE_MAX {
        let mut small = [0u8; STR_INLINE_MAX + 1];
        fill(&mut small[..len]);
        return from_bytes(&small[..len]);
    }
    let r = alloc_str(len);
    // SAFETY: `r` owns `len` writable bytes.
    fill(unsafe { core::slice::from_raw_parts_mut(r.ptr_word, len) });
    if ascii { r.with_ascii() } else { r }
}

/// Whether every byte of `s` is ASCII, from its flag when it has one.
///
/// # Safety
/// `s` is live.
#[inline(always)]
unsafe fn is_ascii(s: &StrVal) -> bool {
    if s.is_inline() {
        return s.inline_bits() & 0x8080_8080_8080_8080_8080_8080_8080_8080 == 0;
    }
    // SAFETY: caller contract.
    s.flagged_ascii() || unsafe { bytes(s) }.is_ascii()
}

/// Frees the bytes of `s` when it is owned.
///
/// # Safety
/// `s` must be a live string that the caller owns and does not use afterwards.
#[inline(always)]
pub unsafe fn release(s: &StrVal) {
    if s.owns() {
        // SAFETY: an owned string is one allocation starting at `ptr`.
        unsafe { free_owned(s.ptr_word) }
    }
}

#[inline(never)]
unsafe fn free_owned(ptr: *mut u8) {
    // SAFETY: `ptr` came from `alloc_str`.
    unsafe { alloc::free(ptr) }
}

/// Allocates an uninitialised string of `len` bytes (NUL terminated).
pub fn alloc_str(len: usize) -> StrVal {
    if len > MAX_BYTES {
        fault::fault(b"string: limit exceeded");
    }
    let ptr = alloc::alloc(len + 1);
    // SAFETY: the allocation holds `len + 1` bytes.
    unsafe { *ptr.add(len) = 0 };
    StrVal::owned(ptr, len)
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
pub const NO_STR: StrVal = StrVal::literal(null_mut(), 0);

/// Releases `s` unless it is [`NO_STR`].
///
/// # Safety
/// `s` is `NO_STR` or a live string the caller owns a reference to.
pub unsafe fn release_opt(s: &StrVal) {
    if s.ptr_word.is_null() && s.is_static() {
        return;
    }
    {
        // SAFETY: a string other than `NO_STR` is live per the contract.
        unsafe { release(s) }
    }
}

/// The static empty string (a literal: no ownership to give back).
pub fn empty() -> StrVal {
    StrVal::literal(core::ptr::addr_of_mut!(EMPTY) as *mut u8, 0)
}

fn ascii_char(b: u8) -> StrVal {
    // SAFETY: as above.
    unsafe { StrVal::literal(core::ptr::addr_of_mut!(ASCII[b as usize]) as *mut u8, 1) }
}

/// New string from bytes (owned, rc 1). Short ASCII and empty results are the shared statics.
#[inline(always)]
pub fn from_bytes(data: &[u8]) -> StrVal {
    match data.len() {
        0 => return empty(),
        1 if data[0] < 0x80 => return ascii_char(data[0]),
        2..=STR_INLINE_MAX => return StrVal::inline(data),
        _ => {}
    }
    heap_copy(data)
}

/// A string for `len` bytes at `p` inside another live string: an inline copy when it fits,
/// otherwise a view. A short piece never points into its source, which may itself be inline.
///
/// # Safety
/// `p..p+len` is readable and stays unchanged while the result lives.
pub unsafe fn view_of(p: *const u8, len: usize) -> StrVal {
    if len <= STR_INLINE_MAX {
        // SAFETY: caller contract.
        return StrVal::inline(unsafe { core::slice::from_raw_parts(p, len) });
    }
    StrVal::view(p.cast_mut(), len)
}

/// Converts a finished buffer into a string.
pub fn from_buf(b: Vec<u8>) -> StrVal {
    from_bytes(b.as_slice())
}

// ---------------------------------------------------------------------------
// Scalar shape and indexing
// ---------------------------------------------------------------------------

/// Whether `s` is known to be ASCII without scanning heap bytes: flagged, or inline with clear
/// high bits (an inline string has no flag, but its bits are one register test).
///
/// # Safety
/// `s` must be live.
#[inline(always)]
unsafe fn known_ascii(s: *const StrVal) -> bool {
    // SAFETY: `s` live.
    unsafe { (*s).flagged_ascii() || ((*s).is_inline() && is_ascii(&*s)) }
}

/// Scalar count: the byte length for a string flagged ASCII (or inline ASCII), else counted on
/// each call. Strings built by copy, concatenation and append carry the flag.
///
/// # Safety
/// `s` must be live.
#[inline]
pub unsafe fn scalar_count(s: *const StrVal) -> usize {
    // SAFETY: `s` live.
    unsafe {
        if known_ascii(s) {
            return (*s).len();
        }
        utf8::count(bytes(s))
    }
}

#[unsafe(no_mangle)]
// ms: leaf domain=map
pub extern "C-unwind" fn msrt_hash_int(v: i64) -> i64 {
    mix(v as u64 ^ 0x9e37_79b9) as i64
}

#[unsafe(no_mangle)]
// ms: leaf domain=map
pub unsafe extern "C-unwind" fn msrt_hash_bytes(p: *const u8, len: usize) -> i64 {
    // SAFETY: caller passes a readable range.
    hash_bytes(unsafe { core::slice::from_raw_parts(p, len) }) as i64
}

/// `find` for a short haystack and a non-empty needle.
///
/// The scan is for one of the needle's less common bytes (see [`rare_offset`]), so a log line full
/// of spaces and slashes does not stop at each of them; only a position where that byte matches is compared
/// whole.
#[inline]
pub(super) fn find_short(hay: &[u8], needle: &[u8]) -> Option<usize> {
    let last = hay.len().checked_sub(needle.len())?;
    let k = rare_offset(needle)?;
    let pivot = needle[k];
    let mut i = 0;
    while i <= last {
        // `hay[i + k]` is the pivot byte of the candidate start `i`.
        i += memchr_short(pivot, &hay[i + k..=last + k])?;
        if hay[i..i + needle.len()] == *needle {
            return Some(i);
        }
        i += 1;
    }
    None
}

/// The offset of the byte to scan for: the last one that is not a space or common punctuation,
/// which text is full of (a needle written between spaces would otherwise stop at every word),
/// or the last byte when it is all of those. None for an empty needle.
#[inline]
fn rare_offset(needle: &[u8]) -> Option<usize> {
    needle
        .iter()
        .rposition(|b| !matches!(b, b' ' | b'/' | b'.' | b',' | b'-' | b':' | b'_'))
        .or(needle.len().checked_sub(1))
}

/// `memchr` for a short haystack: eight bytes per step, testing each word for a byte equal to
/// `c` with the zero-byte trick.
#[inline]
pub(super) fn memchr_short(c: u8, hay: &[u8]) -> Option<usize> {
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

/// `String.parse_int()`: present flag, value through `out`.
#[unsafe(no_mangle)]
// ms: leaf pure domain=string
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

/// `String.scalar_at(offset, default)`: an ASCII byte is its own scalar, one read; anything else
/// is decoded or rejected by [`msrt_string_scalar_at_slow`].
#[unsafe(no_mangle)]
// ms: leaf pure domain=string
pub unsafe extern "C-unwind" fn msrt_string_scalar_at(
    s: *const StrVal,
    offset: i64,
    has_default: HasRaw,
    default: i64,
) -> i64 {
    // SAFETY: caller passes a live string.
    unsafe {
        if let Some(&b) = usize::try_from(offset).ok().and_then(|i| bytes(s).get(i))
            && b < 0x80
        {
            return b as i64;
        }
        msrt_string_scalar_at_slow(s, offset, has_default, default)
    }
}

/// Whether byte offset `i` of `text` starts a scalar (or is the end).
#[inline(always)]
fn is_boundary(text: &[u8], i: usize) -> bool {
    i == text.len() || text[i] & 0xC0 != 0x80
}

/// `String.scalar_at(offset, default)`: the scalar that starts at byte `offset`. An offset outside
/// the text or inside a scalar gives `default`, or a fault without one.
pub unsafe fn msrt_string_scalar_at_slow(
    s: *const StrVal,
    offset: i64,
    has_default: HasRaw,
    default: i64,
) -> i64 {
    // SAFETY: caller passes a live string.
    unsafe {
        let text = bytes(s);
        match usize::try_from(offset) {
            Ok(i) if i < text.len() && is_boundary(text, i) => utf8::decode(&text[i..]).0 as i64,
            _ if has_default.is_set() => default,
            _ => fault::fault_fmt(format_args!(
                "String.scalar_at: offset {offset} does not start a scalar of the {} byte text; pass a default",
                text.len()
            )),
        }
    }
}

// ---------------------------------------------------------------------------
// Comparison, hashing
// ---------------------------------------------------------------------------

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
    if needle.len() == 1 && hay.len() < SHORT_HAY {
        return memchr_short(needle[0], hay);
    }
    if hay.len() < SHORT_HAY || (needle.len() > 1 && hay.len() < MEDIUM_HAY) {
        return find_short(hay, needle);
    }
    if needle.len() == 1 {
        return memchr(needle[0], hay);
    }
    // memmem falls back to Two-Way search when candidate filtering is ineffective.
    // Comparing every candidate slice is quadratic on repetitive near matches.
    memchr::memmem::find(hay, needle)
}

/// Haystacks shorter than this are scanned byte by byte: the vector searchers' setup costs more
/// than the scan.
const SHORT_HAY: usize = 32;

/// Haystacks shorter than this (a line of a log or a record) are also scanned directly for a
/// needle of two or more bytes: building a `memmem` searcher per call costs several times the
/// scan of so few bytes, and the work is bounded by the haystack length times the needle length.
const MEDIUM_HAY: usize = 128;

/// First index of `c` in `hay` (the `memchr` crate picks SSE2, AVX2 or NEON at run time).
#[inline]
fn memchr(c: u8, hay: &[u8]) -> Option<usize> {
    memchr::memchr(c, hay)
}

/// Last occurrence of `needle` in `hay` (empty matches at `hay.len()`).
pub fn rfind(hay: &[u8], needle: &[u8]) -> Option<usize> {
    if needle.is_empty() {
        return Some(hay.len());
    }
    if needle.len() > hay.len() {
        return None;
    }
    memchr::memmem::rfind(hay, needle)
}

/// The search behind `msrt_string_contains` for every case its fast path does not cover.
pub unsafe fn msrt_string_contains_long(a: *const StrVal, v: *const StrVal) -> u8 {
    // SAFETY: caller passes live strings.
    unsafe {
        let (hay, needle) = (bytes(a), bytes(v));
        // A character class test (`"#.SE".contains(c)`): a short haystack and one byte needs no
        // word tricks, just a short scan.
        if let ([b], true) = (needle, hay.len() <= 16) {
            return hay.contains(b) as u8;
        }
        find(hay, needle).is_some() as u8
    }
}

/// Int? result: present flag, value through `out`.
pub unsafe fn msrt_string_index_of_long(a: *const StrVal, v: *const StrVal, out: *mut i64) -> u8 {
    // SAFETY: caller passes live strings and a writable out.
    unsafe {
        let text = bytes(a);
        match find(text, bytes(v)) {
            None => 0,
            Some(i) => {
                *out = i as i64;
                1
            }
        }
    }
}

#[unsafe(no_mangle)]
// ms: leaf
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
                *out = i as i64;
                1
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Building
// ---------------------------------------------------------------------------

/// A growable byte buffer the text formatters append to, so building a long text is linear.
pub struct StrBuf(Vec<u8>);

/// Starts an empty string builder (finish it with [`msrt_strbuf_finish`]).
#[unsafe(no_mangle)]
// ms: leaf
pub extern "C-unwind" fn msrt_strbuf_new() -> *mut StrBuf {
    Box::into_raw(Box::new(StrBuf(Vec::new())))
}

/// Appends a string's bytes to the builder.
///
/// # Safety
/// `buf` must come from `msrt_strbuf_new` and `s` must be live.
#[unsafe(no_mangle)]
// ms: leaf
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
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_strbuf_finish(buf: *mut StrBuf, out: *mut StrVal) {
    // SAFETY: caller passes a writable `out` and live arguments.
    unsafe { (msrt_strbuf_finish_val(buf)).write_to(out) }
}

unsafe fn msrt_strbuf_finish_val(buf: *mut StrBuf) -> StrVal {
    // SAFETY: the builder was boxed by `msrt_strbuf_new` and is consumed once.
    let buf = unsafe { Box::from_raw(buf) };
    from_bytes(&buf.0)
}

/// The string over the first `len` bytes of the owned allocation at `ptr`: the same allocation
/// when it stays on the heap, an inline copy (freeing the buffer) when it fits inline.
///
/// # Safety
/// `ptr` is an owned string allocation of at least `len + 1` bytes.
unsafe fn finish_owned(ptr: *mut u8, len: usize, ascii: bool) -> StrVal {
    // SAFETY: caller contract.
    unsafe {
        if len <= STR_INLINE_MAX {
            let r = from_bytes(core::slice::from_raw_parts(ptr, len));
            free_owned(ptr);
            return r;
        }
        *ptr.add(len) = 0;
        let r = StrVal::owned(ptr, len);
        if ascii { r.with_ascii() } else { r }
    }
}

/// `upper` or `lower` of a string that dies at the call: ASCII text maps in place.
///
/// # Safety
/// `s` is an owned string the callee takes; `out` is writable.
unsafe fn map_case_take(s: *mut StrVal, upper: bool, out: *mut StrVal) {
    // SAFETY: caller contract.
    unsafe {
        if (*s).owns() && is_ascii(&*s) {
            let (ptr, len) = ((*s).ptr_word, (*s).len());
            let text = core::slice::from_raw_parts_mut(ptr, len);
            if upper {
                text.make_ascii_uppercase();
            } else {
                text.make_ascii_lowercase();
            }
            return StrVal::owned(ptr, len).with_ascii().write_to(out);
        }
        let r = map_case(s, upper);
        release(&*s);
        r.write_to(out)
    }
}

/// `upper` or `lower` of non-ASCII `text` written straight into a result of the same size, or
/// `None` when the text is short, has a final-sigma context (lowercasing needs the whole-string
/// rule) or maps to more bytes than it has: the caller then maps it through `str`.
///
/// # Safety
/// The result allocation is private to this call until it is returned.
unsafe fn map_case_in_place(text: &str, upper: bool) -> Option<StrVal> {
    let len = text.len();
    if len <= STR_INLINE_MAX || (!upper && text.contains('\u{3a3}')) {
        return None;
    }
    let r = alloc_str(len);
    // SAFETY: `r` owns `len + 1` writable bytes.
    let dst = unsafe { core::slice::from_raw_parts_mut(r.ptr_word, len) };
    let mut at = 0;
    let mut tmp = [0u8; 4];
    for c in text.chars() {
        if c.is_ascii() {
            if at == len {
                // SAFETY: `r` is owned and unused after this.
                unsafe { free_owned(r.ptr_word) };
                return None;
            }
            dst[at] = if upper {
                c.to_ascii_uppercase()
            } else {
                c.to_ascii_lowercase()
            } as u8;
            at += 1;
            continue;
        }
        let mut put = |m: char| -> bool {
            let n = m.encode_utf8(&mut tmp).len();
            if at + n > len {
                return false;
            }
            dst[at..at + n].copy_from_slice(&tmp[..n]);
            at += n;
            true
        };
        let fits = if upper {
            c.to_uppercase().all(&mut put)
        } else {
            c.to_lowercase().all(&mut put)
        };
        if !fits {
            // SAFETY: `r` is owned and unused after this.
            unsafe { free_owned(r.ptr_word) };
            return None;
        }
    }
    // SAFETY: `r` owns `len + 1` bytes and `at <= len` of them are written.
    Some(unsafe { finish_owned(r.ptr_word, at, false) })
}

/// The high bit of each byte of `x` (all below 0x80) that is a lowercase letter (`lower` true) or an
/// uppercase one: `x + (0x80 - lo)` sets a byte's high bit when it is at least `lo`, and
/// `x + (0x80 - hi - 1)` when it is above `hi`; no byte carries into the next.
#[inline(always)]
fn ascii_letters_of_case(x: u64, lower: bool) -> u64 {
    const LO: u64 = 0x0101_0101_0101_0101;
    const HI: u64 = 0x8080_8080_8080_8080;
    let (first, last) = if lower { (b'a', b'z') } else { (b'A', b'Z') };
    let at_least = x + LO * u64::from(0x80 - first);
    let above = x + LO * u64::from(0x80 - last - 1);
    at_least & !above & HI
}

/// The first eight bytes of `text`, or all of them zero padded when it is shorter.
#[inline(always)]
fn first_word(text: &[u8]) -> u64 {
    let mut word = [0u8; 8];
    let n = text.len().min(8);
    word[..n].copy_from_slice(&text[..n]);
    u64::from_le_bytes(word)
}

/// The last eight bytes of `text` (at least eight long).
#[inline(always)]
fn last_word(text: &[u8]) -> u64 {
    u64::from_le_bytes(text[text.len() - 8..].try_into().unwrap_or([0; 8]))
}

/// Whether ASCII `text` holds a lowercase letter (`lower` false: an uppercase one), eight bytes per
/// step, stopping at the first.
#[inline(always)]
fn has_ascii_letter_of_case(text: &[u8], lower: bool) -> bool {
    if text.len() < 8 {
        return ascii_letters_of_case(first_word(text), lower) != 0;
    }
    // Text that changes usually shows a letter in its first word; the last word overlaps the one
    // before it when the length is not a multiple of eight.
    let head = u64::from_le_bytes(text[..8].try_into().unwrap_or([0; 8]));
    if ascii_letters_of_case(head, lower) != 0 {
        return true;
    }
    let (chunks, _) = text.as_chunks::<8>();
    for w in &chunks[1..] {
        if ascii_letters_of_case(u64::from_le_bytes(*w), lower) != 0 {
            return true;
        }
    }
    ascii_letters_of_case(last_word(text), lower) != 0
}

/// Writes ASCII `text` to `dst` with its lowercase letters uppercased (`upper`) or its uppercase
/// letters lowercased, eight bytes per step in one pass: flipping bit 5 of a letter changes its case.
#[inline(always)]
fn map_ascii_case_into(dst: &mut [u8], text: &[u8], upper: bool) {
    let flip = |x: u64| x ^ (ascii_letters_of_case(x, upper) >> 2);
    if text.len() < 8 {
        let word = flip(first_word(text)).to_le_bytes();
        dst.copy_from_slice(&word[..text.len()]);
        return;
    }
    let (chunks, _) = text.as_chunks::<8>();
    let (out, _) = dst.as_chunks_mut::<8>();
    for (d, w) in out.iter_mut().zip(chunks) {
        *d = flip(u64::from_le_bytes(*w)).to_le_bytes();
    }
    // The last word overlaps the one before it when the length is not a multiple of eight.
    let n = dst.len();
    dst[n - 8..].copy_from_slice(&flip(last_word(text)).to_le_bytes());
}

/// `upper` or `lower` of the string `s`: ASCII text is copied once into its result and mapped
/// there; other text maps scalar by scalar.
///
/// # Safety
/// `s` is a live string.
unsafe fn map_case(s: *const StrVal, upper: bool) -> StrVal {
    // SAFETY: caller contract.
    unsafe {
        let text = bytes(s);
        if is_ascii(&*s) {
            if !has_ascii_letter_of_case(text, upper) {
                // Already in the requested case: share the unchanged input.
                return cloned(&*s);
            }
            return build_exact(text.len(), true, |dst| {
                map_ascii_case_into(dst, text, upper)
            });
        }
        let text = core::str::from_utf8(text).expect("String contains valid UTF-8");
        if let Some(r) = map_case_in_place(text, upper) {
            return r;
        }
        if upper {
            from_buf(text.to_uppercase().into_bytes())
        } else {
            // Whole-string mapping supplies Unicode's full Cased and Case_Ignorable tables
            // for the contextual final-sigma rule.
            from_buf(text.to_lowercase().into_bytes())
        }
    }
}

#[unsafe(no_mangle)]
// ms: leaf fresh takes_self
pub unsafe extern "C-unwind" fn msrt_string_upper(s: *const StrVal, out: *mut StrVal) {
    // SAFETY: caller passes a writable `out` and live arguments.
    unsafe { (msrt_string_upper_val(s)).write_to(out) }
}

#[inline(always)]
unsafe fn msrt_string_upper_val(s: *const StrVal) -> StrVal {
    // SAFETY: caller passes a live string.
    unsafe { map_case(s, true) }
}

#[unsafe(no_mangle)]
// ms: leaf fresh takes_self
pub unsafe extern "C-unwind" fn msrt_string_lower(s: *const StrVal, out: *mut StrVal) {
    // SAFETY: caller passes a writable `out` and live arguments.
    unsafe { (msrt_string_lower_val(s)).write_to(out) }
}

#[inline(always)]
unsafe fn msrt_string_lower_val(s: *const StrVal) -> StrVal {
    // SAFETY: caller passes a live string.
    unsafe { map_case(s, false) }
}

/// `upper` of a string that dies at the call (the optimizer rewrites a call whose receiver
/// drops right after it); same `out` as `msrt_string_upper`.
///
/// # Safety
/// `s` holds an owned string that the callee takes; `out` is writable.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_upper_take(s: *mut StrVal, out: *mut StrVal) {
    // SAFETY: caller contract.
    unsafe { map_case_take(s, true, out) }
}

/// `lower` of a string that dies at the call (the optimizer rewrites a call whose receiver
/// drops right after it); same `out` as `msrt_string_lower`.
///
/// # Safety
/// `s` holds an owned string that the callee takes; `out` is writable.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_lower_take(s: *mut StrVal, out: *mut StrVal) {
    // SAFETY: caller contract.
    unsafe { map_case_take(s, false, out) }
}

/// Copies `n` non-overlapping bytes; up to 16 bytes go through overlapping word moves instead of a call
/// into `memcpy`, which costs more than the copy for the short pieces words and fields split into.
///
/// # Safety
/// `src..src+n` is readable and `dst..dst+n` writable.
#[inline(always)]
unsafe fn copy_bytes(dst: *mut u8, src: *const u8, n: usize) {
    // SAFETY: caller contract; each branch reads and writes only inside the `n` bytes.
    unsafe {
        match n {
            0 => {}
            1..=3 => {
                let (a, b, c) = (*src, *src.add(n / 2), *src.add(n - 1));
                *dst = a;
                *dst.add(n / 2) = b;
                *dst.add(n - 1) = c;
            }
            4..=7 => {
                let a = src.cast::<u32>().read_unaligned();
                let b = src.add(n - 4).cast::<u32>().read_unaligned();
                dst.cast::<u32>().write_unaligned(a);
                dst.add(n - 4).cast::<u32>().write_unaligned(b);
            }
            8..=16 => {
                let a = src.cast::<u64>().read_unaligned();
                let b = src.add(n - 8).cast::<u64>().read_unaligned();
                dst.cast::<u64>().write_unaligned(a);
                dst.add(n - 8).cast::<u64>().write_unaligned(b);
            }
            _ => core::ptr::copy_nonoverlapping(src, dst, n),
        }
    }
}

/// The strings `items[..n]` joined by `sep` with one allocation (none when the result is short).
///
/// # Safety
/// `items` points at `n` live strings.
pub unsafe fn join_strings(items: *const StrVal, n: usize, sep: &[u8]) -> StrVal {
    // SAFETY: caller contract; the second loop writes exactly the `total` bytes counted by the first.
    unsafe {
        let total =
            (0..n).map(|i| (*items.add(i)).len()).sum::<usize>() + sep.len() * n.saturating_sub(1);
        let mut small = [0u8; STR_INLINE_MAX];
        let heap = (total > STR_INLINE_MAX).then(|| alloc_str(total));
        let start = heap.as_ref().map_or(small.as_mut_ptr(), |s| s.ptr_word);
        let mut dst = start;
        for i in 0..n {
            if i > 0 {
                copy_bytes(dst, sep.as_ptr(), sep.len());
                dst = dst.add(sep.len());
            }
            let b = bytes(items.add(i));
            copy_bytes(dst, b.as_ptr(), b.len());
            dst = dst.add(b.len());
        }
        match heap {
            Some(s) => s,
            None => from_bytes(&small[..total]),
        }
    }
}

// ---------------------------------------------------------------------------
// Slicing
// ---------------------------------------------------------------------------

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
// ms: leaf
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
                *q = StrVal::literal(base.add((b as usize) * ms_rt_abi::ASCII_CHAR_STRIDE), 1);
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

#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_lines(s: *const StrVal, out: *mut VecVal) {
    // SAFETY: caller passes a live string and a writable out.
    unsafe {
        let text = bytes(s);
        let mut v = EMPTY_VEC;
        let mut start = 0;
        while let Some(p) = find_newline(&text[start..]) {
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

/// The scalars of a set string: the ASCII ones as a bit mask, the rest by comparison.
struct ScalarSet<'a> {
    low: u64,
    high: u64,
    wide: &'a [u8],
}

impl<'a> ScalarSet<'a> {
    fn new(set: &'a [u8]) -> ScalarSet<'a> {
        let (mut low, mut high) = (0u64, 0u64);
        let mut wide_from = None;
        for (i, &b) in set.iter().enumerate() {
            if b < 64 {
                low |= 1 << b;
            } else if b < 0x80 {
                high |= 1 << (b - 64);
            } else if wide_from.is_none() {
                wide_from = Some(i);
            }
        }
        ScalarSet {
            low,
            high,
            wide: wide_from.map_or(&[], |i| &set[i..]),
        }
    }

    #[inline(always)]
    fn contains(&self, c: u32) -> bool {
        if c < 64 {
            return self.low >> c & 1 != 0;
        }
        if c < 0x80 {
            return self.high >> (c - 64) & 1 != 0;
        }
        let mut i = 0;
        while i < self.wide.len() {
            let (w, n) = utf8::decode(&self.wide[i..]);
            if w == c {
                return true;
            }
            i += n;
        }
        false
    }
}

/// `String.trim_chars` and its start and end forms: the text without the leading and trailing
/// scalars that occur in `set`. ASCII scalars are tested from a bit mask and only others decoded.
#[unsafe(no_mangle)]
// ms: leaf domain=string
pub unsafe extern "C-unwind" fn msrt_string_trim_chars(
    s: *const StrVal,
    set: *const StrVal,
    from_start: u8,
    from_end: u8,
    out: *mut StrVal,
) {
    // SAFETY: caller passes live strings and a writable `out`.
    unsafe {
        let text = bytes(s);
        let members = ScalarSet::new(bytes(set));
        let (mut a, mut b) = (0, text.len());
        if from_start != 0 {
            while a < b {
                let (c, w) = if text[a] < 0x80 {
                    (u32::from(text[a]), 1)
                } else {
                    utf8::decode(&text[a..b])
                };
                if !members.contains(c) {
                    break;
                }
                a += w;
            }
        }
        if from_end != 0 {
            while b > a {
                let (c, w) = if text[b - 1] < 0x80 {
                    (u32::from(text[b - 1]), 1)
                } else {
                    utf8::decode_last(&text[a..b])
                };
                if !members.contains(c) {
                    break;
                }
                b -= w;
            }
        }
        from_bytes(&text[a..b]).write_to(out)
    }
}

/// `String.index_any`: the byte offset of the first scalar of `s` that occurs in `set`.
/// A set of at most eight ASCII bytes is scanned eight bytes per step (a non-ASCII byte of the
/// text is never a member); any other set tests each scalar against a bit mask and decodes
/// only non-ASCII ones.
#[unsafe(no_mangle)]
// ms: leaf pure domain=string
pub unsafe extern "C-unwind" fn msrt_string_index_any(
    s: *const StrVal,
    set: *const StrVal,
    out: *mut i64,
) -> u8 {
    const LO: u64 = 0x0101_0101_0101_0101;
    const HI: u64 = 0x8080_8080_8080_8080;
    // SAFETY: caller passes live strings and a writable `out`.
    unsafe {
        let (text, members) = (bytes(s), bytes(set));
        let found = if members.len() <= 8 && members.is_ascii() {
            let mut pats = [0u64; 8];
            for (p, &b) in pats.iter_mut().zip(members) {
                *p = LO * u64::from(b);
            }
            let pats = &pats[..members.len()];
            let (chunks, rest) = text.as_chunks::<8>();
            let mut at = None;
            for (k, w) in chunks.iter().enumerate() {
                let x = u64::from_le_bytes(*w);
                let hit = pats.iter().fold(0, |hit, &p| {
                    let y = x ^ p;
                    hit | (y.wrapping_sub(LO) & !y & HI)
                });
                if hit != 0 {
                    // A lane above a true match can be flagged falsely, never below it.
                    at = Some(k * 8 + hit.trailing_zeros() as usize / 8);
                    break;
                }
            }
            at.or_else(|| {
                let done = chunks.len() * 8;
                rest.iter()
                    .position(|b| members.contains(b))
                    .map(|i| done + i)
            })
        } else {
            let set = ScalarSet::new(members);
            let mut i = 0;
            let mut at = None;
            while i < text.len() {
                let (c, w) = if text[i] < 0x80 {
                    (u32::from(text[i]), 1)
                } else {
                    utf8::decode(&text[i..])
                };
                if set.contains(c) {
                    at = Some(i);
                    break;
                }
                i += w;
            }
            at
        };
        match found {
            Some(i) => {
                *out = i as i64;
                1
            }
            None => 0,
        }
    }
}

/// How `fields` treats a byte: 0 an ordinary ASCII byte, 1 ASCII White_Space, 2 the start of a
/// multibyte scalar, which is decoded.
const FIELD_CLASS: [u8; 256] = {
    let mut table = [0u8; 256];
    let mut i = 0;
    while i < 256 {
        table[i] = if i >= 0x80 {
            2
        } else if i == 32 || (i >= 9 && i <= 13) {
            1
        } else {
            0
        };
        i += 1;
    }
    table
};

/// `String.fields`: the runs of text between Unicode White_Space, none empty. A byte below 0x80
/// is tested directly and only other scalars are decoded, so ordinary text is one byte loop.
#[unsafe(no_mangle)]
// ms: leaf domain=string
pub unsafe extern "C-unwind" fn msrt_string_fields(s: *const StrVal, out: *mut VecVal) {
    // SAFETY: caller passes a live string and a writable out.
    unsafe {
        let text = bytes(s);
        let mut v = EMPTY_VEC;
        let mut field_start = usize::MAX;
        let mut i = 0;
        while i < text.len() {
            let (space, width) = match FIELD_CLASS[text[i] as usize] {
                0 => (false, 1),
                1 => (true, 1),
                _ => {
                    let (c, w) = utf8::decode(&text[i..]);
                    (utf8::is_space(c), w)
                }
            };
            if space {
                if field_start != usize::MAX {
                    push_str(&mut v, from_bytes(&text[field_start..i]));
                    field_start = usize::MAX;
                }
            } else if field_start == usize::MAX {
                field_start = i;
            }
            i += width;
        }
        if field_start != usize::MAX {
            push_str(&mut v, from_bytes(&text[field_start..]));
        }
        *out = v;
    }
}

/// Keep nearby line endings cheap, then scan long lines with the vector byte searcher.
/// A scalar prefix also avoids vector-search setup for ordinary short lines in a long text.
#[inline]
fn find_newline(text: &[u8]) -> Option<usize> {
    if text.len() <= SHORT_HAY {
        return text.iter().position(|&c| c == b'\n');
    }
    if let Some(at) = text[..SHORT_HAY].iter().position(|&c| c == b'\n') {
        return Some(at);
    }
    memchr(b'\n', &text[SHORT_HAY..]).map(|at| at + SHORT_HAY)
}

/// Room for the pieces of a split that is read in place: the list borrows it.
const SPLIT_BUF: usize = 8;
const _: () = assert!(size_of::<FrameBuf<StrVal, 8>>() == SPLIT_BUF * size_of::<StrVal>());

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

/// Starts a split loop.
#[unsafe(no_mangle)]
// ms: leaf iter_of=msrt_string_split
pub unsafe extern "C-unwind" fn msrt_string_split_iter(
    s: *const StrVal,
    sep: *const StrVal,
) -> *mut SplitIter {
    // SAFETY: caller passes live strings.
    unsafe {
        let it = obj::new_obj(core::mem::size_of::<SplitIter>(), None, split_iter_drop)
            as *mut SplitIter;
        // The loop keeps both strings alive until it ends, so the iterator only borrows them.
        (*it).src = (*s).alias();
        (*it).sep = (*sep).alias();
        (*it).cur = NO_STR;
        (*it).cap = 0;
        (*it).pos = 0;
        (*it).done = false;
        it
    }
}

/// Makes the next piece current and writes a borrow of it to `out` (the iterator owns the bytes
/// until the next call); returns 0 when the pieces are used up.
#[unsafe(no_mangle)]
// ms: leaf domain=split
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
        if st.done {
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
        if st.cap >= piece.len() && !st.cur.ptr_word.is_null() && st.cur.owns() {
            // The loop only borrows the piece: rewrite it in place.
            st.cur.tagged = piece.len();
            copy_short(piece.as_ptr(), st.cur.ptr_word, piece.len());
            *st.cur.ptr_word.add(piece.len()) = 0;
            return;
        }
        release_opt(&st.cur);
        let cap = piece.len().max(24);
        let mut fresh = alloc_str(cap);
        fresh.tagged = piece.len();
        copy_short(piece.as_ptr(), fresh.ptr_word, piece.len());
        *fresh.ptr_word.add(piece.len()) = 0;
        st.cur = fresh;
        st.cap = cap;
    }
}

#[unsafe(no_mangle)]
// ms: leaf
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
        if n == text.len() {
            for (k, &c) in text.iter().enumerate() {
                *p.add(k) = c as i64;
            }
            *out = VecVal {
                ptr: p as *mut u8,
                len: n,
                cap: n,
            };
            return;
        }
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
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_from_scalars(
    values: *const VecVal,
    out: *mut StrVal,
) -> u8 {
    // SAFETY: caller passes a live list of Int and a writable out.
    unsafe {
        let v = &*values;
        let src = if v.len == 0 {
            &[][..]
        } else {
            core::slice::from_raw_parts(v.ptr as *const i64, v.len)
        };
        // All-ASCII is the common case: one OR-reduction proves it (a negative or large value sets a
        // bit above 0x7F as an unsigned word), and the bytes are then narrowed straight into the result.
        let ascii = src.iter().fold(0u64, |acc, &n| acc | n as u64) < 0x80;
        if ascii {
            if src.len() <= STR_INLINE_MAX {
                let mut small = [0u8; STR_INLINE_MAX];
                for (d, &n) in small.iter_mut().zip(src) {
                    *d = n as u8;
                }
                *out = from_bytes(&small[..src.len()]);
                return STATUS_OK;
            }
            let s = alloc_str(src.len());
            let dst = core::slice::from_raw_parts_mut(s.ptr_word, src.len());
            for (d, &n) in dst.iter_mut().zip(src) {
                *d = n as u8;
            }
            *out = s.with_ascii();
            return STATUS_OK;
        }
        let mut b = Vec::with_capacity(src.len());
        let mut tmp = [0u8; 4];
        for &n in src {
            if !(0..=0x10FFFF).contains(&n) || (0xD800..=0xDFFF).contains(&n) {
                return STATUS_INVALID_INPUT;
            }
            if n < 0x80 {
                b.push(n as u8);
                continue;
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
// ms: leaf
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

/// `String.view_bytes()`: the UTF-8 bytes of the text borrowed from the receiver, nothing copied
/// (`cap == 0` marks a view, which is never freed). Valid while the receiver is neither changed nor
/// dropped (the borrow check guarantees that). The bytes of an inline text are the receiver's own
/// storage, which is why the function is declared `borrows`: the backends keep the argument's slot
/// for the whole function.
#[unsafe(no_mangle)]
// ms: leaf pure borrows domain=string
pub unsafe extern "C-unwind" fn msrt_string_view_bytes(s: *const StrVal, out: *mut VecVal) {
    // SAFETY: caller passes a live string and a writable out.
    unsafe {
        let text = bytes(s);
        *out = VecVal {
            ptr: if text.is_empty() {
                null_mut()
            } else {
                text.as_ptr() as *mut u8
            },
            len: text.len(),
            cap: 0,
        };
    }
}

/// `String.parse_float()`: present flag, value through `out`; the `Result` form is `math.parse_float`.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_parse_float(s: *const StrVal, out: *mut f64) -> u8 {
    // SAFETY: caller passes a live string and a writable out.
    unsafe { u8::from(crate::num::msrt_numbers_parse_float(s, out) == STATUS_OK) }
}

/// Normalization forms by the spelling `String.normalize` takes.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_normalize(
    s: *const StrVal,
    form: *const StrVal,
    has_max: HasRaw,
    max: i64,
    out: *mut StrVal,
) -> u8 {
    // SAFETY: caller passes live strings and a writable out.
    unsafe {
        if has_max.is_set() && max < 0 {
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
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_normalize_kind(
    s: *const StrVal,
    kind: i64,
    has_max: HasRaw,
    max: i64,
    out: *mut StrVal,
) -> u8 {
    // SAFETY: forwarded contract.
    unsafe { normalize_kind(s, kind, has_max, max, out) }
}

unsafe fn normalize_kind(
    s: *const StrVal,
    kind: i64,
    has_max: HasRaw,
    max: i64,
    out: *mut StrVal,
) -> u8 {
    use unicode_normalization::UnicodeNormalization;
    if has_max.is_set() && max < 0 {
        return STATUS_INVALID_INPUT;
    }
    // SAFETY: caller passes a live string and a writable out.
    unsafe {
        let limit = if has_max.is_set() {
            max as usize
        } else {
            usize::MAX
        };
        let text = bytes(s);
        if is_ascii(&*s) {
            // ASCII text is already in every normalization form.
            if text.len() > limit {
                return STATUS_LIMIT_EXCEEDED;
            }
            *out = cloned(&*s);
            return STATUS_OK;
        }
        // ASCII is stable under every form and never composes with what precedes it, so
        // a normalization segment starts at the last ASCII byte before a non-ASCII run
        // (a base letter may take a following mark) and ends at the next ASCII byte.
        // Everything between segments is copied as it is.
        let mut b: Vec<u8> = Vec::with_capacity(text.len());
        let mut chars: Vec<char> = Vec::new();
        let mut tmp = [0u8; 4];
        let mut at = 0;
        while at < text.len() {
            let run_end = at
                + text[at..]
                    .iter()
                    .position(|&x| x >= 0x80)
                    .unwrap_or(text.len() - at);
            if run_end == text.len() {
                if text.len() - at > limit.saturating_sub(b.len()) {
                    return STATUS_LIMIT_EXCEEDED;
                }
                b.extend_from_slice(&text[at..]);
                break;
            }
            let start = if run_end > at { run_end - 1 } else { run_end };
            if start - at > limit.saturating_sub(b.len()) {
                return STATUS_LIMIT_EXCEEDED;
            }
            b.extend_from_slice(&text[at..start]);
            let end = run_end
                + text[run_end..]
                    .iter()
                    .position(|&x| x < 0x80)
                    .unwrap_or(text.len() - run_end);
            chars.clear();
            let mut i = start;
            while i < end {
                let (c, w) = utf8::decode(&text[i..end]);
                chars.push(char::from_u32(c).unwrap_or('\u{FFFD}'));
                i += w;
            }
            let mut push = |c: char| -> bool {
                let e = c.encode_utf8(&mut tmp).as_bytes();
                if e.len() > limit.saturating_sub(b.len()) {
                    return false;
                }
                b.extend_from_slice(e);
                true
            };
            let it = chars.iter().copied();
            let ok = match kind {
                0 => it.nfc().all(&mut push),
                1 => it.nfd().all(&mut push),
                2 => it.nfkc().all(&mut push),
                _ => it.nfkd().all(&mut push),
            };
            if !ok {
                return STATUS_LIMIT_EXCEEDED;
            }
            at = end;
        }
        *out = from_buf(b);
        STATUS_OK
    }
}

// ---------------------------------------------------------------------------
// Conversions to string (Int, Float, Bool)
// ---------------------------------------------------------------------------

/// The double-quoted, escaped spelling of a string (as `%q` writes it).
#[unsafe(no_mangle)]
// ms: leaf
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

crate::isolate_static! {
/// Deep copies the runtime performed, `[list copies, list bytes, string clones, string bytes]` (counted by every runtime).
    pub static COPY_COUNTS: [u64; 4] = [0; 4];
}
/// Records one deep copy of `kind` (0 list, 1 string) moving `bytes` bytes.
pub fn count_copy(kind: usize, bytes: usize) {
    // SAFETY: single threaded access to the counters.
    unsafe {
        let c = &mut *COPY_COUNTS.ptr();
        c[kind * 2] += 1;
        c[kind * 2 + 1] += bytes as u64;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // The f-string joins are C (runtime/core/string_join.c); the unit tests link the C runtime.
    unsafe extern "C-unwind" {
        fn msrt_string_fmt2(mask: i64, a: usize, b: usize, out: *mut StrVal);
        fn msrt_string_fmt3(mask: i64, a: usize, b: usize, c: usize, out: *mut StrVal);
        fn msrt_string_append_fmt1(s: *const StrVal, mask: i64, a: usize, out: *mut StrVal);
        fn msrt_string_append_fmt2(
            s: *const StrVal,
            mask: i64,
            a: usize,
            b: usize,
            out: *mut StrVal,
        );
        fn msrt_string_append_fmt3(
            s: *const StrVal,
            mask: i64,
            a: usize,
            b: usize,
            c: usize,
            out: *mut StrVal,
        );
    }

    #[test]
    fn find_short_agrees_with_a_naive_search() {
        let naive = |hay: &[u8], needle: &[u8]| {
            (needle.len() <= hay.len())
                .then(|| {
                    (0..=hay.len() - needle.len()).find(|&i| hay[i..i + needle.len()] == *needle)
                })
                .flatten()
        };
        let alphabet = *b" /.a7P-";
        // Every text up to five bytes and a set of needles over a small alphabet, plus longer
        // texts built from a seed, so each pivot choice meets matches at every offset.
        let mut texts: Vec<Vec<u8>> = vec![vec![]];
        for len in 1..=5 {
            let mut next = Vec::new();
            for t in texts.iter().filter(|t| t.len() == len - 1) {
                for &c in &alphabet {
                    let mut u = t.clone();
                    u.push(c);
                    next.push(u);
                }
            }
            texts.extend(next);
        }
        let mut seed = 7u32;
        for _ in 0..2000 {
            let len = 20 + (seed % 90) as usize;
            let mut t = Vec::new();
            for _ in 0..len {
                seed = seed.wrapping_mul(1103515245).wrapping_add(12345);
                t.push(alphabet[(seed >> 16) as usize % alphabet.len()]);
            }
            texts.push(t);
        }
        let needles: Vec<&[u8]> = vec![
            b" ", b"a", b"7", b"  ", b" a", b"a ", b" 7 ", b"/.", b"./a7", b" P-a", b"aaaa",
            b" /.- ", b"7P-a7 /",
        ];
        for t in &texts {
            for n in &needles {
                assert_eq!(find_short(t, n), naive(t, n), "{t:?} {n:?}");
            }
        }
    }

    #[test]
    fn from_scalars_covers_ascii_unicode_and_invalid_input() {
        let build = |values: &[i64]| {
            let list = VecVal {
                ptr: values.as_ptr() as *mut u8,
                len: values.len(),
                cap: values.len(),
            };
            let mut out = core::mem::MaybeUninit::<StrVal>::uninit();
            // SAFETY: `list` is a live list of Int and `out` is writable.
            let status = unsafe { msrt_string_from_scalars(&list, out.as_mut_ptr()) };
            // SAFETY: a successful call wrote `out`.
            (
                status,
                (status == STATUS_OK).then(|| unsafe { bytes(&out.assume_init()).to_vec() }),
            )
        };
        let long: Vec<i64> = (0..40).map(|i| 65 + i % 26).collect();
        for values in [&[][..], &[104, 105], &long[..]] {
            let want: Vec<u8> = values.iter().map(|&n| n as u8).collect();
            assert_eq!(build(values), (STATUS_OK, Some(want)));
        }
        let mixed = [
            72, 0xE9, 0x20AC, 0x1F600, 33, 33, 33, 33, 33, 33, 33, 33, 33, 33,
        ];
        let want: String = mixed
            .iter()
            .map(|&n| char::from_u32(n as u32).unwrap())
            .collect();
        assert_eq!(build(&mixed), (STATUS_OK, Some(want.into_bytes())));
        for bad in [-1, 0xD800, 0x110000, i64::MIN, i64::MAX] {
            assert_eq!(build(&[65, bad]).0, STATUS_INVALID_INPUT, "{bad}");
        }
    }

    #[test]
    fn slicing_inline_ascii_and_non_ascii_by_bytes() {
        let _g = crate::testutil::lock();
        // SAFETY: the strings are live for the whole test.
        unsafe {
            for (text, a, b, want) in [
                ("Rent,133.47", 5, 11, "133.47"),
                ("Rent,133.47", 0, 11, "Rent,133.47"),
                ("Rent,133.47", 5, 12, "133.47"),
                ("café,1", 3, 5, "é"),
                ("café,1", 5, 7, ",1"),
                ("café,1", 4, 5, ""),
            ] {
                let s = from_bytes(text.as_bytes());
                let mut out = empty();
                msrt_string_slice(&s, a, b, &mut out);
                assert_eq!(bytes(&out), want.as_bytes(), "{text:?}[{a}..{b}]");
            }
        }
    }

    #[test]
    fn contains_a_byte_in_a_short_string() {
        let _g = crate::testutil::lock();
        // SAFETY: the strings are live for the whole test.
        unsafe {
            for (hay, needle, want) in [
                ("#.SE", "S", 1),
                ("#.SE", "x", 0),
                ("", "x", 0),
                ("abcdefghijklmnop", "p", 1),
                ("abcdefghijklmnopq", "q", 1),
                ("é", "\u{a9}", 0),
            ] {
                let (h, n) = (from_bytes(hay.as_bytes()), from_bytes(needle.as_bytes()));
                assert_eq!(
                    msrt_string_contains_long(&h, &n),
                    want,
                    "{hay:?} contains {needle:?}"
                );
            }
        }
    }

    #[test]
    fn concat_parts_joins_and_skips_empties() {
        let _g = crate::testutil::lock();
        // SAFETY: the strings are live for the whole test.
        unsafe {
            let a = from_bytes(b"ab");
            let e = empty();
            let c = from_bytes("cé".as_bytes());
            let d = from_bytes(b"xyz");
            let mut j = empty();
            msrt_string_concat4(&a, &e, &c, &d, &mut j);
            assert_eq!(bytes(&j), "abcéxyz".as_bytes());
            let mut one = empty();
            msrt_string_concat3(&e, &d, &e, &mut one);
            assert_eq!(bytes(&one), b"xyz");
            let mut none = d.alias();
            msrt_string_concat3(&e, &e, &e, &mut none);
            assert_eq!(none.len(), 0);
        }
    }

    #[test]
    fn newline_search_matches_scalar_search_across_the_prefix_boundary() {
        for len in 0..=129 {
            let mut text = vec![b'x'; len];
            assert_eq!(find_newline(&text), None);
            for at in 0..len {
                text[at] = b'\n';
                assert_eq!(
                    find_newline(&text),
                    text.iter().position(|&c| c == b'\n'),
                    "length {len}, newline {at}"
                );
                text[at] = b'x';
            }
        }
    }

    #[test]
    fn append_parts_grows_an_owned_string_and_joins_onto_any_other() {
        let _g = crate::testutil::lock();
        let part = |s: &StrVal| s as *const StrVal as usize;
        // SAFETY: every string is live until it is given up or released.
        unsafe {
            let eq = from_bytes(b"=");
            // An owned string grows where it is once its block has room.
            let mut s = from_bytes(b"a long enough string to be owned");
            assert!(s.owns() && s.flagged_ascii());
            let mut last = core::ptr::null_mut();
            for n in 0..200i64 {
                let old = core::ptr::read(&s);
                msrt_string_append_fmt3(&old, 0b0100, part(&eq), n as usize, part(&eq), &mut s);
                assert!(s.owns() && s.flagged_ascii());
                last = s.ptr_word;
            }
            assert!(bytes(&s).ends_with(b"=198==199="));
            assert_eq!(s.len(), 32 + 2 * 200 + 10 + 180 + 300);
            let old = core::ptr::read(&s);
            msrt_string_append_fmt1(&old, 0b10, -5i64 as usize, &mut s);
            assert_eq!(s.ptr_word, last, "one more short part fits the slack");
            // A part that views the string's own bytes is read before they move.
            let tail = StrVal::view(s.ptr_word.add(s.len() - 2), 2);
            let old = core::ptr::read(&s);
            msrt_string_append_fmt2(&old, 0, part(&tail), part(&tail), &mut s);
            assert!(bytes(&s).ends_with(b"=-5-5-5"));
            // A part that is not ASCII clears the flag.
            let wide = from_bytes("é".as_bytes());
            let old = core::ptr::read(&s);
            msrt_string_append_fmt1(&old, 0, part(&wide), &mut s);
            assert!(!s.flagged_ascii());
            release(&s);
            // An inline or empty string has nothing to grow: the result is a fresh join.
            let short = from_bytes(b"ab");
            let mut r = empty();
            msrt_string_append_fmt2(&short, 0b100, part(&eq), 7usize, &mut r);
            assert_eq!(bytes(&r), b"ab=7");
            assert!(r.is_inline());
            let none = empty();
            let long = from_bytes(b"abcdefghijklmnop");
            let mut r = empty();
            msrt_string_append_fmt2(&none, 0b100, part(&long), 12usize, &mut r);
            assert_eq!(bytes(&r), b"abcdefghijklmnop12");
            release(&r);
            release(&long);
        }
    }

    #[test]
    fn format_parts_writes_integers_in_place_of_strings() {
        let _g = crate::testutil::lock();
        // SAFETY: the strings are live for the whole test.
        unsafe {
            let w = from_bytes(b"w");
            let eq = from_bytes(b"=");
            let mut s = empty();
            msrt_string_fmt2(0b10, &w as *const StrVal as usize, 1234usize, &mut s);
            assert_eq!(bytes(&s), b"w1234");
            assert!(s.is_inline());
            let mut neg = empty();
            msrt_string_fmt3(
                0b101,
                (-7i64) as usize,
                &eq as *const StrVal as usize,
                i64::MIN as usize,
                &mut neg,
            );
            assert_eq!(bytes(&neg), b"-7=-9223372036854775808");
            assert!(neg.owns());
            let long = from_bytes(b"abcdefghijklmn");
            let mut edge = empty();
            msrt_string_fmt2(0b10, &long as *const StrVal as usize, 5usize, &mut edge);
            assert_eq!(bytes(&edge), b"abcdefghijklmn5");
            assert!(edge.is_inline());
            let mut over = empty();
            msrt_string_fmt2(0b10, &long as *const StrVal as usize, 56usize, &mut over);
            assert_eq!(bytes(&over), b"abcdefghijklmn56");
            assert!(over.owns());
            let mut ints = empty();
            msrt_string_fmt2(0b11, 0usize, 10usize, &mut ints);
            assert_eq!(bytes(&ints), b"010");
            release(&neg);
            release(&over);
        }
    }

    #[test]
    fn split_view_pieces_borrow_the_source() {
        let _g = crate::testutil::lock();
        unsafe {
            let s = from_bytes(b"alpha-is-a-long-piece,b,,gamma\xc3\xa9");
            let sep = from_bytes(b",");
            let mut views = EMPTY_VEC;
            msrt_string_split_view(&s, &sep, &mut views);
            let mut copies = EMPTY_VEC;
            msrt_string_split(&s, &sep, &mut copies);
            assert_eq!(views.len, 4);
            for i in 0..views.len {
                let (v, c) = (
                    &*(views.ptr as *const StrVal).add(i),
                    &*(copies.ptr as *const StrVal).add(i),
                );
                assert_eq!(bytes(v), bytes(c));
                assert!(!v.owns(), "piece {i} is not owned");
                // Long pieces point into the source; short ones are inline or shared statics.
                let p = v.data();
                if v.len() > STR_INLINE_MAX {
                    assert!(v.is_view() && p >= s.data() && p < s.data().add(s.len()));
                } else if v.len() > 1 {
                    assert!(v.is_inline(), "piece {i} is inline");
                }
            }
            crate::vec::drop_list(&mut views, &crate::desc::msrt_desc_string);
            crate::vec::drop_list(&mut copies, &crate::desc::msrt_desc_string);
            release(&s);
        }
    }

    #[test]
    fn copy_bytes_copies_exactly_the_requested_bytes() {
        for n in 0..40usize {
            let src: Vec<u8> = (0..n as u8).map(|i| i + 1).collect();
            let mut dst = vec![0xAAu8; n + 8];
            // SAFETY: both buffers hold at least `n` bytes.
            unsafe { copy_bytes(dst.as_mut_ptr().add(4), src.as_ptr(), n) };
            assert_eq!(&dst[4..4 + n], &src[..], "copied {n}");
            assert!(
                dst[..4].iter().chain(&dst[4 + n..]).all(|&b| b == 0xAA),
                "overran at {n}"
            );
        }
    }

    #[test]
    fn join_strings_matches_a_plain_join() {
        let _g = crate::testutil::lock();
        for count in 0..5usize {
            for len in [0usize, 1, 5, 7, 8, 15, 16, 17, 40] {
                for sep in ["", ",", ", ", "-----------------"] {
                    let parts: Vec<StrVal> = (0..count)
                        .map(|i| from_bytes(&vec![b'a' + i as u8; len]))
                        .collect();
                    let want = (0..count)
                        .map(|i| String::from_utf8(vec![b'a' + i as u8; len]).unwrap())
                        .collect::<Vec<_>>()
                        .join(sep);
                    // SAFETY: `parts` holds `count` live strings.
                    let got = unsafe { join_strings(parts.as_ptr(), count, sep.as_bytes()) };
                    assert_eq!(
                        unsafe { bytes(&got) },
                        want.as_bytes(),
                        "{count}x{len} by {sep:?}"
                    );
                }
            }
        }
    }

    /// Every `_take` twin gives exactly what the copying call gives, for inline, heap, non-ASCII
    /// and static inputs, and results that cross the inline size either way.
    #[test]
    fn take_twins_match_the_copying_calls() {
        let _g = crate::testutil::lock();
        let texts = [
            "",
            " ",
            "  a  ",
            "short text",
            "   a heap string with spaces around it   ",
            "   héllo wörld, non ascii heap string   ",
            "ABC def GHI jkl MNO pqr STU vwx",
            "aaaa bbbb aaaa bbbb aaaa bbbb aaaa",
        ];
        let pairs = [
            ("aaaa", "cc"),
            ("bbbb", ""),
            ("a", "a"),
            ("x", "yy"),
            ("", "-"),
            (" ", ""),
        ];
        unsafe {
            for text in texts {
                let new = || from_bytes(text.as_bytes());
                let mut out = from_bytes(b"");
                let mut want = from_bytes(b"");
                for (take, copy) in [
                    (
                        msrt_string_trim_take as unsafe extern "C-unwind" fn(_, _),
                        msrt_string_trim as unsafe extern "C-unwind" fn(_, _),
                    ),
                    (msrt_string_trim_start_take, msrt_string_trim_start),
                    (msrt_string_trim_end_take, msrt_string_trim_end),
                    (msrt_string_upper_take, msrt_string_upper),
                    (msrt_string_lower_take, msrt_string_lower),
                ] {
                    let mut s = new();
                    let src = new();
                    take(&mut s, &mut out);
                    copy(&src, &mut want);
                    assert_eq!(bytes(&out), bytes(&want), "{text:?}");
                    assert_eq!(out.is_inline(), want.is_inline(), "{text:?}");
                    release(&out);
                    release(&want);
                    release(&src);
                }
                for (o, n) in pairs {
                    let (old, rep) = (from_bytes(o.as_bytes()), from_bytes(n.as_bytes()));
                    let mut s = new();
                    let src = new();
                    msrt_string_replace_take(&mut s, &old, &rep, &mut out);
                    msrt_string_replace(&src, &old, &rep, &mut want);
                    assert_eq!(bytes(&out), bytes(&want), "{text:?} {o:?}->{n:?}");
                    assert_eq!(out.is_inline(), want.is_inline(), "{text:?} {o:?}->{n:?}");
                    release(&out);
                    release(&want);
                    release(&src);
                }
            }
        }
    }

    #[test]
    fn bytes_eq_matches_slice_equality() {
        let _g = crate::testutil::lock();
        unsafe {
            for len in 0..40usize {
                let base: Vec<u8> = (0..len).map(|i| b'a' + (i % 7) as u8).collect();
                let a = from_bytes(&base);
                assert!(equal(&a, &from_bytes(&base)), "equal at len {len}");
                for at in 0..len {
                    let mut other = base.clone();
                    other[at] ^= 1;
                    assert!(!equal(&a, &from_bytes(&other)), "byte {at} of {len}");
                }
                let mut longer = base.clone();
                longer.push(b'z');
                assert!(!equal(&a, &from_bytes(&longer)));
            }
        }
    }

    #[test]
    fn hash_vectors_match_the_c_runtime() {
        // The same vectors are asserted by runtime/tests/core_string.c.
        let vectors: [(&str, i64); 6] = [
            ("", 5637604647281345049),
            ("a", -4589632175014895841),
            ("hello", -2768413155067229152),
            ("123456789012345", 1963792452095667305),
            ("1234567890123456", 6017223085291776624),
            (
                "The quick brown fox jumps over the lazy dog",
                5716930301217669884,
            ),
        ];
        for (text, hash) in vectors {
            assert_eq!(hash_bytes(text.as_bytes()) as i64, hash, "{text:?}");
        }
    }

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
    #[cfg_attr(
        miri,
        ignore = "an exhaustive sweep that takes over 200 s interpreted; native CI runs it"
    )]
    fn find_matches_naive_search() {
        let mut seed = 0x2545_f491_4f6c_dd1du64;
        let mut next = || {
            seed ^= seed << 13;
            seed ^= seed >> 7;
            seed ^= seed << 17;
            seed
        };
        for _ in 0..4000 {
            let hay_len = (next() % 300) as usize;
            let needle_len = (next() % if next() % 2 == 0 { 6 } else { 40 }) as usize;
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
    #[test]
    #[cfg_attr(
        miri,
        ignore = "an exhaustive sweep that takes over 200 s interpreted; native CI runs it"
    )]
    fn substring_search_matches_exhaustive_byte_model() {
        // Include NUL and invalid UTF-8; these helpers also implement Bytes search.
        fn words(max_len: usize) -> Vec<Vec<u8>> {
            let mut words = vec![vec![]];
            let mut level = vec![vec![]];
            for _ in 0..max_len {
                level = level
                    .iter()
                    .flat_map(|word| {
                        [0, b'a', 0xff].map(|byte| {
                            let mut next = word.clone();
                            next.push(byte);
                            next
                        })
                    })
                    .collect();
                words.extend(level.iter().cloned());
            }
            words
        }
        for hay in words(5) {
            for needle in words(4) {
                // Subslice searches exercise the offset handling used by split/replace.
                for start in 0..=hay.len() {
                    let text = &hay[start..];
                    let (first, last) = if needle.is_empty() {
                        (Some(0), Some(text.len()))
                    } else {
                        (
                            text.windows(needle.len()).position(|w| w == needle),
                            text.windows(needle.len()).rposition(|w| w == needle),
                        )
                    };
                    assert_eq!(find(text, &needle), first, "{text:?} {needle:?}");
                    assert_eq!(rfind(text, &needle), last, "{text:?} {needle:?}");
                }
            }
        }
    }

    #[test]
    #[cfg_attr(
        miri,
        ignore = "an exhaustive sweep that takes over 200 s interpreted; native CI runs it"
    )]
    fn substring_search_repetitive_near_matches() {
        for n in [4096, 65_536, 262_144] {
            let mut hay = vec![b'a'; n];
            let mut needle = vec![b'a'; n / 16];
            let middle = needle.len() / 2;
            needle[middle] = b'b';
            assert_eq!(find(&hay, &needle), None);
            assert_eq!(rfind(&hay, &needle), None);
            hay.extend_from_slice(&needle);
            assert_eq!(find(&hay, &needle), Some(n));
            assert_eq!(rfind(&hay, &needle), Some(n));
            hay[..needle.len()].copy_from_slice(&needle);
            assert_eq!(find(&hay, &needle), Some(0));
            assert_eq!(rfind(&hay, &needle), Some(n));
        }
    }

    use crate::testutil;
    use std::string::String as S;

    /// A string argument that lives for the rest of the test run.
    fn st(t: &str) -> *const StrVal {
        Box::leak(Box::new(from_bytes(t.as_bytes())))
    }
    #[test]
    fn compare_matches_byte_order_for_inline_and_heap_strings() {
        let long = "abcdefghijklmnopqrstuvwxyz";
        let samples = [
            "",
            "a",
            "a\0",
            "a\0b",
            "ab",
            "b",
            "w123-4",
            "w123-45",
            "é",
            "éa",
            "\u{10ffff}",
            "123456789012345",
            "12345678901234x",
            long,
            "abcdefghijklmnopqrstuvwxyA",
            "abcdefghijklmno",
            "abcdefghijklmnoP",
        ];
        for a in samples {
            for b in samples {
                let want = a.as_bytes().cmp(b.as_bytes()) as i64;
                // SAFETY: both strings are live.
                let got = unsafe { msrt_string_compare(st(a), st(b)) };
                assert_eq!(got, want, "{a:?} against {b:?}");
            }
        }
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
    fn slice_and_scalar_at_follow_byte_offsets() {
        let _g = testutil::lock();
        let texts = [
            "",
            "héllo",
            "ascii only text longer than fifteen",
            "日本語のテキスト、長い文字列です。",
            "a😀b😀c😀d😀e😀f😀g😀h😀i",
        ];
        for text in texts {
            let n = text.len() as i64;
            for i in 0..n + 2 {
                for j in i..n + 2 {
                    let mut o = NO_STR;
                    // SAFETY: `st` creates live strings and `o` is writable.
                    unsafe { msrt_string_slice(st(text), i, j, &mut o) };
                    // Bounds clamp, then a bound inside a scalar moves inward.
                    let (mut a, mut b) = (i.min(n) as usize, j.min(n) as usize);
                    while a < b && !text.is_char_boundary(a) {
                        a += 1;
                    }
                    while b > a && !text.is_char_boundary(b) {
                        b -= 1;
                    }
                    assert_eq!(
                        txt(&o),
                        if a < b { &text[a..b] } else { "" },
                        "{text:?} {i}..{j}"
                    );
                }
                // SAFETY: as above.
                let at = unsafe { msrt_string_scalar_at(st(text), i, HasRaw(1), -1) };
                let want = text
                    .get(i as usize..)
                    .and_then(|rest| rest.chars().next())
                    .map_or(-1, |c| c as i64);
                assert_eq!(at, want, "scalar_at {text:?} {i}");
            }
        }
    }

    #[test]
    fn scalar_length_counts_scalars_and_scalar_at_takes_byte_offsets() {
        let _g = testutil::lock();
        unsafe {
            let s = st("héllo");
            assert_eq!(msrt_string_scalar_length(s), 5);
            assert_eq!(msrt_string_length(s), 6);
            assert_eq!((*s).len() as i64, 6);
            assert_eq!(msrt_string_scalar_at(s, 1, HasRaw(0), 0), 0xE9);
            assert_eq!(msrt_string_scalar_at(s, 3, HasRaw(0), 0), 'l' as i64);
            assert_eq!(msrt_string_scalar_at(s, 2, HasRaw(1), -1), -1);
            testutil::assert_fault(
                "String.scalar_at: offset 2 does not start a scalar of the 6 byte text; pass a default",
                || {
                    msrt_string_scalar_at(s, 2, HasRaw(0), 0);
                },
            );
        }
    }

    #[test]
    fn one_byte_split_matches_the_standard_split_at_every_shape() {
        let _g = testutil::lock();
        let alphabet = b"ab,, \xc3\xa9";
        for len in (0..40).chain([63, 64, 65, 127, 128, 129, 200]) {
            for seed in 0..12usize {
                let text: std::vec::Vec<u8> = (0..len)
                    .map(|i| alphabet[(i * 7 + seed * 5 + i / 3) % alphabet.len()])
                    .collect();
                let Ok(text) = std::string::String::from_utf8(text) else {
                    continue;
                };
                let want: std::vec::Vec<&str> = text.split(',').collect();
                // SAFETY: the strings are live for the calls and the list is released by the test.
                unsafe {
                    let mut v = EMPTY_VEC;
                    msrt_string_split(st(&text), st(","), &mut v);
                    assert_eq!(list(v), want, "{text:?}");
                }
            }
        }
    }

    #[test]
    fn split_replace_trim() {
        let _g = testutil::lock();
        unsafe {
            let mut v = EMPTY_VEC;
            msrt_string_split(st("a,b,c"), st(","), &mut v);
            assert_eq!(list(v), ["a", "b", "c"]);
            msrt_string_split(st("héy"), st(""), &mut v);
            assert_eq!(list(v), ["h", "é", "y"]);
            assert_eq!(
                ret(|o| msrt_string_replace_first(st("aaa"), st("a"), st("b"), o)),
                "baa"
            );
            assert_eq!(
                ret(|o| msrt_string_replace(st("ab"), st(""), st("-"), o)),
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
            assert_eq!(
                ret(|o| msrt_string_replace(st("abab"), st("b"), st("xy"), o)),
                "axyaxy"
            );
            assert_eq!(
                ret(|o| msrt_string_replace(st("aaa"), st("aa"), st("b"), o)),
                "ba"
            );
        }
    }

    #[test]
    fn replace_first_matches_standard_string_model() {
        let _g = testutil::lock();
        let long = format!("{}b", "a".repeat(8192));
        let texts = [
            "",
            "a",
            "aaaa",
            "abababa",
            "é🙂é",
            "e\u{301}é",
            "abcdefghijklmno",
            "abcdefghijklmnop",
            "abcdefghijklmnopq",
            long.as_str(),
        ];
        for text in texts {
            for old in ["", "a", "aa", "aba", "aaaaab", "é", "🙂", "missing"] {
                for new in ["", "b", "AAAAAB", "LONGER", "世界"] {
                    let expected = text.replacen(old, new, 1);
                    // SAFETY: `st` creates live strings and `ret` supplies a writable result.
                    let actual = unsafe {
                        ret(|out| msrt_string_replace_first(st(text), st(old), st(new), out))
                    };
                    assert_eq!(actual, expected, "text={text:?} old={old:?} new={new:?}");
                }
            }
        }
    }

    #[test]
    fn lowercase_sigma_ignores_unicode_marks_and_format_characters() {
        let _g = testutil::lock();
        for mark in ["\u{1ab0}", "\u{5bf}", "\u{2060}", "\u{fe0f}"] {
            let before = std::format!("A{mark}Σ");
            let after = std::format!("AΣ{mark}A");
            // SAFETY: `st` leaks a live string.
            let (lowered_before, lowered_after) =
                unsafe { (map_case(st(&before), false), map_case(st(&after), false)) };
            assert_eq!(txt(&lowered_before), std::format!("a{mark}ς"));
            assert_eq!(txt(&lowered_after), std::format!("aσ{mark}a"));
        }
    }

    #[test]
    #[cfg_attr(
        miri,
        ignore = "an exhaustive sweep that takes over 200 s interpreted; native CI runs it"
    )]
    fn fields_match_the_standard_whitespace_split() {
        let _g = testutil::lock();
        let atoms = [
            "a",
            "bc",
            "é",
            "日本",
            " ",
            "  ",
            "\t",
            "\n",
            "\r",
            "\u{b}",
            "\u{c}",
            "\u{85}",
            "\u{a0}",
            "\u{2003}",
            "\u{3000}",
            "\u{200b}",
            "\u{feff}",
            "😀",
            "long-token-over-fifteen-bytes",
        ];
        let mut x = 7u64;
        for _ in 0..3000 {
            let mut text = S::new();
            for _ in 0..(x % 9) {
                x = x
                    .wrapping_mul(6364136223846793005)
                    .wrapping_add(1442695040888963407);
                text.push_str(atoms[(x >> 33) as usize % atoms.len()]);
            }
            x = x
                .wrapping_mul(6364136223846793005)
                .wrapping_add(1442695040888963407);
            let expected: std::vec::Vec<&str> = text.split_whitespace().collect();
            // SAFETY: `st` leaks a live string; `v` is a writable list.
            let got = unsafe {
                let mut v = EMPTY_VEC;
                msrt_string_fields(st(&text), &mut v);
                list(v)
            };
            assert_eq!(got, expected, "{text:?}");
        }
    }

    #[test]
    #[cfg_attr(
        miri,
        ignore = "an exhaustive sweep that takes over 200 s interpreted; native CI runs it"
    )]
    fn trim_chars_match_the_standard_trim_matches() {
        let _g = testutil::lock();
        let atoms = [
            "a",
            "b",
            "é",
            "ü",
            "日",
            "-",
            " ",
            "😀",
            "xyz",
            "long-token-over-fifteen-bytes",
        ];
        let sets = ["", "a", "ab-", "é", "日é-", "😀 ", "xyzb", "ü日 -"];
        let mut x = 11u64;
        for _ in 0..4000 {
            let mut text = S::new();
            for _ in 0..(x % 8) {
                x = x
                    .wrapping_mul(6364136223846793005)
                    .wrapping_add(1442695040888963407);
                text.push_str(atoms[(x >> 33) as usize % atoms.len()]);
            }
            x = x
                .wrapping_mul(6364136223846793005)
                .wrapping_add(1442695040888963407);
            let set = sets[(x >> 33) as usize % sets.len()];
            let member = |c: char| set.contains(c);
            for (start, end) in [(1u8, 1u8), (1, 0), (0, 1)] {
                let mut expected = text.as_str();
                if start != 0 {
                    expected = expected.trim_start_matches(member);
                }
                if end != 0 {
                    expected = expected.trim_end_matches(member);
                }
                let got =
                    ret(|o| unsafe { msrt_string_trim_chars(st(&text), st(set), start, end, o) });
                assert_eq!(got, expected, "{text:?} {set:?} {start} {end}");
            }
        }
    }

    #[test]
    #[cfg_attr(
        miri,
        ignore = "an exhaustive sweep that takes over 200 s interpreted; native CI runs it"
    )]
    fn case_mapping_and_reverse_of_long_non_ascii_text_match_str() {
        let _g = testutil::lock();
        let atoms = [
            "a",
            "Z",
            "\u{e9}",
            "\u{c9}",
            "\u{df}",
            "\u{3a3}",
            "\u{3c3}",
            "\u{130}",
            "\u{212a}",
            "\u{17f}",
            "\u{20ac}",
            "\u{1d11e}",
            "\u{1f642}",
            " ",
            "\u{149}",
            "\u{1c5}",
        ];
        let mut x = 7u64;
        for _ in 0..400 {
            let mut text = String::new();
            for _ in 0..(8 + x % 24) {
                x = x
                    .wrapping_mul(6364136223846793005)
                    .wrapping_add(1442695040888963407);
                text.push_str(atoms[(x >> 33) as usize % atoms.len()]);
            }
            unsafe {
                let up = ret(|o| msrt_string_upper(st(&text), o));
                assert_eq!(up, text.to_uppercase(), "upper {text:?}");
                let low = ret(|o| msrt_string_lower(st(&text), o));
                assert_eq!(low, text.to_lowercase(), "lower {text:?}");
                let rev = ret(|o| msrt_string_reverse(st(&text), o));
                assert_eq!(
                    rev,
                    text.chars().rev().collect::<String>(),
                    "reverse {text:?}"
                );
            }
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
                ret(|o| msrt_string_pad_start(st("7"), 3, st("ab"), o)),
                "ab7"
            );
            assert_eq!(ret(|o| msrt_string_pad_end(st("7"), -2, st("ab"), o)), "7");
            assert_eq!(ret(|o| msrt_string_pad_end(st("7"), 4, st(""), o)), "7");
            msrt_string_slice(st("héllo"), 1, -1, &mut o);
            assert_eq!(txt(&o), "éll");
            msrt_string_slice(st("abc"), 2, 1, &mut o);
            assert_eq!(txt(&o), "");
            assert_eq!(ret(|o| msrt_string_reverse(st("aé"), o)), "éa");
        }
    }

    #[test]
    fn repeat_and_pad_fill_patterns_across_doubling_boundaries() {
        let _g = testutil::lock();
        unsafe {
            for pattern in ["x", "ab", "é🙂", "abcd123"] {
                for count in [0, 1, 2, 3, 5, 9, 17, 257] {
                    assert_eq!(
                        ret(|o| msrt_string_repeat(st(pattern), count, o)),
                        pattern.repeat(count as usize)
                    );
                    let target = count * pattern.chars().count() as i64 + 1;
                    assert_eq!(
                        ret(|o| msrt_string_pad_start(st("!"), target, st(pattern), o)),
                        std::format!("{}!", pattern.repeat(count as usize))
                    );
                    assert_eq!(
                        ret(|o| msrt_string_pad_end(st("!"), target, st(pattern), o)),
                        std::format!("!{}", pattern.repeat(count as usize))
                    );
                }
            }
            assert_eq!(
                ret(|o| msrt_string_pad_start(st("!"), 6, st("é🙂"), o)),
                "é🙂é🙂é!"
            );
            assert_eq!(ret(|o| msrt_string_repeat(st("ab"), -1, o)), "");
            assert_eq!(ret(|o| msrt_string_repeat(st(""), 3, o)), "");
            assert_eq!(ret(|o| msrt_string_repeat(st("ab"), 3, o)), "ababab");
        }
    }

    #[test]
    fn normalization_preserves_valid_and_malformed_scalar_sequences_with_budgets() {
        let _g = testutil::lock();
        let ascii: S = (0u8..=127).map(char::from).collect();
        let cases: &[(&[u8], [&str; 4])] = &[
            (b"", [""; 4]),
            (b"A\0z", ["A\0z"; 4]),
            (ascii.as_bytes(), [ascii.as_str(); 4]),
            ("e\u{301}".as_bytes(), ["é", "e\u{301}", "é", "e\u{301}"]),
            ("ﬁ①".as_bytes(), ["ﬁ①", "ﬁ①", "fi1", "fi1"]),
            (
                "a\u{315}\u{300}".as_bytes(),
                ["à\u{315}", "a\u{300}\u{315}", "à\u{315}", "a\u{300}\u{315}"],
            ),
            ("각".as_bytes(), ["각", "각", "각", "각"]),
            ("\u{FFFD}".as_bytes(), ["\u{FFFD}"; 4]),
            (&[0xff, 0, b'a'], ["\u{FFFD}\0a"; 4]),
            (&[b'a', 0xff], ["a\u{FFFD}"; 4]),
            (&[0xc0, 0xaf], ["\u{FFFD}\u{FFFD}"; 4]),
            (&[0xf0, 0x9f, 0x98], ["\u{FFFD}\u{FFFD}\u{FFFD}"; 4]),
            (&[0xed, 0xa0, 0x80], ["\u{FFFD}\u{FFFD}\u{FFFD}"; 4]),
            (
                &[0xf4, 0x90, 0x80, 0x80],
                ["\u{FFFD}\u{FFFD}\u{FFFD}\u{FFFD}"; 4],
            ),
            (
                &[0xff, b'e', 0xcc, 0x81],
                [
                    "\u{FFFD}é",
                    "\u{FFFD}e\u{301}",
                    "\u{FFFD}é",
                    "\u{FFFD}e\u{301}",
                ],
            ),
        ];
        for &(data, forms) in cases {
            let input = from_bytes(data);
            for (kind, expected) in forms.into_iter().enumerate() {
                for limit in [
                    None,
                    Some(0),
                    Some(expected.len()),
                    Some(expected.len().saturating_sub(1)),
                    Some(expected.len() + 1),
                ] {
                    let mut actual = from_bytes(b"sentinel");
                    let expected_status = if limit.is_some_and(|max| expected.len() > max) {
                        STATUS_LIMIT_EXCEEDED
                    } else {
                        STATUS_OK
                    };
                    // SAFETY: input and actual are live, and kind is one of the four forms.
                    unsafe {
                        let status = msrt_string_normalize_kind(
                            &input,
                            kind as i64,
                            HasRaw(u8::from(limit.is_some())),
                            limit.unwrap_or(0) as i64,
                            &mut actual,
                        );
                        assert_eq!(
                            status, expected_status,
                            "input {data:?}, form {kind}, limit {limit:?}"
                        );
                        let expected_bytes = if status == STATUS_OK {
                            expected.as_bytes()
                        } else {
                            b"sentinel"
                        };
                        assert_eq!(
                            bytes(&actual),
                            expected_bytes,
                            "input {data:?}, form {kind}, limit {limit:?}"
                        );
                    }
                }
            }
        }
    }

    #[test]
    fn normalization_keeps_invalid_form_and_negative_budget_errors() {
        let _g = testutil::lock();
        // SAFETY: st creates live input strings and actual is a writable live output.
        unsafe {
            for form in ["", "nfc", "NFC\0", "UNKNOWN"] {
                for (has_max, max) in [(0, 0), (1, -1)] {
                    let mut actual = from_bytes(b"sentinel");
                    assert_eq!(
                        msrt_string_normalize(
                            st("é"),
                            st(form),
                            ms_rt_abi::HasRaw(has_max),
                            max,
                            &mut actual
                        ),
                        STATUS_INVALID_INPUT
                    );
                    assert_eq!(bytes(&actual), b"sentinel");
                }
            }
            for form in ["NFC", "NFD", "NFKC", "NFKD"] {
                let mut actual = from_bytes(b"sentinel");
                assert_eq!(
                    msrt_string_normalize(st("é"), st(form), HasRaw(1), -1, &mut actual),
                    STATUS_INVALID_INPUT
                );
                assert_eq!(bytes(&actual), b"sentinel");
            }
        }
    }

    #[test]
    fn normalize_copies_ascii_runs_and_normalizes_around_marks() {
        let _g = testutil::lock();
        unsafe {
            let piece = "ab e\u{301} cd e\u{301}\u{323}x\u{fb01}y";
            let expect = [
                ("NFC", "ab \u{e9} cd \u{1eb9}\u{301}x\u{fb01}y"),
                ("NFD", "ab e\u{301} cd e\u{323}\u{301}x\u{fb01}y"),
                ("NFKC", "ab \u{e9} cd \u{1eb9}\u{301}xfiy"),
                ("NFKD", "ab e\u{301} cd e\u{323}\u{301}xfiy"),
            ];
            for (form, want) in expect {
                let mut o = NO_STR;
                assert_eq!(
                    msrt_string_normalize(st(piece), st(form), HasRaw(0), 0, &mut o),
                    STATUS_OK
                );
                assert_eq!(txt(&o), want, "{form}");
                let wrapped = format!("q{piece}r");
                assert_eq!(
                    msrt_string_normalize(st(&wrapped), st(form), HasRaw(0), 0, &mut o),
                    STATUS_OK
                );
                assert_eq!(txt(&o), format!("q{want}r"), "{form} wrapped");
                assert_eq!(
                    msrt_string_normalize(
                        st(piece),
                        st(form),
                        HasRaw(1),
                        want.len() as i64,
                        &mut o
                    ),
                    STATUS_OK
                );
                assert_eq!(
                    msrt_string_normalize(
                        st(piece),
                        st(form),
                        HasRaw(1),
                        want.len() as i64 - 1,
                        &mut o
                    ),
                    STATUS_LIMIT_EXCEEDED
                );
            }
        }
    }

    #[test]
    fn normalize_nfd() {
        let _g = testutil::lock();
        unsafe {
            let mut o = NO_STR;
            assert_eq!(
                msrt_string_normalize(st("é"), st("NFD"), HasRaw(0), 0, &mut o),
                STATUS_OK
            );
            assert_eq!(txt(&o), "e\u{301}");
            assert_eq!(
                msrt_string_normalize(st("é"), st("NFD"), HasRaw(1), 2, &mut o),
                STATUS_LIMIT_EXCEEDED
            );
        }
    }
}
