/* The SocketH handle (ws_natives.h): the MsObj the standard library holds for a WebSocket session. */
#include "ws_natives.h"

#include "ms_rt/alloc.h"

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

MsWsSocket *ms_ws_handle_socket(const void *handle) { return ((const SocketHandle *)handle)->socket; }
