#define _POSIX_C_SOURCE 200809L
/* Unit test for runtime/net/ws_natives.c: the SocketH handle calls (send, receive, ping, share, close_if_last,
 * subprotocol), msstd_ws_server_new over a connection, and the accept key, on a socketpair. */
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>

#include "../net/ws_natives.h"
#include "../std/abi.h"
#include "ms_rt/alloc.h"
#include "ms_rt/websocket.h"
#include "ms_sched.h"

static void check(bool ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "ws_natives_test.c:%d: %s\n", line, text);
        abort();
    }
}
#define CHECK(cond) check((cond), __LINE__, #cond)

void ms_sched_cancel_return(void) {} /* no scheduler here, so nothing ends a call */

uint32_t msrt_task_wait_fd(int32_t fd, uint32_t events, int64_t timeout_ns) {
    struct pollfd p = {.fd = fd, .events = (short)((events & MS_WAIT_READ ? POLLIN : 0) | (events & MS_WAIT_WRITE ? POLLOUT : 0))};
    const int ms = timeout_ns < 0 ? -1 : (int)(timeout_ns / 1000000 + 1);
    const int r = poll(&p, 1, ms);
    if (r == 0) return MS_WAIT_TIMEOUT;
    return (p.revents & POLLIN ? MS_WAIT_READ : 0) | (p.revents & POLLOUT ? MS_WAIT_WRITE : 0) | (p.revents & (POLLHUP | POLLERR) ? MS_WAIT_HUP : 0);
}

static MsStr string_of(const char *text) {
    MsStr s;
    msrt_string_from_bytes((const uint8_t *)text, strlen(text), &s);
    return s;
}

static MsVec bytes_of_text(const char *text) {
    MsVec v;
    msrt_write_bytes(&v, text, strlen(text));
    return v;
}

static bool vec_is(const MsVec *v, const char *text) { return v->len == strlen(text) && memcmp(v->ptr, text, v->len) == 0; }

static MsObj *connection(int fd) {
    CHECK(fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) == 0);
    MsConnTable *table = ms_conn_table_new(2);
    const MsConnId id = ms_conn_open(table, fd, MS_CONN_WS);
    CHECK(id != 0);
    return ms_netconn_new(table, id);
}

static void test_session(void) {
    int fds[2];
    CHECK(socketpair(AF_UNIX, SOCK_STREAM, 0, fds) == 0);
    const MsWsConfig config = {.max_message_bytes = UINT64_MAX, .subprotocol = ms_bytes_of((const uint8_t *)"echo", 4)};
    MsObj *client = ms_ws_handle_new(ms_ws_socket_new(connection(fds[0]), MS_WS_ROLE_CLIENT, &config));
    CHECK(client != NULL);
    MsObj *server_conn = connection(fds[1]);
    void *server = NULL;
    MsStr err = {0};
    MsStr echo = string_of("echo");
    CHECK(msstd_ws_server_new(server_conn, 0, &echo, 0, 0, &server, &err) == STATUS_OK && server != NULL);
    CHECK(msstd_ws_server_new(server_conn, 0, &echo, 1, 0, &server, &err) == STATUS_INVALID_INPUT);
    server_conn->drop(server_conn); /* the session keeps the connection alive */

    MsStr name;
    msstd_websocket_subprotocol(server, &name);
    CHECK(msrt_str_len(&name) == 4 && memcmp(msrt_str_data(&name), "echo", 4) == 0);
    msrt_string_free(&name);

    MsVec hello = bytes_of_text("hello");
    CHECK(msstd_websocket_send_bytes(client, &hello, 1, &err) == STATUS_OK);
    MsWebSocketMessage message;
    CHECK(msstd_websocket_receive(server, &message, &err) == STATUS_OK && message.text == 1 && vec_is(&message.data, "hello"));
    msrt_free(message.data.ptr);

    MsStr beat = string_of("beat");
    CHECK(msstd_websocket_ping(client, &beat, &err) == STATUS_OK);
    CHECK(msstd_websocket_send_bytes(client, &hello, 0, &err) == STATUS_OK);
    CHECK(msstd_websocket_receive(server, &message, &err) == STATUS_OK && message.text == 0);
    msrt_free(message.data.ptr);

    MsVec bad = bytes_of_text("\xff");
    CHECK(msstd_websocket_send_bytes(client, &bad, 1, &err) == STATUS_INVALID_DATA);

    /* a shared handle keeps the session open when the first is closed if last */
    void *second = msstd_websocket_share(client);
    msstd_websocket_close_if_last(client);
    CHECK(msstd_websocket_send_bytes(second, &hello, 1, &err) == STATUS_OK);
    ((MsObj *)client)->drop(client);
    msstd_websocket_close_if_last(second);
    CHECK(msstd_websocket_send_bytes(second, &hello, 1, &err) == STATUS_CLOSED);
    ((MsObj *)second)->drop(second);

    /* the server read the message sent before, then the peer's normal close ends the stream */
    CHECK(msstd_websocket_receive(server, &message, &err) == STATUS_OK && vec_is(&message.data, "hello"));
    msrt_free(message.data.ptr);
    CHECK(msstd_websocket_receive(server, &message, &err) == STATUS_NONE);
    ((MsObj *)server)->drop(server);
    msrt_string_free(&echo);
    msrt_string_free(&beat);
    msrt_free(hello.ptr);
    msrt_free(bad.ptr);
}

static void test_accept_key(void) {
    MsStr key = string_of("dGhlIHNhbXBsZSBub25jZQ==");
    MsStr accept;
    CHECK(msstd_ws_accept_key(&key, &accept) == STATUS_OK);
    CHECK(msrt_str_len(&accept) == 28 && memcmp(msrt_str_data(&accept), "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", 28) == 0);
    msrt_string_free(&accept);
    msrt_string_free(&key);
}

int main(void) {
    test_session();
    test_accept_key();
    puts("ws_natives_test: ok");
    return 0;
}
