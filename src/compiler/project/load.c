/* compiler/project/load.c: a module and the local modules it imports, parsed into one graph. Port of the
 * `Loader` in crates/ms-driver/src/load.rs for standalone files and local imports. A failure stops the load:
 * the graph then has no modules and one diagnostic. */
#include <errno.h>

#include "base/file.h"
#include "base/path.h"
#include "base/utf8.h"
#include "compiler/project/project_internal.h"
#include "compiler/syntax/parse.h"

MS_LIST_DEFINE(ModuleList, module_list, MsGraphModule)
MS_LIST_DEFINE(GraphDiagList, graph_diag_list, MsGraphDiag)

typedef enum FailureKind {
  FAIL_DIAGNOSTIC, /* a finished diagnostic */
  FAIL_ERROR,      /* a failed system call or rule: it takes the position of the edge that met it */
  FAIL_CYCLE,      /* the same, worded as a cycle */
} FailureKind;

typedef struct Failure {
  FailureKind kind;
  MsGraphDiag diag; /* FAIL_DIAGNOSTIC */
  MsSpan text;      /* FAIL_ERROR: the message; FAIL_CYCLE: the cycle text */
} Failure;

typedef struct Loader {
  MsArena *arena;
  MsNames *names;
  const MsOverlay *overlay;
  MsSpan root;
  ModuleList modules;
  MsSpanList active;  /* canonical paths being loaded, for cycle text */
  MsSpanList loaded;  /* canonical path of modules[i] */
} Loader;

static MsPos start_position(void) {
  return (MsPos){.offset = 0, .line = 1, .column = 1};
}

static MsGraphDiag resolution(MsSpan file, MsPos pos, MsSpan message) {
  return (MsGraphDiag){.file = file, .phase = MS_GRAPH_RESOLUTION, .diag = {.pos = pos, .message = message}};
}

static Failure failure_text(FailureKind kind, MsSpan text) {
  return (Failure){.kind = kind, .text = text};
}

static MsGraphDiag failure_diag(const Failure *failure, MsSpan file, MsPos pos) {
  return failure->kind == FAIL_DIAGNOSTIC ? failure->diag : resolution(file, pos, failure->text);
}

static MsSpan logical_name(Loader *loader, MsSpan canonical) {
  MsStrBuild relative = ms_strbuild_new();
  if (!ms_path_relative(&relative, loader->root, canonical)) {
    ms_strbuild_free(&relative);
    return canonical;
  }
  return ms_project_text(loader->arena, &relative);
}

static Failure cycle_failure(Loader *loader, size_t first, MsSpan canonical) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "cyclic module dependency ");
  for (size_t i = first; i < loader->active.len; i++) {
    ms_strbuild_append(&text, logical_name(loader, loader->active.ptr[i]));
    ms_strbuild_append_text(&text, " -> ");
  }
  ms_strbuild_append(&text, logical_name(loader, canonical));
  ms_strbuild_append_text(&text, "; modules cannot import each other in a loop, so move the shared "
                                 "declarations into a third module that both import");
  return failure_text(FAIL_CYCLE, ms_project_text(loader->arena, &text));
}

static bool find_span(const MsSpanList *list, MsSpan item, size_t *at) {
  for (size_t i = 0; i < list->len; i++) {
    if (ms_span_equal(list->ptr[i], item)) {
      *at = i;
      return true;
    }
  }
  return false;
}

static bool overlay_text(const MsOverlay *overlay, MsSpan path, MsSpan *text) {
  for (size_t i = 0; overlay != NULL && i < overlay->count; i++) {
    if (ms_span_equal(overlay->files[i].path, path)) {
      *text = overlay->files[i].text;
      return true;
    }
  }
  return false;
}

