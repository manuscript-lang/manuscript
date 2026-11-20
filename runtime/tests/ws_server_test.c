/* Test for runtime/net/ws_server.c: the server handshake against every way a request can be wrong, the fields and
 * subprotocol of a good answer, and a served session over loopback TCP exchanging a message with a client session.
 * The task wait is poll(2) (WSAPoll on Windows). */
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
#include "../net/headers.h"
#include "../net/ws_natives.h"
#include "../net/ws_server.h"
#include "../net/ws_socket.h"
#include "../std/abi.h"
#include "ms_rt/sys.h"
#include "ms_rt/sys_net.h"
#include "ms_sched.h"

static void check(bool ok, int line, const char *text) {
    if (!ok) {
        fprintf(stderr, "ws_server_test.c:%d: %s\n", line, text);
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
static MsStr str(const char *s) { MsStr out; msrt_string_from_bytes((const uint8_t *)s, strlen(s), &out); return out; }
static bool is_str(const MsStr *s, const char *want) { return msrt_str_len(s) == strlen(want) && memcmp(msrt_str_data(s), want, strlen(want)) == 0; }
static int64_t after_ms(int64_t ms) { return ms_sys_monotonic_ns() + ms * 1000000; }

static const char *SAMPLE_KEY = "dGhlIHNhbXBsZSBub25jZQ==";

static MsHeaders *request(const char *connection, const char *version, const char *key, const char *origin, const char *protocols) {
    MsHeaders *fields = ms_headers_new();
    CHECK(fields != NULL);
    if (connection != NULL) CHECK(ms_headers_add_canonical(fields, text("Connection"), text(connection)));
    CHECK(ms_headers_add_canonical(fields, text("Upgrade"), text("WebSocket")));
    if (version != NULL) CHECK(ms_headers_add_canonical(fields, text("Sec-WebSocket-Version"), text(version)));
    if (key != NULL) CHECK(ms_headers_add_canonical(fields, text("Sec-WebSocket-Key"), text(key)));
    if (origin != NULL) CHECK(ms_headers_add_canonical(fields, text("Origin"), text(origin)));
    if (protocols != NULL) CHECK(ms_headers_add_canonical(fields, text("Sec-WebSocket-Protocol"), text(protocols)));
    return fields;
}

static MsVec list_of(const char *const *items, size_t count) {
    MsVec list;
    msrt_list_with_capacity(&msrt_desc_string, (int64_t)count, &list);
    for (size_t i = 0; i < count; i++) {
        MsStr item = str(items[i]);
        msrt_list_push(&list, &msrt_desc_string, (const uint8_t *)&item);
    }
    return list;
}

/* Runs a handshake; returns the answered status. */
static int64_t handshake(MsHeaders *fields, const char *method, const char *host, bool tls, const char *const *origins, size_t origin_count,
                         const char *const *protocols, size_t protocol_count, MsHeaders **response, MsStr *chosen, MsStr *why) {
    MsStr method_text = str(method), host_text = str(host);
    MsVec allowed = list_of(origins, origin_count), server = list_of(protocols, protocol_count);
    *response = ms_headers_new();
    MsNetWsHandshake answer = {0};
    MsStr err = {0};
    CHECK(msstd_ws_handshake(&method_text, &host_text, tls ? 1 : 0, fields, &allowed, &server, *response, &answer, &err) == STATUS_OK);
    const int64_t status = answer.status;
    *chosen = answer.subprotocol;
    *why = answer.reason;
    msrt_list_drop(&allowed, &msrt_desc_string);
    msrt_list_drop(&server, &msrt_desc_string);
    ms_str_release(&method_text);
    ms_str_release(&host_text);
    return status;
}

static bool same_name(const uint8_t *a, const char *b, size_t n) {
    for (size_t i = 0; i < n; i++) {
        const char x = (char)a[i], y = b[i];
        if ((x >= 'A' && x <= 'Z' ? x + 32 : x) != (y >= 'A' && y <= 'Z' ? y + 32 : y)) return false;
    }
    return true;
}

static bool has_field(const MsHeaders *fields, const char *name, const char *value) {
    for (size_t i = 0; i < ms_headers_count(fields); i++) {
        MsBytes n, v;
        ms_headers_field(fields, i, &n, &v);
        if (n.len == strlen(name) && same_name(n.ptr, name, n.len) && v.len == strlen(value) && memcmp(v.ptr, value, v.len) == 0) return true;
    }
    return false;
}

static void drop_headers(MsHeaders *fields) { ((MsObj *)fields)->drop((MsObj *)fields); }

/* Every case: the request, what it should answer, and the text. */
static void expect(MsHeaders *fields, const char *method, const char *host, const char *const *origins, size_t origin_count, int64_t want, const char *text_want) {
    MsHeaders *response;
    MsStr chosen, why;
    CHECK(handshake(fields, method, host, false, origins, origin_count, NULL, 0, &response, &chosen, &why) == want);
    if (text_want != NULL) CHECK(is_str(&why, text_want));
    drop_headers(fields);
    drop_headers(response);
    ms_str_release(&chosen);
    ms_str_release(&why);
}

int main(void) {
    /* a good request: the RFC's sample key, a subprotocol picked in the server's order */
    {
        const char *protocols[] = {"superchat", "chat"};
        MsHeaders *fields = request("keep-alive, Upgrade", "13", SAMPLE_KEY, NULL, "chat, superchat");
        MsHeaders *response;
        MsStr chosen, why;
        CHECK(handshake(fields, "GET", "example.test", false, NULL, 0, protocols, 2, &response, &chosen, &why) == 101);
        CHECK(is_str(&chosen, "superchat"));
        CHECK(has_field(response, "Sec-WebSocket-Accept", "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="));
        CHECK(has_field(response, "Upgrade", "websocket") && has_field(response, "Connection", "Upgrade"));
        CHECK(has_field(response, "Sec-WebSocket-Protocol", "superchat"));
        drop_headers(fields);
        drop_headers(response);
        ms_str_release(&chosen);
        ms_str_release(&why);
    }

    /* none of the offered subprotocols is spoken: none is selected */
    {
        const char *protocols[] = {"other"};
        MsHeaders *fields = request("Upgrade", "13", SAMPLE_KEY, NULL, "chat");
        MsHeaders *response;
        MsStr chosen, why;
        CHECK(handshake(fields, "GET", "h", false, NULL, 0, protocols, 1, &response, &chosen, &why) == 101 && msrt_str_len(&chosen) == 0);
        CHECK(!has_field(response, "Sec-WebSocket-Protocol", "other"));
        drop_headers(fields);
        drop_headers(response);
        ms_str_release(&chosen);
        ms_str_release(&why);
    }

    /* the ways to be refused, in the order they are checked */
    expect(request(NULL, "13", SAMPLE_KEY, NULL, NULL), "GET", "h", NULL, 0, 400, "websocket: 'Connection' header lacks the 'upgrade' token");
    expect(request("close", "13", SAMPLE_KEY, NULL, NULL), "GET", "h", NULL, 0, 400, NULL);
    expect(request("Upgrade", "13", SAMPLE_KEY, NULL, NULL), "POST", "h", NULL, 0, 405, "websocket: upgrade method is not GET");
    expect(request("Upgrade", NULL, SAMPLE_KEY, NULL, NULL), "GET", "h", NULL, 0, 400, NULL);
    expect(request("Upgrade", "8", SAMPLE_KEY, NULL, NULL), "GET", "h", NULL, 0, 426, "websocket: 'Sec-WebSocket-Version' header must include 13");
    expect(request("Upgrade", "13", NULL, NULL, NULL), "GET", "h", NULL, 0, 400, NULL);
    expect(request("Upgrade", "13", "not-a-key", NULL, NULL), "GET", "h", NULL, 0, 400, NULL);
    expect(request("Upgrade", "13", "dGhlIHNhbXBsZSBub25jZR==", NULL, NULL), "GET", "h", NULL, 0, 400, NULL); /* stray bits */

    /* two keys: two parsers could read two */
    {
        MsHeaders *fields = request("Upgrade", "13", SAMPLE_KEY, NULL, NULL);
        CHECK(ms_headers_add_canonical(fields, text("Sec-WebSocket-Key"), text(SAMPLE_KEY)));
        expect(fields, "GET", "h", NULL, 0, 400, NULL);
    }

    /* origins: same origin by default, a listed one, and the shapes that are never allowed */
    expect(request("Upgrade", "13", SAMPLE_KEY, "http://Example.test:8080", NULL), "GET", "example.test:8080", NULL, 0, 101, NULL);
    expect(request("Upgrade", "13", SAMPLE_KEY, "https://example.test:8080", NULL), "GET", "example.test:8080", NULL, 0, 403, "websocket: request origin not allowed"); /* another scheme */
    expect(request("Upgrade", "13", SAMPLE_KEY, "http://other.test", NULL), "GET", "example.test", NULL, 0, 403, NULL);
    expect(request("Upgrade", "13", SAMPLE_KEY, "http://user@example.test", NULL), "GET", "example.test", NULL, 0, 403, NULL);
    expect(request("Upgrade", "13", SAMPLE_KEY, "http://example.test/path", NULL), "GET", "example.test", NULL, 0, 403, NULL);
    expect(request("Upgrade", "13", SAMPLE_KEY, "null", NULL), "GET", "example.test", NULL, 0, 403, NULL);
    {
        const char *allowed[] = {"https://app.test"};
        expect(request("Upgrade", "13", SAMPLE_KEY, "https://app.test", NULL), "GET", "example.test", allowed, 1, 101, NULL);
        expect(request("Upgrade", "13", SAMPLE_KEY, "http://example.test", NULL), "GET", "example.test", allowed, 1, 403, NULL); /* a list replaces same-origin */
    }

    /* a subprotocol that is not a token is refused before anything is read */
    {
        MsHeaders *fields = request("Upgrade", "13", SAMPLE_KEY, NULL, NULL), *response = ms_headers_new();
        const char *bad[] = {"a b"};
        MsStr method = str("GET"), host = str("h"), why;
        MsVec none = list_of(NULL, 0), protocols = list_of(bad, 1);
        MsNetWsHandshake answer = {0};
        CHECK(msstd_ws_handshake(&method, &host, 0, fields, &none, &protocols, response, &answer, &why) == STATUS_INVALID_INPUT);
        msrt_list_drop(&none, &msrt_desc_string);
        msrt_list_drop(&protocols, &msrt_desc_string);
        ms_str_release(&method);
        ms_str_release(&host);
        drop_headers(fields);
        drop_headers(response);
    }

    /* a served session talks to a client session over loopback */
    {
        MsAddr loopback = {4, {127, 0, 0, 1}, 0, 0}, bound;
        MsSock listener = MS_SOCK_INVALID, client_fd = MS_SOCK_INVALID, server_fd = MS_SOCK_INVALID;
        CHECK(ms_sys_net_tcp_listen(&loopback, 4, &listener) == MS_SYS_OK && ms_sys_net_local_addr(listener, &bound) == MS_SYS_OK);
        const int started = ms_sys_net_tcp_connect(&bound, &client_fd);
        CHECK(started == MS_SYS_OK || started == MS_SYS_INPROGRESS);
        for (int i = 0; i < 50 && server_fd == MS_SOCK_INVALID; i++) {
            if (ms_sys_net_accept(listener, &server_fd, NULL) != MS_SYS_OK) {
                PollFd p = {.fd = (PollHandle)listener, .events = POLLIN};
                poll_sockets(&p, 1, 100);
            }
        }
        CHECK(server_fd != MS_SOCK_INVALID);
        if (started == MS_SYS_INPROGRESS) {
            PollFd p = {.fd = (PollHandle)client_fd, .events = POLLOUT};
            CHECK(poll_sockets(&p, 1, 5000) == 1 && ms_sys_net_connect_done(client_fd) == MS_SYS_OK);
        }
        MsConnTable *client_table = ms_conn_table_new(1), *server_table = ms_conn_table_new(1);
        MsObj *client_conn = ms_netconn_new(client_table, ms_conn_open(client_table, (int)client_fd, MS_CONN_WS));
        MsObj *server_conn = ms_netconn_new(server_table, ms_conn_open(server_table, (int)server_fd, MS_CONN_WS));
        CHECK(client_conn != NULL && server_conn != NULL);

        MsStr chat = str("chat"), why = str("");
        void *served = NULL;
        CHECK(msstd_ws_serve(server_conn, &chat, 1, 0, &served, &why) == STATUS_INVALID_INPUT); /* a limit of 0 */
        CHECK(msstd_ws_serve(server_conn, &chat, 1, 1 << 20, &served, &why) == STATUS_OK && served != NULL);
        CHECK(memcmp(ms_ws_socket_subprotocol(ms_ws_handle_socket(served)).ptr, "chat", 4) == 0);
        const MsWsConfig config = {.max_message_bytes = UINT64_MAX, .compress = false, .subprotocol = ms_bytes_of(NULL, 0)};
        MsWsSocket *client = ms_ws_socket_new(ms_netconn_alias(client_conn), MS_WS_ROLE_CLIENT, &config);
        CHECK(client != NULL);

        MsWsMessage message;
        bool ended = false;
        CHECK(ms_ws_socket_send(client, text("hello"), true, after_ms(5000)) == MS_WSS_OK);
        CHECK(ms_ws_socket_receive(ms_ws_handle_socket(served), after_ms(5000), &message, &ended) == MS_WSS_OK && message.text && message.data.len == 5 && memcmp(message.data.ptr, "hello", 5) == 0);
        CHECK(ms_ws_socket_send(ms_ws_handle_socket(served), text("back"), false, after_ms(5000)) == MS_WSS_OK);
        CHECK(ms_ws_socket_receive(client, after_ms(5000), &message, &ended) == MS_WSS_OK && !message.text && message.data.len == 4 && memcmp(message.data.ptr, "back", 4) == 0);

        ms_ws_socket_release(client);
        ((MsObj *)served)->drop(served);
        ((MsObj *)server_conn)->drop(server_conn);
        ((MsObj *)client_conn)->drop(client_conn);
        ms_sys_net_close(listener);
        ms_str_release(&chat);
        ms_str_release(&why);
    }

    puts("ws_server_test: ok");
    return 0;
}
