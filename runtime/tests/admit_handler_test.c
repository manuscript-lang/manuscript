#define _POSIX_C_SOURCE 200809L
/* Unit tests for runtime/net/admission.c (the request counter) and runtime/net/handler.c (the shared request
   handler): the limit and its release, handles that share one count across threads, a handler that reads the
   exchange it was given, takes it once, and reports keep, and the closure's end with the last handle. */
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../net/status.h"
#include "../std/abi.h"
#include "ms_rt/alloc.h"
#include "ms_rt/obj.h"
#include "ms_rt/xchg.h"
#include "ms_sched.h"

static int failed;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #c); failed = 1; } } while (0)

void ms_net_write_text(MsStr *out, const char *text) { (void)text; if (out != NULL) memset(out, 0, sizeof *out); }

/* ---- a stand-in exchange: msstd_xchg_share hands out counted copies ---- */

typedef struct FakeExchange {
    MsObj header;
} FakeExchange;
static int live_copies;

static void fake_drop(MsObj *object) {
    live_copies--;
    msrt_free(object);
}

void *msstd_xchg_share(const void *handle) {
    (void)handle;
    FakeExchange *copy = msrt_alloc(sizeof *copy);
    copy->header.clone = NULL;
    copy->header.drop = fake_drop;
    live_copies++;
    return copy;
}

/* ---- the handler closure: `code` is what the compiler emits for `fn() Void` ---- */

typedef struct Closure {
    MsObj header;
    void (*code)(struct Closure *);
    int *calls;
    int keep;
    int take_twice;
} Closure;
static int closure_drops;

static void closure_drop(MsObj *object) {
    closure_drops++;
    msrt_free(object);
}

static void closure_body(Closure *self) {
    __atomic_fetch_add(self->calls, 1, __ATOMIC_RELAXED);
    void *exchange = msstd_handler_take();
    CHECK(exchange != NULL);
    if (self->take_twice) CHECK(msstd_handler_take() == NULL); /* the slot is spent */
    msrt_obj_drop(exchange);
    msstd_handler_keep((uint8_t)self->keep);
}

static Closure *closure_new(int *calls, int keep) {
    Closure *c = msrt_alloc_zeroed(sizeof *c);
    c->header.clone = NULL;
    c->header.drop = closure_drop;
    c->code = closure_body;
    c->calls = calls;
    c->keep = keep;
    c->take_twice = 1;
    return c;
}

/* ---- admission ---- */

static void test_admission_limit(void) {
    void *admit = msstd_admit_new(1, 2);
    CHECK(msstd_admit_enter(admit) == STATUS_OK);
    CHECK(msstd_admit_enter(admit) == STATUS_OK);
    CHECK(msstd_admit_enter(admit) == STATUS_LIMIT_EXCEEDED); /* the third is turned away and not counted */
    CHECK(msstd_admit_enter(admit) == STATUS_LIMIT_EXCEEDED);
    msstd_admit_leave(admit);
    CHECK(msstd_admit_enter(admit) == STATUS_OK); /* a leave frees one slot */
    CHECK(msstd_admit_enter(admit) == STATUS_LIMIT_EXCEEDED);
    msstd_admit_leave(admit);
    msstd_admit_leave(admit);
    msrt_obj_drop(admit);
}

static void test_admission_unlimited_and_zero(void) {
    void *open = msstd_admit_new(0, 0); /* no max: the number is ignored */
    for (int i = 0; i < 1000; i++) CHECK(msstd_admit_enter(open) == STATUS_OK);
    for (int i = 0; i < 1000; i++) msstd_admit_leave(open);
    msrt_obj_drop(open);
    void *none = msstd_admit_new(1, 0); /* a max of zero admits nothing */
    CHECK(msstd_admit_enter(none) == STATUS_LIMIT_EXCEEDED);
    msrt_obj_drop(none);
}

typedef struct Worker {
    void *admit;
    int admitted;
} Worker;

static void *worker_run(void *argument) {
    Worker *worker = argument;
    for (int i = 0; i < 1000; i++) {
        if (msstd_admit_enter(worker->admit) == STATUS_OK) {
            worker->admitted++;
            msstd_admit_leave(worker->admit);
        }
    }
    return NULL;
}

