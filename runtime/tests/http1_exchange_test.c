#define _POSIX_C_SOURCE 200809L
/* Unit tests for runtime/net/http1_exchange.c over loopback against a canned server: bodies framed by length, chunks and
   the end of the stream, HEAD, an interim 1xx head, the request as written, a truncated body, and refused fields. The
   task waits are test doubles (there is no scheduler). */
#include <poll.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#include "../io/reactor.h"
#include "../net/dial.h"
#include "../net/http1_exchange.h"
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


#define S(literal) (const uint8_t *)(literal), sizeof(literal) - 1

/* Serves `connections` connections: reads a request head, then answers by its target. */
typedef struct Server { MsSock listener; int connections; } Server;

/* Answers one request; false when the reply ends the connection. */
static bool answer(MsConnTable *table, MsConnId id, const uint8_t *request, size_t length) {
    const char *text = (const char *)request;
    if (strstr(text, "HEAD ") == text) {
        (void)ms_conn_write(table, id, S("HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\n"), -1);
    } else if (strstr(text, " /len ") != NULL) {
        (void)ms_conn_write(table, id, S("HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello"), -1);
    } else if (strstr(text, " /chunked ") != NULL) {
        (void)ms_conn_write(table, id, S("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nhel\r\n2\r\nlo\r\n0\r\n\r\n"), -1);
    } else if (strstr(text, " /eof ") != NULL) {
        (void)ms_conn_write(table, id, S("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\nuntil close"), -1);
    } else if (strstr(text, " /interim ") != NULL) {
        (void)ms_conn_write(table, id, S("HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 201 Created\r\nContent-Length: 2\r\n\r\nok"), -1);
    } else if (strstr(text, " /short ") != NULL) {
        (void)ms_conn_write(table, id, S("HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nabc"), -1);
    } else {
        /* /echo: the request head comes back as the body */
        char head[128];
        const int n = snprintf(head, sizeof head, "HTTP/1.1 200 OK\r\nContent-Length: %zu\r\n\r\n", length);
        (void)ms_conn_write(table, id, (const uint8_t *)head, (size_t)n, -1);
        (void)ms_conn_write(table, id, request, length, -1);
    }
    return strstr(text, " /eof ") == NULL && strstr(text, " /short ") == NULL;
}

static void *serve(void *argument) {
    Server *server = argument;
    MsConnTable *table = ms_conn_table_new(2);
    for (int served = 0; served < server->connections; served++) {
        MsSock socket = MS_SOCK_INVALID;
        for (;;) {
            if (ms_sys_net_accept(server->listener, &socket, NULL) == MS_SYS_OK) break;
            struct pollfd p = {.fd = (int)server->listener, .events = POLLIN};
            poll(&p, 1, 100);
        }
        const MsConnId id = ms_conn_open(table, (int)socket, MS_CONN_HTTP1);
        char request[2048];
        bool keep = true;
        while (keep) {
            size_t length = 0;
            while (length < sizeof request - 1) {
                size_t count = 0;
                if (ms_conn_read(table, id, (uint8_t *)request + length, sizeof request - 1 - length, -1, &count) != MS_NET_OK || count == 0) {
                    keep = false;
                    break;
                }
                length += count;
                request[length] = 0;
                if (strstr(request, "\r\n\r\n") != NULL) break;
            }
            if (keep) {
                request[length] = 0;
                keep = answer(table, id, (const uint8_t *)request, length);
            }
        }
        (void)ms_conn_close_io(table, id);
    }
    ms_conn_table_free(table);
    return NULL;
}

static MsBytes text(const char *s) { return ms_bytes_of((const uint8_t *)s, strlen(s)); }

/* One exchange for `method` and `target`; reads the body to its end into `out` (NUL-terminated). */
static MsNetStatus fetch_row(MsConnTable *table, MsConnId id, const char *method, const char *target, const char *body_out_text,
                             const MsH1Field *fields, uint32_t nfields, MsBytes head, MsHttpResponse *response, char *out, size_t cap,
                             int *body_status) {
    const MsHttpRequest request = {.method = text(method), .authority = text("example.test"), .target = text(target), .head = head,
                                   .fields = fields, .nfields = nfields, .body = text(body_out_text)};
    MsHttpBody *body = NULL;
    const MsNetStatus status = ms_http1_exchange(table, id, &request, -1, response, &body);
    if (status != MS_NET_OK) {
        return status;
    }
    size_t used = 0;
    *body_status = 0;
    for (;;) {
        size_t n = 0;
        const int r = body->read(body, ms_bytes_mut((uint8_t *)out + used, cap - 1 - used), -1, &n);
        if (r != 0) { *body_status = r; break; }
        if (n == 0) break;
        used += n;
    }
    out[used] = 0;
    body->close(body);
    return MS_NET_OK;
}

/* The same on a row of its own, closed afterwards. */
static MsNetStatus fetch(MsConnTable *table, const MsAddr *address, const char *method, const char *target, const char *body_out_text,
                         const MsH1Field *fields, uint32_t nfields, MsBytes head, MsHttpResponse *response, char *out, size_t cap,
                         int *body_status) {
    MsConnId id = 0;
    int code = 0;
    if (ms_net_connect(table, address, MS_CONN_HTTP1, NULL, NULL, -1, &id, &code) != MS_NET_OK) return MS_NET_FAILED;
    const MsNetStatus status = fetch_row(table, id, method, target, body_out_text, fields, nfields, head, response, out, cap, body_status);
    (void)ms_conn_close_io(table, id);
    return status;
}

