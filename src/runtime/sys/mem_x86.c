/* Copy, move, fill and compare routines for x86-64, behind the names ms_mem_*; src/runtime/sys/musl/mem.c exports them as the
 * C library's memcpy, memmove, memset, memcmp and bcmp for Linux musl programs. Ported from crates/ms-rt/src/mem.rs.
 *
 * musl's x86-64 memcpy and memset begin every call with `rep movsq` / `rep stosq`, which costs tens of cycles before
 * the first byte moves, and its memcmp and bcmp compare one byte at a time. Programs copy and compare short strings,
 * list tails and records constantly, so these take precedence: unaligned word moves for small sizes, `rep movsb` (fast on
 * current CPUs) for large forward copies, descending vector blocks for backward copies, eight bytes per step for
 * comparisons. A copy of 33 bytes or more uses 256-bit registers when the CPU has AVX2, chosen once on the first call.
 *
 * Bodies use vector loads and stores or assembly rather than scalar loops the compiler could turn back into calls to
 * the functions defined here; the file is built with -fno-builtin for the same reason. */
#if defined(__x86_64__)

#include <cpuid.h>
#include <immintrin.h>
#include <stddef.h>
#include <stdint.h>

#include "mem_x86.h"

enum {
    SMALL_MAX = 64,         /* the most a copy of loads-then-stores handles, overlap included */
    REP_MOVSB_MIN = 2048,   /* a forward copy below this uses vector blocks: rep movsb pays a startup cost */
    CPUID_LEAF_FEATURES = 1,
    CPUID_LEAF_EXTENDED = 7,
};

#define MS_SSE_LOAD(p) _mm_loadu_si128((const __m128i_u *)(p))
#define MS_SSE_STORE(p, v) _mm_storeu_si128((__m128i_u *)(p), (v))

/* Unaligned loads and stores of a word of 2, 4 or 8 bytes. */
#define MS_WORD_COPY(T, dst, src, n)                                                                                   \
    do {                                                                                                               \
        T head_, tail_;                                                                                                \
        __builtin_memcpy(&head_, (src), sizeof(T));                                                                              \
        __builtin_memcpy(&tail_, (src) + (n) - sizeof(T), sizeof(T));                                                            \
        __builtin_memcpy((dst), &head_, sizeof(T));                                                                              \
        __builtin_memcpy((dst) + (n) - sizeof(T), &tail_, sizeof(T));                                                            \
    } while (0)

/* Copies n <= 64 bytes; all loads precede all stores, so the ranges may overlap. */
static inline __attribute__((always_inline)) void copy_small(uint8_t *dst, const uint8_t *src, size_t n) {
    if (n >= 16) {
        if (n <= 32) {
            const __m128i a = MS_SSE_LOAD(src), b = MS_SSE_LOAD(src + n - 16);
            MS_SSE_STORE(dst, a);
            MS_SSE_STORE(dst + n - 16, b);
        } else {
            const __m128i a = MS_SSE_LOAD(src), b = MS_SSE_LOAD(src + 16), c = MS_SSE_LOAD(src + n - 32), d = MS_SSE_LOAD(src + n - 16);
            MS_SSE_STORE(dst, a);
            MS_SSE_STORE(dst + 16, b);
            MS_SSE_STORE(dst + n - 32, c);
            MS_SSE_STORE(dst + n - 16, d);
        }
    } else if (n >= 8) {
        MS_WORD_COPY(uint64_t, dst, src, n);
    } else if (n >= 4) {
        MS_WORD_COPY(uint32_t, dst, src, n);
    } else if (n >= 2) {
        MS_WORD_COPY(uint16_t, dst, src, n);
    } else if (n == 1) {
        *dst = *src;
    }
}

/* Copies forward with `rep movsb`. dst must not lie inside (src, src + n). */
static inline __attribute__((always_inline)) void copy_rep(uint8_t *dst, const uint8_t *src, size_t n) {
    void *to = dst;
    __asm__ volatile("rep movsb" : "+c"(n), "+D"(to), "+S"(src) : : "memory");
}

/* Copies n > 64 bytes forward in 64-byte blocks. The last 64 bytes are loaded first and stored at the end, so the tail
 * needs no byte loop; safe when dst <= src overlaps, because every block loads before it stores. */
