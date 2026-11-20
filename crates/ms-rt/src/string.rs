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

unsafe extern "C-unwind" {
    fn ms_utf8_count(s: *const u8, n: usize) -> usize;
}
use core::ptr::null_mut;
use ms_rt_abi::{HasRaw, STR_INLINE_MAX, StrVal, VecVal};

// The moved symbols (runtime/symbols/string.txt) are defined by the C runtime; Rust callers and tests reach them here.
unsafe extern "C-unwind" {
    pub fn msrt_string_fields(s: *const StrVal, out: *mut VecVal);
    pub fn msrt_string_upper(s: *const StrVal, out: *mut StrVal);
    pub fn msrt_string_lower(s: *const StrVal, out: *mut StrVal);
    pub fn msrt_string_upper_take(s: *mut StrVal, out: *mut StrVal);
    pub fn msrt_string_lower_take(s: *mut StrVal, out: *mut StrVal);
    pub fn msrt_string_normalize(
        s: *const StrVal,
        form: *const StrVal,
        has_max: HasRaw,
        max: i64,
        out: *mut StrVal,
    ) -> u8;
    pub fn msrt_string_normalize_kind(
        s: *const StrVal,
        kind: i64,
        has_max: HasRaw,
        max: i64,
        out: *mut StrVal,
    ) -> u8;
    pub fn msrt_string_quote(s: *const StrVal, out: *mut StrVal);
    pub fn msrt_string_parse_float(s: *const StrVal, out: *mut f64) -> u8;
    pub fn msrt_string_scalar_at(
        s: *const StrVal,
        offset: i64,
        has_default: HasRaw,
        default: i64,
    ) -> i64;
    pub fn msrt_string_index_any(s: *const StrVal, set: *const StrVal, out: *mut i64) -> u8;
    pub fn msrt_string_last_index_of(a: *const StrVal, v: *const StrVal, out: *mut i64) -> u8;
    pub fn msrt_string_trim_chars(
        s: *const StrVal,
        set: *const StrVal,
        from_start: u8,
        from_end: u8,
        out: *mut StrVal,
    );
    pub fn msrt_string_from_scalars(values: *const VecVal, out: *mut StrVal) -> u8;
    pub fn msrt_string_to_bytes(s: *const StrVal, out: *mut VecVal);
    pub fn msrt_string_view_bytes(s: *const StrVal, out: *mut VecVal);
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

unsafe extern "C" {
    /// The shared one-character ASCII strings (runtime/core/ascii.c).
    static mut msrt_ascii_chars: [[u8; 2]; 128];
}

fn ascii_char(b: u8) -> StrVal {
    // SAFETY: the table is static and `b` is below 128.
    unsafe {
        StrVal::literal(
            core::ptr::addr_of_mut!(msrt_ascii_chars[b as usize]) as *mut u8,
            1,
        )
    }
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
        ms_utf8_count(bytes(s).as_ptr(), (*s).len())
    }
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

// ---------------------------------------------------------------------------
// Building
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Conversions to string (Int, Float, Bool)
// ---------------------------------------------------------------------------

unsafe extern "C-unwind" {
    /// `[list copies, list bytes, string clones, string bytes]` of the counting runtime (zeros elsewhere).
    pub fn msrt_copy_counts(out: *mut u64);
}

/// The deep copies the runtime performed, counted by the C runtime.
pub fn copy_counts() -> [u64; 4] {
    let mut counts = [0; 4];
    // SAFETY: `counts` has the four words the C side writes.
    unsafe { msrt_copy_counts(counts.as_mut_ptr()) };
    counts
}
