/* The reactor's edge-triggered descriptor registrations (edge.c): a connection socket is added to the thread's epoll
 * set once and stays there, so waiting for its bytes costs no system call of its own and one epoll_wait reports every
 * ready connection of a pass. Only the thread that owns the reactor uses a MsEdge.
 *
 * The protocol of the caller (net_conn.c) is the one of every edge-triggered reader: clear the ready bits, try the
 * system call, and when it would block (or returned less than it asked for) wait for the next edge. An edge reports
 * that something changed since the descriptor was last drained, never that data is there now, so a wake-up can be
 * spurious and the caller retries. Events are only taken inside ms_edge_drain, which runs on the owning thread between
 * tasks, so no edge can arrive between a failed system call and the wait that follows it.
 */
#ifndef MS_RUNTIME_IO_EDGE_H
#define MS_RUNTIME_IO_EDGE_H

#include <uv.h>

#include "runtime/io/reactor.h"
#include "runtime/io/ring.h"

typedef struct MsEdge MsEdge;

/* Whether this platform has edge-triggered registrations (epoll on Linux). */
bool ms_edge_supported(void);

/* The registrations of one reactor: `loop` also watches the epoll descriptor, so a blocking pass ends when one of them
 * is ready, and the edges that pass takes are queued on `ring`. NULL when unsupported or when the system refuses. */
MsEdge *ms_edge_open(uv_loop_t *loop, MsIoRing *ring);
void ms_edge_close(MsEdge *edge);

/* Registers `fd` for `cookie` unless it already is (a descriptor number reused by another connection is registered
 * again), and clears the ready bits in `bits`. False when the descriptor cannot be registered. */
bool ms_edge_reset(MsEdge *edge, int fd, uint64_t cookie, uint32_t bits);

/* Whether an edge for one of `bits` was taken since ms_edge_reset (or the registration). */
bool ms_edge_ready(const MsEdge *edge, int fd, uint32_t bits);

/* Waits for the next edge: when one of `bits` is already held, queues it on `ring` (false when the ring is full);
 * otherwise records the interest, to be reported by ms_edge_drain. */
bool ms_edge_arm(MsEdge *edge, int fd, uint32_t bits, MsIoRing *ring);

/* Drops the interest of `fd` (the registration stays). */
void ms_edge_disarm(MsEdge *edge, int fd);

/* Ends the registration of `fd`. */
void ms_edge_forget(MsEdge *edge, int fd);

/* Takes the edges the kernel has queued without blocking and queues events for the armed descriptors on `ring`.
 * Returns how many events it queued. */
size_t ms_edge_drain(MsEdge *edge, MsIoRing *ring);

#endif
