/* Owns `ms profile` (profile_command.h): builds the program into a new bundle directory, runs it with the runtime's
 * sampling profiler switched on (MS_PROFILE names the file the runtime writes its folded stacks to), converts what the
 * runtime wrote and reports it as text or as the versioned JSON document. Port of crates/ms-cli/src/profile.rs; the
 * conversion lives in profile_folded.c. `--allocs` also has the runtime sample allocations (MS_PROFILE_ALLOCS) and
 * reports which functions allocate. */
#include "cli/profile_command.h"

#include <stdio.h>

#include "base/dir.h"
#include "base/file.h"
#include "base/message.h"
#include "base/path.h"
#include "base/process.h"
#include "base/sort.h"
#include "base/utf8.h"
#include "compiler/syntax/diag_json.h"
#include "cli/checked_input.h"
#include "cli/invocation.h"
#include "cli/pipeline.h"
#include "cli/profile_folded.h"
#include "cli/watch.h"

enum { STATUS_FAILED = 1 };

#ifdef _WIN32
#define PROGRAM_NAME "program.exe" /* Windows will not start a program whose name lacks `.exe` */
#else
#define PROGRAM_NAME "program"
#endif

typedef struct Artifact {
  const char *kind;
  MsSpan path;
  const char *state;
} Artifact;

/* Everything the report of one run needs. */
typedef struct Profile {
  MsArena *arena;
  const MsInvocation *invocation;
  MsSpan display;  /* the bundle directory as the user wrote it */
  MsSpan output;   /* absolute */
  MsSpan program;  /* the executable inside the bundle */
  MsSpan folded;
  MsSpan allocs;   /* the runtime's allocation counts; the bytes are in `<allocs>.bytes` */
  MsSpan captured; /* the program's standard output under --json */
  size_t top;
  Artifact artifacts[12];
  size_t artifact_count;
  MsSpan message;     /* a failure of ms profile itself, or empty */
  const char *phase;  /* the phase of that failure */
  MsSpan reason;      /* how the run ended: `program_exit`, or `<phase>_error` */
  int status;
  bool completed;
  MsStrBuild profile_json; /* the `profile` member, once the folded stacks were read */
  MsStrBuild allocs_json;  /* the `allocs` member of it, with --allocs */
  MsStrBuild allocs_text;  /* the allocation report, with --allocs */
} Profile;

static void print_span(FILE *stream, MsSpan text) { (void)fwrite(text.ptr, 1, text.len, stream); }

static MsSpan absolute(MsArena *arena, MsSpan path) {
  MsString cwd = ms_string_empty();
  MsStrBuild joined = ms_strbuild_new();
  if (ms_path_is_absolute(path) || !ms_dir_current(&cwd)) {
    ms_strbuild_append(&joined, path);
  } else {
    ms_path_append_joined(&joined, ms_string_span(&cwd), path);
  }
  ms_string_release(&cwd);
  MsStrBuild cleaned = ms_strbuild_new();
  ms_path_clean(&cleaned, ms_strbuild_span(&joined));
  const MsSpan result = ms_arena_copy(arena, ms_strbuild_span(&cleaned));
  ms_strbuild_free(&joined);
  ms_strbuild_free(&cleaned);
  return result;
}

static void add_artifact(Profile *profile, const char *kind, MsSpan path, const char *state) {
  profile->artifacts[profile->artifact_count++] = (Artifact){.kind = kind, .path = path, .state = state};
}

static MsSpan bundle_file(const Profile *profile, const char *name) {
  return ms_message_format(profile->arena, "%S/%s", profile->output, name);
}

/* ---- the JSON document ---- */

static void put_base64(MsStrBuild *out, MsSpan data) {
  static const char alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  for (size_t i = 0; i < data.len; i += 3) {
    const size_t left = data.len - i < 3 ? data.len - i : 3;
    uint32_t group = 0;
    for (size_t j = 0; j < 3; j++) {
      group = group << 8 | (j < left ? data.ptr[i + j] : 0u);
    }
    for (size_t j = 0; j < 4; j++) {
      ms_strbuild_append_byte(out, j <= left ? (uint8_t)alphabet[(group >> (18 - 6 * j)) & 63] : (uint8_t)'=');
    }
  }
}

