/* Owns invocation_rules.h. Port of `default_project_target`, `resolve_input`, `expand_workspace` and `validate` in
 * crates/ms-cli (lib.rs, util.rs, invocation.rs), for build, run and test. */
#include "driver/invocation_rules.h"

#include <stdint.h>
#include <stdio.h>

#include "base/dir.h"
#include "base/message.h"
#include "base/path.h"
#include "base/strbuild.h"
#include "compiler/project/project.h"

enum { STATUS_FAILED = 1 };

MsSpan ms_invocation_quote(MsArena *arena, MsSpan text) {
  MsStrBuild out = ms_strbuild_new();
  ms_strbuild_append_byte(&out, '"');
  for (size_t i = 0; i < text.len; i++) {
    if (text.ptr[i] == '"' || text.ptr[i] == '\\') {
      ms_strbuild_append_byte(&out, '\\');
    }
    ms_strbuild_append_byte(&out, text.ptr[i]);
  }
  ms_strbuild_append_byte(&out, '"');
  const MsSpan quoted = ms_arena_copy(arena, ms_strbuild_span(&out));
  ms_strbuild_free(&out);
  return quoted;
}

bool ms_invocation_parse_int(MsSpan text, int64_t *out) {
  size_t at = text.len > 0 && (text.ptr[0] == '-' || text.ptr[0] == '+') ? 1 : 0;
  if (at >= text.len) {
    return false;
  }
  int64_t value = 0;
  for (; at < text.len; at++) {
    if (text.ptr[at] < '0' || text.ptr[at] > '9' || __builtin_mul_overflow(value, 10, &value) ||
        __builtin_add_overflow(value, text.ptr[at] - '0', &value)) {
      return false;
    }
  }
  *out = text.ptr[0] == '-' ? -value : value;
  return true;
}

static bool is_value_option(MsSpan flag) {
  static const char *const NAMES[] = {"-o", "--output", "--build-type", "--timeout", "--filter", "--test", "--bench",
                                      "--match", "--exclude", "--repeat", "--shuffle", "--runs", "--seed", "--fuzz",
                                      "--time", "--samples", "--iterations", "--baseline", "--fail-over", "--link"};
  for (size_t i = 0; i < sizeof NAMES / sizeof NAMES[0]; i++) {
    if (ms_span_is_text(flag, NAMES[i])) {
      return true;
    }
  }
  return false;
}

static bool manifest_exists(void) {
  return ms_path_kind(ms_span_of_text("ms.toml")) == MS_PATH_FILE;
}

/* The command's own arguments with a target: the first input moves ahead of the options, or `ms.toml` goes first. */
static void default_target(int argc, char **argv, MsSpanList *out) {
  size_t first = SIZE_MAX;
  for (int i = 0; i < argc && first == SIZE_MAX; i++) {
    const MsSpan arg = ms_span_of_text(argv[i]);
    if (ms_span_is_text(arg, "--")) {
      break;
    }
    if (arg.len > 0 && arg.ptr[0] == '-') {
      i += is_value_option(arg) ? 1 : 0;
    } else {
      first = (size_t)i;
    }
  }
  if (first != SIZE_MAX) {
    ms_span_list_push(out, ms_span_of_text(argv[first]));
  } else if (manifest_exists()) {
    ms_span_list_push(out, ms_span_of_text("ms.toml"));
  }
  for (int i = 0; i < argc; i++) {
    if ((size_t)i != first) {
      ms_span_list_push(out, ms_span_of_text(argv[i]));
    }
  }
}

static bool needs_default(int argc, char **argv) {
  return argc == 0 || argv[0][0] == '-' || ms_span_is_text(ms_span_of_text(argv[0]), "--");
}

static int missing_input(MsArena *arena, const char *command) {
  return ms_usage_error(arena, ms_message_format(arena, "ms %s: missing the file argument; pass a .ms file or a project "
                                                        "ms.toml, e.g. ms %s ms.toml",
                                                 command, command));
}

