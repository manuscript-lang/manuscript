#define _POSIX_C_SOURCE 200809L
/* Unit tests for runtime/net/exchange_h2.c over a socket pair: a client thread sends four requests in a row on one
   HTTP/2 connection (a POST with a large body, a HEAD, a response shorter than its declared length, a request the
   handler leaves unread) and the main thread serves them through the exchange calls, with the scheduler replaced by
   test doubles (a parked task runs one turn of the connection task, as the scheduler would). */
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#include "../net/exchange_h2.h"
#include "../std/abi.h"
#include "ms_rt/alloc.h"
#include "ms_rt/sys.h"
#include "ms_rt/obj.h"
#include "ms_rt/xchg.h"
#include "ms_sched.h"
#include "../net/status.h"

void ms_sched_cancel_return(void) {}

static int failed;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failed = 1; } } while (0)
#define S(x) x, sizeof x - 1

/* ---- scheduler doubles ---- */

static MsXchgH2Conn *current;
static int connection_over;
static uint64_t posted[16];
static uint64_t next_token = 100;

uint32_t msrt_task_wait_fd(int32_t fd, uint32_t events, int64_t timeout_ns) {
    struct pollfd p = {.fd = fd, .events = (short)((events & MS_WAIT_READ ? POLLIN : 0) | (events & MS_WAIT_WRITE ? POLLOUT : 0))};
    const int ms = timeout_ns < 0 ? -1 : (int)(timeout_ns / 1000000 + 1);
    if (poll(&p, 1, ms) == 0) return MS_WAIT_TIMEOUT;
    return (p.revents & POLLIN ? MS_WAIT_READ : 0) | (p.revents & POLLOUT ? MS_WAIT_WRITE : 0) | (p.revents & (POLLHUP | POLLERR) ? MS_WAIT_HUP : 0);
}
uint64_t msrt_token_new(uint32_t flags) { (void)flags; return ++next_token; }
void msrt_token_free(uint64_t token) { for (size_t i = 0; i < 16; i++) if (posted[i] == token) posted[i] = 0; }
void msrt_token_post_remote(uint64_t token, uint64_t value) {
    (void)value;
    for (size_t i = 0; i < 16; i++) if (posted[i] == token) return;
    for (size_t i = 0; i < 16; i++) if (posted[i] == 0) { posted[i] = token; return; }
}
static int take_post(uint64_t token) {
    for (size_t i = 0; i < 16; i++) if (posted[i] == token) { posted[i] = 0; return 1; }
    return 0;
}
uint32_t msrt_token_park(uint64_t token, int64_t timeout_ns, uint64_t *value) {
    (void)timeout_ns;
    *value = 0;
    while (!take_post(token)) {
        if (connection_over) return MS_WAIT_CANCELLED;
        if (ms_h2_serve_step(ms_xchg_h2_conn_serve(current)) != MS_NET_OK) {
            /* the connection is over: the connection task finishes (it frees the serve state) and wakes `next` */
            connection_over = 1;
            (void)ms_xchg_h2_conn_run(current);
        }
    }
    return 0;
}


/* ---- runtime and status doubles (headers.c and exchange_h2.c use these; the real ones need the whole runtime) ---- */

void *msrt_alloc(size_t size) { return malloc(size == 0 ? 1 : size); }
void *msrt_alloc_zeroed(size_t size) { return calloc(1, size == 0 ? 1 : size); }
void msrt_free(void *pointer) { free(pointer); }
void msrt_obj_drop(MsObj *object) { object->drop(object); }
const MsTypeDesc msrt_desc_bytes, msrt_desc_string;
void msrt_list_with_capacity(const MsTypeDesc *d, int64_t cap, MsVec *out) { (void)d; (void)cap; *out = (MsVec){0}; }
void msrt_list_push(MsVec *v, const MsTypeDesc *d, const void *elem) { (void)v; (void)d; (void)elem; }
void msrt_string_from_bytes(const uint8_t *ptr, size_t len, MsStr *out) { (void)ptr; (void)len; memset(out, 0, sizeof *out); }
void ms_net_write_text(MsStr *out, const char *text) { (void)text; if (out != NULL) memset(out, 0, sizeof *out); }
uint8_t ms_net_finish(MsNetStatus status, int code, MsStr *err) {
    (void)code; (void)err;
    switch (status) {
    case MS_NET_OK: return STATUS_OK;
    case MS_NET_CLOSED: return STATUS_CLOSED;
    case MS_NET_TIMEOUT: return STATUS_TIMED_OUT;
    default: return STATUS_FAILED;
    }
}
int64_t ms_net_deadline_of(uint8_t has_timeout, int64_t timeout) {
    return has_timeout == 0 || timeout < 0 ? -1 : ms_sys_monotonic_ns() + timeout;
}

