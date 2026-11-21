/* Packages and `ms install`: the content-addressed package cache, the git remote the resolver talks to, and the
 * install procedure. Port of crates/ms-driver/src/project/packages.rs (cache, index, hash) and
 * crates/ms-cli/src/fetch.rs (git, download, install). Error texts are the Rust ones.
 *
 * The cache holds one directory per package, named for the SHA-256 of its index; `<hash>.index` beside it lists each
 * file's path and SHA-256, so a file read later is checked against its line alone. */
#ifndef MS_PACKAGES_H
#define MS_PACKAGES_H

#include "ms/resolve.h"

/* The directory holding fetched packages: $MS_PACKAGE_CACHE, else $XDG_CACHE_HOME/ms/packages, else
 * $HOME/.cache/ms/packages. */
const char *ms_package_cache_dir(MsArena *a);

/* Lowercase hexadecimal SHA-256 of `data`, into `out` (64 digits and a NUL). */
void ms_sha256_hex(const void *data, size_t length, char out[65]);

/* The index of the files under `dir`, ignoring a top-level `.git`: one line per file in byte order of its `/` path
 * (the path, a zero byte, the hex SHA-256 of its bytes, a newline). The text holds NUL bytes, so it is a span. */
MS_NODISCARD bool ms_package_index(MsArena *a, const char *dir, MsStr *index, MsProjectError *err);
/* The package hash: the SHA-256 of the index. */
const char *ms_package_hash(MsArena *a, MsStr index);
/* Whether the cache holds the package with `hash` exactly as it was stored. */
bool ms_package_cached_intact(MsArena *a, const char *cache, const char *hash);

/* What `ms install` did with one copy. */
typedef enum MsInstallState {
    MS_INSTALL_FETCHED, /* downloaded, and new to the cache */
    MS_INSTALL_CACHED,  /* downloaded, and the cache already held that content */
    MS_INSTALL_KEPT     /* the locked copy was intact in the cache */
} MsInstallState;

typedef struct MsInstalledCopy {
    const char *name; /* the top-level alias that reaches the copy, else its id */
    MsCopy copy;
    MsInstallState state;
    const char *effects; /* `[project] effects` joined by spaces, "none" without any */
} MsInstalledCopy;

typedef struct MsInstallOptions {
    const char *manifest;       /* path of ms.toml */
    /* A workspace installs every member's dependencies into one lock at `lock_root`: the members' ms.toml paths
     * and the names diagnostics call them. `member_count` 0 installs `manifest` alone (and fails for a member). */
    const char *lock_root;
    const char *const *member_manifests;
    const char *const *member_names;
    uint32_t member_count;
    const char *const *update;  /* names whose repositories are re-picked */
    uint32_t update_count;
    bool locked; /* fail instead of changing ms.lock */
    bool frozen; /* leave ms.lock as it is */
} MsInstallOptions;

typedef struct MsInstallReport {
    MsInstalledCopy *copies; /* sorted by id */
    uint32_t count;
} MsInstallReport;

/* Resolves the dependencies of the project, fetches them into the cache and writes ms.lock when it changed (it is
 * removed when the project has no dependencies). A workspace member or root fails as MS_PERR_UNSUPPORTED unless the
 * caller names the workspace's members (it reads the members: tools/ms/workspace.ms). */
MS_NODISCARD bool ms_install(MsArena *a, const MsInstallOptions *options, MsInstallReport *out, MsProjectError *err);

#endif
