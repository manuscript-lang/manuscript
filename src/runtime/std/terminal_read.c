/* Reading from the raw terminal (see terminal.h): one libuv loop per terminal that runs on a pool thread for the length of
 * one wait. The loop watches the terminal, SIGWINCH (a resize ends the wait with nothing read, and the caller compares
 * sizes), a 40 ms timer for the wait that resolves a lone escape byte, and an async handle another thread uses to end the
 * wait (close, or a stop request). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "base/alloc.h"
#include "runtime/core/task.h"
#include "runtime/core/unwind.h"
#include "runtime/io/pool.h"
#include "runtime/std/fail.h"
#include "runtime/std/fs_job.h"
#include "runtime/std/terminal_state.h"

enum { READ_CAPACITY = 4096, QUICK_WAIT_MS = 40 };

/* One wait for input: runs on a pool thread, owns the bytes it reads, and holds a reference of the terminal. */
typedef struct ReadWait {
  MsTerminal *terminal; /* a reference, released with the wait */
  bool quick;           /* end after QUICK_WAIT_MS with nothing read */
  uv_timer_t timer;     /* on the terminal's loop while the wait runs */
  uint8_t bytes[READ_CAPACITY];
  size_t length; /* bytes read */
  bool ended;    /* input ended or failed */
} ReadWait;

static void on_alloc(uv_handle_t *handle, size_t suggested, uv_buf_t *buffer) {
  ReadWait *wait = handle->data;
  (void)suggested;
  if (atomic_load(&wait->terminal->abandoned)) {
    /* No buffer: libuv reports UV_ENOBUFS and leaves the bytes in the descriptor for the next wait. */
    *buffer = uv_buf_init(NULL, 0);
    return;
  }
  *buffer = uv_buf_init((char *)wait->bytes, (unsigned int)sizeof wait->bytes);
}

static void on_read(uv_stream_t *stream, ssize_t count, const uv_buf_t *buffer) {
  ReadWait *wait = stream->data;
  (void)buffer;
  if (count == 0) {
    return;
  }
  if (count > 0) {
    wait->length = (size_t)count;
  } else if (count != UV_ENOBUFS) {
    wait->ended = true;
  }
  (void)uv_read_stop(stream);
  uv_stop(stream->loop);
}

static void on_quick_timeout(uv_timer_t *timer) { uv_stop(timer->loop); }

/* The pool job: loops the terminal's loop until a key arrives, the input ends, a resize or a wake-up comes, or the quick
 * timer runs out. */
static void read_run(void *data) {
  ReadWait *wait = data;
  MsTerminal *terminal = wait->terminal;
  /* One job at a time on the loop: a wait the caller gave up on (a timed-out `next`) ends when its wake-up reaches it,
   * and a job that started meanwhile would share its loop and input and could take a key into the abandoned wait. */
  uv_mutex_lock(&terminal->read_lock);
  if (atomic_load(&terminal->closed)) {
    wait->ended = true;
    uv_mutex_unlock(&terminal->read_lock);
    return;
  }
  atomic_store(&terminal->abandoned, false); /* the previous job ended: its caller's give-up is not this one's */
  terminal->input.data = wait;
  (void)uv_timer_init(&terminal->loop, &wait->timer);
  if (wait->quick) {
    (void)uv_timer_start(&wait->timer, on_quick_timeout, QUICK_WAIT_MS, 0);
  }
  if (uv_read_start((uv_stream_t *)&terminal->input, on_alloc, on_read) < 0) {
    wait->ended = true;
  } else {
    (void)uv_run(&terminal->loop, UV_RUN_DEFAULT);
    (void)uv_read_stop((uv_stream_t *)&terminal->input);
  }
  uv_timer_stop(&wait->timer);
  uv_close((uv_handle_t *)&wait->timer, NULL);
  (void)uv_run(&terminal->loop, UV_RUN_NOWAIT);
  uv_mutex_unlock(&terminal->read_lock);
}

