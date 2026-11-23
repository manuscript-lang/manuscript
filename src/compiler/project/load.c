/* compiler/project/load.c: a module and the local modules it imports, parsed into one graph. Port of the
 * `Loader` in crates/ms-driver/src/load.rs for standalone files and local imports. A failure stops the load:
 * the graph then has no modules and one diagnostic. */
#include <errno.h>

#include "base/file.h"
#include "base/path.h"
#include "base/utf8.h"
#include "compiler/project/manifest.h"
#include "compiler/project/package.h"
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
  const MsManifest *manifest; /* NULL for a file with no ms.toml above it */
  MsSpan root;
  ModuleList modules;
  MsSpanList active;  /* canonical paths being loaded, for cycle text */
  MsSpanList loaded;  /* canonical path of modules[i] */
  GraphDiagList diagnostics;
  bool recover; /* MsLoadOptions.recover */
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

/* The name diagnostics and metadata use for a canonical file: its path from the project root, or `@package/path` for a
 * fetched package. */
static MsSpan logical_name(Loader *loader, MsSpan canonical) {
  const MsPackage *package = ms_manifest_package_of(loader->manifest, canonical);
  MsStrBuild relative = ms_strbuild_new();
  if (!ms_path_relative(&relative, package == NULL ? loader->root : package->root, canonical)) {
    ms_strbuild_free(&relative);
    return canonical;
  }
  if (package == NULL) {
    return ms_project_text(loader->arena, &relative);
  }
  MsStrBuild named = ms_strbuild_new();
  ms_strbuild_append(&named, package->key);
  ms_strbuild_append_byte(&named, '/');
  ms_strbuild_append(&named, ms_strbuild_span(&relative));
  ms_strbuild_free(&relative);
  return ms_project_text(loader->arena, &named);
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

/* A package file is checked against the locked index as it is read. */
static bool verify_package_file(Loader *loader, MsSpan canonical, MsSpan text, Failure *failure) {
  const MsPackage *package = ms_manifest_package_of(loader->manifest, canonical);
  if (package == NULL) {
    return true;
  }
  MsStrBuild relative = ms_strbuild_new();
  MsProjectError error = {0};
  const bool ok = ms_path_relative(&relative, package->root, canonical) &&
                  ms_package_verify_file(loader->arena, package, ms_strbuild_span(&relative), text, &error);
  ms_strbuild_free(&relative);
  if (!ok) {
    *failure = failure_text(FAIL_ERROR, ms_project_error_text(loader->arena, &error));
  }
  return ok;
}

static bool read_source(Loader *loader, MsSpan canonical, MsSpan *text, Failure *failure) {
  if (overlay_text(loader->overlay, canonical, text)) {
    return true;
  }
  MsSpan name = {0};
  MsSpan directory = {0};
  if (ms_project_embed_of(loader->arena, loader->manifest, canonical, &name, &directory)) {
    MsProjectError error = {0};
    if (ms_project_embed_generate(loader->arena, name, directory, text, &error)) {
      return true;
    }
    *failure = failure_text(FAIL_ERROR, ms_project_error_text(loader->arena, &error));
    return false;
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
  return verify_package_file(loader, canonical, *text, failure);
}

static Failure parse_failure(MsSpan file, const MsDiag *diag) {
  Failure failure = {.kind = FAIL_DIAGNOSTIC};
  failure.diag = (MsGraphDiag){.file = file, .phase = MS_GRAPH_PARSE, .diag = *diag};
  return failure;
}

/* Reports every independent syntax error in the file, not only the first, so one run shows all that need fixing.
 * One unclosed delimiter is one mistake: the strict parse reports it at the end of the file and recovery at the
 * next declaration, naming the same opener. */
static void add_secondary(Loader *loader, MsSpan file, MsSpan text, const MsDiag *first) {
  MsModule kept;
  MsDiag *issues = NULL;
  size_t count = 0;
  (void)ms_parse_partial(loader->arena, loader->names, text, &kept, &issues, &count);
  for (size_t i = 0; i < count; i++) {
    const MsDiag *issue = &issues[i];
    const bool same_place = issue->pos.offset == first->pos.offset && issue->pos.line == first->pos.line &&
                            issue->pos.column == first->pos.column;
    const bool same_opener = issue->opener_line != 0 && issue->opener_line == first->opener_line;
    if (!same_place && issue->pos.line > 0 && !same_opener) {
      graph_diag_list_push(&loader->diagnostics,
                           (MsGraphDiag){.file = file, .phase = MS_GRAPH_PARSE, .diag = *issue});
    }
  }
}

static bool parse_source(Loader *loader, MsSpan file, MsSpan text, MsModule *module, Failure *failure) {
  MsDiag diag = {.pos = start_position()};
  if (!ms_utf8_is_valid(text.ptr, text.len)) {
    diag.message = ms_span_of_text("source must be valid UTF-8; re-save the file with UTF-8 encoding");
    *failure = parse_failure(file, &diag);
    return false;
  }
  if (!ms_parse(loader->arena, loader->names, text, module, &diag)) {
    if (loader->recover) {
      /* Keep what parses; the file's problems are the graph's diagnostics. */
      MsDiag *issues = NULL;
      size_t count = 0;
      (void)ms_parse_partial(loader->arena, loader->names, text, module, &issues, &count);
      /* The recovering parse names where the problem began; the strict one only where it was noticed. */
      bool covered = false;
      for (size_t i = 0; i < count; i++) {
        covered |= issues[i].pos.line > 0 && ((diag.opener_line != 0 && issues[i].opener_line == diag.opener_line) ||
                                              issues[i].pos.offset == diag.pos.offset);
        if (issues[i].pos.line > 0) {
          graph_diag_list_push(&loader->diagnostics, (MsGraphDiag){.file = file, .phase = MS_GRAPH_PARSE, .diag = issues[i]});
        }
      }
      if (!covered) {
        graph_diag_list_push(&loader->diagnostics, (MsGraphDiag){.file = file, .phase = MS_GRAPH_PARSE, .diag = diag});
      }
      return true;
    }
    add_secondary(loader, file, text, &diag);
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
  if (!ms_project_resolve_in(loader->arena, loader->manifest, loader->root, loader->overlay, importer,
                             item->path, &target, &error)) {
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
  out->diagnostic_count = loader->diagnostics.len;
  out->diagnostics = ms_arena_alloc_array(loader->arena, sizeof(MsGraphDiag), _Alignof(MsGraphDiag),
                                          loader->diagnostics.len == 0 ? 1 : loader->diagnostics.len);
  for (size_t i = 0; i < loader->diagnostics.len; i++) {
    out->diagnostics[i] = loader->diagnostics.ptr[i];
  }
  out->count = loader->modules.len;
  out->modules = ms_arena_alloc_array(loader->arena, sizeof(MsGraphModule), _Alignof(MsGraphModule),
                                      loader->modules.len == 0 ? 1 : loader->modules.len);
  for (size_t i = 0; i < loader->modules.len; i++) {
    out->modules[i] = loader->modules.ptr[i];
  }
}

/* A strict load that failed: the diagnostics found on the way, then the failure. */
static void fail_load(Loader *loader, MsGraph *out, MsGraphDiag diag) {
  const size_t found = loader->diagnostics.len;
  out->count = 0;
  out->diagnostic_count = found + 1;
  out->diagnostics = ms_arena_alloc_array(loader->arena, sizeof(MsGraphDiag), _Alignof(MsGraphDiag), found + 1);
  for (size_t i = 0; i < found; i++) {
    out->diagnostics[i] = loader->diagnostics.ptr[i];
  }
  out->diagnostics[found] = diag;
}

static void fail_graph(MsArena *arena, MsGraph *out, MsGraphDiag diag) {
  out->count = 0;
  out->diagnostic_count = 1;
  out->diagnostics = ms_arena_alloc_array(arena, sizeof(MsGraphDiag), _Alignof(MsGraphDiag), 1);
  out->diagnostics[0] = diag;
}

static void fail_error(MsArena *arena, MsSpan filename, const MsProjectError *error, MsGraph *out) {
  if (error->kind == MS_PERR_MANIFEST) {
    fail_graph(arena, out, resolution(error->file, error->position, error->message));
    return;
  }
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

/* The nearest ms.toml in `directory` or above it, as an absolute path. */
static bool enclosing_manifest(MsArena *arena, MsSpan directory, MsSpan *manifest) {
  for (MsSpan current = directory;;) {
    MsStrBuild candidate = ms_strbuild_new();
    ms_path_append_joined(&candidate, current, ms_span_of_text("ms.toml"));
    if (ms_file_is_regular(ms_strbuild_span(&candidate))) {
      *manifest = ms_project_text(arena, &candidate);
      return true;
    }
    ms_strbuild_free(&candidate);
    const MsSpan parent = ms_path_parent(current);
    if (parent.len == 0 || parent.len == current.len) {
      return false;
    }
    current = parent;
  }
}

/* Reads the manifest that governs `absolute`: the file itself when it is an ms.toml, else the nearest one
 * above it. `found` says whether there was one. */
static bool read_governing_manifest(MsArena *arena, MsSpan absolute, MsSpan root, MsManifest *manifest,
                                    bool *found, MsProjectError *error) {
  MsSpan path = absolute;
  *found = true;
  if (!ms_span_is_text(ms_path_file_name(absolute), "ms.toml") && !enclosing_manifest(arena, root, &path)) {
    *found = false;
    return true;
  }
  return ms_manifest_read(arena, path, manifest, error) && ms_package_attach(arena, manifest, error);
}

static void describe_manifest(const MsManifest *manifest, MsGraph *out) {
  out->project_root = manifest->root;
  out->configuration = manifest->configuration;
  out->library = manifest->entry.len == 0;
  out->manifest_file = manifest->file;
  out->manifest_position = manifest->location;
}

/* The packages the graph reaches, with the effects each declares. */
static void describe_packages(MsArena *arena, const MsManifest *manifest, MsGraph *out) {
  out->package_count = manifest->npackages;
  out->packages = ms_arena_alloc_array(arena, sizeof(MsGraphPackage), _Alignof(MsGraphPackage),
                                       manifest->npackages == 0 ? 1 : manifest->npackages);
  for (size_t i = 0; i < manifest->npackages; i++) {
    const MsPackage *package = &manifest->packages[i];
    MsStrBuild prefix = ms_strbuild_new();
    ms_strbuild_append(&prefix, package->key);
    ms_strbuild_append_byte(&prefix, '/');
    out->packages[i] = (MsGraphPackage){.prefix = ms_project_text(arena, &prefix), .spec = package->spec,
                                        .effects = package->manifest->effects,
                                        .effect_count = package->manifest->neffects, .member = package->member};
  }
}

/* Loads one discovered file; a failure is a diagnostic and the load goes on. */
static void add_discovered(Loader *loader, MsSpan file) {
  MsProjectError error = {0};
  MsSpan canonical = {0};
  int32_t index = MS_NO_MODULE;
  Failure failure = {0};
  if (ms_project_source_path(loader->arena, loader->root, file, loader->overlay, &canonical, &error)) {
    if (visit(loader, canonical, &index, &failure)) {
      return;
    }
  } else {
    failure = failure_text(FAIL_ERROR, ms_project_error_text(loader->arena, &error));
  }
  graph_diag_list_push(&loader->diagnostics, failure_diag(&failure, file, start_position()));
}

/* The absolute spelling of `file` with its directory resolved, or false with `error` set. */
static bool real_file(MsArena *arena, MsSpan file, MsSpan *real, MsProjectError *error) {
  MsSpan absolute = {0};
  MsSpan directory = {0};
  if (!absolute_name(arena, file, &absolute, error) || !canonical_root(arena, absolute, &directory, error)) {
    return false;
  }
  MsStrBuild joined = ms_strbuild_new();
  ms_path_append_joined(&joined, directory, ms_path_file_name(absolute));
  *real = ms_project_text(arena, &joined);
  return true;
}

/* Collects the extra files and widens the loader's root to hold them all. A standalone file's root is its directory, so
 * files in other directories need their common ancestor. */
static bool widen_for_extras(Loader *loader, MsSpan filename, const MsLoadOptions *options, bool is_manifest,
                             MsSpanList *files, MsGraph *out) {
  if (options == NULL || options->extra_count == 0 || is_manifest) {
    return true;
  }
  MsProjectError error = {0};
  for (size_t i = 0; i < options->extra_count; i++) {
    MsSpan real = {0};
    if (!real_file(loader->arena, options->extra_files[i], &real, &error)) {
      ms_span_list_free(files);
      fail_error(loader->arena, filename, &error, out);
      return false;
    }
    ms_span_list_push(files, real);
    MsStrBuild relative = ms_strbuild_new();
    while (!(ms_path_relative(&relative, loader->root, ms_path_parent(real)) &&
             !ms_path_escapes(ms_strbuild_span(&relative)))) {
      const MsSpan parent = ms_path_parent(loader->root);
      if (parent.len == 0 || parent.len == loader->root.len) {
        break;
      }
      loader->root = parent;
      ms_strbuild_free(&relative);
      relative = ms_strbuild_new();
    }
    ms_strbuild_free(&relative);
  }
  out->source_root = loader->root;
  return true;
}

static void load_discovered(Loader *loader, const MsManifest *manifest, bool include_source) {
  MsSpanList files = {0};
  MsProjectError error = {0};
  if (!ms_project_discover(loader->arena, manifest->root, manifest->source, include_source, &files, &error)) {
    const MsSpan message = error.kind == MS_PERR_PATH ? ms_project_explain(loader->arena, &error, (MsSpan){0})
                                                      : ms_project_error_text(loader->arena, &error);
    graph_diag_list_push(&loader->diagnostics, resolution(manifest->file, start_position(), message));
  }
  for (size_t i = 0; i < files.len; i++) {
    add_discovered(loader, files.ptr[i]);
  }
  ms_span_list_free(&files);
}

static void load_graph(Loader *loader, MsSpan filename, MsSpan target, bool is_manifest, const MsLoadOptions *options,
                       MsGraph *out) {
  MsProjectError error = {0};
  MsSpan entry = {0};
  int32_t index = MS_NO_MODULE;
  Failure failure = {0};
  MsSpanList extras = {0};
  if (!widen_for_extras(loader, filename, options, is_manifest, &extras, out)) {
    return;
  }
  if (target.len != 0) {
    if (!ms_project_source_path(loader->arena, loader->root, target, loader->overlay, &entry, &error)) {
      ms_span_list_free(&extras);
      fail_error(loader->arena, filename, &error, out);
      return;
    }
    if (!visit(loader, entry, &index, &failure)) {
      ms_span_list_free(&extras);
      fail_load(loader, out, failure_diag(&failure, filename, start_position()));
      return;
    }
  }
  for (size_t i = 0; i < extras.len; i++) {
    add_discovered(loader, extras.ptr[i]);
  }
  ms_span_list_free(&extras);
  const bool tests = options != NULL && options->tests;
  const bool sources = options != NULL && options->project_sources;
  if (is_manifest && (target.len == 0 || tests || sources)) {
    load_discovered(loader, loader->manifest, target.len == 0 || sources);
  }
  finish(loader, out);
  out->entry = index == MS_NO_MODULE ? (MsSpan){0} : out->modules[index].name;
}

void ms_project_load(MsArena *arena, MsNames *names, MsSpan filename, const MsLoadOptions *options,
                     MsGraph *out) {
  *out = (MsGraph){0};
  MsProjectError error = {0};
  MsSpan absolute = {0};
  MsSpan root = {0};
  MsManifest manifest = {0};
  bool governed = false;
  if (!absolute_name(arena, filename, &absolute, &error) || !canonical_root(arena, absolute, &root, &error) ||
      !read_governing_manifest(arena, absolute, root, &manifest, &governed, &error)) {
    out->source_root = manifest.root;
    fail_error(arena, filename, &error, out);
    ms_manifest_free(&manifest);
    return;
  }
  Loader loader = {.arena = arena,
                   .names = names,
                   .overlay = options == NULL ? NULL : options->overlay,
                   .manifest = governed ? &manifest : NULL,
                   .root = governed ? manifest.root : root,
                   .recover = options != NULL && options->recover};
  out->source_root = loader.root;
  const bool is_manifest = ms_span_is_text(ms_path_file_name(absolute), "ms.toml");
  if (is_manifest) {
    describe_manifest(&manifest, out);
  }
  if (governed) {
    describe_packages(arena, &manifest, out);
  }
  load_graph(&loader, filename, is_manifest ? manifest.entry : absolute, is_manifest, options, out);
  module_list_free(&loader.modules);
  graph_diag_list_free(&loader.diagnostics);
  ms_span_list_free(&loader.active);
  ms_span_list_free(&loader.loaded);
  ms_manifest_free(&manifest);
}
