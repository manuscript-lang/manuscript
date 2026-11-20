/* The client natives of ms_rt/net.h: lookup, dial and the connection handle calls. Status mapping and text live in
 * `finish`; everything else is a thin layer over dial.h, conn_io.h and conn_object.h. */
#include "ms_rt/net.h"

#include <stdlib.h>
#include <string.h>

#include "../std/abi.h"
#include "addr_text.h"
#include "conn_object.h"
#include "dial.h"
#include "ms_rt/sys.h"
#include "ms_rt/sys_fs.h"
#include "ms_sched.h"
#include "status.h"
#include "tls_conn.h"

enum { READ_DEFAULT = 64 * 1024, READ_LIMIT = 1024 * 1024, TABLE_ROWS = 1 };

/* The bytes of a string as a NUL-terminated copy, or NULL for a string that holds a NUL (no host or address does). */
static char *copy_text(const MsStr *text) {
    const size_t length = msrt_str_len(text);
    const char *data = msrt_str_data(text);
    if (length > 0 && memchr(data, 0, length) != NULL) {
        return NULL;
    }
    char *copy = malloc(length + 1);
    if (copy != NULL) {
        memcpy(copy, data, length);
        copy[length] = 0;
    }
    return copy;
}


/* ---- lookup ---- */

uint8_t msstd_net_lookup(const MsStr *host, int64_t port, uint8_t has_timeout, int64_t timeout, MsVec *out, MsStr *err) {
    ms_net_clear_text(err);
    char *name = copy_text(host);
    if (name == NULL || port < 0 || port > 65535) {
        free(name);
        return STATUS_INVALID_INPUT;
    }
    MsNetAddresses found;
    const MsNetStatus status = ms_net_resolve(name, (uint16_t)port, ms_net_deadline_of(has_timeout, timeout), &found);
    free(name);
    if (status != MS_NET_OK) {
        if (status == MS_NET_FAILED && err != NULL) {
            ms_net_write_text(err, "name not found");
            return STATUS_FAILED;
        }
        return ms_net_finish(status, 0, err);
    }
    msrt_list_with_capacity(&msrt_desc_string, (int64_t)found.count, out);
    for (size_t i = 0; i < found.count; i++) {
        MsStr text;
        ms_net_write_address(&text, &found.items[i]);
        msrt_list_push(out, &msrt_desc_string, &text);
    }
    return STATUS_OK;
}

/* ---- dial ---- */

uint8_t msstd_net_dial(const MsStr *address, const MsStr *server_name, uint8_t has_tls, const MsNetTlsOptions *tls,
                       uint8_t has_timeout, int64_t timeout, void **out, MsStr *err) {
    ms_net_clear_text(err);
    MsAddr target;
    if (!ms_net_addr_parse(msrt_str_bytes(address), &target)) {
        return STATUS_INVALID_INPUT;
    }
    MsTlsCtx *context = NULL;
    char *name = NULL;
    if (has_tls != 0) {
        name = copy_text(msrt_str_len(server_name) > 0 ? server_name : &tls->server_name);
        if (name == NULL || name[0] == 0) { /* TLS verifies a name, so one is needed */
            free(name);
            return STATUS_INVALID_INPUT;
        }
        const uint8_t built = ms_net_tls_context(0, tls, &context);
        if (built != STATUS_OK) {
            free(name);
            return built;
        }
    }
    MsConnTable *table = ms_conn_table_new(TABLE_ROWS);
    MsConnId id = 0;
    int code = 0;
    const MsNetStatus status = table == NULL ? MS_NET_FAILED
                                              : ms_net_connect(table, &target, MS_CONN_HTTP1, context, name, ms_net_deadline_of(has_timeout, timeout), &id, &code);
    ms_tls_ctx_free(context);
    free(name);
    if (status != MS_NET_OK) {
        ms_conn_table_free(table);
        return ms_net_finish(status, code, err);
    }
    *out = ms_netconn_new(table, id);
    return STATUS_OK;
}

/* ---- connection handles ---- */