/* A percentage as the shortest decimal: `45.45`, `45.5`, `100`. */
static void put_percent_number(MsStrBuild *out, uint64_t hundredths) {
  ms_strbuild_append_u64(out, hundredths / 100);
  if (hundredths % 100 != 0) {
    ms_strbuild_append_byte(out, '.');
    ms_strbuild_append_byte(out, (uint8_t)('0' + hundredths % 100 / 10));
    if (hundredths % 10 != 0) {
      ms_strbuild_append_byte(out, (uint8_t)('0' + hundredths % 10));
    }
  }
}

static MsSpan perf_record(const Profile *profile, MsSpan program) {
  MsStrBuild command = ms_strbuild_new();
  ms_strbuild_append_text(&command, "MS_PERF_MAP=1 perf record -F 999 --call-graph fp -o perf.data -- ");
  ms_strbuild_append(&command, program);
  for (size_t i = 0; i < profile->invocation->arguments.len; i++) {
    ms_strbuild_append_byte(&command, ' ');
    ms_strbuild_append(&command, profile->invocation->arguments.ptr[i]);
  }
  const MsSpan text = ms_message_from_builder(profile->arena, &command);
  ms_strbuild_free(&command);
  return text;
}

static const char PERF_REPORT[] = "perf report -i perf.data --no-children";

/* The `profile` member: samples, rate, duration, the busiest functions and the perf commands for this program. */
static void build_profile_json(Profile *profile, const MsFoldedProfile *folded, const MsTopList *entries) {
  MsStrBuild *const out = &profile->profile_json;
  *out = ms_strbuild_new();
  ms_strbuild_append_text(out, "{\n    \"samples\": ");
  ms_strbuild_append_u64(out, folded->total);
  ms_strbuild_append_text(out, ",\n    \"hz\": ");
  ms_strbuild_append_u64(out, folded->hz);
  ms_strbuild_append_text(out, ",\n    \"duration_ns\": ");
  ms_strbuild_append_u64(out, folded->total * ms_folded_period_nanos(folded));
  ms_strbuild_append_text(out, ",\n    \"top\": [");
  const size_t shown = entries->len < profile->top ? entries->len : profile->top;
  for (size_t i = 0; i < shown; i++) {
    const MsTopEntry *const entry = &entries->ptr[i];
    ms_strbuild_append_text(out, i == 0 ? "\n      {\n        \"function\": " : ",\n      {\n        \"function\": ");
    ms_json_string(out, ms_names_span(&folded->names, entry->function));
    ms_strbuild_append_text(out, ",\n        \"flat\": ");
    ms_strbuild_append_u64(out, entry->flat);
    ms_strbuild_append_text(out, ",\n        \"flat_percent\": ");
    put_percent_number(out, ms_percent_hundredths(entry->flat, folded->total));
    ms_strbuild_append_text(out, ",\n        \"cum\": ");
    ms_strbuild_append_u64(out, entry->cum);
    ms_strbuild_append_text(out, ",\n        \"cum_percent\": ");
    put_percent_number(out, ms_percent_hundredths(entry->cum, folded->total));
    ms_strbuild_append_text(out, "\n      }");
  }
  ms_strbuild_append_text(out, shown == 0 ? "],\n    \"perf\": {\n      \"record\": " : "\n    ],\n    \"perf\": {\n      \"record\": ");
  ms_json_string(out, perf_record(profile, profile->program));
  ms_strbuild_append_text(out, ",\n      \"report\": ");
  ms_json_string(out, ms_span_of_text(PERF_REPORT));
  ms_strbuild_append_text(out, "\n    }\n  }");
}

