/* The Windows half of the reactor: what libuv's loop does not cover for the scheduler.
 *
 * Sockets are libuv poll handles, as everywhere (../reactor.c). Three more things reach the scheduler here:
 *   - Overlapped named pipes (the standard streams of child processes), as libuv pipe handles with a read
 *     buffer and a write buffer each. A read or write that cannot finish reports "would block" and the
 *     completion queues an event, so a task parks until the pipe is ready.
 *   - Waitable kernel objects (a child process). The thread pool waits for them and tells the loop through an
 *     async handle; no thread of ours blocks.
 *   - A high-resolution timer. The loop sleeps in whole system ticks (about 15 ms), so a deadline arms a
 *     waitable timer whose signal wakes the loop at the finest resolution the system has.
 *
 * Events use the keys the scheduler already waits on: a pipe's readers wait on its handle, its writers on the
 * handle plus one (handles are multiples of four), and a grouped pipe wakes the one task parked on its group key.
 * Compiled by the Windows legs only; the PR checks are Linux.
 */
#include <io.h>
#include <string.h>
#include <uv.h>
#include <windows.h>

#include "../reactor_internal.h"
#include "ms_rt/sys.h"

enum {
    PIPE_BUFFER_BYTES = 64 * 1024,
    PIPE_WRITER_KEY_OFFSET = 1,
    SPIN_BELOW_NANOSECONDS = 1000000, /* the timer's own latency would overshoot a shorter wait */
    NANOSECONDS_PER_TICK = 100,       /* the unit of a waitable timer's due time */
    FILE_MODE_INFORMATION_CLASS = 16,
    FILE_SYNCHRONOUS_MODES = 0x30, /* FILE_SYNCHRONOUS_IO_ALERT | FILE_SYNCHRONOUS_IO_NONALERT: not overlapped */
    ERROR_IO_DEVICE_CODE = 1117,
    ERROR_BROKEN_PIPE_CODE = 109,
    FIRST_TABLE_LENGTH = 8,
};

typedef struct MsWindowsState MsWindowsState;

/* An adopted pipe. The libuv handle is first so a handle pointer is the pipe. */
typedef struct MsPipe {
    uv_pipe_t handle;
    struct MsPipe *next;   /* owned by the list in MsWindowsState */
    uv_write_t write_request;
    MsWindowsState *state; /* borrowed from the reactor, valid while the pipe is open */
    uintptr_t key;         /* the OS handle: what tasks wait on */
    uintptr_t group_key;   /* the key to wake instead of the pipe's own, when grouped */
    bool grouped;
    uint8_t *read_buffer;  /* owned */
    size_t read_length;    /* bytes the last read left in the buffer */
    size_t read_offset;    /* how many the scheduler has taken */
    bool reading;          /* a libuv read is running */
    bool end_of_stream;
    int read_status;       /* a negative libuv status, 0 when none */
    uint8_t *write_buffer; /* owned */
    bool writing;          /* a libuv write is in flight */
    int write_status;
    bool owes_read_event;  /* an event could not be queued */
    bool owes_write_event;
    bool closing;
} MsPipe;

/* A watched kernel object. Its address is the context of the thread-pool wait, so it must not move. */
typedef struct MsObject {
    struct MsObject *next; /* owned by the list in MsWindowsState */
    uintptr_t key;
    HANDLE wait; /* NULL when the object was removed */
    MsWindowsState *state;
} MsObject;

struct MsWindowsState {
    MsIoReactor *reactor;
    uv_async_t signalled_async; /* thread-pool waits tell the loop here */
    bool async_open;
    CRITICAL_SECTION lock;      /* guards `signalled` and `signalled_length` */
    uintptr_t *signalled;       /* owned; objects that fired and are not yet queued */
    size_t signalled_length;
    size_t signalled_capacity;
    MsObject *objects;          /* owned; every watched object */
    MsPipe *pipes;              /* owned until its close callback; every open pipe */
    HANDLE timer;               /* the high-resolution timer, NULL when the system has none */
    HANDLE timer_wait;
};

