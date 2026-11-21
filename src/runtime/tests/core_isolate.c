/* Unit test of the isolate registry and mail (src/runtime/core/isolate.c): a thread posts to a token another isolate
 * is parked on, and a stream of mail of a custom kind reaches the owner's hook in order. Runs under the sanitizers
 * by `make c-test`. */
#define _DEFAULT_SOURCE 1
#include <poll.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "../core/scheduler.h"
#include "ms_rt/alloc.h"

static void expect(bool condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "core_isolate: failed: %s\n", what);
        exit(1);
    }
}

static int wake_pipe[2];

static void wake(void *argument) {
    (void)argument;
    const char byte = 1;
    (void)!write(wake_pipe[1], &byte, 1);
}

static int fake_watch(int fd, uint32_t events) {
    (void)fd;
    (void)events;
    return MS_POLL_ARMED;
}

static void fake_fd(int fd) { (void)fd; }

static long fake_wait(int64_t timeout_ns, MsPollReady *out, size_t capacity) {
    (void)out;
    (void)capacity;
    struct pollfd fds[1] = {{.fd = wake_pipe[0], .events = POLLIN}};
    const int ms = timeout_ns < 0 ? -1 : (int)((timeout_ns + 999999) / 1000000);
    if (poll(fds, 1, timeout_ns == 0 ? 0 : ms) > 0) {
        char drain[64];
        (void)!read(wake_pipe[0], drain, sizeof drain);
    }
    return 0;
}

static void fake_fault(MsFaultKind kind, const char *message) {
    (void)kind;
    fprintf(stderr, "core_isolate: fault: %s\n", message);
    exit(1);
}

static void fake_exit(int status) {
    fprintf(stderr, "core_isolate: exit %d\n", status);
    exit(1);
}

static size_t seen;
static uint64_t last_seen;
static bool in_order = true;

static void on_mail(MsMail *mail) {
    if (mail->a != last_seen + 1) {
        in_order = false;
    }
    last_seen = mail->a;
    seen++;
    msrt_free(mail);
}

static uint32_t target;
static uint64_t shared_token;

static void *poster(void *argument) {
    (void)argument;
    usleep(20 * 1000);
    ms_token_post_remote(shared_token, 77);
    for (uint64_t i = 1; i <= 1000; i++) {
        MsMail *const mail = msrt_alloc(sizeof *mail);
        *mail = (MsMail){.kind = MS_MAIL_PROMISE, .a = i};
        expect(ms_isolate_post(target, mail), "post to a live isolate");
    }
    ms_token_post_remote(shared_token + 0, 0); /* a stale second post is dropped */
    return NULL;
}

static void main_task(void *argument) {
    (void)argument;
    shared_token = ms_token_new(MS_TOKEN_REMOTE);
    expect(shared_token != 0, "a remote token");
    pthread_t thread;
    expect(pthread_create(&thread, NULL, poster, NULL) == 0, "thread");
    uint64_t value = 0;
    uint32_t result = 99;
    expect(ms_token_park(shared_token, -1, &value, &result) == MS_TOKEN_OK && result == 0 && value == 77,
           "the remote post wakes the parked task with its value");
    (void)ms_token_free(shared_token);
    while (seen < 1000) {
        ms_task_yield();
        ms_task_sleep(1000 * 1000);
    }
    expect(in_order, "mail arrives in order");
    pthread_join(thread, NULL);
}

int main(void) {
    msrt_heap_claim();
    expect(pipe(wake_pipe) == 0, "pipe");
    MsSchedHooks hooks = {.fault = fake_fault, .exit_process = fake_exit, .mail = on_mail};
    const MsPollOps poll_ops = {.watch = fake_watch, .unwatch = fake_fd, .forget = fake_fd, .wait = fake_wait};
    ms_sched_set_hooks(&hooks, &poll_ops);
    target = ms_sched_attach(wake, NULL);
    expect(target != MS_NO_ISOLATE && ms_isolate_live(target), "attached");
    uint8_t outcome = 9;
    MsFaultText message = {0};
    expect(ms_task_run_main(main_task, NULL, 0, &outcome, &message) == MS_TASK_OK && outcome == 0, "main task");
    ms_sched_teardown();
    expect(!ms_isolate_live(target), "teardown unregisters");
    puts("core_isolate: ok");
    return 0;
}
