/* Running a child program (see process.h), on libuv's process and file calls so every host takes the same code. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "base/process.h"

#include <uv.h>
#ifndef _WIN32
#include <unistd.h>
#endif

#include "base/alloc.h"
#include "base/env.h"
#include "base/fatal.h"
#include "base/file.h"
#include "base/ostext.h"
#include "base/path.h"

enum { LOG_MODE = 0600 };

enum { SUPERVISE_MS = 10, KILL_SIGNAL = 9 };

typedef struct Exit {
  int64_t status;
  int signal;
  uv_timer_t timer;
  const MsProcessSpec *spec;
  uv_process_t *process;
  bool supervised;
} Exit;

static void stop_timer(Exit *done) {
  if (done->supervised) {
    done->supervised = false;
    uv_timer_stop(&done->timer);
    uv_close((uv_handle_t *)&done->timer, NULL);
  }
}

static void on_exit(uv_process_t *process, int64_t status, int signal) {
  Exit *done = process->data;
  done->status = status;
  done->signal = signal;
  stop_timer(done);
  uv_close((uv_handle_t *)process, NULL);
}

static void on_tick(uv_timer_t *timer) {
  Exit *done = timer->data;
  if (done->spec->supervise(done->spec->supervise_context)) {
    stop_timer(done);
    (void)uv_process_kill(done->process, KILL_SIGNAL);
  }
}

/* The argument vector libuv takes: NUL-terminated copies and a NULL-ended pointer array. */
typedef struct Arguments {
  MsOsText *texts; /* owned */
  char **pointers; /* owned: NULL-terminated, into `texts` */
  size_t count;
} Arguments;

static Arguments arguments_new(const MsProcessSpec *spec) {
  size_t slots = 0;
  size_t text_bytes = 0;
  if (!ms_size_add(spec->argc, 1, &slots) || !ms_size_mul(spec->argc, sizeof(MsOsText), &text_bytes) ||
      !ms_size_mul(slots, sizeof(char *), &slots)) {
    ms_fatal(MS_FATAL_OVERFLOW, "argument count");
  }
  Arguments arguments = {.texts = ms_alloc(text_bytes), .pointers = ms_alloc(slots), .count = spec->argc};
  for (size_t index = 0; index < spec->argc; index++) {
    arguments.texts[index] = ms_os_text_new(spec->argv[index]);
    arguments.pointers[index] = arguments.texts[index].ptr;
  }
  arguments.pointers[spec->argc] = NULL;
  return arguments;
}

static void arguments_free(Arguments *arguments) {
  for (size_t index = 0; index < arguments->count; index++) {
    ms_os_text_free(&arguments->texts[index]);
  }
  ms_free(arguments->texts);
  ms_free(arguments->pointers);
}

/* The child's environment: the inherited one with the spec's NAME=VALUE texts set. NULL (inherit) when there are none. */
typedef struct Environment {
  uv_env_item_t *items; /* the inherited variables, from libuv */
  int count;
  MsOsText *texts;      /* owned: the spec's own variables */
  char **pointers;      /* owned: NULL-terminated */
  char **joined;        /* owned strings for the inherited variables */
  size_t joined_count;
} Environment;

static bool overridden(const MsProcessSpec *spec, const char *name) {
  for (size_t i = 0; i < spec->envc; i++) {
    size_t length = 0;
    while (name[length] != 0 && name[length] != '=') {
      length++;
    }
    if (spec->env[i].len > length && spec->env[i].ptr[length] == '=' &&
        __builtin_strncmp((const char *)spec->env[i].ptr, name, length) == 0) {
      return true;
    }
  }
  return false;
}

static bool environment_new(const MsProcessSpec *spec, Environment *environment) {
  *environment = (Environment){0};
  if (spec->envc == 0) {
    return true;
  }
  if (uv_os_environ(&environment->items, &environment->count) < 0) {
    return false;
  }
  const size_t slots = (size_t)environment->count + spec->envc + 1;
  environment->pointers = ms_alloc(slots * sizeof(char *));
  environment->joined = ms_alloc(((size_t)environment->count + 1) * sizeof(char *));
  size_t used = 0;
  for (int i = 0; i < environment->count; i++) {
    const size_t name = __builtin_strlen(environment->items[i].name);
    const size_t value = __builtin_strlen(environment->items[i].value);
    char *entry = ms_alloc(name + value + 2);
    __builtin_memcpy(entry, environment->items[i].name, name);
    entry[name] = '=';
    __builtin_memcpy(entry + name + 1, environment->items[i].value, value + 1);
    environment->joined[environment->joined_count++] = entry;
    if (!overridden(spec, entry)) {
      environment->pointers[used++] = entry;
    }
  }
  environment->texts = ms_alloc(spec->envc * sizeof(MsOsText));
  for (size_t i = 0; i < spec->envc; i++) {
    environment->texts[i] = ms_os_text_new(spec->env[i]);
    environment->pointers[used++] = environment->texts[i].ptr;
  }
  environment->pointers[used] = NULL;
  return true;
}

