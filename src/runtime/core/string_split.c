/* Splitting and replacing strings: the runtime's split, split_view, split_view_into, split_first, replace,
 * replace_first and replace_take. Ported from crates/ms-rt/src/string.rs; the search is ms_needle_find from
 * src/runtime/core/search.c. Strings are read through spans (MsBytes), sizes are added and multiplied with the
 * checked helpers of ms_rt/safe.h, and a string longer than the 1 GiB limit faults like `concat`.
 *
 * Ownership: results are written through `out`, which the caller owns from then on. A split list owns its
 * pieces except in the view forms, where long pieces borrow bytes of the text and the caller keeps the text
 * alive for as long as the list is read. */
#include "ms_rt/search.h"
#include "ms_rt/safe.h"
#include "ms_rt/strbuild.h"
#include "ms_rt/utf8.h"
#include "string_slice.h"

/* Texts up to this many bytes split at a one-byte separator in one pass over their words: a record's fields
 * are a few bytes apart, where a search per piece costs more than the scan. */
#define MS_ONE_PASS_SPLIT_MAX 128
/* Pieces the caller's frame buffer of msrt_string_split_view_into holds. */
#define MS_SPLIT_FRAME_PIECES 8
/* A list that grows starts with room for this many pieces when the text may hold that many. */
#define MS_SPLIT_FIRST_CAPACITY 8

/* How a piece is made: a copy (owned or inline), or a view of the text (only for texts that outlive it). */
typedef enum MsPieceMode {
    MS_PIECE_COPY,
    MS_PIECE_VIEW,
} MsPieceMode;

static MsBytesMut slice_mut(MsBytesMut bytes, size_t start, size_t end) {
    MsBytesMut part = {0};
    if (!ms_bytes_mut_slice(bytes, start, end, &part)) {
        ms_string_internal_fault();
    }
    return part;
}

/* Copies `source` to dst[at..] and returns the offset after it. */
static inline MS_ALWAYS_INLINE size_t write_at(MsBytesMut dst, size_t at, MsBytes source) {
    size_t end = 0;
    if (!ms_size_add(at, source.len, &end) || end > dst.len) {
        ms_string_internal_fault();
    }
    ms_copy_bytes(dst.ptr + at, source.ptr, source.len);
    return end;
}

static inline MS_ALWAYS_INLINE MsStr make_piece(MsPieceMode mode, MsBytes bytes) {
    const bool short_ascii = bytes.len == 0 || (bytes.len == 1 && bytes.ptr[0] < 0x80);
    if (mode == MS_PIECE_VIEW && !short_ascii) {
        return ms_str_view_of(bytes.ptr, bytes.len);
    }
    return ms_str_from_bytes(bytes.ptr, bytes.len);
}

/* ---- split ---- */

/* Makes room for at least one more piece (the list's first allocation holds 4). */
static void list_grow(MsVec *list) {
    const size_t capacity = list->cap == 0 ? 4 : list->cap * 2;
    size_t bytes = 0;
    if (!ms_size_mul(capacity, sizeof(MsStr), &bytes)) {
        ms_limit_fault();
    }
    list->ptr = list->ptr == NULL ? msrt_alloc(bytes) : msrt_realloc(list->ptr, bytes);
    list->cap = capacity;
}

static inline MS_ALWAYS_INLINE void list_push(MsVec *list, MsStr piece) {
    if (list->len == list->cap) {
        list_grow(list);
    }
    MsStr *pieces = list->ptr;
    pieces[list->len] = piece;
    list->len++;
}

/* Reserves room for `count` pieces in an empty list. */
static void list_reserve(MsVec *list, size_t count) {
    size_t bytes = 0;
    if (!ms_size_mul(count, sizeof(MsStr), &bytes)) {
        ms_limit_fault();
    }
    list->ptr = msrt_alloc(bytes);
    list->cap = count;
}

/* Appends to a list that may be a caller's fixed buffer; false when a fixed list is full. */
static inline MS_ALWAYS_INLINE bool list_put(MsVec *list, MsStr piece, bool fixed) {
    if (fixed && list->len == list->cap) {
        return false;
    }
    list_push(list, piece);
    return true;
}

