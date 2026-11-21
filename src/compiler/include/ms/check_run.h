/* `ms check` over libms: one standalone file or one module of a project, as the command prints it. */
#ifndef MS_CHECK_RUN_H
#define MS_CHECK_RUN_H

#include "ms/base.h"
#include "ms/stdlib.h"

#define MS_CHECK_HANDOVER (-1)

/* How `ms check` reports: the terminal text, the `--json` document, or with `--with-text` the document carrying the
 * terminal text as its `text` member. */
typedef struct MsCheckFormat {
    bool json;
    bool with_text; /* only with `json` */
} MsCheckFormat;

/* Checks `target` (a .ms file) against the standard library `std_files` and appends what `ms check` writes in
 * `format` to stdout to `out` and to stderr to `err`. Returns the exit status, or MS_CHECK_HANDOVER, with nothing appended, when the C
 * passes cannot give the answer the Rust command would: a project the loader does not read, a diagnostic, a
 * function or declaration no pass covers, a feature without a C port. The caller then runs the Rust `ms`;
 * `*handover_reason`, when not NULL, is set to a static text saying why. */
int ms_check_run(const MsStdFile *std_files, uint32_t nstd, const char *target, MsCheckFormat format, MsBuf *out,
                 MsBuf *err, const char **handover_reason);

/* `ms check TARGET... --json --with-text --each`: appends `{"results": [{"target", "exit_code", "document",
 * "stderr"}]}` to `out`, each target checked as its own run. Returns the exit status (0), or MS_CHECK_HANDOVER with
 * nothing appended when any one target is handed over. */
int ms_check_run_each(const MsStdFile *std_files, uint32_t nstd, const char *const *targets, size_t count, MsBuf *out,
                      const char **handover_reason);

#endif
