/* runtime/core/bytes.h: Bytes values, the byte builder and the string builder. A Bytes value is an MsList of
 * one-byte elements; a result that can fail reports through the status protocol (abi/status.h). */
#ifndef MS_RUNTIME_CORE_BYTES_H
#define MS_RUNTIME_CORE_BYTES_H

#include "abi/status.h"
#include "base/bytes.h"
#include "base/string.h"

/* ms-sig: msrt_bytes_drop(b: *mut VecVal) @domain=binary @end */
void msrt_bytes_drop(MsList *b);
/* ms-sig: msrt_bytes_length(b: *const VecVal) -> i64 @domain=binary @end */
/* ms-op: msrt_bytes_length list_len */
int64_t msrt_bytes_length(const MsList *b);
/* ms-sig: msrt_bytes_is_empty(b: *const VecVal) -> u8 @domain=binary @end */
/* ms-op: msrt_bytes_is_empty list_is_empty */
uint8_t msrt_bytes_is_empty(const MsList *b);
/* ms-sig: msrt_bytes_copy(b: *const VecVal, out: *mut VecVal) @domain=binary @end */
void msrt_bytes_copy(const MsList *b, MsList *out);
/* ms-sig: msrt_bytes_contains(b: *const VecVal, v: *const VecVal) -> u8 @domain=binary @end */
uint8_t msrt_bytes_contains(const MsList *b, const MsList *v);
/* ms-sig: msrt_bytes_index_of(b: *const VecVal, v: *const VecVal, out: *mut i64) -> u8 @domain=binary @end */
uint8_t msrt_bytes_index_of(const MsList *b, const MsList *v, int64_t *out);
/* ms-sig: msrt_bytes_index_of_byte(b: *const VecVal, value: i64, start: i64, out: *mut i64) -> u8
 * @domain=binary @end */
uint8_t msrt_bytes_index_of_byte(const MsList *b, int64_t value, int64_t start, int64_t *out);
/* ms-sig: msrt_bytes_last_index_of(b: *const VecVal, v: *const VecVal, out: *mut i64) -> u8 @domain=binary
 * */
uint8_t msrt_bytes_last_index_of(const MsList *b, const MsList *v, int64_t *out);
/* ms-sig: msrt_bytes_starts_with(b: *const VecVal, v: *const VecVal) -> u8 @domain=binary @end */
uint8_t msrt_bytes_starts_with(const MsList *b, const MsList *v);
/* ms-sig: msrt_bytes_ends_with(b: *const VecVal, v: *const VecVal) -> u8 @domain=binary @end */
uint8_t msrt_bytes_ends_with(const MsList *b, const MsList *v);
/* ms-sig: msrt_bytes_get(b: *const VecVal, index: i64, has_default: HasRaw, default: i64) -> i64
 * @domain=binary @end */
int64_t msrt_bytes_get(const MsList *b, int64_t index, uint8_t has_default, int64_t default_value);
/* ms-sig: msrt_bytes_slice(b: *const VecVal, start: i64, end: i64, out: *mut VecVal) -> u8 @domain=binary
 * */
uint8_t msrt_bytes_slice(const MsList *b, int64_t start, int64_t end, MsList *out);
/* ms-sig: msrt_bytes_view(b: *const VecVal, start: i64, end: i64, out: *mut VecVal) @borrows @domain=binary
 * */
void msrt_bytes_view(const MsList *b, int64_t start, int64_t end, MsList *out);
/* ms-sig: msrt_bytes_eq(a: *const VecVal, b: *const VecVal) -> u8 @domain=collection @end */
uint8_t msrt_bytes_eq(const MsList *a, const MsList *b);
/* ms-sig: msrt_bytes_reversed(b: *const VecVal, out: *mut VecVal) @domain=binary @end */
void msrt_bytes_reversed(const MsList *b, MsList *out);
/* ms-sig: msrt_bytes_with_value(b: *const VecVal, index: i64, value: i64, out: *mut VecVal) @domain=binary
 * */
void msrt_bytes_with_value(const MsList *b, int64_t index, int64_t value, MsList *out);
/* ms-sig: msrt_bytes_concat(a: *const VecVal, b: *const VecVal, out: *mut VecVal) @domain=binary @end */
void msrt_bytes_concat(const MsList *a, const MsList *b, MsList *out);
/* ms-sig: msrt_bytes_split(b: *const VecVal, sep: *const VecVal, out: *mut VecVal) @domain=binary @end */
void msrt_bytes_split(const MsList *b, const MsList *sep, MsList *out);
/* ms-sig: msrt_bytes_values(b: *const VecVal, out: *mut VecVal) @domain=binary @end */
void msrt_bytes_values(const MsList *b, MsList *out);
/* ms-repr: Bytes bytes_buffer */
/* ms-repr: BytesBuilder bytes_buffer */
/* ms-repr: StringBuilder bytes_buffer */
/* ms-sig: msrt_bytes_join(parts: *const VecVal, out: *mut VecVal) @domain=binary @end */
void msrt_bytes_join(const MsList *parts, MsList *out);
/* ms-sig: msrt_bytes_from_values(values: *const VecVal, out: *mut VecVal) @domain=binary @end */
void msrt_bytes_from_values(const MsList *values, MsList *out);
/* ms-sig: msrt_bytes_from_ints(values: *const VecVal, out: *mut VecVal) @domain=binary @end */
void msrt_bytes_from_ints(const MsList *values, MsList *out);
/* ms-sig: msrt_bytes_append(b: *mut VecVal, value: i64) @domain=binary @method=BytesBuilder.append */
void msrt_bytes_append(MsList *b, int64_t value);
/* ms-sig: msrt_bytes_extend(b: *mut VecVal, values: *const VecVal) @domain=binary
 * @method=BytesBuilder.append_bytes */
void msrt_bytes_extend(MsList *b, const MsList *values);
/* ms-sig: msrt_bytes_read_word(b: *const VecVal, at: i64, width: i64, little: u8, out: *mut i64) -> u8
 * @domain=binary @end */
uint8_t msrt_bytes_read_word(const MsList *b, int64_t at, int64_t width, uint8_t little, int64_t *out);

/* ms-sig: msrt_bytes_decode_utf8(b: *const VecVal, out: *mut StrVal) -> u8 @domain=binary
 * */
uint8_t msrt_bytes_decode_utf8(const MsList *b, MsString *out);
/* The Bytes dies at the call: the string reuses its buffer, and invalid input frees it. */
/* ms-sig: msrt_bytes_decode_utf8_take(b: *mut VecVal, out: *mut StrVal) -> u8 @domain=binary @end */
uint8_t msrt_bytes_decode_utf8_take(MsList *b, MsString *out);
/* ms-sig: msrt_bytes_decode_utf8_range(b: *const VecVal, start: i64, end: i64, out: *mut StrVal) -> u8
 * @domain=binary @end */
uint8_t msrt_bytes_decode_utf8_range(const MsList *b, int64_t start, int64_t end, MsString *out);

/* The bytes of a BytesBuilder moved out: `build` consumes the builder, `drain` leaves it empty. */
/* ms-sig: msrt_bytesbuilder_build(b: *mut VecVal, out: *mut VecVal) @domain=binary @method=BytesBuilder.build */
void msrt_bytesbuilder_build(MsList *b, MsList *out);
/* ms-sig: msrt_bytesbuilder_drain(b: *mut VecVal, out: *mut VecVal) @domain=binary @method=BytesBuilder.drain */
void msrt_bytesbuilder_drain(MsList *b, MsList *out);

#endif
