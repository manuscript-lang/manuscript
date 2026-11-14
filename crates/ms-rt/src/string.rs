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
    HasRaw, Obj, STATUS_INVALID_INPUT, STATUS_LIMIT_EXCEEDED, STATUS_OK, STATUS_OUT_OF_RANGE,
    STR_INLINE_MAX, STR_LEN_MASK, StrVal, VecVal,
};

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

/// Writes an owned copy of `s` to `out` (what `.clone()` and every implicit copy of a string do).
#[unsafe(no_mangle)]
// ms: leaf fresh
pub unsafe extern "C-unwind" fn msrt_string_clone(s: *const StrVal, out: *mut StrVal) {
    #[cfg(feature = "stats")]
    // SAFETY: caller passes a live string.
    count_copy(1, unsafe { bytes(&*s) }.len());
    // SAFETY: caller passes a live string and a writable `out`.
    unsafe { cloned(&*s).write_to(out) }
}

/// Frees an owned string's bytes (the drop compiled code calls when `cap != 0`).
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_str_free(ptr: *mut u8) {
    // SAFETY: `ptr` is the start of an owned string.
    unsafe { free_owned(ptr) }
}

/// Writes a copy of the owned string or view `{ptr, tagged}` to `out`: inline when it fits, so
/// copying a short string allocates nothing (what compiled code calls to copy a string).
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_str_copy(ptr: *const u8, tagged: usize, out: *mut StrVal) {
    // SAFETY: an owned string or a view has `len` readable bytes at `ptr`.
    unsafe { owned_copy(core::slice::from_raw_parts(ptr, tagged & STR_LEN_MASK)).write_to(out) }
}

/// Frees an owned string.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_free(s: *const StrVal) {
    // SAFETY: caller owns `s`.
    unsafe { release(&*s) }
}

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

/// Writes the static empty string to `out`.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_empty(out: *mut StrVal) {
    // SAFETY: caller passes a writable out.
    unsafe { (empty()).write_to(out) }
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

