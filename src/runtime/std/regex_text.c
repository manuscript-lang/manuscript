/* runtime/std/regex_text.c: the @std/regex natives that answer with text: the matched texts, group texts and
 * pieces. Each is one visitor over ms_regex_each_match, so the match order, the empty-match rule and the
 * engine limits are the ones of the offset natives in regex_abi.c. */
#include "runtime/std/regex_internal.h"

#include "runtime/core/string_support.h"

/* The text[start..end] of a match as a new string. */
static MsString piece_of(MsSpan text, int64_t start, int64_t end) {
  return msrt_string_make(ms_span_of(text.ptr + start, (size_t)(end - start)));
}

/* The texts of one match's groups; "" for a group that did not take part. */
static void push_groups(MsStringList *list, MsSpan text, const MsRegexMatch *match) {
  for (size_t group = 0; group < match->pair_count; group++) {
    const int64_t start = match->slots[group * 2];
    const int64_t end = match->slots[group * 2 + 1];
    ms_string_list_push(list, start < 0 ? ms_string_empty() : piece_of(text, start, end));
  }
}

/* A list built from a scan under a count budget; `rows` holds lists of strings, `strings` strings. */
typedef struct TextCollector {
  MsSpan text;
  MsStringList strings;
  MsListList rows;
  uint64_t limit; /* matches (or pieces minus one) the list may hold */
  uint64_t count;
  int64_t piece_start; /* split: where the next piece begins */
} TextCollector;

static const MsTypeDesc list_of_strings_desc = {
    .size = sizeof(MsList),
    .align = _Alignof(MsList),
    .kind = MS_KIND_LIST,
    .inner0 = &ms_desc_string,
};

static uint8_t collect_matched_text(void *state, const MsRegexMatch *match) {
  TextCollector *collector = state;
  if (collector->count++ == collector->limit) {
    return MS_STATUS_LIMIT_EXCEEDED;
  }
  ms_string_list_push(&collector->strings, piece_of(collector->text, match->slots[0], match->slots[1]));
  return MS_STATUS_OK;
}

static uint8_t collect_pieces(void *state, const MsRegexMatch *match) {
  TextCollector *collector = state;
  if (collector->count++ == collector->limit) {
    return MS_STATUS_LIMIT_EXCEEDED;
  }
  ms_string_list_push(&collector->strings,
                      piece_of(collector->text, collector->piece_start, match->slots[0]));
  collector->piece_start = match->slots[1];
  return MS_STATUS_OK;
}

static uint8_t collect_group_rows(void *state, const MsRegexMatch *match) {
  TextCollector *collector = state;
  if (collector->count++ == collector->limit) {
    return MS_STATUS_LIMIT_EXCEEDED;
  }
  MsStringList row = {0};
  ms_string_list_reserve(&row, match->pair_count);
  push_groups(&row, collector->text, match);
  ms_list_list_push(&collector->rows, *ms_string_list_erased(&row));
  return MS_STATUS_OK;
}

/* Runs `visit` over the matches and moves the finished list to `out` when the scan stays within budget. */
static uint8_t scan_into_list(const void *handle, const MsString *text, MsRegexVisitFn visit,
                              TextCollector *collector, bool rows, MsList *out) {
  collector->text = ms_string_span(text);
  const uint8_t status = ms_regex_each_match(ms_regex_of(handle), collector->text, visit, collector);
  MsList *list = rows ? ms_list_list_erased(&collector->rows) : ms_string_list_erased(&collector->strings);
  if (status != MS_STATUS_OK) {
    ms_list_drop_desc(list, rows ? &list_of_strings_desc : &ms_desc_string);
    return status;
  }
  *out = *list;
  return MS_STATUS_OK;
}

uint8_t msstd_regex_find_all(const void *re, const MsString *text, uint8_t has_max, int64_t max,
                             MsList *out) {
  TextCollector collector = {0};
  if (!ms_regex_budget(has_max, max, &collector.limit)) {
    return MS_STATUS_INVALID_INPUT;
  }
  return scan_into_list(re, text, collect_matched_text, &collector, false, out);
}

uint8_t msstd_regex_captures_all(const void *re, const MsString *text, uint8_t has_max, int64_t max,
                                 MsList *out) {
  TextCollector collector = {0};
  if (!ms_regex_budget(has_max, max, &collector.limit)) {
    return MS_STATUS_INVALID_INPUT;
  }
  return scan_into_list(re, text, collect_group_rows, &collector, true, out);
}

/* The pieces between matches, always at least one. A budget of n allows n pieces, so n - 1 matches. */
uint8_t msstd_regex_split(const void *re, const MsString *text, uint8_t has_max, int64_t max, MsList *out) {
  TextCollector collector = {0};
  if (!ms_regex_budget(has_max, max, &collector.limit)) {
    return MS_STATUS_INVALID_INPUT;
  }
  if (has_max && collector.limit == 0) {
    return MS_STATUS_LIMIT_EXCEEDED;
  }
  if (has_max) {
    collector.limit--;
  }
  const uint8_t status = scan_into_list(re, text, collect_pieces, &collector, false, out);
  if (status == MS_STATUS_OK) {
    const MsSpan whole = ms_string_span(text);
    MsStringList *pieces = (MsStringList *)(void *)out;
    ms_string_list_push(pieces, piece_of(whole, collector.piece_start, (int64_t)whole.len));
  }
  return status;
}

/* ---- the first match ---- */

static uint8_t first_match_groups(void *state, const MsRegexMatch *match) {
  TextCollector *collector = state;
  push_groups(&collector->strings, collector->text, match);
  return MS_REGEX_STOP;
}

/* A limit reads as no match, as for `matches`: the result is then empty. */
static void finish_first_match(uint8_t status, MsStringList *list, MsList *out) {
  if (status != MS_STATUS_OK) {
    ms_list_drop_desc(ms_string_list_erased(list), &ms_desc_string);
  }
  *out = *ms_string_list_erased(list);
}

void msstd_regex_captures(const void *re, const MsString *text, MsList *out) {
  TextCollector collector = {.text = ms_string_span(text)};
  const uint8_t status = ms_regex_each_match(ms_regex_of(re), collector.text, first_match_groups, &collector);
  finish_first_match(status, &collector.strings, out);
}

typedef struct NamedCollector {
  const MsRegex *re;
  TextCollector texts;
} NamedCollector;

static uint8_t first_match_names(void *state, const MsRegexMatch *match) {
  NamedCollector *collector = state;
  for (size_t group = 1; group < match->pair_count; group++) {
    const MsSpan name = ms_re_group_name(collector->re, group);
    if (name.len == 0 || match->slots[group * 2] < 0) {
      continue;
    }
    ms_string_list_push(&collector->texts.strings, msrt_string_make(name));
    ms_string_list_push(&collector->texts.strings, piece_of(collector->texts.text, match->slots[group * 2],
                                                            match->slots[group * 2 + 1]));
  }
  return MS_REGEX_STOP;
}

void msstd_regex_named_capture_pairs(const void *re, const MsString *text, MsList *out) {
  NamedCollector collector = {.re = ms_regex_of(re), .texts = {.text = ms_string_span(text)}};
  const uint8_t status =
      ms_regex_each_match(collector.re, collector.texts.text, first_match_names, &collector);
  finish_first_match(status, &collector.texts.strings, out);
}
