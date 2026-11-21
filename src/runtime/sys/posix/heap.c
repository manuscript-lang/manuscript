/* The C library's allocator on Linux and macOS, for blocks the size classes do not serve. */
#include "ms_rt/sys.h"

extern void *malloc(size_t size);
extern void *realloc(void *ptr, size_t size);
extern void free(void *ptr);
#ifdef __APPLE__
extern size_t malloc_size(const void *ptr);
#else
extern size_t malloc_usable_size(void *ptr);
#endif

void *ms_sys_malloc(size_t size) { return malloc(size); }

void *ms_sys_realloc(void *ptr, size_t size) { return realloc(ptr, size); }

void ms_sys_free(void *ptr) { free(ptr); }

size_t ms_sys_malloc_size(void *ptr) {
#ifdef __APPLE__
    return malloc_size(ptr);
#else
    return malloc_usable_size(ptr);
#endif
}
