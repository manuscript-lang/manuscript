/* The JSON writer of @std/data/json: typed encoders call it in document order and it writes text straight
 * into one buffer. A failure (the byte budget, a number that is not JSON, nesting past the ceiling, a bad
 * budget) is kept as the writer's status and every later call does nothing. Strings escape quotes,
 * backslashes and control characters only; floats are Go's shortest round-trip digits, `null` for NaN and
 * infinities. */
#include <math.h>
#include <stdlib.h>

#include "runtime/std/json_internal.h"
#include "base/array.h"
#include "base/list.h"
#include "base/fmt.h"
#include "runtime/std/json.h"
#include "base/strbuild.h"

/* An open array or object: how many members it holds, and where the last separator began for `undo`. */
typedef struct Level {
  uint32_t count;
  size_t undo_length;
  uint32_t undo_count;
} Level;

struct JsonWriter {
  MsObj header;
  JsonBuffer out;
  size_t width;   /* spaces per indent level, 0 for compact text */
  uint8_t status; /* MS_STATUS_OK until the first failure */
  Level *levels;  /* owned */
  size_t depth;
  size_t level_capacity;
  bool lost; /* a value without a JSON form was left out */
};

static void writer_drop(MsObj *object) {
  JsonWriter *writer = (JsonWriter *)object;
  json_buffer_free(&writer->out);
  ms_free(writer->levels);
  ms_free(writer);
}

static void fail(JsonWriter *writer, uint8_t status) {
  if (writer->status == MS_STATUS_OK) {
    writer->status = status;
  }
}

/* Appends bytes unless the writer already failed; passing the byte budget or the string limit is a failure.
 */
static void put(JsonWriter *writer, MsSpan bytes) {
  if (writer->status == MS_STATUS_OK && !json_buffer_append(&writer->out, bytes)) {
    fail(writer, MS_STATUS_LIMIT_EXCEEDED);
  }
}

static void put_byte(JsonWriter *writer, uint8_t byte) {
  put(writer, ms_span_of(&byte, 1));
}

static void put_text(JsonWriter *writer, const char *text) {
  put(writer, ms_span_of_text(text));
}

/* A newline and the indent of `level`, when indenting. */
static void newline(JsonWriter *writer, size_t level) {
  if (writer->width == 0 || writer->status != MS_STATUS_OK) {
    return;
  }
  put_byte(writer, '\n');
  size_t spaces = 0;
  if (writer->status == MS_STATUS_OK &&
      (!ms_size_mul(writer->width, level, &spaces) || !json_buffer_fill(&writer->out, ' ', spaces))) {
    fail(writer, MS_STATUS_LIMIT_EXCEEDED);
  }
}

/* The separator before a member or element of the open container; a top-level value has none. */
static void separate(JsonWriter *writer) {
  if (writer->depth == 0) {
    return;
  }
  Level *top = &writer->levels[writer->depth - 1];
  top->undo_length = writer->out.bytes.len;
  top->undo_count = top->count;
  if (top->count++ > 0) {
    put_byte(writer, ',');
  }
  newline(writer, writer->depth);
}

/* The sizes a limit allows: the budget, and what a string value can hold. */
static size_t effective_limit(size_t max_bytes) {
  return max_bytes < MS_STRING_MAX_LENGTH ? max_bytes : MS_STRING_MAX_LENGTH;
}

static const uint8_t hex_digits[] = "0123456789abcdef";

/* The quoted, escaped text of `text`. */
static void put_quoted(JsonWriter *writer, MsSpan text) {
  put_byte(writer, '"');
  size_t run = 0;
  for (size_t i = 0; i < text.len; i++) {
    const uint8_t c = text.ptr[i];
    if (c != '"' && c != '\\' && c >= 0x20) {
      continue;
    }
    put(writer, ms_span_of(text.ptr + run, i - run));
    run = i + 1;
    switch (c) {
    case '"':
      put_text(writer, "\\\"");
      break;
    case '\\':
      put_text(writer, "\\\\");
      break;
    case '\b':
      put_text(writer, "\\b");
      break;
    case '\f':
      put_text(writer, "\\f");
      break;
    case '\n':
      put_text(writer, "\\n");
      break;
    case '\r':
      put_text(writer, "\\r");
      break;
    case '\t':
      put_text(writer, "\\t");
      break;
    default: {
      const uint8_t escape[] = {'\\', 'u', '0', '0', hex_digits[c >> 4], hex_digits[c & 0xF]};
      put(writer, ms_span_of(escape, sizeof escape));
    }
    }
  }
  put(writer, ms_span_of(text.ptr + run, text.len - run));
  put_byte(writer, '"');
}

