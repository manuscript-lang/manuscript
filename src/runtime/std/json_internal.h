/* What the @std/data/json natives share: a growable output buffer, the parse event interface between the
 * scanner and the two things that consume it (the document of json_doc.c and the tree builder of
 * json_tree.c), and the writer that json_tree.c walks into. */
#ifndef MS_RUNTIME_STD_JSON_INTERNAL_H
#define MS_RUNTIME_STD_JSON_INTERNAL_H

#include <stdbool.h>
#include <string.h>

#include "base/alloc.h"
#include "runtime/std/json.h"
#include "base/string.h"
#include "base/list.h"
#include "base/safe.h"

/* The deepest container nesting a parse accepts or a write produces, and the widest indent a write honors. */
enum { JSON_DEPTH_CEILING = 100000, JSON_INDENT_CEILING = 10 };

/* What the scanner's inner steps answer besides a status: another value follows. */
enum { JSON_MORE = 255 };

/* ---- output buffer ---- */

/* Bytes under a size limit. */
typedef struct JsonBuffer {
  MsList bytes; /* owned; empty until the first append */
  size_t limit; /* the most bytes `bytes.len` may reach */
} JsonBuffer;

/* Each returns false, changing nothing, when the bytes would pass the limit. */
MS_NODISCARD bool json_buffer_append(JsonBuffer *buffer, MsSpan bytes);
MS_NODISCARD bool json_buffer_push(JsonBuffer *buffer, uint8_t byte);
MS_NODISCARD bool json_buffer_fill(JsonBuffer *buffer, uint8_t byte, size_t count);
void json_buffer_free(JsonBuffer *buffer);

/* ---- parse events ---- */

/* The text of a string, key or number: borrowed from the scanner, valid until the sink returns. A string
 * without escapes is a span of the source (`source_offset` says where); a decoded one is scratch
 * (`source_offset` is JSON_DECODED). */
#define JSON_DECODED ((size_t)SIZE_MAX)
typedef struct JsonText {
  MsSpan bytes;
  size_t source_offset;
} JsonText;

/* What the scanner reports, in document order. Each function returns MS_STATUS_OK, MS_STATUS_LIMIT_EXCEEDED,
 * or (from `close`) MS_STATUS_INVALID_DATA for an object with a repeated key. */
typedef struct JsonSinkOps {
  uint8_t (*null)(void *sink);
  uint8_t (*boolean)(void *sink, bool value);
  uint8_t (*number)(void *sink, JsonText text);
  uint8_t (*string)(void *sink, JsonText text);
  uint8_t (*key)(void *sink, JsonText text);
  uint8_t (*open)(void *sink, bool is_array);
  uint8_t (*close)(void *sink, bool is_array);
} JsonSinkOps;

/* The limits of one parse; the byte budget was checked by json_limits. */
typedef struct JsonLimits {
  size_t max_depth;
  size_t max_values;
} JsonLimits;

/* Where a failed scan stopped: the byte offset, and whether it stopped at a repeated object key. */
typedef struct JsonStop {
  size_t at;
  bool duplicate;
} JsonStop;

/* Reads the optional budgets (`has_*`, value) of a parse into limits for text of `length` bytes.
 * MS_STATUS_INVALID_INPUT for a negative one, MS_STATUS_LIMIT_EXCEEDED for text over its byte budget or too
 * long for a string value. */
MS_NODISCARD uint8_t json_limits(size_t length, uint8_t has_max_bytes, int64_t max_bytes,
                                 uint8_t has_max_depth, int64_t max_depth, uint8_t has_max_values,
                                 int64_t max_values, JsonLimits *out);

/* Scans exactly one value of `text` into `ops`. MS_STATUS_OK, MS_STATUS_INVALID_DATA for a syntax error
 * (`stop` says where, and whether it was a repeated key) or MS_STATUS_LIMIT_EXCEEDED. */
MS_NODISCARD uint8_t json_scan(MsSpan text, JsonLimits limits, const JsonSinkOps *ops, void *sink,
                               JsonStop *stop);

/* `line L, column C: <reason>` for a syntax error, as an owned string. */
void json_explain(MsSpan text, JsonStop stop, MsString *out);

/* Whether `text` is exactly one JSON number. */
bool json_number_valid(MsSpan text);

/* ---- the writer ---- */

typedef struct JsonWriter JsonWriter;

void json_writer_item(JsonWriter *writer);
void json_writer_key(JsonWriter *writer, MsSpan name);
void json_writer_begin(JsonWriter *writer, bool is_array);
void json_writer_end(JsonWriter *writer, bool is_array);

#endif
