/* process_spawn.c: the child-process natives of @std/process: `run`, `spawn` with its Subprocess handle, and `replace`.
 *
 * A child runs on libuv: uv_spawn starts it, and a loop of its own on a thread of its own (the design of fs_watch.c)
 * reaps it, reads and writes its pipes, and keeps the deadlines. The loop thread never calls the runtime; it records
 * state under the child's lock and posts the token the waiting task parks on. Each child leads its own process
 * group (UV_PROCESS_DETACHED: a new session on Unix) or job object (Windows), so a kill reaches its whole tree.
 *
 * `run` hands its pipes to the loop: the loop writes the input, reads both outputs up to the limit, and ends the
 * command when the child has exited and its pipes are closed, the deadline passes, the limit is crossed, or the
 * output stays open a second after the exit. `spawn` makes plain descriptors for the piped streams instead, which
 * the program reads and writes through the runtime's stream table (`stream_id`).
 *
 * libuv reports no resource usage of a reaped child, so the peak resident set size is the largest sample taken
 * while it ran (/proc on Linux, the process handle on Windows); samples, not wait4's rusage (workaround, see #4780).
 */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c11 */
#ifdef __APPLE__
#define _DARWIN_C_SOURCE /* with only _POSIX_C_SOURCE, Darwin hides struct rusage's ru_maxrss */
#endif

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <uv.h>

#include "abi.h"
#include "fs_support.h"
#include "ms_rt/process.h"
#include "ms_rt/stream.h"
#include "ms_rt/sys.h"
#include "ms_sched.h"

#ifdef _WIN32
#define PSAPI_VERSION 2 /* GetProcessMemoryInfo from kernel32, so no extra library */
#include <io.h>
#include <windows.h>
#include <psapi.h>
#else
#include <fcntl.h>
#include <signal.h>
#include <sys/resource.h>
#include <unistd.h>
#endif

enum {
    STDIO_PIPE = 0,
    STDIO_INHERIT = 1,
    STDIO_NULL = 2,
    STREAM_IN = 0,
    STREAM_OUT = 1,
    STREAM_ERR = 2,
    STREAM_COUNT = 3,
    STREAM_READS = 1,
    STREAM_WRITES = 2,
    STREAM_OWNS = 4,
    STREAM_NONBLOCK = 8,
    CHUNK_BYTES = 64 * 1024,
    EXIT_DELAY_MS = 1000,
    SAMPLE_MS = 20,
};

/* The runtime stream table (crates/ms-rt/src/streams.rs); a descriptor given to it is closed by it. */
int64_t msrt_streams_open(int64_t fd, int64_t flags);

static const char output_kept_open[] =
    "the command finished but a background process kept its output open; close or redirect its output, or set a timeout";

/* ---- the command ---- */

/* A command's strings as the OS wants them: all malloc'd, NULL terminated where they are lists. */
typedef struct Command {
    char *program;
    char **argv;
    char **env;
    char *cwd; /* NULL: the caller's */
} Command;

static void list_free(char **items) {
    for (size_t i = 0; items != NULL && items[i] != NULL; i++) {
        free(items[i]);
    }
    free(items);
}

static void command_free(Command *command) {
    free(command->program);
    list_free(command->argv);
    list_free(command->env);
    free(command->cwd);
    *command = (Command){0};
}

static char *copy_text(const MsStr *text) {
    char *copy = malloc(msrt_str_len(text) + 1);
    if (copy != NULL) {
        memcpy(copy, msrt_str_data(text), msrt_str_len(text));
        copy[msrt_str_len(text)] = '\0';
    }
    return copy;
}

static const MsStr *string_at(const MsVec *list, size_t index) { return (const MsStr *)list->ptr + index; }

static bool has_nul(const MsStr *text) { return memchr(msrt_str_data(text), 0, msrt_str_len(text)) != NULL; }

/* The arguments, program included, as argv; NULL when out of memory. */
static bool build_argv(Command *command, const MsStr *program, const MsVec *arguments) {
    command->argv = calloc(arguments->len + 2, sizeof *command->argv);
    if (command->argv == NULL) {
        return false;
    }
    command->argv[0] = copy_text(program);
    for (size_t i = 0; i < arguments->len; i++) {
        command->argv[i + 1] = copy_text(string_at(arguments, i));
    }
    for (size_t i = 0; i <= arguments->len; i++) {
        if (command->argv[i] == NULL) {
            return false;
        }
    }
    return true;
}

/* Whether the inherited variable called `item` is the one `name` names; Windows names ignore case. */
static bool names_variable(const char *item, const MsStr *name) {
    const size_t length = msrt_str_len(name);
#ifdef _WIN32
    const bool same = _strnicmp(item, msrt_str_data(name), length) == 0;
#else
    const bool same = strncmp(item, msrt_str_data(name), length) == 0;
#endif
    return same && item[length] == '\0';
}

