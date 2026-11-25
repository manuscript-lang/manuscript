/* Owns the fault tables: the symbol and line tables the runtime reads to name functions and source lines in a trace
 * (`ms_tables`, built by mir_fault_tables). The library reports each function's code size and the source place of
 * every range of its code; the addresses in the table are relocations against the functions. */
#include "compiler/emit_cl/cl_cx.h"

#include "base/alloc.h"
#include "compiler/mir/mir_tables.h"

bool cl_define_tables(ClModule *mod, const EmitTableInfo *info, ms_cl_data tables_data, MsStrBuild *why) {
  const MirModule *module = mod->module;
  const uint32_t nfuncs = (uint32_t)module->funcs.len;
  if (ms_cl_wait(mod->cl) != 0) {
    ms_strbuild_printf(why, "Cranelift: %s\n", ms_cl_error(mod->cl));
    return false;
  }
  MsArena arena = ms_arena_new();
  MirFuncTable *funcs = MS_ARENA_NEW_ARRAY(&arena, MirFuncTable, nfuncs + 1);
  for (uint32_t index = 0; index < nfuncs; index++) {
    const MirFunc *func = &module->funcs.ptr[index];
    uint64_t offset = 0;
    uint32_t size = 0;
    uint32_t count = 0;
    ms_cl_func_info(mod->cl, mod->funcs[index], &offset, &size);
    const ms_cl_code_range *found = ms_cl_func_ranges(mod->cl, mod->funcs[index], &count);
    MirCodeRange *ranges = MS_ARENA_NEW_ARRAY(&arena, MirCodeRange, (size_t)count + 1);
    for (uint32_t at = 0; at < count; at++) {
      const bool known = found[at].file != UINT32_MAX;
      ranges[at] = (MirCodeRange){.off = found[at].off,
                                  .file = known ? found[at].file : func->loc.file,
                                  .line = known ? found[at].line : func->loc.line,
                                  .scope = known ? found[at].scope : 0};
    }
    funcs[index] = (MirFuncTable){.name = info->display[index], .file = func->loc.file, .line = func->loc.line,
                                  .size = size, .ranges = ranges, .nranges = count};
  }
  MirTables tables;
  mir_fault_tables(&arena, module, funcs, nfuncs, info->scopes, info->nscopes, &tables);
  ms_cl_reloc *relocs = ms_alloc((MIR_TABLE_POINTERS + tables.npcs + 1) * sizeof(ms_cl_reloc));
  uint32_t nrelocs = 0;
  for (uint32_t at = 0; at < MIR_TABLE_POINTERS; at++) {
    relocs[nrelocs++] = (ms_cl_reloc){.offset = (uint32_t)tables.pointers[at].at, .kind = 1, .target = tables_data.id,
                                      .addend = (int64_t)tables.pointers[at].to};
  }
  for (size_t at = 0; at < tables.npcs; at++) {
    relocs[nrelocs++] = (ms_cl_reloc){.offset = (uint32_t)tables.pcs[at].at, .kind = 0,
                                      .target = mod->funcs[tables.pcs[at].func].id, .addend = (int64_t)tables.pcs[at].off};
  }
  ms_cl_define_data(mod->cl, tables_data, tables.blob, (uint32_t)tables.size, 8, relocs, nrelocs);
  ms_free(relocs);
  ms_arena_free(&arena);
  return true;
}
