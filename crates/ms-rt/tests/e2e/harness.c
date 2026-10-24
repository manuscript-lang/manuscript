#define _GNU_SOURCE
// End-to-end harness: links against libms_native.a and drives msrt_start like generated code.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { uint64_t rc; void *drop; uint64_t len; uint64_t scalars; } StrHdr;
typedef struct { uintptr_t addr; uint32_t size, name_off, file_off, line; } FuncEntry;
typedef struct { uintptr_t pc; uint32_t line, file_off; } LineEntry;
typedef struct {
    uint32_t abi_version, reserved;
    const FuncEntry *funcs; size_t func_count;
    const LineEntry *lines; size_t line_count;
    const char *strings; size_t strings_len;
} Tables;
typedef struct { uint8_t *ptr; size_t len, cap; } VecVal;

extern int32_t msrt_start(int64_t (*main_fn)(void), const Tables *t, int argc, char **argv);
extern void *msrt_string_from_bytes(const char *p, size_t n);
extern void msrt_io_write_stdout(void *s);
extern void msrt_fault(const char *p, size_t n) __attribute__((noreturn));
extern size_t msrt_cleanup_push(void (*f)(void *), void *arg);
extern int64_t msrt_string_length(void *s);
extern uintptr_t msrt_stack_limit;
extern void msrt_fault_depth(void) __attribute__((noreturn));
extern void msrt_args(VecVal *out);
extern uint8_t msrt_guard_call(void (*code)(void *), void *data, void **msg_out);
extern void msrt_cleanup_run(size_t handle);
extern uint64_t msrt_task_spawn(void (*entry)(void *), void *arg, uint32_t flags, size_t stack);
extern void msrt_task_yield(void);
extern uint32_t msrt_task_wait_fd(int fd, uint32_t events, int64_t timeout_ns);
extern uint32_t msrt_task_sleep(int64_t ns);
extern uint8_t msrt_task_join(uint64_t h, void **msg_out);
extern void msrt_task_cancel(uint64_t h);
extern size_t msrt_task_count(void);
extern void msrt_cancelled(void) __attribute__((noreturn));

static const char *mode;

static void cleanup_a(void *arg) { fputs("cleanup a\n", stderr); }
static void cleanup_b(void *arg) { fputs("cleanup b\n", stderr); }

__attribute__((noinline)) int64_t inner(int64_t n) {
    if (n == 0) msrt_fault("boom", 4);
    return inner(n - 1) + 1;
}
__attribute__((noinline)) int64_t outer(void) { return inner(2); }

__attribute__((noinline)) int64_t busy(void) {
    volatile uint64_t x = 0;
    for (uint64_t i = 0; i < 400000000ull; i++) x += i * i;
    return (int64_t)(x & 1);
}

static int64_t deep(int64_t n) {
    char marker;
    if ((uintptr_t)&marker < msrt_stack_limit) msrt_fault_depth();
    return n == 0 ? 0 : deep(n - 1) + 1;
}

static void faulting_request(void *data) {
    int *n = data;
    msrt_cleanup_push(cleanup_a, 0);
    msrt_cleanup_push(cleanup_b, 0);
    (*n)++;
    outer();
    (*n) += 100;
}
static void fine_request(void *data) { *(int *)data += 1; }
static void nested_request(void *data) {
    void *msg = 0;
    int inner_n = 0;
    uint8_t r = msrt_guard_call(faulting_request, &inner_n, &msg);
    *(int *)data = r == 1 && inner_n == 1 && msg ? 7 : -1;
    // a fault after the inner guard returned reaches the outer guard
    msrt_fault("outer boom", 10);
}

