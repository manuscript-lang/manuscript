/* test_support.c: what the test runner (stdlib/internal/test_runner.ms) asks of the runtime besides output captures
 * (those are in the std layer's stdout): bounding a test's waits, appending its result records, reporting a failed
 * expectation and keeping the fault record of a task that ended under a capture. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c11 */

#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <uv.h>

#include "../core/fault.h"
#include "../core/task.h"
#include "entry.h"
#include "ms_rt/test.h"
#include "../core/array.h"
#include "../core/spin.h"
#include "ms_rt/alloc.h"
#include "ms_rt/desc.h"
#include "ms_rt/map.h"
#include "ms_rt/safe.h"
#include "ms_rt/strbuild.h"
#include "ms_rt/sys.h"

enum {
    SITE_LENGTH = 4,
    ENV_BYTES = 32,
};

/* ---- test deadline ---- */

static _Atomic int64_t test_timeout_ns = -1; /* -1 until the environment was read */

static int64_t timeout_from_environment(void) {
    char text[ENV_BYTES];
    size_t size = sizeof text;
    if (uv_os_getenv("MS_TEST_TIMEOUT_NS", text, &size) != 0) {
        return 0;
    }
    char *end = NULL;
    const long long value = strtoll(text, &end, 10);
    return (end != text && *end == '\0' && value > 0) ? value : 0;
}

void msrt_test_deadline(bool on) {
    int64_t timeout = atomic_load_explicit(&test_timeout_ns, memory_order_relaxed);
    if (timeout < 0) {
        timeout = timeout_from_environment();
        atomic_store_explicit(&test_timeout_ns, timeout, memory_order_relaxed);
    }
    int64_t at = MS_NO_DEADLINE;
    if (on && timeout > 0) {
        const int64_t now = ms_sys_monotonic_ns();
        at = now > INT64_MAX - timeout ? MS_NO_DEADLINE : now + timeout;
    }
    (void)ms_task_set_defer_deadline(at);
}

/* ---- result records ---- */

/* Writes `bytes` to `descriptor` with one write; false when it did not all go. */
static bool write_whole(uv_file descriptor, MsBytes bytes) {
    uv_fs_t request;
    const uv_buf_t buffer = uv_buf_init((char *)(uintptr_t)bytes.ptr, (unsigned)bytes.len);
    const int written = uv_fs_write(NULL, &request, descriptor, &buffer, 1, -1, NULL);
    uv_fs_req_cleanup(&request);
    return written >= 0 && (size_t)written == bytes.len;
}

/* One byte to the pipe MS_TEST_WAKE names (a descriptor on Unix, a handle on Windows), so the supervisor knows a
 * record arrived. Nothing without the variable. */
static void ring_test_bell(void) {
    static _Atomic int64_t bell = -2; /* -2: not read yet, -1: none */
    int64_t descriptor = atomic_load_explicit(&bell, memory_order_relaxed);
    if (descriptor == -2) {
        descriptor = -1;
        char text[ENV_BYTES];
        size_t size = sizeof text;
        char *end = NULL;
        if (uv_os_getenv("MS_TEST_WAKE", text, &size) == 0) {
            const long long raw = strtoll(text, &end, 10);
            if (end != text && *end == '\0' && raw >= 0) {
#ifdef _WIN32
                descriptor = uv_open_osfhandle((uv_os_fd_t)(uintptr_t)raw);
#else
                descriptor = raw;
#endif
            }
        }
        atomic_store_explicit(&bell, descriptor, memory_order_relaxed);
    }
    if (descriptor >= 0) {
        static const uint8_t byte = 1;
        (void)write_whole((uv_file)descriptor, ms_bytes_of(&byte, 1));
    }
}

/* Appends `text` to the file at `path` whole: a record is one write to an append-mode file, so records from tests
 * running at once never interleave. Failure is ignored; the host reports the test as unfinished. */