/// The bytes of a string of at most 16 bytes as little-endian bits.
///
/// # Safety
/// `s` is live and at most 16 bytes long.
#[inline(always)]
unsafe fn bits(s: &StrVal) -> u128 {
    if s.is_inline() {
        return s.inline_bits();
    }
    // SAFETY: caller contract.
    ms_rt_abi::pack(unsafe { bytes(s) })
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

/// New string from raw bytes. Exported for literals built at startup and for the Rust stdlib crates.
///
/// # Safety
/// `ptr..ptr+len` must be readable; `out` writable.
#[unsafe(no_mangle)]
// ms: leaf
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

/// Byte offset of scalar `n` (0..=count).
unsafe fn scalar_offset(s: *const StrVal, n: usize) -> usize {
    // SAFETY: `s` live.
    unsafe { utf8::offset_of(bytes(s), n) }
}

/// Substring by scalar range (callers validated `0 <= a <= b <= count`).
unsafe fn sub_scalars(s: *const StrVal, a: usize, b: usize) -> StrVal {
    // SAFETY: `s` live; range validated.
    unsafe {
        let (text, n) = (bytes(s), scalar_count(s));
        if a == 0 && b == n {
            return cloned(&*s);
        }
        if n == text.len() {
            return from_bytes(&text[a..b]);
        }
        let (ao, bo) = (scalar_offset(s, a), scalar_offset(s, b));
        from_bytes(&text[ao..bo])
    }
}

/// Substring by nonnegative scalar bounds `a <= b` on a string not known to be ASCII, found by
/// walking the text once; `None` when `b` exceeds the scalar length. No whole-string count.
unsafe fn walk_sub_scalars(s: *const StrVal, a: usize, b: usize) -> Option<StrVal> {
    // SAFETY: `s` live.
    unsafe {
        let text = bytes(s);
        let ao = utf8::advance(text, 0, a)?;
        let bo = utf8::advance(text, ao, b - a)?;
        if ao == 0 && bo == text.len() {
            return Some(cloned(&*s));
        }
        Some(from_bytes(&text[ao..bo]))
    }
}

#[unsafe(no_mangle)]
// ms: leaf pure domain=string
pub unsafe extern "C-unwind" fn msrt_string_starts_with(a: *const StrVal, v: *const StrVal) -> u8 {
    // SAFETY: caller passes live strings.
    unsafe { bytes(a).starts_with(bytes(v)) as u8 }
}

#[unsafe(no_mangle)]
// ms: leaf pure domain=string
pub unsafe extern "C-unwind" fn msrt_string_ends_with(a: *const StrVal, v: *const StrVal) -> u8 {
    // SAFETY: caller passes live strings.
    unsafe { bytes(a).ends_with(bytes(v)) as u8 }
}

#[unsafe(no_mangle)]
// ms: leaf pure domain=map
pub unsafe extern "C-unwind" fn msrt_string_compare(a: *const StrVal, b: *const StrVal) -> i64 {
    // SAFETY: caller passes live strings.
    unsafe { bytes(a).cmp(bytes(b)) as i64 }
}

/// Hash of a string's bytes (equal strings hash equally).
///
#[unsafe(no_mangle)]
// ms: leaf pure domain=map
pub unsafe extern "C-unwind" fn msrt_string_hash(s: *const StrVal) -> i64 {
    // SAFETY: caller passes a live string.
    hash_bytes(unsafe { bytes(s) }) as i64
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

/// Whether the text is known to be ASCII without a long scan: the flag, the bits of an inline
/// string, or a check of fewer than [`MEDIUM_HAY`] bytes.
///
/// # Safety
/// `s` must be a live string.
#[inline(always)]
unsafe fn short_ascii(s: *const StrVal) -> bool {
    // SAFETY: caller contract.
    unsafe {
        if (*s).is_inline() {
            return (*s).inline_bits() & 0x8080_8080_8080_8080_8080_8080_8080_8080 == 0;
        }
        (*s).flagged_ascii() || ((*s).len() < MEDIUM_HAY && bytes(s).is_ascii())
    }
}

/// `find` for a short haystack and a non-empty needle.
#[inline]
pub(super) fn find_short(hay: &[u8], needle: &[u8]) -> Option<usize> {
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

/// A one-byte needle in a short text is a short scan; every other search is the general one.
#[unsafe(no_mangle)]
// ms: leaf pure domain=string
pub unsafe extern "C-unwind" fn msrt_string_contains(a: *const StrVal, v: *const StrVal) -> u8 {
    // SAFETY: caller passes live strings.
    unsafe {
        let hay = bytes(a);
        match bytes(v) {
            [] => 1,
            [c] if hay.len() < SHORT_HAY => hay.contains(c) as u8,
            _ => msrt_string_contains_long(a, v),
        }
    }
}

/// A search in an ASCII text of under [`MEDIUM_HAY`] bytes (a line, a record, a field) is a direct
/// scan; every other search is the general one.
#[unsafe(no_mangle)]
// ms: leaf pure domain=string
pub unsafe extern "C-unwind" fn msrt_string_index_of(
    a: *const StrVal,
    v: *const StrVal,
    out: *mut i64,
) -> u8 {
    // SAFETY: caller passes live strings and a writable out.
    unsafe {
        let (hay, needle) = (bytes(a), bytes(v));
        if hay.len() < MEDIUM_HAY && short_ascii(a) {
            let found = match needle {
                [] => Some(0),
                [c] => memchr_short(*c, hay),
                _ => find_short(hay, needle),
            };
            return match found {
                Some(i) => {
                    *out = i as i64;
                    1
                }
                None => 0,
            };
        }
        msrt_string_index_of_long(a, v, out)
    }
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

/// `String.scalar_at` of an ASCII text with an index inside it is one byte read.
#[unsafe(no_mangle)]
// ms: leaf pure domain=string
pub unsafe extern "C-unwind" fn msrt_string_scalar_at(
    s: *const StrVal,
    index: i64,
    has_default: HasRaw,
    default: i64,
) -> i64 {
    // SAFETY: caller passes a live string.
    unsafe {
        let text = bytes(s);
        let n = text.len() as i64;
        let at = if index < 0 { n + index } else { index };
        if let Some(&b) = text.get(at as usize).filter(|_| short_ascii(s) && at >= 0) {
            return b as i64;
        }
        msrt_string_scalar_at_slow(s, index, has_default, default)
    }
}

/// C view: `msrt_string_eq(a: *const StrVal, b: *const StrVal) -> u8`
///
/// The compiler decides most comparisons inline (the backends decide it from the words; `str.eq_lit`) and calls this
/// for two distinct blocks of one length.
#[unsafe(no_mangle)]
// ms: leaf pure domain=string
pub unsafe extern "C-unwind" fn msrt_string_eq(a: *const StrVal, b: *const StrVal) -> u8 {
    // SAFETY: caller passes live strings.
    unsafe { equal(a, b) as u8 }
}

/// C view: `msrt_string_length(s: *const StrVal) -> i64`
/// `byte_length()` for a bound method value; direct calls read the length inline (`str.bytes`).
#[unsafe(no_mangle)]
// ms: leaf pure domain=string
pub unsafe extern "C-unwind" fn msrt_string_byte_length(s: *const StrVal) -> i64 {
    // SAFETY: caller passes a live string.
    unsafe { (*s).len() as i64 }
}

/// `is_empty()` for a bound method value; direct calls read the length inline (`str.bytes`).
#[unsafe(no_mangle)]
// ms: leaf pure domain=string
pub unsafe extern "C-unwind" fn msrt_string_is_empty(s: *const StrVal) -> u8 {
    // SAFETY: caller passes a live string.
    unsafe { (*s).is_empty() as u8 }
}

#[unsafe(no_mangle)]
// ms: leaf pure domain=string
pub unsafe extern "C-unwind" fn msrt_string_length(s: *const StrVal) -> i64 {
    // SAFETY: caller passes a live string.
    unsafe { scalar_count(s) as i64 }
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
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_get(
    s: *const StrVal,
    index: i64,
    has_default: HasRaw,
    default: *const StrVal,
    out: *mut StrVal,
) {
    // SAFETY: caller passes a writable `out` and live arguments.
    unsafe { (string_get(s, index, has_default.is_set(), default)).write_to(out) }
}

unsafe fn string_get(
    s: *const StrVal,
    index: i64,
    has_default: bool,
    default: *const StrVal,
) -> StrVal {
    // SAFETY: caller passes live strings (default may be absent).
    unsafe {
        let text = bytes(s);
        let off = if index >= 0 && !(*s).flagged_ascii() {
            // Non-ASCII text: walk to the scalar instead of counting the whole string first.
            utf8::advance(text, 0, index as usize).filter(|&o| o < text.len())
        } else if index < 0 && !(*s).flagged_ascii() {
            // Negative index: walk back from the end, again without a whole-string count.
            utf8::retreat(text, text.len(), index.unsigned_abs() as usize)
        } else {
            let n = scalar_count(s);
            relative(n, index).map(|i| {
                if n == text.len() {
                    i
                } else {
                    scalar_offset(s, i)
                }
            })
        };
        let Some(off) = off else {
            if !has_default {
                fault::msrt_index_fault(index, scalar_count(s) as i64);
            }
            return cloned(&*default);
        };
        if (*s).flagged_ascii() {
            return from_bytes(&text[off..off + 1]);
        }
        let (c, w) = utf8::decode(&text[off..]);
        if c == 0xFFFD && w == 1 {
            return from_bytes("\u{FFFD}".as_bytes());
        }
        from_bytes(&text[off..off + w])
    }
}

/// `String.scalar_at(index, default)`.
pub unsafe fn msrt_string_scalar_at_slow(
    s: *const StrVal,
    index: i64,
    has_default: HasRaw,
    default: i64,
) -> i64 {
    // SAFETY: caller passes a live string.
    unsafe {
        // All-ASCII text: a scalar index is a byte index.
        if (*s).flagged_ascii()
            && let Some(&byte) = usize::try_from(index).ok().and_then(|i| bytes(s).get(i))
        {
            return i64::from(byte);
        }
        scalar_at_slow(s, index, has_default.is_set(), default)
    }
}

#[inline(never)]
unsafe fn scalar_at_slow(s: *const StrVal, index: i64, has_default: bool, default: i64) -> i64 {
    // SAFETY: caller passes a live string.
    unsafe {
        let text = bytes(s);
        let off = if index >= 0 && !(*s).flagged_ascii() {
            utf8::advance(text, 0, index as usize).filter(|&o| o < text.len())
        } else if index < 0 && !(*s).flagged_ascii() {
            utf8::retreat(text, text.len(), index.unsigned_abs() as usize)
        } else {
            let n = scalar_count(s);
            relative(n, index).map(|i| {
                if n == text.len() {
                    i
                } else {
                    scalar_offset(s, i)
                }
            })
        };
        let Some(off) = off else {
            if !has_default {
                fault::msrt_index_fault(index, scalar_count(s) as i64);
            }
            return default;
        };
        utf8::decode(&text[off..]).0 as i64
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

/// A non-empty needle searched for repeatedly: one byte goes straight to `memchr`, longer ones
/// build their `memmem` searcher once instead of on every search.
#[allow(
    clippy::large_enum_variant,
    reason = "lives on the stack for one call; boxing would allocate"
)]
enum Needle<'a> {
    Byte(u8),
    /// A needle of two or more bytes in a text shorter than [`MEDIUM_HAY`]: scanned directly, so no
    /// `memmem` searcher is built for it.
    Short(&'a [u8]),
    Bytes(memchr::memmem::Finder<'a>),
}

impl<'a> Needle<'a> {
    fn new(needle: &'a [u8]) -> Self {
        match needle {
            [b] => Needle::Byte(*b),
            _ => Needle::Bytes(memchr::memmem::Finder::new(needle)),
        }
    }

    /// A searcher for `needle` over haystacks of at most `text_len` bytes: building a `memmem`
    /// searcher costs more than scanning a short text.
    fn for_text(needle: &'a [u8], text_len: usize) -> Self {
        if needle.len() > 1 && text_len < MEDIUM_HAY {
            return Needle::Short(needle);
        }
        Self::new(needle)
    }

    /// Matches in text are usually a few bytes apart (words, fields), where the vector
    /// searchers' per-call setup costs more than the scan: the first [`NEAR`] bytes are scanned
    /// as words before the long haystack goes to them.
    #[inline]
    fn find(&self, hay: &[u8]) -> Option<usize> {
        match self {
            Needle::Byte(b) if hay.len() < SHORT_HAY => memchr_short(*b, hay),
            Needle::Byte(b) => {
                if let Some(i) = memchr_short(*b, &hay[..NEAR]) {
                    return Some(i);
                }
                memchr(*b, &hay[NEAR..]).map(|i| i + NEAR)
            }
            Needle::Short(n) => find_short(hay, n),
            Needle::Bytes(f) if hay.len() < SHORT_HAY => find_short(hay, f.needle()),
            Needle::Bytes(f) => {
                // A match starting before `NEAR` ends inside this window.
                let near = (NEAR + f.needle().len() - 1).min(hay.len());
                if let Some(i) = find_short(&hay[..near], f.needle()) {
                    return Some(i);
                }
                f.find(&hay[NEAR..]).map(|i| i + NEAR)
            }
        }
    }
}

/// Longest string `slice` checks for ASCII by scanning when it carries no flag: the scan costs less
/// than walking scalars to the bounds.
const SHORT_SCAN: usize = 256;

/// Bytes scanned as words before a long haystack goes to a vector searcher (below [`SHORT_HAY`]).
const NEAR: usize = 16;

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

/// `contains` where the caller knows the needle has two or more bytes (a literal): the general
/// search without the one-byte checks.
#[unsafe(no_mangle)]
// ms: leaf pure domain=string
pub unsafe extern "C-unwind" fn msrt_string_contains_multi(
    a: *const StrVal,
    v: *const StrVal,
) -> u8 {
    // SAFETY: caller passes live strings.
    unsafe { find(bytes(a), bytes(v)).is_some() as u8 }
}

/// The scalar index of byte offset `at` in `text`, the bytes of `s`: a string flagged ASCII needs no
/// scan of the prefix.
///
/// # Safety
/// `s` is live and `text` is its bytes.
unsafe fn scalar_index(s: *const StrVal, text: &[u8], at: usize) -> usize {
    // SAFETY: caller passes a live string.
    if unsafe { (*s).flagged_ascii() } {
        at
    } else {
        utf8::count(&text[..at])
    }
}

/// Non-overlapping occurrences of `v` in `a`; an empty `v` counts the scalars plus one.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_count(a: *const StrVal, v: *const StrVal) -> i64 {
    // SAFETY: caller passes live strings.
    unsafe {
        let (text, part) = (bytes(a), bytes(v));
        if part.is_empty() {
            return utf8::count(text) as i64 + 1;
        }
        count_matches(text, part) as i64
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
                *out = scalar_index(a, text, i) as i64;
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
                *out = scalar_index(a, text, i) as i64;
                1
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Building
// ---------------------------------------------------------------------------

#[unsafe(no_mangle)]
// ms: leaf fresh
pub unsafe extern "C-unwind" fn msrt_string_concat(
    a: *const StrVal,
    b: *const StrVal,
    out: *mut StrVal,
) {
    // SAFETY: caller passes a writable `out` and live arguments.
    unsafe { (msrt_string_concat_val(a, b)).write_to(out) }
}

/// `a + b` that moving_params `a`: an owned `a` grows in place, so `s = s + piece` in a loop reuses
/// one allocation instead of copying the prefix every time.
///
/// # Safety
/// `a` is owned by the caller and dead after the call; `b` is live; `out` is writable.
#[unsafe(no_mangle)]
// ms: leaf fresh
pub unsafe extern "C-unwind" fn msrt_string_append(
    a: *const StrVal,
    b: *const StrVal,
    out: *mut StrVal,
) {
    // SAFETY: caller passes live strings, gives up `a`, and passes a writable `out`.
    unsafe {
        let (sa, la, lb) = (core::ptr::read(a), (*a).len(), (*b).len());
        let within =
            |p: *const u8| p >= sa.ptr_word.cast_const() && p <= sa.ptr_word.add(la).cast_const();
        if !sa.owns() || la == 0 || within((*b).data()) {
            let s = msrt_string_concat_val(a, b);
            release(&sa);
            return s.write_to(out);
        }
        if lb == 0 {
            return sa.write_to(out);
        }
        if la + lb > MAX_BYTES {
            fault::fault(b"string: limit exceeded");
        }
        // Only a flagged `a` stays flagged: scanning an unflagged one on every append is quadratic.
        let ascii = sa.flagged_ascii() && is_ascii(&*b);
        // Room left in the block is used as is; otherwise the string moves to a block with
        // slack, so a run of appends reallocates a logarithmic number of times.
        let need = la + lb + 1;
        let p = if alloc::usable_size(sa.ptr_word) >= need {
            sa.ptr_word
        } else {
            alloc::realloc(sa.ptr_word, need + need / 2)
        };
        core::ptr::copy_nonoverlapping(bytes(b).as_ptr(), p.add(la), lb);
        *p.add(la + lb) = 0;
        let r = StrVal::owned(p, la + lb);
        (if ascii { r.with_ascii() } else { r }).write_to(out)
    }
}

#[inline(always)]
unsafe fn msrt_string_concat_val(a: *const StrVal, b: *const StrVal) -> StrVal {
    // SAFETY: caller passes live strings.
    unsafe {
        let (la, lb) = ((*a).len(), (*b).len());
        if lb == 0 {
            return cloned(&*a);
        }
        if la == 0 {
            return cloned(&*b);
        }
        if la + lb <= STR_INLINE_MAX {
            return StrVal::from_bits(bits(&*a) | (bits(&*b) << (8 * la)), la + lb);
        }
        let s = alloc_str(la + lb);
        core::ptr::copy_nonoverlapping(bytes(a).as_ptr(), s.ptr_word, la);
        core::ptr::copy_nonoverlapping(bytes(b).as_ptr(), s.ptr_word.add(la), lb);
        if is_ascii(&*a) && is_ascii(&*b) {
            s.with_ascii()
        } else {
            s
        }
    }
}

/// Joins `parts` into one string with a single allocation (what a chain of `concat` calls
/// would build with one allocation per link).
unsafe fn concat_parts(parts: &[*const StrVal]) -> StrVal {
    // SAFETY: caller passes live strings.
    unsafe {
        let total: usize = parts.iter().map(|&p| (*p).len()).sum();
        if total <= STR_INLINE_MAX {
            let (mut acc, mut at) = (0u128, 0);
            for &p in parts {
                acc |= bits(&*p) << (8 * at);
                at += (*p).len();
            }
            return StrVal::from_bits(acc, total);
        }
        let s = alloc_str(total);
        let mut dst = s.ptr_word;
        for &p in parts {
            let b = bytes(p);
            core::ptr::copy_nonoverlapping(b.as_ptr(), dst, b.len());
            dst = dst.add(b.len());
        }
        s
    }
}

/// `a + b + c` with one allocation.
#[unsafe(no_mangle)]
// ms: leaf fresh
pub unsafe extern "C-unwind" fn msrt_string_concat3(
    a: *const StrVal,
    b: *const StrVal,
    c: *const StrVal,
    out: *mut StrVal,
) {
    // SAFETY: caller passes live strings and a writable `out`.
    unsafe { concat_parts(&[a, b, c]).write_to(out) }
}

/// `a + b + c + d` with one allocation.
#[unsafe(no_mangle)]
// ms: leaf fresh
pub unsafe extern "C-unwind" fn msrt_string_concat4(
    a: *const StrVal,
    b: *const StrVal,
    c: *const StrVal,
    d: *const StrVal,
    out: *mut StrVal,
) {
    // SAFETY: caller passes live strings and a writable `out`.
    unsafe { concat_parts(&[a, b, c, d]).write_to(out) }
}

/// `a + b + c + d + e` with one allocation.
#[unsafe(no_mangle)]
// ms: leaf fresh
pub unsafe extern "C-unwind" fn msrt_string_concat5(
    a: *const StrVal,
    b: *const StrVal,
    c: *const StrVal,
    d: *const StrVal,
    e: *const StrVal,
    out: *mut StrVal,
) {
    // SAFETY: caller passes live strings and a writable `out`.
    unsafe { concat_parts(&[a, b, c, d, e]).write_to(out) }
}

/// `a + b + c + d + e + f` with one allocation.
#[unsafe(no_mangle)]
// ms: leaf fresh
pub unsafe extern "C-unwind" fn msrt_string_concat6(
    a: *const StrVal,
    b: *const StrVal,
    c: *const StrVal,
    d: *const StrVal,
    e: *const StrVal,
    f: *const StrVal,
    out: *mut StrVal,
) {
    // SAFETY: caller passes live strings and a writable `out`.
    unsafe { concat_parts(&[a, b, c, d, e, f]).write_to(out) }
}

/// Most parts one `msrt_string_fmtN` joins.
const MAX_FMT: usize = 6;

/// Joins `parts` with one allocation: part `k` is an `i64` written in decimal when bit `k` of
/// `mask` is set, otherwise a `*const StrVal`. `f"{name}={n}"` builds its text here without a
/// temporary string for `n`.
///
/// # Safety
/// Every part whose mask bit is clear is a live string.
#[inline(always)]
unsafe fn format_parts<const N: usize>(mask: i64, parts: [usize; N]) -> StrVal {
    const { assert!(N <= MAX_FMT) };
    // Digit buffers are initialised only for the integer parts.
    let mut digits: [core::mem::MaybeUninit<[u8; 20]>; N] = [core::mem::MaybeUninit::uninit(); N];
    let mut slices: [(*const u8, usize); N] = [(core::ptr::null(), 0); N];
    let mut total = 0usize;
    for (k, p) in parts.into_iter().enumerate() {
        let (ptr, len) = if (mask >> k) & 1 == 1 {
            let d = crate::num::format_i64(p as i64, digits[k].write([0u8; 20]));
            (d.as_ptr(), d.len())
        } else {
            // SAFETY: caller contract.
            let s = unsafe { &*(p as *const StrVal) };
            (s.data(), s.len())
        };
        slices[k] = (ptr, len);
        total += len;
    }
    let mut buf = [0u8; 16];
    let s = if total <= STR_INLINE_MAX {
        None
    } else {
        Some(alloc_str(total))
    };
    let dst = match &s {
        Some(s) => s.ptr_word,
        None => buf.as_mut_ptr(),
    };
    let mut at = 0usize;
    for &(ptr, len) in &slices {
        // SAFETY: `dst` has room for `total` bytes and every slice is readable.
        unsafe { core::ptr::copy_nonoverlapping(ptr, dst.add(at), len) };
        at += len;
    }
    match s {
        Some(s) => s,
        // `buf` is zero past `total`.
        None => StrVal::from_bits(u128::from_le_bytes(buf), total),
    }
}

/// `f"{a}{b}"` where a part may be an integer: see [`format_parts`].
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_fmt2(mask: i64, a: usize, b: usize, out: *mut StrVal) {
    // SAFETY: caller passes live strings and a writable `out`.
    unsafe { format_parts(mask, [a, b]).write_to(out) }
}

/// Three parts, any of them integers: see [`format_parts`].
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_fmt3(
    mask: i64,
    a: usize,
    b: usize,
    c: usize,
    out: *mut StrVal,
) {
    // SAFETY: caller passes live strings and a writable `out`.
    unsafe { format_parts(mask, [a, b, c]).write_to(out) }
}

/// Four parts, any of them integers: see [`format_parts`].
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_fmt4(
    mask: i64,
    a: usize,
    b: usize,
    c: usize,
    d: usize,
    out: *mut StrVal,
) {
    // SAFETY: caller passes live strings and a writable `out`.
    unsafe { format_parts(mask, [a, b, c, d]).write_to(out) }
}

/// Five parts, any of them integers: see [`format_parts`].
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_fmt5(
    mask: i64,
    a: usize,
    b: usize,
    c: usize,
    d: usize,
    e: usize,
    out: *mut StrVal,
) {
    // SAFETY: caller passes live strings and a writable `out`.
    unsafe { format_parts(mask, [a, b, c, d, e]).write_to(out) }
}

/// Six parts, any of them integers: see [`format_parts`].
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_fmt6(
    mask: i64,
    a: usize,
    b: usize,
    c: usize,
    d: usize,
    e: usize,
    f: usize,
    out: *mut StrVal,
) {
    // SAFETY: caller passes live strings and a writable `out`.
    unsafe { format_parts(mask, [a, b, c, d, e, f]).write_to(out) }
}

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

#[unsafe(no_mangle)]
// ms: leaf
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

/// Writes a view of `s` without the whitespace the flags name to `out`: no allocation, valid
/// while `s` is neither changed nor dropped (the borrow check guarantees that).
#[inline(always)]
unsafe fn trim_view(s: *const StrVal, start: bool, end: bool, out: *mut StrVal) {
    // SAFETY: caller passes a live string and a writable `out`.
    unsafe {
        let (a, b) = trim_range(bytes(s), start, end);
        let view = if a == b {
            // An empty result borrows nothing.
            StrVal::literal((&raw mut EMPTY).cast(), 0)
        } else {
            view_of(bytes(s)[a..b].as_ptr(), b - a)
        };
        view.write_to(out)
    }
}

#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_trim_view(s: *const StrVal, out: *mut StrVal) {
    // SAFETY: forwarded contract.
    unsafe { trim_view(s, true, true, out) }
}

#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_trim_start_view(s: *const StrVal, out: *mut StrVal) {
    // SAFETY: forwarded contract.
    unsafe { trim_view(s, true, false, out) }
}

#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_trim_end_view(s: *const StrVal, out: *mut StrVal) {
    // SAFETY: forwarded contract.
    unsafe { trim_view(s, false, true, out) }
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

/// `trim`, `trim_start` or `trim_end` of a string that dies at the call: the kept bytes move to
/// the front of the same allocation.
///
/// # Safety
/// `s` is an owned string the callee takes; `out` is writable.
unsafe fn trimmed_take(s: *mut StrVal, start: bool, end: bool, out: *mut StrVal) {
    // SAFETY: caller contract.
    unsafe {
        if !(*s).owns() {
            return trimmed(s, start, end).write_to(out);
        }
        let (ptr, ascii) = ((*s).ptr_word, (*s).flagged_ascii());
        let (a, b) = trim_range(bytes(s), start, end);
        if a > 0 && b > a {
            core::ptr::copy(ptr.add(a), ptr, b - a);
        }
        finish_owned(ptr, b - a, ascii).write_to(out)
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
        let r = from_buf(map_case(bytes(s), upper));
        release(&*s);
        r.write_to(out)
    }
}

#[unsafe(no_mangle)]
// ms: leaf fresh takes_self
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
// ms: leaf fresh takes_self
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
// ms: leaf fresh takes_self
pub unsafe extern "C-unwind" fn msrt_string_trim_end(s: *const StrVal, out: *mut StrVal) {
    // SAFETY: caller passes a writable `out` and live arguments.
    unsafe { (msrt_string_trim_end_val(s)).write_to(out) }
}

#[inline(always)]
unsafe fn msrt_string_trim_end_val(s: *const StrVal) -> StrVal {
    // SAFETY: forwarded contract.
    unsafe { trimmed(s, false, true) }
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
    let text = core::str::from_utf8(text).expect("String contains valid UTF-8");
    if upper {
        text.to_uppercase().into_bytes()
    } else {
        // Whole-string mapping supplies Unicode's full Cased and Case_Ignorable tables
        // for the contextual final-sigma rule.
        text.to_lowercase().into_bytes()
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
    unsafe { from_buf(map_case(bytes(s), true)) }
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
    unsafe { from_buf(map_case(bytes(s), false)) }
}

/// `trim` of a string that dies at the call (the optimizer rewrites a call whose receiver
/// drops right after it); same `out` as `msrt_string_trim`.
///
/// # Safety
/// `s` holds an owned string that the callee takes; `out` is writable.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_trim_take(s: *mut StrVal, out: *mut StrVal) {
    // SAFETY: caller contract.
    unsafe { trimmed_take(s, true, true, out) }
}

/// `trim_start` of a string that dies at the call (the optimizer rewrites a call whose receiver
/// drops right after it); same `out` as `msrt_string_trim_start`.
///
/// # Safety
/// `s` holds an owned string that the callee takes; `out` is writable.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_trim_start_take(s: *mut StrVal, out: *mut StrVal) {
    // SAFETY: caller contract.
    unsafe { trimmed_take(s, true, false, out) }
}

/// `trim_end` of a string that dies at the call (the optimizer rewrites a call whose receiver
/// drops right after it); same `out` as `msrt_string_trim_end`.
///
/// # Safety
/// `s` holds an owned string that the callee takes; `out` is writable.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_trim_end_take(s: *mut StrVal, out: *mut StrVal) {
    // SAFETY: caller contract.
    unsafe { trimmed_take(s, false, true, out) }
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

/// `repeat` with `has_max`/`max`; status protocol, ok through `out`.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_repeat(
    s: *const StrVal,
    count: i64,
    has_max: HasRaw,
    max: i64,
    out: *mut StrVal,
) -> u8 {
    // SAFETY: caller passes a live string and a writable out.
    unsafe {
        let limit = if has_max.is_set() { max } else { i64::MAX };
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
        let total = text.len() * count as usize;
        let r = alloc_str(total);
        fill_repeated(r.ptr_word, text, total);
        *out = if is_ascii(&*s) { r.with_ascii() } else { r };
        STATUS_OK
    }
}

/// Fill an uninitialized destination with a whole number of pattern copies.
///
/// # Safety
/// `dst` has `len` writable bytes, `pattern` is nonempty and independent of the
/// destination, and `len` is a multiple of `pattern.len()`.
unsafe fn fill_repeated(dst: *mut u8, pattern: &[u8], len: usize) {
    // SAFETY: each copy reads only initialized bytes strictly before its destination.
    unsafe {
        if len == 0 {
            return;
        }
        if pattern.len() == 1 {
            core::ptr::write_bytes(dst, pattern[0], len);
            return;
        }
        core::ptr::copy_nonoverlapping(pattern.as_ptr(), dst, pattern.len());
        let mut filled = pattern.len();
        while filled < len {
            let n = filled.min(len - filled);
            core::ptr::copy_nonoverlapping(dst, dst.add(filled), n);
            filled += n;
        }
    }
}

fn count_matches(text: &[u8], old: &[u8]) -> usize {
    let mut n = 0;
    let mut i = 0;
    let f = Needle::for_text(old, text.len());
    while let Some(p) = f.find(&text[i..]) {
        n += 1;
        i += p + old.len();
    }
    n
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

/// The result of replacing the first `matches` occurrences of a non-empty `old` (all of them if
/// `matches` is the full count), written straight into one new string.
fn fill_replaced(text: &[u8], old: &[u8], new: &[u8], matches: usize) -> StrVal {
    if matches == 0 {
        return from_bytes(text);
    }
    let len = text.len() - matches * old.len() + matches * new.len();
    if len < 2 {
        // from_bytes shares the empty and one-ASCII-byte strings.
        return from_buf(replace_n_bytes(text, old, new, matches as i64));
    }
    let out = alloc_str(len);
    // SAFETY: `out` has room for `len` bytes, exactly what the loop below writes.
    unsafe {
        let mut dst = out.ptr_word;
        let mut i = 0;
        let f = Needle::for_text(old, text.len());
        for _ in 0..matches {
            let p = f.find(&text[i..]).unwrap_or(0);
            copy_bytes(dst, text[i..].as_ptr(), p);
            dst = dst.add(p);
            copy_bytes(dst, new.as_ptr(), new.len());
            dst = dst.add(new.len());
            i += p + old.len();
        }
        core::ptr::copy_nonoverlapping(text[i..].as_ptr(), dst, text.len() - i);
    }
    if text.is_ascii() && new.is_ascii() {
        out.with_ascii()
    } else {
        out
    }
}

#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_replace_first(
    s: *const StrVal,
    old: *const StrVal,
    new: *const StrVal,
    out: *mut StrVal,
) {
    // SAFETY: caller passes a writable `out` and live arguments.
    unsafe {
        let (text, old, new) = (bytes(s), bytes(old), bytes(new));
        // The empty pattern matches at the first scalar boundary, before any input bytes.
        let at = if old.is_empty() {
            Some(0)
        } else {
            find(text, old)
        };
        let Some(at) = at else {
            return cloned(&*s).write_to(out);
        };
        let Some(total) = (text.len() - old.len()).checked_add(new.len()) else {
            fault::fault(b"string: limit exceeded");
        };
        let mut small = [0u8; STR_INLINE_MAX];
        let heap = (total > STR_INLINE_MAX).then(|| alloc_str(total));
        let start = heap
            .as_ref()
            .map_or(small.as_mut_ptr(), |value| value.ptr_word);
        copy_bytes(start, text.as_ptr(), at);
        copy_bytes(start.add(at), new.as_ptr(), new.len());
        copy_bytes(
            start.add(at + new.len()),
            text[at + old.len()..].as_ptr(),
            text.len() - at - old.len(),
        );
        match heap {
            Some(value) => value,
            None => from_bytes(&small[..total]),
        }
        .write_to(out)
    }
}

/// Replaces every occurrence of a non-empty `old` by a `new` no longer than it, in one search pass: the
/// result cannot exceed the text, so it is written into a text-sized block and trimmed afterwards.
///
/// # Safety
/// `s` is live and `old` is non-empty.
unsafe fn replace_shrinking(s: *const StrVal, old: &[u8], new: &[u8]) -> StrVal {
    // SAFETY: caller passes a live string; the block holds `text.len() + 1` bytes and the loop writes
    // at most `text.len()` of them, since every replacement is no longer than the match it replaces.
    unsafe {
        let text = bytes(s);
        let f = Needle::for_text(old, text.len());
        let Some(first) = f.find(text) else {
            // Nothing to replace: share the unchanged input.
            return cloned(&*s);
        };
        let buf = alloc::alloc(text.len() + 1);
        let mut dst = buf;
        let mut i = 0;
        let mut at = first;
        loop {
            copy_bytes(dst, text[i..].as_ptr(), at);
            dst = dst.add(at);
            copy_bytes(dst, new.as_ptr(), new.len());
            dst = dst.add(new.len());
            i += at + old.len();
            match f.find(&text[i..]) {
                Some(p) => at = p,
                None => break,
            }
        }
        let rest = text.len() - i;
        core::ptr::copy_nonoverlapping(text[i..].as_ptr(), dst, rest);
        let len = dst.add(rest).offset_from(buf) as usize;
        if len < 2 || len <= STR_INLINE_MAX {
            let r = from_bytes(core::slice::from_raw_parts(buf, len));
            alloc::free(buf);
            return r;
        }
        let ptr = alloc::realloc(buf, len + 1);
        *ptr.add(len) = 0;
        StrVal::owned(ptr, len)
    }
}

/// Replaces every nonoverlapping occurrence; output beyond the string limit faults like `concat`.
#[unsafe(no_mangle)]
// ms: leaf fresh takes_self
pub unsafe extern "C-unwind" fn msrt_string_replace(
    s: *const StrVal,
    old: *const StrVal,
    new: *const StrVal,
    out: *mut StrVal,
) {
    // SAFETY: caller passes live strings and a writable out.
    unsafe {
        let (text, o, n) = (bytes(s), bytes(old), bytes(new));
        if !o.is_empty() && n.len() <= o.len() {
            return replace_shrinking(s, o, n).write_to(out);
        }
        let count = if o.is_empty() {
            utf8::count(text) + 1
        } else {
            count_matches(text, o)
        };
        let total = text.len() as i128 + count as i128 * (n.len() as i128 - o.len() as i128);
        if total > MAX_BYTES as i128 {
            fault::fault(b"string: limit exceeded");
        }
        let r = if count == 0 {
            // Nothing to replace: share the unchanged input.
            cloned(&*s)
        } else if o.is_empty() {
            from_buf(replace_n_bytes(text, o, n, -1))
        } else {
            fill_replaced(text, o, n, count)
        };
        r.write_to(out)
    }
}

/// `replace` of a string that dies at the call: a replacement no longer than its match is written
/// over the same allocation, left to right, so the write position never passes the read position.
/// Other replacements build the result as `replace` does and free the input.
///
/// # Safety
/// `s` holds an owned string that the callee takes; `old`, `new` are live and distinct from `s`;
/// `out` is writable.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_replace_take(
    s: *mut StrVal,
    old: *const StrVal,
    new: *const StrVal,
    out: *mut StrVal,
) {
    // SAFETY: caller contract.
    unsafe {
        let (o, n) = (bytes(old), bytes(new));
        if !((*s).owns() && !o.is_empty() && n.len() <= o.len()) {
            msrt_string_replace(s, old, new, out);
            release(&*s);
            return;
        }
        let (ptr, len) = ((*s).ptr_word, (*s).len());
        let ascii = (*s).flagged_ascii() && n.is_ascii();
        let f = Needle::for_text(o, len);
        let (mut r, mut w) = (0usize, 0usize);
        while let Some(p) = f.find(core::slice::from_raw_parts(ptr.add(r), len - r)) {
            core::ptr::copy(ptr.add(r), ptr.add(w), p);
            w += p;
            core::ptr::copy_nonoverlapping(n.as_ptr(), ptr.add(w), n.len());
            w += n.len();
            r += p + o.len();
        }
        if r == 0 {
            // Nothing to replace: the input is the result.
            return (*s).alias().write_to(out);
        }
        core::ptr::copy(ptr.add(r), ptr.add(w), len - r);
        finish_owned(ptr, w + len - r, ascii).write_to(out)
    }
}

/// Pads to `target` scalars with repeated `padding`; a short target or empty padding leaves the text unchanged.
/// Output beyond the string limit faults like `concat`.
unsafe fn pad(
    atstart: bool,
    s: *const StrVal,
    target: i64,
    padding: *const StrVal,
    out: *mut StrVal,
) {
    // SAFETY: caller passes live strings and a writable out.
    unsafe {
        let text = bytes(s);
        let needed = target as i128 - scalar_count(s) as i128;
        let padb = bytes(padding);
        if needed <= 0 || padb.is_empty() {
            return cloned(&*s).write_to(out);
        }
        let needed = needed as usize;
        let pcount = scalar_count(padding);
        let (cycles, rem) = (needed / pcount, needed % pcount);
        let prefix_end = if rem > 0 {
            utf8::offset_of(padb, rem)
        } else {
            0
        };
        let total = text.len() as u128 + cycles as u128 * padb.len() as u128 + prefix_end as u128;
        if total > MAX_BYTES as u128 {
            fault::fault(b"string: limit exceeded");
        }
        let total = total as usize;
        let pad_len = total - text.len();
        // The result is written where it lives: a short one on the stack and then inline, a long
        // one straight into its allocation, with no temporary buffer.
        let write = |dst: *mut u8| {
            let pad_dst = if atstart { dst } else { dst.add(text.len()) };
            if atstart {
                core::ptr::copy_nonoverlapping(text.as_ptr(), dst.add(pad_len), text.len());
            } else {
                core::ptr::copy_nonoverlapping(text.as_ptr(), dst, text.len());
            }
            fill_repeated(pad_dst, padb, cycles * padb.len());
            core::ptr::copy_nonoverlapping(
                padb.as_ptr(),
                pad_dst.add(cycles * padb.len()),
                prefix_end,
            );
        };
        if total <= STR_INLINE_MAX {
            let mut buf = [0u8; STR_INLINE_MAX];
            write(buf.as_mut_ptr());
            return StrVal::inline(&buf[..total]).write_to(out);
        }
        let r = alloc_str(total);
        write(r.ptr_word);
        (if is_ascii(&*s) && is_ascii(&*padding) {
            r.with_ascii()
        } else {
            r
        })
        .write_to(out)
    }
}

#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_pad_start(
    s: *const StrVal,
    target: i64,
    padding: *const StrVal,
    out: *mut StrVal,
) {
    // SAFETY: forwarded contract.
    unsafe { pad(true, s, target, padding, out) }
}

#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_pad_end(
    s: *const StrVal,
    target: i64,
    padding: *const StrVal,
    out: *mut StrVal,
) {
    // SAFETY: forwarded contract.
    unsafe { pad(false, s, target, padding, out) }
}

