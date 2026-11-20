/* The HTTP/2 server exchange (exchange_h2.h). */
#include "exchange_h2.h"

#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../std/abi.h"
#include "ms_rt/chars.h"
#include "ms_rt/sys.h"
#include "ms_sched.h"
#include "status.h"

enum { TOKEN_ANY_THREAD = 1, READ_DEFAULT = 64 * 1024, READ_LIMIT = 1024 * 1024, ERROR_CANCEL = 8, ERROR_INTERNAL = 2 };

struct MsXchgH2Conn {
    MsH2Serve *serve;
    atomic_uint refs;     /* the run task and the owner */
    int32_t *queue;       /* requests that arrived and were not taken, oldest first */
    size_t queued, capacity;
    uint8_t ended;        /* the connection is over: `next` reports it once the queue is empty */
    uint8_t failed;       /* a request could not be queued: out of memory */
    uint64_t waiter;      /* token `next` parks on; 0 until needed */
};

struct MsXchgH2 {
    MsXchgH2Conn *conn;
    int32_t stream;
    uint8_t released;
    uint8_t head_sent;
    uint8_t local_ended;
    uint8_t no_body;      /* the response has no body: HEAD, 204, 304 */
    uint8_t is_head;
    uint8_t has_length;
    int64_t length;
    int64_t written;
    char *method;         /* owned copies of the request line */
    char *target;
    size_t method_length, target_length;
    MsHeaders *fields;    /* the request fields, owned (a runtime object) */
};

static MsXchgH2 *exchange_new(MsXchgH2Conn *conn, int32_t stream);

/* ---- the connection ---- */

static void wake(MsXchgH2Conn *conn) {
    if (conn->waiter != 0) {
        msrt_token_post_remote(conn->waiter, 0);
    }
}

static void on_request(void *context, MsH2Serve *serve, int32_t stream) {
    MsXchgH2Conn *conn = context;
    if (conn->queued == conn->capacity) {
        const size_t capacity = conn->capacity == 0 ? 8 : conn->capacity * 2;
        int32_t *grown = realloc(conn->queue, capacity * sizeof *grown);
        if (grown == NULL) {
            conn->failed = 1;
            ms_h2_stream_reset(serve, stream, ERROR_INTERNAL);
            ms_h2_serve_release(serve, stream, ERROR_INTERNAL);
            return;
        }
        conn->queue = grown;
        conn->capacity = capacity;
    }
    conn->queue[conn->queued++] = stream;
    wake(conn);
}

MsXchgH2Conn *ms_xchg_h2_conn_new(MsConnTable *table, MsConnId id, const MsH2Limits *limits, int64_t idle_ns) {
    MsXchgH2Conn *conn = calloc(1, sizeof *conn);
    MsH2Conn *h2 = ms_h2conn_new(1, limits);
    if (conn == NULL || h2 == NULL) {
        free(conn);
        ms_h2conn_free(h2);
        return NULL;
    }
    atomic_init(&conn->refs, 2);
    const MsH2ServeHooks hooks = {.context = conn, .on_request = on_request, .idle_ns = idle_ns};
    conn->serve = ms_h2_serve_new(table, id, h2, &hooks);
    if (conn->serve == NULL) {
        ms_h2conn_free(h2);
        free(conn);
        return NULL;
    }
    return conn;
}

MsH2Serve *ms_xchg_h2_conn_serve(MsXchgH2Conn *conn) { return conn->serve; }

MsNetStatus ms_xchg_h2_conn_run(MsXchgH2Conn *conn) {
    MsNetStatus status = MS_NET_OK;
    while (status == MS_NET_OK) {
        status = ms_h2_serve_step(conn->serve);
    }
    conn->ended = 1;
    for (size_t i = 0; i < conn->queued; i++) { /* requests nobody took */
        ms_h2_serve_release(conn->serve, conn->queue[i], ERROR_CANCEL);
    }
    conn->queued = 0;
    wake(conn);
    const MsNetStatus final = ms_h2_serve_run(conn->serve); /* waits for the handlers and closes the row */
    wake(conn);
    ms_xchg_h2_conn_free(conn);
    return final != MS_NET_OK ? final : status;
}