void json_writer_item(JsonWriter *writer) {
  if (writer->status == MS_STATUS_OK) {
    separate(writer);
  }
}

/* Starts member `name` of the open object, with the name's text already quoted when `quoted`. */
static void start_member(JsonWriter *writer, MsSpan name, bool quoted) {
  if (writer->status != MS_STATUS_OK) {
    return;
  }
  separate(writer);
  if (quoted) {
    put(writer, name);
  } else {
    put_quoted(writer, name);
  }
  put_byte(writer, ':');
  if (writer->width > 0) {
    put_byte(writer, ' ');
  }
}

void json_writer_key(JsonWriter *writer, MsSpan name) {
  start_member(writer, name, false);
}

static void open_container(JsonWriter *writer, uint8_t opener) {
  if (writer->status != MS_STATUS_OK) {
    return;
  }
  if (writer->depth >= JSON_DEPTH_CEILING) {
    fail(writer, MS_STATUS_INVALID_DATA);
    return;
  }
  void *levels = writer->levels;
  if (!ms_array_reserve(&levels, &writer->level_capacity, writer->depth + 1, sizeof *writer->levels)) {
    fail(writer, MS_STATUS_LIMIT_EXCEEDED);
    return;
  }
  writer->levels = levels;
  put_byte(writer, opener);
  writer->levels[writer->depth++] = (Level){0};
}

static void close_container(JsonWriter *writer, uint8_t closer) {
  if (writer->status != MS_STATUS_OK) {
    return;
  }
  if (writer->depth == 0) {
    fail(writer, MS_STATUS_INVALID_DATA);
    return;
  }
  const Level level = writer->levels[--writer->depth];
  if (level.count > 0) {
    newline(writer, writer->depth);
  }
  put_byte(writer, closer);
}

void json_writer_begin(JsonWriter *writer, bool is_array) {
  open_container(writer, is_array ? '[' : '{');
}

void json_writer_end(JsonWriter *writer, bool is_array) {
  close_container(writer, is_array ? ']' : '}');
}

/* A float; NaN and infinities are `null`. */
static void put_float(JsonWriter *writer, double value, bool single) {
  uint8_t text[MS_FMT_FLOAT_CAPACITY];
  size_t length = 0;
  if (!isfinite(value)) {
    put_text(writer, "null");
    return;
  }
  const bool formatted = single ? ms_fmt_float32(value, text, sizeof text, &length)
                                : ms_fmt_float(value, text, sizeof text, &length);
  if (!formatted) {
    fail(writer, MS_STATUS_FAILED);
    return;
  }
  put(writer, ms_span_of(text, length));
}

/* The decimal text a Float32 held in a double is written as, read back as the double it stands for: the
 * shortest digits that read back as that Float32. */
static double shortest_single(double value) {
  uint8_t text[MS_FMT_FLOAT_CAPACITY + 1];
  size_t length = 0;
  if (!isfinite(value) || !ms_fmt_float32(value, text, MS_FMT_FLOAT_CAPACITY, &length)) {
    return value;
  }
  text[length] = 0;
  return strtod((const char *)text, NULL); /* NOLINT(cert-err34-c): the text is a float we just formatted */
}

/* ---- the natives ---- */

uint8_t msstd_json_w_finish(void *w, MsString *out) {
  JsonWriter *writer = w;
  if (writer->status != MS_STATUS_OK) {
    return writer->status;
  }
  if (writer->depth != 0) {
    return MS_STATUS_INVALID_DATA;
  }
  JsonBuffer *buffer = &writer->out;
  *out = ms_string_from_span(ms_span_of(buffer->bytes.ptr, buffer->bytes.len));
  json_buffer_free(buffer);
  return MS_STATUS_OK;
}

