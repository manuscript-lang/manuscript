/* The JSON scanner of @std/data/json: a strict parser that reports a document as events (json.h). It keeps number
 * text as written, rejects repeated object keys, trailing values and unpaired surrogate escapes, and walks the
 * document with an explicit stack, so nesting costs heap and not native stack. It owns the output buffer
 * helpers and the error text of a syntax error too. */
#include <stdio.h>

#include "json.h"
#include "yyjson.h"
#include "ms_rt/alloc.h"
#include "ms_rt/array.h"
#include "ms_rt/chars.h"
#include "ms_rt/strbuild.h"
#include "ms_rt/utf8.h"

/* ---- output buffer ---- */

/* Room for `extra` more bytes. */
MS_NODISCARD static bool buffer_reserve(JsonBuffer *buffer, size_t extra) {
    size_t needed = 0;
    if (!ms_size_add(buffer->length, extra, &needed) || needed > buffer->limit) {
        return false;
    }
    if (!ms_size_add(needed, 1, &needed)) { /* the spare byte */
        return false;
    }
    void *ptr = buffer->ptr;
    if (!ms_array_reserve(&ptr, &buffer->allocated, needed, 1)) {
        return false;
    }
    buffer->ptr = ptr;
    return true;
}

bool json_buffer_append(JsonBuffer *buffer, MsBytes bytes) {
    if (!buffer_reserve(buffer, bytes.len)) {
        return false;
    }
    if (bytes.len != 0) {
        memcpy(buffer->ptr + buffer->length, bytes.ptr, bytes.len);
    }
    buffer->length += bytes.len;
    return true;
}

bool json_buffer_push(JsonBuffer *buffer, uint8_t byte) { return json_buffer_append(buffer, ms_bytes_of(&byte, 1)); }

bool json_buffer_fill(JsonBuffer *buffer, uint8_t byte, size_t count) {
    if (!buffer_reserve(buffer, count)) {
        return false;
    }
    if (count != 0) {
        memset(buffer->ptr + buffer->length, byte, count);
    }
    buffer->length += count;
    return true;
}

void json_buffer_free(JsonBuffer *buffer) {
    msrt_free(buffer->ptr);
    buffer->ptr = NULL;
    buffer->length = 0;
    buffer->allocated = 0;
}

/* ---- limits ---- */

/* An optional non-negative budget; unset is unlimited. */
MS_NODISCARD static bool budget(uint8_t has_value, int64_t value, size_t *out) {
    *out = SIZE_MAX;
    if (!has_value) {
        return true;
    }
    if (value < 0 || (uint64_t)value > SIZE_MAX) {
        return false;
    }
    *out = (size_t)value;
    return true;
}

uint8_t json_limits(size_t length, uint8_t has_max_bytes, int64_t max_bytes, uint8_t has_max_depth, int64_t max_depth,
                    uint8_t has_max_values, int64_t max_values, JsonLimits *out) {
    size_t bytes = 0;
    JsonLimits limits = {0};
    if (!budget(has_max_bytes, max_bytes, &bytes) || !budget(has_max_depth, max_depth, &limits.max_depth) ||
        !budget(has_max_values, max_values, &limits.max_values)) {
        return MS_STATUS_INVALID_INPUT;
    }
    if (length > bytes || length > MS_STR_MAX_BYTES) {
        return MS_STATUS_LIMIT_EXCEEDED;
    }
    if (limits.max_depth > JSON_DEPTH_CEILING) {
        limits.max_depth = JSON_DEPTH_CEILING;
    }
    *out = limits;
    return MS_STATUS_OK;
}


/* ---- the scanner ---- */

/* One open container of the walk: the next member or element, and how many remain. */
typedef struct Frame {
    yyjson_val *next;
    size_t remaining;
    bool is_array;
} Frame;

typedef struct Walk {
    const uint8_t *base; /* the buffer yyjson decoded in place, which its strings point into */
    size_t error_at;
    JsonLimits limits;
    const JsonSinkOps *ops;
    void *sink;
    Frame *frames; /* owned */
    size_t depth;
    size_t capacity;
} Walk;

MS_NODISCARD static bool walk_push(Walk *walk, Frame frame) {
    void *items = walk->frames;
    if (!ms_array_reserve(&items, &walk->capacity, walk->depth + 1, sizeof(Frame))) {
        return false;
    }
    walk->frames = items;
    walk->frames[walk->depth++] = frame;
    return true;
}

static JsonText text_of(const Walk *walk, yyjson_val *value) {
    const uint8_t *bytes = (const uint8_t *)unsafe_yyjson_get_str(value);
    const size_t length = unsafe_yyjson_get_len(value);
    return (JsonText){.bytes = ms_bytes_of(bytes, length), .offset = length > 0 ? (size_t)(bytes - walk->base) : 0};
}

/* Objects up to this many members detect a repeated key by pairwise comparison; larger ones hash their keys. */
enum { LINEAR_KEYS = 12 };

