/* compiler/check/import_errors.c: the diagnostics of an import that names nothing usable, and of a redundant
 * prelude import.
 *
 * An import binds to symbol 0 when its module is unknown or does not export the name; this pass runs after
 * every import is bound and explains each such import: an unknown standard module (with a rename, a
 * near-miss path, or the module that exports the name), a name the module lacks or keeps private, and a
 * namespace-style import. An import of a prelude declaration is redundant and carries an edit that removes it. */
#include "abi/prelude.h"
#include "compiler/check/import_fix.h"
#include "compiler/check/std_cache.h"
#include "compiler/check/program.h"
#include "compiler/check/suggest.h"
#include "compiler/syntax/parse.h"

/* The public bundled modules, by name below `@std/`, in sorted order. */
static void std_module_names(MsSpanList *out) {
  size_t count = 0;
  const MsStdSource *sources = ms_std_sources(&count);
  for (size_t index = 0; index < count; index++) {
    if (!ms_span_starts_with(sources[index].name, ms_span_of_text("internal/"))) {
      ms_span_list_push(out, sources[index].name);
    }
  }
}

static MsSpan trim_suffix(MsSpan text, const char *suffix) {
  const MsSpan tail = ms_span_of_text(suffix);
  return ms_span_ends_with(text, tail) ? ms_span_of(text.ptr, text.len - tail.len) : text;
}

static MsSpan after_last_slash(MsSpan text) {
  size_t start = 0;
  for (size_t index = 0; index < text.len; index++) {
    start = text.ptr[index] == '/' ? index + 1 : start;
  }
  return ms_span_of(text.ptr + start, text.len - start);
}

/* The module name without its package folder and extension: `net/http.ms` is `http`. */
static MsSpan module_stem(MsSpan name) {
  static const char *const PACKAGES[] = {"collections/", "concurrency/", "data/", "io/", "math/", "net/", "os/"};
  const MsSpan path = trim_suffix(name, ".ms");
  if (ms_span_is_text(path, "test/test") || ms_span_is_text(path, "test/bench")) {
    return after_last_slash(path);
  }
  for (size_t index = 0; index < MS_COUNT_OF(PACKAGES); index++) {
    if (ms_span_starts_with(path, ms_span_of_text(PACKAGES[index]))) {
      const size_t skip = ms_span_of_text(PACKAGES[index]).len;
      return ms_span_of(path.ptr + skip, path.len - skip);
    }
  }
  return path;
}

/* Whether the bundled module `module` (a name below `@std/`) exports a declaration called `name`. */
static bool std_exports(MsCheckProgram *program, MsSpan module, MsName name) {
  MsStdSource source = {0};
  MsModule parsed = {0};
  const MsModule *tree = NULL;
  if (!ms_std_source_find(module, &source)) {
    return false;
  }
  if (program->std_cache != NULL) { /* the parsed bundled modules are shared: no parse per suggestion */
    MsStrBuild file = ms_strbuild_new();
    ms_strbuild_append_text(&file, "@std/");
    ms_strbuild_append(&file, module);
    tree = ms_std_cache_tree(program->std_cache, ms_names_intern(program->names, ms_strbuild_span(&file)));
    ms_strbuild_free(&file);
  }
  MsDiag diag = {0};
  if (tree == NULL) {
    if (!ms_parse(&program->arena, program->names, source.text, &parsed, &diag)) {
      return false;
    }
    tree = &parsed;
  }
  for (uint32_t index = 0; index < tree->ndecls; index++) {
    MsName declared = 0;
    if (tree->decls[index]->is_exported && ms_check_declared_name(tree->decls[index], &declared) &&
        declared == name) {
      return true;
    }
  }
  return false;
}

/* The first bundled module that exports `name`, unless the name is a prelude declaration. */
static bool exported_elsewhere(MsCheckProgram *program, MsSpan name, const MsSpanList *modules, MsSpan *found) {
  if (ms_is_prelude_type(name)) {
    return false;
  }
  const MsName interned = ms_names_intern(program->names, name);
  for (size_t index = 0; index < modules->len; index++) {
    if (std_exports(program, modules->ptr[index], interned)) {
      *found = modules->ptr[index];
      return true;
    }
  }
  return false;
}

