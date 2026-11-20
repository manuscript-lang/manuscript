/* msstd_ws_connect (ws_connect.h): the argument and status mapping over ms_ws_dial. */
#include "ms_rt/net.h"

#include <stdlib.h>

#include "../std/abi.h"
#include "headers.h"
#include "ms_rt/sys.h"
#include "ms_sched.h"
#include "status.h"
#include "ws_dial.h"
#include "ws_natives.h"


uint8_t msstd_ws_connect(const void *conn, const MsStr *authority, const MsStr *target, const void *headers,
                         const MsVec *subprotocols, uint8_t compression, uint8_t has_max, int64_t max,
                         uint8_t has_timeout, int64_t timeout, void **out, MsStr *err) {
    ms_net_clear_text(err); /* the caller reads the slot for every failure status; only STATUS_FAILED sets text */
    if (has_max != 0 && max < 0) {
        return STATUS_INVALID_INPUT;
    }
    const MsStr *names = subprotocols->ptr;
    MsBytes *protocols = malloc((subprotocols->len + 1) * sizeof *protocols);
    if (protocols == NULL) {
        return ms_ws_finish(MS_WSS_NOMEM, NULL, err);
    }
    for (size_t i = 0; i < subprotocols->len; i++) {
        protocols[i] = msrt_str_bytes(&names[i]);
    }
    const MsWsDial dial = {.authority = msrt_str_bytes(authority),
                           .target = msrt_str_bytes(target),
                           .protocols = protocols,
                           .protocol_count = subprotocols->len,
                           .headers = headers != NULL ? ms_headers_of(headers) : NULL,
                           .compression = compression != 0,
                           .max_message_bytes = has_max != 0 ? (uint64_t)max : UINT64_MAX};
    MsWsSocket *session = NULL;
    const char *why = NULL;
    const MsWsStatus status = ms_ws_dial((const MsObj *)conn, &dial, ms_net_deadline_of(has_timeout, timeout), &session, &why);
    free(protocols);
    if (status != MS_WSS_OK) {
        return ms_ws_finish(status, why, err);
    }
    MsObj *handle = ms_ws_handle_new(session);
    if (handle == NULL) {
        return ms_ws_finish(MS_WSS_NOMEM, NULL, err);
    }
    *out = handle;
    return STATUS_OK;
}
