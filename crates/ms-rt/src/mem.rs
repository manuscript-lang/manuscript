//! Memory routines for Linux musl programs.
//!
//! musl's x86-64 `memcpy` and `memset` begin every call with `rep movsq`/`rep stosq`, which costs
//! tens of cycles before the first byte moves, and its `memcmp`/`bcmp` compare one byte at a time.
//! Programs copy and compare short strings, list tails and records constantly, so these definitions
//! take precedence over libc's: unaligned word moves for small sizes, `rep movsb` (fast on current
//! CPUs) for large forward copies, descending vector blocks for backward copies, and eight
//! bytes per step for comparisons.
//!
//! Copy bodies use explicit SIMD loads/stores or assembly rather than scalar copy loops that
//! LLVM could turn back into calls to the function being defined.

use core::ffi::c_int;
#[cfg(not(test))]
use core::ffi::c_void;

/// Copies `n` bytes; `dst` and `src` may overlap only if `n <= 64` (all loads precede all stores).
///
/// # Safety
/// Both ranges must be valid for `n` bytes.
#[cfg(target_arch = "x86_64")]
#[inline(always)]
unsafe fn copy_small(dst: *mut u8, src: *const u8, n: usize) {
    use core::arch::x86_64::{__m128i, _mm_loadu_si128, _mm_storeu_si128};
    // SAFETY: each branch reads and writes only within the first and last `k` bytes, `k <= n`.
    unsafe {
        if n >= 16 {
            let load = |at: usize| _mm_loadu_si128(src.add(at) as *const __m128i);
            let store = |at: usize, v: __m128i| _mm_storeu_si128(dst.add(at) as *mut __m128i, v);
            if n <= 32 {
                let (a, b) = (load(0), load(n - 16));
                store(0, a);
                store(n - 16, b);
            } else {
                let (a, b, c, d) = (load(0), load(16), load(n - 32), load(n - 16));
                store(0, a);
                store(16, b);
                store(n - 32, c);
                store(n - 16, d);
            }
        } else if n >= 8 {
            let (a, b) = (
                (src as *const u64).read_unaligned(),
                (src.add(n - 8) as *const u64).read_unaligned(),
            );
            (dst as *mut u64).write_unaligned(a);
            (dst.add(n - 8) as *mut u64).write_unaligned(b);
        } else if n >= 4 {
            let (a, b) = (
                (src as *const u32).read_unaligned(),
                (src.add(n - 4) as *const u32).read_unaligned(),
            );
            (dst as *mut u32).write_unaligned(a);
            (dst.add(n - 4) as *mut u32).write_unaligned(b);
        } else if n >= 2 {
            let (a, b) = (
                (src as *const u16).read_unaligned(),
                (src.add(n - 2) as *const u16).read_unaligned(),
            );
            (dst as *mut u16).write_unaligned(a);
            (dst.add(n - 2) as *mut u16).write_unaligned(b);
        } else if n == 1 {
            *dst = *src;
        }
    }
}

/// Copies forward with `rep movsb`.
///
/// # Safety
/// Both ranges must be valid for `n` bytes, and `dst` must not lie inside `(src, src + n)`.
#[cfg(target_arch = "x86_64")]
#[inline(always)]
unsafe fn copy_forward(dst: *mut u8, src: *const u8, n: usize) {
    // SAFETY: the caller guarantees the ranges; the instruction reads `n` bytes and writes `n`.
    unsafe {
        core::arch::asm!(
            "rep movsb",
            inout("rcx") n => _,
            inout("rdi") dst => _,
            inout("rsi") src => _,
            options(nostack, preserves_flags)
        );
    }
}

/// Largest forward copy done with vector blocks; `rep movsb` pays a startup cost that only a
/// longer copy amortises (glibc switches at about the same size).
#[cfg(target_arch = "x86_64")]
const REP_MOVSB_MIN: usize = 2048;

