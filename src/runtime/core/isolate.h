/* isolate.h: the registry of scheduler threads (isolates) and the mail they send each other. Internal to
 * src/runtime/core.
 *
 * Each isolate has its own scheduler, promise table and poller; threads share only this registry, in which an isolate
 * is a slot with a lock-free mail stack, a load figure and a way to wake its poller. A thread sends mail with
 * ms_isolate_post; the owner takes it all at once when its scheduler next looks (between task switches, and when it
 * would block). Sending wakes a poller that is blocked, and costs nothing more when the target is busy.
 */
#ifndef MS_CORE_ISOLATE_H
#define MS_CORE_ISOLATE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "ms_rt/safe.h"

/* Isolate indices fit the promise id's six bits and the token id's twelve. */
#define MS_MAX_ISOLATES 63u
#define MS_NO_ISOLATE UINT32_MAX

typedef enum MsMailKind {
    MS_MAIL_TOKEN = 1, /* a = token id, b = value: post it to the token's owner */
    MS_MAIL_PROMISE,   /* the promise table's events (words below are its own) */
    MS_MAIL_CALL,      /* run `fn(argument)` as a short task on the target */
    MS_MAIL_STOP,      /* a = signal: a stop request for the target's scheduler */
    MS_MAIL_IDLE,      /* idle connections (src/runtime/net/idle.c): a = operation, p = its row */
    MS_MAIL_KIND_COUNT,
} MsMailKind;

/* One message. Allocated by the sender with msrt_alloc and freed by the receiver (or by the sender when the post
 * fails). The payload words belong to the module that defines the kind. */
typedef struct MsMail {
    struct MsMail *next;
    uint32_t kind;
    uint32_t from; /* the sender's isolate, or MS_NO_ISOLATE for a thread without one */
    uint64_t a;
    uint64_t b;
    uint64_t c;
    void *p;
    const void *q;
} MsMail;

/* How a poller blocked in its wait is woken from another thread (uv_async_send for the libuv reactor). */
typedef void (*MsWakeFn)(void *argument);

/* How a module outside the scheduler handles the mail of its own kind: `handle` takes the mail and frees it (on the
 * owner's thread, between task switches); `discard` frees what an undelivered mail owns (the node is freed by the
 * caller). Set once, before any such mail is sent. */
typedef struct MsMailKindOps {
    void (*handle)(MsMail *mail);
    void (*discard)(MsMail *mail);
} MsMailKindOps;
void ms_isolate_set_mail_kind(uint32_t kind, const MsMailKindOps *ops);
const MsMailKindOps *ms_isolate_mail_kind(uint32_t kind);

/* Registers the calling thread; returns its index, or MS_NO_ISOLATE when all are taken. */
uint32_t ms_isolate_register(MsWakeFn wake, void *argument);
/* Ends the registration; mail that arrives afterwards is refused. Mail still queued goes to `discard` (may be
 * NULL) to free its payload, then its node is freed. */
void ms_isolate_unregister(uint32_t index, void (*discard)(MsMail *mail));
/* This thread's index, or MS_NO_ISOLATE. */
uint32_t ms_isolate_self(void);
/* Whether `index` is a live isolate. */
bool ms_isolate_live(uint32_t index);
/* Live isolates, and a figure for how busy `index` is (tasks it runs; set with ms_isolate_set_load). */
uint32_t ms_isolate_count(void);
uint32_t ms_isolate_load(uint32_t index);
void ms_isolate_set_load(uint32_t load);

/* Queues `mail` on `target` and wakes it if it sleeps. False when the target is gone (the caller keeps `mail`). Safe
 * from any thread. */
MS_NODISCARD bool ms_isolate_post(uint32_t target, MsMail *mail) MS_NONNULL;
/* The mail queued for the calling isolate, oldest first, or NULL. Owner only. */
MsMail *ms_isolate_take(void);
/* Whether mail waits (a cheap check for the scheduler's loop). Owner only. */
bool ms_isolate_has_mail(void);
/* Before blocking in the poller: marks the isolate as sleeping; false when mail is already waiting, in which case
 * the caller must not block. Pair with ms_isolate_idle_leave. */
MS_NODISCARD bool ms_isolate_idle_enter(void);
void ms_isolate_idle_leave(void);

/* The isolates that rest: bit `i` is set when isolate `i` is live and sleeping in its poller. `live` receives the
 * live isolates in the same bits. Safe from any thread (the watcher reads it). */
uint64_t ms_isolate_resting(uint64_t *live);

/* Wakes one sleeping isolate other than `except`; false when none sleeps. Safe from any thread. */
bool ms_isolate_wake_one(uint32_t except);

/* Posts `value` to a token of another isolate (or this one): the program-ABI msrt_token_post_remote. */
void ms_token_post_remote(uint64_t token, uint64_t value);

#endif
