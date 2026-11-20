/* Raising a fault and reporting it. See fault.h.
 *
 * ms_fault does the work in this order: capture the source frames, build the report (the message, then the
 * frames as lines), run the cleanups, and leave by the innermost guard or end the process. A fault raised by a
 * cleanup adds a note to the report in progress and runs the cleanups that are left, so one failing cleanup
 * does not stop the others.
 */
#include "alloc.h"
#include "array.h"
#include "fault.h"
#include "ms_rt/alloc.h"
#include "ms_rt/fmt.h"
#include "ms_rt/sys.h"
#include "scheduler.h"

#define MS_NOINLINE __attribute__((noinline))

/* A growable byte string whose storage the buffer owns until it is handed over. */
typedef struct ByteBuffer {
    uint8_t *items; /* owned */
    size_t length;
    size_t capacity;
} ByteBuffer;

static void buffer_append(ByteBuffer *buffer, const uint8_t *bytes, size_t count) {
    size_t needed = 0;
    void *items = buffer->items;
    if (!ms_size_add(buffer->length, count, &needed) || !ms_array_reserve(&items, &buffer->capacity, needed, 1)) {
        return; /* a report too large to hold is cut short */
    }
    buffer->items = items;
    if (count > 0) {
        __builtin_memcpy(buffer->items + buffer->length, bytes, count);
    }
    buffer->length = needed;
}

static void buffer_append_text(ByteBuffer *buffer, const char *text) {
    buffer_append(buffer, (const uint8_t *)text, __builtin_strlen(text));
}

static void buffer_append_number(ByteBuffer *buffer, uint64_t value) {
    uint8_t digits[MS_FMT_INTEGER_CAPACITY];
    size_t length = 0;
    if (msrt_fmt_u64(value, digits, sizeof digits, &length)) {
        buffer_append(buffer, digits, length);
    }
}

/* Appends `\n  at file:line in function` for each frame, the repeat notes and the omission note. */
static void render_frames(ByteBuffer *buffer, const MsFrameList *list) {
    for (size_t i = 0; i < list->count; i++) {
        const MsFrame *const frame = &list->frames[i];
        buffer_append_text(buffer, "\n  at ");
        buffer_append_text(buffer, frame->file);
        buffer_append_text(buffer, ":");
        buffer_append_number(buffer, frame->line);
        buffer_append_text(buffer, " in ");
        buffer_append_text(buffer, frame->function);
        if (frame->repeated > 0) {
            buffer_append_text(buffer, "\n  ... previous frame repeated ");
            buffer_append_number(buffer, frame->repeated);
            buffer_append_text(buffer, " more times");
        }
    }
    if (list->truncated) {
        buffer_append_text(buffer, "\n  ... outer frames omitted");
    }
}

/* ---- the fault in progress ---- */

/* The state of the fault a task is reporting; it lives in the frame of ms_fault, which never returns. */
typedef struct MsFaultFlight {
    bool out_of_memory;  /* an allocation was refused while reporting: the next refusal is fatal */
    ByteBuffer text;     /* the report so far */
    MsFaultDetail *detail; /* owned until the report is sealed; NULL while the process is ending */
} MsFaultFlight;

static void add_note(MsFaultDetail *detail, MsBytes message);

static void detail_free(MsFaultDetail *detail) {
    if (detail == NULL) {
        return;
    }
    for (size_t i = 0; i < detail->note_count; i++) {
        msrt_free(detail->notes[i].bytes);
    }
    msrt_free(detail->notes);
    msrt_free(detail);
}

void ms_fault_text_free(MsFaultText *text) {
    msrt_free(text->bytes);
    detail_free(text->detail);
    *text = (MsFaultText){0};
}

MsFaultText ms_fault_text_clone(const MsFaultText *text) {
    MsFaultText copy = {.length = text->length};
    if (text->bytes != NULL) {
        copy.bytes = msrt_alloc(text->length == 0 ? 1 : text->length);
        __builtin_memcpy(copy.bytes, text->bytes, text->length);
    }
    if (text->detail != NULL) {
        copy.detail = msrt_alloc_zeroed(sizeof *copy.detail);
        *copy.detail = *text->detail;
        copy.detail->notes = NULL;
        copy.detail->note_count = 0;
        copy.detail->note_capacity = 0;
        for (size_t i = 0; i < text->detail->note_count; i++) {
            add_note(copy.detail, ms_bytes_of(text->detail->notes[i].bytes, text->detail->notes[i].length));
        }
    }
    return copy;
}

