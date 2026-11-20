/* The @std/regex natives: the runtime's ABI over regex.c. Every result is plain integers (byte offsets), so no string
   or map crosses here; texts, replacements and templates are built in stdlib/regex.ms from the spans. */
#include "regex_abi.h"
#include "regex.h"

#include <stdbool.h>

#include "abi.h"

typedef struct {
    MsObj header;
    MsRegex *re; /* owned */
} MsRegexCell;


static const MsRegex *regex_of(const void *handle) { return ((const MsRegexCell *)handle)->re; }

static void cell_drop(MsObj *o) {
    ms_re_free(((MsRegexCell *)o)->re);
    msrt_free(o);
}

uint8_t msstd_regex_compile(const MsStr *pattern, void **out, MsStr *err) {
    char msg[200];
    MsRegex *re = ms_re_compile(msrt_str_data(pattern), msrt_str_len(pattern), msg, sizeof msg);
    MsRegexCell *cell = re ? msrt_alloc(sizeof *cell) : NULL;
    if (!cell) {
        if (err) {
            size_t n = strlen(msg);
            char *bytes = msrt_alloc(n + 1);
            memcpy(bytes, msg, n + 1);
            err->ptr_word = (uint8_t *)bytes;
            err->tagged = n; /* owned: the top two bits are 00 */
        }
        ms_re_free(re);
        return STATUS_INVALID_DATA;
    }
    cell->header.clone = NULL;
    cell->header.drop = cell_drop;
    cell->re = re;
    *out = cell;
    return STATUS_OK;
}

static uint8_t status_of(int rc) { return rc == MS_RE_LIMIT ? STATUS_LIMIT_EXCEEDED : STATUS_FAILED; }

uint8_t msstd_regex_matches(const void *handle, const MsStr *text) {
    /* A match that reaches a limit is reported as no match: the result is a plain Bool. */
    return ms_re_match(regex_of(handle), msrt_str_data(text), msrt_str_len(text), 0, NULL) == MS_RE_MATCHED;
}

static void push_int(MsVec *v, int64_t x) { msrt_list_push(v, msrt_desc_int, &x); }

uint8_t msstd_regex_find_span(const void *handle, const MsStr *text, MsVec *out) {
    int64_t slots[2];
    if (ms_re_match(regex_of(handle), msrt_str_data(text), msrt_str_len(text), 0, slots) != MS_RE_MATCHED) return 0;
    msrt_list_with_capacity(msrt_desc_int, 2, out);
    push_int(out, slots[0]);
    push_int(out, slots[1]);
    return 1;
}

/* A budget: unset is unlimited, a negative one is an error. */
static bool budget(uint8_t has, int64_t value, uint64_t *out) {
    *out = UINT64_MAX;
    if (!has) return true;
    if (value < 0) return false;
    *out = (uint64_t)value;
    return true;
}

/* The answer to a query whose budget cannot hold even one match: only whether a match exists decides. */
static uint8_t exists_or_limit(const MsRegex *re, const MsStr *text) {
    int rc = ms_re_match(re, msrt_str_data(text), msrt_str_len(text), 0, NULL);
    return rc == MS_RE_NOMATCH ? STATUS_OK : STATUS_LIMIT_EXCEEDED;
}

/* A scratch of 2 * slots integers on the stack for small patterns, on the heap beyond. */
enum { INLINE_PAIRS = 16 };

uint8_t msstd_regex_find_all_spans(const void *handle, const MsStr *text, uint8_t has_max, int64_t max, MsVec *out) {
    const MsRegex *re = regex_of(handle);
    uint64_t limit;
    if (!budget(has_max, max, &limit)) return STATUS_INVALID_INPUT;
    if (limit == 0) {
        uint8_t st = exists_or_limit(re, text);
        if (st == STATUS_OK) msrt_list_with_capacity(msrt_desc_int, 0, out);
        return st;
    }
    size_t pairs = ms_re_slots(re);
    int64_t inline_slots[2 * INLINE_PAIRS];
    int64_t *slots = pairs <= INLINE_PAIRS ? inline_slots : msrt_alloc(pairs * 2 * sizeof *slots);
    MsVec v;
    msrt_list_with_capacity(msrt_desc_int, 0, &v);
    MsRegexIter it;
    ms_re_iter_init(&it);
    uint8_t st = STATUS_OK;
    uint64_t count = 0;
    for (;;) {
        int rc = ms_re_next(re, msrt_str_data(text), msrt_str_len(text), &it, slots);
        if (rc == MS_RE_NOMATCH) break;
        if (rc != MS_RE_MATCHED) {
            st = status_of(rc);
            break;
        }
        if (count++ == limit) {
            st = STATUS_LIMIT_EXCEEDED;
            break;
        }
        push_int(&v, slots[0]);
        push_int(&v, slots[1]);
    }
    ms_re_iter_done(&it);
    if (slots != inline_slots) msrt_free(slots);
    if (st != STATUS_OK) {
        msrt_list_drop(&v, msrt_desc_int);
        return st;
    }
    *out = v;
    return STATUS_OK;
}

