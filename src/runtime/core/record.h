/* The fault record the CLI reads: what a process leaves in the file MS_FAULT_RECORD names as it ends.
 *
 * Little endian: the magic, a version byte (2), the writer's pid, the kind code, a flags byte, the message, the
 * frames, the frames of where a task was started, the cleanup notes and the site, each list led by its count, strings
 * length-prefixed. The encoder is a cursor over a buffer that may be too small: it counts every byte it
 * is given and stores only what fits, so one pass sizes the record and a second fills it. The text on standard
 * error is for people and is never parsed. */
#ifndef MS_RUNTIME_CORE_RECORD_H
#define MS_RUNTIME_CORE_RECORD_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "abi/fault.h"
#include "base/safe.h"
#include "runtime/core/frames.h"

/* A fault raised while another was being reported: its message, owned by whoever holds the note. */
typedef struct MsFaultNote {
  uint8_t *bytes;
  size_t length;
} MsFaultNote;

/* The record as the CLI reads it. Frames, cleanup faults and the site are optional. */
typedef struct MsFaultRecord {
  uint32_t pid;
  MsFaultKind kind;
  MsSpan message;
  const MsFrameList *frames;  /* may be NULL */
  const MsFrameList *started; /* where the task was started, when it ran as one; may be NULL */
  const MsFaultNote *notes;   /* `note_count` of them */
  size_t note_count;
  bool has_site; /* a failed test's `file:line:column` follows */
  MsSpan site;
} MsFaultRecord;

/* Encodes `record`. Returns the size the encoding needs, and writes it only when that fits in `capacity`. */
size_t ms_fault_record_encode(const MsFaultRecord *record, uint8_t *out, size_t capacity) MS_NONNULL_ARGS(1);
/* Writes a record holding only `kind` and `message` (and `site` when `has_site`) to the file MS_FAULT_RECORD names,
 * if there is one. For a failed test and a stop that cleanup did not survive. Allocates only for a record that does
 * not fit in 1 KiB. */
void ms_fault_record_write(MsFaultKind kind, MsSpan message, bool has_site, MsSpan site);

#endif
