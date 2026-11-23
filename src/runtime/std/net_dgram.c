/* Datagram sockets: receiving and sending UDP on the network loop (see net_core.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include <string.h>

#include "base/alloc.h"
#include "base/bytes.h"
#include "runtime/std/fail.h"
#include "runtime/std/net_calls.h"
#include "runtime/std/net_conn.h"
#include "runtime/std/net_core.h"
#include "runtime/std/net_dgram.h"

enum { RECEIVE_DEFAULT = 64 * 1024, RECEIVE_LIMIT = 64 * 1024 };

typedef struct DgramOp {
  MsNetOp op;
  MsNetCore *core; /* a reference */
  uint8_t *data;   /* receive: the buffer; send: a copy of the payload */
  size_t capacity;
  size_t length;
  MsString sender;
  struct sockaddr_storage target;
  uv_udp_send_t request;
  bool sending;
} DgramOp;

static void dgram_release(MsNetOp *op) {
  DgramOp *dgram = (DgramOp *)op;
  ms_net_core_unref(dgram->core);
  ms_string_release(&dgram->sender);
  ms_free(dgram->data);
}

static void on_alloc(uv_handle_t *handle, size_t suggested, uv_buf_t *buffer) {
  DgramOp *dgram = ((MsNetCore *)(void *)handle)->reading;
  (void)suggested;
  *buffer = uv_buf_init((char *)dgram->data, (unsigned int)dgram->capacity);
}

static void on_receive(uv_udp_t *handle, ssize_t count, const uv_buf_t *buffer, const struct sockaddr *from,
                       unsigned flags) {
  MsNetCore *core = (MsNetCore *)(void *)handle;
  DgramOp *dgram = core->reading;
  (void)buffer;
  (void)flags;
  if (dgram == NULL || (count == 0 && from == NULL)) {
    return;
  }
  core->reading = NULL;
  (void)uv_udp_recv_stop(handle);
  if (count < 0) {
    ms_net_op_done(&dgram->op, (int)count);
    return;
  }
  dgram->length = (size_t)count;
  if (from != NULL) {
    ms_net_address_text(from, &dgram->sender);
  }
  ms_net_op_done(&dgram->op, 0);
}

static void on_sent(uv_udp_send_t *request, int status) {
  DgramOp *dgram = request->data;
  ms_net_op_done(&dgram->op, status);
}

static void dgram_start(MsNetOp *op) {
  DgramOp *dgram = (DgramOp *)op;
  MsNetCore *core = dgram->core;
  if (atomic_load(&core->closed)) {
    ms_net_op_done(op, MS_NET_CLOSED);
  } else if (dgram->sending) {
    dgram->request.data = dgram;
    uv_buf_t buffer = uv_buf_init((char *)dgram->data, (unsigned int)dgram->length);
    const int code = uv_udp_send(&dgram->request, &core->h.udp, &buffer, 1,
                                 (const struct sockaddr *)(const void *)&dgram->target, on_sent);
    if (code != 0) {
      ms_net_op_done(op, code);
    }
  } else if (core->reading != NULL) {
    ms_net_op_done(op, UV_EBUSY);
  } else {
    core->reading = dgram;
    const int code = uv_udp_recv_start(&core->h.udp, on_alloc, on_receive);
    if (code != 0) {
      core->reading = NULL;
      ms_net_op_done(op, code);
    }
  }
}

static void dgram_abandon(MsNetOp *op) {
  DgramOp *dgram = (DgramOp *)op;
  if (dgram->core->reading == dgram) {
    dgram->core->reading = NULL;
    (void)uv_udp_recv_stop(&dgram->core->h.udp);
    ms_net_op_done(op, UV_ECANCELED);
  }
}

void ms_net_dgram_close_ops(MsNetCore *core) {
  if (core->kind != MS_NET_DATAGRAM || core->reading == NULL) {
    return;
  }
  DgramOp *dgram = core->reading;
  core->reading = NULL;
  (void)uv_udp_recv_stop(&core->h.udp);
  ms_net_op_done(&dgram->op, MS_NET_CLOSED);
}

