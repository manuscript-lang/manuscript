/* The Unix domain socket natives (unix.h). */
#include "ms_rt/net.h"

#include <stdlib.h>
#include <string.h>

#include "../std/abi.h"
#include "conn_object.h"
#include "listener.h"
#include "ms_rt/sys_net.h"
#include "status.h"

enum { LISTEN_BACKLOG = 1024 };

uint8_t msstd_net_dial_unix(const MsStr *path, void **out, MsStr *err) {
    ms_net_clear_text(err); /* the caller reads the slot for every failure status; only STATUS_FAILED sets text */
    const size_t length = msrt_str_len(path);
    const char *text = msrt_str_data(path);
    if (length == 0 || memchr(text, 0, length) != NULL) {
        return STATUS_INVALID_INPUT;
    }
    char *copy = malloc(length + 1);
    if (copy == NULL) {
        return ms_net_finish(MS_NET_FAILED, 0, err);
    }
    memcpy(copy, text, length);
    copy[length] = 0;
    MsSock fd = MS_SOCK_INVALID;
    const int connected = ms_sys_net_unix_connect(copy, &fd);
    free(copy);
    if (connected != MS_SYS_OK) {
        return ms_net_finish(MS_NET_FAILED, ms_sys_net_error(), err);
    }
    MsConnTable *table = ms_conn_table_new(1);
    const MsConnId id = table != NULL ? ms_conn_open(table, (int)fd, MS_CONN_HTTP1) : 0;
    MsObj *connection = id != 0 ? ms_netconn_new(table, id) : NULL;
    if (connection == NULL) {
        if (id == 0) {
            ms_sys_net_close(fd);
            ms_conn_table_free(table);
        }
        return ms_net_finish(MS_NET_FAILED, 0, err);
    }
    *out = connection;
    return STATUS_OK;
}

uint8_t msstd_net_listen_unix(const MsStr *path, void **out, MsStr *err) {
    ms_net_clear_text(err); /* the caller reads the slot for every failure status; only STATUS_FAILED sets text */
    const size_t length = msrt_str_len(path);
    if (length == 0 || memchr(msrt_str_data(path), 0, length) != NULL) {
        return STATUS_INVALID_INPUT;
    }
    MsObj *handle = NULL;
    int code = 0;
    const MsNetStatus status = ms_listener_open_unix(ms_bytes_of((const uint8_t *)msrt_str_data(path), length), LISTEN_BACKLOG, &handle, &code);
    if (status != MS_NET_OK) {
        return ms_net_finish(status, code, err);
    }
    *out = handle;
    return STATUS_OK;
}
