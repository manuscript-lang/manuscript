/* What the checker records about a module, as flat columns the later passes and the tools read.
 *
 * Every column is an array of 32-bit ids, indexed by syntax node id (0 .. node_count of the
 * module) or by a dense id of its own (binding, callable). No pointers, so a Manuscript tool can
 * read a column as a `List[Int]` and a cache can write one as it is. MS_NONE marks "nothing
 * recorded". Types are `MsTy` indices into `MsCheck.tys`; `ms_ty_show` turns one into the text
 * the Rust checker prints (`<unknown>` included).
 *
 * This header is the plan: each pass fills its columns and adds a comparison line to
 * compiler/tests/check-diff.sh before anything reads them. Status in the comment on each group. */
#ifndef MS_FACTS_H
#define MS_FACTS_H

#include "ms/tables.h"

/* ---- resolution (first) ---- */

/* How a name, member or call expression resolved. */
typedef enum MsResolution {
    MS_RES_NONE,
    MS_RES_BINDING, /* a local, parameter or pattern name: `ref` is a binding id */
    MS_RES_SYMBOL,  /* a module-level declaration or import: `ref` is a symbol id */
    MS_RES_FIELD,   /* a field of a type: `ref` is the field index */
    MS_RES_CASE,    /* an enum case or payload pattern: `ref` is the case index */
    MS_RES_METHOD,  /* a method or interface operation: `ref` is a method id */
} MsResolution;

/* How the caller comes to own the result of a borrow-returning call over a temporary: a copy taken
 * before the temporary is dropped, or the temporary itself when the callee hands it back whole. */
enum { MS_OWNED_NONE, MS_OWNED_CLONE, MS_OWNED_WHOLE };

/* ---- types (second) ---- */

/* Bindings: one row per parameter, local, pattern name and `for` variable of a module. */
typedef struct MsBindings {
    MsSym *name;
    MsTy *ty;
    uint32_t *decl_node;  /* the syntax node that introduces it */
    uint32_t *callable;   /* the declaration node of the function it belongs to */
    uint32_t *reads;      /* how many times its value is read, not counting reads that only feed its own next value */
    MsPos *pos;           /* where its name is written */
    uint8_t *flags;       /* MS_BIND_* */
    uint8_t *role;        /* MsBindRole */
    uint8_t *conflict;    /* MsConflict: whether a payload name written in capitals names a type or a case */
    MsTy *conflict_ty;    /* the type that owns the case, for MS_CONFLICT_CASE */
    uint32_t count;
} MsBindings;
/* A capitalised payload name that coincides with a name in scope still binds a fresh value, and the lint MSL106 says
 * so. TYPE: it is a type name. CASE_ANY: it is a case of some visible enum, more than one. CASE: it is a case of
 * `conflict_ty`. The Rust checker's `Info`. */
typedef enum MsConflict { MS_CONFLICT_NONE, MS_CONFLICT_TYPE, MS_CONFLICT_CASE_ANY, MS_CONFLICT_CASE } MsConflict;
/* MS_BIND_RESOURCE: set by the ownership walk when the binding's type must be closed, so leaving its scope calls `close`. */
/* MS_BIND_FED: a read of the binding only computes its own next value (`total = total + 1`). */
/* MS_BIND_BORROWS: set by the ownership walk when the binding is a reference into another binding (`y := x`,
 * `y := f(x)` where `f` returns a borrow): it owns nothing, so a lowering neither copies nor drops it. */
enum { MS_BIND_MUTABLE = 1, MS_BIND_MOVING = 2, MS_BIND_FED = 4, MS_BIND_RESOURCE = 8, MS_BIND_BORROWS = 16 };
typedef enum MsBindRole {
    MS_ROLE_PARAM, MS_ROLE_SELF, MS_ROLE_LET, MS_ROLE_VAR, MS_ROLE_PATTERN, MS_ROLE_LOOP,
    MS_ROLE_ARM, MS_ROLE_LAMBDA_PARAM
} MsBindRole;

/* Methods of a program: what an `impl` supplies, in declaration order (see methods.h). A symbol's
 * signature is its `ty` in `MsSyms`: a function type whose parameters carry the label, type and
 * var/move flags (`ms_ty_params`) and whose result is `tys.result`. */
enum { MS_METHOD_MUTATING = 1, MS_METHOD_CONSUMING = 2 };
typedef struct MsMethods {
    MsSym *id;            /* `module/Receiver/Contract/name`, as the Rust checker names it */
    MsTy *receiver;
    MsTy *contract;       /* MS_TY_NONE for a type whose impl names no interface */
    MsTy *ty;             /* the signature, receiver not included */
    const MsFunc **decl;  /* the declaration, or NULL for a property without operations */
    MsNativeKind *native;
    uint8_t *access;      /* MS_METHOD_MUTATING | MS_METHOD_CONSUMING of the receiver */
    bool *inherent;       /* a type's own method: its contract is the synthesized `Type$methods` */
    MsModId *module;      /* the module that declares the impl */
    bool *local;          /* an extension declared outside the receiver's module: visible there only */
    MsPos *pos;           /* the method's name, or the impl for a row without a method */
    uint32_t *vars_at, *nvars; /* the impl's variables, then the method's own, into `vars` */
    MsTy *vars;
    uint32_t vars_len, vars_cap;
    uint32_t count, cap;
} MsMethods;

