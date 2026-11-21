/* Bytes: a list of bytes. The natives that search, slice, join and build them. Ported from
 * crates/ms-rt/src/vec.rs. Decoding to text stays with the string module.
 */
#include "index.h"
#include "list_ops.h"
#include "ms_rt/alloc.h"
#include "ms_rt/bytes.h"
#include "ms_rt/search.h"
#include "rt_calls.h"
#include "text.h"

_Static_assert(__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__, "msrt_bytes_read_word assumes a little-endian host");

static const MsList empty_bytes = {0};

static MsBytes contents(const MsList *bytes) { return ms_bytes_of(bytes->ptr, bytes->len); }

/* A fresh buffer holding a copy of `data`; empty data gives the empty list. */
static MsList copy_of(MsBytes data) {
    if (data.len == 0) {
        return empty_bytes;
    }
    uint8_t *buffer = msrt_alloc(data.len);
    __builtin_memcpy(buffer, data.ptr, data.len);
    return (MsList){.ptr = buffer, .len = data.len, .cap = data.len};
}

static MS_NORETURN void fault_bytes_overflow(void) {
    static const char message[] = "bytes size overflow";
    msfault_raise(MS_FAULT_OVERFLOW, (const uint8_t *)message, sizeof message - 1);
}

/* Faults when `value` is not a byte; `what` names the operation for the message. */
static void check_byte(const char *what, int64_t value) {
    if (value >= 0 && value <= UINT8_MAX) {
        return;
    }
    MsText text = {0};
    ms_text_add(&text, what);
    ms_text_add(&text, ": value must be between 0 and 255, found ");
    ms_text_add_i64(&text, value);
    ms_text_fault(&text, MS_FAULT_GENERIC);
}

void msrt_bytes_drop(MsList *b) {
    if (b->ptr != NULL && b->cap != 0) { /* a view borrows its storage */
        msrt_free(b->ptr);
    }
    *b = empty_bytes;
}

void msrt_bytes_copy(const MsList *b, MsList *out) { *out = copy_of(contents(b)); }

/* ---- search ---- */

static bool find_bytes(const MsList *b, const MsList *v, size_t *out) {
    const size_t at = ms_find(b->ptr, b->len, v->ptr, v->len);
    if (at == SIZE_MAX) {
        return false;
    }
    *out = at;
    return true;
}

int64_t msrt_bytes_length(const MsList *b) { return (int64_t)b->len; }
uint8_t msrt_bytes_is_empty(const MsList *b) { return b->len == 0; }

uint8_t msrt_bytes_contains(const MsList *b, const MsList *v) {
    size_t at = 0;
    return find_bytes(b, v, &at);
}

uint8_t msrt_bytes_index_of(const MsList *b, const MsList *v, int64_t *out) {
    size_t at = 0;
    if (!find_bytes(b, v, &at)) {
        return 0;
    }
    *out = (int64_t)at;
    return 1;
}

/* `index_of_byte(value, start)`: the first offset at or after `start` holding `value`. */
uint8_t msrt_bytes_index_of_byte(const MsList *b, int64_t value, int64_t start, int64_t *out) {
    const size_t from = start > 0 ? (size_t)start : 0;
    if (value < 0 || value > UINT8_MAX || from >= b->len) {
        return 0;
    }
    const uint8_t *hit = __builtin_memchr(b->ptr + from, (int)value, b->len - from);
    if (hit == NULL) {
        return 0;
    }
    *out = (int64_t)(hit - b->ptr);
    return 1;
}

uint8_t msrt_bytes_last_index_of(const MsList *b, const MsList *v, int64_t *out) {
    if (v->len > b->len) {
        return 0;
    }
    for (size_t at = b->len - v->len + 1; at > 0; at--) {
        if (v->len == 0 || __builtin_memcmp(b->ptr + at - 1, v->ptr, v->len) == 0) {
            *out = (int64_t)(at - 1);
            return 1;
        }
    }
    return 0;
}

uint8_t msrt_bytes_starts_with(const MsList *b, const MsList *v) {
    return v->len <= b->len && (v->len == 0 || __builtin_memcmp(b->ptr, v->ptr, v->len) == 0);
}

