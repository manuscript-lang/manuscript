/* The fault record encoder and writer. See record.h. */
#include "runtime/core/record.h"

#include "base/alloc.h"
#include "runtime/sys/sys.h"

enum { RECORD_VERSION = 1, FLAG_TRUNCATED = 1, FLAG_HAS_SITE = 2 };

typedef struct Cursor {
  uint8_t *out;
  size_t capacity;
  size_t length; /* bytes given so far, stored or not */
} Cursor;

static void put_bytes(Cursor *cursor, const uint8_t *bytes, size_t count) {
  if (cursor->length <= cursor->capacity && count <= cursor->capacity - cursor->length) {
    __builtin_memcpy(cursor->out + cursor->length, bytes, count);
  }
  cursor->length += count;
}

static void put_u8(Cursor *cursor, uint8_t value) { put_bytes(cursor, &value, 1); }

static void put_u32(Cursor *cursor, uint32_t value) {
  const uint8_t bytes[4] = {(uint8_t)value, (uint8_t)(value >> 8), (uint8_t)(value >> 16), (uint8_t)(value >> 24)};
  put_bytes(cursor, bytes, sizeof bytes);
}

/* A length is a u32 on the wire; everything the runtime puts here is far smaller. */
static uint32_t wire_length(size_t length) { return length > UINT32_MAX ? UINT32_MAX : (uint32_t)length; }

static void put_string(Cursor *cursor, MsSpan text) {
  put_u32(cursor, wire_length(text.len));
  put_bytes(cursor, text.ptr, text.len);
}

static void put_c_string(Cursor *cursor, const char *text) {
  put_string(cursor, ms_span_of_text(text));
}

static size_t frame_total(const MsFrameList *first, const MsFrameList *second) {
  return (first == NULL ? 0 : first->count) + (second == NULL ? 0 : second->count);
}

static void put_frames(Cursor *cursor, const MsFrameList *list) {
  if (list == NULL) {
    return;
  }
  for (size_t i = 0; i < list->count; i++) {
    put_c_string(cursor, list->frames[i].file);
    put_u32(cursor, list->frames[i].line);
    put_c_string(cursor, list->frames[i].function);
    put_u32(cursor, list->frames[i].repeated);
  }
}

size_t ms_fault_record_encode(const MsFaultRecord *record, uint8_t *out, size_t capacity) {
  Cursor cursor = {.out = out, .capacity = capacity};
  static const uint8_t magic[4] = {'M', 'S', 'F', 'R'};
  put_bytes(&cursor, magic, sizeof magic);
  put_u8(&cursor, RECORD_VERSION);
  put_u32(&cursor, record->pid);
  put_u8(&cursor, (uint8_t)record->kind);
  const bool truncated = record->frames != NULL && record->frames->truncated;
  put_u8(&cursor, (uint8_t)((truncated ? FLAG_TRUNCATED : 0) | (record->has_site ? FLAG_HAS_SITE : 0)));
  put_string(&cursor, record->message);
  put_u32(&cursor, wire_length(frame_total(record->frames, record->started)));
  put_frames(&cursor, record->frames);
  put_frames(&cursor, record->started);
  put_u32(&cursor, wire_length(record->note_count));
  for (size_t i = 0; i < record->note_count; i++) {
    put_string(&cursor, ms_span_of(record->notes[i].bytes, record->notes[i].length));
  }
  if (record->has_site) {
    put_string(&cursor, record->site);
  }
  return cursor.length;
}

/* A record with only a message is small; the stack holds it, so a message of up to this size allocates nothing. */
enum { SMALL_RECORD_BYTES = 1024 };

void ms_fault_record_write(MsFaultKind kind, MsSpan message, bool has_site, MsSpan site) {
  const MsFaultRecord record = {.pid = ms_sys_process_id(),
                  .kind = kind,
                  .message = message,
                  .has_site = has_site,
                  .site = site};
  uint8_t buffer[SMALL_RECORD_BYTES];
  const size_t needed = ms_fault_record_encode(&record, buffer, sizeof buffer);
  if (needed <= sizeof buffer) {
    ms_sys_fault_record_write(ms_span_of(buffer, needed));
    return;
  }
  uint8_t *const large = ms_alloc(needed);
  (void)ms_fault_record_encode(&record, large, needed);
  ms_sys_fault_record_write(ms_span_of(large, needed));
  ms_free(large);
}
