/* start.c: the process entry. msrt_start installs the program's tables, watches for stop requests, runs `main` as the
 * main isolate's main task on a thread of its own and returns the exit status.
 *
 * The thread exists so `main` runs on a task stack the runtime sizes, whatever the process's own stack limit is; the
 * thread's stack only hosts the scheduler. Stop requests (SIGINT, SIGTERM) arrive on the stop thread (io/stop.c), never
 * in a signal handler: the first raises the cancel flag of the running task and wakes the scheduler; a second before
 * cleanup finished, or the grace period running out, ends the process.
 */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "runtime/entry/entry.h"

#include <stdatomic.h>
#include <uv.h>

#include "base/alloc.h"
#include "base/env.h"
#include "runtime/core/alloc.h"
#include "runtime/core/cancel.h"
#include "runtime/core/fault.h"
#include "runtime/core/obj.h"
#include "runtime/core/promise.h"
#include "runtime/core/task.h"
#include "runtime/core/unwind.h"
#include "runtime/core/worker.h"
#include "runtime/io/reactor.h"
#include "runtime/io/stdout.h"
#include "runtime/io/stop.h"
#include "runtime/sys/sys.h"

enum {
  CLEANUP_GRACE_SECONDS = 30, /* after the first stop request, before cleanup is abandoned */
  MAX_MAIN_EXIT = 125,        /* 126 and above are reserved by shells */
  TASK_OUTCOME_CANCELLED = 2, /* ms_task_join's third outcome */
};

_Static_assert(sizeof(MsPollReady) == sizeof(MsIoReady), "the poller's ready entries are the reactor's");

static MsMainFn main_function;
static int64_t main_result;
static int64_t start_nanos;
static _Atomic uint8_t pending_signal; /* the first stop request, 0 until one arrives */

int64_t msrt_start_nanos(void) { return start_nanos; }

/* The value of environment variable `name` as a count: 0 when it is unset or not a number. */
static uint64_t environment_count(const char *name) {
  MsString value;
  if (!ms_env_get(name, &value)) {
    return 0;
  }
  const MsSpan text = ms_string_span(&value);
  uint64_t count = 0;
  for (size_t i = 0; i < text.len && text.ptr[i] >= '0' && text.ptr[i] <= '9' && count < UINT32_MAX; i++) {
    count = count * 10 + (uint64_t)(text.ptr[i] - '0');
  }
  ms_string_release(&value);
  return count;
}

/* Whether `main` frees the plain memory it still owns when it returns. The process exits next, so this is off unless
 * MS_FREE_AT_EXIT asks for it (valgrind). */
uint8_t msrt_exit_frees(void) {
  MsString value;
  if (!ms_env_get("MS_FREE_AT_EXIT", &value)) {
    return 0;
  }
  ms_string_release(&value);
  return 1;
}

/* ---- ending the process ---- */

/* Flushes output, runs the exit hooks and ends the process. */
MS_NORETURN static void finish_process(int status) {
  ms_stdout_flush();
  ms_process_run_exit_hooks();
  ms_sys_exit_now(status);
}

void msrt_process_exit(int64_t code) { finish_process((int)code); }