/* The mask of the bytes of `word` equal to the byte in every lane of `pattern`: bit 7 of each matching byte, with
 * no false bytes above a match. */
static inline MS_ALWAYS_INLINE uint64_t equal_bytes_mask(uint64_t word, uint64_t pattern) {
    const uint64_t low_bits = UINT64_C(0x7f7f7f7f7f7f7f7f), high_bits = UINT64_C(0x8080808080808080);
    const uint64_t diff = word ^ pattern;
    return ~(((diff & low_bits) + low_bits) | diff) & high_bits;
}

/* The pieces of `text` between bytes equal to `separator`, found eight bytes at a time and taken from each word's
 * mask. False when a fixed list fills up. */
static inline MS_ALWAYS_INLINE bool split_at_byte(MsBytes text, uint8_t separator, MsVec *list, MsPieceMode mode, bool fixed) {
    const uint64_t pattern = UINT64_C(0x0101010101010101) * separator;
    size_t piece_start = 0, offset = 0;
    for (; offset + 8 <= text.len; offset += 8) {
        uint64_t mask = equal_bytes_mask(ms_load64(text.ptr + offset), pattern);
        while (mask != 0) {
            const size_t hit = offset + (size_t)__builtin_ctzll(mask) / 8;
            if (!list_put(list, make_piece(mode, ms_string_slice(text, piece_start, hit)), fixed)) {
                return false;
            }
            piece_start = hit + 1;
            mask &= mask - 1;
        }
    }
    for (; offset < text.len; offset++) {
        if (text.ptr[offset] != separator) {
            continue;
        }
        if (!list_put(list, make_piece(mode, ms_string_slice(text, piece_start, offset)), fixed)) {
            return false;
        }
        piece_start = offset + 1;
    }
    return list_put(list, make_piece(mode, ms_string_slice(text, piece_start, text.len)), fixed);
}

/* Split after each scalar: the piece count is known, so the list is sized once. */
static void split_scalars(MsBytes text, MsVec *list, MsPieceMode mode) {
    const size_t count = ms_utf8_count(text.ptr, text.len);
    if (count > 0) {
        list_reserve(list, count);
    }
    for (size_t offset = 0; offset < text.len;) {
        const size_t width = ms_utf8_decode(text.ptr + offset, text.len - offset).width;
        list_push(list, make_piece(mode, ms_string_slice(text, offset, offset + width)));
        offset += width;
    }
}

/* Split at a separator of two or more bytes, or of one byte in a text too long for the one-pass scan. */
static void split_at_pattern(MsBytes text, MsBytes separator, MsVec *list, MsPieceMode mode) {
    const MsNeedle needle = ms_needle_for(separator, text.len);
    size_t piece_start = 0;
    for (;;) {
        const size_t hit = ms_needle_find(&needle, ms_string_slice(text, piece_start, text.len));
        if (hit == SIZE_MAX) {
            list_push(list, make_piece(mode, ms_string_slice(text, piece_start, text.len)));
            return;
        }
        list_push(list, make_piece(mode, ms_string_slice(text, piece_start, piece_start + hit)));
        piece_start += hit + separator.len;
    }
}

static void split_into(const MsStr *s, const MsStr *sep, MsVec *out, MsPieceMode mode) {
    const MsBytes text = ms_str_bytes(s), separator = ms_str_bytes(sep);
    MsVec list = {.ptr = NULL, .len = 0, .cap = 0};
    if (separator.len == 0) {
        split_scalars(text, &list, mode);
    } else {
        /* Most splits are of records with several fields: room for eight pieces (never more than the text can
         * hold) saves the grow-and-copy of the usual seven, without sizing a two-piece split for eight. */
        const size_t possible = text.len / separator.len + 1;
        list_reserve(&list, possible < MS_SPLIT_FIRST_CAPACITY ? possible : MS_SPLIT_FIRST_CAPACITY);
        if (separator.len == 1 && text.len <= MS_ONE_PASS_SPLIT_MAX) {
            (void)split_at_byte(text, separator.ptr[0], &list, mode, false);
        } else {
            split_at_pattern(text, separator, &list, mode);
        }
    }
    *out = list;
}

