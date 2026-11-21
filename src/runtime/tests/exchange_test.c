#define _POSIX_C_SOURCE 200809L
/* Tests for src/runtime/net/exchange.c (the HTTP/1 server exchange) over loopback: a client thread sends raw requests and
 * reads the raw response, while the test drives the exchange natives like the server loop does. The task wait is a
 * test double that polls, since there is no scheduler. */
#include <poll.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../net/conn_object.h"
#include "../net/headers.h"
#include "../std/abi.h"
#include "ms_rt/obj.h"
#include "ms_rt/sys.h"
#include "ms_rt/sys_net.h"
#include "ms_rt/xchg.h"
#include "ms_sched.h"

static int failed;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failed = 1; } } while (0)

__attribute__((weak)) bool ms_sched_cancel_pending(void) { return false; }
__attribute__((weak)) int64_t ms_sched_defer_deadline(void) { return INT64_MAX; }
__attribute__((weak)) void ms_sched_cancel_return(void) {}

/* The HTTP/2 exchange the natives also dispatch to parks on tokens; HTTP/1 never does. */
uint64_t msrt_token_new(uint32_t flags) { (void)flags; return 1; }
uint32_t msrt_token_park(uint64_t token, int64_t timeout_ns, uint64_t *value) { (void)token; (void)timeout_ns; *value = 0; return MS_WAIT_CANCELLED; }
void msrt_token_free(uint64_t token) { (void)token; }
__attribute__((weak)) void msrt_token_post_remote(uint64_t token, uint64_t value) { (void)token; (void)value; }

uint32_t msrt_task_wait_fd(int32_t fd, uint32_t events, int64_t timeout_ns) {
    struct pollfd p = {.fd = fd, .events = (short)((events & MS_WAIT_READ ? POLLIN : 0) | (events & MS_WAIT_WRITE ? POLLOUT : 0))};
    const int ms = timeout_ns < 0 ? -1 : (int)(timeout_ns / 1000000 + 1);
    const int r = poll(&p, 1, ms);
    if (r == 0) return MS_WAIT_TIMEOUT;
    return (p.revents & POLLIN ? MS_WAIT_READ : 0) | (p.revents & POLLOUT ? MS_WAIT_WRITE : 0) | (p.revents & (POLLHUP | POLLERR) ? MS_WAIT_HUP : 0);
}

/* ---- the client: sends `request` (after an optional pause, then `second`), reads until the server closes ---- */

typedef struct Client {
    uint16_t port;
    const char *request;
    int hang_up; /* close after sending, without reading the answer */
    char response[8192];
    size_t length;
} Client;

static void wait_socket(MsSock socket, short events) {
    struct pollfd p = {.fd = (int)socket, .events = events};
    poll(&p, 1, 100);
}

static void *client_run(void *argument) {
    Client *client = argument;
    MsSock socket = MS_SOCK_INVALID;
    MsAddr target = {4, {127, 0, 0, 1}, client->port, 0};
    int r = ms_sys_net_tcp_connect(&target, &socket);
    while (r == MS_SYS_INPROGRESS) {
        wait_socket(socket, POLLOUT);
        r = ms_sys_net_connect_done(socket);
        if (r == MS_SYS_INPROGRESS) continue;
    }
    if (r != MS_SYS_OK) return NULL;
    size_t sent = 0;
    const size_t total = strlen(client->request);
    while (sent < total) {
        size_t wrote = 0;
        r = ms_sys_net_write(socket, client->request + sent, total - sent, &wrote);
        if (r == MS_SYS_AGAIN) { wait_socket(socket, POLLOUT); continue; }
        if (r != MS_SYS_OK) break;
        sent += wrote;
    }
    if (client->hang_up) {
        ms_sys_net_close(socket);
        return NULL;
    }
    for (;;) {
        size_t got = 0;
        r = ms_sys_net_read(socket, client->response + client->length, sizeof client->response - 1 - client->length, &got);
        if (r == MS_SYS_AGAIN) { wait_socket(socket, POLLIN); continue; }
        if (r != MS_SYS_OK || got == 0) break;
        client->length += got;
    }
    ms_sys_net_close(socket);
    return NULL;
}

