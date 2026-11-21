/* Buffered standard output. Every thread that runs Manuscript code appends under one spin lock, so lines stay in
 * program order; the buffer is written out when it reaches 64 KiB, on a newline when stdout is a terminal, and at
 * exit and before standard error. Output of a task under a test capture goes to that capture's buffer instead. */
#include "stdout.h"

#include <stdatomic.h>
#include <stdlib.h>

#include "ms_sched.h"
#include "spin.h"
#include "task.h"
#include "ms_rt/alloc.h"
#include "ms_rt/array.h"
#include "ms_rt/io.h"
#include "ms_rt/test.h"
#include "ms_rt/sys.h"
#include "ms_rt/sys_fs.h"

enum { BUFFER_LIMIT = 64 * 1024, STDOUT_FD = 1 };

enum { OUTPUT_MIN = 4096 };

typedef struct Bytes {
    uint8_t *items;
    size_t length;
    size_t capacity;
} Bytes;

static struct {
    MsSpin lock;
    Bytes buffer;
} out = {.lock = MS_SPIN_INIT};

static _Atomic int32_t first_error; /* the code of the first write that failed; 0: none */
static atomic_int terminal_state;       /* 0 unknown, 1 pipe or file, 2 terminal */

typedef struct Capture {
    uint64_t id;
    Bytes text;
} Capture;

static struct {
    MsSpin lock;
    Capture *items;
    size_t length;
    size_t capacity;
} captures = {.lock = MS_SPIN_INIT};
static atomic_uint_fast64_t next_capture = 1;

static void bytes_append(Bytes *bytes, const uint8_t *data, size_t length) {
    if (length == 0) {
        return;
    }
    size_t needed = 0;
    if (!ms_size_add(bytes->length, length, &needed)) {
        return; /* the request overflows the address space: cannot happen */
    }
    if (needed > bytes->capacity) {
        /* The system's allocator: the output buffer is the runtime's, not a block of the program the counting runtime
         * reports. */
        size_t capacity = bytes->capacity < OUTPUT_MIN ? OUTPUT_MIN : bytes->capacity;
        while (capacity < needed) {
            capacity *= 2;
        }
        uint8_t *const grown = realloc(bytes->items, capacity);
        if (grown == NULL) {
            return;
        }
        bytes->items = grown;
        bytes->capacity = capacity;
    }
    __builtin_memcpy(bytes->items + bytes->length, data, length);
    bytes->length = needed;
}

/* Writes out the buffer with the lock held. What cannot be written is dropped, so a later flush does not retry it. */
static void flush_locked(void) {
    size_t done = 0;
    MsSysError error = 0;
    while (done < out.buffer.length && error == 0) {
        size_t count = 0;
        error = ms_sys_fs_write(ms_sys_fs_standard(1), out.buffer.items + done, out.buffer.length - done, &count);
        if (error == 0 && count == 0) {
            break;
        }
        done += count;
    }
    out.buffer.length = 0;
    if (error != 0 && !ms_sys_error_is_broken_pipe(error)) {
        int32_t none = 0;
        atomic_compare_exchange_strong_explicit(&first_error, &none, (int32_t)error, memory_order_relaxed, memory_order_relaxed);
    }
}

int32_t ms_sched_stdout_error(void) { return atomic_load_explicit(&first_error, memory_order_relaxed); }

void ms_sched_flush_stdout(void) {
    ms_spin_lock(&out.lock);
    flush_locked();
    ms_spin_unlock(&out.lock);
}

void ms_sched_release_stdout(void) {
    ms_spin_lock(&out.lock);
    flush_locked();
    free(out.buffer.items);
    out.buffer = (Bytes){0};
    ms_spin_unlock(&out.lock);
}

static bool is_terminal(void) {
    int state = atomic_load_explicit(&terminal_state, memory_order_relaxed);
    if (state == 0) {
        state = ms_sys_fs_is_terminal(ms_sys_fs_standard(STDOUT_FD)) ? 2 : 1;
        atomic_store_explicit(&terminal_state, state, memory_order_relaxed);
    }
    return state == 2;
}

