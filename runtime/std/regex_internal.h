/* What the @std/regex natives share: the handle object, budgets, and one loop over the matches of a text. */
#ifndef MS_STD_REGEX_INTERNAL_H
#define MS_STD_REGEX_INTERNAL_H

#include <stdbool.h>

#include "abi.h"
#include "ms_rt/safe.h"
#include "regex.h"

/* The object a compiled pattern lives in: the runtime header, then the pattern. */
typedef struct MsRegexCell {
    MsObj header;
    MsRegex *re; /* owned */
} MsRegexCell;

/* The pattern behind a handle the runtime passes. */
static inline const MsRegex *ms_regex_of(const void *handle) { return ((const MsRegexCell *)handle)->re; }

/* An optional budget: unset is unlimited, a negative one is an error. */
static inline bool ms_regex_budget(uint8_t has_value, int64_t value, uint64_t *out) {
    *out = UINT64_MAX;
    if (!has_value) {
        return true;
    }
    if (value < 0) {
        return false;
    }
    *out = (uint64_t)value;
    return true;
}

/* The status for an engine result that is not a match. */
static inline uint8_t ms_regex_status_of(int engine_result) {
    return engine_result == MS_RE_LIMIT ? STATUS_LIMIT_EXCEEDED : STATUS_FAILED;
}

/* A visitor result that ends the scan without an error (the first match was all that was wanted). */
enum { MS_REGEX_STOP = STATUS_NONE };

/* One match as the engine reports it: `pair_count` groups, each two byte offsets (-1, -1 when absent). */
typedef struct MsRegexMatch {
    const int64_t *slots; /* borrowed from the scan, valid during the visit */
    size_t pair_count;
} MsRegexMatch;

/* Called for each match in order; anything but STATUS_OK stops the scan with that status, except MS_REGEX_STOP,
 * which ends it successfully. */
typedef uint8_t (*MsRegexVisitFn)(void *state, const MsRegexMatch *match);

/* Runs `visit` over every match of text[0..len), with the adjacency rule of MsRegexIter. STATUS_OK once the text is
 * exhausted. */
MS_NODISCARD uint8_t ms_regex_each_match(const MsRegex *re, const char *text, size_t len, MsRegexVisitFn visit, void *state);

#endif
