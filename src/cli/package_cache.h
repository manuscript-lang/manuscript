/* cli/package_cache.h: the permissions of a package stored in the cache. */
#ifndef MS_CLI_PACKAGE_CACHE_H
#define MS_CLI_PACKAGE_CACHE_H

#include "base/safe.h"

/* Makes every file below `dir` read-only (and, where the host has it, the directories too), so an edit of a cached
 * package fails instead of silently changing the hash its lock names. */
void ms_cache_protect(MsSpan dir);

/* Undoes `ms_cache_protect` so the tree can be removed. */
void ms_cache_unprotect(MsSpan dir);

#endif