uint8_t msrt_bytes_ends_with(const MsList *b, const MsList *v) {
    return v->len <= b->len && (v->len == 0 || __builtin_memcmp(b->ptr + b->len - v->len, v->ptr, v->len) == 0);
}

uint8_t msrt_bytes_eq(const MsList *a, const MsList *b) {
    return ms_bytes_equal(contents(a), contents(b));
}

/* ---- reads and views ---- */

int64_t msrt_bytes_get(const MsList *b, int64_t index, uint8_t has_default, int64_t default_value) {
    size_t position = 0;
    uint8_t byte = 0;
    if (ms_resolve_index(b->len, index, &position) && ms_bytes_get(contents(b), position, &byte)) {
        return byte;
    }
    if (has_default == 0) {
        msrt_index_fault(index, (int64_t)b->len);
    }
    return default_value;
}

uint8_t msrt_bytes_slice(const MsList *b, int64_t start, int64_t end, MsList *out) {
    size_t from = 0;
    size_t to = 0;
    MsBytes range = {0};
    if (!ms_resolve_bounds(b->len, start, end, &from, &to) || !ms_bytes_slice(contents(b), from, to, &range)) {
        return MS_STATUS_OUT_OF_RANGE;
    }
    *out = copy_of(range);
    return MS_STATUS_OK;
}

static MS_NORETURN void fault_view_bounds(int64_t start, int64_t end, size_t len) {
    MsText text = {0};
    ms_text_add(&text, "Bytes.view: bounds ");
    ms_text_add_i64(&text, start);
    ms_text_add(&text, "..");
    ms_text_add_i64(&text, end);
    ms_text_add(&text, " are outside a length of ");
    ms_text_add_i64(&text, (int64_t)len);
    ms_text_fault(&text, MS_FAULT_GENERIC);
}

/* `view(start, end)`: borrows `[start, end)` of the receiver's storage (a view, `cap == 0`, never freed). */
void msrt_bytes_view(const MsList *b, int64_t start, int64_t end, MsList *out) {
    size_t from = 0;
    size_t to = 0;
    if (!ms_resolve_bounds(b->len, start, end, &from, &to)) {
        fault_view_bounds(start, end, b->len);
    }
    *out = from == to ? empty_bytes : (MsList){.ptr = b->ptr + from, .len = to - from, .cap = 0};
}

void msrt_bytes_reversed(const MsList *b, MsList *out) {
    *out = copy_of(contents(b));
    for (size_t front = 0, back = out->len; front + 1 < back; front++) {
        back--;
        const uint8_t held = out->ptr[front];
        out->ptr[front] = out->ptr[back];
        out->ptr[back] = held;
    }
}

static MS_NORETURN void fault_with_value_index(int64_t index, size_t len) {
    MsText text = {0};
    ms_text_add(&text, "Bytes.with_value: index ");
    if (len == 0) {
        ms_text_add(&text, "has no valid value for an empty collection, found ");
    } else {
        ms_text_add(&text, "must be between ");
        ms_text_add_i64(&text, -(int64_t)len);
        ms_text_add(&text, " and ");
        ms_text_add_i64(&text, (int64_t)len - 1);
        ms_text_add(&text, " (negative indexes count from the end), found ");
    }
    ms_text_add_i64(&text, index);
    ms_text_fault(&text, MS_FAULT_INDEX_OUT_OF_RANGE);
}

void msrt_bytes_with_value(const MsList *b, int64_t index, int64_t value, MsList *out) {
    size_t position = 0;
    if (!ms_resolve_index(b->len, index, &position)) {
        fault_with_value_index(index, b->len);
    }
    check_byte("Bytes.with_value", value);
    *out = copy_of(contents(b));
    out->ptr[position] = (uint8_t)value;
}

/* ---- building ---- */

void msrt_bytes_concat(const MsList *a, const MsList *b, MsList *out) {
    size_t total = 0;
    if (!ms_size_add(a->len, b->len, &total)) {
        fault_bytes_overflow();
    }
    if (total == 0) {
        *out = empty_bytes;
        return;
    }
    uint8_t *buffer = msrt_alloc(total);
    if (a->len != 0) {
        __builtin_memcpy(buffer, a->ptr, a->len);
    }
    if (b->len != 0) {
        __builtin_memcpy(buffer + a->len, b->ptr, b->len);
    }
    *out = (MsList){.ptr = buffer, .len = total, .cap = total};
}