uint8_t msstd_conn_read(const void *handle, uint8_t has_max, int64_t max, uint8_t has_timeout, int64_t timeout, MsVec *out, MsStr *err) {
    ms_net_clear_text(err);
    const MsNetConn *conn = ms_netconn_of(handle);
    if (has_max != 0 && max < 0) {
        return STATUS_INVALID_INPUT;
    }
    size_t capacity = READ_DEFAULT;
    if (has_max != 0) {
        capacity = max > READ_LIMIT ? READ_LIMIT : (size_t)max;
    }
    if (capacity == 0) {
        msrt_write_bytes(out, NULL, 0);
        return STATUS_OK;
    }
    uint8_t *buffer = malloc(capacity);
    if (buffer == NULL) {
        return ms_net_finish(MS_NET_FAILED, 0, err);
    }
    size_t count = 0;
    const MsNetStatus status = ms_conn_read(ms_netconn_table(conn), ms_netconn_id(conn), buffer, capacity, ms_net_deadline_of(has_timeout, timeout), &count);
    if (status == MS_NET_OK && count > 0) {
        msrt_write_bytes(out, buffer, count);
    }
    free(buffer);
    if (status == MS_NET_OK) {
        return count > 0 ? STATUS_OK : STATUS_NONE;
    }
    return ms_net_finish(status, ms_conn_error_code(ms_netconn_table(conn), ms_netconn_id(conn)), err);
}

uint8_t msstd_conn_write_bytes(const void *handle, const MsVec *data, uint8_t has_timeout, int64_t timeout, MsStr *err) {
    ms_net_clear_text(err);
    const MsNetConn *conn = ms_netconn_of(handle);
    const MsNetStatus status = ms_conn_write(ms_netconn_table(conn), ms_netconn_id(conn), data->ptr, data->len, ms_net_deadline_of(has_timeout, timeout));
    return ms_net_finish(status, ms_conn_error_code(ms_netconn_table(conn), ms_netconn_id(conn)), err);
}

uint8_t msstd_conn_shutdown_write(const void *handle, MsStr *err) {
    ms_net_clear_text(err);
    const MsNetConn *conn = ms_netconn_of(handle);
    const MsNetStatus status = ms_conn_shutdown_write(ms_netconn_table(conn), ms_netconn_id(conn), -1);
    return ms_net_finish(status, ms_conn_error_code(ms_netconn_table(conn), ms_netconn_id(conn)), err);
}

void msstd_conn_close(const void *handle) { ms_netconn_close(handle); }
void *msstd_conn_share(const void *handle) { return ms_netconn_share(handle); }
void *msstd_conn_alias(const void *handle) { return ms_netconn_alias(handle); }
void msstd_conn_close_if_last(const void *handle) { ms_netconn_close_if_last(handle); }

/* The row's socket address through `query`, as text; empty when the row is closed. */
static void socket_address(const void *handle, int (*query)(MsSock, MsAddr *), MsStr *out) {
    const MsNetConn *conn = ms_netconn_of(handle);
    const MsConn *row = ms_conn_get(ms_netconn_table(conn), ms_netconn_id(conn));
    MsAddr address;
    if (row != NULL && query(row->fd, &address) == MS_SYS_OK) {
        ms_net_write_address(out, &address);
    } else {
        msrt_string_from_bytes(NULL, 0, out);
    }
}

void msstd_conn_local_address(const void *handle, MsStr *out) { socket_address(handle, ms_sys_net_local_addr, out); }
void msstd_conn_peer_address(const void *handle, MsStr *out) { socket_address(handle, ms_sys_net_peer_addr, out); }

uint8_t msstd_conn_tls_info(const void *handle, MsNetTlsInfo *out) {
    const MsNetConn *conn = ms_netconn_of(handle);
    const MsTls *session = ms_conn_tls(ms_netconn_table(conn), ms_netconn_id(conn));
    if (session == NULL) {
        return 0;
    }
    out->version = ms_tls_version(session);
    out->cipher_suite = ms_tls_cipher(session);
    const MsBytes alpn = ms_tls_alpn(session);
    msrt_string_from_bytes(alpn.ptr, alpn.len, &out->alpn);
    const size_t count = ms_tls_peer_count(session);
    msrt_list_with_capacity(&msrt_desc_bytes, (int64_t)count, &out->peer_certificates);
    for (size_t i = 0; i < count; i++) {
        size_t length = 0;
        uint8_t *der = ms_tls_peer_der(session, i, &length);
        MsVec certificate;
        msrt_write_bytes(&certificate, der, length);
        free(der);
        msrt_list_push(&out->peer_certificates, &msrt_desc_bytes, &certificate);
    }
    out->verified = ms_tls_verified(session);
    return 1;
}
