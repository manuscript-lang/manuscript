/* The WebSocket message session (ws_socket.h). */
#include "ws_socket.h"

#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms_rt/alloc.h"
#include "ms_rt/sys.h"
#include "ms_rt/utf8.h"
#include "ws_codec.h"

enum {
    CONTROL_WRITE_NS = 1000000000,
    PING_WRITE_NS = 1000000000,
    CLOSE_WRITE_NS = 100000000,
    MAX_CLOSE_REASON = 123,
    READ_CHUNK = 16 * 1024,
    ERROR_TEXT = 160
};

/* The wording of a failure inside a message body: the reader's errors cannot be told apart. */
static const char truncated_text[] = "connection closed before the exchange completed";
static const char close_sent_text[] = "websocket: close sent";

typedef struct WriteError {
    MsWsStatus status; /* MS_WSS_OK while writes work */
    char text[ERROR_TEXT];
} WriteError;

struct MsWsSocket {
    atomic_uint refs;
    MsObj *conn;
    MsWsRole role;
    uint64_t max_message_bytes;
    bool compress;
    char subprotocol[128];
    size_t subprotocol_len;
    MsWsDecoder decoder;
    uint8_t *scratch; /* READ_CHUNK bytes, allocated by the first read */
    atomic_bool reading;
    atomic_bool closed; /* close() ran */
    atomic_bool failed; /* a read failure ended the session */
    /* Writes: a frame queued while another task is writing is written by it, in order. */
    atomic_flag queue_lock;
    MsWsBuf queue;
    bool flushing;
    WriteError write_error;
    char error[ERROR_TEXT];
};

/* ---- construction ---- */

static MsNetConn *net_conn(const MsWsSocket *s) { return ms_netconn_of(s->conn); }

MsWsSocket *ms_ws_socket_new(MsObj *conn, MsWsRole role, const MsWsConfig *config) {
    MsWsSocket *s = msrt_alloc_zeroed(sizeof *s);
    if (s == NULL) {
        return NULL;
    }
    atomic_init(&s->refs, 1);
    s->conn = conn;
    s->role = role;
    s->max_message_bytes = config->max_message_bytes;
    s->compress = config->compress;
    s->subprotocol_len = config->subprotocol.len < sizeof s->subprotocol ? config->subprotocol.len : sizeof s->subprotocol - 1;
    if (s->subprotocol_len > 0) {
        memcpy(s->subprotocol, config->subprotocol.ptr, s->subprotocol_len);
    }
    atomic_init(&s->reading, false);
    atomic_init(&s->closed, false);
    atomic_init(&s->failed, false);
    atomic_flag_clear(&s->queue_lock);
    ms_ws_decoder_init(&s->decoder, role == MS_WS_ROLE_SERVER, config->compress, config->max_message_bytes);
    /* Bytes the HTTP layer read past the handshake stay in the row's stash: take them as the first input. */
    MsConn *row = ms_conn_get(ms_netconn_table(net_conn(s)), ms_netconn_id(net_conn(s)));
    if (row != NULL && row->stash_len > 0) {
        const bool taken = ms_ws_decoder_push(&s->decoder, ms_bytes_of(row->stash, row->stash_len));
        free(row->stash); /* the row's stash is the C library's */
        row->stash = NULL;
        row->stash_len = 0;
        if (!taken) {
            ms_ws_decoder_free(&s->decoder);
            msrt_free(s);
            return NULL;
        }
    }
    return s;
}

MsWsSocket *ms_ws_socket_retain(MsWsSocket *s) {
    atomic_fetch_add(&s->refs, 1);
    return s;
}

void ms_ws_socket_release(MsWsSocket *s) {
    if (atomic_fetch_sub(&s->refs, 1) != 1) {
        return;
    }
    ms_ws_decoder_free(&s->decoder);
    ms_ws_buf_free(&s->queue);
    msrt_free(s->scratch);
    s->conn->drop(s->conn);
    msrt_free(s);
}

unsigned ms_ws_socket_refs(const MsWsSocket *s) { return atomic_load(&s->refs); }

MsWsStatus ms_ws_socket_feed(MsWsSocket *s, MsBytes bytes) {
    return ms_ws_decoder_push(&s->decoder, bytes) ? MS_WSS_OK : MS_WSS_NOMEM;
}

MsBytes ms_ws_socket_subprotocol(const MsWsSocket *s) { return ms_bytes_of((const uint8_t *)s->subprotocol, s->subprotocol_len); }

