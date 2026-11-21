/* The module graph (project.h): parses every module reachable from an entry file once, in dependency order, and
 * records which module each import names. Port of the strict path of crates/ms-driver/src/load.rs; diagnostics, their
 * order and their texts match it. Editor recovery, overlays, extra entries, test discovery and packages are not covered. */
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "ms/parse.h"
#include "ms/project.h"

/* ---- failures ---- */

/* Diagnostics pass through import edges unchanged; plain errors and cycles acquire the position of the edge that
 * met them. */
typedef enum LoadFailKind { LOAD_FAIL_DIAG, LOAD_FAIL_ERROR, LOAD_FAIL_CYCLE, LOAD_FAIL_CYCLE_DIAG } LoadFailKind;

typedef struct LoadFailure {
    LoadFailKind kind;
    MsGraphDiag diag;
    MsProjectError error;
    const char *cycle;
    const MsGraphDiag *secondary; /* parse diagnostics replayed each time a cached failure is met */
    uint32_t nsecondary;
} LoadFailure;

static const MsPos load_start = {.offset = 0, .line = 1, .column = 1};

static MsGraphDiag load_resolution(const char *file, MsPos pos, const char *message) {
    MsGraphDiag d = {.file = file, .phase = MS_GRAPH_RESOLUTION};
    d.diag.pos = pos;
    d.diag.message = (MsStr){message, (uint32_t)strlen(message)};
    return d;
}

/* ---- explaining path errors ---- */

/* The path of a failed system call, relative to the working directory when it lies below it. */
static const char *load_display_path(MsArena *a, const char *path) {
    char cwd[4096];
    if (getcwd(cwd, sizeof cwd) == NULL) {
        return path;
    }
    const char *canonical;
    MsProjectError ignored;
    const char *bases[2] = {cwd, NULL};
    if (ms_path_eval_symlinks(a, cwd, &canonical, &ignored)) {
        bases[1] = canonical;
    }
    for (size_t i = 0; i < 2 && bases[i] != NULL; i++) {
        const char *rel;
        if (ms_path_rel(a, bases[i], path, &rel, &ignored) && strncmp(rel, "..", 2) != 0) {
            return rel;
        }
    }
    return path;
}

/* Turns raw file-system failures into a cause and a fix. `import_path` is the import string when the failure came
 * from an import. */
static const char *load_explain(MsArena *a, const MsProjectError *err, const char *import_path) {
    if (err->kind != MS_PERR_PATH) {
        return ms_project_error_text(a, err);
    }
    const char *name = load_display_path(a, err->path);
    if (err->err_no == ENOENT && import_path[0] != 0) {
        return ms_arena_fmt(a, "cannot find module %s (looked for %s); check the spelling, make sure the file exists, and that the path is relative to the importing file", import_path, name).ptr;
    }
    if (err->err_no == ENOENT) {
        return ms_arena_fmt(a, "file not found: %s; check the path, pass a .ms file or a project ms.toml, and run from the directory that contains it", name).ptr;
    }
    if (err->err_no == EACCES) {
        return ms_arena_fmt(a, "permission denied reading %s; make the file readable", name).ptr;
    }
    return ms_project_error_text(a, err);
}

/* A path named in ms.toml that cannot be read: the fix is in the manifest, not the shell. */
static const char *load_manifest_path_message(MsArena *a, const MsProjectError *cause) {
    const char *message = load_explain(a, cause, "");
    const char *marker = strstr(message, "; check the path, pass a .ms file");
    if (marker == NULL) {
        return message;
    }
    const char *prefix = "file not found:";
    const char *head = ms_arena_strndup(a, message, (size_t)(marker - message));
    if (strncmp(head, prefix, strlen(prefix)) == 0) {
        head = ms_arena_fmt(a, "path does not exist:%s", head + strlen(prefix)).ptr;
    }
    return ms_arena_fmt(a, "%s; this path comes from ms.toml, so create it or correct the value there", head).ptr;
}

/* A diagnostic for an error that is not one already. */
static MsGraphDiag load_from_error(MsArena *a, const char *file, const MsProjectError *err) {
    if (err->kind == MS_PERR_MANIFEST) {
        const MsPos pos = {.offset = err->offset, .line = err->line, .column = err->column};
        return load_resolution(err->file, pos, load_manifest_path_message(a, err->cause));
    }
    return load_resolution(file, load_start, load_explain(a, err, ""));
}