MsNetStatus ms_xchg_h2_conn_next(MsXchgH2Conn *conn, int64_t deadline_ns, MsXchgH2 **out) {
    for (;;) {
        if (conn->queued > 0) {
            const int32_t stream = conn->queue[0];
            memmove(conn->queue, conn->queue + 1, (conn->queued - 1) * sizeof *conn->queue);
            conn->queued--;
            *out = exchange_new(conn, stream);
            if (*out == NULL) {
                ms_h2_stream_reset(conn->serve, stream, ERROR_INTERNAL);
                ms_h2_serve_release(conn->serve, stream, ERROR_INTERNAL);
                return MS_NET_FAILED;
            }
            return MS_NET_OK;
        }
        if (conn->ended != 0) {
            return MS_NET_CLOSED;
        }
        if (conn->waiter == 0) {
            conn->waiter = msrt_token_new(TOKEN_ANY_THREAD);
            if (conn->waiter == 0) {
                return MS_NET_FAILED;
            }
        }
        int64_t timeout_ns = -1;
        if (deadline_ns >= 0) {
            timeout_ns = deadline_ns - ms_sys_monotonic_ns();
            if (timeout_ns <= 0) {
                return MS_NET_TIMEOUT;
            }
        }
        uint64_t value = 0;
        const uint32_t result = msrt_token_park(conn->waiter, timeout_ns, &value);
        if ((result & MS_WAIT_CANCELLED) != 0) {
            return MS_NET_CANCELLED;
        }
        if ((result & MS_WAIT_TIMEOUT) != 0 && conn->queued == 0 && conn->ended == 0) {
            return MS_NET_TIMEOUT;
        }
    }
}

void ms_xchg_h2_conn_drain(MsXchgH2Conn *conn) { ms_h2_serve_drain(conn->serve); }

void ms_xchg_h2_conn_free(MsXchgH2Conn *conn) {
    if (atomic_fetch_sub(&conn->refs, 1) != 1) {
        return;
    }
    if (conn->waiter != 0) {
        msrt_token_free(conn->waiter);
    }
    free(conn->queue);
    free(conn);
}

/* ---- the request ---- */

static char *copy_bytes(MsBytes bytes) {
    char *copy = malloc(bytes.len + 1);
    if (copy != NULL) {
        if (bytes.len > 0) {
            memcpy(copy, bytes.ptr, bytes.len);
        }
        copy[bytes.len] = 0;
    }
    return copy;
}

static bool is_name(MsBytes name, const char *text) {
    return name.len == strlen(text) && memcmp(name.ptr, text, name.len) == 0;
}

/* The request fields: names canonical, cookie fields joined with "; ", Host from :authority when none was sent. */
static MsHeaders *request_fields(const MsH2Head *head) {
    MsHeaders *fields = ms_headers_new();
    if (fields == NULL) {
        return NULL;
    }
    uint8_t *cookie = NULL;
    size_t cookie_length = 0;
    bool has_host = false, ok = true;
    for (size_t i = 0; ok && i < head->nfields; i++) {
        const MsH2Header *field = &head->fields[i];
        if (is_name(field->name, "cookie")) {
            const size_t add = field->value.len + (cookie_length > 0 ? 2 : 0);
            uint8_t *grown = realloc(cookie, cookie_length + add);
            ok = grown != NULL;
            if (ok) {
                cookie = grown;
                if (cookie_length > 0) {
                    cookie[cookie_length++] = ';';
                    cookie[cookie_length++] = ' ';
                }
                if (field->value.len > 0) {
                    memcpy(cookie + cookie_length, field->value.ptr, field->value.len);
                }
                cookie_length += field->value.len;
            }
            continue;
        }
        has_host = has_host || is_name(field->name, "host");
        ok = ms_headers_add_canonical(fields, field->name, field->value);
    }
    if (ok && cookie_length > 0) {
        ok = ms_headers_add_canonical(fields, ms_bytes_of((const uint8_t *)"cookie", 6), ms_bytes_of(cookie, cookie_length));
    }
    free(cookie);
    if (ok && !has_host && head->authority.len > 0) {
        ok = ms_headers_add_canonical(fields, ms_bytes_of((const uint8_t *)"host", 4), head->authority);
    }
    if (!ok) {
        ms_headers_object(fields)->drop(ms_headers_object(fields));
        return NULL;
    }
    return fields;
}

