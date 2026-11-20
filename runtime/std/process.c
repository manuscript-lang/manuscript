/* process.c: the @std/process natives for the running process: working directory, environment, signals sent,
 * identity, resource usage and title. libuv answers what it wraps (cwd, environment, memory, rusage, kill); the
 * rest (umask, groups, identity, title) goes through runtime/sys. Nothing here blocks, so it all runs on the
 * runtime thread. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c11 */

#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <uv.h>

#include "ms_rt/alloc.h"
#include "ms_rt/process.h"
#include "ms_rt/obj.h"
#include "ms_rt/sys.h"
#include "ms_rt/sys_process.h"

#include "fs_support.h"

enum {
    MAX_ID = 2147483647,
    MAX_SIGNAL = 64,
    FIRST_PATH = 1024,
    COMM_LIMIT = 15, /* the longest Linux process title */
    FIRST_GROUPS = 32,
    SMALL_VALUE = 256,
};

static void fail_memory(MsFsFail *fail) { ms_fs_fail_text(fail, "out of memory"); }

/* A native whose slots need no more than the failure: returns its status and fills `err`. */
static uint8_t finish(MsFsFail *fail, MsStr *err) { return ms_fs_finish(fail, err); }

static uint8_t invalid(MsStr *err) {
    MsFsFail fail = {0};
    ms_fs_fail_status(&fail, STATUS_INVALID_INPUT);
    return finish(&fail, err);
}

/* A host failure of the sys layer as an error of `operation` (no path). */
static void fail_host(MsFsFail *fail, MsSysError error, const char *operation) {
    ms_fs_fail_errno(fail, error, operation, NULL, 0);
}

static bool in_id_range(int64_t value) { return value >= 0 && value <= MAX_ID; }

/* ---- working directory ---- */

uint8_t msstd_process_working_directory(MsStr *out, MsStr *err) {
    MsFsFail fail = {0};
    size_t capacity = FIRST_PATH;
    char *buffer = malloc(capacity);
    while (buffer != NULL) {
        size_t size = capacity;
        const int code = uv_cwd(buffer, &size);
        if (code == UV_ENOBUFS) {
            capacity = size > capacity ? size : capacity * 2;
            char *grown = realloc(buffer, capacity);
            if (grown == NULL) {
                break;
            }
            buffer = grown;
            continue;
        }
        if (code != 0) {
            ms_fs_fail_uv(&fail, code, "getwd", ms_bytes_of(NULL, 0));
        } else if (!ms_fs_valid_utf8(ms_bytes_of((const uint8_t *)buffer, size))) {
            ms_fs_fail_status(&fail, STATUS_UNSUPPORTED);
        } else {
            ms_fs_write_string(out, (const uint8_t *)buffer, size);
        }
        free(buffer);
        return finish(&fail, err);
    }
    free(buffer);
    fail_memory(&fail);
    return finish(&fail, err);
}

uint8_t msstd_process_change_directory(const MsStr *path, MsStr *err) {
    MsFsFail fail = {0};
    const MsBytes name = msrt_str_bytes(path);
    MsFsPath checked;
    if (!ms_fs_path_init(&checked, name)) {
        ms_fs_fail_status(&fail, STATUS_INVALID_INPUT);
        return ms_fs_finish_at(&fail, name, err);
    }
    const int code = uv_chdir(checked.text);
    if (code != 0) {
        ms_fs_fail_uv(&fail, code, "chdir", name);
    }
    ms_fs_path_free(&checked);
    return ms_fs_finish_at(&fail, name, err);
}

/* ---- environment ---- */

/* A variable whose name or value is not UTF-8 cannot be a String; one such variable must not hide the rest (PATH,
 * the test runner's settings), so listings skip it. */
static bool usable(const uv_env_item_t *item) {
    return ms_fs_valid_utf8(ms_bytes_of((const uint8_t *)item->name, strlen(item->name))) &&
           ms_fs_valid_utf8(ms_bytes_of((const uint8_t *)item->value, strlen(item->value)));
}

static void new_text(MsStr *out, const char *text) { ms_fs_write_string(out, (const uint8_t *)text, strlen(text)); }