/* The inherited environment with the given variables added or replacing: `NAME=value` strings. */
static bool build_environment(Command *command, const MsVec *names, const MsVec *values) {
    uv_env_item_t *inherited = NULL;
    int count = 0;
    if (uv_os_environ(&inherited, &count) != 0) {
        return false;
    }
    command->env = calloc((size_t)count + names->len + 1, sizeof *command->env);
    size_t used = 0;
    bool ok = command->env != NULL;
    for (int i = 0; ok && i < count; i++) {
        bool replaced = false;
        for (size_t k = 0; k < names->len; k++) {
            const MsStr *name = string_at(names, k);
            replaced = replaced || names_variable(inherited[i].name, name);
        }
        if (!replaced) {
            const size_t size = strlen(inherited[i].name) + strlen(inherited[i].value) + 2;
            command->env[used] = malloc(size);
            ok = command->env[used] != NULL;
            if (ok) {
                snprintf(command->env[used++], size, "%s=%s", inherited[i].name, inherited[i].value);
            }
        }
    }
    uv_os_free_environ(inherited, count);
    for (size_t k = 0; ok && k < names->len; k++) {
        const MsStr *name = string_at(names, k);
        const MsStr *value = string_at(values, k);
        const size_t size = msrt_str_len(name) + msrt_str_len(value) + 2;
        command->env[used] = malloc(size);
        ok = command->env[used] != NULL;
        if (ok) {
            snprintf(command->env[used++], size, "%.*s=%.*s", (int)msrt_str_len(name), msrt_str_data(name),
                     (int)msrt_str_len(value), msrt_str_data(value));
        }
    }
    return ok;
}

/* The command's arguments checked as `valid_command` and `valid_environment` did: no empty program, no NUL, no
 * variable name that is empty or holds `=`. */
static bool command_valid(const MsStr *program, const MsVec *arguments, bool has_cwd, const MsStr *cwd,
                          const MsVec *names, const MsVec *values) {
    if (msrt_str_len(program) == 0 || has_nul(program) || names->len != values->len) {
        return false;
    }
    for (size_t i = 0; i < arguments->len; i++) {
        if (has_nul(string_at(arguments, i))) {
            return false;
        }
    }
    for (size_t i = 0; i < names->len; i++) {
        const MsStr *name = string_at(names, i);
        if (msrt_str_len(name) == 0 || has_nul(name) || memchr(msrt_str_data(name), '=', msrt_str_len(name)) != NULL ||
            has_nul(string_at(values, i))) {
            return false;
        }
    }
    return !has_cwd || (msrt_str_len(cwd) != 0 && !has_nul(cwd));
}

/* Builds `command`; false with `fail` set when the arguments are invalid or memory runs out. */
static bool command_build(Command *command, const MsStr *program, const MsVec *arguments, bool has_cwd,
                          const MsStr *cwd, const MsVec *names, const MsVec *values, MsFsFail *fail) {
    if (!command_valid(program, arguments, has_cwd, cwd, names, values)) {
        ms_fs_fail_status(fail, STATUS_INVALID_INPUT);
        return false;
    }
    command->program = copy_text(program);
    command->cwd = has_cwd ? copy_text(cwd) : NULL;
    if (command->program == NULL || (has_cwd && command->cwd == NULL) || !build_argv(command, program, arguments) ||
        !build_environment(command, names, values)) {
        command_free(command);
        ms_fs_fail_text(fail, "out of memory");
        return false;
    }
    return true;
}

/* ---- a child ---- */

/* What `run` collects; owned by the child and touched by the loop thread only until the child is done. */
typedef struct Collected {
    uv_pipe_t pipes[STREAM_COUNT];
    bool open[STREAM_COUNT];
    uv_write_t write;
    uv_timer_t deadline;
    uv_timer_t delay;
    uint8_t *input; /* owned (malloc) */
    size_t input_length;
    MsFsBuffer output[2];
    int64_t remaining;
    int64_t timeout_ns; /* negative: none */
    bool overflow, timed_out, kept_open;
} Collected;

typedef struct MsChild {
    MsObj header; /* first: the runtime drops the handle through it */
    uv_mutex_t lock;
    uv_loop_t loop;
    uv_process_t process;
    uv_timer_t sampler;
    uv_thread_t thread;
    Collected *run; /* NULL for a `spawn` */
    uint64_t token; /* the token a waiting task parks on (0: none); one per park, see child_arm */
    int64_t pid;
    int64_t code; /* once exited */
    int64_t max_resident;
    int descriptors[STREAM_COUNT]; /* a spawn's parent ends; -1 when none or taken */
    int64_t ids[STREAM_COUNT];     /* the stream-table id once taken; -2 not yet */
    bool exited, finished, stopped, loop_ready, started; /* finished: the loop thread has ended */
#ifdef _WIN32
    HANDLE job;
#endif
} MsChild;

