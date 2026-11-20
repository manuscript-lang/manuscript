/* How the other natives that make sessions (the client dial) hand one to the standard library. */
#ifndef MS_NET_WS_NATIVES_H
#define MS_NET_WS_NATIVES_H

#include "ms_rt/base.h"
#include "ws_socket.h"
#include "ms_rt/string.h"

/* A SocketH handle that owns the caller's reference to `socket`; NULL when out of memory (the reference is then
 * released). */
MsObj *ms_ws_handle_new(MsWsSocket *socket);
/* The session behind a SocketH handle. */
MsWsSocket *ms_ws_handle_socket(const void *handle);

/* The runtime status for a WebSocket status; `why` is the text for MS_WSS_FAILED (the session's own error when NULL). A
 * cancelled wait ends the native through the scheduler. */
uint8_t ms_ws_finish(MsWsStatus status, const char *why, MsStr *err);


#endif
