/* runtime/std/regex_abi.c: the @std/regex natives that answer with offsets: the runtime's ABI over the
 * engine. Every result is plain integers (byte offsets), so no string crosses here; regex_text.c builds the
 * texts. */
#include "runtime/std/regex_internal.h"

#include "base/alloc.h"

static void cell_drop(MsObj *object) {
  MsRegexCell *cell = (MsRegexCell *)object;
  if (atomic_fetch_sub(&cell->refs, 1) != 1) {
    return;
  }
  ms_re_free(cell->re);
  ms_free(object);
}

static MsObj *cell_clone(MsObj *object) {
  atomic_fetch_add(&((MsRegexCell *)object)->refs, 1);
  return object;
}

uint8_t msstd_regex_compile(const MsString *pattern, void **out, MsString *err) {
  MsStrBuild error = ms_strbuild_new();
  MsRegex *re = ms_re_compile(ms_string_span(pattern), &error);
  if (re == NULL) {
    if (err != NULL) {
      *err = ms_strbuild_finish(&error);
    }
    ms_strbuild_free(&error);
    return MS_STATUS_INVALID_DATA;
  }
  MsRegexCell *cell = ms_alloc(sizeof *cell);
  *cell = (MsRegexCell){.header = {.clone = cell_clone, .drop = cell_drop}, .re = re, .refs = 1};
  *out = cell;
  return MS_STATUS_OK;
}

uint8_t msstd_regex_matches(const void *re, const MsString *text) {
  return ms_re_match(ms_regex_of(re), ms_string_span(text), 0, NULL) == MS_RE_MATCHED;
}

/* Remembers the first match's whole span and stops the scan. */
typedef struct FirstSpan {
  int64_t start;
  int64_t end;
  bool found;
} FirstSpan;

static uint8_t record_first_span(void *state, const MsRegexMatch *match) {
  FirstSpan *first = state;
  *first = (FirstSpan){.start = match->slots[0], .end = match->slots[1], .found = true};
  return MS_REGEX_STOP;
}

uint8_t msstd_regex_find_span(const void *re, const MsString *text, MsList *out) {
  FirstSpan first = {0};
  const uint8_t status =
      ms_regex_each_match(ms_regex_of(re), ms_string_span(text), record_first_span, &first);
  if (status != MS_STATUS_OK || !first.found) {
    return 0;
  }
  *out = (MsList){0};
  ms_int_list_push((MsIntList *)(void *)out, first.start);
  ms_int_list_push((MsIntList *)(void *)out, first.end);
  return 1;
}

/* The answer to a query whose budget cannot hold even one match: only whether a match exists decides. */
static uint8_t exists_or_limit(const MsRegex *re, const MsString *text, MsList *out) {
  if (ms_re_match(re, ms_string_span(text), 0, NULL) != MS_RE_NOMATCH) {
    return MS_STATUS_LIMIT_EXCEEDED;
  }
  *out = (MsList){0};
  return MS_STATUS_OK;
}

/* A list of integers being built by a scan, with the budget of matches it may hold. */
typedef struct SpanCollector {
  MsIntList list;
  uint64_t match_limit;
  uint64_t capture_limit; /* slots in total, whole matches included */
  uint64_t matches;
  uint64_t slots_used;
  bool all_groups; /* whether each match writes every group (capture_all_spans) or only the whole match */
  bool first_only; /* stop after the first match */
} SpanCollector;

static uint8_t collect_match(void *state, const MsRegexMatch *match) {
  SpanCollector *collector = state;
  if (collector->matches == collector->match_limit ||
      match->pair_count > collector->capture_limit - collector->slots_used) {
    return MS_STATUS_LIMIT_EXCEEDED;
  }
  if (collector->all_groups && collector->list.len == 0) {
    ms_int_list_push(&collector->list, (int64_t)match->pair_count);
  }
  const size_t written = collector->all_groups ? match->pair_count * 2 : 2;
  for (size_t i = 0; i < written; i++) {
    ms_int_list_push(&collector->list, match->slots[i]);
  }
  collector->matches++;
  collector->slots_used += match->pair_count;
  return collector->first_only ? MS_REGEX_STOP : MS_STATUS_OK;
}

/* Runs a collector over the text and moves its list to `out` when the scan finishes within budget. */
static uint8_t collect(const MsRegex *re, const MsString *text, SpanCollector *collector, MsList *out) {
  const uint8_t status = ms_regex_each_match(re, ms_string_span(text), collect_match, collector);
  if (status != MS_STATUS_OK) {
    ms_int_list_free(&collector->list);
    return status;
  }
  *out = *ms_int_list_erased(&collector->list);
  return MS_STATUS_OK;
}

uint8_t msstd_regex_find_all_spans(const void *re, const MsString *text, uint8_t has_max, int64_t max,
                                   MsList *out) {
  SpanCollector collector = {.capture_limit = UINT64_MAX};
  if (!ms_regex_budget(has_max, max, &collector.match_limit)) {
    return MS_STATUS_INVALID_INPUT;
  }
  if (collector.match_limit == 0) {
    return exists_or_limit(ms_regex_of(re), text, out);
  }
  return collect(ms_regex_of(re), text, &collector, out);
}

/* Capture slots of the first match: empty when absent, else the slot count, then a byte pair per group (-1,
 * -1 for a group that did not take part). */
uint8_t msstd_regex_capture_spans(const void *re, const MsString *text, uint8_t has_max, int64_t max,
                                  MsList *out) {
  const MsRegex *regex = ms_regex_of(re);
  uint64_t limit = 0;
  if (!ms_regex_budget(has_max, max, &limit)) {
    return MS_STATUS_INVALID_INPUT;
  }
  if (ms_re_slots(regex) > limit) {
    return exists_or_limit(regex, text, out);
  }
  SpanCollector collector = {
      .match_limit = 1, .capture_limit = UINT64_MAX, .all_groups = true, .first_only = true};
  return collect(regex, text, &collector, out);
}

/* Every match's capture row: empty when nothing matches, else the slot count, then each row's byte pairs. */
uint8_t msstd_regex_capture_all_spans(const void *re, const MsString *text, uint8_t has_matches,
                                      int64_t max_matches, uint8_t has_captures, int64_t max_captures,
                                      MsList *out) {
  const MsRegex *regex = ms_regex_of(re);
  SpanCollector collector = {.all_groups = true};
  if (!ms_regex_budget(has_matches, max_matches, &collector.match_limit) ||
      !ms_regex_budget(has_captures, max_captures, &collector.capture_limit)) {
    return MS_STATUS_INVALID_INPUT;
  }
  if (collector.match_limit == 0 || ms_re_slots(regex) > collector.capture_limit) {
    return exists_or_limit(regex, text, out);
  }
  return collect(regex, text, &collector, out);
}