static void environment_free(Environment *environment, size_t envc) {
  for (size_t i = 0; i < envc && environment->texts != NULL; i++) {
    ms_os_text_free(&environment->texts[i]);
  }
  for (size_t i = 0; i < environment->joined_count; i++) {
    ms_free(environment->joined[i]);
  }
  ms_free(environment->texts);
  ms_free(environment->pointers);
  ms_free(environment->joined);
  if (environment->items != NULL) {
    uv_os_free_environ(environment->items, environment->count);
  }
}

static void fail_with(int code, MsStrBuild *error) { ms_strbuild_append_text(error, uv_strerror(code)); }

/* `what path: reason`, so a missing tool or file names itself. */
static void fail_at(const char *what, MsSpan path, int code, MsStrBuild *error) {
  ms_strbuild_append_text(error, what);
  ms_strbuild_append_byte(error, ' ');
  ms_strbuild_append(error, path);
  ms_strbuild_append_text(error, ": ");
  fail_with(code, error);
}

/* Starts the program with the log as its output and waits for it; false with `error` set when it cannot run. */
static bool spawn_and_wait(const MsProcessSpec *spec, const int fds[2], int *exit_status, MsStrBuild *error) {
  uv_loop_t loop;
  int code = uv_loop_init(&loop);
  if (code < 0) {
    fail_with(code, error);
    return false;
  }
  Arguments arguments = arguments_new(spec);
  MsOsText directory = ms_os_text_new(spec->directory);
  uv_stdio_container_t stdio[3] = {{.flags = spec->inherit ? UV_INHERIT_FD : UV_IGNORE, .data.fd = 0},
                                   {.flags = UV_INHERIT_FD, .data.fd = spec->inherit ? 1 : fds[0]},
                                   {.flags = UV_INHERIT_FD, .data.fd = spec->inherit || spec->inherit_error ? 2 : fds[1]}};
  Exit done = {.status = -1, .signal = 0, .spec = spec};
  uv_process_t process = {.data = &done};
  done.process = &process;
  Environment environment;
  if (!environment_new(spec, &environment)) {
    fail_with(UV_ENOMEM, error);
    arguments_free(&arguments);
    ms_os_text_free(&directory);
    (void)uv_loop_close(&loop);
    return false;
  }
  const uv_process_options_t options = {.exit_cb = on_exit,
                                        .file = arguments.pointers[0],
                                        .args = arguments.pointers,
                                        .env = environment.pointers,
                                        .cwd = spec->directory.len == 0 ? NULL : directory.ptr,
                                        .flags = UV_PROCESS_WINDOWS_HIDE,
                                        .stdio_count = 3,
                                        .stdio = stdio};
  code = uv_spawn(&loop, &process, &options);
  if (code < 0) {
    fail_at("start", ms_span_of_text(options.file), code, error);
    /* A failed spawn leaves the process handle on the loop, and with it the SIGCHLD watcher in libuv's process-wide
     * signal tree. Closing the handle lets the loop close; a loop left open keeps a watcher whose memory is this frame,
     * and the next signal handled or registered by any thread walks freed stack. */
    uv_close((uv_handle_t *)&process, NULL);
    (void)uv_run(&loop, UV_RUN_DEFAULT);
  } else {
    if (spec->supervise != NULL && uv_timer_init(&loop, &done.timer) == 0) {
      done.supervised = true;
      done.timer.data = &done;
      (void)uv_timer_start(&done.timer, on_tick, SUPERVISE_MS, SUPERVISE_MS);
    }
    (void)uv_run(&loop, UV_RUN_DEFAULT);
    *exit_status = done.signal != 0 ? (spec->inherit ? 128 + done.signal : -1) : (int)done.status;
  }
  ms_os_text_free(&directory);
  arguments_free(&arguments);
  environment_free(&environment, spec->envc);
  (void)uv_loop_close(&loop);
  return code >= 0;
}

static int open_log(MsSpan path) {
  MsOsText log = ms_os_text_new(path);
  uv_fs_t request;
  const int fd = uv_fs_open(NULL, &request, log.ptr, UV_FS_O_WRONLY | UV_FS_O_CREAT | UV_FS_O_TRUNC, LOG_MODE, NULL);
  uv_fs_req_cleanup(&request);
  ms_os_text_free(&log);
  return fd;
}

