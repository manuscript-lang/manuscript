/* compiler/check/suggest.c: near-miss suggestions and name lists (see suggest.h). */
#include "compiler/check/suggest.h"

#include "base/sort.h"

static uint8_t lower(uint8_t byte) {
  return byte >= 'A' && byte <= 'Z' ? (uint8_t)(byte + ('a' - 'A')) : byte;
}

/* Levenshtein distance of the two spans compared case-insensitively; names longer than 64 bytes are far. */
static size_t edit_distance(MsSpan a, MsSpan b) {
  enum { MAX = 64 };
  if (a.len > MAX || b.len > MAX) {
    return MAX;
  }
  size_t previous[MAX + 1];
  size_t current[MAX + 1];
  for (size_t j = 0; j <= b.len; j++) {
    previous[j] = j;
  }
  for (size_t i = 1; i <= a.len; i++) {
    current[0] = i;
    for (size_t j = 1; j <= b.len; j++) {
      const size_t cost = lower(a.ptr[i - 1]) != lower(b.ptr[j - 1]);
      size_t best = previous[j] + 1;
      best = current[j - 1] + 1 < best ? current[j - 1] + 1 : best;
      best = previous[j - 1] + cost < best ? previous[j - 1] + cost : best;
      current[j] = best;
    }
    for (size_t j = 0; j <= b.len; j++) {
      previous[j] = current[j];
    }
  }
  return previous[b.len];
}

/* Whether one span, lower-cased, starts with the other. */
static bool related(MsSpan a, MsSpan b) {
  const size_t common = a.len < b.len ? a.len : b.len;
  for (size_t index = 0; index < common; index++) {
    if (lower(a.ptr[index]) != lower(b.ptr[index])) {
      return false;
    }
  }
  return true;
}

bool ms_suggest_closest(MsSpan name, const MsSpanList *candidates, MsSpan *best) {
  if (name.len < 3) {
    return false;
  }
  const size_t limit = (name.len + 1) / 3 < 3 ? (name.len + 1) / 3 : 3;
  const size_t prefix_limit = (name.len + 2) / 3 < 3 ? (name.len + 2) / 3 : 3;
  bool found = false;
  size_t best_distance = 0;
  bool best_unrelated = false;
  for (size_t index = 0; index < candidates->len; index++) {
    const MsSpan candidate = candidates->ptr[index];
    if (ms_span_equal(candidate, name)) {
      continue;
    }
    const size_t distance = edit_distance(name, candidate);
    const bool unrelated = !related(name, candidate);
    if (distance > (unrelated ? limit : prefix_limit)) {
      continue;
    }
    const bool smaller = distance < best_distance || (distance == best_distance && !unrelated && best_unrelated);
    const bool equal = distance == best_distance && unrelated == best_unrelated;
    if (!found || smaller || (equal && ms_span_compare(candidate, *best) < 0)) {
      *best = candidate;
      found = true;
      best_distance = distance;
      best_unrelated = unrelated;
    }
  }
  return found;
}

bool ms_suggest_did_you_mean(MsStrBuild *out, MsSpan name, const MsSpanList *candidates) {
  MsSpan best = {0};
  if (!ms_suggest_closest(name, candidates, &best)) {
    return false;
  }
  ms_strbuild_append_text(out, "; did you mean '");
  ms_strbuild_append(out, best);
  ms_strbuild_append_text(out, "'?");
  return true;
}

void ms_suggest_list(MsStrBuild *out, const MsSpanList *names, size_t limit) {
  MsSpanList sorted = {0};
  for (size_t index = 0; index < names->len; index++) {
    if (names->ptr[index].len != 0) {
      ms_span_list_push(&sorted, names->ptr[index]);
    }
  }
  ms_sort((uint8_t *)(void *)sorted.ptr, sorted.len, sizeof(MsSpan), ms_sort_compare_spans, NULL);
  size_t written = 0;
  bool more = false;
  for (size_t index = 0; index < sorted.len; index++) {
    if (index != 0 && ms_span_equal(sorted.ptr[index], sorted.ptr[index - 1])) {
      continue;
    }
    if (written == limit) {
      more = true;
      break;
    }
    if (written != 0) {
      ms_strbuild_append_text(out, ", ");
    }
    ms_strbuild_append(out, sorted.ptr[index]);
    written++;
  }
  if (more) {
    ms_strbuild_append_text(out, ", ...");
  }
  ms_span_list_free(&sorted);
}
