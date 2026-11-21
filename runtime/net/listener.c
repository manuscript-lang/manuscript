/* Listening sockets (listener.h). */
#include "listener.h"

#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#include "ms_rt/alloc.h"
#include "ms_rt/sys.h"
#include "ms_rt/sys_fs.h"
#include "ms_sched.h"
#include "status.h"

struct MsListener {
    MsSock socket;
    atomic_bool closed;
    atomic_uint handles; /* handles on the listener; the last drop closes the descriptor */
    char *path; /* a Unix domain listener's file, removed when the handle drops; NULL for TCP */
};

/* The handle the standard library holds: it owns the listener and releases it when dropped. */
typedef struct ListenerHandle {
    MsObj header;
    MsListener *listener;
} ListenerHandle;

static void listener_drop(MsObj *object) {
    ListenerHandle *handle = (ListenerHandle *)object;
    MsListener *listener = handle->listener;
    msrt_free(handle);
    if (atomic_fetch_sub(&listener->handles, 1) != 1) {
        return;
    }
    msrt_task_forget_fd((int32_t)listener->socket); /* a parked accept left libuv watching it: the next socket with this number would never be ready */
    ms_sys_net_close(listener->socket);
    if (listener->path != NULL) {
        const MsSysError removed = ms_sys_fs_unlink(listener->path); /* nothing to do when it is gone */
        (void)removed;
        free(listener->path);
    }
    msrt_free(listener);
}

/* Wraps a listening socket (and the file it is bound to, if any) in the handle; takes ownership of both. */
static MsObj *handle_on(MsListener *listener) {
    ListenerHandle *handle = msrt_alloc_zeroed(sizeof *handle);
    atomic_fetch_add(&listener->handles, 1);
    handle->header.clone = NULL;
    handle->header.drop = listener_drop;
    handle->listener = listener;
    return &handle->header;
}

static MsObj *listener_new(MsSock socket, char *path) {
    MsListener *listener = msrt_alloc_zeroed(sizeof *listener);
    listener->socket = socket;
    listener->path = path;
    atomic_init(&listener->closed, false);
    atomic_init(&listener->handles, 0);
    return handle_on(listener);
}

MsObj *ms_listener_share(const void *handle) { return handle_on(((const ListenerHandle *)handle)->listener); }

MsNetStatus ms_listener_open(const MsAddr *address, int backlog, MsObj **out, int *error_code) {
    MsSock socket = MS_SOCK_INVALID;
    if (ms_sys_net_tcp_listen(address, backlog, &socket) != MS_SYS_OK) {
        *error_code = ms_sys_net_error();
        return MS_NET_FAILED;
    }
    *out = listener_new(socket, NULL);
    return MS_NET_OK;
}

MsNetStatus ms_listener_open_unix(MsBytes path, int backlog, MsObj **out, int *error_code) {
    char *copy = path.len == 0 || memchr(path.ptr, 0, path.len) != NULL ? NULL : malloc(path.len + 1);
    if (copy == NULL) {
        *error_code = 0;
        return MS_NET_FAILED;
    }
    memcpy(copy, path.ptr, path.len);
    copy[path.len] = 0;
    MsSock socket = MS_SOCK_INVALID;
    if (ms_sys_net_unix_listen(copy, backlog, &socket) != MS_SYS_OK) {
        *error_code = ms_sys_net_error();
        free(copy);
        return MS_NET_FAILED;
    }
    *out = listener_new(socket, copy);
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
        const MsNetStatus waited = ms_net_wait_status(msrt_task_wait_fd((int32_t)listener->socket, MS_WAIT_READ, ms_net_time_left(deadline_ns)));
        if (waited != MS_NET_OK) {
            return waited;
        }
    }
}

MsNetStatus ms_listener_address(const MsListener *listener, MsAddr *out) {
    return ms_sys_net_local_addr(listener->socket, out) == MS_SYS_OK ? MS_NET_OK : MS_NET_FAILED;
}

const char *ms_listener_path(const MsListener *listener) { return listener->path; }

void ms_listener_close(MsListener *listener) { atomic_store(&listener->closed, true); }
