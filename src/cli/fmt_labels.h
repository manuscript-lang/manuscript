/* cli/fmt_labels.h: the `--drop-labels` step of `ms fmt`. */
#ifndef MS_CLI_FMT_LABELS_H
#define MS_CLI_FMT_LABELS_H

#include "base/arena.h"
#include "base/safe.h"

/* Checks the file at `path` (whose text is `source`) and removes its redundant argument labels. True with the
 * edited text in `*edited`; false with a message that names `display` in `*error`, when the source does not check.
 * Texts live in `arena`. */
MS_NODISCARD bool fmt_drop_labels(MsArena *arena, MsSpan path, MsSpan display, MsSpan source, MsSpan *edited,
                                  MsSpan *error);

#endif