// ---------------------------------------------------------------------------
// Slicing
// ---------------------------------------------------------------------------

#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_slice_scalars(
    s: *const StrVal,
    start: i64,
    end: i64,
    out: *mut StrVal,
) -> u8 {
    // SAFETY: caller passes a live string and a writable out.
    unsafe {
        if start >= 0 && end >= start && !known_ascii(s) {
            return match walk_sub_scalars(s, start as usize, end as usize) {
                Some(r) => {
                    *out = r;
                    STATUS_OK
                }
                None => STATUS_OUT_OF_RANGE,
            };
        }
        let n = scalar_count(s) as i64;
        if start < 0 || end < start || end > n {
            return STATUS_OUT_OF_RANGE;
        }
        *out = sub_scalars(s, start as usize, end as usize);
        STATUS_OK
    }
}

/// Faults on a negative `count`.
fn check_count(name: &str, count: i64) {
    if count < 0 {
        fault::fault_fmt(format_args!(
            "String.{name}: count must be nonnegative, found {count}"
        ));
    }
}

/// Byte offset after the first `count` scalars, clamped to the end of the text. Walks only that
/// prefix (no whole-string count) unless the string is known to be ASCII, where it is the count.
unsafe fn offset_after(s: *const StrVal, count: usize) -> usize {
    // SAFETY: `s` live.
    unsafe {
        let text = bytes(s);
        if known_ascii(s) {
            return count.min(text.len());
        }
        utf8::advance(text, 0, count).unwrap_or(text.len())
    }
}

