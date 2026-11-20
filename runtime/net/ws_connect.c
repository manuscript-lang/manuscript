/* msstd_ws_connect (ws_connect.h): the argument and status mapping over ms_ws_dial. */
#include "ws_connect.h"

#include <stdlib.h>

#include "../std/abi.h"
#include "headers.h"
#include "ms_rt/sys.h"
#include "ms_sched.h"
#include "status.h"
#include "ws_dial.h"
#include "ws_natives.h"

static MsBytes bytes_of_str(const MsStr *text) { return ms_bytes_of((const uint8_t *)msrt_str_data(text), msrt_str_len(text)); }

/* The runtime status for a handshake status; a cancelled wait ends the native through the scheduler. */
static uint8_t finish(MsWsStatus status, const char *why, MsStr *err) {
    switch (status) {
    case MS_WSS_OK: return STATUS_OK;
    case MS_WSS_CLOSED: return STATUS_CLOSED;
    case MS_WSS_INVALID_INPUT: return STATUS_INVALID_INPUT;
    case MS_WSS_LIMIT: return STATUS_LIMIT_EXCEEDED;
    case MS_WSS_INVALID_DATA: return STATUS_INVALID_DATA;
    case MS_WSS_TIMEOUT: return STATUS_TIMED_OUT;
    case MS_WSS_CANCELLED:
        ms_sched_cancel_return();
        return STATUS_OK;
    case MS_WSS_NOMEM:
        ms_net_write_text(err, "out of memory");
        return STATUS_FAILED;
    case MS_WSS_FAILED: break;
    }
    ms_net_write_text(err, why != NULL ? why : "websocket handshake failed");
    return STATUS_FAILED;
}

uint8_t msstd_ws_connect(const void *conn, const MsStr *authority, const MsStr *target, const void *headers,
                         const MsVec *subprotocols, uint8_t compression, uint8_t has_max, int64_t max,
                         uint8_t has_timeout, int64_t timeout, void **out, MsStr *err) {
    if (has_max != 0 && max < 0) {
        return STATUS_INVALID_INPUT;
    }
    const MsStr *names = subprotocols->ptr;
    MsBytes *protocols = malloc((subprotocols->len + 1) * sizeof *protocols);
    if (protocols == NULL) {
        return finish(MS_WSS_NOMEM, NULL, err);
    }
    for (size_t i = 0; i < subprotocols->len; i++) {
        protocols[i] = bytes_of_str(&names[i]);
    }
    const MsWsDial dial = {.authority = bytes_of_str(authority),
                           .target = bytes_of_str(target),
                           .protocols = protocols,
                           .protocol_count = subprotocols->len,
                           .headers = headers != NULL ? ms_headers_of(headers) : NULL,
                           .compression = compression != 0,
                           .max_message_bytes = has_max != 0 ? (uint64_t)max : UINT64_MAX};
    MsWsSocket *session = NULL;
    const char *why = NULL;
    const MsWsStatus status = ms_ws_dial((MsObj *)conn, &dial, ms_net_deadline_of(has_timeout, timeout), &session, &why);
    free(protocols);
    if (status != MS_WSS_OK) {
        return finish(status, why, err);
    }
    MsObj *handle = ms_ws_handle_new(session);
    if (handle == NULL) {
        return finish(MS_WSS_NOMEM, NULL, err);
    }
    *out = handle;
    return STATUS_OK;
}
