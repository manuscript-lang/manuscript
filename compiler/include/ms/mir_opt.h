/* libms MIR optimiser: independent passes over a verified module. Each takes the module, keeps it
 * verifying and returns whether it changed anything, as the former Rust passes in crates/ms-mir/src/opt (deleted; see git history)
 * do. The contract (what a pass may move, drop or weaken) is in that crate's `opt/mod.rs` doc and
 * carries over unchanged. */
#ifndef MS_MIR_OPT_H
#define MS_MIR_OPT_H

#include "ms/mir.h"

bool mir_opt_bytetake(MirModule *m); /* a result of a dying value reuses its storage */
bool mir_opt_strfuse(MirModule *m);  /* `s = s + piece` grows `s` in place */

bool mir_opt_loopslot(MirModule *m); /* a loop-carried owned value lives in one slot */

bool mir_opt_optparam(MirModule *m); /* an optional scalar block parameter becomes flag and value */
bool mir_opt_optparam_func(MirModule *m, MirFunc *f);
bool mir_opt_ifconv(MirModule *m); /* small pure diamonds become `select` */
bool mir_opt_ifconv_func(MirModule *m, MirFunc *f);

bool mir_opt_reserve(MirModule *m); /* a list filled by a counted loop is allocated at its final size */
/* The entry point of a generated stable driftsort of `elem` slots by comparator `g` (opt_sortgen). */
uint32_t mir_sortgen_drift(MirModule *m, uint32_t g, MirTy elem);
bool mir_opt_copyelim(MirModule *m);        /* deep copies that only feed reads are removed */
bool mir_opt_copyelim_func(MirModule *m, MirFunc *f);
bool mir_opt_copyelim_takes(MirModule *m);  /* fields of a dying type are moved out */
bool mir_opt_lastuse(MirModule *m);    /* a plain owned value is dropped after its last use */
bool mir_opt_lastuse_func(MirModule *m, MirFunc *f);
bool mir_opt_range(MirModule *m);      /* checks the value ranges prove redundant are removed */
bool mir_opt_range_func(MirModule *m, MirFunc *f);
bool mir_opt_simplify(MirModule *m);  /* folding, identities, block cleanup, value numbering, dead code */
bool mir_opt_simplify_func(MirModule *m, MirFunc *f);
bool mir_opt_simplify_phis(MirModule *m); /* only trivial block-parameter elimination */
bool mir_opt_sortgen(MirModule *m);    /* sorts by a known comparator run as generated code */
bool mir_opt_viewfast(MirModule *m);   /* `String.view`, `String.slice` and `Bytes.view` run inline for a range inside the text, else call the runtime */
bool mir_opt_strfast(MirModule *m);    /* the common cases of the string runtime functions run inline */
bool mir_opt_bytesfast(MirModule *m);  /* a fixed-width `Bytes` read and a byte search run inline in the common case */
bool mir_opt_probe(MirModule *m);      /* a map or set lookup of a fixed layout runs as a probe loop in the caller */
bool mir_opt_appendfast(MirModule *m); /* `string_append` on an owned string with room runs inline */

/* Direct calls, closures called through a known `closure.new`, and unreferenced functions; the
 * `_small` form is the unoptimised build's (tiny loop-free callees only). */
bool mir_opt_inline(MirModule *m);
bool mir_opt_inline_small(MirModule *m);

/* ---- the pipeline (opt_pipeline.c) ---- */

typedef enum MirOptLevel { MIR_OPT_NONE, MIR_OPT_SPEED } MirOptLevel;

/* Runs the passes for `level`. With `verify` the module is re-verified after every pass; the first
 * failure stops the run, writes the pass name, the errors and the module to `error` and returns
 * false. */
MS_NODISCARD bool mir_optimize(MirModule *m, MirOptLevel level, bool verify, MsBuf *error);

#endif
