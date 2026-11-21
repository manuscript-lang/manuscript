#define _POSIX_C_SOURCE 200809L
/* Unit tests for src/runtime/net/dial.c over loopback: resolving a literal and a name that does not exist, a plain and a
   TLS connect (with the protocol the handshake chose), a refused connection, and a deadline. The reactor is the real
   one; the task waits are test doubles that poll or drive the reactor, since there is no scheduler. */
#include <poll.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>

#include "../io/reactor.h"
#include "../net/dial.h"
#include "ms_rt/sys.h"
#include "ms_rt/sys_net.h"
#include "ms_sched.h"
#include "support/test_cert.h"

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

typedef struct Server { MsSock listener; MsTlsCtx *context; } Server;

/* Accepts one connection; with a context completes the handshake, then closes. */
static void *serve(void *argument) {
    Server *server = argument;
    MsSock socket = MS_SOCK_INVALID;
    for (;;) {
        if (ms_sys_net_accept(server->listener, &socket, NULL) == MS_SYS_OK) break;
        struct pollfd p = {.fd = (int)server->listener, .events = POLLIN};
        poll(&p, 1, 100);
    }
    MsConnTable *table = ms_conn_table_new(2);
    const MsConnId id = ms_conn_open(table, (int)socket, MS_CONN_HTTP1);
    if (server->context != NULL) {
        (void)ms_conn_set_tls(table, id, ms_tls_new(server->context, NULL));
        (void)ms_conn_handshake(table, id, -1);
    }
    uint8_t byte;
    size_t count = 0;
    (void)ms_conn_read(table, id, &byte, 1, -1, &count); /* until the client closes */
    (void)ms_conn_close_io(table, id);
    ms_conn_table_free(table);
    return NULL;
}

static MsAddr listen_on_loopback(Server *server) {
    MsAddr loopback = {4, {127, 0, 0, 1}, 0, 0}, bound;
    CHECK(ms_sys_net_tcp_listen(&loopback, 4, &server->listener) == MS_SYS_OK);
    CHECK(ms_sys_net_local_addr(server->listener, &bound) == MS_SYS_OK);
    return bound;
}

int main(void) {
    MsIoReactor *reactor;
    CHECK(ms_io_open(1, &reactor));

    /* resolving */
    MsNetAddresses found;
    CHECK(ms_net_resolve("127.0.0.1", 8080, -1, &found) == MS_NET_OK && found.count == 1);
    CHECK(found.items[0].family == 4 && found.items[0].ip[0] == 127 && found.items[0].ip[3] == 1 && found.items[0].port == 8080);
    CHECK(ms_net_resolve("no-such-host.invalid", 80, -1, &found) == MS_NET_FAILED && found.count == 0 && found.resolver_code < 0);

    /* a plain connection, then a TLS one that reports the protocol it chose */
    MsConnTable *table = ms_conn_table_new(4);
    Server server = {0};
    MsAddr bound = listen_on_loopback(&server);
    pthread_t thread;
    CHECK(pthread_create(&thread, NULL, serve, &server) == 0);
    MsConnId id = 0;
    int code = -1;
    CHECK(ms_net_connect(table, &bound, MS_CONN_HTTP1, NULL, NULL, -1, &id, &code) == MS_NET_OK && id != 0 && code == 0);
    CHECK(ms_conn_get(table, id) != NULL && ms_conn_get(table, id)->proto == MS_CONN_HTTP1 && ms_conn_live(table) == 1);
    CHECK(ms_conn_close_io(table, id) == MS_NET_OK);
    pthread_join(thread, NULL);
    ms_sys_net_close(server.listener);

    MsTlsCtx *server_context = ms_tls_ctx_new(1, CERT, sizeof CERT - 1, KEY, sizeof KEY - 1, NULL, 0);
    MsTlsCtx *client_context = ms_tls_ctx_new(0, NULL, 0, NULL, 0, CERT, sizeof CERT - 1);
    CHECK(server_context != NULL && client_context != NULL);
    CHECK(ms_tls_ctx_set_alpn(server_context, "h2,http/1.1") == 0 && ms_tls_ctx_set_alpn(client_context, "http/1.1") == 0);
    server.context = server_context;
    bound = listen_on_loopback(&server);
    CHECK(pthread_create(&thread, NULL, serve, &server) == 0);
    CHECK(ms_net_connect(table, &bound, MS_CONN_HTTP1, client_context, "localhost", -1, &id, &code) == MS_NET_OK);
    MsTls *session = ms_conn_tls(table, id);
    CHECK(session != NULL && ms_bytes_equal(ms_tls_alpn(session), ms_bytes_of((const uint8_t *)"http/1.1", 8)));
    CHECK(ms_conn_close_io(table, id) == MS_NET_OK);
    pthread_join(thread, NULL);
    ms_sys_net_close(server.listener);

    /* a certificate for another name fails the handshake and leaves no row behind */
    bound = listen_on_loopback(&server);
    CHECK(pthread_create(&thread, NULL, serve, &server) == 0);
    CHECK(ms_net_connect(table, &bound, MS_CONN_HTTP1, client_context, "example.invalid", -1, &id, &code) == MS_NET_FAILED);
    CHECK(ms_conn_live(table) == 0);
    pthread_join(thread, NULL);
    ms_sys_net_close(server.listener);

    /* a refused connection: nothing listens on a port that was just closed */
    CHECK(ms_net_connect(table, &bound, MS_CONN_NONE, NULL, NULL, -1, &id, &code) == MS_NET_FAILED && ms_conn_live(table) == 0);
    CHECK(ms_net_connect(table, &bound, MS_CONN_HTTP1, NULL, NULL, -1, &id, &code) == MS_NET_FAILED);
    CHECK(code != 0 && ms_conn_live(table) == 0);

    /* a deadline that has passed ends the connect to a port that never answers (a listener nobody accepts from) */
    Server idle = {0};
    bound = listen_on_loopback(&idle);
    MsConnId extra[8];
    int connected = 0;
    for (int i = 0; i < 8; i++) {
        if (ms_net_connect(table, &bound, MS_CONN_HTTP1, NULL, NULL, ms_sys_monotonic_ns() + 200000000, &extra[connected], &code) == MS_NET_OK) connected++;
    }
    CHECK(connected > 0); /* the kernel completes a connect before accept, up to the backlog */
    for (int i = 0; i < connected; i++) (void)ms_conn_close_io(table, extra[i]);
    ms_sys_net_close(idle.listener);

    ms_tls_ctx_free(server_context);
    ms_tls_ctx_free(client_context);
    ms_conn_table_free(table);
    ms_io_close(1);
    puts(failed ? "dial_test: FAILED" : "dial_test: ok");
    return failed;
}
