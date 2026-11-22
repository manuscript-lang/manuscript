/* ms_rt/shape_json.h: JSON text of a value, written and read through its shape table (abi/shape.h). The
 * encoding rules are those of @std/data/json: records are objects (an absent optional field is left out),
 * an alternative is its case name when bare and `{"Case": {fields}}` otherwise, a map is an object keyed by
 * the text of its keys, a set is an array, Bytes are standard base64, BigInt and Decimal are numbers, and a
 * value without a JSON form (a function, an object handle, an opaque value) is `null` in a list, left out
 * of an object, and an error at the root or under `strict`. */
#ifndef MS_RUNTIME_STD_SHAPE_JSON_H
#define MS_RUNTIME_STD_SHAPE_JSON_H

#include "abi/shape.h"

/* ms-sig: msstd_json_stringify(shape: *const ShapeTable, value: *const u8, has_max_bytes: HasRaw, max_bytes:
 * i64, has_indent: HasRaw, indent: i64, strict: u8, out: *mut StrVal) -> u8 @domain=json @leaf */
uint8_t msstd_json_stringify(const MsShapeTable *table, const void *value, uint8_t has_max_bytes,
                             int64_t max_bytes, uint8_t has_indent, int64_t indent, uint8_t strict,
                             MsString *out);

/* Builds a value of the table's root shape from the JSON `text` into `out` (size of the root shape; zeroed
 * here). The six budgets are the (has, value) pairs of JsonLimits. An unknown object member fails unless
 * `ignore_unknown_fields`. Returns the status of a syntax or limit failure, or MS_STATUS_INVALID_DATA with
 * `err` set to the reason ("JSON: invalid data: at $.a[0]: expected number, found string") when the document
 * does not fit the type; on failure nothing is left owned in `out`. */
/* ms-sig: msstd_json_decode(shape: *const ShapeTable, text: *const StrVal, has_max_bytes: HasRaw, max_bytes:
 * i64, has_max_depth: HasRaw, max_depth: i64, has_max_values: HasRaw, max_values: i64, ignore_unknown_fields:
 * u8, out: *mut u8, err: ErrSlot) -> u8 @domain=json @leaf */
uint8_t msstd_json_decode(const MsShapeTable *table, const MsString *text, uint8_t has_max_bytes,
                          int64_t max_bytes, uint8_t has_max_depth, int64_t max_depth, uint8_t has_max_values,
                          int64_t max_values, uint8_t ignore_unknown_fields, void *out, MsString *err);

#endif
