#define _POSIX_C_SOURCE 200809L
/* Unit tests for runtime/net/http2_exchange.c over loopback against a server built on h2conn (prior-knowledge h2 over a
   plain row): a small response, a 200 KB response that needs window updates, an upload the server measures, response
   fields, a reset stream, and refused request fields. The task waits are test doubles (there is no scheduler). */
#include <poll.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../io/reactor.h"
#include "../net/dial.h"
#include "../net/h2conn.h"
#include "../net/http2_exchange.h"
#include "ms_rt/sys.h"
#include "ms_rt/sys_net.h"
#include "ms_sched.h"

static int failed;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failed = 1; } } while (0)

uint32_t msrt_task_wait_fd(int32_t fd, uint32_t events, int64_t timeout_ns) {
    struct pollfd p = {.fd = fd, .events = (short)((events & MS_WAIT_READ ? POLLIN : 0) | (events & MS_WAIT_WRITE ? POLLOUT : 0))};
    const int ms = timeout_ns < 0 ? -1 : (int)(timeout_ns / 1000000 + 1);
    const int r = poll(&p, 1, ms);
    if (r == 0) return MS_WAIT_TIMEOUT;
    return (p.revents & POLLIN ? MS_WAIT_READ : 0) | (p.revents & POLLOUT ? MS_WAIT_WRITE : 0) | (p.revents & (POLLHUP | POLLERR) ? MS_WAIT_HUP : 0);
}

/* Tokens: one at a time, parked by running the reactor until its completion arrives. */
static uint64_t next_token = 1000;
static uint64_t pending_token;

uint64_t msrt_token_new(uint32_t flags) { (void)flags; pending_token = ++next_token; return pending_token; }
void msrt_token_free(uint64_t token) { (void)token; pending_token = 0; }
void msrt_token_post_remote(uint64_t token, uint64_t value) { (void)token; (void)value; }
uint32_t msrt_token_park(uint64_t token, int64_t timeout_ns, uint64_t *value) {
    const int64_t end = timeout_ns < 0 ? -1 : ms_sys_monotonic_ns() + timeout_ns;
    for (;;) {
        MsIoEvent event;
        while (ms_io_completion(&event)) {
            if (event.id == token) { *value = (uint64_t)(int64_t)event.result; return 0; }
        }
        int64_t wait = 50000000;
        if (end >= 0) {
            const int64_t left = end - ms_sys_monotonic_ns();
            if (left <= 0) return MS_WAIT_TIMEOUT;
            if (left < wait) wait = left;
        }
        MsIoReady ready[4];
        size_t count;
        if (!ms_io_wait(wait, ready, 4, &count)) return MS_WAIT_CANCELLED;
    }
}



enum { BIG = 200 * 1024 };

typedef struct Server { MsSock listener; int connections; } Server;

typedef struct Job { int32_t stream; const uint8_t *data; size_t length, sent; } Job;

static bool path_is(const MsH2Head *head, const char *path) {
    return head->path.len == strlen(path) && memcmp(head->path.ptr, path, head->path.len) == 0;
}

/* Answers a request whose body has fully arrived. */
static void answer(MsH2Conn *h2, int32_t stream, Job *job, uint8_t *big, uint8_t *upload, size_t uploaded) {
    const MsH2Head *head = ms_h2conn_head(h2, stream);
    static const MsH2Nv ok[] = {{":status", 7, "200", 3}, {"x-seen", 6, "yes", 3}};
    if (path_is(head, "/small")) {
        (void)ms_h2conn_respond(h2, stream, ok, 2, 1);
        *job = (Job){stream, (const uint8_t *)"hello", 5, 0};
    } else if (path_is(head, "/big")) {
        (void)ms_h2conn_respond(h2, stream, ok, 2, 1);
        *job = (Job){stream, big, BIG, 0};
    } else if (path_is(head, "/upload")) {
        char text[32];
        const int n = snprintf(text, sizeof text, "%zu", uploaded);
        memcpy(upload, text, (size_t)n);
        (void)ms_h2conn_respond(h2, stream, ok, 2, 1);
        *job = (Job){stream, upload, (size_t)n, 0};
    } else if (path_is(head, "/reset")) {
        (void)ms_h2conn_reset(h2, stream, 8);
    } else {
        static const MsH2Nv missing[] = {{":status", 7, "404", 3}};
        (void)ms_h2conn_respond(h2, stream, missing, 1, 0);
    }
}

