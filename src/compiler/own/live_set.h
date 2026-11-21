/* compiler/own/live_set.h: the set of places live after a point of a function body.
 *
 * Each entry is a place (a binding and a path of field names) with the earliest later use of it. Entries
 * sit in one array sorted by binding, so a query or a kill touches only the entries of one binding and a
 * copy at a branch is one allocation. A store to a place is recorded with the marker step
 * MS_LIVE_STORE as the last step of its path; a "stored again" mark for a binding uses the binding's key
 * with MS_LIVE_STORED_BIT set.
 *
 * Ownership: the set owns its array; paths are borrowed from the arena that built them. */
#ifndef MS_COMPILER_OWN_LIVE_SET_H
#define MS_COMPILER_OWN_LIVE_SET_H

#include "base/list.h"
#include "compiler/check/facts.h"

/* No node: node ids start at 0, so the sentinel is the largest id. */
#define MS_NO_NODE ((MsNode)UINT32_MAX)
#define MS_LIVE_STORE ((MsName)UINT32_MAX)
#define MS_LIVE_STORED_BIT (UINT64_C(1) << 32)

typedef struct MsLivePath {
  const MsName *names;
  uint32_t len;
} MsLivePath;

typedef struct MsLiveEntry {
  uint64_t key; /* the binding id, or the id with MS_LIVE_STORED_BIT */
  MsLivePath path;
  MsNode node;
} MsLiveEntry;

MS_LIST_DEFINE(MsLiveSet, ms_live_set, MsLiveEntry)

MsLiveSet ms_live_clone(const MsLiveSet *set);

/* The node of the entry for exactly this place, or MS_NO_NODE. */
MsNode ms_live_get(const MsLiveSet *set, uint64_t key, MsLivePath path);

/* Records the place with `node`, replacing an earlier use of it. */
void ms_live_insert(MsLiveSet *set, uint64_t key, MsLivePath path, MsNode node);

/* Adds the entries of `from`, keeping the earlier use of a place both hold. */
void ms_live_join(MsLiveSet *into, const MsLiveSet *from);

/* Removes every entry of `key`. */
void ms_live_kill(MsLiveSet *set, uint64_t key);

/* Removes the entries of `key` whose path starts with `prefix`. */
void ms_live_remove_prefix(MsLiveSet *set, uint64_t key, MsLivePath prefix);

/* The earliest later use of `key` at a place related to `path` (one a prefix of the other), or MS_NO_NODE. A store
 * counts for the whole binding but not for a place: overwriting `b.f` does not read what an earlier move
 * took from `b.f`. */
MsNode ms_live_next_use(const MsLiveSet *set, uint64_t key, MsLivePath path);

#endif
