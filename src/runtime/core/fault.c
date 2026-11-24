/* Raising a fault and reporting it. See fault.h.
 *
 * ms_fault does the work in this order: capture the source frames, build the report (the message, then the
 * frames as lines), run the cleanups, and leave by the innermost guard or end the process. A fault raised by a
 * cleanup adds a note to the report in progress and runs the cleanups that are left, so one failing cleanup
 * does not stop the others. */
#include "base/alloc.h"
#include "base/fatal.h"
#include "base/strbuild.h"
#include "runtime/core/fault.h"
#include "runtime/core/scheduler.h"
#include "runtime/sys/sys.h"

#define MS_NOINLINE __attribute__((noinline))

/* Appends `\n  at file:line in function` for each frame, the repeat notes and the omission note. */
static void render_frames(MsStrBuild *out, const MsFrameList *list) {
  for (size_t i = 0; i < list->count; i++) {
    const MsFrame *const frame = &list->frames[i];
    ms_strbuild_append_text(out, "\n  at ");
    ms_strbuild_append_text(out, frame->file);
    ms_strbuild_append_text(out, ":");
    ms_strbuild_append_u64(out, frame->line);
    ms_strbuild_append_text(out, " in ");
    ms_strbuild_append_text(out, frame->function);
    if (frame->repeated > 0) {
      ms_strbuild_append_text(out, "\n  ... previous frame repeated ");
      ms_strbuild_append_u64(out, frame->repeated);
      ms_strbuild_append_text(out, " more times");
    }
  }
  if (list->truncated) {
    ms_strbuild_append_text(out, "\n  ... outer frames omitted");
  }
}

/* ---- the fault in progress ---- */

typedef struct MsFaultFlight MsFaultFlight;

/* The state of the fault a task is reporting; it lives in the frame of ms_fault, which never returns. */
struct MsFaultFlight {
  bool out_of_memory;    /* an allocation was refused while reporting: the next refusal is fatal */
  MsStrBuild text;       /* the report so far */
  MsFaultDetail *detail; /* owned until the report is sealed; NULL while the process is ending */
};

static void add_note(MsFaultDetail *detail, MsSpan message) {
  uint8_t *const copy = ms_alloc(message.len == 0 ? 1 : message.len);
  if (message.len > 0) {
    __builtin_memcpy(copy, message.ptr, message.len);
  }
  ms_fault_note_list_push(&detail->notes, (MsFaultNote){.bytes = copy, .length = message.len});
}

/* Points the started frame of `detail` at an owned copy of `file` and `function`. */
static void set_started(MsFaultDetail *detail, MsSpan file, uint32_t line, MsSpan function) {
  char *const names = ms_alloc(file.len + function.len + 2);
  __builtin_memcpy(names, file.ptr, file.len);
  names[file.len] = 0;
  __builtin_memcpy(names + file.len + 1, function.ptr, function.len);
  names[file.len + 1 + function.len] = 0;
  ms_free(detail->started_names);
  detail->started_names = names;
  detail->started = (MsFrameList){.frames = {{.file = names, .function = names + file.len + 1, .line = line}}, .count = 1};
}

static void detail_free(MsFaultDetail *detail) {
  if (detail == NULL) {
    return;
  }
  for (size_t i = 0; i < detail->notes.len; i++) {
    ms_free(detail->notes.ptr[i].bytes);
  }
  ms_fault_note_list_free(&detail->notes);
  ms_free(detail->started_names);
  ms_free(detail);
}

void ms_fault_text_release(MsFaultText *text) {
  ms_free(text->bytes);
  detail_free(text->detail);
  *text = (MsFaultText){0};
}

MsFaultText ms_fault_text_clone(const MsFaultText *text) {
  MsFaultText copy = {.length = text->length};
  if (text->bytes != NULL) {
    copy.bytes = ms_alloc(text->length == 0 ? 1 : text->length);
    __builtin_memcpy(copy.bytes, text->bytes, text->length);
  }
  if (text->detail != NULL) {
    copy.detail = ms_alloc_zeroed(sizeof *copy.detail);
    *copy.detail = *text->detail;
    copy.detail->notes = (MsFaultNoteList){0};
    copy.detail->started_names = NULL;
    if (text->detail->started.count != 0 && text->detail->started_names != NULL) {
      const MsFrame *const frame = &text->detail->started.frames[0];
      set_started(copy.detail, ms_span_of_text(frame->file), frame->line, ms_span_of_text(frame->function));
    }
    for (size_t i = 0; i < text->detail->notes.len; i++) {
      add_note(copy.detail, ms_span_of(text->detail->notes.ptr[i].bytes, text->detail->notes.ptr[i].length));
    }
  }
  return copy;
}

