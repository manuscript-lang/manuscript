/* The SocketH natives (ws_socket_natives.h): the argument and status mapping over ws_socket.h. */
#include "ms_rt/net.h"

#include "../std/abi.h"
#include "ms_sched.h"
#include "status.h"
#include "ws_natives.h"

static MsBytes bytes_of_vec(const MsVec *data) { return ms_bytes_of(data->ptr, data->len); }

uint8_t ms_ws_finish(MsWsStatus status, const char *why, MsStr *err) {
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

/* Maps a session status; a failed one carries the session's own text. */
static uint8_t finish_session(MsWsSocket *socket, MsWsStatus status, MsStr *err) {
    return ms_ws_finish(status, status == MS_WSS_FAILED ? ms_ws_socket_error(socket) : NULL, err);
}

void msstd_websocket_close(const void *handle) { ms_ws_socket_close(ms_ws_handle_socket(handle)); }

void *msstd_websocket_share(const void *handle) {
    MsWsSocket *socket = ms_ws_handle_socket(handle);
    return ms_ws_handle_new(ms_ws_socket_retain(socket));
}

void msstd_websocket_close_if_last(const void *handle) {
    MsWsSocket *socket = ms_ws_handle_socket(handle);
    if (ms_ws_socket_refs(socket) == 1) {
        ms_ws_socket_close(socket);
    }
}

void msstd_websocket_subprotocol(const void *handle, MsStr *out) {
    const MsBytes name = ms_ws_socket_subprotocol(ms_ws_handle_socket(handle));
    msrt_string_from_bytes(name.ptr, name.len, out);
}

uint8_t msstd_websocket_ping_bytes(const void *handle, const MsVec *data, MsStr *err) {
    ms_net_clear_text(err);
    MsWsSocket *socket = ms_ws_handle_socket(handle);
    return finish_session(socket, ms_ws_socket_ping(socket, bytes_of_vec(data)), err);
}

uint8_t msstd_websocket_ping(const void *handle, const MsStr *data, MsStr *err) {
    ms_net_clear_text(err);
    MsWsSocket *socket = ms_ws_handle_socket(handle);
    const MsBytes bytes = msrt_str_bytes(data);
    return finish_session(socket, ms_ws_socket_ping(socket, bytes), err);
}

uint8_t msstd_websocket_send_bytes(const void *handle, const MsVec *data, uint8_t text, MsStr *err) {
    ms_net_clear_text(err);
    MsWsSocket *socket = ms_ws_handle_socket(handle);
    return finish_session(socket, ms_ws_socket_send(socket, bytes_of_vec(data), text != 0, -1), err);
}

uint8_t msstd_websocket_receive(const void *handle, MsNetWsMessage *out, MsStr *err) {
    ms_net_clear_text(err);
    MsWsSocket *socket = ms_ws_handle_socket(handle);
    MsWsMessage message = {0};
    bool ended = false;
    const MsWsStatus status = ms_ws_socket_receive(socket, -1, &message, &ended);
    if (status != MS_WSS_OK) {
        return finish_session(socket, status, err);
    }
    if (ended) {
        return STATUS_NONE;
    }
    msrt_write_bytes(&out->data, message.data.ptr, message.data.len);
    out->text = message.text ? 1 : 0;
    return STATUS_OK;
}