/* ---- the client ---- */

enum { REQUESTS = 4, RESPONSE = 300000 };

typedef struct Result {
    int status, reset, ended, has_connection, has_length;
    size_t got;
    unsigned char *received;
} Result;

typedef struct Client {
    int fd;
    size_t upload;
    Result results[REQUESTS];
} Client;

static void client_write(Client *c, MsH2Conn *h2) {
    unsigned char buf[16384];
    long n;
    while ((n = ms_h2conn_output(h2, buf, sizeof buf)) > 0) {
        long off = 0;
        while (off < n) { ssize_t w = write(c->fd, buf + off, (size_t)(n - off)); if (w <= 0) return; off += w; }
    }
}

static int field_is(const MsH2Head *head, const char *name, const char *value) {
    for (size_t i = 0; i < head->nfields; i++) {
        if (head->fields[i].name.len == strlen(name) && !memcmp(head->fields[i].name.ptr, name, head->fields[i].name.len) &&
            (value == NULL || (head->fields[i].value.len == strlen(value) && !memcmp(head->fields[i].value.ptr, value, head->fields[i].value.len)))) return 1;
    }
    return 0;
}

static void *client_main(void *arg) {
    Client *c = arg;
    MsH2Limits limits = {100, 0, 65535, 65535};
    MsH2Conn *h2 = ms_h2conn_new(0, &limits);
    for (int r = 0; r < REQUESTS; r++) {
        const char *method = r == 0 ? "POST" : r == 1 ? "HEAD" : "GET";
        const char *path = r == 0 ? "/echo?a=1" : r == 1 ? "/head" : r == 2 ? "/short" : "/unread";
        MsH2Nv nv[] = {{S(":method"), method, strlen(method)}, {S(":scheme"), S("https")}, {":path", 5, path, strlen(path)},
                       {S(":authority"), S("a.test")}, {S("cookie"), S("a=1")}, {S("cookie"), S("b=2")}};
        const size_t upload = r == 0 ? c->upload : r == 3 ? 20000 : 0;
        int32_t id = ms_h2conn_open(h2, nv, 6, upload > 0);
        unsigned char *payload = calloc(1, upload + 1);
        for (size_t i = 0; i < upload; i++) payload[i] = (unsigned char)(i * 7);
        size_t sent = 0;
        int ended = upload == 0;
        unsigned char buf[16384];
        Result *res = &c->results[r];
        while (!res->ended && !res->reset) {
            if (!ended) {
                long took = ms_h2conn_send(h2, id, payload + sent, upload - sent, 1);
                if (took >= 0) sent += (size_t)took;
                if (sent == upload) ended = 1;
            }
            client_write(c, h2);
            struct pollfd p = {.fd = c->fd, .events = POLLIN};
            if (poll(&p, 1, 50) > 0) {
                ssize_t n = read(c->fd, buf, sizeof buf);
                if (n <= 0) goto out;
                CHECK(ms_h2conn_input(h2, buf, (size_t)n) == n);
            }
            for (;;) {
                long got = ms_h2conn_read(h2, id, buf, sizeof buf);
                if (got <= 0) break;
                res->received = realloc(res->received, res->got + (size_t)got);
                memcpy(res->received + res->got, buf, (size_t)got);
                res->got += (size_t)got;
            }
            const MsH2Head *head = ms_h2conn_head(h2, id);
            if (head) {
                res->status = (int)head->status;
                res->has_connection = field_is(head, "connection", NULL);
                res->has_length = field_is(head, "content-length", NULL);
            }
            const unsigned state = ms_h2conn_state(h2, id);
            if (state & MS_H2S_ENDED) res->ended = 1;
            MsH2ConnEvent e;
            while (ms_h2conn_next(h2, &e)) if (e.type == MS_H2C_RESET && e.stream == id) res->reset = 1;
            client_write(c, h2);
        }
        free(payload);
        ms_h2conn_release(h2, id, 0);
        client_write(c, h2);
    }
out:
    ms_h2conn_free(h2);
    shutdown(c->fd, SHUT_RDWR);
    return NULL;
}

