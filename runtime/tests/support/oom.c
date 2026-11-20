/* The allocator's out-of-memory hook for C unit tests: report and abort (runtime/core/fault.c has the real one). */
#include <stdio.h>
#include <stdlib.h>

#include "../../core/alloc.h"

void msalloc_oom(size_t bytes) {
    fprintf(stderr, "out of memory: %zu bytes\n", bytes);
    abort();
}