/* Frees a wait, on the runtime thread: now, or after the pool finished an abandoned one. */
static void read_release(void *data) {
  ReadWait *wait = data;
  ms_terminal_release(wait->terminal);
  ms_free(wait);
}

/* The width in bytes of the scalar a lead byte starts (1 for a byte that starts none). */
static size_t scalar_width(uint8_t lead) {
  if ((lead & 0xF8u) == 0xF0u) {
    return 4;
  }
  if ((lead & 0xF0u) == 0xE0u) {
    return 3;
  }
  return (lead & 0xE0u) == 0xC0u ? 2 : 1;
}

/* How many bytes at the end of `bytes` start a scalar that is not complete yet (0 when none does). */
static size_t incomplete_tail(MsSpan bytes) {
  const size_t limit = bytes.len < MS_UTF8_MAX - 1 ? bytes.len : MS_UTF8_MAX - 1;
  for (size_t back = 1; back <= limit; back++) {
    const uint8_t byte = bytes.ptr[bytes.len - back];
    if ((byte & 0xC0u) == 0x80u) {
      continue; /* a continuation byte */
    }
    return scalar_width(byte) > back ? back : 0;
  }
  return 0;
}

/* Turns the carried bytes and `bytes` into the terminal's text: complete scalars only, invalid bytes as U+FFFD, an
 * incomplete trailing scalar kept for the next read. */
static void decode_input(MsTerminal *terminal, MsSpan bytes) {
  MsStrBuild joined = ms_strbuild_new();
  ms_strbuild_clear(&terminal->text);
  ms_strbuild_append(&joined, ms_span_of(terminal->carry, terminal->carry_length));
  ms_strbuild_append(&joined, bytes);
  const MsSpan all = ms_strbuild_span(&joined);
  const size_t tail = incomplete_tail(all);
  const size_t complete = all.len - tail;
  ms_fs_append_lossy(&terminal->text, ms_span_of(all.ptr, complete));
  __builtin_memcpy(terminal->carry, all.ptr + complete, tail);
  terminal->carry_length = tail;
  ms_strbuild_free(&joined);
}

/* The status a finished wait reports and, for MS_STATUS_OK, the text it delivered. */
static uint8_t wait_status(MsTerminal *terminal, const ReadWait *wait) {
  if (wait->length == 0) {
    if (wait->ended || atomic_load(&terminal->closed)) {
      return MS_STATUS_CLOSED;
    }
    /* A bounded read whose time is up returns its parks at once, so "nothing came" would make the caller retry without
     * end. */
    return ms_task_read_limit_passed() ? MS_STATUS_TIMED_OUT : MS_STATUS_NONE;
  }
  decode_input(terminal, ms_span_of(wait->bytes, wait->length));
  return ms_strbuild_length(&terminal->text) == 0 ? MS_STATUS_NONE : MS_STATUS_OK;
}

uint8_t ms_terminal_read(MsTerminal *terminal, bool quick) {
  if (ms_fail_cancel_requested()) {
    return MS_STATUS_CANCELLED;
  }
  if (atomic_load(&terminal->closed)) {
    return MS_STATUS_CLOSED;
  }
  ReadWait *wait = ms_alloc_zeroed(sizeof *wait);
  ms_terminal_retain(terminal);
  wait->terminal = terminal;
  wait->quick = quick;
  const MsPoolWait outcome = ms_pool_run(read_run, read_release, wait, -1);
  if (outcome != MS_POOL_DONE) {
    /* The pool owns the wait now and ends it when the wake-up reaches it; the handle keeps the terminal alive. A bounded
     * read (`next(timeout:)`) whose time is up ends here too, as a timeout. */
    atomic_store(&terminal->abandoned, true);
    (void)uv_async_send(&terminal->wake);
    if (outcome == MS_POOL_TIMED_OUT) {
      return MS_STATUS_TIMED_OUT;
    }
    return MS_STATUS_CANCELLED;
  }
  const uint8_t status = wait_status(terminal, wait);
  read_release(wait);
  return ms_fail_cancel_requested() ? (uint8_t)MS_STATUS_CANCELLED : status;
}