static void print_document(const Profile *profile) {
  const MsInvocation *const invocation = profile->invocation;
  MsStrBuild out = ms_strbuild_new();
  ms_strbuild_append_text(&out, "{\n  \"format\": 1,\n  \"command\": \"profile\",\n  \"build_type\": \"");
  ms_strbuild_append_text(&out, ms_build_type_name(invocation->build_type));
  ms_strbuild_append_text(&out, "\",\n  \"source_root\": \"\",\n  \"output\": ");
  ms_json_string(&out, profile->output);
  ms_strbuild_printf(&out, ",\n  \"completed\": %s,\n  \"exit_code\": %d,\n", profile->completed ? "true" : "false",
                     profile->status);
  if (profile->reason.len > 0) {
    ms_strbuild_append_text(&out, "  \"reason\": ");
    ms_json_string(&out, profile->reason);
    ms_strbuild_append_text(&out, ",\n");
  }
  ms_strbuild_append_text(&out, "  \"artifacts\": [");
  for (size_t i = 0; i < profile->artifact_count; i++) {
    const Artifact *const artifact = &profile->artifacts[i];
    ms_strbuild_printf(&out, "%s\n    {\n      \"kind\": \"%s\",\n      \"path\": ", i == 0 ? "" : ",", artifact->kind);
    ms_json_string(&out, artifact->path);
    ms_strbuild_printf(&out, ",\n      \"state\": \"%s\"\n    }", artifact->state);
  }
  ms_strbuild_append_text(&out, profile->artifact_count == 0 ? "],\n" : "\n  ],\n");
  if (ms_utf8_is_valid(profile->captured.ptr, profile->captured.len)) {
    ms_strbuild_append_text(&out, "  \"stdout\": ");
    ms_json_string(&out, profile->captured);
  } else {
    ms_strbuild_append_text(&out, "  \"stdout\": \"\",\n  \"stdout_base64\": \"");
    put_base64(&out, profile->captured);
    ms_strbuild_append_byte(&out, '"');
  }
  ms_strbuild_append_text(&out, ",\n  \"diagnostics\": [");
  if (profile->message.len > 0) {
    ms_strbuild_append_text(&out, "\n    {\n      \"code\": \"MSN001\",\n      \"phase\": ");
    ms_json_string(&out, ms_span_of_text(profile->phase));
    ms_strbuild_append_text(&out, ",\n      \"message\": ");
    ms_json_string(&out, profile->message);
    ms_strbuild_append_text(&out, ",\n      \"position\": ");
    ms_json_position(&out, invocation->filename, (MsPos){.line = 1, .column = 1}, 3);
    ms_strbuild_append_text(&out, "\n    }\n  ]");
  } else {
    ms_strbuild_append_byte(&out, ']');
  }
  if (profile->profile_json.bytes.len > 0 || profile->allocs_json.bytes.len > 0) {
    ms_strbuild_append_text(&out, ",\n  \"profile\": ");
    if (profile->profile_json.bytes.len > 0) {
      /* the object's closing brace gives way to the `allocs` member */
      MsSpan body = ms_strbuild_span(&profile->profile_json);
      if (profile->allocs_json.bytes.len > 0) {
        ms_strbuild_append(&out, ms_span_of(body.ptr, body.len - 4)); /* up to "\n  }" */
        ms_strbuild_append_text(&out, ",\n    \"allocs\": ");
        ms_strbuild_append(&out, ms_strbuild_span(&profile->allocs_json));
        ms_strbuild_append_text(&out, "\n  }");
      } else {
        ms_strbuild_append(&out, body);
      }
    } else {
      ms_strbuild_append_text(&out, "{\n    \"allocs\": ");
      ms_strbuild_append(&out, ms_strbuild_span(&profile->allocs_json));
      ms_strbuild_append_text(&out, "\n  }");
    }
  }
  ms_strbuild_append_text(&out, "\n}\n");
  print_span(stdout, ms_strbuild_span(&out));
  ms_strbuild_free(&out);
}

/* ---- running ---- */

/* A failure of `ms profile`: the message on stderr (a failed build was already reported), and with --json the document. */
static int fail(Profile *profile, const char *phase, MsSpan message, int status) {
  profile->status = status;
  profile->phase = phase;
  profile->message = message;
  profile->reason = ms_message_format(profile->arena, "%s_error", phase);
  return status;
}

static MsSpan read_text(MsArena *arena, MsSpan path, bool *found) {
  MsBytes bytes = {0};
  MsSpan text = {0};
  *found = ms_file_read(path, &bytes);
  if (*found) {
    text = ms_arena_copy(arena, ms_bytes_span(&bytes));
  }
  ms_bytes_free(&bytes);
  return text;
}