/// A copy of `text[a..b]`, sharing nothing; the whole string is cloned when the range covers it.
unsafe fn sub_bytes(s: *const StrVal, a: usize, b: usize) -> StrVal {
    // SAFETY: `s` live; `a <= b <= len`.
    unsafe {
        let text = bytes(s);
        if a == 0 && b == text.len() {
            return cloned(&*s);
        }
        from_bytes(&text[a..b])
    }
}

/// `take(count)`: the first `count` scalars, clamped to the string.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_take(s: *const StrVal, count: i64, out: *mut StrVal) {
    // SAFETY: caller passes a live string and a writable out.
    unsafe {
        check_count("take", count);
        let end = offset_after(s, count as usize);
        *out = sub_bytes(s, 0, end);
    }
}

/// `drop(count)`: the text after the first `count` scalars.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_drop(s: *const StrVal, count: i64, out: *mut StrVal) {
    // SAFETY: caller passes a live string and a writable out.
    unsafe {
        check_count("drop", count);
        let start = offset_after(s, count as usize);
        *out = sub_bytes(s, start, bytes(s).len());
    }
}

#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_slice(
    s: *const StrVal,
    start: i64,
    end: i64,
    out: *mut StrVal,
) -> u8 {
    // SAFETY: caller passes a live string and a writable out.
    unsafe {
        // ASCII text with in-range bounds: a scalar index is a byte index.
        let n = (*s).len();
        if start >= 0
            && end >= start
            && end as u64 <= n as u64
            && (known_ascii(s) || (n <= SHORT_SCAN && is_ascii(&*s)))
        {
            let (a, b) = (start as usize, end as usize);
            *out = if a == 0 && b == n {
                cloned(&*s)
            } else {
                from_bytes(&bytes(s)[a..b])
            };
            return STATUS_OK;
        }
        if start >= 0 && end >= start && !known_ascii(s) {
            return match walk_sub_scalars(s, start as usize, end as usize) {
                Some(r) => {
                    *out = r;
                    STATUS_OK
                }
                None => STATUS_OUT_OF_RANGE,
            };
        }
        if (start < 0 || end < 0) && !known_ascii(s) {
            // A bound from the end walks back from the end, one from the start walks forward; offsets
            // grow with scalar positions, so `a <= b` is the same check on bytes.
            let text = bytes(s);
            let offset = |bound: i64| {
                if bound < 0 {
                    utf8::retreat(text, text.len(), bound.unsigned_abs() as usize)
                } else {
                    utf8::advance(text, 0, bound as usize)
                }
            };
            return match (offset(start), offset(end)) {
                (Some(a), Some(b)) if a <= b => {
                    *out = sub_bytes(s, a, b);
                    STATUS_OK
                }
                _ => STATUS_OUT_OF_RANGE,
            };
        }
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

/// The byte range of scalars `[start, end)` with the bounds of `slice` (negative bounds count from
/// the end); `None` when they fall outside `0 <= start <= end <= scalar length`.
unsafe fn scalar_range(s: *const StrVal, start: i64, end: i64) -> Option<(usize, usize)> {
    // SAFETY: caller passes a live string.
    unsafe {
        let text = bytes(s);
        if (*s).flagged_ascii() {
            let n = text.len() as i64;
            let (a, b) = (
                if start < 0 { n + start } else { start },
                if end < 0 { n + end } else { end },
            );
            return (a >= 0 && b >= a && b <= n).then_some((a as usize, b as usize));
        }
        // Offsets grow with scalar positions, so `a <= b` on bytes is the same check on scalars.
        let offset = |bound: i64| {
            if bound < 0 {
                utf8::retreat(text, text.len(), bound.unsigned_abs() as usize)
            } else {
                utf8::advance(text, 0, bound as usize)
            }
        };
        let (a, b) = (offset(start)?, offset(end)?);
        (a <= b).then_some((a, b))
    }
}

/// `String.view(start, end)`: the scalars `[start, end)` borrowed from the receiver, nothing
/// allocated. Bounds as in `slice`; a bound outside the string faults. Valid while the receiver is
/// neither changed nor dropped (the borrow check guarantees that).
///
/// A flagged-ASCII text with bounds inside it is the whole fast path: scalar bounds are byte
/// offsets, and a short piece is copied inline. Everything else is [`view_general`].
#[unsafe(no_mangle)]
// ms: leaf pure domain=string
pub unsafe extern "C-unwind" fn msrt_string_view(
    s: *const StrVal,
    start: i64,
    end: i64,
    out: *mut StrVal,
) {
    // SAFETY: caller passes a live string and a writable `out`.
    unsafe {
        let sv = &*s;
        if sv.flagged_ascii() && 0 <= start && start <= end && end as usize <= sv.len() {
            let p = sv.ptr_word.add(start as usize);
            return view_of(p, (end - start) as usize).write_to(out);
        }
        view_general(s, start, end, out)
    }
}

/// The view of text not known to be ASCII, of an inline text, or with bounds counted from the end
/// or outside the text (a fault).
#[inline(never)]
unsafe fn view_general(s: *const StrVal, start: i64, end: i64, out: *mut StrVal) {
    // SAFETY: caller passes a live string and a writable `out`.
    unsafe {
        let text = bytes(s);
        let n = text.len() as i64;
        let (a, b) = (
            if start < 0 { n + start } else { start },
            if end < 0 { n + end } else { end },
        );
        if short_ascii(s) && a >= 0 && b >= a && b <= n {
            return view_of(text.as_ptr().add(a as usize), (b - a) as usize).write_to(out);
        }
        let Some((a, b)) = scalar_range(s, start, end) else {
            fault::fault_fmt(format_args!(
                "String.view: bounds {start}..{end} are outside the string"
            ));
        };
        let view = if a == b {
            // An empty result borrows nothing.
            StrVal::literal((&raw mut EMPTY).cast(), 0)
        } else {
            view_of(text[a..b].as_ptr(), b - a)
        };
        view.write_to(out)
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

/// The character that starts at byte `at`, which `for c in text.chars()` reaches for a non-ASCII
/// lead byte (or a stray byte, which reads as U+FFFD): an owned one-character string.
#[unsafe(no_mangle)]
// ms: leaf
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
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_char_width(s: *const StrVal, at: i64) -> i64 {
    // SAFETY: caller passes a live string and an offset inside it.
    unsafe { utf8::decode(&bytes(s)[at as usize..]).1 as i64 }
}

/// The Unicode scalar value of the character that starts at byte `at`.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_scalar_at_byte(s: *const StrVal, at: i64) -> i64 {
    // SAFETY: caller passes a live string and an offset inside it.
    unsafe { utf8::decode(&bytes(s)[at as usize..]).0 as i64 }
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

#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_split(
    s: *const StrVal,
    sep: *const StrVal,
    has_max: HasRaw,
    max: i64,
    out: *mut VecVal,
) {
    // SAFETY: caller passes live strings and a writable out.
    unsafe { split_into(s, sep, has_max, max, out, from_bytes) }
}

/// `let parts = text.split(separator)` where `text` outlives `parts` unchanged and nothing keeps
/// `parts` or its pieces without copying them: the pieces are views of `text`.
#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_split_view(
    s: *const StrVal,
    sep: *const StrVal,
    has_max: HasRaw,
    max: i64,
    out: *mut VecVal,
) {
    // SAFETY: caller passes live strings and a writable out; the pieces borrow `s`.
    unsafe {
        split_into(s, sep, has_max, max, out, |b| match b {
            [] | [0..=0x7f] => from_bytes(b),
            _ => view_of(b.as_ptr(), b.len()),
        })
    }
}

#[inline(always)]
unsafe fn split_into(
    s: *const StrVal,
    sep: *const StrVal,
    has_max: HasRaw,
    max: i64,
    out: *mut VecVal,
    piece: impl Fn(&[u8]) -> StrVal,
) {
    // SAFETY: caller passes live strings and a writable out.
    unsafe {
        let (text, sepb) = (bytes(s), bytes(sep));
        let mut limit = usize::MAX;
        if has_max.is_set() {
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
            // Split after each scalar: the piece count is known, so the list is sized once.
            let n = utf8::count(text).min(limit);
            if n > 0 {
                v.ptr = alloc::alloc(n * ELEM);
                v.cap = n;
            }
            let mut i = 0;
            while i < text.len() && v.len < limit {
                let w = utf8::decode(&text[i..]).1;
                push_str(&mut v, piece(&text[i..i + w]));
                i += w;
            }
            *out = v;
            return;
        }
        // Most splits are of records with several fields: room for eight pieces (never more than
        // the text can hold) saves the grow-and-copy of the usual seven, without sizing a
        // two-piece split for eight.
        let first = (text.len() / sepb.len() + 1).min(limit).min(8);
        v.ptr = alloc::alloc(first * ELEM);
        v.cap = first;
        let mut start = 0;
        let needle = Needle::for_text(sepb, text.len());
        while v.len < limit {
            match needle.find(&text[start..]) {
                Some(p) => {
                    push_str(&mut v, piece(&text[start..start + p]));
                    start += p + sepb.len();
                }
                None => {
                    push_str(&mut v, piece(&text[start..]));
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
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_string_split_iter(
    s: *const StrVal,
    sep: *const StrVal,
    has_max: HasRaw,
    max: i64,
) -> *mut SplitIter {
    // SAFETY: caller passes live strings.
    unsafe {
        let mut left = usize::MAX;
        if has_max.is_set() {
            if max < 0 {
                fault::fault_fmt(format_args!(
                    "split: max_parts must be nonnegative, found {max}"
                ));
            }
            left = max as usize;
        }
        let it = obj::new_obj(core::mem::size_of::<SplitIter>(), None, split_iter_drop)
            as *mut SplitIter;
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
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_int_to_string(v: i64, out: *mut StrVal) {
    // SAFETY: caller passes a writable `out` and live arguments.
    unsafe { (msrt_int_to_string_val(v)).write_to(out) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_uint_to_string(v: i64, out: *mut StrVal) {
    let mut tmp = [0u8; 20];
    // SAFETY: caller passes a writable `out`.
    unsafe { from_bytes(crate::num::format_u64(v as u64, &mut tmp)).write_to(out) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_uint_to_string_radix(v: i64, radix: i64, out: *mut StrVal) {
    if !(2..=36).contains(&radix) {
        fault::fault_fmt(format_args!(
            "to_string_radix: radix must be between 2 and 36, found {radix}"
        ));
    }
    let mut b = Vec::new();
    crate::num::format_radix_u64(v as u64, radix as u32, &mut b);
    // SAFETY: caller passes a writable `out`.
    unsafe { from_buf(b).write_to(out) }
}

unsafe fn msrt_int_to_string_val(v: i64) -> StrVal {
    let mut tmp = [0u8; 20];
    from_bytes(crate::num::format_i64(v, &mut tmp))
}

#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_float32_to_string(v: f64, out: *mut StrVal) {
    // SAFETY: caller passes a writable `out` and live arguments.
    unsafe { from_buf(crate::num::float32_to_string(v)).write_to(out) }
}

#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_float_to_string(v: f64, out: *mut StrVal) {
    // SAFETY: caller passes a writable `out` and live arguments.
    unsafe { (msrt_float_to_string_val(v)).write_to(out) }
}

unsafe fn msrt_float_to_string_val(v: f64) -> StrVal {
    from_buf(crate::num::float_to_string(v))
}

#[unsafe(no_mangle)]
// ms: leaf
pub unsafe extern "C-unwind" fn msrt_bool_to_string(v: u8, out: *mut StrVal) {
    // SAFETY: caller passes a writable `out` and live arguments.
    unsafe { (msrt_bool_to_string_val(v)).write_to(out) }
}

unsafe fn msrt_bool_to_string_val(v: u8) -> StrVal {
    from_bytes(if v != 0 { b"true" } else { b"false" })
}

#[unsafe(no_mangle)]
// ms: leaf
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
/// Deep copies the runtime performed, `[list copies, list bytes, string clones, string bytes]` (the `stats` runtime).
    pub static COPY_COUNTS: [u64; 4] = [0; 4];
}
/// Records one deep copy of `kind` (0 list, 1 string) moving `bytes` bytes.
#[cfg(feature = "stats")]
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
    fn short_searches_agree_with_a_naive_scan() {
        let naive = |h: &[u8], n: &[u8]| {
            (0..=h.len().saturating_sub(n.len())).find(|&i| h[i..].starts_with(n))
        };
        let hay = b"a,bb,,ccc,a,bb\x80,,ccc,a,bb,,ccc,x";
        for len in 0..hay.len() {
            let h = &hay[..len];
            for n in [
                &b","[..],
                b"bb",
                b",,c",
                b"x",
                b"\x80",
                b"zz",
                b"ccc,a,bb\x80,,c",
            ] {
                let want = if n.len() > h.len() { None } else { naive(h, n) };
                assert_eq!(find(h, n), want, "find {n:?} in {h:?}");
                assert_eq!(Needle::new(n).find(h), want, "needle {n:?} in {h:?}");
                assert_eq!(
                    Needle::for_text(n, h.len()).find(h),
                    want,
                    "for_text needle {n:?} in {h:?}"
                );
            }
        }
    }

    #[test]
    fn slicing_inline_ascii_and_non_ascii_by_scalars() {
        let _g = crate::testutil::lock();
        // SAFETY: the strings are live for the whole test.
        unsafe {
            for (text, a, b, want) in [
                ("Rent,133.47", 5, 11, Some("133.47")),
                ("Rent,133.47", 0, 11, Some("Rent,133.47")),
                ("Rent,133.47", 5, 12, None),
                ("café,1", 3, 4, Some("é")),
                ("café,1", 4, 6, Some(",1")),
            ] {
                let s = from_bytes(text.as_bytes());
                let mut out = empty();
                let status = msrt_string_slice_scalars(&s, a, b, &mut out);
                match want {
                    Some(w) => {
                        assert_eq!(status, STATUS_OK, "{text:?}[{a}..{b}]");
                        assert_eq!(bytes(&out), w.as_bytes());
                    }
                    None => assert_eq!(status, STATUS_OUT_OF_RANGE),
                }
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
    fn needle_find_matches_a_naive_search_near_the_window_edge() {
        let mut seed = 0x9e37_79b9_7f4a_7c15u64;
        let mut next = || {
            seed ^= seed << 13;
            seed ^= seed >> 7;
            seed ^= seed << 17;
            seed
        };
        for len in 0..80usize {
            for nlen in 1..=5usize {
                for _ in 0..20 {
                    let hay: Vec<u8> = (0..len).map(|_| b'a' + (next() % 3) as u8).collect();
                    let needle: Vec<u8> = (0..nlen).map(|_| b'a' + (next() % 3) as u8).collect();
                    let naive = hay.windows(nlen).position(|w| w == &needle[..]);
                    assert_eq!(Needle::new(&needle).find(&hay), naive, "{hay:?} {needle:?}");
                }
            }
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
            msrt_string_split_view(&s, &sep, HasRaw(0), 0, &mut views);
            let mut copies = EMPTY_VEC;
            msrt_string_split(&s, &sep, HasRaw(0), 0, &mut copies);
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
    fn ascii_flag_follows_construction() {
        let _g = crate::testutil::lock();
        unsafe {
            let long = "abcdefghijklmnopqrstuvwxyz";
            let a = from_bytes(long.as_bytes());
            assert!(a.flagged_ascii());
            let u = from_bytes("abcdefghijklmnopqrstuvwxyé".as_bytes());
            assert!(!u.flagged_ascii());
            assert_eq!(scalar_count(&u), 26);
            // concatenation keeps the flag only when both sides are ASCII
            let c = msrt_string_concat_val(&a, &a);
            assert!(c.flagged_ascii() && scalar_count(&c) == 52);
            let d = msrt_string_concat_val(&a, &u);
            assert!(!d.flagged_ascii() && scalar_count(&d) == 52);
            // equal strings may differ in the flag
            let lit = StrVal::literal(long.as_ptr().cast_mut(), long.len());
            assert!(equal(&a, &lit));
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
    fn walking_index_and_slice_match_scalar_lists() {
        let _g = testutil::lock();
        let texts = [
            "",
            "héllo",
            "ascii only text longer than fifteen",
            "日本語のテキスト、長い文字列です。",
            "a😀b😀c😀d😀e😀f😀g😀h😀i",
        ];
        for text in texts {
            let chars: std::vec::Vec<S> = text.chars().map(S::from).collect();
            let n = chars.len() as i64;
            for i in 0..n + 2 {
                let mut o = NO_STR;
                let want_ok = i < n;
                // SAFETY: `st` creates live strings and `o` is writable.
                let got = unsafe { msrt_string_slice(st(text), i, (i + 1).min(n + 1), &mut o) };
                let ok = i < n;
                assert_eq!(got == STATUS_OK, ok, "slice {text:?} {i}");
                if want_ok {
                    assert_eq!(txt(&o), chars[i as usize]);
                    // SAFETY: as above.
                    let g =
                        unsafe { ret(|out| msrt_string_get(st(text), i, HasRaw(1), &NO_STR, out)) };
                    assert_eq!(g, chars[i as usize]);
                }
                for j in i..n + 2 {
                    let mut o = NO_STR;
                    // SAFETY: as above.
                    let got = unsafe { msrt_string_slice_scalars(st(text), i, j, &mut o) };
                    if j <= n {
                        assert_eq!(got, STATUS_OK, "{text:?} {i}..{j}");
                        assert_eq!(txt(&o), chars[i as usize..j as usize].concat());
                    } else {
                        assert_eq!(got, STATUS_OUT_OF_RANGE, "{text:?} {i}..{j}");
                    }
                }
            }
        }
    }

    #[test]
    fn length_and_get_follow_scalars() {
        let _g = testutil::lock();
        unsafe {
            let s = st("héllo");
            assert_eq!(msrt_string_length(s), 5);
            assert_eq!((*s).len() as i64, 6);
            assert_eq!(ret(|o| msrt_string_get(s, 1, HasRaw(0), st(""), o)), "é");
            assert_eq!(ret(|o| msrt_string_get(s, -1, HasRaw(0), st(""), o)), "o");
            assert_eq!(msrt_string_scalar_at(s, 1, HasRaw(0), 0), 0xE9);
            testutil::assert_fault(
                "index 9 out of range for length 5; pass a default: get(index:, default: ...)",
                || {
                    ret(|o| msrt_string_get(s, 9, HasRaw(0), st(""), o));
                },
            );
        }
    }

    #[test]
    fn split_replace_trim() {
        let _g = testutil::lock();
        unsafe {
            let mut v = EMPTY_VEC;
            msrt_string_split(st("a,b,c"), st(","), HasRaw(1), 2, &mut v);
            assert_eq!(list(v), ["a", "b"]);
            msrt_string_split(st("héy"), st(""), HasRaw(0), 0, &mut v);
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
            assert_eq!(
                map_case(before.as_bytes(), false),
                std::format!("a{mark}ς").as_bytes()
            );
            assert_eq!(
                map_case(after.as_bytes(), false),
                std::format!("aσ{mark}a").as_bytes()
            );
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
    fn repeat_and_pad_fill_patterns_across_doubling_boundaries() {
        let _g = testutil::lock();
        unsafe {
            for pattern in ["x", "ab", "é🙂", "abcd123"] {
                for count in [0, 1, 2, 3, 5, 9, 17, 257] {
                    let mut out = NO_STR;
                    assert_eq!(
                        msrt_string_repeat(st(pattern), count, HasRaw(0), 0, &mut out),
                        STATUS_OK
                    );
                    assert_eq!(txt(&out), pattern.repeat(count as usize));
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
            let mut out = NO_STR;
            assert_eq!(
                msrt_string_repeat(st("ab"), -1, HasRaw(0), 0, &mut out),
                STATUS_INVALID_INPUT
            );
            assert_eq!(
                msrt_string_repeat(st("ab"), 3, HasRaw(1), 5, &mut out),
                STATUS_LIMIT_EXCEEDED
            );
            assert_eq!(
                msrt_string_repeat(st(""), 3, HasRaw(1), 0, &mut out),
                STATUS_OK
            );
            assert_eq!(txt(&out), "");
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
