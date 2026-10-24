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
    Obj, STATUS_INVALID_INPUT, STATUS_LIMIT_EXCEEDED, STATUS_OK, STATUS_OUT_OF_RANGE,
    STR_INLINE_MAX, STR_LEN_MASK, StrVal, VecVal,
};
pub use ms_rt_hot::{bytes, bytes_eq, equal, hash_bytes, hash_int, mix};

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

/// Writes a copy of the owned string or view `{ptr, tagged}` to `out`: inline when it fits, so
/// copying a short string allocates nothing (what compiled code calls to copy a string).
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_str_copy(ptr: *const u8, tagged: usize, out: *mut StrVal) {
    // SAFETY: an owned string or a view has `len` readable bytes at `ptr`.
    unsafe { owned_copy(core::slice::from_raw_parts(ptr, tagged & STR_LEN_MASK)).write_to(out) }
}

/// Frees an owned string.
#[unsafe(no_mangle)]
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
    s
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
pub unsafe extern "C-unwind" fn msrt_string_empty(out: *mut StrVal) {
    // SAFETY: caller passes a writable out.
    unsafe { (empty()).write_to(out) }
}

fn ascii_char(b: u8) -> StrVal {
    // SAFETY: as above.
    unsafe { StrVal::literal(core::ptr::addr_of_mut!(ASCII[b as usize]) as *mut u8, 1) }
}

