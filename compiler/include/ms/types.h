/* Checked types: one table of interned type constructors, a struct of arrays indexed by MsTy.
 * Mirrors the Rust checker's TyTable (crates/ms-check/src/tytable.rs) but is the only
 * representation: there is no tree of reference-counted types. Two structurally equal types get
 * the same MsTy, so type identity is an integer compare. */
#ifndef MS_TYPES_H
#define MS_TYPES_H

#include "ms/base.h"

typedef uint32_t MsTy; /* index into one MsTyTable; MS_TY_NONE is "no type" */
#define MS_TY_NONE 0u

/* Same order as `Kind` in types.rs. */
typedef enum MsKind {
    MS_K_PRIMITIVE, MS_K_INVALID, MS_K_INFERRED, MS_K_VARIABLE, MS_K_TYPE, MS_K_ALTERNATIVE,
    MS_K_CONTRACT, MS_K_FUNCTION, MS_K_NATIVE
} MsKind;
const char *ms_kind_str(MsKind k);

/* Standard types the compiler gives a native meaning; same set as `Builtin` in types.rs. */
typedef enum MsBuiltin {
    MS_B_NONE,
    MS_BI_OPTIONAL, MS_BI_RESULT, MS_BI_LIST, MS_BI_MAP, MS_BI_SET, MS_BI_BYTES, MS_BI_BIGINT,
    MS_BI_DECIMAL, MS_BI_ERROR, MS_BI_CLOSEABLE, MS_BI_HASHABLE, MS_BI_STRINGABLE,
    MS_BI_COMPARABLE, MS_BI_EQUAL, MS_BI_DATA, MS_BI_CLONABLE, MS_BI_ITERATOR,
    MS_BI_BYTESBUILDER, MS_BI_REGEX, MS_BI_TYPESET, MS_BI_SELF,
    MS_BI_INT, MS_BI_INT8, MS_BI_INT16, MS_BI_INT32, MS_BI_INT64, MS_BI_UINT8, MS_BI_UINT16,
    MS_BI_UINT32, MS_BI_UINT64, MS_BI_FLOAT, MS_BI_FLOAT32, MS_BI_FLOAT64, MS_BI_BOOL,
    MS_BI_STRING, MS_BI_VOID, MS_BI_NEVER, MS_BI_TIMESTAMP, MS_BI_INSTANT, MS_BI_DURATION,
    MS_BI_URL, MS_BI_IPADDRESS, MS_BI_CIDR, MS_BI_JSONVALUE, MS_BI_JSONENCODE, MS_BI_PROMISE,
    MS_BI_TASKGROUP, MS_BI_TESTHOOKS,
    MS_BUILTIN_COUNT
} MsBuiltin;

size_t ms_primitive_count(void);              /* the primitive types, the one list every pass reads */
const char *ms_primitive_name(size_t index);  /* `Bool`, `Int`, ...: in the order a scope declares them */
MsBuiltin ms_builtin_primitive(MsStr name);       /* `Int`, `String`, ...; MS_B_NONE otherwise */
MsBuiltin ms_builtin_from_id(MsStr id);           /* `@std/List`, ...; MS_B_NONE otherwise */
MsBuiltin ms_builtin_source(MsStr module, MsStr name); /* `@std/time.ms` + `Duration`, ... */
bool ms_builtin_is_int(MsBuiltin b);
bool ms_builtin_is_float(MsBuiltin b);

/* A function parameter, a field or a case payload slot. */
enum { MS_PARAM_VAR = 1, MS_PARAM_MOVE = 2, MS_PARAM_POSITIONAL = 4 };
typedef struct MsTyParam {
    MsSym name;
    MsTy ty;
    uint8_t flags;
} MsTyParam;

/* What a caller describes a type with. Arrays are copied into the table. */
typedef struct MsTyDesc {
    MsSym name; /* display name */
    MsSym id;   /* identity */
    MsKind kind;
    MsBuiltin builtin;
    uint32_t def; /* nominal definition index, 0 for none (see MsDefs) */
    const MsTy *args;
    uint32_t nargs;
    const MsTyParam *params; /* function parameters */
    uint32_t nparams;
    MsTy result; /* function result */
} MsTyDesc;

typedef struct MsTyTable {
    MsArena arena;
    /* one column per field; row 0 is the "no type" row */
    MsSym *name, *id;
    uint8_t *kind, *builtin;
    uint32_t *def;
    uint32_t *args_at, *nargs; /* into args_pool */
    uint32_t *params_at, *nparams; /* into params_pool */
    MsTy *result;
    uint32_t count, cap;
    MsTy *args_pool;
    uint32_t args_len, args_cap;
    MsTyParam *params_pool;
    uint32_t params_len, params_cap;
    uint32_t *slots; /* open addressed: row + 1, 0 for empty */
    uint32_t mask;
} MsTyTable;

void ms_tys_init(MsTyTable *t);
void ms_tys_free(MsTyTable *t);
/* The type with this structure: an existing one, or a new row. */
MsTy ms_ty_intern(MsTyTable *t, const MsTyDesc *d);
/* A type no other type equals (a type variable). `id` must still be unique per variable. */
MsTy ms_ty_fresh(MsTyTable *t, const MsTyDesc *d);

static inline MsKind ms_ty_kind(const MsTyTable *t, MsTy ty) { return (MsKind)t->kind[ty]; }
static inline MsBuiltin ms_ty_builtin(const MsTyTable *t, MsTy ty) { return (MsBuiltin)t->builtin[ty]; }
static inline bool ms_ty_is(const MsTyTable *t, MsTy ty, MsBuiltin b) { return t->builtin[ty] == b; }
static inline const MsTy *ms_ty_args(const MsTyTable *t, MsTy ty) { return t->args_pool + t->args_at[ty]; }
static inline const MsTyParam *ms_ty_params(const MsTyTable *t, MsTy ty) {
    return t->params_pool + t->params_at[ty];
}

/* Appends the type as source reads it (`Int?`, `List[Int]`, `fn(var Int) Void`), at most 64 nodes
 * deep and wide in total, then `…`, as the Rust checker's display does. */
void ms_ty_show(MsBuf *out, const MsNames *names, const MsTyTable *t, MsTy ty);

/* Type variables bound to types: `vars[i]` is replaced by `args[i]`. A variable is matched by id,
 * as the Rust checker's substitution does. */
typedef struct MsTySubst {
    const MsTy *vars;
    const MsTy *args;
    uint32_t count;
} MsTySubst;

/* `ty` with every bound variable replaced, through arguments, parameters and results; `ty` itself
 * when nothing changes. New types are interned in `t`; `scratch` holds the temporary lists. The
 * recursion is as deep as the type, which the checker keeps within MS_MAX_NESTING. */
MsTy ms_ty_subst(MsTyTable *t, MsArena *scratch, MsTy ty, const MsTySubst *subst);

#endif
