/* compiler/mir/mir_tables.c: the fault tables blob. The layout is the runtime's MsTables: a header of
 * pointers, then the function entries, line entries, the scope of each line, the scope entries and the
 * strings. */
#include "base/strbuild.h"
#include "compiler/mir/mir_tables.h"

enum { TABLE_HEADER = 80, TABLE_SCOPE = 16, TABLE_FUNC = 24, TABLE_LINE = 16, TABLE_ABI_VERSION = 3 };

static void put_u32(uint8_t *blob, size_t at, uint32_t value) {
  for (uint32_t index = 0; index < 4; index++) {
    blob[at + index] = (uint8_t)(value >> (8 * index));
  }
}

static void put_u64(uint8_t *blob, size_t at, uint64_t value) {
  put_u32(blob, at, (uint32_t)value);
  put_u32(blob, at + 4, (uint32_t)(value >> 32));
}

static size_t align8(size_t n) {
  return (n + 7) / 8 * 8;
}

/* The strings the tables name, NUL-terminated and back to back; returns where the text starts. */
static uint32_t intern(MsStrBuild *strings, MsSpan text) {
  const uint32_t at = (uint32_t)ms_strbuild_length(strings);
  ms_strbuild_append(strings, text);
  ms_strbuild_append_byte(strings, 0);
  return at;
}

static uint32_t file_offset(const uint32_t *files, size_t nfiles, uint32_t file) {
  return file < nfiles ? files[file] : UINT32_MAX;
}

typedef struct TableLayout {
  size_t funcs_at, lines_at, line_scopes_at, scopes_at, strings_at;
} TableLayout;

typedef struct TableCx {
  const MirModule *module;
  const uint32_t *files;
  uint8_t *blob;
  TableLayout layout;
} TableCx;

static void put_scopes(const TableCx *cx, const MirScope *scopes, uint32_t nscopes, const uint32_t *names) {
  for (uint32_t index = 0; index < nscopes; index++) {
    const size_t at = cx->layout.scopes_at + (size_t)index * TABLE_SCOPE;
    put_u32(cx->blob, at, names[index]);
    put_u32(cx->blob, at + 4, file_offset(cx->files, cx->module->files.len, scopes[index].file));
    put_u32(cx->blob, at + 8, scopes[index].parent);
    put_u32(cx->blob, at + 12, scopes[index].call_line);
  }
}

/* Writes the entries of every function and its line ranges, listing each stored code address in `out`. */
static void put_functions(const TableCx *cx, const MirFuncTable *funcs, uint32_t nfuncs, const uint32_t *names,
                          MirTables *out) {
  size_t npc = 0;
  size_t line_at = cx->layout.lines_at;
  for (uint32_t index = 0; index < nfuncs; index++) {
    const MirFuncTable *func = &funcs[index];
    const size_t at = cx->layout.funcs_at + (size_t)index * TABLE_FUNC;
    out->pcs[npc++] = (MirTablePc){at, index, 0};
    put_u32(cx->blob, at + 8, func->size);
    put_u32(cx->blob, at + 12, names[index]);
    put_u32(cx->blob, at + 16, file_offset(cx->files, cx->module->files.len, func->file));
    put_u32(cx->blob, at + 20, func->line);
    for (uint32_t range = 0; range < func->nranges; range++) {
      const MirCodeRange *entry = &func->ranges[range];
      out->pcs[npc++] = (MirTablePc){line_at, index, entry->off};
      put_u32(cx->blob, line_at + 8, entry->line);
      put_u32(cx->blob, line_at + 12, file_offset(cx->files, cx->module->files.len, entry->file));
      put_u32(cx->blob, cx->layout.line_scopes_at + (line_at - cx->layout.lines_at) / TABLE_LINE * 4,
              entry->scope);
      line_at += TABLE_LINE;
    }
  }
}

/* The offsets of the files', functions' and scopes' names in the strings block. */
static void intern_names(MsArena *arena, const MirModule *module, const MirFuncTable *funcs, uint32_t nfuncs,
                         const MirScope *scopes, uint32_t nscopes, MsStrBuild *strings, uint32_t **files,
                         uint32_t **names, uint32_t **scope_names) {
  *files = MS_ARENA_NEW_ARRAY(arena, uint32_t, module->files.len);
  *names = MS_ARENA_NEW_ARRAY(arena, uint32_t, nfuncs);
  *scope_names = MS_ARENA_NEW_ARRAY(arena, uint32_t, nscopes);
  for (size_t index = 0; index < module->files.len; index++) {
    (*files)[index] = intern(strings, module->files.ptr[index]);
  }
  for (uint32_t index = 0; index < nfuncs; index++) {
    (*names)[index] = intern(strings, funcs[index].name);
  }
  for (uint32_t index = 0; index < nscopes; index++) {
    (*scope_names)[index] = intern(strings, ms_names_span(&module->names, scopes[index].name));
  }
}

void mir_fault_tables(MsArena *arena, const MirModule *module, const MirFuncTable *funcs, uint32_t nfuncs,
                      const MirScope *scopes, uint32_t nscopes, MirTables *out) {
  MsStrBuild strings = ms_strbuild_new();
  uint32_t *files = NULL, *names = NULL, *scope_names = NULL;
  intern_names(arena, module, funcs, nfuncs, scopes, nscopes, &strings, &files, &names, &scope_names);
  size_t nlines = 0;
  for (uint32_t index = 0; index < nfuncs; index++) {
    nlines += funcs[index].nranges;
  }
  TableLayout layout = {.funcs_at = TABLE_HEADER};
  layout.lines_at = layout.funcs_at + (size_t)nfuncs * TABLE_FUNC;
  layout.line_scopes_at = layout.lines_at + nlines * TABLE_LINE;
  layout.scopes_at = align8(layout.line_scopes_at + nlines * 4);
  layout.strings_at = layout.scopes_at + (size_t)nscopes * TABLE_SCOPE;
  const size_t text = ms_strbuild_length(&strings);
  out->size = layout.strings_at + text;
  out->blob = MS_ARENA_NEW_ARRAY(arena, uint8_t, out->size);
  const TableCx cx = {.module = module, .files = files, .blob = out->blob, .layout = layout};
  put_u32(out->blob, 0, TABLE_ABI_VERSION);
  put_u64(out->blob, 16, nfuncs);
  put_u64(out->blob, 32, nlines);
  put_u64(out->blob, 48, text);
  put_u64(out->blob, 72, nscopes);
  put_scopes(&cx, scopes, nscopes, scope_names);
  if (text > 0) {
    __builtin_memcpy(out->blob + layout.strings_at, ms_strbuild_span(&strings).ptr, text);
  }
  out->npcs = nfuncs + nlines;
  out->pcs = MS_ARENA_NEW_ARRAY(arena, MirTablePc, out->npcs);
  put_functions(&cx, funcs, nfuncs, names, out);
  const MirTablePointer pointers[MIR_TABLE_POINTERS] = {{8, layout.funcs_at},
                                                        {24, layout.lines_at},
                                                        {40, layout.strings_at},
                                                        {56, layout.line_scopes_at},
                                                        {64, layout.scopes_at}};
  __builtin_memcpy(out->pointers, pointers, sizeof pointers);
  ms_strbuild_free(&strings);
}