static void *serve(void *argument) {
    Server *server = argument;
    MsConnTable *table = ms_conn_table_new(2);
    uint8_t *big = malloc(BIG), upload[32];
    for (size_t i = 0; i < BIG; i++) big[i] = (uint8_t)(i * 7);
    for (int served = 0; served < server->connections; served++) {
        MsSock socket = MS_SOCK_INVALID;
        for (;;) {
            if (ms_sys_net_accept(server->listener, &socket, NULL) == MS_SYS_OK) break;
            struct pollfd p = {.fd = (int)server->listener, .events = POLLIN};
            poll(&p, 1, 100);
        }
        const MsConnId id = ms_conn_open(table, (int)socket, MS_CONN_H2);
        MsH2Conn *h2 = ms_h2conn_new(1, NULL);
        Job job = {0};
        size_t uploaded = 0;
        bool alive = true;
        while (alive) {
            if (job.stream != 0 && job.sent < job.length) {
                const long taken = ms_h2conn_send(h2, job.stream, job.data + job.sent, job.length - job.sent, 1);
                if (taken > 0) job.sent += (size_t)taken;
            }
            uint8_t out[16384];
            long n;
            while ((n = ms_h2conn_output(h2, out, sizeof out)) > 0) {
                if (ms_conn_write(table, id, out, (size_t)n, -1) != MS_NET_OK) alive = false;
            }
            if (job.stream != 0 && job.sent >= job.length && ms_h2conn_idle(h2)) break; /* the response is out and acknowledged */
            uint8_t in[16384];
            size_t count = 0;
            if (!alive || ms_conn_read(table, id, in, sizeof in, ms_sys_monotonic_ns() + 2000000000, &count) != MS_NET_OK || count == 0) break;
            if (ms_h2conn_input(h2, in, count) < 0) break;
            MsH2ConnEvent event;
            while (ms_h2conn_next(h2, &event)) {
                if (event.type != MS_H2C_HEAD && event.type != MS_H2C_READABLE) continue;
                uint8_t sink[4096];
                long got;
                while ((got = ms_h2conn_read(h2, event.stream, sink, sizeof sink)) > 0) uploaded += (size_t)got;
                if ((ms_h2conn_state(h2, event.stream) & MS_H2S_ENDED) != 0 && job.stream == 0) answer(h2, event.stream, &job, big, upload, uploaded);
            }
        }
        (void)ms_conn_close_io(table, id);
        ms_h2conn_free(h2);
    }
    free(big);
    ms_conn_table_free(table);
    return NULL;
}

static MsBytes text(const char *s) { return ms_bytes_of((const uint8_t *)s, strlen(s)); }

/* One exchange; reads the body into a heap buffer sized `cap`. */
static char seen_name[32], seen_value[32];

static MsNetStatus fetch(MsConnTable *table, const MsAddr *address, const char *method, const char *target, MsBytes body_in,
                         const MsH1Field *fields, uint32_t nfields, MsBytes head_bytes, MsHttpResponse *response, uint8_t *out,
                         size_t cap, size_t *length, int *body_status) {
    MsConnId id = 0;
    int code = 0;
    if (ms_net_connect(table, address, MS_CONN_H2, NULL, NULL, -1, &id, &code) != MS_NET_OK) return MS_NET_FAILED;
    const MsHttpRequest request = {.method = text(method), .authority = text("example.test"), .target = text(target), .head = head_bytes,
                                   .fields = fields, .nfields = nfields, .body = body_in};
    MsHttpBody *body = NULL;
    const MsNetStatus status = ms_http2_exchange(table, id, &request, 5000000000 + ms_sys_monotonic_ns(), response, &body);
    if (status != MS_NET_OK) {
        (void)ms_conn_close_io(table, id);
        return status;
    }
    seen_name[0] = seen_value[0] = 0;
    if (response->nfields > 0) { /* the head is valid until the body is closed */
        const MsH1Field *f = &response->fields[0];
        snprintf(seen_name, sizeof seen_name, "%.*s", (int)f->name.len, (const char *)response->head.ptr + f->name.off);
        snprintf(seen_value, sizeof seen_value, "%.*s", (int)f->value.len, (const char *)response->head.ptr + f->value.off);
    }
    size_t used = 0;
    *body_status = 0;
    for (;;) {
        size_t n = 0;
        const int r = body->read(body, ms_bytes_mut(out + used, cap - used), -1, &n);
        if (r != 0) { *body_status = r; break; }
        if (n == 0) break;
        used += n;
    }
    *length = used;
    body->close(body);
    return MS_NET_OK;
}

