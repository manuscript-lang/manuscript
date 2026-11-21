/* The generated table of runtime functions (rt_ops_data.inc, written
 * by `ms run tools/ms/symbols.ms` from the `ms-sig` tags), searched by symbol. libms.c includes this file. */
#include <string.h>

#include <ctype.h>

#include "ms/check.h"
#include "ms/rt_ops.h"

#include "rt_ops_data.inc"
#include "status_rows_data.inc"

size_t ms_rt_status_rows(const MsRtFn *fn, MsStatusRow *out, size_t cap) {
    const size_t count = sizeof status_rows / sizeof status_rows[0];
    for (size_t i = 0; i < count && i < cap; i++) {
        out[i] = status_rows[i];
        for (size_t k = 0; k < sizeof status_words / sizeof status_words[0]; k++) {
            if (status_words[k].status == status_rows[i].status && strcmp(status_words[k].symbol, fn->symbol) == 0) {
                out[i].words = status_words[k].words;
            }
        }
    }
    return count;
}

const MsRtFn *ms_rt_fn_find(const char *symbol, size_t length) {
    size_t low = 0;
    size_t high = sizeof rt_fns / sizeof rt_fns[0];
    while (low < high) {
        const size_t middle = low + (high - low) / 2;
        const MsRtFn *row = &rt_fns[middle];
        const size_t row_length = strlen(row->symbol);
        const size_t common = row_length < length ? row_length : length;
        int order = strncmp(row->symbol, symbol, common);
        if (order == 0 && row_length != length) {
            order = row_length < length ? -1 : 1;
        }
        if (order == 0) {
            return row;
        }
        if (order < 0) {
            low = middle + 1;
        } else {
            high = middle;
        }
    }
    return NULL;
}

const MsRtFn *ms_rt_method_fn(const MsCheck *c, MsTy receiver, MsSym method) {
    const MsStr type = ms_name(c->names, c->tys.name[receiver]);
    const MsStr name = ms_name(c->names, method);
    char symbol[96];
    if (type.len + name.len + 8 > sizeof symbol) {
        return NULL;
    }
    size_t length = 0;
    for (const char *part = "msrt_"; *part != '\0'; part++) {
        symbol[length++] = *part;
    }
    for (size_t i = 0; i < type.len; i++) {
        symbol[length++] = (char)tolower((unsigned char)type.ptr[i]);
    }
    symbol[length++] = '_';
    for (size_t i = 0; i < name.len; i++) {
        symbol[length++] = name.ptr[i];
    }
    return ms_rt_fn_find(symbol, length);
}