/* The bundle directory must not exist yet; it is created here. On failure `*why` says why. */
static bool make_bundle_directory(Profile *profile, MsSpan *why) {
  const MsSpan parent_of = ms_path_file_name(profile->output).len > 0 ? profile->output : profile->output;
  MsStrBuild parent = ms_strbuild_new();
  ms_path_dir(parent_of, &parent);
  const bool parent_exists = ms_dir_exists(ms_strbuild_span(&parent));
  ms_strbuild_free(&parent);
  const char *cause = NULL;
  if (ms_path_kind(profile->output) != MS_PATH_MISSING) {
    cause = "File exists";
  } else if (!parent_exists) {
    cause = "No such file or directory";
  } else if (!ms_dir_make_all(profile->output)) {
    cause = "cannot create the directory";
  }
  if (cause == NULL) {
    return true;
  }
  *why = ms_message_format(profile->arena,
                           "profile directory must be new: mkdir %S: %s; choose a path that does not exist with --out-dir "
                           "<directory>",
                           profile->output, cause);
  return false;
}

/* Runs the program with the profiler on; its status is the result of `ms profile` unless the profile fails. */
static bool run_program(Profile *profile, int *status, MsSpan scratch) {
  const MsInvocation *const invocation = profile->invocation;
  MsSpanList argv = {0};
  ms_span_list_push(&argv, profile->program);
  for (size_t i = 0; i < invocation->arguments.len; i++) {
    ms_span_list_push(&argv, invocation->arguments.ptr[i]);
  }
  MsSpan environment[2] = {ms_message_format(profile->arena, "MS_PROFILE=%S", profile->folded)};
  if (invocation->allocs) {
    environment[1] = ms_message_format(profile->arena, "MS_PROFILE_ALLOCS=%S", profile->allocs);
  }
  const MsSpan captured_path = ms_message_format(profile->arena, "%S/stdout", scratch);
  const MsProcessSpec spec = {.argv = argv.ptr, .argc = argv.len, .env = environment, .envc = invocation->allocs ? 2 : 1,
                              .log_path = captured_path, .inherit_error = true, .inherit = !invocation->json};
  MsStrBuild why = ms_strbuild_new();
  (void)fflush(stdout);
  const bool started = ms_process_run(&spec, status, &why);
  if (!started) {
    profile->message = ms_arena_copy(profile->arena, ms_strbuild_span(&why));
  } else if (invocation->json) {
    bool found = false;
    profile->captured = read_text(profile->arena, captured_path, &found);
  }
  ms_strbuild_free(&why);
  ms_span_list_free(&argv);
  return started;
}

static void write_bundle_file(Profile *profile, const char *name, MsSpan data, const char *kind, int *status) {
  const MsSpan path = bundle_file(profile, name);
  if (!ms_file_write(path, data)) {
    if (profile->message.len == 0) {
      profile->phase = "artifact";
      profile->message = ms_message_format(profile->arena, "cannot write the profile bundle in %S: cannot write %S",
                                           profile->output, path);
    }
    *status = *status > STATUS_FAILED ? *status : STATUS_FAILED;
  }
  add_artifact(profile, kind, path, "written");
}

static void note_problem(Profile *profile, MsSpan message, int *status) {
  profile->phase = "artifact";
  profile->message = message;
  if (!profile->invocation->json) {
    print_span(stderr, ms_message_format(profile->arena, "%S\n", message));
  }
  if (*status == 0) {
    *status = STATUS_FAILED;
  }
}


/* ---- allocations ---- */

typedef struct AllocRow {
  MsSpan function;
  uint64_t allocations;
  uint64_t bytes;
} AllocRow;
MS_LIST_DEFINE(AllocRows, alloc_rows, AllocRow)

/* An allocation belongs to the innermost Manuscript function of its stack: the runtime frames above it are how it got
 * the memory, not who asked. */
