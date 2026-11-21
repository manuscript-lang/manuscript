/* runtime/std/stream.h: the host stream over a file descriptor, shared by @std/fs file handles and (next to them)
 * @std/io. A stream is an MsObj whose drop closes an owned descriptor. Reads and writes of a regular file run on the
 * blocking pool; those of a descriptor the scheduler can wait for park the task until it is ready, so a stop request
 * interrupts them. Failures of a transfer are MS_STATUS_FAILED with the text `read name: reason`. */
#ifndef MS_RUNTIME_STD_STREAM_H
#define MS_RUNTIME_STD_STREAM_H

#include <uv.h>

#include "base/desc.h"
#include "runtime/std/fail.h"

typedef struct MsStream {
  MsObj header; /* must be first: the runtime drops the handle through it */
  uv_file fd;
  bool owned;
  bool closed;
  bool waitable; /* the scheduler can wait for the descriptor; otherwise its transfers run on the blocking pool */
  bool no_read;  /* the open mode forbids reading or writing: invalid input on every host */
  bool no_write;
  bool append; /* the host ignores a positioned write's offset, so it is invalid input */
  MsString name; /* the path, for error messages */
} MsStream;

typedef enum MsStreamAccess { MS_STREAM_ANY, MS_STREAM_READ, MS_STREAM_WRITE } MsStreamAccess;

/* A stream over `fd`, which it closes when `owned`; `name` is copied. */
MsStream *ms_stream_new(uv_file fd, bool owned, MsSpan name);
/* A stream over a file opened with the libuv `flags` (UV_FS_O_*). */
MsStream *ms_stream_file(uv_file fd, int flags, MsSpan name);
/* A second stream over a duplicate of the file's descriptor, closed on its own; it shares the file position. */
bool ms_stream_duplicate(const MsStream *stream, MsStream **out, MsFail *fail);

/* Admits an operation: a closed stream is MS_STATUS_CLOSED, a pending stop request fails, and the open mode must allow
 * `access` (invalid input otherwise). False with `fail` set. */
bool ms_stream_admit(const MsStream *stream, MsStreamAccess access, MsFail *fail);

/* One read or write of up to `length` bytes at the current position, waiting for the descriptor first when it can be
 * waited on. `*count` is what was transferred. */
bool ms_stream_read_raw(const MsStream *stream, uint8_t *buffer, size_t length, size_t *count, MsFail *fail);
bool ms_stream_write_raw(const MsStream *stream, const uint8_t *data, size_t length, size_t *count, MsFail *fail);

/* Closes the descriptor once: false with `fail` set when the release failed. */
bool ms_stream_close(MsStream *stream, MsFail *fail);

#endif
