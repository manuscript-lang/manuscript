/* compiler/own/look_stores.h: reports a look stored where it outlives the value it looks at.
 *
 * A record with a `&` field is tied to its owner, and the owner's block ends when it ends. A look assigned to, or
 * passed to a `move` parameter of a call that changes, a place that is read after that block ends (or on a later round
 * of a loop that declares the owner anew) would read freed memory, so it is rejected. Runs when checking found nothing
 * else. */
#ifndef MS_COMPILER_OWN_LOOK_STORES_H
#define MS_COMPILER_OWN_LOOK_STORES_H

#include "compiler/check/program.h"

void ms_own_look_stores(MsCheckProgram *program);

#endif
