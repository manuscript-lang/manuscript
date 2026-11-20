/* start.c: the process entry. msrt_start installs the program's tables, watches for stop requests, runs `main` as
 * the main isolate's main task on a thread of its own and returns the exit status.
 *
 * The thread exists so `main` runs on a task stack the runtime sizes (a 256 MiB region), whatever the process's own
 * stack limit is; the thread's stack only hosts the scheduler. Stop requests (SIGINT, SIGTERM) arrive on the stop
 * thread (runtime/io/stop.c), never in a signal handler: the first raises the cancel flag of the running task and
 * wakes the scheduler; a second before cleanup finished, or the grace period running out, ends the process.
 */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c11 */

#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <uv.h>

#include "../core/alloc.h"
#include "../core/cancel.h"
#include "../core/fault.h"
#include "../core/frames.h"
#include "../core/promise.h"
#include "../core/sweep.h"
#include "../core/task.h"
#include "../core/unwind.h"
#include "../core/worker.h"
#include "../io/reactor.h"
#include "../io/stop.h"
#include "entry.h"
#include "../core/stdout.h"
#include "ms_rt/alloc.h"
#include "ms_rt/cabi.h"
#include "ms_rt/list.h"
#include "ms_rt/safe.h"
#include "ms_rt/string.h"
#include "ms_rt/sys.h"

enum {
    CLEANUP_GRACE_SECONDS = 30, /* after the first stop request, before cleanup is abandoned */
    MAX_MAIN_EXIT = 125,        /* 126 and above are reserved by shells */
    SIZE_CLASS_LINE = 160,
    ENV_TEXT_BYTES = 32,
    TASK_OUTCOME_CANCELLED = 2, /* ms_task_join's third outcome */
};

_Static_assert(sizeof(MsPollReady) == sizeof(MsIoReady), "the poller's ready entries are the reactor's");

static MsMainFn main_function;
static int64_t main_result;
static int64_t start_nanos;
static _Atomic uint8_t pending_signal; /* the first stop request, 0 until one arrives */

int64_t msrt_start_nanos(void) { return start_nanos; }

/* Whether `main` frees the plain memory it still owns when it returns. The process exits next, so a normal build
 * skips it; the counting build keeps it so a leak shows, and MS_FREE_AT_EXIT keeps it for valgrind. */
uint8_t msrt_exit_frees(void) {
#ifdef MS_ALLOC_STATS
    return 1;
#else
    return getenv("MS_FREE_AT_EXIT") != NULL ? 1 : 0;
#endif
}

/* ---- ending the process ---- */

/* Flushes output, runs the exit hooks, writes the profile and ends the process. */
MS_NORETURN static void finish_process(int status) {
    ms_sched_flush_stdout();
    ms_process_run_exit_hooks();
    ms_profile_finish();
    ms_sys_exit_now(status);
}

void msrt_process_exit(int64_t code) { finish_process((int)code); }

static MsBytes text_bytes(const char *text) { return ms_bytes_of((const uint8_t *)text, strlen(text)); }

/* Reports a stop that cleanup did not survive, on standard error and in the fault record. */
static void incomplete_cleanup(const char *message) {
    ms_sys_stderr_write(text_bytes(message));
    ms_sys_stderr_write(text_bytes("\n"));
    ms_fault_record_write(MS_FAULT_KIND_INCOMPLETE_CLEANUP, text_bytes(message), false, ms_bytes_of(NULL, 0));
}

MS_NORETURN static void end_incomplete(const char *message) {
    incomplete_cleanup(message);
    ms_sys_exit_now(ms_fault_exit_status(MS_FAULT_KIND_INCOMPLETE_CLEANUP));
}

/* ---- stop requests: run on the stop thread ---- */

static void on_stop(int signal_number) {
    uint8_t first = 0;
    if (!atomic_compare_exchange_strong(&pending_signal, &first, (uint8_t)signal_number)) {
        end_incomplete("incomplete cleanup: a second stop request arrived before cleanup finished");
    }
    ms_sched_stop_remote((uint8_t)signal_number);
    ms_stop_hooks_run();
    ms_io_stop_arm(CLEANUP_GRACE_SECONDS);
}

