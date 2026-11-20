/* cancel.h: cancel switches (@std/concurrency/promise.ms `Cancel`). Internal to runtime/core.
 *
 * A switch is a one-shot signal. Promises listen to it (ms_promise_on_cancel); firing it cancels every listener.
 * Ids are `isolate << 56 | generation << 32 | (slot + 1)`. A fired switch stays readable until freed. The
 * listeners of a switch form a doubly linked list threaded through arrays indexed by the listener's promise row,
 * so listening, leaving and firing cost one step per promise.
 */
#ifndef MS_CORE_CANCEL_H
#define MS_CORE_CANCEL_H

#include <stdbool.h>
#include <stdint.h>

#include "promise.h"

int64_t ms_cancel_new(void);
/* Fires the switch: every listener is cancelled. Firing twice does nothing. */
void ms_cancel_fire(int64_t id);
/* Whether the switch has fired; a freed switch reads as not fired. */
bool ms_cancel_fired(int64_t id);
/* Frees the switch; the promises that listened keep running. */
void ms_cancel_free(int64_t id);

/* Adds `promise` as a listener of `id`; true when the switch already fired (the caller cancels at once). A switch that
 * does not exist adds nothing. */
bool ms_cancel_register(int64_t id, MsPromise promise);
/* Removes `promise` from the listeners of `id`. */
void ms_cancel_unregister(int64_t id, MsPromise promise);

void ms_cancel_teardown(void);

#endif
