/* runtime/std/stream.h: the host stream over a file descriptor, shared by @std/fs file handles and (next to them)
 * @std/io. A stream is an MsObj whose drop closes an owned descriptor. Reads and writes of a regular file run on the
 * blocking pool; those of a descriptor the scheduler can wait for park the task until it is ready, so a stop request
 * interrupts them. Failures of a transfer are MS_STATUS_FAILED with the text `read name: reason`. */
#ifndef MS_RUNTIME_STD_STREAM_H
#define MS_RUNTIME_STD_STREAM_H

#include <stdatomic.h>
#include <uv.h>

#include "base/bytes.h"
#include "base/desc.h"
#include "runtime/std/fail.h"

/* What a file stream and its duplicates share: the count of streams still open on the descriptor (the last to close
 * closes it) and, for a regular file, the position. libuv has no seek and no dup, so the position is kept here and passed
 * to every uv_fs_read and uv_fs_write as the offset, and a duplicate is another stream over the same descriptor. */
typedef struct MsOpenFile {
  _Atomic int64_t at;
  _Atomic uint32_t references;
  bool tracked; /* a regular file: `at` is its position */
} MsOpenFile;

typedef struct MsStream {
  MsObj header; /* must be first: the runtime drops the handle through it */
  uv_file fd;
  bool owned;
  bool closed;
  bool waitable; /* the scheduler can wait for the descriptor; otherwise its transfers run on the blocking pool */
  bool no_read;  /* the open mode forbids reading or writing: invalid input on every host */
  bool no_write;
  bool append; /* the host ignores a positioned write's offset, so it is invalid input */
  MsOpenFile *file; /* NULL for a descriptor not opened as a file: its own position and no duplicates */
  MsString name;    /* the path, for error messages */
} MsStream;

typedef enum MsStreamAccess { MS_STREAM_ANY, MS_STREAM_READ, MS_STREAM_WRITE } MsStreamAccess;

/* A stream over a file opened with the libuv `flags` (UV_FS_O_*). */
MsStream *ms_stream_file(uv_file fd, int flags, MsSpan name);
/* A second stream over the file's descriptor, closed on its own (the descriptor closes with the last); it shares the
 * file position. */
bool ms_stream_duplicate(const MsStream *stream, MsStream **out, MsFail *fail);

/* Whether `stream` keeps the position of a regular file. */
bool ms_stream_tracked(const MsStream *stream);
/* The offset for the next transfer of `stream`: its tracked position, or -1 for the descriptor's own. */
int64_t ms_stream_offset(const MsStream *stream);
/* Records that `count` bytes were transferred at `offset` (a no-op without a tracked position). A write to an append
 * file lands at its end, wherever the position was, so the position becomes the file's size. */
void ms_stream_advance(const MsStream *stream, int64_t offset, int64_t count, bool write);

/* Admits an operation: a closed stream is MS_STATUS_CLOSED, a pending stop request fails, and the open mode must allow
 * `access` (invalid input otherwise). False with `fail` set. */
bool ms_stream_admit(const MsStream *stream, MsStreamAccess access, MsFail *fail);

/* One read or write of up to `length` bytes at the current position, waiting for the descriptor first when it can be
 * waited on. `*count` is what was transferred. */
bool ms_stream_read_raw(const MsStream *stream, uint8_t *buffer, size_t length, size_t *count, MsFail *fail);

/* One read of up to `max` bytes (a default chunk without one): `*out` is a new buffer; `*eof` when nothing was left. */
bool ms_stream_read(MsStream *stream, bool has_max, int64_t max, MsBytes *out, bool *eof, MsFail *fail);
/* Writes all of `data`. A stream of standard output or error first flushes what the program printed. */
bool ms_stream_write(MsStream *stream, MsSpan data, MsFail *fail);

/* Closes the descriptor once: false with `fail` set when the release failed. */
bool ms_stream_close(MsStream *stream, MsFail *fail);

#endif
