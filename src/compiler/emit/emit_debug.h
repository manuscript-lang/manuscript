/* compiler/emit/emit_debug.h: source places for the fault tables. Every instruction gets
 * `!dbg !DILocation(line: <line>, column: <scope>)` in a line-tables-only compile unit, so the assembly `llc`
 * writes has a `.loc file line scope` before each instruction, which the tables step (compiler/link) turns into
 * the line ranges. The column carries the module-wide scope number: 1 to the number of scopes the functions
 * list is an inlined callee of MIR, and above that one number per function body, so a function LLVM inlines
 * keeps its own number. */
#ifndef MS_COMPILER_EMIT_EMIT_DEBUG_H
#define MS_COMPILER_EMIT_EMIT_DEBUG_H

#include "compiler/emit/emit_cx.h"

struct EmitDebug {
  MsStrBuild nodes; /* the numbered metadata lines of the subprograms and locations */
  uint32_t next;    /* the next free metadata number */
  uint32_t subprogram; /* the subprogram of the function being written */
  uint32_t cached;  /* the DILocation node of `cached_line`/`cached_column`, 0 when none */
  uint32_t cached_line, cached_column, cached_scope;
  uint32_t *file_nodes;  /* per module file: its DIFile node, 0 until first used */
  uint32_t *block_nodes; /* per module file: the scope of the current function's lines from it, 0 until used */
  uint32_t nfiles;
  uint32_t basic_types[16]; /* per scalar MirTyKind: its DIBasicType node, 0 until used */
  uint32_t func_file;    /* the module file of the function being written, MIR_NONE when unknown */
};

void emit_debug_init(EmitDebug *debug);
void emit_debug_free(EmitDebug *debug);
/* Starts the subprogram of function `index` and returns its metadata number. */
uint32_t emit_debug_subprogram(EmitCx *cx, uint32_t index);
/* Puts the source place `loc` on the text written to `cx->out` since byte `from`. */
void emit_debug_place(EmitCx *cx, size_t from, MirLoc loc);
/* At the start of the entry block: a `llvm.dbg.value` for each by-value scalar parameter that has a source name. */
void emit_debug_params(EmitCx *cx);
/* The metadata that closes the module. */
void emit_debug_finish(const EmitCx *cx, MsSpan source);

#endif