static void child_lock(MsChild *child) { uv_mutex_lock(&child->lock); }
static void child_unlock(MsChild *child) { uv_mutex_unlock(&child->lock); }

/* A remote token counts as a pending wake-up only until its first post, so a task that parks again needs a new one:
 * arm before reading the state, park only while the state says to, then disarm. */
static uint64_t child_arm(MsChild *child) {
    const uint64_t token = msrt_token_new(1);
    child_lock(child);
    child->token = token;
    child_unlock(child);
    return token;
}

static void child_disarm(MsChild *child, uint64_t token) {
    child_lock(child);
    child->token = 0;
    child_unlock(child);
    msrt_token_free(token);
}

/* Wakes the waiting task, if any (any thread). */
static void child_wake(MsChild *child) {
    child_lock(child);
    if (child->token != 0) {
        msrt_token_post_remote(child->token, 1);
    }
    child_unlock(child);
}

/* ---- signals ---- */

/* Signals the child's group (SIGTERM unless `force`; Windows has no graceful signal: the job ends). A child that has
 * exited is left alone, since its pid may be reused. */
static void child_signal(MsChild *child, bool force) {
    child_lock(child);
    if (!child->exited && child->started) {
#ifdef _WIN32
        (void)force;
        TerminateJobObject(child->job, 1);
        TerminateProcess(child->process.process_handle, 1);
#else
        if (force || kill((pid_t)-child->pid, SIGTERM) != 0) {
            kill((pid_t)-child->pid, SIGKILL);
        }
#endif
    }
    child_unlock(child);
}

/* Kills what remains of the group, also after the leader has been reaped (its pid is the group id). */
static void child_kill_group(MsChild *child) {
#ifdef _WIN32
    TerminateJobObject(child->job, 1);
#else
    if (child->started) {
        kill((pid_t)-child->pid, SIGKILL);
    }
#endif
}

/* ---- the peak resident set size ---- */

#ifndef _WIN32
/* The largest resident set of any child this process has reaped, in bytes: an upper bound for a child that exited
 * before it could be sampled. */
static int64_t reaped_children_peak(void) {
    struct rusage usage;
    if (getrusage(RUSAGE_CHILDREN, &usage) != 0) {
        return 0;
    }
#ifdef __APPLE__
    return (int64_t)usage.ru_maxrss; /* bytes */
#else
    return (int64_t)usage.ru_maxrss * 1024; /* kilobytes */
#endif
}
#endif

static int64_t resident_peak(const MsChild *child) {
#if defined(__linux__)
    char path[64];
    snprintf(path, sizeof path, "/proc/%lld/status", (long long)child->pid);
    FILE *file = fopen(path, "re");
    if (file == NULL) {
        return 0;
    }
    char line[256];
    int64_t kilobytes = 0;
    while (fgets(line, sizeof line, file) != NULL) {
        if (strncmp(line, "VmHWM:", 6) == 0) {
            kilobytes = strtoll(line + 6, NULL, 10);
            break;
        }
    }
    fclose(file);
    return kilobytes * 1024;
#elif defined(_WIN32)
    (void)child;
    return 0; /* read from the process handle when it exits */
#else
    (void)child;
    return 0;
#endif
}

static void sample_resident(MsChild *child) {
    const int64_t peak = resident_peak(child);
    child_lock(child);
    if (peak > child->max_resident) {
        child->max_resident = peak;
    }
    child_unlock(child);
}

static void on_sample(uv_timer_t *timer) {
    sample_resident((MsChild *)timer->data);
}

/* ---- ending the loop ---- */

static void close_once(uv_handle_t *handle) {
    if (!uv_is_closing(handle)) {
        uv_close(handle, NULL);
    }
}

static void run_close_pipe(Collected *run, int stream) {
    if (run->open[stream]) {
        run->open[stream] = false;
        close_once((uv_handle_t *)&run->pipes[stream]);
    }
}

/* Closes every handle of a `run` that is still open; the loop then has nothing left and ends. */
static void run_close_all(Collected *run) {
    close_once((uv_handle_t *)&run->deadline);
    close_once((uv_handle_t *)&run->delay);
    for (int stream = 0; stream < STREAM_COUNT; stream++) {
        run_close_pipe(run, stream);
    }
}

static void on_delay(uv_timer_t *timer);

/* A `run` is complete once the child has exited and its output pipes are closed. When only the exit is in, the
 * pipes get a second more before the output counts as kept open by a background process. */
static void run_progress(MsChild *child) {
    Collected *run = child->run;
    const bool output_open = run->open[STREAM_OUT] || run->open[STREAM_ERR];
    if (output_open) {
        if (!uv_is_active((uv_handle_t *)&run->delay) && !uv_is_closing((uv_handle_t *)&run->delay)) {
            uv_timer_start(&run->delay, on_delay, EXIT_DELAY_MS, 0);
        }
        return;
    }
    run_close_all(run);
}

