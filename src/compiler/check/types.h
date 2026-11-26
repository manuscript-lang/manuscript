/* compiler/check/types.h: checked types, the vocabulary the checker, ownership and lowering share.
 *
 * A type is a MsTy, a dense id into one MsTyTable. The table interns structure: two types with the same
 * identity name, kind, parameters, result and arguments are the same MsTy, so type equality is an integer
 * compare and a type is usable as an array index or a map key. Rows are never removed and ids never change.
 * MS_TY_NONE (0) is "no type"; it reads as an invalid type.
 *
 * What the identity leaves out, by design: the display name (the first row to reach an identity keeps its
 * name), the parameter labels, and the built-in tag. A function parameter's flags (var, move, positional,
 * lifted) are part of the identity; `ms_ty_shape` interns the same structure with the lifted flags cleared.
 *
 * What a nominal type holds beyond that lives in MsDefs (fields, cases, interface operations, declared
 * variables) and a type variable's bounds and default in MsTyTable.variables, both filled in after the
 * type exists, as signatures resolve. A row's `def` indexes the one that applies to its kind.
 *
 * Ownership: the table owns its rows and pools; a pointer or span returned by an accessor is valid until
 * the next intern. Display and substitution allocate nothing outside the table. */
#ifndef MS_COMPILER_CHECK_TYPES_H
#define MS_COMPILER_CHECK_TYPES_H

#include "base/arena.h"
#include "base/intern.h"
#include "base/list.h"
#include "base/safe.h"
#include "base/strbuild.h"

typedef uint32_t MsTy;
#define MS_TY_NONE ((MsTy)0)

/* The kind of a type. */
typedef enum MsTyKind {
  MS_TY_PRIMITIVE,   /* `Int`, `Bool`, ... */
  MS_TY_INVALID,     /* the `<invalid>` marker of an unresolved or erroneous type */
  MS_TY_INFERRED,    /* the `<inferred>` placeholder of a result not yet known */
  MS_TY_VARIABLE,    /* a type parameter */
  MS_TY_TYPE,        /* `type T { ... }` with fields */
  MS_TY_ALTERNATIVE, /* `enum T { ... }` with cases */
  MS_TY_CONTRACT,    /* an interface */
  MS_TY_FUNCTION,    /* a function type */
  MS_TY_NATIVE       /* an opaque runtime-implemented type */
} MsTyKind;

/* The source spelling of a kind: "primitive", "invalid", ... */
const char *ms_ty_kind_name(MsTyKind kind);

typedef enum MsBuiltin {
  MS_BUILTIN_NONE = 0,
#define MS_BUILTIN(id, origin, module, text) MS_BUILTIN_##id,
#include "compiler/check/builtins.def"
#undef MS_BUILTIN
  MS_BUILTIN_COUNT
} MsBuiltin;

/* The text of a built-in: `Int`, `List`, `Self` for the marker. */
const char *ms_builtin_name(MsBuiltin builtin);

/* The primitive spelled `name`, or MS_BUILTIN_NONE. */
MsBuiltin ms_builtin_primitive(MsSpan name);

/* The standard type whose type id is `id` (`@std/List`), or MS_BUILTIN_NONE. */
MsBuiltin ms_builtin_from_id(MsSpan id);

/* The type `name` declared by the bundled module `module` that has a native layout, or MS_BUILTIN_NONE. */
MsBuiltin ms_builtin_source(MsSpan module, MsSpan name);

bool ms_builtin_is_int(MsBuiltin builtin);
bool ms_builtin_is_float(MsBuiltin builtin);

/* Flags of a function parameter; none apply to a field. */
enum {
  MS_PARAM_VAR = 1,        /* the callee changes the caller's variable in place */
  MS_PARAM_MOVE = 2,       /* the callee takes ownership of the argument */
  MS_PARAM_POSITIONAL = 4, /* a written function type's parameter, passed without a label */
  MS_PARAM_LIFTED = 8      /* an omittable parameter a function value passes as an optional */
};

