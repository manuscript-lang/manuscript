/* `ms.lock` and dependency specs: the pins `ms install` writes and a locked build reads. Port of the lock half of
 * crates/ms-driver/src/project/packages.rs and the id helpers of resolve.rs.
 *
 * A spec is `url#reference` (a tag or a 40-digit commit). A copy's id is `host/path@reference`, as repo_key spells the
 * repository. Whitespace and control characters are taken as ASCII, where the Rust code used Unicode classes. */
#ifndef MS_LOCK_H
#define MS_LOCK_H

#include "ms/project.h"
#include "ms/semver.h"

/* One line of ms.lock. */
typedef struct MsLockEntry {
    const char *key;      /* the copy id */
    const char *spec;     /* `url#reference` */
    const char *revision; /* the full commit the reference pointed to */
    const char *sha256;   /* the hash of the package files, lowercase hex */
} MsLockEntry;

/* Entries sorted by key. */
typedef struct MsLock {
    MsLockEntry *entries;
    uint32_t count;
} MsLock;

bool ms_is_hex(const char *text, size_t length);
/* NULL when `spec` is a valid `url#tag` (https:// or file://, a plain tag name or commit); otherwise the message. */
const char *ms_spec_check(MsArena *a, const char *spec);
/* `github.com/acme/wire` for any spelling of the repository URL. */
const char *ms_repo_key(MsArena *a, const char *url);
const char *ms_copy_id(MsArena *a, const char *url, const char *reference);
/* The id a `url#reference` spec names, NULL without a `#`. */
const char *ms_spec_id(MsArena *a, const char *spec);
/* The version the lock entry's reference names, if it is a version tag. */
bool ms_lock_entry_version(MsArena *a, const MsLockEntry *entry, MsVersion *out);

/* Parses the text of ms.lock; an error is a MS_PERR_MESSAGE with the Rust text. */
MS_NODISCARD bool ms_lock_parse(MsArena *a, const char *text, MsLock *out, MsProjectError *err);
/* Reads `<root>/ms.lock`; a missing file is an empty lock. */
MS_NODISCARD bool ms_lock_read(MsArena *a, const char *root, MsLock *out, MsProjectError *err);
const MsLockEntry *ms_lock_find(const MsLock *lock, const char *key);
/* The text of ms.lock for entries in any order (they are sorted by key first). */
const char *ms_lock_text(MsArena *a, MsLockEntry *entries, uint32_t count);

#endif
