/* The @std/regex natives that answer with text: the matched texts, group texts, pieces and replacements. Each is
 * one visitor over ms_regex_each_match, so the match order, the empty-match rule and the engine limits are the
 * ones of the offset natives in regex_abi.c. Strings are built with ms_rt/strbuild.h. */
#include <stdbool.h>

#include "ms_rt/regex.h"
#include "ms_rt/safe.h"
#include "ms_rt/strbuild.h"
#include "regex_internal.h"

/* ---- lists of strings ---- */

/* The text[start..end] of a match as a new string. */
static MsStr piece_of(const uint8_t *text, int64_t start, int64_t end) {
    return ms_str_from_bytes(text + start, (size_t)(end - start));
}

static void push_string(MsVec *list, MsStr value) { msrt_list_push(list, &msrt_desc_string, &value); }

/* The texts of one match's groups; "" for a group that did not take part. */
static void push_groups(MsVec *list, const uint8_t *text, const MsRegexMatch *match) {
    for (size_t group = 0; group < match->pair_count; group++) {
        const int64_t start = match->slots[group * 2];
        const int64_t end = match->slots[group * 2 + 1];
        push_string(list, start < 0 ? ms_str_empty() : piece_of(text, start, end));
    }
}

/* A list of strings built from a scan under a count budget. */
typedef struct TextCollector {
    const uint8_t *text;
    MsVec list;
    uint64_t limit; /* matches (or pieces minus one) the list may hold */
    uint64_t count;
    int64_t piece_start; /* split: where the next piece begins */
} TextCollector;

static uint8_t collect_matched_text(void *state, const MsRegexMatch *match) {
    TextCollector *collector = state;
    if (collector->count++ == collector->limit) {
        return STATUS_LIMIT_EXCEEDED;
    }
    push_string(&collector->list, piece_of(collector->text, match->slots[0], match->slots[1]));
    return STATUS_OK;
}

static uint8_t collect_pieces(void *state, const MsRegexMatch *match) {
    TextCollector *collector = state;
    if (collector->count++ == collector->limit) {
        return STATUS_LIMIT_EXCEEDED;
    }
    push_string(&collector->list, piece_of(collector->text, collector->piece_start, match->slots[0]));
    collector->piece_start = match->slots[1];
    return STATUS_OK;
}

static const MsTypeDesc list_of_strings_desc = {
    .size = sizeof(MsVec),
    .align = _Alignof(MsVec),
    .kind = MS_TYPE_KIND_LIST,
    .inner0 = &msrt_desc_string,
};

static uint8_t collect_group_rows(void *state, const MsRegexMatch *match) {
    TextCollector *collector = state;
    if (collector->count++ == collector->limit) {
        return STATUS_LIMIT_EXCEEDED;
    }
    MsVec row = {0};
    msrt_list_with_capacity(&msrt_desc_string, (int64_t)match->pair_count, &row);
    push_groups(&row, collector->text, match);
    msrt_list_push(&collector->list, &list_of_strings_desc, &row);
    return STATUS_OK;
}

/* Drops a half-built result of a scan that failed. */
static void drop_rows(MsVec *list, const MsTypeDesc *element) { msrt_list_drop(list, element); }

/* Runs `visit` over the matches and moves the list to `out` when the scan finishes within budget. */
static uint8_t scan_into_list(const void *handle, const MsStr *text, MsRegexVisitFn visit, TextCollector *collector,
                              const MsTypeDesc *element, MsVec *out) {
    collector->text = ms_str_data(text);
    msrt_list_with_capacity(element, 0, &collector->list);
    const uint8_t status = ms_regex_each_match(ms_regex_of(handle), msrt_str_data(text), msrt_str_len(text), visit, collector);
    if (status != STATUS_OK) {
        drop_rows(&collector->list, element);
        return status;
    }
    *out = collector->list;
    return STATUS_OK;
}

