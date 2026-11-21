/* runtime/std/command.h: a command to start (@std/process `run`, `spawn` and `replace`): its program, arguments,
 * environment and working directory as the OS wants them, and the status a failed start reports. */
#ifndef MS_RUNTIME_STD_COMMAND_H
#define MS_RUNTIME_STD_COMMAND_H

#include "base/list.h"
#include "base/string.h"
#include "runtime/std/fail.h"

/* A command's strings, each a NUL-terminated copy; `argv` and `env` end with NULL. */
typedef struct MsCommand {
  char *program;
  char **argv; /* the program first */
  char **env;  /* NAME=value, NULL when the child gets the caller's environment unchanged */
  char *cwd;   /* NULL: the caller's */
} MsCommand;

/* Checks the arguments (no empty program, no NUL in any text, no variable name that is empty or holds `=`) and builds
 * the command. `arguments`, `names` and `values` are lists of strings. With `inherit`, the caller's environment is the
 * base and the variables are added or replaced; otherwise they are the whole environment. False with `fail` set. */
MS_NODISCARD bool ms_command_build(MsCommand *command, const MsString *program, const MsList *arguments, bool has_cwd,
                                   const MsString *cwd, const MsList *names, const MsList *values, bool inherit,
                                   MsFail *fail);
void ms_command_free(MsCommand *command);

/* The status of a failed start: a missing program or directory, a file that cannot run, or the host's text. */
void ms_command_start_failure(MsFail *fail, int error, const char *program);

/* Ends a native that starts a command. A command that could not be started is named: the program, or the working
 * directory when that is what does not exist. Other failures are not about the program's name. */
uint8_t ms_command_finish(MsFail *fail, const MsString *program, const MsString *cwd, MsString *err);

#endif
