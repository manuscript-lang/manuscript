/* `__clear_cache`, which libpcre2's JIT (sljit) calls after writing machine code on 64-bit Arm.
 *
 * The compiler normally supplies it from libgcc or compiler-rt, and the Manuscript link has neither. The weak
 * definition leaves a runtime that does provide it in charge. Instruction caches of x86 follow data writes, so
 * only Arm needs work: the data cache lines of the range are cleaned to the point of unification, then the
 * instruction cache lines are invalidated, as compiler-rt does. macOS and Windows have their own calls and the
 * JIT does not use this symbol there.
 */
#include <stddef.h>
#include <stdint.h>

#if defined(__aarch64__) && !defined(__APPLE__) && !defined(_WIN32)

__attribute__((weak)) void __clear_cache(void *begin, void *end);

__attribute__((weak)) void __clear_cache(void *begin, void *end) {
    uint64_t ctr = 0;
    __asm__ volatile("mrs %0, ctr_el0" : "=r"(ctr));
    const uintptr_t data_line = (uintptr_t)4 << ((ctr >> 16) & 15);
    const uintptr_t code_line = (uintptr_t)4 << (ctr & 15);
    const uintptr_t first = (uintptr_t)begin;
    const uintptr_t last = (uintptr_t)end;
    for (uintptr_t address = first & ~(data_line - 1); address < last; address += data_line) {
        __asm__ volatile("dc cvau, %0" : : "r"(address) : "memory");
    }
    __asm__ volatile("dsb ish" : : : "memory");
    for (uintptr_t address = first & ~(code_line - 1); address < last; address += code_line) {
        __asm__ volatile("ic ivau, %0" : : "r"(address) : "memory");
    }
    __asm__ volatile("dsb ish\n\tisb" : : : "memory");
}

#else

typedef int MsClearCacheNotNeeded; /* an empty translation unit is not valid C */

#endif
