/* compiler/mir/mir_glue_demand.h: the sets of what a module asks glue for. Not part of the layer's
 * interface. */
#ifndef MS_COMPILER_MIR_MIR_GLUE_DEMAND_H
#define MS_COMPILER_MIR_MIR_GLUE_DEMAND_H

#include "compiler/mir/mir_desc.h"
#include "compiler/mir/mir_glue_internal.h"

/* Sets over type ids (drops, clones, slots, blocks) and over function ids (the closures). */
typedef struct GlDemand {
  MirBits drops, clones;
  MirBits slots;  /* the types whose descriptors point at slot drop and copy functions */
  MirBits blocks; /* the data types of interface vtables: payload blocks get drop and clone functions */
  MirBits heap_drops, framed_drops, closure_clones;
} GlDemand;

/* Fills the type sets, all in `arena`. */
void mirgl_demand_types(MsArena *arena, const MirModule *module, GlDemand *demand);

/* Fills the closure sets: the closure functions whose objects the program makes, split by whether the object
 * lives in a stack frame (and so is not freed), and those whose objects get a clone entry. */
void mirgl_demand_closures(MsArena *arena, const MirModule *module, GlDemand *demand);

#endif