const char *ms_ws_socket_error(const MsWsSocket *s) { return s->error; }

/* ---- state ---- */

bool ms_ws_socket_is_closed(const MsWsSocket *s) {
    return atomic_load(&s->closed) || atomic_load(&s->failed) || ms_netconn_closed(net_conn(s));
}

static MsWsStatus admit(const MsWsSocket *s) { return ms_ws_socket_is_closed(s) ? MS_WSS_CLOSED : MS_WSS_OK; }

/* Ends the session after a read failure. */
static void fail_session(MsWsSocket *s) {
    atomic_store(&s->failed, true);
    ms_netconn_close(s->conn);
}

static MsWsStatus failed_with(MsWsSocket *s, const char *text) {
    (void)snprintf(s->error, sizeof s->error, "%s", text);
    return MS_WSS_FAILED;
}

/* A failure of the exchange: worded as a truncated exchange once a message body was under way. */
static MsWsStatus failed_text(MsWsSocket *s, const char *text, bool body) { return failed_with(s, body ? truncated_text : text); }

/* Ends the session with `status`, unless the session was closed locally meanwhile. */
static MsWsStatus finish(MsWsSocket *s, MsWsStatus status) {
    const bool local = atomic_load(&s->closed) || ms_netconn_closed(net_conn(s));
    fail_session(s);
    return local ? MS_WSS_CLOSED : status;
}

static int64_t deadline_in(int64_t ns) { return ms_sys_monotonic_ns() + ns; }

/* ---- writing ---- */

static void queue_lock(MsWsSocket *s) {
    while (atomic_flag_test_and_set_explicit(&s->queue_lock, memory_order_acquire)) {
        ms_sys_yield();
    }
}

static void queue_unlock(MsWsSocket *s) { atomic_flag_clear_explicit(&s->queue_lock, memory_order_release); }

/* How a connection status reads as a session status; `on_timeout` is what a timed-out write becomes. */
static MsWsStatus from_net(MsWsSocket *s, MsNetStatus net, MsWsStatus on_timeout, const char *timeout_text) {
    switch (net) {
    case MS_NET_OK: return MS_WSS_OK;
    case MS_NET_CLOSED: return MS_WSS_CLOSED;
    case MS_NET_CANCELLED: return MS_WSS_CANCELLED;
    case MS_NET_TIMEOUT: return on_timeout == MS_WSS_FAILED ? failed_with(s, timeout_text) : on_timeout;
    default: return failed_with(s, ms_net_status_text(net));
    }
}

static void remember_write_error(MsWsSocket *s, MsWsStatus status, const char *text) {
    s->write_error.status = status;
    (void)snprintf(s->write_error.text, sizeof s->write_error.text, "%s", text);
}

static MsWsStatus replay_write_error(MsWsSocket *s) {
    if (s->write_error.status == MS_WSS_FAILED) {
        return failed_with(s, s->write_error.text);
    }
    return s->write_error.status;
}

/* Writes the queued frames, in order, until none is left. A failure is sticky. */
static MsWsStatus flush(MsWsSocket *s, int64_t deadline_ns, MsWsStatus on_timeout, const char *timeout_text) {
    for (;;) {
        queue_lock(s);
        MsWsBuf batch = s->queue;
        s->queue = (MsWsBuf){0};
        if (batch.len == 0) {
            s->flushing = false;
            queue_unlock(s);
            ms_ws_buf_free(&batch);
            return MS_WSS_OK;
        }
        queue_unlock(s);
        MsNetConn *net = net_conn(s);
        const MsNetStatus rc = ms_conn_write(ms_netconn_table(net), ms_netconn_id(net), batch.ptr, batch.len, deadline_ns);
        ms_ws_buf_free(&batch);
        if (rc != MS_NET_OK) {
            const MsWsStatus status = from_net(s, rc, on_timeout, timeout_text);
            remember_write_error(s, status, s->error);
            queue_lock(s);
            ms_ws_buf_free(&s->queue);
            s->flushing = false;
            queue_unlock(s);
            return status;
        }
    }
}

/* Queues one encoded frame (taking it over). A nested call while a write runs only queues its bytes behind it. */
static MsWsStatus write_frame(MsWsSocket *s, MsWsBuf *frame, int64_t deadline_ns, MsWsStatus on_timeout, const char *timeout_text) {
    if (s->write_error.status != MS_WSS_OK) {
        ms_ws_buf_free(frame);
        return replay_write_error(s);
    }
    queue_lock(s);
    const bool queued = ms_ws_buf_append(&s->queue, ms_bytes_of(frame->ptr, frame->len));
    const bool writer = queued && !s->flushing;
    if (writer) {
        s->flushing = true;
    }
    queue_unlock(s);
    ms_ws_buf_free(frame);
    if (!queued) {
        return MS_WSS_NOMEM;
    }
    return writer ? flush(s, deadline_ns, on_timeout, timeout_text) : MS_WSS_OK;
}