static MsWindowsState *state_of(const MsIoReactor *reactor) {
    return ms_io_reactor_platform(reactor);
}

/* ---- the high-resolution timer ---- */

static VOID CALLBACK on_timer_signal(PVOID context, BOOLEAN timed_out) {
    (void)timed_out;
    (void)uv_async_send(context);
}

static void timer_open(MsWindowsState *state) {
    enum { CREATE_WAITABLE_TIMER_HIGH_RESOLUTION_FLAG = 0x2, TIMER_ALL_ACCESS_RIGHTS = 0x1F0003 };
    state->timer = CreateWaitableTimerExW(NULL, NULL, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION_FLAG, TIMER_ALL_ACCESS_RIGHTS);
    if (state->timer == NULL) {
        return; /* before Windows 10 1803: the caller falls back to a millisecond timer */
    }
    uv_async_t *const wake = ms_io_reactor_wake_handle(state->reactor);
    if (!RegisterWaitForSingleObject(&state->timer_wait, state->timer, on_timer_signal, wake, INFINITE, WT_EXECUTEDEFAULT)) {
        (void)CloseHandle(state->timer);
        state->timer = NULL;
    }
}

static void timer_close(MsWindowsState *state) {
    if (state->timer == NULL) {
        return;
    }
    (void)UnregisterWaitEx(state->timer_wait, INVALID_HANDLE_VALUE); /* returns after a running callback */
    (void)CloseHandle(state->timer);
    state->timer = NULL;
}

static void timer_arm(const MsWindowsState *state, int64_t nanoseconds) {
    LARGE_INTEGER due;
    const int64_t ticks = nanoseconds / NANOSECONDS_PER_TICK;
    due.QuadPart = -(ticks > 0 ? ticks : 1); /* a negative due time is relative */
    (void)SetWaitableTimer(state->timer, &due, 0, NULL, NULL, FALSE);
}

static int64_t now_nanoseconds(void) {
    return (int64_t)uv_hrtime();
}

bool ms_io_windows_wait(MsIoReactor *reactor, int64_t timeout_ns) {
    MsWindowsState *const state = state_of(reactor);
    uv_loop_t *const loop = ms_io_reactor_loop(reactor);
    if (timeout_ns < SPIN_BELOW_NANOSECONDS) {
        const int64_t deadline = now_nanoseconds() + timeout_ns;
        while (!ms_io_reactor_pending(reactor) && now_nanoseconds() < deadline) {
            (void)uv_run(loop, UV_RUN_NOWAIT);
        }
        return true;
    }
    if (state->timer == NULL) {
        return false;
    }
    timer_arm(state, timeout_ns);
    (void)uv_run(loop, UV_RUN_ONCE);
    (void)CancelWaitableTimer(state->timer); /* a wake for another reason must not leave a stale signal */
    return true;
}

/* ---- tables of pipes and objects ---- */

static MsPipe *pipe_find(const MsWindowsState *state, uintptr_t key) {
    for (MsPipe *pipe = state->pipes; pipe != NULL; pipe = pipe->next) {
        if (pipe->key == key) {
            return pipe;
        }
    }
    return NULL;
}

static MsObject *object_find(const MsWindowsState *state, uintptr_t key) {
    for (MsObject *object = state->objects; object != NULL; object = object->next) {
        if (object->key == key) {
            return object;
        }
    }
    return NULL;
}

bool ms_io_windows_owns(const MsIoReactor *reactor, uintptr_t fd) {
    const MsWindowsState *const state = state_of(reactor);
    return pipe_find(state, fd & ~(uintptr_t)3) != NULL || object_find(state, fd) != NULL;
}

/* ---- objects ---- */

