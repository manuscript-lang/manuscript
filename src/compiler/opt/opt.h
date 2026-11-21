/* The MIR optimiser: the passes that rewrite a module before it is emitted, and the pipeline that orders them. */
#ifndef MS_COMPILER_OPT_OPT_H
#define MS_COMPILER_OPT_OPT_H

#include "base/strbuild.h"
#include "compiler/mir/mir.h"

typedef enum MirOptLevel {
  MIR_OPT_NONE,  /* only what an unoptimised build needs: small inlining, copy elimination, early drops */
  MIR_OPT_SPEED, /* the full pipeline */
} MirOptLevel;

/* Optimises `module` in place. With `verify`, the module is verified after every step; when one fails, `error`
 * receives what is wrong and the call returns false. */
bool mir_optimize(MirModule *module, MirOptLevel level, bool verify, MsStrBuild *error);

#endif
