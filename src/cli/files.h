/* cli/files.h: the file and path steps the commands share: read a file into an arena, write a command's result to
 * `-o` or standard output, and spell a path against the working directory. */
#ifndef MS_CLI_FILES_H
#define MS_CLI_FILES_H

#include "base/arena.h"

/* The text of the file at `path` copied into `arena`; empty when it cannot be read. */
MsSpan ms_cli_read_text(MsArena *arena, MsSpan path);

/* Writes `text` to the file `output` names, or to standard output when it is empty. Returns the exit status:
 * 0, or 1 after naming the file that could not be written. */
int ms_cli_write_output(MsSpan output, MsSpan text);

/* `path` made absolute against the working directory and cleaned, copied into `arena`. */
MsSpan ms_cli_absolute(MsArena *arena, MsSpan path);

/* `left` and `right` joined by one separator, copied into `arena`. */
MsSpan ms_cli_joined(MsArena *arena, MsSpan left, MsSpan right);

#endif
