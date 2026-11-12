// Keep-alive HTTP/1.1 load generator in C: loadc <port> <conns> <seconds> <path> [threads]
// One epoll loop per thread, one request in flight per connection, no latency histogram.
// Prints "req/s <n> failed <n>". It exists because the Go load generator saturates near
// 185k req/s, which cannot tell a fast server from a faster one.
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
#include <time.h>
#include <unistd.h>

static int port, conns, secs, nthreads;
static char req[256];
static int reqlen;

struct conn { int fd; int have; char buf[2048]; };
struct result { long done, failed; };

static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }

static int complete(struct conn *c) {
	c->buf[c->have] = 0;
	char *end = strstr(c->buf, "\r\n\r\n");
	if (!end) return 0;
	char *cl = strcasestr(c->buf, "content-length:");
	int n = cl && cl < end ? atoi(cl + 15) : 0;
	return c->have >= (end - c->buf) + 4 + n;
}

static void *run(void *arg) {
	struct result *r = arg;
	int mine = conns / nthreads;
	int ep = epoll_create1(0);
	struct conn *cs = calloc(mine, sizeof *cs);
	struct sockaddr_in a = {.sin_family = AF_INET, .sin_port = htons(port)};
	a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	for (int i = 0; i < mine; i++) {
		int fd = socket(AF_INET, SOCK_STREAM, 0), one = 1;
		if (connect(fd, (void *)&a, sizeof a)) { perror("connect"); exit(1); }
		setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
		cs[i].fd = fd;
		struct epoll_event ev = {.events = EPOLLIN, .data.ptr = &cs[i]};
		epoll_ctl(ep, EPOLL_CTL_ADD, fd, &ev);
		if (write(fd, req, reqlen) != reqlen) r->failed++;
	}
	double stop = now() + secs;
	struct epoll_event evs[256];
	while (now() < stop) {
		int n = epoll_wait(ep, evs, 256, 100);
		for (int i = 0; i < n; i++) {
			struct conn *c = evs[i].data.ptr;
			int got = read(c->fd, c->buf + c->have, sizeof c->buf - 1 - c->have);
			if (got <= 0) { r->failed++; epoll_ctl(ep, EPOLL_CTL_DEL, c->fd, NULL); continue; }
			c->have += got;
			if (!complete(c)) continue;
			if (memcmp(c->buf, "HTTP/1.1 200", 12)) r->failed++;
			r->done++;
			c->have = 0;
			if (write(c->fd, req, reqlen) != reqlen) r->failed++;
		}
	}
	return NULL;
}

int main(int argc, char **argv) {
	if (argc < 5) { fprintf(stderr, "usage: loadc <port> <conns> <seconds> <path> [threads]\n"); return 2; }
	port = atoi(argv[1]); conns = atoi(argv[2]); secs = atoi(argv[3]);
	nthreads = argc > 5 ? atoi(argv[5]) : 1;
	reqlen = snprintf(req, sizeof req, "GET %s HTTP/1.1\r\nHost: localhost\r\n\r\n", argv[4]);
	pthread_t t[64]; struct result rs[64] = {0};
	for (int i = 0; i < nthreads; i++) pthread_create(&t[i], NULL, run, &rs[i]);
	long done = 0, failed = 0;
	for (int i = 0; i < nthreads; i++) { pthread_join(t[i], NULL); done += rs[i].done; failed += rs[i].failed; }
	printf("req/s %ld failed %ld\n", done / secs, failed);
	return failed != 0;
}
