// Prototype: idle websocket echo server, two task designs, same wire behaviour.
//   stack : each connection runs a blocking-style handler on its own stack slot
//           (slots carved from one NORESERVE region, like ms task stacks).
//   state : each connection is one small block plus a state tag; no stack.
// Linux/epoll only; this is a measurement probe, not runtime code.
// Handshake skips the Sec-WebSocket-Accept hash (client does not check it).
#define _GNU_SOURCE
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <time.h>
#include <ucontext.h>
#include <unistd.h>

#define SLOT (512 * 1024)
static const char RESP[] = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: x\r\n\r\n";
static int ep;
static char scratch[65536]; // shared per-thread read buffer: idle connections hold none

static void nb(int fd) { fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK); }
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec * 1e-9; }
static long rss_kb(const char *key) {
  FILE *f = fopen("/proc/self/status", "r"); char l[256]; long v = -1;
  while (fgets(l, sizeof l, f)) if (!strncmp(l, key, strlen(key))) { v = atol(l + strlen(key) + 1); break; }
  fclose(f); return v;
}

// ---- wire: parse one client frame from buf; returns bytes consumed or 0 if incomplete.
// out: opcode, payload pointer/len (unmasked in place).
static size_t parse_frame(unsigned char *b, size_t n, int *op, unsigned char **pl, size_t *pn) {
  if (n < 2) return 0;
  size_t len = b[1] & 0x7f, off = 2;
  if (len > 125) return (size_t)-1; // probe supports small messages only
  int masked = b[1] >> 7;
  if (masked) off += 4;
  if (n < off + len) return 0;
  if (masked) for (size_t i = 0; i < len; i++) b[off + i] ^= b[off - 4 + (i & 3)];
  *op = b[0] & 15; *pl = b + off; *pn = len; return off + len;
}
static size_t build_frame(unsigned char *o, int op, unsigned char *pl, size_t n) {
  o[0] = 0x80 | op; o[1] = n; memcpy(o + 2, pl, n); return n + 2;
}

// ======================= design 1: stack tasks =======================
typedef struct Task { ucontext_t ctx; int fd; int cancelled; int dead; char *stack; } Task;
static ucontext_t sched_ctx;
static char *region; static size_t region_next;
static size_t live_tasks;

// Park the current task until fd is readable. Returns 0, or -1 if cancelled.
static int wait_readable(Task *t) {
  struct epoll_event ev = {.events = EPOLLIN | EPOLLONESHOT, .data.ptr = t};
  if (epoll_ctl(ep, EPOLL_CTL_MOD, t->fd, &ev) < 0) epoll_ctl(ep, EPOLL_CTL_ADD, t->fd, &ev);
  swapcontext(&t->ctx, &sched_ctx);
  return t->cancelled ? -1 : 0;
}
static int read_some(Task *t, unsigned char *b, size_t cap) {
  for (;;) {
    ssize_t r = read(t->fd, b, cap);
    if (r >= 0) return (int)r;
    if (errno != EAGAIN) return -1;
    if (wait_readable(t) < 0) return -1;
  }
}
static void stack_handler(Task *t) {
  unsigned char buf[1024]; // a modest frame; real ms handlers measured 5.2 KB parked
  size_t have = 0;
  // handshake
  for (;;) {
    int r = read_some(t, buf + have, sizeof buf - have);
    if (r <= 0) goto out;
    have += r;
    if (have >= 4 && memmem(buf, have, "\r\n\r\n", 4)) break;
    if (have == sizeof buf) goto out;
  }
  write(t->fd, RESP, sizeof RESP - 1); have = 0;
  for (;;) { // frame loop
    int op; unsigned char *pl; size_t pn, used;
    while ((used = parse_frame(buf, have, &op, &pl, &pn)) == 0) {
      int r = read_some(t, buf + have, sizeof buf - have);
      if (r <= 0) goto out;
      have += r;
    }
    if (used == (size_t)-1) goto out;
    if (op == 8) goto out;
    unsigned char o[131]; size_t on = build_frame(o, op, pl, pn);
    write(t->fd, o, on);
    memmove(buf, buf + used, have - used); have -= used;
  }
out:
  close(t->fd); t->dead = 1;
}
static Task *cur_boot;
static void stack_boot(void) { Task *t = cur_boot; stack_handler(t); } // uc_link returns to scheduler