uint8_t msstd_process_environment(MsVec *names, MsVec *values, MsStr *err) {
    MsFsFail fail = {0};
    uv_env_item_t *items = NULL;
    int count = 0;
    const int code = uv_os_environ(&items, &count);
    if (code != 0) {
        ms_fs_fail_uv(&fail, code, "environ", ms_bytes_of(NULL, 0));
        return finish(&fail, err);
    }
    msrt_list_with_capacity(&msrt_desc_string, count, names);
    msrt_list_with_capacity(&msrt_desc_string, count, values);
    for (int i = 0; i < count; i++) {
        if (!usable(&items[i])) {
            continue;
        }
        MsStr text;
        new_text(&text, items[i].name);
        msrt_list_push(names, &msrt_desc_string, &text);
        new_text(&text, items[i].value);
        msrt_list_push(values, &msrt_desc_string, &text);
    }
    uv_os_free_environ(items, count);
    return finish(&fail, err);
}

uint8_t msstd_process_environment_map(MsMap *out, MsStr *err) {
    MsFsFail fail = {0};
    uv_env_item_t *items = NULL;
    int count = 0;
    const int code = uv_os_environ(&items, &count);
    if (code != 0) {
        ms_fs_fail_uv(&fail, code, "environ", ms_bytes_of(NULL, 0));
        return finish(&fail, err);
    }
    msrt_map_new(out);
    for (int i = 0; i < count; i++) {
        if (!usable(&items[i])) {
            continue;
        }
        MsStr key, value;
        new_text(&key, items[i].name);
        new_text(&value, items[i].value);
        msrt_map_add(out, &msrt_desc_string, &msrt_desc_string, (uint8_t *)&key, (uint8_t *)&value);
    }
    uv_os_free_environ(items, count);
    return finish(&fail, err);
}

uint8_t msstd_process_set_environment(const MsStr *name, uint8_t has_value, const MsStr *value, MsStr *err) {
    const MsBytes key = msrt_str_bytes(name);
    const MsBytes text = msrt_str_bytes(value);
    if (key.len == 0 || memchr(key.ptr, 0, key.len) != NULL || memchr(key.ptr, '=', key.len) != NULL ||
        (has_value != 0 && memchr(text.ptr, 0, text.len) != NULL)) {
        return invalid(err);
    }
    MsFsFail fail = {0};
    MsFsPath key_text;
    MsFsPath value_text;
    if (!ms_fs_path_init(&key_text, key)) {
        fail_memory(&fail);
        return finish(&fail, err);
    }
    int code = 0;
    if (has_value == 0) {
        code = uv_os_unsetenv(key_text.text);
    } else if (text.len == 0) {
        code = uv_os_setenv(key_text.text, "");
    } else if (ms_fs_path_init(&value_text, text)) {
        code = uv_os_setenv(key_text.text, value_text.text);
        ms_fs_path_free(&value_text);
    } else {
        code = UV_ENOMEM;
    }
    ms_fs_path_free(&key_text);
    if (code != 0) {
        ms_fs_fail_uv(&fail, code, "setenv", key);
    }
    return finish(&fail, err);
}

uint8_t msstd_process_environment_is_set(const MsStr *name) {
    const MsBytes key = msrt_str_bytes(name);
    MsFsPath text;
    if (memchr(key.ptr, '=', key.len) != NULL || !ms_fs_path_init(&text, key)) {
        return 0;
    }
    char buffer[SMALL_VALUE];
    size_t size = sizeof buffer;
    const int code = uv_os_getenv(text.text, buffer, &size);
    ms_fs_path_free(&text);
    return code == 0 || code == UV_ENOBUFS ? 1 : 0;
}

/* ---- signals sent ---- */

uint8_t msstd_process_send_signal(int64_t pid, int64_t signal, MsStr *err) {
    if (pid < INT32_MIN || pid > INT32_MAX || signal < 0 || signal > MAX_SIGNAL) {
        return invalid(err);
    }
    MsFsFail fail = {0};
    const int code = uv_kill((int)pid, (int)signal);
    if (code == UV_ESRCH) {
        ms_fs_fail_status(&fail, STATUS_NOT_FOUND); /* the same NotFound on every platform */
    } else if (code != 0) {
        ms_fs_fail_uv(&fail, code, "kill", ms_bytes_of(NULL, 0));
    }
    return finish(&fail, err);
}