static MsSpan stack_owner(const MsFoldedProfile *folded, size_t stack) {
  for (size_t at = folded->length.ptr[stack]; at > 0; at--) {
    const MsSpan name = ms_names_span(&folded->names, (MsName)folded->frames.ptr[folded->first.ptr[stack] + at - 1]);
    if (!ms_span_is_text(name, "[runtime]")) {
      return name;
    }
  }
  return ms_span_of_text("[runtime]");
}

static AllocRow *row_of(AllocRows *rows, MsSpan function) {
  for (size_t i = 0; i < rows->len; i++) {
    if (ms_span_equal(rows->ptr[i].function, function)) {
      return &rows->ptr[i];
    }
  }
  alloc_rows_push(rows, (AllocRow){.function = function});
  return &rows->ptr[rows->len - 1];
}

static int64_t compare_rows(uint8_t *unused, const uint8_t *a, const uint8_t *b) {
  (void)unused;
  AllocRow left_row;
  AllocRow right_row;
  __builtin_memcpy(&left_row, a, sizeof left_row);
  __builtin_memcpy(&right_row, b, sizeof right_row);
  const AllocRow *const left = &left_row;
  const AllocRow *const right = &right_row;
  if (left->allocations != right->allocations) {
    return left->allocations > right->allocations ? -1 : 1;
  }
  if (left->bytes != right->bytes) {
    return left->bytes > right->bytes ? -1 : 1;
  }
  const size_t common = left->function.len < right->function.len ? left->function.len : right->function.len;
  const int order = __builtin_memcmp(left->function.ptr, right->function.ptr, common);
  return order != 0 ? order : (left->function.len < right->function.len ? -1 : left->function.len > right->function.len);
}

/* `text` right-aligned in `width` columns after one space. */
static void pad_left(MsStrBuild *out, MsSpan text, size_t width) {
  ms_strbuild_append_byte(out, ' ');
  for (size_t used = text.len; used + 1 < width; used++) {
    ms_strbuild_append_byte(out, ' ');
  }
  ms_strbuild_append(out, text);
}

static void pad_number(MsStrBuild *out, uint64_t value, size_t width) {
  MsStrBuild digits = ms_strbuild_new();
  ms_strbuild_append_u64(&digits, value);
  pad_left(out, ms_strbuild_span(&digits), width);
  ms_strbuild_free(&digits);
}

/* The value after `# <key> ` in the runtime's comments, or 0. */
static uint64_t comment_value(MsSpan text, const char *key) {
  const size_t keylen = __builtin_strlen(key);
  for (size_t at = 0; at + 2 + keylen < text.len;) {
    size_t end = at;
    while (end < text.len && text.ptr[end] != '\n') {
      end++;
    }
    const MsSpan line = ms_span_of(text.ptr + at, end - at);
    if (line.len > 2 + keylen && line.ptr[0] == '#' && line.ptr[1] == ' ' && __builtin_memcmp(line.ptr + 2, key, keylen) == 0 &&
        line.ptr[2 + keylen] == ' ') {
      uint64_t value = 0;
      for (size_t i = 3 + keylen; i < line.len && line.ptr[i] >= '0' && line.ptr[i] <= '9'; i++) {
        value = value * 10 + (uint64_t)(line.ptr[i] - '0');
      }
      return value;
    }
    at = end + 1;
  }
  return 0;
}

/* Reads the runtime's two allocation files and builds the report and the `allocs` member. False (with `problem`) when
 * the program wrote none. */