static Task *stack_spawn(int fd) {
  Task *t = calloc(1, sizeof *t);
  t->fd = fd; t->stack = region + region_next; region_next += SLOT;
  getcontext(&t->ctx);
  t->ctx.uc_stack.ss_sp = t->stack; t->ctx.uc_stack.ss_size = SLOT; t->ctx.uc_link = &sched_ctx;
  makecontext(&t->ctx, stack_boot, 0);
  cur_boot = t; live_tasks++;
  swapcontext(&sched_ctx, &t->ctx); // runs until first park
  return t;
}
// Cancel: resume the parked task with a cancelled result; the handler unwinds by
// returning through its own error checks (here: closes fd and returns).
static void stack_cancel(Task *t) {
  if (t->dead) return;
  t->cancelled = 1; swapcontext(&sched_ctx, &t->ctx);
}
static void stack_reap(Task *t) { madvise(t->stack, SLOT, MADV_DONTNEED); free(t); live_tasks--; }

// ======================= design 2: state-machine tasks =======================
enum { S_HANDSHAKE, S_FRAMES, S_DONE };
typedef struct Conn {
  int fd; unsigned char state;
  unsigned char partial_len; // bytes of a partial frame held in `stash`
  unsigned short _pad;
  unsigned char *stash;      // allocated only while a frame is split across reads
} Conn;                       // 24 bytes (+ malloc header)
static void conn_free(Conn *c) { close(c->fd); free(c->stash); free(c); }
// Advance on readability. Returns 0 to keep waiting, 1 when finished.
static int conn_step(Conn *c) {
  for (;;) {
    size_t have = 0;
    if (c->stash) { memcpy(scratch, c->stash, c->partial_len); have = c->partial_len; free(c->stash); c->stash = NULL; c->partial_len = 0; }
    ssize_t r = read(c->fd, scratch + have, sizeof scratch - have);
    if (r == 0) return 1;
    if (r < 0) return errno == EAGAIN ? (have ? (c->stash = malloc(have), memcpy(c->stash, scratch, have), c->partial_len = have, 0) : 0) : 1;
    have += r;
    unsigned char *b = (unsigned char *)scratch;
    if (c->state == S_HANDSHAKE) {
      if (!memmem(b, have, "\r\n\r\n", 4)) {
        if (have > 1024) return 1;
        c->stash = malloc(have); memcpy(c->stash, b, have); c->partial_len = have > 255 ? 255 : have; return 0;
      }
      write(c->fd, RESP, sizeof RESP - 1); c->state = S_FRAMES; continue;
    }
    for (;;) {
      int op; unsigned char *pl; size_t pn, used = parse_frame(b, have, &op, &pl, &pn);
      if (used == (size_t)-1 || (used && op == 8)) return 1;
      if (!used) { if (have) { c->stash = malloc(have); memcpy(c->stash, b, have); c->partial_len = have; } break; }
      unsigned char o[131]; size_t on = build_frame(o, op, pl, pn); write(c->fd, o, on);
      b += used; have -= used;
    }
  }
}
// Cancel: no unwinding; run cleanup directly on the block.
static void conn_cancel(Conn *c) { epoll_ctl(ep, EPOLL_CTL_DEL, c->fd, 0); conn_free(c); }

