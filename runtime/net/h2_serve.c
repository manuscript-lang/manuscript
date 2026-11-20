/* Serving HTTP/2 on a connection row (h2_serve.h). */
#include "h2_serve.h"

#include <stdlib.h>

#include "ms_rt/safe.h"
#include "ms_rt/sys.h"
#include "ms_sched.h"

enum { CHUNK_BYTES = 16384, TOKEN_ANY_THREAD = 1 };

struct MsH2Serve {
    MsConnTable *table;
    MsConnId id;
    MsH2Conn *h2;        /* owned */
    MsH2ServeHooks hooks;
    uint8_t closed;      /* the connection is over: handlers fail, nothing more is read or flushed */
    uint8_t flushing;    /* a task is writing output now */
    uint32_t handlers;   /* requests delivered and not yet released */
    uint64_t joiner;     /* token the connection task parks on while handlers finish; 0 when none */
};

/* ---- wake-ups ---- */

static void wake(uint64_t token) {
    if (token != 0) {
        msrt_token_post_remote(token, 0);
    }
}

static void wake_stream(void *context, int32_t stream, const uint64_t *user) {
    (void)context;
    (void)stream;
    wake(user[0]);
    wake(user[1]);
}

static void wake_all(MsH2Serve *serve) { ms_h2conn_for_each(serve->h2, wake_stream, NULL); }

