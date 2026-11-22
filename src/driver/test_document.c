/* Owns test_document.h. */
#include "driver/test_document.h"

#include "base/message.h"
#include "base/utf8.h"
#include "compiler/syntax/diag_json.h"

bool test_plan_select(MsArena *arena, const MsSpanList *names, const MsTestOptions *options, const char *noun,
                      TestPlan *plan, MsSpan *error) {
  plan->selected = MS_ARENA_NEW_ARRAY(arena, size_t, names->len + 1);
  plan->count = 0;
  bool *found = MS_ARENA_NEW_ARRAY(arena, bool, options->names.len + 1);
  for (size_t i = 0; i < names->len; i++) {
    bool exact = options->names.len == 0;
    for (size_t n = 0; n < options->names.len; n++) {
      if (ms_span_equal(options->names.ptr[n], names->ptr[i])) {
        exact = true;
        found[n] = true;
      }
    }
    size_t at = 0;
    if (exact && (options->filter.len == 0 || ms_span_find(names->ptr[i], options->filter, &at))) {
      plan->selected[plan->count++] = i;
    }
  }
  for (size_t n = 0; n < options->names.len; n++) {
    if (!found[n]) {
      *error = ms_message_format(arena, "unknown %s \"%S\"; use --list to find full module::name identities", noun,
                                 options->names.ptr[n]);
      return false;
    }
  }
  return true;
}

void test_plan_shuffle(TestPlan *plan, int64_t seed) {
  uint64_t state = (uint64_t)seed ^ 0x9E3779B97F4A7C15ULL;
  for (size_t i = plan->count; i-- > 1;) {
    state += 0x9E3779B97F4A7C15ULL;
    uint64_t z = state;
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    z ^= z >> 31;
    const size_t at = (size_t)(z % (i + 1));
    const size_t held = plan->selected[i];
    plan->selected[i] = plan->selected[at];
    plan->selected[at] = held;
  }
}

bool test_failure_position(MsSpan message, MsSpan *file, int64_t *line, int64_t *column) {
  size_t at = message.len;
  int64_t numbers[2] = {0, 0};
  for (int part = 1; part >= 0; part--) {
    size_t end = at;
    while (at > 0 && message.ptr[at - 1] >= '0' && message.ptr[at - 1] <= '9') {
      at--;
    }
    if (at == end || at == 0 || message.ptr[at - 1] != ':') {
      return false;
    }
    for (size_t i = at; i < end; i++) {
      numbers[part] = numbers[part] * 10 + (message.ptr[i] - '0');
    }
    at--;
  }
  const size_t file_end = at;
  size_t start = file_end;
  while (start > 0 && message.ptr[start - 1] != ' ') {
    start--;
  }
  if (start < 6 || start == file_end || !ms_span_starts_with(ms_span_of(message.ptr + start - 6, 6), ms_span_of_text("\n  at "))) {
    return false;
  }
  *file = ms_span_of(message.ptr + start, file_end - start);
  *line = numbers[0];
  *column = numbers[1];
  return true;
}

static void write_case(MsStrBuild *out, size_t index, const DocumentCase *row) {
  ms_strbuild_printf(out, "%s    {\n      \"index\": %zu,\n      \"duration_ns\": %lld,\n      \"name\": ", index == 0 ? "" : ",\n",
                     index, (long long)row->nanos);
  ms_json_string(out, row->name);
  ms_strbuild_printf(out, ",\n      \"status\": \"%s\"", row->status);
  if (row->failure.len > 0) {
    ms_strbuild_append_text(out, ",\n      \"failure\": ");
    ms_json_string(out, row->failure);
    MsSpan file;
    int64_t line, column;
    if (test_failure_position(row->failure, &file, &line, &column)) {
      ms_strbuild_append_text(out, ",\n      \"position\": {\n        \"file\": ");
      ms_json_string(out, file);
      ms_strbuild_printf(out, ",\n        \"line\": %lld,\n        \"column\": %lld,\n        \"offset\": 0\n      }",
                         (long long)line, (long long)column);
    }
  }
  if (row->stats != NULL) {
    ms_strbuild_append_text(out, ",\n      \"stats\": ");
    ms_json_write(out, row->stats, 3);
  }
  ms_strbuild_append_text(out, "\n    }");
}

void test_document_diagnostic(MsStrBuild *out, const char *phase, MsSpan message, MsSpan file, uint32_t line) {
  ms_strbuild_append_text(out, "    {\n      \"code\": \"MST001\",\n      \"phase\": ");
  ms_json_string(out, ms_span_of_text(phase));
  ms_strbuild_append_text(out, ",\n      \"message\": ");
  ms_json_string(out, message);
  ms_strbuild_append_text(out, ",\n      \"position\": ");
  ms_json_position(out, file, (MsPos){.line = line, .column = line > 0 ? 1U : 0U}, 3);
  ms_strbuild_append_text(out, "\n    }");
}

static size_t count_status(const TestDocument *document, const char *status) {
  size_t count = 0;
  for (size_t i = 0; i < document->count; i++) {
    count += ms_span_is_text(ms_span_of_text(document->cases[i].status), status);
  }
  return count;
}

