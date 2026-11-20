/* Scanning a string for the scalars of a set, and for its last substring: `String.index_any`,
 * `String.trim_chars` (and its start and end forms) and `String.last_index_of`. Ported from
 * crates/ms-rt/src/string.rs. Text is read through spans, so every offset below is checked by the span helpers. */
#include "ms_rt/safe.h"
#include "ms_rt/search.h"
#include "ms_rt/strbuild.h"
#include "ms_rt/utf8.h"

/* A set of scalars: the ASCII members are two 64-bit masks, the rest are the set's own bytes from the first
 * non-ASCII one, decoded on demand. A member is never tested against a scalar it could not equal. */
typedef struct ScalarSet {
    uint64_t low;  /* scalars 0..63 */
    uint64_t high; /* scalars 64..127 */
    MsBytes wide;  /* from the first non-ASCII byte to the end of the set */
} ScalarSet;

#define MS_ASCII_LIMIT 0x80u
#define MS_MASK_BITS 64u

static ScalarSet scalar_set(MsBytes members) {
    ScalarSet set = {0};
    bool wide_found = false;
    for (size_t i = 0; i < members.len; i++) {
        const uint8_t byte = members.ptr[i];
        if (byte < MS_MASK_BITS) {
            set.low |= UINT64_C(1) << byte;
        } else if (byte < MS_ASCII_LIMIT) {
            set.high |= UINT64_C(1) << (byte - MS_MASK_BITS);
        } else if (!wide_found) {
            wide_found = true;
            if (!ms_bytes_slice(members, i, members.len, &set.wide)) {
                ms_limit_fault();
            }
        }
    }
    return set;
}

static bool wide_contains(MsBytes wide, uint32_t scalar) {
    size_t at = 0;
    while (at < wide.len) {
        const MsRune member = ms_utf8_decode(wide.ptr + at, wide.len - at);
        if (member.rune == scalar) {
            return true;
        }
        at += member.width;
    }
    return false;
}

static bool set_contains(const ScalarSet *set, uint32_t scalar) {
    if (scalar < MS_MASK_BITS) {
        return ((set->low >> scalar) & 1) != 0;
    }
    if (scalar < MS_ASCII_LIMIT) {
        return ((set->high >> (scalar - MS_MASK_BITS)) & 1) != 0;
    }
    return wide_contains(set->wide, scalar);
}

uint8_t msrt_string_index_any(const MsStr *s, const MsStr *set, int64_t *out) {
    const MsBytes text = ms_str_bytes(s);
    const ScalarSet members = scalar_set(ms_str_bytes(set));
    size_t at = 0;
    while (at < text.len) {
        const MsRune scalar = ms_utf8_decode(text.ptr + at, text.len - at);
        if (set_contains(&members, scalar.rune)) {
            *out = (int64_t)at;
            return 1;
        }
        at += scalar.width;
    }
    return 0;
}

/* The offset after skipping the members of the set from the start of text[begin..end]. */
static size_t skip_start(MsBytes text, const ScalarSet *set, size_t begin, size_t end) {
    while (begin < end) {
        const MsRune scalar = ms_utf8_decode(text.ptr + begin, end - begin);
        if (!set_contains(set, scalar.rune)) {
            break;
        }
        begin += scalar.width;
    }
    return begin;
}

/* The offset after skipping the members of the set from the end of text[begin..end]. */
static size_t skip_end(MsBytes text, const ScalarSet *set, size_t begin, size_t end) {
    while (end > begin) {
        const MsRune scalar = ms_utf8_decode_last(text.ptr + begin, end - begin);
        if (!set_contains(set, scalar.rune)) {
            break;
        }
        end -= scalar.width;
    }
    return end;
}

void msrt_string_trim_chars(const MsStr *s, const MsStr *set, uint8_t from_start, uint8_t from_end, MsStr *out) {
    const MsBytes text = ms_str_bytes(s);
    const ScalarSet members = scalar_set(ms_str_bytes(set));
    size_t begin = 0;
    size_t end = text.len;
    if (from_start != 0) {
        begin = skip_start(text, &members, begin, end);
    }
    if (from_end != 0) {
        end = skip_end(text, &members, begin, end);
    }
    MsBytes kept = {0};
    if (!ms_bytes_slice(text, begin, end, &kept)) {
        ms_limit_fault();
    }
    *out = ms_str_from_bytes(kept.ptr, kept.len);
}

uint8_t msrt_string_last_index_of(const MsStr *a, const MsStr *v, int64_t *out) {
    const MsBytes text = ms_str_bytes(a);
    const MsBytes needle = ms_str_bytes(v);
    const size_t at = ms_rfind(text.ptr, text.len, needle.ptr, needle.len);
    if (at == SIZE_MAX) {
        return 0;
    }
    *out = (int64_t)at;
    return 1;
}
