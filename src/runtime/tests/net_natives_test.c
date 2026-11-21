#define _POSIX_C_SOURCE 200809L
/* Unit tests for src/runtime/net/natives.c over loopback: lookup, a plain and a TLS dial, reads and writes through a
   connection handle, the end of a stream, share and close_if_last, addresses, TLS facts, and the refusals. The task
   waits are test doubles (there is no scheduler) and the runtime is the fake of fake_rt.h. */
#include <stdbool.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <uv.h>

#ifdef _WIN32
#include <winsock2.h>
#include <afunix.h>
#include <io.h>
#include <process.h>
#define poll_sockets(fds, count, ms) WSAPoll((fds), (ULONG)(count), (ms))
#define remove_file _unlink
#define current_pid _getpid
#define close_socket closesocket
typedef WSAPOLLFD PollFd;
typedef SOCKET PollHandle;
#else
#include <poll.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#define poll_sockets(fds, count, ms) poll((fds), (nfds_t)(count), (ms))
#define remove_file unlink
#define current_pid getpid
#define close_socket close
typedef struct pollfd PollFd;
typedef int PollHandle;
#endif

#include "../io/reactor.h"
#include "../net/addr_text.h"
#include "../net/conn_object.h"
#include "../net/curl_client.h"
#include "../net/dial.h"
#define FAKE_RT_TRACK
#include "fake_rt.h"
#include "ms_rt/net.h"
#include "ms_rt/sys.h"
#include "ms_rt/sys_net.h"
#include "ms_sched.h"
#include "support/test_cert.h"

static int failed;
static const int64_t SECOND = 1000000000;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failed = 1; } } while (0)

void msrt_string_from_bytes(const uint8_t *ptr, size_t len, MsStr *out) {
    uint8_t *copy = msrt_alloc_zeroed(len + 1); /* NUL-terminated: the test reads some strings as C strings */
    if (copy != NULL && len > 0) memcpy(copy, ptr, len);
    *out = (MsStr){.ptr_word = copy, .tagged = len};
}
void msrt_string_free(const MsStr *s) {
    if (s->tagged < ((uint64_t)1 << 62)) msrt_free(s->ptr_word);
}
void msrt_string_clone(const MsStr *s, MsStr *out) { msrt_string_from_bytes((const uint8_t *)s->ptr_word, (size_t)s->tagged, out); }
bool ms_sched_cancel_pending(void) { return false; }
__attribute__((weak)) int64_t ms_sched_defer_deadline(void) { return INT64_MAX; }
void ms_sched_cancel_return(void) {}

uint32_t msrt_task_wait_fd(int32_t fd, uint32_t events, int64_t timeout_ns) {
    PollFd p = {.fd = (PollHandle)fd, .events = (short)((events & MS_WAIT_READ ? POLLIN : 0) | (events & MS_WAIT_WRITE ? POLLOUT : 0))};
    const int ms = timeout_ns < 0 ? -1 : (int)(timeout_ns / 1000000 + 1);
    const int r = poll_sockets(&p, 1, ms);
    if (r == 0) return MS_WAIT_TIMEOUT;
    return (p.revents & POLLIN ? MS_WAIT_READ : 0) | (p.revents & POLLOUT ? MS_WAIT_WRITE : 0) | (p.revents & (POLLHUP | POLLERR) ? MS_WAIT_HUP : 0);
}

/* Tokens: one at a time, parked by running the reactor until its completion arrives. */
static uint64_t next_token = 1000;
static uint64_t pending_token;

uint64_t msrt_token_new(uint32_t flags) { (void)flags; pending_token = ++next_token; return pending_token; }
void msrt_token_free(uint64_t token) { (void)token; pending_token = 0; }
/* Posts from other threads (the HTTP client's driver) are remembered until the token's park takes them. */
static uv_mutex_t post_lock;
static struct { uint64_t token, value; } posted[16];

void msrt_token_post_remote(uint64_t token, uint64_t value) {
    uv_mutex_lock(&post_lock);
    for (size_t i = 0; i < sizeof posted / sizeof posted[0]; i++) {
        if (posted[i].token == 0) { posted[i].token = token; posted[i].value = value; break; }
    }
    uv_mutex_unlock(&post_lock);
}

static bool take_post(uint64_t token, uint64_t *value) {
    bool found = false;
    uv_mutex_lock(&post_lock);
    for (size_t i = 0; i < sizeof posted / sizeof posted[0]; i++) {
        if (posted[i].token == token) { *value = posted[i].value; posted[i].token = 0; found = true; break; }
    }
    uv_mutex_unlock(&post_lock);
    return found;
}

