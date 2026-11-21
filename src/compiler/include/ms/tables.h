/* The tables every checker pass reads: name maps, symbols and modules. Rows are dense and
 * addressed by index; nothing is global. A pass adds columns of its own beside these, indexed by
 * the same ids. */
#ifndef MS_TABLES_H
#define MS_TABLES_H

#include "ms/ast.h"
#include "ms/base.h"
#include "ms/types.h"

/* ---- a map from name to a dense id: scopes, export lists, the standard-type index ---- */

typedef struct MsNameMap {
    MsSym *keys;
    uint32_t *vals; /* val + 1 so that 0 marks an empty slot */
    uint32_t count, cap;
} MsNameMap;

void ms_map_free(MsNameMap *m);
/* Inserts unless `key` is present; returns false (and leaves the old value) when it was. */
bool ms_map_add(MsNameMap *m, MsSym key, uint32_t val);
/* The value of `key`, or UINT32_MAX when absent. */
uint32_t ms_map_get(const MsNameMap *m, MsSym key);
#define MS_NONE UINT32_MAX

/* ---- symbols ---- */

typedef enum MsSymKind { MS_SYM_TYPE, MS_SYM_FN, MS_SYM_ALIAS } MsSymKind;

/* What a declaration binds to; `Native` in types.rs. */
typedef enum MsNativeKind { MS_NATIVE_SOURCE, MS_NATIVE_CONTRACT, MS_NATIVE_EXTERN, MS_NATIVE_BUILTIN } MsNativeKind;

typedef uint32_t MsSymId;
typedef uint32_t MsModId;

typedef struct MsSyms {
    MsSym *name, *id; /* id is the identity text: `@std/List`, `@std/collections/map_from_entries` */
    MsSymKind *kind;
    MsModId *module;
    MsNativeKind *native;
    MsSym *native_name; /* the builtin or extern symbol, else 0 */
    bool *is_exported;
    const MsDecl **decl; /* NULL for a primitive */
    MsTy *ty;            /* MS_TY_NONE until resolved */
    uint32_t *nvars;     /* declared type variables */
    uint32_t count, cap;
} MsSyms;

/* ---- declared types: per symbol and per type variable ---- */

typedef struct MsCaseRow {
    MsSym name;
    MsTyParam *fields;
    uint32_t nfields;
} MsCaseRow;

/* What a nominal declaration or function carries beyond its type: the type variables it declares
 * (those a native type carries as arguments of its type are not repeated), and the fields or
 * cases a `type` or `enum` resolves to. The Rust checker's `Definition`. */
typedef struct MsDef {
    MsTy *vars;
    uint32_t nvars;
    MsTyParam *fields;
    uint32_t nfields;
    MsCaseRow *cases;
    uint32_t ncases;
} MsDef;

/* Beside a type variable: its default argument and the interfaces that bound it. */
typedef struct MsVarInfo {
    MsTy def; /* MS_TY_NONE for none */
    MsTy *bounds;
    uint32_t nbounds;
} MsVarInfo;

/* ---- diagnostics ---- */

typedef enum MsPhase { MS_PHASE_RESOLUTION, MS_PHASE_TYPE, MS_PHASE_OWNERSHIP } MsPhase;

/* A checker diagnostic: the position and message, the phase that reports it, and, for an unknown
 * name, the name (which later suggestions read). */
typedef struct MsCheckDiag {
    MsDiag diag;
    MsPhase phase;
    MsSym unknown;
} MsCheckDiag;

/* ---- modules ---- */

struct MsFacts;

typedef struct MsModuleRow {
    MsSym path; /* `@std/core.ms`, or a user module's path */
    const MsModule *syntax;
    MsNameMap scope; /* every symbol the module declares, by name; exported ones are those with is_exported */
    bool source;       /* has implementation bodies: checked like user code, on first import */
    /* Name resolution (check_scope.c): everything the module's code can name at the top level --
     * primitives, the prelude, imports and its own declarations -- and what that found wrong. */
    MsNameMap names;
    MsCheckDiag *diags;
    uint32_t ndiags, diags_cap;
    MsStr text;           /* a bundled module's source (the caller keeps it alive), else empty */
    bool impls_added;     /* its impls are in the program's method table */
    const MsModId *import_targets; /* by import index: the project module it names, MS_NONE for the standard library */
    bool declared;
    bool unknown_type; /* an unknown type was reported: later `<invalid>` messages only restate it */
    struct MsFacts *facts; /* the columns the checker fills for the module; NULL until it runs */
    MsSymId *order;    /* the same symbols in declaration order */
    uint32_t norder;
} MsModuleRow;

typedef struct MsCheck {
    MsArena arena;
    MsNames *names; /* not owned */
    MsTyTable tys;
    MsSyms syms;
    MsModuleRow *mods;
    uint32_t nmods, mods_cap;
    MsNameMap std_types; /* standard type name -> symbol, as the world map of the Rust loader */
    MsSymId builtin_sym_plus_one[MS_BUILTIN_COUNT]; /* the symbol that declares each builtin type, plus one; 0 when none (ms_builtin_symbol) */
    MsNameMap module_by_path; /* module path -> module id */
    MsNameMap primitives;     /* primitive type name -> symbol; those symbols belong to no module */
    MsDef *defs;              /* by symbol id; grown on demand */
    uint32_t defs_cap;
    MsVarInfo *var_info;      /* by type id, for type variables; grown on demand */
    uint32_t var_info_cap;
    struct MsMethodTable *methods; /* the program's method table (program.h); NULL until a module is checked */
    bool std_desugared;            /* every bundled module's inherent methods are desugared (ms_program_check_module) */
} MsCheck;

void ms_check_init(MsCheck *c, MsNames *names);
void ms_check_free(MsCheck *c);

MsModId ms_module_add(MsCheck *c, MsSym path, const MsModule *syntax);
/* What a symbol is declared with; the rest of its row starts empty. */
typedef struct MsSymSpec {
    MsSym name;
    MsSym id;
    MsSymKind kind;
    MsNativeKind native;
    MsSym native_name;
    bool is_exported;
    const MsDecl *decl; /* borrowed from the module's syntax, which outlives the tables */
    uint32_t nvars;
} MsSymSpec;

/* Adds a symbol of `module`; exported ones are visible to importers. Returns the new id, or
 * MS_NONE when the module already has a symbol of this name. */
MsSymId ms_sym_add(MsCheck *c, MsModId module, const MsSymSpec *spec);

/* Appends a symbol row without listing it in any scope. `module` is MS_NONE for a primitive type,
 * which belongs to no module. */
MsSymId ms_sym_new(MsCheck *c, MsModId module, const MsSymSpec *spec);

/* The name a declaration binds (0 for an `impl` or a test) and how many type variables it declares. */
MsSym ms_decl_name(const MsDecl *d);
uint32_t ms_decl_nvars(const MsDecl *d);

/* The definition row of `sym`, created empty on first use. The pointer is valid until the next
 * call that may add a row. */
MsDef *ms_def(MsCheck *c, MsSymId sym);
/* The variable row of type variable `ty`, created empty on first use; same lifetime. */
MsVarInfo *ms_var_info(MsCheck *c, MsTy ty);

#endif
