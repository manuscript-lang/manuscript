/* Listening sockets (listener.h). */
#include "listener.h"

#include <stdatomic.h>

#include "ms_rt/alloc.h"
#include "ms_rt/sys.h"
#include "ms_sched.h"

struct MsListener {
    MsSock socket;
    atomic_bool closed;
};

/* The handle the standard library holds: it owns the listener and releases it when dropped. */
typedef struct ListenerHandle {
    MsObj header;
    MsListener *listener;
} ListenerHandle;

static void listener_drop(MsObj *object) {
    ListenerHandle *handle = (ListenerHandle *)object;
    ms_sys_net_close(handle->listener->socket);
    msrt_free(handle->listener);
    msrt_free(handle);
}

/* The nanoseconds a park may take before `deadline_ns`: -1 for no deadline, 0 once it has passed. */
static int64_t time_left(int64_t deadline_ns) {
    if (deadline_ns < 0) {
        return -1;
    }
    const int64_t left = deadline_ns - ms_sys_monotonic_ns();
    return left > 0 ? left : 0;
}

static MsNetStatus wait_status(uint32_t result) {
    if ((result & MS_WAIT_CANCELLED) != 0) {
        return MS_NET_CANCELLED;
    }
    return (result & MS_WAIT_TIMEOUT) != 0 ? MS_NET_TIMEOUT : MS_NET_OK;
}

MsNetStatus ms_listener_open(const MsAddr *address, int backlog, MsObj **out, int *error_code) {
    MsSock socket = MS_SOCK_INVALID;
    if (ms_sys_net_tcp_listen(address, backlog, &socket) != MS_SYS_OK) {
        *error_code = ms_sys_net_error();
        return MS_NET_FAILED;
    }
    MsListener *listener = msrt_alloc_zeroed(sizeof *listener);
    ListenerHandle *handle = msrt_alloc_zeroed(sizeof *handle);
    listener->socket = socket;
    atomic_init(&listener->closed, false);
    handle->header.clone = NULL;
    handle->header.drop = listener_drop;
    handle->listener = listener;
    *out = &handle->header;
    return MS_NET_OK;
}

MsListener *ms_listener_of(const void *handle) { return ((const ListenerHandle *)handle)->listener; }

MsNetStatus ms_listener_accept(MsListener *listener, int64_t deadline_ns, MsConnTable **out_table, MsConnId *out_id,
                               int *error_code) {
    for (;;) {
        if (atomic_load(&listener->closed)) {
            return MS_NET_CLOSED;
        }
        MsSock accepted = MS_SOCK_INVALID;
        const int result = ms_sys_net_accept(listener->socket, &accepted, NULL);
        if (result == MS_SYS_ERROR) {
            *error_code = ms_sys_net_error();
            return MS_NET_FAILED;
        }
        if (result == MS_SYS_OK) {
            MsConnTable *table = ms_conn_table_new(1);
            const MsConnId id = table != NULL ? ms_conn_open(table, (int)accepted, MS_CONN_HTTP1) : 0;
            if (id == 0) {
                ms_sys_net_close(accepted);
                ms_conn_table_free(table);
                return MS_NET_FAILED;
            }
            *out_table = table;
            *out_id = id;
            return MS_NET_OK;
        }
        const MsNetStatus waited = wait_status(msrt_task_wait_fd((int32_t)listener->socket, MS_WAIT_READ, time_left(deadline_ns)));
        if (waited != MS_NET_OK) {
            return waited;
        }
    }
}

MsNetStatus ms_listener_address(const MsListener *listener, MsAddr *out) {
    return ms_sys_net_local_addr(listener->socket, out) == MS_SYS_OK ? MS_NET_OK : MS_NET_FAILED;
}

void ms_listener_close(MsListener *listener) { atomic_store(&listener->closed, true); }