static bool read_allocs(Profile *profile, MsSpan *problem) {
  const MsSpan bytes_path = ms_message_format(profile->arena, "%S.bytes", profile->allocs);
  bool found_counts = false;
  bool found_bytes = false;
  const MsSpan counts_text = read_text(profile->arena, profile->allocs, &found_counts);
  const MsSpan bytes_text = read_text(profile->arena, bytes_path, &found_bytes);
  if (!found_counts || !found_bytes) {
    *problem = ms_message_format(profile->arena,
                                 "the program wrote no allocation profile to %S; a program that never allocates on its "
                                 "main thread, a runtime built without profiling support or a program killed before "
                                 "cleanup writes nothing",
                                 found_counts ? bytes_path : profile->allocs);
    return false;
  }
  MsFoldedProfile counts = {0};
  MsFoldedProfile bytes = {0};
  MsSpan error = {0};
  if (!ms_folded_parse(profile->arena, counts_text, &counts, &error)) {
    *problem = ms_message_format(profile->arena, "cannot read %S: %S", profile->allocs, error);
    return false;
  }
  if (!ms_folded_parse(profile->arena, bytes_text, &bytes, &error)) {
    ms_folded_free(&counts);
    *problem = ms_message_format(profile->arena, "cannot read %S: %S", bytes_path, error);
    return false;
  }
  AllocRows rows = {0};
  for (size_t s = 0; s < counts.counts.len; s++) {
    row_of(&rows, stack_owner(&counts, s))->allocations += counts.counts.ptr[s];
  }
  for (size_t s = 0; s < bytes.counts.len; s++) {
    row_of(&rows, stack_owner(&bytes, s))->bytes += bytes.counts.ptr[s];
  }
  if (rows.len > 0) {
    ms_sort((uint8_t *)rows.ptr, rows.len, sizeof(AllocRow), compare_rows, NULL);
  }
  const uint64_t period = comment_value(counts_text, "period");
  const size_t shown = rows.len < profile->top ? rows.len : profile->top;
  MsStrBuild *const text = &profile->allocs_text;
  *text = ms_strbuild_new();
  ms_strbuild_printf(text, "Allocations on the main thread: about %zu (%zu bytes), sampling every %zuth; top %zu of %zu functions\n",
                     (size_t)counts.total, (size_t)bytes.total, (size_t)period, shown, rows.len);
  pad_left(text, ms_span_of_text("allocs"), 10);
  pad_left(text, ms_span_of_text("allocs%"), 8);
  pad_left(text, ms_span_of_text("bytes"), 13);
  ms_strbuild_append_text(text, "  function\n");
  MsStrBuild *const json = &profile->allocs_json;
  *json = ms_strbuild_new();
  ms_strbuild_printf(json, "{\n      \"period\": %zu,\n      \"allocations\": %zu,\n      \"bytes\": %zu,\n      \"top\": [",
                     (size_t)period, (size_t)counts.total, (size_t)bytes.total);
  for (size_t i = 0; i < shown; i++) {
    const AllocRow *const row = &rows.ptr[i];
    const uint64_t hundredths = ms_percent_hundredths(row->allocations, counts.total);
    pad_number(text, row->allocations, 10);
    MsStrBuild percent = ms_strbuild_new();
    ms_strbuild_printf(&percent, "%zu.%s%zu%%", (size_t)(hundredths / 100), hundredths % 100 < 10 ? "0" : "",
                       (size_t)(hundredths % 100));
    pad_left(text, ms_strbuild_span(&percent), 8);
    ms_strbuild_free(&percent);
    pad_number(text, row->bytes, 13);
    ms_strbuild_append_text(text, "  ");
    ms_strbuild_append(text, row->function);
    ms_strbuild_append_byte(text, '\n');
    ms_strbuild_append_text(json, i == 0 ? "\n        {\n          \"function\": " : ",\n        {\n          \"function\": ");
    ms_json_string(json, row->function);
    ms_strbuild_printf(json, ",\n          \"allocations\": %zu,\n          \"bytes\": %zu\n        }", (size_t)row->allocations,
                       (size_t)row->bytes);
  }
  ms_strbuild_append_text(json, shown == 0 ? "]\n    }" : "\n      ]\n    }");
  alloc_rows_free(&rows);
  ms_folded_free(&counts);
  ms_folded_free(&bytes);
  return true;
}

/* The allocation report: allocs.txt in the bundle, and the text and JSON the run prints. */
static void convert_allocs(Profile *profile, int *status) {
  MsSpan problem = {0};
  if (!read_allocs(profile, &problem)) {
    note_problem(profile, problem, status);
    return;
  }
  add_artifact(profile, "allocs", profile->allocs, "written");
  add_artifact(profile, "allocs_bytes", ms_message_format(profile->arena, "%S.bytes", profile->allocs), "written");
  write_bundle_file(profile, "allocs.txt", ms_strbuild_span(&profile->allocs_text), "allocs_top", status);
}

