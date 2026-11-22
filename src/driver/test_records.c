/* Owns test_records.h. */
#include "driver/test_records.h"
#include "driver/fault_record.h"

#include "base/message.h"
#include "driver/invocation_rules.h"
#include "driver/watch.h"

enum { SOH = 1, STX = 2 };

void test_records_init(TestRecords *records, MsArena *arena, size_t total, size_t files) {
  *records = (TestRecords){.arena = arena, .total = total, .files = files};
  records->started = MS_ARENA_NEW_ARRAY(arena, bool, total + 1);
  records->running = MS_ARENA_NEW_ARRAY(arena, bool, total + 1);
  records->timed_out = MS_ARENA_NEW_ARRAY(arena, bool, total + 1);
  records->began_ms = MS_ARENA_NEW_ARRAY(arena, uint64_t, total + 1);
  records->running_file = MS_ARENA_NEW_ARRAY(arena, size_t, total + 1);
  records->pending_output = MS_ARENA_NEW_ARRAY(arena, MsSpan, total + 1);
  records->faulted = MS_ARENA_NEW_ARRAY(arena, bool, files + 1);
  records->fault_message = MS_ARENA_NEW_ARRAY(arena, MsSpan, files + 1);
  records->fault_output = MS_ARENA_NEW_ARRAY(arena, MsSpan, files + 1);
  records->fault_object = MS_ARENA_NEW_ARRAY(arena, MsSpan, files + 1);
}

static bool starts(MsSpan line, const char *keyword, MsSpan *rest) {
  const MsSpan prefix = ms_span_of_text(keyword);
  if (!ms_span_starts_with(line, prefix)) {
    return false;
  }
  *rest = ms_span_of(line.ptr + prefix.len, line.len - prefix.len);
  return true;
}

/* The text up to `separator` (or the end), and the text after it. */
static MsSpan split_at(MsSpan text, uint8_t separator, MsSpan *after) {
  size_t i = 0;
  while (i < text.len && text.ptr[i] != separator) {
    i++;
  }
  *after = i < text.len ? ms_span_of(text.ptr + i + 1, text.len - i - 1) : (MsSpan){0};
  return ms_span_of(text.ptr, i);
}

static size_t number(MsSpan text) {
  int64_t value = 0;
  return ms_invocation_parse_int(text, &value) && value >= 0 ? (size_t)value : (size_t)-1;
}

/* `MSOUT <key> <bytes>` and the bytes after the line: `f<file>` is a faulted file's output, anything else a test's. */
static void read_output(TestRecords *r, MsSpan header, MsSpan body) {
  MsSpan size_text = {0};
  const MsSpan key = split_at(header, ' ', &size_text);
  const MsSpan printed = ms_arena_copy(r->arena, body);
  if (key.len > 0 && key.ptr[0] == 'f') {
    const size_t file = number(ms_span_of(key.ptr + 1, key.len - 1));
    if (file < r->files) {
      r->fault_output[file] = printed;
    }
  } else if (key.len > 0 && key.ptr[0] == 'r') {
    const size_t file = number(ms_span_of(key.ptr + 1, key.len - 1));
    if (file < r->files) {
      r->fault_object[file] = fault_record_json(r->arena, body);
    }
  } else if (key.len > 0) {
    const size_t index = number(key);
    if (index < r->total) {
      r->pending_output[index] = printed;
    }
  }
}

static void read_start(TestRecords *r, MsSpan rest) {
  MsSpan file_text = {0};
  const size_t index = number(split_at(rest, ' ', &file_text));
  const size_t file = number(file_text);
  if (index < r->total) {
    r->started[index] = true;
    r->running[index] = true;
    r->running_file[index] = file;
    r->began_ms[index] = watch_now_ms();
  }
}

static void read_fault(TestRecords *r, MsSpan rest) {
  MsSpan message = {0};
  const size_t file = number(split_at(rest, SOH, &message));
  if (file >= r->files) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  for (size_t i = 0; i < message.len; i++) {
    ms_strbuild_append_byte(&text, message.ptr[i] == STX ? '\n' : message.ptr[i]);
  }
  r->faulted[file] = true;
  r->fault_message[file] = ms_arena_copy(r->arena, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  for (size_t t = 0; t < r->total; t++) {
    r->running[t] = r->running[t] && r->running_file[t] != file;
  }
}

/* `MSTEST <index> <status> <nanoseconds>\x01<message>\x01<site>`. */
static void read_result(TestRecords *r, MsSpan rest) {
  MsSpan tail = {0};
  MsSpan head = split_at(rest, SOH, &tail);
  MsSpan site = {0};
  const MsSpan message = split_at(tail, SOH, &site);
  MsSpan more = {0};
  const size_t index = number(split_at(head, ' ', &more));
  MsSpan nanos_text = {0};
  const MsSpan status = split_at(more, ' ', &nanos_text);
  if (index >= r->total) {
    return;
  }
  TestOutcome outcome = {.kind = TEST_FAILED, .message = ms_arena_copy(r->arena, message),
                         .output = r->pending_output[index], .nanos = (int64_t)number(nanos_text)};
  if (ms_span_is_text(status, "pass")) {
    outcome.kind = TEST_PASSED;
  } else if (ms_span_is_text(status, "skip")) {
    outcome.kind = TEST_SKIPPED;
  } else if (site.len > 0) {
    outcome.message = ms_message_format(r->arena, "%S\n  at %S", message, site);
  }
  r->pending_output[index] = (MsSpan){0};
  r->running[index] = false;
  test_entry_list_push(&r->results, (TestEntry){.index = index, .outcome = outcome});
}

/* One record whose line is `line` (without its newline), with the bytes after it for MSOUT; returns the bytes it
 * used after the line, or `(size_t)-1` when the output is not all there yet. */
static size_t read_record(TestRecords *r, MsSpan line, MsSpan following) {
  MsSpan rest = {0};
  if (starts(line, "\x01MSOUT ", &rest)) {
    MsSpan size_text = {0};
    (void)split_at(rest, ' ', &size_text);
    const size_t size = number(size_text) == (size_t)-1 ? 0 : number(size_text);
    if (following.len < size + 1) {
      return (size_t)-1;
    }
    read_output(r, rest, ms_span_of(following.ptr, size));
    return size + 1;
  }
  if (starts(line, "\x01MSSTART ", &rest)) {
    read_start(r, rest);
  } else if (starts(line, "\x01MSFAULT ", &rest)) {
    read_fault(r, rest);
  } else if (starts(line, "\x01MSTEST ", &rest)) {
    read_result(r, rest);
  }
  return 0;
}

void test_records_read(TestRecords *r, MsSpan text) {
  size_t at = r->consumed;
  while (at < text.len) {
    size_t end = at;
    while (end < text.len && text.ptr[end] != '\n') {
      end++;
    }
    if (end >= text.len) {
      break;
    }
    const size_t used = read_record(r, ms_span_of(text.ptr + at, end - at),
                                    ms_span_of(text.ptr + end + 1, text.len - end - 1));
    if (used == (size_t)-1) {
      break;
    }
    at = end + 1 + used;
    r->consumed = at;
  }
}
