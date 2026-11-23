/* The MIR optimiser: the passes that rewrite a module before it is emitted, and the pipeline that orders them. */
#ifndef MS_COMPILER_OPT_OPT_H
#define MS_COMPILER_OPT_OPT_H

#include "base/strbuild.h"
#include "compiler/mir/mir.h"

/* Optimises `module` in place with the one pipeline every build type runs. With `verify`, the module is verified
 * once at the end; when that fails, `error` receives what is wrong and the call returns false. */
bool mir_optimize(MirModule *module, bool verify, MsStrBuild *error);

#endif
