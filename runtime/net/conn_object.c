/* The connection object (conn_object.h). */
#include "conn_object.h"

#include <stdatomic.h>

#include "h2conn.h"
#include "ms_rt/alloc.h"

struct MsNetConn {
    atomic_uint handles; /* handles that refer to the core */
    atomic_uint ends;    /* stream ends still open */
    atomic_bool closed;
    atomic_bool exchanging; /* an exchange is open on the row */
    MsH2Conn *h2;           /* the HTTP/2 session, made by the first exchange that needs it */
    MsConnTable *table;
    MsConnId id;
};

typedef struct ConnHandle {
    MsObj header;
    MsNetConn *conn;
} ConnHandle;

static void core_release(MsNetConn *conn) {
    if (atomic_fetch_sub(&conn->handles, 1) != 1) {
        return;
    }
    if (!atomic_exchange(&conn->closed, true)) {
        (void)ms_conn_close_io(conn->table, conn->id);
    }
    ms_conn_table_free(conn->table);
    ms_h2conn_free(conn->h2);
    msrt_free(conn);
}

static void handle_drop(MsObj *object) {
    ConnHandle *handle = (ConnHandle *)object;
    core_release(handle->conn);
    msrt_free(handle);
}

/* A handle on `conn`, which the caller has already counted. */
static MsObj *handle_new(MsNetConn *conn) {
    ConnHandle *handle = msrt_alloc(sizeof *handle);
    handle->header.clone = NULL;
    handle->header.drop = handle_drop;
    handle->conn = conn;
    return &handle->header;
}

MsObj *ms_netconn_new(MsConnTable *table, MsConnId id) {
    MsNetConn *conn = msrt_alloc_zeroed(sizeof *conn);
    atomic_init(&conn->handles, 1);
    atomic_init(&conn->ends, 1);
    atomic_init(&conn->closed, false);
    atomic_init(&conn->exchanging, false);
    conn->table = table;
    conn->id = id;
    return handle_new(conn);
}

MsNetConn *ms_netconn_of(const void *handle) { return ((const ConnHandle *)handle)->conn; }
MsConnTable *ms_netconn_table(const MsNetConn *conn) { return conn->table; }
MsConnId ms_netconn_id(const MsNetConn *conn) { return conn->id; }
bool ms_netconn_closed(const MsNetConn *conn) { return atomic_load(&conn->closed); }

MsObj *ms_netconn_alias(const void *handle) {
    MsNetConn *conn = ms_netconn_of(handle);
    atomic_fetch_add(&conn->handles, 1);
    return handle_new(conn);
}

MsObj *ms_netconn_share(const void *handle) {
    atomic_fetch_add(&ms_netconn_of(handle)->ends, 1);
    return ms_netconn_alias(handle);
}

void ms_netconn_close(const void *handle) {
    MsNetConn *conn = ms_netconn_of(handle);
    if (!atomic_exchange(&conn->closed, true)) {
        (void)ms_conn_close_io(conn->table, conn->id);
    }
}

void ms_netconn_close_if_last(const void *handle) {
    MsNetConn *conn = ms_netconn_of(handle);
    if (atomic_fetch_sub(&conn->ends, 1) == 1) {
        ms_netconn_close(handle);
    }
}

bool ms_netconn_begin_exchange(MsNetConn *conn) { return !atomic_exchange(&conn->exchanging, true); }
void ms_netconn_end_exchange(MsNetConn *conn) { atomic_store(&conn->exchanging, false); }

MsH2Conn *ms_netconn_h2(MsNetConn *conn) {
    if (conn->h2 == NULL) {
        conn->h2 = ms_h2conn_new(0, NULL);
    }
    return conn->h2;
}
