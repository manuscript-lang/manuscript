/* ms_rt.h: the ABI of the native runtime, the single source of truth for the C side.
 *
 * Rules for everything under runtime/sys and runtime/core:
 *  - include only freestanding headers (stdint.h, stddef.h, stdbool.h) here and in core, so one
 *    source compiles for glibc, musl, macOS and Windows without a C library's headers;
 *  - an exported function is declared here with the exact signature crates/ms-lower/rt_symbols.txt
 *    records for it (`cargo xtask symbols --check` compares them);
 *  - a function listed in runtime/c-symbols.txt is defined in C and its Rust definition is compiled out.
 *
 * Values cross as the runtime scalar ABI: Int is int64_t, Float is double, UInt64 travels as the
 * int64_t bit pattern.
 */
#ifndef MS_RT_H
#define MS_RT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* core/num.c */
int64_t msrt_float_compare(double a, double b);
int64_t msrt_int_compare(int64_t a, int64_t b);
int64_t msrt_uint_compare(int64_t a, int64_t b);
double msrt_uint_to_float(int64_t v);
double msrt_uint_to_float32(int64_t v);
double msrt_float_from_bits(int64_t bits);
int64_t msrt_float_to_bits(double value);
double msrt_float32_from_bits(int64_t bits);
int64_t msrt_float32_to_bits(double value);
uint8_t msrt_float_truncate_to_int(double v, int64_t *out);
uint8_t msrt_float_to_float32(double v, float *out);

/* core/alloc.c: the allocator. msrt_alloc, msrt_alloc_zeroed, msrt_realloc and msrt_free are the program ABI;
 * the msrt_heap_* functions serve the rest of the runtime (heap claim per thread, sizes, figures). */
void *msrt_alloc(size_t size);
void *msrt_alloc_zeroed(size_t size);
void *msrt_realloc(void *p, size_t size);
void msrt_free(void *p);
void msrt_heap_claim(void);
void msrt_heap_release(void);
uint8_t msrt_heap_has(void);
uint8_t msrt_heap_owns(const void *p);
size_t msrt_heap_usable_size(void *p);
void *msrt_heap_trim(void *p, size_t new_size);
void *msrt_heap_alloc_zeroed_cached(size_t size);
size_t msrt_heap_large_request(size_t size);
void *msrt_heap_shared_take(size_t size);
uint8_t msrt_heap_shared_put(void *p);
void msrt_heap_stats(int64_t *out);
void msrt_heap_requested(uint64_t *out);
void msrt_heap_sample_every(int64_t period, void *hook);

#endif
