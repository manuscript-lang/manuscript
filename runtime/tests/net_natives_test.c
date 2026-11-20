#define _POSIX_C_SOURCE 200809L
/* Unit tests for runtime/net/natives.c over loopback: lookup, a plain and a TLS dial, reads and writes through a
   connection handle, the end of a stream, share and close_if_last, addresses, TLS facts, and the refusals. The task
   waits are test doubles (there is no scheduler) and the runtime is the fake of fake_rt.h. */
#include <poll.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>

#include "../io/reactor.h"
#include "../net/addr_text.h"
#include "../net/conn_object.h"
#include "../net/dial.h"
#include "fake_rt.h"
#include "ms_rt/net.h"
#include "ms_rt/sys.h"
#include "ms_rt/sys_net.h"
#include "ms_sched.h"
#include "support/test_cert.h"

static int failed;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failed = 1; } } while (0)

void msrt_string_from_bytes(const uint8_t *ptr, size_t len, MsStr *out) {
    uint8_t *copy = malloc(len + 1);
    if (copy != NULL && len > 0) memcpy(copy, ptr, len);
    *out = (MsStr){.ptr_word = copy, .tagged = len};
}
bool ms_sched_cancel_pending(void) { return false; }
void ms_sched_cancel_return(void) {}

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


/* A server that echoes what it reads until the client closes, then closes. With a context it speaks TLS. */
typedef struct Server { MsSock listener; MsTlsCtx *context; } Server;

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
    uint8_t buffer[256];
    size_t count = 0;
    while (ms_conn_read(table, id, buffer, sizeof buffer, -1, &count) == MS_NET_OK && count > 0) {
        if (ms_conn_write(table, id, buffer, count, -1) != MS_NET_OK) break;
    }
    (void)ms_conn_close_io(table, id);
    ms_conn_table_free(table);
    return NULL;
}

static MsStr str(const char *s) {
    MsStr out;
    msrt_string_from_bytes((const uint8_t *)s, strlen(s), &out);
    return out;
}

static bool str_is(const MsStr *s, const char *expected) {
    return msrt_str_len(s) == strlen(expected) && memcmp(msrt_str_data(s), expected, strlen(expected)) == 0;
}

static MsVec bytes(const char *s) {
    MsVec out;
    msrt_write_bytes(&out, s, strlen(s));
    return out;
}

static MsStr listen_on_loopback(Server *server) {
    MsAddr loopback = {4, {127, 0, 0, 1}, 0, 0}, bound;
    CHECK(ms_sys_net_tcp_listen(&loopback, 4, &server->listener) == MS_SYS_OK);
    CHECK(ms_sys_net_local_addr(server->listener, &bound) == MS_SYS_OK);
    char text[MS_NET_ADDR_TEXT_MAX];
    size_t length = 0;
    CHECK(ms_net_addr_format(&bound, text, sizeof text, &length));
    return str(text);
}

static const int64_t SECOND = 1000000000;

