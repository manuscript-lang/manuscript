/* Owns invocation.h: the option loop. The rules that combine options are in invocation_rules.c. */
#include "cli/invocation.h"

#include <stdio.h>

#include "base/dir.h"
#include "base/message.h"
#include "base/path.h"
#include "compiler/project/project.h"
#include "base/duration.h"
#include "cli/invocation_rules.h"

enum { STATUS_FAILED = 1, STATUS_USAGE = 2 };

typedef struct Parser {
  MsArena *arena;
  MsInvocation *out;
  MsSpan command;
  const MsSpan *args;
  size_t count;
  size_t at;
  MsRawOptions raw;
} Parser;

int ms_usage_error(MsArena *arena, MsSpan message) {
  (void)fwrite(message.ptr, 1, message.len, stderr);
  (void)fputc('\n', stderr);
  (void)arena;
  return STATUS_USAGE;
}

static const char *const VALUE_OPTIONS[] = {
    "-o",      "--output",     "--out-dir", "--build-type", "--timeout",   "--filter", "--test", "--bench",
    "--match", "--exclude",    "--repeat",  "--shuffle",    "--runs",      "--seed",   "--fuzz", "--time",
    "--samples", "--iterations", "--baseline", "--fail-over", "--format",  "--view",   "--entity", "--depth",
    "--diff",  "--top",        "--link"};

/* Whether `flag` is an option that consumes the next argument as its value. */
static bool ms_invocation_takes_value(MsSpan flag) {
  for (size_t i = 0; i < sizeof VALUE_OPTIONS / sizeof VALUE_OPTIONS[0]; i++) {
    if (ms_span_is_text(flag, VALUE_OPTIONS[i])) {
      return true;
    }
  }
  return false;
}

bool ms_invocation_skips_value(MsSpan flag) {
  return ms_invocation_takes_value(flag) || ms_span_is_text(flag, "--limit") || ms_span_is_text(flag, "--explain") ||
         ms_span_is_text(flag, "--effect");
}

/* `--name=value` for a long option that takes a value; any other token stays whole. */
static bool split_inline(MsSpan arg, MsSpan *flag, MsSpan *value) {
  *flag = arg;
  *value = (MsSpan){0};
  if (arg.len < 2 || arg.ptr[0] != '-' || arg.ptr[1] != '-') {
    return false;
  }
  for (size_t i = 0; i < arg.len; i++) {
    if (arg.ptr[i] == '=') {
      const MsSpan name = ms_span_of(arg.ptr, i);
      if (!ms_invocation_takes_value(name)) {
        return false;
      }
      *flag = name;
      *value = ms_span_of(arg.ptr + i + 1, arg.len - i - 1);
      return true;
    }
  }
  return false;
}

/* The value of an option: inline, or the next argument. Empty is refused. */
static bool required_value(Parser *p, bool inline_value, MsSpan inline_text, MsSpan *value) {
  if (inline_value) {
    *value = inline_text;
  } else if (p->at + 1 < p->count) {
    p->at++;
    *value = p->args[p->at];
  } else {
    return false;
  }
  return value->len > 0;
}

static int usage(Parser *p, const char *format, MsSpan a, MsSpan b) {
  return ms_usage_error(p->arena, ms_message_format(p->arena, format, a, b));
}

