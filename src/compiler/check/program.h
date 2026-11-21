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
  const MsDecl *decl;
} MsSymbol;

MS_LIST_DEFINE(MsSymbolList, ms_symbol_list, MsSymbol)
MS_MAP_DEFINE(MsScope, ms_scope, uint32_t, MsSymbolId, ms_hash_u32_key, ms_equal_u32_key)

/* One loaded module: its tree, its file name and its scope of module-level names. */
typedef struct MsModuleInfo {
  MsName file; /* the name the file is reported under */
  const MsModule *tree;
  MsScope scope;      /* owned: name -> symbol id */
  MsFacts facts;
} MsModuleInfo;

MS_LIST_DEFINE(MsModuleList, ms_module_list, MsModuleInfo)

typedef enum MsCheckPhase { MS_CHECK_RESOLUTION, MS_CHECK_TYPE } MsCheckPhase;

typedef struct MsCheckDiag {
  uint32_t module;
  MsPos pos;
  MsCheckPhase phase;
  MsString message; /* owned */
} MsCheckDiag;

MS_LIST_DEFINE(MsCheckDiagList, ms_check_diag_list, MsCheckDiag)

typedef struct MsCheckProgram {
  MsArena arena;
  MsNames *names; /* borrowed */
  MsTyTable types;
  MsDefs defs;
  MsSymbolList symbols; /* index 0 is unused */
  MsModuleList modules;
  MsCheckDiagList diagnostics;
  uint32_t serial; /* counter behind unique symbol ids */
} MsCheckProgram;

void ms_check_program_init(MsCheckProgram *program, MsNames *names);
void ms_check_program_free(MsCheckProgram *program);

/* Adds a module and returns its index. */
uint32_t ms_check_add_module(MsCheckProgram *program, MsName file, const MsModule *tree);

/* Records a diagnostic at `pos` of `module`. */
void ms_check_report(MsCheckProgram *program, uint32_t module, MsPos pos, MsCheckPhase phase,
                     MsString message);

/* Declares a module's own types, functions, constants and aliases in its scope (a duplicate name is a
 * resolution diagnostic). Impl and test declarations declare nothing. */
void ms_check_declare(MsCheckProgram *program, uint32_t module);


/* The entry point of the checker: checks every module of `graph` in order and leaves the diagnostics in
 * `program` (resolution and type phases, in the order the oracle reports them). `graph` and `names` must
 * outlive `program`. Passes are added as they land; a program is accepted only when `program->diagnostics`
 * is empty. */
void ms_check_graph(MsCheckProgram *program, MsNames *names, const MsGraph *graph);

#endif
