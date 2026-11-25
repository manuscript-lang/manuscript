/* Driver: `ms verify` (see verify_command.h). Each step (check, fmt --check, lint, test) is this program run on the
 * target with `--json`; verify embeds each result in one document or summarizes them as text. Status 0 is every step passed or skipped, 1 a failed step, 2 a usage error. */
#include "cli/verify_command.h"

#include <stdio.h>
#include <time.h>

#include "base/arena.h"
#include "base/file.h"
#include "base/message.h"
#include "base/path.h"
#include "base/process.h"
#include "base/strbuild.h"
#include "compiler/syntax/diag_json.h"
#include "tooling/json_value.h"

enum { STATUS_FAILED = 1, STATUS_USAGE = 2, FINDING_LIMIT = 8, MAX_STEPS = 4 };

static const char *self_program = "ms";

void ms_verify_set_program(const char *program) {
  self_program = program;
}

typedef struct VerifyOptions {
  bool json, no_test, deny_warnings;
  const char *target;
} VerifyOptions;

typedef struct Step {
  const char *name;
  const char *status;
  int exit_code;
  int64_t duration_ns;
  MsSpan reason, error;
  const MsJson *result;
} Step;

static int refuse(const char *message, int status) {
  (void)fprintf(stderr, "%s\n", message);
  return status;
}

static int parse_arguments(int argc, char **argv, VerifyOptions *options) {
  bool positional = false;
  for (int index = 0; index < argc; index++) {
    const MsSpan argument = ms_span_of_text(argv[index]);
    if (!positional && ms_span_is_text(argument, "--")) {
      positional = true;
    } else if (!positional && ms_span_is_text(argument, "--no-test")) {
      options->no_test = true;
    } else if (!positional && ms_span_is_text(argument, "--deny-warnings")) {
      options->deny_warnings = true;
    } else if (!positional && ms_span_is_text(argument, "--json")) {
      options->json = true;
    } else if (!positional && argument.len != 0 && argument.ptr[0] == '-') {
      (void)fprintf(stderr, "unknown option %s for ms verify; run 'ms help verify' for its options\n", argv[index]);
      return STATUS_USAGE;
    } else if (options->target != NULL) {
      return refuse("ms verify takes one target; pass a .ms file, directory, or ms.toml", STATUS_USAGE);
    } else {
      options->target = argv[index];
    }
  }
  if (options->target == NULL) {
    options->target = "ms.toml";
  }
  if (options->target[0] == '\0') {
    return refuse("ms verify: the target is empty; pass a .ms file, directory, or ms.toml", STATUS_USAGE);
  }
  return 0;
}

/* A directory names the ms.toml inside it; empty when it has none. */
static MsSpan resolve_target(MsArena *arena, const char *target) {
  const MsSpan path = ms_span_of_text(target);
  if (!ms_dir_exists(path)) {
    return path;
  }
  MsStrBuild joined = ms_strbuild_new();
  ms_path_append_joined(&joined, path, ms_span_of_text("ms.toml"));
  const MsSpan named = ms_message_take_builder(arena, &joined);
  MsBytes manifest = {0};
  const bool present = ms_file_read(named, &manifest);
  ms_bytes_free(&manifest);
  return present ? named : (MsSpan){0};
}

static int64_t now_ns(void) {
  struct timespec time = {0};
  (void)timespec_get(&time, TIME_UTC);
  return (int64_t)time.tv_sec * 1000000000 + time.tv_nsec;
}

static MsSpan trimmed(MsSpan text) {
  while (text.len > 0 && (text.ptr[text.len - 1] == '\n' || text.ptr[text.len - 1] == '\r' || text.ptr[text.len - 1] == ' ')) {
    text.len--;
  }
  size_t start = 0;
  while (start < text.len && (text.ptr[start] == '\n' || text.ptr[start] == ' ')) {
    start++;
  }
  return ms_span_of(text.ptr + start, text.len - start);
}

static MsSpan read_text(MsArena *arena, MsSpan path) {
  MsBytes bytes = {0};
  MsSpan text = {0};
  if (ms_file_read(path, &bytes)) {
    text = ms_arena_copy(arena, ms_span_of(bytes.ptr, bytes.len));
  }
  ms_bytes_free(&bytes);
  return text;
}

