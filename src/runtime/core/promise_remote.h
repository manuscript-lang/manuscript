/* promise_remote.h: the calls on a promise whose id names another isolate's table.
 *
 * The owner answers by mail: the caller mails an Ask, parks (shielded) on a remote token, and the owner runs the
 * operation as a short task on its own table and posts the token. A wait watches instead (the owner posts the token
 * when the promise finishes), so a cancel or a timeout of the waiter needs no reply.
 */
#ifndef MS_RUNTIME_CORE_PROMISE_REMOTE_H
#define MS_RUNTIME_CORE_PROMISE_REMOTE_H

#include "runtime/core/isolate.h"
#include "runtime/core/promise.h"

/* The mail ops of this module (MsMail.a of a MS_MAIL_PROMISE message; promise.c uses the ones below 0x40). */
#define MS_MAIL_ASK 0x40u   /* p = the Ask to run */
#define MS_MAIL_WATCH 0x41u /* b = the promise, c = the remote token to post when it finishes */

/* An id of an isolate that is gone reads as closed. */
bool ms_remote_done(MsPromise id);
int64_t ms_remote_wait(MsPromise id, int64_t timeout_ns);
bool ms_remote_take(MsPromise id, const MsTypeDesc *desc, uint8_t *out);
void ms_remote_cancel(MsPromise id);
void ms_remote_limit(MsPromise id, int64_t timeout_ns);
bool ms_remote_end(MsPromise id);
void ms_remote_drop(MsPromise id);
MsFaultText ms_remote_fault_report(MsPromise id);
MsPromiseProbe ms_remote_probe(MsPromise id);
void ms_remote_on_cancel(MsPromise id, int64_t cancel);
void ms_remote_drain(MsPromise id, int64_t drain, int64_t grace_ns);
void ms_remote_set_grouped(MsPromise id, bool grouped);
/* Runs a deferred promise of the owner now; answers whether it ran. */
bool ms_remote_run_inline(MsPromise id);
/* Asks the owner to post `token` (a MS_TOKEN_REMOTE token of this isolate) when `id` finishes; false when the
 * owner is gone. */
bool ms_remote_watch_post(MsPromise id, uint64_t token);

/* Owner side: runs the Ask of `mail` (taken) as a task of this isolate, and answers a Watch. */
void ms_remote_serve(MsMail *mail);
void ms_remote_watch(MsMail *mail);

#endif