static void on_grace_expired(void) {
    end_incomplete("incomplete cleanup: cleanup did not finish within 30s of the stop request");
}

/* ---- the scheduler's hooks for the main isolate ---- */

static void hook_fault(MsFaultKind kind, const char *message) { ms_fault(kind, text_bytes(message)); }

static void hook_exit(int status) { finish_process(status); }

/* A task started with MS_SPAWN_FATAL faulted: report it and end the process with the fault's status. */
static void hook_task_fault(const MsFaultText *message) {
    MsFaultText copy = ms_fault_text_clone(message);
    ms_fault_exit(&copy);
}

static int poll_watch(int fd, uint32_t events) { return (int)ms_io_watch(fd, events); }

static void poll_unwatch(int fd) { ms_io_unwatch(fd); }

static void poll_forget(int fd) { ms_io_forget(fd); }

static long poll_wait(int64_t timeout_ns, MsPollReady *out, size_t capacity) {
    size_t count = 0;
    if (!ms_io_wait(timeout_ns, (MsIoReady *)out, capacity, &count)) {
        return -1;
    }
    return (long)count;
}

static void wake_reactor(void *argument) { ms_io_wake(argument); }

/* ---- main ---- */

#ifdef MS_ALLOC_STATS
static uint64_t program_requested[2]; /* this thread's allocation counts when main returned */
#endif

static void main_task(void *argument) {
    (void)argument;
#ifdef MS_ALLOC_STATS
    msrt_heap_requested_reset();
#endif
    const int64_t value = main_function();
#ifdef MS_ALLOC_STATS
    ms_heap_requested_thread(program_requested);
#endif
    if (ms_cancel_flag() != 0) {
        ms_cancelled(); /* the main task's own boundary: nothing above it takes an exit */
    }
    if (value < 0 || value > MAX_MAIN_EXIT) {
        ms_fault(MS_FAULT_KIND_FAULT,
                 text_bytes("main exit code must be between 0 and 125; return 0 for success or a small positive Int for "
                            "failure (126 and above are reserved by shells)"));
    }
    main_result = value;
    /* A process that frees at exit also unwinds the tasks still parked, so what they own is released. */
    if (msrt_exit_frees() != 0) {
        ms_task_unwind_others();
    }
}

/* The fault handler of the runtime thread, on its alternate stack: ends the process for a stack overflow and
 * returns for any other fault, which then crashes as it would have without a handler. */
static void report_overflow(uintptr_t address) {
    if (ms_task_stack_overflow_at(address)) {
        ms_fault_fatal(MS_FAULT_KIND_STACK_OVERFLOW,
                       text_bytes("stack overflow: recursion too deep or stack frames too large"));
    }
}

#ifdef MS_ALLOC_STATS
/* Which size classes still hold blocks: a flaky leak names its blocks by size (0 is the large blocks). */
static void report_live_by_size(void) {
    enum { CLASSES = 64 };
    size_t sizes[CLASSES];
    int64_t counts[CLASSES];
    const size_t found = msrt_heap_live_by_size(sizes, counts, CLASSES);
    char line[SIZE_CLASS_LINE * 4];
    int length = snprintf(line, sizeof line, "ms-rt live blocks by size:");
    for (size_t i = 0; i < found && length > 0 && (size_t)length < sizeof line - SIZE_CLASS_LINE; i++) {
        if (sizes[i] == 0) {
            length += snprintf(line + length, sizeof line - (size_t)length, " large=%lld", (long long)counts[i]);
        } else {
            length += snprintf(line + length, sizeof line - (size_t)length, " %zuB=%lld", sizes[i], (long long)counts[i]);
        }
    }
    line[length++] = '\n';
    ms_sys_stderr_write(ms_bytes_of((const uint8_t *)line, (size_t)length));
}