/* Queues an event for each object that fired; the ones that do not fit stay for the next flush. */
static void signalled_flush(MsWindowsState *state) {
    EnterCriticalSection(&state->lock);
    size_t kept = 0;
    for (size_t index = 0; index < state->signalled_length; index++) {
        const MsIoEvent event = {.id = state->signalled[index], .result = 0, .kind = MS_IO_READ};
        if (!ms_io_reactor_push(state->reactor, event)) {
            state->signalled[kept] = state->signalled[index];
            kept++;
        }
    }
    state->signalled_length = kept;
    LeaveCriticalSection(&state->lock);
}

static void on_signalled_async(uv_async_t *handle) {
    signalled_flush(uv_handle_get_data((uv_handle_t *)handle));
}

/* Runs on a thread-pool thread when a watched object is signalled. */
static VOID CALLBACK on_object_signalled(PVOID context, BOOLEAN timed_out) {
    (void)timed_out;
    const MsObject *const object = context;
    MsWindowsState *const state = object->state;
    EnterCriticalSection(&state->lock);
    bool queued = false;
    if (state->signalled_length < state->signalled_capacity) {
        queued = true;
    } else {
        size_t capacity = 0;
        size_t bytes = 0;
        if (ms_size_mul(state->signalled_capacity == 0 ? FIRST_TABLE_LENGTH : state->signalled_capacity, 2, &capacity) &&
            ms_size_mul(capacity, sizeof(uintptr_t), &bytes)) {
            uintptr_t *const grown = ms_sys_realloc(state->signalled, bytes);
            if (grown != NULL) {
                state->signalled = grown;
                state->signalled_capacity = capacity;
                queued = true;
            }
        }
    }
    if (queued) {
        state->signalled[state->signalled_length] = object->key;
        state->signalled_length++;
    }
    LeaveCriticalSection(&state->lock);
    (void)uv_async_send(&state->signalled_async);
}

bool ms_io_object_watch(uintptr_t handle) {
    MsIoReactor *const reactor = ms_io_reactor_current();
    if (reactor == NULL) {
        return false;
    }
    MsWindowsState *const state = state_of(reactor);
    if (object_find(state, handle) != NULL) {
        return true;
    }
    MsObject *const object = ms_sys_malloc(sizeof *object);
    if (object == NULL) {
        return false;
    }
    *object = (MsObject){.key = handle, .state = state};
    /* WT_EXECUTEONLYONCE: the wait ends with the first signal; the scheduler watches again if it needs to. */
    if (!RegisterWaitForSingleObject(&object->wait, (HANDLE)handle, on_object_signalled, object, INFINITE, WT_EXECUTEONLYONCE)) {
        ms_sys_free(object);
        return false;
    }
    object->next = state->objects;
    state->objects = object;
    return true;
}

/* Ends the wait on the object `key`: returns after a running callback, so the context is free to release. */
static void object_remove(MsWindowsState *state, uintptr_t key) {
    MsObject **link = &state->objects;
    while (*link != NULL && (*link)->key != key) {
        link = &(*link)->next;
    }
    MsObject *const object = *link;
    if (object == NULL) {
        return;
    }
    *link = object->next;
    (void)UnregisterWaitEx(object->wait, INVALID_HANDLE_VALUE);
    EnterCriticalSection(&state->lock);
    size_t kept = 0;
    for (size_t index = 0; index < state->signalled_length; index++) {
        if (state->signalled[index] != key) {
            state->signalled[kept] = state->signalled[index];
            kept++;
        }
    }
    state->signalled_length = kept;
    LeaveCriticalSection(&state->lock);
    ms_sys_free(object);
}

void ms_io_object_drop(uintptr_t handle) {
    MsIoReactor *const reactor = ms_io_reactor_current();
    if (reactor != NULL) {
        object_remove(state_of(reactor), handle);
    }
}

/* ---- pipes ---- */

