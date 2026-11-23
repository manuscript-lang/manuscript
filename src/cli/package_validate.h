/* cli/package_validate.h: what a downloaded package must be before it enters the cache. Port of
 * `reject_unportable` and `validate` of crates/ms-cli/src/fetch.rs. */
#ifndef MS_CLI_PACKAGE_VALIDATE_H
#define MS_CLI_PACKAGE_VALIDATE_H

#include "cli/package_git.h"

/* A package is judged from git's own record of the checkout, because the hash is taken from the directory and must
 * come out the same on every platform. Each of these is rejected everywhere: a symbolic link, two paths that differ
 * only by letter case, and a name Windows cannot create. */
MS_NODISCARD bool ms_package_reject_unportable(MsGit *git, MsSpan key, MsSpan directory, const char *protocols,
                                               MsSpan *error);

/* A package is a library with a manifest, no entry, no embedded files and no top-level `@` directory. */
MS_NODISCARD bool ms_package_validate(MsArena *arena, MsSpan key, MsSpan directory, MsSpan *error);

#endif
