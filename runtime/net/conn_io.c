/* Byte I/O on connection rows (conn_io.h). */
#include "../io/probe.h"
#include "conn_io.h"

#include <stdlib.h>
#include <string.h>

#include "ms_rt/safe.h"
#include "ms_rt/sys.h"
#include "ms_rt/sys_net.h"
#include "ms_sched.h"

enum { PUMP_BYTES = 16384 };

/* ---- row state ---- */

static MsConnExt *ext_of(MsConn *row) { return row->ext; }

/* The row's cold state, made on first use. NULL when out of memory. */
static MsConnExt *ext_ensure(MsConn *row) {
    if (row->ext == NULL) {
        row->ext = calloc(1, sizeof(MsConnExt));
    }
    return ext_of(row);
}

static MsNetStatus fail(MsConn *row, MsNetStatus status, int code) {
    MsConnExt *ext = ext_ensure(row);
    if (ext != NULL) {
        ext->error_code = code;
    }
    return status;
}

static bool is_broken(const MsConn *row) {
    const MsConnExt *ext = row->ext;
    return ext != NULL && ext->broken != 0;
}

static void mark_broken(MsConn *row) {
    MsConnExt *ext = ext_ensure(row);
    if (ext != NULL) {
        ext->broken = 1;
    }
}

static MsTls *tls_of(const MsConn *row) {
    const MsConnExt *ext = row->ext;
    return ext == NULL ? NULL : ext->tls;
}

/* The live, unbroken row for `id`, or NULL. */
static MsConn *usable(MsConnTable *table, MsConnId id) {
    MsConn *row = ms_conn_get(table, id);
    return row == NULL || is_broken(row) ? NULL : row;
}

MsNetStatus ms_conn_set_tls(MsConnTable *table, MsConnId id, MsTls *tls) {
    MsConn *row = ms_conn_get(table, id);
    MsConnExt *ext = row == NULL ? NULL : ext_ensure(row);
    if (ext == NULL) {
        return MS_NET_CLOSED;
    }
    ext->tls = tls;
    return MS_NET_OK;
}

MsNetStatus ms_conn_set_app(MsConnTable *table, MsConnId id, void *app, void (*app_free)(void *app)) {
    MsConn *row = ms_conn_get(table, id);
    MsConnExt *ext = row == NULL ? NULL : ext_ensure(row);
    if (ext == NULL) {
        return MS_NET_CLOSED;
    }
    ext->app = app;
    ext->app_free = app_free;
    return MS_NET_OK;
}

void *ms_conn_app(MsConnTable *table, MsConnId id) {
    const MsConn *row = ms_conn_get(table, id);
    const MsConnExt *ext = row == NULL ? NULL : row->ext;
    return ext == NULL ? NULL : ext->app;
}

MsTls *ms_conn_tls(MsConnTable *table, MsConnId id) {
    const MsConn *row = ms_conn_get(table, id);
    return row == NULL ? NULL : tls_of(row);
}

bool ms_conn_buffered(MsConnTable *table, MsConnId id) {
    const MsConn *row = ms_conn_get(table, id);
    const MsConnExt *ext = row == NULL ? NULL : row->ext;
    if (ext == NULL) {
        return false;
    }
    return ext->unread_length > 0 || (ext->tls != NULL && ms_tls_pending(ext->tls) != 0);
}

int ms_conn_error_code(MsConnTable *table, MsConnId id) {
    const MsConn *row = ms_conn_get(table, id);
    const MsConnExt *ext = row == NULL ? NULL : row->ext;
    return ext == NULL ? 0 : ext->error_code;
}

const char *ms_net_status_text(MsNetStatus status) {
    switch (status) {
    case MS_NET_OK: return "";
    case MS_NET_CLOSED: return "connection closed";
    case MS_NET_TIMEOUT: return "timed out";
    case MS_NET_CANCELLED: return "cancelled";
    case MS_NET_RESET: return "connection reset by peer";
    case MS_NET_FAILED: return "connection failed";
    }
    return "connection failed";
}

/* ---- waiting ---- */

/* Parks the task until the descriptor is ready for `events` or the deadline passes. */
static MsNetStatus wait_for(const MsConn *row, uint32_t events, int64_t deadline_ns) {
    int64_t timeout_ns = -1;
    if (deadline_ns >= 0) {
        timeout_ns = deadline_ns - ms_sys_monotonic_ns();
        if (timeout_ns <= 0) {
            return MS_NET_TIMEOUT;
        }
    }
    const uint32_t got = msrt_task_wait_fd(row->fd, events, timeout_ns);
    if ((got & MS_WAIT_CANCELLED) != 0) {
        return MS_NET_CANCELLED;
    }
    if ((got & MS_WAIT_TIMEOUT) != 0 && (got & (MS_WAIT_READ | MS_WAIT_WRITE | MS_WAIT_HUP)) == 0) {
        return MS_NET_TIMEOUT;
    }
    return MS_NET_OK;
}

