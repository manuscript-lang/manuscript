/* Unit test of the C scheduler (src/runtime/core: task.c, park.c, token.c, unwind.c, segment.c): switching and
 * yielding, timers, tokens, descriptors, cancellation, guards, stack segments and the size of a parked task.
 * Descriptors go through a small poll(2) poller defined here, standing in for src/runtime/io. Run under the
 * sanitizers by `make c-test`. */
#include <errno.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "ms_rt/alloc.h"
#include "ms_rt/sys.h"
#include "../core/scheduler.h"

static void expect(bool condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "core_task: failed: %s\n", what);
        exit(1);
    }
}

/* ---- the scheduler's environment ---- */

enum { MAX_FDS = 64 };

static uint32_t watched[MAX_FDS]; /* events asked for each descriptor, 0 when not watched */

static int fake_watch(int fd, uint32_t events) {
    watched[fd] = events;
    return MS_POLL_ARMED;
}

static void fake_unwatch(int fd) { watched[fd] = 0; }

static void fake_forget(int fd) { watched[fd] = 0; }

/* A real poll(2) over the watched descriptors; an interest is one-shot, as in the reactor. */
static long fake_wait(int64_t timeout_ns, MsPollReady *out, size_t capacity) {
    struct pollfd fds[MAX_FDS];
    nfds_t count = 0;
    for (int fd = 0; fd < MAX_FDS; fd++) {
        if (watched[fd] != 0) {
            fds[count].fd = fd;
            fds[count].events = (short)(((watched[fd] & MS_WAIT_READ) != 0 ? POLLIN : 0) |
                                        ((watched[fd] & MS_WAIT_WRITE) != 0 ? POLLOUT : 0));
            fds[count].revents = 0;
            count++;
        }
    }
    const int timeout_ms = timeout_ns < 0 ? -1 : (int)((timeout_ns + 999999) / 1000000);
    if (poll(fds, count, timeout_ms) < 0) {
        return -1;
    }
    long ready = 0;
    for (nfds_t i = 0; i < count && (size_t)ready < capacity; i++) {
        uint32_t bits = 0;
        bits |= (fds[i].revents & POLLIN) != 0 ? MS_WAIT_READ : 0;
        bits |= (fds[i].revents & POLLOUT) != 0 ? MS_WAIT_WRITE : 0;
        bits |= (fds[i].revents & (POLLHUP | POLLERR)) != 0 ? MS_WAIT_HUP : 0;
        if (bits != 0) {
            out[ready++] = (MsPollReady){.fd = (uintptr_t)fds[i].fd, .bits = bits};
        }
    }
    return ready;
}

static char last_fault[256];
static MsFaultKind last_fault_kind;

/* A fault leaves the running task through its guard, as the real fault path does. */
static void fake_fault(MsFaultKind kind, const char *message) {
    last_fault_kind = kind;
    snprintf(last_fault, sizeof last_fault, "%s", message);
    MsFaultText text = {.bytes = msrt_alloc(strlen(message) + 1), .length = strlen(message)};
    memcpy(text.bytes, message, text.length + 1);
    if (!ms_guard_leave(MS_GUARD_FAULT, text)) {
        fprintf(stderr, "core_task: fault with no guard: %s\n", message);
        exit(1);
    }
    for (;;) {
    }
}

static void fake_exit(int status) {
    fprintf(stderr, "core_task: unexpected process exit %d\n", status);
    exit(1);
}

static void install(void) {
    const MsSchedHooks hooks = {.fault = fake_fault, .exit_process = fake_exit};
    const MsPollOps poll_ops = {.watch = fake_watch, .unwatch = fake_unwatch, .forget = fake_forget, .wait = fake_wait};
    ms_sched_set_hooks(&hooks, &poll_ops);
}

/* ---- helpers ---- */

static char log_text[512];
static size_t log_length;

static void log_char(char c) {
    expect(log_length + 1 < sizeof log_text, "log has room");
    log_text[log_length++] = c;
    log_text[log_length] = 0;
}

static void log_reset(void) {
    log_length = 0;
    log_text[0] = 0;
}