int main(void) {
    MsIoReactor *reactor;
    CHECK(ms_io_open(1, &reactor));
    MsConnTable *table = ms_conn_table_new(4);
    Server server = {.connections = 5};
    MsAddr loopback = {4, {127, 0, 0, 1}, 0, 0}, bound;
    CHECK(ms_sys_net_tcp_listen(&loopback, 4, &server.listener) == MS_SYS_OK);
    CHECK(ms_sys_net_local_addr(server.listener, &bound) == MS_SYS_OK);
    pthread_t thread;
    CHECK(pthread_create(&thread, NULL, serve, &server) == 0);

    MsHttpResponse response;
    uint8_t *out = malloc(BIG + 16);
    size_t length = 0;
    int body_status = 0;
    MsBytes none = {0};

    CHECK(fetch(table, &bound, "GET", "/small", none, NULL, 0, none, &response, out, BIG + 16, &length, &body_status) == MS_NET_OK);
    CHECK(response.status == 200 && body_status == 0 && length == 5 && memcmp(out, "hello", 5) == 0);
    CHECK(response.nfields == 1 && strcmp(seen_name, "x-seen") == 0 && strcmp(seen_value, "yes") == 0);

    CHECK(fetch(table, &bound, "GET", "/big", none, NULL, 0, none, &response, out, BIG + 16, &length, &body_status) == MS_NET_OK);
    CHECK(body_status == 0 && length == BIG);
    bool same = length == BIG;
    for (size_t i = 0; same && i < BIG; i++) same = out[i] == (uint8_t)(i * 7);
    CHECK(same);

    uint8_t *upload = malloc(150000);
    memset(upload, 'u', 150000);
    static const char names[] = "X-Mixed-Caseq";
    const MsH1Field mixed[] = {{{0, 12}, {12, 1}}};
    CHECK(fetch(table, &bound, "POST", "/upload", ms_bytes_of(upload, 150000), mixed, 1, text(names), &response, out, BIG + 16, &length, &body_status) == MS_NET_OK);
    CHECK(response.status == 200 && length == 6 && memcmp(out, "150000", 6) == 0);
    free(upload);

    CHECK(fetch(table, &bound, "GET", "/reset", none, NULL, 0, none, &response, out, BIG + 16, &length, &body_status) == MS_NET_FAILED);

    CHECK(fetch(table, &bound, "GET", "/missing", none, NULL, 0, none, &response, out, BIG + 16, &length, &body_status) == MS_NET_OK);
    CHECK(response.status == 404 && length == 0 && body_status == 0);

    /* fields HTTP/2 forbids, and the ones the exchange writes, are refused before anything is sent */
    static const char host[] = "Hostx";
    const MsH1Field own[] = {{{0, 4}, {4, 1}}};
    MsConnId id = 0;
    int code = 0;
    pthread_join(thread, NULL);
    ms_sys_net_close(server.listener);
    CHECK(ms_conn_live(table) == 0);
    bound = (MsAddr){4, {127, 0, 0, 1}, 0, 0};
    Server again = {.connections = 1};
    CHECK(ms_sys_net_tcp_listen(&loopback, 4, &again.listener) == MS_SYS_OK && ms_sys_net_local_addr(again.listener, &bound) == MS_SYS_OK);
    CHECK(pthread_create(&thread, NULL, serve, &again) == 0);
    CHECK(ms_net_connect(table, &bound, MS_CONN_H2, NULL, NULL, -1, &id, &code) == MS_NET_OK);
    const MsHttpRequest bad = {.method = text("GET"), .authority = text("example.test"), .target = text("/small"), .head = text(host), .fields = own, .nfields = 1};
    MsHttpBody *body = NULL;
    CHECK(ms_http2_exchange(table, id, &bad, -1, &response, &body) == MS_NET_FAILED && body == NULL);
    CHECK(ms_conn_close_io(table, id) == MS_NET_OK);
    pthread_join(thread, NULL); /* the server saw the connection close */
    ms_sys_net_close(again.listener);

    free(out);
    ms_conn_table_free(table);
    ms_io_close(1);
    puts(failed ? "http2_exchange_test: FAILED" : "http2_exchange_test: ok");
    return failed;
}