/* ---- the loader ---- */

typedef enum LoadState { LOAD_NEW, LOAD_ACTIVE, LOAD_LOADED, LOAD_FAILED } LoadState;

/* What is known of one canonical path, indexed by its symbol in GraphLoader.paths. */
typedef struct LoadPathInfo {
    uint8_t state;
    int32_t module; /* LOAD_LOADED */
    uint32_t failure; /* LOAD_FAILED: index into GraphLoader.failures */
} LoadPathInfo;

typedef struct GraphLoader {
    MsArena *arena;
    MsNames *names;
    MsNames paths;      /* canonical paths, and request keys, as symbols */
    const char *root;   /* canonical project root */
    const MsProject *project; /* NULL without a manifest */
    MsBuf info;         /* LoadPathInfo by path symbol */
    MsBuf requests;     /* uint32_t by request-key symbol: target path symbol + 1, 0 for none */
    MsBuf active;       /* MsSym: the import stack, so a cycle can name its whole path */
    MsBuf modules;      /* MsGraphModule */
    MsBuf diags;        /* MsGraphDiag */
    MsBuf failures;     /* LoadFailure */
} GraphLoader;

/* Element `index` of the vector `b`, zero-filled when first reached. */
static void *load_slot(MsBuf *b, size_t size, uint32_t index) {
    const size_t want = ((size_t)index + 1) * size;
    if (b->len < want) {
        const size_t old = b->len;
        ms_buf_push(b, want - old);
        memset(b->data + old, 0, want - old);
    }
    return b->data + (size_t)index * size;
}

static void load_report(GraphLoader *l, MsGraphDiag diag) { MS_VEC_PUSH(l->diags, MsGraphDiag, diag); }

static MsGraphDiag load_diag_of(GraphLoader *l, const LoadFailure *f, const char *file, MsPos cycle_pos) {
    switch (f->kind) {
    case LOAD_FAIL_DIAG:
    case LOAD_FAIL_CYCLE_DIAG: return f->diag;
    case LOAD_FAIL_ERROR: return load_from_error(l->arena, file, &f->error);
    case LOAD_FAIL_CYCLE: return load_resolution(file, cycle_pos, f->cycle);
    }
    return f->diag;
}

static const char *load_message(GraphLoader *l, const LoadFailure *f) {
    switch (f->kind) {
    case LOAD_FAIL_DIAG:
    case LOAD_FAIL_CYCLE_DIAG: return ms_arena_strndup(l->arena, f->diag.diag.message.ptr, f->diag.diag.message.len);
    case LOAD_FAIL_ERROR: return ms_project_error_text(l->arena, &f->error);
    case LOAD_FAIL_CYCLE: return f->cycle;
    }
    return "";
}

static LoadFailure load_failure_diag(MsGraphDiag diag) { return (LoadFailure){.kind = LOAD_FAIL_DIAG, .diag = diag}; }

static LoadFailure load_failure_error(const MsProjectError *err) { return (LoadFailure){.kind = LOAD_FAIL_ERROR, .error = *err}; }

/* The name diagnostics use for a canonical file: its path from the project root. */
static bool load_logical(GraphLoader *l, const char *canonical, const char **out, LoadFailure *fail) {
    MsProjectError err;
    const bool named = l->project != NULL ? ms_project_logical(l->arena, l->project, canonical, out, &err) : ms_path_rel(l->arena, l->root, canonical, out, &err);
    if (named) {
        return true;
    }
    *fail = load_failure_error(&err);
    return false;
}

static const char *load_read(MsArena *a, const char *path, size_t *length, MsProjectError *err) {
    FILE *f = fopen(path, "rbe");
    if (f == NULL) {
        ms_project_error_path(err, a, "open", path, errno);
        return NULL;
    }
    MsBuf data = {0};
    char chunk[16384];
    size_t n;
    while ((n = fread(chunk, 1, sizeof chunk, f)) > 0) {
        ms_buf_put(&data, chunk, n);
    }
    const bool failed = ferror(f) != 0;
    const int saved = errno;
    fclose(f);
    if (failed) {
        ms_buf_free(&data);
        ms_project_error_path(err, a, "read", path, saved);
        return NULL;
    }
    *length = data.len;
    char *text = ms_arena_strndup(a, data.data == NULL ? "" : data.data, data.len);
    ms_buf_free(&data);
    return text;
}

