/* A public declaration's signature must not name a private type of its own module. */
#include "compiler/check/exports.h"
#include "compiler/check/types.h"

#define MAX_SEEN 64

typedef struct Walk {
  MsCheckProgram *program;
  uint32_t module;
  MsPos pos;
  MsTy seen[MAX_SEEN];
  size_t seen_count;
} Walk;

static void exposes(Walk *walk, MsTy ty) {
  const MsTyTable *types = &walk->program->types;
  if (ty == MS_TY_NONE) {
    return;
  }
  for (size_t index = 0; index < walk->seen_count; index++) {
    if (walk->seen[index] == ty) {
      return;
    }
  }
  if (walk->seen_count == MAX_SEEN) {
    return;
  }
  walk->seen[walk->seen_count++] = ty;
  const MsTyKind kind = ms_ty_kind(types, ty);
  const uint32_t def_index = ms_ty_row(types, ty)->def;
  if (def_index != 0 && (kind == MS_TY_TYPE || kind == MS_TY_ALTERNATIVE || kind == MS_TY_CONTRACT)) {
    const MsSymbol *symbol = &walk->program->symbols.ptr[ms_defs_get(&walk->program->defs, def_index)->symbol];
    if (symbol->module == walk->module && !symbol->exported) {
      MsStrBuild text = ms_strbuild_new();
      ms_strbuild_append_text(&text, "public signature exposes private type ");
      ms_strbuild_append(&text, ms_names_span(walk->program->names, symbol->name));
      ms_strbuild_append_text(&text, "; add 'export' to its declaration or keep the function private");
      ms_check_report(walk->program, walk->module, walk->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
    }
  }
  for (size_t index = 0; index < ms_ty_arg_count(types, ty); index++) {
    exposes(walk, ms_ty_args(types, ty)[index]);
  }
  for (size_t index = 0; index < ms_ty_param_count(types, ty); index++) {
    exposes(walk, ms_ty_params(types, ty)[index].ty);
  }
  if (ms_ty_kind(types, ty) == MS_TY_FUNCTION) {
    exposes(walk, ms_ty_result(types, ty));
  }
}

/* One written type is its own site: the walk starts again for each. */
static void site(MsCheckProgram *program, uint32_t module, MsPos pos, MsTy ty) {
  Walk walk = {.program = program, .module = module, .pos = pos};
  exposes(&walk, ty);
}

static void fields(MsCheckProgram *program, uint32_t module, MsPos pos, const MsTyParamList *list) {
  for (size_t index = 0; index < list->len; index++) {
    site(program, module, pos, list->ptr[index].ty);
  }
}

void ms_check_exports(MsCheckProgram *program, uint32_t module) {
  for (MsSymbolId id = 1; id < program->symbols.len; id++) {
    const MsSymbol *symbol = &program->symbols.ptr[id];
    if (symbol->module != module || !symbol->exported || symbol->decl == NULL || symbol->ty == MS_TY_NONE) {
      continue;
    }
    const MsPos pos = symbol->decl->pos;
    if (symbol->decl->kind == MS_D_FN || symbol->decl->kind == MS_D_ALIAS) {
      site(program, module, pos, symbol->ty);
    } else if (symbol->def != 0) {
      const MsDef *def = ms_defs_get(&program->defs, symbol->def);
      fields(program, module, pos, &def->fields);
      for (size_t index = 0; index < def->cases.len; index++) {
        fields(program, module, pos, &def->cases.ptr[index].fields);
      }
      for (size_t index = 0; index < def->operations.len; index++) {
        site(program, module, pos, def->operations.ptr[index].ty);
      }
    }
  }
}