/* A directory stands for its manifest. */
static int resolve_input(MsArena *arena, MsSpan command, MsSpan *filename) {
  if (ms_path_kind(*filename) != MS_PATH_DIRECTORY) {
    return 0;
  }
  MsStrBuild manifest = ms_strbuild_new();
  ms_path_append_joined(&manifest, *filename, ms_span_of_text("ms.toml"));
  const MsSpan path = ms_arena_copy(arena, ms_strbuild_span(&manifest));
  ms_strbuild_free(&manifest);
  if (ms_path_kind(path) == MS_PATH_MISSING) {
    return ms_usage_error(arena, ms_message_format(arena, "ms %S: %S is a directory without an ms.toml; pass a .ms file "
                                                          "or a project ms.toml, e.g. ms %S ms.toml",
                                                   command, *filename, command));
  }
  *filename = path;
  return 0;
}

int ms_invocation_arguments(MsArena *arena, const char *command, int argc, char **argv, MsSpanList *out) {
  if (needs_default(argc, argv)) {
    default_target(argc, argv, out);
  } else {
    for (int i = 0; i < argc; i++) {
      ms_span_list_push(out, ms_span_of_text(argv[i]));
    }
  }
  if (out->len == 0) {
    return missing_input(arena, command);
  }
  const MsSpan name = ms_span_of_text(command);
  MsSpan filename = out->ptr[0];
  if (filename.len == 0) {
    return ms_usage_error(arena, ms_message_format(arena, "ms %s: the file argument is empty; pass a .ms file, "
                                                          "directory, or ms.toml",
                                                   command));
  }
  if (filename.ptr[0] == '-' && !ms_span_is_text(filename, "--")) {
    const char *hint = manifest_exists() ? "" : "; with no file, ms uses ./ms.toml, which does not exist here, so pass a "
                                                ".ms file or a project ms.toml";
    return ms_usage_error(arena, ms_message_format(arena, "unknown option %S for ms %S; run 'ms help %S' for its options "
                                                          "(put the file first, then options%s)",
                                                   filename, name, name, hint));
  }
  const int status = resolve_input(arena, name, &filename);
  out->ptr[0] = filename;
  return status;
}

int ms_invocation_expand_workspaces(MsArena *arena, MsInvocation *invocation) {
  MsSpanList targets = {0};
  bool expanded = false;
  for (size_t i = 0; i < invocation->targets.len; i++) {
    MsSpanList members = {0};
    MsProjectError error = {0};
    bool root = false;
    if (!ms_project_workspace_members(arena, invocation->targets.ptr[i], &members, &root, &error)) {
      (void)fprintf(stderr, "ms %.*s: %s\n", (int)invocation->command.len, (const char *)invocation->command.ptr,
                    (const char *)ms_project_error_text(arena, &error).ptr);
      ms_span_list_free(&targets);
      return STATUS_FAILED;
    }
    if (root && !ms_span_is_text(invocation->command, "test")) {
      const MsSpan first = members.len > 0 ? members.ptr[0] : ms_span_of_text("app/ms.toml");
      ms_span_list_free(&targets);
      return ms_usage_error(arena, ms_message_format(arena, "ms %S: %S is a workspace root; name one member's ms.toml "
                                                            "instead, such as %S",
                                                     invocation->command, invocation->targets.ptr[i], first));
    }
    for (size_t m = 0; root && m < members.len; m++) {
      ms_span_list_push(&targets, members.ptr[m]);
    }
    if (!root) {
      ms_span_list_push(&targets, invocation->targets.ptr[i]);
    }
    expanded = expanded || root;
    ms_span_list_free(&members);
  }
  ms_span_list_free(&invocation->targets);
  invocation->targets = targets;
  if (expanded && targets.len > 0) {
    invocation->filename = targets.ptr[0];
  }
  return 0;
}

static bool is_bench_only(MsSpan option) {
  static const char *const NAMES[] = {"--time", "--samples", "--iterations", "--baseline", "--fail-over", "--ops"};
  size_t name = 0;
  while (name < option.len && option.ptr[name] != '=') {
    name++;
  }
  for (size_t i = 0; i < sizeof NAMES / sizeof NAMES[0]; i++) {
    if (ms_span_is_text(ms_span_of(option.ptr, name), NAMES[i])) {
      return true;
    }
  }
  return false;
}

