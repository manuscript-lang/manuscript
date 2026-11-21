/* `spawn`, the Subprocess natives and `replace` for @std/process (see spawn.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "runtime/std/spawn.h"

#include "base/strbuild.h"
#include "runtime/core/task.h"
#include "runtime/std/child.h"
#include "runtime/std/streams.h"

/* The flags of the parent end of a stream's pipe when a task reads or writes it. The runtime polls a POSIX descriptor, so
 * it is non-blocking; a Windows end is a blocking handle, because an overlapped one belongs to the one loop that
 * registered it and a task can run on any thread. */
#ifdef _WIN32
enum { TASK_PARENT_FLAGS = 0 };
#else
enum { TASK_PARENT_FLAGS = UV_NONBLOCK_PIPE };
#endif

uint8_t msstd_process_command_spawn(const MsString *program, const MsList *arguments, int64_t stdin_mode,
                                    int64_t stdout_mode, int64_t stderr_mode, uint8_t has_cwd, const MsString *cwd,
                                    const MsList *env_names, const MsList *env_values, MsObj **out, MsString *err) {
  MsFail fail = ms_fail_new();
  MsCommand command = {0};
  const int64_t modes[MS_STREAM_COUNT] = {stdin_mode, stdout_mode, stderr_mode};
  int parent[MS_STREAM_COUNT] = {-1, -1, -1};
  if (ms_command_build(&command, program, arguments, has_cwd != 0, cwd, env_names, env_values, true, &fail)) {
    MsChild *child = ms_child_new(NULL);
    if (child == NULL) {
      ms_fail_text(&fail, "cannot start the process");
    } else if (ms_child_spawn(child, &command, modes, TASK_PARENT_FLAGS, parent, &fail) && ms_child_start_loop(child)) {
      __builtin_memcpy(child->descriptors, parent, sizeof parent);
      *out = &child->header;
    } else {
      if (!ms_fail_failed(&fail)) {
        ms_fail_text(&fail, "cannot start the process thread");
      }
      child->started = false; /* nothing to join */
      ms_child_free(&child->header);
    }
  }
  ms_command_free(&command);
  return ms_command_finish(&fail, program, has_cwd != 0 ? cwd : NULL, err);
}

int64_t msstd_process_subprocess_stream_id(MsObj *handle, int64_t which) {
  MsChild *child = (MsChild *)handle;
  const int stream = which < 0 ? 0 : which >= MS_STREAM_COUNT ? MS_STREAM_COUNT - 1 : (int)which;
  if (child->ids[stream] == -2) {
    const int fd = child->descriptors[stream];
    const int64_t access = stream == MS_STREAM_IN ? MS_STREAMS_WRITES : MS_STREAMS_READS;
    child->descriptors[stream] = -1;
    child->ids[stream] = fd < 0 ? -1 : msrt_streams_open(fd, MS_STREAMS_OWNS | MS_STREAMS_NONBLOCK | access);
  }
  return child->ids[stream];
}

int64_t msstd_process_subprocess_max_resident(MsObj *handle) {
  MsChild *child = (MsChild *)handle;
  ms_child_lock(child);
  const int64_t peak = child->exited ? child->max_resident : 0;
  ms_child_unlock(child);
  return peak;
}

void msstd_process_subprocess_terminate(MsObj *handle) { ms_child_signal((MsChild *)handle, false); }

void msstd_process_subprocess_kill(MsObj *handle) { ms_child_signal((MsChild *)handle, true); }

void msstd_process_subprocess_close(MsObj *handle) {
  MsChild *child = (MsChild *)handle;
  if (child->stopped) {
    return;
  }
  child->stopped = true;
  ms_child_signal(child, true);
  ms_child_join(child);
  ms_child_kill_group(child);
  for (int stream = 0; stream < MS_STREAM_COUNT; stream++) {
    ms_child_close_descriptor(child->descriptors[stream]);
    child->descriptors[stream] = -1;
  }
}

uint8_t msstd_process_subprocess_wait(MsObj *handle, uint8_t has_timeout, int64_t timeout_ns, int64_t *out,
                                      MsString *err) {
  MsChild *child = (MsChild *)handle;
  MsFail fail = ms_fail_new();
  if (has_timeout != 0 && timeout_ns < 0) {
    ms_fail_status(&fail, MS_STATUS_INVALID_INPUT);
    return ms_fail_finish(&fail, err);
  }
  const int64_t deadline = has_timeout != 0 ? (int64_t)uv_hrtime() + timeout_ns : -1;
  for (;;) {
    const uint64_t token = ms_child_arm(child);
    ms_child_lock(child);
    const bool exited = child->exited;
    const int64_t code = child->code;
    ms_child_unlock(child);
    const int64_t left = deadline >= 0 ? deadline - (int64_t)uv_hrtime() : -1;
    uint32_t result = 0;
    if (!exited && (deadline < 0 || left > 0)) {
      uint64_t value = 0;
      (void)ms_token_park(token, left, &value, &result);
    }
    ms_child_disarm(child, token);
    if (exited) {
      *out = code;
      return ms_fail_finish(&fail, err);
    }
    if ((result & MS_WAIT_CANCELLED) != 0) {
      ms_fail_text(&fail, "cancelled");
      return ms_fail_finish(&fail, err);
    }
    if (deadline >= 0 && left <= 0) {
      ms_fail_status(&fail, MS_STATUS_TIMED_OUT);
      return ms_fail_finish(&fail, err);
    }
  }
}

uint8_t msstd_process_replace(const MsString *program, const MsList *arguments, const MsList *env_names,
                              const MsList *env_values, MsString *err) {
  MsFail fail = ms_fail_new();
  MsCommand command = {0};
  if (arguments->len == 0) {
    ms_fail_status(&fail, MS_STATUS_INVALID_INPUT);
  } else if (ms_command_build(&command, program, arguments, false, NULL, env_names, env_values, false, &fail)) {
    const int error = ms_sys_process_exec(command.program, command.argv, command.env);
    if (error == UV_ENOTSUP) {
      ms_fail_status(&fail, MS_STATUS_UNSUPPORTED);
    } else {
      ms_command_start_failure(&fail, error, command.program);
    }
    if (fail.status == MS_STATUS_FAILED) {
      ms_fail_free(&fail);
      MsStrBuild text = ms_strbuild_new();
      ms_strbuild_append_text(&text, "exec ");
      ms_strbuild_append_text(&text, command.program);
      ms_strbuild_append_text(&text, ": ");
      ms_strbuild_append_text(&text, uv_strerror(error));
      fail.status = MS_STATUS_FAILED;
      fail.message = ms_strbuild_finish(&text);
    }
  }
  ms_command_free(&command);
  return ms_fail_finish(&fail, err);
}
