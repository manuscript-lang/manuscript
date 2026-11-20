/* `__clear_cache`, which compiler-rt and libgcc define and the Manuscript link has neither of. PCRE2's JIT calls it
 * after it writes machine code, so the instruction cache sees the new instructions. x86-64 keeps the two caches
 * coherent and the compiler never emits a call there; aarch64 does not, so the data cache is cleaned to the point of
 * unification and the instruction cache invalidated, a line at a time. */
#if defined(__aarch64__)
#include <stdint.h>

void __clear_cache(void *begin, void *end);

/* CTR_EL0 holds both line sizes as log2 of words: DminLine in bits 19:16 and IminLine in bits 3:0. */
#define MS_CTR_LINE_MASK 0xFu
#define MS_CTR_DCACHE_SHIFT 16
#define MS_WORD_BYTES 4u

static uint64_t cache_type_register(void) {
    uint64_t ctr = 0;
    __asm__ volatile("mrs %0, ctr_el0" : "=r"(ctr));
    return ctr;
}

void __clear_cache(void *begin, void *end) {
    const uint64_t ctr = cache_type_register();
    const uintptr_t data_line = (uintptr_t)MS_WORD_BYTES << ((ctr >> MS_CTR_DCACHE_SHIFT) & MS_CTR_LINE_MASK);
    const uintptr_t code_line = (uintptr_t)MS_WORD_BYTES << (ctr & MS_CTR_LINE_MASK);
    const uintptr_t first = (uintptr_t)begin;
    const uintptr_t last = (uintptr_t)end;
    for (uintptr_t line = first & ~(data_line - 1); line < last; line += data_line) {
        __asm__ volatile("dc cvau, %0" : : "r"(line) : "memory");
    }
    __asm__ volatile("dsb ish" : : : "memory");
    for (uintptr_t line = first & ~(code_line - 1); line < last; line += code_line) {
        __asm__ volatile("ic ivau, %0" : : "r"(line) : "memory");
    }
    __asm__ volatile("dsb ish\n\tisb" : : : "memory");
}
#else
typedef int MsClearCacheIsAarch64Only;
#endif
