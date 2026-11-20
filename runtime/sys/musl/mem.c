/* The C library's memory routines for Linux musl on x86-64, over runtime/sys/mem_x86.c (see there for why musl's
 * own are replaced). Other architectures keep musl's. */
#if defined(__x86_64__)
#include <strings.h>
#include <string.h>

#include "../mem_x86.h"

void *memcpy(void *restrict to, const void *restrict from, size_t n) { return ms_mem_copy(to, from, n); }
void *memmove(void *to, const void *from, size_t n) { return ms_mem_move(to, from, n); }
void *memset(void *to, int c, size_t n) { return ms_mem_set(to, c, n); }
int memcmp(const void *left, const void *right, size_t n) { return ms_mem_compare(left, right, n); }
int bcmp(const void *left, const void *right, size_t n) { return ms_mem_compare(left, right, n); }
#endif
