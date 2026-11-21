/* Unit test of the idle connection pool (runtime/core/idle.c) on real schedulers: a parked connection starts its
 * request when its descriptor is readable, an idle timeout and a drain close it, pipelined input starts it at once,
 * and a thread held up by a long computation loses its idle connections to a resting thread, which serves them. */
#define _DEFAULT_SOURCE 1
#include <poll.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

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

/* ---- a scheduler thread's environment: a poll(2) over its descriptors and a pipe that wakes it ---- */

enum { MAX_FDS = 128 };
static _Thread_local uint32_t watched[MAX_FDS];
static _Thread_local int wake_pipe[2];

static void wake(void *argument) {
    const int *const pipe_fds = argument;
    const char byte = 1;
    (void)!write(pipe_fds[1], &byte, 1);
}

static int fake_watch(int fd, uint32_t events) {
    watched[fd] = events;
    return MS_POLL_ARMED;
}
static void fake_unwatch(int fd) { watched[fd] = 0; }

static long fake_wait(int64_t timeout_ns, MsPollReady *out, size_t capacity) {
    struct pollfd fds[MAX_FDS + 1];
    size_t count = 0;
    fds[count++] = (struct pollfd){.fd = wake_pipe[0], .events = POLLIN};
    for (int fd = 0; fd < MAX_FDS; fd++) {
        if (watched[fd] != 0) {
            fds[count++] = (struct pollfd){.fd = fd, .events = POLLIN};
        }
    }
    const int ms = timeout_ns < 0 ? -1 : (int)((timeout_ns + 999999) / 1000000);
    if (poll(fds, count, timeout_ns == 0 ? 0 : ms) <= 0) {
        return 0;
    }
    if ((fds[0].revents & POLLIN) != 0) {
        char drain[64];
        (void)!read(wake_pipe[0], drain, sizeof drain);
    }
    long ready = 0;
    for (size_t i = 1; i < count && (size_t)ready < capacity; i++) {
        if ((fds[i].revents & (POLLIN | POLLHUP)) != 0) {
            watched[fds[i].fd] = 0;
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
    expect(pipe(wake_pipe) == 0, "pipe");
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
static int ops_duplicate(int fd) { return dup(fd); }
static void ops_release(int fd) { close(fd); }
static void ops_close(void *subject) { atomic_fetch_add(&((Conn *)subject)->closed, 1); }
static const MsIdleOps ops = {ops_buffered, ops_moved, ops_duplicate, ops_release, ops_close};

static void serve(Next *next) {
    char byte = 0;
    (void)!read(next->conn->fd, &byte, 1);
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
    expect(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0, "socketpair");

    Conn *const conn = make_conn(pair[0], false);
    expect(ms_idle_park(&ops, conn, conn->fd, make_next(conn), group_a, -1), "park");
    expect(ms_idle_count(ms_isolate_self()) == 1, "one idle connection");
    ms_task_sleep(5 * 1000 * 1000);
    expect(atomic_load(&conn->served) == 0, "an idle connection does not start");
    expect(write(pair[1], "x", 1) == 1, "write");
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
    expect(write(pair[1], "y", 1) == 1, "write");
    expect(ms_idle_park(&ops, piped, piped->fd, make_next(piped), group_a, -1), "park with buffered input");
    wait_for(&piped->served, 1, "buffered input starts at once");

    Conn *const drained = make_conn(pair[0], false);
    expect(ms_idle_park(&ops, drained, drained->fd, make_next(drained), group_b, -1), "park to drain");
    ms_idle_drain(group_b);
    wait_for(&drained->closed, 1, "a drain closes the connection");
    ms_task_sleep(5 * 1000 * 1000);
    expect(atomic_load(&drained->served) == 0, "a drained connection does not serve");

    close(pair[0]);
    close(pair[1]);
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
        usleep(1000);
    }
    int pair[2];
    expect(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0, "socketpair");
    Conn *const conn = make_conn(pair[0], false);
    expect(ms_idle_park(&ops, conn, conn->fd, make_next(conn), group_a, -1), "park");
    expect(write(pair[1], "z", 1) == 1, "the request arrives while this thread computes");
    busy_for(400LL * 1000 * 1000); /* held up: no reactor turn, no rest */
    wait_for(&conn->served, 1, "the connection was served");
    expect(atomic_load(&conn->served_on) == atomic_load(&helper_index), "a resting thread served it");
    expect(atomic_load(&conn->served) == 1, "it was served once");
    atomic_store(&helper_stop, true);
    ms_task_sleep(2 * 1000 * 1000);
    close(pair[1]);
    msrt_free(conn);
}

int main(void) {
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
