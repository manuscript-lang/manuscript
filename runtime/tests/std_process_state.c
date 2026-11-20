/* Unit tests of runtime/std/process.c: argument checks and the round trips that need no runtime beyond strings. */
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include "../std/abi.h"
#include "fake_rt.h"
#include "ms_rt/process.h"

static int failures;
static MsStr err;
/* The status of a native, with the err slot it filled released. */
#define RUN(call) ({ const uint8_t status_ = (call); msrt_string_free(&err); err = (MsStr){0}; status_; })
#define CHECK(cond) do { if (!(cond)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

static MsStr make(const char *text) {
    MsStr out;
    msrt_string_from_bytes((const uint8_t *)text, strlen(text), &out);
    return out;
}

static void environment_round_trip(void) {
    MsStr name = make("MS_PROCESS_UNIT");
    MsStr value = make("v1");
    CHECK(msstd_process_environment_is_set(&name) == 0);
    CHECK(RUN(msstd_process_set_environment(&name, 1, &value, &err)) == STATUS_OK);
    CHECK(msstd_process_environment_is_set(&name) == 1);
    CHECK(RUN(msstd_process_set_environment(&name, 0, &value, &err)) == STATUS_OK);
    CHECK(msstd_process_environment_is_set(&name) == 0);
    MsStr empty = make("");
    CHECK(RUN(msstd_process_set_environment(&empty, 1, &value, &err)) == STATUS_INVALID_INPUT);
    MsStr equals = make("A=B");
    CHECK(RUN(msstd_process_set_environment(&equals, 0, &value, &err)) == STATUS_INVALID_INPUT);
    msrt_string_free(&name);
    msrt_string_free(&value);
    msrt_string_free(&empty);
    msrt_string_free(&equals);
}

static void identity_memory_and_counts(void) {
    MsProcessInfo info;
    CHECK(RUN(msstd_process_info(&info, &err)) == STATUS_OK);
    CHECK(info.pid > 0 && info.parent_pid >= 0);
    CHECK(ms_str_len(&info.os) > 0 && ms_str_len(&info.architecture) > 0 && ms_str_len(&info.executable) > 0);
    CHECK(info.uid >= 0 && info.effective_gid >= 0);
    msrt_string_free(&info.executable);
    msrt_string_free(&info.os);
    msrt_string_free(&info.architecture);
    MsProcessMemory memory;
    CHECK(RUN(msstd_process_memory_usage(&memory, &err)) == STATUS_OK);
    CHECK(memory.resident > 0 && memory.external >= 0);
    MsProcessCounts counts;
    CHECK(msstd_process_runtime_counts(&counts) == STATUS_OK);
    int64_t elapsed = -1;
    CHECK(msstd_process_elapsed(&elapsed) == STATUS_OK && elapsed >= 0);
    CHECK(msstd_process_uptime() >= elapsed);
}

static void validation(void) {
    int64_t out = 0;
    CHECK(RUN(msstd_process_umask(01000, &out, &err)) == STATUS_INVALID_INPUT);
    CHECK(RUN(msstd_process_umask(022, &out, &err)) == STATUS_OK);
    CHECK(RUN(msstd_process_send_signal(0, 65, &err)) == STATUS_INVALID_INPUT);
    CHECK(RUN(msstd_process_send_signal((int64_t)getpid(), 0, &err)) == STATUS_OK);
    CHECK(RUN(msstd_process_send_signal(2147483647, 0, &err)) == STATUS_NOT_FOUND); /* no process has the largest pid */
    MsStr kind = make("nope");
    CHECK(RUN(msstd_process_set_identity(&kind, 0, &err)) == STATUS_INVALID_INPUT);
    msrt_string_free(&kind);
}

static void usage_and_directory(void) {
    MsProcessResources usage;
    CHECK(RUN(msstd_process_resource_usage(&usage, &err)) == STATUS_OK);
    CHECK(usage.max_resident_bytes > 0);
    int64_t memory = 0;
    CHECK(RUN(msstd_process_available_memory(&memory, &err)) == STATUS_OK);
    CHECK(memory > 0);
    MsStr cwd;
    CHECK(RUN(msstd_process_working_directory(&cwd, &err)) == STATUS_OK);
    CHECK(msrt_str_len(&cwd) > 0);
    CHECK(RUN(msstd_process_change_directory(&cwd, &err)) == STATUS_OK);
    MsStr missing = make("/nonexistent-ms-process-dir");
    CHECK(RUN(msstd_process_change_directory(&missing, &err)) == STATUS_NOT_FOUND);
    msrt_string_free(&cwd);
    msrt_string_free(&missing);
}

int main(void) {
    environment_round_trip();
    identity_memory_and_counts();
    validation();
    usage_and_directory();
    if (failures != 0) {
        printf("%d failures\n", failures);
        return 1;
    }
    printf("ok\n");
    return 0;
}
