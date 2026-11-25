/* A child process: starting it, its loop thread, signals, and peak memory (see child.h). libuv reports no resource usage
 * of a reaped child, so the peak resident set size is the largest sample taken while it ran, or the platform's bound
 * once it has exited (workaround, see #4780). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "runtime/std/child.h"

#include "base/alloc.h"
#include "runtime/core/isolate.h"
#include "runtime/core/task.h"
#include "runtime/std/run.h"

enum { SAMPLE_MS = 20 };

void ms_child_lock(MsChild *child) { uv_mutex_lock(&child->lock); }
void ms_child_unlock(MsChild *child) { uv_mutex_unlock(&child->lock); }

uint64_t ms_child_arm(MsChild *child) {
  const uint64_t token = ms_token_new(MS_TOKEN_REMOTE);
  ms_child_lock(child);
  child->token = token;
  ms_child_unlock(child);
  return token;
}

void ms_child_disarm(MsChild *child, uint64_t token) {
  ms_child_lock(child);
  child->token = 0;
  ms_child_unlock(child);
  (void)ms_token_free(token);
}

/* Wakes the waiting task, if any (any thread). */
static void ms_child_wake(MsChild *child) {
  ms_child_lock(child);
  if (child->token != 0) {
    ms_token_post_remote(child->token, 1);
  }
  ms_child_unlock(child);
}

/* ---- signals ---- */

void ms_child_signal(MsChild *child, bool force) {
  ms_child_lock(child);
  if (!child->exited && child->started) {
    ms_sys_group_signal(child->group, force);
  }
  ms_child_unlock(child);
}

int ms_child_send(MsChild *child, MsSysKill signal) {
  int code = 0;
  ms_child_lock(child);
  if (!child->exited && child->started) {
    code = ms_sys_group_kill_send(child->group, signal);
  }
  ms_child_unlock(child);
  return code;
}

void ms_child_kill_group(MsChild *child) {
  if (child->group != NULL) {
    ms_sys_group_kill(child->group);
  }
}

/* ---- the loop ---- */

static void sample_resident(MsChild *child) {
  const int64_t peak = ms_sys_group_peak_resident(child->group, false);
  ms_child_lock(child);
  if (peak > child->max_resident) {
    child->max_resident = peak;
  }
  ms_child_unlock(child);
}

static void on_sample(uv_timer_t *timer) { sample_resident(timer->data); }

void ms_child_progress(MsChild *child) {
  ms_child_lock(child);
  const bool exited = child->exited;
  ms_child_unlock(child);
  if (exited) {
    if (!uv_is_closing((uv_handle_t *)&child->sampler)) {
      uv_close((uv_handle_t *)&child->sampler, NULL);
    }
    if (child->run != NULL) {
      ms_run_progress(child);
    }
  }
  ms_child_wake(child);
}

static void on_exit(uv_process_t *process, int64_t status, int term_signal) {
  MsChild *child = process->data;
  ms_child_lock(child);
  child->exited = true;
  child->code = ms_sys_group_exit_code(child->group, status, term_signal);
  const int64_t peak = ms_sys_group_peak_resident(child->group, true);
  if (peak > child->max_resident) {
    child->max_resident = peak;
  }
  ms_child_unlock(child);
  uv_close((uv_handle_t *)process, NULL);
  ms_child_progress(child);
}

static void loop_thread(void *argument) {
  MsChild *child = argument;
  (void)uv_run(&child->loop, UV_RUN_DEFAULT);
  ms_child_lock(child);
  child->finished = true;
  ms_child_unlock(child);
  ms_child_wake(child);
}

/* ---- starting ---- */

void ms_child_close_descriptor(int fd) {
  if (fd >= 0) {
    uv_fs_t request;
    (void)uv_fs_close(NULL, &request, fd, NULL);
    uv_fs_req_cleanup(&request);
  }
}

/* A pipe pair for one standard stream: `parent` (opened with `parent_flags`) stays here, `child` goes to the process. */
static bool make_pipe(int stream, int parent_flags, int *parent, int *child) {
  int ends[2];
  const int read_flags = stream == MS_STREAM_IN ? 0 : parent_flags;
  const int write_flags = stream == MS_STREAM_IN ? parent_flags : 0;
  if (uv_pipe(ends, read_flags, write_flags) != 0) {
    return false;
  }
  *parent = stream == MS_STREAM_IN ? ends[1] : ends[0];
  *child = stream == MS_STREAM_IN ? ends[0] : ends[1];
  return true;
}