/* A parameter, a field or a case payload slot. */
typedef struct MsTyParam {
  MsName name;
  MsTy ty;
  uint8_t flags;
} MsTyParam;

MS_LIST_DEFINE(MsTyList, ms_ty_list, MsTy)
MS_LIST_DEFINE(MsTyParamList, ms_ty_param_list, MsTyParam)
MS_LIST_DEFINE(MsWordList, ms_word_list, uint32_t)

/* What a caller describes a type with; the arrays are copied into the table. */
typedef struct MsTyDesc {
  MsName name; /* display name */
  MsName id;   /* identity */
  MsTyKind kind;
  MsBuiltin builtin;
  uint32_t def; /* the MsDefs index of a nominal type, the variables index of a variable, else 0 */
  const MsTy *args;
  uint32_t arg_count;
  const MsTyParam *params;
  uint32_t param_count;
  MsTy result; /* function result; MS_TY_NONE while unknown */
} MsTyDesc;

/* One interned type. */
typedef struct MsTyRow {
  MsName name;
  MsName id;
  uint8_t kind;    /* MsTyKind */
  uint8_t builtin; /* MsBuiltin */
  bool open;       /* mentions a type variable: itself, or through arguments, parameters or result */
  uint32_t def;
  uint32_t args_at;
  uint32_t arg_count;
  uint32_t params_at;
  uint32_t param_count;
  MsTy result;
} MsTyRow;

MS_LIST_DEFINE(MsTyRowList, ms_ty_row_list, MsTyRow)

/* A type variable's bounds and default, filled in after the variable exists. */
typedef struct MsTyVariable {
  MsTyList bounds; /* owned */
  MsTy default_ty; /* MS_TY_NONE when it has none */
} MsTyVariable;

MS_LIST_DEFINE(MsTyVariableList, ms_ty_variable_list, MsTyVariable)

typedef struct MsTyTable {
  MsNames keys;              /* owned: the packed structure of each row; the key id is the row number */
  MsTyRowList rows;          /* owned: row 0 is "no type" */
  MsTyList args_pool;        /* owned */
  MsTyParamList params_pool; /* owned */
  MsTyVariableList variables; /* owned: index 0 is unused */
  MsWordList key_words;      /* owned scratch: the key being built */
  MsTyList scratch;          /* owned scratch: substitution */
  MsTyParamList param_scratch; /* owned scratch: parameters being rebuilt */
} MsTyTable;

/* Starts a table holding only row 0. */
void ms_tys_init(MsTyTable *table);
void ms_tys_free(MsTyTable *table);

/* The type with this structure: the existing row, or a new one. */
MsTy ms_ty_intern(MsTyTable *table, const MsTyDesc *desc);

/* The same structure with every parameter's lifted flag cleared. */
MsTy ms_ty_shape(MsTyTable *table, MsTy ty);

/* A new type variable named `name` whose identity is `id` (unique per variable); its bounds and default
 * start empty. */
MsTy ms_ty_variable_new(MsTyTable *table, MsName name, MsName id);

static inline const MsTyRow *ms_ty_row(const MsTyTable *table, MsTy ty) {
  return &table->rows.ptr[ty < table->rows.len ? ty : 0];
}

static inline MsTyKind ms_ty_kind(const MsTyTable *table, MsTy ty) {
  return (MsTyKind)ms_ty_row(table, ty)->kind;
}

static inline MsBuiltin ms_ty_builtin(const MsTyTable *table, MsTy ty) {
  return (MsBuiltin)ms_ty_row(table, ty)->builtin;
}

static inline bool ms_ty_is(const MsTyTable *table, MsTy ty, MsBuiltin builtin) {
  return ms_ty_row(table, ty)->builtin == (uint8_t)builtin;
}

static inline bool ms_ty_is_invalid(const MsTyTable *table, MsTy ty) {
  return ms_ty_kind(table, ty) == MS_TY_INVALID;
}

