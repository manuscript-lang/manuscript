/* Unit test of the C pipe (src/runtime/core/pipe.c) on the C scheduler and promise table: order, a parked read finished
 * by a write, the end of a pipe, flush back pressure, a dropped read, values that own memory,
 * several writers and a cancelled read. Run under the sanitizers by `make c-test`. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../core/promise.h"
#include "../core/scheduler.h"
#include "ms_rt/alloc.h"
#include "ms_rt/pipe.h"
#include "support/sched_env.h"

static void expect(bool condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "core_pipe: failed: %s\n", what);
        exit(1);
    }
}

static int64_t write_int(int64_t pipe, int64_t value) { return msrt_pipe_write(pipe, (uint8_t *)&value, &msrt_desc_int); }

/* The next value, or false when the read finished with none. */
static bool read_int(int64_t pipe, int64_t *value) {
    const MsPromise read = (MsPromise)msrt_pipe_read(pipe);
    expect(ms_promise_wait(read, -1) == MS_PROMISE_OK, "a read finishes");
    const bool got = ms_promise_take(read, &msrt_desc_int, (uint8_t *)value);
    ms_promise_drop(read);
    return got;
}

static void test_order_then_end(void) {
    const int64_t pipe = msrt_pipe_new(8);
    for (int64_t i = 0; i < 5; i++) {
        expect(write_int(pipe, i) == MS_PIPE_WRITTEN, "write under capacity");
    }
    int64_t value = -1;
    for (int64_t i = 0; i < 3; i++) {
        expect(msrt_pipe_try(pipe, &msrt_desc_int, (uint8_t *)&value) == 1 && value == i, "try gives values in order");
    }
    expect(msrt_pipe_ended(pipe) == 0, "not ended with a writer");
    msrt_pipe_close_writer(pipe);
    expect(msrt_pipe_ended(pipe) == 0, "not ended while values are queued");
    expect(read_int(pipe, &value) && value == 3, "read after close_writer");
    expect(read_int(pipe, &value) && value == 4, "read the last value");
    expect(!read_int(pipe, &value), "then the end, with no value");
    expect(msrt_pipe_ended(pipe) == 1, "ended");
    expect(msrt_pipe_try(pipe, &msrt_desc_int, (uint8_t *)&value) == 0, "nothing to try");
    msrt_pipe_close_reader(pipe);
    expect(msrt_pipe_ended(pipe) == 1, "a retired pipe reads as ended");
    expect(write_int(pipe, 1) == MS_PIPE_CLOSED, "a stale id refuses writes");
}

typedef struct WriterJob {
    int64_t pipe;
    int64_t first;
    int64_t count;
    bool close_at_end;
} WriterJob;

static void writer_task(void *arg) {
    WriterJob *job = arg;
    for (int64_t i = 0; i < job->count; i++) {
        (void)write_int(job->pipe, job->first + i);
        ms_task_yield();
    }
    if (job->close_at_end) {
        msrt_pipe_close_writer(job->pipe);
    }
}

static void spawn_writer(WriterJob *job) {
    MsTaskStatus status = MS_TASK_OK;
    expect(ms_task_spawn(writer_task, job, MS_SPAWN_DETACHED, 0, &status) != 0 && status == MS_TASK_OK, "spawn");
}

static void test_parked_read_finished_by_writer(void) {
    const int64_t pipe = msrt_pipe_new(4);
    static WriterJob job;
    job = (WriterJob){.pipe = pipe, .first = 10, .count = 3, .close_at_end = true};
    spawn_writer(&job);
    int64_t value = 0;
    for (int64_t i = 0; i < 3; i++) {
        expect(read_int(pipe, &value) && value == 10 + i, "a parked read gets each written value");
    }
    expect(!read_int(pipe, &value), "closing the last writer ends the parked read");
    msrt_pipe_close_reader(pipe);
}

static void test_several_writers(void) {
    const int64_t pipe = msrt_pipe_new(64);
    msrt_pipe_add_writer(pipe);
    static WriterJob a, b;
    a = (WriterJob){.pipe = pipe, .first = 0, .count = 20, .close_at_end = true};
    b = (WriterJob){.pipe = pipe, .first = 100, .count = 20, .close_at_end = false};
    spawn_writer(&a);
    spawn_writer(&b);
    int64_t value = 0;
    int64_t next_a = 0;
    int64_t next_b = 100;
    for (int i = 0; i < 40; i++) {
        expect(read_int(pipe, &value), "a value from either writer");
        if (value < 100) {
            expect(value == next_a++, "each writer's order holds");
        } else {
            expect(value == next_b++, "each writer's order holds");
        }
    }
    msrt_pipe_close_writer(pipe); /* the Pipe value's own writer, the third */
    expect(!read_int(pipe, &value), "the end once every writer closed");
    msrt_pipe_close_reader(pipe);
}

