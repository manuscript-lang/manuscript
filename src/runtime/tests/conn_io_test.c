#define _POSIX_C_SOURCE 200809L
/* Unit tests for src/runtime/net/conn_io.c over loopback: plain and TLS echo, the end of a stream, a stale id, and a
   deadline. A server thread owns its own connection table; the task wait is poll(2), since there is one thread per
   side and no scheduler. */
#include <poll.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>

#include "../net/conn_io.h"
#include "ms_rt/sys.h"
#include "ms_rt/sys_net.h"
#include "ms_sched.h"
#include "test_cert.h"

static int failed;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failed = 1; } } while (0)

uint32_t msrt_task_wait_fd(int32_t fd, uint32_t events, int64_t timeout_ns) {
    struct pollfd p = {.fd = fd, .events = (short)((events & MS_WAIT_READ ? POLLIN : 0) | (events & MS_WAIT_WRITE ? POLLOUT : 0))};
    const int ms = timeout_ns < 0 ? -1 : (int)(timeout_ns / 1000000 + 1);
    const int r = poll(&p, 1, ms);
    if (r == 0) return MS_WAIT_TIMEOUT;
    return (p.revents & POLLIN ? MS_WAIT_READ : 0) | (p.revents & POLLOUT ? MS_WAIT_WRITE : 0) | (p.revents & (POLLHUP | POLLERR) ? MS_WAIT_HUP : 0);
}

typedef struct Server {
    MsSock listener;
    int tls;
    MsTlsCtx *context;
} Server;

/* Accepts one connection and echoes until the end of the stream, then closes. */
static void *serve(void *argument) {
    Server *server = argument;
    MsSock socket = MS_SOCK_INVALID;
    for (;;) {
        const int r = ms_sys_net_accept(server->listener, &socket, NULL);
        if (r == MS_SYS_OK) break;
        struct pollfd p = {.fd = (int)server->listener, .events = POLLIN};
        poll(&p, 1, 100);
    }
    MsConnTable *table = ms_conn_table_new(4);
    const MsConnId id = ms_conn_open(table, (int)socket, MS_CONN_HTTP1);
    if (server->tls) {
        ms_conn_set_tls(table, id, ms_tls_new(server->context, NULL));
        if (ms_conn_handshake(table, id, -1) != MS_NET_OK) {
            ms_conn_close_io(table, id);
            ms_conn_table_free(table);
            return NULL;
        }
    }
    uint8_t buffer[8192];
    size_t count = 0;
    while (ms_conn_read(table, id, buffer, sizeof buffer, -1, &count) == MS_NET_OK && count > 0) {
        if (ms_conn_write(table, id, buffer, count, -1) != MS_NET_OK) break;
    }
    ms_conn_close_io(table, id);
    ms_conn_table_free(table);
    return NULL;
}

