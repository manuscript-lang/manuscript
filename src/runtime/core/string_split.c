/* runtime/core/string_split.c: splitting and replacing strings: split, split_view, split_view_into,
 * split_first, the split iterator, replace, replace_first and replace_take.
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

/* Split at a separator of one or more bytes. */
static void split_at_pattern(MsSpan text, MsSpan separator, MsStringList *list, PieceMode mode) {
  const MsNeedle needle = ms_needle_for(separator, text.len);
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

static void split_into(const MsString *s, const MsString *sep, MsList *out, PieceMode mode) {
  const MsSpan text = msrt_text(s);
  const MsSpan separator = msrt_text(sep);
  MsStringList list = {0};
  if (separator.len == 0) {
    split_scalars(text, &list, mode);
  } else {
    split_at_pattern(text, separator, &list, mode);
  }
  *out = *ms_string_list_erased(&list);
}

void msrt_string_split(const MsString *s, const MsString *sep, MsList *out) {
  split_into(s, sep, out, PIECE_COPY);
}

void msrt_string_split_view(const MsString *s, const MsString *sep, MsList *out) {
  split_into(s, sep, out, PIECE_VIEW);
}

/* Splits at a one-byte separator into `buffer` (room for SPLIT_FRAME_PIECES); false when it fills up. */
static bool split_into_buffer(MsSpan text, uint8_t separator, MsString *buffer, size_t *count) {
  size_t start = 0;
  *count = 0;
  for (;;) {
    const size_t hit = ms_find_byte(separator, text.ptr + start, text.len - start);
    const size_t end = hit == SIZE_MAX ? text.len : start + hit;
    if (*count == SPLIT_FRAME_PIECES) {
      return false;
    }
    buffer[(*count)++] = make_piece(PIECE_VIEW, between(text, start, end));
    if (hit == SIZE_MAX) {
      return true;
    }
    start = end + 1;
  }
}

/* The view split into the caller's frame buffer when the text is short and has at most eight pieces at a
 * one-byte separator (the list then has capacity 0: it owns nothing); otherwise the heap list of split_view.
 */
void msrt_string_split_view_into(const MsString *s, const MsString *sep, MsString *buffer, MsList *out) {
  const MsSpan text = msrt_text(s);
  const MsSpan separator = msrt_text(sep);
  size_t count = 0;
  if (separator.len == 1 && text.len <= SPLIT_FRAME_TEXT_MAX &&
      split_into_buffer(text, separator.ptr[0], buffer, &count)) {
    *out = (MsList){.ptr = (uint8_t *)(void *)buffer, .len = count, .cap = 0};
    return;
  }
  split_into(s, sep, out, PIECE_VIEW);
}

/* text.split(separator)[0], a view of text, found without building the list. Faults like an index of an empty
 * list when text is empty and the separator is not. */
void msrt_string_split_first(const MsString *s, const MsString *sep, MsString *out) {
  const MsSpan text = msrt_text(s);
  const MsSpan separator = msrt_text(sep);
  size_t end = 0;
  if (separator.len == 0) {
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
  *out = make_piece(PIECE_VIEW, between(text, 0, end));
}

/* ---- the split iterator ---- */

/* The state of `for piece in text.split(separator)`, which walks the pieces without building the list. A
 * piece is a view of the text (an inline copy when short). The iterator holds copies of the two string
 * values, since a short string's bytes are inside its value. */
struct MsSplitIter {
  MsObj header;
  MsString text;
  MsString separator;
  MsNeedle needle; /* the separator prepared for the text; its pattern points into `separator` */
  size_t position; /* the start of the next piece */
  bool done;
};

static void split_iter_drop(MsObj *object) {
  ms_free(object);
}

MsSplitIter *msrt_string_split_iter(const MsString *s, const MsString *sep) {
  MsSplitIter *iter = ms_alloc(sizeof *iter);
  iter->header = (MsObj){.clone = NULL, .drop = split_iter_drop};
  iter->text = *s;
  iter->separator = *sep;
  const MsSpan separator = msrt_text(&iter->separator);
  iter->needle = separator.len == 0 ? (MsNeedle){0} : ms_needle_for(separator, ms_string_length(&iter->text));
  iter->position = 0;
  iter->done = false;
  return iter;
}

/* The next piece of a split at a separator; the last one runs to the end of the text. */
static MsSpan next_delimited(MsSplitIter *iter, MsSpan text, size_t separator_length) {
  const MsSpan rest = between(text, iter->position, text.len);
  const size_t at = ms_needle_find(&iter->needle, rest);
  if (at == SIZE_MAX) {
    iter->done = true;
    return rest;
  }
  iter->position += at + separator_length;
  return between(rest, 0, at);
}

uint8_t msrt_split_next(MsSplitIter *iter, MsString *out) {
  if (iter->done) {
    return 0;
  }
  const MsSpan text = msrt_text(&iter->text);
  const size_t separator_length = ms_string_length(&iter->separator);
  MsSpan piece = {0};
  if (separator_length != 0) {
    piece = next_delimited(iter, text, separator_length);
  } else if (iter->position < text.len) {
    const size_t width = ms_utf8_decode(text.ptr + iter->position, text.len - iter->position).width;
    piece = between(text, iter->position, iter->position + width);
    iter->position += width;
  } else {
    iter->done = true;
    return 0;
  }
  *out = msrt_string_view_of(piece);
  return 1;
}

/* ---- replace ---- */

/* The length of text after replacing `count` matches of old_len bytes by replacement_len bytes; faults over
 * the string limit. */
static size_t replaced_length(size_t text_len, size_t count, size_t old_len, size_t replacement_len) {
  size_t added = 0;
  size_t removed = 0;
  size_t grown = 0;
  size_t total = 0;
  if (!ms_size_mul(count, replacement_len, &added) || !ms_size_mul(count, old_len, &removed) ||
      !ms_size_add(text_len, added, &grown) || !ms_size_sub(grown, removed, &total) ||
      total > MSRT_STRING_LIMIT) {
    msrt_string_limit_fault();
  }
  return total;
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
  uint8_t *destination = length <= MS_STRING_INLINE_MAX ? small : msrt_string_block(length, &result);
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

/* Replaces every match; a result over the string limit faults like concat. The input is only read. */
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
  const size_t total = replaced_length(text.len, job.matches, old_text.len, job.replacement.len);
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
  *out = build_exact(replaced_length(text.len, 1, old_text.len, job.replacement.len), fill_first, &job);
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
