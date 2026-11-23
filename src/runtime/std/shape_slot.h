/* runtime/std/shape_slot.h: reads of an integer slot of a shape, widened by the shape's size. */
#ifndef MS_RUNTIME_STD_SHAPE_SLOT_H
#define MS_RUNTIME_STD_SHAPE_SLOT_H

#include "abi/shape.h"

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

#endif