static yyjson_val *next_key(yyjson_val *key) { return unsafe_yyjson_get_next(key + 1); }

static bool same_key(yyjson_val *a, yyjson_val *b) {
    const size_t length = unsafe_yyjson_get_len(a);
    return length == unsafe_yyjson_get_len(b) && memcmp(unsafe_yyjson_get_str(a), unsafe_yyjson_get_str(b), length) == 0;
}

/* FNV-1a over the key's bytes. */
static uint64_t key_hash(yyjson_val *key) {
    const uint8_t *bytes = (const uint8_t *)unsafe_yyjson_get_str(key);
    const size_t length = unsafe_yyjson_get_len(key);
    uint64_t hash = UINT64_C(0xcbf29ce484222325);
    for (size_t i = 0; i < length; i++) {
        hash = (hash ^ bytes[i]) * UINT64_C(0x100000001b3);
    }
    return hash;
}

typedef struct KeySlot {
    yyjson_val *key;
} KeySlot;

/* The first key of `object` (with `count` members) that repeats an earlier one, or NULL. */
static yyjson_val *repeated_key(yyjson_val *object, size_t count) {
    yyjson_val *first = unsafe_yyjson_get_first(object);
    if (count <= LINEAR_KEYS) {
        yyjson_val *key = first;
        for (size_t i = 0; i < count; i++, key = next_key(key)) {
            yyjson_val *earlier = first;
            for (size_t j = 0; j < i; j++, earlier = next_key(earlier)) {
                if (same_key(key, earlier)) {
                    return key;
                }
            }
        }
        return NULL;
    }
    size_t size = 1;
    while (size < count * 2) {
        size *= 2;
    }
    KeySlot *table = msrt_alloc_zeroed(size * sizeof *table);
    yyjson_val *repeat = NULL;
    yyjson_val *key = first;
    for (size_t i = 0; i < count && repeat == NULL; i++, key = next_key(key)) {
        size_t slot = (size_t)key_hash(key) & (size - 1);
        while (table[slot].key != NULL) {
            if (same_key(table[slot].key, key)) {
                repeat = key;
                break;
            }
            slot = (slot + 1) & (size - 1);
        }
        table[slot].key = key;
    }
    msrt_free(table);
    return repeat;
}

/* Reports `value`; a non-empty container is pushed, and `advance` then yields its members. */
static uint8_t emit(Walk *walk, yyjson_val *value) {
    const JsonSinkOps *ops = walk->ops;
    switch (yyjson_get_type(value)) {
    case YYJSON_TYPE_NULL: return ops->null(walk->sink);
    case YYJSON_TYPE_BOOL: return ops->boolean(walk->sink, yyjson_get_bool(value));
    case YYJSON_TYPE_RAW: return ops->number(walk->sink, text_of(walk, value));
    case YYJSON_TYPE_STR: return ops->string(walk->sink, text_of(walk, value));
    default: break;
    }
    const bool is_array = yyjson_is_arr(value);
    if (walk->depth + 1 > walk->limits.max_depth) {
        return MS_STATUS_LIMIT_EXCEEDED;
    }
    const size_t length = yyjson_get_len(value);
    if (!is_array && length > 1) {
        yyjson_val *repeat = repeated_key(value, length);
        if (repeat != NULL) { /* the key's quote is the byte before its text */
            walk->error_at = (size_t)((const uint8_t *)unsafe_yyjson_get_str(repeat) - walk->base) - 1;
            return MS_STATUS_INVALID_DATA;
        }
    }
    const uint8_t status = ops->open(walk->sink, is_array);
    if (status != MS_STATUS_OK) {
        return status;
    }
    if (length == 0) {
        return ops->close(walk->sink, is_array);
    }
    const Frame frame = {.next = unsafe_yyjson_get_first(value), .remaining = length, .is_array = is_array};
    return walk_push(walk, frame) ? MS_STATUS_OK : MS_STATUS_LIMIT_EXCEEDED;
}

/* The next value to report, closing the containers it ends. MS_STATUS_OK with `*value` NULL when the document is
 * complete. */
static uint8_t advance(Walk *walk, yyjson_val **value) {
    while (walk->depth > 0) {
        Frame *top = &walk->frames[walk->depth - 1];
        if (top->remaining == 0) {
            walk->depth--;
            const uint8_t status = walk->ops->close(walk->sink, top->is_array);
            if (status != MS_STATUS_OK) {
                return status;
            }
            continue;
        }
        top->remaining--;
        yyjson_val *item = top->next;
        if (!top->is_array) {
            const uint8_t status = walk->ops->key(walk->sink, text_of(walk, item));
            if (status != MS_STATUS_OK) {
                return status;
            }
            item++; /* the value follows its key */
        }
        top->next = unsafe_yyjson_get_next(item);
        *value = item;
        return MS_STATUS_OK;
    }
    *value = NULL;
    return MS_STATUS_OK;
}