/* The key a pipe event wakes: its group's, or the handle (readers) or handle plus one (writers). */
static uintptr_t pipe_event_key(const MsPipe *pipe, bool writer) {
    if (pipe->grouped) {
        return pipe->group_key;
    }
    return writer ? pipe->key + PIPE_WRITER_KEY_OFFSET : pipe->key;
}

static bool pipe_push(const MsPipe *pipe, bool writer) {
    const MsIoEvent event = {.id = pipe_event_key(pipe, writer), .result = 0, .kind = writer ? MS_IO_WRITE : MS_IO_READ};
    return ms_io_reactor_push(pipe->state->reactor, event);
}

static void pipe_notify(MsPipe *pipe, bool writer) {
    if (!pipe_push(pipe, writer)) {
        if (writer) {
            pipe->owes_write_event = true;
        } else {
            pipe->owes_read_event = true;
        }
    }
}

static void on_pipe_alloc(uv_handle_t *handle, size_t suggested, uv_buf_t *buffer) {
    (void)suggested;
    MsPipe *const pipe = (MsPipe *)handle;
    *buffer = uv_buf_init((char *)pipe->read_buffer, PIPE_BUFFER_BYTES);
}

static void on_pipe_read(uv_stream_t *stream, ssize_t count, const uv_buf_t *buffer) {
    (void)buffer;
    MsPipe *const pipe = (MsPipe *)stream;
    if (count == 0) {
        return; /* libuv's "nothing now" */
    }
    (void)uv_read_stop(stream);
    pipe->reading = false;
    if (count > 0) {
        pipe->read_length = (size_t)count;
        pipe->read_offset = 0;
    } else if (count == UV_EOF || count == UV_EPIPE || count == UV_ECONNRESET) {
        pipe->end_of_stream = true;
    } else {
        pipe->read_status = (int)count;
    }
    pipe_notify(pipe, false);
}

static void on_pipe_write(uv_write_t *request, int status) {
    MsPipe *const pipe = request->data;
    pipe->writing = false;
    pipe->write_status = status < 0 ? status : 0;
    if (!pipe->closing) {
        pipe_notify(pipe, true);
    }
}

static void on_pipe_closed(uv_handle_t *handle) {
    MsPipe *const pipe = (MsPipe *)handle;
    ms_sys_free(pipe->read_buffer);
    ms_sys_free(pipe->write_buffer);
    ms_sys_free(pipe);
}

/* Takes `pipe` off the list and ends its handle; libuv finishes the close (and cancels a pending read or write)
 * while the loop runs, then the callback frees it. */
static void pipe_close(MsPipe *pipe) {
    MsPipe **link = &pipe->state->pipes;
    while (*link != NULL && *link != pipe) {
        link = &(*link)->next;
    }
    if (*link == pipe) {
        *link = pipe->next;
    }
    pipe->closing = true;
    uv_close((uv_handle_t *)&pipe->handle, on_pipe_closed);
}

/* Whether `handle` was opened for overlapped I/O, which libuv's pipes need to be asynchronous. A handle opened
 * without it works, but through a helper thread per call; the scheduler wants the real thing. */
static bool is_overlapped(HANDLE handle) {
    typedef struct {
        union {
            LONG status;
            PVOID pointer;
        };
        ULONG_PTR information;
    } StatusBlock;
    typedef LONG(NTAPI * QueryFile)(HANDLE, StatusBlock *, PVOID, ULONG, ULONG);
    const HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
    const FARPROC found = ntdll == NULL ? NULL : GetProcAddress(ntdll, "NtQueryInformationFile");
    if (found == NULL) {
        return true;
    }
    QueryFile query = NULL;
    memcpy(&query, &found, sizeof query);
    StatusBlock block = {0};
    ULONG mode = 0;
    if (query(handle, &block, &mode, sizeof mode, FILE_MODE_INFORMATION_CLASS) < 0) {
        return false;
    }
    return (mode & FILE_SYNCHRONOUS_MODES) == 0;
}

