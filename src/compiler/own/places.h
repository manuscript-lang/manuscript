/* compiler/own/places.h: places, a local binding and a path of projections below it.
 *
 * A place names part of a binding's value (`b`, `b.items`, `b.xs[0]`). Two places overlap when they share
 * storage: same root and one path is a prefix of the other, where distinct fields and distinct literal
 * list indexes are disjoint and any other pair of element steps may alias.
 *
 * Ownership: a place's step array is borrowed from the arena it was built in. */
#ifndef MS_COMPILER_OWN_PLACES_H
#define MS_COMPILER_OWN_PLACES_H

#include "base/arena.h"
#include "base/intern.h"
#include "base/strbuild.h"

typedef enum MsStepKind {
  MS_STEP_FIELD,   /* a type field: `name` */
  MS_STEP_ELEMENT, /* some element of a collection */
  MS_STEP_INDEX    /* the list element at a literal index: `index` */
} MsStepKind;

typedef struct MsStep {
  MsStepKind kind;
  MsName name;
  uint64_t index;
} MsStep;

typedef struct MsPlace {
  uint32_t root; /* the binding's id */
  const MsStep *steps;
  uint32_t count;
} MsPlace;

MsPlace ms_place_local(uint32_t root);

/* The place followed by one more step, allocated in `arena`. */
MsPlace ms_place_then(MsArena *arena, MsPlace place, MsStep step);

/* Whether the two places can share storage. */
bool ms_place_overlaps(const MsPlace *a, const MsPlace *b);

#endif
