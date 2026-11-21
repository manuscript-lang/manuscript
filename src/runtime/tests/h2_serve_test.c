#define _POSIX_C_SOURCE 200809L
/* Unit tests for src/runtime/net/h2_serve.c over a socket pair: a client thread speaks HTTP/2 to the serve loop, which
   runs on the main thread with the scheduler replaced by test doubles. A handler parks while the request body
   arrives (the park double runs one turn of the connection task, as the scheduler would) and while a response
   larger than the peer's window drains; a reset and the end of the connection are checked as well. */
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#include "../net/h2_serve.h"
#include "ms_rt/sys.h"
#include "ms_sched.h"

static int failed;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failed = 1; } } while (0)
#define S(x) x, sizeof x - 1

/* ---- scheduler doubles ---- */

static MsH2Serve *current_serve;
static uint64_t posted[16];
static uint64_t next_token = 100;

uint32_t msrt_task_wait_fd(int32_t fd, uint32_t events, int64_t timeout_ns) {
    struct pollfd p = {.fd = fd, .events = (short)((events & MS_WAIT_READ ? POLLIN : 0) | (events & MS_WAIT_WRITE ? POLLOUT : 0))};
    const int ms = timeout_ns < 0 ? -1 : (int)(timeout_ns / 1000000 + 1);
    if (poll(&p, 1, ms) == 0) return MS_WAIT_TIMEOUT;
    return (p.revents & POLLIN ? MS_WAIT_READ : 0) | (p.revents & POLLOUT ? MS_WAIT_WRITE : 0) | (p.revents & (POLLHUP | POLLERR) ? MS_WAIT_HUP : 0);
}
uint64_t msrt_token_new(uint32_t flags) { (void)flags; return ++next_token; }
void msrt_token_free(uint64_t token) { for (size_t i = 0; i < 16; i++) if (posted[i] == token) posted[i] = 0; }
void msrt_token_post_remote(uint64_t token, uint64_t value) {
    (void)value;
    for (size_t i = 0; i < 16; i++) if (posted[i] == token) return;
    for (size_t i = 0; i < 16; i++) if (posted[i] == 0) { posted[i] = token; return; }
}
static int take_post(uint64_t token) {
    for (size_t i = 0; i < 16; i++) if (posted[i] == token) { posted[i] = 0; return 1; }
    return 0;
}
/* Parking lets the connection task run: one turn at a time until the token is posted. */
uint32_t msrt_token_park(uint64_t token, int64_t timeout_ns, uint64_t *value) {
    (void)timeout_ns;
    *value = 0;
    while (!take_post(token)) {
        if (ms_h2_serve_step(current_serve) != MS_NET_OK) return take_post(token) ? 0 : MS_WAIT_CANCELLED;
    }
    return 0;
}

/* ---- the client ---- */

typedef struct Client {
    int fd;
    size_t upload;
    size_t got;
    int status, trailer_ok, reset_seen, done;
    unsigned char *received;
} Client;

static void client_write(Client *c, MsH2Conn *h2) {
    unsigned char buf[16384];
    long n;
    while ((n = ms_h2conn_output(h2, buf, sizeof buf)) > 0) {
        long off = 0;
        while (off < n) { ssize_t w = write(c->fd, buf + off, (size_t)(n - off)); if (w <= 0) return; off += w; }
    }
}

static int has_field(const MsH2Head *head, const char *name, const char *value) {
    for (size_t i = 0; i < head->nfields; i++) {
        if (head->fields[i].name.len == strlen(name) && !memcmp(head->fields[i].name.ptr, name, head->fields[i].name.len) &&
            head->fields[i].value.len == strlen(value) && !memcmp(head->fields[i].value.ptr, value, head->fields[i].value.len)) return 1;
    }
    return 0;
}