/* ---- identity ---- */

static void groups_to_list(const int64_t *groups, size_t count, MsVec *out) {
    msrt_list_with_capacity(&msrt_desc_int, (int64_t)count, out);
    for (size_t i = 0; i < count; i++) {
        msrt_list_push(out, &msrt_desc_int, &groups[i]);
    }
}

uint8_t msstd_process_groups(MsVec *out, MsStr *err) {
    MsFsFail fail = {0};
    int64_t *groups = NULL;
    size_t count = 0;
    const MsSysError error = ms_sys_process_groups(&groups, &count);
    if (error != 0) {
        fail_host(&fail, error, "getgroups");
    } else {
        groups_to_list(groups, count, out);
        free(groups);
    }
    return finish(&fail, err);
}

static uint8_t apply_groups(const int64_t *groups, size_t count, MsStr *err) {
    MsFsFail fail = {0};
    const MsSysError error = ms_sys_process_set_groups(groups, count);
    if (error != 0) {
        fail_host(&fail, error, "setgroups");
    }
    return finish(&fail, err);
}

uint8_t msstd_process_set_groups(const MsVec *groups, MsStr *err) {
    const int64_t *list = groups->ptr;
    for (size_t i = 0; i < groups->len; i++) {
        if (!in_id_range(list[i])) {
            return invalid(err);
        }
    }
    return apply_groups(list, groups->len, err);
}

/* `gid` first, then the groups of `username`, each once. */
uint8_t msstd_process_initialize_groups(const MsStr *username, int64_t gid, MsStr *err) {
    const MsBytes name = msrt_str_bytes(username);
    MsFsFail fail = {0};
    if (!in_id_range(gid) || memchr(name.ptr, 0, name.len) != NULL) {
        return invalid(err);
    }
    MsFsPath text;
    if (name.len == 0 || !ms_fs_path_init(&text, name)) {
        return invalid(err);
    }
    int64_t *found = NULL;
    size_t count = 0;
    const MsSysError error = ms_sys_process_user_groups(text.text, &found, &count);
    ms_fs_path_free(&text);
    if (ms_sys_fs_error_kind(error) == MS_SYS_ERR_NOT_FOUND) {
        char message[SMALL_VALUE + 32];
        (void)snprintf(message, sizeof message, "user: unknown user %.*s", (int)name.len, (const char *)name.ptr);
        ms_fs_fail_text(&fail, message);
        return finish(&fail, err);
    }
    if (error != 0) {
        fail_host(&fail, error, "getgrouplist");
        return finish(&fail, err);
    }
    int64_t *groups = malloc((count + 1) * sizeof *groups);
    if (groups == NULL) {
        free(found);
        fail_memory(&fail);
        return finish(&fail, err);
    }
    size_t total = 0;
    groups[total++] = gid;
    for (size_t i = 0; i < count; i++) {
        bool seen = false;
        for (size_t j = 0; j < total && !seen; j++) {
            seen = groups[j] == found[i];
        }
        if (!seen) {
            groups[total++] = found[i];
        }
    }
    free(found);
    const uint8_t status = apply_groups(groups, total, err);
    free(groups);
    return status;
}

uint8_t msstd_process_umask(int64_t mask, int64_t *out, MsStr *err) {
    if (mask < 0 || mask > 0777) {
        return invalid(err);
    }
    MsFsFail fail = {0};
    uint32_t previous = 0;
    const MsSysError error = ms_sys_process_umask((uint32_t)mask, &previous);
    if (error != 0) {
        fail_host(&fail, error, "umask");
    } else {
        *out = (int64_t)previous;
    }
    return finish(&fail, err);
}

