/* The host stream of @std/io and @std/fs files, shared by stream.c, file.c and io.c. */
#ifndef MS_STD_STREAM_H
#define MS_STD_STREAM_H

#include "fs_support.h"
#include "ms_rt/stream.h"

struct MsStream {
    MsObj header; /* must be first: the runtime drops the handle through it */
    MsSysFd fd;
    MsSysFdKind kind; /* how reads block: MS_SYS_FD_FILE reads run on the blocking pool, the others are waited on */
    bool shares_output; /* standard output or error: shares the descriptor with the runtime's buffered print */
    bool owned;
    bool closed;
    bool no_read; /* the open mode forbids reading or writing: invalid input on every host */
    bool no_write;
    bool append; /* the host ignores a positioned write's offset, so it is invalid input */
    bool file;   /* an @std/fs file handle: flushing synchronizes the file */
#ifdef _WIN32
    bool adopted; /* a blocking pipe the scheduler adopted (a child's piped stream): its transfers run on the pool */
#endif
    char *name; /* owned (malloc), NUL-terminated: the path for error messages */
    size_t name_length;
};

typedef enum { MS_STREAM_ANY, MS_STREAM_READ, MS_STREAM_WRITE } MsStreamAccess;

static inline MsBytes ms_stream_name(const MsStream *stream) { return ms_bytes_of((const uint8_t *)stream->name, stream->name_length); }

/* A stream over an @std/fs file opened with the host `flags` (MS_SYS_O_*). */
MsStream *ms_stream_file(MsSysFd fd, int32_t flags, MsBytes name);
/* A second stream over a duplicate of the file's descriptor, closed on its own; it shares the file position. */
bool ms_stream_duplicate(const MsStream *stream, MsStream **out, MsFsFail *fail);

/* Admits an operation: a closed stream is STATUS_CLOSED, a pending stop request fails, and the open mode must allow
 * `access` (invalid input otherwise). False with `fail` set. */
bool ms_stream_admit(const MsStream *stream, MsStreamAccess access, MsFsFail *fail);

/* Whether reads and writes of the descriptor run on the blocking pool (a regular file). */
static inline bool ms_stream_regular(const MsStream *stream) { return stream->kind == MS_SYS_FD_FILE; }

/* One read(2) / write(2) of a regular file on the blocking pool, others inline; failures are `read name: reason`. */
bool ms_stream_read_raw(const MsStream *stream, uint8_t *buffer, size_t capacity, size_t *count, MsFsFail *fail);
bool ms_stream_write_raw(const MsStream *stream, const uint8_t *data, size_t length, size_t *count, MsFsFail *fail);

/* Closes the descriptor once: false with `fail` set when the release failed. */
bool ms_stream_close(MsStream *stream, MsFsFail *fail);
/* One read of up to `max` bytes (a chunk of at most 64 KiB) into `data`; `*eof` at the end of the stream. */
bool ms_stream_read(MsStream *stream, bool has_max, int64_t max, MsFsBuffer *data, bool *eof, MsFsFail *fail);
bool ms_stream_write(MsStream *stream, MsBytes data, MsFsFail *fail);

#ifdef _WIN32
/* Windows waits for console input (stream_win.c). */
bool ms_stream_win_wait_console(const MsStream *stream, MsFsFail *fail);
#endif

#endif
