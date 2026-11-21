/* Name resolution of a module's top level: what its code can name before any body is read.
 *
 * `ms_module_declare` fills `MsModuleRow.names` with the primitives, the prelude, the module's
 * imports and its own declarations, and appends to `MsModuleRow.diags` what is wrong with them
 * (a declaration that reuses a prelude name, two imports of one name, an import the standard
 * library cannot satisfy). The Rust checker's `begin_module`, `import_symbols` and
 * `declare_symbols`. */
#ifndef MS_CHECK_H
#define MS_CHECK_H

#include "ms/tables.h"
#include "ms/text.h"

/* The row of the module with this path, or MS_NONE. */
MsModId ms_module_find(const MsCheck *c, MsSym path);

/* The project modules `module`'s imports name: `targets[i]` is the row of what `syntax->imports[i]`
 * imports, or MS_NONE for a standard-library import. The array has `nimports` entries and must outlive
 * the checker; call before `ms_module_declare`. Port of the Rust `ImportMap`. */
void ms_module_set_imports(MsCheck *c, MsModId module, const MsModId *targets);

/* Declares the module's names once; later calls do nothing. Imports of `@std/` modules declare
 * the source module they read first. Imports of other modules are not resolved yet and leave no
 * name behind. */
void ms_module_declare(MsCheck *c, MsModId module);

/* ---- declared types ---- */

/* Appends a diagnostic to the module's list, unless the checker's suppression rules drop it. */
void ms_report(MsCheck *c, MsModId module, const MsCheckDiag *diag);

/* Whether `sym` is `print` or a prelude type: a declaration every module sees. */
bool ms_is_prelude_symbol(const MsCheck *c, MsSymId sym);

/* The type variables in scope while a written type resolves, innermost scope first. */
typedef struct MsTypeScope {
    const struct MsTypeScope *parent;
    const MsSym *names;
    const MsTy *types;
    uint32_t len;
} MsTypeScope;

/* Whether `name` is a type variable of `scope` or of an enclosing one. */
static inline bool ms_type_scope_has(const MsTypeScope *scope, MsSym name) {
    for (; scope != NULL; scope = scope->parent) {
        for (uint32_t i = 0; i < scope->len; i++) {
            if (scope->names[i] == name) {
                return true;
            }
        }
    }
    return false;
}

/* Whether the interned name `name` spells `text`. */
static inline bool ms_name_is(const MsNames *names, MsSym name, const char *text) {
    return ms_text_is(ms_name(names, name), text);
}

/* The type of the primitive called `name`, or MS_TY_NONE. */
static inline MsTy ms_check_primitive(const MsCheck *c, const char *name) {
    const MsSymId sym = ms_map_get(&c->primitives, ms_intern_cstr(c->names, name));
    return sym == MS_NONE ? MS_TY_NONE : c->syms.ty[sym];
}

/* The `<invalid>` type a diagnostic leaves behind. */
static inline MsTy ms_check_invalid_ty(MsCheck *c) {
    const MsSym name = ms_intern_cstr(c->names, "<invalid>");
    const MsTyDesc desc = {.name = name, .id = name, .kind = MS_K_INVALID};
    return ms_ty_intern(&c->tys, &desc);
}

/* Whether `d` makes a nominal type: a type, an enum or an interface. */
static inline bool ms_decl_is_nominal(const MsDecl *d) {
    return d->kind == MS_D_TYPE || d->kind == MS_D_ENUM || d->kind == MS_D_INTERFACE;
}

/* The kind of symbol a declaration registers. */
static inline MsSymKind ms_decl_symbol_kind(const MsDecl *d) {
    if (ms_decl_is_nominal(d)) {
        return MS_SYM_TYPE;
    }
    return d->kind == MS_D_ALIAS ? MS_SYM_ALIAS : MS_SYM_FN;
}

/* Resolves the written types of one module: a context that the resolution functions share. */
typedef struct MsResolver {
    MsCheck *c;
    MsModId module;
    const MsTypeScope *scope;
    MsTy *refs; /* by node id: what each resolved type reference means */
    bool allow_type_set;
    MsSymId *aliases; /* the aliases being resolved, innermost last */
    uint32_t naliases, aliases_cap;
} MsResolver;

/* What a written type means in the resolver's scope; `<invalid>` after a diagnostic. NULL is
 * `<invalid>` without one. */
MsTy ms_resolve_type(MsResolver *r, const MsTypeRef *t);

/* The generic type `base` applied to `args`. */
MsTy ms_ty_apply(MsCheck *c, MsTy base, const MsTy *args, uint32_t nargs);

/* A parameter, field or payload list: the types resolved, duplicate names reported. */
MsTyParam *ms_resolve_params(MsResolver *r, const MsParams *params);

/* The function type of a signature. */
MsTy ms_resolve_signature(MsResolver *r, const MsParams *params, const MsTypeRef *result);

/* The variables a type-parameter list declares for `owner`; duplicates and intrinsic names are
 * reported. */
MsTy *ms_declare_type_variables(MsResolver *r, MsSymId owner, const MsTypeParams *params);

/* Resolves each default type argument (the earlier variables are in scope) and attaches it. */
void ms_resolve_type_defaults(MsResolver *r, const MsTypeParams *params, const MsTy *vars);

/* Resolves each bound and attaches the interfaces; the variables are in scope. */
void ms_resolve_type_bounds(MsResolver *r, const MsTypeParams *params, const MsTy *vars);

/* A scope holding exactly `vars`, allocated in the checker's arena. */
const MsTypeScope *ms_variable_scope(MsCheck *c, const MsTy *vars, uint32_t count);

/* The type an alias names, over its own variables; resolved once. */
MsTy ms_alias_target(MsResolver *r, MsSymId alias);

/* The variables a symbol declares. */
const MsTy *ms_sym_vars(const MsCheck *c, MsSymId sym, uint32_t *count);

/* Declares and resolves the module's top-level types: type variables with their defaults and
 * bounds, nominal types, aliases, and the signatures, fields and cases of declarations. Constants
 * and the operations of interfaces and implementations come with the passes that read bodies. */
void ms_module_resolve_types(MsCheck *c, MsModId module);

/* The symbol `d` declared in the module, unless a duplicate name took its place; MS_NONE then. */
MsSymId ms_decl_own_symbol(const MsCheck *c, MsModId module, const MsDecl *d);

/* Checks the bodies of the module's functions, after `ms_module_resolve_types`. A function is
 * checked only when every construct in it is one the pass supports so far (see check_body.c);
 * for the others no fact is written. Fills `expr_ty`, `res_kind`/`res_ref`, `pattern_binding`,
 * `bindings` and `body_checked` of the module's facts for the checked ones. */
void ms_module_check_bodies(MsCheck *c, MsModId module);
/* The same with the program's method table (`ms_module_add_implementations` has run for every
 * module that declares impls): method calls and interface calls are checked too. */
struct MsMethodTable;
void ms_module_check_bodies_with(MsCheck *c, MsModId module, struct MsMethodTable *methods);

/* Reports the locals and match payloads of the checked functions that nothing reads (`unused.rs`).
 * Like the Rust pass it reports only for a module with no other diagnostic, and it exempts names
 * that begin with `_`. Call after ms_module_check_bodies (and the ownership pass). */
void ms_module_check_unused(MsCheck *c, MsModId module);

#endif

/* Called with the source line of each construct the body checker gives up on (first one per function);
 * a tool sets it to rank what keeps functions with the Rust checker. */
extern void (*ms_body_decline_hook)(const char *file, int line);
