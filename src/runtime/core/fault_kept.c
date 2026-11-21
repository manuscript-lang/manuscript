/* The fault records a test output capture keeps: the promise table stores the record of a task that faulted under a
 * capture, and the test runner takes it (msrt_test_capture_fault in src/runtime/entry/test_support.c). */
#include "fault_kept.h"

#include "array.h"
#include "fault.h"
#include "spin.h"
#include "ms_rt/alloc.h"
#include "ms_rt/safe.h"
#include "ms_rt/sys.h"

typedef struct KeptFault {
    uint64_t capture;
    uint8_t *bytes; /* the encoded record, owned */
    size_t length;
} KeptFault;

static struct {
    MsSpin lock;
    KeptFault *items;
    size_t length;
    size_t capacity;
} kept = {.lock = MS_SPIN_INIT};

void ms_test_keep_fault(uint64_t capture, const MsFaultText *text) {
    const MsFaultDetail *const detail = text->detail;
    const MsFaultRecord record = {.pid = ms_sys_process_id(),
                                  .kind = detail != NULL ? detail->kind : MS_FAULT_KIND_FAULT,
                                  .message = ms_bytes_of(text->bytes, detail != NULL ? detail->message_length : text->length),
                                  .frames = detail != NULL ? &detail->frames : NULL,
                                  .started = detail != NULL ? &detail->started : NULL,
                                  .notes = detail != NULL ? detail->notes : NULL,
                                  .note_count = detail != NULL ? detail->note_count : 0};
    const size_t needed = ms_fault_record_encode(&record, NULL, 0);
    uint8_t *const bytes = msrt_alloc(needed);
    (void)ms_fault_record_encode(&record, bytes, needed);
    ms_spin_lock(&kept.lock);
    size_t at = 0;
    while (at < kept.length && kept.items[at].capture != capture) {
        at++;
    }
    if (at < kept.length) {
        msrt_free(kept.items[at].bytes); /* only the last fault of a capture is kept */
    } else {
        void *grown = kept.items;
        if (!ms_array_reserve_system(&grown, &kept.capacity, kept.length + 1, sizeof kept.items[0])) {
            ms_spin_unlock(&kept.lock);
            msrt_free(bytes);
            return;
        }
        kept.items = grown;
        kept.length++;
    }
    kept.items[at] = (KeptFault){.capture = capture, .bytes = bytes, .length = needed};
    ms_spin_unlock(&kept.lock);
}

void ms_test_drop_fault(uint64_t capture) {
    uint8_t *bytes = NULL;
    ms_spin_lock(&kept.lock);
    for (size_t at = 0; at < kept.length; at++) {
        if (kept.items[at].capture == capture) {
            bytes = kept.items[at].bytes;
            kept.items[at] = kept.items[--kept.length];
            break;
        }
    }
    ms_spin_unlock(&kept.lock);
    msrt_free(bytes);
}

void ms_test_take_fault(uint64_t capture, uint8_t **bytes, size_t *length) {
    *bytes = NULL;
    *length = 0;
    ms_spin_lock(&kept.lock);
    for (size_t at = 0; at < kept.length; at++) {
        if (kept.items[at].capture == capture) {
            *bytes = kept.items[at].bytes;
            *length = kept.items[at].length;
            kept.items[at] = kept.items[--kept.length];
            break;
        }
    }
    ms_spin_unlock(&kept.lock);
}
