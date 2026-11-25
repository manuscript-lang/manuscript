/* compiler/own/places.c: places, a binding and a path of projections below it. */
#include "compiler/own/places.h"

MsPlace ms_place_local(uint32_t root) {
  return (MsPlace){.root = root};
}

MsPlace ms_place_then(MsArena *arena, MsPlace place, MsStep step) {
  MsStep *steps = MS_ARENA_NEW_ARRAY(arena, MsStep, (size_t)place.count + 1);
  for (uint32_t index = 0; index < place.count; index++) {
    steps[index] = place.steps[index];
  }
  steps[place.count] = step;
  return (MsPlace){.root = place.root, .steps = steps, .count = place.count + 1};
}

static bool steps_may_alias(const MsStep *a, const MsStep *b) {
  if (a->kind == MS_STEP_INDEX && b->kind == MS_STEP_INDEX) {
    return a->index == b->index;
  }
  if (a->kind == MS_STEP_FIELD && b->kind == MS_STEP_FIELD) {
    return a->name == b->name;
  }
  return a->kind != MS_STEP_FIELD && b->kind != MS_STEP_FIELD;
}

bool ms_place_overlaps(const MsPlace *a, const MsPlace *b) {
  if (a->root != b->root) {
    return false;
  }
  const uint32_t shared = a->count < b->count ? a->count : b->count;
  for (uint32_t index = 0; index < shared; index++) {
    if (!steps_may_alias(&a->steps[index], &b->steps[index])) {
      return false;
    }
  }
  return true;
}
