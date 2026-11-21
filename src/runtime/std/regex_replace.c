/* The @std/regex replacements: `replace_all` inserts a literal, `replace_template` expands `$1`, `${name}` and `$$`
 * from each match. The output is built in one growing buffer under the caller's byte budget, which every append
 * checks before it copies, so an oversized capture or literal fails without being copied. */
#include <stdbool.h>

#include "ms_rt/regex.h"
#include "ms_rt/safe.h"
#include "ms_rt/strbuild.h"
#include "regex_internal.h"

/* ---- the output buffer ---- */

typedef struct ReplaceBuffer {
    uint8_t *ptr; /* owned; NULL until the first append */
    size_t len;
    size_t capacity;
    uint64_t max; /* bytes the result may hold */
} ReplaceBuffer;

static void buffer_free(ReplaceBuffer *buffer) {
    msrt_free(buffer->ptr);
    buffer->ptr = NULL;
}

/* Room for `extra` more bytes; false when the result would pass the budget or the string limit. */
MS_NODISCARD static bool buffer_reserve(ReplaceBuffer *buffer, size_t extra) {
    size_t needed = 0;
    if (!ms_size_add(buffer->len, extra, &needed) || needed > buffer->max || needed > MS_STR_MAX_BYTES) {
        return false;
    }
    if (needed <= buffer->capacity) {
        return true;
    }
    size_t capacity = buffer->capacity ? buffer->capacity : 64;
    while (capacity < needed) {
        if (!ms_size_mul(capacity, 2, &capacity)) {
            return false;
        }
    }
    buffer->ptr = buffer->ptr ? msrt_realloc(buffer->ptr, capacity) : msrt_alloc(capacity);
    buffer->capacity = capacity;
    return true;
}

MS_NODISCARD static bool buffer_append(ReplaceBuffer *buffer, MsBytes bytes) {
    if (!buffer_reserve(buffer, bytes.len)) {
        return false;
    }
    if (bytes.len != 0) {
        memcpy(buffer->ptr + buffer->len, bytes.ptr, bytes.len);
    }
    buffer->len += bytes.len;
    return true;
}

/* text[start..end]; the offsets come from the engine, so a bad range is a bug in it. */
static MsBytes slice_of(MsBytes text, int64_t start, int64_t end) {
    MsBytes part = {0};
    if (start < 0 || end < start || !ms_bytes_slice(text, (size_t)start, (size_t)end, &part)) {
        return ms_bytes_of(NULL, 0);
    }
    return part;
}

/* ---- the template ---- */

/* Where a `$` reference ends and what it names. `name` is empty and `found` false for a `$` that is literal. */
typedef struct Reference {
    MsBytes name;
    size_t end; /* template offset after the reference */
    bool found;
} Reference;

static bool is_name_byte(uint8_t byte) {
    return (byte >= '0' && byte <= '9') || (byte >= 'a' && byte <= 'z') || (byte >= 'A' && byte <= 'Z') || byte == '_';
}

/* The reference after the `$` that ended at template[at]: `${...}` up to the first `}`, else the run of name bytes. */
static Reference reference_at(MsBytes tmpl, size_t at) {
    Reference reference = {0};
    if (at < tmpl.len && tmpl.ptr[at] == '{') {
        const uint8_t *close = memchr(tmpl.ptr + at + 1, '}', tmpl.len - at - 1);
        if (close != NULL) {
            const size_t close_at = (size_t)(close - tmpl.ptr);
            reference.name = ms_bytes_of(tmpl.ptr + at + 1, close_at - at - 1);
            reference.end = close_at + 1;
            reference.found = true;
        }
        return reference;
    }
    size_t end = at;
    while (end < tmpl.len && is_name_byte(tmpl.ptr[end])) {
        end++;
    }
    reference.name = ms_bytes_of(tmpl.ptr + at, end - at);
    reference.end = end;
    reference.found = end > at;
    return reference;
}

/* A group number as Rust's usize parser reads it: digits with an optional leading `+`; false for anything else,
 * overflow included, which makes the reference a name. */
static bool parse_group_number(MsBytes name, size_t *out) {
    size_t at = (name.len > 0 && name.ptr[0] == '+') ? 1 : 0;
    if (at == name.len) {
        return false;
    }
    size_t value = 0;
    for (; at < name.len; at++) {
        const uint8_t digit = name.ptr[at];
        if (digit < '0' || digit > '9' || !ms_size_mul(value, 10, &value) || !ms_size_add(value, (size_t)(digit - '0'), &value)) {
            return false;
        }
    }
    *out = value;
    return true;
}

