/* Name resolution and connecting (dial.h). */
#include "dial.h"

#include <stdio.h>

#include "../io/reactor.h"
#include "ms_rt/sys.h"
#include "ms_sched.h"
#include "status.h"

/* Copies the addresses of a finished lookup into `out`. */
static void collect(const MsIoAddresses *found, MsNetAddresses *out) {
    const size_t available = ms_io_addresses_count(found);
    for (size_t i = 0; i < available && out->count < MS_NET_MAX_ADDRESSES; i++) {
        MsIoAddress raw;
        if (ms_io_addresses_at(found, i, &raw) && ms_sys_net_addr_from_raw(raw.socket_address, raw.length, &out->items[out->count]) == 0) {
            out->count++;
        }
    }
}

MsNetStatus ms_net_resolve(const char *host, uint16_t port, int64_t deadline_ns, MsNetAddresses *out) {
    out->count = 0;
    out->resolver_code = 0;
    char service[8];
    (void)snprintf(service, sizeof service, "%u", (unsigned)port);

    const uint64_t token = msrt_token_new(1); /* flag 1: the reactor posts it */
    if (token == 0) {
        return MS_NET_FAILED;
    }
    MsIoAddresses *found = NULL;
    if (!ms_io_resolve(host, service, token, &found)) {
        msrt_token_free(token);
        return MS_NET_FAILED;
    }
    uint64_t value = 0;
    const uint32_t result = msrt_token_park(token, ms_net_time_left(deadline_ns), &value);
    msrt_token_free(token);
    const MsNetStatus ended = ms_net_wait_status(result);
    if (ended != MS_NET_OK) {
        ms_io_addresses_abandon(found); /* the lookup is still running: libuv releases it when it ends */
        return ended;
    }
    const int32_t status = (int32_t)value;
    if (status == 0) {
        collect(found, out);
    } else {
        out->resolver_code = status;
    }
    ms_io_addresses_free(found);
    return out->count > 0 ? MS_NET_OK : MS_NET_FAILED;
}

/* Waits for a connect that is in progress, then asks the system how it ended. */
static MsNetStatus finish_connect(MsSock socket, int64_t deadline_ns, int *error_code) {
    const MsNetStatus waited = ms_net_wait_status(msrt_task_wait_fd((int32_t)socket, MS_WAIT_WRITE, ms_net_time_left(deadline_ns)));
    if (waited != MS_NET_OK) {
        return waited;
    }
    if (ms_sys_net_connect_done(socket) == MS_SYS_OK) {
        return MS_NET_OK;
    }
    if (error_code != NULL) {
        *error_code = ms_sys_net_error();
    }
    return MS_NET_FAILED;
}

MsNetStatus ms_net_connect(MsConnTable *table, const MsAddr *address, uint8_t proto, MsTlsCtx *tls,
                           const char *server_name, int64_t deadline_ns, MsConnId *out, int *error_code) {
    if (error_code != NULL) {
        *error_code = 0;
    }
    if (proto == MS_CONN_NONE) {
        return MS_NET_FAILED;
    }
    MsSock socket = MS_SOCK_INVALID;
    const int started = ms_sys_net_tcp_connect(address, &socket);
    if (started == MS_SYS_ERROR) {
        if (error_code != NULL) {
            *error_code = ms_sys_net_error();
        }
        return MS_NET_FAILED;
    }
    MsNetStatus status = started == MS_SYS_INPROGRESS ? finish_connect(socket, deadline_ns, error_code) : MS_NET_OK;
    MsConnId id = 0;
    if (status == MS_NET_OK) {
        id = ms_conn_open(table, (int)socket, proto);
        status = id != 0 ? MS_NET_OK : MS_NET_FAILED; /* the table is full */
    }
    if (status != MS_NET_OK) {
        ms_sys_net_close(socket);
        return status;
    }
    if (tls != NULL) {
        MsTls *session = ms_tls_new(tls, server_name);
        status = session != NULL ? ms_conn_set_tls(table, id, session) : MS_NET_FAILED;
        if (status != MS_NET_OK) {
            ms_tls_free(session);
        }
        if (status == MS_NET_OK) {
            status = ms_conn_handshake(table, id, deadline_ns);
        }
        if (status != MS_NET_OK) {
            if (error_code != NULL) {
                *error_code = ms_conn_error_code(table, id);
            }
            (void)ms_conn_close_io(table, id);
            return status;
        }
    }
    *out = id;
    return MS_NET_OK;
}