/* Converts what the runtime wrote into the bundle files and the report. */
static void convert(Profile *profile, int *status, MsStrBuild *report) {
  bool found = false;
  const MsSpan text = read_text(profile->arena, profile->folded, &found);
  if (!found) {
    note_problem(profile,
                 ms_message_format(profile->arena,
                                   "the program wrote no profile to %S (it exited with status %z); a runtime built without "
                                   "profiling support or a program killed before cleanup writes nothing",
                                   profile->folded, (size_t)*status),
                 status);
    add_artifact(profile, "folded", profile->folded, "missing");
    return;
  }
  MsFoldedProfile folded = {0};
  MsSpan problem = {0};
  if (!ms_folded_parse(profile->arena, text, &folded, &problem)) {
    note_problem(profile, ms_message_format(profile->arena, "cannot read %S: %S", profile->folded, problem), status);
    add_artifact(profile, "folded", profile->folded, "written");
    return;
  }
  MsTopList entries = {0};
  ms_folded_top(&folded, &entries);
  ms_folded_render_top(&folded, &entries, profile->top, report);
  MsStrBuild pprof = ms_strbuild_new();
  ms_folded_encode_pprof(&folded, watch_now_ms() * UINT64_C(1000000), &pprof);
  MsStrBuild manifest = ms_strbuild_new();
  ms_strbuild_printf(&manifest, "{\n  \"format\": 1,\n  \"executable\": \"%s\",\n  \"folded\": \"profile.folded\",\n"
                                "  \"pprof\": \"profile.pb\",\n  \"top\": \"top.txt\",\n  \"samples\": ",
                     PROGRAM_NAME);
  ms_strbuild_append_u64(&manifest, folded.total);
  ms_strbuild_append_text(&manifest, ",\n  \"hz\": ");
  ms_strbuild_append_u64(&manifest, folded.hz);
  ms_strbuild_append_text(&manifest, "\n}\n");
  add_artifact(profile, "folded", profile->folded, "written");
  write_bundle_file(profile, "profile.pb", ms_strbuild_span(&pprof), "pprof", status);
  write_bundle_file(profile, "top.txt", ms_strbuild_span(report), "top", status);
  write_bundle_file(profile, "manifest.json", ms_strbuild_span(&manifest), "manifest", status);
  build_profile_json(profile, &folded, &entries);
  ms_strbuild_free(&manifest);
  ms_strbuild_free(&pprof);
  ms_top_list_free(&entries);
  ms_folded_free(&folded);
}

static void print_text_report(const Profile *profile, const MsStrBuild *report) {
  MsArena *const arena = profile->arena;
  print_span(stdout, ms_strbuild_span(report));
  if (profile->allocs_text.bytes.len > 0) {
    (void)fputc('\n', stdout);
    print_span(stdout, ms_strbuild_span(&profile->allocs_text));
  }
  print_span(stdout, ms_message_format(arena, "\nProfile bundle: %S\n", profile->display));
  static const struct {
    const char *file;
    const char *what;
  } files[] = {{"profile.folded", "folded stacks (flamegraph.pl, inferno, speedscope)"},
               {"profile.pb", "pprof protobuf (go tool pprof, pprof -http=:8080)"},
               {"top.txt", "this report"},
               {PROGRAM_NAME, "the profiled executable"}};
  for (size_t i = 0; i < sizeof files / sizeof files[0]; i++) {
    MsStrBuild path = ms_strbuild_new();
    ms_path_append_joined(&path, profile->display, ms_span_of_text(files[i].file));
    const MsSpan shown = ms_strbuild_span(&path);
    print_span(stdout, ms_message_format(arena, "  %S", shown));
    for (size_t used = shown.len; used < 28; used++) {
      (void)fputc(' ', stdout);
    }
    print_span(stdout, ms_message_format(arena, " %s\n", files[i].what));
    ms_strbuild_free(&path);
  }
  MsStrBuild shown_program = ms_strbuild_new();
  ms_path_append_joined(&shown_program, profile->display, ms_span_of_text(PROGRAM_NAME));
  const MsSpan record = perf_record(profile, ms_strbuild_span(&shown_program));
  print_span(stdout, ms_message_format(arena,
                                       "\nTo sample with perf instead (no ms involved):\n  %S\n  %s\nBuilds keep frame "
                                       "pointers, DWARF line tables and a perf map (/tmp/perf-<pid>.map, written when MS_PERF_MAP=1), so perf resolves "
                                       "Manuscript function names and lines.\n",
                                       record, PERF_REPORT));
  ms_strbuild_free(&shown_program);
}