/// Copies `64 < n` bytes forward in 64-byte blocks. The last 64 bytes are loaded up front and
/// stored at the end, so the tail needs no byte loop. Safe when `dst <= src` overlaps, because
/// every block loads before it stores and the stores never reach the tail's source.
///
/// # Safety
/// Both ranges must be valid for `n > 64` bytes, and `dst` must not lie inside `(src, src + n)`.
#[cfg(target_arch = "x86_64")]
#[inline(always)]
unsafe fn copy_blocks(dst: *mut u8, src: *const u8, n: usize) {
    use core::arch::x86_64::{__m128i, _mm_loadu_si128, _mm_storeu_si128};
    // SAFETY: every block lies within the first `n` bytes of both ranges.
    unsafe {
        let load = |at: usize| _mm_loadu_si128(src.add(at) as *const __m128i);
        let store = |at: usize, v: __m128i| _mm_storeu_si128(dst.add(at) as *mut __m128i, v);
        let tail = [load(n - 64), load(n - 48), load(n - 32), load(n - 16)];
        let mut at = 0;
        while at + 64 < n {
            let (a, b, c, d) = (load(at), load(at + 16), load(at + 32), load(at + 48));
            store(at, a);
            store(at + 16, b);
            store(at + 32, c);
            store(at + 48, d);
            at += 64;
        }
        store(n - 64, tail[0]);
        store(n - 48, tail[1]);
        store(n - 32, tail[2]);
        store(n - 16, tail[3]);
    }
}

/// [`copy_blocks`] with 32-byte registers: half the loads and stores per block.
///
/// # Safety
/// As [`copy_blocks`], and the CPU must support AVX2.
#[cfg(target_arch = "x86_64")]
#[target_feature(enable = "avx2")]
unsafe fn copy_blocks_avx2(dst: *mut u8, src: *const u8, n: usize) {
    use core::arch::x86_64::{__m256i, _mm256_loadu_si256, _mm256_storeu_si256};
    // SAFETY: every block lies within the first `n` bytes of both ranges.
    unsafe {
        let load = |at: usize| _mm256_loadu_si256(src.add(at) as *const __m256i);
        let store = |at: usize, v: __m256i| _mm256_storeu_si256(dst.add(at) as *mut __m256i, v);
        let tail = [load(n - 64), load(n - 32)];
        let mut at = 0;
        while at + 64 < n {
            let (a, b) = (load(at), load(at + 32));
            store(at, a);
            store(at + 32, b);
            at += 64;
        }
        store(n - 64, tail[0]);
        store(n - 32, tail[1]);
    }
}

/// Whether this CPU runs AVX2 (and the OS saves its registers), probed once.
#[cfg(target_arch = "x86_64")]
#[inline(always)]
fn has_avx2() -> bool {
    use core::sync::atomic::{AtomicU8, Ordering};
    static STATE: AtomicU8 = AtomicU8::new(0);
    let state = STATE.load(Ordering::Relaxed);
    if state != 0 {
        return state == 2;
    }
    let yes = probe_avx2();
    STATE.store(if yes { 2 } else { 1 }, Ordering::Relaxed);
    yes
}

#[cfg(target_arch = "x86_64")]
#[cold]
fn probe_avx2() -> bool {
    use core::arch::x86_64::{__cpuid, __cpuid_count, _xgetbv};
    // SAFETY: cpuid exists on every x86_64 CPU; xgetbv is read only after OSXSAVE is reported.
    unsafe {
        if __cpuid(0).eax < 7 {
            return false;
        }
        let l1 = __cpuid(1);
        let osxsave = l1.ecx & (1 << 27) != 0;
        let avx = l1.ecx & (1 << 28) != 0;
        if !osxsave || !avx || _xgetbv(0) & 6 != 6 {
            return false;
        }
        __cpuid_count(7, 0).ebx & (1 << 5) != 0
    }
}

