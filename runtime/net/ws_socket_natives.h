/* The status mapping of the SocketH natives declared in ms_rt/net.h. */
#ifndef MS_NET_WS_SOCKET_NATIVES_H
#define MS_NET_WS_SOCKET_NATIVES_H

#include "ms_rt/base.h"
#include "ms_rt/net.h"
#include "ms_rt/string.h"
#include "ws_socket.h"

/* The runtime status for a WebSocket status; `why` is the text for MS_WSS_FAILED (the session's own error when NULL). A
 * cancelled wait ends the native through the scheduler. */
uint8_t ms_ws_finish(MsWsStatus status, const char *why, MsStr *err);

#endif
