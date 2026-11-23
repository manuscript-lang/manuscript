/* Owns running git (package_git.h): the environment, the fixed options, and the output read back from the log. */
#include "cli/package_git.h"

#include "base/bytes.h"
#include "base/file.h"
#include "base/message.h"
#include "base/path.h"
#include "base/process.h"

enum { kMaxArguments = 24 };

bool ms_git_open(MsGit *git, MsArena *arena, MsSpan *error) {
  git->arena = arena;
  const MsString temp = ms_temp_dir();
  const bool made = ms_dir_make_temp(ms_string_span(&temp), ms_span_of_text("ms-git-"), &git->directory);
  MsString release = temp;
  ms_string_release(&release);
  if (!made) {
    *error = ms_span_of_text("cannot make a temporary directory for git");
    return false;
  }
  MsStrBuild log = ms_strbuild_new();
  ms_path_append_joined(&log, ms_string_span(&git->directory), ms_span_of_text("git.log"));
  git->log = ms_message_from_builder(arena, &log);
  ms_strbuild_free(&log);
  return true;
}

void ms_git_close(MsGit *git) {
  ms_path_remove_tree(ms_string_span(&git->directory));
  ms_string_release(&git->directory);
}

MsSpan ms_git_redact(MsArena *arena, MsSpan text) {
  MsStrBuild out = ms_strbuild_new();
  size_t at = 0;
  while (at < text.len) {
    if (!(text.ptr[at] == ':' && at + 2 < text.len && text.ptr[at + 1] == '/' && text.ptr[at + 2] == '/')) {
      ms_strbuild_append_byte(&out, text.ptr[at++]);
      continue;
    }
    ms_strbuild_append_text(&out, "://");
    at += 3;
    size_t end = at;
    while (end < text.len && text.ptr[end] > ' ' && text.ptr[end] != '/' && text.ptr[end] != '\'' &&
           text.ptr[end] != '"') {
      end++;
    }
    size_t start = at;
    for (size_t i = at; i < end; i++) {
      start = text.ptr[i] == '@' ? i + 1 : start;
    }
    ms_strbuild_append(&out, ms_span_of(text.ptr + start, end - start));
    at = end;
  }
  const MsSpan copy = ms_message_from_builder(arena, &out);
  ms_strbuild_free(&out);
  return copy;
}

static MsSpan trimmed(MsSpan text) {
  while (text.len > 0 && text.ptr[text.len - 1] <= ' ') {
    text.len--;
  }
  while (text.len > 0 && text.ptr[0] <= ' ') {
    text = ms_span_of(text.ptr + 1, text.len - 1);
  }
  return text;
}

static MsSpan failure(MsGit *git, const char *const *args, size_t count, MsSpan said) {
  MsStrBuild line = ms_strbuild_new();
  for (size_t i = 0; i < count; i++) {
    ms_strbuild_append_text(&line, i == 0 ? "" : " ");
    ms_strbuild_append_text(&line, args[i]);
  }
  const MsSpan joined = ms_message_from_builder(git->arena, &line);
  ms_strbuild_free(&line);
  return ms_message_format(git->arena, "git %S failed: %S", ms_git_redact(git->arena, joined),
                           ms_git_redact(git->arena, trimmed(said)));
}

static MsSpan read_log(MsGit *git) {
  MsBytes bytes = {0};
  if (!ms_file_read(git->log, &bytes)) {
    return (MsSpan){0};
  }
  const MsSpan copy = ms_arena_copy(git->arena, ms_bytes_span(&bytes));
  ms_bytes_free(&bytes);
  return copy;
}

bool ms_git_run(MsGit *git, MsSpan directory, const char *protocols, const char *const *args, size_t count,
                MsSpan *output, MsSpan *error) {
  static const char *const fixed[] = {"git", "-c", "core.autocrlf=false", "-c", "core.safecrlf=false", "-c",
                                      "advice.detachedHead=false", "-c", "http.lowSpeedLimit=1000", "-c",
                                      "http.lowSpeedTime=30"};
  const size_t fixed_count = sizeof fixed / sizeof fixed[0];
  MsSpan argv[kMaxArguments + 16];
  size_t argc = 0;
  for (size_t i = 0; i < fixed_count; i++) {
    argv[argc++] = ms_span_of_text(fixed[i]);
  }
  for (size_t i = 0; i < count && argc < kMaxArguments + 14; i++) {
    argv[argc++] = ms_span_of_text(args[i]);
  }
  const MsSpan env[3] = {ms_span_of_text("GIT_TERMINAL_PROMPT=0"), ms_span_of_text("LC_ALL=C"),
                         ms_message_format(git->arena, "GIT_ALLOW_PROTOCOL=%s", protocols)};
  const MsProcessSpec spec = {.argv = argv, .argc = argc, .directory = directory, .env = env, .envc = 3,
                              .log_path = git->log};
  int status = 0;
  MsStrBuild why = ms_strbuild_new();
  if (!ms_process_run(&spec, &status, &why)) {
    ms_strbuild_free(&why);
    *error = ms_span_of_text("cannot run git; install git and put it on PATH");
    return false;
  }
  ms_strbuild_free(&why);
  const MsSpan said = read_log(git);
  if (status != 0) {
    *error = failure(git, args, count, said);
    return false;
  }
  *output = said;
  return true;
}