static void add_note(MsFaultDetail *detail, MsBytes message) {
    void *notes = detail->notes;
    if (!ms_array_reserve(&notes, &detail->note_capacity, detail->note_count + 1, sizeof *detail->notes)) {
        return;
    }
    detail->notes = notes;
    uint8_t *const copy = msrt_alloc(message.len == 0 ? 1 : message.len);
    if (message.len > 0) {
        __builtin_memcpy(copy, message.ptr, message.len);
    }
    detail->notes[detail->note_count++] = (MsFaultNote){.bytes = copy, .length = message.len};
}

static MsStackWindow window_of(const MsUnwind *unwind) {
    return (MsStackWindow){.low = unwind->stack_low, .high = unwind->stack_high, .chain = unwind->stack_chain};
}

/* The report with the cleanup faults appended, handed over with its detail. */
static MsFaultText seal(MsFaultFlight *flight) {
    MsFaultDetail *const detail = flight->detail;
    for (size_t i = 0; i < detail->note_count; i++) {
        buffer_append_text(&flight->text, "\ncleanup fault: ");
        buffer_append(&flight->text, detail->notes[i].bytes, detail->notes[i].length);
    }
    flight->detail = NULL;
    return (MsFaultText){.bytes = flight->text.items, .length = flight->text.length, .detail = detail};
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
                            .message = ms_bytes_of(text->bytes, text->length)};
    if (detail != NULL) {
        record.kind = detail->kind;
        record.message = ms_bytes_of(text->bytes, detail->message_length);
        record.frames = &detail->frames;
        record.started = &detail->started;
        record.notes = detail->notes;
        record.note_count = detail->note_count;
    }
    const size_t needed = ms_fault_record_encode(&record, NULL, 0);
    uint8_t *const encoded = msrt_alloc(needed);
    (void)ms_fault_record_encode(&record, encoded, needed);
    ms_sys_fault_record_write(ms_bytes_of(encoded, needed));
    msrt_free(encoded);
}

void ms_fault_exit(MsFaultText *text) {
    MsSched *const sched = ms_sched();
    /* Reporting allocates; a refusal now must end the process, not start another report. */
    MsFaultFlight reporting = {.out_of_memory = true};
    ms_task_running()->unwind.flight = &reporting;
    const MsFaultKind kind = text->detail == NULL ? MS_FAULT_KIND_FAULT : text->detail->kind;
    ByteBuffer line = {0};
    buffer_append(&line, text->bytes, text->length);
    buffer_append_text(&line, "\n");
    flush_output();
    ms_sys_stderr_write(ms_bytes_of(line.items, line.length));
    write_report_record(text);
    sched->hooks.exit_process(ms_fault_exit_status(kind));
    for (;;) {
        /* The hook ends the process and never returns. */
    }
}

enum { FATAL_RECORD_MESSAGE_BYTES = 512 };

void ms_fault_fatal(MsFaultKind kind, MsBytes message) {
    flush_output();
    ms_sys_stderr_write(message);
    ms_sys_stderr_write(ms_bytes_of((const uint8_t *)"\n", 1));
    const size_t kept = message.len < FATAL_RECORD_MESSAGE_BYTES ? message.len : FATAL_RECORD_MESSAGE_BYTES;
    ms_fault_record_write(kind, ms_bytes_of(message.ptr, kept), false, ms_bytes_of(NULL, 0));
    ms_sys_exit_now(ms_fault_exit_status(kind));
}

/* Hands the sealed report to the innermost guard, or ends the process when none is open. */
MS_NORETURN static void finish(MsUnwind *unwind, MsFaultFlight *flight) {
    MsFaultText text = seal(flight);
    unwind->flight = NULL;
    if (unwind->guard_length > 0) {
        (void)ms_guard_leave(MS_GUARD_FAULT, text);
    }
    ms_fault_exit(&text);
}

/* ---- raising ---- */

/* A fault raised by a cleanup while `flight` is being reported. */
MS_NORETURN static void fault_in_cleanup(MsUnwind *unwind, MsFaultKind kind, MsBytes message, bool out_of_memory) {
    MsFaultFlight *const flight = unwind->flight;
    if (flight->detail == NULL || (out_of_memory && flight->out_of_memory)) {
        ms_fault_fatal(kind, message);
    }
    flight->out_of_memory = flight->out_of_memory || out_of_memory;
    add_note(flight->detail, message);
    ms_cleanup_run_pending();
    finish(unwind, flight);
}

/* The one place a fault starts. Not inlined: the frame walk starts at its frame, so what it adds to the stack is
 * the same on every path. */
