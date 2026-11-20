/* TLS on connection rows (tls_conn.h). */
#include "tls_conn.h"

#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#include "../std/abi.h"
#include "conn_object.h"
#include "ms_rt/alloc.h"
#include "ms_rt/net.h"
#include "ms_rt/obj.h"
#include "status.h"

static MsBytes bytes_of_str(const MsStr *text) { return ms_bytes_of((const uint8_t *)msrt_str_data(text), msrt_str_len(text)); }

/* The comma-separated ALPN names of the options' list, or NULL when one holds a comma or memory runs out. */
static char *alpn_names(const MsVec *list) {
    const MsStr *items = list->ptr;
    size_t total = 1;
    for (size_t i = 0; i < list->len; i++) {
        total += msrt_str_len(&items[i]) + 1;
    }
    char *names = malloc(total);
    size_t used = 0;
    for (size_t i = 0; names != NULL && i < list->len; i++) {
        const size_t length = msrt_str_len(&items[i]);
        if (memchr(msrt_str_data(&items[i]), ',', length) != NULL) {
            free(names);
            return NULL;
        }
        memcpy(names + used, msrt_str_data(&items[i]), length);
        used += length;
        names[used++] = ',';
    }
    if (names != NULL) {
        names[used > 0 ? used - 1 : 0] = 0;
    }
    return names;
}

static uint8_t set_alpn(MsTlsCtx *context, const MsVec *list) {
    if (list->len == 0) {
        return STATUS_OK;
    }
    char *names = alpn_names(list);
    const bool set = names != NULL && ms_tls_ctx_set_alpn(context, names) == 0;
    free(names);
    return set ? STATUS_OK : STATUS_INVALID_INPUT;
}

uint8_t ms_net_tls_context(int server, const MsNetTlsOptions *options, MsTlsCtx **out) {
    const MsBytes roots = bytes_of_str(&options->roots_pem);
    const MsBytes certificate = bytes_of_str(&options->certificate_pem);
    const MsBytes key = bytes_of_str(&options->private_key_pem);
    if (!server && options->require_client_certificate != 0) {
        return STATUS_INVALID_INPUT;
    }
    const bool clients = server && (roots.len > 0 || options->require_client_certificate != 0);
    MsTlsCtx *context = ms_tls_ctx_new(server, (const char *)certificate.ptr, certificate.len, (const char *)key.ptr, key.len,
                                       server || roots.len == 0 ? NULL : (const char *)roots.ptr, server ? 0 : roots.len);
    uint8_t status = context == NULL ? STATUS_INVALID_INPUT : set_alpn(context, &options->alpn);
    if (status == STATUS_OK && clients &&
        ms_tls_ctx_verify_clients(context, (const char *)roots.ptr, roots.len, options->require_client_certificate) != 0) {
        status = STATUS_INVALID_INPUT;
    }
    if (status != STATUS_OK) {
        ms_tls_ctx_free(context);
        return status;
    }
    *out = context;
    return STATUS_OK;
}

/* Upgrades the plain row behind `handle` with a new session of `context`, runs the handshake and hands back another
 * handle on the same connection (the caller drops the old one). A failed handshake closes the connection. */
static uint8_t upgrade(const void *handle, MsTlsCtx *context, const char *host, uint8_t has_timeout, int64_t timeout, void **out, MsStr *err) {
    MsNetConn *conn = ms_netconn_of(handle);
    MsConnTable *table = ms_netconn_table(conn);
    const MsConnId id = ms_netconn_id(conn);
    if (ms_netconn_closed(conn) || ms_conn_get(table, id) == NULL) {
        return STATUS_CLOSED;
    }
    if (ms_conn_tls(table, id) != NULL) {
        return STATUS_INVALID_INPUT;
    }
    MsTls *session = ms_tls_new(context, host);
    if (session == NULL) {
        return STATUS_INVALID_INPUT;
    }
    if (ms_conn_set_tls(table, id, session) != MS_NET_OK) {
        ms_tls_free(session);
        return STATUS_CLOSED;
    }
    const MsNetStatus status = ms_conn_handshake(table, id, ms_net_deadline_of(has_timeout, timeout));
    if (status != MS_NET_OK) {
        const uint8_t code = ms_net_finish(status, ms_conn_error_code(table, id), err);
        ms_netconn_close(handle);
        return code;
    }
    *out = ms_netconn_take(handle);
    return *out != NULL ? STATUS_OK : STATUS_FAILED;
}