static MsTaskHandle spawn(MsTaskEntry entry, void *arg, uint32_t flags) {
    MsTaskStatus status = MS_TASK_OK;
    const MsTaskHandle handle = ms_task_spawn(entry, arg, flags, 0, &status);
    expect(handle != 0 && status == MS_TASK_OK, "spawn");
    return handle;
}

static uint8_t join(MsTaskHandle handle, MsFaultText *message) {
    uint8_t outcome = 99;
    MsFaultText text = {0};
    expect(ms_task_join(handle, &outcome, &text) == MS_TASK_OK, "join");
    if (message != NULL) {
        *message = text;
    } else {
        msrt_free(text.bytes);
    }
    return outcome;
}

static int64_t elapsed_ms(int64_t since) { return (ms_sched_now() - since) / 1000000; }

/* ---- yielding and joining ---- */

static void yielder(void *arg) {
    const char c = (char)(uintptr_t)arg;
    for (int i = 0; i < 3; i++) {
        log_char(c);
        ms_task_yield();
    }
}

static void test_yield_order(void) {
    log_reset();
    const MsTaskHandle a = spawn(yielder, (void *)(uintptr_t)'a', 0);
    const MsTaskHandle b = spawn(yielder, (void *)(uintptr_t)'b', 0);
    const MsTaskHandle c = spawn(yielder, (void *)(uintptr_t)'c', 0);
    expect(ms_task_count() == 4, "root plus three tasks exist");
    expect(join(a, NULL) == MS_GUARD_OK && join(b, NULL) == MS_GUARD_OK && join(c, NULL) == MS_GUARD_OK, "all returned");
    expect(strcmp(log_text, "abcabcabc") == 0, "round robin order");
    expect(ms_task_count() == 1, "joined tasks are gone");
    uint8_t outcome = 0;
    MsFaultText text = {0};
    expect(ms_task_join(a, &outcome, &text) == MS_TASK_NO_SUCH_TASK, "a joined handle is stale");
}

static void nothing(void *arg) { (void)arg; }

static void test_join_errors(void) {
    uint8_t outcome = 0;
    MsFaultText text = {0};
    const MsTaskHandle detached = spawn(nothing, NULL, MS_SPAWN_DETACHED);
    expect(ms_task_join(detached, &outcome, &text) == MS_TASK_DETACHED, "a detached task cannot be joined");
    expect(ms_task_join(ms_task_current(), &outcome, &text) == MS_TASK_SELF, "a task cannot join itself");
    ms_task_yield();
    expect(ms_task_join(detached, &outcome, &text) == MS_TASK_NO_SUCH_TASK, "a finished detached task is freed");
}

/* ---- timers ---- */

static void sleeper(void *arg) {
    const unsigned ms = (unsigned)(uintptr_t)arg;
    expect(ms_task_sleep((int64_t)ms * 1000000) == MS_WAIT_TIMEOUT, "a sleep times out");
    log_char((char)('0' + ms));
}

static void test_sleep_order(void) {
    log_reset();
    const int64_t start = ms_sched_now();
    const MsTaskHandle slow = spawn(sleeper, (void *)(uintptr_t)3, 0);
    const MsTaskHandle fast = spawn(sleeper, (void *)(uintptr_t)1, 0);
    const MsTaskHandle mid = spawn(sleeper, (void *)(uintptr_t)2, 0);
    (void)join(slow, NULL);
    (void)join(fast, NULL);
    (void)join(mid, NULL);
    expect(strcmp(log_text, "123") == 0, "timers fire in deadline order");
    expect(elapsed_ms(start) >= 3, "the longest sleep was waited out");
}

/* ---- tokens ---- */

static uint64_t shared_token;

static void token_waiter(void *arg) {
    uint64_t value = 0;
    uint32_t result = 99;
    expect(ms_token_park(shared_token, -1, &value, &result) == MS_TOKEN_OK, "park");
    *(uint64_t *)arg = result == 0 ? value : 0;
}