static void test_admission_shared_across_threads(void) {
    void *admit = msstd_admit_new(1, 3);
    void *first = msstd_admit_share(admit);
    msrt_obj_drop(admit); /* the count outlives the handle that made it */
    enum { THREADS = 4 };
    pthread_t threads[THREADS];
    Worker workers[THREADS];
    for (int i = 0; i < THREADS; i++) {
        workers[i] = (Worker){.admit = msstd_admit_share(first)};
        CHECK(pthread_create(&threads[i], NULL, worker_run, &workers[i]) == 0);
    }
    for (int i = 0; i < THREADS; i++) {
        pthread_join(threads[i], NULL);
        msrt_obj_drop(workers[i].admit);
    }
    /* every enter was paired with a leave, so the count is back at zero: exactly the limit fits again */
    CHECK(msstd_admit_enter(first) == STATUS_OK);
    CHECK(msstd_admit_enter(first) == STATUS_OK);
    CHECK(msstd_admit_enter(first) == STATUS_OK);
    CHECK(msstd_admit_enter(first) == STATUS_LIMIT_EXCEEDED);
    msrt_obj_drop(first);
}

/* ---- handler ---- */

static void test_handler_call(void) {
    int calls = 0;
    closure_drops = 0;
    void *handler = msstd_handler_new(closure_new(&calls, 1));
    MsStr err;
    memset(&err, 0, sizeof err);
    uint8_t keep = 0;
    FakeExchange exchange;
    CHECK(msstd_handler_call(handler, &exchange, &keep, &err) == STATUS_OK && keep == 1 && calls == 1);
    CHECK(live_copies == 0); /* the closure took one copy and dropped it */
    CHECK(msstd_handler_take() == NULL); /* nothing is left in the slot after the call */
    keep = 9;
    CHECK(msstd_handler_call(handler, &exchange, &keep, &err) == STATUS_OK && keep == 1 && calls == 2);
    msrt_obj_drop(handler);
    CHECK(closure_drops == 1);
}

static void test_handler_keep_defaults_to_close(void) {
    int calls = 0;
    void *handler = msstd_handler_new(closure_new(&calls, 0));
    MsStr err;
    memset(&err, 0, sizeof err);
    uint8_t keep = 7;
    FakeExchange exchange;
    CHECK(msstd_handler_call(handler, &exchange, &keep, &err) == STATUS_OK && keep == 0);
    msrt_obj_drop(handler);
}

static void test_handler_closure_ends_with_last_handle(void) {
    int calls = 0;
    closure_drops = 0;
    void *first = msstd_handler_new(closure_new(&calls, 1));
    void *second = msstd_handler_share(first);
    msrt_obj_drop(first);
    CHECK(closure_drops == 0); /* a handle remains */
    MsStr err;
    memset(&err, 0, sizeof err);
    uint8_t keep = 0;
    FakeExchange exchange;
    CHECK(msstd_handler_call(second, &exchange, &keep, &err) == STATUS_OK && calls == 1);
    msrt_obj_drop(second);
    CHECK(closure_drops == 1);
}

typedef struct CallerThread {
    void *handler;
    int calls;
    int ok;
} CallerThread;

static void *caller_run(void *argument) {
    CallerThread *caller = argument;
    FakeExchange exchange;
    MsStr err;
    memset(&err, 0, sizeof err);
    caller->ok = 1;
    for (int i = 0; i < 200; i++) {
        uint8_t keep = 0;
        if (msstd_handler_call(caller->handler, &exchange, &keep, &err) != STATUS_OK || keep != 1) caller->ok = 0;
    }
    return NULL;
}

static void test_handler_threads(void) {
    /* each thread has its own slots: calls on four threads at once all see their own exchange and keep */
    int calls = 0;
    Closure *closure = closure_new(&calls, 1);
    void *handler = msstd_handler_new(closure);
    enum { THREADS = 4 };
    pthread_t threads[THREADS];
    CallerThread callers[THREADS];
    for (int i = 0; i < THREADS; i++) {
        callers[i] = (CallerThread){.handler = msstd_handler_share(handler)};
        CHECK(pthread_create(&threads[i], NULL, caller_run, &callers[i]) == 0);
    }
    for (int i = 0; i < THREADS; i++) {
        pthread_join(threads[i], NULL);
        CHECK(callers[i].ok);
        msrt_obj_drop(callers[i].handler);
    }
    CHECK(calls == THREADS * 200);
    msrt_obj_drop(handler);
}

int main(void) {
    test_admission_limit();
    test_admission_unlimited_and_zero();
    test_admission_shared_across_threads();
    test_handler_call();
    test_handler_keep_defaults_to_close();
    test_handler_closure_ends_with_last_handle();
    test_handler_threads();
    puts(failed ? "admit_handler_test: FAILED" : "admit_handler_test: ok");
    return failed;
}
