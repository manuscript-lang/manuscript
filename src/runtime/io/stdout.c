/* Standard output through the C library's stdout, which buffers it (line by line on a terminal). The
 * buffer is flushed at exit, before standard error and before the scheduler blocks. Output of a task under a test
 * capture goes to that capture's buffer instead. */
#include "runtime/io/stdout.h"

#include <errno.h>
#include <stdatomic.h>
#include <stdio.h>

#include "base/list.h"
#include "runtime/core/fault_kept.h"
#include "runtime/core/task.h"
#include "runtime/sys/spin.h"

MS_LIST_DEFINE(ByteBuffer, byte_buffer, uint8_t)

typedef struct Capture {
  uint64_t id;
  ByteBuffer text;
} Capture;

MS_LIST_DEFINE(CaptureList, capture_list, Capture)

static struct {
  MsSpin lock;
  CaptureList list;
} captures = {.lock = MS_SPIN_INIT};

static _Atomic int32_t first_error; /* the code of the first write that failed; 0: none */
static atomic_uint_fast64_t next_capture = 1;

static void buffer_append(ByteBuffer *buffer, MsSpan data) {
  if (data.len > 0) {
    __builtin_memcpy(byte_buffer_extend(buffer, data.len), data.ptr, data.len);
  }
}

/* Remembers a failed write of the C library's stdout, unless the reader went away (which the program does not report). */
static void note_failure(void) {
  const int code = errno;
  if (code != 0 && code != EPIPE) {
    int32_t none = 0;
    (void)atomic_compare_exchange_strong_explicit(&first_error, &none, code, memory_order_relaxed, memory_order_relaxed);
  }
  clearerr(stdout);
}

static void write_out(MsSpan bytes) {
  if (bytes.len > 0 && fwrite(bytes.ptr, 1, bytes.len, stdout) != bytes.len) {
    note_failure();
  }
}

int32_t ms_stdout_error(void) { return atomic_load_explicit(&first_error, memory_order_relaxed); }

void ms_stdout_flush(void) {
  if (fflush(stdout) != 0) {
    note_failure();
  }
}

void ms_stdout_release(void) {
  ms_stdout_flush();
  ms_spin_lock(&captures.lock);
  for (size_t i = 0; i < captures.list.len; i++) {
    byte_buffer_free(&captures.list.ptr[i].text);
  }
  capture_list_free(&captures.list);
  ms_spin_unlock(&captures.lock);
  ms_test_release_faults();
}

/* Appends to capture `id`; false when it has ended (the output then goes to standard output). */
static bool capture_append(uint64_t id, MsSpan data) {
  bool found = false;
  ms_spin_lock(&captures.lock);
  for (size_t i = 0; i < captures.list.len && !found; i++) {
    Capture *capture = &captures.list.ptr[i];
    if (capture->id == id) {
      buffer_append(&capture->text, data);
      found = true;
    }
  }
  ms_spin_unlock(&captures.lock);
  return found;
}

void ms_stdout_write(MsSpan data) {
  const uint64_t capture = ms_task_capture();
  if (capture != 0 && capture_append(capture, data)) {
    return;
  }
  write_out(data);
}

void msrt_io_write_stdout(const MsString *text) { ms_stdout_write(ms_string_span(text)); }

void msrt_io_write_stderr(const MsString *text) {
  ms_stdout_flush();
  ms_sys_stderr_write(ms_string_span(text));
}

void msrt_io_write_bytes_stdout(const MsList *bytes) { ms_stdout_write(ms_span_of(bytes->ptr, bytes->len)); }

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
