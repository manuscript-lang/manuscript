/* The descriptor stream table: one entry per descriptor-backed ReadStream[Bytes] or WriteStream[Bytes], in a flat
 * array indexed by a generation-tagged id (ms_rt/streams.h has the contract).
 *
 * A read tries the system call at once and registers with the poller only when the call would block. A write
 * appends to the entry's buffer and drains it past 64 KiB or on flush. A failure ends the promise with no value
 * and stays on the entry: a write failure stays until close, because the unwritten bytes were discarded, so a
 * later empty flush cannot establish success.
 *
 * On Windows a child's pipe ends are the poller's overlapped pipes, which the scheduler reads and writes by
 * parking the calling task (ms_sched_pipe_*), so such a read or flush completes before it returns; the standard
 * handles block their thread as they always did.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms_rt/alloc.h"
#include "ms_rt/streams.h"
#include "ms_rt/sys.h"
#include "ms_rt/sys_fs.h"
#include "ms_sched.h"
#include "promise.h"
#include "spin.h"


enum {
    READ_CHUNK = 64 * 1024,  /* bytes a read asks the system for */
    AUTO_DRAIN = 64 * 1024,  /* buffered bytes past which write drains on its own */
    REASON_BYTES = 128,
    STANDARD_STREAMS = 3,
    FIRST_GENERATION_LIMIT = INT32_MAX /* a slot whose generation ran out is never reused */
};

typedef struct Entry {
    uint32_t generation;
    bool live;
    MsSysFd fd;
    int64_t flags;
    uint8_t *out; /* owned (system allocator): accepted bytes not yet drained are out[out_start..out_len] */
    size_t out_len;
    size_t out_start;
    size_t out_cap;
    MsPromise reading; /* the read promise waiting on the poller, 0 when none */
    char *error;       /* owned: the message of a read failure or terminal write failure, NULL when none */
    size_t error_len;
} Entry;

static struct {
    MsSpin lock;
    Entry *entries; /* owned; grows, so an Entry pointer is valid only while the lock is held */
    size_t count;
    size_t cap;
} table = {.lock = MS_SPIN_INIT};

/* ---- entries ---- */

/* The live entry of `id`, with the table lock held; NULL (lock released) when the stream is gone. */
static Entry *entry_lock(int64_t id) {
    ms_spin_lock(&table.lock);
    const int64_t position = (id & 0xffffffff) - 1;
    if (position >= 0 && (size_t)position < table.count) {
        Entry *entry = &table.entries[position];
        if (entry->live && (int64_t)entry->generation == id >> 32) {
            return entry;
        }
    }
    ms_spin_unlock(&table.lock);
    return NULL;
}

static void entry_unlock(void) { ms_spin_unlock(&table.lock); }

static void entry_set_error(Entry *entry, const char *text, size_t length) {
    free(entry->error);
    entry->error = malloc(length + 1);
    if (entry->error == NULL) {
        entry->error_len = 0;
        return;
    }
    memcpy(entry->error, text, length);
    entry->error[length] = '\0';
    entry->error_len = length;
}

/* Records a failure as `what: reason`, with the reason in the lower-case wording the other runtime errors use. A code
 * of 0 means the descriptor accepted no bytes. */
static void entry_fail(Entry *entry, const char *what, MsSysError code) {
    char reason[REASON_BYTES] = "accepted no bytes";
    if (code != 0) {
        (void)ms_sys_fs_error_text(code, reason, sizeof reason);
    }
    char text[REASON_BYTES + 32];
    const int length = snprintf(text, sizeof text, "%s: %s", what, reason);
    entry_set_error(entry, text, length > 0 ? (size_t)length : 0);
}

static size_t entry_buffered(const Entry *entry) { return entry->out_len - entry->out_start; }

static void entry_reset_out(Entry *entry) {
    entry->out_len = 0;
    entry->out_start = 0;
}

/* ---- transfers ---- */

typedef enum { TRANSFER_DONE, TRANSFER_BLOCKED, TRANSFER_FAILED } TransferKind;

typedef struct Transfer {
    TransferKind kind;
    size_t count;
    MsSysError error; /* TRANSFER_FAILED: the host code */
} Transfer;

#ifdef _WIN32
static bool is_adopted(const Entry *entry) { return ms_sched_pipe_is_adopted((intptr_t)entry->fd); }
#endif

