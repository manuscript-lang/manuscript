/* Unit test for the exported hashes of src/runtime/core/desc.c: msrt_hash_bytes (the String key hash, with fixed
 * vectors), msrt_hash_int and msrt_hash_combine. `make c-test` builds it with ASan and UBSan. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ms_rt/desc.h"

static void check(bool ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "core_hash.c:%d: %s\n", line, text);
        abort();
    }
}
#define CHECK(cond) check((cond), __LINE__, #cond)

static int64_t hash_of(const char *text) {
    return msrt_hash_bytes((const uint8_t *)text, strlen(text));
}

/* Fixed vectors: the generated code's inline map probe computes the same values. */
static void test_vectors(void) {
    CHECK(hash_of("") == INT64_C(5637604647281345049));
    CHECK(hash_of("a") == INT64_C(-4589632175014895841));
    CHECK(hash_of("hello") == INT64_C(-2768413155067229152));
    CHECK(hash_of("123456789012345") == INT64_C(1963792452095667305));
    CHECK(hash_of("1234567890123456") == INT64_C(6017223085291776624));
    CHECK(hash_of("The quick brown fox jumps over the lazy dog") == INT64_C(5716930301217669884));
}

/* Length and every byte take part: no two of these buffers collide, and changing any byte changes the hash. */
static void test_separation(void) {
    enum { MAX = 40, FILLS = 3 };
    static const uint8_t fills[FILLS] = {0, 'a', 0xff};
    int64_t seen[MAX * FILLS];
    size_t count = 0;
    for (size_t length = 0; length < MAX; length++) {
        uint8_t buffer[MAX];
        for (size_t f = 0; f < (length == 0 ? 1 : FILLS); f++) {
            memset(buffer, fills[f], length);
            const int64_t hash = msrt_hash_bytes(buffer, length);
            for (size_t i = 0; i < count; i++) {
                CHECK(seen[i] != hash);
            }
            seen[count++] = hash;
        }
    }
    uint8_t base[24];
    memset(base, 'x', sizeof base);
    for (size_t at = 0; at < sizeof base; at++) {
        uint8_t changed[24];
        memcpy(changed, base, sizeof base);
        changed[at] = 'y';
        CHECK(msrt_hash_bytes(changed, sizeof changed) != msrt_hash_bytes(base, sizeof base));
    }
}

static void test_int_and_combine(void) {
    CHECK(msrt_hash_int(1) != msrt_hash_int(2));
    CHECK(msrt_hash_int(0) == msrt_hash_int(0));
    CHECK(msrt_hash_combine(1, 2) != msrt_hash_combine(2, 1));
    CHECK(msrt_hash_combine(msrt_hash_int(7), 3) == msrt_hash_combine(msrt_hash_int(7), 3));
}

int main(void) {
    test_vectors();
    test_separation();
    test_int_and_combine();
    return puts("core_hash ok") < 0;
}