typedef struct Case {
    MsSock listener;
    pthread_t thread;
    Client client;
    MsConnTable *table;
    MsObj *conn;
} Case;

/* Starts the client and accepts its connection as a ConnH. */
static void case_open_with(Case *c, const char *request, int hang_up) {
    MsAddr loopback = {4, {127, 0, 0, 1}, 0, 0}, bound;
    memset(c, 0, sizeof *c);
    CHECK(ms_sys_net_tcp_listen(&loopback, 4, &c->listener) == MS_SYS_OK);
    CHECK(ms_sys_net_local_addr(c->listener, &bound) == MS_SYS_OK);
    c->client.port = bound.port;
    c->client.request = request;
    c->client.hang_up = hang_up;
    CHECK(pthread_create(&c->thread, NULL, client_run, &c->client) == 0);
    MsSock socket = MS_SOCK_INVALID;
    for (;;) {
        if (ms_sys_net_accept(c->listener, &socket, NULL) == MS_SYS_OK) break;
        struct pollfd p = {.fd = (int)c->listener, .events = POLLIN};
        poll(&p, 1, 100);
    }
    c->table = ms_conn_table_new(2);
    c->conn = ms_netconn_new(c->table, ms_conn_open(c->table, (int)socket, MS_CONN_HTTP1));
}

static void case_open(Case *c, const char *request) { case_open_with(c, request, 0); }

/* Closes the server side, waits for the client and answers what it read. */
static const char *case_close(Case *c) {
    ms_netconn_close(c->conn);
    pthread_join(c->thread, NULL);
    ms_sys_net_close(c->listener);
    msrt_obj_drop(c->conn);
    c->client.response[c->client.length] = 0;
    return c->client.response;
}

static MsStr text_of(const char *s) { MsStr out; msrt_string_from_bytes((const uint8_t *)s, strlen(s), &out); return out; }
static bool str_is(const MsStr *s, const char *expected) { return msrt_str_len(s) == strlen(expected) && memcmp(msrt_str_data(s), expected, strlen(expected)) == 0; }
static MsVec bytes_of(const char *s) { MsVec v; msrt_write_bytes(&v, (const uint8_t *)s, strlen(s)); return v; }
static bool vec_is(const MsVec *v, const char *expected) { return v->len == strlen(expected) && memcmp(v->ptr, expected, v->len) == 0; }

static MsObj *headers_of(const char *name, const char *value) {
    MsHeaders *table = ms_headers_new();
    MsBytes n = ms_bytes_of((const uint8_t *)name, strlen(name)), v = ms_bytes_of((const uint8_t *)value, strlen(value));
    CHECK(ms_headers_add(table, n, v));
    return ms_headers_object(table);
}

/* Answers with a Content-Length body and ends the exchange; returns keep. */
static uint8_t answer(void *exchange, int status, const char *body) {
    MsStr err = text_of("");
    MsObj *fields = headers_of("Content-Type", "text/plain");
    CHECK(msstd_xchg_send_head(exchange, status, fields, 1, (int64_t)strlen(body), 0, 0, &err) == STATUS_OK);
    MsVec data = bytes_of(body);
    CHECK(msstd_xchg_write(exchange, &data, 0, 0, &err) == STATUS_OK);
    msrt_free(data.ptr);
    uint8_t keep = 99;
    CHECK(msstd_xchg_finish(exchange, 0, 0, &keep, &err) == STATUS_OK);
    msrt_obj_drop(fields);
    return keep;
}

