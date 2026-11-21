/* The test runner's natives: records append whole to a file and ring the bell, a fault kept under a capture is handed
 * out once, and the deadline bounds the running task's deferred promises. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c11 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <uv.h>

#include "../core/fault_kept.h"
#include "../core/task.h"
#include "../entry/entry.h"
#include "ms_rt/alloc.h"
#include "ms_rt/strbuild.h"
#include "ms_rt/test.h"
#include "support/sched_env.h"


static void expect(int condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "entry_test_support: failed: %s\n", what);
        exit(1);
    }
}

static void deadline_task(void *argument) {
    (void)argument;
    expect(uv_os_setenv("MS_TEST_TIMEOUT_NS", "1000000000") == 0, "setenv timeout");
    msrt_test_deadline(true);
    const int64_t bound = ms_task_defer_deadline();
    expect(bound != MS_NO_DEADLINE, "a deadline is set");
    msrt_test_deadline(false);
    expect(ms_task_defer_deadline() == MS_NO_DEADLINE, "and lifted");
}

static MsStr text_of(const char *text) { return ms_str_from_bytes((const uint8_t *)text, strlen(text)); }

int main(void) {
    char directory[512];
    size_t directory_size = sizeof directory;
    expect(uv_os_tmpdir(directory, &directory_size) == 0, "tmpdir");
    char path[640];
    snprintf(path, sizeof path, "%s/ms-test-support-%d.records", directory, (int)uv_os_getpid());
    remove(path);
    /* The bell: one end of a pipe whose write end the runtime is told by number (a descriptor on Unix, a handle on
     * Windows). */
    uv_file bell[2];
    expect(uv_pipe(bell, 0, 0) == 0, "pipe");
#ifdef _WIN32
    const long long wake_value = (long long)(uintptr_t)uv_get_osfhandle(bell[1]);
#else
    const long long wake_value = bell[1];
#endif
    char wake[32];
    snprintf(wake, sizeof wake, "%lld", wake_value);
    expect(uv_os_setenv("MS_TEST_WAKE", wake) == 0, "setenv wake");

    ms_test_sched_install();
    uint8_t outcome = 0;
    MsFaultText message = {0};
    expect(ms_task_run_main(deadline_task, NULL, 0, &outcome, &message) == MS_TASK_OK && outcome == 0, "the deadline task ran");

    MsStr name = text_of(path);
    const MsStr first = text_of("one\n");
    const MsStr second = text_of("two\n");
    msrt_test_record(&name, &first);
    msrt_test_record(&name, &second);
    FILE *file = fopen(path, "rb");
    expect(file != NULL, "the records file exists");
    char contents[16] = {0};
    expect(fread(contents, 1, sizeof contents - 1, file) == 8, "both records are there");
    (void)fclose(file);
    expect(strcmp(contents, "one\ntwo\n") == 0, "in order");
    char rings[4];
    uv_fs_t reading;
    const uv_buf_t ring_buffer = uv_buf_init(rings, sizeof rings);
    expect(uv_fs_read(NULL, &reading, bell[0], &ring_buffer, 1, -1, NULL) == 2, "each record rang the bell once");
    uv_fs_req_cleanup(&reading);
    remove(path);

    MsFaultText fault = {.bytes = msrt_alloc(5), .length = 5};
    memcpy(fault.bytes, "oops!", 5);
    ms_test_keep_fault(7, &fault);
    MsStr record = ms_str_empty();
    msrt_test_capture_fault(8, &record);
    expect(ms_str_len(&record) == 0, "another capture has no fault");
    msrt_test_capture_fault(7, &record);
    expect(ms_str_len(&record) > 4 && memcmp(ms_str_data(&record), "MSFR", 4) == 0, "the record is handed out");
    ms_str_release(&record);
    msrt_test_capture_fault(7, &record);
    expect(ms_str_len(&record) == 0, "once");
    msrt_free(fault.bytes);
    ms_str_release(&name);
    puts("entry_test_support: ok");
    return 0;
}