/* The group a reference names: its number, or the group with that name. SIZE_MAX when no group does. */
static size_t group_of(const MsRegex *re, size_t group_count, MsBytes name) {
    size_t number = 0;
    if (parse_group_number(name, &number)) {
        return number < group_count ? number : SIZE_MAX;
    }
    for (size_t group = 1; group < group_count; group++) {
        size_t length = 0;
        const char *group_name = ms_re_group_name(re, group, &length);
        if (group_name != NULL && length == name.len && memcmp(group_name, name.ptr, length) == 0) {
            return group;
        }
    }
    return SIZE_MAX;
}

/* Appends the text of a referenced group; an absent group or a name no group has adds nothing. */
static bool append_reference(ReplaceBuffer *out, const MsRegex *re, MsBytes text, const MsRegexMatch *match, MsBytes name) {
    const size_t group = group_of(re, match->pair_count, name);
    if (group == SIZE_MAX || match->slots[group * 2] < 0) {
        return true;
    }
    return buffer_append(out, slice_of(text, match->slots[group * 2], match->slots[group * 2 + 1]));
}

/* One match's expansion of the template; false when it passes the budget. */
static bool expand_template(ReplaceBuffer *out, const MsRegex *re, MsBytes text, MsBytes tmpl, const MsRegexMatch *match) {
    size_t at = 0;
    while (at < tmpl.len) {
        const uint8_t *dollar = memchr(tmpl.ptr + at, '$', tmpl.len - at);
        const size_t stop = dollar ? (size_t)(dollar - tmpl.ptr) : tmpl.len;
        if (!buffer_append(out, ms_bytes_of(tmpl.ptr + at, stop - at))) {
            return false;
        }
        if (dollar == NULL) {
            return true;
        }
        at = stop + 1;
        if (at < tmpl.len && tmpl.ptr[at] == '$') {
            at++;
            if (!buffer_append(out, ms_bytes_of((const uint8_t *)"$", 1))) {
                return false;
            }
            continue;
        }
        const Reference reference = reference_at(tmpl, at);
        if (!reference.found) { /* a lone or unfinished `$` is literal; later dollars may still start references */
            if (!buffer_append(out, ms_bytes_of((const uint8_t *)"$", 1))) {
                return false;
            }
            continue;
        }
        if (!append_reference(out, re, text, match, reference.name)) {
            return false;
        }
        at = reference.end;
    }
    return true;
}

/* ---- the scans ---- */

typedef struct Replacement {
    const MsRegex *re;
    MsBytes text;
    MsBytes with; /* the literal or the template */
    bool expand;  /* the template holds a `$` */
    size_t copied; /* text before this offset is in the buffer */
    ReplaceBuffer buffer;
} Replacement;

static uint8_t replace_match(void *state, const MsRegexMatch *match) {
    Replacement *replacement = state;
    const MsBytes between = slice_of(replacement->text, (int64_t)replacement->copied, match->slots[0]);
    if (!buffer_append(&replacement->buffer, between)) {
        return STATUS_LIMIT_EXCEEDED;
    }
    const bool fits = replacement->expand
                          ? expand_template(&replacement->buffer, replacement->re, replacement->text, replacement->with, match)
                          : buffer_append(&replacement->buffer, replacement->with);
    replacement->copied = (size_t)match->slots[1];
    return fits ? STATUS_OK : STATUS_LIMIT_EXCEEDED;
}

static uint8_t replace(const void *handle, const MsStr *text, const MsStr *with, bool expand, uint8_t has_max, int64_t max, MsStr *out) {
    Replacement replacement = {
        .re = ms_regex_of(handle),
        .text = ms_bytes_of(ms_str_data(text), ms_str_len(text)),
        .with = ms_bytes_of(ms_str_data(with), ms_str_len(with)),
        .expand = expand && memchr(ms_str_data(with), '$', ms_str_len(with)) != NULL,
    };
    if (!ms_regex_budget(has_max, max, &replacement.buffer.max)) {
        return STATUS_INVALID_INPUT;
    }
    uint8_t status = ms_regex_each_match(replacement.re, msrt_str_data(text), msrt_str_len(text), replace_match, &replacement);
    const MsBytes tail = slice_of(replacement.text, (int64_t)replacement.copied, (int64_t)replacement.text.len);
    if (status == STATUS_OK && !buffer_append(&replacement.buffer, tail)) {
        status = STATUS_LIMIT_EXCEEDED;
    }
    if (status == STATUS_OK) {
        *out = ms_str_from_bytes(replacement.buffer.ptr, replacement.buffer.len);
    }
    buffer_free(&replacement.buffer);
    return status;
}

uint8_t msstd_regex_replace_all(const void *re, const MsStr *text, const MsStr *replacement, uint8_t has_max, int64_t max, MsStr *out) {
    return replace(re, text, replacement, false, has_max, max, out);
}

uint8_t msstd_regex_replace_template(const void *re, const MsStr *text, const MsStr *template_text, uint8_t has_max, int64_t max, MsStr *out) {
    return replace(re, text, template_text, true, has_max, max, out);
}