static void append_statement(MsStrBuild *text, MsSpan name, MsSpan module) {
  ms_strbuild_append_text(text, "import ");
  ms_strbuild_append(text, name);
  ms_strbuild_append_text(text, " from \"@std/");
  ms_strbuild_append(text, module);
  ms_strbuild_append_text(text, "\"");
}

/* The module name that replaces a renamed standard module, or false. */
static bool renamed_module(MsSpan path, MsSpan *replacement) {
  if (ms_span_is_text(path, "@std/concurrency/flow.ms")) {
    *replacement = ms_span_of_text("@std/concurrency/resilience.ms");
    return true;
  }
  return false;
}

typedef struct ImportView {
  MsCheckProgram *program;
  uint32_t module;
  const MsImport *import;
  MsSpan name; /* the imported name */
  MsSpan path; /* the module path as written */
} ImportView;

/* The suggestion for a module path that no bundled module has: a path with the extension, the same file under
 * another folder, or the closest spelling. Appends nothing when there is none. */
static bool suggest_module(const ImportView *view, const MsSpanList *modules, MsSpan *chosen) {
  MsSpan written = {0};
  (void)ms_check_std_path(view->path, &written);
  MsSpanList stems = {0};
  for (size_t index = 0; index < modules->len; index++) {
    ms_span_list_push(&stems, module_stem(modules->ptr[index]));
  }
  MsSpan stem = {0};
  bool found = ms_suggest_closest(module_stem(written), &stems, &stem);
  const MsSpan base = after_last_slash(written);
  *chosen = (MsSpan){0};
  for (size_t index = 0; index < modules->len && !found; index++) {
    if (ms_span_equal(after_last_slash(modules->ptr[index]), base)) {
      *chosen = modules->ptr[index];
      found = true;
    }
  }
  for (size_t index = 0; index < modules->len && chosen->len == 0; index++) {
    if (ms_span_equal(module_stem(modules->ptr[index]), stem)) {
      *chosen = modules->ptr[index];
    }
  }
  ms_span_list_free(&stems);
  return found;
}

/* Whether a bundled module is called `path` plus the extension. */
static bool std_has_module_with_extension(const MsSpanList *modules, MsSpan path) {
  for (size_t index = 0; index < modules->len; index++) {
    const MsSpan name = modules->ptr[index];
    if (name.len == path.len + 3 && ms_span_starts_with(name, path) && ms_span_ends_with(name, ms_span_of_text(".ms"))) {
      return true;
    }
  }
  return false;
}

/* The explanation of an import of a bundled module that does not exist. */
static MsString unknown_module_message(const ImportView *view) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "unknown standard module ");
  ms_strbuild_append(&text, view->path);
  MsSpan replacement = {0};
  MsSpan written = {0};
  (void)ms_check_std_path(view->path, &written);
  MsSpanList modules = {0};
  std_module_names(&modules);
  MsSpan chosen = {0};
  if (renamed_module(view->path, &replacement)) {
    ms_strbuild_append_text(&text, "; it was renamed: import '");
    ms_strbuild_append(&text, replacement);
    ms_strbuild_append_text(&text, "'");
  } else if (std_has_module_with_extension(&modules, written)) {
    ms_strbuild_append_text(&text, "; did you mean '");
    ms_strbuild_append(&text, view->path);
    ms_strbuild_append_text(&text, ".ms'? Import paths end in .ms");
  } else {
    const bool suggested = suggest_module(view, &modules, &chosen);
    MsSpan elsewhere = {0};
    const MsName name = ms_names_intern(view->program->names, view->name);
    const bool suggestion_exports = suggested && std_exports(view->program, chosen, name);
    if (!suggestion_exports && exported_elsewhere(view->program, view->name, &modules, &elsewhere)) {
      ms_strbuild_append_text(&text, "; ");
      ms_strbuild_append(&text, view->name);
      ms_strbuild_append_text(&text, " is exported by another standard module, so write: ");
      append_statement(&text, view->name, elsewhere);
    } else if (suggested) {
      ms_strbuild_append_text(&text, "; did you mean '@std/");
      ms_strbuild_append(&text, chosen);
      ms_strbuild_append_text(&text, "'?");
    }
  }
  ms_span_list_free(&modules);
  return ms_strbuild_finish(&text);
}