uint8_t msstd_process_set_identity(const MsStr *kind, int64_t id, MsStr *err) {
    static const struct {
        const char *name;
        MsSysIdentity which;
    } kinds[] = {{"uid", MS_SYS_ID_UID}, {"gid", MS_SYS_ID_GID}, {"euid", MS_SYS_ID_EUID}, {"egid", MS_SYS_ID_EGID}};
    const MsBytes text = msrt_str_bytes(kind);
    if (!in_id_range(id)) {
        return invalid(err);
    }
    for (size_t i = 0; i < sizeof kinds / sizeof kinds[0]; i++) {
        const size_t length = strlen(kinds[i].name);
        if (text.len != length || memcmp(text.ptr, kinds[i].name, length) != 0) {
            continue;
        }
        MsFsFail fail = {0};
        const MsSysError error = ms_sys_process_set_identity(kinds[i].which, (uint32_t)id);
        if (error != 0) {
            fail_host(&fail, error, "set identity");
        }
        return finish(&fail, err);
    }
    return invalid(err);
}

/* ---- title ---- */

uint8_t msstd_process_title(MsStr *out, MsStr *err) {
    MsFsFail fail = {0};
    char *text = NULL;
    size_t length = 0;
    const MsSysError error = ms_sys_process_title(&text, &length);
    if (error != 0) {
        fail_host(&fail, error, "title");
    } else if (!ms_fs_valid_utf8(ms_bytes_of((const uint8_t *)text, length))) {
        ms_fs_fail_status(&fail, STATUS_UNSUPPORTED);
    } else {
        ms_fs_write_string(out, (const uint8_t *)text, length);
    }
    free(text);
    return finish(&fail, err);
}

uint8_t msstd_process_set_title(const MsStr *title, MsStr *err) {
    const MsBytes text = msrt_str_bytes(title);
    if (memchr(text.ptr, 0, text.len) != NULL || memchr(text.ptr, '\n', text.len) != NULL) {
        return invalid(err);
    }
#ifdef __linux__
    if (text.len > COMM_LIMIT) {
        MsFsFail fail = {0};
        ms_fs_fail_text(&fail, "write: file name too long");
        return finish(&fail, err);
    }
#endif
    MsFsFail fail = {0};
    const MsSysError error = ms_sys_process_set_title((const char *)text.ptr, text.len);
    if (error != 0) {
        fail_host(&fail, error, "set title");
    }
    return finish(&fail, err);
}

/* ---- memory and usage ---- */

/* A byte count from libuv as a signed one; a limit libuv reports as "none" (the largest value) is 0. */
static int64_t counted(uint64_t bytes) { return bytes > (uint64_t)INT64_MAX ? 0 : (int64_t)bytes; }

uint8_t msstd_process_constrained_memory(int64_t *out, MsStr *err) {
    MsFsFail fail = {0};
    *out = counted(uv_get_constrained_memory());
    return finish(&fail, err);
}

uint8_t msstd_process_available_memory(int64_t *out, MsStr *err) {
    MsFsFail fail = {0};
    *out = counted(uv_get_available_memory());
    return finish(&fail, err);
}

static int64_t micros(uv_timeval_t time) { return (int64_t)time.tv_sec * 1000000 + (int64_t)time.tv_usec; }

static bool usage_of(uv_rusage_t *usage, MsFsFail *fail) {
    const int code = uv_getrusage(usage);
    if (code != 0) {
        ms_fs_fail_uv(fail, code, "getrusage", ms_bytes_of(NULL, 0));
    }
    return code == 0;
}

uint8_t msstd_process_resource_usage(MsProcessResources *out, MsStr *err) {
    MsFsFail fail = {0};
    uv_rusage_t usage;
    if (usage_of(&usage, &fail)) {
        *out = (MsProcessResources){
            .user_microseconds = micros(usage.ru_utime),
            .system_microseconds = micros(usage.ru_stime),
            .max_resident_bytes = (int64_t)usage.ru_maxrss * 1024, /* libuv reports kilobytes on every host */
            .minor_faults = (int64_t)usage.ru_minflt,
            .major_faults = (int64_t)usage.ru_majflt,
            .filesystem_reads = (int64_t)usage.ru_inblock,
            .filesystem_writes = (int64_t)usage.ru_oublock,
            .voluntary_switches = (int64_t)usage.ru_nvcsw,
            .involuntary_switches = (int64_t)usage.ru_nivcsw,
        };
    }
    return finish(&fail, err);
}

uint8_t msstd_process_cpu_usage(MsProcessCpu *out, MsStr *err) {
    MsFsFail fail = {0};
    uv_rusage_t usage;
    if (usage_of(&usage, &fail)) {
        *out = (MsProcessCpu){.user_microseconds = micros(usage.ru_utime), .system_microseconds = micros(usage.ru_stime)};
    }
    return finish(&fail, err);
}

