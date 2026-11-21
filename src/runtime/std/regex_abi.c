/* The @std/regex natives that answer with offsets: the runtime's ABI over regex.c. Every result is plain integers
 * (byte offsets), so no string crosses here; regex_text.c builds the texts. */
#include <stdbool.h>

#include "ms_rt/regex.h"
#include "regex_internal.h"

static void cell_drop(MsObj *object) {
    ms_re_free(((MsRegexCell *)object)->re);
    msrt_free(object);
}

/* The compile error as an owned string for the caller, when it asked for one. */
static void write_error(MsStr *err, const char *message) {
    if (err == NULL) {
        return;
    }
    const size_t length = strlen(message);
    char *bytes = msrt_alloc(length + 1);
    memcpy(bytes, message, length + 1);
    err->ptr_word = (uint8_t *)bytes;
    err->tagged = length; /* owned: the top two bits are 00 */
}

uint8_t msstd_regex_compile(const MsStr *pattern, void **out, MsStr *err) {
    char message[200];
    MsRegex *re = ms_re_compile(msrt_str_data(pattern), msrt_str_len(pattern), message, sizeof message);
    MsRegexCell *cell = re ? msrt_alloc(sizeof *cell) : NULL;
    if (cell == NULL) {
        write_error(err, message);
        ms_re_free(re);
        return STATUS_INVALID_DATA;
    }
    cell->header.clone = NULL;
    cell->header.drop = cell_drop;
    cell->re = re;
    *out = cell;
    return STATUS_OK;
}

uint8_t msstd_regex_matches(const void *re, const MsStr *text) {
    return ms_re_match(ms_regex_of(re), msrt_str_data(text), msrt_str_len(text), 0, NULL) == MS_RE_MATCHED;
}

static void push_int(MsVec *list, int64_t value) { msrt_list_push(list, &msrt_desc_int, &value); }

/* Remembers the first match's whole span and stops the scan. */
typedef struct FirstSpan {
    int64_t start, end;
    uint8_t found;
} FirstSpan;

static uint8_t record_first_span(void *state, const MsRegexMatch *match) {
    FirstSpan *first = state;
    first->start = match->slots[0];
    first->end = match->slots[1];
    first->found = 1;
    return MS_REGEX_STOP;
}

uint8_t msstd_regex_find_span(const void *re, const MsStr *text, MsVec *out) {
    FirstSpan first = {0};
    const uint8_t status = ms_regex_each_match(ms_regex_of(re), msrt_str_data(text), msrt_str_len(text),
                                               record_first_span, &first);
    if (status != STATUS_OK || !first.found) {
        return 0;
    }
    msrt_list_with_capacity(&msrt_desc_int, 2, out);
    push_int(out, first.start);
    push_int(out, first.end);
    return 1;
}

/* The answer to a query whose budget cannot hold even one match: only whether a match exists decides. */
static uint8_t exists_or_limit(const MsRegex *re, const MsStr *text, MsVec *out) {
    const int result = ms_re_match(re, msrt_str_data(text), msrt_str_len(text), 0, NULL);
    if (result != MS_RE_NOMATCH) {
        return STATUS_LIMIT_EXCEEDED;
    }
    msrt_list_with_capacity(&msrt_desc_int, 0, out);
    return STATUS_OK;
}

/* A list of integers being built by a scan, with the budget of matches it may hold. */
typedef struct SpanCollector {
    MsVec list;
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
        return STATUS_LIMIT_EXCEEDED;
    }
    if (collector->all_groups && collector->list.len == 0) {
        push_int(&collector->list, (int64_t)match->pair_count);
    }
    const size_t written = collector->all_groups ? match->pair_count * 2 : 2;
    for (size_t i = 0; i < written; i++) {
        push_int(&collector->list, match->slots[i]);
    }
    collector->matches++;
    collector->slots_used += match->pair_count;
    return collector->first_only ? MS_REGEX_STOP : STATUS_OK;
}

/* Runs a collector over the text and moves its list to `out` when the scan finishes within budget. */
static uint8_t collect(const MsRegex *re, const MsStr *text, SpanCollector *collector, MsVec *out) {
    msrt_list_with_capacity(&msrt_desc_int, 0, &collector->list);
    const uint8_t status = ms_regex_each_match(re, msrt_str_data(text), msrt_str_len(text), collect_match, collector);
    if (status != STATUS_OK) {
        msrt_list_drop(&collector->list, &msrt_desc_int);
        return status;
    }
    *out = collector->list;
    return STATUS_OK;
}

uint8_t msstd_regex_find_all_spans(const void *re, const MsStr *text, uint8_t has_max, int64_t max, MsVec *out) {
    SpanCollector collector = {.capture_limit = UINT64_MAX};
    if (!ms_regex_budget(has_max, max, &collector.match_limit)) {
        return STATUS_INVALID_INPUT;
    }
    if (collector.match_limit == 0) {
        return exists_or_limit(ms_regex_of(re), text, out);
    }
    return collect(ms_regex_of(re), text, &collector, out);
}

/* Capture slots of the first match: empty when absent, else the slot count, then a byte pair per group (-1, -1 for a
 * group that did not take part). */
uint8_t msstd_regex_capture_spans(const void *re, const MsStr *text, uint8_t has_max, int64_t max, MsVec *out) {
    const MsRegex *regex = ms_regex_of(re);
    uint64_t limit = 0;
    if (!ms_regex_budget(has_max, max, &limit)) {
        return STATUS_INVALID_INPUT;
    }
    const size_t count = ms_re_slots(regex);
    if (count > limit) {
        return exists_or_limit(regex, text, out);
    }
    SpanCollector collector = {.match_limit = 1, .capture_limit = UINT64_MAX, .all_groups = true, .first_only = true};
    return collect(regex, text, &collector, out);
}

/* Every match's capture row: empty when nothing matches, else the slot count, then each row's byte pairs. */
uint8_t msstd_regex_capture_all_spans(const void *re, const MsStr *text, uint8_t has_matches, int64_t max_matches,
                                      uint8_t has_captures, int64_t max_captures, MsVec *out) {
    const MsRegex *regex = ms_regex_of(re);
    SpanCollector collector = {.all_groups = true};
    if (!ms_regex_budget(has_matches, max_matches, &collector.match_limit) ||
        !ms_regex_budget(has_captures, max_captures, &collector.capture_limit)) {
        return STATUS_INVALID_INPUT;
    }
    if (collector.match_limit == 0 || ms_re_slots(regex) > collector.capture_limit) {
        return exists_or_limit(regex, text, out);
    }
    return collect(regex, text, &collector, out);
}
