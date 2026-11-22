/* driver/compile_front.h: the front half of `ms build`, `ms run` and `ms test`: load and check the input, require
 * the entry the command needs, and report what is wrong as `ms check` does. Port of `compile_target` in
 * crates/ms-cli/src/engine/mod.rs. */
#ifndef MS_DRIVER_COMPILE_FRONT_H
#define MS_DRIVER_COMPILE_FRONT_H

#include "base/arena.h"
#include "compiler/check/program.h"
#include "driver/findings.h"

typedef struct MsFront {
  MsNames names;
  MsGraph graph;
  MsCheckProgram program;
  FindingList findings; /* empty when the input compiles */
  uint32_t entry;       /* the program module that holds `main` */
  bool checked;         /* `program` is initialised */
} MsFront;

/* Loads and checks `filename` for an executable. True when it can be lowered; false leaves the diagnostics in
 * `findings`. Texts live in `arena`; `ms_front_free` releases the rest. */
MS_NODISCARD bool ms_front_compile(MsArena *arena, MsFront *front, MsSpan filename);

/* The terminal report of the failure, with the count line, on stderr. Returns the status 1. */
int ms_front_report(const MsFront *front);

void ms_front_free(MsFront *front);

#endif
