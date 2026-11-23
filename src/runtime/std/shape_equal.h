/* runtime/std/shape_equal.h: structural equality of two values of one shape (abi/shape.h): the `equals` of a type
 * that has none of its own. Records compare field by field, alternatives by case and payload, collections by
 * contents (a map or set regardless of order). */
#ifndef MS_RUNTIME_STD_SHAPE_EQUAL_H
#define MS_RUNTIME_STD_SHAPE_EQUAL_H

#include "abi/shape.h"

/* ms-sig: msstd_value_equals(shape: *const ShapeTable, a: *const u8, b: *const u8) -> bool @domain=value @end */
uint8_t msstd_value_equals(const MsShapeTable *table, const void *a, const void *b);

/* ms-sig: msstd_value_hash(shape: *const ShapeTable, value: *const u8) -> i64 @domain=value @end */
int64_t msstd_value_hash(const MsShapeTable *table, const void *value);

#endif
