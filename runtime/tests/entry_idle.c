/* Unit test of the idle connection pool (runtime/core/idle.c) on real schedulers and reactors: a parked connection starts its
 * request when its descriptor is readable, an idle timeout and a drain close it, pipelined input starts it at once,
 * and a thread held up by a long computation loses its idle connections to a resting thread, which serves them. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c11 */

#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <uv.h>
#ifdef _WIN32
#include <winsock2.h>
#else
#include <sys/socket.h>
#endif

#include "../core/idle.h"
#include "../core/isolate.h"
#include "../core/promise.h"
#include "../core/scheduler.h"
#include "../entry/entry.h"
#include "../io/reactor.h"
#include "ms_rt/alloc.h"
#include "ms_rt/sys_net.h"

static void expect(bool condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "entry_idle: failed: %s\n", what);
        exit(1);
    }
}

/* ---- a scheduler thread's environment: the runtime's own reactor, scheduler and hooks ---- */

static void attach_thread(void) { expect(ms_start_attach_thread(), "attach"); }

static void run_main(void (*entry)(void *)) {
    uint8_t outcome = 9;
    MsFaultText message = {0};
    expect(ms_task_run_main(entry, NULL, 0, &outcome, &message) == MS_TASK_OK && outcome == 0, "main task");
    ms_sched_teardown();
    ms_io_close(true); /* attach opens every thread's reactor as the main one */
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
static int ops_duplicate(int fd) {
    MsSock copy = -1;
    return ms_sys_net_duplicate(fd, &copy) == 0 ? (int)copy : -1;
}
static void ops_release(int fd) { ms_sys_net_close(fd); }
static void ops_close(void *subject) { atomic_fetch_add(&((Conn *)subject)->closed, 1); }
static const MsIdleOps ops = {ops_buffered, ops_moved, ops_duplicate, ops_release, ops_close};

static void serve(Next *next) {
    char byte = 0;
    size_t done = 0;
    (void)ms_sys_net_read(next->conn->fd, &byte, 1, &done);
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

/* A connected pair of sockets: the pool watches `ends[0]`, the test writes to `ends[1]`. */
static void make_pair(MsSock ends[2]) {
    uv_os_sock_t sockets[2];
    expect(uv_socketpair(SOCK_STREAM, 0, sockets, 0, 0) == 0, "socketpair");
    ends[0] = (MsSock)sockets[0];
    ends[1] = (MsSock)sockets[1];
}

static void send_byte(MsSock socket, char byte) {
    size_t done = 0;
    expect(ms_sys_net_write(socket, &byte, 1, &done) == 0 && done == 1, "write");
}

/* ---- one thread ---- */

static void single(void *argument) {
    (void)argument;
    MsSock pair[2];
    make_pair(pair);

    Conn *const conn = make_conn((int)pair[0], false);
    expect(ms_idle_park(&ops, conn, conn->fd, make_next(conn), group_a, -1), "park");
    expect(ms_idle_count(ms_isolate_self()) == 1, "one idle connection");
    ms_task_sleep(5 * 1000 * 1000);
    expect(atomic_load(&conn->served) == 0, "an idle connection does not start");
    send_byte(pair[1], 'x');
    wait_for(&conn->served, 1, "readable starts the request");
    for (int i = 0; i < 100 && ms_idle_inflight(group_a) != 0; i++) {
        ms_task_sleep(1000 * 1000);
    }
    expect(ms_idle_inflight(group_a) == 0, "a finished request leaves the count");
    expect(ms_idle_count(ms_isolate_self()) == 0, "a started row leaves the pool");

    Conn *const quiet = make_conn((int)pair[0], false);
    expect(ms_idle_park(&ops, quiet, quiet->fd, make_next(quiet), group_a, 20 * 1000 * 1000), "park with a timeout");
    wait_for(&quiet->closed, 1, "an idle timeout closes the connection");
    expect(atomic_load(&quiet->served) == 0, "a timed-out connection does not serve");

    Conn *const piped = make_conn((int)pair[0], true);
    send_byte(pair[1], 'y');
    expect(ms_idle_park(&ops, piped, piped->fd, make_next(piped), group_a, -1), "park with buffered input");
    wait_for(&piped->served, 1, "buffered input starts at once");

    Conn *const drained = make_conn((int)pair[0], false);
    expect(ms_idle_park(&ops, drained, drained->fd, make_next(drained), group_b, -1), "park to drain");
    ms_idle_drain(group_b);
    wait_for(&drained->closed, 1, "a drain closes the connection");
    ms_task_sleep(5 * 1000 * 1000);
    expect(atomic_load(&drained->served) == 0, "a drained connection does not serve");

    ms_sys_net_close(pair[0]);
    ms_sys_net_close(pair[1]);
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

static void helper_thread(void *argument) {
    (void)argument;
    attach_thread();
    atomic_store(&helper_index, ms_isolate_self());
    run_main(helper_main);
}

static void busy_for(int64_t ns) {
    const int64_t until = ms_sched_now() + ns;
    while (ms_sched_now() < until) {
    }
}

static void stolen(void *argument) {
    (void)argument;
    while (atomic_load(&helper_index) == MS_NO_ISOLATE) {
        uv_sleep(1);
    }
    MsSock pair[2];
    make_pair(pair);
    Conn *const conn = make_conn((int)pair[0], false);
    expect(ms_idle_park(&ops, conn, conn->fd, make_next(conn), group_a, -1), "park");
    send_byte(pair[1], 'z'); /* the request arrives while this thread computes */
    busy_for(400LL * 1000 * 1000); /* held up: no reactor turn, no rest */
    wait_for(&conn->served, 1, "the connection was served");
    expect(atomic_load(&conn->served_on) == atomic_load(&helper_index), "a resting thread served it");
    expect(atomic_load(&conn->served) == 1, "it was served once");
    atomic_store(&helper_stop, true);
    ms_task_sleep(2 * 1000 * 1000);
    ms_sys_net_close(pair[1]);
    msrt_free(conn);
}

int main(void) {
    msrt_heap_claim();
    group_a = ms_idle_group_new();
    group_b = ms_idle_group_new();
    attach_thread();
    run_main(single);

    uv_thread_t helper;
    expect(uv_thread_create(&helper, helper_thread, NULL) == 0, "thread");
    attach_thread();
    run_main(stolen);
    uv_thread_join(&helper);
    puts("entry_idle: ok");
    return 0;
}
