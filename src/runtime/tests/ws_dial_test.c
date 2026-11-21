/* Integration test for src/runtime/net/ws_dial.c over loopback TCP: the upgrade request a server sees, the subprotocol and
 * compression it selects, a message each way, and the ways the handshake is refused. The server is a thread on the
 * connection layer. The task wait is poll(2) (WSAPoll on Windows). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <winsock2.h>
#define poll_sockets(fds, count, ms) WSAPoll((fds), (ULONG)(count), (ms))
typedef WSAPOLLFD PollFd;
typedef SOCKET PollHandle;
#else
#include <poll.h>
#define poll_sockets(fds, count, ms) poll((fds), (nfds_t)(count), (ms))
typedef struct pollfd PollFd;
typedef int PollHandle;
#endif

#include "../net/conn_object.h"
#include "../net/ws.h"
#include "../net/ws_dial.h"
#include "../net/ws_natives.h"
#include "ms_rt/net.h"
#include "../std/abi.h"
#include "ms_rt/alloc.h"
#include "ms_rt/sys.h"
#include "ms_rt/sys_net.h"
#include "ms_sched.h"

static void check(bool ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "ws_dial_test.c:%d: %s\n", line, text);
        abort();
    }
}
#define CHECK(cond) check((cond), __LINE__, #cond)

void ms_sched_cancel_return(void) {}

uint32_t msrt_task_wait_fd(int32_t fd, uint32_t events, int64_t timeout_ns) {
    PollFd p = {.fd = (PollHandle)fd, .events = (short)((events & MS_WAIT_READ ? POLLIN : 0) | (events & MS_WAIT_WRITE ? POLLOUT : 0))};
    const int ms = timeout_ns < 0 ? -1 : (int)(timeout_ns / 1000000 + 1);
    if (poll_sockets(&p, 1, ms) == 0) return MS_WAIT_TIMEOUT;
    return (p.revents & POLLIN ? MS_WAIT_READ : 0) | (p.revents & POLLOUT ? MS_WAIT_WRITE : 0) | (p.revents & (POLLHUP | POLLERR) ? MS_WAIT_HUP : 0);
}

static MsBytes text(const char *s) { return ms_bytes_of((const uint8_t *)s, strlen(s)); }
static bool is(MsBytes bytes, const char *s) { return bytes.len == strlen(s) && memcmp(bytes.ptr, s, bytes.len) == 0; }
static int64_t after_ms(int64_t ms) { return ms_sys_monotonic_ns() + ms * 1000000; }

/* How the server answers: the Sec-WebSocket-Protocol it picks ("" for none) and extra answer fields. */
typedef struct Server {
    MsSock listener;
    const char *select;
    const char *extra;
    char request[4096]; /* what the client sent, for the test to inspect */
    char echoed[64];    /* the text of the client's first frame, unmasked */
} Server;

static void reply(MsConnTable *table, MsConnId id, const char *data, size_t length) {
    (void)ms_conn_write(table, id, (const uint8_t *)data, length, -1);
}

static void serve(void *argument) {
    Server *server = argument;
    MsSock socket = MS_SOCK_INVALID;
    for (;;) {
        if (ms_sys_net_accept(server->listener, &socket, NULL) == MS_SYS_OK) break;
        PollFd p = {.fd = (PollHandle)server->listener, .events = POLLIN};
        (void)poll_sockets(&p, 1, 100);
    }
    MsConnTable *table = ms_conn_table_new(2);
    const MsConnId id = ms_conn_open(table, (int)socket, MS_CONN_WS);
    size_t have = 0, count = 0;
    while (strstr(server->request, "\r\n\r\n") == NULL &&
           ms_conn_read(table, id, (uint8_t *)server->request + have, sizeof server->request - 1 - have, -1, &count) == MS_NET_OK && count > 0) {
        have += count;
        server->request[have] = 0;
    }
    const char *key = strstr(server->request, "Sec-WebSocket-Key: ");
    char accept[29], head[512];
    CHECK(key != NULL && ms_ws_accept_key(key + 19, 24, accept) == 0);
    int length = snprintf(head, sizeof head, "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: %s\r\n%s%s%s%s\r\n",
                          accept, server->select[0] != 0 ? "Sec-WebSocket-Protocol: " : "", server->select, server->select[0] != 0 ? "\r\n" : "", server->extra);
    /* the first frame (a text "hello") follows the head in the same write: the client must not lose it */
    const uint8_t hello[] = {0x81, 5, 'h', 'e', 'l', 'l', 'o'};
    memcpy(head + length, hello, sizeof hello);
    reply(table, id, head, (size_t)length + sizeof hello);
    uint8_t frame[64];
    size_t got = 0;
    while (got < 6 || got < 6 + (size_t)(frame[1] & 0x7f)) {
        if (ms_conn_read(table, id, frame + got, sizeof frame - got, -1, &count) != MS_NET_OK || count == 0) break;
        got += count;
    }
    if (got >= 6) {
        const size_t payload = frame[1] & 0x7f;
        for (size_t i = 0; i < payload; i++) server->echoed[i] = (char)(frame[6 + i] ^ frame[2 + i % 4]);
    }
    (void)ms_conn_close_io(table, id);
    ms_conn_table_free(table);
}