// ============================ server ============================
static int run_server(int stack_mode, int port, int pipefd, int expect) {
  signal(13, SIG_IGN);
  int ls = socket(AF_INET, SOCK_STREAM, 0), one = 1;
  setsockopt(ls, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
  struct sockaddr_in a = {.sin_family = AF_INET, .sin_port = htons(port), .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
  bind(ls, (void *)&a, sizeof a); listen(ls, 4096); nb(ls);
  ep = epoll_create1(0);
  struct epoll_event lev = {.events = EPOLLIN, .data.ptr = NULL};
  epoll_ctl(ep, EPOLL_CTL_ADD, ls, &lev);
  struct epoll_event cev = {.events = EPOLLIN, .data.ptr = (void *)1};
  epoll_ctl(ep, EPOLL_CTL_ADD, pipefd, &cev);
  if (stack_mode) { region = mmap(0, (size_t)SLOT * (expect + 16), PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0); }
  getcontext(&sched_ctx);
  Task **tasks = calloc(expect + 16, sizeof *tasks); Conn **conns = calloc(expect + 16, sizeof *conns); int nt = 0;
  write(pipefd, "R", 1);
  long rss0 = -1, pte0 = -1; int accepted = 0; char cmd;
  struct epoll_event evs[256];
  for (;;) {
    int n = epoll_wait(ep, evs, 256, -1);
    for (int i = 0; i < n; i++) {
      void *p = evs[i].data.ptr;
      if (!p) { // accept
        for (;;) {
          int fd = accept(ls, 0, 0); if (fd < 0) break;
          nb(fd); setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof one);
          if (rss0 < 0) { rss0 = rss_kb("VmRSS:"); pte0 = rss_kb("VmPTE:"); }
          if (stack_mode) tasks[nt++] = stack_spawn(fd);
          else {
            Conn *c = calloc(1, sizeof *c); c->fd = fd; conns[nt++] = c;
            struct epoll_event ev = {.events = EPOLLIN, .data.ptr = c}; epoll_ctl(ep, EPOLL_CTL_ADD, fd, &ev);
          }
          accepted++;
        }
        // told via pipe when all accepted and handshaken is the client's job; poll control pipe below
      } else if (p == (void *)1) { // control pipe
        read(pipefd, &cmd, 1);
        if (cmd == 'M') { // report memory
          long rss1 = rss_kb("VmRSS:"), pte1 = rss_kb("VmPTE:");
          printf("%s: conns=%d  rss+%ld KB  pagetables+%ld KB  => %.0f B/conn (rss) + %.0f B/conn (page tables)\n",
                 stack_mode ? "stack" : "state", accepted, rss1 - rss0, pte1 - pte0,
                 (rss1 - rss0) * 1024.0 / accepted, (pte1 - pte0) * 1024.0 / accepted);
          { FILE *f = fopen("/proc/net/sockstat", "r"); char l[200]; while (fgets(l, sizeof l, f)) if (!strncmp(l, "TCP:", 4)) printf("  kernel (both ends of every connection) %s", l); fclose(f); }
          fflush(stdout); write(pipefd, "K", 1);
        } else if (cmd == 'C') { // cancel everything, time it
          double t0 = now();
          for (int k = 0; k < nt; k++) {
            if (stack_mode) { if (tasks[k]) { stack_cancel(tasks[k]); stack_reap(tasks[k]); tasks[k] = 0; } }
            else if (conns[k]) { conn_cancel(conns[k]); conns[k] = 0; }
          }
          printf("%s: cancel of %d idle tasks: %.1f ms (%.2f us each)\n", stack_mode ? "stack" : "state", nt, (now() - t0) * 1e3, (now() - t0) * 1e6 / nt);
          fflush(stdout); write(pipefd, "K", 1); return 0;
        }
      } else if (stack_mode) {
        Task *t = p; swapcontext(&sched_ctx, &t->ctx);
        if (t->dead) { for (int k = 0; k < nt; k++) if (tasks[k] == t) { stack_reap(t); tasks[k] = 0; } }
      } else {
        Conn *c = p; if (conn_step(c)) { for (int k = 0; k < nt; k++) if (conns[k] == c) conns[k] = 0; epoll_ctl(ep, EPOLL_CTL_DEL, c->fd, 0); conn_free(c); }
      }
    }
  }
}

// ============================ client ============================
static int client(int port, int n, int pipefd) {
  static const char REQ[] = "GET / HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n";
  int *fds = malloc(n * sizeof(int)); struct sockaddr_in a = {.sin_family = AF_INET, .sin_port = htons(port), .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
  for (int i = 0; i < n; i++) {
    fds[i] = socket(AF_INET, SOCK_STREAM, 0);
    if (connect(fds[i], (void *)&a, sizeof a) < 0) { perror("connect"); return 1; }
    write(fds[i], REQ, sizeof REQ - 1);
    char b[512]; ssize_t r = read(fds[i], b, sizeof b); if (r <= 0) { puts("no handshake"); return 1; }
  }
  // one echo round trip on every 10th connection to prove the handler works
  int ok = 0;
  for (int i = 0; i < n; i += 10) {
    unsigned char f[2 + 4 + 5] = {0x81, 0x85, 1, 2, 3, 4}; memcpy(f + 6, "hello", 5); for (int k = 0; k < 5; k++) f[6 + k] ^= f[2 + (k & 3)];
    write(fds[i], f, sizeof f); unsigned char r[16]; ssize_t g = read(fds[i], r, sizeof r);
    if (g == 7 && !memcmp(r + 2, "hello", 5)) ok++;
  }
  fprintf(stderr, "client: %d/%d echo checks passed\n", ok, (n + 9) / 10);
  return ok == (n + 9) / 10 ? 0 : 1;
}

int main(int argc, char **argv) {
  if (argc < 3) { fprintf(stderr, "usage: %s stack|state N [port]\n", argv[0]); return 2; }
  int stack_mode = !strcmp(argv[1], "stack"), n = atoi(argv[2]), port = argc > 3 ? atoi(argv[3]) : 18080;
  int sp[2]; socketpair(AF_UNIX, SOCK_STREAM, 0, sp);
  pid_t srv = fork();
  if (!srv) { close(sp[0]); // server: pipe fd registered in epoll via data.ptr == 1 after bind
    // register control pipe inside run_server's epoll by creating after ep exists:
    return run_server(stack_mode, port, sp[1], n); }
  close(sp[1]);
  char c; read(sp[0], &c, 1); // ready
  int rc = client(port, n, sp[0]);
  write(sp[0], "M", 1); read(sp[0], &c, 1);
  write(sp[0], "C", 1); read(sp[0], &c, 1);
  int st; waitpid(srv, &st, 0); return rc;
}
