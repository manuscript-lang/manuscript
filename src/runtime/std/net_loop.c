/* The network loop thread and the operation protocol (see net_loop.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "runtime/std/net_loop.h"

#include "base/alloc.h"
#include "runtime/core/task.h"

static struct {
  uv_once_t once;
  uv_loop_t loop;
  uv_async_t wake;
  uv_mutex_t lock;
  MsNetOp *head; /* queued, oldest first */
  MsNetOp *tail;
  uv_thread_t thread;
} net = {.once = UV_ONCE_INIT};

uv_loop_t *ms_net_loop(void) { return &net.loop; }

static void op_unref(MsNetOp *op) {
  if (atomic_fetch_sub(&op->references, 1) != 1) {
    return;
  }
  if (op->release != NULL) {
    op->release(op);
  }
  if (op->token != 0) {
    (void)ms_token_free(op->token);
  }
  ms_free(op);
}

void ms_net_op_free(MsNetOp *op) { op_unref(op); }

void ms_net_op_done(MsNetOp *op, int status) {
  int expected = MS_NET_OP_PENDING;
  op->status = status;
  op->finished = true;
  if (atomic_compare_exchange_strong(&op->state, &expected, MS_NET_OP_DONE) && op->token != 0) {
    ms_token_post_remote(op->token, 1);
  }
  op_unref(op); /* the loop's reference */
}

/* An abandon request: runs op->abandon on the loop when the operation is still running. */
typedef struct Abandon {
  MsNetOp op;
  MsNetOp *target;
} Abandon;

static void abandon_start(MsNetOp *request) {
  MsNetOp *target = ((Abandon *)request)->target;
  if (!target->finished && target->abandon != NULL) {
    target->abandon(target);
  }
  op_unref(target);
  ms_net_op_done(request, 0);
}

static void drain(uv_async_t *handle) {
  (void)handle;
  for (;;) {
    uv_mutex_lock(&net.lock);
    MsNetOp *op = net.head;
    if (op != NULL) {
      net.head = op->next;
      net.tail = net.head == NULL ? NULL : net.tail;
    }
    uv_mutex_unlock(&net.lock);
    if (op == NULL) {
      return;
    }
    op->start(op);
  }
}

static void run_loop(void *argument) {
  (void)argument;
  (void)uv_run(&net.loop, UV_RUN_DEFAULT);
}

static void start_loop(void) {
  (void)uv_loop_init(&net.loop);
  (void)uv_mutex_init(&net.lock);
  (void)uv_async_init(&net.loop, &net.wake, drain);
  (void)uv_thread_create(&net.thread, run_loop, NULL);
}

static void enqueue(MsNetOp *op) {
  uv_once(&net.once, start_loop);
  op->next = NULL;
  uv_mutex_lock(&net.lock);
  if (net.tail == NULL) {
    net.head = op;
  } else {
    net.tail->next = op;
  }
  net.tail = op;
  uv_mutex_unlock(&net.lock);
  (void)uv_async_send(&net.wake);
}

void *ms_net_op_new(size_t size, void (*start)(MsNetOp *), void (*abandon)(MsNetOp *), void (*release)(MsNetOp *)) {
  MsNetOp *op = ms_alloc_zeroed(size);
  op->start = start;
  op->abandon = abandon;
  op->release = release;
  atomic_init(&op->references, 2); /* the waiter's and the loop's */
  atomic_init(&op->state, MS_NET_OP_PENDING);
  return op;
}

void ms_net_post(MsNetOp *op) {
  atomic_store(&op->state, MS_NET_OP_ABANDONED);
  atomic_fetch_sub(&op->references, 1); /* nobody waits */
  enqueue(op);
}

MsNetWait ms_net_run(MsNetOp *op, int64_t timeout_ns) {
  op->token = ms_token_new(MS_TOKEN_REMOTE);
  enqueue(op);
  uint64_t value = 0;
  uint32_t result = 0;
  (void)ms_token_park(op->token, timeout_ns, &value, &result);
  if (result == 0) {
    return MS_NET_WAIT_DONE;
  }
  int expected = MS_NET_OP_PENDING;
  if (!atomic_compare_exchange_strong(&op->state, &expected, MS_NET_OP_ABANDONED)) {
    return MS_NET_WAIT_DONE; /* it finished while the wait ended: its result is ours */
  }
  Abandon *request = ms_net_op_new(sizeof *request, abandon_start, NULL, NULL);
  atomic_fetch_add(&op->references, 1);
  request->target = op;
  atomic_store(&request->op.state, MS_NET_OP_ABANDONED);
  atomic_fetch_sub(&request->op.references, 1);
  enqueue(&request->op);
  op_unref(op); /* the waiter's reference */
  return (result & MS_WAIT_CANCELLED) != 0 ? MS_NET_WAIT_CANCELLED : MS_NET_WAIT_TIMED_OUT;
}

int64_t ms_net_timeout(uint8_t has_timeout, int64_t timeout) { return has_timeout != 0 && timeout >= 0 ? timeout : -1; }