static DgramOp *dgram_new(MsNetCore *core, bool sending) {
  DgramOp *dgram = ms_net_op_new(sizeof *dgram, dgram_start, dgram_abandon, dgram_release);
  atomic_fetch_add(&core->references, 1);
  dgram->core = core;
  dgram->sending = sending;
  dgram->sender = ms_string_empty();
  return dgram;
}

uint8_t ms_net_datagram_receive(const MsObj *handle, uint8_t has_max, int64_t max, uint8_t has_timeout,
                                   int64_t timeout, MsDatagramWire *out, MsString *err) {
  *err = ms_string_empty();
  if (has_max != 0 && max < 0) {
    return MS_STATUS_INVALID_INPUT;
  }
  const size_t capacity = has_max != 0 ? (max > RECEIVE_LIMIT ? RECEIVE_LIMIT : (size_t)max) : RECEIVE_DEFAULT;
  DgramOp *dgram = dgram_new(ms_net_handle_core(handle), false);
  dgram->capacity = capacity > 0 ? capacity : 1;
  dgram->data = ms_alloc(dgram->capacity);
  const MsNetWait wait = ms_net_run(&dgram->op, ms_net_timeout(has_timeout, timeout));
  const uint8_t status = ms_net_finish(wait, wait == MS_NET_WAIT_DONE ? dgram->op.status : 0, "receive", err);
  if (wait != MS_NET_WAIT_DONE) {
    return status;
  }
  if (status == MS_STATUS_OK) {
    const size_t kept = dgram->length < capacity ? dgram->length : capacity;
    out->data = ms_bytes_from_span(ms_span_of(dgram->data, kept));
    out->sender = ms_string_clone(&dgram->sender);
  }
  ms_net_op_free(&dgram->op);
  return status;
}

uint8_t msstd_net_datagram_receive(const MsObj *handle, uint8_t has_max, int64_t max, uint8_t has_timeout,
                                   int64_t timeout, MsDatagramWire *out, MsString *err) {
  return ms_native_return(ms_net_datagram_receive(handle, has_max, max, has_timeout, timeout, out, err), err);
}

uint8_t ms_net_datagram_send_bytes(const MsObj *handle, const MsBytes *data, const MsString *address,
                                      uint8_t has_timeout, int64_t timeout, MsString *err) {
  struct sockaddr_storage target;
  *err = ms_string_empty();
  if (!ms_net_parse_literal(ms_string_span(address), &target)) {
    return MS_STATUS_INVALID_INPUT;
  }
  DgramOp *dgram = dgram_new(ms_net_handle_core(handle), true);
  dgram->target = target;
  dgram->length = data->len;
  dgram->data = ms_alloc(data->len + 1);
  if (data->len != 0) {
    memcpy(dgram->data, data->ptr, data->len);
  }
  const MsNetWait wait = ms_net_run(&dgram->op, ms_net_timeout(has_timeout, timeout));
  const uint8_t status = ms_net_finish(wait, wait == MS_NET_WAIT_DONE ? dgram->op.status : 0, "send", err);
  if (wait == MS_NET_WAIT_DONE) {
    ms_net_op_free(&dgram->op);
  }
  return status;
}

uint8_t msstd_net_datagram_send_bytes(const MsObj *handle, const MsBytes *data, const MsString *address,
                                      uint8_t has_timeout, int64_t timeout, MsString *err) {
  return ms_native_return(ms_net_datagram_send_bytes(handle, data, address, has_timeout, timeout, err), err);
}

void msstd_net_datagram_address(const MsObj *handle, MsString *out) {
  *out = ms_string_clone(&ms_net_handle_core(handle)->local);
}

void msstd_net_datagram_close(const MsObj *handle) { ms_net_handle_close(handle); }
void msstd_net_datagram_close_if_last(const MsObj *handle) { ms_net_handle_close_if_last(handle); }
MsObj *msstd_net_datagram_share(const MsObj *handle) { return ms_net_handle_share(handle); }