/* ---- the server ---- */

static int served;
static size_t upload_seen;
static int upload_matches = 1;

static int bytes_is(MsBytes bytes, const char *text) { return bytes.len == strlen(text) && !memcmp(bytes.ptr, text, bytes.len); }

static MsHeaders *response_fields(void) {
    MsHeaders *headers = ms_headers_new();
    CHECK(ms_headers_add(headers, ms_bytes_of((const uint8_t *)"X-Test", 6), ms_bytes_of((const uint8_t *)"v", 1)));
    CHECK(ms_headers_add(headers, ms_bytes_of((const uint8_t *)"Connection", 10), ms_bytes_of((const uint8_t *)"close", 5)));
    return headers;
}

static void handle(MsXchgH2 *x) {
    MsObj *object = ms_exchange_from_h2(x); /* the natives of xchg.h work on this */
    CHECK(object != NULL);
    MsStr err;
    MsHeaders *headers = response_fields();
    uint8_t keep = 0;
    const int index = served++;
    if (index == 0) {
        CHECK(bytes_is(ms_xchg_h2_method(x), "POST") && bytes_is(ms_xchg_h2_target(x), "/echo?a=1") && bytes_is(ms_xchg_h2_protocol(x), "HTTP/2.0"));
        MsHeaders *fields = ms_xchg_h2_headers(x);
        int host = 0, cookie = 0;
        for (size_t i = 0; fields != NULL && i < ms_headers_count(fields); i++) {
            MsBytes name, value;
            ms_headers_field(fields, i, &name, &value);
            if (bytes_is(name, "Host") && bytes_is(value, "a.test")) host++;
            if (bytes_is(name, "Cookie") && bytes_is(value, "a=1; b=2")) cookie++;
        }
        CHECK(host == 1 && cookie == 1);
        ms_headers_object(fields)->drop(ms_headers_object(fields));
        CHECK(msstd_xchg_write(object, &(MsVec){(void *)(uintptr_t)"x", (size_t)(1), (size_t)(1)}, 0, 0, &err) == STATUS_INVALID_INPUT); /* no head yet */
        for (;;) {
            MsVec chunk = {0};
            const uint8_t status = msstd_xchg_read(object, 1, 4096, 0, 0, &chunk, &err);
            if (status == STATUS_NONE) break;
            CHECK(status == STATUS_OK);
            for (size_t i = 0; i < chunk.len; i++) if (((uint8_t *)chunk.ptr)[i] != (uint8_t)((upload_seen + i) * 7)) upload_matches = 0;
            upload_seen += chunk.len;
            msrt_free(chunk.ptr);
        }
        CHECK(msstd_xchg_send_head(object, 99, ms_headers_object(headers), 0, 0, 0, 0, &err) == STATUS_INVALID_INPUT);
        CHECK(msstd_xchg_send_head(object, 200, ms_headers_object(headers), 1, RESPONSE, 0, 0, &err) == STATUS_OK);
        CHECK(msstd_xchg_send_head(object, 200, ms_headers_object(headers), 1, RESPONSE, 0, 0, &err) == STATUS_INVALID_INPUT); /* once */
        uint8_t *body = malloc(RESPONSE);
        for (size_t i = 0; i < RESPONSE; i++) body[i] = (uint8_t)(i * 3);
        CHECK(msstd_xchg_write(object, &(MsVec){body, (size_t)(100000), (size_t)(100000)}, 0, 0, &err) == STATUS_OK);
        CHECK(msstd_xchg_write(object, &(MsVec){body + 100000, (size_t)(RESPONSE - 100000), (size_t)(RESPONSE - 100000)}, 0, 0, &err) == STATUS_OK);
        CHECK(msstd_xchg_write(object, &(MsVec){body, (size_t)(1), (size_t)(1)}, 0, 0, &err) == STATUS_OUT_OF_RANGE); /* past the declared length */
        free(body);
        CHECK(msstd_xchg_finish(object, 0, 0, &keep, &err) == STATUS_OK && keep == 1);
    } else if (index == 1) {
        CHECK(bytes_is(ms_xchg_h2_method(x), "HEAD"));
        CHECK(msstd_xchg_send_head(object, 200, ms_headers_object(headers), 1, 5, 0, 0, &err) == STATUS_OK);
        CHECK(msstd_xchg_write(object, &(MsVec){(void *)(uintptr_t)"hello", (size_t)(5), (size_t)(5)}, 0, 0, &err) == STATUS_OK); /* a HEAD response has no body */
        CHECK(msstd_xchg_finish(object, 0, 0, &keep, &err) == STATUS_OK && keep == 1);
    } else if (index == 2) {
        CHECK(msstd_xchg_send_head(object, 200, ms_headers_object(headers), 1, 10, 0, 0, &err) == STATUS_OK);
        CHECK(msstd_xchg_write(object, &(MsVec){(void *)(uintptr_t)"four", (size_t)(4), (size_t)(4)}, 0, 0, &err) == STATUS_OK);
        CHECK(msstd_xchg_finish(object, 0, 0, &keep, &err) == STATUS_INVALID_DATA && keep == 1); /* the stream is reset, not the connection */
    } else {
        CHECK(msstd_xchg_reset(object, 100, 0, 0, &err) == STATUS_LIMIT_EXCEEDED); /* 20000 bytes of body left, over the limit of 100 */
        CHECK(msstd_xchg_send_head(object, 204, ms_headers_object(headers), 0, 0, 0, 0, &err) == STATUS_OK);
        CHECK(msstd_xchg_finish(object, 0, 0, &keep, &err) == STATUS_OK && keep == 1);
    }
    ms_headers_object(headers)->drop(ms_headers_object(headers));
    msrt_obj_drop(object);
}

