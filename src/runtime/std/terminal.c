/* The raw terminal of @std/io: capabilities, size, opening, handles and writes (see terminal.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */
#ifdef __APPLE__
#define _DARWIN_C_SOURCE 1 /* <signal.h> hides SIGWINCH under a strict POSIX level */
#endif

#include "runtime/std/terminal.h"

#include <signal.h>

#include "base/alloc.h"
#include "runtime/core/task.h"
#include "runtime/core/unwind.h"
#include "runtime/entry/entry.h"
#include "runtime/io/stdout.h"
#include "runtime/std/fail.h"
#include "runtime/std/terminal_state.h"
#include "runtime/sys/sys.h"

enum {
  WRITE_RETRY_NS = 1000000,
  TRUE_COLOR = 16777216,
  COLOR_256 = 256,
  COLOR_16 = 16,
  ENV_CAPACITY = 256,
};

/* The raw terminal holding the host terminal, or NULL. The host has one terminal and the process-exit hook has no
 * argument, so this is process-wide; it is only read and written with atomic operations. */
static _Atomic(MsTerminal *) active_terminal = NULL;
static atomic_flag exit_hook_registered = ATOMIC_FLAG_INIT;

MsTerminal *ms_terminal_active(void) { return atomic_load(&active_terminal); }

/* ---- the host terminal ---- */

static bool is_terminal(int fd) { return uv_guess_handle(fd) == UV_TTY; }

static bool raw_mode_capable(void) { return is_terminal(MS_TERMINAL_INPUT_FD) && is_terminal(MS_TERMINAL_OUTPUT_FD); }

uint8_t msstd_terminal_capabilities_input_is_terminal(void) { return is_terminal(MS_TERMINAL_INPUT_FD); }
uint8_t msstd_terminal_capabilities_output_is_terminal(void) { return is_terminal(MS_TERMINAL_OUTPUT_FD); }
uint8_t msstd_terminal_capabilities_error_is_terminal(void) { return is_terminal(MS_TERMINAL_ERROR_FD); }
uint8_t msstd_terminal_capabilities_raw_mode(void) { return raw_mode_capable(); }
uint8_t msstd_terminal_capabilities_resize_events(void) { return raw_mode_capable(); }

/* The value of an environment variable into `value`; false when it is not set. */
static bool env_text(const char *name, char *value, size_t capacity) {
  size_t size = capacity;
  return uv_os_getenv(name, value, &size) == 0;
}

static bool env_is_set(const char *name) {
  char value[ENV_CAPACITY];
  size_t size = sizeof value;
  const int code = uv_os_getenv(name, value, &size);
  return code == 0 || code == UV_ENOBUFS;
}

/* Windows 10 consoles take 24-bit color through virtual-terminal sequences, so only a TERM that says 256 colors lowers
 * it there. */
int64_t msstd_terminal_capabilities_colors(void) {
  char term[ENV_CAPACITY] = "";
  const bool has_term = env_text("TERM", term, sizeof term);
  const MsSpan term_text = ms_span_of_text(term);
  if (!is_terminal(MS_TERMINAL_OUTPUT_FD) || env_is_set("NO_COLOR") ||
      (has_term && ms_span_is_text(term_text, "dumb"))) {
    return 0;
  }
  char color_term[ENV_CAPACITY] = "";
  const bool has_color_term = env_text("COLORTERM", color_term, sizeof color_term);
  size_t at = 0;
  const bool wide = ms_span_find(term_text, ms_span_of_text("256color"), &at);
#ifdef _WIN32
  return !has_color_term && wide ? COLOR_256 : TRUE_COLOR;
#else
  const MsSpan color_text = ms_span_of_text(color_term);
  if (ms_span_is_text(color_text, "truecolor") || ms_span_is_text(color_text, "24bit")) {
    return TRUE_COLOR;
  }
  (void)has_color_term;
  return wide ? COLOR_256 : COLOR_16;
#endif
}

/* Whether `fd` is in non-blocking mode; false where the host cannot tell. */
static bool is_nonblocking(int fd) {
  bool on = false;
  return ms_sys_fd_get_nonblocking(fd, &on) && on;
}

/* The columns and rows of the terminal behind `fd` through a handle that lives for the call. libuv reopens the terminal
 * and makes the descriptor non-blocking, so the descriptor's mode is put back. False when `fd` has no size. */
