/* What the @std/data/json natives share: a growable output buffer, the parse event interface between the scanner and
 * the two things that consume it (the document of json_doc.c and the tree builder of json_tree.c), and the writer
 * that json_tree.c walks into. */
#ifndef MS_STD_JSON_H
#define MS_STD_JSON_H

#include <stdbool.h>
#include <string.h>

#include "ms_rt/base.h"
#include "ms_rt/string.h"
#include "ms_rt/safe.h"

/* The deepest container nesting a parse accepts or a write produces, and the widest indent a write honors. */
enum { JSON_DEPTH_CEILING = 100000, JSON_INDENT_CEILING = 10 };

/* ---- output buffer ---- */

/* Bytes under a size limit. The allocation always holds one spare byte, so the contents can become a string value
 * (which ends in a NUL) without a copy. */
typedef struct JsonBuffer {
    uint8_t *ptr; /* owned; NULL until the first append */
    size_t length;
    size_t allocated; /* bytes allocated, the spare one included */
    size_t limit;     /* the most bytes `length` may reach */
} JsonBuffer;

/* Each returns false, changing nothing, when the bytes would pass the limit. */
MS_NODISCARD bool json_buffer_append(JsonBuffer *buffer, MsBytes bytes);
MS_NODISCARD bool json_buffer_push(JsonBuffer *buffer, uint8_t byte);
MS_NODISCARD bool json_buffer_fill(JsonBuffer *buffer, uint8_t byte, size_t count);
void json_buffer_free(JsonBuffer *buffer);

/* ---- parse events ---- */

/* The text of a string, key or number (decoded, without quotes): borrowed from the scanner and valid until the sink
 * returns, or until the buffer is released when json_scan keeps it. `offset` is its start in that buffer. */
typedef struct JsonText {
    MsBytes bytes;
    size_t offset;
} JsonText;

/* What the scanner reports, in document order. Each function returns MS_STATUS_OK or
 * MS_STATUS_LIMIT_EXCEEDED; the scanner has rejected a repeated object key before the sink sees the object. */
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

/* Where a failed scan stopped: the byte offset and the reason (a static string: yyjson's, or the repeated key). */
typedef struct JsonStop {
    size_t at;
    const char *reason;
} JsonStop;

/* Reads the optional budgets (`has_*`, value) of a parse into limits for text of `length` bytes. MS_STATUS_INVALID_INPUT
 * for a negative one, MS_STATUS_LIMIT_EXCEEDED for text over its byte budget or too long for a string value. */
MS_NODISCARD uint8_t json_limits(size_t length, uint8_t has_max_bytes, int64_t max_bytes, uint8_t has_max_depth,
                                 int64_t max_depth, uint8_t has_max_values, int64_t max_values, JsonLimits *out);

/* Scans exactly one value of `text` into `ops`. MS_STATUS_OK, MS_STATUS_INVALID_DATA for a syntax error (`stop` says
 * where and why, a repeated object key included) or MS_STATUS_LIMIT_EXCEEDED. The scanner decodes a private copy of
 * the text, which the reported JsonText offsets index. A successful scan hands that copy to `keep` when it is not
 * NULL (the caller frees it) and frees it otherwise; a failed scan always frees it. */
MS_NODISCARD uint8_t json_scan(MsBytes text, JsonLimits limits, const JsonSinkOps *ops, void *sink, JsonStop *stop,
                               JsonBuffer *keep);

/* `line L, column C: <reason>` for a syntax error, as an owned string. */
void json_explain(MsBytes text, JsonStop stop, MsStr *out);

/* Whether `text` is exactly one JSON number. */
bool json_number_valid(MsBytes text);

/* ---- the writer ---- */

typedef struct JsonWriter JsonWriter;

void json_writer_item(JsonWriter *writer);
void json_writer_key(JsonWriter *writer, MsBytes name);
void json_writer_begin(JsonWriter *writer, bool is_array);
void json_writer_end(JsonWriter *writer, bool is_array);

#endif
