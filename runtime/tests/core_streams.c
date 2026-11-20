/* Unit test of the descriptor stream table (runtime/core/streams.c) over real pipes, on the C scheduler: a read that
 * finds data at once, a read that parks on the poller until a write, the end of a stream, chunk sizing, buffered
 * writes with flush, write failures that stay on the entry, and stale ids. Run under the sanitizers by `make c-test`. */
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "../core/promise.h"
#include "../core/scheduler.h"
#include "ms_rt/alloc.h"
#include "ms_rt/streams.h"
#include "support/sched_env.h"

static void expect(bool condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "core_streams: failed: %s\n", what);
        exit(1);
    }
}

typedef struct Pair {
    int64_t reader;
    int64_t writer;
    int write_fd;
} Pair;

/* A pipe with a reading stream (non-blocking) and a writing stream, both owning their descriptors. */
static Pair open_pair(void) {
    int fds[2];
    expect(pipe(fds) == 0, "pipe");
    const int64_t flags_read = MS_STREAMS_READS | MS_STREAMS_OWNS | MS_STREAMS_NONBLOCK;
    return (Pair){.reader = msrt_streams_open(fds[0], flags_read),
                  .writer = msrt_streams_open(fds[1], MS_STREAMS_WRITES | MS_STREAMS_OWNS),
                  .write_fd = fds[1]};
}

static void write_text(int64_t stream, const char *text) {
    uint8_t copy[64];
    const size_t length = strlen(text);
    expect(length <= sizeof copy, "short text");
    memcpy(copy, text, length);
    const MsList bytes = {.ptr = copy, .len = length, .cap = 0};
    expect(msrt_streams_write(stream, &bytes) == 0, "write admitted");
}

static void flush(int64_t stream) {
    const MsPromise flush = (MsPromise)msrt_streams_flush(stream);
    expect(ms_promise_wait(flush, -1) == MS_PROMISE_OK, "flush finishes");
    ms_promise_drop(flush);
}

/* The next chunk as a malloc'd copy, or NULL at the end; *length is its size. */
static char *read_chunk(int64_t stream, size_t *length) {
    const MsPromise read = (MsPromise)msrt_streams_read(stream);
    expect(ms_promise_wait(read, -1) == MS_PROMISE_OK, "read finishes");
    MsList bytes = {0};
    char *copy = NULL;
    if (ms_promise_take(read, &msrt_desc_bytes, (uint8_t *)&bytes)) {
        copy = malloc(bytes.len + 1);
        memcpy(copy, bytes.ptr, bytes.len);
        copy[bytes.len] = '\0';
        *length = bytes.len;
        msrt_free(bytes.ptr);
    }
    ms_promise_drop(read);
    return copy;
}

static bool error_is(int64_t stream, const char *prefix) {
    MsStr error;
    msrt_streams_error(stream, &error);
    const bool matches = ms_str_len(&error) >= strlen(prefix) && memcmp(ms_str_data(&error), prefix, strlen(prefix)) == 0;
    msrt_string_free(&error);
    return matches;
}

static void test_read_what_was_written(void) {
    const Pair pair = open_pair();
    write_text(pair.writer, "hello");
    expect(msrt_streams_buffered(pair.writer) == 5, "buffered until flush");
    flush(pair.writer);
    expect(msrt_streams_buffered(pair.writer) == 0, "drained");
    size_t length = 0;
    char *chunk = read_chunk(pair.reader, &length);
    expect(chunk != NULL && length == 5 && strcmp(chunk, "hello") == 0, "the chunk");
    free(chunk);
    msrt_streams_close(pair.writer);
    chunk = read_chunk(pair.reader, &length);
    expect(chunk == NULL, "the end of the stream gives no value");
    expect(error_is(pair.reader, ""), "no error at the end");
    msrt_streams_close(pair.reader);
}

typedef struct Delayed {
    int64_t writer;
    const char *text;
} Delayed;

static void delayed_write(void *arg) {
    Delayed *job = arg;
    (void)ms_task_sleep(5 * 1000 * 1000);
    write_text(job->writer, job->text);
    flush(job->writer);
    msrt_streams_close(job->writer);
}

static void test_blocked_read_parks_until_data(void) {
    const Pair pair = open_pair();
    static Delayed job;
    job = (Delayed){.writer = pair.writer, .text = "late"};
    MsTaskStatus status = MS_TASK_OK;
    expect(ms_task_spawn(delayed_write, &job, MS_SPAWN_DETACHED, 0, &status) != 0, "spawn");
    const MsPromise read = (MsPromise)msrt_streams_read(pair.reader);
    expect(!ms_promise_done(read), "an empty pipe parks the read");
    expect(ms_promise_wait(read, -1) == MS_PROMISE_OK, "the poller wakes the read");
    MsList bytes = {0};
    expect(ms_promise_take(read, &msrt_desc_bytes, (uint8_t *)&bytes) && bytes.len == 4 && memcmp(bytes.ptr, "late", 4) == 0, "data");
    msrt_free(bytes.ptr);
    ms_promise_drop(read);
    size_t length = 0;
    expect(read_chunk(pair.reader, &length) == NULL, "then the end");
    msrt_streams_close(pair.reader);
}