/* The per-module columns. */
/* A place in the checker's source, for reports of why a function was left to the Rust checker. */
typedef struct MsSite {
    const char *file;
    uint32_t line;
} MsSite;

typedef struct MsFacts {
    uint32_t node_count;
    /* resolution */
    uint8_t *res_kind;    /* by node id: MsResolution */
    uint32_t *res_ref;    /* by node id: the id `res_kind` names */
    /* types */
    MsTy *expr_ty;        /* by expression node id */
    MsTy *type_ref_ty;    /* by type-reference node id: what a written type means */
    uint32_t *pattern_binding; /* by pattern node id: binding id, or MS_NONE */
    uint32_t *arm_case;   /* by match-arm node id: the case index the arm matches */
    MsTy *arm_contract;   /* by match-arm node id: the type an arm of a match over an interface value names, else MS_TY_NONE */
    /* calls, by call-expression node id */
    uint32_t *call_callee;     /* symbol id of the called function, else MS_NONE */
    bool *const_use;           /* by name node: a module constant read, which evaluates its initializer */
    uint32_t *call_method;     /* method id when the call is a method call, else MS_NONE */
    uint32_t *text_method;     /* by interpolated expression: the row of its type's own `to_string() String`, else MS_NONE */
    MsTy *call_receiver;       /* the receiver's type for a method call */
    uint8_t *call_owned_borrow; /* a call returning a borrow over a temporary argument: MS_OWNED_CLONE or MS_OWNED_WHOLE */
    uint32_t *call_owned_param; /* MS_OWNED_WHOLE: the parameter whose argument comes back whole */
    MsTy *call_interface;      /* the interface a call dispatches through, else MS_TY_NONE */
    uint32_t *call_type_args_at, *call_type_args_len; /* into `type_args` */
    MsTy *type_args;
    uint32_t ntype_args, ctype_args; /* used and allocated entries of `type_args` */
    uint32_t *lambda_first;   /* by lambda node id: the first binding of its parameters and body; the ones below are captured */
    uint32_t *assign_binding; /* by assignment statement node id: the binding it writes, else MS_NONE */
    uint32_t *field_store_root; /* by assignment statement node id: the `var` a field store changes, else MS_NONE */
    bool *each_list;  /* by `for` statement node id: it iterates a list, a set or a map, not a range */
    bool *each_collection; /* by `for` statement node id: the iterated value is a set or a map (a subset of `each_list`), which ownership and lowering leave to Rust */
    bool *call_borrows; /* by call node id: a native whose result points into its receiver (`s.chars()`) */
    MsTy *coerce_iface; /* by expression node id: the concrete type of a value passed as an interface (the expression's own type), else MS_TY_NONE */
    bool *call_reordered; /* by call node id: an argument is not at its parameter's position (labels out of order or skipping a default); passes that pair arguments with parameters by index leave the call to Rust */
    bool *some_wrap;  /* by expression node id: a value of the payload type used where an Optional is expected, so it is wrapped in `some` */
    bool *moved_out;      /* by name node id: the use moves a binding's value out (ownership pass; a resource closed at scope end is closed only on the paths that keep it) */
    bool *borrowed_match; /* by match node id: every arm yields a reference and the value is only read, so the match is a reference too (ownership pass) */
    bool *body_checked;   /* by declaration node id: the function's body was checked */
    MsSite *refusal;      /* by declaration node id: where the body checker gave up on the body, or NULL file when it did not */
    uint32_t *param_consumed; /* by declaration node id: bit i is set when the function moves its plain parameter i, so callers hand it over (ownership pass) */
    const MsPos **param_consumed_at; /* by declaration node id: where the function moves each parameter (by position), NULL when it moves none; a caller's diagnostic names it */
    bool ownership_done; /* the ownership pass walked this module */
    bool *ret_borrowed;   /* by declaration node id: every result is a reference into the arguments (ownership pass) */
    MsBindings bindings;
    MsMethods *methods; /* the program's table, shared by every module */
} MsFacts;

/* ---- ownership (third, own thread) ---- */

/* Per expression node: how the value is used. Filled by the ownership pass; same indexing. */
typedef enum MsAccess { MS_ACC_NONE, MS_ACC_BORROW, MS_ACC_MOVE, MS_ACC_COPY, MS_ACC_CLONE } MsAccess;
typedef struct MsOwnership {
    uint8_t *access;      /* by expression node id: MsAccess */
    uint32_t *flags;      /* by binding id: MS_OWN_* (implicit close, moved, ...) */
} MsOwnership;

/* ---- effects (third, own thread) ---- */

/* Per callable symbol: the effect names it reaches, as indices into `names` (sorted, deduplicated
 * ranges of `pool`). A violation row is a callable and the effect no `allow_effect` line permits. */
typedef struct MsEffects {
    MsSym *names;
    uint32_t *start, *len; /* by symbol id, into pool */
    uint32_t *pool;
} MsEffects;

#endif
