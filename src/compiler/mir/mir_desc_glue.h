/* compiler/mir/mir_desc_glue.h: the equality and hash functions of aggregate descriptors (mir_desc_glue.c). */
#ifndef MS_COMPILER_MIR_MIR_DESC_GLUE_H
#define MS_COMPILER_MIR_MIR_DESC_GLUE_H

#include "compiler/mir/mir.h"

/* Adds `MirModule.desc_glue` for every type a `typedesc` names whose descriptor has no equality of its own. */
void mir_desc_glue(MirModule *module);

#endif
