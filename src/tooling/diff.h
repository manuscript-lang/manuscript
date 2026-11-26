/* tooling/diff.h: unified diff parsing and reverse application, for `ms map --view review --diff`. Never runs git.
 * Texts live in the arena. */
#ifndef MS_TOOLING_DIFF_H
#define MS_TOOLING_DIFF_H

#include "tooling/avec.h"
#include "base/message.h"

/* One `@@` hunk. Lines keep their one-character prefix: ' ' context, '+' added, '-' removed. */
typedef struct MsDiffHunk {
  int64_t old_start, old_len, new_start, new_len;
  MsSpans lines;
  bool old_no_newline, new_no_newline;
} MsDiffHunk;
MS_AVEC(MsDiffHunks, ms_diff_hunks, MsDiffHunk)

/* The hunks of one file. An empty `old` marks an added file and an empty `new` a deleted one. */
typedef struct MsDiffFile {
  MsSpan old, new;
  MsDiffHunks hunks;
} MsDiffFile;
MS_AVEC(MsDiffFiles, ms_diff_files, MsDiffFile)

/* The path a file is known by: its new path, or the old one when deleted. */
MsSpan ms_diff_path(const MsDiffFile *file);

/* Head-side line numbers the hunks changed; a removal belongs to the head line that follows it. */
void ms_diff_touched(MsArena *arena, const MsDiffFile *file, int64_t **lines, size_t *count);

/* Reads a unified diff (git or plain `diff -u`). False leaves the reason in `error`. */
bool ms_diff_parse(MsArena *arena, MsSpan text, MsDiffFiles *files, MsSpan *error);

/* The base file from the head file and the hunks. False when the diff does not describe the head. */
bool ms_diff_reverse_apply(MsArena *arena, MsSpan head, const MsDiffHunks *hunks, MsSpan *out, MsSpan *error);

#endif
