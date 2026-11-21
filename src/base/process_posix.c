/* Running a child program on POSIX hosts (see process.h). */
#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#if defined(__APPLE__)
#define _DARWIN_C_SOURCE
#endif
#include <errno.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include "base/alloc.h"
#include "base/env.h"
#include "base/fatal.h"
#include "base/ostext.h"
#include "base/process.h"

enum { LOG_MODE = 0600, CHILD_FAILED = 127 };

typedef struct Command {
  MsOsText *texts;  /* owned: one NUL-terminated copy per argument */
  char **pointers;  /* owned: NULL-terminated argument vector into `texts` */
  size_t count;
} Command;

static Command command_new(const MsProcessSpec *spec) {
  size_t slots = 0;
  size_t text_bytes = 0;
  if (!ms_size_add(spec->argc, 1, &slots) || !ms_size_mul(spec->argc, sizeof(MsOsText), &text_bytes) ||
      !ms_size_mul(slots, sizeof(char *), &slots)) {
    ms_fatal(MS_FATAL_OVERFLOW, "argument count");
  }
  Command command = {.texts = ms_alloc(text_bytes), .pointers = ms_alloc(slots), .count = spec->argc};
  for (size_t index = 0; index < spec->argc; index++) {
    command.texts[index] = ms_os_text_new(spec->argv[index]);
    command.pointers[index] = command.texts[index].ptr;
  }
  command.pointers[spec->argc] = NULL;
  return command;
}

static void command_free(Command *command) {
  for (size_t index = 0; index < command->count; index++) {
    ms_os_text_free(&command->texts[index]);
  }
  ms_free(command->texts);
  ms_free(command->pointers);
}

/* Runs in the child between fork and exec: only calls that are safe there. */
static void exec_child(const Command *command, const char *directory, const char *log) {
  int input = open("/dev/null", O_RDONLY);
  int output = open(log, O_WRONLY | O_CREAT | O_TRUNC, LOG_MODE);
  bool ready = input >= 0 && output >= 0 && dup2(input, STDIN_FILENO) >= 0 &&
               dup2(output, STDOUT_FILENO) >= 0 && dup2(output, STDERR_FILENO) >= 0 &&
               (directory == NULL || chdir(directory) == 0);
  if (ready) {
    (void)execvp(command->pointers[0], command->pointers);
  }
  _exit(CHILD_FAILED);
}

static bool wait_for(pid_t child, int *exit_status) {
  int status = 0;
  while (waitpid(child, &status, 0) < 0) {
    if (errno != EINTR) {
      return false;
    }
  }
  *exit_status = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
  return true;
}

bool ms_process_run(const MsProcessSpec *spec, int *exit_status, MsStrBuild *error) {
  Command command = command_new(spec);
  MsOsText log = ms_os_text_new(spec->log_path);
  MsOsText directory = ms_os_text_new(spec->directory);
  pid_t child = fork();
  if (child == 0) {
    exec_child(&command, spec->directory.len == 0 ? NULL : directory.ptr, log.ptr);
  }
  int fork_error = errno;
  ms_os_text_free(&log);
  ms_os_text_free(&directory);
  command_free(&command);
  if (child < 0) {
    ms_os_error_text(fork_error, error);
    return false;
  }
  if (!wait_for(child, exit_status)) {
    ms_os_error_text(errno, error);
    return false;
  }
  if (*exit_status == CHILD_FAILED) {
    ms_strbuild_append_text(error, "the program could not be started");
    return false;
  }
  return true;
}

bool ms_process_find(MsSpan name) {
  MsString path = ms_string_empty();
  bool found = false;
  if (name.len != 0 && ms_env_get("PATH", &path)) {
    MsSpan rest = ms_string_span(&path);
    while (!found) {
      size_t end = 0;
      while (end < rest.len && rest.ptr[end] != ':') {
        end++;
      }
      MsStrBuild candidate = ms_strbuild_new();
      ms_strbuild_append(&candidate, end == 0 ? ms_span_of_text(".") : ms_span_of(rest.ptr, end));
      ms_strbuild_append_byte(&candidate, '/');
      ms_strbuild_append(&candidate, name);
      MsOsText text = ms_os_text_new(ms_strbuild_span(&candidate));
      found = access(text.ptr, X_OK) == 0;
      ms_os_text_free(&text);
      ms_strbuild_free(&candidate);
      if (end >= rest.len) {
        break;
      }
      rest = ms_span_of(rest.ptr + end + 1, rest.len - end - 1);
    }
  }
  ms_string_release(&path);
  return found;
}

#endif
