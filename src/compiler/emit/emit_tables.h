/* compiler/emit/emit_tables.h: what the fault tables need to know about the emitted functions that the symbols
 * no longer say (see emit_debug.h for how the line places refer to scopes). */
#ifndef MS_COMPILER_EMIT_EMIT_TABLES_H
#define MS_COMPILER_EMIT_EMIT_TABLES_H

#include "base/arena.h"
#include "compiler/mir/mir.h"

typedef struct EmitTableInfo {
  MsSpan *display;   /* per function: the name a trace shows (the name before emit_name_symbols) */
  MirScope *scopes;  /* the module-wide scope list: every function's scopes, then one per function body */
  uint32_t nscopes;
} EmitTableInfo;

/* Reads the module before emit_name_symbols renames its functions. Everything is in `arena`. */
void emit_table_info(MsArena *arena, const MirModule *module, EmitTableInfo *out);

#endif
