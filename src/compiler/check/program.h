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
} MsModuleInfo;

MS_LIST_DEFINE(MsModuleList, ms_module_list, MsModuleInfo)

typedef enum MsCheckPhase { MS_CHECK_RESOLUTION, MS_CHECK_TYPE } MsCheckPhase;

typedef struct MsCheckDiag {
  uint32_t module;
  MsPos pos;
  MsCheckPhase phase;
  MsString message; /* owned */
  bool has_fix;     /* an edit that repairs the diagnostic: replace [fix_pos, fix_end) with `fix_text` */
  MsPos fix_pos, fix_end;
  MsString fix_text; /* owned; empty without a fix */
} MsCheckDiag;

MS_LIST_DEFINE(MsCheckDiagList, ms_check_diag_list, MsCheckDiag)

typedef struct MsCheckProgram {
  MsArena arena;
  MsNames *names; /* borrowed */
  MsTyTable types;
  MsDefs defs;
  MsPropertyMemo properties; /* property queries in flight and answered */
  MsMethodList methods; /* every module's methods, in declaration order */
  MsSymbolList symbols; /* index 0 is unused */
  MsTyList symbol_vars; /* the type variables of every symbol, by range */
  MsModuleList modules;
  MsCheckDiagList diagnostics;
  uint32_t serial; /* counter behind unique symbol ids */
  uint32_t user_modules; /* the first modules are the graph's; the rest are bundled standard modules */
} MsCheckProgram;

void ms_check_program_init(MsCheckProgram *program, MsNames *names);
void ms_check_program_free(MsCheckProgram *program);

/* Adds a module and returns its index. */
uint32_t ms_check_add_module(MsCheckProgram *program, MsName file, const MsModule *tree);

/* Records a diagnostic at `pos` of `module`. */
void ms_check_report(MsCheckProgram *program, uint32_t module, MsPos pos, MsCheckPhase phase,
                     MsString message);

/* Attaches a repairing edit to the last diagnostic: replace [pos, end) with `replacement` (taken). */
void ms_check_attach_fix(MsCheckProgram *program, MsPos pos, MsPos end, MsString replacement);

/* Declares a module's own types, functions, constants and aliases in its scope (a duplicate name is a
 * resolution diagnostic). Impl and test declarations declare nothing. */
void ms_check_declare(MsCheckProgram *program, uint32_t module);

/* The type parameters a declaration writes (none for a constant, an impl or a test). */
MsTypeParams ms_check_decl_type_params(const MsDecl *decl);

/* A fresh name for a symbol or variable, unique across the program (`<prefix><serial>`). */
MsName ms_check_unique_id(MsCheckProgram *program, const char *prefix);

/* Gives each type-like and generic declaration of `module` its type variables, and a nominal type that
 * carries them as arguments. */
void ms_check_type_variables(MsCheckProgram *program, uint32_t module);

/* Resolves the bounds and defaults of the module's type variables, then the signatures of its types and
 * functions into checked types. Unknown type names are reported for the program's own modules. */
void ms_check_signatures(MsCheckProgram *program, uint32_t module);

/* Loads every bundled standard module the program's modules import, transitively, as further modules. */
void ms_check_load_std(MsCheckProgram *program);

/* Binds each import of `module` to the exported symbol it names (declare must have run on every module). */
void ms_check_bind_imports(MsCheckProgram *program, uint32_t module);



/* The entry point of the checker: checks every module of `graph` in order and leaves the diagnostics in
 * `program` (resolution and type phases, in the order the oracle reports them). `graph` and `names` must
 * outlive `program`. Passes are added as they land; a program is accepted only when `program->diagnostics`
 * is empty. */
void ms_check_graph(MsCheckProgram *program, MsNames *names, const MsGraph *graph);

#endif