/// Copies forward: vector blocks for a medium size, `rep movsb` beyond.
///
/// # Safety
/// As [`copy_blocks`], for any `n > 64`.
#[cfg(target_arch = "x86_64")]
#[cfg_attr(test, allow(dead_code))]
#[inline(always)]
unsafe fn copy_forward_any(dst: *mut u8, src: *const u8, n: usize) {
    // SAFETY: forwarded contract.
    unsafe {
        if n < REP_MOVSB_MIN {
            if has_avx2() {
                copy_blocks_avx2(dst, src, n);
            } else {
                copy_blocks(dst, src, n);
            }
        } else {
            copy_forward(dst, src, n);
        }
    }
}

/// Copies backward in blocks whose loads all precede their stores.
///
/// # Safety
/// Both ranges must be valid for `n` bytes. They may overlap only when `dst >= src`.
#[cfg(target_arch = "x86_64")]
#[inline(always)]
unsafe fn copy_backward(dst: *mut u8, src: *const u8, mut n: usize) {
    // SAFETY: each block lies within the original ranges. Its stores cannot overwrite
    // the lower source prefix still to be read; copy_small handles overlap within a block.
    unsafe {
        while n > 64 {
            n -= 64;
            copy_small(dst.add(n), src.add(n), 64);
        }
        copy_small(dst, src, n);
    }
}

/// The C `memcpy`.
///
/// # Safety
/// As in C: valid, non-overlapping ranges.
#[cfg(all(
    not(test),
    target_os = "linux",
    target_env = "musl",
    target_arch = "x86_64"
))]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn memcpy(dst: *mut c_void, src: *const c_void, n: usize) -> *mut c_void {
    // SAFETY: the C contract gives valid, disjoint ranges.
    unsafe {
        if n <= 64 {
            copy_small(dst.cast(), src.cast(), n);
        } else {
            copy_forward_any(dst.cast(), src.cast(), n);
        }
    }
    dst
}

/// The C `memmove`.
///
/// # Safety
/// As in C: valid ranges, which may overlap.
#[cfg(all(
    not(test),
    target_os = "linux",
    target_env = "musl",
    target_arch = "x86_64"
))]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn memmove(dst: *mut c_void, src: *const c_void, n: usize) -> *mut c_void {
    // SAFETY: the C contract gives valid ranges; each branch handles the overlap it can meet.
    unsafe {
        let (d, s): (*mut u8, *const u8) = (dst.cast(), src.cast());
        if n <= 64 {
            copy_small(d, s, n);
        } else if (d as usize).wrapping_sub(s as usize) >= n {
            // `dst` is below `src` or past its end: copying forward never overwrites unread bytes.
            copy_forward_any(d, s, n);
        } else {
            copy_backward(d, s, n);
        }
    }
    dst
}

/// The C `memset`.
///
/// # Safety
/// As in C: a valid range.
#[cfg(all(
    not(test),
    target_os = "linux",
    target_env = "musl",
    target_arch = "x86_64"
))]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn memset(dst: *mut c_void, c: c_int, n: usize) -> *mut c_void {
    // SAFETY: the C contract gives a valid range; each branch stays within the first and last `k` bytes.
    unsafe {
        let d: *mut u8 = dst.cast();
        use core::arch::x86_64::{__m128i, _mm_set1_epi8, _mm_storeu_si128};
        let byte = c as u8;
        if n > 64 {
            core::arch::asm!(
                "rep stosb",
                inout("rcx") n => _,
                inout("rdi") d => _,
                in("al") byte,
                options(nostack, preserves_flags)
            );
        } else if n >= 16 {
            let v = _mm_set1_epi8(byte as i8);
            let store = |at: usize| _mm_storeu_si128(d.add(at) as *mut __m128i, v);
            if n <= 32 {
                store(0);
                store(n - 16);
            } else {
                store(0);
                store(16);
                store(n - 32);
                store(n - 16);
            }
        } else if n >= 8 {
            let w = u64::from(byte) * 0x0101_0101_0101_0101;
            (d as *mut u64).write_unaligned(w);
            (d.add(n - 8) as *mut u64).write_unaligned(w);
        } else if n >= 4 {
            let w = u32::from(byte) * 0x0101_0101;
            (d as *mut u32).write_unaligned(w);
            (d.add(n - 4) as *mut u32).write_unaligned(w);
        } else if n >= 2 {
            let w = u16::from(byte) * 0x0101;
            (d as *mut u16).write_unaligned(w);
            (d.add(n - 2) as *mut u16).write_unaligned(w);
        } else if n == 1 {
            *d = byte;
        }
    }
    dst
}