static void echo_round(int use_tls, MsTlsCtx *server_context, MsTlsCtx *client_context) {
    MsAddr loopback = {4, {127, 0, 0, 1}, 0, 0}, bound;
    Server server = {.tls = use_tls, .context = server_context};
    CHECK(ms_sys_net_tcp_listen(&loopback, 4, &server.listener) == MS_SYS_OK);
    CHECK(ms_sys_net_local_addr(server.listener, &bound) == MS_SYS_OK);
    pthread_t thread;
    CHECK(pthread_create(&thread, NULL, serve, &server) == 0);

    MsSock client = MS_SOCK_INVALID;
    const int r = ms_sys_net_tcp_connect(&bound, &client);
    CHECK(r == MS_SYS_OK || r == MS_SYS_INPROGRESS);
    MsConnTable *table = ms_conn_table_new(4);
    const MsConnId id = ms_conn_open(table, (int)client, MS_CONN_HTTP1);
    if (r == MS_SYS_INPROGRESS) {
        (void)msrt_task_wait_fd((int32_t)client, MS_WAIT_WRITE, -1);
        CHECK(ms_sys_net_connect_done(client) == MS_SYS_OK);
    }
    if (use_tls) {
        CHECK(ms_conn_set_tls(table, id, ms_tls_new(client_context, "localhost")) == MS_NET_OK);
        CHECK(ms_conn_handshake(table, id, -1) == MS_NET_OK);
    }

    uint8_t big[70000], back[70000];
    for (size_t i = 0; i < sizeof big; i++) big[i] = (uint8_t)(i * 31u);
    CHECK(ms_conn_write(table, id, (const uint8_t *)"hello", 5, -1) == MS_NET_OK);
    size_t count = 0;
    CHECK(ms_conn_read(table, id, back, sizeof back, -1, &count) == MS_NET_OK && count == 5 && !memcmp(back, "hello", 5));

    /* A write larger than the socket buffers, read back in pieces. */
    CHECK(ms_conn_write(table, id, big, 40000, -1) == MS_NET_OK);
    size_t total = 0;
    while (total < 40000) {
        CHECK(ms_conn_read(table, id, back + total, sizeof back - total, -1, &count) == MS_NET_OK && count > 0);
        total += count;
    }
    CHECK(total == 40000 && !memcmp(big, back, 40000));

    /* Nothing more is coming: a read with a deadline times out and the row stays usable. */
    CHECK(ms_conn_read(table, id, back, sizeof back, ms_sys_monotonic_ns() + 20000000, &count) == MS_NET_TIMEOUT);
    CHECK(ms_conn_write(table, id, (const uint8_t *)"x", 1, -1) == MS_NET_OK);
    CHECK(ms_conn_read(table, id, back, 1, -1, &count) == MS_NET_OK && count == 1);

    /* Half close: the server sees the end and closes, so the client reads the end too. */
    CHECK(ms_conn_shutdown_write(table, id, -1) == MS_NET_OK);
    CHECK(ms_conn_read(table, id, back, sizeof back, -1, &count) == MS_NET_OK && count == 0);
    CHECK(ms_conn_close_io(table, id) == MS_NET_OK);
    CHECK(ms_conn_close_io(table, id) == MS_NET_CLOSED); /* a stale id */
    CHECK(ms_conn_write(table, id, (const uint8_t *)"x", 1, -1) == MS_NET_CLOSED);
    CHECK(ms_conn_live(table) == 0);
    ms_conn_table_free(table);
    pthread_join(thread, NULL);
    ms_sys_net_close(server.listener);
}

/* wait_gone returns CLOSED once the peer has closed, and CLOSED again for the stale id. */
static void gone_round(void) {
    MsAddr loopback = {4, {127, 0, 0, 1}, 0, 0}, bound;
    Server server = {.tls = 0, .context = NULL};
    CHECK(ms_sys_net_tcp_listen(&loopback, 4, &server.listener) == MS_SYS_OK);
    CHECK(ms_sys_net_local_addr(server.listener, &bound) == MS_SYS_OK);
    pthread_t thread;
    CHECK(pthread_create(&thread, NULL, serve, &server) == 0);
    MsSock client = MS_SOCK_INVALID;
    const int r = ms_sys_net_tcp_connect(&bound, &client);
    CHECK(r == MS_SYS_OK || r == MS_SYS_INPROGRESS);
    MsConnTable *table = ms_conn_table_new(4);
    const MsConnId id = ms_conn_open(table, (int)client, MS_CONN_HTTP1);
    if (r == MS_SYS_INPROGRESS) {
        (void)msrt_task_wait_fd((int32_t)client, MS_WAIT_WRITE, -1);
        CHECK(ms_sys_net_connect_done(client) == MS_SYS_OK);
    }
    CHECK(ms_conn_shutdown_write(table, id, -1) == MS_NET_OK); /* the echo server reads the end and closes */
    CHECK(ms_conn_wait_gone(table, id, NULL) == MS_NET_CLOSED);
    CHECK(ms_conn_close_io(table, id) == MS_NET_OK);
    CHECK(ms_conn_wait_gone(table, id, NULL) == MS_NET_CLOSED); /* a stale id */
    ms_conn_table_free(table);
    pthread_join(thread, NULL);
    ms_sys_net_close(server.listener);
}

int main(void) {
    echo_round(0, NULL, NULL);
    gone_round();
    MsTlsCtx *server_context = ms_tls_ctx_new(1, CERT, sizeof CERT - 1, KEY, sizeof KEY - 1, NULL, 0);
    MsTlsCtx *client_context = ms_tls_ctx_new(0, NULL, 0, NULL, 0, CERT, sizeof CERT - 1);
    CHECK(server_context != NULL && client_context != NULL);
    echo_round(1, server_context, client_context);
    ms_tls_ctx_free(server_context);
    ms_tls_ctx_free(client_context);
    puts(failed ? "conn_io_test: FAILED" : "conn_io_test: ok");
    return failed;
}
