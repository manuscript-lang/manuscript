/* compiler/check/imports.c: loading the bundled standard modules a program imports, and binding imports.
 *
 * The standard modules a program reaches are parsed once, appended after the graph's modules and declared
 * like any other module. An import of `@std/<path>` names the module `<path>` of the bundled sources; a local
 * import names the graph module the loader resolved. An import binds to the exported symbol of that name; an
 * import that does not resolve binds to symbol 0 so later passes do not report it a second time. */
#include "compiler/check/program.h"
#include "compiler/syntax/parse.h"

bool ms_check_std_path(MsSpan path, MsSpan *name) {
  return ms_span_starts_with(path, ms_span_of_text("@std/")) && ms_span_slice(path, 5, path.len, name);
}

/* The index of the module with logical path `path`, or false. */
static bool find_module(const MsCheckProgram *program, MsName file, uint32_t *out) {
  for (uint32_t index = 0; index < program->modules.len; index++) {
    if (program->modules.ptr[index].file == file) {
      *out = index;
      return true;
    }
  }
  return false;
}

/* Parses and adds the bundled module `path` unless it is already loaded; false when there is no such module. */
static bool load_std_module(MsCheckProgram *program, MsSpan path, uint32_t *out) {
  const MsName file = ms_names_intern(program->names, path);
  if (find_module(program, file, out)) {
    return true;
  }
  MsSpan name = {0};
  MsStdSource source = {0};
  if (!ms_check_std_path(path, &name) || !ms_std_source_find(name, &source)) {
    return false;
  }
  MsModule *tree = MS_ARENA_NEW(&program->arena, MsModule);
  MsDiag diag = {0};
  if (!ms_parse(&program->arena, program->names, source.text, tree, &diag)) {
    return false;
  }
  *out = ms_check_add_module(program, file, tree);
  return true;
}

/* The modules whose types every module sees without an import. */
static const char *const PRELUDE_MODULES[] = {"@std/core.ms", "@std/collections/collections.ms"};

void ms_check_load_std(MsCheckProgram *program) {
  for (size_t index = 0; index < MS_COUNT_OF(PRELUDE_MODULES); index++) {
    uint32_t loaded = 0;
    (void)load_std_module(program, ms_span_of_text(PRELUDE_MODULES[index]), &loaded);
  }
  for (uint32_t module = 0; module < program->modules.len; module++) {
    const MsModule *tree = program->modules.ptr[module].tree;
    for (uint32_t index = 0; index < tree->nimports; index++) {
      MsSpan name = {0};
      uint32_t loaded = 0;
      if (ms_check_std_path(tree->imports[index].path, &name)) {
        (void)load_std_module(program, tree->imports[index].path, &loaded);
      }
    }
  }
}

/* The module an import names, or false when it does not resolve. */
static bool import_target(MsCheckProgram *program, uint32_t module, uint32_t index, uint32_t *target) {
  const MsModuleInfo *info = &program->modules.ptr[module];
  const MsSpan path = info->tree->imports[index].path;
  MsSpan name = {0};
  if (ms_check_std_path(path, &name)) {
    return load_std_module(program, path, target);
  }
  if (info->targets == NULL || info->targets[index] < 0) {
    return false;
  }
  *target = (uint32_t)info->targets[index];
  return true;
}

void ms_check_bind_imports(MsCheckProgram *program, uint32_t module) {
  const MsModule *tree = program->modules.ptr[module].tree;
  for (uint32_t index = 0; index < tree->nimports; index++) {
    const MsImport *import = &tree->imports[index];
    MsSymbolId symbol = 0;
    uint32_t target = 0;
    if (import_target(program, module, index, &target)) {
      const MsSymbolId *found = ms_scope_get(&program->modules.ptr[target].scope, import->name);
      if (found != NULL && program->symbols.ptr[*found].module == target &&
          program->symbols.ptr[*found].exported) {
        symbol = *found;
      }
    }
    ms_scope_put(&program->modules.ptr[module].imports, import->name, symbol);
  }
}