static bool load_visit(GraphLoader *l, MsSym canonical, int32_t *module, LoadFailure *fail);

typedef enum LoadEmbedded { LOAD_NOT_EMBEDDED, LOAD_EMBEDDED, LOAD_EMBED_FAILED } LoadEmbedded;

/* The source of the module generated for an `[embed]` name when `path` is its module path. */
static LoadEmbedded load_embedded(GraphLoader *l, const char *path, const char **text, MsProjectError *err) {
    for (uint32_t i = 0; l->project != NULL && i < l->project->embed_count; i++) {
        const MsAlias *embed = &l->project->embed[i];
        if (strcmp(ms_embed_module_path(l->arena, l->root, embed->name), path) == 0) {
            return ms_embed_generate(l->arena, embed->name, embed->target, text, err) ? LOAD_EMBEDDED : LOAD_EMBED_FAILED;
        }
    }
    return LOAD_NOT_EMBEDDED;
}

/* Parses `text`. A failure reports every independent syntax error of the file, not only the first, so one run shows
 * all that need fixing: the others are the failure's secondary diagnostics. */
static bool load_parse(GraphLoader *l, const char *file, const char *text, size_t length, MsModule *module, LoadFailure *fail) {
    MsDiag first;
    if (ms_parse(l->arena, l->names, text, length, module, &first)) {
        return true;
    }
    MsModule recovered;
    MsDiagList issues = {0};
    ms_parse_partial(l->arena, l->names, text, length, &recovered, &issues);
    MsGraphDiag *kept = MS_NEW_N(l->arena, MsGraphDiag, issues.len + 1);
    uint32_t count = 0;
    for (uint32_t i = 0; i < issues.len; i++) {
        const MsDiag *d = &issues.items[i];
        const bool same = d->pos.offset == first.pos.offset && d->pos.line == first.pos.line && d->pos.column == first.pos.column;
        /* One unclosed delimiter is one mistake: the strict parse reports it at the end of the file and recovery at
         * the next declaration, naming the same opener. */
        if (same || d->pos.line == 0 || (d->opener_line != 0 && d->opener_line == first.opener_line)) {
            continue;
        }
        kept[count++] = (MsGraphDiag){.file = file, .phase = MS_GRAPH_PARSE, .diag = *d};
    }
    for (uint32_t i = 0; i < count; i++) {
        load_report(l, kept[i]);
    }
    *fail = load_failure_diag((MsGraphDiag){.file = file, .phase = MS_GRAPH_PARSE, .diag = first});
    fail->secondary = kept;
    fail->nsecondary = count;
    return false;
}

/* Resolves a local import, remembering the answer for the directory and path it was written with. */
static bool load_resolve(GraphLoader *l, const char *importer, const MsImport *item, MsSym *target, const char *file, LoadFailure *fail) {
    const char *dir = ms_path_dir(l->arena, importer);
    char *key_chars = ms_alloc(l->arena, strlen(dir) + 2 + item->path.len, 1);
    memcpy(key_chars, dir, strlen(dir));
    key_chars[strlen(dir)] = '\0';
    memcpy(key_chars + strlen(dir) + 1, item->path.ptr, item->path.len);
    const MsSym key = ms_intern(&l->paths, key_chars, strlen(dir) + 1 + item->path.len);
    uint32_t *cached = load_slot(&l->requests, sizeof(uint32_t), key);
    if (*cached != 0) {
        *target = *cached - 1;
        return true;
    }
    const char *path = ms_arena_strndup(l->arena, item->path.ptr, item->path.len);
    const char *resolved;
    MsProjectError err;
    if (l->project == NULL) {
        MsProject bare = {.root = l->root, .name = "", .source = "", .entry = ""};
        if (!ms_project_resolve_import(l->arena, &bare, importer, path, &resolved, &err)) {
            *fail = load_failure_diag(load_resolution(file, item->pos, load_explain(l->arena, &err, path)));
            return false;
        }
    } else if (!ms_project_resolve_import(l->arena, l->project, importer, path, &resolved, &err)) {
        *fail = load_failure_diag(load_resolution(file, item->pos, load_explain(l->arena, &err, path)));
        return false;
    }
    *target = ms_intern_cstr(&l->paths, resolved);
    *(uint32_t *)load_slot(&l->requests, sizeof(uint32_t), key) = *target + 1;
    return true;
}