uint8_t msstd_regex_find_all(const void *re, const MsStr *text, uint8_t has_max, int64_t max, MsVec *out) {
    TextCollector collector = {0};
    if (!ms_regex_budget(has_max, max, &collector.limit)) {
        return STATUS_INVALID_INPUT;
    }
    return scan_into_list(re, text, collect_matched_text, &collector, &msrt_desc_string, out);
}

uint8_t msstd_regex_captures_all(const void *re, const MsStr *text, uint8_t has_max, int64_t max, MsVec *out) {
    TextCollector collector = {0};
    if (!ms_regex_budget(has_max, max, &collector.limit)) {
        return STATUS_INVALID_INPUT;
    }
    return scan_into_list(re, text, collect_group_rows, &collector, &list_of_strings_desc, out);
}

/* The pieces between matches, always at least one. A budget of n allows n pieces, so n - 1 matches. */
uint8_t msstd_regex_split(const void *re, const MsStr *text, uint8_t has_max, int64_t max, MsVec *out) {
    TextCollector collector = {0};
    if (!ms_regex_budget(has_max, max, &collector.limit)) {
        return STATUS_INVALID_INPUT;
    }
    if (has_max && collector.limit == 0) {
        return STATUS_LIMIT_EXCEEDED;
    }
    if (has_max) {
        collector.limit--;
    }
    const uint8_t status = scan_into_list(re, text, collect_pieces, &collector, &msrt_desc_string, out);
    if (status == STATUS_OK) {
        push_string(out, piece_of(collector.text, collector.piece_start, (int64_t)msrt_str_len(text)));
    }
    return status;
}

/* ---- the first match ---- */

static uint8_t first_match_groups(void *state, const MsRegexMatch *match) {
    TextCollector *collector = state;
    push_groups(&collector->list, collector->text, match);
    return MS_REGEX_STOP;
}

void msstd_regex_captures(const void *re, const MsStr *text, MsVec *out) {
    TextCollector collector = {.text = ms_str_data(text)};
    msrt_list_with_capacity(&msrt_desc_string, 0, &collector.list);
    const uint8_t status = ms_regex_each_match(ms_regex_of(re), msrt_str_data(text), msrt_str_len(text), first_match_groups, &collector);
    if (status != STATUS_OK) { /* a limit reads as no match, as for `matches` */
        msrt_list_drop(&collector.list, &msrt_desc_string);
        msrt_list_with_capacity(&msrt_desc_string, 0, &collector.list);
    }
    *out = collector.list;
}

typedef struct NamedCollector {
    const MsRegex *re;
    TextCollector texts;
} NamedCollector;

static uint8_t first_match_names(void *state, const MsRegexMatch *match) {
    NamedCollector *collector = state;
    for (size_t group = 1; group < match->pair_count; group++) {
        size_t name_length = 0;
        const char *name = ms_re_group_name(collector->re, group, &name_length);
        if (name == NULL || match->slots[group * 2] < 0) {
            continue;
        }
        push_string(&collector->texts.list, ms_str_from_bytes((const uint8_t *)name, name_length));
        push_string(&collector->texts.list, piece_of(collector->texts.text, match->slots[group * 2], match->slots[group * 2 + 1]));
    }
    return MS_REGEX_STOP;
}

void msstd_regex_named_capture_pairs(const void *re, const MsStr *text, MsVec *out) {
    NamedCollector collector = {.re = ms_regex_of(re), .texts = {.text = ms_str_data(text)}};
    msrt_list_with_capacity(&msrt_desc_string, 0, &collector.texts.list);
    const uint8_t status = ms_regex_each_match(collector.re, msrt_str_data(text), msrt_str_len(text), first_match_names, &collector);
    if (status != STATUS_OK) {
        msrt_list_drop(&collector.texts.list, &msrt_desc_string);
        msrt_list_with_capacity(&msrt_desc_string, 0, &collector.texts.list);
    }
    *out = collector.texts.list;
}
