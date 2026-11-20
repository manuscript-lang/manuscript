/* What the Rust runtime provides to runtime/core in a real build, stubbed for the C unit tests: faults that
 * jump back to the test, strings, objects, the cleanup stack and the map functions. The string stubs
 * implement just the layout the tests use (owned and inline strings are both a malloc copy here). */
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms_rt/desc.h"
#include "ms_rt/alloc.h"
#include "rt_calls.h"
#include "rt_stubs.h"

jmp_buf *ms_test_fault;
char ms_test_fault_message[256];
uint8_t ms_test_fault_kind;
size_t ms_test_cleanups;

#define MAX_CLEANUPS 8
static void (*cleanup_run[MAX_CLEANUPS])(uint8_t *);
static uint8_t *cleanup_arg[MAX_CLEANUPS];

_Noreturn void msfault_raise(uint8_t kind, const uint8_t *msg, size_t len) {
    if (ms_test_fault == NULL) {
        fprintf(stderr, "fault: %.*s\n", (int)len, msg);
        abort();
    }
    const size_t n = len < sizeof ms_test_fault_message - 1 ? len : sizeof ms_test_fault_message - 1;
    memcpy(ms_test_fault_message, msg, n);
    ms_test_fault_message[n] = 0;
    ms_test_fault_kind = kind;
    while (ms_test_cleanups > 0) { /* a fault runs the pending cleanups, newest first, before it jumps */
        ms_test_cleanups--;
        cleanup_run[ms_test_cleanups](cleanup_arg[ms_test_cleanups]);
    }
    longjmp(*ms_test_fault, 1);
}

_Noreturn void msrt_fault(const uint8_t *msg, size_t len) { msfault_raise(0, msg, len); }

_Noreturn void msrt_index_fault(int64_t index, int64_t length) {
    char text[96];
    int n = snprintf(text, sizeof text, "index %lld out of range for length %lld", (long long)index, (long long)length);
    msfault_raise(6, (const uint8_t *)text, (size_t)n);
}

_Noreturn void msrt_list_index_fault(int64_t operation, int64_t index, int64_t len) {
    char text[96];
    int n = snprintf(text, sizeof text, "list op %lld index %lld length %lld", (long long)operation, (long long)index,
                     (long long)len);
    msfault_raise(6, (const uint8_t *)text, (size_t)n);
}

size_t msrt_cleanup_push(void (*run)(uint8_t *), uint8_t *arg) {
    cleanup_run[ms_test_cleanups] = run;
    cleanup_arg[ms_test_cleanups] = arg;
    return ++ms_test_cleanups;
}

void msrt_cleanup_discard(size_t handle) { ms_test_cleanups = handle - 1; }

/* A test string is always owned: the first word is a malloc'ed copy and the second its length (tag bits 00),
 * which msrt_string_eq and msrt_string_hash in core/string.c read like any owned string. */
static void make_owned(const uint8_t *bytes, size_t len, MsStr *out) {
    uint8_t *copy = malloc(len + 1);
    memcpy(copy, bytes, len);
    copy[len] = 0;
    const uint64_t words[2] = {(uint64_t)(uintptr_t)copy, len};
    memcpy(out, words, sizeof words);
}

static void owned_parts(const MsStr *s, const uint8_t **bytes, size_t *len) {
    uint64_t words[2];
    memcpy(words, s, sizeof words);
    *bytes = (const uint8_t *)(uintptr_t)words[0];
    *len = (size_t)words[1];
}

void msrt_string_clone(const MsStr *s, MsStr *out) {
    const uint8_t *bytes = NULL;
    size_t len = 0;
    owned_parts(s, &bytes, &len);
    make_owned(bytes, len, out);
}

void msrt_string_free(const MsStr *s) {
    uint64_t words[2];
    memcpy(words, s, sizeof words);
    free((void *)(uintptr_t)words[0]);
}

/* The empty string owns nothing, like the static empty string of the real runtime. */
void msrt_string_empty(MsStr *out) { memset(out, 0, 16); }

void msrt_string_from_bytes(const uint8_t *ptr, size_t len, MsStr *out) { make_owned(ptr, len, out); }

int64_t msrt_hash_bytes(const uint8_t *ptr, size_t len) {
    uint64_t hash = 14695981039346656037ull;
    for (size_t i = 0; i < len; i++) {
        hash = (hash ^ ptr[i]) * 1099511628211ull;
    }
    return (int64_t)hash;
}

MsObj *msrt_obj_clone(MsObj *object) { return object; }
void msrt_obj_drop(MsObj *object) { (void)object; }

/* Maps are not part of the list tests: a set is a list of its keys, enough for `distinct` and `to_set`. */
void msrt_map_new(MsMap *out) { memset(out, 0, sizeof *out); }

uint8_t msrt_map_contains(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, const uint8_t *key) {
    (void)vd;
    for (size_t i = 0; i < m->len; i++) {
        if (memcmp(m->slots + i * kd->size, key, kd->size) == 0) {
            return 1;
        }
    }
    return 0;
}

void msrt_set_add_copy(MsMap *m, const MsTypeDesc *kd, const uint8_t *key) {
    if (msrt_map_contains(m, kd, NULL, key)) {
        return;
    }
    m->slots = realloc(m->slots, (m->len + 1) * kd->size);
    memcpy(m->slots + m->len * kd->size, key, kd->size);
    m->len++;
}

void msrt_map_drop(MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd) {
    (void)kd;
    (void)vd;
    free(m->slots);
    memset(m, 0, sizeof *m);
}

void msrt_map_copy(const MsMap *m, const MsTypeDesc *kd, const MsTypeDesc *vd, MsMap *out) {
    (void)m;
    (void)kd;
    (void)vd;
    memset(out, 0, sizeof *out);
}

uint8_t msmap_eq(const MsMap *a, const MsMap *b, const MsTypeDesc *kd, const MsTypeDesc *vd) {
    (void)a;
    (void)b;
    (void)kd;
    (void)vd;
    return 0;
}
