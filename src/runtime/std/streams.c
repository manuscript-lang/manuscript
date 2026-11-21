/* The descriptor stream table: one entry per descriptor-backed ReadStream[Bytes] or WriteStream[Bytes], in a flat array
 * indexed by a generation-tagged id (streams.h has the contract).
 *
 * A read tries the system call at once and registers with the poller only when the call would block. A write appends
 * to the entry's buffer and drains it past 64 KiB or on flush. A failure ends the promise with no value and stays on
 * the entry: a write failure stays until close, because the unwritten bytes were discarded, so a later empty flush
 * cannot establish success. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "runtime/std/streams.h"

#include <uv.h>

#include "base/alloc.h"
#include "base/strbuild.h"
#include "runtime/core/fault_abi.h"
#include "runtime/core/promise.h"
#include "runtime/core/task.h"
#include "runtime/sys/spin.h"
#include "runtime/sys/sys.h"

enum {
  READ_CHUNK = 64 * 1024, /* bytes a read asks the system for */
  AUTO_DRAIN = 64 * 1024, /* buffered bytes past which write drains on its own */
  FIRST_ENTRIES = 8,
  GENERATION_LIMIT = INT32_MAX, /* a slot whose generation ran out is never reused */
};

typedef struct Entry {
  uint32_t generation;
  bool live;
  uv_file fd;
  int64_t flags;
  uint8_t *out; /* accepted bytes not yet drained are out[out_start..out_len] */
  size_t out_len;
  size_t out_start;
  size_t out_cap;
  MsPromise reading; /* the read promise waiting on the poller, 0 when none */
  MsString error;    /* the message of a read failure or terminal write failure; empty when none */
} Entry;

static struct {
  MsSpin lock;
  Entry *entries; /* grows, so an Entry pointer is valid only while the lock is held */
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

static void entry_set_error(Entry *entry, MsSpan text) {
  ms_string_release(&entry->error);
  entry->error = ms_string_from_span(text);
}

static void entry_clear_error(Entry *entry) {
  ms_string_release(&entry->error);
  entry->error = ms_string_empty();
}

/* Records a failure as `what: reason`; a code of 0 means the descriptor accepted no bytes. */
static void entry_fail(Entry *entry, const char *what, int code) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, what);
  ms_strbuild_append_text(&text, ": ");
  ms_strbuild_append_text(&text, code != 0 ? uv_strerror(code) : "accepted no bytes");
  ms_string_release(&entry->error);
  entry->error = ms_strbuild_finish(&text);
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
  int error; /* TRANSFER_FAILED: the libuv status */
} Transfer;

/* One read (`read_into`) or write (`write_from`), retrying an interrupted call and reporting a would-block call as
 * blocked. */
static Transfer transfer(const Entry *entry, uint8_t *read_into, const uint8_t *write_from, size_t length) {
  const unsigned size = length > (size_t)INT32_MAX ? (unsigned)INT32_MAX : (unsigned)length;
  const uv_buf_t buffer = uv_buf_init(read_into != NULL ? (char *)read_into : (char *)(uintptr_t)write_from, size);
  int64_t result = 0;
  do {
    uv_fs_t request;
    result = read_into != NULL ? uv_fs_read(NULL, &request, entry->fd, &buffer, 1, -1, NULL)
                               : uv_fs_write(NULL, &request, entry->fd, &buffer, 1, -1, NULL);
    uv_fs_req_cleanup(&request);
  } while (result == UV_EINTR);
  if (result >= 0) {
    return (Transfer){.kind = TRANSFER_DONE, .count = (size_t)result};
  }
  return (Transfer){.kind = result == UV_EAGAIN ? TRANSFER_BLOCKED : TRANSFER_FAILED, .error = (int)result};
}

/* Whether a read would not block. A descriptor opened without NONBLOCK (the inherited standard input, whose file
 * description other processes share) is polled first, so a silent pipe parks the task instead of the thread. */
static bool readable_now(const Entry *entry) {
  return (entry->flags & MS_STREAMS_NONBLOCK) != 0 || ms_sys_fd_readable_now(entry->fd);
}

typedef enum { STEP_DATA, STEP_END, STEP_BLOCKED, STEP_FAILED } StepKind;

typedef struct Step {
  StepKind kind;
  MsList data; /* STEP_DATA: the chunk, in a heap block the promise's Bytes will own */
} Step;

/* A short read keeps its block when it fills at least half of it, else moves to an exact one, so a trickle of small
 * reads does not pin 64 KiB each. */
static MsList chunk_of(uint8_t *block, size_t count) {
  if (count >= READ_CHUNK / 2) {
    return (MsList){.ptr = block, .len = count, .cap = READ_CHUNK};
  }
  uint8_t *small = ms_alloc(count);
  __builtin_memcpy(small, block, count);
  ms_free(block);
  return (MsList){.ptr = small, .len = count, .cap = count};
}