/* Reports every value of the document under `root` in order, within the value and depth budgets. */
static uint8_t walk_document(Walk *walk, yyjson_val *root) {
    size_t count = 0;
    yyjson_val *value = root;
    while (value != NULL) {
        if (++count > walk->limits.max_values) {
            return MS_STATUS_LIMIT_EXCEEDED;
        }
        uint8_t status = emit(walk, value);
        if (status == MS_STATUS_OK) {
            status = advance(walk, &value);
        }
        if (status != MS_STATUS_OK) {
            return status;
        }
    }
    return MS_STATUS_OK;
}

uint8_t json_scan(MsBytes text, JsonLimits limits, const JsonSinkOps *ops, void *sink, JsonStop *stop,
                  JsonBuffer *keep) {
    *stop = (JsonStop){0};
    /* yyjson decodes in place, so it reads a private copy with the padding it asks for. */
    size_t size = 0;
    if (!ms_size_add(text.len, YYJSON_PADDING_SIZE, &size)) {
        return MS_STATUS_LIMIT_EXCEEDED;
    }
    uint8_t *copy = msrt_alloc(size);
    if (copy == NULL) {
        return MS_STATUS_LIMIT_EXCEEDED;
    }
    if (text.len > 0) {
        memcpy(copy, text.ptr, text.len);
    }
    memset(copy + text.len, 0, YYJSON_PADDING_SIZE);
    yyjson_read_err error = {0};
    yyjson_doc *doc = yyjson_read_opts((char *)copy, text.len, YYJSON_READ_NUMBER_AS_RAW | YYJSON_READ_INSITU, NULL,
                                       &error);
    uint8_t status = MS_STATUS_INVALID_DATA;
    if (doc != NULL) {
        Walk walk = {.base = copy, .limits = limits, .ops = ops, .sink = sink};
        status = walk_document(&walk, yyjson_doc_get_root(doc));
        if (status == MS_STATUS_INVALID_DATA) {
            *stop = (JsonStop){.at = walk.error_at, .reason = "duplicate object key"};
        }
        msrt_free(walk.frames);
        yyjson_doc_free(doc);
    } else if (error.code == YYJSON_READ_ERROR_MEMORY_ALLOCATION) {
        status = MS_STATUS_LIMIT_EXCEEDED;
    } else {
        *stop = (JsonStop){.at = error.pos, .reason = error.msg};
    }
    if (status == MS_STATUS_OK && keep != NULL) {
        *keep = (JsonBuffer){.ptr = copy, .length = text.len, .allocated = size, .limit = MS_STR_MAX_BYTES};
    } else {
        msrt_free(copy);
    }
    return status;
}

/* Whether `text` is exactly one JSON number. A number starts with `-` or a digit and ends with a digit, so the
 * surrounding whitespace that yyjson allows around a document is excluded. */
static uint8_t accept_null(void *sink) {
    (void)sink;
    return MS_STATUS_OK;
}
static uint8_t accept_boolean(void *sink, bool value) {
    (void)sink;
    (void)value;
    return MS_STATUS_OK;
}
static uint8_t accept_text(void *sink, JsonText text) {
    (void)sink;
    (void)text;
    return MS_STATUS_OK;
}
static uint8_t accept_container(void *sink, bool is_array) {
    (void)sink;
    (void)is_array;
    return MS_STATUS_OK;
}

bool json_number_valid(MsBytes text) {
    if (text.len == 0 || (text.ptr[0] != '-' && !ms_ascii_is_digit(text.ptr[0])) ||
        !ms_ascii_is_digit(text.ptr[text.len - 1])) {
        return false;
    }
    static const JsonSinkOps accept = {accept_null, accept_boolean, accept_text,     accept_text,
                                       accept_text, accept_container, accept_container};
    JsonStop stop = {0};
    return json_scan(text, (JsonLimits){.max_depth = 1, .max_values = 1}, &accept, NULL, &stop, NULL) == MS_STATUS_OK;
}

/* ---- the text of a syntax error ---- */

/* The number of scalars in text[0..at) after its last newline, and the number of newlines. */
static void locate(MsBytes text, size_t at, size_t *line, size_t *column) {
    size_t newlines = 0;
    size_t line_start = 0;
    for (size_t i = 0; i < at; i++) {
        if (text.ptr[i] == '\n') {
            newlines++;
            line_start = i + 1;
        }
    }
    *line = newlines + 1;
    *column = ms_utf8_count(text.ptr + line_start, at - line_start) + 1;
}

void json_explain(MsBytes text, JsonStop stop, MsStr *out) {
    char message[160];
    int length = 0;
    size_t at = stop.at < text.len ? stop.at : text.len;
    while (at > 0 && at < text.len && ms_utf8_is_continuation(text.ptr[at])) {
        at--;
    }
    size_t line = 0;
    size_t column = 0;
    locate(text, at, &line, &column);
    length = snprintf(message, sizeof message, "line %zu, column %zu: %s", line, column, stop.reason);
    msrt_string_from_bytes((const uint8_t *)message, length > 0 ? (size_t)length : 0, out);
}
