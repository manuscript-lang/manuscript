/* ms_rt/vec.h: the list value (crates/ms-rt-abi VecVal): a pointer to the elements, their count and the capacity
 * in elements. A list with cap 0 borrows its elements from a caller's buffer. */
#ifndef MS_RT_VEC_H
#define MS_RT_VEC_H

#include "ms_rt/base.h"

typedef struct MsVec {
    void *ptr; /* owned unless cap is 0 */
    size_t len;
    size_t cap;
} MsVec;

#endif
