/* runtime/core/string_split.c: splitting and replacing strings: split, split_view, split_view_into,
 * split_first, `split_at`, replace, replace_first and replace_take.
 *
 * Ownership: results are written through `out`, which the caller owns from then on. A split list owns its
 * pieces except in the view forms, where long pieces borrow bytes of the text and the caller keeps the text
 * alive for as long as the list is read. */
#include "base/alloc.h"
#include "base/desc.h"
#include "base/search.h"
#include "base/utf8.h"
#include "runtime/core/index_fault.h"
#include "runtime/core/string.h"
#include "runtime/core/string_split.h"
#include "runtime/core/string_support.h"

/* Texts up to this long split at a one-byte separator into the caller's frame buffer. */
#define SPLIT_FRAME_TEXT_MAX 128
/* Pieces the frame buffer of msrt_string_split_view_into holds. */
#define SPLIT_FRAME_PIECES 8

/* How a piece is made: a copy (owned or inline), or a view of the text (for texts that outlive it). */
typedef enum PieceMode { PIECE_COPY, PIECE_VIEW } PieceMode;

static MS_ALWAYS_INLINE MsString make_piece(PieceMode mode, MsSpan bytes) {
  if (bytes.len <= MS_STRING_INLINE_MAX) {
    return ms_string_make_inline(bytes); /* a short piece is its two words, copied or not */
  }
  return mode == PIECE_VIEW ? ms_string_view(bytes) : msrt_string_make(bytes);
}

static MsSpan between(MsSpan text, size_t start, size_t end) {
  return ms_span_of(text.ptr + start, end - start);
}

/* ---- split ---- */

/* Split after each scalar: the piece count is known, so the list is sized once. */
static void split_scalars(MsSpan text, MsStringList *list, PieceMode mode) {
  ms_string_list_reserve(list, ms_utf8_count(text.ptr, text.len));
  for (size_t offset = 0; offset < text.len;) {
    const size_t width = ms_utf8_decode(text.ptr + offset, text.len - offset).width;
    ms_string_list_push(list, make_piece(mode, between(text, offset, offset + width)));
    offset += width;
  }
}

/* Texts up to this long have their pieces counted before the list is built, so a short text's list is one allocation
 * instead of a chain of doublings. A longer text is not scanned twice: the doublings are amortized over its pieces and
 * cost less than a second pass (grep over 22 MB: +24% instructions with the count). */
#define SPLIT_COUNT_TEXT_MAX 4096

/* Split at a separator of one or more bytes. */
static void split_at_pattern(MsSpan text, MsSpan separator, MsStringList *list, PieceMode mode) {
  const MsNeedle needle = ms_needle_for(separator, text.len);
  if (text.len <= SPLIT_COUNT_TEXT_MAX) {
    ms_string_list_reserve(list, ms_count(text.ptr, text.len, separator.ptr, separator.len) + 1);
  }
  size_t piece_start = 0;
  for (;;) {
    const size_t hit = ms_needle_find(&needle, between(text, piece_start, text.len));
    if (hit == SIZE_MAX) {
      ms_string_list_push(list, make_piece(mode, between(text, piece_start, text.len)));
      return;
    }
    ms_string_list_push(list, make_piece(mode, between(text, piece_start, piece_start + hit)));
    piece_start += hit + separator.len;
  }
}

/* The part of `s` a split that has walked to byte `at` still has to cut; false when it has no piece left: `at` is
 * past the text, or at its end for an empty separator (a separator of bytes yields one empty piece there). */
static bool split_rest(MsSpan text, MsSpan separator, int64_t at, MsSpan *rest) {
  if (at < 0 || (size_t)at > text.len || ((size_t)at == text.len && separator.len == 0)) {
    return false;
  }
  *rest = between(text, (size_t)at, text.len);
  return true;
}

static void split_into(const MsString *s, const MsString *sep, int64_t at, MsList *out, PieceMode mode) {
  const MsSpan separator = msrt_text(sep);
  MsSpan text = {0};
  MsStringList list = {0};
  if (!split_rest(msrt_text(s), separator, at, &text)) {
    *out = (MsList){0};
    return;
  }
  if (separator.len == 0) {
    split_scalars(text, &list, mode);
  } else {
    split_at_pattern(text, separator, &list, mode);
  }
  *out = *ms_string_list_erased(&list);
}

void msrt_string_split(const MsString *s, const MsString *sep, MsList *out) {
  split_into(s, sep, 0, out, PIECE_COPY);
}

void msrt_string_split_view(const MsString *s, const MsString *sep, int64_t at, MsList *out) {
  split_into(s, sep, at, out, PIECE_VIEW);
}

/* Splits at a one-byte separator into `buffer` (room for SPLIT_FRAME_PIECES); false when it fills up. The text is
 * scanned once, eight bytes at a time: every separator in a word is found from its mask, so a piece costs no search
 * call of its own. */