static void test_tokens(void) {
    shared_token = ms_token_new(0);
    expect(shared_token != 0, "token");
    uint64_t seen = 0;
    const MsTaskHandle waiter = spawn(token_waiter, &seen, 0);
    ms_task_yield();
    ms_token_post(shared_token, 42);
    expect(join(waiter, NULL) == MS_GUARD_OK && seen == 42, "the waiter got the posted value");

    /* A post made before the park is kept. */
    ms_token_post(shared_token, 7);
    ms_token_post(shared_token, 8); /* dropped: the first post is untaken */
    uint64_t value = 0;
    uint32_t result = 99;
    expect(ms_token_park(shared_token, -1, &value, &result) == MS_TOKEN_OK && result == 0 && value == 7,
           "an early post is kept, a second one is dropped");

    /* A timeout leaves the token usable. */
    expect(ms_token_park(shared_token, 1000000, &value, &result) == MS_TOKEN_OK && result == MS_WAIT_TIMEOUT,
           "a park times out");
    ms_token_post(shared_token, 9);
    expect(ms_token_park(shared_token, 1000000, &value, &result) == MS_TOKEN_OK && result == 0 && value == 9,
           "it still works after a timeout");

    expect(ms_token_free(shared_token) == MS_TOKEN_OK, "free");
    expect(ms_token_park(shared_token, 0, &value, &result) == MS_TOKEN_NO_SUCH_TOKEN, "a freed token is gone");
    const uint64_t reused = ms_token_new(0);
    expect(reused != shared_token, "a reused slot has a new generation");
    expect(ms_token_free(reused) == MS_TOKEN_OK, "free again");
}

static void test_token_free_while_waited_on(void) {
    shared_token = ms_token_new(0);
    uint64_t seen = 0;
    const MsTaskHandle waiter = spawn(token_waiter, &seen, 0);
    ms_task_yield();
    expect(ms_token_free(shared_token) == MS_TOKEN_WAITED_ON, "a token with a waiter cannot be freed");
    ms_token_post(shared_token, 5);
    (void)join(waiter, NULL);
    expect(ms_token_free(shared_token) == MS_TOKEN_OK, "free after the wait");
}

/* ---- descriptors ---- */

static int pipe_fds[2];

static void reader(void *arg) {
    const uint32_t bits = ms_task_wait_fd(pipe_fds[0], MS_WAIT_READ, -1);
    char byte = 0;
    expect(read(pipe_fds[0], &byte, 1) == 1, "the byte is there");
    *(uint32_t *)arg = bits << 8 | (uint32_t)(unsigned char)byte;
}

static void test_descriptor_wait(void) {
    expect(pipe(pipe_fds) == 0, "pipe");
    uint32_t seen = 0;
    const MsTaskHandle task = spawn(reader, &seen, 0);
    ms_task_yield();
    expect(watched[pipe_fds[0]] == MS_WAIT_READ, "the poller watches what the task asked");
    expect(write(pipe_fds[1], "x", 1) == 1, "write");
    (void)join(task, NULL);
    expect(seen == (MS_WAIT_READ << 8 | 'x'), "woken with the read bit");
    expect(watched[pipe_fds[0]] == 0, "no waiter, no interest");

    expect(ms_task_wait_fd(pipe_fds[0], MS_WAIT_READ, 2000000) == MS_WAIT_TIMEOUT, "an idle descriptor times out");
    close(pipe_fds[0]);
    close(pipe_fds[1]);
}

static void two_readers_entry(void *arg) {
    expect(ms_task_wait_fd(pipe_fds[0], MS_WAIT_READ, -1) == MS_WAIT_READ, "woken");
    char byte = 0;
    if (read(pipe_fds[0], &byte, 1) == 1) {
        (*(int *)arg)++;
    }
}

static void test_two_waiters_one_descriptor(void) {
    expect(pipe(pipe_fds) == 0, "pipe");
    int got = 0;
    const MsTaskHandle first = spawn(two_readers_entry, &got, 0);
    const MsTaskHandle second = spawn(two_readers_entry, &got, 0);
    ms_task_yield();
    expect(write(pipe_fds[1], "ab", 2) == 2, "write");
    (void)join(first, NULL);
    (void)join(second, NULL);
    expect(got == 2, "both readers got a byte");
    close(pipe_fds[0]);
    close(pipe_fds[1]);
}

/* ---- cancellation ---- */

static void cancel_victim(void *arg) {
    const uint32_t result = ms_task_sleep(60 * 1000000000LL);
    *(uint32_t *)arg = result;
    expect(ms_cancel_flag() != 0, "the cancel flag is up");
}