uint32_t msrt_token_park(uint64_t token, int64_t timeout_ns, uint64_t *value) {
    const int64_t end = timeout_ns < 0 ? -1 : ms_sys_monotonic_ns() + timeout_ns;
    for (;;) {
        if (take_post(token, value)) return 0;
        MsIoEvent event;
        while (ms_io_completion(&event)) {
            if (event.id == token) { *value = (uint64_t)(int64_t)event.result; return 0; }
        }
        int64_t wait = 2000000; /* short: a post from another thread does not wake the reactor */
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

static void serve(void *argument) {
    Server *server = argument;
    MsSock socket = MS_SOCK_INVALID;
    for (;;) {
        if (ms_sys_net_accept(server->listener, &socket, NULL) == MS_SYS_OK) break;
        PollFd p = {.fd = (PollHandle)server->listener, .events = POLLIN};
        poll_sockets(&p, 1, 100);
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
}

/* An HTTP/1.1 server for one connection, answering each request by its path until the client closes or a reply ends
   the connection: /a (5 bytes), /b (chunked), /post (the body back), /echo (the request head back), /redir and
   /hop (redirects to /a and to another host), /gz (gzip), /cookie (sets one), /big (1 MiB), /slow (after 300 ms),
   and /close. */
static const uint8_t GZIP_HELLO[36] = {0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0xff, 0xcb, 0x48, 0xcd, 0xc9, 0xc9, 0x57, 0x48, 0xaf,
                                       0xca, 0x2c, 0x50, 0x28, 0xcf, 0x2f, 0xca, 0x49, 0x01, 0x00, 0x6b, 0x7d, 0xe8, 0xb7, 0x10, 0x00, 0x00, 0x00};
enum { BIG_BYTES = 1 << 20 };

static void reply(MsConnTable *table, MsConnId id, const char *text) { (void)ms_conn_write(table, id, (const uint8_t *)text, strlen(text), -1); }

static void reply_big(MsConnTable *table, MsConnId id) {
    reply(table, id, "HTTP/1.1 200 OK\r\nContent-Length: 1048576\r\n\r\n");
    uint8_t chunk[65536];
    for (size_t sent = 0; sent < BIG_BYTES; sent += sizeof chunk) {
        for (size_t i = 0; i < sizeof chunk; i++) chunk[i] = (uint8_t)((sent + i) & 0xff);
        if (ms_conn_write(table, id, chunk, sizeof chunk, -1) != MS_NET_OK) return;
    }
}

/* Answers one request; false when the reply ends the connection. */
static bool answer_http(MsConnTable *table, MsConnId id, const char *request, size_t length, const char *body) {
    if (strstr(request, " /a ") != NULL) {
        reply(table, id, "HTTP/1.1 200 OK\r\nx-reply: 1\r\nContent-Length: 5\r\n\r\nhello");
    } else if (strstr(request, " /b ") != NULL) {
        reply(table, id, "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nhel\r\n2\r\nlo\r\n0\r\n\r\n");
    } else if (strstr(request, " /post ") != NULL) {
        char text[96];
        const char *length_field = strstr(request, "Content-Length: ");
        const size_t count = length_field == NULL ? 0 : (size_t)atoi(length_field + 16);
        snprintf(text, sizeof text, "HTTP/1.1 200 OK\r\nContent-Length: %zu\r\n\r\n%.*s", count, (int)count, body);
        reply(table, id, text);
    } else if (strstr(request, " /echo ") != NULL) {
        char head[96];
        snprintf(head, sizeof head, "HTTP/1.1 200 OK\r\nContent-Length: %zu\r\n\r\n", length);
        reply(table, id, head);
        (void)ms_conn_write(table, id, (const uint8_t *)request, length, -1);
    } else if (strstr(request, " /redir ") != NULL) {
        reply(table, id, "HTTP/1.1 302 Found\r\nLocation: /a\r\nContent-Length: 0\r\n\r\n");
    } else if (strstr(request, " /hop ") != NULL) {
        reply(table, id, "HTTP/1.1 302 Found\r\nLocation: http://blocked.example/x\r\nContent-Length: 0\r\n\r\n");
    } else if (strstr(request, " /gz ") != NULL) {
        reply(table, id, "HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\nContent-Length: 36\r\n\r\n");
        (void)ms_conn_write(table, id, GZIP_HELLO, sizeof GZIP_HELLO, -1);
    } else if (strstr(request, " /cookie ") != NULL) {
        reply(table, id, "HTTP/1.1 200 OK\r\nSet-Cookie: a=1; Path=/\r\nContent-Length: 0\r\n\r\n");
    } else if (strstr(request, " /big ") != NULL) {
        reply_big(table, id);
    } else if (strstr(request, " /slow ") != NULL) {
        ms_sys_sleep_ms(300);
        reply(table, id, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello");
    } else {
        reply(table, id, "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 3\r\n\r\nbye");
        return false;
    }
    return true;
}

static void serve_http(void *argument) {
    Server *server = argument;
    MsSock socket = MS_SOCK_INVALID;
    for (;;) {
        if (ms_sys_net_accept(server->listener, &socket, NULL) == MS_SYS_OK) break;
        PollFd p = {.fd = (PollHandle)server->listener, .events = POLLIN};
        poll_sockets(&p, 1, 100);
    }
    MsConnTable *table = ms_conn_table_new(2);
    const MsConnId id = ms_conn_open(table, (int)socket, MS_CONN_HTTP1);
    if (server->context != NULL) {
        (void)ms_conn_set_tls(table, id, ms_tls_new(server->context, NULL));
        (void)ms_conn_handshake(table, id, -1);
    }
    char request[4096];
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
        open = open && answer_http(table, id, request, (size_t)(end + 4 - request), end + 4);
    }
    (void)ms_conn_close_io(table, id);
    ms_conn_table_free(table);
}

static MsStr str(const char *s) {
    MsStr out;
    msrt_string_from_bytes((const uint8_t *)s, strlen(s), &out);
    return out;
}

static bool str_is(const MsStr *s, const char *expected) {
    return msrt_str_len(s) == strlen(expected) && memcmp(msrt_str_data(s), expected, strlen(expected)) == 0;
}

static bool contains(const MsVec *data, const char *needle) {
    const size_t length = strlen(needle);
    for (size_t i = 0; i + length <= data->len; i++) {
        if (memcmp((const uint8_t *)data->ptr + i, needle, length) == 0) return true;
    }
    return false;
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

/* A TLS server built on the natives: it accepts one connection as a ConnH, upgrades it with a shared server context
   (or with the options, when `server` is null), echoes five bytes and closes. */
typedef struct TlsServe { MsSock listener; void *server; const MsNetTlsOptions *options; uint8_t status; } TlsServe;

static void serve_tls_natives(void *argument) {
    TlsServe *serve = argument;
    MsSock socket = MS_SOCK_INVALID;
    for (;;) {
        if (ms_sys_net_accept(serve->listener, &socket, NULL) == MS_SYS_OK) break;
        PollFd p = {.fd = (PollHandle)serve->listener, .events = POLLIN};
        poll_sockets(&p, 1, 100);
    }
    MsConnTable *table = ms_conn_table_new(2);
    MsObj *plain = ms_netconn_new(table, ms_conn_open(table, (int)socket, MS_CONN_HTTP1));
    MsStr err;
    void *secure = NULL;
    serve->status = serve->server != NULL ? msstd_conn_accept_tls_with(plain, serve->server, 1, 5 * SECOND, &secure, &err)
                                           : msstd_conn_accept_tls(plain, serve->options, 1, 5 * SECOND, &secure, &err);
    if (serve->status == STATUS_OK) {
        MsVec got;
        if (msstd_conn_read(secure, 1, 5, 1, 5 * SECOND, &got, &err) == STATUS_OK) {
            (void)msstd_conn_write_bytes(secure, &got, 1, 5 * SECOND, &err);
        }
        msstd_conn_close(secure);
        ((MsObj *)secure)->drop(secure);
    }
    msstd_conn_close(plain);
    ((MsObj *)plain)->drop(plain);
}

/* A DNS server for the resolver test: every name has the address 127.0.0.1, and there are no IPv6 records. */
typedef struct DnsServer { MsSock udp; atomic_bool stop; } DnsServer;

static void serve_dns(void *argument) {
    DnsServer *server = argument;
    while (!atomic_load(&server->stop)) {
        uint8_t query[512], out[600];
        MsAddr from;
        size_t count = 0;
        const int received = ms_sys_net_udp_recv(server->udp, query, sizeof query, &count, &from);
        if (received == MS_SYS_AGAIN) {
            PollFd p = {.fd = (PollHandle)server->udp, .events = POLLIN};
            poll_sockets(&p, 1, 50);
            continue;
        }
        if (received != MS_SYS_OK) {
            break;
        }
        size_t end = 12;
        while (end < count && query[end] != 0) end += (size_t)query[end] + 1;
        end += 5;
        const bool wants_a = query[end - 3] == 1;
        memcpy(out, query, end);
        out[2] = 0x81;
        out[3] = 0x80;
        out[6] = 0;
        out[7] = wants_a ? 1 : 0;
        size_t length = end;
        if (wants_a) {
            static const uint8_t record[] = {0xC0, 0x0C, 0, 1, 0, 1, 0, 0, 0, 30, 0, 4, 127, 0, 0, 1};
            memcpy(out + length, record, sizeof record);
            length += sizeof record;
        }
        size_t sent = 0;
        (void)ms_sys_net_udp_send(server->udp, out, length, &from, &sent);
    }
}


int main(void) {
    CHECK(uv_mutex_init(&post_lock) == 0);
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
    MsSysThread *thread = NULL;
    thread = ms_sys_thread_spawn(1 << 20, serve, &server);
    CHECK(thread != NULL);
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
    ms_sys_thread_join(thread);
    ms_sys_net_close(server.listener);

    /* TLS: the handshake verifies the name, the options carry the ALPN list, tls_info reports the facts */
    MsTlsCtx *context = ms_tls_ctx_new(1, CERT, sizeof CERT - 1, KEY, sizeof KEY - 1, NULL, 0);
    CHECK(context != NULL && ms_tls_ctx_set_alpn(context, "h2,http/1.1") == 0);
    server.context = context;
    address = listen_on_loopback(&server);
    thread = ms_sys_thread_spawn(1 << 20, serve, &server);
    CHECK(thread != NULL);
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
    ms_sys_thread_join(thread);
    ms_sys_net_close(server.listener);

    /* a name the certificate does not cover fails the handshake and leaves nothing open */
    address = listen_on_loopback(&server);
    thread = ms_sys_thread_spawn(1 << 20, serve, &server);
    CHECK(thread != NULL);
    MsStr wrong = str("example.invalid");
    CHECK(msstd_net_dial(&address, &wrong, 1, &options, 1, 5 * SECOND, &conn, &err) == STATUS_FAILED);
    ms_sys_thread_join(thread);
    ms_sys_net_close(server.listener);

    /* start_tls upgrades a plain connection in place: the handshake runs on the row and the result is a handle on it */
    address = listen_on_loopback(&server);
    thread = ms_sys_thread_spawn(1 << 20, serve, &server);
    CHECK(thread != NULL);
    CHECK(msstd_net_dial(&address, &no_name, 0, NULL, 1, 5 * SECOND, &conn, &err) == STATUS_OK);
    MsStr plain_alpn;
    msstd_conn_alpn(conn, &plain_alpn);
    CHECK(msrt_str_len(&plain_alpn) == 0 && msstd_conn_tls_info(conn, &info) == 0);
    void *upgraded = NULL, *conn_again = NULL;
    MsNetTlsOptions no_server_name = options;
    no_server_name.server_name = str("");
    CHECK(msstd_conn_start_tls(conn, &no_server_name, 1, 5 * SECOND, &upgraded, &err) == STATUS_INVALID_INPUT); /* a name is needed */
    CHECK(msstd_conn_start_tls(conn, &options, 1, 5 * SECOND, &upgraded, &err) == STATUS_OK && upgraded != NULL);
    CHECK(msstd_conn_tls_info(upgraded, &info) == 1 && str_is(&info.alpn, "h2") && info.verified == 1);
    MsStr chosen;
    msstd_conn_alpn(upgraded, &chosen);
    CHECK(str_is(&chosen, "h2"));
    CHECK(msstd_conn_start_tls(upgraded, &options, 1, 5 * SECOND, &conn_again, &err) == STATUS_INVALID_INPUT); /* already TLS */
    CHECK(msstd_conn_write_bytes(upgraded, &hello, 1, 5 * SECOND, &err) == STATUS_OK);
    CHECK(msstd_conn_read(upgraded, 1, 5, 1, 5 * SECOND, &got, &err) == STATUS_OK && got.len == 5);
    msstd_conn_close(upgraded);
    ((MsObj *)upgraded)->drop(upgraded);
    ((MsObj *)conn)->drop(conn);
    ms_sys_thread_join(thread);
    ms_sys_net_close(server.listener);

    /* refusals: a malformed address, a connection that is refused, TLS without a name */
    MsStr bad = str("not an address");
    CHECK(msstd_net_dial(&bad, &no_name, 0, NULL, 0, 0, &conn, &err) == STATUS_INVALID_INPUT);
    CHECK(msstd_net_dial(&address, &no_name, 0, NULL, 1, 5 * SECOND, &conn, &err) == STATUS_FAILED); /* nothing listens now */
    MsNetTlsOptions nameless = options;
    nameless.server_name = str("");
    CHECK(msstd_net_dial(&address, &no_name, 1, &nameless, 1, 5 * SECOND, &conn, &err) == STATUS_INVALID_INPUT);

    /* server contexts: one context serves every connection of a listener and ends with its last handle; the options
       form of accept builds a context for one connection */
    MsNetTlsOptions server_options = {.server_name = str(""), .roots_pem = str(""), .certificate_pem = str(CERT), .private_key_pem = str(KEY)};
    MsNetTlsOptions no_key = server_options;
    no_key.private_key_pem = str("");
    void *tls_server = NULL;
    CHECK(msstd_tls_server_new(&no_key, &tls_server) == STATUS_INVALID_INPUT && tls_server == NULL);
    CHECK(msstd_tls_server_new(&server_options, &tls_server) == STATUS_OK && tls_server != NULL);
    void *tls_server_copy = msstd_tls_server_share(tls_server);
    ((MsObj *)tls_server)->drop(tls_server); /* the context outlives the handle that made it */
    for (int round = 0; round < 2; round++) {
        TlsServe tls_serve = {.server = round == 0 ? tls_server_copy : NULL, .options = &server_options};
        MsStr tls_address = listen_on_loopback(&server);
        tls_serve.listener = server.listener;
        thread = ms_sys_thread_spawn(1 << 20, serve_tls_natives, &tls_serve);
        CHECK(thread != NULL);
        MsNetTlsOptions client_options = {.server_name = str("localhost"), .roots_pem = str(CERT), .certificate_pem = str(""), .private_key_pem = str("")};
        CHECK(msstd_net_dial(&tls_address, &no_name, 1, &client_options, 1, 5 * SECOND, &conn, &err) == STATUS_OK);
        CHECK(msstd_conn_write_bytes(conn, &hello, 1, 5 * SECOND, &err) == STATUS_OK);
        CHECK(msstd_conn_read(conn, 1, 5, 1, 5 * SECOND, &got, &err) == STATUS_OK && got.len == 5 && memcmp(got.ptr, "hello", 5) == 0);
        msstd_conn_close(conn);
        ((MsObj *)conn)->drop(conn);
        ms_sys_thread_join(thread);
        CHECK(tls_serve.status == STATUS_OK);
        ms_sys_net_close(server.listener);
    }
    ((MsObj *)tls_server_copy)->drop(tls_server_copy);

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

    /* the HTTP client: one connection carries every request of a client (the server accepts one), and the client
       follows redirects, keeps cookies and decodes gzip */
    MsNetHttpOptions http_options = {.roots_pem = str(""), .certificate_pem = str(""), .private_key_pem = str(""), .unix_socket = str(""), .max_redirects = -1, .cookies = 1, .decompress = 1};
    address = listen_on_loopback(&server);
    server.context = NULL;
    thread = ms_sys_thread_spawn(1 << 20, serve_http, &server);
    CHECK(thread != NULL);
    void *client = NULL;
    CHECK(msstd_client_new(&http_options, &client, &err) == STATUS_OK);
    char url[128];
    MsStr get = str("GET"), post = str("POST"), url_text;
    MsVec nobody = bytes("");
    MsVec sent = bytes("abc");
    void *response = NULL;
    MsVec data;
    const char *host_port = (const char *)msrt_str_data(&address);
#define URL(path) (snprintf(url, sizeof url, "http://%s%s", host_port, path), url_text = str(url), &url_text)
    MsStr x_req = str("X-Req");
    MsVec token = bytes("v");
    CHECK(msstd_headers_append(table, &x_req, &token) == STATUS_OK);
    CHECK(msstd_client_fetch(client, &get, URL("/a"), table, &nobody, 1, 5 * SECOND, &response, &err) == STATUS_OK);
    MsNetBodyMetadata metadata;
    msstd_body_metadata(response, &metadata);
    MsStr reply_name = str("x-reply");
    CHECK(metadata.status == 200 && str_is(&metadata.protocol, "HTTP/1.1") && msstd_headers_values(metadata.headers, &reply_name, &values) == 1);
    msstd_headers_names(metadata.headers, &names);
    CHECK(names.len >= 1 && str_is(&((MsStr *)names.ptr)[0], "X-Reply")); /* received names are canonical */
    CHECK(msstd_body_read(response, 1, 2, &data, &err) == STATUS_OK && data.len == 2 && memcmp(data.ptr, "he", 2) == 0);
    CHECK(msstd_body_read_all(response, 1, 2, &data, &err) == STATUS_LIMIT_EXCEEDED); /* 3 bytes remain, over the limit of 2 */
    msstd_body_close(response);
    CHECK(msstd_body_read(response, 0, 0, &data, &err) == STATUS_CLOSED);
    ((MsObj *)response)->drop(response);
    ((MsObj *)metadata.headers)->drop(metadata.headers);

    CHECK(msstd_client_fetch(client, &get, URL("/b"), table, &nobody, 1, 5 * SECOND, &response, &err) == STATUS_OK);
    CHECK(msstd_body_read_all(response, 0, 0, &data, &err) == STATUS_OK && data.len == 5 && memcmp(data.ptr, "hello", 5) == 0);
    CHECK(msstd_body_read(response, 0, 0, &data, &err) == STATUS_NONE);
    ((MsObj *)response)->drop(response);
    CHECK(msstd_client_fetch(client, &post, URL("/post"), table, &sent, 1, 5 * SECOND, &response, &err) == STATUS_OK);
    CHECK(msstd_body_read_all(response, 0, 0, &data, &err) == STATUS_OK && data.len == 3 && memcmp(data.ptr, "abc", 3) == 0);
    ((MsObj *)response)->drop(response);
    CHECK(msstd_client_fetch(client, &get, URL("/redir"), table, &nobody, 1, 5 * SECOND, &response, &err) == STATUS_OK);
    msstd_body_metadata(response, &metadata);
    CHECK(metadata.status == 200); /* the redirect to /a was followed */
    ((MsObj *)metadata.headers)->drop(metadata.headers);
    ((MsObj *)response)->drop(response);
    CHECK(msstd_client_fetch(client, &get, URL("/gz"), table, &nobody, 1, 5 * SECOND, &response, &err) == STATUS_OK);
    CHECK(msstd_body_read_all(response, 0, 0, &data, &err) == STATUS_OK && data.len == 16 && memcmp(data.ptr, "hello gzip world", 16) == 0);
    ((MsObj *)response)->drop(response);
    CHECK(msstd_client_fetch(client, &get, URL("/cookie"), table, &nobody, 1, 5 * SECOND, &response, &err) == STATUS_OK);
    ((MsObj *)response)->drop(response);
    CHECK(msstd_client_fetch(client, &get, URL("/echo"), table, &nobody, 1, 5 * SECOND, &response, &err) == STATUS_OK);
    CHECK(msstd_body_read_all(response, 0, 0, &data, &err) == STATUS_OK && contains(&data, "X-Req: v") && contains(&data, "a=1")); /* the caller's field and the cookie the server set */
    ((MsObj *)response)->drop(response);
    CHECK(msstd_client_fetch(client, &get, URL("/big"), table, &nobody, 1, 10 * SECOND, &response, &err) == STATUS_OK);
    size_t total = 0;
    bool intact = true;
    while (msstd_body_read(response, 0, 0, &data, &err) == STATUS_OK) {
        for (size_t i = 0; i < data.len; i++) intact = intact && ((const uint8_t *)data.ptr)[i] == (uint8_t)((total + i) & 0xff);
        total += data.len;
    }
    CHECK(total == BIG_BYTES && intact); /* streamed through the 256 KiB buffer with the transfer paused and resumed */
    ((MsObj *)response)->drop(response);

    /* refused requests never reach the wire */
    void *refused = msstd_headers_new();
    MsStr host_name = str("host"), split_name = str("X-Split");
    MsVec host_value = bytes("elsewhere"), split_value = bytes("a\r\nInjected: 1");
    CHECK(msstd_headers_append(refused, &host_name, &host_value) == STATUS_OK);
    CHECK(msstd_client_fetch(client, &get, URL("/a"), refused, &nobody, 0, 0, &response, &err) == STATUS_INVALID_INPUT);
    ((MsObj *)refused)->drop(refused);
    refused = msstd_headers_new();
    CHECK(msstd_headers_append(refused, &split_name, &split_value) == STATUS_OK);
    CHECK(msstd_client_fetch(client, &get, URL("/a"), refused, &nobody, 0, 0, &response, &err) == STATUS_INVALID_INPUT);
    ((MsObj *)refused)->drop(refused);
    MsStr bad_method = str("GE T"), not_a_url = str("not a url");
    CHECK(msstd_client_fetch(client, &bad_method, URL("/a"), table, &nobody, 0, 0, &response, &err) == STATUS_INVALID_INPUT);
    CHECK(msstd_client_fetch(client, &get, &not_a_url, table, &nobody, 0, 0, &response, &err) == STATUS_INVALID_INPUT);

    /* a restricted client: a host or CIDR outside its levels is refused before any connection */
    void *narrow = NULL;
    CHECK(msstd_client_new(&http_options, &narrow, &err) == STATUS_OK);
    void *shared = msstd_client_share(narrow); /* a handle on the same client: the same filter */
    MsVec only_hosts, no_cidrs;
    msrt_list_with_capacity(&msrt_desc_string, 1, &only_hosts);
    MsStr allowed_host = str("example.invalid");
    msrt_list_push(&only_hosts, &msrt_desc_string, &allowed_host);
    msrt_list_with_capacity(&msrt_desc_string, 0, &no_cidrs);
    MsVec no_hosts;
    msrt_list_with_capacity(&msrt_desc_string, 0, &no_hosts);
    MsVec bad_cidrs;
    msrt_list_with_capacity(&msrt_desc_string, 1, &bad_cidrs);
    MsStr bad_cidr = str("10.0.0.0/33");
    msrt_list_push(&bad_cidrs, &msrt_desc_string, &bad_cidr);
    CHECK(msstd_client_narrow(narrow, &no_hosts, &bad_cidrs) == STATUS_INVALID_INPUT);
    CHECK(msstd_client_narrow(narrow, &only_hosts, &no_cidrs) == STATUS_OK);
    CHECK(msstd_client_fetch(shared, &get, URL("/a"), table, &nobody, 0, 0, &response, &err) == STATUS_PERMISSION_DENIED);
    ((MsObj *)shared)->drop(shared);
    ((MsObj *)narrow)->drop(narrow);

    /* the last request ends the connection; the pool is gone with the client */
    CHECK(msstd_client_fetch(client, &get, URL("/close"), table, &nobody, 1, 5 * SECOND, &response, &err) == STATUS_OK);
    CHECK(msstd_body_read_all(response, 0, 0, &data, &err) == STATUS_OK && data.len == 3);
    ((MsObj *)response)->drop(response);
    ((MsObj *)client)->drop(client);
    ms_sys_thread_join(thread);
    ms_sys_net_close(server.listener);

    /* the filter's address and redirect checks: 127.0.0.1 inside an allowed range connects, and a redirect to a name
       outside the levels ends the request with the hop never made */
    address = listen_on_loopback(&server);
    host_port = (const char *)msrt_str_data(&address);
    thread = ms_sys_thread_spawn(1 << 20, serve_http, &server);
    CHECK(thread != NULL);
    CHECK(msstd_client_new(&http_options, &client, &err) == STATUS_OK);
    MsVec loopback_cidrs;
    msrt_list_with_capacity(&msrt_desc_string, 1, &loopback_cidrs);
    MsStr loopback_range = str("127.0.0.0/8");
    msrt_list_push(&loopback_cidrs, &msrt_desc_string, &loopback_range);
    CHECK(msstd_client_narrow(client, &no_hosts, &loopback_cidrs) == STATUS_OK);
    CHECK(msstd_client_fetch(client, &get, URL("/a"), table, &nobody, 1, 5 * SECOND, &response, &err) == STATUS_OK);
    ((MsObj *)response)->drop(response);
    CHECK(msstd_client_fetch(client, &get, URL("/hop"), table, &nobody, 1, 5 * SECOND, &response, &err) == STATUS_PERMISSION_DENIED); /* the aborted hop drops the connection */
    ((MsObj *)client)->drop(client);
    ms_sys_thread_join(thread);
    ms_sys_net_close(server.listener);

    /* a Unix socket client reaches a server by path; a narrowed one is refused */
    {
        char path[108];
        snprintf(path, sizeof path, "ms_net_test_%d.sock", (int)current_pid());
        remove_file(path);
        struct sockaddr_un unix_address = {.sun_family = AF_UNIX};
        snprintf(unix_address.sun_path, sizeof unix_address.sun_path, "%s", path);
        const PollHandle listener = (PollHandle)socket(AF_UNIX, SOCK_STREAM, 0);
        CHECK((MsSock)listener != MS_SOCK_INVALID && bind(listener, (struct sockaddr *)&unix_address, sizeof unix_address) == 0 && listen(listener, 4) == 0);
        server.listener = (MsSock)listener;
        server.context = NULL;
        thread = ms_sys_thread_spawn(1 << 20, serve_http, &server);
    CHECK(thread != NULL);
        MsNetHttpOptions unix_options = http_options;
        unix_options.unix_socket = str(path);
        CHECK(msstd_client_new(&unix_options, &client, &err) == STATUS_OK);
        CHECK(msstd_client_fetch(client, &get, URL("/a"), table, &nobody, 1, 5 * SECOND, &response, &err) == STATUS_OK);
        CHECK(msstd_body_read_all(response, 0, 0, &data, &err) == STATUS_OK && data.len > 0);
        ((MsObj *)response)->drop(response);
        void *denied_client = NULL;
        CHECK(msstd_client_new(&unix_options, &denied_client, &err) == STATUS_OK);
        CHECK(msstd_client_narrow(denied_client, &no_hosts, &no_hosts) == STATUS_OK);
        CHECK(msstd_client_fetch(denied_client, &get, URL("/a"), table, &nobody, 1, 5 * SECOND, &response, &err) == STATUS_PERMISSION_DENIED);
        ((MsObj *)denied_client)->drop(denied_client);
        ((MsObj *)client)->drop(client);
        ms_sys_thread_join(thread);
        close_socket(listener);
        remove_file(path);
    }

    /* HTTPS: the client verifies the server against the roots it was given, and the request goes over TLS */
    MsTlsCtx *https_context = ms_tls_ctx_new(1, CERT, sizeof CERT - 1, KEY, sizeof KEY - 1, NULL, 0);
    CHECK(https_context != NULL && ms_tls_ctx_set_alpn(https_context, "http/1.1") == 0);
    server.context = https_context;
    address = listen_on_loopback(&server);
    const char *port_text = strrchr((const char *)msrt_str_data(&address), ':') + 1;
    thread = ms_sys_thread_spawn(1 << 20, serve_http, &server);
    CHECK(thread != NULL);
    MsNetHttpOptions https_options = http_options;
    https_options.roots_pem = str(CERT);
    CHECK(msstd_client_new(&https_options, &client, &err) == STATUS_OK);
    snprintf(url, sizeof url, "https://localhost:%s/a", port_text);
    url_text = str(url);
    CHECK(msstd_client_fetch(client, &get, &url_text, table, &nobody, 1, 10 * SECOND, &response, &err) == STATUS_OK);
    CHECK(msstd_body_read_all(response, 0, 0, &data, &err) == STATUS_OK && data.len == 5);
    ((MsObj *)response)->drop(response);
    ((MsObj *)client)->drop(client);
    ms_sys_thread_join(thread);
    ms_sys_net_close(server.listener);
    server.context = NULL;
    /* without those roots the same server is not trusted */
    address = listen_on_loopback(&server);
    server.context = https_context;
    port_text = strrchr((const char *)msrt_str_data(&address), ':') + 1;
    thread = ms_sys_thread_spawn(1 << 20, serve_http, &server);
    CHECK(thread != NULL);
    CHECK(msstd_client_new(&http_options, &client, &err) == STATUS_OK);
    snprintf(url, sizeof url, "https://localhost:%s/a", port_text);
    url_text = str(url);
    CHECK(msstd_client_fetch(client, &get, &url_text, table, &nobody, 1, 10 * SECOND, &response, &err) == STATUS_FAILED);
    ((MsObj *)client)->drop(client);
    ms_sys_thread_join(thread);
    ms_sys_net_close(server.listener);
    ms_tls_ctx_free(https_context);
    server.context = NULL;


    /* a client with its own resolver: the DNS server gives the address of each hop, and a redirect to a host the filter
       refuses ends the request */
    {
        DnsServer dns = {0};
        MsAddr dns_bind = {4, {127, 0, 0, 1}, 0, 0}, dns_at;
        CHECK(ms_sys_net_udp_bind(&dns_bind, &dns.udp) == MS_SYS_OK && ms_sys_net_local_addr(dns.udp, &dns_at) == MS_SYS_OK);
        char dns_text[MS_NET_ADDR_TEXT_MAX];
        size_t dns_length = 0;
        CHECK(ms_net_addr_format(&dns_at, dns_text, sizeof dns_text, &dns_length));
        MsSysThread *dns_thread = ms_sys_thread_spawn(1 << 20, serve_dns, &dns);
        CHECK(dns_thread != NULL);
        address = listen_on_loopback(&server);
        const char *port = strrchr((const char *)msrt_str_data(&address), ':');
        char named[128];
        snprintf(named, sizeof named, "http://pinned.test%s", port);
        thread = ms_sys_thread_spawn(1 << 20, serve_http, &server);
        CHECK(thread != NULL);
        MsNetHttpOptions pinned_options = http_options;
        pinned_options.resolver = str(dns_text);
        CHECK(msstd_client_new(&pinned_options, &client, &err) == STATUS_OK);
        MsVec pinned_hosts;
        msrt_list_with_capacity(&msrt_desc_string, 1, &pinned_hosts);
        MsStr pinned_name = str("pinned.test");
        msrt_list_push(&pinned_hosts, &msrt_desc_string, &pinned_name);
        CHECK(msstd_client_narrow(client, &pinned_hosts, &no_cidrs) == STATUS_OK);
        char target[160];
        snprintf(target, sizeof target, "%s/a", named);
        MsStr target_text = str(target);
        CHECK(msstd_client_fetch(client, &get, &target_text, table, &nobody, 1, 5 * SECOND, &response, &err) == STATUS_OK);
        CHECK(msstd_body_read_all(response, 0, 0, &data, &err) == STATUS_OK && data.len > 0);
        ((MsObj *)response)->drop(response);
        snprintf(target, sizeof target, "%s/redir", named); /* followed here: the next hop is resolved again */
        target_text = str(target);
        CHECK(msstd_client_fetch(client, &get, &target_text, table, &nobody, 1, 5 * SECOND, &response, &err) == STATUS_OK);
        CHECK(msstd_body_read_all(response, 0, 0, &data, &err) == STATUS_OK && data.len > 0);
        ((MsObj *)response)->drop(response);
        snprintf(target, sizeof target, "%s/hop", named);
        target_text = str(target);
        CHECK(msstd_client_fetch(client, &get, &target_text, table, &nobody, 1, 5 * SECOND, &response, &err) == STATUS_PERMISSION_DENIED);
        ((MsObj *)client)->drop(client);
        ms_sys_thread_join(thread);
        atomic_store(&dns.stop, true);
        ms_sys_thread_join(dns_thread);
        ms_sys_net_close(server.listener);
        ms_sys_net_close(dns.udp);
    }

    /* a deadline covers the wait for the response */
    address = listen_on_loopback(&server);
    host_port = (const char *)msrt_str_data(&address);
    thread = ms_sys_thread_spawn(1 << 20, serve_http, &server);
    CHECK(thread != NULL);
    CHECK(msstd_client_new(&http_options, &client, &err) == STATUS_OK);
    CHECK(msstd_client_fetch(client, &get, URL("/slow"), table, &nobody, 1, 50000000, &response, &err) == STATUS_TIMED_OUT);
    ((MsObj *)client)->drop(client);
    ms_sys_thread_join(thread);
    ms_sys_net_close(server.listener);

    /* closing a client ends the body it has open and refuses later requests */
    address = listen_on_loopback(&server);
    host_port = (const char *)msrt_str_data(&address);
    thread = ms_sys_thread_spawn(1 << 20, serve_http, &server);
    CHECK(thread != NULL);
    CHECK(msstd_client_new(&http_options, &client, &err) == STATUS_OK);
    CHECK(msstd_client_fetch(client, &get, URL("/big"), table, &nobody, 1, 10 * SECOND, &response, &err) == STATUS_OK);
    msstd_client_close(client);
    msstd_client_close(client);
    CHECK(msstd_body_read(response, 0, 0, &data, &err) == STATUS_CLOSED);
    void *refused_response = NULL;
    CHECK(msstd_client_fetch(client, &get, URL("/a"), table, &nobody, 1, 5 * SECOND, &refused_response, &err) == STATUS_CLOSED);
    ((MsObj *)response)->drop(response);
    ((MsObj *)client)->drop(client);
    ms_sys_thread_join(thread);
    ms_sys_net_close(server.listener);
    ((MsObj *)table)->drop(table);
    ms_curl_shutdown();
#undef URL

    /* a listener: accept a client_end connection and move bytes both ways, time out, close */
    {
        MsStr any_port = str("127.0.0.1:0");
        void *socket_listener = NULL;
        CHECK(msstd_net_listen(&any_port, &socket_listener, &err) == STATUS_OK && socket_listener != NULL);
        MsStr listen_address;
        msstd_listener_address(socket_listener, &listen_address);
        CHECK(msrt_str_len(&listen_address) > 0 && !str_is(&listen_address, "127.0.0.1:0"));
        void *server_end = NULL;
        CHECK(msstd_listener_accept(socket_listener, 1, SECOND / 20, &server_end, &err) == STATUS_TIMED_OUT);
        void *client_end = NULL;
        MsStr empty_name = str("");
        CHECK(msstd_net_dial(&listen_address, &empty_name, 0, NULL, 1, 5 * SECOND, &client_end, &err) == STATUS_OK);
        CHECK(msstd_listener_accept(socket_listener, 1, 5 * SECOND, &server_end, &err) == STATUS_OK && server_end != NULL);
        MsVec ping_bytes = bytes("ping");
        MsVec received;
        CHECK(msstd_conn_write_bytes(client_end, &ping_bytes, 1, 5 * SECOND, &err) == STATUS_OK);
        CHECK(msstd_conn_read(server_end, 1, 4, 1, 5 * SECOND, &received, &err) == STATUS_OK && received.len == 4 && memcmp(received.ptr, "ping", 4) == 0);
        MsVec pong_bytes = bytes("pong");
        CHECK(msstd_conn_write_bytes(server_end, &pong_bytes, 1, 5 * SECOND, &err) == STATUS_OK);
        CHECK(msstd_conn_read(client_end, 1, 4, 1, 5 * SECOND, &received, &err) == STATUS_OK && received.len == 4 && memcmp(received.ptr, "pong", 4) == 0);
        msstd_listener_close(socket_listener);
        CHECK(msstd_listener_accept(socket_listener, 1, SECOND / 20, &server_end, &err) == STATUS_CLOSED);
        MsStr busy = str("127.0.0.1:1");
        void *rejected = NULL;
        CHECK(msstd_net_listen(&busy, &rejected, &err) != STATUS_OK || rejected != NULL);
        MsStr garbage = str("not an address");
        CHECK(msstd_net_listen(&garbage, &rejected, &err) == STATUS_INVALID_INPUT);
        msstd_conn_close(client_end);
        msstd_conn_close(server_end);
        ((MsObj *)client_end)->drop(client_end);
        ((MsObj *)server_end)->drop(server_end);
        ((MsObj *)socket_listener)->drop(socket_listener);
    }

    /* scopes: closing one closes what it tracked, in it and in its children, and refuses more */
    {
        MsStr any_port = str("127.0.0.1:0");
        void *scope = msstd_scope_new();
        void *inner = msstd_scope_child(scope);
        void *tracked_listener = NULL;
        CHECK(msstd_net_listen(&any_port, &tracked_listener, &err) == STATUS_OK);
        void *shared_listener = msstd_listener_share(tracked_listener);
        MsStr scope_address;
        msstd_listener_address(tracked_listener, &scope_address);
        void *client_end = NULL, *server_end = NULL;
        MsStr empty_name = str("");
        CHECK(msstd_net_dial(&scope_address, &empty_name, 0, NULL, 1, 5 * SECOND, &client_end, &err) == STATUS_OK);
        CHECK(msstd_listener_accept(shared_listener, 1, 5 * SECOND, &server_end, &err) == STATUS_OK);
        CHECK(msstd_scope_track_listener(scope, tracked_listener) == 1);
        CHECK(msstd_scope_track_conn(inner, server_end) == 1);
        msstd_scope_close(scope);
        MsVec scoped_read;
        CHECK(msstd_listener_accept(shared_listener, 1, SECOND / 20, &(void *){NULL}, &err) == STATUS_CLOSED);
        CHECK(msstd_conn_read(server_end, 1, 4, 1, SECOND / 20, &scoped_read, &err) == STATUS_CLOSED);
        CHECK(msstd_scope_track_conn(scope, client_end) == 0);
        CHECK(msstd_conn_read(client_end, 1, 4, 1, SECOND / 20, &scoped_read, &err) == STATUS_CLOSED);
        ((MsObj *)client_end)->drop(client_end);
        ((MsObj *)server_end)->drop(server_end);
        ((MsObj *)shared_listener)->drop(shared_listener);
        ((MsObj *)tracked_listener)->drop(tracked_listener);
        ((MsObj *)inner)->drop(inner);
        ((MsObj *)scope)->drop(scope);
    }

    ms_tls_ctx_free(context);
    ms_io_close(1);
    fake_rt_free_all();
    puts(failed ? "net_natives_test: FAILED" : "net_natives_test: ok");
    return failed;
}