/* The counting build: what is still live after the scheduler state was released. */
static void report_leaks(void) {
    char line[SIZE_CLASS_LINE];
    char park_text[8];
    size_t park_size = sizeof park_text;
    if (uv_os_getenv("MS_PARK_COUNT", park_text, &park_size) == 0) {
        const int parked = snprintf(line, sizeof line, "ms-rt parks: %llu\n", (unsigned long long)ms_sweep_parks());
        ms_sys_stderr_write(ms_bytes_of((const uint8_t *)line, (size_t)parked));
    }
    const int64_t live = msrt_heap_live_total();
    const int length = snprintf(line, sizeof line, "ms-rt live blocks at exit: %lld\n", (long long)live);
    ms_sys_stderr_write(ms_bytes_of((const uint8_t *)line, (size_t)length));
    if (live != 0) {
        report_live_by_size();
    }
    uint64_t requested[2] = {0};
    msrt_heap_requested(requested);
    uint64_t copies[4] = {0};
    msrt_copy_counts(copies);
    const int counted = snprintf(line, sizeof line,
                                 "ms-rt counts: allocs=%llu alloc_bytes=%llu list_copies=%llu list_copy_bytes=%llu "
                                 "string_clones=%llu string_clone_bytes=%llu\n",
                                 (unsigned long long)requested[0], (unsigned long long)requested[1],
                                 (unsigned long long)copies[0], (unsigned long long)copies[1],
                                 (unsigned long long)copies[2], (unsigned long long)copies[3]);
    ms_sys_stderr_write(ms_bytes_of((const uint8_t *)line, (size_t)counted));
}
#endif

static const MsPollOps poll_ops = {.watch = poll_watch, .unwatch = poll_unwatch, .forget = poll_forget, .wait = poll_wait};

/* Opens the calling thread's reactor and says how to poll and wake it. False when the reactor cannot open. */
MS_NODISCARD static bool open_poller(bool is_main, MsPollOps *poll, MsWakeFn *wake, void **wake_argument) {
    MsIoReactor *reactor = NULL;
    if (!ms_io_open(is_main, &reactor)) {
        return false;
    }
    ms_io_set_completion_sink(ms_sched_post_completion);
    *poll = poll_ops;
    *wake = wake_reactor;
    *wake_argument = reactor;
    return true;
}

/* The hooks of a scheduler of this process; `service` marks a worker. */
static MsSchedHooks scheduler_hooks(void) {
    MsSchedHooks hooks = {
        .fault = hook_fault,
        .exit_process = hook_exit,
        .flush_output = ms_sched_flush_stdout,
        .task_fault = hook_task_fault,
    };
    ms_promise_hooks(&hooks);
    return hooks;
}

/* The core count unless MS_THREADS says otherwise, within what the isolate registry holds. */
static uint32_t default_limit(void) {
    char text[ENV_TEXT_BYTES];
    size_t size = sizeof text;
    long wanted = 0;
    if (uv_os_getenv("MS_THREADS", text, &size) == 0) {
        wanted = strtol(text, NULL, 10);
    }
    if (wanted <= 0) {
        wanted = (long)uv_available_parallelism();
    }
    return wanted > (long)MS_MAX_ISOLATES ? MS_MAX_ISOLATES : (wanted < 1 ? 1 : (uint32_t)wanted);
}

void msrt_runtime_set_threads(int64_t threads) {
    ms_workers_set_limit(threads < 1 ? 1 : (threads > (int64_t)MS_MAX_ISOLATES ? MS_MAX_ISOLATES : (uint32_t)threads));
}

int64_t msrt_runtime_limit(void) { return ms_workers_limit(); }

static bool worker_setup(MsPollOps *poll, MsWakeFn *wake, void **wake_argument) {
    const bool overflow_reported = ms_sys_fault_handler_install(report_overflow);
    (void)overflow_reported;
    msrt_heap_claim();
    return open_poller(false, poll, wake, wake_argument);
}

static void worker_finish(void) {
    ms_io_close(false);
    msrt_heap_release();
}

/* Starts the worker isolates' configuration: the limit is the core count unless MS_THREADS says otherwise. */
static void configure_workers(void) {
    MsWorkerEnv env = {.limit = default_limit(), .hooks = scheduler_hooks(), .setup = worker_setup, .finish = worker_finish};
    ms_workers_configure(&env);
}

