/* The listener natives of ms_rt/net.h: listen, accept, address and close over listener.h. Status mapping lives in
 * status.c; everything else is a thin layer over listener.h and conn_object.h. */
#include <stdlib.h>
#include <string.h>

#include "../std/abi.h"
#include "addr_text.h"
#include "conn_object.h"
#include "listener.h"
#include "ms_rt/net.h"
#include "status.h"

enum { LISTEN_BACKLOG = 1024 };


uint8_t msstd_net_listen(const MsStr *address, void **out, MsStr *err) {
    ms_net_clear_text(err);
    MsAddr target;
    if (!ms_net_addr_parse(msrt_str_bytes(address), &target)) {
        return STATUS_INVALID_INPUT;
    }
    MsObj *handle = NULL;
    int code = 0;
    const MsNetStatus status = ms_listener_open(&target, LISTEN_BACKLOG, &handle, &code);
    if (status != MS_NET_OK) {
        return ms_net_finish(status, code, err);
    }
    *out = handle;
    return STATUS_OK;
}

uint8_t msstd_listener_accept(const void *handle, uint8_t has_timeout, int64_t timeout, void **out, MsStr *err) {
    ms_net_clear_text(err);
    MsConnTable *table = NULL;
    MsConnId id = 0;
    int code = 0;
    const MsNetStatus status = ms_listener_accept(ms_listener_of(handle), ms_net_deadline_of(has_timeout, timeout), &table, &id, &code);
    if (status != MS_NET_OK) {
        return ms_net_finish(status, code, err);
    }
    MsObj *connection = ms_netconn_new(table, id);
    if (connection == NULL) {
        return ms_net_finish(MS_NET_FAILED, 0, err);
    }
    *out = connection;
    return STATUS_OK;
}

void msstd_listener_address(const void *handle, MsStr *out) {
    const char *path = ms_listener_path(ms_listener_of(handle));
    if (path != NULL) { /* a Unix domain listener's address is its path */
        msrt_string_from_bytes((const uint8_t *)path, strlen(path), out);
        return;
    }
    MsAddr address;
    char text[MS_NET_ADDR_TEXT_MAX];
    size_t length = 0;
    if (ms_listener_address(ms_listener_of(handle), &address) != MS_NET_OK || !ms_net_addr_format(&address, text, sizeof text, &length)) {
        length = 0;
    }
    msrt_string_from_bytes((const uint8_t *)text, length, out);
}

void *msstd_listener_share(const void *handle) { return ms_listener_share(handle); }

void msstd_listener_close(const void *handle) { ms_listener_close(ms_listener_of(handle)); }