static int check_selection_value(Parser *p, MsSpan flag, MsSpan value) {
  int64_t number = 0;
  const bool positive = ms_span_is_text(flag, "--repeat") || ms_span_is_text(flag, "--runs") ||
                        ms_span_is_text(flag, "--samples") || ms_span_is_text(flag, "--iterations");
  const bool integer = positive || ms_span_is_text(flag, "--shuffle") || ms_span_is_text(flag, "--seed");
  if (integer && !ms_invocation_parse_int(value, &number)) {
    return usage(p, positive ? "invalid %S; use a positive integer" : "invalid %S; use an integer seed", flag,
                 (MsSpan){0});
  }
  if (positive && number <= 0) {
    return usage(p, "invalid %S; use a positive integer", flag, (MsSpan){0});
  }
  int64_t nanoseconds = 0;
  if (ms_span_is_text(flag, "--time") && (!ms_duration_parse(value, &nanoseconds) || nanoseconds < 1000000)) {
    return usage(p, "invalid --time %S; use a duration of at least 1ms such as 200ms or 1s",
                 ms_invocation_quote(p->arena, value), (MsSpan){0});
  }
  if (ms_span_is_text(flag, "--fuzz") && (!ms_duration_parse(value, &nanoseconds) || nanoseconds <= 0)) {
    return usage(p, "invalid --fuzz %S; use a positive duration such as 30s or 5m",
                 ms_invocation_quote(p->arena, value), (MsSpan){0});
  }
  return 0;
}

static int selection_option(Parser *p, MsSpan flag, bool inline_value, MsSpan inline_text) {
  MsSpan value = {0};
  if (!required_value(p, inline_value, inline_text, &value)) {
    return usage(p, "%S requires a value; run 'ms help test' for examples", flag, (MsSpan){0});
  }
  const int status = check_selection_value(p, flag, value);
  if (status != 0) {
    return status;
  }
  const MsSpan name = ms_span_is_text(flag, "--bench") ? ms_span_of_text("--test") : flag;
  ms_span_list_push(&p->raw.test_options, ms_message_format(p->arena, "%S=%S", name, value));
  return 0;
}

static int timeout_or_filter(Parser *p, MsSpan flag, bool inline_value, MsSpan inline_text) {
  MsSpan value = {0};
  const bool timeout = ms_span_is_text(flag, "--timeout");
  if (!required_value(p, inline_value, inline_text, &value)) {
    return usage(p, "%S requires a value, e.g. %S", flag,
                 ms_span_of_text(timeout ? "--timeout 30s" : "--filter \"test name\""));
  }
  int64_t nanoseconds = 0;
  if (!timeout) {
    p->raw.filter = value;
  } else if (!ms_duration_parse(value, &nanoseconds) || nanoseconds < 0) {
    return usage(p, "invalid --timeout %S; use a duration such as 30s or 2m, or 0 to disable",
                 ms_invocation_quote(p->arena, value), (MsSpan){0});
  } else {
    p->raw.timeout = value;
  }
  return 0;
}

static int build_type_option(Parser *p, bool inline_value, MsSpan inline_text) {
  MsSpan value = {0};
  if (!required_value(p, inline_value, inline_text, &value)) {
    return usage(p, "--build-type requires a build type; use Debug, Release, or MinSizeRel", (MsSpan){0}, (MsSpan){0});
  }
  if (p->raw.build_type_name.len > 0) {
    return usage(p, "--build-type may only be specified once; remove the duplicate flag", (MsSpan){0}, (MsSpan){0});
  }
  p->raw.build_type_name = value;
  return 0;
}

static int path_option(Parser *p, MsSpan flag, bool inline_value, MsSpan inline_text) {
  MsSpan value = {0};
  const bool out_dir = ms_span_is_text(flag, "--out-dir");
  if (!required_value(p, inline_value, inline_text, &value)) {
    return ms_usage_error(p->arena, ms_message_format(p->arena, "%S requires a path argument, e.g. %S %s", flag, flag,
                                                      out_dir ? "profile-bundle" : "out.txt"));
  }
  const bool profile = ms_span_is_text(p->command, "profile");
  if (out_dir && !profile) {
    return usage(p, "--out-dir is valid only for ms profile, not ms %S; use -o for commands that write a file",
                 p->command, (MsSpan){0});
  }
  if (!out_dir && profile) {
    return usage(p, "%S is not valid for ms profile; use --out-dir for the bundle directory", flag, (MsSpan){0});
  }
  p->out->output = value;
  return 0;
}