static void close_log(int fd) {
  uv_fs_t request;
  (void)uv_fs_close(NULL, &request, fd, NULL);
  uv_fs_req_cleanup(&request);
}

bool ms_process_run(const MsProcessSpec *spec, int *exit_status, MsStrBuild *error) {
  int fds[2] = {-1, -1};
  if (!spec->inherit) {
    fds[0] = open_log(spec->log_path);
    fds[1] = spec->inherit_error ? -1 : (spec->error_path.len > 0 && fds[0] >= 0 ? open_log(spec->error_path) : fds[0]);
    if (fds[0] < 0 || (fds[1] < 0 && !spec->inherit_error)) {
      fail_at("open", fds[0] < 0 ? spec->log_path : spec->error_path, fds[0] < 0 ? fds[0] : fds[1], error);
      if (fds[0] >= 0) {
        close_log(fds[0]);
      }
      return false;
    }
  }
  const bool ok = spawn_and_wait(spec, fds, exit_status, error);
  if (!spec->inherit) {
    close_log(fds[0]);
    if (fds[1] >= 0 && fds[1] != fds[0]) {
      close_log(fds[1]);
    }
  }
  return ok;
}

/* Whether `directory`/`name` is an executable file; libuv has no PATH lookup, so the caller walks the directories. */
static bool executable_in(MsSpan directory, MsSpan name) {
  MsStrBuild candidate = ms_strbuild_new();
  ms_strbuild_append(&candidate, directory.len == 0 ? ms_span_of_text(".") : directory);
  ms_strbuild_append_byte(&candidate, '/');
  ms_strbuild_append(&candidate, name);
#ifdef _WIN32
  ms_strbuild_append_text(&candidate, ".exe");
#endif
  MsOsText text = ms_os_text_new(ms_strbuild_span(&candidate));
  uv_fs_t request;
  const bool found = uv_fs_access(NULL, &request, text.ptr, X_OK, NULL) == 0;
  uv_fs_req_cleanup(&request);
  ms_os_text_free(&text);
  ms_strbuild_free(&candidate);
  return found;
}

bool ms_process_find(MsSpan name) {
#ifdef _WIN32
  const uint8_t separator = ';';
#else
  const uint8_t separator = ':';
#endif
  MsString path = ms_string_empty();
  bool found = false;
  if (name.len != 0 && ms_env_get("PATH", &path)) {
    MsSpan rest = ms_string_span(&path);
    while (!found) {
      size_t end = 0;
      while (end < rest.len && rest.ptr[end] != separator) {
        end++;
      }
      found = executable_in(ms_span_of(rest.ptr, end), name);
      if (end >= rest.len) {
        break;
      }
      rest = ms_span_of(rest.ptr + end + 1, rest.len - end - 1);
    }
  }
  ms_string_release(&path);
  return found;
}

static void append_trimmed_log(MsSpan log_path, MsStrBuild *out) {
  MsBytes text = {0};
  if (!ms_file_read(log_path, &text)) {
    return;
  }
  size_t end = text.len;
  while (end > 0 && (text.ptr[end - 1] == '\n' || text.ptr[end - 1] == '\r' || text.ptr[end - 1] == ' ')) {
    end--;
  }
  ms_strbuild_append(out, ms_span_of(text.ptr, end));
  ms_bytes_free(&text);
}

bool ms_process_run_logged(MsSpan what, const MsProcessSpec *spec, MsStrBuild *why) {
  int status = 0;
  MsStrBuild reason = ms_strbuild_new();
  if (!ms_process_run(spec, &status, &reason)) {
    ms_strbuild_append_text(why, "cannot run ");
    ms_strbuild_append(why, what);
    ms_strbuild_append_text(why, ": ");
    ms_strbuild_append(why, ms_strbuild_span(&reason));
    ms_strbuild_free(&reason);
    return false;
  }
  ms_strbuild_free(&reason);
  if (status == 0) {
    return true;
  }
  ms_strbuild_append(why, what);
  ms_strbuild_append_text(why, " failed: ");
  append_trimmed_log(spec->log_path, why);
  return false;
}

bool ms_process_executable(MsString *out) {
  char buffer[4096];
  size_t size = sizeof buffer;
  if (uv_exepath(buffer, &size) != 0) {
    return false;
  }
  ms_path_from_os(buffer, size);
  ms_string_release(out);
  *out = ms_string_from_span(ms_span_of((const uint8_t *)buffer, size));
  return true;
}
