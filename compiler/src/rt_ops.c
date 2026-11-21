/* The generated table of runtime functions (rt_ops_data.inc, written
 * by `cargo xtask symbols` from the `ms-sig` tags), searched by symbol. libms.c includes this file. */
#include <string.h>

#include "ms/rt_ops.h"

#include "rt_ops_data.inc"

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
