/* runtime/std/net_loop.h: the network's libuv loop. One loop on one thread of its own runs every socket handle of
 * @std/net; a native hands it an operation and parks its task on a token the loop posts, the way a child process does
 * (child.h). The loop thread never calls the runtime.
 *
 * An operation is owned by two parties, the waiting task and the loop. A task that gives up (a timeout, a stop request)
 * abandons it: the loop finishes it alone and drops its result. The state word decides which side a finished operation
 * belongs to, so a result is never both delivered and dropped. */
#ifndef MS_RUNTIME_STD_NET_LOOP_H
#define MS_RUNTIME_STD_NET_LOOP_H

#include <stdatomic.h>
#include <uv.h>

#include "base/safe.h"

typedef struct MsNetOp MsNetOp;

struct MsNetOp {
  MsNetOp *next;                   /* the queue link */
  void (*start)(MsNetOp *op);      /* on the loop thread: begins the work; calls ms_net_op_done when it ends */
  void (*abandon)(MsNetOp *op);    /* on the loop thread: the waiter gave up; stop the work (may be NULL) */
  void (*release)(MsNetOp *op);    /* frees what the operation holds, not the operation (may be NULL) */
  uint64_t token;                  /* the waiter's token, 0 when nobody waits */
  atomic_uint references;
  atomic_int state;                /* MS_NET_OP_* */
  int status;                      /* a libuv status; 0 on success */
  bool finished;                   /* loop thread only: ms_net_op_done ran */
};

enum { MS_NET_OP_PENDING = 0, MS_NET_OP_DONE = 1, MS_NET_OP_ABANDONED = 2 };

/* How a wait ended. */
typedef enum MsNetWait { MS_NET_WAIT_DONE, MS_NET_WAIT_TIMED_OUT, MS_NET_WAIT_CANCELLED } MsNetWait;

/* A status of ours beside libuv's: the handle was closed. */
enum { MS_NET_CLOSED = -100000 };

/* Allocates an operation of `size` bytes (a MsNetOp first) with its callbacks set. */
MS_NODISCARD void *ms_net_op_new(size_t size, void (*start)(MsNetOp *), void (*abandon)(MsNetOp *),
                                 void (*release)(MsNetOp *));

/* Runs `op` on the loop and parks the task for at most `timeout_ns` (negative: no limit). On MS_NET_WAIT_DONE the
 * caller reads `op->status` and its results, then drops the operation with ms_net_op_free. Otherwise the operation
 * belongs to the loop and the caller must not touch it. */
MS_NODISCARD MsNetWait ms_net_run(MsNetOp *op, int64_t timeout_ns);
void ms_net_op_free(MsNetOp *op);

/* Runs `op` without waiting for it; the loop frees it when it ends. */
void ms_net_post(MsNetOp *op);

/* On the loop thread: `op` ended with `status`. A waiter is woken; an abandoned operation is freed. */
void ms_net_op_done(MsNetOp *op, int status);

/* The loop, for handle initialisation on the loop thread. */
uv_loop_t *ms_net_loop(void);

/* Ends the loop thread and frees the loop, for a process that ends with balanced books (MS_FREE_AT_EXIT); a no-op when no
 * operation ever ran. No operation may start afterwards. */
void ms_net_release_all(void);

/* The relative timeout of a native's optional timeout argument; negative for none. */
int64_t ms_net_timeout(uint8_t has_timeout, int64_t timeout);

#endif