static inline __attribute__((always_inline)) void copy_blocks(uint8_t *dst, const uint8_t *src, size_t n) {
    const __m128i t0 = MS_SSE_LOAD(src + n - 64), t1 = MS_SSE_LOAD(src + n - 48), t2 = MS_SSE_LOAD(src + n - 32),
                  t3 = MS_SSE_LOAD(src + n - 16);
    for (size_t at = 0; at + 64 < n; at += 64) {
        const __m128i a = MS_SSE_LOAD(src + at), b = MS_SSE_LOAD(src + at + 16), c = MS_SSE_LOAD(src + at + 32),
                      d = MS_SSE_LOAD(src + at + 48);
        MS_SSE_STORE(dst + at, a);
        MS_SSE_STORE(dst + at + 16, b);
        MS_SSE_STORE(dst + at + 32, c);
        MS_SSE_STORE(dst + at + 48, d);
    }
    MS_SSE_STORE(dst + n - 64, t0);
    MS_SSE_STORE(dst + n - 48, t1);
    MS_SSE_STORE(dst + n - 32, t2);
    MS_SSE_STORE(dst + n - 16, t3);
}

/* Copies n > 64 bytes forward: vector blocks for a medium size, `rep movsb` beyond. */
static inline __attribute__((always_inline)) void copy_forward(uint8_t *dst, const uint8_t *src, size_t n) {
    if (n < REP_MOVSB_MIN) {
        copy_blocks(dst, src, n);
    } else {
        copy_rep(dst, src, n);
    }
}

/* Copies backward in blocks whose loads all precede their stores; the ranges overlap only when dst >= src. */
static inline __attribute__((always_inline)) void copy_backward(uint8_t *dst, const uint8_t *src, size_t n) {
    while (n > SMALL_MAX) {
        n -= SMALL_MAX;
        copy_small(dst + n, src + n, SMALL_MAX);
    }
    copy_small(dst, src, n);
}

typedef void *(*CopyFn)(void *, const void *, size_t);

/* The copy body for CPUs with AVX2: 32-byte registers halve the loads and stores of a medium copy. */
__attribute__((target("avx2"))) static void *copy_avx2(void *to, const void *from, size_t n) {
    uint8_t *dst = to;
    const uint8_t *src = from;
#define AVX_LOAD(p) _mm256_loadu_si256((const __m256i_u *)(p))
#define AVX_STORE(p, v) _mm256_storeu_si256((__m256i_u *)(p), (v))
    if (n <= SMALL_MAX) {
        if (n > 32) { /* two overlapping 32-byte moves cover 33..=64 bytes */
            const __m256i a = AVX_LOAD(src), b = AVX_LOAD(src + n - 32);
            AVX_STORE(dst, a);
            AVX_STORE(dst + n - 32, b);
        } else {
            copy_small(dst, src, n);
        }
        return to;
    }
    if (n >= REP_MOVSB_MIN) {
        copy_rep(dst, src, n);
        return to;
    }
    if (n <= 128) {
        const __m256i a = AVX_LOAD(src), b = AVX_LOAD(src + 32), c = AVX_LOAD(src + n - 64), d = AVX_LOAD(src + n - 32);
        AVX_STORE(dst, a);
        AVX_STORE(dst + 32, b);
        AVX_STORE(dst + n - 64, c);
        AVX_STORE(dst + n - 32, d);
        return to;
    }
    const __m256i t0 = AVX_LOAD(src + n - 128), t1 = AVX_LOAD(src + n - 96), t2 = AVX_LOAD(src + n - 64),
                  t3 = AVX_LOAD(src + n - 32);
    for (size_t at = 0; at + 128 < n; at += 128) {
        const __m256i a = AVX_LOAD(src + at), b = AVX_LOAD(src + at + 32), c = AVX_LOAD(src + at + 64),
                      d = AVX_LOAD(src + at + 96);
        AVX_STORE(dst + at, a);
        AVX_STORE(dst + at + 32, b);
        AVX_STORE(dst + at + 64, c);
        AVX_STORE(dst + at + 96, d);
    }
    AVX_STORE(dst + n - 128, t0);
    AVX_STORE(dst + n - 96, t1);
    AVX_STORE(dst + n - 64, t2);
    AVX_STORE(dst + n - 32, t3);
    return to;
#undef AVX_LOAD
#undef AVX_STORE
}

/* The copy body for any x86-64 CPU. */
static void *copy_sse(void *to, const void *from, size_t n) {
    if (n <= SMALL_MAX) {
        copy_small(to, from, n);
    } else {
        copy_forward(to, from, n);
    }
    return to;
}