/* One read or write, retrying an interrupted call and reporting a would-block call as blocked. */
static Transfer transfer(Entry *entry, uint8_t *read_into, const uint8_t *write_from, size_t length) {
    Transfer result = {.kind = TRANSFER_DONE};
    for (;;) {
#ifdef _WIN32
        if (is_adopted(entry)) {
            int32_t os_error = 0;
            const MsPipeStatus status = read_into != NULL
                                            ? ms_sched_pipe_read((intptr_t)entry->fd, read_into, length, &result.count, &os_error)
                                            : ms_sched_pipe_write((intptr_t)entry->fd, write_from, length, &os_error);
            if (status != MS_PIPE_OK) {
                result.kind = TRANSFER_FAILED;
                result.error = status == MS_PIPE_ERROR ? os_error : ms_sys_fs_error_of(MS_SYS_ERR_IO);
            } else if (write_from != NULL) {
                result.count = length;
            }
            return result;
        }
#endif
        result.error = read_into != NULL ? ms_sys_fs_read(entry->fd, read_into, length, &result.count)
                                         : ms_sys_fs_write(entry->fd, write_from, length, &result.count);
        if (result.error == 0) {
            return result;
        }
        const MsSysErrorKind kind = ms_sys_fs_error_kind(result.error);
        if (kind == MS_SYS_ERR_INTERRUPTED) {
            continue;
        }
        result.kind = kind == MS_SYS_ERR_WOULD_BLOCK ? TRANSFER_BLOCKED : TRANSFER_FAILED;
        return result;
    }
}

/* Whether a read would not block. A descriptor opened without NONBLOCK (the inherited standard input, whose file
 * description other processes share) is polled first, so a silent pipe parks the task instead of the thread. */
static bool readable_now(const Entry *entry) {
    return (entry->flags & MS_STREAMS_NONBLOCK) != 0 || ms_sys_fd_readable_now((int)entry->fd);
}

typedef enum { STEP_DATA, STEP_END, STEP_BLOCKED, STEP_FAILED } StepKind;

typedef struct Step {
    StepKind kind;
    MsList data; /* STEP_DATA: the chunk, in a heap block the promise's Bytes will own */
} Step;

/* A short read keeps its block when it fills at least half of it, else moves to an exact one, so a trickle of
 * small reads does not pin 64 KiB each. */
static MsList chunk_of(uint8_t *block, size_t count) {
    if (count >= READ_CHUNK / 2) {
        return (MsList){.ptr = block, .len = count, .cap = READ_CHUNK};
    }
    uint8_t *small = msrt_alloc(count);
    memcpy(small, block, count);
    msrt_free(block);
    return (MsList){.ptr = small, .len = count, .cap = count};
}

static Step try_read(Entry *entry) {
    Step step = {.kind = STEP_BLOCKED};
    if (!readable_now(entry)) {
        return step;
    }
    uint8_t *block = msrt_alloc(READ_CHUNK);
    const Transfer got = transfer(entry, block, NULL, READ_CHUNK);
    if (got.kind == TRANSFER_DONE && got.count > 0) {
        step.kind = STEP_DATA;
        step.data = chunk_of(block, got.count);
        return step;
    }
    msrt_free(block);
    if (got.kind == TRANSFER_DONE) {
        step.kind = STEP_END;
    } else if (got.kind == TRANSFER_FAILED) {
        entry_fail(entry, "read", got.error);
        step.kind = STEP_FAILED;
    }
    return step;
}

/* Hands the chunk to the promise: the Bytes value takes the block. */
static void finish_data(MsPromise id, MsList data) {
    MsList *block = msrt_alloc(sizeof *block);
    *block = data;
    ms_promise_io_done_block(id, block, &msrt_desc_bytes, 0);
}

static void finish_step(MsPromise id, const Step *step) {
    if (step->kind == STEP_DATA) {
        finish_data(id, step->data);
    } else {
        ms_promise_io_done(id);
    }
}

