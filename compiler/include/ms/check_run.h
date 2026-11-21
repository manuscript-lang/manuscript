/* `ms check` over libms: one standalone file or one module of a project, as the command prints it. */
#ifndef MS_CHECK_RUN_H
#define MS_CHECK_RUN_H

#include "ms/base.h"
#include "ms/stdlib.h"

#define MS_CHECK_HANDOVER (-1)

/* Checks `target` (a .ms file) against the standard library `std_files` and appends what `ms check [--json]`
 * writes to stdout to `out` and to stderr to `err`. Returns the exit status, or MS_CHECK_HANDOVER, with nothing appended, when the C
 * passes cannot give the answer the Rust command would: a project the loader does not read, a diagnostic, a
 * function or declaration no pass covers, a feature without a C port. The caller then runs the Rust `ms`;
 * `*handover_reason`, when not NULL, is set to a static text saying why. */
int ms_check_run(const MsStdFile *std_files, uint32_t nstd, const char *target, bool json, MsBuf *out, MsBuf *err,
                 const char **handover_reason);

#endif
