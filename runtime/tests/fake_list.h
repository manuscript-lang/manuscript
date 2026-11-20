/* Fake list runtime for the unit tests that only need the std natives to link: lists of 8-byte elements on malloc. */
#ifndef MS_TEST_FAKE_LIST_H
#define MS_TEST_FAKE_LIST_H
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct { int64_t *ptr; size_t len, cap; } fake_vec;

void msrt_list_with_capacity(const void *d, int64_t cap, void *out);
void msrt_list_push(void *v, const void *d, const void *e);
void msrt_list_drop(void *v, const void *d);

const unsigned char msrt_desc_int[1];
void msrt_list_with_capacity(const void *d, int64_t cap, void *vec) {
    fake_vec *const out = vec;
    (void)d;
    out->ptr = cap ? malloc((size_t)cap * 8) : NULL;
    out->len = 0;
    out->cap = (size_t)cap;
}
void msrt_list_push(void *vec, const void *d, const void *e) {
    fake_vec *const v = vec;
    (void)d;
    if (v->len == v->cap) {
        v->cap = v->cap ? v->cap * 2 : 4;
        v->ptr = realloc(v->ptr, v->cap * 8);
    }
    memcpy(v->ptr + v->len++, e, 8);
}
void msrt_list_drop(void *vec, const void *d) {
    (void)d;
    free(((fake_vec *)vec)->ptr);
}

#endif
