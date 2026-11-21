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

#endif