/* Runs this program with `args` and reads what it printed. */
static Step run_step(MsArena *arena, MsSpan directory, const char *name, const MsSpan *args, size_t count) {
  Step step = {.name = name, .status = "failed"};
  MsSpan argv[8] = {ms_span_of_text(self_program)};
  for (size_t i = 0; i < count; i++) {
    argv[i + 1] = args[i];
  }
  const MsSpan out_path = ms_message_format(arena, "%S/%s.out", directory, name);
  const MsSpan err_path = ms_message_format(arena, "%S/%s.err", directory, name);
  const MsProcessSpec spec = {.argv = argv, .argc = count + 1, .log_path = out_path, .error_path = err_path};
  MsStrBuild why = ms_strbuild_new();
  int code = STATUS_FAILED;
  const int64_t start = now_ns();
  if (!ms_process_run(&spec, &code, &why)) {
    step.error = ms_arena_copy(arena, ms_strbuild_span(&why));
  }
  ms_strbuild_free(&why);
  step.exit_code = code;
  step.duration_ns = now_ns() - start;
  step.result = ms_json_parse(arena, trimmed(read_text(arena, out_path)));
  if (code == 0) {
    step.status = "passed";
  } else if (step.result == NULL && step.error.len == 0) {
    step.error = trimmed(read_text(arena, err_path));
  }
  return step;
}

static Step skipped(const char *name, const char *reason) {
  return (Step){.name = name, .status = "skipped", .reason = ms_span_of_text(reason)};
}

static void write_step(MsStrBuild *out, const Step *step, bool last) {
  ms_strbuild_printf(out, "    {\n      \"name\": \"%s\",\n      \"status\": \"%s\",\n      \"exit_code\": %d,\n      "
                          "\"duration_ns\": %lld",
                     step->name, step->status, step->exit_code, (long long)step->duration_ns);
  if (step->reason.len > 0) {
    ms_strbuild_append_text(out, ",\n      \"reason\": ");
    ms_json_string(out, step->reason);
  }
  if (step->error.len > 0) {
    ms_strbuild_append_text(out, ",\n      \"error\": ");
    ms_json_string(out, step->error);
  }
  if (step->result != NULL) {
    ms_strbuild_append_text(out, ",\n      \"result\": ");
    ms_json_write(out, step->result, 3);
  }
  ms_strbuild_append_text(out, last ? "\n    }\n" : "\n    },\n");
}

static void print_document(MsSpan target, bool ok, const Step *steps, size_t count) {
  MsStrBuild out = ms_strbuild_new();
  ms_strbuild_append_text(&out, "{\n  \"format\": 1,\n  \"target\": ");
  ms_json_string(&out, target);
  ms_strbuild_printf(&out, ",\n  \"ok\": %s,\n  \"steps\": [\n", ok ? "true" : "false");
  for (size_t i = 0; i < count; i++) {
    write_step(&out, &steps[i], i + 1 == count);
  }
  ms_strbuild_append_text(&out, "  ]\n}\n");
  const MsSpan text = ms_strbuild_span(&out);
  (void)fwrite(text.ptr, 1, text.len, stdout);
  ms_strbuild_free(&out);
}

static MsSpan string_member(const MsJson *object, const char *key) {
  const MsJson *member = ms_json_member(object, key);
  return member != NULL && member->kind == MS_JSON_STRING ? member->text : (MsSpan){0};
}

static MsSpan number_member(const MsJson *object, const char *key) {
  const MsJson *member = ms_json_member(object, key);
  return member != NULL && member->kind == MS_JSON_NUMBER ? member->text : ms_span_of_text("0");
}

static void print_span(MsSpan text) {
  (void)fwrite(text.ptr, 1, text.len, stderr);
}

/* One printed finding, capped at the limit with a "... N more" line. */
typedef struct Printer {
  size_t printed, total;
} Printer;

static void print_finding(Printer *printer, const MsStrBuild *line) {
  if (printer->total < FINDING_LIMIT) {
    (void)fputs("  ", stderr);
    print_span(ms_strbuild_span(line));
    (void)fputc('\n', stderr);
  }
  printer->total++;
}

/* The leading findings of a step, so the summary names the problem instead of only pointing at another command.
 * Errors come first: a capped list must not bury them under warnings. */
static size_t print_findings(const Step *step) {
  Printer printer = {0};
  MsStrBuild line = ms_strbuild_new();
  if (step->error.len > 0) {
    ms_strbuild_append(&line, step->error);
    print_finding(&printer, &line);
  }
  const MsJson *diagnostics = ms_json_member(step->result, "diagnostics");
  for (int pass = 0; diagnostics != NULL && diagnostics->kind == MS_JSON_ARRAY && pass < 2; pass++) {
    for (size_t i = 0; i < diagnostics->count; i++) {
      const MsJson *diag = diagnostics->items[i];
      const bool error = ms_span_is_text(string_member(diag, "severity"), "error");
      if (error != (pass == 0)) {
        continue;
      }
      const MsJson *position = ms_json_member(diag, "position");
      ms_strbuild_clear(&line);
      ms_strbuild_append(&line, string_member(position, "file"));
      ms_strbuild_append_byte(&line, ':');
      ms_strbuild_append(&line, number_member(position, "line"));
      ms_strbuild_append_byte(&line, ':');
      ms_strbuild_append(&line, number_member(position, "column"));
      ms_strbuild_append_text(&line, ": ");
      ms_strbuild_append(&line, string_member(diag, "message"));
      print_finding(&printer, &line);
    }
  }
  const MsJson *tests = ms_json_member(step->result, "tests");
  for (size_t i = 0; tests != NULL && tests->kind == MS_JSON_ARRAY && i < tests->count; i++) {
    if (!ms_span_is_text(string_member(tests->items[i], "status"), "failed")) {
      continue;
    }
    const MsSpan failure = string_member(tests->items[i], "failure");
    size_t first = 0;
    while (first < failure.len && failure.ptr[first] != '\n') {
      first++;
    }
    ms_strbuild_clear(&line);
    ms_strbuild_append(&line, string_member(tests->items[i], "name"));
    ms_strbuild_append_text(&line, ": ");
    ms_strbuild_append(&line, ms_span_of(failure.ptr, first));
    print_finding(&printer, &line);
  }
  ms_strbuild_free(&line);
  if (printer.total > FINDING_LIMIT) {
    (void)fprintf(stderr, "  ... %zu more\n", printer.total - FINDING_LIMIT);
  }
  return printer.total;
}

