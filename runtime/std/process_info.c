/* process_info.c: what @std/process reports about the running process: identity, arguments, memory, the runtime's
 * counters, uptime and the environment as a map. libuv answers pid, parent, executable path, resident set size
 * and the environment; the heap numbers and counters come from the runtime, and the program's arguments and start
 * time from startup state. Nothing here blocks. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c11 */

#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <uv.h>

#include "ms_rt/alloc.h"
#include "ms_rt/process.h"
#include "ms_rt/sys.h"
#include "ms_rt/sys_process.h"
#include "ms_sched.h"

#include "fs_support.h"

enum { FIRST_PATH = 1024, COUNTERS = 7 };

#ifdef __APPLE__
#define OS_NAME "darwin"
#elif defined(_WIN32)
#define OS_NAME "windows"
#else
#define OS_NAME "linux"
#endif

#if defined(__aarch64__) || defined(_M_ARM64)
#define ARCH_NAME "arm64"
#else
#define ARCH_NAME "amd64"
#endif

/* Nanoseconds since the runtime started, or since the first call when it did not record a start. */
static int64_t uptime_ns(void) {
    static atomic_llong first;
    const int64_t now = ms_sys_monotonic_ns();
    int64_t origin = msrt_start_nanos();
    if (origin == 0) {
        long long expected = 0;
        (void)atomic_compare_exchange_strong(&first, &expected, now);
        origin = atomic_load(&first);
    }
    return now - origin;
}

int64_t msstd_process_uptime(void) { return uptime_ns(); }

uint8_t msstd_process_elapsed(int64_t *out) {
    *out = uptime_ns();
    return STATUS_OK;
}

static void write_text(MsStr *out, const char *text) { ms_fs_write_string(out, (const uint8_t *)text, strlen(text)); }

/* The path of the running executable; a path that is not UTF-8 cannot be a String. */
static bool executable_path(MsStr *out, MsFsFail *fail) {
    size_t capacity = FIRST_PATH;
    char *buffer = malloc(capacity);
    while (buffer != NULL) {
        size_t size = capacity;
        const int code = uv_exepath(buffer, &size);
        if (code == UV_ENOBUFS) {
            capacity *= 2;
            char *grown = realloc(buffer, capacity);
            if (grown == NULL) {
                break;
            }
            buffer = grown;
            continue;
        }
        if (code != 0) {
            ms_fs_fail_uv(fail, code, "executable", ms_bytes_of(NULL, 0));
        } else if (!ms_fs_valid_utf8(ms_bytes_of((const uint8_t *)buffer, size))) {
            ms_fs_fail_status(fail, STATUS_UNSUPPORTED);
        } else {
            ms_fs_write_string(out, (const uint8_t *)buffer, size);
            free(buffer);
            return true;
        }
        free(buffer);
        return false;
    }
    free(buffer);
    ms_fs_fail_text(fail, "out of memory");
    return false;
}

uint8_t msstd_process_info(MsProcessInfo *out, MsStr *err) {
    MsFsFail fail = {0};
    MsStr executable;
    if (!executable_path(&executable, &fail)) {
        return ms_fs_finish(&fail, err);
    }
    out->pid = (int64_t)uv_os_getpid();
    out->parent_pid = (int64_t)uv_os_getppid();
    out->executable = executable;
    msrt_argv(&out->arguments);
    write_text(&out->os, OS_NAME);
    write_text(&out->architecture, ARCH_NAME);
    out->uid = ms_sys_process_identity(MS_SYS_ID_UID);
    out->gid = ms_sys_process_identity(MS_SYS_ID_GID);
    out->effective_uid = ms_sys_process_identity(MS_SYS_ID_EUID);
    out->effective_gid = ms_sys_process_identity(MS_SYS_ID_EGID);
    return ms_fs_finish(&fail, err);
}

uint8_t msstd_process_memory_usage(MsProcessMemory *out, MsStr *err) {
    MsFsFail fail = {0};
    size_t resident = 0;
    const int code = uv_resident_set_memory(&resident);
    if (code != 0) {
        ms_fs_fail_uv(&fail, code, "memory", ms_bytes_of(NULL, 0));
        return ms_fs_finish(&fail, err);
    }
    int64_t heap[2] = {0, 0};
    msrt_heap_stats(heap);
    const int64_t rss = (int64_t)resident;
    out->heap_used = heap[0];
    out->heap_total = heap[1];
    out->heap_system = heap[1];
    out->external = rss > heap[1] ? rss - heap[1] : 0;
    out->resident = rss;
    return ms_fs_finish(&fail, err);
}

uint8_t msstd_process_runtime_counts(MsProcessCounts *out) {
    uint64_t counters[COUNTERS] = {0};
    msrt_counts(counters);
    out->allocations = (int64_t)counters[0];
    out->allocated_bytes = (int64_t)counters[1];
    out->list_copies = (int64_t)counters[2];
    out->list_copy_bytes = (int64_t)counters[3];
    out->string_clones = (int64_t)counters[4];
    out->string_clone_bytes = (int64_t)counters[5];
    out->operations = (int64_t)counters[6];
    return STATUS_OK;
}

uint8_t msstd_process_environment_map(MsMap *out, MsStr *err) {
    MsFsFail fail = {0};
    uv_env_item_t *items = NULL;
    int count = 0;
    const int code = uv_os_environ(&items, &count);
    if (code != 0) {
        ms_fs_fail_uv(&fail, code, "environ", ms_bytes_of(NULL, 0));
        return ms_fs_finish(&fail, err);
    }
    msrt_map_new(out);
    for (int i = 0; i < count; i++) {
        const MsBytes name = ms_bytes_of((const uint8_t *)items[i].name, strlen(items[i].name));
        const MsBytes value = ms_bytes_of((const uint8_t *)items[i].value, strlen(items[i].value));
        /* One variable that is not UTF-8 must not hide the rest (PATH, the test runner's settings). */
        if (!ms_fs_valid_utf8(name) || !ms_fs_valid_utf8(value)) {
            continue;
        }
        MsStr key;
        MsStr text;
        ms_fs_write_string(&key, name.ptr, name.len);
        ms_fs_write_string(&text, value.ptr, value.len);
        msrt_map_add(out, &msrt_desc_string, &msrt_desc_string, (uint8_t *)&key, (uint8_t *)&text);
    }
    uv_os_free_environ(items, count);
    return ms_fs_finish(&fail, err);
}
