/* The optimiser's passes, one per file. Each returns whether it changed the module (or function). */
#ifndef MS_COMPILER_OPT_OPT_PASS_H
#define MS_COMPILER_OPT_OPT_PASS_H

#include "compiler/opt/opt_util.h"

bool opt_unwind_sites(MirModule *m); /* the `unwinding` test after a call that cannot park is dropped */
bool opt_unwind_pairs(MirModule *m);  /* a `pause` right before a `resume` is dropped: the exit closes nothing */
bool opt_unwind_thread(MirModule *m); /* an edge that knows the `unwinding` byte skips its test */
bool opt_bytetake(MirModule *m);  /* a result of a dying value reuses its storage */
bool opt_strfuse(MirModule *m);   /* `s = s + piece` grows `s` in place */
bool opt_loopslot(MirModule *m);  /* a loop-carried owned value lives in one slot */
bool opt_fuse(MirModule *m);      /* a loop that builds a temporary list runs inside the loop that reads it */
bool opt_optparam(MirModule *m);  /* an optional scalar block parameter becomes flag and value */
bool opt_optparam_func(MirModule *m, MirFunc *f);
bool opt_ifconv(MirModule *m);    /* small pure diamonds become `select` */
bool opt_ifconv_func(MirModule *m, MirFunc *f);
bool opt_twins(MirModule *m);     /* blocks that run the same operations merge, selecting what differs */
bool opt_twins_func(MirModule *m, MirFunc *f);
bool opt_thread(MirModule *m);    /* a predecessor that knows a join's branch gets its own copy of the join and the chosen successor */
bool opt_thread_func(MirModule *m, MirFunc *f);
bool opt_thread(MirModule *m);    /* a predecessor that knows a join's branch gets its own copy of the join and the chosen successor */
bool opt_thread_func(MirModule *m, MirFunc *f);
bool opt_reserve(MirModule *m);   /* a list filled by a counted loop is allocated at its final size */
bool opt_copyelim(MirModule *m);  /* deep copies that only feed reads are removed */
bool opt_copyelim_func(MirModule *m, MirFunc *f);
bool opt_copyelim_takes(MirModule *m); /* fields of a dying type are moved out */
bool opt_lastuse(MirModule *m);   /* a plain owned value is dropped after its last use */
bool opt_lastuse_func(MirModule *m, MirFunc *f);
bool opt_range(MirModule *m);     /* checks the value ranges prove redundant are removed */
bool opt_range_func(MirModule *m, MirFunc *f);
bool opt_simplify(MirModule *m);  /* folding, identities, block cleanup, value numbering, dead code */
bool opt_simplify_func(MirModule *m, MirFunc *f);
bool opt_simplify_phis(MirModule *m); /* only trivial block-parameter elimination */
uint32_t opt_sortgen_drift(MirModule *m, uint32_t g, MirTy elem); /* the generated comparison-sort function for comparator `g` */
bool opt_sortgen(MirModule *m);   /* sorts by a known comparator run as generated code */
bool opt_viewfast(MirModule *m);  /* `String.view`, `String.slice` and `Bytes.view` run inline for a range inside the text */
bool opt_strfast(MirModule *m);   /* the common cases of the string runtime functions run inline */
bool opt_bytesfast(MirModule *m); /* a fixed-width `Bytes` read and a byte search run inline in the common case */
bool opt_splitview(MirModule *m); /* a split read only in place makes no heap list: first piece, or pieces in the frame */
bool opt_probe(MirModule *m);     /* a map or set lookup of a fixed layout runs as a probe loop in the caller */
bool opt_appendfast(MirModule *m);/* `string_append` on an owned string with room runs inline */
bool opt_exit_drops(MirModule *m); /* the plain drops on the entry's return paths run only when `msrt_exit_frees` says so */
bool opt_inline(MirModule *m);

#endif
