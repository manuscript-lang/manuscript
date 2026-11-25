/* compiler/mir/mir_expand.h: the two expansion passes. Not part of the layer's interface beyond what
 * mir_pipeline.h exposes. */
#ifndef MS_COMPILER_MIR_MIR_EXPAND_H
#define MS_COMPILER_MIR_MIR_EXPAND_H

#include "compiler/mir/mir.h"

/* Safety checks and list growth as explicit MIR. With `checks` off the branches are left out. Returns whether
 * any function changed. */
bool mir_expand(MirModule *module, bool checks);

bool mir_expand_owned(MirModule *module);

#endif
