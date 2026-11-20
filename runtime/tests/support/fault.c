/* What the Rust runtime still provides to runtime/core, for the C unit tests: the fault entry point and the
 * table of one-character ASCII strings. A test that expects a fault sets ms_test_fault (rt_stubs.h). */
#include <setjmp.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include "rt_stubs.h"

uint8_t msrt_ascii_chars[128][2];
jmp_buf *ms_test_fault;
char ms_test_fault_msg[256];

__attribute__((constructor)) static void init_ascii(void) {
    for (int i = 0; i < 128; i++) {
        msrt_ascii_chars[i][0] = (uint8_t)i;
    }
}

_Noreturn void msrt_fault(const uint8_t *msg, size_t len) {
    if (ms_test_fault == NULL) {
        fprintf(stderr, "fault: %.*s\n", (int)len, msg);
        abort();
    }
    size_t n = len < sizeof ms_test_fault_msg - 1 ? len : sizeof ms_test_fault_msg - 1;
    memcpy(ms_test_fault_msg, msg, n);
    ms_test_fault_msg[n] = 0;
    longjmp(*ms_test_fault, 1);
}