/// New string from bytes (owned, rc 1). Short ASCII and empty results are the shared statics.
pub fn from_bytes(data: &[u8]) -> StrVal {
    match data.len() {
        0 => return empty(),
        1 if data[0] < 0x80 => return ascii_char(data[0]),
        _ => {}
    }
    owned_copy(data)
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
        if (*s).is_inline() {
            // ASCII when no byte has its top bit (the bytes past the length are zero).
            if (*s).inline_bits() & 0x8080_8080_8080_8080_8080_8080_8080_8080 == 0 {
                return (*s).len();
            }
            return utf8::count(bytes(s));
        }
        let b = bytes(s);
        if b.len() < HINT_MIN || !(*s).owns() {
            return utf8::count(b);
        }
        let h = HINT.ptr();
        if core::ptr::eq((*h).s, (*s).ptr_word) && (*h).len == b.len() && (*h).count != usize::MAX {
            return (*h).count;
        }
        let n = utf8::count(b);
        *h = Hint {
            s: (*s).ptr_word,
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
const HINT_MIN: usize = 24;

/// Byte offset of scalar `n` (0..=count) with a remembered position for sequential access.
unsafe fn scalar_offset(s: *const StrVal, n: usize) -> usize {
    // SAFETY: `s` live; the hint is cleared when its string dies.
    unsafe {
        let b = bytes(s);
        if b.len() < HINT_MIN || !(*s).owns() {
            return utf8::offset_of(b, n);
        }
        let h = HINT.ptr();
        let (mut sc, mut off) = (0usize, 0usize);
        if std::ptr::eq((*h).s, (*s).ptr_word) && (*h).scalar.abs_diff(n) < n {
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
        if !core::ptr::eq((*h).s, (*s).ptr_word) || (*h).len != b.len() {
            (*h).count = usize::MAX;
        }
        (*h).s = (*s).ptr_word;
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
        if n == text.len() {
            return text[i] as i64;
        }
        utf8::decode(&text[scalar_offset(s, i)..]).0 as i64
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
    if hay.len() < SHORT_HAY {
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
    Bytes(memchr::memmem::Finder<'a>),
}

impl<'a> Needle<'a> {
    fn new(needle: &'a [u8]) -> Self {
        match needle {
            [b] => Needle::Byte(*b),
            _ => Needle::Bytes(memchr::memmem::Finder::new(needle)),
        }
    }

    #[inline]
    fn find(&self, hay: &[u8]) -> Option<usize> {
        match self {
            Needle::Byte(b) if hay.len() < SHORT_HAY => memchr_short(*b, hay),
            Needle::Byte(b) => memchr(*b, hay),
            Needle::Bytes(f) if hay.len() < SHORT_HAY => find_short(hay, f.needle()),
            Needle::Bytes(f) => f.find(hay),
        }
    }
}

/// Haystacks shorter than this are scanned byte by byte: the vector searchers' setup costs more
/// than the scan.
const SHORT_HAY: usize = 32;

/// `find` for a short haystack and a non-empty needle.
#[inline]
fn find_short(hay: &[u8], needle: &[u8]) -> Option<usize> {
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
fn memchr_short(c: u8, hay: &[u8]) -> Option<usize> {
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

/// `a + b` that consumes `a`: an owned `a` grows in place, so `s = s + piece` in a loop reuses
/// one allocation instead of copying the prefix every time.
///
/// # Safety
/// `a` is owned by the caller and dead after the call; `b` is live; `out` is writable.
#[unsafe(no_mangle)]
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
        let h = HINT.ptr();
        if core::ptr::eq((*h).s, sa.ptr_word) {
            (*h).s = core::ptr::null();
        }
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
        StrVal::owned(p, la + lb).write_to(out)
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
        s
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
pub unsafe extern "C-unwind" fn msrt_string_trim_view(s: *const StrVal, out: *mut StrVal) {
    // SAFETY: forwarded contract.
    unsafe { trim_view(s, true, true, out) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_trim_start_view(s: *const StrVal, out: *mut StrVal) {
    // SAFETY: forwarded contract.
    unsafe { trim_view(s, true, false, out) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_trim_end_view(s: *const StrVal, out: *mut StrVal) {
    // SAFETY: forwarded contract.
    unsafe { trim_view(s, false, true, out) }
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
        let d = r.ptr_word;
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
    let f = Needle::new(old);
    while let Some(p) = f.find(&text[i..]) {
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
        let n = n.min(bound);
        if o.is_empty() {
            return from_buf(replace_n_bytes(text, o, bytes(new), n));
        }
        if n == 0 || find(text, o).is_none() {
            // Nothing to replace: share the unchanged input.
            return cloned(&*s);
        }
        replace_into_str(text, o, bytes(new), n)
    }
}

/// `replace_n_bytes` for a non-empty `old`, written straight into the result string: one allocation,
/// and an unchanged text is a plain copy.
fn replace_into_str(text: &[u8], old: &[u8], new: &[u8], n: i64) -> StrVal {
    let mut matches = 0usize;
    let mut i = 0;
    let f = Needle::new(old);
    while (matches as i64) < n {
        match f.find(&text[i..]) {
            None => break,
            Some(p) => {
                i += p + old.len();
                matches += 1;
            }
        }
    }
    fill_replaced(text, old, new, matches)
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
        let f = Needle::new(old);
        for _ in 0..matches {
            let p = f.find(&text[i..]).unwrap_or(0);
            core::ptr::copy_nonoverlapping(text[i..].as_ptr(), dst, p);
            dst = dst.add(p);
            core::ptr::copy_nonoverlapping(new.as_ptr(), dst, new.len());
            dst = dst.add(new.len());
            i += p + old.len();
        }
        core::ptr::copy_nonoverlapping(text[i..].as_ptr(), dst, text.len() - i);
    }
    out
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
        *out = if count == 0 {
            // Nothing to replace: share the unchanged input.
            cloned(&*s)
        } else if o.is_empty() {
            from_buf(replace_n_bytes(text, o, n, -1))
        } else {
            fill_replaced(text, o, n, count)
        };
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

/// Faults on a negative `count`, else clamps it to the scalar length.
unsafe fn scalar_count_arg(name: &str, s: *const StrVal, count: i64) -> usize {
    if count < 0 {
        fault::fault_fmt(format_args!(
            "String.{name}: count must be nonnegative, found {count}"
        ));
    }
    // SAFETY: caller passes a live string.
    (count as usize).min(unsafe { scalar_count(s) })
}

/// `take(count)`: the first `count` scalars, clamped to the string.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_take(s: *const StrVal, count: i64, out: *mut StrVal) {
    // SAFETY: caller passes a live string and a writable out.
    unsafe {
        let n = scalar_count_arg("take", s, count);
        *out = sub_scalars(s, 0, n);
    }
}

/// `drop(count)` (named `drop_n` because `msrt_string_drop` releases a value).
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_drop_n(s: *const StrVal, count: i64, out: *mut StrVal) {
    // SAFETY: caller passes a live string and a writable out.
    unsafe {
        let n = scalar_count_arg("drop", s, count);
        *out = sub_scalars(s, n, scalar_count(s));
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

/// The Unicode scalar value of the character that starts at byte `at`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_scalar_at_byte(s: *const StrVal, at: i64) -> i64 {
    // SAFETY: caller passes a live string and an offset inside it.
    unsafe { utf8::decode(&bytes(s)[at as usize..]).0 as i64 }
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
    unsafe { split_into(s, sep, has_max, max, out, from_bytes) }
}

/// `let parts = text.split(separator)` where `text` outlives `parts` unchanged and nothing keeps
/// `parts` or its pieces without copying them: the pieces are views of `text`.
#[unsafe(no_mangle)]
pub unsafe extern "C-unwind" fn msrt_string_split_view(
    s: *const StrVal,
    sep: *const StrVal,
    has_max: u8,
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
    has_max: u8,
    max: i64,
    out: *mut VecVal,
    piece: impl Fn(&[u8]) -> StrVal,
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
        let mut start = 0;
        while v.len < limit {
            match find(&text[start..], sepb) {
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
        if st.cap >= piece.len() && !st.cur.ptr_word.is_null() && st.cur.owns() {
            // The loop only borrows the piece: rewrite it in place.
            let h = HINT.ptr();
            if core::ptr::eq((*h).s, st.cur.ptr_word) {
                (*h).s = core::ptr::null();
            }
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
    unsafe { (*STR_COUNTS.ptr())[(kind as usize) * 2 + (cap >= 0) as usize] += 1 };
}

#[cfg(test)]
mod tests {
    use super::*;

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
    fn split_view_pieces_borrow_the_source() {
        let _g = crate::testutil::lock();
        unsafe {
            let s = from_bytes(b"alpha-is-a-long-piece,b,,gamma\xc3\xa9");
            let sep = from_bytes(b",");
            let mut views = EMPTY_VEC;
            msrt_string_split_view(&s, &sep, 0, 0, &mut views);
            let mut copies = EMPTY_VEC;
            msrt_string_split(&s, &sep, 0, 0, &mut copies);
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
    fn length_and_get_follow_scalars() {
        let _g = testutil::lock();
        unsafe {
            let s = st("héllo");
            assert_eq!(msrt_string_length(s), 5);
            assert_eq!(crate::testutil::hot::msrt_string_byte_length(s), 6);
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