/* Writes as much of the buffer as the descriptor takes now; whether it is empty. A failure empties it. */
static bool drain(Entry *entry) {
    while (entry->out_start < entry->out_len) {
        const Transfer sent = transfer(entry, NULL, entry->out + entry->out_start, entry_buffered(entry));
        if (sent.kind == TRANSFER_BLOCKED) {
            return false;
        }
        if (sent.kind == TRANSFER_FAILED || sent.count == 0) {
            entry_fail(entry, "write", sent.kind == TRANSFER_FAILED ? sent.error : 0);
            entry_reset_out(entry);
            return true;
        }
        entry->out_start += sent.count;
    }
    entry_reset_out(entry);
    return true;
}

/* ---- the program ABI ---- */

int64_t msrt_streams_open(int64_t fd, int64_t flags) {
    MsSysFd descriptor = (MsSysFd)fd;
#ifdef _WIN32
    if (fd >= 0 && fd < STANDARD_STREAMS) {
        descriptor = ms_sys_fs_standard((int32_t)fd);
    }
#endif
    if ((flags & MS_STREAMS_NONBLOCK) != 0) {
        (void)ms_sys_fd_set_nonblocking((int)descriptor, true);
    }
    ms_spin_lock(&table.lock);
    size_t slot = 0;
    while (slot < table.count && (table.entries[slot].live || table.entries[slot].generation >= FIRST_GENERATION_LIMIT)) {
        slot++;
    }
    if (slot == table.count) {
        if (table.count == table.cap) {
            const size_t cap = table.cap == 0 ? 8 : table.cap * 2;
            size_t bytes = 0;
            Entry *grown = ms_size_mul(cap, sizeof(Entry), &bytes) ? ms_sys_realloc(table.entries, bytes) : NULL;
            if (grown == NULL) {
                ms_spin_unlock(&table.lock);
                static const char message[] = "stream: out of memory";
                msrt_fault((const uint8_t *)message, sizeof message - 1);
            }
            table.entries = grown;
            table.cap = cap;
        }
        table.entries[table.count++] = (Entry){0};
    }
    Entry *entry = &table.entries[slot];
    entry->generation++;
    entry->live = true;
    entry->fd = descriptor;
    entry->flags = flags;
    entry_reset_out(entry);
    entry->reading = 0;
    free(entry->error);
    entry->error = NULL;
    entry->error_len = 0;
    const int64_t id = (int64_t)entry->generation << 32 | (int64_t)(slot + 1);
    ms_spin_unlock(&table.lock);
    return id;
}

/* The poller says the descriptor may be readable: try again. */
static bool read_retry(MsPromise id, uintptr_t stream, uint32_t bits) {
    Entry *entry = entry_lock((int64_t)stream);
    if ((bits & MS_WAIT_CANCELLED) != 0) {
        if (entry != NULL) {
            entry->reading = 0;
            entry_unlock();
        }
        return true;
    }
    if (entry == NULL) {
        ms_promise_io_done(id);
        return true;
    }
    const Step step = try_read(entry);
    if (step.kind != STEP_BLOCKED) {
        entry->reading = 0;
    }
    entry_unlock();
    if (step.kind == STEP_BLOCKED) {
        return false;
    }
    finish_step(id, &step);
    return true;
}

int64_t msrt_streams_read(int64_t stream) {
    const MsPromise id = ms_promise_new();
    Entry *entry = entry_lock(stream);
    if (entry == NULL) {
        ms_promise_io_done(id);
        return id;
    }
    if ((entry->flags & MS_STREAMS_READS) == 0) {
        static const char message[] = "read: the stream is not readable";
        entry_set_error(entry, message, sizeof message - 1);
        entry_unlock();
        ms_promise_io_done(id);
        return id;
    }
    if (entry->reading != 0) {
        entry_unlock();
        static const char message[] = "stream: a read is already waiting";
        msrt_fault((const uint8_t *)message, sizeof message - 1);
    }
    free(entry->error);
    entry->error = NULL;
    entry->error_len = 0;
    const Step step = try_read(entry);
    if (step.kind == STEP_BLOCKED) {
        entry->reading = id;
    }
    const int fd = (int)entry->fd;
    entry_unlock();
    if (step.kind != STEP_BLOCKED) {
        finish_step(id, &step);
    } else if (!ms_promise_io_on_ready(id, fd, MS_WAIT_READ, -1, read_retry, (uintptr_t)stream)) {
        Entry *waiting = entry_lock(stream);
        if (waiting != NULL) {
            waiting->reading = 0;
            entry_unlock();
        }
        ms_promise_io_done(id);
    }
    return id;
}

