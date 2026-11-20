#define _POSIX_C_SOURCE 200809L
/* Unit tests for runtime/net/natives.c over loopback: lookup, a plain and a TLS dial, reads and writes through a
   connection handle, the end of a stream, share and close_if_last, addresses, TLS facts, and the refusals. The task
   waits are test doubles (there is no scheduler) and the runtime is the fake of fake_rt.h. */
#include <poll.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../io/reactor.h"
#include "../net/addr_text.h"
#include "../net/conn_object.h"
#include "../net/dial.h"
#define FAKE_RT_TRACK
#include "fake_rt.h"
#include "ms_rt/net.h"
#include "ms_rt/sys.h"
#include "ms_rt/sys_net.h"
#include "ms_sched.h"
#include "support/test_cert.h"

static int failed;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failed = 1; } } while (0)

void msrt_string_from_bytes(const uint8_t *ptr, size_t len, MsStr *out) {
    uint8_t *copy = msrt_alloc_zeroed(len + 1); /* NUL-terminated: the test reads some strings as C strings */
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

/* An HTTP/1.1 server for one connection: answers /a (5 bytes), /b (chunked), /post (the request body's length and
   text) and /close (a reply that ends the connection), each by its request line, until the client closes. */
static void reply(MsConnTable *table, MsConnId id, const char *text) { (void)ms_conn_write(table, id, (const uint8_t *)text, strlen(text), -1); }

static void *serve_http(void *argument) {
    Server *server = argument;
    MsSock socket = MS_SOCK_INVALID;
    for (;;) {
        if (ms_sys_net_accept(server->listener, &socket, NULL) == MS_SYS_OK) break;
        struct pollfd p = {.fd = (int)server->listener, .events = POLLIN};
        poll(&p, 1, 100);
    }
    MsConnTable *table = ms_conn_table_new(2);
    const MsConnId id = ms_conn_open(table, (int)socket, MS_CONN_HTTP1);
    char request[2048];
    bool open = true;
    while (open) {
        size_t have = 0;
        const char *end = NULL;
        while (end == NULL && open) {
            size_t count = 0;
            open = ms_conn_read(table, id, (uint8_t *)request + have, sizeof request - 1 - have, -1, &count) == MS_NET_OK && count > 0;
            have += open ? count : 0;
            request[have] = 0;
            end = strstr(request, "\r\n\r\n");
        }
        if (!open) break;
        const char *length_field = strstr(request, "Content-Length: ");
        const size_t length = length_field == NULL ? 0 : (size_t)atoi(length_field + 16);
        size_t body_have = have - (size_t)(end + 4 - request);
        while (body_have < length && open) {
            size_t count = 0;
            open = ms_conn_read(table, id, (uint8_t *)request + have, sizeof request - 1 - have, -1, &count) == MS_NET_OK && count > 0;
            have += open ? count : 0;
            body_have += open ? count : 0;
        }
        request[have] = 0;
        if (strstr(request, " /a ") != NULL) {
            reply(table, id, "HTTP/1.1 200 OK\r\nx-reply: 1\r\nContent-Length: 5\r\n\r\nhello");
        } else if (strstr(request, " /b ") != NULL) {
            reply(table, id, "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nhel\r\n2\r\nlo\r\n0\r\n\r\n");
        } else if (strstr(request, " /post ") != NULL) {
            char text[64];
            snprintf(text, sizeof text, "HTTP/1.1 200 OK\r\nContent-Length: %zu\r\n\r\n%.*s", length, (int)length, end + 4);
            reply(table, id, text);
        } else {
            reply(table, id, "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\nbye");
            break;
        }
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

    /* header tables: names fold case and keep their first spelling, values keep their order */
    void *table = msstd_headers_new();
    MsStr x_dup = str("X-Dup"), x_dup_lower = str("x-dup"), other_name = str("Other"), spaced = str("bad name");
    MsVec first = bytes("first"), second = bytes("second"), one = bytes("1");
    CHECK(msstd_headers_append(table, &x_dup, &first) == STATUS_OK && msstd_headers_append(table, &x_dup_lower, &second) == STATUS_OK);
    CHECK(msstd_headers_append(table, &other_name, &one) == STATUS_OK && msstd_headers_append(table, &spaced, &one) == STATUS_INVALID_INPUT);
    MsVec names, values;
    msstd_headers_names(table, &names);
    CHECK(names.len == 2 && str_is(&((MsStr *)names.ptr)[0], "X-Dup") && str_is(&((MsStr *)names.ptr)[1], "Other"));
    MsStr loud = str("X-DUP");
    CHECK(msstd_headers_values(table, &loud, &values) == 1 && values.len == 2);
    CHECK(((MsVec *)values.ptr)[0].len == 5 && memcmp(((MsVec *)values.ptr)[1].ptr, "second", 6) == 0);
    MsStr nothing = str("Nothing");
    CHECK(msstd_headers_values(table, &nothing, &values) == 0);
    void *copy = msstd_headers_clone(table);
    MsStr other_loud = str("OTHER");
    CHECK(msstd_headers_remove(table, &other_loud) == 1 && msstd_headers_remove(table, &other_loud) == 0);
    CHECK(msstd_headers_values(copy, &other_name, &values) == 1); /* the copy is independent */
    ((MsObj *)copy)->drop(copy);

    /* fetch over HTTP/1.1: one connection carries several exchanges, each ended by reading its body */
    address = listen_on_loopback(&server);
    server.context = NULL;
    CHECK(pthread_create(&thread, NULL, serve_http, &server) == 0);
    CHECK(msstd_net_dial(&address, &no_name, 0, NULL, 1, 5 * SECOND, &conn, &err) == STATUS_OK);
    MsStr get = str("GET"), post = str("POST"), authority = str("example.test");
    MsStr target_a = str("/a"), target_b = str("/b"), target_post = str("/post"), target_close = str("/close");
    MsVec nobody = bytes("");
    MsVec sent = bytes("abc");
    void *response = NULL;
    MsVec data;
    CHECK(msstd_http_fetch(conn, &get, &authority, &target_a, table, &nobody, 1, 5 * SECOND, &response, &err) == STATUS_OK);
    MsNetBodyMetadata metadata;
    msstd_body_metadata(response, &metadata);
    MsStr reply_name = str("x-reply");
    CHECK(metadata.status == 200 && str_is(&metadata.protocol, "HTTP/1.1") && msstd_headers_values(metadata.headers, &reply_name, &values) == 1);
    msstd_headers_names(metadata.headers, &names);
    CHECK(names.len == 2 && str_is(&((MsStr *)names.ptr)[0], "X-Reply")); /* received names are canonical */
    void *busy = NULL;
    CHECK(msstd_http_fetch(conn, &get, &authority, &target_a, table, &nobody, 0, 0, &busy, &err) == STATUS_BUSY); /* the body is still open */
    CHECK(msstd_body_read(response, 1, 2, &data, &err) == STATUS_OK && data.len == 2);
    msstd_body_close(response); /* part of the body unread: the connection closes with it */
    CHECK(msstd_body_read(response, 0, 0, &data, &err) == STATUS_CLOSED);
    ((MsObj *)response)->drop(response);
    ((MsObj *)metadata.headers)->drop(metadata.headers);
    CHECK(msstd_http_fetch(conn, &get, &authority, &target_a, table, &nobody, 0, 0, &busy, &err) == STATUS_CLOSED);
    ((MsObj *)conn)->drop(conn);
    pthread_join(thread, NULL);
    ms_sys_net_close(server.listener);

    address = listen_on_loopback(&server);
    CHECK(pthread_create(&thread, NULL, serve_http, &server) == 0);
    CHECK(msstd_net_dial(&address, &no_name, 0, NULL, 1, 5 * SECOND, &conn, &err) == STATUS_OK);
    CHECK(msstd_http_fetch(conn, &get, &authority, &target_a, table, &nobody, 1, 5 * SECOND, &response, &err) == STATUS_OK);
    CHECK(msstd_body_read_all(response, 1, 4, &data, &err) == STATUS_LIMIT_EXCEEDED); /* all 5 bytes came: the row is still good */
    msstd_body_close(response);
    ((MsObj *)response)->drop(response);
    CHECK(msstd_http_fetch(conn, &get, &authority, &target_a, table, &nobody, 1, 5 * SECOND, &response, &err) == STATUS_OK);
    CHECK(msstd_body_read_all(response, 0, 0, &data, &err) == STATUS_OK && data.len == 5 && memcmp(data.ptr, "hello", 5) == 0);
    msstd_body_close(response);
    ((MsObj *)response)->drop(response);
    CHECK(msstd_http_fetch(conn, &get, &authority, &target_b, table, &nobody, 1, 5 * SECOND, &response, &err) == STATUS_OK);
    CHECK(msstd_body_read(response, 1, 2, &data, &err) == STATUS_OK && data.len == 2 && memcmp(data.ptr, "he", 2) == 0);
    CHECK(msstd_body_read(response, 0, 0, &data, &err) == STATUS_OK && data.len == 1);
    CHECK(msstd_body_read(response, 0, 0, &data, &err) == STATUS_OK && data.len == 2);
    CHECK(msstd_body_read(response, 0, 0, &data, &err) == STATUS_NONE);
    ((MsObj *)response)->drop(response); /* dropping ends the exchange as a close does */
    CHECK(msstd_http_fetch(conn, &post, &authority, &target_post, table, &sent, 1, 5 * SECOND, &response, &err) == STATUS_OK);
    CHECK(msstd_body_read_all(response, 0, 0, &data, &err) == STATUS_OK && data.len == 3 && memcmp(data.ptr, "abc", 3) == 0);
    msstd_body_close(response);
    ((MsObj *)response)->drop(response);

    /* a field the exchange writes itself, or a value that could split the head, is refused and the connection stays */
    void *refused = msstd_headers_new();
    MsStr host_name = str("host"), split_name = str("X-Split");
    MsVec host_value = bytes("elsewhere"), split_value = bytes("a\r\nInjected: 1");
    CHECK(msstd_headers_append(refused, &host_name, &host_value) == STATUS_OK);
    CHECK(msstd_http_fetch(conn, &get, &authority, &target_a, refused, &nobody, 0, 0, &response, &err) == STATUS_INVALID_INPUT);
    ((MsObj *)refused)->drop(refused);
    refused = msstd_headers_new();
    CHECK(msstd_headers_append(refused, &split_name, &split_value) == STATUS_OK);
    CHECK(msstd_http_fetch(conn, &get, &authority, &target_a, refused, &nobody, 0, 0, &response, &err) == STATUS_INVALID_INPUT);
    ((MsObj *)refused)->drop(refused);
    MsStr bad_method = str("GE T");
    CHECK(msstd_http_fetch(conn, &bad_method, &authority, &target_a, table, &nobody, 0, 0, &response, &err) == STATUS_INVALID_INPUT);
    CHECK(msstd_http_fetch(conn, &get, &authority, &target_a, table, &nobody, 1, 5 * SECOND, &response, &err) == STATUS_OK);
    CHECK(msstd_body_read_all(response, 0, 0, &data, &err) == STATUS_OK && data.len == 5);
    msstd_body_close(response);
    ((MsObj *)response)->drop(response);

    /* a reply that ends the connection closes the row with the body, and the metadata outlives it */
    CHECK(msstd_http_fetch(conn, &get, &authority, &target_close, table, &nobody, 1, 5 * SECOND, &response, &err) == STATUS_OK);
    CHECK(msstd_body_read_all(response, 0, 0, &data, &err) == STATUS_OK && data.len == 3);
    msstd_body_close(response);
    msstd_body_metadata(response, &metadata);
    CHECK(metadata.status == 200);
    ((MsObj *)metadata.headers)->drop(metadata.headers);
    ((MsObj *)response)->drop(response);
    CHECK(msstd_http_fetch(conn, &get, &authority, &target_a, table, &nobody, 0, 0, &response, &err) == STATUS_CLOSED);
    ((MsObj *)conn)->drop(conn);
    ((MsObj *)table)->drop(table);
    pthread_join(thread, NULL);
    ms_sys_net_close(server.listener);

    ms_tls_ctx_free(context);
    ms_io_close(1);
    fake_rt_free_all();
    puts(failed ? "net_natives_test: FAILED" : "net_natives_test: ok");
    return failed;
}
