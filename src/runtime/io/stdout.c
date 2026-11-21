/* Buffered standard output. Every thread that runs Manuscript code appends under one spin lock, so lines stay in
 * program order; the buffer is written out when it reaches 64 KiB, on a newline when stdout is a terminal, and at exit
 * and before standard error. Output of a task under a test capture goes to that capture's buffer instead. */
#include "runtime/io/stdout.h"

#include <stdatomic.h>

#include "base/list.h"
#include "runtime/core/fault_kept.h"
#include "runtime/core/task.h"
#include "runtime/sys/spin.h"
#include "runtime/sys/sys.h"

enum { BUFFER_LIMIT = 64 * 1024 };

MS_LIST_DEFINE(ByteBuffer, byte_buffer, uint8_t)

typedef struct Capture {
  uint64_t id;
  ByteBuffer text;
} Capture;

MS_LIST_DEFINE(CaptureList, capture_list, Capture)

static struct {
  MsSpin lock;
  ByteBuffer buffer;
} out = {.lock = MS_SPIN_INIT};

static struct {
  MsSpin lock;
  CaptureList list;
} captures = {.lock = MS_SPIN_INIT};

static _Atomic int32_t first_error; /* the code of the first write that failed; 0: none */
static atomic_int terminal_state;   /* 0 unknown, 1 pipe or file, 2 terminal */
static atomic_uint_fast64_t next_capture = 1;

static void buffer_append(ByteBuffer *buffer, MsSpan data) {
  if (data.len > 0) {
    __builtin_memcpy(byte_buffer_extend(buffer, data.len), data.ptr, data.len);
  }
}

/* Writes out the buffer with the lock held. What cannot be written is dropped, so a later flush does not retry it. */
static void flush_locked(void) {
  size_t done = 0;
  int32_t error = 0;
  while (done < out.buffer.len && error == 0) {
    size_t count = 0;
    error = ms_sys_stdout_write(ms_span_of(out.buffer.ptr + done, out.buffer.len - done), &count);
    if (error == 0 && count == 0) {
      break;
    }
    done += count;
  }
  out.buffer.len = 0;
  if (error != 0 && !ms_sys_error_is_broken_pipe(error)) {
    int32_t none = 0;
    (void)atomic_compare_exchange_strong_explicit(&first_error, &none, error, memory_order_relaxed, memory_order_relaxed);
  }
}

int32_t ms_stdout_error(void) { return atomic_load_explicit(&first_error, memory_order_relaxed); }

void ms_stdout_flush(void) {
  ms_spin_lock(&out.lock);
  flush_locked();
  ms_spin_unlock(&out.lock);
}

void ms_stdout_release(void) {
  ms_spin_lock(&out.lock);
  flush_locked();
  byte_buffer_free(&out.buffer);
  ms_spin_unlock(&out.lock);
}

static bool is_terminal(void) {
  int state = atomic_load_explicit(&terminal_state, memory_order_relaxed);
  if (state == 0) {
    state = ms_sys_stdout_is_terminal() ? 2 : 1;
    atomic_store_explicit(&terminal_state, state, memory_order_relaxed);
  }
  return state == 2;
}

static bool has_newline(MsSpan data) { return data.len > 0 && __builtin_memchr(data.ptr, '\n', data.len) != NULL; }

/* Appends to capture `id`; false when it has ended (the output then goes to standard output). */
static bool capture_append(uint64_t id, MsSpan data, MsSpan end) {
  bool found = false;
  ms_spin_lock(&captures.lock);
  for (size_t i = 0; i < captures.list.len && !found; i++) {
    Capture *capture = &captures.list.ptr[i];
    if (capture->id == id) {
      buffer_append(&capture->text, data);
      buffer_append(&capture->text, end);
      found = true;
    }
  }
  ms_spin_unlock(&captures.lock);
  return found;
}

void ms_stdout_write(MsSpan data, MsSpan end) {
  const uint64_t capture = ms_task_capture();
  if (capture != 0 && capture_append(capture, data, end)) {
    return;
  }
  const bool flush_line = is_terminal() && (has_newline(data) || has_newline(end));
  ms_spin_lock(&out.lock);
  buffer_append(&out.buffer, data);
  buffer_append(&out.buffer, end);
  if (out.buffer.len >= BUFFER_LIMIT || flush_line) {
    flush_locked();
  }
  ms_spin_unlock(&out.lock);
}

void msrt_io_write_stdout(const MsString *text) { ms_stdout_write(ms_string_span(text), ms_span_of(NULL, 0)); }

void msrt_io_write_stdout_line(const MsString *text, const MsString *end) {
  ms_stdout_write(ms_string_span(text), ms_string_span(end));
}

void msrt_io_write_stderr(const MsString *text) {
  ms_stdout_flush();
  ms_sys_stderr_write(ms_string_span(text));
}

void msrt_io_write_bytes_stdout(const MsList *bytes) { ms_stdout_write(ms_span_of(bytes->ptr, bytes->len), ms_span_of(NULL, 0)); }

void msrt_io_write_bytes_stderr(const MsList *bytes) {
  ms_stdout_flush();
  ms_sys_stderr_write(ms_span_of(bytes->ptr, bytes->len));
}

void msrt_io_flush(void) { ms_stdout_flush(); }

int64_t msrt_test_capture_new(void) {
  const uint64_t id = atomic_fetch_add_explicit(&next_capture, 1, memory_order_relaxed);
  ms_spin_lock(&captures.lock);
  capture_list_push(&captures.list, (Capture){.id = id});
  ms_spin_unlock(&captures.lock);
  return (int64_t)id;
}

void msrt_test_capture_set(int64_t id) { ms_task_set_capture((uint64_t)id); }

int64_t msrt_test_capture_current(void) { return (int64_t)ms_task_capture(); }

/* Returns and clears what capture `id` has collected. */
void msrt_test_capture_take(int64_t id, MsString *out_text) {
  ByteBuffer taken = {0};
  ms_spin_lock(&captures.lock);
  for (size_t i = 0; i < captures.list.len; i++) {
    Capture *capture = &captures.list.ptr[i];
    if (capture->id == (uint64_t)id) {
      taken = capture->text;
      capture->text = (ByteBuffer){0};
      break;
    }
  }
  ms_spin_unlock(&captures.lock);
  *out_text = ms_string_from_span(ms_span_of(taken.ptr, taken.len));
  byte_buffer_free(&taken);
}

/* Ends capture `id`; later output of its tasks goes to standard output. */
void msrt_test_capture_free(int64_t id) {
  ms_test_drop_fault((uint64_t)id);
  ms_spin_lock(&captures.lock);
  for (size_t i = 0; i < captures.list.len; i++) {
    if (captures.list.ptr[i].id == (uint64_t)id) {
      byte_buffer_free(&captures.list.ptr[i].text);
      captures.list.ptr[i] = captures.list.ptr[--captures.list.len];
      break;
    }
  }
  ms_spin_unlock(&captures.lock);
}