/* The exported names of `target`; sets *private_name when `name` is declared there without `export`. */
static void module_exports(const MsCheckProgram *program, uint32_t target, MsName name, MsSpanList *exports,
                           bool *private_name) {
  for (MsSymbolId id = 1; id < program->symbols.len; id++) {
    const MsSymbol *symbol = &program->symbols.ptr[id];
    if (symbol->module != target || symbol->decl == NULL) {
      continue;
    }
    if (symbol->exported) {
      ms_span_list_push(exports, ms_names_span(program->names, symbol->name));
    } else if (symbol->name == name) {
      *private_name = true;
    }
  }
}

static void append_message_head(MsStrBuild *text, MsSpan name) {
  ms_strbuild_append_text(text, "module does not export ");
  ms_strbuild_append(text, name);
}

/* The explanation of a name that module `target` does not export. */
static MsString export_message(const ImportView *view, uint32_t target) {
  MsStrBuild text = ms_strbuild_new();
  append_message_head(&text, view->name);
  MsSpanList exports = {0};
  bool private_name = false;
  module_exports(view->program, target, view->import->name, &exports, &private_name);
  MsSpan written = {0};
  private_name = private_name && !ms_check_std_path(view->path, &written); /* a standard module's private names are not seen */
  MsSpanList modules = {0};
  std_module_names(&modules);
  MsSpan elsewhere = {0};
  const MsSpan stem = trim_suffix(after_last_slash(view->path), ".ms");
  if (private_name) {
    ms_strbuild_append_text(&text, "; it is declared in ");
    ms_strbuild_append(&text, view->path);
    ms_strbuild_append_text(&text, " but not exported, so write 'export' before its declaration");
  } else if (ms_span_equal(stem, view->name) && exports.len != 0) {
    ms_strbuild_append_text(&text, "; ");
    ms_strbuild_append(&text, view->path);
    ms_strbuild_append_text(&text, " is that module, and namespace imports are unsupported, so import what it exports by name: ");
    ms_suggest_list(&text, &exports, 12);
  } else if (!ms_suggest_did_you_mean(&text, view->name, &exports)) {
    if (exported_elsewhere(view->program, view->name, &modules, &elsewhere)) {
      ms_strbuild_append_text(&text, "; another standard module exports it, so replace this import with: ");
      append_statement(&text, view->name, elsewhere);
    } else if (exports.len == 0) {
      ms_strbuild_append_text(&text, "; ");
      ms_strbuild_append(&text, view->path);
      ms_strbuild_append_text(&text, " exports nothing; namespace imports are unsupported, so import individual exported declarations");
    } else {
      ms_strbuild_append_text(&text, "; ");
      ms_strbuild_append(&text, view->path);
      ms_strbuild_append_text(&text, " exports: ");
      ms_suggest_list(&text, &exports, 12);
      ms_strbuild_append_text(&text, "; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from \"");
      ms_strbuild_append(&text, view->path);
      ms_strbuild_append_text(&text, "\"'");
    }
  }
  ms_span_list_free(&exports);
  ms_span_list_free(&modules);
  return ms_strbuild_finish(&text);
}

bool ms_check_is_prelude_declaration(MsSpan file, MsSpan name) {
  const bool prelude_module = ms_span_is_text(file, "@std/core.ms") || ms_span_is_text(file, "@std/collections/collections.ms");
  return prelude_module && ms_is_prelude_type(name);
}

bool ms_check_is_prelude_symbol(const MsCheckProgram *program, const MsSymbol *symbol) {
  return ms_check_is_prelude_declaration(ms_names_span(program->names, program->modules.ptr[symbol->module].id),
                                         ms_names_span(program->names, symbol->name));
}

static MsPos name_end(const MsImport *import, MsSpan name) {
  MsPos end = import->name_pos;
  end.offset += (uint32_t)name.len;
  end.column += (uint32_t)name.len;
  return end;
}

