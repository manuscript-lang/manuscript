/* ms_rt/base.h: what every module header includes. The ABI of a module lives in ms_rt/<module>.h and the
 * symbols it defines in C are listed in runtime/symbols/<module>.txt (`cargo xtask symbols --check`
 * compares the two with the recorded signatures).
 *
 * Rules for everything under runtime/sys and runtime/core:
 *  - include only freestanding headers (stdint.h, stddef.h, stdbool.h) here and in core, so one source
 *    compiles for glibc, musl, macOS and Windows without a C library's headers;
 *  - an exported function is declared with the exact signature crates/ms-lower/rt_symbols.txt records;
 *  - a function listed in a symbols file is defined in C and its Rust definition is compiled out.
 *
 * Values cross as the runtime scalar ABI: Int is int64_t, Float is double, UInt64 travels as the
 * int64_t bit pattern.
 */
#ifndef MS_RT_BASE_H
#define MS_RT_BASE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Status codes of fallible natives (crates/ms-rt-abi STATUS_*). */
enum {
    MS_STATUS_OK = 0,
    MS_STATUS_INVALID_INPUT = 1,
    MS_STATUS_OUT_OF_RANGE = 2,
    MS_STATUS_LIMIT_EXCEEDED = 3
};

#endif
