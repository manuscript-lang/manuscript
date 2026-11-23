/* compiler/project/project.h: file names to the module graph the checker reads. Port of crates/ms-driver
 * (`project` and `load`).
 *
 * Paths are UTF-8 spans with `/` separators, cleaned as Go's path/filepath does (base/path.h). Everything a
 * call returns lives in the arena the caller passes, so one arena holds a whole load. A failure is a
 * diagnostic in the graph, or an MsProjectError for what has no source position, whose text is what the Rust
 * driver printed, byte for byte. Standard-library imports (`@std/...`) are not resolved here: the graph names
 * them with MS_NO_MODULE and the checker finds them among the bundled sources below. */
#ifndef MS_PROJECT_H
#define MS_PROJECT_H

#include "base/arena.h"
#include "base/intern.h"
#include "base/safe.h"
#include "compiler/syntax/ast.h"
#include "compiler/syntax/pos.h"

/* ---- errors ---- */

typedef enum MsProjectErrorKind {
  MS_PERR_NONE,
  MS_PERR_PATH,     /* a failed system call on a path: `op path: message` */
  MS_PERR_MESSAGE,  /* any other text */
  MS_PERR_MANIFEST, /* `file:line:column: cause` */
} MsProjectErrorKind;

typedef struct MsProjectError {
  MsProjectErrorKind kind;
  MsSpan op, path; /* MS_PERR_PATH */
  int os_error;    /* MS_PERR_PATH: the OS error number, 0 when unknown */
  MsSpan message;  /* MS_PERR_MESSAGE, and the cause of MS_PERR_MANIFEST */
  MsSpan file;     /* MS_PERR_MANIFEST: where it was found */
  MsPos position;  /* MS_PERR_MANIFEST */
} MsProjectError;

/* The text of the error as the Rust driver's `Display` printed it, in the arena. */
MsSpan ms_project_error_text(MsArena *arena, const MsProjectError *error);

/* ---- sources ---- */

/* Unsaved editor contents by canonical path; a file not on disk may be named only when an overlay holds it.
 */
typedef struct MsOverlayFile {
  MsSpan path;
  MsSpan text;
} MsOverlayFile;

typedef struct MsOverlay {
  const MsOverlayFile *files;
  size_t count;
} MsOverlay;

/* A `.ms` file the executable carries: the bundled standard library (the .ms files of stdlib/), by its name below `@std/`
 * (`io/io.ms`, `bytes.ms`). Sorted by name, static storage. */
typedef struct MsStdSource {
  MsSpan name;
  MsSpan text;
} MsStdSource;

/* Every bundled file in name order. */
const MsStdSource *ms_std_sources(size_t *count);
/* The bundled file named `name` (without the `@std/` prefix), or false. */
MS_NODISCARD bool ms_std_source_find(MsSpan name, MsStdSource *out);

/* ---- imports ---- */

/* The canonical file a local import `path` written in the file `importer` names, confined to the project root
 * (`root`, canonical). `overlay` may be NULL. False with *error filled when the file cannot be named or read.
 */
MS_NODISCARD bool ms_project_resolve_import(MsArena *arena, MsSpan root, const MsOverlay *overlay,
                                            MsSpan importer, MsSpan path, MsSpan *canonical,
                                            MsProjectError *error);

/* ---- the module graph ---- */

enum { MS_NO_MODULE = -1 };

typedef enum MsGraphPhase { MS_GRAPH_PARSE, MS_GRAPH_RESOLUTION, MS_GRAPH_TYPE } MsGraphPhase;

/* A problem found while loading, named by the file it is in (the module's logical path, or the manifest). */
typedef struct MsGraphDiag {
  MsSpan file;
  MsGraphPhase phase;
  MsDiag diag;
} MsGraphDiag;

/* One parsed local module. `targets[i]` is the index in MsGraph.modules of what `syntax.imports[i]` names, or
 * MS_NO_MODULE for a standard-library import. A module's imports come before it in the graph. */
typedef struct MsGraphModule {
  MsSpan name;   /* logical path: relative to the project root */
  MsSpan path;   /* canonical file */
  MsSpan source; /* the text as read */
  MsModule syntax;
  const int32_t *targets;
} MsGraphModule;

/* A fetched package the graph reaches: the checker lets it use only its declared effects and no natives. */
typedef struct MsGraphPackage {
  MsSpan prefix; /* `@github.com/acme/wire@v1.4.2/`, which starts the logical path of each of its modules */
  MsSpan spec;
  const MsSpan *effects;
  size_t effect_count;
  bool member; /* a workspace member: it may declare natives */
} MsGraphPackage;

typedef struct MsGraph {
  MsGraphModule *modules; /* dependency order; empty when a strict load failed */
  size_t count;
  MsGraphDiag *diagnostics;
  size_t diagnostic_count;
  MsSpan entry;         /* logical path of the entry module; empty for a library */
  MsSpan source_root;   /* the directory the logical paths are relative to */
  MsSpan project_root;  /* the directory of ms.toml; empty for a standalone file */
  MsSpan configuration; /* the manifest text */
  MsSpan manifest_file; /* where [project] is declared, for diagnostics; empty without a manifest */
  MsPos manifest_position;
  MsGraphPackage *packages; /* every package reached, however deep */
  size_t package_count;
  bool library; /* a manifest without an entry */
} MsGraph;

typedef struct MsLoadOptions {
  bool tests;               /* add the project's test.ms, *_test.ms, bench.ms and *_bench.ms files */
  bool project_sources;     /* add every source file of a manifest's project too (`ms check`) */
  const MsOverlay *overlay; /* unsaved contents in place of disk, or NULL */
  bool recover;             /* a module that does not parse keeps the declarations that do, its problems left in
                               the graph's diagnostics: editor use */
  const MsSpan *extra_files; /* more standalone files loaded with the first (`ms test a.ms b.ms`); the source root widens to
                                hold them all */
  size_t extra_count;
} MsLoadOptions;

/* Loads the module `filename` (a .ms file, or an ms.toml) with every local module it imports, as the Rust
 * driver's `load_file` does. Problems with the inputs are diagnostics in the graph. Modules parse into
 * `names` and `arena`. */
void ms_project_load(MsArena *arena, MsNames *names, MsSpan filename, const MsLoadOptions *options,
                     MsGraph *out);

/* The source files a command target stands for: a .ms file is itself; a directory or an ms.toml stands for the
 * project's modules (every .ms file below its source directory, its test and bench files, and its entry),
 * confined to the project root. Paths are appended to `paths`. */
/* Whether a directory of this name is left out of discovery and search: hidden, `vendor` or `node_modules`. */
bool ms_project_skips_name(MsSpan name);

/* For a directory with no `.ms` files of its own: text starting with "; " that names the projects (directories with
 * their own ms.toml) below it, or empty when there are none. */
MsSpan ms_project_nested_hint(MsArena *arena, MsSpan dir);

MS_NODISCARD bool ms_project_format_files(MsArena *arena, MsSpan target, MsSpanList *paths,
                                          MsProjectError *error);

/* The manifests of the members of `target` when it is a workspace root without a [project] of its own, so a command
 * aimed at it means "every member"; `*found` is false for any other target. */
MS_NODISCARD bool ms_project_workspace_members(MsArena *arena, MsSpan target, MsSpanList *manifests, bool *found,
                                               MsProjectError *error);

#endif