static MsXchgH2 *exchange_new(MsXchgH2Conn *conn, int32_t stream) {
    const MsH2Head *head = ms_h2_stream_head(conn->serve, stream);
    if (head == NULL) {
        return NULL;
    }
    MsXchgH2 *x = calloc(1, sizeof *x);
    if (x == NULL) {
        return NULL;
    }
    x->conn = conn;
    x->stream = stream;
    x->method_length = head->method.len;
    const bool connect = is_name(head->method, "CONNECT");
    const MsBytes target = connect ? head->authority : head->path;
    x->target_length = target.len;
    x->method = copy_bytes(head->method);
    x->target = copy_bytes(target);
    x->fields = request_fields(head);
    x->is_head = is_name(head->method, "HEAD");
    if (x->method == NULL || x->target == NULL || x->fields == NULL) {
        free(x->method);
        free(x->target);
        free(x);
        return NULL;
    }
    atomic_fetch_add(&conn->refs, 1);
    return x;
}

MsBytes ms_xchg_h2_method(const MsXchgH2 *x) { return ms_bytes_of((const uint8_t *)x->method, x->method_length); }
MsBytes ms_xchg_h2_target(const MsXchgH2 *x) { return ms_bytes_of((const uint8_t *)x->target, x->target_length); }
MsBytes ms_xchg_h2_protocol(const MsXchgH2 *x) {
    (void)x;
    return ms_bytes_of((const uint8_t *)"HTTP/2.0", 8);
}

MsHeaders *ms_xchg_h2_headers(const MsXchgH2 *x) {
    MsHeaders *copy = ms_headers_new();
    for (size_t i = 0; copy != NULL && i < ms_headers_count(x->fields); i++) {
        MsBytes name, value;
        ms_headers_field(x->fields, i, &name, &value);
        if (!ms_headers_add_canonical(copy, name, value)) {
            ms_headers_object(copy)->drop(ms_headers_object(copy));
            return NULL;
        }
    }
    return copy;
}

/* ---- the body ---- */

static uint8_t status_of(MsNetStatus status, MsStr *err) {
    if (status == MS_NET_RESET) {
        return STATUS_INVALID_DATA; /* the peer reset the request: a truncated body */
    }
    return ms_net_finish(status, 0, err);
}

uint8_t ms_xchg_h2_read(MsXchgH2 *x, uint8_t has_max, int64_t max, uint8_t has_timeout, int64_t timeout, MsVec *out, MsStr *err) {
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
    if (x->released != 0) {
        return STATUS_CLOSED;
    }
    uint8_t *buffer = malloc(capacity);
    if (buffer == NULL) {
        return ms_net_finish(MS_NET_FAILED, 0, err);
    }
    size_t count = 0;
    const MsNetStatus status = ms_h2_stream_read(x->conn->serve, x->stream, buffer, capacity, ms_net_deadline_of(has_timeout, timeout), &count);
    if (status == MS_NET_OK && count > 0) {
        msrt_write_bytes(out, buffer, count);
    }
    free(buffer);
    if (status == MS_NET_OK) {
        return count > 0 ? STATUS_OK : STATUS_NONE;
    }
    return status_of(status, err);
}

/* ---- the response ---- */

static bool is_token_byte(uint8_t c) {
    return ms_ascii_is_alnum(c) || (c != 0 && strchr("!#$%&'*+-.^_`|~", (char)c) != NULL);
}

static bool connection_specific(MsBytes name) {
    static const char *const names[] = {"connection", "keep-alive", "proxy-connection", "transfer-encoding", "upgrade", "content-length", "te", "host"};
    for (size_t i = 0; i < sizeof names / sizeof *names; i++) {
        if (is_name(name, names[i])) {
            return true;
        }
    }
    return false;
}

static bool body_forbidden(int64_t status) { return status < 200 || status == 204 || status == 304; }

