/* String.upper and String.lower: ASCII text maps eight bytes at a time, other text scalar by scalar through the
 * generated case tables (ucd.h), with the full mappings of SpecialCasing (`ß` to `SS`) and the final-sigma rule of
 * lowercasing. A result is never shared with its input except when ASCII text is already in the requested case. */
#include "ms_rt/alloc.h"
#include "ms_rt/chars.h"
#include "ms_rt/strbuild.h"
#include "ms_rt/utf8.h"
#include "ucd.h"

#define SIGMA 0x3A3u

/* The high bit of each byte of `word` (all below 0x80) that is a letter to flip: a lowercase one when mapping to
 * upper case, an uppercase one otherwise. Adding (0x80 - first) sets a byte's high bit when it is at least `first`,
 * and adding (0x80 - last - 1) when it is above `last`; no byte carries into the next. */
static inline uint64_t letters_to_flip(uint64_t word, bool to_upper) {
    const uint64_t ones = UINT64_C(0x0101010101010101);
    const uint64_t high = UINT64_C(0x8080808080808080);
    const uint8_t first = to_upper ? 'a' : 'A';
    const uint8_t last = to_upper ? 'z' : 'Z';
    const uint64_t at_least = word + ones * (uint64_t)(0x80 - first);
    const uint64_t above = word + ones * (uint64_t)(0x80 - last - 1);
    return at_least & ~above & high;
}

static inline uint64_t flipped_word(uint64_t word, bool to_upper) { return word ^ (letters_to_flip(word, to_upper) >> 2); }

/* The first eight bytes of the n bytes at p, or all of them zero padded when there are fewer. */
static inline uint64_t first_word(const uint8_t *p, size_t n) {
    uint64_t word = 0;
    __builtin_memcpy(&word, p, n < 8 ? n : 8);
    return word;
}

/* Whether the ASCII bytes hold a letter that the mapping changes, eight bytes per step. */
static bool has_letter_to_flip(MsBytes text, bool to_upper) {
    if (text.len < 8) {
        return letters_to_flip(first_word(text.ptr, text.len), to_upper) != 0;
    }
    size_t at = 0;
    for (; at + 8 <= text.len; at += 8) {
        if (letters_to_flip(ms_load64(text.ptr + at), to_upper) != 0) {
            return true;
        }
    }
    return letters_to_flip(ms_load64(text.ptr + text.len - 8), to_upper) != 0;
}

/* Writes the mapped ASCII bytes to `dst` (`src` and `dst` may be the same bytes). */
static void flip_ascii_into(uint8_t *dst, const uint8_t *src, size_t length, bool to_upper) {
    if (length < 8) {
        const uint64_t word = flipped_word(first_word(src, length), to_upper);
        __builtin_memcpy(dst, &word, length);
        return;
    }
    const uint64_t tail = flipped_word(ms_load64(src + length - 8), to_upper);
    size_t at = 0;
    for (; at + 8 <= length; at += 8) {
        const uint64_t word = flipped_word(ms_load64(src + at), to_upper);
        __builtin_memcpy(dst + at, &word, 8);
    }
    __builtin_memcpy(dst + length - 8, &tail, 8);
}

static MsStr map_ascii(const MsStr *s, bool to_upper) {
    const MsBytes text = ms_str_bytes(s);
    if (!has_letter_to_flip(text, to_upper)) {
        return ms_str_cloned(s); /* already in the requested case */
    }
    if (text.len <= MS_STR_INLINE_MAX) {
        uint8_t small[MS_STR_INLINE_MAX + 1] = {0};
        flip_ascii_into(small, text.ptr, text.len, to_upper);
        return ms_str_from_bytes(small, text.len);
    }
    MsStr result = ms_str_alloc(text.len);
    flip_ascii_into(result.ptr_word, text.ptr, text.len, to_upper);
    return ms_str_with_ascii(result);
}

/* Whether the Cased scalar, past any Case_Ignorable ones, starts (forward) or ends (backward) the bytes. */
static bool cased_before(MsBytes text, size_t end) {
    while (end > 0) {
        const MsRune scalar = ms_utf8_decode_last(text.ptr, end);
        end -= scalar.width;
        const int32_t flags = ms_ucd_case_of(scalar.rune)[2];
        if ((flags & MS_UCD_CASE_IGNORABLE) == 0) {
            return (flags & MS_UCD_CASED) != 0;
        }
    }
    return false;
}

