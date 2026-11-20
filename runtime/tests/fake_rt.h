/* A fake of the runtime functions the std natives call, for the unit tests: lists of 8-byte elements, malloc. */
#ifndef MS_TEST_FAKE_RT_H
#define MS_TEST_FAKE_RT_H
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void *msrt_alloc(size_t n) { return malloc(n); }
void msrt_free(void *p) { free(p); }
#include "fake_list.h"

/* Faults end the test with the message; the real runtime records and unwinds. */
void msrt_fault(const void *message, size_t length) {
    fprintf(stderr, "FAULT %.*s\n", (int)length, (const char *)message);
    exit(1);
}
void msfault_raise(uint8_t kind, const void *message, size_t length) {
    fprintf(stderr, "FAULT(%u) %.*s\n", kind, (int)length, (const char *)message);
    exit(1);
}
/* An owned string (tag bits 00): the allocation and the byte length. */
void msrt_string_from_bytes(const uint8_t *bytes, size_t length, void *out) {
    struct { uint8_t *ptr; uint64_t tagged; } *s = out;
    s->ptr = malloc(length + 1);
    memcpy(s->ptr, bytes, length);
    s->tagged = length;
}


#endif
