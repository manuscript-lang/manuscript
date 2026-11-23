/* group.h: wait groups.
 *
 * A group watches promises of this thread and reports each as it finishes, so waiting for many costs one step per
 * promise instead of a rescan after every wake. The promise table tells the group when a member finishes
 * (ms_group_finished); a waiter takes finished tags in finishing order with ms_group_next.
 */
#ifndef MS_RUNTIME_CORE_GROUP_H
#define MS_RUNTIME_CORE_GROUP_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "runtime/core/promise.h"

/* How the promises of a waiter joined a group (ms_group_join). */
enum { MS_GROUP_JOINED_ALL = 1, MS_GROUP_JOINED_PARTLY = 2 };

/* Results of ms_promise_run_watched. */
enum { MS_RUN_NOTHING = 0, MS_RUN_RAN = 1, MS_RUN_INTERRUPTED = 2 };

/* A new group; ids start at 1. */
int64_t ms_group_new(void);
/* Adds the promise with `tag`; false when it is already in a group. A finished or closed promise reports at once. */
bool ms_group_add(int64_t group, MsPromise id, int64_t tag);
/* Adds ids[from..count) tagged by their index, unless that was done; answers how they joined. */
int64_t ms_group_join(int64_t group, const MsPromise *ids, size_t count, size_t from);
/* Waits for a finished promise and answers its tag, or -1 when none is left, MS_WAITER_CANCELLED on a cancel. */
int64_t ms_group_next(int64_t group);
/* The tag of a finished promise not reported yet, or -1; never waits. */
int64_t ms_group_poll(int64_t group);
/* Detaches the members and frees the group. */
void ms_group_free(int64_t group);

/* Runs a deferred promise `id` on the caller's stack for a waiter on `group`: while it runs, a member that ends
 * without a value interrupts the run at its next park. `ids[from..count)` join the group at the first park. */
int64_t ms_promise_run_watched(MsPromise id, int64_t group, const MsPromise *ids, size_t count, size_t from);

/* Called by the promise table when a member finished; `failed` when it ended without a value. */
void ms_group_finished(MsPromise id, bool failed);
/* Fills the park hooks into `hooks`. */
void ms_group_hooks(MsSchedHooks *hooks) MS_NONNULL;
/* Frees the tables of this thread. */
void ms_groups_teardown(void);

#endif