/* Capture slots of the first match: empty when absent, else the slot count, then a byte pair per group (-1, -1 for a
   group that did not take part). */
uint8_t msstd_regex_capture_spans(const void *handle, const MsStr *text, uint8_t has_max, int64_t max, MsVec *out) {
    const MsRegex *re = regex_of(handle);
    uint64_t limit;
    if (!budget(has_max, max, &limit)) return STATUS_INVALID_INPUT;
    size_t count = ms_re_slots(re);
    if (count > limit) {
        uint8_t st = exists_or_limit(re, text);
        if (st == STATUS_OK) msrt_list_with_capacity(msrt_desc_int, 0, out);
        return st;
    }
    int64_t inline_slots[2 * INLINE_PAIRS];
    int64_t *slots = count <= INLINE_PAIRS ? inline_slots : msrt_alloc(count * 2 * sizeof *slots);
    int rc = ms_re_match(re, msrt_str_data(text), msrt_str_len(text), 0, slots);
    uint8_t st = STATUS_OK;
    if (rc == MS_RE_MATCHED) {
        msrt_list_with_capacity(msrt_desc_int, (int64_t)(count * 2 + 1), out);
        push_int(out, (int64_t)count);
        for (size_t i = 0; i < count * 2; i++) push_int(out, slots[i]);
    } else if (rc == MS_RE_NOMATCH) {
        msrt_list_with_capacity(msrt_desc_int, 0, out);
    } else {
        st = status_of(rc);
    }
    if (slots != inline_slots) msrt_free(slots);
    return st;
}

/* Every match's capture row: empty when nothing matches, else the slot count, then each row's byte pairs. */
uint8_t msstd_regex_capture_all_spans(const void *handle, const MsStr *text, uint8_t has_matches, int64_t max_matches,
                                      uint8_t has_captures, int64_t max_captures, MsVec *out) {
    const MsRegex *re = regex_of(handle);
    uint64_t match_limit, capture_limit;
    if (!budget(has_matches, max_matches, &match_limit) || !budget(has_captures, max_captures, &capture_limit))
        return STATUS_INVALID_INPUT;
    size_t count = ms_re_slots(re);
    if (match_limit == 0 || count > capture_limit) {
        uint8_t st = exists_or_limit(re, text);
        if (st == STATUS_OK) msrt_list_with_capacity(msrt_desc_int, 0, out);
        return st;
    }
    int64_t inline_slots[2 * INLINE_PAIRS];
    int64_t *slots = count <= INLINE_PAIRS ? inline_slots : msrt_alloc(count * 2 * sizeof *slots);
    MsVec v;
    msrt_list_with_capacity(msrt_desc_int, 0, &v);
    MsRegexIter it;
    ms_re_iter_init(&it);
    uint8_t st = STATUS_OK;
    uint64_t matches = 0, used = 0;
    for (;;) {
        int rc = ms_re_next(re, msrt_str_data(text), msrt_str_len(text), &it, slots);
        if (rc == MS_RE_NOMATCH) break;
        if (rc != MS_RE_MATCHED) {
            st = status_of(rc);
            break;
        }
        if (matches == match_limit || count > capture_limit - used) {
            st = STATUS_LIMIT_EXCEEDED;
            break;
        }
        if (v.len == 0) push_int(&v, (int64_t)count);
        for (size_t i = 0; i < count * 2; i++) push_int(&v, slots[i]);
        matches++;
        used += count;
    }
    ms_re_iter_done(&it);
    if (slots != inline_slots) msrt_free(slots);
    if (st != STATUS_OK) {
        msrt_list_drop(&v, msrt_desc_int);
        return st;
    }
    *out = v;
    return STATUS_OK;
}