static inline bool ms_ty_has_variable(const MsTyTable *table, MsTy ty) {
  return ms_ty_row(table, ty)->open;
}

static inline size_t ms_ty_arg_count(const MsTyTable *table, MsTy ty) {
  return ms_ty_row(table, ty)->arg_count;
}

static inline const MsTy *ms_ty_args(const MsTyTable *table, MsTy ty) {
  return table->args_pool.ptr + ms_ty_row(table, ty)->args_at;
}

static inline size_t ms_ty_param_count(const MsTyTable *table, MsTy ty) {
  return ms_ty_row(table, ty)->param_count;
}

static inline const MsTyParam *ms_ty_params(const MsTyTable *table, MsTy ty) {
  return table->params_pool.ptr + ms_ty_row(table, ty)->params_at;
}

static inline MsTy ms_ty_result(const MsTyTable *table, MsTy ty) {
  return ms_ty_row(table, ty)->result;
}

/* The variable record of a type variable; NULL for any other type. */
MsTyVariable *ms_ty_variable(MsTyTable *table, MsTy ty);

/* Appends `ty` as source reads it (`Int?`, `List[Int]`, `fn(var Int) Void`). At most 64 type nodes are
 * written; the rest of a larger type is `…`. */
void ms_ty_show(MsStrBuild *out, const MsNames *names, const MsTyTable *table, MsTy ty);
/* The same text with every type named in full (`Result[T, Error]`): lowering keys runtime type names on it. */
void ms_ty_show_canonical(MsStrBuild *out, const MsNames *names, const MsTyTable *table, MsTy ty);

/* `ty` with each variable `vars[i]` replaced by `args[i]`, through arguments, parameters and results; `ty`
 * itself when nothing changes. Variables match by identity. New types are interned in the table. */
MsTy ms_ty_subst(MsTyTable *table, MsTy ty, const MsTy *vars, const MsTy *args, size_t count);

/* ---- nominal definitions ---- */

/* One case of an alternative: its name and payload slots. */
typedef struct MsTyCase {
  MsName name;
  MsTyParamList fields; /* owned */
} MsTyCase;

MS_LIST_DEFINE(MsTyCaseList, ms_ty_case_list, MsTyCase)

/* A declaration inside a loaded file: the file's index and a node id in its syntax tree. */
typedef struct MsDeclRef {
  uint32_t file;
  uint32_t node;
} MsDeclRef;

/* An interface or native operation: its name, signature and declaration. `variables` are the operation's own
 * type parameters, with their bounds and defaults. */
typedef struct MsOperation {
  MsName name;
  MsTy ty;
  MsDeclRef decl;
  MsTyList variables; /* owned */
} MsOperation;

MS_LIST_DEFINE(MsOperationList, ms_operation_list, MsOperation)

/* A nominal type definition, owned by the type's symbol. */
typedef struct MsDef {
  MsTyKind kind; /* type, alternative, contract or native */
  uint32_t symbol;
  MsTyList variables;       /* owned: declared type variables */
  MsTyParamList fields;     /* owned */
  MsTyCaseList cases;         /* owned */
  MsOperationList operations; /* owned */
} MsDef;

typedef struct MsDefs {
  MsArena arena;    /* owned: every MsDef, so a pointer to one stays valid */
  MsDef **by_index; /* owned: index 0 is unused */
  size_t count;
  size_t capacity;
} MsDefs;

void ms_defs_init(MsDefs *defs);
void ms_defs_free(MsDefs *defs);

/* A new empty definition; returns its index (never 0). */
uint32_t ms_defs_add(MsDefs *defs, MsTyKind kind, uint32_t symbol);

/* The definition at `index`; an index never handed out reports through ms_fatal. */
MsDef *ms_defs_get(const MsDefs *defs, uint32_t index);

/* The position of the first case called `name`, or false. */
MS_NODISCARD MS_NONNULL bool ms_def_find_case(const MsDef *def, MsName name, size_t *index);

#endif
