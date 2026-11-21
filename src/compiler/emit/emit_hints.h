/* compiler/emit/emit_hints.h: facts about whole functions that only speed up LLVM. */
#ifndef MS_COMPILER_EMIT_EMIT_HINTS_H
#define MS_COMPILER_EMIT_EMIT_HINTS_H

#include "compiler/emit/emit_cx.h"

typedef struct EmitHints {
  MsArena arena;
  uint8_t *purity; /* per function: 0 unvisited, 1 on the path (recursion: not pure), 2 pure, 3 not */
  uint32_t *depth; /* per function: 0 unvisited, else 1 + the longest chain of glue below it */
  bool *is_glue;
} EmitHints;

void emit_hints_init(EmitHints *hints, const MirModule *module, const MirGlue *glue);
void emit_hints_free(EmitHints *hints);

/* Whether function `index` is a scalar function whose result depends on its arguments alone: no memory, no
 * fault, no loop, and only such callees, so it always returns. LLVM cannot see that across a unit boundary,
 * and a call of it may then be merged or dropped. */
bool emit_hint_pure(EmitCx *cx, EmitHints *hints, uint32_t index);

/* Whether `index` is glue at the top of a chain of three or more levels of glue. Inlining a chain nests one
 * loop per level and makes the optimizer quadratic in the depth, so such glue stays out of line. */
bool emit_hint_deep_glue(const EmitCx *cx, EmitHints *hints, uint32_t index);

#endif
