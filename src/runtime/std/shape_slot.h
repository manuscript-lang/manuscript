/* runtime/std/shape_slot.h: reads of an integer slot of a shape, widened by the shape's size. */
#ifndef MS_RUNTIME_STD_SHAPE_SLOT_H
#define MS_RUNTIME_STD_SHAPE_SLOT_H

#include <string.h>
#include "abi/shape.h"
#include "base/alloc.h"

#define MS_SLOT_AT(type, address) ((const type *)(const void *)(address))

static inline int64_t ms_shape_read_signed(const MsShape *shape, const uint8_t *slot) {
  switch (shape->size) {
  case 1:
    return *(const int8_t *)slot;
  case 2:
    return *MS_SLOT_AT(int16_t, slot);
  case 4:
    return *MS_SLOT_AT(int32_t, slot);
  default:
    return *MS_SLOT_AT(int64_t, slot);
  }
}

static inline uint64_t ms_shape_read_unsigned(const MsShape *shape, const uint8_t *slot) {
  switch (shape->size) {
  case 1:
    return *slot;
  case 2:
    return *MS_SLOT_AT(uint16_t, slot);
  case 4:
    return *MS_SLOT_AT(uint32_t, slot);
  default:
    return *MS_SLOT_AT(uint64_t, slot);
  }
}

/* A hook reads and writes a value in its own layout. An EMBEDDED shape's value lies in a flattened image with its leaves
 * placed by the host, so the leaves are gathered into a buffer in the own layout first (zeroed when `slot` is NULL, for a
 * hook that builds the value) and, after a hook that builds, scattered back. */
typedef struct MsOwnSlot {
  _Alignas(16) uint8_t small[256];
  uint8_t *heap;
} MsOwnSlot;

static inline const uint8_t *ms_own_gather(MsOwnSlot *own, const MsShapeTable *table, const MsShape *shape,
                                           const uint8_t *slot) {
  own->heap = NULL;
  if ((shape->flags & MS_SHAPE_EMBEDDED) == 0) {
    return slot;
  }
  uint8_t *bytes = own->small;
  if (shape->size > sizeof own->small) {
    own->heap = ms_alloc(shape->size);
    bytes = own->heap;
  }
  memset(bytes, 0, shape->size);
  uint32_t count = 0;
  const MsShapeMember *leaves = ms_shape_leaves(table, shape, &count);
  for (uint32_t at = 0; slot != NULL && at < count; at++) {
    memcpy(bytes + leaves[at].tag, ms_shape_member_at(slot, &leaves[at]), leaves[at].count);
  }
  return bytes;
}

static inline void ms_own_scatter(const MsShapeTable *table, const MsShape *shape, const uint8_t *own, uint8_t *slot) {
  if ((shape->flags & MS_SHAPE_EMBEDDED) == 0) {
    return;
  }
  uint32_t count = 0;
  const MsShapeMember *leaves = ms_shape_leaves(table, shape, &count);
  for (uint32_t at = 0; at < count; at++) {
    memcpy(slot + (int32_t)leaves[at].offset, own + leaves[at].tag, leaves[at].count);
  }
}

static inline void ms_own_done(MsOwnSlot *own) {
  if (own->heap != NULL) {
    ms_free(own->heap);
  }
}

#endif
