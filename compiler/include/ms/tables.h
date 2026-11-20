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

/* ---- modules ---- */

typedef struct MsModuleRow {
    MsSym path; /* `@std/core.ms`, or a user module's path */
    const MsModule *syntax;
    MsNameMap scope; /* every symbol the module declares, by name; exported ones are those with is_exported */
    bool source;       /* has implementation bodies: checked like user code, on first import */
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
} MsCheck;

void ms_check_init(MsCheck *c, MsNames *names);
void ms_check_free(MsCheck *c);

MsModId ms_module_add(MsCheck *c, MsSym path, const MsModule *syntax);
/* Adds a symbol of `module`; exported ones also join the module's export map. Returns the new id,
 * or MS_NONE when the module already has a symbol of this name. */
MsSymId ms_sym_add(MsCheck *c, MsModId module, MsSym name, MsSym id, MsSymKind kind,
                   MsNativeKind native, MsSym native_name, bool is_exported, const MsDecl *decl,
                   uint32_t nvars);

#endif