int64_t msrt_streams_write(int64_t stream, const MsList *data) {
    Entry *entry = entry_lock(stream);
    if (entry == NULL) {
        return 1;
    }
    if ((entry->flags & MS_STREAMS_WRITES) == 0) {
        entry_unlock();
        return 1;
    }
    if (entry->error != NULL) { /* a terminal write failure: nothing more is queued */
        entry_unlock();
        return 0;
    }
    size_t needed = 0;
    if (!ms_size_add(entry->out_len, data->len, &needed)) {
        entry_unlock();
        static const char message[] = "stream: write buffer limit exceeded";
        msrt_fault((const uint8_t *)message, sizeof message - 1);
    }
    if (needed > entry->out_cap) {
        size_t cap = entry->out_cap == 0 ? READ_CHUNK : entry->out_cap;
        while (cap < needed && cap <= SIZE_MAX / 2) {
            cap *= 2;
        }
        uint8_t *grown = cap >= needed ? ms_sys_realloc(entry->out, cap) : NULL;
        if (grown == NULL) {
            entry_unlock();
            static const char message[] = "stream: out of memory";
            msrt_fault((const uint8_t *)message, sizeof message - 1);
        }
        entry->out = grown;
        entry->out_cap = cap;
    }
    if (data->len > 0) {
        memcpy(entry->out + entry->out_len, data->ptr, data->len);
    }
    entry->out_len = needed;
    if (entry_buffered(entry) >= AUTO_DRAIN) {
        (void)drain(entry);
    }
    entry_unlock();
    return 0;
}

static bool write_retry(MsPromise id, uintptr_t stream, uint32_t bits) {
    if ((bits & MS_WAIT_CANCELLED) != 0) {
        return true;
    }
    Entry *entry = entry_lock((int64_t)stream);
    const bool drained = entry == NULL || drain(entry);
    if (entry != NULL) {
        entry_unlock();
    }
    if (drained) {
        ms_promise_io_done_unit(id);
    }
    return drained;
}

int64_t msrt_streams_flush(int64_t stream) {
    const MsPromise id = ms_promise_new();
    Entry *entry = entry_lock(stream);
    bool drained = true;
    int fd = -1;
    if (entry != NULL) {
        drained = drain(entry);
        fd = (int)entry->fd;
        entry_unlock();
    }
    if (drained || !ms_promise_io_on_ready(id, fd, MS_WAIT_WRITE, -1, write_retry, (uintptr_t)stream)) {
        ms_promise_io_done_unit(id);
    }
    return id;
}

int64_t msrt_streams_buffered(int64_t stream) {
    Entry *entry = entry_lock(stream);
    if (entry == NULL) {
        return 0;
    }
    const int64_t buffered = (int64_t)entry_buffered(entry);
    entry_unlock();
    return buffered;
}

void msrt_streams_error(int64_t stream, MsStr *out) {
    Entry *entry = entry_lock(stream);
    if (entry == NULL || entry->error == NULL) {
        if (entry != NULL) {
            entry_unlock();
        }
        msrt_string_from_bytes((const uint8_t *)"", 0, out);
        return;
    }
    msrt_string_from_bytes((const uint8_t *)entry->error, entry->error_len, out);
    entry_unlock();
}

void msrt_streams_close(int64_t stream) {
    Entry *entry = entry_lock(stream);
    if (entry == NULL) {
        return;
    }
    if ((entry->flags & MS_STREAMS_WRITES) != 0) {
        (void)drain(entry);
    }
    if ((entry->flags & MS_STREAMS_OWNS) != 0 && entry->fd != MS_SYS_FD_INVALID) {
#ifdef _WIN32
        if (is_adopted(entry)) {
            ms_sched_pipe_close((intptr_t)entry->fd);
        } else
#endif
        {
            const MsSysError closed = ms_sys_fs_close(entry->fd);
            (void)closed; /* the descriptor is gone either way */
        }
    }
    entry->live = false;
    entry->fd = MS_SYS_FD_INVALID;
    ms_sys_free(entry->out);
    entry->out = NULL;
    entry->out_cap = 0;
    entry_reset_out(entry);
    free(entry->error);
    entry->error = NULL;
    entry->error_len = 0;
    entry_unlock();
}