static bool split_into_buffer(MsSpan text, uint8_t separator, MsString *buffer, size_t *count) {
  const uint64_t lo = UINT64_C(0x0101010101010101), low7 = UINT64_C(0x7f7f7f7f7f7f7f7f);
  const uint64_t pattern = lo * separator;
  size_t start = 0, at = 0, pieces = 0;
  for (; at < text.len; at += 8) {
    uint64_t mask;
    if (at + 8 <= text.len) {
      const uint64_t x = ms_load64(text.ptr + at) ^ pattern;
      mask = ~(((x & low7) + low7) | x | low7); /* the high bit of each byte equal to the separator */
    } else if (text.len >= 8) { /* the last word overlaps the one before: only its bytes from `at` on are new */
      const uint64_t x = ms_load64(text.ptr + text.len - 8) ^ pattern;
      mask = ~(((x & low7) + low7) | x | low7);
      mask &= ~UINT64_C(0) << ((8 - (text.len - at)) * 8);
      at = text.len - 8;
    } else {
      mask = 0;
      for (size_t k = 0; k < text.len; k++) {
        mask |= (uint64_t)(text.ptr[k] == separator) << (k * 8 + 7);
      }
    }
    for (; mask != 0; mask &= mask - 1) {
      const size_t end = at + (size_t)__builtin_ctzll(mask) / 8;
      if (pieces == SPLIT_FRAME_PIECES) {
        return false;
      }
      buffer[pieces++] = make_piece(PIECE_VIEW, between(text, start, end));
      start = end + 1;
    }
  }
  if (pieces == SPLIT_FRAME_PIECES) {
    return false;
  }
  buffer[pieces++] = make_piece(PIECE_VIEW, between(text, start, text.len));
  *count = pieces;
  return true;
}

/* The view split into the caller's frame buffer when a split from the start is of short text with at most eight pieces at a
 * one-byte separator (the list then has capacity 0: it owns nothing); otherwise the heap list of split_view.
 */
void msrt_string_split_view_into(const MsString *s, const MsString *sep, int64_t at, MsString *buffer, MsList *out) {
  const MsSpan text = msrt_text(s);
  const MsSpan separator = msrt_text(sep);
  size_t count = 0;
  if (at == 0 && separator.len == 1 && text.len <= SPLIT_FRAME_TEXT_MAX &&
      split_into_buffer(text, separator.ptr[0], buffer, &count)) {
    *out = (MsList){.ptr = (uint8_t *)(void *)buffer, .len = count, .cap = 0};
    return;
  }
  split_into(s, sep, at, out, PIECE_VIEW);
}

/* text.split(separator)[0] from byte `at`, a view of text, found without building the list. Faults like an index of
 * an empty list when no piece is left, or text is empty and the separator is not. */
void msrt_string_split_first(const MsString *s, const MsString *sep, int64_t at, MsString *out) {
  const MsSpan separator = msrt_text(sep);
  MsSpan text = {0};
  if (!split_rest(msrt_text(s), separator, at, &text)) {
    msrt_post_index(0, 0);
    *out = make_piece(PIECE_VIEW, between(msrt_text(s), 0, 0)); /* the caller leaves */
    return;
  }
  size_t end = 0;
  if (separator.len == 0) {
    end = ms_utf8_decode(text.ptr, text.len).width;
  } else {
    const MsNeedle needle = ms_needle_for(separator, text.len);
    end = ms_needle_find(&needle, text);
    if (end == SIZE_MAX) {
      end = text.len;
    }
  }
  *out = make_piece(PIECE_VIEW, between(text, 0, end));
}

/* ---- one piece of a split ---- */

/* The piece of `s` that starts at byte `at` when it is split at `sep`: the loop `for piece in s.split(sep)` visits
 * the pieces by byte offset, with no list. `at` is 0 or the end of the previous piece and its separator. A separator
 * of no bytes cuts after each scalar. A piece is a view of the text (an inline copy when short), like the pieces of
 * `split_view`. */
/* The byte offset where the piece that starts at `at` ends. */
static size_t piece_end(MsSpan text, MsSpan separator, size_t at) {
  const MsSpan rest = between(text, at, text.len);
  if (separator.len == 0) {
    return at + (rest.len == 0 ? 0 : ms_utf8_decode(rest.ptr, rest.len).width);
  }
  /* A one-byte separator needs no preparation, and a piece must not pay for any. */
  const MsNeedle needle = separator.len == 1 ? (MsNeedle){.pattern = separator} : ms_needle_for(separator, text.len);
  const size_t hit = ms_needle_find(&needle, rest);
  return at + (hit == SIZE_MAX ? rest.len : hit);
}

