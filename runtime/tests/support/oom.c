/* The out-of-memory hook the Rust runtime provides, for C unit tests: report and abort. */
#include <stdio.h>
#include <stdlib.h>

#include "alloc.h"

void msalloc_rust_oom(size_t bytes) {
    fprintf(stderr, "out of memory: %zu bytes\n", bytes);
    abort();
}
