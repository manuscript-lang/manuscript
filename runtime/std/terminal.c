/* terminal.c: the raw terminal of @std/io. libuv's uv_tty does the terminal work on every platform: raw mode and its
 * restore, the window size, and writes that Windows consoles understand. Reading is one libuv loop per terminal that
 * runs on a pool thread for the length of one wait, so a task that waits for a key parks no scheduler thread. The
 * loop watches the terminal, SIGWINCH (a resize ends the wait with nothing read, and the caller compares sizes), a
 * 40 ms timer for the wait that resolves a lone escape byte, and an async handle another thread uses to end the wait
 * (close, or a stop request). Decoding keys and pastes from the text is Manuscript (stdlib/cli/terminal.ms).
 *
 * One raw terminal holds the host terminal at a time. Closing it (explicitly, by the last handle's drop, or at
 * process exit) writes the text the program registered (leaving the alternate screen and so on) and puts the saved
 * settings back. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c11 */
#ifdef __APPLE__
#define _DARWIN_C_SOURCE 1 /* <signal.h> hides SIGWINCH under a strict POSIX level */
#endif

#include <signal.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <uv.h>

#include "abi.h"
#include "fs_support.h"
#include "ms_rt/chars.h"
#include "ms_rt/safe.h"
#include "ms_rt/io.h"
#include "ms_rt/sys.h"
#include "ms_rt/terminal.h"
#include "ms_sched.h"

enum {
    INPUT_FD = 0,
    OUTPUT_FD = 1,
    ERROR_FD = 2,
    READ_CAPACITY = 4096,
    QUICK_WAIT_MS = 40,
    WRITE_RETRY_MS = 1,
    MAX_UTF8_WIDTH = 4,
    TRUE_COLOR = 16777216,
    COLOR_256 = 256,
    COLOR_16 = 16,
    ENV_CAPACITY = 256,
};

/* Which parts of a terminal were set up, so a failed open releases exactly those. */
enum {
    PART_LOOP = 1u << 0,
    PART_INPUT = 1u << 1,
    PART_OUTPUT = 1u << 2,
    PART_WAKE = 1u << 3,
    PART_RESIZE = 1u << 4,
    PART_RAW = 1u << 5,
};

/* A raw terminal shared by its handles and by the read waits that are running. */
typedef struct MsTerminal {
    _Atomic uint32_t references; /* handles and running reads; the last release destroys it */
    _Atomic uint32_t handles;    /* handles alone; the last one's drop closes the terminal */
    _Atomic bool closed;         /* set once, by close */
    _Atomic bool abandoned;      /* the running read job's caller gave up (timeout or cancel): it reads nothing more */
    uint32_t parts;              /* PART_* bits, set while opening and read while destroying */
    bool input_was_nonblocking;  /* the descriptors' modes before libuv reopened them, put back at destroy */
    bool output_was_nonblocking;
    uv_mutex_t read_lock; /* held by a read job from start to end: an abandoned job may still be ending when the next starts */
    uv_loop_t loop;     /* runs only inside a read wait, one at a time per terminal */
    uv_tty_t input;     /* on `loop` */
    uv_tty_t output;    /* writes only; used from the runtime thread */
    uv_async_t wake;    /* the one handle another thread may use: uv_async_send ends a wait */
    uv_signal_t resize; /* SIGWINCH, started for the life of the terminal so a resize between waits is kept */
    MsFsBuffer restore; /* owned; written at close; runtime thread only */
    MsFsBuffer text;    /* owned; the text the last read delivered; runtime thread only */
    uint8_t carry[MAX_UTF8_WIDTH];
    size_t carry_length; /* bytes of an incomplete scalar kept for the next read; runtime thread only */
} MsTerminal;

/* The handle a program holds: the header the runtime drops it through, then the shared terminal. */
typedef struct MsTerminalHandle {
    MsObj header; /* must be first */
    MsTerminal *terminal;
} MsTerminalHandle;

/* The raw terminal holding the host terminal, or null. The host has one terminal and the process-exit hook has no
 * argument, so this is process-wide; it is only read and written with atomic operations. */
static _Atomic(MsTerminal *) active_terminal = NULL;
static atomic_flag exit_hook_registered = ATOMIC_FLAG_INIT;

/* ---- the host terminal ---- */

static bool is_terminal(int fd) { return uv_guess_handle(fd) == UV_TTY; }

