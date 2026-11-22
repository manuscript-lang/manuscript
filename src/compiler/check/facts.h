/* compiler/check/facts.h: what the checker decided, as lowering reads it.
 *
 * One MsFacts per module (a source file), indexed by the dense node ids of that module's syntax tree
 * (compiler/syntax/ast.h). Every column has one entry per node, in node order, so a lookup is an array
 * read; a node a column does not apply to holds the zero value (MS_TY_NONE, MS_REF_NONE, ...). Calls,
 * conversions and constants are sparse and sit in side tables keyed by the node id they describe.
 *
 * Ownership: MsFacts and everything it points at is allocated from the program arena and lives as long as
 * the checked program. Lowering only reads it. */
#ifndef MS_COMPILER_CHECK_FACTS_H
#define MS_COMPILER_CHECK_FACTS_H

#include "base/intern.h"
#include "base/safe.h"
#include "compiler/check/types.h"

typedef uint32_t MsNode; /* a node id in one module's syntax tree; 0 is "no node" */

/* A node in a module of the program: the module's index and the node. */
typedef struct MsNodeRef {
  uint32_t module;
  MsNode node;
} MsNodeRef;

/* ---- 2. what a name resolves to ---- */

typedef enum MsRefKind {
  MS_REF_NONE,
  MS_REF_LOCAL,     /* a `let`/`var` binding or pattern binding: `local` is the dense local id */
  MS_REF_PARAM,     /* a parameter of the enclosing function: `local` is its index */
  MS_REF_FUNCTION,  /* a module-level function */
  MS_REF_METHOD,    /* a method of a type or an implemented interface */
  MS_REF_CONSTANT,  /* a module-level `let` */
  MS_REF_TYPE,      /* a type, alternative or interface name */
  MS_REF_CASE,      /* an alternative case: `index` is the case number */
  MS_REF_FIELD,     /* a record field: `index` is the field number */
  MS_REF_OPERATION, /* an interface operation: `index` is its position in the interface */
  MS_REF_NATIVE,    /* a bodiless standard declaration the compiler or runtime provides */
  MS_REF_MODULE     /* a module (an import alias) */
} MsRefKind;

typedef struct MsRef {
  MsRefKind kind;
  MsNodeRef decl; /* the declaration; for a native, its declaring node in the standard module */
  uint32_t local; /* local and param: the id within the enclosing function, dense from 0 */
  uint32_t index; /* case, field and operation number */
  MsTy owner;     /* method, field, case and operation: the receiver or declaring type */
} MsRef;

/* ---- 3. calls ---- */

typedef enum MsArgSource {
  MS_ARG_WRITTEN,  /* the call wrote this argument: `node` is its expression */
  MS_ARG_DEFAULT,  /* the parameter's default expression, evaluated at the call: `node` is it */
  MS_ARG_OMITTED   /* an omittable parameter left out; the value is "none" */
} MsArgSource;

/* How one parameter of the callee is filled, in parameter order. */
typedef struct MsCallArg {
  MsArgSource source;
  MsNodeRef node; /* the argument or default expression; none when omitted */
  MsName label;   /* the label written at the call, or MS_NAME_EMPTY */
  uint8_t flags;  /* MS_PARAM_VAR / MS_PARAM_MOVE of the parameter, as the call passes it */
} MsCallArg;

typedef struct MsCall {
  MsNode node; /* the call expression */
  MsRef callee;
  MsTy callee_ty;         /* the callee's type with its type arguments applied */
  const MsTy *type_args;  /* type arguments inferred or written, in declaration order */
  uint32_t type_arg_count;
  const MsCallArg *args;  /* one per callee parameter, receiver first for a method */
  uint32_t arg_count;
} MsCall;

/* ---- 4. conversions ---- */

typedef enum MsConversionKind {
  MS_CONV_INTERFACE_VIEW, /* a value seen as an interface it implements */
  MS_CONV_INT_WIDEN,      /* an integer widened to a larger integer type */
  MS_CONV_OPTIONAL_WRAP,  /* `T` to `T?` */
  MS_CONV_FUNCTION_VALUE  /* a function or lambda used as a function value */
} MsConversionKind;

/* The conversion applied to the expression `node` to give it type `to` (its own type is `from`). */
typedef struct MsConversion {
  MsNode node;
  MsConversionKind kind;
  MsTy from;
  MsTy to;
} MsConversion;

