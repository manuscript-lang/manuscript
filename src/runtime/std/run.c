/* `run` for @std/process (see run.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "runtime/std/run.h"

#include "base/alloc.h"
#include "runtime/core/task.h"
#include "runtime/std/fs_job.h"

enum { CHUNK_BYTES = 64 * 1024, EXIT_DELAY_MS = 1000 };

MS_LIST_DEFINE(ByteBuffer, byte_buffer, uint8_t)

/* Owned by the child; touched by the loop thread only until the child is done. */
struct MsRun {
  uv_pipe_t pipes[MS_STREAM_COUNT];
  bool open[MS_STREAM_COUNT];
  uv_write_t write;
  uv_timer_t deadline;
  uv_timer_t delay;
  uint8_t *input;
  size_t input_length;
  ByteBuffer output[2];
  int64_t remaining;
  int64_t timeout_ns; /* negative: none */
  bool overflow, timed_out, kept_open;
};

static const char output_kept_open[] =
    "the command finished but a background process kept its output open; close or redirect its output, or set a timeout";

/* The collection for a run: `input` is copied; `limit` bounds the output bytes; a negative `timeout_ns` is none. */
static MsRun *ms_run_new(const MsList *input, int64_t limit, int64_t timeout_ns) {
  MsRun *run = ms_alloc_zeroed(sizeof *run);
  run->remaining = limit;
  run->timeout_ns = timeout_ns;
  run->input_length = input->len;
  if (input->len != 0) {
    run->input = ms_alloc(input->len);
    __builtin_memcpy(run->input, input->ptr, input->len);
  }
  return run;
}

void ms_run_free(MsRun *run) {
  if (run != NULL) {
    byte_buffer_free(&run->output[0]);
    byte_buffer_free(&run->output[1]);
    ms_free(run->input);
    ms_free(run);
  }
}

/* ---- the loop's half ---- */

static void close_once(uv_handle_t *handle) {
  if (!uv_is_closing(handle)) {
    uv_close(handle, NULL);
  }
}

static void close_pipe(MsRun *run, int stream) {
  if (run->open[stream]) {
    run->open[stream] = false;
    close_once((uv_handle_t *)&run->pipes[stream]);
  }
}

/* Closes every handle that is still open; the loop then has nothing left and ends. */
static void close_all(MsRun *run) {
  close_once((uv_handle_t *)&run->deadline);
  close_once((uv_handle_t *)&run->delay);
  for (int stream = 0; stream < MS_STREAM_COUNT; stream++) {
    close_pipe(run, stream);
  }
}

static void on_delay(uv_timer_t *timer) {
  MsChild *child = timer->data;
  child->run->kept_open = true;
  close_all(child->run);
  ms_child_progress(child);
}

/* A run is complete once the child has exited and its output pipes are closed. When only the exit is in, the pipes get a
 * second more before the output counts as kept open by a background process. */
void ms_run_progress(MsChild *child) {
  MsRun *run = child->run;
  if (!run->open[MS_STREAM_OUT] && !run->open[MS_STREAM_ERR]) {
    close_all(run);
  } else if (!uv_is_active((uv_handle_t *)&run->delay) && !uv_is_closing((uv_handle_t *)&run->delay)) {
    uv_timer_start(&run->delay, on_delay, EXIT_DELAY_MS, 0);
  }
}

static void on_deadline(uv_timer_t *timer) {
  MsChild *child = timer->data;
  child->run->timed_out = true;
  ms_child_kill_group(child);
}

static void on_alloc(uv_handle_t *handle, size_t suggested, uv_buf_t *buffer) {
  (void)handle;
  (void)suggested;
  *buffer = uv_buf_init(ms_alloc(CHUNK_BYTES), CHUNK_BYTES);
}

static void on_read(uv_stream_t *stream, ssize_t count, const uv_buf_t *buffer) {
  MsChild *child = stream->data;
  MsRun *run = child->run;
  const int which = stream == (uv_stream_t *)&run->pipes[MS_STREAM_ERR] ? MS_STREAM_ERR : MS_STREAM_OUT;
  if (count > 0) {
    const size_t accepted = (int64_t)count > run->remaining ? (size_t)run->remaining : (size_t)count;
    __builtin_memcpy(byte_buffer_extend(&run->output[which - 1], accepted), buffer->base, accepted);
    run->remaining -= (int64_t)accepted;
    if (accepted != (size_t)count) {
      run->overflow = true;
      ms_child_kill_group(child);
      uv_read_stop(stream);
    }
  } else if (count < 0) {
    close_pipe(run, which);
  }
  ms_free(buffer->base);
  if (count < 0 || run->overflow) {
    ms_child_progress(child);
  }
}

static void on_written(uv_write_t *request, int status) {
  (void)status; /* a child that closed its input early drops the rest */
  MsChild *child = request->data;
  close_pipe(child->run, MS_STREAM_IN);
}