static void test_cancel_parked(void) {
    uint32_t result = 0;
    const MsTaskHandle victim = spawn(cancel_victim, &result, 0);
    ms_task_yield();
    const int64_t start = ms_sched_now();
    ms_task_cancel(victim);
    (void)join(victim, NULL);
    expect(result == MS_WAIT_CANCELLED, "a parked task wakes cancelled");
    expect(elapsed_ms(start) < 1000, "without waiting for the timer");
}

static void test_cancel_unknown_handle(void) {
    ms_task_cancel(0);
    ms_task_cancel(0xdeadbeef00000001ULL);
}

static void shielded_victim(void *arg) {
    ms_shield_enter();
    *(uint32_t *)arg = ms_task_sleep(3 * 1000000LL);
    ms_shield_exit();
    *(uint32_t *)arg |= ms_cancel_flag() != 0 ? 0x100u : 0;
}

static void test_cancel_respects_shield(void) {
    uint32_t result = 0;
    const MsTaskHandle victim = spawn(shielded_victim, &result, 0);
    ms_task_yield();
    ms_task_cancel(victim);
    (void)join(victim, NULL);
    expect((result & 0xffu) == MS_WAIT_TIMEOUT, "a shielded park is not cancelled");
    expect((result & 0x100u) != 0, "the cancel applies once the shield is lowered");
}

static void test_join_cancelled_caller(void) {
    uint32_t result = 0;
    const MsTaskHandle victim = spawn(cancel_victim, &result, 0);
    ms_cancel_set_task(1);
    uint8_t outcome = 0;
    MsFaultText text = {0};
    expect(ms_task_join(victim, &outcome, &text) == MS_TASK_OK && outcome == 2, "a cancelled caller gets outcome 2");
    ms_cancel_set_task(0);
    ms_task_cancel(victim);
    (void)join(victim, NULL);
}

static void stopped_task(void *arg) { *(uint32_t *)arg = ms_task_sleep(60 * 1000000000LL); }

static void test_stop_request(void) {
    uint32_t a = 0;
    uint32_t b = 0;
    const MsTaskHandle first = spawn(stopped_task, &a, 0);
    const MsTaskHandle second = spawn(shielded_victim, &b, 0);
    ms_task_yield();
    ms_shield_enter(); /* the test's own flow is shielded, as an isolate's root flow is while it waits for main */
    ms_sched_stop(15);
    (void)join(first, NULL);
    (void)join(second, NULL);
    expect(a == MS_WAIT_CANCELLED, "a stop request cancels a parked task");
    expect((b & 0xffu) == MS_WAIT_TIMEOUT, "but not a shielded one");
    ms_sched_stop(0);
    ms_shield_exit();
}

/* A park that reports a cancel is followed by the unwind, as generated code does. */
static void limited_task(void *arg) {
    ms_task_limit_current(2 * 1000000LL);
    *(uint32_t *)arg = ms_task_sleep(60 * 1000000000LL);
    if (*(uint32_t *)arg == MS_WAIT_CANCELLED) {
        ms_cancelled();
    }
}

static void test_time_limit(void) {
    uint32_t result = 0;
    const int64_t start = ms_sched_now();
    const MsTaskHandle task = spawn(limited_task, &result, 0);
    expect(join(task, NULL) == MS_GUARD_CANCELLED, "a task past its time limit ends cancelled");
    expect(result == MS_WAIT_CANCELLED, "its park reported the cancel");
    expect(ms_task_timed_out(), "and the join says it timed out");
    expect(elapsed_ms(start) >= 2 && elapsed_ms(start) < 1000, "after about the limit");
}

static void read_limited(void *arg) {
    ms_task_read_limit(2 * 1000000LL);
    *(uint32_t *)arg = ms_task_sleep(60 * 1000000000LL);
}

static void test_read_limit(void) {
    uint32_t result = 0;
    (void)join(spawn(read_limited, &result, 0), NULL);
    expect(result == MS_WAIT_TIMEOUT, "a read limit ends a long park with a timeout");
}

/* ---- guards, cleanups and faults ---- */

static int cleanup_order[4];
static int cleanup_count;

static void note_cleanup(uint8_t *arg) { cleanup_order[cleanup_count++] = (int)(uintptr_t)arg; }

