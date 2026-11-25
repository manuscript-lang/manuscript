/* compiler/check/std_exports.c: which bundled standard module exports a name (see std_exports.h). */
#include "compiler/check/std_exports.h"

#include <stdatomic.h>

#include "base/intern.h"
#include "base/list.h"
#include "compiler/syntax/parse.h"

/* The exporters of every standard name, built from one parse of each bundled module the first time a name is
 * asked for and kept for the process: a diagnostic for a mistyped name (a language server meets one per keystroke)
 * no longer parses the whole library. `any` and `types` are indexed by the id of a name in `names`; -1 means no
 * module, otherwise the first module in name order. */
MS_LIST_DEFINE(ExportModuleList, export_module_list, int32_t)

typedef struct ExportIndex {
  MsNames names;
  ExportModuleList any, types;
  bool built;
} ExportIndex;

static ExportIndex export_index;
static atomic_flag export_lock = ATOMIC_FLAG_INIT;

static void record_export(MsName name, int32_t module, bool is_type) {
  while (export_index.any.len <= name) {
    export_module_list_push(&export_index.any, -1);
    export_module_list_push(&export_index.types, -1);
  }
  if (export_index.any.ptr[name] < 0) export_index.any.ptr[name] = module;
  if (is_type && export_index.types.ptr[name] < 0) export_index.types.ptr[name] = module;
}

static bool declared_name(const MsDecl *decl, const MsNames *names, MsSpan *name, bool *is_type) {
  MsName declared = MS_NAME_EMPTY;
  *is_type = true;
  switch ((MsDeclKind)decl->kind) {
  case MS_D_FN:
    declared = decl->u.fn.name;
    *is_type = false;
    break;
  case MS_D_CONST:
    declared = decl->u.konst.name;
    *is_type = false;
    break;
  case MS_D_TYPE:
    declared = decl->u.type.name;
    break;
  case MS_D_ENUM:
    declared = decl->u.enumeration.name;
    break;
  case MS_D_ALIAS:
    declared = decl->u.alias.name;
    break;
  case MS_D_INTERFACE:
    declared = decl->u.iface.name;
    break;
  case MS_D_IMPL:
  case MS_D_TEST:
    return false;
  }
  if (!decl->is_exported || declared == MS_NAME_EMPTY) return false;
  *name = ms_names_span(names, declared);
  return true;
}

static void index_module(MsCheckProgram *program, MsStdSource source, int32_t module) {
  MsArena arena = ms_arena_new();
  MsModule tree = {0};
  MsDiag diag = {0};
  if (ms_parse(&arena, program->names, source.text, &tree, &diag)) {
    for (uint32_t index = 0; index < tree.ndecls; index++) {
      MsSpan name;
      bool is_type;
      if (declared_name(tree.decls[index], program->names, &name, &is_type)) {
        record_export(ms_names_intern(&export_index.names, name), module, is_type);
      }
    }
  }
  ms_arena_free(&arena);
}

static void build_index(MsCheckProgram *program, const MsStdSource *sources, size_t count) {
  ms_names_init(&export_index.names);
  for (size_t index = 0; index < count; index++) {
    if (ms_span_starts_with_text(sources[index].name, "internal/")) continue;
    index_module(program, sources[index], (int32_t)index);
  }
  export_index.built = true;
}

bool ms_std_exporter(MsCheckProgram *program, MsSpan name, bool types_only, MsStrBuild *out) {
  size_t count = 0;
  const MsStdSource *sources = ms_std_sources(&count);
  while (atomic_flag_test_and_set_explicit(&export_lock, memory_order_acquire)) {
  }
  if (!export_index.built) build_index(program, sources, count);
  int32_t module = -1;
  MsName id;
  if (ms_names_find(&export_index.names, name, &id) && id < export_index.any.len) {
    module = types_only ? export_index.types.ptr[id] : export_index.any.ptr[id];
  }
  atomic_flag_clear_explicit(&export_lock, memory_order_release);
  if (module < 0) return false;
  ms_strbuild_append_text(out, "@std/");
  ms_strbuild_append(out, sources[module].name);
  return true;
}