static MsStackWindow window_of(const MsUnwind *unwind) {
  return (MsStackWindow){.low = unwind->stack_low, .high = unwind->stack_high, .chain = unwind->stack_chain};
}

/* The report with the cleanup faults appended, handed over with its detail. */
static MsFaultText seal(MsFaultFlight *flight) {
  MsFaultDetail *const detail = flight->detail;
  for (size_t i = 0; i < detail->notes.len; i++) {
    ms_strbuild_append_text(&flight->text, "\ncleanup fault: ");
    ms_strbuild_append(&flight->text, ms_span_of(detail->notes.ptr[i].bytes, detail->notes.ptr[i].length));
  }
  flight->detail = NULL;
  const MsFaultText sealed = {.bytes = flight->text.bytes.ptr, .length = flight->text.bytes.len, .detail = detail};
  flight->text = ms_strbuild_new(); /* the text now belongs to the report */
  return sealed;
}

/* ---- ending ---- */

static void flush_output(void) {
  const MsSched *const sched = ms_sched_if_any();
  if (sched != NULL && sched->hooks.flush_output != NULL) {
    sched->hooks.flush_output();
  }
}

/* The record of a report that reaches the process's end. */
static void write_report_record(const MsFaultText *text) {
  const MsFaultDetail *const detail = text->detail;
  MsFaultRecord record = {.pid = ms_sys_process_id(),
                          .kind = MS_FAULT_KIND_FAULT,
                          .message = ms_span_of(text->bytes, text->length)};
  if (detail != NULL) {
    record.kind = detail->kind;
    record.message = ms_span_of(text->bytes, detail->message_length);
    record.frames = &detail->frames;
    record.started = &detail->started;
    record.notes = detail->notes.ptr;
    record.note_count = detail->notes.len;
  }
  const size_t needed = ms_fault_record_encode(&record, NULL, 0);
  uint8_t *const encoded = ms_alloc(needed);
  (void)ms_fault_record_encode(&record, encoded, needed);
  ms_sys_fault_record_write(ms_span_of(encoded, needed));
  ms_free(encoded);
}

void ms_fault_exit(MsFaultText *text) {
  MsSched *const sched = ms_sched();
  /* Reporting allocates; a refusal now must end the process, not start another report. */
  MsFaultFlight reporting = {.out_of_memory = true};
  ms_task_running()->unwind.flight = &reporting;
  const MsFaultKind kind = text->detail == NULL ? MS_FAULT_KIND_FAULT : text->detail->kind;
  MsStrBuild line = ms_strbuild_new();
  ms_strbuild_append(&line, ms_span_of(text->bytes, text->length));
  ms_strbuild_append_text(&line, "\n");
  flush_output();
  ms_sys_stderr_write(ms_strbuild_span(&line));
  write_report_record(text);
  sched->hooks.exit_process(ms_fault_exit_status(kind));
  for (;;) {
    /* The hook ends the process and never returns. */
  }
}

enum { FATAL_RECORD_MESSAGE_BYTES = 512 };

void ms_fault_fatal(MsFaultKind kind, MsSpan message) {
  flush_output();
  ms_sys_stderr_write(message);
  ms_sys_stderr_write(ms_span_of_text("\n"));
  const size_t kept = message.len < FATAL_RECORD_MESSAGE_BYTES ? message.len : FATAL_RECORD_MESSAGE_BYTES;
  ms_fault_record_write(kind, ms_span_of(message.ptr, kept), false, ms_span_of(NULL, 0));
  ms_sys_exit_now(ms_fault_exit_status(kind));
}

/* Hands the sealed report to the innermost guard, or ends the process when none is open. */
MS_NORETURN static void finish(MsUnwind *unwind, MsFaultFlight *flight) {
  MsFaultText text = seal(flight);
  unwind->flight = NULL;
  if (unwind->guards.len > 0) {
    (void)ms_guard_leave(MS_GUARD_FAULT, text);
  }
  ms_fault_exit(&text);
}

/* ---- raising ---- */