/* Parks a handler on its stream's token until an event wakes it or the deadline passes. */
static MsNetStatus park_on(uint64_t *user, int64_t deadline_ns) {
    if (user == NULL) {
        return MS_NET_CLOSED;
    }
    if (*user == 0) {
        *user = msrt_token_new(TOKEN_ANY_THREAD);
        if (*user == 0) {
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
    const uint32_t result = msrt_token_park(*user, timeout_ns, &value);
    if ((result & MS_WAIT_CANCELLED) != 0) {
        return MS_NET_CANCELLED;
    }
    return (result & MS_WAIT_TIMEOUT) != 0 ? MS_NET_TIMEOUT : MS_NET_OK;
}

static MsNetStatus park(MsH2Serve *serve, int32_t stream, int64_t deadline_ns) {
    return park_on(ms_h2conn_user(serve->h2, stream), deadline_ns);
}

/* ---- the connection ---- */

/* Marks the connection over and wakes every handler so each sees it. */
static void shut(MsH2Serve *serve) {
    serve->closed = 1;
    wake_all(serve);
}

/* Writes the output the connection has queued, one flusher at a time. */
static void flush(MsH2Serve *serve) {
    if (serve->flushing != 0 || serve->closed != 0) {
        return;
    }
    uint8_t chunk[CHUNK_BYTES];
    serve->flushing = 1;
    for (;;) {
        const long produced = ms_h2conn_output(serve->h2, chunk, sizeof chunk);
        if (produced <= 0) {
            break;
        }
        if (ms_conn_write(serve->table, serve->id, chunk, (size_t)produced, -1) != MS_NET_OK) {
            shut(serve);
            break;
        }
    }
    serve->flushing = 0;
}

static void dispatch(MsH2Serve *serve) {
    MsH2ConnEvent event;
    while (ms_h2conn_next(serve->h2, &event) != 0) {
        if (event.type == MS_H2C_HEAD) {
            serve->handlers++;
            serve->hooks.on_request(serve->hooks.context, serve, event.stream);
        } else if (event.type != MS_H2C_GOAWAY) { /* readable, writable or reset: the stream's handler may go on */
            uint64_t *user = ms_h2conn_user(serve->h2, event.stream);
            uint64_t *watch = ms_h2conn_watch(serve->h2, event.stream);
            if (user != NULL) {
                wake(*user);
            }
            if (watch != NULL) {
                wake(*watch);
            }
        }
    }
}

/* The row's release hook: runs once when the row closes. */
static void serve_free(void *app) {
    MsH2Serve *serve = app;
    ms_h2conn_free(serve->h2);
    free(serve);
}

MsH2Serve *ms_h2_serve_new(MsConnTable *table, MsConnId id, MsH2Conn *h2, const MsH2ServeHooks *hooks) {
    MsH2Serve *serve = calloc(1, sizeof *serve);
    if (serve == NULL) {
        return NULL;
    }
    *serve = (MsH2Serve){.table = table, .id = id, .h2 = h2, .hooks = *hooks};
    if (ms_conn_set_app(table, id, serve, serve_free) != MS_NET_OK) {
        free(serve);
        return NULL;
    }
    return serve;
}

MsNetStatus ms_h2_serve_step(MsH2Serve *serve) {
    if (serve->closed != 0) {
        return MS_NET_CLOSED;
    }
    int64_t deadline_ns = -1;
    if (serve->hooks.idle_ns > 0 && ms_h2conn_idle(serve->h2) != 0) {
        deadline_ns = ms_sys_monotonic_ns() + serve->hooks.idle_ns;
    }
    uint8_t chunk[CHUNK_BYTES];
    size_t count = 0;
    const MsNetStatus read = ms_conn_read(serve->table, serve->id, chunk, sizeof chunk, deadline_ns, &count);
    if (read != MS_NET_OK) {
        shut(serve);
        return read;
    }
    if (count == 0) {
        shut(serve);
        return MS_NET_CLOSED;
    }
    const long used = ms_h2conn_input(serve->h2, chunk, count);
    dispatch(serve);
    flush(serve); /* answers, window updates and, after a protocol error, the GOAWAY */
    if (used < 0) {
        shut(serve);
        return MS_NET_FAILED;
    }
    if (ms_h2conn_alive(serve->h2) == 0) {
        shut(serve);
        return MS_NET_CLOSED;
    }
    return MS_NET_OK;
}

void ms_h2_serve_drain(MsH2Serve *serve) {
    if (ms_h2conn_goaway(serve->h2, 0) == 0) {
        flush(serve);
    }
}

MsNetStatus ms_h2_serve_run(MsH2Serve *serve) {
    MsNetStatus status = MS_NET_OK;
    while (status == MS_NET_OK) {
        status = ms_h2_serve_step(serve);
    }
    shut(serve);
    while (serve->handlers > 0) {
        if (serve->joiner == 0) {
            serve->joiner = msrt_token_new(TOKEN_ANY_THREAD);
        }
        uint64_t value = 0;
        if (serve->joiner == 0 || (msrt_token_park(serve->joiner, -1, &value) & MS_WAIT_CANCELLED) != 0) {
            break; /* cancelled or out of tokens: close under the handlers, whose calls then fail */
        }
    }
    if (serve->joiner != 0) {
        msrt_token_free(serve->joiner);
    }
    (void)ms_conn_close_io(serve->table, serve->id);
    return status;
}

/* ---- handler calls ---- */

MsNetStatus ms_h2_stream_read(MsH2Serve *serve, int32_t stream, uint8_t *buffer, size_t capacity, int64_t deadline_ns,
                              size_t *count) {
    for (;;) {
        const long got = ms_h2conn_read(serve->h2, stream, buffer, capacity);
        if (got < 0) {
            return MS_NET_CLOSED;
        }
        if (got > 0) {
            flush(serve); /* the window update */
            *count = (size_t)got;
            return MS_NET_OK;
        }
        const unsigned state = ms_h2conn_state(serve->h2, stream);
        if ((state & MS_H2S_ENDED) != 0) {
            *count = 0;
            return MS_NET_OK;
        }
        if ((state & MS_H2S_RESET) != 0) {
            return MS_NET_RESET;
        }
        if (serve->closed != 0) {
            return MS_NET_CLOSED;
        }
        const MsNetStatus waited = park(serve, stream, deadline_ns);
        if (waited != MS_NET_OK) {
            return waited;
        }
    }
}

const MsH2Head *ms_h2_stream_head(MsH2Serve *serve, int32_t stream) { return ms_h2conn_head(serve->h2, stream); }
const MsH2Head *ms_h2_stream_trailers(MsH2Serve *serve, int32_t stream) { return ms_h2conn_trailers(serve->h2, stream); }

/* The result of a call that queued frames: flush them, and report a connection that went away meanwhile. */
static MsNetStatus sent(MsH2Serve *serve, int result) {
    if (result != 0) {
        return MS_NET_CLOSED; /* an unknown or finished stream */
    }
    flush(serve);
    return serve->closed != 0 ? MS_NET_CLOSED : MS_NET_OK;
}

MsNetStatus ms_h2_stream_respond(MsH2Serve *serve, int32_t stream, const MsH2Nv *nv, size_t nnv, int has_body) {
    return sent(serve, ms_h2conn_respond(serve->h2, stream, nv, nnv, has_body));
}

MsNetStatus ms_h2_stream_write(MsH2Serve *serve, int32_t stream, const uint8_t *data, size_t length, int end,
                               int64_t deadline_ns) {
    size_t offset = 0;
    for (;;) {
        const long took = ms_h2conn_send(serve->h2, stream, data + offset, length - offset, end);
        if (took < 0) {
            return MS_NET_CLOSED;
        }
        offset += (size_t)took;
        flush(serve);
        if (offset == length) {
            return serve->closed != 0 ? MS_NET_CLOSED : MS_NET_OK;
        }
        if ((ms_h2conn_state(serve->h2, stream) & MS_H2S_RESET) != 0) {
            return MS_NET_RESET;
        }
        if (serve->closed != 0) {
            return MS_NET_CLOSED;
        }
        const MsNetStatus waited = park(serve, stream, deadline_ns);
        if (waited != MS_NET_OK) {
            return waited;
        }
    }
}

MsNetStatus ms_h2_stream_wait_gone(MsH2Serve *serve, int32_t stream) {
    for (;;) {
        if ((ms_h2conn_state(serve->h2, stream) & MS_H2S_RESET) != 0) {
            return MS_NET_RESET;
        }
        if (serve->closed != 0) {
            return MS_NET_CLOSED;
        }
        const MsNetStatus waited = park_on(ms_h2conn_watch(serve->h2, stream), -1);
        if (waited != MS_NET_OK) {
            return waited;
        }
    }
}

MsNetStatus ms_h2_stream_trailers_send(MsH2Serve *serve, int32_t stream, const MsH2Nv *nv, size_t nnv) {
    return sent(serve, ms_h2conn_trailers_send(serve->h2, stream, nv, nnv));
}

MsNetStatus ms_h2_stream_reset(MsH2Serve *serve, int32_t stream, uint32_t code) {
    return sent(serve, ms_h2conn_reset(serve->h2, stream, code));
}

void ms_h2_serve_release(MsH2Serve *serve, int32_t stream, uint32_t code) {
    uint64_t *user = ms_h2conn_user(serve->h2, stream);
    uint64_t *watch = ms_h2conn_watch(serve->h2, stream);
    if (user != NULL && *user != 0) {
        msrt_token_free(*user);
        *user = 0;
    }
    if (watch != NULL && *watch != 0) {
        msrt_token_free(*watch);
        *watch = 0;
    }
    ms_h2conn_release(serve->h2, stream, code);
    flush(serve);
    serve->handlers--;
    if (serve->closed != 0 && serve->handlers == 0) {
        wake(serve->joiner); /* last use of `serve`: the connection task may free it from here */
    }
}