/* Called on the loop thread after an exit or a closed pipe: ends what is finished, wakes the task. */
static void child_progress(MsChild *child) {
    child_lock(child);
    const bool exited = child->exited;
    child_unlock(child);
    if (exited) {
        close_once((uv_handle_t *)&child->sampler);
        if (child->run != NULL) {
            run_progress(child);
        }
    }
    child_wake(child);
}

static void on_delay(uv_timer_t *timer) {
    MsChild *child = timer->data;
    child->run->kept_open = true;
    run_close_all(child->run);
    child_progress(child);
}

static void on_exit(uv_process_t *process, int64_t status, int term_signal) {
    MsChild *child = process->data;
    child_lock(child);
    child->exited = true;
    child->code = term_signal != 0 ? -1 : status;
#ifdef _WIN32
    PROCESS_MEMORY_COUNTERS counters = {.cb = sizeof counters};
    if (GetProcessMemoryInfo(process->process_handle, &counters, sizeof counters)) {
        child->max_resident = (int64_t)counters.PeakWorkingSetSize;
    }
#else
    if (child->max_resident == 0) {
        child->max_resident = reaped_children_peak();
    }
#endif
    child_unlock(child);
    uv_close((uv_handle_t *)process, NULL);
    child_progress(child);
}

/* ---- run: the loop's half ---- */

static void on_deadline(uv_timer_t *timer) {
    MsChild *child = timer->data;
    child->run->timed_out = true;
    child_kill_group(child);
}

static void on_alloc(uv_handle_t *handle, size_t suggested, uv_buf_t *buffer) {
    (void)suggested;
    (void)handle;
    *buffer = uv_buf_init(malloc(CHUNK_BYTES), CHUNK_BYTES); // NOLINT(clang-analyzer-unix.Malloc): on_read frees it
}

static void on_read(uv_stream_t *stream, ssize_t count, const uv_buf_t *buffer) {
    MsChild *child = stream->data;
    Collected *run = child->run;
    const int which = stream == (uv_stream_t *)&run->pipes[STREAM_ERR] ? STREAM_ERR : STREAM_OUT;
    if (count > 0) {
        const size_t accepted = (int64_t)count > run->remaining ? (size_t)run->remaining : (size_t)count;
        if (!ms_fs_buffer_append(&run->output[which - 1], (const uint8_t *)buffer->base, accepted)) {
            run->overflow = true;
        }
        run->remaining -= (int64_t)accepted;
        if (accepted != (size_t)count) {
            run->overflow = true;
        }
        if (run->overflow) {
            child_kill_group(child);
            uv_read_stop(stream);
        }
    } else if (count < 0) {
        run_close_pipe(run, which);
    }
    free(buffer->base);
    if (count < 0 || run->overflow) {
        child_progress(child);
    }
}

static void on_written(uv_write_t *request, int status) {
    (void)status; /* a child that closed its input early drops the rest */
    MsChild *child = request->data;
    run_close_pipe(child->run, STREAM_IN);
}

/* Opens the parent ends of a `run`'s pipes on the loop and starts reading, writing and timing. Runs before the loop
 * thread starts. */
static bool run_attach(MsChild *child, const int descriptors[STREAM_COUNT]) {
    Collected *run = child->run;
    for (int stream = 0; stream < STREAM_COUNT; stream++) {
        if (uv_pipe_init(&child->loop, &run->pipes[stream], 0) != 0) {
            return false;
        }
        run->pipes[stream].data = child;
        run->open[stream] = true;
        if (uv_pipe_open(&run->pipes[stream], descriptors[stream]) != 0) {
            return false;
        }
    }
    uv_timer_init(&child->loop, &run->deadline);
    uv_timer_init(&child->loop, &run->delay);
    run->deadline.data = child;
    run->delay.data = child;
    run->write.data = child;
    if (run->input_length == 0) {
        run_close_pipe(run, STREAM_IN);
    } else {
        const uv_buf_t input = uv_buf_init((char *)run->input, (unsigned)run->input_length);
        if (uv_write(&run->write, (uv_stream_t *)&run->pipes[STREAM_IN], &input, 1, on_written) != 0) {
            run_close_pipe(run, STREAM_IN);
        }
    }
    uv_read_start((uv_stream_t *)&run->pipes[STREAM_OUT], on_alloc, on_read);
    uv_read_start((uv_stream_t *)&run->pipes[STREAM_ERR], on_alloc, on_read);
    if (run->timeout_ns >= 0) {
        uv_timer_start(&run->deadline, on_deadline, (uint64_t)(run->timeout_ns / 1000000), 0);
    }
    return true;
}

/* ---- starting ---- */

static void child_thread(void *argument) {
    MsChild *child = argument;
    uv_run(&child->loop, UV_RUN_DEFAULT);
    child_lock(child);
    child->finished = true;
    child_unlock(child);
    child_wake(child);
}