static int64_t guard_mode(void) {
    size_t base = msrt_cleanup_push(cleanup_a, 0);
    for (int round = 0; round < 3; round++) {
        int n = 0;
        void *msg = 0;
        uint8_t r = msrt_guard_call(faulting_request, &n, &msg);
        if (r != 1 || n != 1 || !msg) return 10;
        if (msrt_string_length(msg) < 4) return 11;
        msrt_io_write_stdout(msg);
        n = 0;
        if (msrt_guard_call(fine_request, &n, &msg) != 0 || n != 1 || msg) return 12;
    }
    int n = 0;
    void *msg = 0;
    if (msrt_guard_call(nested_request, &n, &msg) != 1 || n != 7 || !msg) return 13;
    msrt_io_write_stdout(msg);
    msrt_cleanup_run(base);
    puts("guards ok");
    return 0;
}

#include <unistd.h>
#include <fcntl.h>
#include <time.h>
static int order[1024];
static int order_n;
static void note(int v) { order[order_n++] = v; }
static void sleeper(void *arg) {
    long ms = (long)arg;
    uint32_t r = msrt_task_sleep(ms * 1000000);
    if (r != 8) note(-1);
    note((int)ms);
}
static void yielder(void *arg) {
    for (int i = 0; i < 3; i++) { note((int)(long)arg * 10 + i); msrt_task_yield(); }
}
static void reader(void *arg) {
    int *fds = arg;
    char b[4];
    uint32_t r = msrt_task_wait_fd(fds[0], 1, -1);
    if (!(r & 1)) { note(-2); return; }
    ssize_t n = read(fds[0], b, 4);
    note(n == 4 ? 100 : -3);
}
static void writer(void *arg) {
    int *fds = arg;
    msrt_task_sleep(5 * 1000000);
    note(50);
    if (write(fds[1], "ping", 4) != 4) note(-4);
}
static void faulter(void *arg) {
    msrt_cleanup_push(cleanup_a, 0);
    msrt_task_yield();
    msrt_fault("task boom", 9);
}
static void timeout_waiter(void *arg) {
    int *fds = arg;
    uint32_t r = msrt_task_wait_fd(fds[0], 1, 10 * 1000000);
    note(r == 8 ? 200 : -5);
}
static void canceller_target(void *arg) {
    uint32_t r = msrt_task_sleep(60ll * 1000000000);
    note(r == 16 ? 300 : -6);
}

static int64_t tasks_mode(void) {
    // sleepers wake in deadline order, not spawn order
    uint64_t a = msrt_task_spawn(sleeper, (void *)30, 0, 0);
    uint64_t b = msrt_task_spawn(sleeper, (void *)10, 0, 0);
    uint64_t c = msrt_task_spawn(sleeper, (void *)20, 0, 0);
    if (msrt_task_join(a, 0) || msrt_task_join(b, 0) || msrt_task_join(c, 0)) return 10;
    if (order_n != 3 || order[0] != 10 || order[1] != 20 || order[2] != 30) return 11;
    // yields interleave round robin
    order_n = 0;
    uint64_t y1 = msrt_task_spawn(yielder, (void *)1, 0, 0);
    uint64_t y2 = msrt_task_spawn(yielder, (void *)2, 0, 0);
    msrt_task_join(y1, 0); msrt_task_join(y2, 0);
    int want[6] = {10, 20, 11, 21, 12, 22};
    if (order_n != 6) return 12;
    for (int i = 0; i < 6; i++) if (order[i] != want[i]) return 13;
    // I/O wakeup
    order_n = 0;
    int fds[2];
    if (pipe2(fds, O_NONBLOCK)) return 14;
    uint64_t r = msrt_task_spawn(reader, fds, 0, 0);
    uint64_t w = msrt_task_spawn(writer, fds, 0, 0);
    msrt_task_join(r, 0); msrt_task_join(w, 0);
    if (order_n != 2 || order[0] != 50 || order[1] != 100) return 15;
    // wait timeout
    order_n = 0;
    int fds2[2];
    if (pipe2(fds2, O_NONBLOCK)) return 16;
    uint64_t t = msrt_task_spawn(timeout_waiter, fds2, 0, 0);
    msrt_task_join(t, 0);
    if (order_n != 1 || order[0] != 200) return 17;
    // a fault in a joined task is returned with its report and runs its cleanups
    void *msg = 0;
    uint64_t f = msrt_task_spawn(faulter, 0, 0, 0);
    if (msrt_task_join(f, &msg) != 1 || !msg) return 18;
    msrt_io_write_stdout(msg);
    // cancellation wakes a parked task
    order_n = 0;
    uint64_t k = msrt_task_spawn(canceller_target, 0, 0, 0);
    msrt_task_yield();
    msrt_task_cancel(k);
    msrt_task_join(k, 0);
    if (order_n != 1 || order[0] != 300) return 19;
    // many tasks
    order_n = 0;
    uint64_t many[200];
    for (int i = 0; i < 200; i++) many[i] = msrt_task_spawn(yielder, (void *)0, 0, 0);
    for (int i = 0; i < 200; i++) msrt_task_join(many[i], 0);
    if (msrt_task_count() != 1) return 20;
    puts("tasks ok");
    return 0;
}