int main(void) {
    MsIoReactor *reactor;
    CHECK(ms_io_open(1, &reactor));
    MsStr err;

    /* lookup */
    MsVec found;
    MsStr host = str("127.0.0.1");
    CHECK(msstd_net_lookup(&host, 80, 0, 0, &found, &err) == STATUS_OK && found.len == 1);
    CHECK(str_is((const MsStr *)found.ptr, "127.0.0.1:80"));
    MsStr missing = str("no-such-host.invalid");
    CHECK(msstd_net_lookup(&missing, 80, 1, 5 * SECOND, &found, &err) == STATUS_FAILED && str_is(&err, "name not found"));
    CHECK(msstd_net_lookup(&host, 70000, 0, 0, &found, &err) == STATUS_INVALID_INPUT);

    /* a plain connection: echo, share, addresses, end of stream */
    Server server = {0};
    MsStr address = listen_on_loopback(&server);
    pthread_t thread;
    CHECK(pthread_create(&thread, NULL, serve, &server) == 0);
    MsStr no_name = str("");
    void *conn = NULL;
    CHECK(msstd_net_dial(&address, &no_name, 0, NULL, 1, 5 * SECOND, &conn, &err) == STATUS_OK && conn != NULL);
    MsStr local, peer;
    msstd_conn_local_address(conn, &local);
    msstd_conn_peer_address(conn, &peer);
    CHECK(str_is(&peer, (const char *)msrt_str_data(&address)) && msrt_str_len(&local) > 0);
    MsVec hello = bytes("hello");
    CHECK(msstd_conn_write_bytes(conn, &hello, 1, 5 * SECOND, &err) == STATUS_OK);
    MsVec got;
    CHECK(msstd_conn_read(conn, 1, 5, 1, 5 * SECOND, &got, &err) == STATUS_OK && got.len == 5 && memcmp(got.ptr, "hello", 5) == 0);
    MsNetTlsInfo info;
    CHECK(msstd_conn_tls_info(conn, &info) == 0);
    void *other = msstd_conn_share(conn); /* a second end: closing one leaves the connection open */
    msstd_conn_close_if_last(other);
    MsVec again = bytes("again");
    CHECK(msstd_conn_write_bytes(conn, &again, 0, 0, &err) == STATUS_OK);
    CHECK(msstd_conn_read(conn, 1, 100, 1, 5 * SECOND, &got, &err) == STATUS_OK && got.len == 5);
    CHECK(msstd_conn_shutdown_write(conn, &err) == STATUS_OK); /* the server then closes: the end of the stream */
    CHECK(msstd_conn_read(conn, 0, 0, 1, 5 * SECOND, &got, &err) == STATUS_NONE);
    msstd_conn_close_if_last(conn);
    CHECK(msstd_conn_write_bytes(conn, &again, 0, 0, &err) == STATUS_CLOSED);
    CHECK(msstd_conn_read(conn, 0, 0, 0, 0, &got, &err) == STATUS_CLOSED);
    ((MsObj *)other)->drop(other);
    ((MsObj *)conn)->drop(conn);
    pthread_join(thread, NULL);
    ms_sys_net_close(server.listener);

    /* TLS: the handshake verifies the name, the options carry the ALPN list, tls_info reports the facts */
    MsTlsCtx *context = ms_tls_ctx_new(1, CERT, sizeof CERT - 1, KEY, sizeof KEY - 1, NULL, 0);
    CHECK(context != NULL && ms_tls_ctx_set_alpn(context, "h2,http/1.1") == 0);
    server.context = context;
    address = listen_on_loopback(&server);
    CHECK(pthread_create(&thread, NULL, serve, &server) == 0);
    MsNetTlsOptions options = {.server_name = str("localhost"), .roots_pem = str(CERT), .certificate_pem = str(""), .private_key_pem = str("")};
    MsStr offered[2] = {str("h2"), str("http/1.1")};
    options.alpn = (MsVec){offered, 2, 2};
    CHECK(msstd_net_dial(&address, &no_name, 1, &options, 1, 5 * SECOND, &conn, &err) == STATUS_OK);
    CHECK(msstd_conn_tls_info(conn, &info) == 1 && info.version == 0x0304 && info.cipher_suite != 0 && str_is(&info.alpn, "h2"));
    CHECK(info.peer_certificates.len >= 1 && ((MsVec *)info.peer_certificates.ptr)[0].len > 100 && info.verified == 1);
    CHECK(msstd_conn_write_bytes(conn, &hello, 1, 5 * SECOND, &err) == STATUS_OK);
    CHECK(msstd_conn_read(conn, 1, 5, 1, 5 * SECOND, &got, &err) == STATUS_OK && got.len == 5);
    msstd_conn_close(conn);
    ((MsObj *)conn)->drop(conn);
    pthread_join(thread, NULL);
    ms_sys_net_close(server.listener);

    /* a name the certificate does not cover fails the handshake and leaves nothing open */
    address = listen_on_loopback(&server);
    CHECK(pthread_create(&thread, NULL, serve, &server) == 0);
    MsStr wrong = str("example.invalid");
    CHECK(msstd_net_dial(&address, &wrong, 1, &options, 1, 5 * SECOND, &conn, &err) == STATUS_FAILED);
    pthread_join(thread, NULL);
    ms_sys_net_close(server.listener);

    /* refusals: a malformed address, a connection that is refused, TLS without a name */
    MsStr bad = str("not an address");
    CHECK(msstd_net_dial(&bad, &no_name, 0, NULL, 0, 0, &conn, &err) == STATUS_INVALID_INPUT);
    CHECK(msstd_net_dial(&address, &no_name, 0, NULL, 1, 5 * SECOND, &conn, &err) == STATUS_FAILED); /* nothing listens now */
    MsNetTlsOptions nameless = options;
    nameless.server_name = str("");
    CHECK(msstd_net_dial(&address, &no_name, 1, &nameless, 1, 5 * SECOND, &conn, &err) == STATUS_INVALID_INPUT);

    ms_tls_ctx_free(context);
    ms_io_close(1);
    puts(failed ? "net_natives_test: FAILED" : "net_natives_test: ok");
    return failed;
}