void msrt_string_split(const MsStr *s, const MsStr *sep, MsVec *out) { split_into(s, sep, out, MS_PIECE_COPY); }

void msrt_string_split_view(const MsStr *s, const MsStr *sep, MsVec *out) { split_into(s, sep, out, MS_PIECE_VIEW); }

/* The view split into the caller's frame buffer when the text is short and has at most eight pieces at a one-byte
 * separator (the list then has capacity 0: it owns nothing); otherwise the heap list of split_view. */
void msrt_string_split_view_into(const MsStr *s, const MsStr *sep, MsStr *buffer, MsVec *out) {
    const MsBytes text = ms_str_bytes(s), separator = ms_str_bytes(sep);
    if (separator.len == 1 && text.len <= MS_ONE_PASS_SPLIT_MAX) {
        MsVec list = {.ptr = buffer, .len = 0, .cap = MS_SPLIT_FRAME_PIECES};
        if (split_at_byte(text, separator.ptr[0], &list, MS_PIECE_VIEW, true)) {
            list.cap = 0;
            *out = list;
            return;
        }
    }
    split_into(s, sep, out, MS_PIECE_VIEW);
}

/* text.split(separator)[0], a view of text, found without building the list. Faults like an index of an empty
 * list when text is empty and the separator is not. */
void msrt_string_split_first(const MsStr *s, const MsStr *sep, MsStr *out) {
    const MsBytes text = ms_str_bytes(s), separator = ms_str_bytes(sep);
    size_t end = 0;
    if (separator.len == 0) {
        /* Split after each scalar: the first piece is the first scalar. */
        if (text.len == 0) {
            msrt_index_fault(0, 0);
        }
        end = ms_utf8_decode(text.ptr, text.len).width;
    } else {
        const MsNeedle needle = ms_needle_for(separator, text.len);
        end = ms_needle_find(&needle, text);
        if (end == SIZE_MAX) {
            end = text.len;
        }
    }
    ms_str_write(make_piece(MS_PIECE_VIEW, ms_string_slice(text, 0, end)), out);
}

/* ---- replace ---- */

/* The string of `length` bytes that `fill` writes into a buffer of that size: inline when it fits, otherwise one
 * allocation. `ascii` says the bytes are all ASCII (known from the inputs). */
typedef void (*MsFillFn)(MsBytesMut destination, const void *context);

static MsStr build_exact(size_t length, bool ascii, MsFillFn fill, const void *context) {
    if (length <= MS_STR_INLINE_MAX) {
        uint8_t small[MS_STR_INLINE_MAX + 1] = {0};
        fill(ms_bytes_mut(small, length), context);
        return ms_str_from_bytes(small, length);
    }
    const MsStr result = ms_str_alloc(length);
    fill(ms_bytes_mut(result.ptr_word, length), context);
    return ascii ? ms_str_with_ascii(result) : result;
}

typedef struct MsReplacement {
    MsBytes text;
    MsBytes old_text;    /* what to replace; empty means before every scalar and at the end */
    MsBytes replacement;
    const MsNeedle *needle; /* for old_text, when it is not empty */
    size_t matches;      /* how many matches to replace (all of them, counted before) */
} MsReplacement;

/* The text with `matches` occurrences of the non-empty old_text replaced. */
static void fill_replaced(MsBytesMut destination, const void *context) {
    const MsReplacement *job = context;
    size_t written = 0, read = 0;
    for (size_t match = 0; match < job->matches; match++) {
        const MsBytes rest = ms_string_slice(job->text, read, job->text.len);
        const size_t before = ms_needle_find(job->needle, rest);
        if (before == SIZE_MAX) {
            ms_string_internal_fault(); /* counted before: the match is there */
        }
        written = write_at(destination, written, ms_string_slice(rest, 0, before));
        written = write_at(destination, written, job->replacement);
        read += before + job->old_text.len;
    }
    (void)write_at(destination, written, ms_string_slice(job->text, read, job->text.len));
}