static const char BASE64[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static void write_base64(MsStrBuild *out, MsSpan bytes) {
  ms_strbuild_append_byte(out, '"');
  for (size_t i = 0; i < bytes.len; i += 3) {
    const size_t left = bytes.len - i;
    const uint32_t word = (uint32_t)bytes.ptr[i] << 16 | (left > 1 ? (uint32_t)bytes.ptr[i + 1] << 8 : 0) |
                          (left > 2 ? (uint32_t)bytes.ptr[i + 2] : 0);
    ms_strbuild_append_byte(out, (uint8_t)BASE64[(word >> 18) & 63]);
    ms_strbuild_append_byte(out, (uint8_t)BASE64[(word >> 12) & 63]);
    ms_strbuild_append_byte(out, left > 1 ? (uint8_t)BASE64[(word >> 6) & 63] : '=');
    ms_strbuild_append_byte(out, left > 2 ? (uint8_t)BASE64[word & 63] : '=');
  }
  ms_strbuild_append_byte(out, '"');
}

void test_document_write(const TestDocument *document, MsStrBuild *out) {
  ms_strbuild_append_text(out, "{\n");
  if (document->listed) {
    ms_strbuild_append_text(out, "  \"listed\": true,\n");
  }
  if (document->repeat > 0) {
    ms_strbuild_printf(out, "  \"repeat\": %zu,\n", document->repeat);
  }
  if (document->has_shuffle) {
    ms_strbuild_printf(out, "  \"shuffle_seed\": %lld,\n", (long long)document->shuffle_seed);
  }
  ms_strbuild_printf(out, "  \"format\": 1,\n  \"source_root\": ");
  ms_json_string(out, document->source_root);
  ms_strbuild_printf(out, ",\n  \"%s\": [", document->bench ? "benches" : "tests");
  if (document->count > 0) {
    ms_strbuild_append_byte(out, '\n');
  }
  for (size_t i = 0; i < document->count; i++) {
    write_case(out, i, &document->cases[i]);
  }
  ms_strbuild_append_text(out, document->count > 0 ? "\n  ]" : "]");
  const size_t passed = count_status(document, "passed");
  const size_t failed = count_status(document, "failed");
  const size_t skipped = count_status(document, "skipped");
  const size_t not_run = document->completed ? document->count - (passed + failed + skipped) : 0;
  ms_strbuild_printf(out,
                     ",\n  \"summary\": {\n    \"available\": %zu,\n    \"selected\": %zu,\n    \"passed\": %zu,\n    "
                     "\"failed\": %zu,\n    \"skipped\": %zu,\n    \"not_run\": %zu,\n    \"duration_ns\": %lld\n  },\n  "
                     "\"completed\": %s,\n  \"exit_code\": %d",
                     document->available, document->count, passed, failed, skipped, not_run, (long long)document->nanos,
                     document->completed ? "true" : "false", document->exit_code);
  if (document->reason.len > 0) {
    ms_strbuild_append_text(out, ",\n  \"reason\": ");
    ms_json_string(out, document->reason);
  }
  const bool text = ms_utf8_is_valid(document->output.ptr, document->output.len);
  ms_strbuild_append_text(out, ",\n  \"stdout\": ");
  ms_json_string(out, text ? document->output : ms_span_of_text(""));
  if (!text) {
    ms_strbuild_append_text(out, ",\n  \"stdout_base64\": ");
    write_base64(out, document->output);
  }
  ms_strbuild_append_text(out, ",\n  \"diagnostics\": [");
  if (document->diagnostics.len > 0) {
    ms_strbuild_append_byte(out, '\n');
    ms_strbuild_append(out, document->diagnostics);
    ms_strbuild_append_text(out, "\n  ]\n}\n");
  } else {
    ms_strbuild_append_text(out, "]\n}\n");
  }
}

static MsStrBuild *capture;

void test_output_capture(MsStrBuild *into) {
  capture = into;
}

bool test_capturing(void) {
  return capture != NULL;
}

void test_print(FILE *stream, MsSpan text) {
  if (stream == stdout && capture != NULL) {
    ms_strbuild_append(capture, text);
    return;
  }
  (void)fwrite(text.ptr, 1, text.len, stream);
}

void test_document_finish(TestDocument *document) {
  if (capture == NULL) {
    return;
  }
  MsStrBuild *printed = capture;
  capture = NULL;
  document->output = ms_strbuild_span(printed);
  MsStrBuild out = ms_strbuild_new();
  test_document_write(document, &out);
  test_print(stdout, ms_strbuild_span(&out));
  ms_strbuild_free(&out);
  capture = printed;
}

int test_fail_early(MsArena *arena, MsSpan source_root, MsSpan input, bool bench, const char *phase, MsSpan message) {
  test_print(stderr, ms_message_format(arena, "%S\n", message));
  if (capture != NULL) {
    MsStrBuild entry = ms_strbuild_new();
    test_document_diagnostic(&entry, phase, message, input, 1);
    TestDocument document = {.bench = bench, .source_root = source_root, .exit_code = 1,
                             .reason = ms_message_format(arena, "%s_error", phase),
                             .diagnostics = ms_arena_copy(arena, ms_strbuild_span(&entry))};
    ms_strbuild_free(&entry);
    test_document_finish(&document);
  }
  return 1;
}