static int build_and_profile(Profile *profile, MsCheckedInput *checked) {
  const MsInvocation *const invocation = profile->invocation;
  profile->display = invocation->output.len > 0 ? invocation->output : ms_span_of_text("profile");
  profile->output = absolute(profile->arena, profile->display);
  profile->program = bundle_file(profile, PROGRAM_NAME);
  profile->folded = bundle_file(profile, "profile.folded");
  profile->allocs = bundle_file(profile, "allocs.folded");
  profile->top = invocation->top == 0 ? MS_PROFILE_DEFAULT_TOP : (size_t)invocation->top;
  MsSpan why = {0};
  if (!make_bundle_directory(profile, &why)) {
    print_span(stderr, ms_message_format(profile->arena, "%S\n", why));
    return fail(profile, "artifact", why, STATUS_FAILED);
  }
  if (!ms_checked_input_load(profile->arena, checked, invocation->filename, MS_INPUT_PROGRAM)) {
    ms_path_remove_tree(profile->output);
    return invocation->json ? ms_checked_input_report_json(checked) : ms_checked_input_report(checked);
  }
  MsSpan error = {0};
  const MsLinkRequest request = {.program = &checked->program, .entry = checked->entry, .build_type = invocation->build_type,
                                 .output = profile->program, .link = invocation->link.ptr, .link_count = invocation->link.len,
                                 .static_libc = invocation->static_libc};
  if (!ms_pipeline_link(&request, &error)) {
    ms_path_remove_tree(profile->output); /* this run made the directory, and a failed build must not block a retry */
    print_span(stderr, ms_message_format(profile->arena, "%S\n", error));
    return fail(profile, "build", error, STATUS_FAILED);
  }
  add_artifact(profile, "executable", profile->program, "verified");
  const MsString temp = ms_temp_dir();
  MsString scratch = ms_string_empty();
  if (!ms_dir_make_temp(ms_string_span(&temp), ms_span_of_text("manuscript-profile-"), &scratch)) {
    return fail(profile, "execution", ms_span_of_text("cannot create a temporary directory"), STATUS_FAILED);
  }
  int status = 0;
  const bool started = run_program(profile, &status, ms_arena_copy(profile->arena, ms_string_span(&scratch)));
  ms_path_remove_tree(ms_string_span(&scratch));
  ms_string_release(&scratch);
  if (!started) {
    print_span(stderr, ms_message_format(profile->arena, "%S\n", profile->message));
    return fail(profile, "execution", profile->message, STATUS_FAILED);
  }
  profile->completed = true;
  profile->reason = ms_span_of_text("program_exit");
  MsStrBuild report = ms_strbuild_new();
  convert(profile, &status, &report);
  if (invocation->allocs) {
    convert_allocs(profile, &status);
  }
  profile->status = status;
  if (invocation->json) {
    print_document(profile);
  } else if (report.bytes.len > 0) {
    print_text_report(profile, &report);
  }
  ms_strbuild_free(&report);
  ms_strbuild_free(&profile->profile_json);
  ms_strbuild_free(&profile->allocs_json);
  ms_strbuild_free(&profile->allocs_text);
  return status;
}

int ms_profile_command(int argc, char **argv) {
  MsArena arena = ms_arena_new();
  MsInvocation invocation = {0};
  int status = ms_invocation_parse(&arena, "profile", argc, argv, &invocation);
  if (status == 0) {
    Profile profile = {.arena = &arena, .invocation = &invocation};
    MsCheckedInput checked = {0};
    status = build_and_profile(&profile, &checked);
    if (!profile.completed && invocation.json && profile.message.len > 0) {
      print_document(&profile);
    }
    ms_checked_input_free(&checked);
  }
  ms_invocation_free(&invocation);
  ms_arena_free(&arena);
  return status;
}
