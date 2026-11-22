/* compiler/check/imports.c: loading the bundled standard modules a program imports, and binding imports.
 *
 * The standard modules a program reaches are parsed once, appended after the graph's modules and declared
 * like any other module. An import of `@std/<path>` names the module `<path>` of the bundled sources; a local
 * import names the graph module the loader resolved. An import binds to the exported symbol of that name; an
 * import that does not resolve binds to symbol 0 so later passes do not report it a second time. */
#include "base/message.h"
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
  const bool parsed = ms_parse(&program->arena, program->names, source.text, tree, &diag);
  if (!parsed) {
    *tree = (MsModule){0}; /* an empty module keeps the importer's bindings; the parse error is reported below */
  }
  *out = ms_check_add_module(program, file, tree);
  program->modules.ptr[*out].source = source.text;
  if (!parsed) {
    ms_check_report(program, *out, diag.pos, MS_CHECK_RESOLUTION,
                    ms_string_from_span(ms_message_format(&program->arena, "parse: %S (in the bundled standard library)", diag.message, (MsSpan){0})));
  }
  return true;
}

/* The modules whose types every module sees without an import. */
static const char *const PRELUDE_MODULES[] = {"@std/core.ms", "@std/collections/collections.ms", "@std/intrinsics.ms", "@std/collections/ordering.ms"};

/* Whether a module of the program declares a `test` or `bench` block: the test entry then needs the runner. */
static bool has_tests(const MsCheckProgram *program) {
  for (uint32_t module = 0; module < program->modules.len; module++) {
    const MsModule *tree = program->modules.ptr[module].tree;
    for (uint32_t index = 0; index < tree->ndecls; index++) {
      if (tree->decls[index]->kind == MS_D_TEST) {
        return true;
      }
    }
  }
  return false;
}

/* Whether a module of the program declares a `bench` block: the bench runner then needs the bench driver. */
static bool has_bench(const MsCheckProgram *program) {
  for (uint32_t module = 0; module < program->modules.len; module++) {
    const MsModule *tree = program->modules.ptr[module].tree;
    for (uint32_t index = 0; index < tree->ndecls; index++) {
      if (tree->decls[index]->kind == MS_D_TEST && tree->decls[index]->u.test.bench) {
        return true;
      }
    }
  }
  return false;
}

/* Whether a module declaring a `test` also declares `make_fixture`: the fixture contract lives in @std/test/test.ms. */
static bool has_fixture(const MsCheckProgram *program) {
  for (uint32_t module = 0; module < program->modules.len; module++) {
    const MsModule *tree = program->modules.ptr[module].tree;
    for (uint32_t index = 0; index < tree->ndecls; index++) {
      const MsDecl *decl = tree->decls[index];
      if (decl->kind == MS_D_FN && ms_span_is_text(ms_names_span(program->names, decl->u.fn.name), "make_fixture")) {
        return true;
      }
    }
  }
  return false;
}

void ms_check_load_std(MsCheckProgram *program) {
  for (size_t index = 0; index < MS_COUNT_OF(PRELUDE_MODULES); index++) {
    uint32_t loaded = 0;
    (void)load_std_module(program, ms_span_of_text(PRELUDE_MODULES[index]), &loaded);
  }
  if (has_tests(program)) {
    uint32_t loaded = 0;
    (void)load_std_module(program, ms_span_of_text("@std/internal/test_runner.ms"), &loaded);
    if (has_bench(program)) {
      (void)load_std_module(program, ms_span_of_text("@std/test/bench.ms"), &loaded);
    }
    if (has_fixture(program)) {
      (void)load_std_module(program, ms_span_of_text("@std/test/test.ms"), &loaded);
    }
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
