/* The task and token ABI over the scheduler: spawn and join, sleeping, tokens and the faults a misuse raises. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../core/scheduler.h"
#include "ms_rt/task.h"

static void expect(bool condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "core_task_abi: failed: %s\n", what);
        exit(1);
    }
}

static char last_fault[256];

/* A fault leaves the running task through its guard, as the real fault path does. */
static void fake_fault(MsFaultKind kind, const char *message) {
    (void)kind;
    snprintf(last_fault, sizeof last_fault, "%s", message);
    const size_t length = strlen(message);
    MsFaultText text = {.bytes = msrt_alloc(length + 1), .length = length};
    memcpy(text.bytes, message, length + 1);
    expect(ms_guard_leave(MS_GUARD_FAULT, text), "fault with no guard");
    for (;;) {
    }
}

static void fake_exit(int status) {
    fprintf(stderr, "core_task_abi: unexpected exit %d\n", status);
    exit(1);
}

static long no_events(int64_t timeout_ns, MsPollReady *out, size_t capacity) {
    (void)timeout_ns;
    (void)out;
    (void)capacity;
    return 0;
}

static int arm(int fd, uint32_t events) {
    (void)fd;
    (void)events;
    return MS_POLL_ARMED;
}

static void release(int fd) { (void)fd; }

static int counter;

static void count_up(void *arg) {
    counter += (int)(uintptr_t)arg;
    (void)msrt_task_sleep(1000000);
    counter += 1;
}

static void test_spawn_and_join(void) {
    const uint64_t handle = msrt_task_spawn(count_up, (void *)(uintptr_t)10, 0, 0);
    expect(msrt_task_count() >= 1, "the task counts");
    MsStr message = {0};
    expect(msrt_task_join(handle, &message) == 0, "returned");
    expect(counter == 11, "the task ran to its end");
}

static void post_later(void *arg) {
    msrt_token_post((uint64_t)(uintptr_t)arg, 42);
}

static void test_token_round_trip(void) {
    const uint64_t token = msrt_token_new(0);
    const uint64_t task = msrt_task_spawn(post_later, (void *)(uintptr_t)token, 0, 0);
    uint64_t value = 0;
    expect(msrt_token_park(token, -1, &value) == 0 && value == 42, "the post arrives");
    MsStr message = {0};
    expect(msrt_task_join(task, &message) == 0, "poster returned");
    msrt_token_free(token);
}

static void test_park_timeout(void) {
    const uint64_t token = msrt_token_new(0);
    uint64_t value = 0;
    expect(msrt_token_park(token, 1000000, &value) == MS_WAIT_TIMEOUT, "times out");
    msrt_token_free(token);
}

static void park_freed(void *arg) {
    uint64_t value = 0;
    (void)msrt_token_park((uint64_t)(uintptr_t)arg, 0, &value);
}

static void test_fault_text(void) {
    const uint64_t token = msrt_token_new(0);
    msrt_token_free(token);
    const uint64_t task = msrt_task_spawn(park_freed, (void *)(uintptr_t)token, 0, 0);
    MsStr message = {0};
    expect(msrt_task_join(task, &message) == 1, "faulted");
    expect(strcmp(last_fault, "park on a token that does not exist") == 0, "message");
    expect(ms_str_len(&message) == strlen(last_fault), "the report reaches the joiner");
    msrt_string_free(&message);
}

int main(void) {
    msrt_heap_claim();
    const MsSchedHooks hooks = {.fault = fake_fault, .exit_process = fake_exit};
    const MsPollOps poll_ops = {.watch = arm, .unwatch = release, .forget = release, .wait = no_events};
    ms_sched_set_hooks(&hooks, &poll_ops);
    test_spawn_and_join();
    test_token_round_trip();
    test_park_timeout();
    test_fault_text();
    ms_sched_teardown();
    puts("core_task_abi: ok");
    return 0;
}
