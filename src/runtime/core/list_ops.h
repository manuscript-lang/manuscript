/* list_ops.h: list operations the rest of src/runtime/core calls directly, without the ABI's pointer dance.
 * The exported symbols (ms_rt/list.h) wrap these.
 */
#ifndef MS_LIST_OPS_H
#define MS_LIST_OPS_H

#include "ms_rt/desc.h"
#include "ms_rt/safe.h"

/* The largest list the runtime builds from a range or a repeat. */
#define MS_LIST_MAX_ITEMS ((size_t)1 << 28)

/* Frees the elements and the buffer of an owned list and leaves it empty. A view is left as it is. */
MS_NONNULL void ms_list_drop(MsList *list, const MsTypeDesc *d);

/* Deep copy of `src` into the uninitialised `out`. */
MS_NONNULL void ms_list_clone(const MsList *src, const MsTypeDesc *d, MsList *out);

/* Copy of a byte buffer into the uninitialised `out`. */
MS_NONNULL void ms_bytes_clone(const MsList *src, MsList *out);

/* Element-wise equality of two lists of `d`. */
MS_NONNULL bool ms_list_eq(const MsList *a, const MsList *b, const MsTypeDesc *d);

/* Makes room for `extra` more elements, growing the buffer when it must. */
MS_NONNULL void ms_list_reserve(MsList *list, const MsTypeDesc *d, size_t extra);

/* Moves the slot at `element` onto the end of the list; the list now owns it. */
MS_NONNULL void ms_list_push(MsList *list, const MsTypeDesc *d, const uint8_t *element);

/* The address of element `index`, which must be below `list->len`. */
static inline uint8_t *ms_list_at(const MsList *list, const MsTypeDesc *d, size_t index) {
    return list->ptr + index * d->size;
}

#endif