MS_NORETURN MS_NOINLINE static void raise_fault(MsFaultKind kind, MsBytes message, bool out_of_memory) {
    MsUnwind *const unwind = &ms_task_running()->unwind;
    if (unwind->flight != NULL) {
        fault_in_cleanup(unwind, kind, message, out_of_memory);
    }
    MsFaultFlight flight = {.out_of_memory = out_of_memory};
    unwind->flight = &flight;
    flight.detail = msrt_alloc_zeroed(sizeof *flight.detail);
    flight.detail->kind = kind;
    flight.detail->message_length = message.len;
    buffer_append(&flight.text, message.ptr, message.len);
    ms_frames_collect((uintptr_t)__builtin_frame_address(0), (uintptr_t)raise_fault, window_of(unwind),
                      &flight.detail->frames);
    render_frames(&flight.text, &flight.detail->frames);
    /* A fault that leaves a guarded task abandons its frames, so drop cleanups release what they own; an
     * unguarded fault ends the process. */
    unwind->unwind_drops = unwind->guard_length > 0;
    ms_cleanup_run_pending();
    finish(unwind, &flight);
}

void ms_fault(MsFaultKind kind, MsBytes message) { raise_fault(kind, message, false); }

static const char oom_before[] = "out of memory: could not allocate ";
static const char oom_after[] = " bytes; hold less data at once, or process it in chunks or as a stream";
enum { OOM_MESSAGE_BYTES = 160 };
_Static_assert(sizeof oom_before - 1 + MS_FMT_INTEGER_CAPACITY + sizeof oom_after - 1 <= OOM_MESSAGE_BYTES,
               "the out-of-memory message fits its buffer");

void ms_fault_out_of_memory(size_t bytes) {
    uint8_t message[OOM_MESSAGE_BYTES];
    size_t length = sizeof oom_before - 1;
    __builtin_memcpy(message, oom_before, length);
    size_t digit_count = 0;
    /* A size that does not fit an Int is shown as the largest Int, as the message always has. */
    const uint64_t shown = bytes > (uint64_t)INT64_MAX ? (uint64_t)INT64_MAX : bytes;
    if (!msrt_fmt_u64(shown, message + length, MS_FMT_INTEGER_CAPACITY, &digit_count)) {
        ms_fault_fatal(MS_FAULT_KIND_OUT_OF_MEMORY, ms_bytes_of((const uint8_t *)"out of memory", 13));
    }
    length += digit_count;
    __builtin_memcpy(message + length, oom_after, sizeof oom_after - 1);
    length += sizeof oom_after - 1;
    raise_fault(MS_FAULT_KIND_OUT_OF_MEMORY, ms_bytes_of(message, length), true);
}

/* ---- reports that outlive the fault ---- */

size_t ms_fault_capture_frames(uintptr_t *out, size_t capacity) {
    return ms_frames_capture((uintptr_t)__builtin_frame_address(0), (uintptr_t)ms_fault_capture_frames,
                             window_of(&ms_task_running()->unwind), out, capacity);
}

/* The frames a task was started from begin inside the standard library's `promise`; the report names where the
 * program started it, so those leading frames are left out. */
static void drop_library_frames(MsFrameList *list) {
    size_t skip = 0;
    while (skip < list->count && __builtin_strncmp(list->frames[skip].file, "@std/", 5) == 0) {
        skip++;
    }
    if (skip == 0) {
        return;
    }
    list->count -= skip;
    __builtin_memmove(list->frames, list->frames + skip, list->count * sizeof list->frames[0]);
}

void ms_fault_text_add_started(MsFaultText *text, const uintptr_t *addresses, size_t count) {
    if (text->detail == NULL) {
        text->detail = msrt_alloc_zeroed(sizeof *text->detail);
        text->detail->kind = MS_FAULT_KIND_FAULT;
        text->detail->message_length = text->length;
    }
    MsFrameList *const started = &text->detail->started;
    ms_frames_describe(addresses, count, started);
    drop_library_frames(started);
    if (started->count == 0) {
        return;
    }
    ByteBuffer grown = {.items = text->bytes, .length = text->length, .capacity = text->length};
    buffer_append_text(&grown, "\n  task started by:");
    render_frames(&grown, started);
    text->bytes = grown.items;
    text->length = grown.length;
}

/* The allocator's out-of-memory hook (alloc.h): the full fault path. Weak so a unit test can supply its own. */
__attribute__((weak)) void msalloc_oom(size_t bytes) { ms_fault_out_of_memory(bytes); }