/* An import's module, with the failure of the module it names moved onto this edge. */
static bool load_import(GraphLoader *l, const char *importer, const char *file, const MsImport *item, int32_t *module, LoadFailure *fail) {
    MsSym target;
    if (!load_resolve(l, importer, item, &target, file, fail)) {
        return false;
    }
    if (load_visit(l, target, module, fail)) {
        return true;
    }
    switch (fail->kind) {
    case LOAD_FAIL_DIAG:
    case LOAD_FAIL_CYCLE_DIAG: break;
    case LOAD_FAIL_CYCLE: *fail = (LoadFailure){.kind = LOAD_FAIL_CYCLE_DIAG, .diag = load_resolution(file, item->pos, fail->cycle)}; break;
    case LOAD_FAIL_ERROR: *fail = load_failure_diag(load_resolution(file, item->pos, load_message(l, fail))); break;
    }
    return false;
}

static bool load_module(GraphLoader *l, MsSym canonical, const char *file, int32_t *module, LoadFailure *fail) {
    const MsStr canonical_text = ms_name(&l->paths, canonical);
    const char *path = ms_arena_strndup(l->arena, canonical_text.ptr, canonical_text.len); /* outlives l->paths */
    size_t length = 0;
    MsProjectError err;
    const char *text = NULL;
    const LoadEmbedded embedded = load_embedded(l, path, &text, &err);
    if (embedded == LOAD_NOT_EMBEDDED) {
        text = load_read(l->arena, path, &length, &err);
        /* A package file is checked against the locked index as it is read. */
        const MsPackage *package = text != NULL && l->project != NULL ? ms_project_package_of(l->project, path) : NULL;
        if (package != NULL && !ms_package_verify_file(l->arena, package, path, text, length, &err)) {
            text = NULL;
        }
    } else if (embedded == LOAD_EMBEDDED) {
        length = strlen(text);
    }
    if (text == NULL) {
        *fail = load_failure_error(&err);
        return false;
    }
    if (!ms_utf8_valid(text, length)) {
        MsGraphDiag d = {.file = file, .phase = MS_GRAPH_PARSE};
        d.diag.pos = load_start;
        d.diag.message = (MsStr){"source must be valid UTF-8; re-save the file with UTF-8 encoding", 66};
        *fail = load_failure_diag(d);
        return false;
    }
    MsModule syntax = {0};
    if (!load_parse(l, file, text, length, &syntax, fail)) {
        return false;
    }
    int32_t *targets = MS_NEW_N(l->arena, int32_t, syntax.nimports + 1);
    for (uint32_t i = 0; i < syntax.nimports; i++) {
        const MsImport *item = &syntax.imports[i];
        targets[i] = -1;
        if (item->path.len >= 5 && memcmp(item->path.ptr, "@std/", 5) == 0) {
            continue;
        }
        if (!load_import(l, path, file, item, &targets[i], fail)) {
            return false;
        }
    }
    MsGraphModule m = {.name = file, .path = path, .syntax = syntax, .source = text, .length = length, .targets = targets};
    *module = (int32_t)MS_VEC_LEN(l->modules, MsGraphModule);
    MS_VEC_PUSH(l->modules, MsGraphModule, m);
    return true;
}

