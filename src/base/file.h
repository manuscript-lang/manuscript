/* base/file.h: files and directories by path, the only place the compiler touches the file system.
 *
 * Paths are UTF-8 spans and may use `/` on every host. A function that can fail returns false and leaves
 * its out value as it was. Nothing here is thread-safe against another process changing the same path. */
#ifndef MS_BASE_FILE_H
#define MS_BASE_FILE_H

#include "base/bytes.h"
#include "base/string.h"

/* Replaces `*out` with the bytes of the file (the old contents are freed). */
MS_NODISCARD MS_NONNULL bool ms_file_read(MsSpan path, MsBytes *out);
/* Writes `data` as the whole file, creating or truncating it. */
MS_NODISCARD bool ms_file_write(MsSpan path, MsSpan data);
MS_NODISCARD bool ms_file_is_regular(MsSpan path);
MS_NODISCARD bool ms_dir_exists(MsSpan path);
/* Makes the directory `path` and the missing ones above it; true when it exists afterwards. */
MS_NODISCARD bool ms_dir_make_all(MsSpan path);
/* Makes a fresh private directory named `prefix` plus a unique suffix inside `parent`. */
MS_NODISCARD MS_NONNULL bool ms_dir_make_temp(MsSpan parent, MsSpan prefix, MsString *path);
MS_NODISCARD bool ms_file_rename(MsSpan from, MsSpan to);
/* Removes a file or an empty directory; a missing path is fine. */
void ms_path_remove(MsSpan path);
/* Removes a directory and everything in it, or a file; a missing path is fine. */
void ms_path_remove_tree(MsSpan path);
/* The canonical absolute path of `path`: symbolic links resolved, `.` and `..` folded. The path must exist.
 * On failure the C `errno` holds the cause (ENOENT for a missing path). */
MS_NODISCARD MS_NONNULL bool ms_file_real_path(MsSpan path, MsString *out);
/* The current working directory; false when it cannot be read. */
MS_NODISCARD MS_NONNULL bool ms_dir_current(MsString *path);
/* The directory for temporary files: TMPDIR or TEMP when set, else the host default. */
MsString ms_temp_dir(void);

#endif