static void faulting(void *arg) {
    (void)arg;
    (void)ms_cleanup_push(note_cleanup, (void *)(uintptr_t)1);
    (void)ms_cleanup_push(note_cleanup, (void *)(uintptr_t)2);
    ms_task_sleep(1000000);
    (void)ms_cleanup_push(note_cleanup, (void *)(uintptr_t)3);
    MsFaultText text = {.bytes = msrt_alloc(5), .length = 4};
    memcpy(text.bytes, "boom", 5);
    (void)ms_guard_leave(MS_GUARD_FAULT, text);
}

static void test_guard_fault(void) {
    cleanup_count = 0;
    MsFaultText message = {0};
    const MsTaskHandle task = spawn(faulting, NULL, 0);
    expect(join(task, &message) == MS_GUARD_FAULT, "the task faulted");
    expect(message.length == 4 && memcmp(message.bytes, "boom", 4) == 0, "the message came through");
    msrt_free(message.bytes);
    expect(cleanup_count == 0, "a guard that is left by a fault does not run cleanups itself");
}

static void unwinding_entry(void *arg) {
    (void)arg;
    (void)ms_cleanup_push(note_cleanup, (void *)(uintptr_t)1);
    (void)ms_cleanup_push(note_cleanup, (void *)(uintptr_t)2);
    ms_cancelled();
}

static void test_cancelled_unwinds(void) {
    cleanup_count = 0;
    expect(join(spawn(unwinding_entry, NULL, 0), NULL) == MS_GUARD_CANCELLED, "cancelled outcome");
    expect(cleanup_count == 2 && cleanup_order[0] == 2 && cleanup_order[1] == 1, "cleanups ran innermost first");
}

static void cleanup_inner(uint8_t *arg) { (void)arg; }

static void test_cleanup_handles(void) {
    cleanup_count = 0;
    const size_t base = ms_cleanup_base();
    const size_t one = ms_cleanup_push(note_cleanup, (void *)(uintptr_t)1);
    const size_t two = ms_cleanup_push(note_cleanup, (void *)(uintptr_t)2);
    const size_t three = ms_cleanup_push(cleanup_inner, NULL);
    expect(two == one + 1 && three == two + 1, "handles count up");
    ms_cleanup_remove(two);
    ms_cleanup_discard(three);
    ms_cleanup_run(one);
    expect(cleanup_count == 1 && cleanup_order[0] == 1, "only the live action ran");
    expect(ms_cleanup_base() == base, "the stack is back where it began");
}

static void deadlocked(void *arg) {
    (void)arg;
    uint64_t value = 0;
    uint32_t result = 0;
    const uint64_t token = ms_token_new(0);
    (void)ms_token_park(token, -1, &value, &result); /* nothing can post it: the scheduler reports a deadlock */
}

static void test_deadlock(void) {
    last_fault[0] = 0;
    MsFaultText message = {0};
    expect(join(spawn(deadlocked, NULL, 0), &message) == MS_GUARD_FAULT, "the deadlock is a fault of the waiter");
    expect(last_fault_kind == MS_FAULT_KIND_DEADLOCK && strncmp(last_fault, "deadlock:", 9) == 0, "reported as one");
    msrt_free(message.bytes);
}

/* ---- stack segments ---- */

static int64_t deep(int64_t depth, MsTask *task);

typedef struct DeepCall {
    int64_t depth;
    int64_t result;
} DeepCall;

static void deep_shim(void *block) {
    DeepCall *const call = block;
    call->result = deep(call->depth, ms_task_running());
}

/* Recurses with a frame of about 4 KiB; below the limit it continues on the next segment. */
static int64_t deep(int64_t depth, MsTask *task) {
    volatile char frame[4096];
    frame[0] = 1;
    if (depth == 0) {
        return frame[0];
    }
    if ((uintptr_t)__builtin_frame_address(0) < task->unwind.hdr.limit) {
        DeepCall *const call = msrt_alloc(sizeof *call);
        call->depth = depth;
        expect(ms_task_grow(deep_shim, call) == MS_TASK_OK, "grow");
        const int64_t result = call->result;
        msrt_free(call);
        return result + 1;
    }
    return deep(depth - 1, task) + frame[0];
}

