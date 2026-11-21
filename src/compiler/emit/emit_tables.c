/* Owns the names and scope list handed to the fault tables (see emit_tables.h). */
#include "compiler/emit/emit_tables.h"

void emit_table_info(MsArena *arena, const MirModule *module, EmitTableInfo *out) {
  uint32_t count = (uint32_t)module->funcs.len;
  uint32_t inlined = 0;
  for (uint32_t index = 0; index < count; index++) {
    inlined += (uint32_t)module->funcs.ptr[index].scopes.len;
  }
  out->nscopes = inlined + count;
  out->display = MS_ARENA_NEW_ARRAY(arena, MsSpan, count);
  out->scopes = MS_ARENA_NEW_ARRAY(arena, MirScope, out->nscopes);
  uint32_t base = 0;
  for (uint32_t index = 0; index < count; index++) {
    const MirFunc *func = &module->funcs.ptr[index];
    out->display[index] = ms_arena_copy(arena, ms_names_span(&module->names, func->name));
    for (uint32_t scope = 0; scope < func->scopes.len; scope++) {
      MirScope entry = func->scopes.ptr[scope];
      /* A parent is a scope number of the function; 0 is the function itself. */
      entry.parent = entry.parent == 0 ? 0 : base + entry.parent;
      out->scopes[base + scope] = entry;
    }
    base += (uint32_t)func->scopes.len;
    out->scopes[inlined + index] = (MirScope){.name = func->name, .file = func->loc.file, .parent = 0, .call_line = 0};
  }
}