/* ---- 5. constants ---- */

typedef enum MsConstKind { MS_CONST_INT, MS_CONST_FLOAT, MS_CONST_BOOL, MS_CONST_STRING } MsConstKind;

/* A value the checker folded; the node is replaced by the constant at lowering. */
typedef struct MsConstant {
  MsNode node;
  MsConstKind kind;
  int64_t integer;  /* int and bool; floats keep their bits here */
  MsName text;      /* string: the interned text */
} MsConstant;

/* ---- 6. ownership of uses ---- */

typedef enum MsUse {
  MS_USE_NONE,
  MS_USE_BORROW, /* read or passed by borrow; the binding stays live */
  MS_USE_MOVE,   /* ownership leaves the binding: it is consumed and not dropped here */
  MS_USE_CLONE   /* `.clone()`: a new owner; the binding stays live */
} MsUse;

/* ---- 7. closers ---- */

typedef enum MsCloserFlags {
  MS_CLOSER_FALLIBLE = 1,   /* the close returns a Result: its error is the exit's outcome (first error wins) */
  MS_CLOSER_CONSUMES = 2,   /* `move fn close`: the close takes the value, nothing is left to drop */
  MS_CLOSER_WRITES_BACK = 4, /* `var fn close`: the receiver lives in memory and the close changes it */
  MS_CLOSER_EXPLICIT = 8,   /* the body also calls `.close()` on the binding by hand */
  MS_CLOSER_MOVED = 16,     /* a use moves the whole binding out of its scope */
  MS_CLOSER_PARTIAL = 32    /* a field moves out alone, or a closure captures the binding */
} MsCloserFlags;

/* How a local binding of a Closeable type is closed where its scope ends. `node` is the binding site (the
 * pattern node a MS_REF_LOCAL reference names as its `decl`), `method` the declaration of its `close` method,
 * as a METHOD callee names it. */
typedef struct MsCloser {
  MsNode node;
  MsNodeRef method;
  uint8_t flags; /* MsCloserFlags */
} MsCloser;

MS_LIST_DEFINE(MsRefList, ms_ref_list, MsRef)
MS_LIST_DEFINE(MsCallList, ms_call_list, MsCall)
MS_LIST_DEFINE(MsConversionList, ms_conversion_list, MsConversion)
MS_LIST_DEFINE(MsConstantList, ms_constant_list, MsConstant)
MS_LIST_DEFINE(MsUseList, ms_use_list, uint8_t)
MS_LIST_DEFINE(MsCloserList, ms_closer_list, MsCloser)

/* The facts of one module. The node columns have `node_count` entries. */
typedef struct MsFacts {
  uint32_t module;
  uint32_t node_count;
  MsTy *types;      /* 1. the type of each expression, pattern and parameter node, after inference */
  MsRef *refs;      /* 2. what each NAME, MEMBER and callee node resolves to */
  uint8_t *uses;    /* 6. MsUse of each use of a local */
  MsCallList calls;             /* 3. sorted by node */
  MsConversionList conversions; /* 4. sorted by node */
  MsConstantList constants;     /* 5. sorted by node */
  MsCloserList closers;         /* 7. sorted by node; filled by the ownership pass (own/closers.c) */
  uint32_t *local_counts; /* locals per function, indexed by the function declaration node id */
} MsFacts;

/* The type of `node`; MS_TY_NONE for a node that has none. */
static inline MsTy ms_facts_type(const MsFacts *facts, MsNode node) {
  return node < facts->node_count ? facts->types[node] : MS_TY_NONE;
}

static inline const MsRef *ms_facts_ref(const MsFacts *facts, MsNode node) {
  return node < facts->node_count ? &facts->refs[node] : NULL;
}

static inline MsUse ms_facts_use(const MsFacts *facts, MsNode node) {
  return node < facts->node_count ? (MsUse)facts->uses[node] : MS_USE_NONE;
}

/* The call, conversion or constant recorded for `node`, or NULL. */
const MsCall *ms_facts_call(const MsFacts *facts, MsNode node);
const MsConversion *ms_facts_conversion(const MsFacts *facts, MsNode node);
const MsConstant *ms_facts_constant(const MsFacts *facts, MsNode node);
/* The closer of the binding site `node`, or NULL when its type is not closed at scope end. */
const MsCloser *ms_facts_closer(const MsFacts *facts, MsNode node);

#endif
