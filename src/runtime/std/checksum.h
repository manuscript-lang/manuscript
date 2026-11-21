/* ms_rt/checksum.h: the @std/data/checksum natives (src/runtime/std/checksum.c, on zlib). `initial` is a
 * finished checksum: 0 for an empty CRC-32 prefix, 1 for an empty Adler-32 prefix. An empty update returns it
 * unchanged. Symbols are listed in src/runtime/symbols/checksum.txt. */
#ifndef MS_RUNTIME_STD_CHECKSUM_H
#define MS_RUNTIME_STD_CHECKSUM_H

#include "abi/status.h"
#include "base/bytes.h"

/* ms-sig: msstd_checksum_adler32_update(initial: i64, data: *const VecVal) -> i64 */
int64_t msstd_checksum_adler32_update(int64_t initial, const MsBytes *data);
/* ms-sig: msstd_checksum_crc32(data: *const VecVal) -> i64 */
int64_t msstd_checksum_crc32(const MsBytes *data);
/* ms-sig: msstd_checksum_crc32_update(initial: i64, data: *const VecVal) -> i64 */
int64_t msstd_checksum_crc32_update(int64_t initial, const MsBytes *data);

#endif
