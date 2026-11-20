/* The HTTP/2 connection natives of ms_rt/xchg.h (H2ConnH): a handle on the shared HTTP/2 state of one connection,
 * which the task running the connection and the accept loop each hold. The state ends with its last handle. */
#include <stdatomic.h>
#include <stdlib.h>

#include "../std/abi.h"
#include "conn_object.h"
#include "exchange_h2.h"
#include "ms_rt/alloc.h"
#include "ms_rt/obj.h"
#include "ms_rt/xchg.h"
#include "status.h"

typedef struct H2State {
    atomic_uint handles;
    MsXchgH2Conn *conn; /* the owner's reference */
    MsObj *row;         /* an alias handle on the connection, so its table outlives the serve loop */
} H2State;

typedef struct H2Handle {
    MsObj header;
    H2State *state;
} H2Handle;

static void handle_drop(MsObj *object) {
    H2Handle *handle = (H2Handle *)object;
    if (atomic_fetch_sub(&handle->state->handles, 1) == 1) {
        ms_xchg_h2_conn_free(handle->state->conn);
        msrt_obj_drop(handle->state->row);
        msrt_free(handle->state);
    }
    msrt_free(handle);
}

static MsObj *handle_new(H2State *state) {
    H2Handle *handle = msrt_alloc(sizeof *handle);
    handle->header.clone = NULL;
    handle->header.drop = handle_drop;
    handle->state = state;
    return &handle->header;
}

static H2State *state_of(const void *handle) { return ((const H2Handle *)handle)->state; }

static uint32_t limit_of(int64_t value) {
    if (value <= 0) {
        return 0;
    }
    return value > UINT32_MAX ? UINT32_MAX : (uint32_t)value;
}

uint8_t msstd_h2_open(const void *conn, int64_t max_streams, int64_t max_header_list, int64_t stream_window, int64_t connection_window, uint8_t has_idle, int64_t idle, void **out, MsStr *err) {
    ms_net_clear_text(err);
    const MsNetConn *core = ms_netconn_of(conn);
    const MsH2Limits limits = {limit_of(max_streams) != 0 ? limit_of(max_streams) : 100, limit_of(max_header_list), limit_of(stream_window), limit_of(connection_window)};
    MsXchgH2Conn *h2 = ms_xchg_h2_conn_new(ms_netconn_table(core), ms_netconn_id(core), &limits, has_idle != 0 && idle > 0 ? idle : 0);
    if (h2 == NULL) {
        return ms_net_finish(MS_NET_FAILED, 0, err);
    }
    H2State *state = msrt_alloc_zeroed(sizeof *state);
    atomic_init(&state->handles, 1);
    state->conn = h2;
    state->row = ms_netconn_alias(conn);
    *out = handle_new(state);
    return STATUS_OK;
}

uint8_t msstd_h2_run(const void *h2, MsStr *err) {
    ms_net_clear_text(err);
    const MsNetStatus status = ms_xchg_h2_conn_run(state_of(h2)->conn);
    return status == MS_NET_CANCELLED ? ms_net_finish(status, 0, err) : STATUS_OK;
}

uint8_t msstd_h2_next(const void *h2, uint8_t has_timeout, int64_t timeout, void **out, MsStr *err) {
    ms_net_clear_text(err);
    MsXchgH2 *request = NULL;
    const MsNetStatus status = ms_xchg_h2_conn_next(state_of(h2)->conn, ms_net_deadline_of(has_timeout, timeout), &request);
    if (status == MS_NET_CLOSED) {
        return STATUS_NONE;
    }
    if (status != MS_NET_OK) {
        return ms_net_finish(status, 0, err);
    }
    MsObj *exchange = ms_exchange_from_h2(request);
    if (exchange == NULL) {
        ms_xchg_h2_drop(request);
        return ms_net_finish(MS_NET_FAILED, 0, err);
    }
    *out = exchange;
    return STATUS_OK;
}

void msstd_h2_drain(const void *h2) { ms_xchg_h2_conn_drain(state_of(h2)->conn); }

void *msstd_h2_share(const void *h2) {
    H2State *state = state_of(h2);
    atomic_fetch_add(&state->handles, 1);
    return handle_new(state);
}
