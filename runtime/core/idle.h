/* idle.h: connections between requests, held by the scheduler without a task. Internal to runtime/core.
 *
 * A server whose connection tasks park between requests cannot move a waiting connection: a started task never moves.
 * So after a response the connection task ends and parks the connection here instead, as a row: its descriptor is
 * watched by the thread's reactor as a task-free promise, and when the descriptor turns readable the pool starts the
 * server's `next` closure (it reads the head, serves the request and parks the connection again) as a promise of this
 * thread. A row between requests is thread-neutral state, so a resting thread can take the rows of a thread that a
 * long handler holds up: it watches a duplicate of the descriptor with its own reactor and starts `next` itself.
 *
 * The watcher (watch.h) finds the held-up thread; nothing here runs inside it. See proposals/connection-stealing-in-c.md.
 */
#ifndef MS_CORE_IDLE_H
#define MS_CORE_IDLE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "ms_rt/obj.h"
#include "ms_rt/safe.h"

/* What the pool asks of the layer that owns the connections. All run on one thread at a time. */
typedef struct MsIdleOps {
    /* Whether input is already held for `subject` (a pipelined request): its next read returns without the descriptor
     * being readable, so the pool starts it at once instead of waiting. */
    bool (*buffered)(void *subject);
    /* `subject` now uses `fd`, a duplicate of its socket (the pool took the row to another thread). */
    void (*moved)(void *subject, int fd);
    /* A descriptor for the same socket, or -1. */
    int (*duplicate)(int fd);
    /* Closes a descriptor the pool no longer needs; the socket stays open while another descriptor of it does. */
    void (*release)(int fd);
    /* Ends the connection (an idle timeout, a drain, a stopping server). */
    void (*close)(void *subject);
} MsIdleOps;

/* Parks the connection `subject` (a handle the pool now owns and drops, with `next`, when it starts a request or
 * closes) on `fd` for at most `timeout_ns` (negative: no limit). `group` names the server, for ms_idle_drain.
 * `next` is a function value taking no arguments, started as a promise of the thread that serves the request. False
 * when the connection cannot be watched; the caller keeps both objects and closes the connection. */
MS_NODISCARD bool ms_idle_park(const MsIdleOps *ops, void *subject, int fd, MsObj *next, uintptr_t group,
                               int64_t timeout_ns);
/* A group names one server's connections: a number to pass to ms_idle_park, and to the calls below. It lives to the end
 * of the process (a few bytes per server). */
uintptr_t ms_idle_group_new(void);
/* Closes every idle connection of `group` now; requests in flight finish. Safe from any thread. */
void ms_idle_drain(uintptr_t group);
/* The requests of `group` that are running or waiting to run. */
size_t ms_idle_inflight(uintptr_t group);
/* Asks the requests in flight of `group`, on every thread, to end as a cancelled promise does. */
void ms_idle_cancel(uintptr_t group);
/* Ends the rows this thread owns, as its scheduler ends. */
void ms_idle_teardown(void);
/* Idle connections held for `isolate` (a cheap count for the watcher's hook). */
uint32_t ms_idle_count(uint32_t isolate);

#endif
