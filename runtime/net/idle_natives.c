/* The idle-connection natives of ms_rt/xchg.h: the glue between a connection handle and the scheduler's idle pool
 * (runtime/core/idle.c). The pool holds a handle on the connection for as long as the row is idle. */
#include "../core/idle.h"
#include "conn_object.h"
#include "ms_rt/alloc.h"
#include "ms_rt/obj.h"
#include "ms_rt/sys_net.h"
#include "ms_rt/xchg.h"
#include "status.h"

static const MsNetConn *core_of(void *subject) { return ms_netconn_of(subject); }

static bool conn_buffered(void *subject) {
    const MsNetConn *const core = core_of(subject);
    return ms_conn_buffered(ms_netconn_table(core), ms_netconn_id(core));
}

static void conn_moved(void *subject, int fd) {
    const MsNetConn *const core = core_of(subject);
    MsConn *const row = ms_conn_get(ms_netconn_table(core), ms_netconn_id(core));
    if (row != NULL) {
        row->fd = fd;
    }
}

static int conn_duplicate(int fd) {
    MsSock copy = -1;
    return ms_sys_net_duplicate(fd, &copy) == MS_SYS_OK ? (int)copy : -1;
}

/* The descriptor was watched by this thread's reactor: forget it before it closes, or libuv keeps a handle for a closed one
 * and the next socket to get the number is never reported ready. */
static void conn_release(int fd) {
    msrt_task_forget_fd(fd);
    ms_sys_net_close(fd);
}

static void conn_close(void *subject) { ms_netconn_close(subject); }

static const MsIdleOps conn_ops = {conn_buffered, conn_moved, conn_duplicate, conn_release, conn_close};

uint8_t msstd_idle_park(const void *conn, void *next, int64_t group, uint8_t has_timeout, int64_t timeout, MsStr *err) {
    ms_net_clear_text(err);
    const MsNetConn *const core = ms_netconn_of(conn);
    const MsConn *const row = ms_conn_get(ms_netconn_table(core), ms_netconn_id(core));
    if (row == NULL) {
        msrt_obj_drop(next);
        return ms_net_finish(MS_NET_CLOSED, 0, err);
    }
    MsObj *const subject = ms_netconn_alias(conn);
    const int64_t idle_ns = has_timeout != 0 && timeout >= 0 ? timeout : -1;
    if (!ms_idle_park(&conn_ops, subject, row->fd, next, (uintptr_t)group, idle_ns)) {
        msrt_obj_drop(subject);
        msrt_obj_drop(next);
        return ms_net_finish(MS_NET_FAILED, 0, err);
    }
    return MS_STATUS_OK;
}

int64_t msstd_idle_group(void) { return (int64_t)ms_idle_group_new(); }

void msstd_idle_drain(int64_t group) { ms_idle_drain((uintptr_t)group); }

int64_t msstd_idle_inflight(int64_t group) { return (int64_t)ms_idle_inflight((uintptr_t)group); }

void msstd_idle_cancel(int64_t group) { ms_idle_cancel((uintptr_t)group); }
