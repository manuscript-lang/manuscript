/* Shared parts of the @std/fs and @std/io natives: failures, validated paths, the blocking-pool wrapper, a byte
 * buffer and runtime values (fs_support.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c11 */

#include "fs_support.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <uv.h>

/* ---- failures ---- */

uint8_t ms_fs_classify(MsSysError error) {
    switch (ms_sys_fs_error_kind(error)) {
    case MS_SYS_ERR_NOT_FOUND:
        return STATUS_NOT_FOUND;
    case MS_SYS_ERR_NOT_EMPTY:
        return STATUS_NOT_EMPTY;
    case MS_SYS_ERR_EXISTS:
        return STATUS_ALREADY_EXISTS;
    case MS_SYS_ERR_NOT_DIRECTORY:
    case MS_SYS_ERR_IS_DIRECTORY:
    case MS_SYS_ERR_INVALID:
        return STATUS_INVALID_INPUT;
    case MS_SYS_ERR_PERMISSION:
        return STATUS_PERMISSION_DENIED;
    case MS_SYS_ERR_UNSUPPORTED:
        return STATUS_UNSUPPORTED;
    case MS_SYS_ERR_OTHER:
    case MS_SYS_ERR_WOULD_BLOCK:
    case MS_SYS_ERR_LINK_LOOP:
    case MS_SYS_ERR_INTERRUPTED:
    case MS_SYS_ERR_IO:
    case MS_SYS_ERR_BAD_DESCRIPTOR:
    case MS_SYS_ERR_NO_ENTRY_DEVICE:
        break;
    }
    return STATUS_FAILED;
}

bool ms_fs_failed(const MsFsFail *fail) { return fail->status != STATUS_OK; }

void ms_fs_fail_free(MsFsFail *fail) {
    free(fail->message);
    fail->message = NULL;
    fail->message_length = 0;
}

void ms_fs_fail_status(MsFsFail *fail, uint8_t status) {
    ms_fs_fail_free(fail);
    fail->status = status;
}

/* Takes ownership of a message. */
static void fail_with_message(MsFsFail *fail, char *message, size_t length) {
    ms_fs_fail_free(fail);
    fail->status = STATUS_FAILED;
    fail->message = message;
    fail->message_length = length;
}

void ms_fs_fail_uv(MsFsFail *fail, int code, const char *operation, MsBytes name) {
    if (code == UV_ENOENT) {
        ms_fs_fail_status(fail, STATUS_NOT_FOUND);
    } else if (code == UV_EACCES || code == UV_EPERM) {
        ms_fs_fail_status(fail, STATUS_PERMISSION_DENIED);
    } else if (code == UV_ENOTSUP || code == UV_ENOSYS) {
        ms_fs_fail_status(fail, STATUS_UNSUPPORTED);
    } else {
        char text[512];
        (void)snprintf(text, sizeof text, "%s%s%.*s: %s", operation, name.len != 0 ? " " : "", (int)name.len,
                       name.len != 0 ? (const char *)name.ptr : "", uv_strerror(code));
        ms_fs_fail_text(fail, text);
    }
}

void ms_fs_fail_text(MsFsFail *fail, const char *text) {
    const size_t length = strlen(text);
    char *copy = malloc(length + 1);
    if (copy == NULL) {
        ms_fs_fail_status(fail, STATUS_FAILED);
        return;
    }
    memcpy(copy, text, length + 1);
    fail_with_message(fail, copy, length);
}

/* The host's text for `error`, appended to `message`. */
static bool append_error_text(MsFsBuffer *message, MsSysError error) {
    char text[512];
    const size_t length = ms_sys_fs_error_text(error, text, sizeof text);
    return ms_fs_buffer_append(message, (const uint8_t *)text, length);
}

/* Moves a finished message buffer into the failure; an empty or failed build leaves a plain STATUS_FAILED. */
static void fail_from_buffer(MsFsFail *fail, MsFsBuffer *message, bool complete) {
    if (!complete || !ms_fs_buffer_push(message, 0)) {
        ms_fs_buffer_free(message);
        ms_fs_fail_status(fail, STATUS_FAILED);
        return;
    }
    fail_with_message(fail, (char *)message->data, message->length - 1);
    message->data = NULL;
    message->length = 0;
    message->capacity = 0;
}

void ms_fs_fail_raw(MsFsFail *fail, MsSysError error) {
    const uint8_t status = ms_fs_classify(error);
    if (status != STATUS_FAILED) {
        ms_fs_fail_status(fail, status);
        return;
    }
    MsFsBuffer message = {0};
    fail_from_buffer(fail, &message, append_error_text(&message, error));
}

