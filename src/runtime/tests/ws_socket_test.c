#define _POSIX_C_SOURCE 200809L
/* Unit test for src/runtime/net/ws_socket.c over a socketpair: messages both ways, pings, the message limit, text
 * validation, a timed-out receive that resumes, the peer's close, the close handshake, and compression. One thread and
 * no scheduler, so the task wait is poll(2) and each side's writes fit the socket buffer. */
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#include "../net/ws_natives.h"
#include "../net/ws_socket.h"
#include "ms_rt/sys.h"
#include "ms_sched.h"

static void check(bool ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "ws_socket_test.c:%d: %s\n", line, text);
        abort();
    }
}
#define CHECK(cond) check((cond), __LINE__, #cond)

uint32_t msrt_task_wait_fd(int32_t fd, uint32_t events, int64_t timeout_ns) {
    struct pollfd p = {.fd = fd, .events = (short)((events & MS_WAIT_READ ? POLLIN : 0) | (events & MS_WAIT_WRITE ? POLLOUT : 0))};
    const int ms = timeout_ns < 0 ? -1 : (int)(timeout_ns / 1000000 + 1);
    const int r = poll(&p, 1, ms);
    if (r == 0) return MS_WAIT_TIMEOUT;
    return (p.revents & POLLIN ? MS_WAIT_READ : 0) | (p.revents & POLLOUT ? MS_WAIT_WRITE : 0) | (p.revents & (POLLHUP | POLLERR) ? MS_WAIT_HUP : 0);
}

static MsBytes text(const char *s) { return ms_bytes_of((const uint8_t *)s, strlen(s)); }
static bool is(MsBytes bytes, const char *s) { return bytes.len == strlen(s) && memcmp(bytes.ptr, s, bytes.len) == 0; }
static int64_t after_ms(int64_t ms) { return ms_sys_monotonic_ns() + ms * 1000000; }

typedef struct Pair {
    MsWsSocket *client, *server;
    int client_fd, server_fd;
} Pair;

static MsWsSocket *session(int fd, MsWsRole role, bool compress, uint64_t limit) {
    CHECK(fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) == 0); /* the connection layer waits on EAGAIN */
    MsConnTable *table = ms_conn_table_new(2);
    const MsConnId id = ms_conn_open(table, fd, MS_CONN_WS);
    CHECK(id != 0);
    MsObj *conn = ms_netconn_new(table, id);
    const MsWsConfig config = {.max_message_bytes = limit, .compress = compress, .subprotocol = text("echo")};
    MsWsSocket *s = ms_ws_socket_new(conn, role, &config);
    CHECK(s != NULL);
    return s;
}

static Pair open_pair(bool compress, uint64_t server_limit) {
    int fds[2];
    CHECK(socketpair(AF_UNIX, SOCK_STREAM, 0, fds) == 0);
    return (Pair){session(fds[0], MS_WS_ROLE_CLIENT, compress, UINT64_MAX), session(fds[1], MS_WS_ROLE_SERVER, compress, server_limit), fds[0], fds[1]};
}

static void close_pair(Pair *p) {
    ms_ws_socket_release(p->client);
    ms_ws_socket_release(p->server);
}

static MsWsStatus receive(MsWsSocket *s, int64_t deadline, MsWsMessage *m, bool *ended) { return ms_ws_socket_receive(s, deadline, m, ended); }

static void test_echo_both_ways(void) {
    Pair p = open_pair(false, UINT64_MAX);
    MsWsMessage m;
    bool ended;
    CHECK(is(ms_ws_socket_subprotocol(p.client), "echo"));
    CHECK(ms_ws_socket_send(p.client, text("h\xc3\xa9llo"), true, -1) == MS_WSS_OK);
    CHECK(receive(p.server, after_ms(2000), &m, &ended) == MS_WSS_OK && m.text && is(m.data, "h\xc3\xa9llo"));
    const uint8_t binary[] = {0xff, 0x00};
    CHECK(ms_ws_socket_send(p.server, ms_bytes_of(binary, 2), false, -1) == MS_WSS_OK);
    CHECK(receive(p.client, after_ms(2000), &m, &ended) == MS_WSS_OK && !m.text && m.data.len == 2 && m.data.ptr[0] == 0xff);
    CHECK(ms_ws_socket_send(p.client, text(""), true, -1) == MS_WSS_OK);
    CHECK(receive(p.server, after_ms(2000), &m, &ended) == MS_WSS_OK && m.text && m.data.len == 0);
    close_pair(&p);
}

static void test_ping_is_answered(void) {
    Pair p = open_pair(false, UINT64_MAX);
    MsWsMessage m;
    bool ended;
    CHECK(ms_ws_socket_ping(p.client, text("beat")) == MS_WSS_OK);
    CHECK(ms_ws_socket_send(p.client, text("after"), true, -1) == MS_WSS_OK);
    /* the server answers the ping while it waits for the message; the client then drops the pong */
    CHECK(receive(p.server, after_ms(2000), &m, &ended) == MS_WSS_OK && is(m.data, "after"));
    CHECK(ms_ws_socket_send(p.server, text("back"), true, -1) == MS_WSS_OK);
    CHECK(receive(p.client, after_ms(2000), &m, &ended) == MS_WSS_OK && is(m.data, "back"));
    uint8_t big[126] = {0};
    CHECK(ms_ws_socket_ping(p.client, ms_bytes_of(big, sizeof big)) == MS_WSS_INVALID_INPUT);
    close_pair(&p);
}

