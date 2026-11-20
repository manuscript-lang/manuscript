/* Projects: file names to the module graph the checker reads. Port of crates/ms-driver (`project` and `load`).
 *
 * Paths are `/`-separated text, cleaned as Go's path/filepath does. Every function allocates its results in the
 * caller's arena. A failure fills an MsProjectError, whose text (ms_project_error_text) is what the Rust driver
 * printed, byte for byte. POSIX only for now: the file-system calls are in project/path.c. */
#ifndef MS_PROJECT_H
#define MS_PROJECT_H

#include "ms/ast.h"
#include "ms/base.h"
#include "ms/semver.h"
#include "ms/tables.h"

typedef enum MsProjectErrorKind {
    MS_PERR_NONE,
    MS_PERR_PATH,    /* a failed system call on a path: `op path: message` */
    MS_PERR_ERRNO,   /* a bare errno, as Go returns from symlink walks */
    MS_PERR_MESSAGE, /* any other text */
    MS_PERR_MANIFEST, /* `file:line:column: cause` */
    MS_PERR_UNSUPPORTED /* a feature the C reader lacks: the caller hands the work to the Rust driver */
} MsProjectErrorKind;

typedef struct MsProjectError MsProjectError;
struct MsProjectError {
    MsProjectErrorKind kind;
    const char *op, *path;       /* MS_PERR_PATH */
    int err_no;                  /* MS_PERR_PATH, MS_PERR_ERRNO */
    const char *message;         /* MS_PERR_MESSAGE, MS_PERR_UNSUPPORTED (what is missing) */
    const char *file;            /* MS_PERR_MANIFEST: where it was found, and the cause */
    uint32_t line, column, offset;
    const MsProjectError *cause;
};

/* The text of the error, as `Display` printed it. */
const char *ms_project_error_text(MsArena *a, const MsProjectError *err);
/* True for ENOENT only (Go's os.IsNotExist), looking through a manifest location. */
bool ms_project_error_not_exist(const MsProjectError *err);
void ms_project_error_message(MsProjectError *err, const char *message);
void ms_project_error_unsupported(MsProjectError *err, const char *what);
bool ms_project_error_is_unsupported(const MsProjectError *err);
void ms_project_error_path(MsProjectError *err, MsArena *a, const char *op, const char *path, int err_no);

/* ---- paths (project/path.c): filepath.Clean, Join, Dir, Base, Ext, Abs, Rel, EvalSymlinks ---- */

const char *ms_path_clean(MsArena *a, const char *path);
/* Joins the non-empty elements and cleans the result; all empty gives "". */
const char *ms_path_join(MsArena *a, const char *const *elements, size_t count);
#define MS_PATH_JOIN(a, ...) \
    ms_path_join((a), (const char *const[]){__VA_ARGS__}, sizeof((const char *const[]){__VA_ARGS__}) / sizeof(char *))
const char *ms_path_dir(MsArena *a, const char *path);
const char *ms_path_base(MsArena *a, const char *path);
/* The suffix beginning at the final dot of the last element ("" for none); points into `path`. */
const char *ms_path_ext(const char *path);
bool ms_path_is_abs(const char *path);
MS_NODISCARD bool ms_path_abs(MsArena *a, const char *path, const char **out, MsProjectError *err);
MS_NODISCARD bool ms_path_rel(MsArena *a, const char *base, const char *target, const char **out, MsProjectError *err);
/* True when `rel` (from ms_path_rel) leaves its base directory. */
bool ms_path_escapes(const char *rel);
/* The entry names of `dir` other than `.` and `..`, in byte order. A directory that cannot be opened fails as
 * `<open_op> <dir>: <reason>`. */
MS_NODISCARD bool ms_path_list_dir(MsArena *a, const char *dir, const char *open_op, const char *const **names, uint32_t *count, MsProjectError *err);
MS_NODISCARD bool ms_path_eval_symlinks(MsArena *a, const char *path, const char **out, MsProjectError *err);


/* ---- ms.toml (project/manifest.c) ---- */

/* An `[aliases]` entry: the name as written (`@lib`), its target made canonical, and where each was written. */
typedef struct MsAlias {
    const char *name, *target;
    MsPos key_pos, value_pos;
} MsAlias;