/* The text with the replacement inserted before every scalar and at the end. */
static void fill_inserted(MsBytesMut destination, const void *context) {
    const MsReplacement *job = context;
    size_t written = 0, read = 0;
    for (;;) {
        written = write_at(destination, written, job->replacement);
        if (read >= job->text.len) {
            return;
        }
        const size_t width = ms_utf8_decode(job->text.ptr + read, job->text.len - read).width;
        written = write_at(destination, written, ms_string_slice(job->text, read, read + width));
        read += width;
    }
}

static size_t count_matches(const MsNeedle *needle, MsBytes text) {
    size_t count = 0, read = 0;
    while (text.len - read >= needle->pattern.len) {
        const size_t before = ms_needle_find(needle, ms_string_slice(text, read, text.len));
        if (before == SIZE_MAX) {
            break;
        }
        count++;
        read += before + needle->pattern.len;
    }
    return count;
}

/* The length of text after replacing `count` matches of old_len bytes by replacement_len bytes; faults over the
 * string limit. */
static size_t replaced_length(size_t text_len, size_t count, size_t old_len, size_t replacement_len) {
    size_t added = 0, removed = 0, grown = 0, total = 0;
    if (!ms_size_mul(count, replacement_len, &added) || !ms_size_mul(count, old_len, &removed) ||
        !ms_size_add(text_len, added, &grown) || !ms_size_sub(grown, removed, &total) || total > MS_STR_MAX_BYTES) {
        ms_limit_fault();
    }
    return total;
}

/* replace_first: the first match, or the empty pattern before everything. */
void msrt_string_replace_first(const MsStr *s, const MsStr *old, const MsStr *replacement, MsStr *out) {
    const MsBytes text = ms_str_bytes(s), old_text = ms_str_bytes(old), with = ms_str_bytes(replacement);
    size_t at = 0;
    if (old_text.len != 0) {
        at = ms_find(text.ptr, text.len, old_text.ptr, old_text.len);
        if (at == SIZE_MAX) {
            ms_str_write(ms_str_cloned(s), out);
            return;
        }
    }
    const size_t total = replaced_length(text.len, 1, old_text.len, with.len);
    uint8_t small[MS_STR_INLINE_MAX + 1] = {0};
    const MsStr heap = total > MS_STR_INLINE_MAX ? ms_str_alloc(total) : (MsStr){.ptr_word = NULL, .tagged = 0};
    const MsBytesMut destination = ms_bytes_mut(total > MS_STR_INLINE_MAX ? heap.ptr_word : small, total);
    size_t written = write_at(destination, 0, ms_string_slice(text, 0, at));
    written = write_at(destination, written, with);
    (void)write_at(destination, written, ms_string_slice(text, at + old_text.len, text.len));
    ms_str_write(total > MS_STR_INLINE_MAX ? heap : ms_str_from_bytes(small, total), out);
}

/* Replaces every match of a non-empty old_text by a replacement no longer than it, in one search pass: the result
 * cannot exceed the text, so it is written into a text-sized block and trimmed afterwards. */
static MsStr replace_shrinking(const MsStr *s, MsBytes old_text, MsBytes with) {
    const MsBytes text = ms_str_bytes(s);
    const MsNeedle needle = ms_needle_for(old_text, text.len);
    size_t before = ms_needle_find(&needle, text);
    if (before == SIZE_MAX) {
        return ms_str_cloned(s); /* nothing to replace */
    }
    const MsBytesMut block = ms_bytes_mut(msrt_alloc(text.len + 1), text.len + 1);
    size_t written = 0, read = 0;
    while (before != SIZE_MAX) {
        written = write_at(block, written, ms_string_slice(text, read, read + before));
        written = write_at(block, written, with);
        read += before + old_text.len;
        before = ms_needle_find(&needle, ms_string_slice(text, read, text.len));
    }
    written = write_at(block, written, ms_string_slice(text, read, text.len));
    if (written <= MS_STR_INLINE_MAX) {
        const MsStr result = ms_str_from_bytes(block.ptr, written);
        msrt_free(block.ptr);
        return result;
    }
    /* Text known to be ASCII stays so when the replacement is. */
    const bool ascii = !ms_str_is_inline(s) && (s->tagged & MS_STR_ASCII) != 0 && ms_bytes_ascii(with.ptr, with.len);
    const MsStr result = ms_str_owned(msrt_realloc(block.ptr, written + 1), written);
    return ascii ? ms_str_with_ascii(result) : result;
}

