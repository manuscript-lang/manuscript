/* base/process.h: running a child program and waiting for it, the only place the compiler starts one.
 *
 * The child's standard output and error go to a log file (or the child shares the standard streams); its standard
 * input is empty unless it shares them. Arguments are
 * passed as given (no shell). */
#ifndef MS_BASE_PROCESS_H
#define MS_BASE_PROCESS_H

#include "base/strbuild.h"

typedef struct MsProcessSpec {
  const MsSpan *argv; /* borrowed: the program (a path, or a name looked up on PATH) then its arguments */
  size_t argc;
  MsSpan directory;   /* the working directory; empty for the current one */
  const MsSpan *env;  /* NAME=VALUE texts that are set (or replace a variable) in the child's environment */
  size_t envc;
  MsSpan log_path;    /* the file that receives the output */
  MsSpan error_path;  /* when set, the file that receives the error output instead of `log_path` */
  bool inherit_error; /* only the error output is shared with this process; the output still goes to `log_path` */
  bool (*supervise)(void *context); /* called about every 10 ms while the child runs; true kills the child */
  void *supervise_context;
  bool inherit;       /* the child shares this process's standard streams; `log_path` is unused, and a signal ends it
                         with the shell's status 128 + signal */
} MsProcessSpec;

/* Starts the program and waits. Returns false, with the reason in `error`, when it cannot be started;
 * otherwise true with its exit status in `*exit_status`. */
MS_NODISCARD MS_NONNULL bool ms_process_run(const MsProcessSpec *spec, int *exit_status, MsStrBuild *error);

/* Runs the program and succeeds when it exits with status 0. On failure `why` gets `what` and either the
 * reason it could not start or its output (read from the log file). */
MS_NODISCARD MS_NONNULL bool ms_process_run_logged(MsSpan what, const MsProcessSpec *spec, MsStrBuild *why);

/* Whether `name` is an executable on PATH. */
bool ms_process_find(MsSpan name);

#endif
