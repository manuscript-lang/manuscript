/* libms MIR optimiser: independent passes over a verified module. Each takes the module, keeps it
 * verifying and returns whether it changed anything, as the Rust passes in crates/ms-mir/src/opt
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
bool mir_opt_appendfast(MirModule *m); /* `string_append` on an owned string with room runs inline */

#endif
