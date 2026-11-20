/* What the Rust runtime provides to C core code, for the C unit tests: the one-byte string table and faults. */
#include <stdio.h>
#include <stdlib.h>

#include "ms_rt/base.h"

uint8_t msrt_ascii_chars[128][2] = {
#define C4(n) {(n)}, {(n) + 1}, {(n) + 2}, {(n) + 3}
#define C16(n) C4(n), C4((n) + 4), C4((n) + 8), C4((n) + 12)
    C16(0), C16(16), C16(32), C16(48), C16(64), C16(80), C16(96), C16(112)};

void msrt_fault(const uint8_t *msg, size_t len) {
    fprintf(stderr, "fault: %.*s\n", (int)len, (const char *)msg);
    exit(134);
}

void msrt_index_fault(int64_t index, int64_t length) {
    fprintf(stderr, "fault: index %lld out of range for length %lld\n", (long long)index, (long long)length);
    exit(134);
}