/* ---- the socket ---- */

/* Reads some ciphertext or plain bytes; `*count` 0 with OK is the end of the stream. */
static MsNetStatus socket_read(MsConn *row, uint8_t *buffer, size_t capacity, int64_t deadline_ns, size_t *count) {
    for (;;) {
        size_t done = 0;
        const int result = ms_sys_net_read(row->fd, buffer, capacity, &done);
        if (result == MS_SYS_OK || result == MS_SYS_EOF) {
            *count = result == MS_SYS_EOF ? 0 : done;
            return MS_NET_OK;
        }
        if (result == MS_SYS_ERROR) {
            return fail(row, MS_NET_RESET, ms_sys_net_error());
        }
        const MsNetStatus waited = wait_for(row, MS_WAIT_READ, deadline_ns);
        if (waited != MS_NET_OK) {
            return waited;
        }
    }
}

/* Writes every byte. */
static MsNetStatus socket_write(MsConn *row, const uint8_t *data, size_t length, int64_t deadline_ns) {
    size_t sent = 0;
    while (sent < length) {
        size_t done = 0;
        const int result = ms_sys_net_write(row->fd, data + sent, length - sent, &done);
        if (result == MS_SYS_OK) {
            sent += done;
        } else if (result == MS_SYS_ERROR) {
            return fail(row, MS_NET_RESET, ms_sys_net_error());
        } else {
            const MsNetStatus waited = wait_for(row, MS_WAIT_WRITE, deadline_ns);
            if (waited != MS_NET_OK) {
                return waited;
            }
        }
    }
    return MS_NET_OK;
}

/* ---- TLS pump ---- */

/* Sends the ciphertext the session has queued. An interruption tears the stream, so the row is marked broken. */
static MsNetStatus pump_out(MsConn *row, MsTls *tls, int64_t deadline_ns) {
    uint8_t chunk[PUMP_BYTES];
    for (;;) {
        const long produced = ms_tls_outgoing(tls, chunk, sizeof chunk);
        if (produced <= 0) {
            return MS_NET_OK;
        }
        const MsNetStatus sent = socket_write(row, chunk, (size_t)produced, deadline_ns);
        if (sent != MS_NET_OK) {
            mark_broken(row);
            return sent;
        }
    }
}

/* Feeds the session one socket read of ciphertext; `*ended` is set at the end of the stream. */
static MsNetStatus pump_in(MsConn *row, MsTls *tls, int64_t deadline_ns, bool *ended) {
    uint8_t chunk[PUMP_BYTES];
    size_t count = 0;
    const MsNetStatus read = socket_read(row, chunk, sizeof chunk, deadline_ns, &count);
    if (read != MS_NET_OK) {
        return read;
    }
    *ended = count == 0;
    if (count > 0 && ms_tls_incoming(tls, chunk, count) < 0) {
        return fail(row, MS_NET_FAILED, 0);
    }
    return MS_NET_OK;
}

enum { GONE_POLL_NS = 20000000 };

MsNetStatus ms_conn_wait_gone(MsConnTable *table, MsConnId id, const uint8_t *handed_on) {
    for (;;) {
        MsConn *row = usable(table, id);
        if (row == NULL) {
            return MS_NET_CLOSED;
        }
        const MsNetStatus waited = wait_for(row, MS_WAIT_READ, -1);
        if (waited != MS_NET_OK) {
            return waited;
        }
        uint8_t probe;
        size_t seen = 0;
        const int result = ms_sys_net_peek(row->fd, &probe, 1, &seen);
        if (result == MS_SYS_EOF) {
            return MS_NET_CLOSED;
        }
        if (result == MS_SYS_ERROR) {
            return MS_NET_RESET;
        }
        if (result == MS_SYS_OK) {
            /* Queued bytes hide a FIN behind them; once another owner took the reads (an upgrade) the system is asked
             * whether the peer ended its side. */
            if (handed_on != NULL && __atomic_load_n(handed_on, __ATOMIC_ACQUIRE) != 0 && ms_sys_net_peer_ended(row->fd) != 0) {
                return MS_NET_CLOSED;
            }
            if ((msrt_task_sleep(GONE_POLL_NS) & MS_WAIT_CANCELLED) != 0) {
                return MS_NET_CANCELLED;
            }
        }
    }
}

