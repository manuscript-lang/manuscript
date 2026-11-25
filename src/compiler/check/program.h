/* compiler/check/program.h: the checked program: symbols, module scopes and diagnostics.
 *
 * A MsCheckProgram holds every module the check reaches (the user's files and the bundled standard
 * modules). Modules are indexed in load order. A symbol is a module-level name: a type, a function or
 * constant, or a type alias. Each module has a scope mapping names to symbol ids, built by the declare pass
 * and extended by the import pass; a symbol id is an index into `symbols` and never changes.
 *
 * Ownership: the program owns its tables, its arena and its diagnostics. The syntax trees and the name table
 * are borrowed from the loader and must outlive the program. */
#ifndef MS_COMPILER_CHECK_PROGRAM_H
#define MS_COMPILER_CHECK_PROGRAM_H

#include "base/arena.h"
#include "base/intern.h"
#include "base/map.h"
#include "base/string.h"
#include "compiler/check/facts.h"
#include "compiler/check/methods.h"
#include "compiler/check/properties.h"
#include "compiler/check/types.h"
#include "compiler/project/project.h"
#include "compiler/syntax/ast.h"

typedef uint32_t MsSymbolId; /* 0 is "no symbol" */

typedef enum MsSymbolKind { MS_SYMBOL_TYPE, MS_SYMBOL_FN, MS_SYMBOL_ALIAS } MsSymbolKind;

/* What a declaration binds to. */
typedef enum MsNativeKind {
  MS_NATIVE_SOURCE,   /* a source body */
  MS_NATIVE_CONTRACT, /* an interface operation */
  MS_NATIVE_EXTERN,   /* an `extern fn`: a runtime symbol */
  MS_NATIVE_BUILTIN   /* a bodiless standard declaration the compiler lowers */
} MsNativeKind;

typedef struct MsSymbol {
  MsName name;
  MsName id; /* unique across the program */
  MsSymbolKind kind;
  MsNativeKind native;
  uint32_t module;
  bool exported;
  MsTy ty;       /* MS_TY_NONE until its signature resolves */
  uint32_t def;  /* MsDefs index of a nominal type, else 0 */
  uint32_t var_at;    /* the declared type variables: a range of the program's symbol_vars */
  uint32_t var_count;
  uint8_t alias_state; /* an alias target: 0 not yet resolved, 1 resolving, 2 resolved */
  const MsDecl *decl;
} MsSymbol;

MS_LIST_DEFINE(MsSymbolList, ms_symbol_list, MsSymbol)
MS_MAP_DEFINE(MsScope, ms_scope, uint32_t, MsSymbolId, ms_hash_u32_key, ms_equal_u32_key)

/* One loaded module: its tree, its file name and its scope of module-level names. */
typedef struct MsModuleInfo {
  MsName file; /* the name the file is reported under */
  const MsModule *tree;
  MsScope scope;      /* owned: name -> symbol id */
  MsScope imports;    /* owned: imported name -> symbol id (0 when the import did not resolve) */
  const int32_t *targets; /* borrowed from the graph: module index of each local import; NULL for std */
  MsFacts facts;
  MsSpan source; /* the text the tree was parsed from; borrowed */
  bool bundled;  /* the module stands for a bundled standard module (`@std/...`), loaded from the bundle or given by an editor */
} MsModuleInfo;

MS_LIST_DEFINE(MsModuleList, ms_module_list, MsModuleInfo)

/* A local the checker declared, in declaration order: what `ms inspect` lists. */
typedef struct MsLocalRecord {
  uint32_t module;
  MsName name;
  MsTy ty;
  MsPos pos;
} MsLocalRecord;

MS_LIST_DEFINE(MsLocalRecordList, ms_local_record_list, MsLocalRecord)

/* A written type of a user module, as the resolver read it: the node id of the reference and its checked type. */
typedef struct MsTypeRefRecord {
  uint32_t module;
  MsNode node;
  MsTy ty;
} MsTypeRefRecord;

MS_LIST_DEFINE(MsTypeRefRecordList, ms_type_ref_record_list, MsTypeRefRecord)

/* A written generic type whose arguments await the bound check, which needs every method declared first. */
typedef struct MsPendingBound {
  uint32_t module;
  MsPos pos;
  MsTy ty;
} MsPendingBound;

MS_LIST_DEFINE(MsPendingBoundList, ms_pending_bound_list, MsPendingBound)

/* A type parameter's default awaiting the check that it meets the parameter's bounds. */
typedef struct MsPendingDefault {
  uint32_t module;
  MsPos pos;
  MsTy variable; /* the resolved default */
  MsTy owner;    /* the type parameter */
} MsPendingDefault;