/* The status of a failed start: a missing program or directory, a file that cannot run, or the host's text. */
static void start_failure(MsFsFail *fail, int error, const char *program) {
    if (error == UV_ENOENT || error == UV_ENOTDIR) {
        ms_fs_fail_status(fail, STATUS_NOT_FOUND);
    } else if (error == UV_EACCES || error == UV_EPERM) {
        ms_fs_fail_status(fail, STATUS_PERMISSION_DENIED);
    } else {
        char text[512];
        snprintf(text, sizeof text, "fork/exec %s: %s", program, uv_strerror(error));
        ms_fs_fail_text(fail, text);
    }
}

/* A pipe pair for one standard stream: `parent` stays here, `child` goes to the process. */
static bool make_pipe(int stream, int *parent, int *child) {
    int ends[2];
    const int read_flags = stream == STREAM_IN ? 0 : UV_NONBLOCK_PIPE;
    const int write_flags = stream == STREAM_IN ? UV_NONBLOCK_PIPE : 0;
    if (uv_pipe(ends, read_flags, write_flags) != 0) {
        return false;
    }
    *parent = stream == STREAM_IN ? ends[1] : ends[0];
    *child = stream == STREAM_IN ? ends[0] : ends[1];
    return true;
}

static void descriptor_close(int fd) {
    if (fd >= 0) {
#ifdef _WIN32
        _close(fd);
#else
        close(fd);
#endif
    }
}

/* Starts the process with the given modes; on success the parent ends of its pipes are in `parent` (-1 for a stream
 * that is not piped). The loop is initialised and the process spawned, but the loop thread is not started. */
static bool child_spawn(MsChild *child, const Command *command, const int64_t modes[STREAM_COUNT], int parent[STREAM_COUNT],
                        MsFsFail *fail) {
    uv_stdio_container_t stdio[STREAM_COUNT];
    int theirs[STREAM_COUNT] = {-1, -1, -1};
    for (int stream = 0; stream < STREAM_COUNT; stream++) {
        parent[stream] = -1;
        stdio[stream] = (uv_stdio_container_t){.flags = UV_IGNORE};
        if (modes[stream] == STDIO_PIPE) {
            if (!make_pipe(stream, &parent[stream], &theirs[stream])) {
                ms_fs_fail_text(fail, "pipe: system call failed");
                break;
            }
            stdio[stream] = (uv_stdio_container_t){.flags = UV_INHERIT_FD, .data.fd = theirs[stream]};
        } else if (modes[stream] == STDIO_INHERIT) {
            stdio[stream] = (uv_stdio_container_t){.flags = UV_INHERIT_FD, .data.fd = stream};
        } else {
            stdio[stream] = (uv_stdio_container_t){.flags = UV_IGNORE};
        }
    }
    int error = ms_fs_failed(fail) ? UV_EINVAL : 0;
    if (error == 0) {
        uv_process_options_t options = {.exit_cb = on_exit,
                                        .file = command->program,
                                        .args = command->argv,
                                        .env = command->env,
                                        .cwd = command->cwd,
                                        .flags = UV_PROCESS_DETACHED,
                                        .stdio_count = STREAM_COUNT,
                                        .stdio = stdio};
        error = uv_spawn(&child->loop, &child->process, &options);
        if (error != 0) {
            uv_close((uv_handle_t *)&child->process, NULL); /* initialised by the failed start */
            start_failure(fail, error, command->program);
        }
    }
    for (int stream = 0; stream < STREAM_COUNT; stream++) {
        descriptor_close(theirs[stream]);
        if (error != 0) {
            descriptor_close(parent[stream]);
            parent[stream] = -1;
        }
    }
    return error == 0;
}

static void child_free(MsObj *object);

static MsChild *child_new(Collected *run) {
    MsChild *child = calloc(1, sizeof *child);
    if (child == NULL) {
        return NULL;
    }
    child->header.drop = child_free;
    child->run = run;
    for (int stream = 0; stream < STREAM_COUNT; stream++) {
        child->descriptors[stream] = -1;
        child->ids[stream] = -2;
    }
    if (uv_mutex_init(&child->lock) != 0) {
        free(child);
        return NULL;
    }
    if (uv_loop_init(&child->loop) != 0) {
        uv_mutex_destroy(&child->lock);
        free(child);
        return NULL;
    }
    child->loop_ready = true;
    return child;
}

/* After a successful spawn: the sampler, the job object, and the loop thread. */
static bool child_run_loop(MsChild *child) {
    child->pid = child->process.pid;
    child->process.data = child;
    child->started = true;
#ifdef _WIN32
    child->job = CreateJobObjectW(NULL, NULL);
    if (child->job != NULL) {
        AssignProcessToJobObject(child->job, child->process.process_handle);
    }
#endif
    uv_timer_init(&child->loop, &child->sampler);
    child->sampler.data = child;
    sample_resident(child);
    uv_timer_start(&child->sampler, on_sample, SAMPLE_MS, SAMPLE_MS);
    return uv_thread_create(&child->thread, child_thread, child) == 0;
}