/* ---- [dependencies] ---- */

typedef enum MsDepKind { MS_DEP_TAG, MS_DEP_SHA, MS_DEP_VERSION } MsDepKind;

/* One entry of `[dependencies]`: `alias = { url = ..., tag | sha | version = ... }`. */
typedef struct MsDependency {
    const char *alias;
    const char *url;
    MsDepKind kind;
    const char *reference;       /* the tag or commit (TAG, SHA) */
    MsRequirement requirement;   /* VERSION */
} MsDependency;

/* `[effects] @pg = ["std.net.*"]`: the effects the project allows a dependency. */
typedef struct MsEffectRule {
    const char *name;
    const char *const *patterns;
    uint32_t count;
} MsEffectRule;

/* A read manifest. `[project]`, `[aliases]`, `[embed]`, `[dependencies]` (inline tables), `[effects]` and
 * `[workspace] members` are read; a manifest that uses another TOML form (dotted keys, `[dependencies.x]` tables,
 * multi-line strings) or is not valid TOML fails with MS_PERR_UNSUPPORTED, so the caller can hand the command to the
 * Rust driver. Every list below is sorted by name, as the Rust maps iterate. */
typedef struct MsProject {
    const char *root;          /* canonical directory holding ms.toml */
    const char *file;          /* base name of the manifest, as diagnostics print it */
    const char *name;
    const char *source;        /* canonical source directory */
    const char *entry;         /* canonical entry file, "" for a library */
    const char *configuration; /* the manifest text as read */
    MsAlias *aliases;          /* sorted by name */
    uint32_t alias_count;
    MsAlias *embed;            /* [embed]: name and canonical directory */
    uint32_t embed_count;
    MsDependency *dependencies; /* [dependencies] with a url */
    uint32_t dependency_count;
    MsAlias *path_dependencies; /* [dependencies] written { path = "../member" }: canonical directory */
    uint32_t path_dependency_count;
    MsEffectRule *allowed_effects; /* [effects] */
    uint32_t allowed_effect_count;
    const char *const *effects; /* [project] effects */
    uint32_t effect_count;
    bool is_workspace;          /* a [workspace] table is present */
    const char *const *members; /* its members, as written */
    uint32_t member_count;
    bool has_version;           /* [project] version */
    MsVersion version;
    MsPos location;            /* the [project] header */
} MsProject;

/* One `[dependencies]` entry as `alias\turl\tkind\treference` (kind tag, sha or version; the reference is the tag, the
 * commit or the requirement as written), the row ms_tool_dependencies returns. */
const char *ms_project_dependency_row(MsArena *a, const MsDependency *d);

/* The whole file at `path`, NUL-terminated after its `*length` bytes (which may include NULs); NULL with *err set. */
const char *ms_project_read_file(MsArena *a, const char *path, size_t *length, MsProjectError *err);
/* The nearest ms.toml in `filename`'s directory or above, NULL when there is none. */
const char *ms_project_find_manifest(MsArena *a, const char *filename);
MS_NODISCARD bool ms_project_read(MsArena *a, const char *manifest, MsProject *out, MsProjectError *err);

/* ---- [embed] (project/embed.c) ---- */

/* The logical path of the generated module that imports of the embed `name` (such as `@assets`) resolve to, under `root`. */
const char *ms_embed_module_path(MsArena *a, const char *root, const char *name);
/* The source of that module for the directory `root` (which holds the files): every file as Base64 text. A symbolic
 * link, names that differ only by letter case, a file over 16 MiB or more than 64 MiB in all is an error. */
MS_NODISCARD bool ms_embed_generate(MsArena *a, const char *name, const char *root, const char **source, MsProjectError *err);

/* ---- discovery (project/discover.c) ---- */

/* The test files (`test.ms`, `*_test.ms`, `bench.ms`, `*_bench.ms`) below the project root and, with `include_source`,
 * every `.ms` file below its source directory, sorted and without duplicates. Hidden, `vendor` and `node_modules`
 * directories and nested projects are skipped, and directory links are not followed. */