static void test_keep_alive_and_pipelining(void) {
    Case c;
    case_open(&c, "GET /a?x=1 HTTP/1.1\r\nHost: t\r\nX-Two: 1\r\nx-two: 2\r\n\r\nGET /b HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n");
    void *exchange = NULL;
    MsStr err = text_of("");
    CHECK(msstd_xchg_next(c.conn, 0, 1, 5000000000, &exchange, &err) == STATUS_OK);
    MsStr method, target, protocol;
    msstd_xchg_method(exchange, &method);
    msstd_xchg_target(exchange, &target);
    msstd_xchg_protocol(exchange, &protocol);
    void *headers = msstd_xchg_headers(exchange);
    CHECK(str_is(&method, "GET") && str_is(&target, "/a?x=1") && str_is(&protocol, "HTTP/1.1"));
    CHECK(headers != NULL && ms_headers_count(ms_headers_of(headers)) == 3);
    msrt_obj_drop(headers);
    MsVec body = {0};
    CHECK(msstd_xchg_read(exchange, 0, 0, 1, 1000000000, &body, &err) == STATUS_NONE); /* GET: no body */
    CHECK(answer(exchange, 200, "hello") == 1);
    msrt_obj_drop(exchange);
    /* the second request was read ahead and comes back from the row */
    CHECK(msstd_xchg_next(c.conn, 0, 1, 5000000000, &exchange, &err) == STATUS_OK);
    msstd_xchg_target(exchange, &target);
    headers = msstd_xchg_headers(exchange);
    CHECK(str_is(&target, "/b"));
    msrt_obj_drop(headers);
    CHECK(answer(exchange, 404, "no") == 0); /* the request said Connection: close */
    msrt_obj_drop(exchange);
    const char *response = case_close(&c);
    CHECK(strstr(response, "HTTP/1.1 200 OK\r\n") == response);
    CHECK(strstr(response, "Content-Length: 5\r\n") && strstr(response, "\r\n\r\nhello"));
    CHECK(strstr(response, "HTTP/1.1 404 Not Found\r\n") && strstr(response, "Connection: close\r\n") && strstr(response, "\r\n\r\nno"));
}

static void test_bodies(void) {
    Case c;
    case_open(&c, "POST /p HTTP/1.1\r\nHost: t\r\nContent-Length: 11\r\n\r\nhello worldPOST /q HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n6\r\n world\r\n0\r\nX-T: 1\r\n\r\n");
    void *exchange = NULL;
    MsStr err = text_of("");
    CHECK(msstd_xchg_next(c.conn, 0, 1, 5000000000, &exchange, &err) == STATUS_OK);
    MsVec piece = {0};
    CHECK(msstd_xchg_read(exchange, 1, 5, 1, 1000000000, &piece, &err) == STATUS_OK && vec_is(&piece, "hello"));
    msrt_free(piece.ptr);
    CHECK(msstd_xchg_read(exchange, 0, 0, 1, 1000000000, &piece, &err) == STATUS_OK && vec_is(&piece, " world"));
    msrt_free(piece.ptr);
    CHECK(msstd_xchg_read(exchange, 0, 0, 1, 1000000000, &piece, &err) == STATUS_NONE);
    CHECK(answer(exchange, 200, "ok") == 1);
    msrt_obj_drop(exchange);

    CHECK(msstd_xchg_next(c.conn, 0, 1, 5000000000, &exchange, &err) == STATUS_OK);
    char all[64] = {0};
    size_t have = 0;
    for (;;) {
        const uint8_t status = msstd_xchg_read(exchange, 0, 0, 1, 1000000000, &piece, &err);
        if (status != STATUS_OK) { CHECK(status == STATUS_NONE); break; }
        memcpy(all + have, piece.ptr, piece.len);
        have += piece.len;
        msrt_free(piece.ptr);
    }
    CHECK(have == 11 && memcmp(all, "hello world", 11) == 0);
    /* a chunked response: two writes and the closing chunk */
    MsObj *fields = headers_of("X-A", "b");
    CHECK(msstd_xchg_send_head(exchange, 200, fields, 0, 0, 0, 0, &err) == STATUS_OK);
    MsVec one = bytes_of("abc"), two = bytes_of("de");
    CHECK(msstd_xchg_write(exchange, &one, 0, 0, &err) == STATUS_OK && msstd_xchg_write(exchange, &two, 0, 0, &err) == STATUS_OK);
    msrt_free(one.ptr); msrt_free(two.ptr);
    uint8_t keep = 9;
    CHECK(msstd_xchg_finish(exchange, 0, 0, &keep, &err) == STATUS_OK && keep == 1);
    msrt_obj_drop(fields);
    msrt_obj_drop(exchange);
    const char *response = case_close(&c);
    CHECK(strstr(response, "Transfer-Encoding: chunked\r\n") && strstr(response, "X-A: b\r\n"));
    CHECK(strstr(response, "\r\n\r\n3\r\nabc\r\n2\r\nde\r\n0\r\n\r\n"));
}