/* Waits for the loop thread to finish and releases the loop. The child must be exiting: callers kill it first. */
static void child_join(MsChild *child) {
    if (child->loop_ready && child->started) {
        uv_thread_join(&child->thread);
        child->started = false;
    }
}

static void child_free(MsObj *object) {
    MsChild *child = (MsChild *)object;
    child_kill_group(child);
    child_signal(child, true);
    child_join(child);
    for (int stream = 0; stream < STREAM_COUNT; stream++) {
        descriptor_close(child->descriptors[stream]);
    }
    if (child->run != NULL) {
        ms_fs_buffer_free(&child->run->output[0]);
        ms_fs_buffer_free(&child->run->output[1]);
        free(child->run->input);
        free(child->run);
    }
    if (child->loop_ready) {
        uv_run(&child->loop, UV_RUN_NOWAIT);
        uv_loop_close(&child->loop);
    }
    uv_mutex_destroy(&child->lock);
#ifdef _WIN32
    if (child->job != NULL) {
        CloseHandle(child->job);
    }
#endif
    free(child);
}

/* ---- spawn ---- */

/* Ends a native that starts a command. A command that could not be started is named: the program, or the working
 * directory when that is what does not exist. Other failures (invalid input, a timeout, an output limit) are not about
 * the program's name. */
static uint8_t command_finish(MsFsFail *fail, const MsStr *program, const MsStr *cwd, MsStr *err) {
    if (fail->status != STATUS_NOT_FOUND && fail->status != STATUS_PERMISSION_DENIED) {
        return ms_fs_finish(fail, err);
    }
    char *directory = cwd != NULL ? copy_text(cwd) : NULL;
    uv_fs_t request;
    const bool missing_directory = directory != NULL && uv_fs_stat(NULL, &request, directory, NULL) != 0;
    if (directory != NULL) {
        uv_fs_req_cleanup(&request);
    }
    free(directory);
    if (!missing_directory) {
        return ms_fs_finish_at(fail, msrt_str_bytes(program), err);
    }
    const char prefix[] = "working directory ";
    const size_t length = msrt_str_len(cwd);
    uint8_t *detail = malloc(sizeof prefix - 1 + length);
    if (detail == NULL) {
        return ms_fs_finish(fail, err);
    }
    memcpy(detail, prefix, sizeof prefix - 1);
    memcpy(detail + sizeof prefix - 1, msrt_str_data(cwd), length);
    const uint8_t status = ms_fs_finish_at(fail, ms_bytes_of(detail, sizeof prefix - 1 + length), err);
    free(detail);
    return status;
}

uint8_t msstd_process_command_spawn(const MsStr *program, const MsVec *arguments, int64_t stdin_mode, int64_t stdout_mode,
                                    int64_t stderr_mode, uint8_t has_cwd, const MsStr *cwd, const MsVec *env_names,
                                    const MsVec *env_values, MsObj **out, MsStr *err) {
    MsFsFail fail = {0};
    Command command = {0};
    const int64_t modes[STREAM_COUNT] = {stdin_mode, stdout_mode, stderr_mode};
    MsChild *child = NULL;
    int parent[STREAM_COUNT] = {-1, -1, -1};
    if (command_build(&command, program, arguments, has_cwd != 0, cwd, env_names, env_values, &fail)) {
        child = child_new(NULL);
        if (child == NULL) {
            ms_fs_fail_text(&fail, "out of memory");
        } else if (!child_spawn(child, &command, modes, parent, &fail) || !child_run_loop(child)) {
            if (!ms_fs_failed(&fail)) {
                ms_fs_fail_text(&fail, "cannot start the process thread");
            }
        }
    }
    if (child != NULL && !ms_fs_failed(&fail)) {
        memcpy(child->descriptors, parent, sizeof parent);
        *out = &child->header;
    } else if (child != NULL) {
        child->started = false; /* nothing to join */
        child_free(&child->header);
    }
    command_free(&command);
    return command_finish(&fail, program, has_cwd != 0 ? cwd : NULL, err);
}

/* The runtime stream-table id of a piped stream: the first call moves the descriptor into the table. */
int64_t msstd_process_subprocess_stream_id(MsObj *object, int64_t which) {
    MsChild *child = (MsChild *)object;
    int stream = (int)which;
    if (which < 0 || which >= STREAM_COUNT) {
        stream = which < 0 ? 0 : STREAM_COUNT - 1;
    }
    if (child->ids[stream] == -2) {
        const int fd = child->descriptors[stream];
        const int64_t access = stream == STREAM_IN ? STREAM_WRITES : STREAM_READS;
        child->descriptors[stream] = -1;
        child->ids[stream] = fd < 0 ? -1 : msrt_streams_open(fd, STREAM_OWNS | STREAM_NONBLOCK | access);
    }
    return child->ids[stream];
}

