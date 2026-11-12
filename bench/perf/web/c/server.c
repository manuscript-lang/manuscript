// Hand-written epoll HTTP/1.1 server: the C ceiling for the web benchmark.
// server <port> <data-dir> [threads]; data-dir is ignored and only matches the other servers'
// argv. One epoll loop per thread, SO_REUSEPORT listeners, level-triggered
// reads, one read and one write per request. Serves /health and /user/<id> like ms/ and go/.
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/socket.h>
#include <unistd.h>

static int port;

static int listener(void) {
	int fd = socket(AF_INET, SOCK_STREAM | SOCK_NONBLOCK, 0), one = 1;
	setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &one, sizeof one);
	setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
	struct sockaddr_in a = {.sin_family = AF_INET, .sin_port = htons(port)};
	if (bind(fd, (void *)&a, sizeof a) || listen(fd, 4096)) { perror("bind"); exit(1); }
	return fd;
}

static int reply(char *out, int status, const char *body, int n) {
	return sprintf(out, "HTTP/1.1 %d %s\r\nContent-Length: %d\r\n\r\n%.*s", status,
		status == 200 ? "OK" : "Not Found", n, n, body);
}

static int handle(char *req, int len, char *out) {
	char body[128];
	if (len < 14 || memcmp(req, "GET ", 4)) return reply(out, 404, "not found\n", 10);
	if (!memcmp(req + 4, "/health ", 8)) return reply(out, 200, "ok\n", 3);
	if (!memcmp(req + 4, "/user/", 6)) {
		int id = atoi(req + 10);
		int n = sprintf(body, "{\"id\":%d,\"name\":\"user%d\",\"score\":%d}\n", id, id, id * 7919 % 1000);
		return reply(out, 200, body, n);
	}
	return reply(out, 404, "not found\n", 10);
}

typedef struct { int fd, len; char buf[4096]; } conn;

static void *run(void *arg) {
	int lfd = listener(), ep = epoll_create1(0);
	struct epoll_event ev = {.events = EPOLLIN, .data.ptr = NULL}, evs[256];
	epoll_ctl(ep, EPOLL_CTL_ADD, lfd, &ev);
	char out[512];
	for (;;) {
		int n = epoll_wait(ep, evs, 256, -1);
		for (int i = 0; i < n; i++) {
			conn *c = evs[i].data.ptr;
			if (!c) {
				for (;;) {
					int fd = accept4(lfd, NULL, NULL, SOCK_NONBLOCK), one = 1;
					if (fd < 0) break;
					setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
					conn *nc = calloc(1, sizeof *nc);
					nc->fd = fd;
					struct epoll_event e = {.events = EPOLLIN, .data.ptr = nc};
					epoll_ctl(ep, EPOLL_CTL_ADD, fd, &e);
				}
				continue;
			}
			int r = read(c->fd, c->buf + c->len, sizeof c->buf - c->len);
			if (r <= 0) {
				if (r < 0 && errno == EAGAIN) continue;
				close(c->fd);
				free(c);
				continue;
			}
			c->len += r;
			char *end;
			while ((end = memmem(c->buf, c->len, "\r\n\r\n", 4))) {
				int used = end + 4 - c->buf;
				int w = handle(c->buf, used, out);
				if (write(c->fd, out, w) < 0) break;
				memmove(c->buf, c->buf + used, c->len - used);
				c->len -= used;
			}
		}
	}
	return arg;
}

int main(int argc, char **argv) {
	if (argc < 3) { fprintf(stderr, "usage: server <port> <data-dir> [threads]  (data-dir is ignored; it matches the other servers' argv)\n"); return 2; }
	port = atoi(argv[1]);
	int threads = argc > 3 ? atoi(argv[3]) : 2;
	pthread_t t;
	for (int i = 1; i < threads; i++) pthread_create(&t, NULL, run, NULL);
	run(NULL);
}