int main(void) {
    MsIoReactor *reactor;
    CHECK(ms_io_open(1, &reactor));
    MsConnTable *table = ms_conn_table_new(4);
    Server server = {.connections = 9};
    MsAddr loopback = {4, {127, 0, 0, 1}, 0, 0}, bound;
    CHECK(ms_sys_net_tcp_listen(&loopback, 4, &server.listener) == MS_SYS_OK);
    CHECK(ms_sys_net_local_addr(server.listener, &bound) == MS_SYS_OK);
    pthread_t thread;
    CHECK(pthread_create(&thread, NULL, serve, &server) == 0);

    MsHttpResponse response;
    char out[2048];
    int body_status = 0;
    MsBytes none = {0};

    CHECK(fetch(table, &bound, "GET", "/len", "", NULL, 0, none, &response, out, sizeof out, &body_status) == MS_NET_OK);
    CHECK(response.status == 200 && body_status == 0 && strcmp(out, "hello") == 0);

    CHECK(fetch(table, &bound, "GET", "/chunked", "", NULL, 0, none, &response, out, sizeof out, &body_status) == MS_NET_OK);
    CHECK(response.status == 200 && body_status == 0 && strcmp(out, "hello") == 0);

    CHECK(fetch(table, &bound, "GET", "/eof", "", NULL, 0, none, &response, out, sizeof out, &body_status) == MS_NET_OK);
    CHECK(body_status == 0 && strcmp(out, "until close") == 0);

    CHECK(fetch(table, &bound, "HEAD", "/len", "", NULL, 0, none, &response, out, sizeof out, &body_status) == MS_NET_OK);
    CHECK(response.status == 200 && body_status == 0 && out[0] == 0);

    CHECK(fetch(table, &bound, "GET", "/interim", "", NULL, 0, none, &response, out, sizeof out, &body_status) == MS_NET_OK);
    CHECK(response.status == 201 && body_status == 0 && strcmp(out, "ok") == 0);

    CHECK(fetch(table, &bound, "GET", "/short", "", NULL, 0, none, &response, out, sizeof out, &body_status) == MS_NET_OK);
    CHECK(strcmp(out, "abc") == 0 && body_status != 0); /* the stream ended before 10 bytes: not a clean end */

    /* the request as written: Host and Content-Length first, then the caller's fields, then the body */
    static const char names[] = "X-One1";
    const MsH1Field one[] = {{{0, 5}, {5, 1}}};
    CHECK(fetch(table, &bound, "POST", "/echo", "abc", one, 1, text(names), &response, out, sizeof out, &body_status) == MS_NET_OK);
    CHECK(strstr(out, "POST /echo HTTP/1.1\r\nHost: example.test\r\nContent-Length: 3\r\nX-One: 1\r\n\r\n") == out);

    /* a body read to its end on a keep-alive response leaves the row for the next request; anything else closes it */
    MsConnId kept = 0;
    int kept_code = 0;
    CHECK(ms_net_connect(table, &bound, MS_CONN_HTTP1, NULL, NULL, -1, &kept, &kept_code) == MS_NET_OK);
    CHECK(fetch_row(table, kept, "GET", "/len", "", NULL, 0, none, &response, out, sizeof out, &body_status) == MS_NET_OK);
    CHECK(strcmp(out, "hello") == 0 && ms_conn_get(table, kept) != NULL);
    CHECK(fetch_row(table, kept, "GET", "/chunked", "", NULL, 0, none, &response, out, sizeof out, &body_status) == MS_NET_OK);
    CHECK(strcmp(out, "hello") == 0 && ms_conn_get(table, kept) != NULL);
    CHECK(fetch_row(table, kept, "HEAD", "/len", "", NULL, 0, none, &response, out, sizeof out, &body_status) == MS_NET_OK);
    CHECK(out[0] == 0 && ms_conn_get(table, kept) != NULL); /* a HEAD reply has no body and keeps the row */
    CHECK(fetch_row(table, kept, "GET", "/eof", "", NULL, 0, none, &response, out, sizeof out, &body_status) == MS_NET_OK);
    CHECK(strcmp(out, "until close") == 0 && ms_conn_get(table, kept) == NULL); /* the reply ended the connection */

    /* a field the exchange writes itself is refused, and the row stays open for the caller */
    static const char host[] = "Hostx";
    const MsH1Field own[] = {{{0, 4}, {4, 1}}};
    MsConnId id = 0;
    int code = 0;
    CHECK(ms_net_connect(table, &bound, MS_CONN_HTTP1, NULL, NULL, -1, &id, &code) == MS_NET_OK);
    const MsHttpRequest bad = {.method = text("GET"), .authority = text("example.test"), .target = text("/echo"), .head = text(host), .fields = own, .nfields = 1};
    MsHttpBody *body = NULL;
    CHECK(ms_http1_exchange(table, id, &bad, -1, &response, &body) == MS_NET_FAILED && body == NULL);
    CHECK(ms_conn_live(table) == 1);
    CHECK(ms_conn_close_io(table, id) == MS_NET_OK);
    pthread_join(thread, NULL);
    ms_sys_net_close(server.listener);
    CHECK(ms_conn_live(table) == 0);

    ms_conn_table_free(table);
    ms_io_close(1);
    puts(failed ? "http1_exchange_test: FAILED" : "http1_exchange_test: ok");
    return failed;
}
