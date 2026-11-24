/* compiler/emit/emit_units.h: cutting a module into several LLVM modules, so `opt` and `llc` can run on each at once. */
#ifndef MS_COMPILER_EMIT_EMIT_UNITS_H
#define MS_COMPILER_EMIT_EMIT_UNITS_H

#include "compiler/emit/emit.h"

/* Where one function's text is in the module text; `from == to` for a function that was not written. */
typedef struct EmitFuncSpan {
  size_t from, to;
} EmitFuncSpan;

/* How many modules `bytes` of function text are written as: `options->units` at most, and one per
 * `options->unit_bytes`. */
uint32_t emit_unit_count(const EmitOptions *options, size_t bytes);

/* Writes the module text `whole` (`first` bytes of header, then the `nfuncs` functions in `spans`) as up to `wanted`
 * modules into `outs`, which are new builders: each holds the header, its functions (a function no other module
 * defines is `hidden` instead of `internal`) and a declaration of each function another module holds. Returns how many
 * modules have functions; the others are left empty. */
uint32_t emit_split_functions(MsSpan whole, size_t first, const EmitFuncSpan *spans, uint32_t nfuncs, uint32_t wanted,
                              MsStrBuild *outs);

#endif
