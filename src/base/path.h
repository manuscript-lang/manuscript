/* base/path.h: path text by span. Paths are UTF-8 and use `/` as the separator on every host. */
#ifndef MS_BASE_PATH_H
#define MS_BASE_PATH_H

#include "base/strbuild.h"

/* Appends `left`, a separator unless `left` is empty or ends in one, then `right`. */
void ms_path_append_joined(MsStrBuild *out, MsSpan left, MsSpan right);
/* The final component of `path`. */
MsSpan ms_path_file_name(MsSpan path);
/* Everything before the final component, without the separator; empty when there is none. */
MsSpan ms_path_parent(MsSpan path);


/* Rewrites a path the host returned (`uv_cwd`, `uv_fs_realpath`, `uv_os_tmpdir`) in place to this module's `/`-separated
 * form. The only place the host's separator is known. */
void ms_path_from_os(char *text, size_t size);

/* Lexical path operations as Go's path/filepath does them, with `/` the only separator. */

/* Appends `path` cleaned: no `.` or empty elements, `..` folded where it can be, "." for an empty result. */
void ms_path_clean(MsStrBuild *out, MsSpan path);
/* Whether the path starts at the root. */
bool ms_path_is_absolute(MsSpan path);
/* The suffix from the last dot of the final element ("" when none). */
MsSpan ms_path_ext(MsSpan path);
/* Appends the cleaned path of `target` relative to `base`; false when it cannot be made relative (one is
 * absolute and the other is not). */
MS_NODISCARD bool ms_path_relative(MsStrBuild *out, MsSpan base, MsSpan target);
/* Whether a relative path leaves its base directory. */
bool ms_path_escapes(MsSpan relative);

#endif