static bool probe_size(int fd, int *columns, int *rows) {
  uv_loop_t loop;
  if (uv_loop_init(&loop) < 0) {
    return false;
  }
  const bool was_nonblocking = is_nonblocking(fd);
  uv_tty_t tty;
  bool sized = false;
  if (uv_tty_init(&loop, &tty, fd, 0) == 0) {
    sized = uv_tty_get_winsize(&tty, columns, rows) == 0;
    uv_close((uv_handle_t *)&tty, NULL);
    (void)uv_run(&loop, UV_RUN_NOWAIT);
  }
  (void)ms_sys_fd_set_nonblocking(fd, was_nonblocking);
  (void)uv_loop_close(&loop);
  return sized;
}

uint8_t msstd_terminal_size_status(void) {
  int columns = 0;
  int rows = 0;
  if (!is_terminal(MS_TERMINAL_OUTPUT_FD)) {
    return MS_STATUS_NOT_TERMINAL;
  }
  return probe_size(MS_TERMINAL_OUTPUT_FD, &columns, &rows) ? MS_STATUS_OK : MS_STATUS_UNSUPPORTED;
}

int64_t msstd_terminal_size_columns(void) {
  int columns = 0;
  int rows = 0;
  return probe_size(MS_TERMINAL_OUTPUT_FD, &columns, &rows) ? columns : 0;
}

int64_t msstd_terminal_size_rows(void) {
  int columns = 0;
  int rows = 0;
  return probe_size(MS_TERMINAL_OUTPUT_FD, &columns, &rows) ? rows : 0;
}

/* ---- the shared terminal ---- */

void ms_terminal_retain(MsTerminal *terminal) { atomic_fetch_add(&terminal->references, 1); }

static void terminal_close(MsTerminal *terminal, bool can_park);

static void terminal_destroy(MsTerminal *terminal) {
  terminal_close(terminal, false);
  const uint32_t parts = terminal->parts;
  if ((parts & MS_TERMINAL_RESIZE) != 0) {
    uv_signal_stop(&terminal->resize);
    uv_close((uv_handle_t *)&terminal->resize, NULL);
  }
  if ((parts & MS_TERMINAL_WAKE) != 0) {
    uv_close((uv_handle_t *)&terminal->wake, NULL);
  }
  if ((parts & MS_TERMINAL_INPUT) != 0) {
    uv_close((uv_handle_t *)&terminal->input, NULL);
  }
  if ((parts & MS_TERMINAL_OUTPUT) != 0) {
    uv_close((uv_handle_t *)&terminal->output, NULL);
  }
  if ((parts & MS_TERMINAL_LOOP) != 0) {
    (void)uv_run(&terminal->loop, UV_RUN_NOWAIT);
    (void)uv_loop_close(&terminal->loop);
  }
  /* libuv made the standard descriptors non-blocking when it reopened them; the program's own reads of them expect the
   * mode they had. */
  (void)ms_sys_fd_set_nonblocking(MS_TERMINAL_INPUT_FD, terminal->input_was_nonblocking);
  (void)ms_sys_fd_set_nonblocking(MS_TERMINAL_OUTPUT_FD, terminal->output_was_nonblocking);
  ms_strbuild_free(&terminal->restore);
  ms_strbuild_free(&terminal->text);
  uv_mutex_destroy(&terminal->read_lock);
  ms_free(terminal);
}

void ms_terminal_release(MsTerminal *terminal) {
  if (atomic_fetch_sub(&terminal->references, 1) == 1) {
    terminal_destroy(terminal);
  }
}

/* Waits a moment for a full terminal to drain; `can_park` lets the task park meanwhile (false at process exit, where no
 * task runs). False when a stop request ended the wait. */
static bool wait_to_retry(bool can_park) {
  if (!can_park) {
    uv_sleep(WRITE_RETRY_NS / 1000000);
    return true;
  }
  return (ms_task_sleep(WRITE_RETRY_NS) & MS_WAIT_CANCELLED) == 0;
}

/* Writes all of `data` to the terminal. A full terminal is retried every millisecond. False when the write failed or a
 * stop request ended it. */
static bool write_buffer(MsTerminal *terminal, MsSpan data, bool can_park) {
  size_t written = 0;
  while (written < data.len) {
    uv_buf_t buffer = uv_buf_init((char *)(uintptr_t)(data.ptr + written), (unsigned int)(data.len - written));
    const int count = uv_try_write((uv_stream_t *)&terminal->output, &buffer, 1);
    if (count > 0) {
      written += (size_t)count;
    } else if (count == UV_EAGAIN && wait_to_retry(can_park)) {
      continue;
    } else {
      return false;
    }
  }
  return true;
}

