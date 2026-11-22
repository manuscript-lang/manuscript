/* Owns the effects rule of lint.h: MSL116, a project function reaches an effect no `// ms: allow_effect` line
 * permits. Port of crates/ms-tooling/src/lint/effects.rs. */
#include "base/strbuild.h"
#include "compiler/check/effects_scan.h"
#include "tooling/lint.h"

void ms_lint_effects(MsArena *arena, const MsCheckProgram *program, MsLintFindingList *findings) {
  const MsReach reach = ms_check_effects(program, arena);
  for (uint32_t i = 0; i < reach.violation_count; i++) {
    const MsReachViolation *violation = &reach.violations[i];
    MsStrBuild message = ms_strbuild_new();
    ms_effect_message(&message, violation->path_count > 0 ? violation->path[0] : ms_span_of_text("this function"),
                      violation);
    ms_lint_add(findings, "MSL116", ms_names_span(program->names, violation->file), violation->pos,
                ms_arena_copy(arena, ms_strbuild_span(&message)));
    ms_strbuild_free(&message);
  }
}