void ms_fs_fail_errno(MsFsFail *fail, MsSysError error, const char *operation, const MsBytes *paths, size_t count) {
    const uint8_t status = ms_fs_classify(error);
    if (status != STATUS_FAILED) {
        ms_fs_fail_status(fail, status);
        return;
    }
    MsFsBuffer message = {0};
    bool complete = ms_fs_buffer_append(&message, (const uint8_t *)operation, strlen(operation));
    for (size_t i = 0; complete && i < count; i++) {
        complete = ms_fs_buffer_push(&message, ' ') && ms_fs_buffer_append(&message, paths[i].ptr, paths[i].len);
    }
    complete = complete && ms_fs_buffer_append(&message, (const uint8_t *)": ", 2) && append_error_text(&message, error);
    fail_from_buffer(fail, &message, complete);
}

void ms_fs_fail_os(MsFsFail *fail, MsSysError error, const char *operation, MsBytes name) {
    MsFsBuffer message = {0};
    bool complete = ms_fs_buffer_append(&message, (const uint8_t *)operation, strlen(operation)) && ms_fs_buffer_push(&message, ' ') &&
                    ms_fs_buffer_append(&message, name.ptr, name.len) && ms_fs_buffer_append(&message, (const uint8_t *)": ", 2);
    complete = complete && append_error_text(&message, error);
    fail_from_buffer(fail, &message, complete);
}

void ms_fs_fail_errno_at(MsFsFail *fail, MsSysError error, const char *operation, MsBytes path) {
    ms_fs_fail_errno(fail, error, operation, &path, 1);
}

static uint8_t finish_with(MsFsFail *fail, MsBytes detail, MsStr *err) {
    const uint8_t status = fail->status;
    if (status != STATUS_OK && ms_fs_cancel_requested()) {
        /* The text is dropped first, while the cancel can still jump. */
        ms_fs_fail_free(fail);
        ms_sched_cancel_return();
        return status;
    }
    if (err != NULL && status != STATUS_OK) {
        /* Always written for a failure: the caller reads the slot whatever the status. */
        const uint8_t *text = (const uint8_t *)"";
        size_t length = 0;
        if (status == STATUS_FAILED && fail->message != NULL) {
            text = (const uint8_t *)fail->message;
            length = fail->message_length;
        } else if (status != STATUS_FAILED) {
            text = detail.ptr;
            length = detail.len;
        }
        msrt_string_from_bytes(text, length, err);
    }
    ms_fs_fail_free(fail);
    return status;
}

uint8_t ms_fs_finish(MsFsFail *fail, MsStr *err) { return finish_with(fail, ms_bytes_of((const uint8_t *)"", 0), err); }

uint8_t ms_fs_finish_at(MsFsFail *fail, MsBytes path, MsStr *err) {
    return finish_with(fail, path, err);
}

uint8_t ms_fs_finish_pair(MsFsFail *fail, MsBytes source, MsBytes destination, MsStr *err) {
    MsFsBuffer both = {0};
    const bool built = ms_fs_buffer_append(&both, source.ptr, source.len) &&
                       ms_fs_buffer_append(&both, (const uint8_t *)" -> ", 4) &&
                       ms_fs_buffer_append(&both, destination.ptr, destination.len);
    const uint8_t status = finish_with(fail, built ? ms_fs_buffer_view(&both) : ms_bytes_of((const uint8_t *)"", 0), err);
    ms_fs_buffer_free(&both);
    return status;
}

/* ---- stop requests and the blocking pool ---- */

bool ms_fs_cancel_requested(void) { return !ms_sched_on_pool_thread() && ms_sched_cancel_pending(); }

bool ms_fs_poll_cancel(MsFsFail *fail) {
    if (!ms_fs_cancel_requested()) {
        return false;
    }
    ms_fs_fail_text(fail, "cancelled");
    return true;
}

void ms_fs_run(MsFsRunFn run, void *job, MsFsFail *fail) {
    if (ms_sched_on_pool_thread() || ms_sched_pool_alone()) {
        run(job);
        return;
    }
    if (ms_sched_pool_run_shielded(run, job) != MS_SCHED_DONE) {
        ms_fs_fail_text(fail, "cancelled");
    }
}

/* ---- validated paths ---- */

bool ms_fs_path_init(MsFsPath *path, MsBytes bytes) {
    *path = (MsFsPath){0};
    if (bytes.len == 0 || memchr(bytes.ptr, 0, bytes.len) != NULL) {
        return false;
    }
    size_t size = 0;
    if (!ms_size_add(bytes.len, 1, &size)) {
        return false;
    }
    char *target = path->inline_text;
    if (size > sizeof path->inline_text) {
        path->heap = malloc(size);
        if (path->heap == NULL) {
            return false;
        }
        target = path->heap;
    }
    memcpy(target, bytes.ptr, bytes.len);
    target[bytes.len] = '\0';
    path->text = target;
    path->length = bytes.len;
    return true;
}