int64_t msstd_process_subprocess_max_resident(MsObj *object) {
    MsChild *child = (MsChild *)object;
    child_lock(child);
    const int64_t peak = child->exited ? child->max_resident : 0;
    child_unlock(child);
    return peak;
}

int64_t msstd_process_subprocess_pid(MsObj *object) { return ((MsChild *)object)->pid; }

void msstd_process_subprocess_terminate(MsObj *object) { child_signal((MsChild *)object, false); }

void msstd_process_subprocess_kill(MsObj *object) { child_signal((MsChild *)object, true); }

/* Kills the group, joins the child and closes the pipes not yet handed to the table. Idempotent. */
void msstd_process_subprocess_close(MsObj *object) {
    MsChild *child = (MsChild *)object;
    if (!child->stopped) {
        child->stopped = true;
        child_signal(child, true);
        child_join(child);
        child_kill_group(child);
        for (int stream = 0; stream < STREAM_COUNT; stream++) {
            descriptor_close(child->descriptors[stream]);
            child->descriptors[stream] = -1;
        }
    }
}

/* Waits for the exit, or STATUS_TIMED_OUT when `timeout_ns` passes first (the child keeps running). */
uint8_t msstd_process_subprocess_wait(MsObj *object, uint8_t has_timeout, int64_t timeout_ns, int64_t *out, MsStr *err) {
    MsChild *child = (MsChild *)object;
    MsFsFail fail = {0};
    if (has_timeout != 0 && timeout_ns < 0) {
        ms_fs_fail_status(&fail, STATUS_INVALID_INPUT);
        return ms_fs_finish(&fail, err);
    }
    const int64_t deadline = has_timeout != 0 ? (int64_t)uv_hrtime() + timeout_ns : -1;
    for (;;) {
        const uint64_t token = child_arm(child);
        child_lock(child);
        const bool exited = child->exited;
        const int64_t code = child->code;
        child_unlock(child);
        const int64_t left = deadline >= 0 ? deadline - (int64_t)uv_hrtime() : -1;
        uint32_t woke = 0;
        if (!exited && (deadline < 0 || left > 0)) {
            uint64_t value = 0;
            woke = msrt_token_park(token, left, &value);
        }
        child_disarm(child, token);
        if (exited) {
            *out = code;
            return ms_fs_finish(&fail, err);
        }
        if ((woke & MS_WAIT_CANCELLED) != 0) {
            ms_fs_fail_text(&fail, "cancelled");
            return ms_fs_finish(&fail, err);
        }
        if (deadline >= 0 && left <= 0) {
            ms_fs_fail_status(&fail, STATUS_TIMED_OUT);
            return ms_fs_finish(&fail, err);
        }
    }
}

/* ---- run ---- */

static Collected *collected_new(const MsVec *input, bool has_max, int64_t max, bool has_timeout, int64_t timeout_ns) {
    Collected *run = calloc(1, sizeof *run);
    if (run == NULL) {
        return NULL;
    }
    run->remaining = has_max ? max : INT64_MAX;
    run->timeout_ns = has_timeout ? timeout_ns : -1;
    run->input_length = input->len;
    if (input->len != 0) {
        run->input = malloc(input->len);
        if (run->input == NULL) {
            free(run);
            return NULL;
        }
        memcpy(run->input, input->ptr, input->len);
    }
    return run;
}

/* Waits for the loop thread of a `run` to end. A stop request aborts the child, waits for the loop (the abort kills
 * the group, and the delay after the exit closes pipes a background process still holds) and fails the call. */
static bool run_wait(MsChild *child, MsFsFail *fail) {
    for (;;) {
        const uint64_t token = child_arm(child);
        child_lock(child);
        const bool finished = child->finished;
        child_unlock(child);
        uint32_t woke = 0;
        if (!finished) {
            uint64_t value = 0;
            woke = msrt_token_park(token, -1, &value);
        }
        child_disarm(child, token);
        if (finished) {
            child_join(child);
            return true;
        }
        if ((woke & MS_WAIT_CANCELLED) != 0) {
            child_kill_group(child);
            child_signal(child, true);
            child_join(child);
            ms_fs_fail_text(fail, "cancelled");
            return false;
        }
    }
}

/* The result of a finished `run`: its status, and the output on success. */
static uint8_t run_result(MsChild *child, MsCommandOut *out, MsFsFail *fail) {
    const Collected *run = child->run;
    if (run->overflow) {
        ms_fs_fail_status(fail, STATUS_OUTPUT_LIMIT);
    } else if (run->timed_out) {
        ms_fs_fail_status(fail, STATUS_TIMED_OUT);
    } else if (run->kept_open && child->code == 0) {
        ms_fs_fail_text(fail, output_kept_open);
    } else {
        out->exit_code = child->code;
        msrt_write_bytes(&out->out, run->output[0].data, run->output[0].length);
        msrt_write_bytes(&out->err, run->output[1].data, run->output[1].length);
        out->max_resident_bytes = child->max_resident;
    }
    return fail->status;
}