/* The selection options, `--timeout=` and `--filter=`, then the user's arguments after `--`. */
static void test_arguments(MsArena *arena, MsInvocation *invocation, const MsRawOptions *raw) {
  MsSpanList arguments = {0};
  for (size_t i = 0; i < raw->test_options.len; i++) {
    ms_span_list_push(&arguments, raw->test_options.ptr[i]);
  }
  if (raw->timeout.len > 0) {
    ms_span_list_push(&arguments, ms_message_format(arena, "--timeout=%S", raw->timeout));
  }
  if (raw->filter.len > 0) {
    ms_span_list_push(&arguments, ms_message_format(arena, "--filter=%S", raw->filter));
  }
  if (invocation->arguments.len > 0) {
    ms_span_list_push(&arguments, ms_span_of_text("--"));
    for (size_t i = 0; i < invocation->arguments.len; i++) {
      ms_span_list_push(&arguments, invocation->arguments.ptr[i]);
    }
  }
  ms_span_list_free(&invocation->arguments);
  invocation->arguments = arguments;
}

static int selection_rules(MsArena *arena, MsInvocation *invocation, const MsRawOptions *raw) {
  const bool test = ms_span_is_text(invocation->command, "test");
  if (!test && (raw->timeout.len > 0 || raw->filter.len > 0 || raw->test_options.len > 0)) {
    return ms_usage_error(arena, ms_message_format(arena, "test selection options are valid only for ms test and ms "
                                                          "bench, not ms %S; run 'ms help %S' for the options this "
                                                          "command accepts",
                                                   invocation->command, invocation->command));
  }
  for (size_t i = 0; test && i < raw->test_options.len; i++) {
    if (is_bench_only(raw->test_options.ptr[i])) {
      size_t name = 0;
      while (name < raw->test_options.ptr[i].len && raw->test_options.ptr[i].ptr[name] != '=') {
        name++;
      }
      return ms_usage_error(arena, ms_message_format(arena, "%S is valid only for ms bench; run 'ms help test' for the "
                                                            "options this command accepts",
                                                     ms_span_of(raw->test_options.ptr[i].ptr, name), (MsSpan){0}));
    }
  }
  if (test) {
    test_arguments(arena, invocation, raw);
  }
  return 0;
}

static int build_type_rule(MsArena *arena, MsInvocation *invocation, const MsRawOptions *raw) {
  const MsBuildType fallback = ms_span_is_text(invocation->command, "build") ? MS_BUILD_RELEASE : MS_BUILD_DEBUG;
  if (!ms_build_type_parse(raw->build_type_name, fallback, &invocation->build_type)) {
    return ms_usage_error(arena, ms_message_format(arena, "unknown build type %S; expected Debug, Release, or MinSizeRel",
                                                   ms_invocation_quote(arena, raw->build_type_name), (MsSpan){0}));
  }
  return 0;
}

int ms_invocation_validate(MsArena *arena, MsInvocation *invocation, const MsRawOptions *raw) {
  const MsSpan command = invocation->command;
  if (invocation->arguments.len > 0 && ms_span_is_text(command, "build")) {
    return ms_usage_error(arena, ms_message_format(arena, "ms build does not run a program; remove the arguments after --",
                                                   (MsSpan){0}, (MsSpan){0}));
  }
  const int selection = selection_rules(arena, invocation, raw);
  if (selection != 0) {
    return selection;
  }
  if (invocation->watch && invocation->json) {
    return ms_usage_error(arena, ms_message_format(arena, "--json cannot be combined with --watch; remove --watch for one "
                                                          "versioned result",
                                                   (MsSpan){0}, (MsSpan){0}));
  }
  if (invocation->watch && ms_span_is_text(command, "build")) {
    return ms_usage_error(arena, ms_message_format(arena, "--watch requires check, lint, run, or test, not build; use ms "
                                                          "check <file> --watch or ms run <file> --watch",
                                                   (MsSpan){0}, (MsSpan){0}));
  }
  const int type = build_type_rule(arena, invocation, raw);
#ifndef __linux__
  if (type == 0 && invocation->static_libc) {
    return ms_usage_error(arena, ms_message_format(arena, "--static links static musl, which only Linux has; remove the "
                                                          "flag",
                                                   (MsSpan){0}, (MsSpan){0}));
  }
#endif
  return type;
}