/* Reports a stop that cleanup did not survive, on standard error and in the fault record. */
MS_NORETURN static void end_incomplete(const char *message) {
  const MsSpan text = ms_span_of_text(message);
  ms_sys_stderr_write(text);
  ms_sys_stderr_write(ms_span_of_text("\n"));
  ms_fault_record_write(MS_FAULT_KIND_INCOMPLETE_CLEANUP, text, false, ms_span_of(NULL, 0));
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

static void hook_fault(MsFaultKind kind, const char *message) { ms_fault(kind, ms_span_of_text(message)); }

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

static void main_task(void *argument) {
  (void)argument;
  const int64_t value = main_function();
  if (ms_cancel_flag() != 0) {
    ms_cancelled(); /* the main task's own boundary: nothing above it takes an exit */
  }
  if (value < 0 || value > MAX_MAIN_EXIT) {
    ms_fault(MS_FAULT_KIND_FAULT,
             ms_span_of_text("main exit code must be between 0 and 125; return 0 for success or a small positive Int "
                             "for failure (126 and above are reserved by shells)"));
  }
  main_result = value;
  /* A process that frees at exit also unwinds the tasks still parked, so what they own is released. */
  if (msrt_exit_frees() != 0) {
    ms_task_unwind_others();
  }
}

/* The fault handler of the runtime thread, on its alternate stack: ends the process for a stack overflow and returns
 * for any other fault, which then crashes as it would have without a handler. */
static void report_overflow(uintptr_t address) {
  if (ms_task_stack_overflow_at(address)) {
    ms_fault_fatal(MS_FAULT_KIND_STACK_OVERFLOW,
                   ms_span_of_text("stack overflow: recursion too deep or stack frames too large"));
  }
}

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

/* The hooks of a scheduler of this process. */
static MsSchedHooks scheduler_hooks(void) {
  MsSchedHooks hooks = {
    .fault = hook_fault,
    .exit_process = hook_exit,
    .flush_output = ms_stdout_flush,
    .task_fault = hook_task_fault,
  };
  ms_promise_hooks(&hooks);
  return hooks;
}

/* The core count unless MS_THREADS says otherwise, within what the isolate registry holds. */
static uint32_t default_limit(void) {
  uint64_t wanted = environment_count("MS_THREADS");
  if (wanted == 0) {
    wanted = ms_sys_available_cores();
  }
  return wanted > MS_MAX_ISOLATES ? MS_MAX_ISOLATES : (uint32_t)wanted;
}

void msrt_runtime_set_threads(int64_t threads) {
  ms_workers_set_limit(threads < 1 ? 1 : (threads > (int64_t)MS_MAX_ISOLATES ? MS_MAX_ISOLATES : (uint32_t)threads));
}

int64_t msrt_runtime_limit(void) { return ms_workers_limit(); }

static bool worker_setup(MsPollOps *poll, MsWakeFn *wake, void **wake_argument) {
  (void)ms_sys_fault_handler_install(report_overflow);
  return open_poller(false, poll, wake, wake_argument);
}

static void worker_finish(void) { ms_io_close(false); }

/* Starts the worker isolates' configuration: the limit is the core count unless MS_THREADS says otherwise. */
static void configure_workers(void) {
  const MsWorkerEnv env = {.stress = environment_count("MS_SCHED_STRESS") != 0,
                           .limit = default_limit(),
                           .hooks = scheduler_hooks(),
                           .setup = worker_setup,
                           .finish = worker_finish};
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
  const MsSchedHooks hooks = scheduler_hooks();
  ms_sched_set_hooks(&hooks, &poll);
  (void)ms_sched_attach(wake, wake_argument);
  return true;
}

/* The runtime thread: runs main as the isolate's main task and ends the scheduler. */
static void runtime_thread(void *argument) {
  (void)argument;
  (void)ms_sys_fault_handler_install(report_overflow); /* Windows reports false */
  if (!open_scheduler()) {
    ms_fault_fatal(MS_FAULT_KIND_FAULT, ms_span_of_text("cannot open the event loop"));
  }
  ms_sched_set_stop_target();
  configure_workers();
  uint8_t outcome = 0;
  MsFaultText message = {0};
  if (ms_task_run_main(main_task, NULL, MS_SPAWN_FATAL, &outcome, &message) != MS_TASK_OK) {
    ms_fault_fatal(MS_FAULT_KIND_FAULT, ms_span_of_text("cannot start the main task"));
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
  ms_stdout_release();
}

int msrt_start(MsMainFn main_fn, const MsTables *tables, int argc, const char *const *argv) {
  ms_fault_install_base_hook();
  ms_obj_install_bounded_drop();
  ms_frames_install(tables); /* without them a report simply has no source frames */
  ms_entry_set_arguments(argc, argv);
  main_function = main_fn;
  start_nanos = ms_sys_monotonic_ns();
  if (!ms_io_stop_start(on_stop, on_grace_expired)) {
    ms_fault_fatal(MS_FAULT_KIND_FAULT, ms_span_of_text("cannot watch for stop requests"));
  }
  ms_sys_ignore_broken_pipe();
  MsSysThread *const thread = ms_sys_thread_spawn(0, runtime_thread, NULL);
  if (thread == NULL) {
    ms_fault_fatal(MS_FAULT_KIND_FAULT, ms_span_of_text("cannot start the main thread"));
  }
  ms_sys_thread_join(thread);
  ms_stdout_flush();
  ms_process_run_exit_hooks();
  const int status = (int)main_result;
  const int32_t lost = ms_stdout_error();
  if (lost != 0 && status == 0) {
    /* Output the buffer could not deliver (a full disk, a closed descriptor): say so instead of exiting as if it had
     * been written. */
    ms_sys_stderr_write(ms_span_of_text("error: write to standard output: "));
    ms_sys_stderr_write(ms_span_of_text(uv_strerror(uv_translate_sys_error(lost))));
    ms_sys_stderr_write(ms_span_of_text("\n"));
    return 1;
  }
  return status;
}