static void test_limits_and_validation(void) {
    Pair p = open_pair(false, 4);
    MsWsMessage m;
    bool ended;
    CHECK(ms_ws_socket_send(p.server, text("12345"), true, -1) == MS_WSS_LIMIT);
    CHECK(ms_ws_socket_send(p.client, text("\xff"), true, -1) == MS_WSS_INVALID_DATA);
    CHECK(ms_ws_socket_send(p.client, text("12345"), true, -1) == MS_WSS_OK);
    CHECK(receive(p.server, after_ms(2000), &m, &ended) == MS_WSS_LIMIT);
    CHECK(ms_ws_socket_is_closed(p.server));
    CHECK(receive(p.server, after_ms(10), &m, &ended) == MS_WSS_CLOSED);
    /* the client sees the close 1009 the server replied with */
    CHECK(receive(p.client, after_ms(2000), &m, &ended) == MS_WSS_FAILED);
    CHECK(!strcmp(ms_ws_socket_error(p.client), "websocket: close 1009 (message too big)"));
    close_pair(&p);
}

static void test_timeout_resumes(void) {
    Pair p = open_pair(false, UINT64_MAX);
    MsWsMessage m;
    bool ended;
    CHECK(receive(p.server, after_ms(20), &m, &ended) == MS_WSS_TIMEOUT);
    CHECK(!ms_ws_socket_is_closed(p.server));
    /* half a frame, then a timeout, then the rest */
    const uint8_t frame[] = {0x81, 0x85, 1, 2, 3, 4, 'H' ^ 1, 'e' ^ 2, 'l' ^ 3, 'l' ^ 4, 'o' ^ 1};
    CHECK(write(p.client_fd, frame, 4) == 4);
    CHECK(receive(p.server, after_ms(20), &m, &ended) == MS_WSS_TIMEOUT);
    CHECK(write(p.client_fd, frame + 4, sizeof frame - 4) == (ssize_t)(sizeof frame - 4));
    CHECK(receive(p.server, after_ms(2000), &m, &ended) == MS_WSS_OK && is(m.data, "Hello"));
    close_pair(&p);
}

static void test_peer_close(void) {
    Pair p = open_pair(false, UINT64_MAX);
    MsWsMessage m;
    bool ended;
    ms_ws_socket_close(p.client);
    CHECK(ms_ws_socket_is_closed(p.client));
    CHECK(ms_ws_socket_send(p.client, text("x"), true, -1) == MS_WSS_CLOSED);
    CHECK(receive(p.server, after_ms(2000), &m, &ended) == MS_WSS_OK && ended);
    CHECK(receive(p.server, after_ms(10), &m, &ended) == MS_WSS_CLOSED);
    close_pair(&p);

    /* a stream that ends without a close frame is an abnormal closure */
    p = open_pair(false, UINT64_MAX);
    CHECK(close(p.client_fd) == 0);
    p.client_fd = -1;
    CHECK(receive(p.server, after_ms(2000), &m, &ended) == MS_WSS_FAILED);
    CHECK(!strcmp(ms_ws_socket_error(p.server), "websocket: close 1006 (abnormal closure): unexpected EOF"));
    ms_ws_socket_release(p.server);
    ms_ws_socket_release(p.client);
}

static void test_close_handshake(void) {
    Pair p = open_pair(false, UINT64_MAX);
    /* the peer's close frame is already on the wire, behind a message the handshake discards */
    const uint8_t close_frame[] = {0x88, 0x02, 0x03, 0xe8};
    CHECK(ms_ws_socket_send(p.server, text("discarded"), true, -1) == MS_WSS_OK);
    CHECK(write(p.server_fd, close_frame, sizeof close_frame) == (ssize_t)sizeof close_frame);
    CHECK(ms_ws_socket_close_handshake(p.client, 1000, text("bye"), after_ms(2000)) == MS_WSS_OK);
    CHECK(ms_ws_socket_is_closed(p.client));
    close_pair(&p);
}

static void test_compression(void) {
    Pair p = open_pair(true, UINT64_MAX);
    char body[3000];
    memset(body, 'z', sizeof body);
    MsWsMessage m;
    bool ended;
    CHECK(ms_ws_socket_send(p.client, ms_bytes_of((const uint8_t *)body, sizeof body), true, -1) == MS_WSS_OK);
    CHECK(receive(p.server, after_ms(2000), &m, &ended) == MS_WSS_OK && m.text && m.data.len == sizeof body && memcmp(m.data.ptr, body, sizeof body) == 0);
    close_pair(&p);
}

static void test_refs(void) {
    Pair p = open_pair(false, UINT64_MAX);
    MsWsSocket *second = ms_ws_socket_retain(p.client);
    CHECK(ms_ws_socket_refs(p.client) == 2);
    ms_ws_socket_release(second);
    CHECK(ms_ws_socket_refs(p.client) == 1);
    close_pair(&p);
}

static void test_handle(void) {
    Pair p = open_pair(false, UINT64_MAX);
    MsObj *handle = ms_ws_handle_new(ms_ws_socket_retain(p.client));
    CHECK(handle != NULL && ms_ws_handle_socket(handle) == p.client && ms_ws_socket_refs(p.client) == 2);
    handle->drop(handle);
    CHECK(ms_ws_socket_refs(p.client) == 1);
    close_pair(&p);
}

int main(void) {
    test_echo_both_ways();
    test_ping_is_answered();
    test_limits_and_validation();
    test_timeout_resumes();
    test_peer_close();
    test_close_handshake();
    test_compression();
    test_refs();
    test_handle();
    puts("ws_socket_test: ok");
    return 0;
}
