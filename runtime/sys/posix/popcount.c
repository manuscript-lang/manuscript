/* `__popcountdi2`, which gcc emits for `__builtin_popcountll` on targets without a population-count instruction
 * (libcurl's bit sets on x86-64). The compiler normally supplies it from libgcc, and the Manuscript link has none.
 * The weak definition leaves a runtime that does provide it in charge.
 */
#include <stdint.h>

#if defined(__x86_64__) || defined(__i386__)

/* The name is the compiler runtime's (libgcc ABI), so it cannot avoid the reserved prefix. */
// NOLINTBEGIN(bugprone-reserved-identifier)
__attribute__((weak)) int __popcountdi2(int64_t value);

__attribute__((weak)) int __popcountdi2(int64_t value) {
    uint64_t v = (uint64_t)value;
    v = v - ((v >> 1) & 0x5555555555555555ULL);
    v = (v & 0x3333333333333333ULL) + ((v >> 2) & 0x3333333333333333ULL);
    v = (v + (v >> 4)) & 0x0F0F0F0F0F0F0F0FULL;
    return (int)((v * 0x0101010101010101ULL) >> 56);
}
// NOLINTEND(bugprone-reserved-identifier)

#else

typedef int MsPopcountNotNeeded; /* an empty translation unit is not valid C */

#endif