MsNetStatus ms_conn_handshake(MsConnTable *table, MsConnId id, int64_t deadline_ns) {
    MsConn *row = usable(table, id);
    MsTls *tls = row == NULL ? NULL : tls_of(row);
    if (tls == NULL) {
        return MS_NET_CLOSED;
    }
    for (;;) {
        const int step = ms_tls_handshake(tls);
        const MsNetStatus sent = pump_out(row, tls, deadline_ns);
        if (sent != MS_NET_OK) {
            return sent;
        }
        if (step == MS_TLS_DONE) {
            return MS_NET_OK;
        }
        if (step == MS_TLS_ERROR || step == MS_TLS_CLOSED) {
            return fail(row, MS_NET_FAILED, 0);
        }
        bool ended = false;
        const MsNetStatus received = pump_in(row, tls, deadline_ns, &ended);
        if (received != MS_NET_OK) {
            return received;
        }
        if (ended) {
            return fail(row, MS_NET_RESET, 0);
        }
    }
}

/* ---- reads and writes ---- */

static MsNetStatus tls_read(MsConn *row, MsTls *tls, uint8_t *buffer, size_t capacity, int64_t deadline_ns,
                            size_t *count) {
    for (;;) {
        const long plain = ms_tls_read(tls, buffer, capacity);
        if (plain > 0) {
            *count = (size_t)plain;
            return MS_NET_OK;
        }
        if (plain == MS_TLS_CLOSED) {
            *count = 0;
            return MS_NET_OK;
        }
        if (plain == MS_TLS_ERROR) {
            return fail(row, MS_NET_FAILED, 0);
        }
        const MsNetStatus sent = pump_out(row, tls, deadline_ns);
        if (sent != MS_NET_OK) {
            return sent;
        }
        bool ended = false;
        const MsNetStatus received = pump_in(row, tls, deadline_ns, &ended);
        if (received != MS_NET_OK) {
            return received;
        }
        if (ended) {
            *count = 0; /* the peer closed without close_notify: the same end as a plain connection */
            return MS_NET_OK;
        }
    }
}

MsNetStatus ms_conn_read(MsConnTable *table, MsConnId id, uint8_t *buffer, size_t capacity, int64_t deadline_ns,
                         size_t *count) {
    MsConn *row = usable(table, id);
    if (row == NULL) {
        return MS_NET_CLOSED;
    }
    if (capacity == 0) {
        *count = 0;
        return MS_NET_OK;
    }
    MsConnExt *ext = ext_of(row);
    if (ext != NULL && ext->unread_length > 0) {
        const size_t taken = ext->unread_length < capacity ? ext->unread_length : capacity;
        memcpy(buffer, ext->unread, taken);
        ext->unread_length -= taken;
        memmove(ext->unread, ext->unread + taken, ext->unread_length);
        *count = taken;
        return MS_NET_OK;
    }
    MsTls *tls = tls_of(row);
    return tls == NULL ? socket_read(row, buffer, capacity, deadline_ns, count)
                       : tls_read(row, tls, buffer, capacity, deadline_ns, count);
}

void ms_conn_set_refusal(MsConnTable *table, MsConnId id, uint16_t status) {
    MsConn *row = usable(table, id);
    MsConnExt *ext = row == NULL ? NULL : ext_ensure(row);
    if (ext != NULL) {
        ext->refusal = status;
    }
}

uint16_t ms_conn_refusal(MsConnTable *table, MsConnId id) {
    MsConn *row = usable(table, id);
    const MsConnExt *ext = row == NULL ? NULL : row->ext;
    return ext == NULL ? 0 : ext->refusal;
}

MsNetStatus ms_conn_unread(MsConnTable *table, MsConnId id, const uint8_t *data, size_t length) {
    MsConn *row = usable(table, id);
    if (row == NULL) {
        return MS_NET_CLOSED;
    }
    if (length == 0) {
        return MS_NET_OK;
    }
    MsConnExt *ext = ext_ensure(row);
    uint8_t *grown = ext == NULL ? NULL : malloc(length + ext->unread_length);
    if (grown == NULL) {
        return MS_NET_FAILED;
    }
    memcpy(grown, data, length);
    if (ext->unread_length > 0) {
        memcpy(grown + length, ext->unread, ext->unread_length);
    }
    free(ext->unread);
    ext->unread = grown;
    ext->unread_length += length;
    return MS_NET_OK;
}