static void spin_yield(void *arg) { int n = getenv("YL") ? atoi(getenv("YL")) : 100; for (int i = 0; i < n; i++) msrt_task_yield(); }
static int64_t bench_tasks(void) {
    int N = getenv("NT") ? atoi(getenv("NT")) : 10000;
    static uint64_t hs[100000];
    struct timespec a, b;
    clock_gettime(CLOCK_MONOTONIC, &a);
    for (int i = 0; i < N; i++) hs[i] = msrt_task_spawn(spin_yield, 0, 0, 0);
    for (int i = 0; i < N; i++) msrt_task_join(hs[i], 0);
    clock_gettime(CLOCK_MONOTONIC, &b);
    double ns = (b.tv_sec - a.tv_sec) * 1e9 + (b.tv_nsec - a.tv_nsec);
    printf("%d tasks x 100 yields: %.0f ms total, %.1f ns/switch\n", N, ns / 1e6, ns / (N * ((getenv("YL") ? atof(getenv("YL")) : 100.0) + 1)));
    return 0;
}

static int64_t entry(void) {
    if (!strcmp(mode, "taskbench")) return bench_tasks();
    if (!strcmp(mode, "parked")) {
        msrt_cleanup_push(cleanup_a, 0);
        uint32_t r = msrt_task_sleep(60ll * 1000000000);
        if (r == 16) msrt_cancelled();
        return 1;
    }
    if (!strcmp(mode, "tasks")) return tasks_mode();
    if (!strcmp(mode, "guard")) return guard_mode();
    if (!strcmp(mode, "ok")) {
        void *s = msrt_string_from_bytes("héllo\n", 7);
        msrt_io_write_stdout(s);
        return 3;
    }
    if (!strcmp(mode, "fault")) {
        msrt_cleanup_push(cleanup_a, 0);
        msrt_cleanup_push(cleanup_b, 0);
        return outer();
    }
    if (!strcmp(mode, "badexit")) return 200;
    if (!strcmp(mode, "deep")) { deep(199990); return 0; }
    if (!strcmp(mode, "toodeep")) { deep(100000000); return 0; }
    if (!strcmp(mode, "args")) {
        VecVal v; msrt_args(&v);
        printf("%zu\n", v.len);
        return 0;
    }
    if (!strcmp(mode, "busy")) return busy();
    return 1;
}

int main(int argc, char **argv) {
    mode = argc > 1 ? argv[1] : "ok";
    static const char names[] = "\0outer\0inner\0busy\0t.ms\0";
    FuncEntry funcs[3] = {
        { (uintptr_t)busy, 128, 13, 18, 20 },
        { (uintptr_t)inner, 128, 7, 18, 3 },
        { (uintptr_t)outer, 64, 1, 18, 9 },
    };
    // Sort by address.
    for (int i = 0; i < 3; i++) for (int j = i + 1; j < 3; j++)
        if (funcs[j].addr < funcs[i].addr) { FuncEntry t = funcs[i]; funcs[i] = funcs[j]; funcs[j] = t; }
    Tables t = { 2, 0, funcs, 3, 0, 0, names, sizeof names };
    return msrt_start(entry, &t, argc - 1, argv + 1);
}