void *msstd_json_writer_new(uint8_t has_max_bytes, int64_t max_bytes, uint8_t has_indent, int64_t indent) {
  JsonWriter *writer = ms_alloc_zeroed(sizeof *writer);
  writer->header.drop = writer_drop;
  size_t limit = SIZE_MAX;
  if (has_max_bytes && max_bytes < 0) {
    writer->status = MS_STATUS_INVALID_INPUT;
  } else if (has_max_bytes) {
    limit = (uint64_t)max_bytes > SIZE_MAX ? SIZE_MAX : (size_t)max_bytes;
  }
  if (has_indent && indent < 0) {
    fail(writer, MS_STATUS_INVALID_INPUT);
  } else if (has_indent) {
    writer->width = indent > JSON_INDENT_CEILING ? JSON_INDENT_CEILING : (size_t)indent;
  }
  writer->out.limit = effective_limit(limit);
  return writer;
}

void msstd_json_w_item(void *w) {
  json_writer_item(w);
}

void msstd_json_w_key(void *w, const MsString *key) {
  json_writer_key(w, ms_string_span(key));
}

void msstd_json_w_key_quoted(void *w, const MsString *quoted_name) {
  start_member(w, ms_string_span(quoted_name), true);
}

/* Removes the last item or key and whatever followed it. */
void msstd_json_w_undo(void *w) {
  JsonWriter *writer = w;
  if (writer->status != MS_STATUS_OK || writer->depth == 0) {
    return;
  }
  Level *top = &writer->levels[writer->depth - 1];
  writer->out.bytes.len = top->undo_length;
  top->count = top->undo_count;
}

void msstd_json_w_begin_array(void *w) {
  json_writer_begin(w, true);
}
void msstd_json_w_end_array(void *w) {
  json_writer_end(w, true);
}
void msstd_json_w_begin_object(void *w) {
  json_writer_begin(w, false);
}
void msstd_json_w_end_object(void *w) {
  json_writer_end(w, false);
}

void msstd_json_w_no_form(void *w) {
  ((JsonWriter *)w)->lost = true;
}

uint8_t msstd_json_w_lost(const void *w) {
  return ((const JsonWriter *)w)->lost;
}

void msstd_json_w_null(void *w) {
  put_text(w, "null");
}

void msstd_json_w_bool(void *w, uint8_t value) {
  put_text(w, value ? "true" : "false");
}

void msstd_json_w_int(void *w, int64_t value) {
  uint8_t text[MS_FMT_INTEGER_CAPACITY];
  size_t length = 0;
  if (ms_fmt_i64(value, text, sizeof text, &length)) {
    put(w, ms_span_of(text, length));
  }
}

/* A UInt64 given as its bit pattern. */
void msstd_json_w_uint(void *w, int64_t value) {
  uint8_t text[MS_FMT_INTEGER_CAPACITY];
  size_t length = 0;
  if (ms_fmt_u64((uint64_t)value, text, sizeof text, &length)) {
    put(w, ms_span_of(text, length));
  }
}

/* A Float32 held in a double, written as the shortest decimal that reads back as that Float32. */
void msstd_json_w_float32(void *w, double value) {
  put_float(w, shortest_single(value), false);
}

void msstd_json_w_float(void *w, double value) {
  put_float(w, value, false);
}

/* Number text from a caller, which has to be one JSON number. */
void msstd_json_w_number(void *w, const MsString *text) {
  JsonWriter *writer = w;
  const MsSpan number = ms_string_span(text);
  if (writer->status != MS_STATUS_OK) {
    return;
  }
  if (!json_number_valid(number)) {
    fail(writer, MS_STATUS_INVALID_DATA);
    return;
  }
  put(writer, number);
}

void msstd_json_w_string(void *w, const MsString *text) {
  JsonWriter *writer = w;
  if (writer->status == MS_STATUS_OK) {
    put_quoted(writer, ms_string_span(text));
  }
}