/* Opens this thread's reactor and scheduler for the main isolate. False when the reactor cannot open. */
MS_NODISCARD static bool open_scheduler(void) {
    MsPollOps poll = {0};
    MsWakeFn wake = NULL;
    void *wake_argument = NULL;
    if (!open_poller(true, &poll, &wake, &wake_argument)) {
        return false;
    }
    MsSchedHooks hooks = scheduler_hooks();
    ms_sched_set_hooks(&hooks, &poll);
    (void)ms_sched_attach(wake, wake_argument);
    return true;
}

/* Gives the calling thread a reactor and scheduler without starting a program: the Rust unit tests of ms-std-net run
 * their tasks this way. Once per thread; false when the reactor cannot open. */
bool ms_start_attach_thread(void) { return open_scheduler(); }

/* The runtime thread: runs main as the isolate's main task and ends the scheduler. */
static void runtime_thread(void *argument) {
    (void)argument;
    const bool overflow_reported = ms_sys_fault_handler_install(report_overflow); /* Windows reports false */
    (void)overflow_reported;
    msrt_heap_claim();
    ms_profile_attach_runtime_thread();
    if (!open_scheduler()) {
        ms_fault_fatal(MS_FAULT_KIND_FAULT, text_bytes("cannot open the event loop"));
    }
    ms_sched_set_stop_target();
    configure_workers();
    uint8_t outcome = 0;
    MsFaultText message = {0};
    if (ms_task_run_main(main_task, NULL, MS_SPAWN_FATAL, &outcome, &message) != MS_TASK_OK) {
        ms_fault_fatal(MS_FAULT_KIND_FAULT, text_bytes("cannot start the main task"));
    }
    ms_fault_text_free(&message);
    if (outcome == TASK_OUTCOME_CANCELLED) {
        /* A stop request unwound the main task through its guard: the program ends with the signal's status. */
        main_result = atomic_load(&pending_signal) == MS_STOP_INTERRUPT ? MS_EXIT_INTERRUPT : MS_EXIT_TERMINATE;
    }
    ms_workers_shutdown();
    ms_io_stop_end();
    ms_sched_clear_stop_target();
    ms_sched_teardown();
    ms_io_close(true);
    ms_sched_release_stdout();
#ifdef MS_ALLOC_STATS
    ms_heap_requested_restore(program_requested);
    report_leaks();
#endif
    msrt_heap_release();
}

int msrt_start(MsMainFn main_fn, const MsTables *tables, int argc, const char *const *argv) {
    const bool frames = ms_frames_install(tables); /* without them a report simply has no source frames */
    (void)frames;
    ms_entry_set_arguments(argc, argv);
    main_function = main_fn;
    start_nanos = ms_sys_monotonic_ns();
    if (!ms_io_stop_start(on_stop, on_grace_expired)) {
        ms_fault_fatal(MS_FAULT_KIND_FAULT, text_bytes("cannot watch for stop requests"));
    }
    ms_sys_ignore_broken_pipe();
    ms_profile_start();
    MsSysThread *const thread = ms_sys_thread_spawn(0, runtime_thread, NULL);
    if (thread == NULL) {
        ms_fault_fatal(MS_FAULT_KIND_FAULT, text_bytes("cannot start the main thread"));
    }
    ms_sys_thread_join(thread);
    ms_sched_flush_stdout();
    ms_process_run_exit_hooks();
    ms_profile_finish();
    const int status = (int)main_result;
    const int32_t lost = ms_sched_stdout_error();
    if (lost != 0 && status == 0) {
        /* Output the buffer could not deliver (a full disk, a closed descriptor): say so instead of exiting as if it
         * had been written. */
        char line[SIZE_CLASS_LINE];
        const int length = snprintf(line, sizeof line, "error: write to standard output: %s\n", strerror((int)lost));
        ms_sys_stderr_write(ms_bytes_of((const uint8_t *)line, (size_t)length));
        return 1;
    }
    return status;
}
