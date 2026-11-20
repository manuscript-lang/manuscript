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

#endif