/* Opens the parent ends of the pipes on the child's loop and starts reading, writing and timing. Runs before the loop
 * thread starts. */
static bool ms_run_attach(MsChild *child, const int descriptors[MS_STREAM_COUNT]) {
  MsRun *run = child->run;
  for (int stream = 0; stream < MS_STREAM_COUNT; stream++) {
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
    close_pipe(run, MS_STREAM_IN);
  } else {
    const uv_buf_t input = uv_buf_init((char *)run->input, (unsigned)run->input_length);
    if (uv_write(&run->write, (uv_stream_t *)&run->pipes[MS_STREAM_IN], &input, 1, on_written) != 0) {
      close_pipe(run, MS_STREAM_IN);
    }
  }
  uv_read_start((uv_stream_t *)&run->pipes[MS_STREAM_OUT], on_alloc, on_read);
  uv_read_start((uv_stream_t *)&run->pipes[MS_STREAM_ERR], on_alloc, on_read);
  if (run->timeout_ns >= 0) {
    uv_timer_start(&run->deadline, on_deadline, (uint64_t)(run->timeout_ns / 1000000), 0);
  }
  return true;
}

/* ---- the task's half ---- */

/* Waits for the loop thread to end. A stop request kills the child, waits for the loop and fails the call. */
static bool ms_run_wait(MsChild *child, MsFail *fail) {
  for (;;) {
    const uint64_t token = ms_child_arm(child);
    ms_child_lock(child);
    const bool finished = child->finished;
    ms_child_unlock(child);
    uint32_t result = 0;
    if (!finished) {
      uint64_t value = 0;
      (void)ms_token_park(token, -1, &value, &result);
    }
    ms_child_disarm(child, token);
    if (finished) {
      ms_child_join(child);
      return true;
    }
    if ((result & MS_WAIT_CANCELLED) != 0) {
      ms_child_kill_group(child);
      ms_child_signal(child, true);
      ms_child_join(child);
      ms_fail_text(fail, "cancelled");
      return false;
    }
  }
}

/* The result of a finished run: its status, and the output on success. */
static uint8_t ms_run_result(MsChild *child, MsCommandOut *out, MsFail *fail) {
  MsRun *run = child->run;
  if (run->overflow) {
    ms_fail_status(fail, MS_STATUS_OUTPUT_LIMIT);
  } else if (run->timed_out) {
    ms_fail_status(fail, MS_STATUS_TIMED_OUT);
  } else if (run->kept_open && child->code == 0) {
    ms_fail_text(fail, output_kept_open);
  } else {
    out->exit_code = child->code;
    out->out = (MsBytes){.ptr = run->output[0].ptr, .len = run->output[0].len, .cap = run->output[0].cap};
    out->err = (MsBytes){.ptr = run->output[1].ptr, .len = run->output[1].len, .cap = run->output[1].cap};
    run->output[0] = (ByteBuffer){0}; /* the result owns them now */
    run->output[1] = (ByteBuffer){0};
    out->max_resident_bytes = child->max_resident;
  }
  return fail->status;
}

uint8_t msstd_process_command_run(const MsString *program, const MsList *arguments, const MsList *input, uint8_t has_max,
                                  int64_t max, uint8_t has_timeout, int64_t timeout_ns, uint8_t has_cwd,
                                  const MsString *cwd, const MsList *env_names, const MsList *env_values,
                                  MsCommandOut *out, MsString *err) {
  MsFail fail = ms_fail_new();
  MsCommand command = {0};
  int64_t limit = 0;
  if (!ms_fs_limit(has_max, max, &limit) || (has_timeout != 0 && timeout_ns < 0)) {
    ms_fail_status(&fail, MS_STATUS_INVALID_INPUT);
  } else if (ms_command_build(&command, program, arguments, has_cwd != 0, cwd, env_names, env_values, true, &fail)) {
    MsRun *run = ms_run_new(input, limit, has_timeout != 0 ? timeout_ns : -1);
    MsChild *child = ms_child_new(run);
    int parent[MS_STREAM_COUNT] = {-1, -1, -1};
    const int64_t modes[MS_STREAM_COUNT] = {MS_STDIO_PIPE, MS_STDIO_PIPE, MS_STDIO_PIPE};
    if (child == NULL) {
      ms_run_free(run);
      ms_fail_text(&fail, "cannot start the process");
    } else if (!ms_child_spawn(child, &command, modes, UV_NONBLOCK_PIPE, parent, &fail)) {
      ms_child_free(&child->header);
    } else if (!ms_run_attach(child, parent) || !ms_child_start_loop(child)) {
      ms_fail_text(&fail, "cannot start the process thread");
      ms_child_free(&child->header);
    } else {
      if (ms_run_wait(child, &fail)) {
        (void)ms_run_result(child, out, &fail);
      }
      ms_child_free(&child->header);
    }
  }
  ms_command_free(&command);
  return ms_command_finish(&fail, program, has_cwd != 0 ? cwd : NULL, err);
}