typedef struct Block {
    MsH2Nv *nv;
    char **names;   /* owned lowercase copies */
    size_t count, capacity;
    char status[8];
    char length[24];
} Block;

static void block_free(Block *block) {
    for (size_t i = 0; i < block->count; i++) {
        free(block->names[i]);
    }
    free(block->names);
    free(block->nv);
}

static bool block_add(Block *block, const char *name, size_t name_length, const char *value, size_t value_length, char *owned) {
    if (block->count == block->capacity) {
        const size_t capacity = block->capacity == 0 ? 16 : block->capacity * 2;
        MsH2Nv *nv = realloc(block->nv, capacity * sizeof *nv);
        if (nv == NULL) {
            return false;
        }
        block->nv = nv;
        char **names = realloc(block->names, capacity * sizeof *names);
        if (names == NULL) {
            return false;
        }
        block->names = names;
        block->capacity = capacity;
    }
    block->nv[block->count] = (MsH2Nv){name, name_length, value, value_length};
    block->names[block->count] = owned;
    block->count++;
    return true;
}

/* The response head: `:status`, then the handler's fields lowercased without the connection-specific ones, then
 * content-length. INVALID_INPUT for a name or value that could split a message. */
static uint8_t build_head(Block *block, int64_t status, const MsHeaders *headers, bool with_length, int64_t length) {
    (void)snprintf(block->status, sizeof block->status, "%d", (int)status);
    if (!block_add(block, ":status", 7, block->status, strlen(block->status), NULL)) {
        return STATUS_FAILED;
    }
    for (size_t i = 0; headers != NULL && i < ms_headers_count(headers); i++) {
        MsBytes name, value;
        ms_headers_field(headers, i, &name, &value);
        if (name.len == 0) {
            return STATUS_INVALID_INPUT;
        }
        for (size_t n = 0; n < name.len; n++) {
            if (!is_token_byte(name.ptr[n])) {
                return STATUS_INVALID_INPUT;
            }
        }
        for (size_t n = 0; n < value.len; n++) {
            if (value.ptr[n] == '\r' || value.ptr[n] == '\n' || value.ptr[n] == 0) {
                return STATUS_INVALID_INPUT;
            }
        }
        char *lower = malloc(name.len + 1);
        if (lower == NULL) {
            return STATUS_FAILED;
        }
        for (size_t n = 0; n < name.len; n++) {
            lower[n] = (char)(ms_ascii_is_upper(name.ptr[n]) ? name.ptr[n] + ('a' - 'A') : name.ptr[n]);
        }
        lower[name.len] = 0;
        if (connection_specific(ms_bytes_of((const uint8_t *)lower, name.len))) {
            free(lower);
            continue;
        }
        if (!block_add(block, lower, name.len, (const char *)value.ptr, value.len, lower)) {
            free(lower);
            return STATUS_FAILED;
        }
    }
    if (with_length) {
        (void)snprintf(block->length, sizeof block->length, "%lld", (long long)length);
        if (!block_add(block, "content-length", 14, block->length, strlen(block->length), NULL)) {
            return STATUS_FAILED;
        }
    }
    return STATUS_OK;
}

uint8_t ms_xchg_h2_send_head(MsXchgH2 *x, int64_t status, const MsHeaders *headers, uint8_t has_length, int64_t length, MsStr *err) {
    if (status < 100 || status > 999 || x->head_sent != 0 || (has_length != 0 && length < 0)) {
        return STATUS_INVALID_INPUT;
    }
    if (x->released != 0) {
        return STATUS_CLOSED;
    }
    if (status < 200) {
        return STATUS_OK; /* an interim response: nothing is sent on this transport */
    }
    const bool no_body = x->is_head || body_forbidden(status);
    Block block = {0};
    uint8_t result = build_head(&block, status, headers, has_length != 0 && !body_forbidden(status), length);
    if (result == STATUS_OK) {
        const MsNetStatus sent = ms_h2_stream_respond(x->conn->serve, x->stream, block.nv, block.count, no_body ? 0 : 1);
        result = sent == MS_NET_OK ? STATUS_OK : status_of(sent, err);
    }
    block_free(&block);
    if (result == STATUS_OK) {
        x->head_sent = 1;
        x->no_body = no_body ? 1 : 0;
        x->local_ended = no_body ? 1 : 0;
        x->has_length = has_length != 0 && !body_forbidden(status) ? 1 : 0;
        x->length = length;
    }
    return result;
}

