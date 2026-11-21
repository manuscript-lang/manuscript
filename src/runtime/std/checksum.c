/* @std/data/checksum natives: CRC-32 (IEEE) and Adler-32 from zlib, which takes at most UINT_MAX bytes per
 * call. */
#include <limits.h>
#include <zlib.h>

#include "abi/status.h"
#include "base/bytes.h"
#include "runtime/std/checksum.h"

typedef uLong (*ChecksumFn)(uLong, const Bytef *, uInt);

/* Folds all of `data` into the finished checksum `initial`. */
static uint32_t fold(ChecksumFn update, uint32_t initial, const MsBytes *data) {
  const Bytef *bytes = data->ptr;
  size_t remaining = data->len;
  uLong checksum = initial;
  while (remaining > 0) {
    const uInt step = remaining > UINT_MAX ? UINT_MAX : (uInt)remaining;
    checksum = update(checksum, bytes, step);
    bytes += step;
    remaining -= step;
  }
  return (uint32_t)checksum;
}

int64_t msstd_checksum_crc32(const MsBytes *data) {
  return fold(crc32, 0, data);
}
int64_t msstd_checksum_crc32_update(int64_t initial, const MsBytes *data) {
  return fold(crc32, (uint32_t)initial, data);
}
int64_t msstd_checksum_adler32_update(int64_t initial, const MsBytes *data) {
  return fold(adler32, (uint32_t)initial, data);
}