static MsObj *connect_to(Server *server) {
    MsAddr loopback = {4, {127, 0, 0, 1}, 0, 0}, bound;
    CHECK(ms_sys_net_tcp_listen(&loopback, 4, &server->listener) == MS_SYS_OK);
    CHECK(ms_sys_net_local_addr(server->listener, &bound) == MS_SYS_OK);
    MsSock client = MS_SOCK_INVALID;
    const int started = ms_sys_net_tcp_connect(&bound, &client);
    CHECK(started == MS_SYS_OK || started == MS_SYS_INPROGRESS);
    if (started == MS_SYS_INPROGRESS) { /* wait until writable, then confirm */
        PollFd p = {.fd = (PollHandle)client, .events = POLLOUT};
        CHECK(poll_sockets(&p, 1, 5000) == 1 && ms_sys_net_connect_done(client) == MS_SYS_OK);
    }
    MsConnTable *table = ms_conn_table_new(2);
    const MsConnId id = ms_conn_open(table, (int)client, MS_CONN_WS);
    CHECK(id != 0);
    MsObj *conn = ms_netconn_new(table, id);
    CHECK(conn != NULL);
    return conn;
}

static MsWsDial dial_of(const MsBytes *protocols, size_t count, const MsHeaders *headers, bool compression) {
    return (MsWsDial){.authority = text("example.test:8080"), .target = text("/chat?x=1"), .protocols = protocols, .protocol_count = count,
                      .headers = headers, .compression = compression, .max_message_bytes = UINT64_MAX};
}

