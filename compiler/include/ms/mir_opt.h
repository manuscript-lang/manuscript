/* libms MIR optimiser: independent passes over a verified module. Each takes the module, keeps it
 * verifying and returns whether it changed anything, as the Rust passes in crates/ms-mir/src/opt
 * do. The contract (what a pass may move, drop or weaken) is in that crate's `opt/mod.rs` doc and
 * carries over unchanged. */
#ifndef MS_MIR_OPT_H
#define MS_MIR_OPT_H

#include "ms/mir.h"

bool mir_opt_bytetake(MirModule *m); /* a result of a dying value reuses its storage */
bool mir_opt_strfuse(MirModule *m);  /* `s = s + piece` grows `s` in place */

#endif