/// Orders the first difference between two ranges, like C `memcmp`.
///
/// # Safety
/// Both ranges must be valid for `n` bytes.
#[cfg(any(test, all(target_os = "linux", target_env = "musl")))]
#[inline(always)]
unsafe fn compare(a: *const u8, b: *const u8, n: usize) -> c_int {
    // SAFETY: every read lies inside the first `n` bytes of a range.
    unsafe {
        let mut i = 0;
        while i + 8 <= n {
            let x = (a.add(i) as *const u64).read_unaligned();
            let y = (b.add(i) as *const u64).read_unaligned();
            if x != y {
                // Big-endian order makes the first differing byte the most significant one.
                return if x.swap_bytes() < y.swap_bytes() {
                    -1
                } else {
                    1
                };
            }
            i += 8;
        }
        while i < n {
            let (x, y) = (*a.add(i), *b.add(i));
            if x != y {
                return c_int::from(x) - c_int::from(y);
            }
            i += 1;
        }
        0
    }
}

/// The C `memcmp`.
///
/// # Safety
/// As in C: valid ranges.
#[cfg(all(not(test), target_os = "linux", target_env = "musl"))]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn memcmp(a: *const c_void, b: *const c_void, n: usize) -> c_int {
    // SAFETY: the C contract gives valid ranges.
    unsafe { compare(a.cast(), b.cast(), n) }
}

/// The C `bcmp`: zero when equal, nonzero otherwise.
///
/// # Safety
/// As in C: valid ranges.
#[cfg(all(not(test), target_os = "linux", target_env = "musl"))]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn bcmp(a: *const c_void, b: *const c_void, n: usize) -> c_int {
    // SAFETY: the C contract gives valid ranges.
    unsafe { compare(a.cast(), b.cast(), n) }
}

#[cfg(all(test, target_arch = "x86_64"))]
mod tests {
    use super::*;

    fn pattern(n: usize, seed: u8) -> Vec<u8> {
        (0..n)
            .map(|i| (i as u8).wrapping_mul(31).wrapping_add(seed))
            .collect()
    }

    #[test]
    fn block_copy_matches_slice_copy_and_forward_overlap() {
        // SAFETY: `check_blocks` passes in-bounds ranges.
        check_blocks(|d, s, n| unsafe { copy_blocks(d, s, n) });
        if has_avx2() {
            // SAFETY: the CPU reports AVX2.
            check_blocks(|d, s, n| unsafe { copy_blocks_avx2(d, s, n) });
        }
    }

    fn check_blocks(copy: impl Fn(*mut u8, *const u8, usize)) {
        for n in (65..=300).chain([1023, 2047, 2048, 4097]) {
            let src = pattern(n + 16, 3);
            let mut dst = vec![0xAAu8; n + 16];
            // SAFETY: both buffers hold `n + 16` bytes.
            unsafe { copy(dst.as_mut_ptr().add(5), src.as_ptr().add(2), n) };
            assert_eq!(dst[5..5 + n], src[2..2 + n], "n={n}");
            assert!(dst[..5].iter().all(|b| *b == 0xAA), "head touched n={n}");
            assert!(
                dst[5 + n..].iter().all(|b| *b == 0xAA),
                "tail touched n={n}"
            );
            for gap in [1usize, 7, 16, 63, 64, 65] {
                let mut buf = pattern(n + gap, 9);
                let want = buf[gap..gap + n].to_vec();
                let p = buf.as_mut_ptr();
                // SAFETY: dst < src within one buffer of `n + gap` bytes, a forward overlap.
                unsafe { copy(p, p.add(gap), n) };
                assert_eq!(buf[..n], want[..], "overlap n={n} gap={gap}");
            }
        }
    }