static int has_avx2(void) {
    unsigned eax = 0, ebx = 0, ecx = 0, edx = 0;
    if (!__get_cpuid(0, &eax, &ebx, &ecx, &edx) || eax < CPUID_LEAF_EXTENDED) {
        return 0;
    }
    (void)__get_cpuid(CPUID_LEAF_FEATURES, &eax, &ebx, &ecx, &edx);
    const int osxsave = (int)((ecx >> 27) & 1u), avx = (int)((ecx >> 28) & 1u);
    if (!osxsave || !avx) {
        return 0;
    }
    unsigned xcr_low = 0, xcr_high = 0;
    __asm__ volatile("xgetbv" : "=a"(xcr_low), "=d"(xcr_high) : "c"(0));
    if ((xcr_low & 6) != 6) {
        return 0;
    }
    __cpuid_count(CPUID_LEAF_EXTENDED, 0, eax, ebx, ecx, edx);
    return (int)((ebx >> 5) & 1);
}

static void *copy_probe(void *to, const void *from, size_t n);
static CopyFn copy_impl = copy_probe; /* the body ms_mem_copy jumps to; one pointer, written once per thread race, always valid */

/* The first call: picks the body for this CPU, then runs it. Two threads probing at once both store the same value. */
static void *copy_probe(void *to, const void *from, size_t n) {
    const CopyFn pick = has_avx2() ? copy_avx2 : copy_sse;
    __atomic_store_n(&copy_impl, pick, __ATOMIC_RELAXED);
    return pick(to, from, n);
}

void *ms_mem_copy(void *to, const void *from, size_t n) {
    return __atomic_load_n(&copy_impl, __ATOMIC_RELAXED)(to, from, n);
}

void *ms_mem_move(void *to, const void *from, size_t n) {
    uint8_t *dst = to;
    const uint8_t *src = from;
    if (n <= SMALL_MAX) {
        copy_small(dst, src, n);
    } else if ((uintptr_t)dst - (uintptr_t)src >= n) {
        /* dst is below src or past its end: copying forward never overwrites unread bytes. */
        copy_forward(dst, src, n);
    } else {
        copy_backward(dst, src, n);
    }
    return to;
}

void *ms_mem_set(void *to, int c, size_t n) {
    uint8_t *dst = to;
    const uint8_t byte = (uint8_t)c;
    if (n > SMALL_MAX) {
        void *rdi = dst;
        __asm__ volatile("rep stosb" : "+c"(n), "+D"(rdi) : "a"(byte) : "memory");
    } else if (n >= 16) {
        const __m128i v = _mm_set1_epi8((char)byte);
        MS_SSE_STORE(dst, v);
        if (n > 32) {
            MS_SSE_STORE(dst + 16, v);
            MS_SSE_STORE(dst + n - 32, v);
        }
        MS_SSE_STORE(dst + n - 16, v);
    } else if (n >= 8) {
        const uint64_t w = (uint64_t)byte * UINT64_C(0x0101010101010101);
        __builtin_memcpy(dst, &w, 8);
        __builtin_memcpy(dst + n - 8, &w, 8);
    } else if (n >= 4) {
        const uint32_t w = (uint32_t)byte * UINT32_C(0x01010101);
        __builtin_memcpy(dst, &w, 4);
        __builtin_memcpy(dst + n - 4, &w, 4);
    } else if (n >= 2) {
        const uint16_t w = (uint16_t)(byte * 0x0101u);
        __builtin_memcpy(dst, &w, 2);
        __builtin_memcpy(dst + n - 2, &w, 2);
    } else if (n == 1) {
        *dst = byte;
    }
    return to;
}

int ms_mem_compare(const void *left, const void *right, size_t n) {
    const uint8_t *a = left, *b = right;
    size_t i = 0;
    for (; i + 8 <= n; i += 8) {
        uint64_t x, y;
        __builtin_memcpy(&x, a + i, 8);
        __builtin_memcpy(&y, b + i, 8);
        if (x != y) {
            /* Big-endian order makes the first differing byte the most significant one. */
            return __builtin_bswap64(x) < __builtin_bswap64(y) ? -1 : 1;
        }
    }
    for (; i < n; i++) {
        if (a[i] != b[i]) {
            return (int)a[i] - (int)b[i];
        }
    }
    return 0;
}

#endif