static void test_flush_back_pressure(void) {
    const int64_t pipe = msrt_pipe_new(2);
    expect(write_int(pipe, 1) == MS_PIPE_WRITTEN && write_int(pipe, 2) == MS_PIPE_WRITTEN, "within capacity");
    expect(write_int(pipe, 3) == MS_PIPE_FULL, "above capacity answers full");
    const MsPromise flush = (MsPromise)msrt_pipe_flush(pipe);
    expect(!ms_promise_done(flush), "a flush above capacity waits");
    int64_t value = 0;
    expect(msrt_pipe_try(pipe, &msrt_desc_int, (uint8_t *)&value) == 1 && value == 1, "the reader takes a value");
    expect(ms_promise_wait(flush, -1) == MS_PROMISE_OK, "the flush finishes once the backlog fits");
    ms_promise_drop(flush);
    const MsPromise again = (MsPromise)msrt_pipe_flush(pipe);
    expect(ms_promise_done(again), "a flush within capacity is done at once");
    ms_promise_drop(again);
    msrt_pipe_close_writer(pipe);
    msrt_pipe_close_reader(pipe);
}

static void test_close_reader_releases_flush_and_refuses_writes(void) {
    const int64_t pipe = msrt_pipe_new(0);
    expect(write_int(pipe, 1) == MS_PIPE_FULL, "capacity zero is full at one");
    const MsPromise flush = (MsPromise)msrt_pipe_flush(pipe);
    expect(!ms_promise_done(flush), "waits");
    msrt_pipe_close_reader(pipe);
    expect(ms_promise_wait(flush, -1) == MS_PROMISE_OK, "a closed reader releases the flush");
    ms_promise_drop(flush);
    expect(write_int(pipe, 2) == MS_PIPE_CLOSED, "a closed reader refuses writes");
    msrt_pipe_close_writer(pipe);
}

static void test_dropped_read_leaves_the_queue_alone(void) {
    const int64_t pipe = msrt_pipe_new(4);
    const MsPromise read = (MsPromise)msrt_pipe_read(pipe);
    ms_promise_drop(read);
    /* The next write queues the value instead of handing it to the dropped read. */
    expect(write_int(pipe, 7) == MS_PIPE_WRITTEN, "write after a dropped read");
    int64_t value = 0;
    expect(read_int(pipe, &value) && value == 7, "the value is still there");
    msrt_pipe_close_writer(pipe);
    msrt_pipe_close_reader(pipe);
}

static void test_cancelled_read_leaves_the_wait(void) {
    const int64_t pipe = msrt_pipe_new(4);
    const MsPromise read = (MsPromise)msrt_pipe_read(pipe);
    expect(!ms_promise_done(read), "an empty pipe parks the read");
    ms_promise_cancel(read);
    ms_promise_drop(read);
    int64_t value = 0;
    static WriterJob job;
    job = (WriterJob){.pipe = pipe, .first = 5, .count = 1, .close_at_end = true};
    spawn_writer(&job);
    expect(read_int(pipe, &value) && value == 5, "a new read works after the cancel");
    msrt_pipe_close_reader(pipe);
}

/* A value that owns memory: dropping the pipe's queue frees it (the sanitizer reports a leak otherwise). */
static void test_owned_values_are_dropped(void) {
    const int64_t pipe = msrt_pipe_new(8);
    for (int i = 0; i < 3; i++) {
        MsList bytes = {.ptr = msrt_alloc(100), .len = 100, .cap = 100};
        memset(bytes.ptr, i, bytes.len);
        expect(msrt_pipe_write(pipe, (uint8_t *)&bytes, &msrt_desc_bytes) == MS_PIPE_WRITTEN, "write owned bytes");
    }
    MsList out = {0};
    expect(msrt_pipe_try(pipe, &msrt_desc_bytes, (uint8_t *)&out) == 1 && out.len == 100 && out.ptr[0] == 0, "try moves the bytes out");
    msrt_free(out.ptr);
    const MsPromise read = (MsPromise)msrt_pipe_read(pipe);
    expect(ms_promise_wait(read, -1) == MS_PROMISE_OK && ms_promise_take(read, &msrt_desc_bytes, (uint8_t *)&out) && out.ptr[0] == 1,
           "read hands over the next");
    msrt_free(out.ptr);
    ms_promise_drop(read);
    msrt_pipe_close_writer(pipe);
    msrt_pipe_close_reader(pipe); /* frees the third */
}

static void test_ids_are_not_reused_while_stale(void) {
    const int64_t first = msrt_pipe_new(1);
    msrt_pipe_close_writer(first);
    msrt_pipe_close_reader(first);
    const int64_t second = msrt_pipe_new(1);
    expect(second != first, "a reused cell has a new generation");
    expect(write_int(first, 1) == MS_PIPE_CLOSED, "the stale id refuses writes");
    expect(write_int(second, 1) == MS_PIPE_WRITTEN, "the new pipe works");
    msrt_pipe_close_writer(second);
    msrt_pipe_close_reader(second);
}

static void entry(void *arg) {
    (void)arg;
    test_order_then_end();
    test_parked_read_finished_by_writer();
    test_several_writers();
    test_flush_back_pressure();
    test_close_reader_releases_flush_and_refuses_writes();
    test_dropped_read_leaves_the_queue_alone();
    test_cancelled_read_leaves_the_wait();
    test_owned_values_are_dropped();
    test_ids_are_not_reused_while_stale();
}

int main(void) {
    msrt_heap_claim();
    ms_test_sched_install();
    uint8_t outcome = 9;
    MsFaultText message = {0};
    expect(ms_task_run_main(entry, NULL, 0, &outcome, &message) == MS_TASK_OK && outcome == 0, "main task runs");
    ms_sched_teardown();
    puts("core_pipe: ok");
    return 0;
}