/* `--format`, `--view`, `--entity`, `--diff`, `--depth` and `--top`: the options of `diagram` and `profile`. */
static int tool_option(Parser *p, MsSpan flag, bool inline_value, MsSpan inline_text) {
  MsSpan value = {0};
  const bool review = ms_span_is_text(p->command, "review");
  if (ms_span_is_text(flag, "--all")) {
    p->out->all = true;
    return 0;
  }
  if (ms_span_is_text(flag, "--format")) {
    if (!required_value(p, inline_value, inline_text, &value)) {
      if (review) {
        return usage(p, "%S requires a value; run 'ms help review' for examples", flag, (MsSpan){0});
      }
      return usage(p, "--format requires a name, e.g. --format mermaid", (MsSpan){0}, (MsSpan){0});
    }
    p->out->format = value;
    return 0;
  }
  if (!required_value(p, inline_value, inline_text, &value)) {
    return usage(p, "%S requires a value; run 'ms help %S' for examples", flag,
                 ms_span_of_text(ms_span_is_text(flag, "--top") ? "profile" : review ? "review" : "diagram"));
  }
  if (ms_span_is_text(flag, "--explain")) {
    p->out->explain = value;
  } else if (ms_span_is_text(flag, "--effect")) {
    p->out->effect = value;
  } else if (ms_span_is_text(flag, "--view")) {
    p->out->view = value;
  } else if (ms_span_is_text(flag, "--entity")) {
    p->out->entity = value;
  } else if (ms_span_is_text(flag, "--diff")) {
    p->out->diff = value;
  } else {
    int64_t number = 0;
    if (!ms_invocation_parse_int(value, &number) || number <= 0) {
      return usage(p, "invalid %S; use a positive integer", flag, (MsSpan){0});
    }
    *(ms_span_is_text(flag, "--depth") ? &p->out->depth : &p->out->top) = number;
  }
  return 0;
}

static bool is_tool_option(MsSpan flag) {
  static const char *const NAMES[] = {"--format", "--view", "--entity", "--diff", "--depth", "--top",
                                         "--explain", "--effect", "--all"};
  for (size_t i = 0; i < sizeof NAMES / sizeof NAMES[0]; i++) {
    if (ms_span_is_text(flag, NAMES[i])) {
      return true;
    }
  }
  return false;
}

/* An argument that is no known option: another test input, or a usage error. */
static int other_argument(Parser *p, MsSpan arg) {
  const bool program_args = ms_span_is_text(p->command, "run") || ms_span_is_text(p->command, "test") ||
                            ms_span_is_text(p->command, "bench") || ms_span_is_text(p->command, "profile");
  if (arg.len == 0 || arg.ptr[0] != '-') {
    if (ms_span_is_text(p->command, "test")) {
      if (arg.len == 0) {
        return usage(p, "ms %S: an input argument is empty; pass a .ms file, directory, or ms.toml", p->command,
                     (MsSpan){0});
      }
      ms_span_list_push(&p->out->targets, arg);
      return 0;
    }
    return ms_usage_error(p->arena, ms_message_format(p->arena, "unexpected extra argument %S (ms %S takes one file; %s)", arg,
                                                      p->command,
                                                      program_args ? "arguments for the program go after --"
                                                                   : "remove the extra argument"));
  }
  return ms_usage_error(p->arena, ms_message_format(p->arena, "unknown option %S for ms %S; run 'ms help %S' for its options%s",
                                                    arg, p->command, p->command,
                                                    program_args ? " (arguments for the program go after --)" : ""));
}

