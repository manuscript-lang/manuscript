// The same server in C: one epoll loop per core, each with its own listening socket
// (SO_REUSEPORT), keep-alive HTTP/1.1, and the same JSON body built per request.
// Linux only. Build: cc -O2 -pthread -o /tmp/cserver server.c ; run: /tmp/cserver 8084
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/socket.h>
#include <unistd.h>

enum { IN_CAP = 8192 };

struct conn {
    int fd;
    size_t in_len;
    char in[IN_CAP];
    char *out;
    size_t out_len, out_sent;
};

static int port = 8084;
static long spin = 1000000;

static char *append(char *at, const char *text) {
    size_t n = strlen(text);
    memcpy(at, text, n);
    return at + n;
}

static char *append_int(char *at, long value) {
    char digits[24];
    int n = 0;
    if (value == 0) digits[n++] = '0';
    for (; value > 0; value /= 10) digits[n++] = (char)('0' + value % 10);
    while (n > 0) *at++ = digits[--n];
    return at;
}

// Builds the response for `path` into a fresh buffer.
static void respond(struct conn *c, const char *path, size_t path_len) {
    long spun = 0;
    if (path_len >= 5 && memcmp(path, "/slow", 5) == 0) {
        long x = 1;
        for (long i = 0; i < spin; i++) x = (x * 31 + i) % 1000003;
        spun = x;
    }
    int count = path_len >= 4 && memcmp(path, "/big", 4) == 0 ? 4096 : 64;
    char *body = malloc(64 + path_len + (size_t)count * 40);
    char *at = append(body, "{\"path\":\"");
    memcpy(at, path, path_len);
    at = append(at + path_len, "\",\"spun\":");
    at = append(append_int(at, spun), ",\"items\":[");
    for (int i = 0; i < count; i++) {
        if (i > 0) *at++ = ',';
        at = append_int(append(at, "{\"id\":"), i);
        at = append_int(append(at, ",\"name\":\"item-"), i);
        at = append(at, "\"}");
    }
    at = append(at, "]}");
    size_t body_len = (size_t)(at - body);
    c->out = malloc(128 + body_len);
    int head = sprintf(c->out,
                       "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %zu\r\n\r\n",
                       body_len);
    memcpy(c->out + head, body, body_len);
    free(body);
    c->out_len = (size_t)head + body_len;
    c->out_sent = 0;
}

static void drop(int ep, struct conn *c) {
    epoll_ctl(ep, EPOLL_CTL_DEL, c->fd, NULL);
    close(c->fd);
    free(c->out);
    free(c);
}

// Writes what is pending; answers 1 when all of it went out, 0 to wait, -1 on error.
static int flush_out(int ep, struct conn *c) {
    while (c->out_sent < c->out_len) {
        ssize_t n = write(c->fd, c->out + c->out_sent, c->out_len - c->out_sent);
        if (n < 0) {
            if (errno != EAGAIN) return -1;
            struct epoll_event ev = {.events = EPOLLIN | EPOLLOUT, .data.ptr = c};
            epoll_ctl(ep, EPOLL_CTL_MOD, c->fd, &ev);
            return 0;
        }
        c->out_sent += (size_t)n;
    }
    free(c->out);
    c->out = NULL;
    return 1;
}

// Answers every complete request in the input buffer; -1 on error.
static int serve(int ep, struct conn *c) {
    for (;;) {
        char *end = memmem(c->in, c->in_len, "\r\n\r\n", 4);
        if (!end) return c->in_len == IN_CAP ? -1 : 0;
        char *path = memchr(c->in, ' ', (size_t)(end - c->in));
        if (!path) return -1;
        path++;
        char *path_end = memchr(path, ' ', (size_t)(end - path));
        if (!path_end) return -1;
        respond(c, path, (size_t)(path_end - path));
        size_t used = (size_t)(end + 4 - c->in);
        memmove(c->in, c->in + used, c->in_len - used);
        c->in_len -= used;
        int sent = flush_out(ep, c);
        if (sent <= 0) return sent;
    }
}

static void *loop(void *unused) {
    (void)unused;
    int listener = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK, 0);
    int one = 1;
    setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    setsockopt(listener, SOL_SOCKET, SO_REUSEPORT, &one, sizeof one);
    struct sockaddr_in addr = {.sin_family = AF_INET, .sin_port = htons((unsigned short)port)};
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (bind(listener, (struct sockaddr *)&addr, sizeof addr) != 0 || listen(listener, 1024) != 0) {
        perror("listen");
        exit(1);
    }
    int ep = epoll_create1(0);
    struct epoll_event ev = {.events = EPOLLIN, .data.ptr = NULL};
    epoll_ctl(ep, EPOLL_CTL_ADD, listener, &ev);
    struct epoll_event events[64];
    for (;;) {
        int n = epoll_wait(ep, events, 64, -1);
        for (int i = 0; i < n; i++) {
            struct conn *c = events[i].data.ptr;
            if (!c) {
                for (;;) {
                    int fd = accept4(listener, NULL, NULL, SOCK_NONBLOCK);
                    if (fd < 0) break;
                    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
                    struct conn *fresh = calloc(1, sizeof *fresh);
                    fresh->fd = fd;
                    struct epoll_event add = {.events = EPOLLIN, .data.ptr = fresh};
                    epoll_ctl(ep, EPOLL_CTL_ADD, fd, &add);
                }
                continue;
            }
            int ok = 1;
            if (c->out) {
                ok = flush_out(ep, c);
                if (ok == 1) {
                    struct epoll_event mod = {.events = EPOLLIN, .data.ptr = c};
                    epoll_ctl(ep, EPOLL_CTL_MOD, c->fd, &mod);
                    ok = serve(ep, c);
                }
            }
            if (ok >= 0 && !c->out && (events[i].events & EPOLLIN)) {
                ssize_t got = read(c->fd, c->in + c->in_len, IN_CAP - c->in_len);
                if (got == 0 || (got < 0 && errno != EAGAIN)) {
                    ok = -1;
                } else if (got > 0) {
                    c->in_len += (size_t)got;
                    ok = serve(ep, c);
                }
            }
            if (ok < 0 || (events[i].events & (EPOLLHUP | EPOLLERR))) drop(ep, c);
        }
    }
    return NULL;
}

int main(int argc, char **argv) {
    if (argc > 1) port = atoi(argv[1]);
    if (getenv("SPIN")) spin = atol(getenv("SPIN"));
    long cores = sysconf(_SC_NPROCESSORS_ONLN);
    for (long i = 1; i < cores; i++) {
        pthread_t thread;
        pthread_create(&thread, NULL, loop, NULL);
    }
    loop(NULL);
    return 0;
}