static void test_unread_body_and_reset(void) {
    Case c;
    case_open(&c, "POST /p HTTP/1.1\r\nHost: t\r\nContent-Length: 4\r\n\r\nabcdPOST /n HTTP/1.1\r\nHost: t\r\nContent-Length: 0\r\n\r\n");
    void *exchange = NULL;
    MsStr err = text_of("");
    CHECK(msstd_xchg_next(c.conn, 0, 1, 5000000000, &exchange, &err) == STATUS_OK);
    CHECK(answer(exchange, 200, "x") == 0); /* the body was not read: the connection cannot be reused */
    msrt_obj_drop(exchange);
    ms_netconn_close(c.conn);
    (void)case_close(&c);

    case_open(&c, "POST /p HTTP/1.1\r\nHost: t\r\nContent-Length: 4\r\n\r\nabcdPOST /n HTTP/1.1\r\nHost: t\r\nContent-Length: 0\r\n\r\n");
    CHECK(msstd_xchg_next(c.conn, 0, 1, 5000000000, &exchange, &err) == STATUS_OK);
    CHECK(msstd_xchg_reset(exchange, 2, 1, 1000000000, &err) == STATUS_LIMIT_EXCEEDED);
    msrt_obj_drop(exchange);
    ms_netconn_close(c.conn);
    (void)case_close(&c);

    case_open(&c, "POST /p HTTP/1.1\r\nHost: t\r\nContent-Length: 4\r\n\r\nabcdPOST /n HTTP/1.1\r\nHost: t\r\nContent-Length: 0\r\n\r\n");
    CHECK(msstd_xchg_next(c.conn, 0, 1, 5000000000, &exchange, &err) == STATUS_OK);
    CHECK(msstd_xchg_reset(exchange, 100, 1, 1000000000, &err) == STATUS_OK);
    CHECK(answer(exchange, 200, "x") == 1);
    msrt_obj_drop(exchange);
    CHECK(msstd_xchg_next(c.conn, 0, 1, 5000000000, &exchange, &err) == STATUS_OK);
    MsStr method, target, protocol;
    msstd_xchg_method(exchange, &method);
    msstd_xchg_target(exchange, &target);
    msstd_xchg_protocol(exchange, &protocol);
    void *headers = msstd_xchg_headers(exchange);
    CHECK(str_is(&target, "/n"));
    msrt_obj_drop(headers);
    msrt_obj_drop(exchange);
    (void)case_close(&c);
}

static void test_refusals(void) {
    Case c;
    void *exchange = NULL;
    MsStr err = text_of("");
    case_open(&c, "GET / HTTP/9.9\r\n\r\n");
    CHECK(msstd_xchg_next(c.conn, 0, 1, 5000000000, &exchange, &err) == STATUS_INVALID_DATA && msstd_xchg_reject_status(c.conn) == 400);
    CHECK(msstd_xchg_reject(c.conn, msstd_xchg_reject_status(c.conn), 0, 0, &err) == STATUS_OK);
    const char *response = case_close(&c);
    CHECK(strstr(response, "HTTP/1.1 400 Bad Request\r\n") == response && strstr(response, "Connection: close\r\n"));

    case_open(&c, "GET /aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa HTTP/1.1\r\nHost: t\r\n\r\n");
    CHECK(msstd_xchg_next(c.conn, 40, 1, 5000000000, &exchange, &err) == STATUS_INVALID_DATA && msstd_xchg_reject_status(c.conn) == 431);
    (void)case_close(&c);
}