/* Pushes a fresh copy of `part` onto `parts`, a list of Bytes. */
static void push_part(MsList *parts, MsBytes part) {
    MsList item = copy_of(part);
    ms_list_push(parts, &msrt_desc_bytes, (const uint8_t *)&item);
}

void msrt_bytes_split(const MsList *b, const MsList *sep, MsList *out) {
    MsList parts = empty_bytes;
    if (sep->len == 0) { /* every byte on its own */
        for (size_t i = 0; i < b->len; i++) {
            push_part(&parts, ms_bytes_of(b->ptr + i, 1));
        }
        *out = parts;
        return;
    }
    size_t start = 0;
    for (;;) {
        const size_t found = ms_find(b->ptr + start, b->len - start, sep->ptr, sep->len);
        if (found == SIZE_MAX) {
            push_part(&parts, ms_bytes_of(b->ptr + start, b->len - start));
            break;
        }
        push_part(&parts, ms_bytes_of(b->ptr + start, found));
        start += found + sep->len;
    }
    *out = parts;
}

/* `values()` and `Bytes(values)`: a `List[UInt8]` stores one byte per element, the layout of the bytes. */
void msrt_bytes_values(const MsList *b, MsList *out) { *out = copy_of(contents(b)); }

void msrt_bytes_from_values(const MsList *values, MsList *out) { *out = copy_of(contents(values)); }

/* `join(parts)`: the parts end to end in one allocation. The list holds Bytes values inline. */
void msrt_bytes_join(const MsList *parts, MsList *out) {
    size_t total = 0;
    for (size_t i = 0; i < parts->len; i++) {
        MsList part;
        __builtin_memcpy(&part, ms_list_at(parts, &msrt_desc_bytes, i), sizeof part);
        if (!ms_size_add(total, part.len, &total)) {
            fault_bytes_overflow();
        }
    }
    if (total == 0) {
        *out = empty_bytes;
        return;
    }
    uint8_t *buffer = msrt_alloc(total);
    size_t at = 0;
    for (size_t i = 0; i < parts->len; i++) {
        MsList part;
        __builtin_memcpy(&part, ms_list_at(parts, &msrt_desc_bytes, i), sizeof part);
        if (part.len != 0) {
            __builtin_memcpy(buffer + at, part.ptr, part.len);
            at += part.len;
        }
    }
    *out = (MsList){.ptr = buffer, .len = total, .cap = total};
}

/* `BytesBuilder.append(value)`. */
void msrt_bytes_append(MsList *b, int64_t value) {
    check_byte("BytesBuilder.append", value);
    const uint8_t byte = (uint8_t)value;
    ms_list_push(b, &msrt_desc_bool, &byte);
}

/* `BytesBuilder.append_bytes(values)`. */
void msrt_bytes_extend(MsList *b, const MsList *values) {
    ms_list_reserve(b, &msrt_desc_bool, values->len);
    if (values->len != 0) {
        __builtin_memcpy(b->ptr + b->len, values->ptr, values->len);
    }
    b->len += values->len;
}

/* ---- fixed-width reads ---- */

/* The `width` bytes (1, 2, 4 or 8) at `at` as an unsigned number, or all eight as the Int with that bit
 * pattern. Missing bytes are an out-of-range status. */
uint8_t msrt_bytes_read_word(const MsList *b, int64_t at, int64_t width, uint8_t little, int64_t *out) {
    if (at < 0 || (uint64_t)at > b->len || (width != 1 && width != 2 && width != 4 && width != 8)) {
        return MS_STATUS_OUT_OF_RANGE;
    }
    const size_t start = (size_t)at;
    const size_t count = (size_t)width;
    if (b->len - start < count) {
        return MS_STATUS_OUT_OF_RANGE;
    }
    uint64_t raw = 0;
    __builtin_memcpy(&raw, b->ptr + start, count); /* this host is little-endian: bytes fill the low end */
    if (little == 0 && count != 1) {
        raw = __builtin_bswap64(raw) >> (64 - 8 * count);
    }
    *out = (int64_t)raw;
    return MS_STATUS_OK;
}