    #[test]
    fn copies_every_small_size_at_every_offset() {
        for n in 0..=130 {
            for off in 0..8 {
                let src = pattern(n + 16, 7);
                let mut dst = vec![0xAAu8; n + 16];
                // SAFETY: both buffers hold `n + 16` bytes.
                unsafe {
                    if n <= 64 {
                        copy_small(dst.as_mut_ptr().add(off), src.as_ptr().add(off), n);
                    } else {
                        copy_forward(dst.as_mut_ptr().add(off), src.as_ptr().add(off), n);
                    }
                }
                assert_eq!(dst[off..off + n], src[off..off + n], "n={n} off={off}");
                assert!(dst[..off].iter().all(|b| *b == 0xAA), "head touched n={n}");
                assert!(
                    dst[off + n..].iter().all(|b| *b == 0xAA),
                    "tail touched n={n}"
                );
            }
        }
    }

    #[test]
    fn small_copies_tolerate_overlap() {
        for n in 0..=64 {
            for shift in 1..40 {
                let mut buf = pattern(200, 3);
                let expected: Vec<u8> = buf[10..10 + n].to_vec();
                // SAFETY: both ranges lie inside the 200-byte buffer.
                unsafe {
                    let p = buf.as_mut_ptr();
                    copy_small(p.add(10 + shift), p.add(10), n);
                }
                assert_eq!(
                    buf[10 + shift..10 + shift + n],
                    expected[..],
                    "n={n} shift={shift}"
                );
            }
        }
    }

    fn check_backward(n: usize, shift: usize, offset: usize, tail: usize) {
        let mut buf: Vec<u8> = (0..offset + shift + n + tail)
            .map(|i| (i.wrapping_mul(31) ^ (i / 251)) as u8)
            .collect();
        let mut expected = buf.clone();
        expected[offset + shift..offset + shift + n].copy_from_slice(&buf[offset..offset + n]);
        // SAFETY: both ranges fit in buf, and the destination is at or above the source.
        unsafe {
            let p = buf.as_mut_ptr();
            copy_backward(p.add(offset + shift), p.add(offset), n);
        }
        assert_eq!(
            buf, expected,
            "n={n} shift={shift} offset={offset} tail={tail}"
        );
    }

    #[test]
    fn backward_copies_match_snapshot_at_every_small_size_and_shift() {
        for n in 0..=130 {
            for shift in 0..=130 {
                for offset in 0..8 {
                    check_backward(n, shift, offset, 17);
                }
            }
        }
    }

    #[test]
    fn backward_copies_match_snapshot_across_large_boundaries() {
        for n in [255, 256, 257, 1023, 1024, 1025, 24576, 73728] {
            for shift in [
                0,
                1,
                7,
                8,
                15,
                16,
                24,
                31,
                32,
                63,
                64,
                65,
                127,
                128,
                n - 1,
                n,
                n + 1,
            ] {
                for offset in [0, 1, 7] {
                    // Include exact-sized buffers as well as an untouched tail sentinel.
                    for tail in [0, 17] {
                        check_backward(n, shift, offset, tail);
                    }
                }
            }
        }
    }

    #[test]
    fn compare_matches_the_slice_order() {
        for n in 0..=40 {
            let a = pattern(n, 1);
            let mut b = a.clone();
            // SAFETY: both vectors hold `n` bytes.
            unsafe {
                assert_eq!(compare(a.as_ptr(), b.as_ptr(), n), 0);
                for at in 0..n {
                    for delta in [1u8, 200] {
                        b[at] = a[at].wrapping_add(delta);
                        let got = compare(a.as_ptr(), b.as_ptr(), n);
                        assert_eq!(got.signum(), a.cmp(&b) as i32, "n={n} at={at}");
                        b[at] = a[at];
                    }
                }
            }
        }
    }
}