int main(void) {
    int fds[2];
    CHECK(socketpair(AF_UNIX, SOCK_STREAM, 0, fds) == 0);
    fcntl(fds[0], F_SETFL, fcntl(fds[0], F_GETFL) | O_NONBLOCK);
    Client client = {.fd = fds[1], .upload = 150000};
    pthread_t thread;
    pthread_create(&thread, NULL, client_main, &client);

    MsConnTable *table = ms_conn_table_new(4);
    MsConnId id = ms_conn_open(table, fds[0], MS_CONN_H2);
    MsH2Limits limits = {100, 0, 65535, 65535};
    current = ms_xchg_h2_conn_new(table, id, &limits, 5000000000LL);
    CHECK(current != NULL);
    MsNetStatus status = MS_NET_OK;
    while (status == MS_NET_OK) {
        MsXchgH2 *x = NULL;
        status = ms_xchg_h2_conn_next(current, -1, &x);
        if (status == MS_NET_OK) handle(x);
    }
    CHECK(status == MS_NET_CLOSED && served == REQUESTS && connection_over);
    ms_xchg_h2_conn_free(current);
    pthread_join(thread, NULL);

    CHECK(upload_seen == client.upload && upload_matches);
    Result *first = &client.results[0];
    CHECK(first->status == 200 && first->got == RESPONSE && first->has_length && !first->has_connection && first->ended);
    int body_ok = first->got == RESPONSE;
    for (size_t i = 0; i < first->got && body_ok; i++) body_ok = first->received[i] == (unsigned char)(i * 3);
    CHECK(body_ok);
    CHECK(client.results[1].status == 200 && client.results[1].got == 0 && client.results[1].ended && client.results[1].has_length);
    CHECK(client.results[2].reset == 1);
    CHECK(client.results[3].status == 204 && client.results[3].ended);
    CHECK(ms_conn_live(table) == 0);
    for (int r = 0; r < REQUESTS; r++) free(client.results[r].received);
    ms_conn_table_free(table);
    close(fds[1]);
    if (!failed) printf("exchange_h2 ok\n");
    return failed;
}