/* `piece_end` for the piece at `at`, or -1 when the split has no piece left there (see split_rest). */
int64_t msrt_string_split_end(const MsString *s, const MsString *sep, int64_t at) {
  const MsSpan text = msrt_text(s);
  const MsSpan separator = msrt_text(sep);
  if (at < 0 || (size_t)at > text.len || ((size_t)at == text.len && separator.len == 0)) {
    return -1;
  }
  return (int64_t)piece_end(text, separator, (size_t)at);
}

/* The bytes of `s` from `start` to `end`, a view (an inline string when short). The iterators cut at separators and
 * scalar ends of valid text, so the bounds need no check. */
void msrt_string_piece(const MsString *s, int64_t start, int64_t end, MsString *out) {
  *out = make_piece(PIECE_VIEW, between(msrt_text(s), (size_t)start, (size_t)end));
}

/* ---- replace ---- */

/* The length of text after replacing `count` matches of old_len bytes by replacement_len bytes; posts the limit
 * fault and returns false over the string limit. */
static bool replaced_length(size_t text_len, size_t count, size_t old_len, size_t replacement_len, size_t *out) {
  size_t added = 0;
  size_t removed = 0;
  size_t grown = 0;
  size_t total = 0;
  if (!ms_size_mul(count, replacement_len, &added) || !ms_size_mul(count, old_len, &removed) ||
      !ms_size_add(text_len, added, &grown) || !ms_size_sub(grown, removed, &total) ||
      total > MSRT_STRING_LIMIT) {
    msrt_string_limit_post();
    return false;
  }
  *out = total;
  return true;
}

static uint8_t *write_bytes(uint8_t *destination, MsSpan source) {
  if (source.len != 0) {
    __builtin_memcpy(destination, source.ptr, source.len);
  }
  return destination + source.len;
}

/* Writes the text with `matches` occurrences of the non-empty `old_text` replaced. */
static void fill_replaced(uint8_t *destination, MsSpan text, const MsNeedle *needle, MsSpan replacement,
                          size_t matches) {
  size_t read = 0;
  for (size_t match = 0; match < matches; match++) {
    const MsSpan rest = between(text, read, text.len);
    const size_t before = ms_needle_find(needle, rest);
    destination = write_bytes(destination, between(rest, 0, before));
    destination = write_bytes(destination, replacement);
    read += before + needle->pattern.len;
  }
  (void)write_bytes(destination, between(text, read, text.len));
}

/* Writes the text with the replacement inserted before every scalar and at the end (an empty `old`). */
static void fill_inserted(uint8_t *destination, MsSpan text, MsSpan replacement) {
  for (size_t read = 0;;) {
    destination = write_bytes(destination, replacement);
    if (read >= text.len) {
      return;
    }
    const size_t width = ms_utf8_decode(text.ptr + read, text.len - read).width;
    destination = write_bytes(destination, between(text, read, read + width));
    read += width;
  }
}

static size_t count_matches(const MsNeedle *needle, MsSpan text) {
  size_t count = 0;
  size_t read = 0;
  while (text.len - read >= needle->pattern.len) {
    const size_t before = ms_needle_find(needle, between(text, read, text.len));
    if (before == SIZE_MAX) {
      break;
    }
    count++;
    read += before + needle->pattern.len;
  }
  return count;
}

/* The string of `length` bytes that `fill` writes: inline when it fits, otherwise one allocation. */
typedef void (*FillFn)(uint8_t *destination, const void *context);

static MsString build_exact(size_t length, FillFn fill, const void *context) {
  uint8_t small[MS_STRING_INLINE_MAX + 1];
  MsString result = ms_string_empty();
  uint8_t *destination = length <= MS_STRING_INLINE_MAX ? small : msrt_string_block_post(length, &result);
  if (destination == NULL) {
    return result;
  }
  fill(destination, context);
  return length <= MS_STRING_INLINE_MAX ? msrt_string_make(ms_span_of(small, length)) : result;
}

typedef struct ReplaceJob {
  MsSpan text;
  MsSpan replacement;
  MsNeedle needle; /* for a non-empty old text */
  size_t matches;
} ReplaceJob;

static void fill_job(uint8_t *destination, const void *context) {
  const ReplaceJob *job = context;
  if (job->needle.pattern.len == 0) {
    fill_inserted(destination, job->text, job->replacement);
  } else {
    fill_replaced(destination, job->text, &job->needle, job->replacement, job->matches);
  }
}

/* Replaces every match of the non-empty `needle` by a replacement no longer than it, in one search pass: the
 * result fits the input's length, so it is written into a block of that size and trimmed when mostly spare.
 * Returns false, leaving `out` untouched, when nothing matched. */