/* Writes all of `data` to the terminal after the output the program buffered earlier. */
static bool terminal_write(MsTerminal *terminal, MsSpan data, bool can_park) {
  if ((terminal->parts & MS_TERMINAL_OUTPUT) == 0) {
    return false;
  }
  ms_stdout_flush();
  return write_buffer(terminal, data, can_park);
}

/* Writes the restore text and the saved settings once; closing again does nothing. Safe from any thread but a read
 * wait's own: the wake handle ends a wait that is running. */
static void terminal_close(MsTerminal *terminal, bool can_park) {
  if (atomic_exchange(&terminal->closed, true)) {
    return;
  }
  if ((terminal->parts & MS_TERMINAL_WAKE) != 0) {
    (void)uv_async_send(&terminal->wake);
  }
  /* Nothing useful to report if the terminal vanished already. */
  (void)terminal_write(terminal, ms_strbuild_span(&terminal->restore), can_park);
  if ((terminal->parts & MS_TERMINAL_RAW) != 0) {
    (void)uv_tty_set_mode(&terminal->input, UV_TTY_MODE_NORMAL);
  }
  MsTerminal *self = terminal;
  (void)atomic_compare_exchange_strong(&active_terminal, &self, NULL);
}

static void restore_at_exit(void) {
  MsTerminal *terminal = atomic_load(&active_terminal);
  if (terminal != NULL) {
    terminal_close(terminal, false);
  }
}

/* ---- opening ---- */

static void on_wake(uv_async_t *handle) { uv_stop(handle->loop); }

static void on_resize(uv_signal_t *handle, int signal) {
  (void)signal;
  uv_stop(handle->loop);
}

/* Sets up the terminal's loop and handles, recording each part in `parts`. */
static int terminal_setup(MsTerminal *terminal) {
  int code = uv_loop_init(&terminal->loop);
  if (code < 0) {
    return code;
  }
  terminal->parts |= MS_TERMINAL_LOOP;
  code = uv_tty_init(&terminal->loop, &terminal->input, MS_TERMINAL_INPUT_FD, 1);
  if (code < 0) {
    return code;
  }
  terminal->parts |= MS_TERMINAL_INPUT;
  code = uv_tty_init(&terminal->loop, &terminal->output, MS_TERMINAL_OUTPUT_FD, 0);
  if (code < 0) {
    return code;
  }
  terminal->parts |= MS_TERMINAL_OUTPUT;
  code = uv_async_init(&terminal->loop, &terminal->wake, on_wake);
  if (code < 0) {
    return code;
  }
  terminal->parts |= MS_TERMINAL_WAKE;
  code = uv_signal_init(&terminal->loop, &terminal->resize);
  if (code < 0) {
    return code;
  }
  terminal->parts |= MS_TERMINAL_RESIZE;
  code = uv_signal_start(&terminal->resize, on_resize, SIGWINCH);
  if (code < 0) {
    return code;
  }
  code = uv_tty_set_mode(&terminal->input, UV_TTY_MODE_RAW);
  if (code >= 0) {
    terminal->parts |= MS_TERMINAL_RAW;
  }
  return code;
}

static void handle_drop(MsObj *object) {
  MsTerminalHandle *handle = (MsTerminalHandle *)object;
  MsTerminal *terminal = handle->terminal;
  ms_free(handle);
  /* The last handle's drop closes the terminal; a read still running holds its own reference. */
  if (atomic_fetch_sub(&terminal->handles, 1) == 1) {
    terminal_close(terminal, true);
  }
  ms_terminal_release(terminal);
}

/* A handle that owns one reference of `terminal`. */
static MsTerminalHandle *handle_new(MsTerminal *terminal) {
  MsTerminalHandle *handle = ms_alloc_zeroed(sizeof *handle);
  atomic_fetch_add(&terminal->handles, 1);
  handle->header.drop = handle_drop;
  handle->terminal = terminal;
  return handle;
}

/* A new terminal in raw mode, with one reference for the caller, or NULL with `err` set. */
static MsTerminal *terminal_open(MsString *err) {
  MsTerminal *terminal = ms_alloc_zeroed(sizeof *terminal);
  atomic_init(&terminal->references, 1);
  atomic_init(&terminal->handles, 0);
  atomic_init(&terminal->closed, false);
  terminal->restore = ms_strbuild_new();
  terminal->text = ms_strbuild_new();
  if (uv_mutex_init(&terminal->read_lock) < 0) {
    *err = ms_string_from_span(ms_span_of_text("cannot enter raw mode"));
    ms_free(terminal);
    return NULL;
  }
  terminal->input_was_nonblocking = is_nonblocking(MS_TERMINAL_INPUT_FD);
  terminal->output_was_nonblocking = is_nonblocking(MS_TERMINAL_OUTPUT_FD);
  if (terminal_setup(terminal) < 0) {
    *err = ms_string_from_span(ms_span_of_text("cannot enter raw mode"));
    terminal_destroy(terminal);
    return NULL;
  }
  return terminal;
}

