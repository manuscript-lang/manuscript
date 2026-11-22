/* driver/checked_input.h: the checked half of `ms build`, `ms run` and `ms test`: load and check the input, require
 * the entry the command needs, and report what is wrong as `ms check` does. Port of `compile_target` in
 * crates/ms-cli/src/engine/mod.rs. */
#ifndef MS_DRIVER_CHECKED_INPUT_H
#define MS_DRIVER_CHECKED_INPUT_H

#include "base/arena.h"
#include "compiler/check/program.h"
#include "driver/findings.h"

typedef enum MsInputTarget {
  MS_INPUT_PROGRAM, /* an executable: it needs an entry `main` */
  MS_INPUT_TESTS    /* the test executable: the project's test files too, and no entry */
} MsInputTarget;

typedef struct MsCheckedInput {
  MsNames names;
  MsGraph graph;
  MsCheckProgram program;
  FindingList findings; /* empty when the input compiles */
  uint32_t entry;       /* the program module that holds `main` */
  bool checked;         /* `program` is initialised */
} MsCheckedInput;

/* Loads and checks `filename` for an executable. True when it can be lowered; false leaves the diagnostics in
 * `findings`. Texts live in `arena`; `ms_checked_input_free` releases the rest. */
MS_NODISCARD bool ms_checked_input_load(MsArena *arena, MsCheckedInput *checked, MsSpan filename, MsInputTarget target);

/* The names of the tests of the checked program, `file::name`, in the order `lower_tests` numbers them: user modules in
 * program order, then declaration order; bench blocks are left out. */
void ms_checked_input_test_names(MsArena *arena, const MsCheckedInput *checked, MsSpanList *names);

/* The terminal report of the failure, with the count line, on stderr. Returns the status 1. */
int ms_checked_input_report(const MsCheckedInput *checked);

void ms_checked_input_free(MsCheckedInput *checked);

#endif
