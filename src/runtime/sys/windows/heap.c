/* The C runtime's allocator on Windows, for blocks the size classes do not serve. */
#include "runtime/sys/sys.h"

extern void *malloc(size_t size);
extern void *realloc(void *ptr, size_t size);
extern void free(void *ptr);
extern size_t _msize(void *ptr);

void *ms_sys_malloc(size_t size) { return malloc(size); }

void *ms_sys_realloc(void *ptr, size_t size) { return realloc(ptr, size); }

void ms_sys_free(void *ptr) { free(ptr); }

size_t ms_sys_malloc_size(void *ptr) { return _msize(ptr); }