/* A fault raised by a cleanup while `flight` is being reported. */
MS_NORETURN static void fault_in_cleanup(MsUnwind *unwind, MsFaultKind kind, MsSpan message, bool out_of_memory,
                                         void *owned) {
  MsFaultFlight *const flight = unwind->flight;
  if (flight->detail == NULL || (out_of_memory && flight->out_of_memory)) {
    ms_fault_fatal(kind, message);
  }
  flight->out_of_memory = flight->out_of_memory || out_of_memory;
  add_note(flight->detail, message);
  ms_free(owned);
  ms_cleanup_run_pending();
  finish(unwind, flight);
}

/* Whether a frame belongs to the standard library, whose files are shown as `@std/...`. */
static bool is_library_frame(const MsFrame *frame) {
  return ms_span_starts_with(ms_span_of_text(frame->file), ms_span_of_text("@std/"));
}

/* The frames below the program's last one are the library code that ran it (a test runner waiting on the promise
 * that holds the test): the report ends at the program's frame, as an optimized build's does once those calls are
 * inlined away. A list with no program frame at all is left whole. */
static void drop_trailing_library_frames(MsFrameList *list) {
  if (list->truncated) {
    return; /* the walk stopped early: these are not the bottom frames */
  }
  size_t last = list->count;
  while (last > 0 && is_library_frame(&list->frames[last - 1])) {
    last--;
  }
  if (last > 0) {
    list->count = last;
  }
}

/* The one place a fault starts. Not inlined: the frame walk starts at its frame, so what it adds to the stack is
 * the same on every path. */
MS_NORETURN MS_NOINLINE static void raise_fault(MsFaultKind kind, MsSpan message, bool out_of_memory,
                                                void *owned) {
  MsUnwind *const unwind = &ms_task_running()->unwind;
  if (unwind->flight != NULL) {
    fault_in_cleanup(unwind, kind, message, out_of_memory, owned);
  }
  MsFaultFlight flight = {.out_of_memory = out_of_memory, .text = ms_strbuild_new()};
  unwind->flight = &flight;
  flight.detail = ms_alloc_zeroed(sizeof *flight.detail);
  flight.detail->kind = kind;
  flight.detail->message_length = message.len;
  ms_strbuild_append(&flight.text, message);
  ms_free(owned); /* the message is copied: a fault never returns, so its builder is released here */
  ms_frames_collect((uintptr_t)__builtin_frame_address(0), (uintptr_t)raise_fault, window_of(unwind),
                    &flight.detail->frames);
  drop_trailing_library_frames(&flight.detail->frames);
  render_frames(&flight.text, &flight.detail->frames);
  /* A fault that leaves a guarded task abandons its frames, so drop cleanups release what they own; an
   * unguarded fault ends the process. */
  unwind->unwind_drops = unwind->guards.len > 0;
  ms_cleanup_run_pending();
  finish(unwind, &flight);
}

/* Builds the report of a fault that is posted instead of raised, and leaves it with the task. */
MS_NOINLINE static void post_fault(MsFaultKind kind, MsSpan message, void *owned) {
  MsUnwind *const unwind = &ms_task_running()->unwind;
  if (unwind->pending.detail != NULL) {
    add_note(unwind->pending.detail, message); /* a fault of a close that ran for the posted one */
    ms_free(owned);
    ms_cancel_deliver(); /* the exit that ran the close may return without resuming */
    return;
  }
  MsFaultFlight flight = {.text = ms_strbuild_new()};
  flight.detail = ms_alloc_zeroed(sizeof *flight.detail);
  flight.detail->kind = kind;
  flight.detail->message_length = message.len;
  ms_strbuild_append(&flight.text, message);
  ms_free(owned);
  ms_frames_collect((uintptr_t)__builtin_frame_address(0), (uintptr_t)post_fault, window_of(unwind),
                    &flight.detail->frames);
  drop_trailing_library_frames(&flight.detail->frames);
  render_frames(&flight.text, &flight.detail->frames);
  unwind->pending = seal(&flight);
  ms_cancel_deliver();
}

void ms_fault_post(MsFaultKind kind, MsSpan message) { post_fault(kind, message, NULL); }

void ms_fault_post_built(MsFaultKind kind, MsStrBuild *message) {
  post_fault(kind, ms_strbuild_span(message), message->bytes.ptr);
}

void ms_fault_post_text(MsFaultKind kind, const char *message) { post_fault(kind, ms_span_of_text(message), NULL); }

void ms_fault(MsFaultKind kind, MsSpan message) { raise_fault(kind, message, false, NULL); }

