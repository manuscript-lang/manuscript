/* ms_rt/bytes.h: Bytes values and the byte builder (runtime/core/bytes.c). A Bytes value is an MsList of
 * one-byte elements; a result that can fail reports through the status protocol (ms_rt/base.h).
 */
#ifndef MS_RT_BYTES_H
#define MS_RT_BYTES_H

#include "ms_rt/desc.h"

void msrt_bytes_drop(MsList *b);
void msrt_bytes_copy(const MsList *b, MsList *out);
uint8_t msrt_bytes_contains(const MsList *b, const MsList *v);
uint8_t msrt_bytes_index_of(const MsList *b, const MsList *v, int64_t *out);
uint8_t msrt_bytes_index_of_byte(const MsList *b, int64_t value, int64_t start, int64_t *out);
uint8_t msrt_bytes_last_index_of(const MsList *b, const MsList *v, int64_t *out);
uint8_t msrt_bytes_starts_with(const MsList *b, const MsList *v);
uint8_t msrt_bytes_ends_with(const MsList *b, const MsList *v);
int64_t msrt_bytes_get(const MsList *b, int64_t index, uint8_t has_default, int64_t default_value);
uint8_t msrt_bytes_slice(const MsList *b, int64_t start, int64_t end, MsList *out);
void msrt_bytes_view(const MsList *b, int64_t start, int64_t end, MsList *out);
uint8_t msrt_bytes_eq(const MsList *a, const MsList *b);
void msrt_bytes_reversed(const MsList *b, MsList *out);
void msrt_bytes_with_value(const MsList *b, int64_t index, int64_t value, MsList *out);
void msrt_bytes_concat(const MsList *a, const MsList *b, MsList *out);
void msrt_bytes_split(const MsList *b, const MsList *sep, MsList *out);
void msrt_bytes_values(const MsList *b, MsList *out);
void msrt_bytes_join(const MsList *parts, MsList *out);
void msrt_bytes_from_values(const MsList *values, MsList *out);
void msrt_bytes_append(MsList *b, int64_t value);
void msrt_bytes_extend(MsList *b, const MsList *values);
uint8_t msrt_bytes_read_word(const MsList *b, int64_t at, int64_t width, uint8_t little, int64_t *out);

#endif