MS_LIST_DEFINE(MsPendingDefaultList, ms_pending_default_list, MsPendingDefault)

typedef enum MsCheckPhase { MS_CHECK_RESOLUTION, MS_CHECK_TYPE } MsCheckPhase;

/* Where in the oracle's order a diagnostic is found: imports, then the declaration passes, then each body. The
 * whole-module passes that look into bodies (names, mutation, returns) are SIDE; the body walk is WALK, whose
 * order is the oracle's. */
typedef enum MsCheckStage { MS_STAGE_DECLARATIONS, MS_STAGE_IMPORTS, MS_STAGE_SIDE, MS_STAGE_WALK, MS_STAGE_FINAL } MsCheckStage;

typedef struct MsCheckDiag {
  uint32_t module;
  MsPos pos;
  MsCheckPhase phase;
  MsString message; /* owned */
  bool has_end;     /* the diagnostic spans [pos, end) */
  MsPos end;
  uint8_t stage;    /* an MsCheckStage: imports, then declarations (each in the order found), then bodies */
  uint32_t anchor;  /* where the oracle's walk emits it among the body's diagnostics, when after its position; else 0 */
  bool ends_decl;   /* found once the declaration's body was walked: listed after the rest of its declaration */
  bool has_fix;     /* an edit that repairs the diagnostic: replace [fix_pos, fix_end) with `fix_text` */
  MsPos fix_pos, fix_end;
  MsString fix_text; /* owned; empty without a fix */
} MsCheckDiag;

MS_LIST_DEFINE(MsCheckDiagList, ms_check_diag_list, MsCheckDiag)

/* A standard function or method whose body lazy_std.c set aside, until something reaches it. */
typedef struct MsDeferredBody {
  uint32_t module;
  uint32_t node;      /* the function's or method's id */
  MsDecl *decl;       /* the function, or the impl that holds the method */
  MsMethod *method;   /* NULL for a function */
  MsStmts body;
  bool restored;
} MsDeferredBody;

MS_LIST_DEFINE(MsDeferredBodyList, ms_deferred_body_list, MsDeferredBody)

typedef struct MsCheckProgram {
  MsArena arena;
  MsNames *names; /* borrowed */
  MsTyTable types;
  MsDefs defs;
  MsPropertyMemo properties; /* property queries in flight and answered */
  MsMethodList methods; /* every module's methods, in declaration order */
  MsMethodIndex method_index; /* methods by name and by declaring node, rebuilt as modules register theirs */
  MsSymbolList symbols; /* index 0 is unused */
  MsTyList symbol_vars; /* the type variables of every symbol, by range */
  MsModuleList modules;
  MsCheckDiagList diagnostics;
  MsLocalRecordList bindings; /* every local, parameter and loop or match variable the bodies declared */
  MsTypeRefRecordList type_refs; /* every written type of the user's modules, as resolved */
  MsPendingBoundList pending_bounds;
  MsCheckDiagList ownership; /* findings only the ownership pass reports, and only for a program that checked clean */
  MsCheckDiagList deferred; /* side-pass findings the body walk releases when it reaches their place */
  MsPendingDefaultList pending_defaults;
  uint8_t stage;       /* the MsCheckStage the driver is in; stamps what is reported next */
  uint32_t serial; /* counter behind unique symbol ids */
  bool check_std; /* the bundled standard modules report their diagnostics too */
  const struct MsStdCache *std_cache; /* parsed bundled modules to reuse, or NULL: names then layer over its names */
  bool all_std;   /* load every bundled standard module, not only the imported ones (`ms check --std`) */
  bool lazy_std;  /* standard bodies are checked only once reached (lazy_std.c): the program is analyzed, never lowered */
  MsDeferredBodyList deferred_bodies;
  MsMethodKeyList deferred_index; /* the deferred bodies by (module, node), sorted */
  uint32_t user_modules; /* the first modules are the graph's; the rest are bundled standard modules */
} MsCheckProgram;

void ms_check_program_init(MsCheckProgram *program, MsNames *names);
void ms_check_program_free(MsCheckProgram *program);

/* Adds a module and returns its index. */
uint32_t ms_check_add_module(MsCheckProgram *program, MsName file, const MsModule *tree);

/* Records a diagnostic at `pos` of `module`. */
void ms_check_report(MsCheckProgram *program, uint32_t module, MsPos pos, MsCheckPhase phase,
                     MsString message);

/* Gives the last diagnostic the end of its range. */
void ms_check_attach_end(MsCheckProgram *program, MsPos end);

/* Attaches a repairing edit to the last diagnostic: replace [pos, end) with `replacement` (taken). */
void ms_check_attach_fix(MsCheckProgram *program, MsPos pos, MsPos end, MsString replacement);

