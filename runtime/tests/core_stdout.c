/* Unit test of the standard output (runtime/core/stdout.c): buffering, order, the captures, standard error
 * flushing stdout first, and a failed write being remembered. Standard output is pointed at a file for the test. */
#define _POSIX_C_SOURCE 200809L
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifdef _WIN32
#include <io.h>
#endif

#include "../core/task.h"
#include "ms_rt/alloc.h"
#include "ms_rt/io.h"
#include "ms_rt/test.h"
#include "support/sched_env.h"

static void expect(bool condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "core_stdout: failed: %s\n", what);
        exit(1);
    }
}

static MsStr make(const char *text) {
    MsStr value;
    msrt_string_from_bytes((const uint8_t *)text, strlen(text), &value);
    return value;
}

static size_t file_size(const char *path) {
    char text[256];
    const int fd = open(path, O_RDONLY);
    const ssize_t count = fd < 0 ? -1 : read(fd, text, sizeof text);
    if (fd >= 0) {
        close(fd);
    }
    return count < 0 ? (size_t)-1 : (size_t)count;
}

static void expect_file(const char *path, const char *want, const char *what) {
    char text[256] = {0};
    const int fd = open(path, O_RDONLY);
    const ssize_t count = fd < 0 ? -1 : read(fd, text, sizeof text - 1);
    if (fd >= 0) {
        close(fd);
    }
    expect(count >= 0 && (size_t)count == strlen(want) && memcmp(text, want, (size_t)count) == 0, what);
}

static void body(void *unused) {
    (void)unused;
#ifdef _WIN32
    /* Windows has no /tmp or mkstemp: a unique name in the working directory, and binary mode so "\n" is one byte. */
    _set_fmode(_O_BINARY);
    char path[] = "ms_core_stdout_XXXXXX";
    expect(_mktemp_s(path, sizeof path) == 0, "temporary name");
    const int file = open(path, O_RDWR | O_CREAT | O_EXCL | O_BINARY, 0600);
#else
    char path[] = "/tmp/ms_core_stdout_XXXXXX";
    const int file = mkstemp(path);
#endif
    expect(file >= 0, "temporary file");
    expect(dup2(file, 1) == 1, "point stdout at the file");

    MsStr hello = make("hello");
    MsStr newline = make("\n");
    msrt_io_write_stdout(&hello);
    msrt_io_write_stdout_line(&hello, &newline);
    expect(file_size(path) == 0, "output stays buffered until flushed (stdout is not a terminal)");
    ms_sched_flush_stdout();
    expect_file(path, "hellohello\n", "flush writes in order");

    /* A capture takes the output of its task and nothing reaches the file. */
    const int64_t capture = msrt_test_capture_new();
    msrt_test_capture_set(capture);
    expect(msrt_test_capture_current() == capture, "the capture is current");
    msrt_io_write_stdout_line(&hello, &newline);
    ms_sched_flush_stdout();
    expect_file(path, "hellohello\n", "captured output does not reach stdout");
    MsStr taken;
    msrt_test_capture_take(capture, &taken);
    expect(ms_str_len(&taken) == 6 && memcmp(ms_str_data(&taken), "hello\n", 6) == 0, "take returns the text");
    MsStr again;
    msrt_test_capture_take(capture, &again);
    expect(ms_str_len(&again) == 0, "take clears the capture");
    msrt_test_capture_free(capture);
    msrt_io_write_stdout(&newline); /* the capture ended: back to stdout */
    ms_sched_flush_stdout();
    expect_file(path, "hellohello\n\n", "output after the capture ended goes to stdout");
    msrt_test_capture_set(0);

    /* Standard error flushes standard output first, so the two keep their order on a shared stream. */
    expect(dup2(file, 2) == 2, "point stderr at the file");
    MsStr oops = make("E");
    msrt_io_write_stdout(&hello);
    msrt_io_write_stderr(&oops);
    expect_file(path, "hellohello\n\nhelloE", "stderr flushes stdout first");

    /* A failed write is remembered once; the data is dropped. */
    expect(ms_sched_stdout_error() == 0, "no error so far");
    expect(close(1) == 0, "close stdout");
    msrt_io_write_stdout(&hello);
    ms_sched_flush_stdout();
    expect(ms_sched_stdout_error() != 0, "the failed write is remembered");
    ms_sched_flush_stdout();
    unlink(path);
}

int main(void) {
    ms_test_sched_install();
    uint8_t outcome = 1;
    MsFaultText text = {0};
    expect(ms_task_run_main(body, NULL, 0, &outcome, &text) == MS_TASK_OK && outcome == 0, "the main task ends");
    puts("core_stdout: ok");
    return 0;
}