MsChild *ms_child_new(MsRun *run) {
  MsChild *child = ms_alloc_zeroed(sizeof *child);
  child->header.drop = ms_child_free;
  child->run = run;
  for (int stream = 0; stream < MS_STREAM_COUNT; stream++) {
    child->descriptors[stream] = -1;
    child->ids[stream] = -2;
  }
  if (uv_mutex_init(&child->lock) != 0) {
    ms_free(child);
    return NULL;
  }
  if (uv_loop_init(&child->loop) != 0) {
    uv_mutex_destroy(&child->lock);
    ms_free(child);
    return NULL;
  }
  child->loop_ready = true;
  return child;
}

bool ms_child_spawn(MsChild *child, const MsCommand *command, const int64_t modes[MS_STREAM_COUNT], int parent_flags,
                    int parent[MS_STREAM_COUNT], MsFail *fail) {
  uv_stdio_container_t stdio[MS_STREAM_COUNT];
  int theirs[MS_STREAM_COUNT] = {-1, -1, -1};
  for (int stream = 0; stream < MS_STREAM_COUNT && !ms_fail_failed(fail); stream++) {
    parent[stream] = -1;
    stdio[stream] = (uv_stdio_container_t){.flags = UV_IGNORE};
    if (modes[stream] == MS_STDIO_PIPE) {
      if (!make_pipe(stream, parent_flags, &parent[stream], &theirs[stream])) {
        ms_fail_text(fail, "pipe: system call failed");
      }
      stdio[stream] = (uv_stdio_container_t){.flags = UV_INHERIT_FD, .data.fd = theirs[stream]};
    } else if (modes[stream] == MS_STDIO_INHERIT) {
      stdio[stream] = (uv_stdio_container_t){.flags = UV_INHERIT_FD, .data.fd = stream};
    }
  }
  int error = ms_fail_failed(fail) ? UV_EINVAL : 0;
  if (error == 0) {
    uv_process_options_t options = {.exit_cb = on_exit,
                                    .file = command->program,
                                    .args = command->argv,
                                    .env = command->env,
                                    .cwd = command->cwd,
                                    .flags = UV_PROCESS_DETACHED,
                                    .stdio_count = MS_STREAM_COUNT,
                                    .stdio = stdio};
    error = uv_spawn(&child->loop, &child->process, &options);
    if (error != 0) {
      uv_close((uv_handle_t *)&child->process, NULL); /* initialised by the failed start */
      ms_command_start_failure(fail, error, command->program);
    }
  }
  for (int stream = 0; stream < MS_STREAM_COUNT; stream++) {
    ms_child_close_descriptor(theirs[stream]);
    if (error != 0) {
      ms_child_close_descriptor(parent[stream]);
      parent[stream] = -1;
    }
  }
  return error == 0;
}

bool ms_child_start_loop(MsChild *child) {
  child->pid = child->process.pid;
  child->process.data = child;
#ifdef _WIN32
  void *process_handle = child->process.process_handle;
#else
  void *process_handle = NULL;
#endif
  child->group = ms_sys_group_new(child->pid, process_handle);
  child->started = true;
  uv_timer_init(&child->loop, &child->sampler);
  child->sampler.data = child;
  sample_resident(child);
  uv_timer_start(&child->sampler, on_sample, SAMPLE_MS, SAMPLE_MS);
  return uv_thread_create(&child->thread, loop_thread, child) == 0;
}

void ms_child_join(MsChild *child) {
  if (child->loop_ready && child->started) {
    uv_thread_join(&child->thread);
    child->started = false;
  }
}

void ms_child_free(MsObj *object) {
  MsChild *child = (MsChild *)object;
  ms_child_kill_group(child);
  ms_child_signal(child, true);
  ms_child_join(child);
  for (int stream = 0; stream < MS_STREAM_COUNT; stream++) {
    ms_child_close_descriptor(child->descriptors[stream]);
  }
  ms_run_free(child->run);
  if (child->loop_ready) {
    (void)uv_run(&child->loop, UV_RUN_NOWAIT);
    (void)uv_loop_close(&child->loop);
  }
  uv_mutex_destroy(&child->lock);
  if (child->group != NULL) {
    ms_sys_group_free(child->group);
  }
  ms_free(child);
}