uint8_t msstd_terminal_raw_mode(MsObj **out, MsString *err) {
  *err = ms_string_empty();
  if (!raw_mode_capable()) {
    return MS_STATUS_NOT_TERMINAL;
  }
  if (atomic_load(&active_terminal) != NULL) {
    return MS_STATUS_BUSY;
  }
  MsTerminal *terminal = terminal_open(err);
  if (terminal == NULL) {
    return MS_STATUS_FAILED;
  }
  MsTerminal *expected = NULL;
  if (!atomic_compare_exchange_strong(&active_terminal, &expected, terminal)) {
    terminal_close(terminal, true);
    ms_terminal_release(terminal);
    return MS_STATUS_BUSY;
  }
  if (!atomic_flag_test_and_set(&exit_hook_registered)) {
    msrt_process_on_exit(restore_at_exit);
  }
  *out = &handle_new(terminal)->header;
  return MS_STATUS_OK;
}

/* ---- handles ---- */

static MsTerminal *terminal_of(const MsObj *object) { return ((const MsTerminalHandle *)object)->terminal; }

MsObj *msstd_terminal_raw_terminal_share(const MsObj *handle) {
  MsTerminal *terminal = terminal_of(handle);
  ms_terminal_retain(terminal);
  return &handle_new(terminal)->header;
}

void msstd_terminal_raw_terminal_close(const MsObj *handle) { terminal_close(terminal_of(handle), true); }

void msstd_terminal_raw_terminal_set_restore(const MsObj *handle, const MsString *text) {
  MsTerminal *terminal = terminal_of(handle);
  ms_strbuild_clear(&terminal->restore);
  ms_strbuild_append(&terminal->restore, ms_string_span(text));
}

/* ---- size and writes ---- */

/* The size of the terminal, from its output and failing that its input. */
static bool terminal_size(MsTerminal *terminal, int *columns, int *rows) {
  return uv_tty_get_winsize(&terminal->output, columns, rows) == 0 ||
         uv_tty_get_winsize(&terminal->input, columns, rows) == 0;
}

/* A stop request ends a native that has no error to return by cancelling the task. */
static void cancel_if_requested(void) {
  if (ms_fail_cancel_requested()) {
    ms_cancelled();
  }
}

uint8_t msstd_terminal_raw_terminal_size_status(const MsObj *handle) {
  MsTerminal *terminal = terminal_of(handle);
  int columns = 0;
  int rows = 0;
  cancel_if_requested();
  if (atomic_load(&terminal->closed)) {
    return MS_STATUS_CLOSED;
  }
  return terminal_size(terminal, &columns, &rows) ? MS_STATUS_OK : MS_STATUS_NOT_TERMINAL;
}

int64_t msstd_terminal_raw_terminal_size_columns(const MsObj *handle) {
  int columns = 0;
  int rows = 0;
  MsTerminal *terminal = terminal_of(handle);
  return !atomic_load(&terminal->closed) && terminal_size(terminal, &columns, &rows) ? columns : 0;
}

int64_t msstd_terminal_raw_terminal_size_rows(const MsObj *handle) {
  int columns = 0;
  int rows = 0;
  MsTerminal *terminal = terminal_of(handle);
  return !atomic_load(&terminal->closed) && terminal_size(terminal, &columns, &rows) ? rows : 0;
}

uint8_t msstd_terminal_raw_terminal_write(const MsObj *handle, const MsString *text, MsString *err) {
  MsTerminal *terminal = terminal_of(handle);
  *err = ms_string_empty();
  cancel_if_requested();
  if (atomic_load(&terminal->closed)) {
    return MS_STATUS_CLOSED;
  }
  if (terminal_write(terminal, ms_string_span(text), true)) {
    return MS_STATUS_OK;
  }
  cancel_if_requested();
  *err = ms_string_from_span(ms_span_of_text("cannot write to the terminal"));
  return MS_STATUS_FAILED;
}

uint8_t msstd_terminal_raw_terminal_read(const MsObj *handle, uint8_t quick) {
  return ms_terminal_read(terminal_of(handle), quick != 0);
}

void msstd_terminal_input_text(MsString *out) {
  MsTerminal *terminal = ms_terminal_active();
  *out = terminal != NULL ? ms_string_from_span(ms_strbuild_span(&terminal->text)) : ms_string_empty();
}
