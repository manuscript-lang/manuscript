/* Owns invocation_rules.h. Port of `default_project_target`, `resolve_input`, `expand_workspace` and `validate` in
 * crates/ms-cli (lib.rs, util.rs, invocation.rs), for build, run and test. */
#include "cli/invocation_rules.h"

#include <stdint.h>
#include <stdio.h>

#include "base/dir.h"
#include "base/message.h"
#include "base/path.h"
#include "base/strbuild.h"
#include "compiler/project/project.h"
#include "cli/help_command.h"

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

static bool is_one_of(MsSpan command, const char *const *names, size_t count) {
  for (size_t i = 0; i < count; i++) {
    if (ms_span_is_text(command, names[i])) {
      return true;
    }
  }
  return false;
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

static int missing_input(const char *command) {
  (void)fprintf(stderr, "ms %s: missing the file argument; pass a .ms file or a project ms.toml, e.g. ms %s ms.toml\n\n%s",
                command, command, ms_help_page(ms_span_of_text(command)));
  return 2;
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
    return missing_input(command);
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

static MsSpan option_name(MsSpan option) {
  size_t name = 0;
  while (name < option.len && option.ptr[name] != '=') {
    name++;
  }
  return ms_span_of(option.ptr, name);
}

static bool is_test_only(MsSpan option) {
  static const char *const NAMES[] = {"--runs", "--seed", "--fuzz", "--shuffle"};
  return is_one_of(option_name(option), NAMES, 4);
}

static int selection_rules(MsArena *arena, MsInvocation *invocation, const MsRawOptions *raw) {
  const bool test = ms_span_is_text(invocation->command, "test");
  const bool bench = ms_span_is_text(invocation->command, "bench");
  if (!test && !bench && (raw->timeout.len > 0 || raw->filter.len > 0 || raw->test_options.len > 0)) {
    return ms_usage_error(arena, ms_message_format(arena, "test selection options are valid only for ms test and ms "
                                                          "bench, not ms %S; run 'ms help %S' for the options this "
                                                          "command accepts",
                                                   invocation->command, invocation->command));
  }
  for (size_t i = 0; (test || bench) && i < raw->test_options.len; i++) {
    const MsSpan option = raw->test_options.ptr[i];
    if (test && is_bench_only(option)) {
      return ms_usage_error(arena, ms_message_format(arena, "%S is valid only for ms bench; run 'ms help test' for the "
                                                            "options this command accepts",
                                                     option_name(option), (MsSpan){0}));
    }
    if (bench && is_test_only(option)) {
      return ms_usage_error(arena, ms_message_format(arena, "%S is valid only for ms test; run 'ms help bench' for the "
                                                            "options this command accepts",
                                                     option_name(option), (MsSpan){0}));
    }
  }
  if (test || bench) {
    test_arguments(arena, invocation, raw);
  }
  return 0;
}

static int build_type_rule(MsArena *arena, MsInvocation *invocation, const MsRawOptions *raw) {
  const bool debug = ms_span_is_text(invocation->command, "run") || ms_span_is_text(invocation->command, "test");
  const MsBuildType fallback = debug ? MS_BUILD_DEBUG : MS_BUILD_RELEASE;
  if (!ms_build_type_parse(raw->build_type_name, fallback, &invocation->build_type)) {
    return ms_usage_error(arena, ms_message_format(arena, "unknown build type %S; expected Debug, Release, or MinSizeRel",
                                                   ms_invocation_quote(arena, raw->build_type_name), (MsSpan){0}));
  }
  return 0;
}

static const char *const VIEWS[] = {"overview", "calls", "effects", "errors", "modules",
                                    "flow",     "scope", "tasks",   "types",  "ownership"};

/* The rules of `ms review` options, in the order the Rust CLI checks them. */
static int review_rules(MsArena *arena, MsInvocation *invocation) {
  if (invocation->json && invocation->format.len > 0) {
    return ms_usage_error(arena, ms_message_format(arena, "--json and --format cannot be combined; --json is the JSON report",
                                                   (MsSpan){0}, (MsSpan){0}));
  }
  if (invocation->format.len > 0 && !ms_span_is_text(invocation->format, "ascii") &&
      !ms_span_is_text(invocation->format, "markdown")) {
    return ms_usage_error(arena, ms_message_format(arena, "unknown --format %S for ms review; use ascii or markdown (--json "
                                                          "for JSON)",
                                                   ms_invocation_quote(arena, invocation->format), (MsSpan){0}));
  }
  if (invocation->explain.len > 0 && invocation->diff.len == 0) {
    return ms_usage_error(arena, ms_message_format(arena, "--explain needs --diff; it explains one finding of a diff report, "
                                                          "e.g. ms review ms.toml --diff change.patch --explain 1",
                                                   (MsSpan){0}, (MsSpan){0}));
  }
  if (invocation->effect.len > 0 && invocation->diff.len == 0) {
    return ms_usage_error(arena, ms_message_format(arena, "--effect needs --diff; it keeps the findings that reach or permit "
                                                          "one effect, e.g. ms review ms.toml --diff change.patch --effect "
                                                          "std.net.*",
                                                   (MsSpan){0}, (MsSpan){0}));
  }
  return 0;
}

/* Options of `diagram` and `profile` used on another command, and the rules that combine them. */
static int tool_rules(MsArena *arena, MsInvocation *invocation) {
  const MsSpan command = invocation->command;
  const bool diagram = ms_span_is_text(command, "diagram");
  const bool profile = ms_span_is_text(command, "profile");
  const bool review = ms_span_is_text(command, "review");
  const MsSpan hint = command;
  if (review) {
    const int status = review_rules(arena, invocation);
    if (status != 0) {
      return status;
    }
  }
  if ((invocation->explain.len > 0 || invocation->effect.len > 0 || invocation->all) && !review) {
    return ms_usage_error(arena, ms_message_format(arena, "--all, --explain, and --effect are valid only for ms review, not "
                                                          "ms %S; run 'ms help %S' for its options", command, hint));
  }
  if (invocation->format.len > 0 && !diagram && !review) {
    return ms_usage_error(arena, ms_message_format(arena, "--format is valid only for ms diagram and ms review, not ms %S; "
                                                          "run 'ms help %S' for its options", command, hint));
  }
  if ((invocation->view.len > 0 || invocation->entity.len > 0 || invocation->depth != 0 ||
       (invocation->diff.len > 0 && !review)) && !diagram) {
    return ms_usage_error(arena, ms_message_format(arena, "--view, --entity, --depth, and --diff are valid only for ms "
                                                          "diagram, not ms %S; run 'ms help %S' for its options",
                                                   command, hint));
  }
  if (invocation->allocs && !profile) {
    return ms_usage_error(arena, ms_message_format(arena, "--allocs is valid only for ms profile, not ms %S; run 'ms help "
                                                          "%S' for its options", command, hint));
  }
  if (invocation->top != 0 && !profile) {
    return ms_usage_error(arena, ms_message_format(arena, "--top is valid only for ms profile, not ms %S; run 'ms help %S' "
                                                          "for its options", command, hint));
  }
  if (ms_span_is_text(invocation->view, "class")) {
    invocation->view = ms_span_of_text("types");
  } else if (ms_span_is_text(invocation->view, "mutability")) {
    invocation->view = ms_span_of_text("ownership");
  }
  if (invocation->view.len > 0 && !is_one_of(invocation->view, VIEWS, sizeof VIEWS / sizeof VIEWS[0])) {
    return ms_usage_error(arena, ms_message_format(arena, "unknown --view %S for ms diagram; use overview, calls, effects, "
                                                          "errors, modules, flow, scope, tasks, types, ownership",
                                                   ms_invocation_quote(arena, invocation->view), (MsSpan){0}));
  }
  const bool html = ms_span_is_text(invocation->format, "html");
  const bool scoped = invocation->view.len > 0 || invocation->entity.len > 0;
  if (diagram && invocation->diff.len > 0 && !scoped && !html) {
    return ms_usage_error(arena, ms_message_format(arena, "--diff marks a scoped view; add --view or --entity, e.g. ms "
                                                          "diagram ms.toml --view flow --entity save --diff change.patch",
                                                   (MsSpan){0}, (MsSpan){0}));
  }
  if (invocation->depth != 0 && !scoped) {
    return ms_usage_error(arena, ms_message_format(arena, "--depth needs --view or --entity; run 'ms help diagram' for "
                                                          "examples", (MsSpan){0}, (MsSpan){0}));
  }
  if (diagram && invocation->json && invocation->format.len > 0) {
    return ms_usage_error(arena, ms_message_format(arena, "--json and --format cannot be combined; --json emits the "
                                                          "diagram tree", (MsSpan){0}, (MsSpan){0}));
  }
  if (diagram && html && scoped) {
    return ms_usage_error(arena, ms_message_format(arena, "--format html covers every view in one page; drop --view and "
                                                          "--entity", (MsSpan){0}, (MsSpan){0}));
  }
  static const char *const FORMATS[] = {"ascii", "mermaid", "html"};
  if (diagram && invocation->format.len > 0 && !is_one_of(invocation->format, FORMATS, 3)) {
    return ms_usage_error(arena, ms_message_format(arena, "unknown --format %S for ms diagram; use ascii, mermaid, or html",
                                                   ms_invocation_quote(arena, invocation->format), (MsSpan){0}));
  }
  static const char *const WRITERS[] = {"build", "emit", "inspect", "diagram", "review", "profile"};
  if (invocation->output.len > 0 && !is_one_of(command, WRITERS, 5)) {
    return ms_usage_error(arena, ms_message_format(arena, "-o and --output are valid only for ms build, emit, inspect, "
                                                          "diagram, or profile, not ms %S; run 'ms help %S' for its options",
                                                   command, hint));
  }
  return 0;
}

int ms_invocation_validate(MsArena *arena, MsInvocation *invocation, const MsRawOptions *raw) {
  const MsSpan command = invocation->command;
  static const char *const PROGRAMS[] = {"run", "test", "bench", "profile"};
  if (invocation->arguments.len > 0 && !is_one_of(command, PROGRAMS, 4)) {
    return ms_usage_error(arena, ms_message_format(arena, "ms %S does not run a program; remove the arguments after --",
                                                   command, (MsSpan){0}));
  }
  const int tool = tool_rules(arena, invocation);
  if (tool != 0) {
    return tool;
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
  if (invocation->watch && !ms_span_is_text(command, "run") && !ms_span_is_text(command, "test")) {
    return ms_usage_error(arena, ms_message_format(arena, "--watch requires check, lint, run, or test, not %S; use ms "
                                                          "check <file> --watch or ms run <file> --watch",
                                                   command, (MsSpan){0}));
  }
  static const char *const EXECUTING[] = {"build", "run", "test", "bench"};
  const bool builds = is_one_of(command, EXECUTING, 4);
  if (invocation->static_libc && !builds) {
    return ms_usage_error(arena, ms_message_format(arena, "--static requires build, run, test, or bench, not %S; remove "
                                                          "the flag", command, (MsSpan){0}));
  }
  if (invocation->link.len > 0 && !builds) {
    return ms_usage_error(arena, ms_message_format(arena, "--link requires build, run, test, or bench, not %S; remove "
                                                          "the flag", command, (MsSpan){0}));
  }
  if (raw->build_type_name.len > 0 && !builds && !ms_span_is_text(command, "profile")) {
    return ms_usage_error(arena, ms_message_format(arena, "--build-type requires build, run, test, bench, or profile, not "
                                                          "%S; remove the flag", command, (MsSpan){0}));
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
