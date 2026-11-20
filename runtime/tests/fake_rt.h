/* A fake of the runtime functions the std natives call, for the unit tests: lists of 8-byte elements, malloc. */
#ifndef MS_TEST_FAKE_RT_H
#define MS_TEST_FAKE_RT_H
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "../std/abi.h"

const unsigned char msrt_desc_int[1];
void *msrt_alloc(size_t n) { return malloc(n); }
void msrt_free(void *p) { free(p); }
void *msrt_alloc_zeroed(size_t n) { return calloc(1, n); }

void msrt_list_with_capacity(const void *d, int64_t cap, MsVec *out) {
    (void)d;
    out->ptr = cap ? malloc((size_t)cap * sizeof(int64_t)) : NULL;
    out->len = 0;
    out->cap = (size_t)cap;
}

void msrt_list_push(MsVec *v, const void *d, const void *e) {
    (void)d;
    if (v->len == v->cap) {
        v->cap = v->cap ? v->cap * 2 : 4;
        v->ptr = realloc(v->ptr, v->cap * sizeof(int64_t));
    }
    memcpy((int64_t *)v->ptr + v->len, e, sizeof(int64_t));
    v->len++;
}

void msrt_list_drop(MsVec *v, const void *d) {
    (void)d;
    free(v->ptr);
}

#endif