void ms_fault_built(MsFaultKind kind, MsStrBuild *message) {
  raise_fault(kind, ms_strbuild_span(message), false, message->bytes.ptr);
}

void ms_fault_text(MsFaultKind kind, const char *message) { ms_fault(kind, ms_span_of_text(message)); }

enum { OOM_MESSAGE_BYTES = 160 };

/* Appends the decimal digits of `value` at `out`, which holds at least 20 bytes; returns how many. */
static size_t put_decimal(uint8_t *out, uint64_t value) {
  uint8_t reversed[20];
  size_t count = 0;
  do {
    reversed[count++] = (uint8_t)('0' + value % 10);
    value /= 10;
  } while (value != 0);
  for (size_t i = 0; i < count; i++) {
    out[i] = reversed[count - 1 - i];
  }
  return count;
}

/* The message is built on the stack: reporting an allocation that was refused cannot allocate. */
void ms_fault_out_of_memory(size_t bytes) {
  static const char before[] = "out of memory: could not allocate ";
  static const char after[] = " bytes; hold less data at once, or process it in chunks or as a stream";
  _Static_assert(sizeof before - 1 + 20 + sizeof after - 1 <= OOM_MESSAGE_BYTES, "the message fits its buffer");
  /* A size that does not fit an Int is shown as the largest Int, as the message always has. */
  const uint64_t shown = bytes > (uint64_t)INT64_MAX ? (uint64_t)INT64_MAX : bytes;
  uint8_t message[OOM_MESSAGE_BYTES];
  size_t length = sizeof before - 1;
  __builtin_memcpy(message, before, length);
  length += put_decimal(message + length, shown);
  __builtin_memcpy(message + length, after, sizeof after - 1);
  length += sizeof after - 1;
  raise_fault(MS_FAULT_KIND_OUT_OF_MEMORY, ms_span_of(message, length), true, NULL);
}

/* base reports its unrecoverable conditions as Manuscript faults. */
static void raise_base_fatal(MsFatalKind kind, MsSpan message) {
  raise_fault(ms_fault_kind_of_fatal(kind), message, kind == MS_FATAL_OUT_OF_MEMORY, NULL);
}

void ms_fault_install_base_hook(void) { ms_fatal_install(raise_base_fatal); }

/* ---- reports that outlive the fault ---- */

/* Splits `site` (`file:line in function`, or `file:line:col` with no function) into a frame's parts. False when
 * it names no line. */
static bool site_parts(MsSpan site, MsSpan *file, uint32_t *line, MsSpan *function) {
  size_t colon = 0;
  while (colon < site.len && site.ptr[colon] != ':') {
    colon++;
  }
  size_t at = colon + 1;
  uint64_t number = 0;
  while (at < site.len && site.ptr[at] >= '0' && site.ptr[at] <= '9' && number <= UINT32_MAX) {
    number = number * 10 + (uint64_t)(site.ptr[at++] - '0');
  }
  if (colon == 0 || at <= colon + 1 || number > UINT32_MAX) {
    return false;
  }
  static const char in[] = " in ";
  const size_t in_len = sizeof in - 1;
  const bool named = site.len - at > in_len && __builtin_memcmp(site.ptr + at, in, in_len) == 0;
  *file = ms_span_of(site.ptr, colon);
  *line = (uint32_t)number;
  *function = named ? ms_span_of(site.ptr + at + in_len, site.len - at - in_len) : ms_span_of_text("?");
  return true;
}

void ms_fault_text_add_started(MsFaultText *text, MsSpan site) {
  MsSpan file;
  MsSpan function;
  uint32_t line = 0;
  /* The report names a line of the program: one of the standard library's own starts is left out. */
  if (!site_parts(site, &file, &line, &function) || ms_span_starts_with(file, ms_span_of_text("@std/"))) {
    return;
  }
  if (text->detail == NULL) {
    text->detail = ms_alloc_zeroed(sizeof *text->detail);
    text->detail->kind = MS_FAULT_KIND_FAULT;
    text->detail->message_length = text->length;
  }
  set_started(text->detail, file, line, function);
  /* The report's bytes are an owned block: rebuild it with the new lines on the end. */
  MsStrBuild grown = ms_strbuild_new();
  ms_strbuild_append(&grown, ms_span_of(text->bytes, text->length));
  ms_strbuild_append_text(&grown, "\n  task started by:");
  render_frames(&grown, &text->detail->started);
  ms_free(text->bytes);
  text->bytes = grown.bytes.ptr;
  text->length = grown.bytes.len;
}
