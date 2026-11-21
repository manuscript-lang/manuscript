/* cancel.h: cancel switches (@std/concurrency/promise.ms `Cancel`). Internal to src/runtime/core.
 *
 * A switch is a one-shot signal. Promises listen to it (ms_promise_on_cancel); firing it cancels every listener. Any isolate
 * may fire, read, listen to or free a switch: the fired flag is shared, and the owner (the isolate that made it) is mailed
 * the rest.
 * Ids are `isolate << 56 | generation << 32 | (slot + 1)`. A fired switch stays readable until freed. The
 * listeners of a switch form a doubly linked list threaded through arrays indexed by the listener's promise row,
 * so listening, leaving and firing cost one step per promise.
 */
#ifndef MS_CORE_CANCEL_H
#define MS_CORE_CANCEL_H

#include <stdbool.h>
#include <stdint.h>

#include "isolate.h"
#include "promise.h"

/* Mail for a switch's owner (a promise-kind mail: a = MS_MAIL_SWITCH | sub << 8, b = the switch, c = the promise). */
#define MS_MAIL_SWITCH 0x42u
/* Mail for the owner of a promise: cancel it (b = the promise). */
#define MS_MAIL_CANCEL_ID 0x43u
enum { SWITCH_FIRE = 1, SWITCH_REGISTER, SWITCH_UNREGISTER, SWITCH_FREE };

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

/* Runs a switch operation another isolate mailed to its owner; takes `mail`. */
void ms_cancel_serve(MsMail *mail);

void ms_cancel_teardown(void);

#endif