static MsNetStatus tls_write(MsConn *row, MsTls *tls, const uint8_t *data, size_t length, int64_t deadline_ns) {
    size_t queued = 0;
    while (queued < length) {
        const long taken = ms_tls_write(tls, data + queued, length - queued);
        if (taken > 0) {
            queued += (size_t)taken;
        } else if (taken != MS_TLS_WANT_IO) {
            return fail(row, MS_NET_FAILED, 0);
        }
        const MsNetStatus sent = pump_out(row, tls, deadline_ns);
        if (sent != MS_NET_OK) {
            return sent;
        }
        if (taken == MS_TLS_WANT_IO) {
            bool ended = false;
            const MsNetStatus received = pump_in(row, tls, deadline_ns, &ended);
            if (received != MS_NET_OK) {
                return received;
            }
            if (ended) {
                return fail(row, MS_NET_RESET, 0);
            }
        }
    }
    return MS_NET_OK;
}

MsNetStatus ms_conn_write(MsConnTable *table, MsConnId id, const uint8_t *data, size_t length, int64_t deadline_ns) {
    MsConn *row = usable(table, id);
    if (row == NULL) {
        return MS_NET_CLOSED;
    }
    MsTls *tls = tls_of(row);
    const MsNetStatus status = tls == NULL ? socket_write(row, data, length, deadline_ns)
                                           : tls_write(row, tls, data, length, deadline_ns);
    if (status != MS_NET_OK && tls == NULL && status != MS_NET_RESET) {
        mark_broken(row); /* some of `data` may have gone out: a retry would repeat or tear it */
    }
    return status;
}

MsNetStatus ms_conn_shutdown_write(MsConnTable *table, MsConnId id, int64_t deadline_ns) {
    MsConn *row = usable(table, id);
    if (row == NULL) {
        return MS_NET_CLOSED;
    }
    MsTls *tls = tls_of(row);
    if (tls != NULL) {
        (void)ms_tls_shutdown(tls);
        const MsNetStatus sent = pump_out(row, tls, deadline_ns);
        if (sent != MS_NET_OK) {
            return sent;
        }
    }
    if (ms_sys_net_shutdown(row->fd, 1) != MS_SYS_OK) {
        return fail(row, MS_NET_FAILED, ms_sys_net_error());
    }
    return MS_NET_OK;
}

/* ---- closing ---- */

static void ext_release(MsConnExt *ext) {
    if (ext == NULL) {
        return;
    }
    if (ext->app != NULL && ext->app_free != NULL) {
        ext->app_free(ext->app);
    }
    if (ext->tls != NULL) {
        ms_tls_free(ext->tls);
    }
    free(ext->unread);
    free(ext);
}

enum { DRAIN_ROUNDS = 16 };

MsNetStatus ms_conn_close_io(MsConnTable *table, MsConnId id) {
    MsConn *row = ms_conn_get(table, id);
    if (row == NULL) {
        return MS_NET_CLOSED;
    }
    MsTls *tls = tls_of(row);
    if (tls != NULL && !is_broken(row)) {
        /* close_notify is best effort: one try, no waiting */
        (void)ms_tls_shutdown(tls);
        uint8_t chunk[PUMP_BYTES];
        const long produced = ms_tls_outgoing(tls, chunk, sizeof chunk);
        size_t done = 0;
        if (produced > 0) {
            (void)ms_sys_net_write(row->fd, chunk, (size_t)produced, &done);
        }
    }
    /* Closing a socket that still holds unread bytes resets the connection and the peer loses what it was sent, so end
     * our side first and take what has already arrived. */
    if (ms_sys_net_shutdown(row->fd, 1) == MS_SYS_OK) {
        uint8_t unread[PUMP_BYTES];
        size_t got = 1;
        for (int rounds = 0; rounds < DRAIN_ROUNDS && got > 0 && ms_sys_net_read(row->fd, unread, sizeof unread, &got) == MS_SYS_OK; rounds++) {
        }
    }
    ext_release(row->ext);
    row->ext = NULL;
    MS_PROBE("conn close fd=%d", row->fd);
    msrt_task_forget_fd(row->fd); /* a task still parked on the descriptor would otherwise leave libuv watching a closed one */
    ms_sys_net_close(row->fd);
    MS_PROBE("conn closed");
    return ms_conn_close(table, id) == 0 ? MS_NET_OK : MS_NET_CLOSED;
}
