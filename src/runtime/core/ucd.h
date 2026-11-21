/* ucd.h: readers for the generated Unicode tables (unicode_tables.c, from tools/unicode-tables.ms) and the growable
 * UTF-8 output the string case and normalization natives write into. Header for src/runtime/core only. */
#ifndef MS_UCD_H
#define MS_UCD_H

#include "ms_rt/safe.h"
#include "ms_rt/string.h"
#include "unicode_tables.h"

/* Normalization record of a scalar: [info, pool offset, lengths]. `info` holds the combining class in bits 0..7 and
 * the flags below it in bits 8 and up. The low four bits of `lengths` count the UTF-16 units of the canonical
 * decomposition, the rest those of the compatibility one when it differs (zero: the canonical one, or none).
 * Canonical units sit at the offset, the compatibility ones after them. */
enum {
    MS_UCD_NFD_NOT_YES = 1u << 8,
    MS_UCD_NFKD_NOT_YES = 1u << 9,
    MS_UCD_NFC_NOT_YES = 1u << 10,
    MS_UCD_NFKC_NOT_YES = 1u << 11,
    MS_UCD_COMP_FIRST = 1u << 12,
    MS_UCD_COMP_SECOND = 1u << 13,
    MS_UCD_CASED = 1,
    MS_UCD_CASE_IGNORABLE = 2,
    MS_UCD_CASE_SPECIAL = 1 << 30
};

static inline size_t ms_ucd_lookup(const uint8_t *top, const uint16_t *mid, const uint16_t *leaf, uint32_t scalar) {
    const uint32_t mid_blocks = 1u << (MS_UCD_MID_BITS - MS_UCD_LEAF_BITS);
    const size_t mid_at = (size_t)top[scalar >> MS_UCD_MID_BITS] * mid_blocks + ((scalar >> MS_UCD_LEAF_BITS) & (mid_blocks - 1u));
    return (size_t)leaf[(size_t)mid[mid_at] * (1u << MS_UCD_LEAF_BITS) + (scalar & ((1u << MS_UCD_LEAF_BITS) - 1u))];
}

/* The normalization record of a scalar (at most 0x10FFFF). */
static inline const uint16_t *ms_ucd_norm_of(uint32_t scalar) {
    return &ms_ucd_norm_record[3u * ms_ucd_lookup(ms_ucd_norm_top, ms_ucd_norm_mid, ms_ucd_norm_leaf, scalar)];
}

/* The case record of a scalar: [lowercase field, uppercase field, Cased and Case_Ignorable bits]. A field below
 * MS_UCD_CASE_SPECIAL is the signed distance to the one-scalar mapping; otherwise bits 16..29 count the UTF-16 units of
 * the mapping and bits 0..15 are their offset in ms_ucd_case_pool. */
static inline const int32_t *ms_ucd_case_of(uint32_t scalar) {
    return &ms_ucd_case_record[3u * ms_ucd_lookup(ms_ucd_case_top, ms_ucd_case_mid, ms_ucd_case_leaf, scalar)];
}

/* UTF-8 text under construction. */
typedef struct MsUtf8Out {
    uint8_t *ptr; /* owned: the buffer, with room for a closing NUL */
    size_t len;
    size_t cap; /* bytes the buffer holds, not counting the NUL */
    size_t limit; /* most bytes the text may reach */
} MsUtf8Out;

/* Starts an empty buffer with room for `capacity` bytes; `limit` bounds the text (at most MS_STR_MAX_BYTES). */
MS_NONNULL void ms_utf8_out_init(MsUtf8Out *out, size_t capacity, size_t limit);
/* Appends the scalar; false (nothing appended) when that passes the limit. */
MS_NODISCARD MS_NONNULL bool ms_utf8_out_scalar(MsUtf8Out *out, uint32_t scalar);
/* Appends the bytes; false (nothing appended) when that passes the limit. */
MS_NODISCARD MS_NONNULL bool ms_utf8_out_bytes(MsUtf8Out *out, const uint8_t *bytes, size_t count);
/* Frees the buffer. */
MS_NONNULL void ms_utf8_out_free(MsUtf8Out *out);
/* The text as a string value, which takes the buffer; `out` is empty afterwards. */
MS_NONNULL MsStr ms_utf8_out_finish(MsUtf8Out *out);

#endif