/* Visits a canonical path: resolution happens at the graph's edges, never again during traversal. */
static bool load_visit(GraphLoader *l, MsSym canonical, int32_t *module, LoadFailure *fail) {
    const char *path = ms_name(&l->paths, canonical).ptr;
    const char *file;
    if (!load_logical(l, path, &file, fail)) {
        return false;
    }
    const size_t depth = MS_VEC_LEN(l->active, MsSym);
    for (size_t i = 0; i < depth; i++) {
        if (MS_VEC_AT(l->active, MsSym, i) != canonical) {
            continue;
        }
        MsBuf chain = {0};
        for (size_t k = i; k < depth; k++) {
            const char *step;
            if (!load_logical(l, ms_name(&l->paths, MS_VEC_AT(l->active, MsSym, k)).ptr, &step, fail)) {
                ms_buf_free(&chain);
                return false;
            }
            ms_buf_puts(&chain, step);
            ms_buf_puts(&chain, " -> ");
        }
        ms_buf_puts(&chain, file);
        ms_buf_putc(&chain, 0);
        *fail = (LoadFailure){.kind = LOAD_FAIL_CYCLE, .cycle = ms_arena_fmt(l->arena, "cyclic module dependency %s; modules cannot import each other in a loop, so move the shared declarations into a third module that both import", chain.data).ptr};
        ms_buf_free(&chain);
        return false;
    }
    LoadPathInfo *info = load_slot(&l->info, sizeof(LoadPathInfo), canonical);
    if (info->state == LOAD_LOADED) {
        *module = info->module;
        return true;
    }
    if (info->state == LOAD_FAILED) {
        *fail = MS_VEC_AT(l->failures, LoadFailure, info->failure);
        for (uint32_t i = 0; i < fail->nsecondary; i++) {
            load_report(l, fail->secondary[i]);
        }
        return false;
    }
    MS_VEC_PUSH(l->active, MsSym, canonical);
    const bool ok = load_module(l, canonical, file, module, fail);
    MS_VEC_POP(l->active, MsSym);
    info = load_slot(&l->info, sizeof(LoadPathInfo), canonical); /* the vector may have moved */
    if (ok) {
        info->state = LOAD_LOADED;
        info->module = *module;
    } else if (fail->kind == LOAD_FAIL_DIAG || fail->kind == LOAD_FAIL_ERROR) {
        info->state = LOAD_FAILED;
        info->failure = (uint32_t)MS_VEC_LEN(l->failures, LoadFailure);
        MS_VEC_PUSH(l->failures, LoadFailure, *fail);
    }
    return ok;
}

/* ---- finding the project ---- */

/* The nearest enclosing ms.toml of `dir`, which supplies the import root and aliases so an entry file can share a
 * library above it. */
static const char *load_enclosing_manifest(MsArena *a, const char *dir) {
    const char *current = dir;
    for (;;) {
        const char *candidate = MS_PATH_JOIN(a, current, "ms.toml");
        struct stat info;
        if (stat(candidate, &info) == 0 && S_ISREG(info.st_mode)) {
            return candidate;
        }
        const char *parent = ms_path_dir(a, current);
        if (strcmp(parent, current) == 0) {
            return NULL;
        }
        current = parent;
    }
}

static void load_finish(GraphLoader *l, MsGraph *out) {
    const size_t modules = MS_VEC_LEN(l->modules, MsGraphModule);
    out->count = (uint32_t)modules;
    out->modules = MS_NEW_N(l->arena, MsGraphModule, modules + 1);
    if (modules > 0) {
        memcpy(out->modules, ms_buf_items(&l->modules), modules * sizeof(MsGraphModule));
    }
    const size_t diags = MS_VEC_LEN(l->diags, MsGraphDiag);
    out->ndiagnostics = (uint32_t)diags;
    out->diagnostics = MS_NEW_N(l->arena, MsGraphDiag, diags + 1);
    if (diags > 0) {
        memcpy(out->diagnostics, ms_buf_items(&l->diags), diags * sizeof(MsGraphDiag));
    }
}

static void load_free(GraphLoader *l) {
    ms_names_free(&l->paths);
    ms_buf_free(&l->info);
    ms_buf_free(&l->requests);
    ms_buf_free(&l->active);
    ms_buf_free(&l->modules);
    ms_buf_free(&l->diags);
    ms_buf_free(&l->failures);
}

static bool load_graph(MsArena *a, MsNames *names, const char *filename, MsGraph *out, MsProjectError *err);

/* The packages of a project that is not a workspace member and has no path dependency, which the loader hands on to
 * the caller. */
static bool load_attach(MsArena *a, MsProject *project, MsProjectError *err) {
    return project->is_workspace || project->path_dependency_count > 0 || ms_project_attach(a, project, err);
}

bool ms_project_load(MsArena *a, MsNames *names, const char *filename, MsGraph *out, MsProjectError *err) {
    if (!load_graph(a, names, filename, out, err)) {
        return false;
    }
    if (out->package_count > 0) {
        ms_project_error_unsupported(err, "[dependencies] in the module graph");
        return false;
    }
    return true;
}