/* Replaces every match; a result over the string limit faults like concat. The input is only read. */
void msrt_string_replace(const MsStr *s, const MsStr *old, const MsStr *replacement, MsStr *out) {
    const MsBytes text = ms_str_bytes(s), old_text = ms_str_bytes(old), with = ms_str_bytes(replacement);
    if (old_text.len != 0 && with.len <= old_text.len) {
        ms_str_write(replace_shrinking(s, old_text, with), out);
        return;
    }
    MsNeedle needle = {.pattern = old_text, .rare_index = 0, .prepared = false};
    size_t count = 0;
    if (old_text.len == 0) {
        count = ms_utf8_count(text.ptr, text.len) + 1;
    } else {
        needle = ms_needle_for(old_text, text.len);
        count = count_matches(&needle, text);
    }
    const size_t total = replaced_length(text.len, count, old_text.len, with.len);
    if (count == 0) {
        ms_str_write(ms_str_cloned(s), out); /* nothing to replace */
        return;
    }
    const bool ascii = ms_str_is_ascii(s) && ms_str_is_ascii(replacement);
    const MsReplacement job = {.text = text, .old_text = old_text, .replacement = with, .needle = &needle, .matches = count};
    ms_str_write(build_exact(total, ascii, old_text.len == 0 ? fill_inserted : fill_replaced, &job), out);
}

/* Moves bytes within one buffer; the ranges may overlap. */
static void move_within(MsBytesMut buffer, size_t to, size_t from, size_t length) {
    const MsBytes source = ms_string_slice(ms_bytes_view(buffer), from, from + length);
    if (!ms_bytes_copy(slice_mut(buffer, to, to + length), source)) {
        ms_string_internal_fault();
    }
}

/* replace of a string that dies at the call: a replacement no longer than its match is written over the same
 * allocation, left to right, so the write position never passes the read position. Other cases build the
 * result as replace does and free the input. `s` is taken: the caller must not use or free it afterwards. */
void msrt_string_replace_take(MsStr *s, const MsStr *old, const MsStr *replacement, MsStr *out) {
    const MsBytes old_text = ms_str_bytes(old), with = ms_str_bytes(replacement);
    const bool in_place = s->tagged < MS_STR_INLINE && old_text.len != 0 && with.len <= old_text.len;
    if (!in_place) {
        msrt_string_replace(s, old, replacement, out);
        ms_str_release(s);
        return;
    }
    const MsBytesMut buffer = ms_bytes_mut(s->ptr_word, ms_str_len(s));
    const bool ascii = (s->tagged & MS_STR_ASCII) != 0 && ms_bytes_ascii(with.ptr, with.len);
    const MsNeedle needle = ms_needle_for(old_text, buffer.len);
    size_t written = 0, read = 0;
    for (;;) {
        const size_t before = ms_needle_find(&needle, ms_string_slice(ms_bytes_view(buffer), read, buffer.len));
        if (before == SIZE_MAX) {
            break;
        }
        move_within(buffer, written, read, before);
        written += before;
        written = write_at(buffer, written, with);
        read += before + old_text.len;
    }
    if (read == 0) {
        ms_str_write(*s, out); /* nothing to replace: the input is the result */
        return;
    }
    const size_t rest = buffer.len - read;
    move_within(buffer, written, read, rest);
    const size_t total = written + rest;
    if (total <= MS_STR_INLINE_MAX) {
        const MsStr result = ms_str_from_bytes(buffer.ptr, total);
        msrt_free(buffer.ptr);
        ms_str_write(result, out);
        return;
    }
    const MsStr result = ms_str_owned(buffer.ptr, total);
    ms_str_write(ascii ? ms_str_with_ascii(result) : result, out);
}
