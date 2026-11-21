/* ms_rt/base.h: what every module header includes. The ABI of a module lives in ms_rt/<module>.h and the
 * symbols it defines in C are listed in src/runtime/symbols/<module>.txt (`ms run src/ms/symbols.ms -- --check`
 * compares the two with the recorded signatures).
 *
 * Rules for everything under src/runtime/sys and src/runtime/core:
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
    MS_STATUS_LIMIT_EXCEEDED = 3,
    MS_STATUS_INVALID_DATA = 4,
    MS_STATUS_FAILED = 11
};

/* A list or Bytes value: three words (crates/ms-rt-abi VecVal). An empty Bytes has a null `ptr`. */
typedef struct MsVec {
    void *ptr;
    size_t len, cap;
} MsVec;

/* The 16-byte header every heap object starts with (crates/ms-rt-abi Obj): `clone` is null for a value with one
 * owner; `drop` drops the children and frees the object with msrt_free. */
typedef struct MsObj MsObj;
struct MsObj {
    MsObj *(*clone)(MsObj *);
    void (*drop)(MsObj *);
};

#endif
