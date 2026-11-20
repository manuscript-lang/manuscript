/* An idle-connection server built only from the C runtime pieces: sockets (runtime/sys), one libuv poll handle
 * per connection (runtime/io style), the completion ring, the shared scratch read buffer, connection rows and
 * the HTTP/1 and WebSocket parsers (runtime/net). It answers a keep-alive HTTP request with "hello" and echoes
 * WebSocket text and binary frames, so a client can open thousands of idle connections and measure what each
 * one costs. A measurement probe, not the runtime: one thread, plain TCP, frames must arrive whole.
 *
 * Usage: server <port> <max connections>; prints "ready <pid>" once listening. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>
#include <uv.h>
#include "../../runtime/include/ms_rt/sys_net.h"
#include "../../runtime/io/ring.h"
#include "../../runtime/net/conn.h"
#include "../../runtime/net/ws.h"

enum { HEAD_LIMIT = 8192, FIELD_CAPACITY = 32, SCRATCH_BYTES = 65536 };
#define LISTENER_ID UINT64_MAX

typedef struct {
    uv_loop_t loop;
    MsConnTable *table;
    uv_poll_t *polls; /* owned: one handle per row, indexed like the table, so no per-connection allocation */
    uv_poll_t listener_poll;
    MsSock listener;
    MsIoRing *ring;     /* owned */
    MsIoScratch scratch; /* owned buffer */
} Server;

static Server server;

static uint32_t row_index(MsConnId id) { return (uint32_t)id; }

/* Poll callbacks only record which row is readable; nothing else runs inside libuv. */
static void on_readable(uv_poll_t *handle, int status, int events) {
    (void)events;
    const MsIoEvent event = {
        .id = (uint64_t)(uintptr_t)handle->data,
        .result = status,
        .kind = MS_IO_READ,
    };
    if (!ms_io_ring_push(server.ring, event)) fprintf(stderr, "ring full\n");
}

static void on_closed(uv_handle_t *handle) { (void)handle; }

static void close_connection(MsConnId id) {
    MsConn *conn = ms_conn_get(server.table, id);
    if (conn == NULL) return;
    uv_poll_t *poll = &server.polls[row_index(id)];
    uv_poll_stop(poll);
    uv_close((uv_handle_t *)poll, on_closed);
    ms_sys_net_close(conn->fd);
    ms_conn_close(server.table, id);
}

static void send_all(MsConn *conn, const void *data, size_t length) {
    size_t sent = 0;
    if (ms_sys_net_write(conn->fd, data, length, &sent) != MS_SYS_OK || sent != length) conn->flags |= 1; /* broken */
}

static const MsH1Field *find_field(const MsH1Request *request, const char *base, const char *name) {
    const size_t name_length = strlen(name);
    for (uint32_t i = 0; i < request->nfields; i++) {
        const MsH1Field *field = &request->fields[i];
        if (field->name.len == name_length && strncasecmp(base + field->name.off, name, name_length) == 0) return field;
    }
    return NULL;
}

static void answer_hello(MsConn *conn) {
    char out[128];
    size_t used = 0;
    const char body[] = "hello";
    ms_h1_write_status(out, sizeof out, &used, 1, 200, "OK", 2);
    ms_h1_write_field(out, sizeof out, &used, "Content-Length", 14, "5", 1);
    ms_h1_write_head_end(out, sizeof out, &used);
    memcpy(out + used, body, 5);
    send_all(conn, out, used + 5);
}

static void answer_upgrade(MsConn *conn, const char *base, const MsH1Field *key) {
    char accept[29];
    if (ms_ws_accept_key(base + key->value.off, key->value.len, accept) != 0) {
        conn->flags |= 1;
        return;
    }
    char out[256];
    size_t used = 0;
    ms_h1_write_status(out, sizeof out, &used, 1, 101, "Switching Protocols", 19);
    ms_h1_write_field(out, sizeof out, &used, "Upgrade", 7, "websocket", 9);
    ms_h1_write_field(out, sizeof out, &used, "Connection", 10, "Upgrade", 7);
    ms_h1_write_field(out, sizeof out, &used, "Sec-WebSocket-Accept", 20, accept, 28);
    ms_h1_write_head_end(out, sizeof out, &used);
    send_all(conn, out, used);
    conn->proto = MS_CONN_WS;
}

static void handle_http(MsConn *conn, const uint8_t *data, size_t length) {
    MsH1Field fields[FIELD_CAPACITY];
    MsH1Request request = {.fields = fields};
    const uint8_t *base = NULL;
    size_t available = 0;
    for (;;) {
        const int step = ms_conn_h1_feed(conn, data, length, HEAD_LIMIT, fields, FIELD_CAPACITY, &request, &base, &available);
        if (step == MS_CONN_BAD) {
            conn->flags |= 1;
            return;
        }
        if (step == MS_CONN_NEED_MORE) return;
        const MsH1Field *key = find_field(&request, (const char *)base, "Sec-WebSocket-Key");
        if (key != NULL) answer_upgrade(conn, (const char *)base, key);
        else answer_hello(conn);
        const size_t kept = ms_conn_request_done(conn, base, available, request.head_len);
        if (key != NULL || kept == 0) return; /* a pipelined next request would loop; the probe has none */
        data = NULL;
        length = 0;
    }
}