MS_NODISCARD bool ms_project_discover(MsArena *a, const MsProject *project, bool include_source, const char ***paths,
                                      uint32_t *count, MsProjectError *err);
/* The files `ms fmt target` formats: `target` itself when it is a file, else the discovered modules of the directory or
 * of the project the manifest names, with its entry, each confined to the project root. A workspace root, and a project
 * with dependencies, fail as MS_PERR_UNSUPPORTED. */
MS_NODISCARD bool ms_project_format_paths(MsArena *a, const char *target, const char ***paths, uint32_t *count,
                                          MsProjectError *err);

/* ---- imports (project/resolve.c) ---- */

/* Resolves a local import written in `importer` to a canonical file confined to the project root. Standard-library
 * imports (`@std/`) belong to the checker and are not passed here. */
MS_NODISCARD bool ms_project_resolve_import(MsArena *a, const MsProject *p, const char *importer, const char *path,
                                            const char **out, MsProjectError *err);
/* Canonicalises `path` (relative paths are under `root`, which is canonical) and rejects one that leaves `root`. */
MS_NODISCARD bool ms_project_source_path(MsArena *a, const char *root, const char *path, const char **out,
                                         MsProjectError *err);
/* Go's strconv.Quote, for `%q` in diagnostics. */
const char *ms_project_quote(MsArena *a, const char *text);
/* The text as Rust's `{:?}` writes a string, for the messages that were formatted that way. */
const char *ms_debug_quote(MsArena *a, const char *text);

/* ---- the module graph (project/load.c) ---- */

typedef enum MsGraphPhase { MS_GRAPH_PARSE, MS_GRAPH_RESOLUTION } MsGraphPhase;

/* A problem found while loading, named by the file it is in (the module's logical path, or the manifest). */
typedef struct MsGraphDiag {
    const char *file;
    MsGraphPhase phase;
    MsDiag diag;
} MsGraphDiag;

/* One parsed local module. `targets[i]` is the index in MsGraph.modules of what `syntax.imports[i]` names, or -1 for a
 * standard-library import, which the checker resolves. A module's imports come before it in the graph. */
typedef struct MsGraphModule {
    const char *name; /* logical path: relative to the project root */
    const char *path; /* canonical file */
    MsModule syntax;
    const char *source;
    size_t length;
    const int32_t *targets;
} MsGraphModule;

typedef struct MsGraph {
    MsGraphModule *modules; /* dependency order; empty when a strict load failed */
    uint32_t count;
    MsGraphDiag *diagnostics;
    uint32_t ndiagnostics;
    const char *entry;        /* logical path of the entry module */
    const char *source_root;  /* the directory the logical paths are relative to */
    const char *project_root; /* the directory of ms.toml; NULL for a standalone file */
    const char *configuration;
    const char *manifest_file; /* where [project] is declared, for diagnostics; NULL without a manifest */
    MsPos manifest_pos;
} MsGraph;

/* Loads the module `filename` (a .ms file) with everything it imports, as the Rust driver's strict `load_file` does.
 * Problems with the inputs are diagnostics in the graph; the result is false only when the C loader does not cover
 * the request (MS_PERR_UNSUPPORTED in `err`: a library manifest, test discovery, anything the manifest reader
 * leaves out), so the caller can hand the command to the Rust driver. Modules parse into `names` and `a`. */
MS_NODISCARD bool ms_project_load(MsArena *a, MsNames *names, const char *filename, MsGraph *out, MsProjectError *err);

/* ---- checking a graph (project/graph_check.c) ---- */

/* Adds each module of the graph to the checker, in graph order, with its imports resolved to the modules they name
 * (`import_targets`; standard-library imports stay MS_NONE). `ids` receives the checker's id of each module. */
void ms_graph_add_modules(MsCheck *c, MsNames *names, MsArena *a, const MsGraph *graph, MsModId *ids);
/* Checks the bodies of every module of the graph with the program's method table (ms_program_check_module). Modules
 * with an inherent error are left unchecked and their ids appear in `unchecked` when it is not NULL; returns how many. */
uint32_t ms_graph_check(MsCheck *c, const MsGraph *graph, const MsModId *ids, bool *unchecked);

#endif