static bool replace_shrinking(const MsString *s, const MsNeedle *needle, MsSpan replacement, MsString *out) {
  const MsSpan text = msrt_text(s);
  size_t read = 0;
  size_t before = ms_needle_find(needle, text);
  if (before == SIZE_MAX) {
    return false;
  }
  uint8_t *const block = ms_alloc(text.len);
  uint8_t *destination = block;
  while (before != SIZE_MAX) {
    destination = write_bytes(destination, ms_span_of(text.ptr + read, before));
    destination = write_bytes(destination, replacement);
    read += before + needle->pattern.len;
    before = text.len - read >= needle->pattern.len ? ms_needle_find(needle, between(text, read, text.len))
                                                    : SIZE_MAX;
  }
  destination = write_bytes(destination, between(text, read, text.len));
  const size_t length = (size_t)(destination - block);
  *out = msrt_string_from_block(length > text.len - (text.len >> 2) || length <= MS_STRING_INLINE_MAX
                                    ? block
                                    : ms_realloc(block, length),
                                length);
  return true;
}

/* Replaces every match; a result over the string limit posts the fault like concat. The input is only read. */
void msrt_string_replace(const MsString *s, const MsString *old, const MsString *replacement, MsString *out) {
  const MsSpan text = msrt_text(s);
  const MsSpan old_text = msrt_text(old);
  ReplaceJob job = {.text = text, .replacement = msrt_text(replacement), .needle = {.pattern = old_text}};
  if (old_text.len == 0) {
    job.matches = ms_utf8_count(text.ptr, text.len) + 1;
  } else {
    job.needle = ms_needle_for(old_text, text.len);
    if (job.replacement.len <= old_text.len) {
      if (!replace_shrinking(s, &job.needle, job.replacement, out)) {
        *out = ms_string_clone(s);
      }
      return;
    }
    job.matches = count_matches(&job.needle, text);
  }
  size_t total = 0;
  if (!replaced_length(text.len, job.matches, old_text.len, job.replacement.len, &total)) {
    return;
  }
  *out = job.matches == 0 ? ms_string_clone(s) : build_exact(total, fill_job, &job);
}

typedef struct FirstJob {
  MsSpan text;
  MsSpan replacement;
  size_t at;
  size_t old_length;
} FirstJob;

static void fill_first(uint8_t *destination, const void *context) {
  const FirstJob *job = context;
  destination = write_bytes(destination, between(job->text, 0, job->at));
  destination = write_bytes(destination, job->replacement);
  (void)write_bytes(destination, between(job->text, job->at + job->old_length, job->text.len));
}

/* replace_first: the first match, or the empty pattern before everything. */
void msrt_string_replace_first(const MsString *s, const MsString *old, const MsString *replacement,
                               MsString *out) {
  const MsSpan text = msrt_text(s);
  const MsSpan old_text = msrt_text(old);
  FirstJob job = {.text = text, .replacement = msrt_text(replacement), .at = 0, .old_length = old_text.len};
  if (old_text.len != 0) {
    job.at = ms_find(text.ptr, text.len, old_text.ptr, old_text.len);
    if (job.at == SIZE_MAX) {
      *out = ms_string_clone(s);
      return;
    }
  }
  size_t total = 0;
  if (replaced_length(text.len, 1, old_text.len, job.replacement.len, &total)) {
    *out = build_exact(total, fill_first, &job);
  }
}

/* replace of a string that dies at the call: a replacement no longer than its match is written over the same
 * allocation, left to right, so the write position never passes the read position. Other cases build the
 * result as replace does and free the input. `s` is taken: the caller must not use or free it afterwards. */
void msrt_string_replace_take(MsString *s, const MsString *old, const MsString *replacement, MsString *out) {
  const MsSpan old_text = msrt_text(old);
  const MsSpan with = msrt_text(replacement);
  if (!msrt_string_owns(s) || old_text.len == 0 || with.len > old_text.len) {
    msrt_string_replace(s, old, replacement, out);
    msrt_string_free(s);
    return;
  }
  uint8_t *buffer = s->owned;
  const size_t length = ms_string_length(s);
  const MsNeedle needle = ms_needle_for(old_text, length);
  size_t written = 0;
  size_t read = 0;
  for (;;) {
    const size_t before = ms_needle_find(&needle, ms_span_of(buffer + read, length - read));
    if (before == SIZE_MAX) {
      break;
    }
    __builtin_memmove(buffer + written, buffer + read, before);
    written += before;
    if (with.len != 0) {
      __builtin_memcpy(buffer + written, with.ptr, with.len);
    }
    written += with.len;
    read += before + old_text.len;
  }
  if (read == 0) {
    *out = *s; /* nothing to replace: the input is the result */
    return;
  }
  __builtin_memmove(buffer + written, buffer + read, length - read);
  *out = msrt_string_from_block(buffer, written + (length - read));
}