static bool cased_after(MsBytes text, size_t start) {
    while (start < text.len) {
        const MsRune scalar = ms_utf8_decode(text.ptr + start, text.len - start);
        start += scalar.width;
        const int32_t flags = ms_ucd_case_of(scalar.rune)[2];
        if ((flags & MS_UCD_CASE_IGNORABLE) == 0) {
            return (flags & MS_UCD_CASED) != 0;
        }
    }
    return false;
}

/* Capital sigma lowercases to the final form when a cased letter precedes it and none follows (case-ignorable
 * scalars aside). */
static uint32_t lower_sigma(MsBytes text, size_t at) {
    const bool final_form = cased_before(text, at) && !cased_after(text, at + 2);
    return final_form ? 0x3C2u : 0x3C3u;
}

/* Appends the mapping of one non-ASCII scalar; false when the text passes the limit. */
MS_NODISCARD static bool put_mapped(MsUtf8Out *out, uint32_t scalar, int32_t field) {
    if (field < MS_UCD_CASE_SPECIAL) {
        return ms_utf8_out_scalar(out, (uint32_t)((int32_t)scalar + field));
    }
    const uint32_t count = ((uint32_t)field >> 16) & 0x3FFFu;
    const uint32_t offset = (uint32_t)field & 0xFFFFu;
    for (uint32_t i = 0; i < count; i++) {
        if (!ms_utf8_out_scalar(out, ms_ucd_case_pool[offset + i])) {
            return false;
        }
    }
    return true;
}

static bool map_scalars(MsBytes text, bool to_upper, MsUtf8Out *out) {
    size_t at = 0;
    while (at < text.len) {
        const uint8_t byte = text.ptr[at];
        if (byte < 0x80) {
            const uint8_t mapped = to_upper ? ms_ascii_to_upper(byte) : ms_ascii_to_lower(byte);
            if (!ms_utf8_out_bytes(out, &mapped, 1)) {
                return false;
            }
            at++;
            continue;
        }
        const MsRune scalar = ms_utf8_decode_multi(text.ptr + at, text.len - at);
        const int32_t *record = ms_ucd_case_of(scalar.rune);
        const int32_t field = record[to_upper ? 1 : 0];
        bool done = false;
        if (!to_upper && scalar.rune == SIGMA) {
            done = ms_utf8_out_scalar(out, lower_sigma(text, at));
        } else if (field == 0) {
            done = ms_utf8_out_bytes(out, text.ptr + at, scalar.width);
        } else {
            done = put_mapped(out, scalar.rune, field);
        }
        if (!done) {
            return false;
        }
        at += scalar.width;
    }
    return true;
}

static MsStr map_text(const MsStr *s, bool to_upper) {
    const MsBytes text = ms_str_bytes(s);
    MsUtf8Out out;
    ms_utf8_out_init(&out, text.len, MS_STR_MAX_BYTES);
    if (!map_scalars(text, to_upper, &out)) {
        ms_utf8_out_free(&out);
        ms_limit_fault();
    }
    return ms_utf8_out_finish(&out);
}

static MsStr map_case(const MsStr *s, bool to_upper) {
    return ms_str_is_ascii(s) ? map_ascii(s, to_upper) : map_text(s, to_upper);
}

/* The string that dies at the call: owned ASCII text maps in place, anything else maps as above and is released. */
static void map_case_take(MsStr *s, bool to_upper, MsStr *out) {
    const bool owned = (s->tagged >> MS_STR_TAG_SHIFT) == 0;
    if (owned && ms_str_is_ascii(s)) {
        flip_ascii_into(s->ptr_word, s->ptr_word, ms_str_len(s), to_upper);
        ms_str_write(ms_str_with_ascii(*s), out);
        return;
    }
    ms_str_write(map_case(s, to_upper), out);
    ms_str_release(s);
}

void msrt_string_upper(const MsStr *s, MsStr *out) { ms_str_write(map_case(s, true), out); }

void msrt_string_lower(const MsStr *s, MsStr *out) { ms_str_write(map_case(s, false), out); }

void msrt_string_upper_take(MsStr *s, MsStr *out) { map_case_take(s, true, out); }

void msrt_string_lower_take(MsStr *s, MsStr *out) { map_case_take(s, false, out); }