static void report_redundant(const ImportView *view, uint32_t index, MsSpan source) {
  MsCheckProgram *program = view->program;
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "redundant prelude import ");
  ms_strbuild_append(&text, view->name);
  ms_strbuild_append_text(&text, "; remove ");
  ms_strbuild_append(&text, view->name);
  ms_strbuild_append_text(&text, " from this import and use its prelude declaration directly");
  ms_check_report(program, view->module, view->import->name_pos, MS_CHECK_RESOLUTION, ms_strbuild_finish(&text));
  ms_check_attach_end(program, name_end(view->import, view->name));
  MsImportFix fix = {0};
  if (ms_import_fix(&program->arena, program->modules.ptr[view->module].tree, index, source, &fix)) {
    ms_check_attach_fix(program, fix.pos, fix.end, fix.text);
  }
}

/* The module an unresolved import names, when it exists (a standard module that is bundled, or a local module). */
static bool import_target(const ImportView *view, uint32_t index, uint32_t *target) {
  const MsModuleInfo *info = &view->program->modules.ptr[view->module];
  MsSpan written = {0};
  if (ms_check_std_path(view->path, &written)) {
    const MsName file = ms_names_intern(view->program->names, view->path);
    for (uint32_t at = 0; at < view->program->modules.len; at++) {
      if (view->program->modules.ptr[at].id == file) {
        *target = at;
        return true;
      }
    }
    return false;
  }
  if (info->targets == NULL || info->targets[index] < 0) {
    return false;
  }
  *target = (uint32_t)info->targets[index];
  return true;
}

static MsSpan text_from(MsSpan source, uint32_t offset) {
  return offset <= source.len ? ms_span_of(source.ptr + offset, source.len - offset) : (MsSpan){0};
}

/* The text up to the end of its first line. */
static MsSpan line_of(MsSpan text) {
  size_t end = 0;
  while (end < text.len && text.ptr[end] != '\n') {
    end++;
  }
  return ms_span_of(text.ptr, end);
}

static void report_unresolved(const ImportView *view, uint32_t index, MsSpan source) {
  uint32_t target = 0;
  MsString message = {0};
  MsSpan written = {0};
  const bool standard = ms_check_std_path(view->path, &written);
  if (import_target(view, index, &target)) {
    message = export_message(view, target);
  } else if (standard) {
    message = unknown_module_message(view);
  } else {
    return;
  }
  ms_check_report(view->program, view->module, view->import->name_pos, MS_CHECK_RESOLUTION, message);
  ms_check_attach_end(view->program, name_end(view->import, view->name));
  MsSpan replacement = {0};
  if (renamed_module(view->path, &replacement)) {
    const MsSpan quoted_path = view->path;
    size_t at = 0;
    const MsSpan from = text_from(source, view->import->clause.offset);
    MsStrBuild old = ms_strbuild_new();
    ms_strbuild_append_byte(&old, '"');
    ms_strbuild_append(&old, quoted_path);
    ms_strbuild_append_byte(&old, '"');
    if (ms_span_find(line_of(from), ms_strbuild_span(&old), &at)) {
      MsPos start = view->import->clause;
      start.offset += (uint32_t)at;
      start.column += (uint32_t)at;
      MsPos end = start;
      end.offset += (uint32_t)old.bytes.len;
      end.column += (uint32_t)old.bytes.len;
      MsStrBuild text = ms_strbuild_new();
      ms_strbuild_printf(&text, "\"%.*s\"", (int)replacement.len, (const char *)replacement.ptr);
      ms_check_attach_fix(view->program, start, end, ms_strbuild_finish(&text));
    }
    ms_strbuild_free(&old);
  }
}

void ms_check_report_imports(MsCheckProgram *program, uint32_t module, MsSpan source) {
  const MsModule *tree = program->modules.ptr[module].tree;
  for (uint32_t index = 0; index < tree->nimports; index++) {
    const MsImport *import = &tree->imports[index];
    const ImportView view = {.program = program, .module = module, .import = import,
                             .name = ms_names_span(program->names, import->name), .path = import->path};
    const MsSymbolId *found = ms_scope_get(&program->modules.ptr[module].imports, import->name);
    if (found == NULL) {
      continue;
    }
    if (*found == 0) {
      report_unresolved(&view, index, source);
    } else if (ms_check_is_prelude_symbol(program, &program->symbols.ptr[*found])) {
      report_redundant(&view, index, source);
    }
  }
}
