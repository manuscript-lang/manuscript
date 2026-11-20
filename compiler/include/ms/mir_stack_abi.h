/* The stack-region layout generated code relies on (runtime/core/stack.h owns it): every task stack
 * lies inside a region aligned to its size, so masking the stack pointer finds the region's end,
 * and the last 16 bytes there hold the task header pointer and the recursion limit. */
#ifndef MS_MIR_STACK_ABI_H
#define MS_MIR_STACK_ABI_H

#include <stdint.h>

enum {
    MIR_STACK_REGION = 256 << 20, /* region size and alignment */
    MIR_STACK_CELL_HDR = 16,      /* the task header pointer, bytes before the region's end */
    MIR_STACK_CELL_LIMIT = 8,     /* the recursion limit, bytes before the region's end */
    MIR_HDR_CANCEL = 8            /* the cancel flag byte, offset into the task header */
};

#endif
