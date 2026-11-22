/* Owns fault_record.h. */
#include "driver/fault_record.h"

#include "abi/fault.h"
#include "base/strbuild.h"
#include "compiler/syntax/diag_json.h"

enum { RECORD_VERSION = 2, FLAG_TRUNCATED = 1, FLAG_HAS_SITE = 2 };

typedef struct Reader {
  MsSpan bytes;
  size_t at;
  bool ok;
} Reader;

static uint32_t read_u32(Reader *r) {
  if (!r->ok || r->bytes.len - r->at < 4) {
    r->ok = false;
    return 0;
  }
  const uint8_t *p = r->bytes.ptr + r->at;
  r->at += 4;
  return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

static uint8_t read_u8(Reader *r) {
  if (!r->ok || r->at >= r->bytes.len) {
    r->ok = false;
    return 0;
  }
  return r->bytes.ptr[r->at++];
}

static MsSpan read_string(Reader *r) {
  const uint32_t length = read_u32(r);
  if (!r->ok || r->bytes.len - r->at < length) {
    r->ok = false;
    return (MsSpan){0};
  }
  const MsSpan text = ms_span_of(r->bytes.ptr + r->at, length);
  r->at += length;
  return text;
}

static const char *kind_name(uint8_t kind) {
  switch (kind) {
  case MS_FAULT_KIND_INCOMPLETE_CLEANUP:
    return "incomplete_cleanup";
  case MS_FAULT_KIND_STACK_OVERFLOW:
    return "stack_overflow";
  case MS_FAULT_KIND_DEADLOCK:
    return "deadlock";
  case MS_FAULT_KIND_DIVISION_BY_ZERO:
    return "division_by_zero";
  case MS_FAULT_KIND_OVERFLOW:
    return "overflow";
  case MS_FAULT_KIND_INDEX_OUT_OF_RANGE:
    return "index_out_of_range";
  case MS_FAULT_KIND_TEST_FAILURE:
    return "test_failure";
  case MS_FAULT_KIND_OUT_OF_MEMORY:
    return "out_of_memory";
  default:
    return "fault";
  }
}

typedef struct Frame {
  MsSpan file, function;
  uint32_t line, repeated;
} Frame;

static Frame read_frame(Reader *r) {
  Frame frame = {0};
  frame.file = read_string(r);
  frame.line = read_u32(r);
  frame.function = read_string(r);
  frame.repeated = read_u32(r);
  return frame;
}

MsSpan fault_record_json(MsArena *arena, MsSpan bytes) {
  Reader r = {.bytes = bytes, .ok = true};
  if (bytes.len < 5 || bytes.ptr[0] != 'M' || bytes.ptr[1] != 'S' || bytes.ptr[2] != 'F' || bytes.ptr[3] != 'R') {
    return (MsSpan){0};
  }
  r.at = 4;
  if (read_u8(&r) != RECORD_VERSION) {
    return (MsSpan){0};
  }
  (void)read_u32(&r); /* the writer's pid */
  const uint8_t kind = read_u8(&r);
  const uint8_t flags = read_u8(&r);
  const MsSpan message = read_string(&r);
  const uint32_t frame_count = read_u32(&r);
  MsStrBuild out = ms_strbuild_new();
  Frame first = {0};
  MsStrBuild trace = ms_strbuild_new();
  for (uint32_t i = 0; i < frame_count && r.ok; i++) {
    const Frame frame = read_frame(&r);
    first = i == 0 ? frame : first;
    ms_strbuild_append_text(&trace, i == 0 ? "\n" : ",\n");
    ms_strbuild_append_text(&trace, "          {\n            \"function\": ");
    ms_json_string(&trace, frame.function);
    ms_strbuild_append_text(&trace, ",\n            \"file\": ");
    ms_json_string(&trace, frame.file);
    ms_strbuild_printf(&trace, ",\n            \"line\": %u", frame.line);
    if (frame.repeated > 0) {
      ms_strbuild_printf(&trace, ",\n            \"repeated\": %u", frame.repeated);
    }
    ms_strbuild_append_text(&trace, "\n          }");
  }
  const uint32_t started = read_u32(&r);
  for (uint32_t i = 0; i < started && r.ok; i++) {
    (void)read_frame(&r); /* where a task was started: the text report shows it, the trace does not */
  }
  const uint32_t note_count = read_u32(&r);
  MsStrBuild notes = ms_strbuild_new();
  for (uint32_t i = 0; i < note_count && r.ok; i++) {
    ms_strbuild_append_text(&notes, i == 0 ? "\n" : ",\n");
    ms_strbuild_append_text(&notes, "          ");
    ms_json_string(&notes, read_string(&r));
  }
  MsSpan result = {0};
  if (r.ok) {
    ms_strbuild_append_text(&out, "{\n        \"kind\": \"");
    ms_strbuild_append_text(&out, kind_name(kind));
    ms_strbuild_append_text(&out, "\",\n        \"message\": ");
    ms_json_string(&out, message);
    if (frame_count > 0) {
      ms_strbuild_append_text(&out, ",\n        \"position\": {\n          \"file\": ");
      ms_json_string(&out, first.file);
      ms_strbuild_printf(&out, ",\n          \"line\": %u\n        }", first.line);
    }
    ms_strbuild_append_text(&out, ",\n        \"trace\": [");
    ms_strbuild_append(&out, ms_strbuild_span(&trace));
    ms_strbuild_append_text(&out, frame_count > 0 ? "\n        ]" : "]");
    ms_strbuild_printf(&out, ",\n        \"trace_truncated\": %s,\n        \"cleanups_ran\": %s,\n        \"cleanup_faults\": [",
                       (flags & FLAG_TRUNCATED) != 0 ? "true" : "false",
                       kind == MS_FAULT_KIND_INCOMPLETE_CLEANUP ? "false" : "true");
    ms_strbuild_append(&out, ms_strbuild_span(&notes));
    ms_strbuild_append_text(&out, note_count > 0 ? "\n        ]" : "]");
    ms_strbuild_printf(&out, ",\n        \"exit_code\": %d\n      }", ms_fault_exit_status((MsFaultKind)kind));
    result = ms_arena_copy(arena, ms_strbuild_span(&out));
  }
  ms_strbuild_free(&out);
  ms_strbuild_free(&trace);
  ms_strbuild_free(&notes);
  return result;
}
