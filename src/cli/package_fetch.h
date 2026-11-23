/* cli/package_fetch.h: the network and the cache as the resolver sees them: tags from `git ls-remote`, packages
 * downloaded with git into the content-addressed cache. Port of the `Git` remote of crates/ms-cli/src/fetch.rs. */
#ifndef MS_CLI_PACKAGE_FETCH_H
#define MS_CLI_PACKAGE_FETCH_H

#include "compiler/project/solve.h"
#include "cli/package_git.h"

typedef struct MsGitRemote {
  MsGit git;
  MsRemote remote;
} MsGitRemote;

/* Prepares a remote backed by git; false with `*error` when git's scratch space cannot be made. */
MS_NODISCARD bool ms_git_remote_open(MsGitRemote *remote, MsArena *arena, MsSpan *error);
void ms_git_remote_close(MsGitRemote *remote);

#endif
