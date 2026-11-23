/* The fault records a test output capture keeps: the promise table stores the record of a task that faulted under a
 * capture, and the test runner takes it (msrt_test_capture_fault in src/runtime/entry/test_support.c). */
#include "runtime/core/fault_kept.h"

#include "base/alloc.h"
#include "base/list.h"
#include "base/safe.h"
#include "runtime/core/fault.h"
#include "runtime/sys/spin.h"
#include "runtime/sys/sys.h"

typedef struct KeptFault {
  uint64_t capture;
  uint8_t *bytes; /* the encoded record, owned */
  size_t length;
} KeptFault;

MS_LIST_DEFINE(KeptList, kept_list, KeptFault)

static struct {
  MsSpin lock;
  KeptList list;
} kept = {.lock = MS_SPIN_INIT};

void ms_test_keep_fault(uint64_t capture, const MsFaultText *text) {
  const MsFaultDetail *const detail = text->detail;
  const MsFaultRecord record = {.pid = ms_sys_process_id(),
                  .kind = detail != NULL ? detail->kind : MS_FAULT_KIND_FAULT,
                  .message = ms_span_of(text->bytes, detail != NULL ? detail->message_length : text->length),
                  .frames = detail != NULL ? &detail->frames : NULL,
                  .started = detail != NULL ? &detail->started : NULL,
                  .notes = detail != NULL ? detail->notes.ptr : NULL,
                  .note_count = detail != NULL ? detail->notes.len : 0};
  const size_t needed = ms_fault_record_encode(&record, NULL, 0);
  uint8_t *const bytes = ms_alloc(needed);
  (void)ms_fault_record_encode(&record, bytes, needed);
  ms_spin_lock(&kept.lock);
  size_t at = 0;
  while (at < kept.list.len && kept.list.ptr[at].capture != capture) {
    at++;
  }
  const KeptFault entry = {.capture = capture, .bytes = bytes, .length = needed};
  if (at < kept.list.len) {
    ms_free(kept.list.ptr[at].bytes); /* only the last fault of a capture is kept */
    kept.list.ptr[at] = entry;
  } else {
    kept_list_push(&kept.list, entry);
  }
  ms_spin_unlock(&kept.lock);
}

void ms_test_drop_fault(uint64_t capture) {
  uint8_t *bytes = NULL;
  ms_spin_lock(&kept.lock);
  for (size_t at = 0; at < kept.list.len; at++) {
    if (kept.list.ptr[at].capture == capture) {
      bytes = kept.list.ptr[at].bytes;
      kept.list.ptr[at] = kept.list.ptr[--kept.list.len];
      break;
    }
  }
  ms_spin_unlock(&kept.lock);
  ms_free(bytes);
}

void ms_test_take_fault(uint64_t capture, uint8_t **bytes, size_t *length) {
  *bytes = NULL;
  *length = 0;
  ms_spin_lock(&kept.lock);
  for (size_t at = 0; at < kept.list.len; at++) {
    if (kept.list.ptr[at].capture == capture) {
      *bytes = kept.list.ptr[at].bytes;
      *length = kept.list.ptr[at].length;
      kept.list.ptr[at] = kept.list.ptr[--kept.list.len];
      break;
    }
  }
  ms_spin_unlock(&kept.lock);
}

void ms_test_release_faults(void) {
  ms_spin_lock(&kept.lock);
  for (size_t at = 0; at < kept.list.len; at++) {
    ms_free(kept.list.ptr[at].bytes);
  }
  kept_list_free(&kept.list);
  ms_spin_unlock(&kept.lock);
}
