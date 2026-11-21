/* ms_rt/random.h: the @std/random natives (src/runtime/std/random.c). `os_bytes` fills a Bytes value from the
 * operating system's entropy through libcrypto; the status is 0 ok, 1 InvalidInput (a count outside 0..16
 * MiB) or 11 Failed (the text in `err`, which may be null). Symbols are listed in
 * src/runtime/symbols/random.txt. */
#ifndef MS_RUNTIME_STD_RANDOM_H
#define MS_RUNTIME_STD_RANDOM_H

#include "abi/status.h"
#include "base/bytes.h"
#include "base/string.h"

/* ms-sig: msstd_random_os_bytes(count: i64, out: *mut VecVal, err: ErrSlot) -> u8 @domain=random */
uint8_t msstd_random_os_bytes(int64_t count, MsBytes *out, MsString *err);
/* ms-sig: msstd_random_v7_next(millis: i64, seed: i64) -> i64 @domain=random */
int64_t msstd_random_v7_next(int64_t millis, int64_t seed);

#endif
