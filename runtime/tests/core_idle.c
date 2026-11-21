/* Unit test of the idle connection pool (runtime/core/idle.c) on real schedulers: a parked connection starts its
 * request when its descriptor is readable, an idle timeout and a drain close it, pipelined input starts it at once,
 * and a thread held up by a long computation loses its idle connections to a resting thread, which serves them. */
#define _DEFAULT_SOURCE 1
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include "ms_rt/sys_net.h"
#else
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>
#endif

#include "../core/idle.h"
#include "../core/isolate.h"
#include "../core/promise.h"
#include "../core/scheduler.h"
#include "ms_rt/alloc.h"

static void expect(bool condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "core_idle: failed: %s\n", what);
        exit(1);
    }
}

/* ---- the descriptors the test uses: sockets everywhere. Windows has no socketpair, poll or dup, so they are built
 * from a loopback connection, WSAPoll and ms_sys_net_duplicate; the pool itself is the code under test. ---- */

#ifdef _WIN32
typedef WSAPOLLFD PollFd;
enum { POLL_IN = POLLRDNORM, POLL_HUP = POLLHUP };

static int make_pair(int pair[2]) {
    SOCKET listener = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address = {.sin_family = AF_INET, .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
    int length = sizeof address;
    if (listener == INVALID_SOCKET || bind(listener, (struct sockaddr *)&address, sizeof address) != 0 ||
        listen(listener, 1) != 0 || getsockname(listener, (struct sockaddr *)&address, &length) != 0) {
        return -1;
    }
    SOCKET client = socket(AF_INET, SOCK_STREAM, 0);
    if (client == INVALID_SOCKET || connect(client, (struct sockaddr *)&address, sizeof address) != 0) {
        return -1;
    }
    SOCKET server = accept(listener, NULL, NULL);
    (void)closesocket(listener);
    if (server == INVALID_SOCKET) {
        return -1;
    }
    pair[0] = (int)server;
    pair[1] = (int)client;
    return 0;
}
static long fd_read(int fd, void *buffer, size_t count) { return recv((SOCKET)fd, buffer, (int)count, 0); }
static long fd_write(int fd, const void *buffer, size_t count) { return send((SOCKET)fd, buffer, (int)count, 0); }
static void fd_close(int fd) { (void)closesocket((SOCKET)fd); }
static int fd_duplicate(int fd) {
    MsSock copy = 0;
    return ms_sys_net_duplicate((MsSock)fd, &copy) == MS_SYS_OK ? (int)copy : -1;
}
static int poll_fds(PollFd *fds, size_t count, int milliseconds) { return WSAPoll(fds, (ULONG)count, milliseconds); }
static void sleep_us(unsigned microseconds) { Sleep((microseconds + 999) / 1000); }
#else
typedef struct pollfd PollFd;
enum { POLL_IN = POLLIN, POLL_HUP = POLLHUP };

static int make_pair(int pair[2]) { return socketpair(AF_UNIX, SOCK_STREAM, 0, pair); }
static long fd_read(int fd, void *buffer, size_t count) { return read(fd, buffer, count); }
static long fd_write(int fd, const void *buffer, size_t count) { return write(fd, buffer, count); }
static void fd_close(int fd) { (void)close(fd); }
static int fd_duplicate(int fd) { return dup(fd); }
static int poll_fds(PollFd *fds, size_t count, int milliseconds) { return poll(fds, (nfds_t)count, milliseconds); }
static void sleep_us(unsigned microseconds) { (void)usleep(microseconds); }
#endif

/* ---- a scheduler thread's environment: a poll(2) over its descriptors and a pipe that wakes it ---- */

/* The descriptors this thread waits on and what for. Socket numbers are not small on Windows, so a short list is
 * searched instead of indexing by number. */
enum { MAX_WATCHED = 16 };
typedef struct Watch {
    int fd;
    uint32_t events; /* 0: free */
} Watch;
static _Thread_local Watch watched[MAX_WATCHED];
static _Thread_local int wake_pipe[2];

static void wake(void *argument) {
    const int *const pipe_fds = argument;
    const char byte = 1;
    (void)!fd_write(pipe_fds[1], &byte, 1);
}

static Watch *watch_of(int fd) {
    Watch *free_slot = NULL;
    for (size_t i = 0; i < MAX_WATCHED; i++) {
        if (watched[i].events != 0 && watched[i].fd == fd) {
            return &watched[i];
        }
        if (watched[i].events == 0 && free_slot == NULL) {
            free_slot = &watched[i];
        }
    }
    return free_slot;
}

static int fake_watch(int fd, uint32_t events) {
    Watch *const slot = watch_of(fd);
    expect(slot != NULL, "a free watch slot");
    *slot = (Watch){.fd = fd, .events = events};
    return MS_POLL_ARMED;
}
static void fake_unwatch(int fd) {
    Watch *const slot = watch_of(fd);
    if (slot != NULL) {
        slot->events = 0;
    }
}

static long fake_wait(int64_t timeout_ns, MsPollReady *out, size_t capacity) {
    PollFd fds[MAX_WATCHED + 1];
    size_t count = 0;
    fds[count++] = (PollFd){.fd = (uintptr_t)wake_pipe[0], .events = POLL_IN};
    for (size_t i = 0; i < MAX_WATCHED; i++) {
        if (watched[i].events != 0) {
            fds[count++] = (PollFd){.fd = (uintptr_t)watched[i].fd, .events = POLL_IN};
        }
    }
    const int ms = timeout_ns < 0 ? -1 : (int)((timeout_ns + 999999) / 1000000);
    if (poll_fds(fds, count, timeout_ns == 0 ? 0 : ms) <= 0) {
        return 0;
    }
    if ((fds[0].revents & POLL_IN) != 0) {
        char drain[64];
        (void)!fd_read(wake_pipe[0], drain, sizeof drain);
    }
    long ready = 0;
    for (size_t i = 1; i < count && (size_t)ready < capacity; i++) {
        if ((fds[i].revents & (POLL_IN | POLL_HUP)) != 0) {
            fake_unwatch((int)fds[i].fd);
            out[ready++] = (MsPollReady){.fd = (uintptr_t)fds[i].fd, .bits = MS_WAIT_READ};
        }
    }
    return ready;
}

static void fake_fault(MsFaultKind kind, const char *message) {
    (void)kind;
    fprintf(stderr, "core_idle: fault: %s\n", message);
    exit(1);
}
static void fake_exit(int status) {
    fprintf(stderr, "core_idle: exit %d\n", status);
    exit(1);
}

static uint32_t attach_thread(void) {
    expect(make_pair(wake_pipe) == 0, "wake pair");
    MsSchedHooks hooks = {.fault = fake_fault, .exit_process = fake_exit};
    ms_promise_hooks(&hooks);
    const MsPollOps poll_ops = {.watch = fake_watch, .unwatch = fake_unwatch, .forget = fake_unwatch, .wait = fake_wait};
    ms_sched_set_hooks(&hooks, &poll_ops);
    const uint32_t index = ms_sched_attach(wake, wake_pipe);
    expect(index != MS_NO_ISOLATE, "attach");
    return index;
}

static void run_main(void (*entry)(void *)) {
    uint8_t outcome = 9;
    MsFaultText message = {0};
    expect(ms_task_run_main(entry, NULL, 0, &outcome, &message) == MS_TASK_OK && outcome == 0, "main task");
    ms_sched_teardown();
}

/* ---- connections: a socket pair end the pool watches, a closure that serves it ---- */

typedef struct Conn {
    MsObj header;
    int fd;
    atomic_int closed;
    atomic_int served;
    atomic_uint served_on;
    bool buffered;
} Conn;

typedef struct Next {
    MsObj header;
    void (*code)(struct Next *);
    Conn *conn;
} Next;

static void conn_drop(MsObj *object) { (void)object; /* the test owns the Conn */ }

static bool ops_buffered(void *subject) { return ((Conn *)subject)->buffered; }
static void ops_moved(void *subject, int fd) { ((Conn *)subject)->fd = fd; }
static int ops_duplicate(int fd) { return fd_duplicate(fd); }
static void ops_release(int fd) { fd_close(fd); }
static void ops_close(void *subject) { atomic_fetch_add(&((Conn *)subject)->closed, 1); }
static const MsIdleOps ops = {ops_buffered, ops_moved, ops_duplicate, ops_release, ops_close};

static void serve(Next *next) {
    char byte = 0;
    (void)!fd_read(next->conn->fd, &byte, 1);
    atomic_store(&next->conn->served_on, ms_isolate_self());
    atomic_fetch_add(&next->conn->served, 1);
}

static void next_drop(MsObj *object) { msrt_free(object); }

static MsObj *make_next(Conn *conn) {
    Next *const next = msrt_alloc_zeroed(sizeof *next);
    next->header.drop = next_drop;
    next->code = serve;
    next->conn = conn;
    return &next->header;
}

static Conn *make_conn(int fd, bool buffered) {
    Conn *const conn = msrt_alloc_zeroed(sizeof *conn);
    conn->header.drop = conn_drop;
    conn->fd = fd;
    conn->buffered = buffered;
    return conn;
}

static uintptr_t group_a, group_b;

static void wait_for(atomic_int *value, int wanted, const char *what) {
    for (int i = 0; i < 2000 && atomic_load(value) < wanted; i++) {
        ms_task_sleep(1000 * 1000);
    }
    expect(atomic_load(value) >= wanted, what);
}

/* ---- one thread ---- */

static void single(void *argument) {
    (void)argument;
    int pair[2];
    expect(make_pair(pair) == 0, "socketpair");

    Conn *const conn = make_conn(pair[0], false);
    expect(ms_idle_park(&ops, conn, conn->fd, make_next(conn), group_a, -1), "park");
    expect(ms_idle_count(ms_isolate_self()) == 1, "one idle connection");
    ms_task_sleep(5 * 1000 * 1000);
    expect(atomic_load(&conn->served) == 0, "an idle connection does not start");
    expect(fd_write(pair[1], "x", 1) == 1, "write");
    wait_for(&conn->served, 1, "readable starts the request");
    for (int i = 0; i < 100 && ms_idle_inflight(group_a) != 0; i++) {
        ms_task_sleep(1000 * 1000);
    }
    expect(ms_idle_inflight(group_a) == 0, "a finished request leaves the count");
    expect(ms_idle_count(ms_isolate_self()) == 0, "a started row leaves the pool");

    Conn *const quiet = make_conn(pair[0], false);
    expect(ms_idle_park(&ops, quiet, quiet->fd, make_next(quiet), group_a, 20 * 1000 * 1000), "park with a timeout");
    wait_for(&quiet->closed, 1, "an idle timeout closes the connection");
    expect(atomic_load(&quiet->served) == 0, "a timed-out connection does not serve");

    Conn *const piped = make_conn(pair[0], true);
    expect(fd_write(pair[1], "y", 1) == 1, "write");
    expect(ms_idle_park(&ops, piped, piped->fd, make_next(piped), group_a, -1), "park with buffered input");
    wait_for(&piped->served, 1, "buffered input starts at once");

    Conn *const drained = make_conn(pair[0], false);
    expect(ms_idle_park(&ops, drained, drained->fd, make_next(drained), group_b, -1), "park to drain");
    ms_idle_drain(group_b);
    wait_for(&drained->closed, 1, "a drain closes the connection");
    ms_task_sleep(5 * 1000 * 1000);
    expect(atomic_load(&drained->served) == 0, "a drained connection does not serve");

    fd_close(pair[0]);
    fd_close(pair[1]);
    msrt_free(conn);
    msrt_free(quiet);
    msrt_free(piped);
    msrt_free(drained);
}

/* ---- two threads: a held-up thread loses its idle connection ---- */

static atomic_uint helper_index = MS_NO_ISOLATE;
static atomic_bool helper_stop;

static void helper_main(void *argument) {
    (void)argument;
    for (int i = 0; i < 4000 && !atomic_load(&helper_stop); i++) {
        ms_task_sleep(1000 * 1000 * 1000 / 4);
    }
}

static void *helper_thread(void *argument) {
    (void)argument;
    atomic_store(&helper_index, attach_thread());
    run_main(helper_main);
    return NULL;
}

static void busy_for(int64_t ns) {
    const int64_t until = ms_sched_now() + ns;
    while (ms_sched_now() < until) {
    }
}

static void stolen(void *argument) {
    (void)argument;
    while (atomic_load(&helper_index) == MS_NO_ISOLATE) {
        sleep_us(1000);
    }
    int pair[2];
    expect(make_pair(pair) == 0, "socketpair");
    Conn *const conn = make_conn(pair[0], false);
    expect(ms_idle_park(&ops, conn, conn->fd, make_next(conn), group_a, -1), "park");
    expect(fd_write(pair[1], "z", 1) == 1, "the request arrives while this thread computes");
    busy_for(400LL * 1000 * 1000); /* held up: no reactor turn, no rest */
    wait_for(&conn->served, 1, "the connection was served");
    expect(atomic_load(&conn->served_on) == atomic_load(&helper_index), "a resting thread served it");
    expect(atomic_load(&conn->served) == 1, "it was served once");
    atomic_store(&helper_stop, true);
    ms_task_sleep(2 * 1000 * 1000);
    fd_close(pair[1]);
    msrt_free(conn);
}

int main(void) {
#ifdef _WIN32
    WSADATA winsock;
    expect(WSAStartup(MAKEWORD(2, 2), &winsock) == 0, "winsock");
#endif
    msrt_heap_claim();
    group_a = ms_idle_group_new();
    group_b = ms_idle_group_new();
    attach_thread();
    run_main(single);

    pthread_t helper;
    expect(pthread_create(&helper, NULL, helper_thread, NULL) == 0, "thread");
    attach_thread();
    run_main(stolen);
    pthread_join(helper, NULL);
    puts("core_idle: ok");
    return 0;
}