static MsWsStatus write_control(MsWsSocket *s, uint8_t opcode, MsBytes payload, int64_t timeout_ns, MsWsStatus on_timeout,
                                const char *timeout_text) {
    MsWsBuf frame = {0};
    bool too_long;
    if (!ms_ws_encode_control(&frame, opcode, payload, s->role == MS_WS_ROLE_CLIENT, &too_long)) {
        ms_ws_buf_free(&frame);
        return too_long ? MS_WSS_INVALID_INPUT : MS_WSS_NOMEM;
    }
    const MsWsStatus status = write_frame(s, &frame, deadline_in(timeout_ns), on_timeout, timeout_text);
    if (status == MS_WSS_OK && opcode == MS_WS_CLOSE) {
        remember_write_error(s, MS_WSS_FAILED, close_sent_text);
    }
    return status;
}

/* A close frame carrying `code` and `reason`, best effort. */
static void send_close(MsWsSocket *s, unsigned code, MsBytes reason, int64_t timeout_ns) {
    MsWsBuf payload = {0};
    if (ms_ws_format_close(&payload, code, reason)) {
        (void)write_control(s, MS_WS_CLOSE, ms_bytes_of(payload.ptr, payload.len), timeout_ns, MS_WSS_TIMEOUT, "");
    }
    ms_ws_buf_free(&payload);
}

MsWsStatus ms_ws_socket_send(MsWsSocket *s, MsBytes data, bool text, int64_t deadline_ns) {
    const MsWsStatus open = admit(s);
    if (open != MS_WSS_OK) {
        return open;
    }
    if (data.len > s->max_message_bytes) {
        return MS_WSS_LIMIT;
    }
    if (text && !ms_utf8_is_valid(data.ptr, data.len)) {
        return MS_WSS_INVALID_DATA;
    }
    MsWsBuf frame = {0};
    if (!ms_ws_encode_message(&frame, text ? MS_WS_TEXT : MS_WS_BINARY, data, s->role == MS_WS_ROLE_CLIENT, s->compress)) {
        ms_ws_buf_free(&frame);
        return MS_WSS_NOMEM;
    }
    return write_frame(s, &frame, deadline_ns, MS_WSS_TIMEOUT, "");
}

MsWsStatus ms_ws_socket_ping(MsWsSocket *s, MsBytes data) {
    const MsWsStatus open = admit(s);
    return open != MS_WSS_OK ? open : write_control(s, MS_WS_PING, data, PING_WRITE_NS, MS_WSS_FAILED, "i/o timeout");
}

/* ---- closing ---- */

void ms_ws_socket_close_with(MsWsSocket *s, unsigned code, MsBytes reason) {
    if (atomic_exchange(&s->closed, true)) {
        return;
    }
    if (!ms_netconn_closed(net_conn(s))) {
        size_t end = reason.len < MAX_CLOSE_REASON ? reason.len : MAX_CLOSE_REASON;
        while (end > 0 && end < reason.len && (reason.ptr[end] & 0xc0) == 0x80) {
            end--;
        }
        send_close(s, code, ms_bytes_of(reason.ptr, end), CLOSE_WRITE_NS);
    }
    ms_netconn_close(s->conn);
}

void ms_ws_socket_close(MsWsSocket *s) { ms_ws_socket_close_with(s, MS_WS_CLOSE_NORMAL, ms_bytes_of(NULL, 0)); }

/* ---- reading ---- */

