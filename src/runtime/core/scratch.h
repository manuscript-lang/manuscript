/* runtime/core/scratch.h: a temporary slot, on the stack when it fits and allocated otherwise. */
#ifndef MS_RUNTIME_CORE_SCRATCH_H
#define MS_RUNTIME_CORE_SCRATCH_H

#include "base/alloc.h"

typedef struct MsrtScratch {
  _Alignas(16) uint64_t words[8];
  uint8_t *ptr;
  bool heap;
} MsrtScratch;

static inline void msrt_scratch_open(MsrtScratch *scratch, size_t size) {
  scratch->heap = size > sizeof scratch->words;
  scratch->ptr = scratch->heap ? ms_alloc(size) : (uint8_t *)scratch->words;
}

static inline void msrt_scratch_close(const MsrtScratch *scratch) {
  if (scratch->heap) {
    ms_free(scratch->ptr);
  }
}

#endif