uint8_t msstd_process_command_run(const MsStr *program, const MsVec *arguments, const MsVec *input, uint8_t has_max,
                                  int64_t max, uint8_t has_timeout, int64_t timeout_ns, uint8_t has_cwd, const MsStr *cwd,
                                  const MsVec *env_names, const MsVec *env_values, MsCommandOut *out, MsStr *err) {
    MsFsFail fail = {0};
    Command command = {0};
    int64_t limit = 0;
    if (!ms_fs_limit(has_max, max, &limit) || (has_timeout != 0 && timeout_ns < 0)) {
        ms_fs_fail_status(&fail, STATUS_INVALID_INPUT);
    } else if (command_build(&command, program, arguments, has_cwd != 0, cwd, env_names, env_values, &fail)) {
        Collected *run = collected_new(input, true, limit, has_timeout != 0, timeout_ns);
        MsChild *child = run == NULL ? NULL : child_new(run);
        int parent[STREAM_COUNT] = {-1, -1, -1};
        const int64_t modes[STREAM_COUNT] = {STDIO_PIPE, STDIO_PIPE, STDIO_PIPE};
        if (child == NULL) {
            free(run);
            ms_fs_fail_text(&fail, "out of memory");
        } else if (!child_spawn(child, &command, modes, parent, &fail)) {
            child_free(&child->header);
        } else if (!run_attach(child, parent) || !child_run_loop(child)) {
            ms_fs_fail_text(&fail, "cannot start the process thread");
            child_free(&child->header);
        } else {
            if (run_wait(child, &fail)) {
                run_result(child, out, &fail);
            }
            child_free(&child->header);
        }
    }
    command_free(&command);
    return command_finish(&fail, program, has_cwd != 0 ? cwd : NULL, err);
}

/* ---- replace ---- */

#ifdef _WIN32
uint8_t msstd_process_replace(const MsStr *program, const MsVec *arguments, const MsVec *env_names,
                              const MsVec *env_values, MsStr *err) {
    (void)program;
    (void)arguments;
    (void)env_names;
    (void)env_values;
    MsFsFail fail = {0};
    ms_fs_fail_status(&fail, STATUS_UNSUPPORTED); /* Windows has no exec */
    return ms_fs_finish(&fail, err);
}
#else
/* The strings of `list` as a NULL-terminated array, or NULL when out of memory. */
static char **text_array(const MsVec *list) {
    char **items = calloc(list->len + 1, sizeof *items);
    for (size_t i = 0; items != NULL && i < list->len; i++) {
        items[i] = copy_text(string_at(list, i));
        if (items[i] == NULL) {
            list_free(items);
            return NULL;
        }
    }
    return items;
}

/* `NAME=value` for each pair, as an environment array; NULL when out of memory. */
static char **pair_array(const MsVec *names, const MsVec *values) {
    char **items = calloc(names->len + 1, sizeof *items);
    for (size_t i = 0; items != NULL && i < names->len; i++) {
        const MsStr *name = string_at(names, i);
        const MsStr *value = string_at(values, i);
        const size_t size = msrt_str_len(name) + msrt_str_len(value) + 2;
        items[i] = malloc(size);
        if (items[i] == NULL) {
            list_free(items);
            return NULL;
        }
        snprintf(items[i], size, "%.*s=%.*s", (int)msrt_str_len(name), msrt_str_data(name),
                 (int)msrt_str_len(value), msrt_str_data(value));
    }
    return items;
}

/* Replaces the process image; returns only on failure. The environment is exactly the given variables. */
uint8_t msstd_process_replace(const MsStr *program, const MsVec *arguments, const MsVec *env_names,
                              const MsVec *env_values, MsStr *err) {
    MsFsFail fail = {0};
    if (arguments->len == 0 || !command_valid(program, arguments, false, NULL, env_names, env_values)) {
        ms_fs_fail_status(&fail, STATUS_INVALID_INPUT);
        return ms_fs_finish(&fail, err);
    }
    Command command = {.program = copy_text(program), .argv = text_array(arguments),
                       .env = pair_array(env_names, env_values)};
    if (command.program == NULL || command.argv == NULL || command.env == NULL) {
        ms_fs_fail_text(&fail, "out of memory");
    } else {
        execve(command.program, command.argv, command.env);
        const int error = uv_translate_sys_error(errno);
        start_failure(&fail, error, command.program);
        if (fail.status == STATUS_FAILED) {
            char text[512];
            snprintf(text, sizeof text, "exec %s: %s", command.program, uv_strerror(error));
            ms_fs_fail_free(&fail);
            ms_fs_fail_text(&fail, text);
        }
    }
    command_free(&command);
    return ms_fs_finish(&fail, err);
}
#endif
