/* ms_rt/shape_text.h: the text form of a value, read through its shape table (abi/shape.h). `repr` is the
 * quoted form test failures print: strings in quotes, record fields in declaration order, case names bare.
 * The plain form is what interpolation shows: strings raw (an empty string nested in a container shows as
 * `""`), record fields by name, other cases as `Type.Case`. Nesting past 64 levels shows `...`. */
#ifndef MS_RUNTIME_STD_SHAPE_TEXT_H
#define MS_RUNTIME_STD_SHAPE_TEXT_H

#include "abi/shape.h"

/* The text form of the value at `value`, of the table's root shape. */
void ms_shape_text_of(const MsShapeTable *table, const void *value, bool repr, MsString *out);

/* The same for the value of shape `shape` of the table, such as a map key. */
void ms_shape_text_at(const MsShapeTable *table, uint32_t shape, const void *value, bool repr, MsString *out);

/* The decimal digits of the BigInt handle `cell`. The BigInt natives install this when they make their first handle, so
 * a program that formats values but never makes a BigInt does not link the arbitrary-precision code. */
typedef void (*MsShapeBigIntText)(const void *cell, MsString *out);
void ms_shape_text_set_bigint(MsShapeBigIntText text);

/* ms-sig: msstd_test_repr(shape: *const ShapeTable, value: *const u8, out: *mut StrVal) @domain=test @end */
void msstd_test_repr(const MsShapeTable *table, const void *value, MsString *out);

/* ms-sig: msstd_value_text(shape: *const ShapeTable, value: *const u8, out: *mut StrVal) @domain=string @end */
void msstd_value_text(const MsShapeTable *table, const void *value, MsString *out);

/* ms-sig: msstd_value_to_string(shape: *const ShapeTable, value: *const u8, out: *mut StrVal) @domain=string @end */
void msstd_value_to_string(const MsShapeTable *table, const void *value, MsString *out);

#endif
