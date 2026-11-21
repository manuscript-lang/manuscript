/* compiler/emit/emit_func.h: how one function is written as LLVM IR: blocks, edges and phis. */
#ifndef MS_COMPILER_EMIT_EMIT_FUNC_H
#define MS_COMPILER_EMIT_EMIT_FUNC_H

#include "compiler/emit/emit_cx.h"

/* The edges leaving a block in a fixed order: a branch has one, a conditional two, a switch its cases and then
 * its default. */
uint32_t emit_edge_count(const MirTerm *term);
const MirTarget *emit_edge(const MirTerm *term, uint32_t index);
bool emit_edge_repeats(const MirTerm *term, uint32_t index);

/* Writes the terminator of block `from`; false with `cx->why` set when it cannot. */
bool emit_terminator(EmitCx *cx, const MirTerm *term, uint32_t from);
/* The small blocks that carry the repeated edges of `term`. */
void emit_edge_blocks(EmitCx *cx, const MirTerm *term, uint32_t from);
/* The phis of block `block`; `last` is the final piece number of every block. */
void emit_phis(EmitCx *cx, uint32_t block, const uint32_t *last);

/* Writes function `index` of the module; false with `cx->why` set when it cannot. */
bool emit_function(EmitCx *cx, uint32_t index);

#endif