static void *client_main(void *arg) {
    Client *c = arg;
    MsH2Limits limits = {100, 0, 65535, 65535};
    MsH2Conn *h2 = ms_h2conn_new(0, &limits);
    MsH2Nv post[] = {{S(":method"), S("POST")}, {S(":scheme"), S("https")}, {S(":path"), S("/echo")}, {S(":authority"), S("a.test")}};
    int32_t id = ms_h2conn_open(h2, post, 4, 1);
    unsigned char *payload = malloc(c->upload);
    for (size_t i = 0; i < c->upload; i++) payload[i] = (unsigned char)(i * 7);
    size_t sent = 0;
    int ended = 0;
    unsigned char buf[16384];
    while (!c->done) {
        if (sent < c->upload || !ended) {
            long took = ms_h2conn_send(h2, id, payload + sent, c->upload - sent, 1);
            if (took >= 0) sent += (size_t)took;
            if (sent == c->upload) ended = 1;
        }
        client_write(c, h2);
        struct pollfd p = {.fd = c->fd, .events = POLLIN};
        if (poll(&p, 1, 50) > 0) {
            ssize_t n = read(c->fd, buf, sizeof buf);
            if (n <= 0) break;
            CHECK(ms_h2conn_input(h2, buf, (size_t)n) == n);
        }
        for (;;) {
            long r = ms_h2conn_read(h2, id, buf, sizeof buf);
            if (r <= 0) break;
            c->received = realloc(c->received, c->got + (size_t)r);
            memcpy(c->received + c->got, buf, (size_t)r);
            c->got += (size_t)r;
        }
        const MsH2Head *head = ms_h2conn_head(h2, id);
        if (head) c->status = (int)head->status;
        unsigned state = ms_h2conn_state(h2, id);
        if (state & MS_H2S_ENDED) {
            const MsH2Head *tr = ms_h2conn_trailers(h2, id);
            c->trailer_ok = tr && has_field(tr, "x-bytes", "ok");
            c->done = 1;
        }
        MsH2ConnEvent e;
        while (ms_h2conn_next(h2, &e)) if (e.type == MS_H2C_RESET) c->reset_seen = 1;
        client_write(c, h2);
    }
    free(payload);
    ms_h2conn_release(h2, id, 0);
    client_write(c, h2);
    ms_h2conn_free(h2);
    shutdown(c->fd, SHUT_RDWR);
    return NULL;
}

/* ---- the server ---- */

enum { RESPONSE = 300000 };
static int32_t queued[8];
static size_t queued_count;
static size_t upload_seen;
static int upload_matches = 1;

static void on_request(void *context, MsH2Serve *serve, int32_t stream) {
    (void)context; (void)serve;
    queued[queued_count++] = stream;
}

/* Reads the whole upload (parking until it arrives), then answers with a response bigger than the window. */
static void handle(MsH2Serve *serve, int32_t stream) {
    const MsH2Head *head = ms_h2_stream_head(serve, stream);
    CHECK(head != NULL && head->path.len == 5 && !memcmp(head->path.ptr, "/echo", 5));
    uint8_t buf[4096];
    size_t count = 1;
    while (count > 0) {
        CHECK(ms_h2_stream_read(serve, stream, buf, sizeof buf, -1, &count) == MS_NET_OK);
        for (size_t i = 0; i < count; i++) if (buf[i] != (uint8_t)((upload_seen + i) * 7)) upload_matches = 0;
        upload_seen += count;
    }
    MsH2Nv ok[] = {{S(":status"), S("200")}};
    CHECK(ms_h2_stream_respond(serve, stream, ok, 1, 1) == MS_NET_OK);
    uint8_t *body = malloc(RESPONSE);
    for (size_t i = 0; i < RESPONSE; i++) body[i] = (uint8_t)(i * 3);
    CHECK(ms_h2_stream_write(serve, stream, body, RESPONSE, 0, -1) == MS_NET_OK);
    free(body);
    MsH2Nv tr[] = {{S("x-bytes"), S("ok")}};
    CHECK(ms_h2_stream_trailers_send(serve, stream, tr, 1) == MS_NET_OK);
    ms_h2_serve_release(serve, stream, 0);
}

int main(void) {
    int fds[2];
    CHECK(socketpair(AF_UNIX, SOCK_STREAM, 0, fds) == 0);
    fcntl(fds[0], F_SETFL, fcntl(fds[0], F_GETFL) | O_NONBLOCK);
    Client client = {.fd = fds[1], .upload = 150000};
    pthread_t thread;
    pthread_create(&thread, NULL, client_main, &client);

    MsConnTable *table = ms_conn_table_new(4);
    MsConnId id = ms_conn_open(table, fds[0], MS_CONN_H2);
    MsH2Limits limits = {100, 0, 65535, 65535};
    MsH2ServeHooks hooks = {.on_request = on_request, .idle_ns = 5000000000LL};
    MsH2Serve *serve = ms_h2_serve_new(table, id, ms_h2conn_new(1, &limits), &hooks);
    CHECK(serve != NULL);
    current_serve = serve;
    MsNetStatus status = MS_NET_OK;
    while (status == MS_NET_OK) {
        status = ms_h2_serve_step(serve);
        while (queued_count > 0) handle(serve, queued[--queued_count]);
    }
    CHECK(status == MS_NET_CLOSED);
    CHECK(ms_h2_serve_run(serve) == MS_NET_CLOSED); /* closes the row and frees the serve state */
    pthread_join(thread, NULL);

    CHECK(upload_seen == client.upload && upload_matches);
    CHECK(client.status == 200 && client.got == RESPONSE && client.trailer_ok);
    int body_ok = client.got == RESPONSE;
    for (size_t i = 0; i < client.got && body_ok; i++) body_ok = client.received[i] == (unsigned char)(i * 3);
    CHECK(body_ok);
    CHECK(ms_conn_live(table) == 0);
    free(client.received);
    ms_conn_table_free(table);
    close(fds[1]);
    if (!failed) printf("h2_serve ok\n");
    return failed;
}