static int flag_option(Parser *p, MsSpan flag, bool inline_value, MsSpan value) {
  MsInvocation *out = p->out;
  if (ms_span_is_text(flag, "--watch")) {
    out->watch = true;
  } else if (ms_span_is_text(flag, "--static")) {
    out->static_libc = true;
  } else if (ms_span_is_text(flag, "--allocs")) {
    out->allocs = true;
  } else if (ms_span_is_text(flag, "--json")) {
    out->json = true;
  } else if (ms_span_is_text(flag, "--list") || ms_span_is_text(flag, "--fail-fast") || ms_span_is_text(flag, "--ops")) {
    ms_span_list_push(&p->raw.test_options, flag);
  } else if (ms_span_is_text(flag, "--build-type")) {
    return build_type_option(p, inline_value, value);
  } else if (ms_span_is_text(flag, "--link")) {
    MsSpan path = {0};
    if (!required_value(p, inline_value, value, &path)) {
      return usage(p, "--link requires a path argument, e.g. --link native/libgreet.a", (MsSpan){0}, (MsSpan){0});
    }
    ms_span_list_push(&out->link, path);
  } else {
    return -1;
  }
  return 0;
}

static bool selection_flag(MsSpan flag) {
  static const char *const NAMES[] = {"--test", "--match", "--exclude", "--repeat", "--shuffle", "--runs", "--seed",
                                      "--fuzz", "--time",  "--samples", "--iterations", "--bench", "--baseline",
                                      "--fail-over"};
  for (size_t i = 0; i < sizeof NAMES / sizeof NAMES[0]; i++) {
    if (ms_span_is_text(flag, NAMES[i])) {
      return true;
    }
  }
  return false;
}

/* One argument at `p->at`. Returns 0, or a status; `*done` is set at `--`. */
static int one_option(Parser *p, bool *done) {
  MsSpan flag = {0};
  MsSpan value = {0};
  const MsSpan arg = p->args[p->at];
  const bool inline_value = split_inline(arg, &flag, &value);
  if (ms_span_is_text(flag, "--")) {
    for (size_t i = p->at + 1; i < p->count; i++) {
      ms_span_list_push(&p->out->arguments, p->args[i]);
    }
    *done = true;
    return 0;
  }
  const int flagged = flag_option(p, flag, inline_value, value);
  if (flagged >= 0) {
    return flagged;
  }
  if (selection_flag(flag)) {
    return selection_option(p, flag, inline_value, value);
  }
  if (ms_span_is_text(flag, "--timeout") || ms_span_is_text(flag, "--filter")) {
    return timeout_or_filter(p, flag, inline_value, value);
  }
  if (is_tool_option(flag)) {
    return tool_option(p, flag, inline_value, value);
  }
  if (ms_span_is_text(flag, "-o") || ms_span_is_text(flag, "--output") || ms_span_is_text(flag, "--out-dir")) {
    return path_option(p, flag, inline_value, value);
  }
  return other_argument(p, arg);
}

static int parse_options(Parser *p) {
  bool done = false;
  for (p->at = 1; p->at < p->count && !done; p->at++) {
    const int status = one_option(p, &done);
    if (status != 0) {
      return status;
    }
  }
  return 0;
}

int ms_invocation_parse(MsArena *arena, const char *command, int argc, char **argv, MsInvocation *out) {
  MsSpanList args = {0};
  const int normalized = ms_invocation_arguments(arena, command, argc, argv, &args);
  if (normalized != 0) {
    ms_span_list_free(&args);
    return normalized;
  }
  Parser p = {.arena = arena, .out = out, .command = ms_span_of_text(command), .args = args.ptr, .count = args.len};
  out->command = p.command;
  out->filename = args.ptr[0];
  ms_span_list_push(&out->targets, out->filename);
  int status = parse_options(&p);
  if (status == 0) {
    status = ms_invocation_expand_workspaces(arena, out);
  }
  if (status == 0) {
    status = ms_invocation_validate(arena, out, &p.raw);
  }
  ms_span_list_free(&p.raw.test_options);
  ms_span_list_free(&args);
  return status;
}

void ms_invocation_free(MsInvocation *invocation) {
  ms_span_list_free(&invocation->targets);
  ms_span_list_free(&invocation->link);
  ms_span_list_free(&invocation->arguments);
}