void ms_fs_path_free(MsFsPath *path) {
    free(path->heap);
    path->heap = NULL;
    path->text = NULL;
}

/* ---- a growable byte buffer ---- */

static bool buffer_reserve(MsFsBuffer *buffer, size_t extra) {
    size_t needed = 0;
    if (!ms_size_add(buffer->length, extra, &needed)) {
        return false;
    }
    if (needed <= buffer->capacity) {
        return true;
    }
    size_t capacity = buffer->capacity == 0 ? 64 : buffer->capacity;
    while (capacity < needed) {
        if (!ms_size_mul(capacity, 2, &capacity)) {
            return false;
        }
    }
    uint8_t *grown = realloc(buffer->data, capacity);
    if (grown == NULL) {
        return false;
    }
    buffer->data = grown;
    buffer->capacity = capacity;
    return true;
}

bool ms_fs_buffer_append(MsFsBuffer *buffer, const uint8_t *bytes, size_t length) {
    if (!buffer_reserve(buffer, length)) {
        return false;
    }
    if (length > 0) {
        memcpy(buffer->data + buffer->length, bytes, length);
        buffer->length += length;
    }
    return true;
}

bool ms_fs_buffer_push(MsFsBuffer *buffer, uint8_t byte) { return ms_fs_buffer_append(buffer, &byte, 1); }

void ms_fs_buffer_free(MsFsBuffer *buffer) {
    free(buffer->data);
    *buffer = (MsFsBuffer){0};
}

/* ---- UTF-8 ---- */

static bool in_range(uint8_t byte, uint8_t low, uint8_t high) { return byte >= low && byte <= high; }

/* The width of the valid UTF-8 sequence at the start of `bytes` (length > 0), or 0 with `*skip` set to how many
 * bytes the invalid sequence covers (all of them when the input ends inside one). */
static size_t utf8_sequence(MsBytes bytes, size_t *skip) {
    const uint8_t first = bytes.ptr[0];
    size_t width = 0;
    uint8_t second_low = 0x80;
    uint8_t second_high = 0xBF;
    if (first < 0x80) {
        return 1;
    }
    if (in_range(first, 0xC2, 0xDF)) {
        width = 2;
    } else if (in_range(first, 0xE0, 0xEF)) {
        width = 3;
        second_low = first == 0xE0 ? 0xA0 : 0x80;
        second_high = first == 0xED ? 0x9F : 0xBF;
    } else if (in_range(first, 0xF0, 0xF4)) {
        width = 4;
        second_low = first == 0xF0 ? 0x90 : 0x80;
        second_high = first == 0xF4 ? 0x8F : 0xBF;
    } else {
        *skip = 1;
        return 0;
    }
    for (size_t i = 1; i < width; i++) {
        if (i >= bytes.len) {
            *skip = bytes.len;
            return 0;
        }
        const bool good = i == 1 ? in_range(bytes.ptr[1], second_low, second_high) : in_range(bytes.ptr[i], 0x80, 0xBF);
        if (!good) {
            *skip = i;
            return 0;
        }
    }
    return width;
}

bool ms_fs_valid_utf8(MsBytes bytes) {
    size_t at = 0;
    while (at < bytes.len) {
        size_t skip = 0;
        const size_t width = utf8_sequence(ms_bytes_of(bytes.ptr + at, bytes.len - at), &skip);
        if (width == 0) {
            return false;
        }
        at += width;
    }
    return true;
}

bool ms_fs_buffer_append_lossy(MsFsBuffer *buffer, const uint8_t *bytes, size_t length) {
    static const uint8_t replacement[] = {0xEF, 0xBF, 0xBD};
    size_t at = 0;
    while (at < length) {
        size_t skip = 0;
        const size_t width = utf8_sequence(ms_bytes_of(bytes + at, length - at), &skip);
        if (width != 0) {
            if (!ms_fs_buffer_append(buffer, bytes + at, width)) {
                return false;
            }
            at += width;
        } else {
            if (!ms_fs_buffer_append(buffer, replacement, sizeof replacement)) {
                return false;
            }
            at += skip;
        }
    }
    return true;
}

/* ---- runtime values ---- */

void ms_fs_write_string(MsStr *out, const uint8_t *bytes, size_t length) { msrt_string_from_bytes(bytes, length, out); }

void ms_fs_write_buffer_string(MsStr *out, const MsFsBuffer *buffer) {
    msrt_string_from_bytes(buffer->data, buffer->length, out);
}

bool ms_fs_limit(uint8_t present, int64_t value, int64_t *out) {
    if (present == 0) {
        *out = MS_FS_UNLIMITED;
        return true;
    }
    if (value < 0) {
        return false;
    }
    *out = value;
    return true;
}
