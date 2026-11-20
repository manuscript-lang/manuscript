/* The natives of ms_rt/websocket.h: the SocketH handle and its calls, a thin layer over ws_socket.h. */
#include "ms_rt/websocket.h"

#include <string.h>

#include "../std/abi.h"
#include "conn_object.h"
#include "ms_rt/alloc.h"
#include "ms_sched.h"
#include "ws.h"
#include "ws_natives.h"

typedef struct SocketHandle {
    MsObj header;
    MsWsSocket *socket;
} SocketHandle;

static void handle_drop(MsObj *object) {
    SocketHandle *handle = (SocketHandle *)object;
    ms_ws_socket_release(handle->socket);
    msrt_free(handle);
}

MsObj *ms_ws_handle_new(MsWsSocket *socket) {
    SocketHandle *handle = msrt_alloc(sizeof *handle);
    if (handle == NULL) {
        ms_ws_socket_release(socket);
        return NULL;
    }
    handle->header.clone = NULL;
    handle->header.drop = handle_drop;
    handle->socket = socket;
    return &handle->header;
}

static MsWsSocket *socket_of(const void *handle) { return ((const SocketHandle *)handle)->socket; }

static void write_text(MsStr *out, const char *text) {
    if (out != NULL) {
        msrt_string_from_bytes((const uint8_t *)text, strlen(text), out);
    }
}

/* The runtime status for a session status. A cancelled wait ends the native through the scheduler, so the caller has
 * released everything it holds before this runs. */
static uint8_t finish(const MsWsSocket *socket, MsWsStatus status, MsStr *err) {
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
        write_text(err, "out of memory");
        return STATUS_FAILED;
    case MS_WSS_FAILED: break;
    }
    write_text(err, ms_ws_socket_error(socket));
    return STATUS_FAILED;
}

uint8_t msstd_websocket_send_bytes(const void *handle, const MsVec *data, uint8_t text, MsStr *err) {
    MsWsSocket *socket = socket_of(handle);
    return finish(socket, ms_ws_socket_send(socket, ms_bytes_of(data->ptr, data->len), text != 0, -1), err);
}

uint8_t msstd_websocket_ping_bytes(const void *handle, const MsVec *data, MsStr *err) {
    MsWsSocket *socket = socket_of(handle);
    return finish(socket, ms_ws_socket_ping(socket, ms_bytes_of(data->ptr, data->len)), err);
}

uint8_t msstd_websocket_ping(const void *handle, const MsStr *data, MsStr *err) {
    MsWsSocket *socket = socket_of(handle);
    return finish(socket, ms_ws_socket_ping(socket, ms_bytes_of((const uint8_t *)msrt_str_data(data), msrt_str_len(data))), err);
}

uint8_t msstd_websocket_receive(const void *handle, MsWebSocketMessage *out, MsStr *err) {
    MsWsSocket *socket = socket_of(handle);
    MsWsMessage message = {0};
    bool ended = false;
    const MsWsStatus status = ms_ws_socket_receive(socket, -1, &message, &ended);
    if (status != MS_WSS_OK) {
        return finish(socket, status, err);
    }
    if (ended) {
        return STATUS_NONE;
    }
    msrt_write_bytes(&out->data, message.data.ptr, message.data.len);
    out->text = message.text ? 1 : 0;
    return STATUS_OK;
}

void msstd_websocket_close(const void *handle) { ms_ws_socket_close(socket_of(handle)); }

void *msstd_websocket_share(const void *handle) {
    MsWsSocket *socket = ms_ws_socket_retain(socket_of(handle));
    return ms_ws_handle_new(socket);
}

void msstd_websocket_close_if_last(const void *handle) {
    MsWsSocket *socket = socket_of(handle);
    if (ms_ws_socket_refs(socket) == 1) {
        ms_ws_socket_close(socket);
    }
}

void msstd_websocket_subprotocol(const void *handle, MsStr *out) {
    const MsBytes name = ms_ws_socket_subprotocol(socket_of(handle));
    msrt_string_from_bytes(name.ptr, name.len, out);
}

uint8_t msstd_ws_server_new(const void *conn, uint8_t compress, const MsStr *subprotocol, uint8_t has_max, int64_t max,
                            void **out, MsStr *err) {
    if (has_max != 0 && max <= 0) {
        return STATUS_INVALID_INPUT;
    }
    MsObj *alias = ms_netconn_alias(conn);
    if (alias == NULL) {
        write_text(err, "out of memory");
        return STATUS_FAILED;
    }
    const MsWsConfig config = {
        .max_message_bytes = has_max != 0 ? (uint64_t)max : UINT64_MAX,
        .compress = compress != 0,
        .subprotocol = ms_bytes_of((const uint8_t *)msrt_str_data(subprotocol), msrt_str_len(subprotocol)),
    };
    MsWsSocket *socket = ms_ws_socket_new(alias, MS_WS_ROLE_SERVER, &config);
    if (socket == NULL) {
        alias->drop(alias);
        write_text(err, "out of memory");
        return STATUS_FAILED;
    }
    *out = ms_ws_handle_new(socket);
    return *out != NULL ? STATUS_OK : STATUS_FAILED;
}

uint8_t msstd_ws_accept_key(const MsStr *key, MsStr *out) {
    char accept[29];
    if (ms_ws_accept_key(msrt_str_data(key), msrt_str_len(key), accept) != 0) {
        return STATUS_INVALID_INPUT;
    }
    msrt_string_from_bytes((const uint8_t *)accept, 28, out);
    return STATUS_OK;
}