static bool raw_mode_capable(void) { return is_terminal(INPUT_FD) && is_terminal(OUTPUT_FD); }

uint8_t msstd_terminal_capabilities_input_is_terminal(void) { return is_terminal(INPUT_FD); }

uint8_t msstd_terminal_capabilities_output_is_terminal(void) { return is_terminal(OUTPUT_FD); }

uint8_t msstd_terminal_capabilities_error_is_terminal(void) { return is_terminal(ERROR_FD); }

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

/* Colors that standard output supports: 0, 16, 256 or 16777216. Windows 10 consoles take 24-bit color through
 * virtual-terminal sequences, so only a TERM that says 256 colors lowers it there. */
int64_t msstd_terminal_capabilities_colors(void) {
    char term[ENV_CAPACITY] = "";
    const bool has_term = env_text("TERM", term, sizeof term);
    if (!is_terminal(OUTPUT_FD) || env_is_set("NO_COLOR") || (has_term && strcmp(term, "dumb") == 0)) {
        return 0;
    }
    char color_term[ENV_CAPACITY] = "";
    const bool has_color_term = env_text("COLORTERM", color_term, sizeof color_term);
    const bool wide = strstr(term, "256color") != NULL;
#if defined(_WIN32)
    return !has_color_term && wide ? COLOR_256 : TRUE_COLOR;
#else
    if (strcmp(color_term, "truecolor") == 0 || strcmp(color_term, "24bit") == 0) {
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

/* The columns and rows of the terminal behind `fd` through a handle that lives for the call. libuv reopens the
 * terminal and makes the descriptor non-blocking, so the descriptor's mode is put back. False when `fd` has no
 * size. */
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
    if (!is_terminal(OUTPUT_FD)) {
        return STATUS_NOT_TERMINAL;
    }
    return probe_size(OUTPUT_FD, &columns, &rows) ? STATUS_OK : STATUS_UNSUPPORTED;
}

int64_t msstd_terminal_size_columns(void) {
    int columns = 0;
    int rows = 0;
    return probe_size(OUTPUT_FD, &columns, &rows) ? columns : 0;
}

int64_t msstd_terminal_size_rows(void) {
    int columns = 0;
    int rows = 0;
    return probe_size(OUTPUT_FD, &columns, &rows) ? rows : 0;
}

/* ---- the shared terminal ---- */

static void terminal_retain(MsTerminal *terminal) { atomic_fetch_add(&terminal->references, 1); }

/* Ends the terminal's libuv handles and runs the loop until they are gone. */
static void terminal_close(MsTerminal *terminal, bool can_park);

static void terminal_destroy(MsTerminal *terminal) {
    terminal_close(terminal, false);
    const uint32_t parts = terminal->parts;
    if ((parts & PART_RESIZE) != 0) {
        uv_signal_stop(&terminal->resize);
        uv_close((uv_handle_t *)&terminal->resize, NULL);
    }
    if ((parts & PART_WAKE) != 0) {
        uv_close((uv_handle_t *)&terminal->wake, NULL);
    }
    if ((parts & PART_INPUT) != 0) {
        uv_close((uv_handle_t *)&terminal->input, NULL);
    }
    if ((parts & PART_OUTPUT) != 0) {
        uv_close((uv_handle_t *)&terminal->output, NULL);
    }
    if ((parts & PART_LOOP) != 0) {
        (void)uv_run(&terminal->loop, UV_RUN_NOWAIT);
        (void)uv_loop_close(&terminal->loop);
    }
    /* libuv made the standard descriptors non-blocking when it reopened them; the program's own reads of them expect
     * the mode they had. */
    (void)ms_sys_fd_set_nonblocking(INPUT_FD, terminal->input_was_nonblocking);
    (void)ms_sys_fd_set_nonblocking(OUTPUT_FD, terminal->output_was_nonblocking);
    ms_fs_buffer_free(&terminal->restore);
    ms_fs_buffer_free(&terminal->text);
    uv_mutex_destroy(&terminal->read_lock);
    free(terminal);
}

static void terminal_release(MsTerminal *terminal) {
    if (atomic_fetch_sub(&terminal->references, 1) == 1) {
        terminal_destroy(terminal);
    }
}

/* Waits a moment for a full terminal to drain; `can_park` lets the task park meanwhile (false at process exit, where
 * no task runs). False when a stop request ended the wait. */
static bool wait_to_retry(bool can_park) {
    if (!can_park) {
        uv_sleep(WRITE_RETRY_MS);
        return true;
    }
    return (msrt_task_sleep((int64_t)WRITE_RETRY_MS * 1000000) & MS_WAIT_CANCELLED) == 0;
}

/* Writes all of `data` (libuv takes a mutable buffer, so the caller's copy) to the terminal. A full terminal is
 * retried every millisecond. False when the write failed or a stop request ended it. */
static bool write_buffer(MsTerminal *terminal, MsFsBuffer *data, bool can_park) {
    size_t written = 0;
    while (written < data->length) {
        uv_buf_t buffer = uv_buf_init((char *)data->data + written, (unsigned int)(data->length - written));
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

/* Writes all of `bytes` to the terminal after the output the program buffered earlier. */
static bool terminal_write(MsTerminal *terminal, MsBytes bytes, bool can_park) {
    if ((terminal->parts & PART_OUTPUT) == 0) {
        return false;
    }
    ms_sched_flush_stdout();
    MsFsBuffer data = {0};
    const bool copied = ms_fs_buffer_append(&data, bytes.ptr, bytes.len);
    const bool written = copied && write_buffer(terminal, &data, can_park);
    ms_fs_buffer_free(&data);
    return written;
}

/* Writes the restore text and the saved settings once; closing again does nothing. Safe from any thread but a read
 * wait's own: the wake handle ends a wait that is running. */
static void terminal_close(MsTerminal *terminal, bool can_park) {
    if (atomic_exchange(&terminal->closed, true)) {
        return;
    }
    if ((terminal->parts & PART_WAKE) != 0) {
        (void)uv_async_send(&terminal->wake);
    }
    /* Nothing useful to report if the terminal vanished already. */
    (void)terminal_write(terminal, ms_fs_buffer_view(&terminal->restore), can_park);
    if ((terminal->parts & PART_RAW) != 0) {
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

static void stop_loop(uv_handle_t *handle) { uv_stop(handle->loop); }

static void on_wake(uv_async_t *handle) { stop_loop((uv_handle_t *)handle); }

static void on_resize(uv_signal_t *handle, int signal) {
    (void)signal;
    stop_loop((uv_handle_t *)handle);
}

/* Sets up the terminal's loop and handles, recording each part in `parts`. */
static int terminal_setup(MsTerminal *terminal) {
    int code = uv_loop_init(&terminal->loop);
    if (code < 0) {
        return code;
    }
    terminal->parts |= PART_LOOP;
    code = uv_tty_init(&terminal->loop, &terminal->input, INPUT_FD, 1);
    if (code < 0) {
        return code;
    }
    terminal->parts |= PART_INPUT;
    code = uv_tty_init(&terminal->loop, &terminal->output, OUTPUT_FD, 0);
    if (code < 0) {
        return code;
    }
    terminal->parts |= PART_OUTPUT;
    code = uv_async_init(&terminal->loop, &terminal->wake, on_wake);
    if (code < 0) {
        return code;
    }
    terminal->parts |= PART_WAKE;
    code = uv_signal_init(&terminal->loop, &terminal->resize);
    if (code < 0) {
        return code;
    }
    terminal->parts |= PART_RESIZE;
    code = uv_signal_start(&terminal->resize, on_resize, SIGWINCH);
    if (code < 0) {
        return code;
    }
    code = uv_tty_set_mode(&terminal->input, UV_TTY_MODE_RAW);
    if (code >= 0) {
        terminal->parts |= PART_RAW;
    }
    return code;
}

static MsTerminalHandle *handle_new(MsTerminal *terminal);

/* A new terminal in raw mode, with one reference for the caller, or null with `err` set. */
static MsTerminal *terminal_open(MsStr *err) {
    MsTerminal *terminal = calloc(1, sizeof *terminal);
    if (terminal == NULL) {
        msrt_string_from_bytes((const uint8_t *)"out of memory", 13, err);
        return NULL;
    }
    atomic_init(&terminal->references, 1);
    atomic_init(&terminal->handles, 0);
    atomic_init(&terminal->closed, false);
    if (uv_mutex_init(&terminal->read_lock) < 0) {
        msrt_string_from_bytes((const uint8_t *)"out of memory", 13, err);
        free(terminal);
        return NULL;
    }
    terminal->input_was_nonblocking = is_nonblocking(INPUT_FD);
    terminal->output_was_nonblocking = is_nonblocking(OUTPUT_FD);
    if (terminal_setup(terminal) < 0) {
        msrt_string_from_bytes((const uint8_t *)"cannot enter raw mode", 21, err);
        terminal_destroy(terminal);
        return NULL;
    }
    return terminal;
}

uint8_t msstd_terminal_raw_mode(MsObj **out, MsStr *err) {
    msrt_string_empty(err);
    if (!raw_mode_capable()) {
        return STATUS_NOT_TERMINAL;
    }
    if (atomic_load(&active_terminal) != NULL) {
        return STATUS_BUSY;
    }
    MsTerminal *terminal = terminal_open(err);
    if (terminal == NULL) {
        return STATUS_FAILED;
    }
    MsTerminal *expected = NULL;
    if (!atomic_compare_exchange_strong(&active_terminal, &expected, terminal)) {
        terminal_close(terminal, true);
        terminal_release(terminal);
        return STATUS_BUSY;
    }
    if (!atomic_flag_test_and_set(&exit_hook_registered)) {
        msrt_process_on_exit(restore_at_exit);
    }
    *out = &handle_new(terminal)->header;
    return STATUS_OK;
}

/* ---- handles ---- */

static void handle_drop(MsObj *object) {
    MsTerminalHandle *handle = (MsTerminalHandle *)object;
    MsTerminal *terminal = handle->terminal;
    msrt_free(handle);
    /* The last handle's drop closes the terminal; a read still running holds its own reference. */
    if (atomic_fetch_sub(&terminal->handles, 1) == 1) {
        terminal_close(terminal, true);
    }
    terminal_release(terminal);
}

/* A handle that owns one reference of `terminal`. */
static MsTerminalHandle *handle_new(MsTerminal *terminal) {
    MsTerminalHandle *handle = msrt_alloc_zeroed(sizeof *handle);
    atomic_fetch_add(&terminal->handles, 1);
    handle->header.drop = handle_drop;
    handle->terminal = terminal;
    return handle;
}

static MsTerminal *terminal_of(const MsObj *object) { return ((const MsTerminalHandle *)object)->terminal; }

MsObj *msstd_terminal_raw_terminal_share(const MsObj *handle) {
    MsTerminal *terminal = terminal_of(handle);
    terminal_retain(terminal);
    return &handle_new(terminal)->header;
}

void msstd_terminal_raw_terminal_close(const MsObj *handle) { terminal_close(terminal_of(handle), true); }

void msstd_terminal_raw_terminal_set_restore(const MsObj *handle, const MsStr *text) {
    MsTerminal *terminal = terminal_of(handle);
    terminal->restore.length = 0;
    if (!ms_fs_buffer_append(&terminal->restore, ms_str_data(text), ms_str_len(text))) {
        terminal->restore.length = 0; /* out of memory: close restores the settings without the text */
    }
}

/* ---- size and writes ---- */

/* The size of the terminal, from its output and failing that its input. */
static bool terminal_size(MsTerminal *terminal, int *columns, int *rows) {
    return uv_tty_get_winsize(&terminal->output, columns, rows) == 0 ||
           uv_tty_get_winsize(&terminal->input, columns, rows) == 0;
}

uint8_t msstd_terminal_raw_terminal_size_status(const MsObj *handle) {
    MsTerminal *terminal = terminal_of(handle);
    int columns = 0;
    int rows = 0;
    if (ms_sched_cancel_pending()) {
        return STATUS_OK;
    }
    if (atomic_load(&terminal->closed)) {
        return STATUS_CLOSED;
    }
    return terminal_size(terminal, &columns, &rows) ? STATUS_OK : STATUS_NOT_TERMINAL;
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

uint8_t msstd_terminal_raw_terminal_write(const MsObj *handle, const MsStr *text, MsStr *err) {
    MsTerminal *terminal = terminal_of(handle);
    msrt_string_empty(err);
    if (ms_sched_cancel_pending()) {
        return STATUS_OK;
    }
    if (atomic_load(&terminal->closed)) {
        return STATUS_CLOSED;
    }
    if (terminal_write(terminal, ms_bytes_of(ms_str_data(text), ms_str_len(text)), true)) {
        return STATUS_OK;
    }
    const char *reason = ms_sched_cancel_pending() ? "cancelled" : "cannot write to the terminal";
    msrt_string_from_bytes((const uint8_t *)reason, strlen(reason), err);
    return STATUS_FAILED;
}

/* ---- reading ---- */

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

/* The pool job: loops the terminal's loop until a key arrives, the input ends, a resize or a wake-up comes, or the
 * quick timer runs out. */
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
    terminal_release(wait->terminal);
    free(wait);
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
static size_t incomplete_tail(const uint8_t *bytes, size_t length) {
    const size_t limit = length < MAX_UTF8_WIDTH - 1 ? length : MAX_UTF8_WIDTH - 1;
    for (size_t back = 1; back <= limit; back++) {
        const uint8_t byte = bytes[length - back];
        if (ms_utf8_is_continuation(byte)) {
            continue;
        }
        return scalar_width(byte) > back ? back : 0;
    }
    return 0;
}

/* Turns the carried bytes and `bytes` into the terminal's text: complete scalars only, invalid bytes as U+FFFD, an
 * incomplete trailing scalar kept for the next read. */
static void decode_input(MsTerminal *terminal, const uint8_t *bytes, size_t length) {
    MsFsBuffer joined = {0};
    terminal->text.length = 0;
    if (ms_fs_buffer_append(&joined, terminal->carry, terminal->carry_length) &&
        ms_fs_buffer_append(&joined, bytes, length)) {
        const size_t tail = incomplete_tail(joined.data, joined.length);
        const size_t complete = joined.length - tail;
        if (!ms_fs_buffer_append_lossy(&terminal->text, joined.data, complete)) {
            terminal->text.length = 0; /* out of memory: the read delivers nothing */
        }
        memcpy(terminal->carry, joined.data + complete, tail);
        terminal->carry_length = tail;
    }
    ms_fs_buffer_free(&joined);
}

/* The status a finished wait reports and, for STATUS_OK, the text it delivered. */
static uint8_t wait_status(MsTerminal *terminal, const ReadWait *wait) {
    if (wait->length == 0) {
        if (wait->ended || atomic_load(&terminal->closed)) {
            return STATUS_CLOSED;
        }
        /* A bounded read whose time is up returns its parks at once, so "nothing came" would make the caller retry
         * without end. */
        return ms_sched_read_limit_passed() ? STATUS_TIMED_OUT : STATUS_NONE;
    }
    decode_input(terminal, wait->bytes, wait->length);
    return terminal->text.length == 0 ? STATUS_NONE : STATUS_OK;
}

/* Waits on the pool for input. A stop request wakes the wait and ends the call by return. */
uint8_t msstd_terminal_raw_terminal_read(const MsObj *handle, uint8_t quick) {
    MsTerminal *terminal = terminal_of(handle);
    if (ms_sched_cancel_pending()) {
        return STATUS_OK;
    }
    if (atomic_load(&terminal->closed)) {
        return STATUS_CLOSED;
    }
    ReadWait *wait = calloc(1, sizeof *wait);
    if (wait == NULL) {
        return STATUS_CLOSED;
    }
    terminal_retain(terminal);
    wait->terminal = terminal;
    wait->quick = quick != 0;
    const MsSchedWait outcome = ms_sched_pool_run(read_run, read_release, wait, -1);
    if (outcome != MS_SCHED_DONE) {
        /* The pool owns the wait now and ends it when the wake-up reaches it; the handle keeps the terminal alive. A
         * bounded read (`next(timeout:)`) whose time is up ends here too, as a timeout. */
        atomic_store(&terminal->abandoned, true);
        (void)uv_async_send(&terminal->wake);
        if (outcome == MS_SCHED_TIMED_OUT) {
            return STATUS_TIMED_OUT;
        }
        ms_sched_cancel_return();
        return STATUS_OK;
    }
    const uint8_t status = wait_status(terminal, wait);
    read_release(wait);
    if (ms_sched_cancel_pending()) {
        ms_sched_cancel_return();
        return STATUS_OK;
    }
    return status;
}

void msstd_terminal_input_text(const MsObj *handle, MsStr *out) {
    const MsTerminal *terminal = terminal_of(handle);
    msrt_string_from_bytes(terminal->text.length > 0 ? terminal->text.data : (const uint8_t *)"", terminal->text.length,
                           out);
}