bool ms_io_pipe_adopt(uintptr_t handle) {
    MsIoReactor *const reactor = ms_io_reactor_current();
    if (reactor == NULL || !is_overlapped((HANDLE)handle)) {
        return false;
    }
    MsWindowsState *const state = state_of(reactor);
    MsPipe *const pipe = ms_sys_malloc(sizeof *pipe);
    if (pipe == NULL) {
        return false;
    }
    *pipe = (MsPipe){.state = state, .key = handle};
    pipe->read_buffer = ms_sys_malloc(PIPE_BUFFER_BYTES);
    pipe->write_buffer = ms_sys_malloc(PIPE_BUFFER_BYTES);
    if (pipe->read_buffer == NULL || pipe->write_buffer == NULL ||
        uv_pipe_init(ms_io_reactor_loop(reactor), &pipe->handle, 0) != 0) {
        ms_sys_free(pipe->read_buffer);
        ms_sys_free(pipe->write_buffer);
        ms_sys_free(pipe);
        return false;
    }
    /* libuv takes a C runtime descriptor; it owns the handle from here and closes it with the pipe. */
    const int descriptor = _open_osfhandle((intptr_t)handle, 0);
    if (descriptor < 0 || uv_pipe_open(&pipe->handle, descriptor) != 0) {
        pipe->closing = true;
        uv_close((uv_handle_t *)&pipe->handle, on_pipe_closed);
        return false;
    }
    pipe->write_request.data = pipe;
    pipe->next = state->pipes;
    state->pipes = pipe;
    return true;
}

bool ms_io_pipe_adopted(uintptr_t handle) {
    MsIoReactor *const reactor = ms_io_reactor_current();
    return reactor != NULL && pipe_find(state_of(reactor), handle) != NULL;
}

/* Starts the read that will fill the buffer. */
static void pipe_read_start(MsPipe *pipe) {
    if (pipe->reading || pipe->end_of_stream || pipe->read_status != 0) {
        return;
    }
    const int error = uv_read_start((uv_stream_t *)&pipe->handle, on_pipe_alloc, on_pipe_read);
    if (error != 0) {
        pipe->read_status = error;
        pipe_notify(pipe, false);
        return;
    }
    pipe->reading = true;
}

/* The OS error code the scheduler reports for a libuv status. */
static int32_t os_code_of(int status) {
    return status == UV_EPIPE ? ERROR_BROKEN_PIPE_CODE : ERROR_IO_DEVICE_CODE;
}

MsIoPipeStatus ms_io_pipe_read(uintptr_t handle, MsBytesMut buffer, size_t *count, int32_t *os_code) {
    MsIoReactor *const reactor = ms_io_reactor_current();
    MsPipe *const pipe = reactor == NULL ? NULL : pipe_find(state_of(reactor), handle);
    if (pipe == NULL) {
        return MS_IO_PIPE_NOT_FOUND;
    }
    const size_t available = pipe->read_length - pipe->read_offset;
    if (available > 0) {
        const size_t taken = available < buffer.len ? available : buffer.len;
        memcpy(buffer.ptr, pipe->read_buffer + pipe->read_offset, taken);
        pipe->read_offset += taken;
        if (pipe->read_offset == pipe->read_length) {
            pipe->read_length = 0;
            pipe->read_offset = 0;
        }
        *count = taken;
        return MS_IO_PIPE_OK;
    }
    if (pipe->end_of_stream) {
        return MS_IO_PIPE_END;
    }
    if (pipe->read_status != 0) {
        *os_code = os_code_of(pipe->read_status);
        return MS_IO_PIPE_FAILED;
    }
    pipe_read_start(pipe);
    return MS_IO_PIPE_WOULD_BLOCK;
}

