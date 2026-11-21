/* The generated table of runtime functions that are one MIR instruction (rt_ops_data.inc, written
 * by `cargo xtask symbols` from the `ms-sig` tags), searched by symbol. libms.c includes this file. */
#include <string.h>

#include "ms/rt_ops.h"

#include "rt_ops_data.inc"

const MsRtOp *ms_rt_op_find(const char *symbol, size_t length) {
    size_t low = 0;
    size_t high = sizeof rt_ops / sizeof rt_ops[0];
    while (low < high) {
        const size_t middle = low + (high - low) / 2;
        const MsRtOp *row = &rt_ops[middle];
        const size_t common = strlen(row->symbol) < length ? strlen(row->symbol) : length;
        int order = strncmp(row->symbol, symbol, common);
        if (order == 0) {
            order = strlen(row->symbol) == length ? 0 : (strlen(row->symbol) < length ? -1 : 1);
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