static bool read_source(Loader *loader, MsSpan canonical, MsSpan *text, Failure *failure) {
  if (overlay_text(loader->overlay, canonical, text)) {
    return true;
  }
  MsBytes bytes = {0};
  if (!ms_file_read(canonical, &bytes)) {
    MsProjectError error = {0};
    ms_project_error_path(&error, "open", canonical, errno);
    *failure = failure_text(FAIL_ERROR, ms_project_error_text(loader->arena, &error));
    return false;
  }
  *text = ms_arena_copy(loader->arena, ms_bytes_span(&bytes));
  ms_bytes_free(&bytes);
  return true;
}

static Failure parse_failure(MsSpan file, const MsDiag *diag) {
  Failure failure = {.kind = FAIL_DIAGNOSTIC};
  failure.diag = (MsGraphDiag){.file = file, .phase = MS_GRAPH_PARSE, .diag = *diag};
  return failure;
}

static bool parse_source(Loader *loader, MsSpan file, MsSpan text, MsModule *module, Failure *failure) {
  MsDiag diag = {.pos = start_position()};
  if (!ms_utf8_is_valid(text.ptr, text.len)) {
    diag.message = ms_span_of_text("source must be valid UTF-8; re-save the file with UTF-8 encoding");
    *failure = parse_failure(file, &diag);
    return false;
  }
  if (!ms_parse(loader->arena, loader->names, text, module, &diag)) {
    *failure = parse_failure(file, &diag);
    return false;
  }
  return true;
}

static bool visit(Loader *loader, MsSpan canonical, int32_t *index, Failure *failure);

/* Resolves and loads the module a local import names. */
static bool import_module(Loader *loader, MsSpan importer, MsSpan file, const MsImport *item, int32_t *index,
                          Failure *failure) {
  MsProjectError error = {0};
  MsSpan target = {0};
  if (!ms_project_resolve_import(loader->arena, loader->root, loader->overlay, importer, item->path, &target,
                                 &error)) {
    const MsSpan message = ms_project_explain(loader->arena, &error, item->path);
    failure->kind = FAIL_DIAGNOSTIC;
    failure->diag = resolution(file, item->pos, message);
    return false;
  }
  if (visit(loader, target, index, failure)) {
    return true;
  }
  if (failure->kind != FAIL_DIAGNOSTIC) {
    failure->diag = resolution(file, item->pos, failure->text);
    failure->kind = FAIL_DIAGNOSTIC;
  }
  return false;
}

static bool load_imports(Loader *loader, MsSpan canonical, MsSpan file, const MsModule *module,
                         int32_t *targets, Failure *failure) {
  for (uint32_t i = 0; i < module->nimports; i++) {
    const MsImport *item = &module->imports[i];
    targets[i] = MS_NO_MODULE;
    if (ms_span_starts_with(item->path, ms_span_of_text("@std/"))) {
      continue;
    }
    if (!import_module(loader, canonical, file, item, &targets[i], failure)) {
      return false;
    }
  }
  return true;
}

static bool load(Loader *loader, MsSpan canonical, MsSpan file, int32_t *index, Failure *failure) {
  MsSpan text = {0};
  MsModule module = {0};
  if (!read_source(loader, canonical, &text, failure) || !parse_source(loader, file, text, &module, failure)) {
    return false;
  }
  int32_t *targets = ms_arena_alloc_array(loader->arena, sizeof(int32_t), _Alignof(int32_t),
                                          module.nimports == 0 ? 1 : module.nimports);
  if (!load_imports(loader, canonical, file, &module, targets, failure)) {
    return false;
  }
  *index = (int32_t)loader->modules.len;
  module_list_push(&loader->modules, (MsGraphModule){.name = file,
                                                     .path = canonical,
                                                     .source = text,
                                                     .syntax = module,
                                                     .targets = targets});
  ms_span_list_push(&loader->loaded, canonical);
  return true;
}

/* Loads `canonical` unless it is already loaded; a path still being loaded is a cycle. */
static bool visit(Loader *loader, MsSpan canonical, int32_t *index, Failure *failure) {
  size_t at = 0;
  if (find_span(&loader->active, canonical, &at)) {
    *failure = cycle_failure(loader, at, canonical);
    return false;
  }
  if (find_span(&loader->loaded, canonical, &at)) {
    *index = (int32_t)at;
    return true;
  }
  const MsSpan file = logical_name(loader, canonical);
  ms_span_list_push(&loader->active, canonical);
  const bool ok = load(loader, canonical, file, index, failure);
  loader->active.len--;
  return ok;
}