void msrt_test_record(const MsStr *path, const MsStr *text) {
    const MsBytes name = ms_str_bytes(path);
    char *const file_name = msrt_alloc(name.len + 1);
    memcpy(file_name, name.ptr, name.len);
    file_name[name.len] = '\0';
    uv_fs_t request;
    const uv_file file = uv_fs_open(NULL, &request, file_name, UV_FS_O_WRONLY | UV_FS_O_CREAT | UV_FS_O_APPEND, 0644, NULL);
    uv_fs_req_cleanup(&request);
    msrt_free(file_name);
    if (file < 0) {
        return;
    }
    if (write_whole(file, ms_str_bytes(text))) {
        ring_test_bell();
    }
    uv_fs_t closing;
    (void)uv_fs_close(NULL, &closing, file, NULL);
    uv_fs_req_cleanup(&closing);
}

/* ---- a failed expectation ---- */

void msrt_test_failure(const MsStr *message, const MsMap *details) {
    static const uint8_t site_text[SITE_LENGTH] = {'s', 'i', 't', 'e'};
    const MsStr key = ms_str_from_bytes(site_text, SITE_LENGTH);
    const uint8_t *const found = msrt_map_get_ptr(details, &msrt_desc_string, &msrt_desc_string, (const uint8_t *)&key);
    const MsStr *const site = (const MsStr *)found;
    const MsBytes reason = ms_str_bytes(message);
    ms_sched_flush_stdout();
    ms_sys_stderr_write(reason);
    if (site != NULL) {
        ms_sys_stderr_write(ms_bytes_of((const uint8_t *)"\n  at ", 6));
        ms_sys_stderr_write(ms_str_bytes(site));
    }
    ms_sys_stderr_write(ms_bytes_of((const uint8_t *)"\n", 1));
    ms_fault_record_write(MS_FAULT_KIND_TEST_FAILURE, reason, site != NULL, site != NULL ? ms_str_bytes(site) : ms_bytes_of(NULL, 0));
}

/* ---- the fault of a task that ended under a capture ---- */

typedef struct KeptFault {
    uint64_t capture;
    uint8_t *bytes; /* the encoded record, owned */
    size_t length;
} KeptFault;

static struct {
    MsSpin lock;
    KeptFault *items;
    size_t length;
    size_t capacity;
} kept = {.lock = MS_SPIN_INIT};

void ms_test_keep_fault(uint64_t capture, const MsFaultText *text) {
    const MsFaultDetail *const detail = text->detail;
    const MsFaultRecord record = {.pid = ms_sys_process_id(),
                                  .kind = detail != NULL ? detail->kind : MS_FAULT_KIND_FAULT,
                                  .message = ms_bytes_of(text->bytes, detail != NULL ? detail->message_length : text->length),
                                  .frames = detail != NULL ? &detail->frames : NULL,
                                  .started = detail != NULL ? &detail->started : NULL,
                                  .notes = detail != NULL ? detail->notes : NULL,
                                  .note_count = detail != NULL ? detail->note_count : 0};
    const size_t needed = ms_fault_record_encode(&record, NULL, 0);
    uint8_t *const bytes = msrt_alloc(needed);
    (void)ms_fault_record_encode(&record, bytes, needed);
    ms_spin_lock(&kept.lock);
    size_t at = 0;
    while (at < kept.length && kept.items[at].capture != capture) {
        at++;
    }
    if (at < kept.length) {
        msrt_free(kept.items[at].bytes); /* only the last fault of a capture is kept */
    } else {
        void *grown = kept.items;
        if (!ms_array_reserve_system(&grown, &kept.capacity, kept.length + 1, sizeof kept.items[0])) {
            ms_spin_unlock(&kept.lock);
            msrt_free(bytes);
            return;
        }
        kept.items = grown;
        kept.length++;
    }
    kept.items[at] = (KeptFault){.capture = capture, .bytes = bytes, .length = needed};
    ms_spin_unlock(&kept.lock);
}

/* The encoded fault record of the last task under capture `id` that faulted, or an empty string; taking clears it. */
void msrt_test_capture_fault(int64_t id, MsStr *out) {
    uint8_t *bytes = NULL;
    size_t length = 0;
    ms_spin_lock(&kept.lock);
    for (size_t at = 0; at < kept.length; at++) {
        if (kept.items[at].capture == (uint64_t)id) {
            bytes = kept.items[at].bytes;
            length = kept.items[at].length;
            kept.items[at] = kept.items[--kept.length];
            break;
        }
    }
    ms_spin_unlock(&kept.lock);
    *out = ms_str_from_bytes(bytes, length);
    msrt_free(bytes);
}
