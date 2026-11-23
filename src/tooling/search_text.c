/* Owns search_text.h. */
#include "tooling/search_text.h"

#include "base/message.h"
#include "base/strbuild.h"

bool ms_text_is_blank(uint8_t c) {
  return c == ' ' || c == '\t' || c == '\r' || c == '\n';
}

MsSpan ms_text_one_spaced(MsArena *arena, MsSpan s) {
  MsStrBuild out = ms_strbuild_new();
  size_t i = 0;
  bool first = true;
  while (i < s.len) {
    while (i < s.len && ms_text_is_blank(s.ptr[i])) {
      i++;
    }
    size_t j = i;
    while (j < s.len && !ms_text_is_blank(s.ptr[j])) {
      j++;
    }
    if (j > i) {
      ms_strbuild_append_text(&out, first ? "" : " ");
      ms_strbuild_append(&out, ms_span_of(s.ptr + i, j - i));
      first = false;
    }
    i = j;
  }
  return ms_message_take_builder(arena, &out);
}

bool ms_text_is_subsequence(MsSpan needle, MsSpan haystack) {
  size_t i = 0;
  for (size_t k = 0; k < haystack.len; k++) {
    if (i < needle.len && needle.ptr[i] == haystack.ptr[k]) {
      i++;
    }
  }
  return i == needle.len;
}

size_t ms_text_edit_distance(MsArena *arena, MsSpan a, MsSpan b, size_t limit) {
  if ((a.len > b.len ? a.len - b.len : b.len - a.len) > limit) {
    return limit + 1;
  }
  const size_t cols = b.len + 1;
  size_t *d = MS_ARENA_NEW_ARRAY(arena, size_t, (a.len + 1) * cols);
  for (size_t i = 0; i <= a.len; i++) {
    d[i * cols] = i;
  }
  for (size_t j = 0; j <= b.len; j++) {
    d[j] = j;
  }
  for (size_t i = 1; i <= a.len; i++) {
    for (size_t j = 1; j <= b.len; j++) {
      const size_t cost = a.ptr[i - 1] != b.ptr[j - 1] ? 1 : 0;
      size_t best = d[(i - 1) * cols + j] + 1;
      const size_t insert = d[i * cols + j - 1] + 1;
      const size_t replace = d[(i - 1) * cols + j - 1] + cost;
      best = insert < best ? insert : best;
      best = replace < best ? replace : best;
      if (i > 1 && j > 1 && a.ptr[i - 1] == b.ptr[j - 2] && a.ptr[i - 2] == b.ptr[j - 1]) {
        const size_t swap = d[(i - 2) * cols + j - 2] + 1;
        best = swap < best ? swap : best;
      }
      d[i * cols + j] = best;
    }
  }
  return d[a.len * cols + b.len];
}