MsIoPipeStatus ms_io_pipe_write(uintptr_t handle, MsBytes data, size_t *count, int32_t *os_code) {
    MsIoReactor *const reactor = ms_io_reactor_current();
    MsPipe *const pipe = reactor == NULL ? NULL : pipe_find(state_of(reactor), handle);
    if (pipe == NULL) {
        return MS_IO_PIPE_NOT_FOUND;
    }
    if (pipe->write_status != 0) {
        *os_code = os_code_of(pipe->write_status);
        return MS_IO_PIPE_FAILED;
    }
    if (pipe->writing) {
        return MS_IO_PIPE_WOULD_BLOCK;
    }
    const size_t taken = data.len < PIPE_BUFFER_BYTES ? data.len : PIPE_BUFFER_BYTES;
    memcpy(pipe->write_buffer, data.ptr, taken);
    uv_buf_t buffer = uv_buf_init((char *)pipe->write_buffer, (unsigned int)taken);
    const int error = uv_write(&pipe->write_request, (uv_stream_t *)&pipe->handle, &buffer, 1, on_pipe_write);
    if (error != 0) {
        *os_code = os_code_of(error);
        return MS_IO_PIPE_FAILED;
    }
    pipe->writing = true;
    *count = taken;
    return MS_IO_PIPE_OK;
}

void ms_io_pipe_group(uintptr_t handle, uintptr_t key) {
    MsIoReactor *const reactor = ms_io_reactor_current();
    MsPipe *const pipe = reactor == NULL ? NULL : pipe_find(state_of(reactor), handle);
    if (pipe != NULL) {
        pipe->grouped = true;
        pipe->group_key = key;
    }
}

void ms_io_pipe_drop(uintptr_t handle) {
    MsIoReactor *const reactor = ms_io_reactor_current();
    MsPipe *const pipe = reactor == NULL ? NULL : pipe_find(state_of(reactor), handle);
    if (pipe != NULL) {
        pipe_close(pipe);
    }
}

/* ---- the reactor's hooks ---- */

void ms_io_windows_flush(MsIoReactor *reactor) {
    MsWindowsState *const state = state_of(reactor);
    signalled_flush(state);
    for (MsPipe *pipe = state->pipes; pipe != NULL; pipe = pipe->next) {
        if (pipe->owes_read_event && pipe_push(pipe, false)) {
            pipe->owes_read_event = false;
        }
        if (pipe->owes_write_event && pipe_push(pipe, true)) {
            pipe->owes_write_event = false;
        }
    }
}

bool ms_io_windows_open(MsIoReactor *reactor) {
    MsWindowsState *const state = ms_sys_malloc(sizeof *state);
    if (state == NULL) {
        return false;
    }
    *state = (MsWindowsState){.reactor = reactor};
    InitializeCriticalSection(&state->lock);
    ms_io_reactor_set_platform(reactor, state);
    if (uv_async_init(ms_io_reactor_loop(reactor), &state->signalled_async, on_signalled_async) != 0) {
        return false; /* the reactor's own destroy ends the state through ms_io_windows_close */
    }
    state->async_open = true;
    uv_handle_set_data((uv_handle_t *)&state->signalled_async, state);
    timer_open(state);
    return true;
}

/* Releases the state once libuv no longer touches its async handle. */
static void state_release(MsWindowsState *state) {
    DeleteCriticalSection(&state->lock);
    ms_sys_free(state->signalled);
    ms_sys_free(state);
}

static void on_state_closed(uv_handle_t *handle) {
    state_release(uv_handle_get_data(handle));
}

void ms_io_windows_close(MsIoReactor *reactor) {
    MsWindowsState *const state = state_of(reactor);
    if (state == NULL) {
        return;
    }
    ms_io_reactor_set_platform(reactor, NULL);
    timer_close(state);
    while (state->objects != NULL) {
        object_remove(state, state->objects->key);
    }
    while (state->pipes != NULL) {
        pipe_close(state->pipes);
    }
    if (state->async_open) {
        uv_close((uv_handle_t *)&state->signalled_async, on_state_closed);
    } else {
        state_release(state);
    }
}
