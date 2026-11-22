/* driver/checked_input.h: the checked half of `ms build`, `ms run` and `ms test`: load and check the input, require
 * the entry the command needs, and report what is wrong as `ms check` does. Port of `compile_target` in
 * crates/ms-cli/src/engine/mod.rs. */
#ifndef MS_DRIVER_CHECKED_INPUT_H
#define MS_DRIVER_CHECKED_INPUT_H

#include "base/arena.h"
#include "compiler/check/program.h"
#include "compiler/project/project.h"
#include "driver/findings.h"

typedef enum MsInputTarget {
  MS_INPUT_PROGRAM, /* an executable: it needs an entry `main` */
  MS_INPUT_TESTS,   /* the test executable: the project's test files too, and no entry */
  MS_INPUT_ANALYSIS /* a program or library read, not built: no entry needed (inspect, diagram, review) */
} MsInputTarget;

typedef struct MsCheckedInput {
  MsNames names;
  MsGraph graph;
  MsCheckProgram program;
  FindingList findings; /* empty when the input compiles */
  uint32_t entry;       /* the program module that holds `main` */
  bool checked;         /* `program` is initialised */
} MsCheckedInput;

/* Reports an entry `main` the language cannot run; with `declared_only`, only when the entry declares one. */
void ms_require_main(MsArena *arena, const MsCheckProgram *program, uint32_t entry, bool declared_only,
                     FindingList *findings);

/* The module of `graph` that is the entry. */
uint32_t ms_entry_module(const MsCheckProgram *program, const MsGraph *graph);

/* Loads and checks `filename` for an executable. True when it can be lowered; false leaves the diagnostics in
 * `findings`. Texts live in `arena`; `ms_checked_input_free` releases the rest. */
MS_NODISCARD bool ms_checked_input_load(MsArena *arena, MsCheckedInput *checked, MsSpan filename, MsInputTarget target);

/* The same, with extra loader options (`project_sources`, an unsaved-contents `overlay`). */
MS_NODISCARD bool ms_checked_input_load_with(MsArena *arena, MsCheckedInput *checked, MsSpan filename, MsInputTarget target,
                                             const MsLoadOptions *extra);

/* The names of the tests of the checked program, `file::name`, in the order `lower_tests` numbers them: user modules in
 * program order, then declaration order. With `benches` the bench blocks are named instead of the tests. */
void ms_checked_input_test_names(MsArena *arena, const MsCheckedInput *checked, bool benches, MsSpanList *names);

/* The terminal report of the failure, with the count line, on stderr. Returns the status 1. */
int ms_checked_input_report(const MsCheckedInput *checked);

/* The same failure as the versioned `{format, diagnostics}` document on stdout, for `--json`. Returns the status 1. */
/* The diagnostics as the entries of a `diagnostics` array, joined by `,\n` (empty for none). */
MsSpan ms_checked_input_diagnostics_json(MsArena *arena, const MsCheckedInput *checked);

int ms_checked_input_report_json(const MsCheckedInput *checked);

void ms_checked_input_free(MsCheckedInput *checked);

#endif