static void test_take_conn(void) {
    Case c;
    case_open(&c, "GET /ws HTTP/1.1\r\nHost: t\r\nUpgrade: websocket\r\n\r\nFRAME-BYTES");
    void *exchange = NULL;
    MsStr err = text_of("");
    CHECK(msstd_xchg_next(c.conn, 0, 1, 5000000000, &exchange, &err) == STATUS_OK);
    MsObj *upgrade = headers_of("Connection", "Upgrade"); /* a 101 head keeps its Connection field */
    CHECK(msstd_xchg_send_head(exchange, 101, upgrade, 0, 0, 0, 0, &err) == STATUS_OK);
    msrt_obj_drop(upgrade);
    void *taken = NULL;
    CHECK(msstd_xchg_take_conn(exchange, &taken) == STATUS_OK && taken != NULL);
    CHECK(msstd_xchg_take_conn(exchange, &taken) == STATUS_INVALID_INPUT); /* spent */
    msrt_obj_drop(exchange);
    uint8_t got[32];
    size_t count = 0;
    const MsNetConn *core = ms_netconn_of(taken);
    CHECK(ms_conn_read(ms_netconn_table(core), ms_netconn_id(core), got, sizeof got, -1, &count) == MS_NET_OK);
    CHECK(count == 11 && memcmp(got, "FRAME-BYTES", 11) == 0);
    msrt_obj_drop(taken);
    const char *response = case_close(&c);
    CHECK(strstr(response, "HTTP/1.1 101 ") != NULL && strstr(response, "Connection: Upgrade\r\n") != NULL);
}

static void test_share(void) {
    Case c;
    case_open(&c, "GET /s HTTP/1.1\r\nHost: t\r\n\r\n");
    void *exchange = NULL;
    MsStr err = text_of("");
    CHECK(msstd_xchg_next(c.conn, 0, 1, 5000000000, &exchange, &err) == STATUS_OK);
    void *other = msstd_xchg_share(exchange);
    CHECK(other != NULL && other != exchange);
    msrt_obj_drop(exchange); /* the handler's handle goes; the loop's still finishes the response */
    CHECK(answer(other, 200, "s") == 1);
    msrt_obj_drop(other);
    CHECK(strstr(case_close(&c), "\r\n\r\ns") != NULL);
}

/* wait_gone returns once the client has hung up, and again at once for a connection that is already gone. */
static void test_wait_gone(void) {
    Case c;
    case_open_with(&c, "GET /g HTTP/1.1\r\nHost: t\r\n\r\n", 1);
    void *exchange = NULL;
    MsStr err = text_of("");
    CHECK(msstd_xchg_next(c.conn, 0, 1, 5000000000, &exchange, &err) == STATUS_OK);
    CHECK(msstd_xchg_wait_gone(exchange, &err) == STATUS_OK);
    CHECK(msstd_xchg_wait_gone(exchange, &err) == STATUS_OK);
    msrt_obj_drop(exchange);
    (void)case_close(&c);
}

static void test_head_request_and_informational(void) {
    Case c;
    case_open(&c, "HEAD /h HTTP/1.1\r\nHost: t\r\n\r\n");
    void *exchange = NULL;
    MsStr err = text_of("");
    CHECK(msstd_xchg_next(c.conn, 0, 1, 5000000000, &exchange, &err) == STATUS_OK);
    CHECK(msstd_xchg_send_head(exchange, 100, NULL, 0, 0, 0, 0, &err) == STATUS_OK); /* informational, then the final */
    CHECK(msstd_xchg_send_head(exchange, 200, NULL, 1, 5, 0, 0, &err) == STATUS_OK);
    CHECK(msstd_xchg_send_head(exchange, 200, NULL, 1, 5, 0, 0, &err) == STATUS_INVALID_INPUT); /* one final head */
    MsVec body = bytes_of("hello");
    CHECK(msstd_xchg_write(exchange, &body, 0, 0, &err) == STATUS_OK); /* a HEAD answer drops its body */
    msrt_free(body.ptr);
    uint8_t keep = 0;
    CHECK(msstd_xchg_finish(exchange, 0, 0, &keep, &err) == STATUS_OK && keep == 1);
    msrt_obj_drop(exchange);
    const char *response = case_close(&c);
    CHECK(strstr(response, "HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 200 OK\r\n") == response);
    CHECK(strstr(response, "Content-Length: 5\r\n") && strstr(response, "hello") == NULL);
}

int main(void) {
    test_keep_alive_and_pipelining();
    test_bodies();
    test_unread_body_and_reset();
    test_refusals();
    test_take_conn();
    test_share();
    test_wait_gone();
    test_head_request_and_informational();
    if (!failed) printf("exchange ok\n");
    return failed;
}
