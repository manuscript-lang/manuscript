/* A fake of the runtime functions the std natives call, for the unit tests: lists with the descriptor's element size,
 * malloc, and the string tables of ms_rt/strbuild.h. */
#ifndef MS_TEST_FAKE_RT_H
#define MS_TEST_FAKE_RT_H
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../std/abi.h"
#include "ms_rt/strbuild.h"

const MsTypeDesc msrt_desc_int = {.size = 8, .align = 8, .kind = 0};
const MsTypeDesc msrt_desc_string = {.size = 16, .align = 8, .kind = MS_TYPE_KIND_STRING};
const MsTypeDesc msrt_desc_bytes = {.size = 24, .align = 8, .kind = MS_TYPE_KIND_LIST};
uint8_t msrt_ascii_chars[128][2];

/* Entry b of the one-byte ASCII string table is {b, 0}, as the Rust runtime defines it. */
__attribute__((constructor)) static void init_ascii_chars(void) {
    for (int i = 0; i < 128; i++) {
        msrt_ascii_chars[i][0] = (uint8_t)i;
    }
}

void *msrt_alloc(size_t n) { return malloc(n); }
void *msrt_realloc(void *p, size_t n) { return realloc(p, n); }
void *msrt_alloc_zeroed(size_t n) { return calloc(1, n); }
void msrt_free(void *p) { free(p); }

_Noreturn void msrt_fault(const uint8_t *message, size_t length) {
    fprintf(stderr, "fault: %.*s\n", (int)length, (const char *)message);
    abort();
}

_Noreturn void msrt_index_fault(int64_t index, int64_t length) {
    fprintf(stderr, "index fault: %lld of %lld\n", (long long)index, (long long)length);
    abort();
}

void msrt_list_with_capacity(const MsTypeDesc *d, int64_t cap, MsVec *out) {
    out->ptr = cap ? malloc((size_t)cap * d->size) : NULL;
    out->len = 0;
    out->cap = (size_t)cap;
}

void msrt_list_push(MsVec *v, const MsTypeDesc *d, const void *e) {
    if (v->len == v->cap) {
        v->cap = v->cap ? v->cap * 2 : 4;
        v->ptr = realloc(v->ptr, v->cap * d->size);
    }
    memcpy((uint8_t *)v->ptr + v->len * d->size, e, d->size);
    v->len++;
}

/* Frees what the list owns: nested lists and strings by their descriptor, then the buffer. */
void msrt_list_drop(MsVec *v, const MsTypeDesc *d) {
    for (size_t i = 0; i < v->len; i++) {
        const uint8_t *slot = (const uint8_t *)v->ptr + i * d->size;
        if (d->kind == MS_TYPE_KIND_LIST) {
            MsVec inner;
            memcpy(&inner, slot, sizeof inner);
            msrt_list_drop(&inner, d->inner0);
        } else if (d->kind == MS_TYPE_KIND_STRING) {
            MsStr string;
            memcpy(&string, slot, sizeof string);
            if (string.tagged < ((uint64_t)1 << 62)) {
                free(string.ptr_word);
            }
        }
    }
    free(v->ptr);
}

#endif
