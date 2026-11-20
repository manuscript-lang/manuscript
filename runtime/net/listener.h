/* Listening sockets for the server (ListenerH): a bound socket that hands out connection rows. `accept` parks the
 * running task on the descriptor, so a stop request interrupts it and other tasks run meanwhile. Closing a listener
 * stops later accepts; the descriptor itself closes when the last handle is dropped. */
#ifndef MS_NET_LISTENER_H
#define MS_NET_LISTENER_H

#include <stdint.h>

#include "conn_io.h"
#include "ms_rt/base.h"
#include "ms_rt/safe.h"
#include "ms_rt/sys_net.h"

typedef struct MsListener MsListener;

/* Binds and listens on `address`. MS_NET_OK with the first handle in *out (a heap MsObj the runtime drops), or
 * MS_NET_FAILED with the system code in *error_code. */
MS_NODISCARD MsNetStatus ms_listener_open(const MsAddr *address, int backlog, MsObj **out, int *error_code);

/* The listener behind a handle. */
MsListener *ms_listener_of(const void *handle);

/* The next connection, as a row in a table of its own: *out_table owns it. `deadline_ns` is an absolute
 * ms_sys_monotonic_ns time, or negative for none. MS_NET_CLOSED once the listener is closed. */
MS_NODISCARD MsNetStatus ms_listener_accept(MsListener *listener, int64_t deadline_ns, MsConnTable **out_table,
                                            MsConnId *out_id, int *error_code);

/* The bound address (the port 0 case reads back the chosen port). */
MS_NODISCARD MsNetStatus ms_listener_address(const MsListener *listener, MsAddr *out);

/* Stops later accepts; safe to call twice. */
void ms_listener_close(MsListener *listener);

#endif