static void finish(Loader *loader, MsGraph *out) {
  out->count = loader->modules.len;
  out->modules = ms_arena_alloc_array(loader->arena, sizeof(MsGraphModule), _Alignof(MsGraphModule),
                                      loader->modules.len == 0 ? 1 : loader->modules.len);
  for (size_t i = 0; i < loader->modules.len; i++) {
    out->modules[i] = loader->modules.ptr[i];
  }
}

static void fail_graph(MsArena *arena, MsGraph *out, MsGraphDiag diag) {
  out->count = 0;
  out->diagnostic_count = 1;
  out->diagnostics = ms_arena_alloc_array(arena, sizeof(MsGraphDiag), _Alignof(MsGraphDiag), 1);
  out->diagnostics[0] = diag;
}

static void fail_error(MsArena *arena, MsSpan filename, const MsProjectError *error, MsGraph *out) {
  fail_graph(arena, out, resolution(filename, start_position(), ms_project_explain(arena, error, (MsSpan){0})));
}

/* The absolute, cleaned spelling of `filename`. */
static bool absolute_name(MsArena *arena, MsSpan filename, MsSpan *absolute, MsProjectError *error) {
  MsStrBuild joined = ms_strbuild_new();
  if (ms_path_is_absolute(filename)) {
    ms_strbuild_append(&joined, filename);
  } else {
    MsString cwd = ms_string_empty();
    if (!ms_dir_current(&cwd)) {
      ms_strbuild_free(&joined);
      ms_project_error_path(error, "getwd", ms_span_of_text("."), errno);
      return false;
    }
    ms_path_append_joined(&joined, ms_string_span(&cwd), filename);
    ms_string_release(&cwd);
  }
  MsStrBuild cleaned = ms_strbuild_new();
  ms_path_clean(&cleaned, ms_strbuild_span(&joined));
  ms_strbuild_free(&joined);
  *absolute = ms_project_text(arena, &cleaned);
  return true;
}

static bool canonical_root(MsArena *arena, MsSpan absolute, MsSpan *root, MsProjectError *error) {
  MsString real = ms_string_empty();
  const MsSpan directory = ms_path_parent(absolute);
  if (!ms_file_real_path(directory.len == 0 ? ms_span_of_text("/") : directory, &real)) {
    ms_project_error_path(error, "lstat", ms_arena_copy(arena, directory), errno);
    return false;
  }
  *root = ms_arena_copy(arena, ms_string_span(&real));
  ms_string_release(&real);
  return true;
}

void ms_project_load(MsArena *arena, MsNames *names, MsSpan filename, const MsLoadOptions *options,
                     MsGraph *out) {
  *out = (MsGraph){0};
  MsProjectError error = {0};
  MsSpan absolute = {0};
  MsSpan root = {0};
  if (!absolute_name(arena, filename, &absolute, &error) || !canonical_root(arena, absolute, &root, &error)) {
    fail_error(arena, filename, &error, out);
    return;
  }
  Loader loader = {.arena = arena, .names = names, .overlay = options == NULL ? NULL : options->overlay, .root = root};
  out->source_root = root;
  MsSpan entry = {0};
  int32_t index = MS_NO_MODULE;
  Failure failure = {0};
  if (!ms_project_source_path(arena, root, absolute, loader.overlay, &entry, &error)) {
    fail_error(arena, filename, &error, out);
  } else if (!visit(&loader, entry, &index, &failure)) {
    fail_graph(arena, out, failure_diag(&failure, filename, start_position()));
  } else {
    finish(&loader, out);
    out->entry = out->modules[index].name;
  }
  module_list_free(&loader.modules);
  ms_span_list_free(&loader.active);
  ms_span_list_free(&loader.loaded);
}
