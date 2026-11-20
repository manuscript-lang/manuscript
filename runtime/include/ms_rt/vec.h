/* ms_rt/vec.h: the list value (crates/ms-rt-abi VecVal): a pointer to the elements, their count and the capacity
 * in elements. A list with cap 0 borrows its elements from a caller's buffer. */
#ifndef MS_RT_VEC_H
#define MS_RT_VEC_H

#include "ms_rt/base.h"

typedef struct ms_vec {
    uint8_t *ptr;
    size_t len;
    size_t cap;
} ms_vec;

#endif