bool ms_project_load_packages(MsArena *a, MsNames *names, const char *filename, MsGraph *out, MsProjectError *err) {
    return load_graph(a, names, filename, out, err);
}

/* A manifest that cannot be read is the graph's one diagnostic, named by the entry's path from the project root. */
static void load_manifest_failed(MsArena *a, const char *filename, const char *absolute, const char *root, const MsProject *project, MsProjectError *failure, MsGraph *out) {
    const char *shown = filename;
    const char *rel;
    const char *base = project->root != NULL ? project->root : root;
    if (ms_path_rel(a, base, absolute, &rel, failure) && !ms_path_escapes(rel)) {
        shown = rel;
    }
    out->source_root = base;
    out->diagnostics = MS_NEW(a, MsGraphDiag);
    out->diagnostics[0] = load_from_error(a, shown, failure);
    out->ndiagnostics = 1;
}

/* Lists the packages of `project` in the graph. */
static void load_packages(MsArena *a, const MsProject *project, MsGraph *out) {
    out->package_count = project->package_count;
    out->packages = MS_NEW_N(a, MsGraphPackage, project->package_count + 1);
    for (uint32_t i = 0; i < project->package_count; i++) {
        const MsPackage *package = &project->packages[i];
        out->packages[i] = (MsGraphPackage){.prefix = ms_arena_fmt(a, "%s/", package->key).ptr, .spec = package->spec, .effects = package->project.effects, .effect_count = package->project.effect_count};
    }
}

static bool load_graph(MsArena *a, MsNames *names, const char *filename, MsGraph *out, MsProjectError *err) {
    *out = (MsGraph){0};
    MsProjectError failure;
    const char *absolute;
    const char *root = "";
    if (!ms_path_abs(a, filename, &absolute, &failure) ||
        !ms_path_eval_symlinks(a, ms_path_dir(a, absolute), &root, &failure)) {
        out->diagnostics = MS_NEW(a, MsGraphDiag);
        out->diagnostics[0] = load_from_error(a, filename, &failure);
        out->ndiagnostics = 1;
        return true;
    }
    MsProject project;
    MsProject *config = NULL;
    const bool is_manifest = strcmp(ms_path_base(a, absolute), "ms.toml") == 0;
    const char *manifest = is_manifest ? absolute : load_enclosing_manifest(a, root);
    if (manifest != NULL) {
        if (!ms_project_read(a, manifest, &project, &failure) || !load_attach(a, &project, &failure)) {
            if (ms_project_error_is_unsupported(&failure)) {
                *err = failure;
                return false;
            }
            load_manifest_failed(a, filename, absolute, root, &project, &failure, out);
            return true;
        }
        if (project.is_workspace || project.path_dependency_count > 0) {
            ms_project_error_unsupported(err, "[workspace] and path dependencies in the module graph");
            return false;
        }
        load_packages(a, &project, out);
        config = &project;
        root = project.root;
        if (is_manifest) {
            if (project.entry[0] == 0) {
                ms_project_error_unsupported(err, "a library manifest");
                return false;
            }
            out->project_root = project.root;
            out->configuration = project.configuration;
            out->manifest_file = project.file;
            out->manifest_pos = project.location;
        } else {
            project.entry = absolute;
        }
    }
    out->source_root = root;

    GraphLoader l = {.arena = a, .names = names, .root = root, .project = config};
    ms_names_init(&l.paths);
    const char *entry;
    const char *entry_input = config != NULL && config->entry[0] != 0 ? config->entry : absolute;
    if (!ms_project_source_path(a, root, entry_input, &entry, &failure)) {
        load_report(&l, load_from_error(a, filename, &failure));
        load_finish(&l, out);
        load_free(&l);
        return true;
    }
    int32_t module;
    LoadFailure fail;
    if (load_visit(&l, ms_intern_cstr(&l.paths, entry), &module, &fail)) {
        out->entry = ((MsGraphModule *)ms_buf_items(&l.modules))[module].name;
    } else {
        /* An incomplete strict graph cannot be checked. */
        l.modules.len = 0;
        load_report(&l, load_diag_of(&l, &fail, filename, load_start));
    }
    load_finish(&l, out);
    load_free(&l);
    return true;
}