uint8_t ms_xchg_h2_write(MsXchgH2 *x, MsBytes data, uint8_t has_timeout, int64_t timeout, MsStr *err) {
    if (x->head_sent == 0) {
        return STATUS_INVALID_INPUT;
    }
    if (x->released != 0) {
        return STATUS_CLOSED;
    }
    if (x->no_body != 0 || data.len == 0) {
        return STATUS_OK;
    }
    if (x->has_length != 0 && (int64_t)data.len > x->length - x->written) {
        return STATUS_OUT_OF_RANGE;
    }
    const MsNetStatus status = ms_h2_stream_write(x->conn->serve, x->stream, data.ptr, data.len, 0, ms_net_deadline_of(has_timeout, timeout));
    if (status != MS_NET_OK) {
        return status_of(status, err);
    }
    x->written += (int64_t)data.len;
    return STATUS_OK;
}

static void release(MsXchgH2 *x, uint32_t code) {
    if (x->released == 0) {
        x->released = 1;
        ms_h2_serve_release(x->conn->serve, x->stream, code);
    }
}

uint8_t ms_xchg_h2_finish(MsXchgH2 *x, uint8_t has_timeout, int64_t timeout, uint8_t *keep, MsStr *err) {
    *keep = 0;
    if (x->released != 0) {
        return STATUS_CLOSED;
    }
    if (x->head_sent == 0) {
        return STATUS_INVALID_INPUT;
    }
    uint8_t result = STATUS_OK;
    if (x->local_ended == 0) {
        if (x->has_length != 0 && x->written < x->length) {
            (void)ms_h2_stream_reset(x->conn->serve, x->stream, ERROR_INTERNAL);
            result = STATUS_INVALID_DATA; /* shorter than declared: the stream is reset, the connection is fine */
        } else {
            const MsNetStatus status = ms_h2_stream_write(x->conn->serve, x->stream, NULL, 0, 1, ms_net_deadline_of(has_timeout, timeout));
            result = status == MS_NET_OK ? STATUS_OK : status_of(status, err);
        }
        x->local_ended = 1;
    }
    release(x, 0); /* a request body still unread is cut off with NO_ERROR */
    *keep = x->conn->ended == 0 ? 1 : 0;
    return result;
}

uint8_t ms_xchg_h2_reset(MsXchgH2 *x, int64_t max, uint8_t has_timeout, int64_t timeout, MsStr *err) {
    if (max < 0) {
        return STATUS_INVALID_INPUT;
    }
    if (x->released != 0) {
        return STATUS_CLOSED;
    }
    const int64_t deadline = ms_net_deadline_of(has_timeout, timeout);
    uint8_t buffer[4096];
    int64_t left = max;
    for (;;) {
        size_t count = 0;
        const MsNetStatus status = ms_h2_stream_read(x->conn->serve, x->stream, buffer, sizeof buffer, deadline, &count);
        if (status != MS_NET_OK) {
            return status_of(status, err);
        }
        if (count == 0) {
            return STATUS_OK;
        }
        if ((int64_t)count > left) {
            return STATUS_LIMIT_EXCEEDED;
        }
        left -= (int64_t)count;
    }
}

uint8_t ms_xchg_h2_wait_gone(MsXchgH2 *x, MsStr *err) {
    if (x->released != 0) {
        return STATUS_OK;
    }
    const MsNetStatus status = ms_h2_stream_wait_gone(x->conn->serve, x->stream);
    return status == MS_NET_RESET || status == MS_NET_CLOSED ? STATUS_OK : ms_net_finish(status, 0, err);
}

void ms_xchg_h2_drop(MsXchgH2 *x) {
    release(x, x->local_ended != 0 ? 0 : ERROR_CANCEL);
    ms_headers_object(x->fields)->drop(ms_headers_object(x->fields));
    free(x->method);
    free(x->target);
    ms_xchg_h2_conn_free(x->conn);
    free(x);
}
