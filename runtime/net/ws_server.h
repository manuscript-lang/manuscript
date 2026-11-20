/* The server side of the WebSocket opening handshake and the session it opens, over an exchange of the HTTP layer.
 * `msstd_ws_handshake` checks an upgrade request and answers what to send; standard-library code sends it with the
 * exchange natives (a 1xx head, `msstd_xchg_send_head`), takes the connection (`msstd_xchg_take_conn`) and calls
 * `msstd_ws_serve` on it. */
#ifndef MS_NET_WS_SERVER_H
#define MS_NET_WS_SERVER_H

#include "ms_rt/xchg.h"

/* The natives `msstd_ws_handshake` and `msstd_ws_serve` are declared in ms_rt/xchg.h with the exchange natives. */

#endif