/* ---- identity, memory and counters ---- */

#if defined(__APPLE__)
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

/* The path of the running executable; not UTF-8 is unsupported, as for every String the runtime hands out. */
static bool executable_path(MsStr *out, MsFsFail *fail) {
    size_t capacity = FIRST_PATH;
    char *buffer = malloc(capacity);
    while (buffer != NULL) {
        size_t size = capacity;
        const int code = uv_exepath(buffer, &size);
        if (code == UV_ENOBUFS || (code == 0 && size >= capacity - 1)) {
            capacity *= 2;
            char *grown = realloc(buffer, capacity);
            if (grown == NULL) {
                break;
            }
            buffer = grown;
            continue;
        }
        bool ok = false;
        if (code != 0) {
            ms_fs_fail_uv(fail, code, "executable", ms_bytes_of(NULL, 0));
        } else if (!ms_fs_valid_utf8(ms_bytes_of((const uint8_t *)buffer, size))) {
            ms_fs_fail_status(fail, STATUS_UNSUPPORTED);
        } else {
            ms_fs_write_string(out, (const uint8_t *)buffer, size);
            ok = true;
        }
        free(buffer);
        return ok;
    }
    free(buffer);
    fail_memory(fail);
    return false;
}

uint8_t msstd_process_info(MsProcessInfo *out, MsStr *err) {
    MsFsFail fail = {0};
    MsStr executable;
    if (executable_path(&executable, &fail)) {
        *out = (MsProcessInfo){
            .pid = (int64_t)uv_os_getpid(),
            .parent_pid = (int64_t)uv_os_getppid(),
            .executable = executable,
            .uid = ms_sys_process_identity(MS_SYS_ID_UID),
            .gid = ms_sys_process_identity(MS_SYS_ID_GID),
            .effective_uid = ms_sys_process_identity(MS_SYS_ID_EUID),
            .effective_gid = ms_sys_process_identity(MS_SYS_ID_EGID),
        };
        msrt_argv(&out->arguments);
        new_text(&out->os, OS_NAME);
        new_text(&out->architecture, ARCH_NAME);
    }
    return finish(&fail, err);
}

uint8_t msstd_process_memory_usage(MsProcessMemory *out, MsStr *err) {
    MsFsFail fail = {0};
    size_t resident = 0;
    const int code = uv_resident_set_memory(&resident);
    if (code != 0) {
        ms_fs_fail_uv(&fail, code, "resident memory", ms_bytes_of(NULL, 0));
        return finish(&fail, err);
    }
    int64_t heap[2];
    msrt_heap_stats(heap);
    const int64_t total = counted(resident);
    *out = (MsProcessMemory){
        .heap_used = heap[0],
        .heap_total = heap[1],
        .heap_system = heap[1],
        .external = total > heap[1] ? total - heap[1] : 0,
        .resident = total,
    };
    return finish(&fail, err);
}

uint8_t msstd_process_runtime_counts(MsProcessCounts *out) {
    uint64_t words[7];
    msrt_counts(words);
    *out = (MsProcessCounts){
        .allocations = (int64_t)words[0],
        .allocated_bytes = (int64_t)words[1],
        .list_copies = (int64_t)words[2],
        .list_copy_bytes = (int64_t)words[3],
        .string_clones = (int64_t)words[4],
        .string_clone_bytes = (int64_t)words[5],
        .operations = (int64_t)words[6],
    };
    return STATUS_OK;
}

/* Nanoseconds since the runtime started; a program that never recorded a start counts from its first call. */
int64_t msstd_process_uptime(void) {
    static _Atomic int64_t first;
    const int64_t now = ms_sys_monotonic_ns();
    int64_t origin = msrt_start_nanos();
    if (origin == 0) {
        int64_t unset = 0;
        (void)atomic_compare_exchange_strong(&first, &unset, now);
        origin = atomic_load(&first);
    }
    return now - origin;
}

uint8_t msstd_process_elapsed(int64_t *out) {
    *out = msstd_process_uptime();
    return STATUS_OK;
}
