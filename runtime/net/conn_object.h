/* The connection object the standard library holds (ConnH): a handle on a shared connection core, which owns one
 * connection row in a table of its own. Handles are cheap to make: `share` makes another stream end, `alias` another
 * handle that is not an end. The row closes when `close` is called, when the last end closes (`close_if_last`), or
 * when the last handle is dropped. The natives of ms_rt/net.h and the exchange natives are built on these calls.
 */
#ifndef MS_NET_CONN_OBJECT_H
#define MS_NET_CONN_OBJECT_H

#include <stdbool.h>

#include "conn_io.h"
#include "ms_rt/base.h"

typedef struct MsNetConn MsNetConn;

/* A core that owns an open row (taking over `table`). Returns the first handle (a heap MsObj the runtime drops) or
 * NULL when out of memory, in which case the row is closed and the table freed. */
MsObj *ms_netconn_new(MsConnTable *table, MsConnId id);

/* The core behind a handle. */
MsNetConn *ms_netconn_of(const void *handle);
MsConnTable *ms_netconn_table(const MsNetConn *conn);
MsConnId ms_netconn_id(const MsNetConn *conn);

/* Another handle on the same core, counted as a stream end (`share`) or not (`alias`). */
MsObj *ms_netconn_share(const void *handle);
MsObj *ms_netconn_alias(const void *handle);
/* Closes the row now, whatever other handles exist. Later calls on it give MS_NET_CLOSED. */
void ms_netconn_close(const void *handle);
/* Ends one stream end; closes the row when none is left. */
void ms_netconn_close_if_last(const void *handle);
/* Moves the row to a new core and returns its first handle (NULL when out of memory, nothing moved). The old core is
 * closed without closing the row: its handles give MS_NET_CLOSED from here on. The caller guarantees no call is using
 * the row. */
MsObj *ms_netconn_take(const void *handle);
/* Whether the row has been closed. */
bool ms_netconn_closed(const MsNetConn *conn);


#endif
