/* How the other natives that make sessions (the client dial) hand one to the standard library. */
#ifndef MS_NET_WS_NATIVES_H
#define MS_NET_WS_NATIVES_H

#include "ms_rt/base.h"
#include "ws_socket.h"

/* A SocketH handle that owns the caller's reference to `socket`; NULL when out of memory (the reference is then
 * released). */
MsObj *ms_ws_handle_new(MsWsSocket *socket);
/* The session behind a SocketH handle. */
MsWsSocket *ms_ws_handle_socket(const void *handle);

#endif
