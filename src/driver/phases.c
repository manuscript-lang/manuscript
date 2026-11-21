/* Owns the phase table. Each entry is a stub until its layer lands. */
#include "driver/phases.h"

#include <stdbool.h>

static bool not_implemented(void) { return false; }

static const MsPhase PHASES[] = {
    {"parse", "L2 syntax", not_implemented},
    {"project", "L3 checker", not_implemented},
    {"check", "L3 checker", not_implemented},
    {"own", "L3 checker", not_implemented},
    {"lower", "L4 back end", not_implemented},
    {"mir", "L4 back end", not_implemented},
    {"opt", "L4 back end", not_implemented},
    {"emit", "L4 back end", not_implemented},
    {"link", "L4 back end", not_implemented},
};

const MsPhase *ms_phases(size_t *count) {
  *count = sizeof PHASES / sizeof PHASES[0];
  return PHASES;
}