static Step try_read(Entry *entry) {
  Step step = {.kind = STEP_BLOCKED};
  if (!readable_now(entry)) {
    return step;
  }
  uint8_t *block = ms_alloc(READ_CHUNK);
  const Transfer got = transfer(entry, block, NULL, READ_CHUNK);
  if (got.kind == TRANSFER_DONE && got.count > 0) {
    step.kind = STEP_DATA;
    step.data = chunk_of(block, got.count);
    return step;
  }
  ms_free(block);
  if (got.kind == TRANSFER_DONE) {
    step.kind = STEP_END;
  } else if (got.kind == TRANSFER_FAILED) {
    entry_fail(entry, "read", got.error);
    step.kind = STEP_FAILED;
  }
  return step;
}

/* Completes the promise with the step: the Bytes value takes the chunk's block, otherwise there is no value. */
static void finish_step(MsPromise id, const Step *step) {
  if (step->kind != STEP_DATA) {
    ms_promise_io_done(id);
    return;
  }
  MsList *block = ms_alloc(sizeof *block);
  *block = step->data;
  ms_promise_io_done_block(id, block, &ms_desc_bytes, 0);
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

/* A free slot (the table lock held), growing the table when none is. */
static size_t slot_take(void) {
  size_t slot = 0;
  while (slot < table.count && (table.entries[slot].live || table.entries[slot].generation >= GENERATION_LIMIT)) {
    slot++;
  }
  if (slot == table.count) {
    if (table.count == table.cap) {
      table.cap = table.cap == 0 ? FIRST_ENTRIES : table.cap * 2;
      table.entries = ms_realloc(table.entries, table.cap * sizeof(Entry));
    }
    table.entries[table.count++] = (Entry){.error = ms_string_empty()};
  }
  return slot;
}

int64_t msrt_streams_open(int64_t fd, int64_t flags) {
  if ((flags & MS_STREAMS_NONBLOCK) != 0) {
    (void)ms_sys_fd_set_nonblocking((int)fd, true);
  }
  ms_spin_lock(&table.lock);
  const size_t slot = slot_take();
  Entry *entry = &table.entries[slot];
  entry->generation++;
  entry->live = true;
  entry->fd = (uv_file)fd;
  entry->flags = flags;
  entry_reset_out(entry);
  entry->reading = 0;
  entry_clear_error(entry);
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

static void fault_text(const char *message) { msrt_fault((const uint8_t *)message, __builtin_strlen(message)); }

int64_t msrt_streams_read(int64_t stream) {
  const MsPromise id = ms_promise_new();
  Entry *entry = entry_lock(stream);
  if (entry == NULL) {
    ms_promise_io_done(id);
    return id;
  }
  if ((entry->flags & MS_STREAMS_READS) == 0) {
    entry_set_error(entry, ms_span_of_text("read: the stream is not readable"));
    entry_unlock();
    ms_promise_io_done(id);
    return id;
  }
  if (entry->reading != 0) {
    entry_unlock();
    fault_text("stream: a read is already waiting");
  }
  entry_clear_error(entry);
  const Step step = try_read(entry);
  if (step.kind == STEP_BLOCKED) {
    entry->reading = id;
  }
  const int fd = entry->fd;
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

/* Grows the buffer to hold `needed` bytes (the table lock held). */
static void out_reserve(Entry *entry, size_t needed) {
  if (needed <= entry->out_cap) {
    return;
  }
  size_t cap = entry->out_cap == 0 ? READ_CHUNK : entry->out_cap;
  while (cap < needed && cap <= SIZE_MAX / 2) {
    cap *= 2;
  }
  if (cap < needed) {
    entry_unlock();
    fault_text("stream: write buffer limit exceeded");
  }
  entry->out = ms_realloc(entry->out, cap);
  entry->out_cap = cap;
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
  if (!ms_string_is_empty(&entry->error)) { /* a terminal write failure: nothing more is queued */
    entry_unlock();
    return 0;
  }
  size_t needed = 0;
  if (!ms_size_add(entry->out_len, data->len, &needed)) {
    entry_unlock();
    fault_text("stream: write buffer limit exceeded");
  }
  out_reserve(entry, needed);
  if (data->len > 0) {
    __builtin_memcpy(entry->out + entry->out_len, data->ptr, data->len);
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
    fd = entry->fd;
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

void msrt_streams_error(int64_t stream, MsString *out) {
  Entry *entry = entry_lock(stream);
  if (entry == NULL) {
    *out = ms_string_empty();
    return;
  }
  *out = ms_string_clone(&entry->error);
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
  if ((entry->flags & MS_STREAMS_OWNS) != 0) {
    uv_fs_t request;
    (void)uv_fs_close(NULL, &request, entry->fd, NULL); /* the descriptor is gone either way */
    uv_fs_req_cleanup(&request);
  }
  entry->live = false;
  ms_free(entry->out);
  entry->out = NULL;
  entry->out_cap = 0;
  entry_reset_out(entry);
  entry_clear_error(entry);
  entry_unlock();
}