/* Reads more bytes into the decoder. OK means the caller polls again. */
static MsWsStatus fill(MsWsSocket *s, int64_t deadline_ns) {
    if (s->scratch == NULL) {
        s->scratch = msrt_alloc(READ_CHUNK);
        if (s->scratch == NULL) {
            return MS_WSS_NOMEM;
        }
    }
    MsNetConn *net = net_conn(s);
    size_t count = 0;
    const MsNetStatus rc = ms_conn_read(ms_netconn_table(net), ms_netconn_id(net), s->scratch, READ_CHUNK, deadline_ns, &count);
    const bool body = ms_ws_decoder_in_message(&s->decoder);
    MsWsStatus status;
    if (rc == MS_NET_OK && count > 0) {
        return ms_ws_decoder_push(&s->decoder, ms_bytes_of(s->scratch, count)) ? MS_WSS_OK : MS_WSS_NOMEM;
    }
    if (rc == MS_NET_OK) {
        char text[ERROR_TEXT];
        ms_ws_close_text(MS_WS_CLOSE_ABNORMAL, ms_bytes_of((const uint8_t *)"unexpected EOF", 14), text, sizeof text);
        status = failed_text(s, text, body);
    } else if (rc == MS_NET_TIMEOUT && deadline_ns >= 0) {
        return MS_WSS_TIMEOUT;
    } else if (rc == MS_NET_CANCELLED) {
        return MS_WSS_CANCELLED;
    } else if (rc == MS_NET_CLOSED) {
        status = MS_WSS_CLOSED;
    } else if (rc == MS_NET_RESET) {
        status = failed_text(s, ms_net_status_text(rc), body);
    } else {
        status = failed_text(s, truncated_text, true);
    }
    return finish(s, status);
}

/* The default ping handler: a pong with the same payload. A sent close frame and a timeout are ignored; any other
 * write failure ends the session. */
static MsWsStatus answer_ping(MsWsSocket *s, MsBytes payload) {
    const MsWsStatus status = write_control(s, MS_WS_PONG, payload, CONTROL_WRITE_NS, MS_WSS_TIMEOUT, "");
    if (status == MS_WSS_OK || status == MS_WSS_TIMEOUT) {
        return MS_WSS_OK;
    }
    if (status == MS_WSS_FAILED && strcmp(s->error, close_sent_text) == 0) {
        return MS_WSS_OK;
    }
    if (status == MS_WSS_FAILED && ms_ws_decoder_in_message(&s->decoder)) {
        (void)failed_with(s, truncated_text);
    }
    return finish(s, status);
}

/* The default close handler: echoes the code. A normal end (1000, 1001) between messages is not an error. */
static MsWsStatus peer_closed(MsWsSocket *s, const MsWsEvent *event, bool *ended) {
    char text[ERROR_TEXT];
    ms_ws_close_text(event->code, event->data, text, sizeof text);
    send_close(s, event->code, ms_bytes_of(NULL, 0), CONTROL_WRITE_NS);
    const bool body = ms_ws_decoder_in_message(&s->decoder);
    if (!body && (event->code == MS_WS_CLOSE_NORMAL || event->code == MS_WS_CLOSE_GOING_AWAY)) {
        fail_session(s);
        *ended = true;
        return MS_WSS_OK;
    }
    return finish(s, failed_text(s, text, body));
}

static MsWsStatus decode_failure(MsWsSocket *s, const MsWsEvent *event) {
    MsWsStatus status;
    switch (event->failure) {
    case MS_WSF_PROTOCOL: {
        MsWsBuf payload = {0};
        const size_t length = strlen(event->reason);
        const size_t cut = length < MS_WS_MAX_CONTROL - 2 ? length : MS_WS_MAX_CONTROL - 2;
        if (ms_ws_format_close(&payload, MS_WS_CLOSE_PROTOCOL, ms_bytes_of((const uint8_t *)event->reason, cut))) {
            (void)write_control(s, MS_WS_CLOSE, ms_bytes_of(payload.ptr, payload.len), CONTROL_WRITE_NS, MS_WSS_TIMEOUT, "");
        }
        ms_ws_buf_free(&payload);
        char text[ERROR_TEXT];
        (void)snprintf(text, sizeof text, "websocket: %s", event->reason);
        status = failed_text(s, text, event->body);
        break;
    }
    case MS_WSF_LIMIT:
        if (event->reply_close) {
            send_close(s, MS_WS_CLOSE_TOO_BIG, ms_bytes_of(NULL, 0), CONTROL_WRITE_NS);
        }
        status = event->body ? failed_with(s, truncated_text) : MS_WSS_LIMIT;
        break;
    case MS_WSF_INVALID_PAYLOAD:
        send_close(s, MS_WS_CLOSE_INVALID_PAYLOAD, ms_bytes_of(NULL, 0), CONTROL_WRITE_NS);
        status = MS_WSS_INVALID_DATA;
        break;
    case MS_WSF_OVERFLOW: status = MS_WSS_LIMIT; break;
    case MS_WSF_CORRUPT: status = failed_with(s, truncated_text); break;
    default: status = MS_WSS_NOMEM; break;
    }
    return finish(s, status);
}

