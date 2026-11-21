/* @std/random natives: the operating system's entropy through libcrypto, and the version-7 UUID stamp sequence. */
#include <openssl/rand.h>
#include <stdatomic.h>

#include "abi.h"
#include "ms_rt/random.h"
#include "ms_rt/strbuild.h"

/* The largest request an `Entropy` source must serve. */
enum { MAX_BYTES = 16 * 1024 * 1024 };

/* The status for a failed source; the text goes to `err` when the caller passed a slot. */
static uint8_t source_failed(MsStr *err) {
    static const char text[] = "the operating system's random source failed";
    if (err != NULL) {
        *err = ms_str_from_bytes((const uint8_t *)text, sizeof text - 1);
    }
    return STATUS_FAILED;
}

uint8_t msstd_random_os_bytes(int64_t count, MsVec *out, MsStr *err) {
    // The caller reads both slots whatever the status: an empty result and no text until there is one.
    msrt_write_bytes(out, NULL, 0);
    if (err != NULL) {
        *err = ms_str_empty();
    }
    if (count < 0 || count > MAX_BYTES) {
        return STATUS_INVALID_INPUT;
    }
    if (count == 0) {
        return STATUS_OK;
    }
    uint8_t *buffer = msrt_alloc((size_t)count);
    if (RAND_bytes(buffer, (int)count) != 1) {
        msrt_free(buffer);
        return source_failed(err);
    }
    out->ptr = buffer;
    out->len = out->cap = (size_t)count;
    return STATUS_OK;
}

/* Bits of the sequence below the millisecond in a version-7 stamp, and of the seed that starts it. */
enum { STAMP_SEQUENCE_BITS = 12, SEED_MASK = 0x7ff };

/* The last stamp handed out: `(millis << 12) | sequence`. */
static _Atomic int64_t last_stamp;

/* The stamp of the next version-7 UUID made at `millis`. A new millisecond starts the sequence at `seed` (low 11 bits,
 * leaving room to count up); the same millisecond, or a clock that stepped back, continues from the last stamp. Stamps
 * are strictly increasing, and a full 12-bit sequence carries into the millisecond. */
int64_t msstd_random_v7_next(int64_t millis, int64_t seed) {
    const int64_t fresh = (int64_t)((uint64_t)millis << STAMP_SEQUENCE_BITS) | (seed & SEED_MASK);
    int64_t last = atomic_load_explicit(&last_stamp, memory_order_relaxed);
    int64_t next;
    do {
        next = fresh > last ? fresh : last + 1;
    } while (!atomic_compare_exchange_weak_explicit(&last_stamp, &last, next, memory_order_relaxed, memory_order_relaxed));
    return next;
}
