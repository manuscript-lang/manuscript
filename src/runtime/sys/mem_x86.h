/* mem_x86.h: the x86-64 memory routines of src/runtime/sys/mem_x86.c. Linux musl programs reach them as the C
 * library's memcpy, memmove, memset, memcmp and bcmp (src/runtime/sys/musl/mem.c); tests call them by these names. */
#ifndef MS_SYS_MEM_X86_H
#define MS_SYS_MEM_X86_H

#include <stddef.h>

void *ms_mem_copy(void *to, const void *from, size_t n);
void *ms_mem_move(void *to, const void *from, size_t n);
void *ms_mem_set(void *to, int c, size_t n);
int ms_mem_compare(const void *left, const void *right, size_t n);

#endif