static void deep_entry(void *arg) { *(int64_t *)arg = deep(600, ms_task_running()); }

static void test_stack_growth(void) {
    int64_t result = 0;
    (void)join(spawn(deep_entry, &result, 0), NULL);
    expect(result == 601 || result == 600 + 1 || result > 0, "the recursion completed across segments");
}

/* ---- the main task ---- */

static void main_task(void *arg) { *(int *)arg = 17; }

static void test_run_main(void) {
    int value = 0;
    uint8_t outcome = 9;
    MsFaultText message = {0};
    expect(ms_task_run_main(main_task, &value, 0, &outcome, &message) == MS_TASK_OK, "run_main");
    expect(outcome == MS_GUARD_OK && value == 17, "the main task ran on its own region");
    expect(ms_task_count() == 1, "and is gone");
}

/* ---- many tasks ---- */

enum { MANY = 20000 };

static uint64_t many_token;

static void parked_task(void *arg) {
    uint32_t result = 0;
    uint64_t value = 0;
    (void)ms_token_park(many_token, -1, &value, &result);
    *(uint32_t *)arg = result;
}

static long resident_kib(void) {
    FILE *const statm = fopen("/proc/self/statm", "r");
    long pages = 0;
    long resident = 0;
    if (statm == NULL) {
        return 0;
    }
    if (fscanf(statm, "%ld %ld", &pages, &resident) != 2) {
        resident = 0;
    }
    fclose(statm);
    return resident * (long)sysconf(_SC_PAGESIZE) / 1024;
}

/* Parks MANY tasks on one descriptor each... on tokens would fault (one waiter per token), so each takes its
 * own token; then cancels all of them. Reports bytes per parked task and the cancel time. */
static void test_many_parked_tasks(void) {
    MsTaskHandle *handles = msrt_alloc(MANY * sizeof *handles);
    uint64_t *tokens = msrt_alloc(MANY * sizeof *tokens);
    uint32_t *results = msrt_alloc(MANY * sizeof *results);
    (void)many_token;
    const long before = resident_kib();
    for (int i = 0; i < MANY; i++) {
        tokens[i] = ms_token_new(0);
        many_token = tokens[i];
        handles[i] = spawn(parked_task, &results[i], 0);
        ms_task_yield(); /* the task runs to its park, so the token is bound before the next one is made */
    }
    const long parked = resident_kib();
    const int64_t start = ms_sched_now();
    for (int i = 0; i < MANY; i++) {
        ms_task_cancel(handles[i]);
    }
    for (int i = 0; i < MANY; i++) {
        expect(join(handles[i], NULL) == MS_GUARD_OK && results[i] == MS_WAIT_CANCELLED, "cancelled");
        expect(ms_token_free(tokens[i]) == MS_TOKEN_OK, "free token");
    }
    printf("core_task: %d parked tasks held %ld KiB resident (%ld bytes each, stack pages included); "
           "cancelling and joining them took %lld ms\n",
           MANY, parked - before, (parked - before) * 1024 / MANY, (long long)elapsed_ms(start));
    msrt_free(handles);
    msrt_free(tokens);
    msrt_free(results);
}

static void test_record_sizes(void) {
    printf("core_task: record %zu B, handle slot %zu B, waiter %zu B, token %zu B, timer %zu B\n", sizeof(MsTask),
           sizeof(MsTaskSlot), sizeof(MsWaiter), sizeof(MsToken), sizeof(MsTimer));
}

int main(void) {
    msrt_heap_claim();
    install();
    test_yield_order();
    test_join_errors();
    test_sleep_order();
    test_tokens();
    test_token_free_while_waited_on();
    test_descriptor_wait();
    test_two_waiters_one_descriptor();
    test_cancel_parked();
    test_cancel_unknown_handle();
    test_cancel_respects_shield();
    test_join_cancelled_caller();
    test_stop_request();
    test_time_limit();
    test_read_limit();
    test_guard_fault();
    test_cancelled_unwinds();
    test_cleanup_handles();
    test_deadlock();
    test_stack_growth();
    test_run_main();
    test_many_parked_tasks();
    test_record_sizes();
    ms_sched_teardown();
    puts("core_task: ok");
    return 0;
}