/* Echoes the frames in data[0..length); a frame split across reads closes the connection (probe limit). */
static void handle_websocket(MsConn *conn, uint8_t *data, size_t length) {
    MsWsState state = {.server = 1};
    size_t offset = 0;
    while (offset < length) {
        MsWsHead head;
        char reason[64];
        if (ms_ws_parse_head(&state, data + offset, length - offset, &head, reason, sizeof reason) != MS_WS_OK) break;
        const size_t payload_at = offset + head.head_len;
        if (head.payload_len > length - payload_at) break;
        uint8_t *payload = data + payload_at;
        if (head.masked) ms_ws_unmask(payload, (size_t)head.payload_len, head.mask, 0);
        ms_ws_after_head(&state, &head);
        uint8_t reply[14];
        if (head.opcode == MS_WS_CLOSE) {
            send_all(conn, reply, ms_ws_write_head(reply, MS_WS_CLOSE, 1, 0, 0, NULL));
            conn->flags |= 1;
            return;
        }
        const uint8_t opcode = head.opcode == MS_WS_PING ? MS_WS_PONG : head.opcode;
        send_all(conn, reply, ms_ws_write_head(reply, opcode, 1, 0, head.payload_len, NULL));
        send_all(conn, payload, (size_t)head.payload_len);
        offset = payload_at + (size_t)head.payload_len;
    }
    if (offset < length) conn->flags |= 1;
}

/* One readable row: read into the shared scratch buffer and hand the bytes to its protocol. */
static void serve_readable(MsConnId id) {
    MsConn *conn = ms_conn_get(server.table, id);
    if (conn == NULL) return;
    size_t got = 0;
    const int status = ms_sys_net_read(conn->fd, server.scratch.data, server.scratch.size, &got);
    if (status == MS_SYS_AGAIN) return;
    if (status != MS_SYS_OK) {
        close_connection(id);
        return;
    }
    if (conn->proto == MS_CONN_WS) handle_websocket(conn, server.scratch.data, got);
    else handle_http(conn, server.scratch.data, got);
    if (conn->flags & 1) close_connection(id);
}

static void accept_all(void) {
    for (;;) {
        MsSock fd = MS_SOCK_INVALID;
        if (ms_sys_net_accept(server.listener, &fd, NULL) != MS_SYS_OK) return;
        const MsConnId id = ms_conn_open(server.table, (int)fd, MS_CONN_HTTP1);
        if (id == 0) {
            ms_sys_net_close(fd);
            continue;
        }
        uv_poll_t *poll = &server.polls[row_index(id)];
        uv_poll_init_socket(&server.loop, poll, (uv_os_sock_t)fd);
        poll->data = (void *)(uintptr_t)id;
        uv_poll_start(poll, UV_READABLE, on_readable);
    }
}

static void drain_ring(void) {
    MsIoEvent event;
    while (ms_io_ring_pop(server.ring, &event)) {
        if (event.id == LISTENER_ID) accept_all();
        else serve_readable(event.id);
    }
}

static void on_listener(uv_poll_t *handle, int status, int events) {
    (void)handle;
    (void)status;
    (void)events;
    const MsIoEvent event = {.id = LISTENER_ID, .result = 0, .kind = MS_IO_ACCEPT};
    ms_io_ring_push(server.ring, event);
}

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s <port> <max connections>\n", argv[0]);
        return 2;
    }
    const uint32_t capacity = (uint32_t)strtoul(argv[2], NULL, 10);
    MsAddr address = {.family = 4, .ip = {127, 0, 0, 1}, .port = (uint16_t)strtoul(argv[1], NULL, 10)};
    server.table = ms_conn_table_new(capacity + 1);
    server.polls = calloc((size_t)capacity + 2, sizeof server.polls[0]);
    server.ring = ms_io_ring_new(2 * capacity + 4);
    if (server.table == NULL || server.polls == NULL || server.ring == NULL) return 1;
    if (!ms_io_scratch_init(&server.scratch, SCRATCH_BYTES)) return 1;
    if (ms_sys_net_tcp_listen(&address, 4096, &server.listener) != MS_SYS_OK) return 1;
    uv_loop_init(&server.loop);
    uv_poll_init_socket(&server.loop, &server.listener_poll, (uv_os_sock_t)server.listener);
    uv_poll_start(&server.listener_poll, UV_READABLE, on_listener);
    printf("ready %d\n", (int)getpid());
    fflush(stdout);
    for (;;) {
        uv_run(&server.loop, UV_RUN_ONCE);
        drain_ring();
    }
}
