/* Driver: the compile phases `ms-c` runs, in order, and what is implemented.
 *
 * Every phase has a stub that reports "not implemented"; a layer owner replaces the stub
 * in the same PR that lands the layer. The pass counts of `conform-c` then move. */
#ifndef MS_CLI_PHASES_H
#define MS_CLI_PHASES_H

#include <stdbool.h>
#include <stddef.h>

typedef struct MsPhase {
  const char *name;   /* Borrowed static string. */
  const char *layer;  /* Owner layer, e.g. "L2 syntax". */
  bool (*run)(void);  /* True when the phase ran; false when it is not implemented. */
} MsPhase;

/* The phases in pipeline order. */
const MsPhase *ms_phases(size_t *count);

#endif