int main(void) {
    const MsBytes offered[] = {{(const uint8_t *)"chat", 4}, {(const uint8_t *)"other", 5}};
    MsWsMessage message;
    bool ended;
    const char *why = "";

    /* a good handshake: request fields, the selected subprotocol, the frame sent with the head, a message back */
    {
        Server server = {.select = "chat", .extra = ""}; /* the server ignores the offered extension, which is allowed */
        MsObj *conn = connect_to(&server);
        MsSysThread *thread = ms_sys_thread_spawn(1 << 20, serve, &server);
        CHECK(thread != NULL);
        MsHeaders *headers = ms_headers_new();
        CHECK(headers != NULL && ms_headers_add_canonical(headers, text("x-token"), text("abc")));
        const MsWsDial dial = dial_of(offered, 2, headers, true);
        MsWsSocket *session = NULL;
        CHECK(ms_ws_dial(conn, &dial, after_ms(5000), &session, &why) == MS_WSS_OK && session != NULL);
        CHECK(is(ms_ws_socket_subprotocol(session), "chat"));
        CHECK(ms_ws_socket_receive(session, after_ms(5000), &message, &ended) == MS_WSS_OK && message.text && is(message.data, "hello"));
        CHECK(ms_ws_socket_send(session, text("hi"), true, after_ms(5000)) == MS_WSS_OK);
        ms_sys_thread_join(thread);
        CHECK(strstr(server.request, "GET /chat?x=1 HTTP/1.1\r\n") == server.request);
        CHECK(strstr(server.request, "Host: example.test:8080\r\n") != NULL && strstr(server.request, "X-Token: abc\r\n") != NULL);
        CHECK(strstr(server.request, "Sec-WebSocket-Protocol: chat, other\r\n") != NULL);
        CHECK(strstr(server.request, "Sec-WebSocket-Extensions: permessage-deflate; server_no_context_takeover; client_no_context_takeover\r\n") != NULL);
        CHECK(strcmp(server.echoed, "hi") == 0);
        ms_ws_socket_release(session);
        ((MsObj *)conn)->drop(conn);
        ((MsObj *)headers)->drop((MsObj *)headers);
        ms_sys_net_close(server.listener);
    }

    /* the native: the same handshake through msstd_ws_connect, and a field the caller may not set */
    {
        Server server = {.select = "chat", .extra = ""};
        MsObj *conn = connect_to(&server);
        MsSysThread *thread = ms_sys_thread_spawn(1 << 20, serve, &server);
        CHECK(thread != NULL);
        MsStr authority, target, bad, none;
        msrt_string_from_bytes((const uint8_t *)"example.test:8080", 17, &authority);
        msrt_string_from_bytes((const uint8_t *)"/chat?x=1", 9, &target);
        msrt_string_from_bytes((const uint8_t *)"chat", 4, &bad);
        msrt_string_from_bytes(NULL, 0, &none);
        MsVec names;
        msrt_list_with_capacity(&msrt_desc_string, 1, &names);
        msrt_list_push(&names, &msrt_desc_string, &bad);
        void *handle = NULL;
        CHECK(msstd_ws_connect(conn, &authority, &target, NULL, &names, 0, 0, 0, 1, 5000000000, &handle, &none) == STATUS_OK && handle != NULL);
        MsWsSocket *session = ms_ws_handle_socket(handle);
        CHECK(is(ms_ws_socket_subprotocol(session), "chat"));
        /* the SocketH natives over the same session: subprotocol, receive, send, share and close_if_last */
        MsStr chosen;
        msstd_websocket_subprotocol(handle, &chosen);
        CHECK(msrt_str_len(&chosen) == 4 && memcmp(msrt_str_data(&chosen), "chat", 4) == 0);
        msrt_string_free(&chosen);
        MsNetWsMessage received;
        MsStr failure;
        CHECK(msstd_websocket_receive(handle, &received, &failure) == STATUS_OK && received.text == 1 &&
              is(ms_bytes_of(received.data.ptr, received.data.len), "hello"));
        msrt_free(received.data.ptr);
        void *other = msstd_websocket_share(handle);
        CHECK(other != NULL && ms_ws_socket_refs(session) == 2);
        MsVec reply_data;
        msrt_write_bytes(&reply_data, "hi", 2);
        CHECK(msstd_websocket_send_bytes(handle, &reply_data, 1, &failure) == STATUS_OK);
        msrt_free(reply_data.ptr);
        msstd_websocket_close_if_last(other); /* not the last handle: the session stays open */
        CHECK(!ms_ws_socket_is_closed(session));
        ((MsObj *)other)->drop(other);
        ms_sys_thread_join(thread);
        ((MsObj *)handle)->drop(handle);
        ((MsObj *)conn)->drop(conn);
        msrt_string_free(&authority);
        msrt_string_free(&target);
        msrt_list_drop(&names, &msrt_desc_string);
        ms_sys_net_close(server.listener);
    }

    /* a subprotocol that was not offered, and compression the client did not get right, fail the handshake */
    for (int mode = 0; mode < 2; mode++) {
        Server server = {.select = mode == 0 ? "bogus" : "", .extra = mode == 0 ? "" : "Sec-WebSocket-Extensions: permessage-deflate\r\n"};
        MsObj *conn = connect_to(&server);
        MsSysThread *thread = ms_sys_thread_spawn(1 << 20, serve, &server);
        CHECK(thread != NULL);
        const MsWsDial dial = dial_of(offered, 2, NULL, true);
        MsWsSocket *session = NULL;
        CHECK(ms_ws_dial(conn, &dial, after_ms(5000), &session, &why) == MS_WSS_FAILED && session == NULL);
        CHECK(strstr(why, mode == 0 ? "not offered" : "compression") != NULL);
        ((MsObj *)conn)->drop(conn); /* closes the row, which ends the server's wait for a frame */
        ms_sys_thread_join(thread);
        ms_sys_net_close(server.listener);
    }

    /* fields the caller may not set, bad subprotocols and a zero limit are refused before anything is sent */
    {
        Server server = {.select = "", .extra = ""};
        MsObj *conn = connect_to(&server);
        MsWsSocket *session = NULL;
        const char *reserved[] = {"Host", "Upgrade", "connection", "Sec-WebSocket-Key"};
        for (size_t i = 0; i < sizeof reserved / sizeof reserved[0]; i++) {
            MsHeaders *headers = ms_headers_new();
            CHECK(ms_headers_add(headers, text(reserved[i]), text("x")));
            const MsWsDial dial = dial_of(NULL, 0, headers, false);
            CHECK(ms_ws_dial(conn, &dial, after_ms(5000), &session, &why) == MS_WSS_INVALID_INPUT);
            ((MsObj *)headers)->drop((MsObj *)headers);
        }
        const MsBytes bad_protocol[] = {{(const uint8_t *)"a b", 3}};
        MsWsDial dial = dial_of(bad_protocol, 1, NULL, false);
        CHECK(ms_ws_dial(conn, &dial, after_ms(5000), &session, &why) == MS_WSS_INVALID_INPUT);
        dial = dial_of(NULL, 0, NULL, false);
        dial.max_message_bytes = 0;
        CHECK(ms_ws_dial(conn, &dial, after_ms(5000), &session, &why) == MS_WSS_INVALID_INPUT);
        ((MsObj *)conn)->drop(conn);
        ms_sys_net_close(server.listener);
    }

    printf("ws_dial_test: ok\n");
    return 0;
}