/* RFC 6455 8.1: a text message that is not UTF-8 fails the connection with 1007. */
static MsWsStatus reject_text(MsWsSocket *s) {
    atomic_store(&s->failed, true);
    send_close(s, MS_WS_CLOSE_INVALID_PAYLOAD, ms_bytes_of(NULL, 0), CLOSE_WRITE_NS);
    ms_netconn_close(s->conn);
    return MS_WSS_INVALID_DATA;
}

static MsWsStatus receive_loop(MsWsSocket *s, int64_t deadline_ns, MsWsMessage *message, bool *ended) {
    for (;;) {
        MsWsEvent event;
        ms_ws_decoder_poll(&s->decoder, &event);
        MsWsStatus status;
        switch (event.kind) {
        case MS_WSE_NEED_MORE:
            status = fill(s, deadline_ns);
            if (status != MS_WSS_OK) {
                return status;
            }
            break;
        case MS_WSE_MESSAGE:
            if (event.text && !ms_utf8_is_valid(event.data.ptr, event.data.len)) {
                return reject_text(s);
            }
            *message = (MsWsMessage){.data = event.data, .text = event.text};
            return MS_WSS_OK;
        case MS_WSE_PING:
            status = answer_ping(s, event.data);
            if (status != MS_WSS_OK) {
                return status;
            }
            break;
        case MS_WSE_PONG: break;
        case MS_WSE_CLOSE: return peer_closed(s, &event, ended);
        case MS_WSE_FAIL: return decode_failure(s, &event);
        }
    }
}

MsWsStatus ms_ws_socket_receive(MsWsSocket *s, int64_t deadline_ns, MsWsMessage *message, bool *ended) {
    *ended = false;
    const MsWsStatus open = admit(s);
    if (open != MS_WSS_OK) {
        return open;
    }
    if (atomic_exchange(&s->reading, true)) {
        return failed_with(s, "websocket: concurrent receive");
    }
    const MsWsStatus status = receive_loop(s, deadline_ns, message, ended);
    atomic_store(&s->reading, false);
    return status;
}

/* ---- closing with a handshake ---- */

static MsWsStatus await_close(MsWsSocket *s, int64_t deadline_ns) {
    MsNetConn *net = net_conn(s);
    for (;;) {
        MsWsEvent event;
        ms_ws_decoder_poll(&s->decoder, &event);
        if (event.kind == MS_WSE_CLOSE) {
            return MS_WSS_OK;
        }
        if (event.kind == MS_WSE_FAIL) {
            return failed_with(s, truncated_text);
        }
        if (event.kind != MS_WSE_NEED_MORE) {
            continue;
        }
        if (s->scratch == NULL) {
            s->scratch = msrt_alloc(READ_CHUNK);
            if (s->scratch == NULL) {
                return MS_WSS_NOMEM;
            }
        }
        size_t count = 0;
        const MsNetStatus rc = ms_conn_read(ms_netconn_table(net), ms_netconn_id(net), s->scratch, READ_CHUNK, deadline_ns, &count);
        if (rc == MS_NET_OK && count == 0) {
            return MS_WSS_OK;
        }
        if (rc == MS_NET_RESET) {
            return MS_WSS_OK; /* a peer that closed its socket answers our close frame with a reset */
        }
        if (rc != MS_NET_OK) {
            return from_net(s, rc, MS_WSS_TIMEOUT, "");
        }
        if (!ms_ws_decoder_push(&s->decoder, ms_bytes_of(s->scratch, count))) {
            return MS_WSS_NOMEM;
        }
    }
}

MsWsStatus ms_ws_socket_close_handshake(MsWsSocket *s, unsigned code, MsBytes reason, int64_t deadline_ns) {
    const MsWsStatus open = admit(s);
    if (open != MS_WSS_OK) {
        return open;
    }
    if (atomic_exchange(&s->reading, true)) {
        return failed_with(s, "websocket: concurrent receive");
    }
    const size_t cut = reason.len < MAX_CLOSE_REASON ? reason.len : MAX_CLOSE_REASON;
    size_t end = cut;
    while (end > 0 && end < reason.len && (reason.ptr[end] & 0xc0) == 0x80) {
        end--;
    }
    send_close(s, code, ms_bytes_of(reason.ptr, end), CONTROL_WRITE_NS);
    const MsWsStatus status = await_close(s, deadline_ns);
    atomic_store(&s->reading, false);
    atomic_store(&s->closed, true);
    ms_netconn_close(s->conn);
    return status;
}
