/* Unit tests of src/runtime/std/process.c: argument checks and the round trips that need no runtime beyond strings. */
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

static void identity_and_counters(void) {
    MsProcessInfo info;
    CHECK(RUN(msstd_process_info(&info, &err)) == STATUS_OK);
    CHECK(info.pid == (int64_t)getpid() && info.parent_pid == (int64_t)getppid());
    CHECK(info.uid == (int64_t)getuid() && info.effective_gid == (int64_t)getegid());
    CHECK(msrt_str_len(&info.executable) > 0 && info.arguments.len == 0);
#if defined(__APPLE__)
    CHECK(msrt_str_len(&info.os) == 6 && memcmp(ms_str_data(&info.os), "darwin", 6) == 0);
#else
    CHECK(msrt_str_len(&info.os) == 5 && memcmp(ms_str_data(&info.os), "linux", 5) == 0);
#endif
    msrt_string_free(&info.executable);
    msrt_string_free(&info.os);
    msrt_string_free(&info.architecture);

    MsProcessMemory memory;
    CHECK(RUN(msstd_process_memory_usage(&memory, &err)) == STATUS_OK);
    CHECK(memory.resident > 0 && memory.external >= 0 && memory.heap_total >= memory.heap_used);

    MsProcessCounts counts;
    CHECK(msstd_process_runtime_counts(&counts) == STATUS_OK && counts.allocations >= 0);

    int64_t first = msstd_process_uptime();
    int64_t second = 0;
    CHECK(msstd_process_elapsed(&second) == STATUS_OK);
    CHECK(first >= 0 && second >= first);
}

static void environment_map(void) {
    MsStr name = make("MS_PROCESS_MAP");
    MsStr value = make("seen");
    CHECK(RUN(msstd_process_set_environment(&name, 1, &value, &err)) == STATUS_OK);
    _Alignas(8) uint8_t storage[56]; /* sizeof(MsMap), which std code only handles by address */
    MsMap *map = (MsMap *)storage;
    CHECK(RUN(msstd_process_environment_map(map, &err)) == STATUS_OK);
    const uint8_t *found = msrt_map_get_ptr(map, &msrt_desc_string, &msrt_desc_string, (const uint8_t *)&name);
    MsStr seen = {0};
    if (found != NULL) {
        memcpy(&seen, found, sizeof seen);
    }
    CHECK(found != NULL && msrt_str_len(&seen) == 4);
    msrt_map_drop(map, &msrt_desc_string, &msrt_desc_string);
    msrt_string_free(&name);
    msrt_string_free(&value);
}

int main(void) {
    identity_and_counters();
    environment_map();
    environment_round_trip();
    validation();
    usage_and_directory();
    if (failures != 0) {
        printf("%d failures\n", failures);
        return 1;
    }
    printf("ok\n");
    return 0;
}