/* Declares a module's own types, functions, constants and aliases in its scope (a duplicate name is a
 * resolution diagnostic). Impl and test declarations declare nothing. */
void ms_check_declare(MsCheckProgram *program, uint32_t module);

/* The name a declaration binds in its module scope; false for an impl or a test. */
bool ms_check_declared_name(const MsDecl *decl, MsName *name);

/* The type parameters a declaration writes (none for a constant, an impl or a test). */
MsTypeParams ms_check_decl_type_params(const MsDecl *decl);

/* A fresh name for a symbol or variable, unique across the program (`<prefix><serial>`). */
MsName ms_check_unique_id(MsCheckProgram *program, const char *prefix);

/* Gives each type-like and generic declaration of `module` its type variables, and a nominal type that
 * carries them as arguments. */
void ms_check_type_variables(MsCheckProgram *program, uint32_t module);

/* Whether a type parameter may not take `name`: it is a primitive or one of the reserved prelude interfaces. */
bool ms_check_intrinsic_type_param(const MsCheckProgram *program, MsName name);

/* Reports a type parameter that repeats a name or takes an intrinsic one. */
void ms_check_report_type_param(MsCheckProgram *program, uint32_t module, const MsTypeParam *param);

/* Resolves the bounds and defaults of the module's type variables, then the signatures of its types and
 * functions into checked types. Unknown type names are reported for the program's own modules. */
void ms_check_signatures(MsCheckProgram *program, uint32_t module);

/* Loads every bundled standard module the program's modules import, transitively, as further modules. */
void ms_check_load_std(MsCheckProgram *program);

/* Whether `path` names a bundled module (`@std/<name>`); *name is what follows the prefix. */
bool ms_check_std_path(MsSpan path, MsSpan *name);

/* Whether `module` is part of the standard library: a bundled module, or an editor's copy of one. It has the library's
 * privileges (prelude names, native declarations, intrinsic receivers) that project code lacks. */
static inline bool ms_check_is_std(const MsCheckProgram *program, uint32_t module) {
  return module >= program->user_modules || program->modules.ptr[module].bundled;
}

/* Explains the imports of `module` that name nothing usable, and the redundant prelude imports. */
/* Rejects declarations whose recursive generic applications change their type arguments. */
void ms_check_finite_types(MsCheckProgram *program);
/* The same for generic functions and types followed through the calls in their bodies; runs after the bodies. */
void ms_check_finite_functions(MsCheckProgram *program);

void ms_check_report_imports(MsCheckProgram *program, uint32_t module, MsSpan source);

/* Binds each import of `module` to the exported symbol it names (declare must have run on every module). */
/* Whether `name` declared in the bundled module `file` (`@std/core.ms`) is a prelude name. */
bool ms_check_is_prelude_declaration(MsSpan file, MsSpan name);
/* Whether `symbol` is a prelude declaration, which every module sees under its own name. */
bool ms_check_is_prelude_symbol(const MsCheckProgram *program, const MsSymbol *symbol);

/* Moves the diagnostics from index `from` on aside until the body walk reaches the place they are about. */
void ms_check_defer(MsCheckProgram *program, size_t from);

/* Returns the deferred diagnostic of `module` at `offset` whose message starts with `prefix` to the list, in walk
 * order; false when there is none. */
bool ms_check_release(MsCheckProgram *program, uint32_t module, uint32_t offset, MsSpan prefix);

/* Returns whatever the walk did not reach, as the side pass found it. */
void ms_check_release_rest(MsCheckProgram *program);

void ms_check_bind_imports(MsCheckProgram *program, uint32_t module);



/* The entry point of the checker: checks every module of `graph` in order and leaves the diagnostics in
 * `program` (resolution and type phases, in the order the oracle reports them). `graph` and `names` must
 * outlive `program`. Passes are added as they land; a program is accepted only when `program->diagnostics`
 * is empty. */
void ms_check_graph(MsCheckProgram *program, MsNames *names, const MsGraph *graph);
/* The same reusing `cache`'s parsed standard modules; `names` must be layered over the cache's names. */
void ms_check_graph_cached(MsCheckProgram *program, MsNames *names, const MsGraph *graph, const struct MsStdCache *cache);
/* The same for a program that is only analyzed (check, lint, the language server): the bodies of bundled standard
 * functions nothing in it reaches are not checked. Its facts must not be lowered. */
void ms_check_graph_analysis(MsCheckProgram *program, MsNames *names, const MsGraph *graph);
/* The eager check over every bundled standard module: the gate that every bundled body checks. */
void ms_check_graph_std(MsCheckProgram *program, MsNames *names, const MsGraph *graph);

#endif
