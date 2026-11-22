/* compiler/check/std_exports.c: which bundled standard module exports a name (see std_exports.h). */
#include "compiler/check/std_exports.h"

#include "compiler/syntax/parse.h"

static bool declared_export(const MsDecl *decl, MsSpan name, const MsNames *names) {
  MsName declared = MS_NAME_EMPTY;
  switch ((MsDeclKind)decl->kind) {
  case MS_D_FN:
    declared = decl->u.fn.name;
    break;
  case MS_D_CONST:
    declared = decl->u.konst.name;
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
  return decl->is_exported && ms_span_equal(ms_names_span(names, declared), name);
}

static bool exports_name(MsCheckProgram *program, MsStdSource source, MsSpan name) {
  MsArena arena = ms_arena_new();
  MsModule tree = {0};
  MsDiag diag = {0};
  bool found = false;
  if (ms_parse(&arena, program->names, source.text, &tree, &diag)) {
    for (uint32_t index = 0; index < tree.ndecls && !found; index++) {
      found = declared_export(tree.decls[index], name, program->names);
    }
  }
  ms_arena_free(&arena);
  return found;
}

bool ms_std_exporter(MsCheckProgram *program, MsSpan name, MsStrBuild *out) {
  size_t count = 0;
  const MsStdSource *sources = ms_std_sources(&count);
  for (size_t index = 0; index < count; index++) {
    if (ms_span_starts_with(sources[index].name, ms_span_of_text("internal/"))) {
      continue;
    }
    if (exports_name(program, sources[index], name)) {
      ms_strbuild_append_text(out, "@std/");
      ms_strbuild_append(out, sources[index].name);
      return true;
    }
  }
  return false;
}