static bool has_newline(const uint8_t *data, size_t length) { return length > 0 && __builtin_memchr(data, '\n', length) != NULL; }

/* Appends to capture `id`; false when it has ended (the output then goes to standard output). */
static bool capture_append(uint64_t id, const uint8_t *data, size_t length, const uint8_t *end, size_t end_length) {
    bool found = false;
    ms_spin_lock(&captures.lock);
    for (size_t i = 0; i < captures.length && !found; i++) {
        if (captures.items[i].id == id) {
            bytes_append(&captures.items[i].text, data, length);
            bytes_append(&captures.items[i].text, end, end_length);
            found = true;
        }
    }
    ms_spin_unlock(&captures.lock);
    return found;
}

void ms_stdout_write(const uint8_t *data, size_t length, const uint8_t *end, size_t end_length) {
    const uint64_t capture = ms_task_capture();
    if (capture != 0 && capture_append(capture, data, length, end, end_length)) {
        return;
    }
    const bool flush_line = is_terminal() && (has_newline(data, length) || has_newline(end, end_length));
    ms_spin_lock(&out.lock);
    bytes_append(&out.buffer, data, length);
    bytes_append(&out.buffer, end, end_length);
    if (out.buffer.length >= BUFFER_LIMIT || flush_line) {
        flush_locked();
    }
    ms_spin_unlock(&out.lock);
}

void msrt_io_write_stdout(const MsStr *text) { ms_stdout_write(ms_str_data(text), ms_str_len(text), NULL, 0); }

void msrt_io_write_stdout_line(const MsStr *text, const MsStr *end) {
    ms_stdout_write(ms_str_data(text), ms_str_len(text), ms_str_data(end), ms_str_len(end));
}

void msrt_io_write_stderr(const MsStr *text) {
    ms_sched_flush_stdout();
    ms_sys_stderr_write((MsBytes){ms_str_data(text), ms_str_len(text)});
}

void msrt_io_write_bytes_stdout(const MsVec *bytes) { ms_stdout_write(bytes->ptr, bytes->len, NULL, 0); }

void msrt_io_write_bytes_stderr(const MsVec *bytes) {
    ms_sched_flush_stdout();
    ms_sys_stderr_write(ms_bytes_of(bytes->ptr, bytes->len));
}

void msrt_io_flush(void) { ms_sched_flush_stdout(); }

int64_t msrt_test_capture_new(void) {
    const uint64_t id = atomic_fetch_add_explicit(&next_capture, 1, memory_order_relaxed);
    ms_spin_lock(&captures.lock);
    if (ms_array_reserve_system((void **)&captures.items, &captures.capacity, captures.length + 1, sizeof *captures.items)) {
        captures.items[captures.length++] = (Capture){.id = id};
    }
    ms_spin_unlock(&captures.lock);
    return (int64_t)id;
}

void msrt_test_capture_set(int64_t id) { ms_task_set_capture((uint64_t)id); }

int64_t msrt_test_capture_current(void) { return (int64_t)ms_task_capture(); }

/* Returns and clears what capture `id` has collected. */
void msrt_test_capture_take(int64_t id, MsStr *out_text) {
    uint8_t *taken = NULL;
    size_t length = 0;
    ms_spin_lock(&captures.lock);
    for (size_t i = 0; i < captures.length; i++) {
        if (captures.items[i].id == (uint64_t)id) {
            taken = captures.items[i].text.items;
            length = captures.items[i].text.length;
            captures.items[i].text = (Bytes){0};
            break;
        }
    }
    ms_spin_unlock(&captures.lock);
    msrt_string_from_bytes(taken, length, out_text);
    free(taken);
}

/* Ends capture `id`; later output of its tasks goes to standard output. */
void msrt_test_capture_free(int64_t id) {
    ms_spin_lock(&captures.lock);
    for (size_t i = 0; i < captures.length; i++) {
        if (captures.items[i].id == (uint64_t)id) {
            free(captures.items[i].text.items);
            captures.items[i] = captures.items[--captures.length];
            break;
        }
    }
    ms_spin_unlock(&captures.lock);
}
