/* What the @std/io/archive natives share: the tar reader and writer (archive_tar.c) and the zip reader and
 * writer (archive_zip.c), both over memory. Failures of a reader are plain `false` or -1: the natives report
 * all of them as invalid data. */
#ifndef MS_RUNTIME_STD_ARCHIVE_INTERNAL_H
#define MS_RUNTIME_STD_ARCHIVE_INTERNAL_H

#include "base/strbuild.h"

/* ---- tar ---- */

enum { TAR_TYPE_REG = '0', TAR_TYPE_REG_A = 0, TAR_TYPE_DIR = '5', TAR_TYPE_X_GLOBAL = 'g' };

typedef struct TarItem {
  MsStrBuild name; /* owned */
  uint8_t typeflag;
  int64_t size;
  size_t start;  /* where the data section lies in the archive */
  size_t length; /* its length: the declared size, or less when the archive ends first */
  bool truncated;
} TarItem;

typedef struct TarReader {
  MsSpan data;
  size_t pos;
  size_t pad;
} TarReader;

/* The next entry that is not a PAX or GNU special: 1 with `item` filled (free it with tar_item_free), 0 at
 * the end of the archive, -1 for a malformed archive. */
int tar_next(TarReader *reader, TarItem *item);
void tar_item_free(TarItem *item);
/* Appends one entry; false when it is too large for a header. */
MS_NODISCARD bool tar_write_entry(MsStrBuild *out, MsSpan name, MsSpan data, bool directory);
void tar_finish(MsStrBuild *out);

/* ---- zip ---- */

/* A central directory record; `name` points into the archive. */
typedef struct ZipFile {
  MsSpan name;
  uint16_t creator;
  uint16_t flags;
  uint16_t method;
  uint32_t crc32;
  uint64_t compressed_size;
  uint64_t size;
  uint32_t attrs;
  int64_t offset;
} ZipFile;

typedef struct ZipMember {
  MsSpan name; /* with a trailing slash for a directory */
  MsSpan data;
  bool directory;
} ZipMember;

/* The members in central directory order, in an allocation the caller frees with ms_free; false when
 * malformed. */
MS_NODISCARD bool zip_open(MsSpan data, ZipFile **files, size_t *count);
/* Go's FileHeader.Mode: whether the member is a regular file or a directory (neither: unsupported). */
void zip_kind(const ZipFile *file, bool *regular, bool *directory);
/* The failures of Go's File.Open: a bad local header or an unsupported method. */
MS_NODISCARD bool zip_check_open(const ZipFile *file, MsSpan data);
/* Appends the verified body of a member. */
MS_NODISCARD bool zip_read(const ZipFile *file, MsSpan data, MsStrBuild *out);
void zip_pack(MsStrBuild *out, const ZipMember *members, size_t count);

#endif