static void print_summary(MsSpan target, const Step *steps, size_t count) {
  for (size_t i = 0; i < count; i++) {
    if (ms_span_is_text(ms_span_of_text(steps[i].name), "lint") && ms_span_is_text(ms_span_of_text(steps[i].status), "passed") &&
        print_findings(&steps[i]) > 0) {
      (void)fputs("lint warnings do not fail verify; pass --deny-warnings to fail on them\n", stderr);
    }
  }
  for (size_t i = 0; i < count; i++) {
    if (ms_span_is_text(ms_span_of_text(steps[i].status), "failed")) {
      (void)print_findings(&steps[i]);
      (void)fprintf(stderr, "%s failed; run ms %s %.*s for details (or ms verify %.*s --json for every step)\n",
                    steps[i].name, steps[i].name, (int)target.len, (const char *)target.ptr, (int)target.len,
                    (const char *)target.ptr);
    }
  }
}

int ms_verify_command(int argc, char **argv) {
  VerifyOptions options = {0};
  const int status = parse_arguments(argc, argv, &options);
  if (status != 0) {
    return status;
  }
  MsArena arena = ms_arena_new();
  const MsSpan target = resolve_target(&arena, options.target);
  if (target.len == 0) {
    (void)fprintf(stderr,
                  "ms verify: %s is a directory without an ms.toml; pass a .ms file or a project ms.toml, e.g. ms verify ms.toml\n",
                  options.target);
    ms_arena_free(&arena);
    return STATUS_USAGE;
  }
  const MsSpan input = target.len > 0 && target.ptr[0] == '-' ? ms_message_format(&arena, "./%S", target, (MsSpan){0}) : target;
  const MsString temp = ms_temp_dir();
  MsString directory = ms_string_empty();
  if (!ms_dir_make_temp(ms_string_span(&temp), ms_span_of_text("manuscript-verify-"), &directory)) {
    ms_arena_free(&arena);
    return refuse("cannot create a temporary directory", STATUS_FAILED);
  }
  const MsSpan folder = ms_arena_copy(&arena, ms_string_span(&directory));
  Step steps[MAX_STEPS];
  const MsSpan json = ms_span_of_text("--json");
  const MsSpan check_args[] = {ms_span_of_text("check"), input, json};
  const MsSpan fmt_args[] = {ms_span_of_text("fmt"), input, ms_span_of_text("--check"), json};
  const MsSpan lint_args[] = {ms_span_of_text("lint"), input, json, ms_span_of_text("--deny-warnings")};
  const MsSpan test_args[] = {ms_span_of_text("test"), input, json};
  steps[0] = run_step(&arena, folder, "check", check_args, 3);
  const bool check_passed = ms_span_is_text(ms_span_of_text(steps[0].status), "passed");
  steps[1] = run_step(&arena, folder, "fmt", fmt_args, 4);
  steps[2] = check_passed ? run_step(&arena, folder, "lint", lint_args, options.deny_warnings ? 4 : 3)
                          : skipped("lint", "check failed");
  steps[3] = options.no_test ? skipped("test", "--no-test")
             : !check_passed ? skipped("test", "check failed")
                             : run_step(&arena, folder, "test", test_args, 3);
  bool ok = true;
  for (size_t i = 0; i < MAX_STEPS; i++) {
    ok = ok && !ms_span_is_text(ms_span_of_text(steps[i].status), "failed");
    if (!options.json) {
      (void)printf("%-6s %s\n", steps[i].name, steps[i].status);
    }
  }
  if (options.json) {
    print_document(target, ok, steps, MAX_STEPS);
  } else {
    print_summary(target, steps, MAX_STEPS);
  }
  ms_path_remove_tree(folder);
  ms_string_release(&directory);
  ms_arena_free(&arena);
  return ok ? 0 : STATUS_FAILED;
}
