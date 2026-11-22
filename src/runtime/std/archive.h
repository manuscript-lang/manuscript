/* runtime/std/archive.h: the @std/io/archive natives (src/runtime/std/archive*.c): in-memory zip and tar
 * packing and unpacking with validation, limits and error mapping. Statuses: 0 ok, 1 InvalidInput, 3
 * LimitExceeded, 4 InvalidData, 9 Unsupported (a format other than "zip" or "tar", or a member type).
 * `ArchiveEntry` records are passed at their natural layout; a `List[ArchiveEntry]` holds them inline. */
#ifndef MS_RUNTIME_STD_ARCHIVE_H
#define MS_RUNTIME_STD_ARCHIVE_H

#include "abi/status.h"
#include "base/bytes.h"
#include "base/string.h"

/* `ArchiveEntry`: `path, data, directory`. */
typedef struct MsArchiveEntry {
  MsString path;
  MsBytes data;
  uint8_t directory;
} MsArchiveEntry;

/* ms-sig: msstd_archive_pack(entries: *const VecVal, format: *const StrVal, has_max: HasRaw, max: i64, out: *mut
 * VecVal)
 * -> u8 @domain=archive */
uint8_t msstd_archive_pack(const MsBytes *entries, const MsString *format, uint8_t has_max, int64_t max,
                           MsBytes *out);
/* ms-sig: msstd_archive_unpack(data: *const VecVal, format: *const StrVal, has_entries: HasRaw,
 * max_entries: i64, has_entry_bytes: HasRaw, max_entry_bytes: i64, has_total: HasRaw, max_total_bytes: i64, out: *mut
 * VecVal) -> u8 @domain=archive */
uint8_t msstd_archive_unpack(const MsBytes *data, const MsString *format,
                             uint8_t has_entries, int64_t max_entries, uint8_t has_entry_bytes,
                             int64_t max_entry_bytes, uint8_t has_total, int64_t max_total_bytes,
                             MsBytes *out);

#endif
