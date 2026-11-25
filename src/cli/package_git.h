/* cli/package_git.h: running `git` for `ms install`, without prompts and with only the transports a package may
 * use. */
#ifndef MS_CLI_PACKAGE_GIT_H
#define MS_CLI_PACKAGE_GIT_H

#include "base/arena.h"
#include "base/string.h"

typedef struct MsGit {
  MsArena *arena;
  MsString directory; /* owned: holds the log of the child's output */
  MsSpan log;
} MsGit;

/* Prepares a runner; false with `*error` when the log directory cannot be made. */
MS_NODISCARD bool ms_git_open(MsGit *git, MsArena *arena, MsSpan *error);
void ms_git_close(MsGit *git);

/* Runs `git <args>` in `directory` (empty for the current one) with `protocols` allowed (`https` or `https:file`).
 * `*output` is what git printed. On failure `*error` is "git <args> failed: <what git said>" with credentials in URLs
 * removed. */
MS_NODISCARD bool ms_git_run(MsGit *git, MsSpan directory, const char *protocols, const char *const *args,
                             size_t count, MsSpan *output, MsSpan *error);

/* `text` without the `user:password@` of any URL in it. */
MsSpan ms_git_redact(MsArena *arena, MsSpan text);

#endif