enum { LARGE_TOTAL = 300 * 1000 };

typedef struct Reader {
    int64_t stream;
    size_t received;
    bool finished;
} Reader;

static void reader_task(void *arg) {
    Reader *reader = arg;
    size_t length = 0;
    char *chunk = NULL;
    while ((chunk = read_chunk(reader->stream, &length)) != NULL) {
        reader->received += length;
        free(chunk);
    }
    reader->finished = true;
}

/* A write bigger than the pipe drains what fits, keeps the rest buffered, and a flush finishes when a reader has made room. */
static void test_large_write_drains_through_flush(void) {
    int fds[2];
    expect(pipe(fds) == 0, "pipe");
    static Reader reader;
    reader = (Reader){.stream = msrt_streams_open(fds[0], MS_STREAMS_READS | MS_STREAMS_OWNS | MS_STREAMS_NONBLOCK)};
    const int64_t writer = msrt_streams_open(fds[1], MS_STREAMS_WRITES | MS_STREAMS_OWNS | MS_STREAMS_NONBLOCK);
    uint8_t *data = malloc(LARGE_TOTAL);
    memset(data, 'x', LARGE_TOTAL);
    const MsList bytes = {.ptr = data, .len = LARGE_TOTAL, .cap = 0};
    expect(msrt_streams_write(writer, &bytes) == 0, "write admitted");
    expect(msrt_streams_buffered(writer) > 0, "a pipe holds less than the write: the rest stays buffered");
    MsTaskStatus status = MS_TASK_OK;
    expect(ms_task_spawn(reader_task, &reader, MS_SPAWN_DETACHED, 0, &status) != 0, "spawn");
    flush(writer);
    expect(msrt_streams_buffered(writer) == 0, "the flush finished once everything drained");
    msrt_streams_close(writer);
    while (!reader.finished) {
        ms_task_yield();
    }
    expect(reader.received == LARGE_TOTAL, "every byte arrived");
    msrt_streams_close(reader.stream);
    free(data);
}

static void test_failures_stay_on_the_entry(void) {
    /* No platform has a stream at this descriptor, so every write fails. */
    const int64_t stream = msrt_streams_open(INT32_MAX, MS_STREAMS_WRITES);
    enum { AUTO = 64 * 1024 };
    uint8_t *data = calloc(AUTO, 1);
    const MsList bytes = {.ptr = data, .len = AUTO, .cap = 0};
    expect(msrt_streams_write(stream, &bytes) == 0, "the write is admitted, then drained and failed");
    expect(error_is(stream, "write: "), "the failure is recorded");
    expect(msrt_streams_buffered(stream) == 0, "nothing stays buffered");
    for (int i = 0; i < 2; i++) {
        flush(stream);
        expect(error_is(stream, "write: "), "a flush keeps the failure");
        write_text(stream, "not queued after failure");
        expect(msrt_streams_buffered(stream) == 0, "a failed stream queues nothing");
    }
    msrt_streams_close(stream);
    free(data);
}

static void test_broken_pipe_reads_lower_case(void) {
    const Pair pair = open_pair();
    msrt_streams_close(pair.reader);
    write_text(pair.writer, "into a pipe with no reader");
    flush(pair.writer);
    expect(error_is(pair.writer, "write: broken pipe"), "the reason is lower case without an os error suffix");
    msrt_streams_close(pair.writer);
}

static void test_wrong_direction_and_stale_ids(void) {
    const Pair pair = open_pair();
    const MsList none = {0};
    expect(msrt_streams_write(pair.reader, &none) == 1, "a reading stream refuses writes");
    const MsPromise read = (MsPromise)msrt_streams_read(pair.writer);
    expect(ms_promise_wait(read, -1) == MS_PROMISE_OK && error_is(pair.writer, "read: the stream is not readable"), "a writing stream cannot read");
    ms_promise_drop(read);
    const int64_t stale = pair.reader;
    msrt_streams_close(pair.reader);
    msrt_streams_close(pair.reader); /* closing twice does nothing */
    expect(msrt_streams_write(stale, &none) == 1 && msrt_streams_buffered(stale) == 0, "a closed id is gone");
    const int64_t reused = msrt_streams_open(dup(pair.write_fd), MS_STREAMS_READS | MS_STREAMS_OWNS);
    expect(reused != stale, "a reused slot has a new generation");
    msrt_streams_close(reused);
    msrt_streams_close(pair.writer);
}

static void entry(void *arg) {
    (void)arg;
    test_read_what_was_written();
    test_blocked_read_parks_until_data();
    test_large_write_drains_through_flush();
    test_failures_stay_on_the_entry();
    test_broken_pipe_reads_lower_case();
    test_wrong_direction_and_stale_ids();
}

int main(void) {
    (void)signal(SIGPIPE, SIG_IGN);
    msrt_heap_claim();
    ms_test_sched_install();
    uint8_t outcome = 9;
    MsFaultText message = {0};
    expect(ms_task_run_main(entry, NULL, 0, &outcome, &message) == MS_TASK_OK && outcome == 0, "main task runs");
    ms_sched_teardown();
    puts("core_streams: ok");
    return 0;
}
