/* Shared by the three files of the `simplify` pass: opt_simplify.c (the driver and the small rewrites),
 * opt_simplify_fold.c (folding) and opt_simplify_cfg.c (control flow, value numbering and map probes). */
#ifndef MS_COMPILER_OPT_OPT_SIMPLIFY_H
#define MS_COMPILER_OPT_OPT_SIMPLIFY_H

#include "compiler/opt/opt_pass.h"

/* opt_simplify_mutate.c. */
bool opt_simplify_roundtrips(MirFunc *f);
bool opt_simplify_shields(MirModule *m, MirFunc *f);
bool opt_simplify_put_takes(MirFunc *f);

/* opt_simplify_dead.c. */
bool opt_simplify_dead_owned(MirModule *m, MirFunc *f);

/* opt_simplify_fold.c. */
bool opt_simplify_fold(MirModule *m, MirFunc *f);
bool opt_simplify_phis_func(MirModule *m, MirFunc *f);

/* opt_simplify_cfg.c. Each returns whether it changed the function. */
bool opt_simplify_branches(MirModule *m, MirFunc *f);
bool opt_simplify_cse(MirModule *m, MirFunc *f);
bool opt_simplify_map_probes(MirModule *m, MirFunc *f);
bool opt_simplify_fuse_contains(MirModule *m, MirFunc *f);

#endif