uint8_t msstd_conn_start_tls(const void *handle, const MsNetTlsOptions *options, uint8_t has_timeout, int64_t timeout, void **out, MsStr *err) {
    ms_net_clear_text(err);
    if (msrt_str_len(&options->server_name) == 0 || memchr(msrt_str_data(&options->server_name), 0, msrt_str_len(&options->server_name)) != NULL) {
        return STATUS_INVALID_INPUT;
    }
    MsTlsCtx *context = NULL;
    const uint8_t built = ms_net_tls_context(0, options, &context);
    if (built != STATUS_OK) {
        return built;
    }
    char *host = malloc(msrt_str_len(&options->server_name) + 1);
    if (host == NULL) {
        ms_tls_ctx_free(context);
        return STATUS_FAILED;
    }
    memcpy(host, msrt_str_data(&options->server_name), msrt_str_len(&options->server_name));
    host[msrt_str_len(&options->server_name)] = 0;
    const uint8_t status = upgrade(handle, context, host, has_timeout, timeout, out, err);
    free(host);
    ms_tls_ctx_free(context);
    return status;
}

uint8_t msstd_conn_accept_tls(const void *handle, const MsNetTlsOptions *options, uint8_t has_timeout, int64_t timeout, void **out, MsStr *err) {
    ms_net_clear_text(err);
    MsTlsCtx *context = NULL;
    const uint8_t built = ms_net_tls_context(1, options, &context);
    if (built != STATUS_OK) {
        return built;
    }
    const uint8_t status = upgrade(handle, context, NULL, has_timeout, timeout, out, err);
    ms_tls_ctx_free(context);
    return status;
}

/* A server context built once for every connection of one listener: a handle shares it, the last one frees it. */
typedef struct TlsServerState {
    atomic_uint handles;
    MsTlsCtx *context;
} TlsServerState;

typedef struct TlsServerHandle {
    MsObj header;
    TlsServerState *state;
} TlsServerHandle;

static void server_drop(MsObj *object) {
    TlsServerHandle *handle = (TlsServerHandle *)object;
    if (atomic_fetch_sub(&handle->state->handles, 1) == 1) {
        ms_tls_ctx_free(handle->state->context);
        msrt_free(handle->state);
    }
    msrt_free(handle);
}

static MsObj *server_handle(TlsServerState *state) {
    TlsServerHandle *handle = msrt_alloc(sizeof *handle);
    handle->header.clone = NULL;
    handle->header.drop = server_drop;
    handle->state = state;
    return &handle->header;
}

uint8_t msstd_tls_server_new(const MsNetTlsOptions *options, void **out) {
    MsTlsCtx *context = NULL;
    const uint8_t built = ms_net_tls_context(1, options, &context);
    if (built != STATUS_OK) {
        return built;
    }
    TlsServerState *state = msrt_alloc(sizeof *state);
    atomic_init(&state->handles, 1);
    state->context = context;
    *out = server_handle(state);
    return STATUS_OK;
}

void *msstd_tls_server_share(const void *handle) {
    TlsServerState *state = ((const TlsServerHandle *)handle)->state;
    atomic_fetch_add(&state->handles, 1);
    return server_handle(state);
}

uint8_t msstd_conn_accept_tls_with(const void *handle, const void *server, uint8_t has_timeout, int64_t timeout, void **out, MsStr *err) {
    ms_net_clear_text(err);
    return upgrade(handle, ((const TlsServerHandle *)server)->state->context, NULL, has_timeout, timeout, out, err);
}

void msstd_conn_alpn(const void *handle, MsStr *out) {
    const MsNetConn *conn = ms_netconn_of(handle);
    const MsTls *session = ms_conn_tls(ms_netconn_table(conn), ms_netconn_id(conn));
    const MsBytes name = session == NULL ? ms_bytes_of(NULL, 0) : ms_tls_alpn(session);
    msrt_string_from_bytes(name.ptr, name.len, out);
}
