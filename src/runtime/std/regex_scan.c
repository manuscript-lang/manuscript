/* The loop every @std/regex native over the matches of a whole text shares. */
#include "ms_rt/safe.h"
#include "regex_internal.h"

/* Groups whose offsets fit on the stack; a pattern with more takes a heap scratch. */
enum { INLINE_PAIRS = 16 };

uint8_t ms_regex_each_match(const MsRegex *re, const char *text, size_t len, MsRegexVisitFn visit, void *state) {
    const size_t pair_count = ms_re_slots(re);
    int64_t inline_slots[2 * INLINE_PAIRS];
    int64_t *slots = inline_slots;
    if (pair_count > INLINE_PAIRS) {
        size_t bytes = 0;
        if (!ms_size_mul(pair_count, 2 * sizeof *slots, &bytes)) {
            return STATUS_LIMIT_EXCEEDED;
        }
        slots = msrt_alloc(bytes);
    }
    MsRegexIter iterator;
    ms_re_iter_init(&iterator);
    uint8_t status = STATUS_OK;
    for (;;) {
        const int result = ms_re_next(re, text, len, &iterator, slots);
        if (result == MS_RE_NOMATCH) {
            break;
        }
        if (result != MS_RE_MATCHED) {
            status = ms_regex_status_of(result);
            break;
        }
        const MsRegexMatch match = {.slots = slots, .pair_count = pair_count};
        status = visit(state, &match);
        if (status == MS_REGEX_STOP) {
            status = STATUS_OK;
            break;
        }
        if (status != STATUS_OK) {
            break;
        }
    }
    ms_re_iter_done(&iterator);
    if (slots != inline_slots) {
        msrt_free(slots);
    }
    return status;
}
