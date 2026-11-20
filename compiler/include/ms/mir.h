/* libms MIR: the mid-level IR, a port of crates/ms-mir (ir.rs, types.rs) and its text form.
 *
 * A function is a CFG of basic blocks in SSA form; joins use block parameters. Every value has one
 * monomorphic type. Ids are indices into the module's or function's flat arrays. Everything lives
 * in the module's arena, so a module is freed in one call. No global state.
 *
 * The text form (mir_print.c, mir_parse.c) is byte-identical to the Rust printer's output. */
#ifndef MS_MIR_H
#define MS_MIR_H

#include "ms/base.h"

#define MIR_NONE UINT32_MAX /* no value, no function, unknown file */

typedef uint32_t MirTy; /* index into MirTyTable; high bits hold an implementation scope */
typedef uint32_t MirValue, MirBlock;

/* ---- types ---- */

enum {
    MIR_VOID = 0, MIR_BOOL, MIR_INT, MIR_FLOAT, MIR_STR, MIR_BYTES, MIR_PTR, MIR_INT8, MIR_INT16,
    MIR_INT32, MIR_FLOAT32, MIR_UINT8, MIR_UINT16, MIR_UINT32, MIR_UINT64,
    MIR_BUILTIN_TYPES /* 15 */
};

#define MIR_SCOPE_SHIFT 20
static inline MirTy mir_ty_unscoped(MirTy t) { return t & ((1u << MIR_SCOPE_SHIFT) - 1); }
static inline uint32_t mir_ty_scope(MirTy t) { return t >> MIR_SCOPE_SHIFT; }

typedef enum MirTyKind {
    MK_VOID, MK_BOOL, MK_INT, MK_FLOAT, MK_INT8, MK_INT16, MK_INT32, MK_FLOAT32, MK_UINT8,
    MK_UINT16, MK_UINT32, MK_UINT64, MK_STR, MK_BYTES, MK_PTR,
    MK_TYPE,  /* id: type declaration */
    MK_ALT,   /* id: alternative declaration */
    MK_LIST,  /* elem */
    MK_OPT,   /* elem */
    MK_OBJ,   /* name, args: a runtime object such as Map[K, V] */
    MK_FN,    /* args = parameters, elem = result, owned bit set = parameter moves in */
    MK_IFACE  /* id: interface declaration */
} MirTyKind;

/* What a runtime object is, set when its type is made (`mir_ty_obj`) from the runtime's declaration of the name:
 * a handle is one shared word; a collection (`Map`, `Set`) keeps its contents, named by the type arguments, in
 * its own layout; a value object (`BigInt`) is raw bytes that copy like plain data when its arguments do. */
typedef enum MirObjClass { MIR_OBJ_HANDLE = 0, MIR_OBJ_COLLECTION, MIR_OBJ_VALUE } MirObjClass;

typedef struct MirTyData {
    uint8_t kind;
    uint8_t obj_class;  /* MK_OBJ: a MirObjClass, derived from `name` */
    uint32_t id;        /* MK_TYPE, MK_ALT, MK_IFACE */
    MirTy elem;         /* MK_LIST, MK_OPT, result of MK_FN */
    MsSym name;         /* MK_OBJ: the runtime's name */
    const MirTy *args;  /* MK_OBJ, MK_FN */
    uint32_t nargs;
    uint64_t owned;
} MirTyData;

typedef struct MirTyTable {
    MirTyData *kinds;
    uint32_t len, cap;
    uint32_t *index; /* open addressed: type + 1, 0 for empty */
    uint32_t mask;
} MirTyTable;

/* ---- operations ---- */

typedef enum MirImmKind {
    MIR_K_NONE, MIR_K_INT, MIR_K_FLOAT, MIR_K_BOOL, MIR_K_STR, MIR_K_FUNC, MIR_K_EXT, MIR_K_TY,
    MIR_K_TYPE, MIR_K_FIELD, MIR_K_CASE, MIR_K_ALTFIELD, MIR_K_ALTMASK, MIR_K_TYPEMASK,
    MIR_K_VTABLE, MIR_K_GLOBAL, MIR_K_METHOD, MIR_K_CC, MIR_K_IDX, MIR_K_SCOPE
} MirImmKind;

enum { MIR_E_READS = 1, MIR_E_WRITES = 2, MIR_E_FAULTS = 4, MIR_E_OWNERSHIP = 8, MIR_E_ALLOC = 16,
       MIR_E_IO = 32 };

typedef enum MirOp {
#define MIR_OP(id, name, imm, res, fx) MOP_##id,
#include "ms/mir_ops.def"
#undef MIR_OP
    MOP_COUNT
} MirOp;

typedef struct MirOpInfo {
    const char *name;
    uint8_t imm;        /* MirImmKind */
    uint8_t has_result;
    uint8_t effects;    /* MIR_E_* */
} MirOpInfo;

extern const MirOpInfo mir_op_info[MOP_COUNT];
int mir_op_from_name(const char *s, size_t n); /* -1 when unknown */
static inline bool mir_op_is_call(MirOp op) {
    return op == MOP_Call || op == MOP_CallInd || op == MOP_CallRt || op == MOP_CallMethod;
}

typedef enum MirCc { MCC_EQ, MCC_NE, MCC_LT, MCC_LE, MCC_GT, MCC_GE } MirCc;
extern const char *const mir_cc_name[6];
int mir_role_from_name(const char *s, size_t n); /* MR_NONE when unknown */

typedef enum MirImmTag {
    MI_NONE, MI_INT, MI_FLOAT, MI_BOOL, MI_STR, MI_FUNC, MI_EXT, MI_TY, MI_TYPE, MI_FIELD, MI_CASE,
    MI_ALTFIELD, MI_ALTMASK, MI_TYPEMASK, MI_VTABLE, MI_GLOBAL, MI_METHOD, MI_CC, MI_IDX, MI_SCOPE
} MirImmTag;

/* An immediate: `i` holds an integer or the bits of a float; `a`, `b`, `c` hold ids as the tag
 * says (FIELD: type, field; CASE: alt, case; ALTFIELD: alt, case, field; ALTMASK: alt, case,
 * mask; TYPEMASK: type, mask; METHOD: iface, method; SCOPE: two numbers; the single-id tags use
 * `a`; BOOL and CC use `a`). */
typedef struct MirImm {
    uint8_t tag;
    uint32_t a, b, c;
    int64_t i;
} MirImm;

typedef enum MirFault {
    MF_INT_OVERFLOW, MF_DIV_BY_ZERO, MF_INDEX_OUT_OF_RANGE, MF_NONE_UNWRAP, MF_CANCELLED,
    MF_CALL_DEPTH, MF_UNREACHABLE, MF_MESSAGE /* str */
} MirFault;

typedef struct MirLoc {
    uint32_t file, line, col, scope; /* file is MIR_NONE when unknown */
} MirLoc;
#define MIR_LOC_NONE ((MirLoc){MIR_NONE, 0, 0, 0})
static inline bool mir_loc_none(MirLoc l) { return l.file == MIR_NONE; }

typedef enum MirMode { MM_BORROW, MM_MOVE, MM_VAR } MirMode;

typedef struct MirParam { MirTy ty; uint8_t mode; } MirParam;
typedef struct MirBlockParam { MirValue value; uint8_t mode; } MirBlockParam;

typedef struct MirInst {
    MirValue *args; /* owned by the module arena; passes edit it in place or replace it */
    MirImm imm;
    MirValue res;    /* MIR_NONE when the op defines nothing */
    uint32_t nargs;
    MirLoc loc;
    uint8_t op;      /* MirOp */
} MirInst;

typedef struct MirTarget {
    MirBlock block;
    MirValue *args;
    uint32_t nargs;
} MirTarget;

typedef struct MirCase { int64_t value; MirTarget target; } MirCase;

typedef enum MirTermKind { MT_BR, MT_CONDBR, MT_SWITCH, MT_RET, MT_FAULT, MT_UNREACHABLE } MirTermKind;

typedef struct MirTerm {
    uint8_t kind;
    MirValue value;      /* CONDBR condition, SWITCH scrutinee, RET value (MIR_NONE for none) */
    MirTarget a, b;      /* BR: a. CONDBR: a then, b else. SWITCH: b is the default */
    MirCase *cases; /* SWITCH */
    uint32_t ncases;
    uint8_t fault;       /* MirFault */
    uint32_t fault_str;  /* MF_MESSAGE: string id */
} MirTerm;

typedef struct MirBlockData {
    MirBlockParam *params;
    uint32_t nparams, cparams;
    MirInst *insts;
    uint32_t ninsts, cinsts;
    MirTerm term;
    MirLoc term_loc;
    bool cold; /* laid out of line, branches to it unlikely (expand's fault and grow blocks); not in the text form */
} MirBlockData;

typedef enum MirLinkage { ML_INTERNAL, ML_EXPORT } MirLinkage;
typedef enum MirInline { MINL_AUTO, MINL_ALWAYS, MINL_NEVER } MirInline;
typedef enum MirFuncKind { MFK_NORMAL, MFK_CLOSURE, MFK_METHOD } MirFuncKind;
typedef enum MirSort { MSORT_NONE, MSORT_GENERIC, MSORT_SPECIALIZED } MirSort;

typedef struct MirCaptureCloser { uint32_t capture, func; } MirCaptureCloser;

/* A callee body inlined into a function: fault traces and profiles show it as its own frame,
 * called from `call_line` of the enclosing scope. `MirLoc.scope` is one plus an index into
 * `MirFunc.scopes` (0 is the function itself). */
typedef struct MirScope {
    MsSym name;
    uint32_t file; /* MIR_NONE when unknown */
    uint32_t parent; /* enclosing scope number */
    uint32_t call_line;
} MirScope;

/* A value a debugger shows under its source name; `scope` is the `MirLoc.scope` of the body that
 * declares it. */
typedef struct MirNamedValue {
    MirValue value;
    MsSym name;
    bool param; /* a parameter of the body that holds it, not a local */
    uint32_t scope;
} MirNamedValue;

typedef struct MirFunc {
    MsSym name;
    MirParam *params;
    uint32_t nparams;
    MirTy ret;
    bool ret_borrowed, ret_view;
    /* Set by passes: a function made only to run while a cancellation
     * unwinds; one whose lists are raw slot copies (they own no elements). */
    bool unwind_only, raw_scratch;
    /* In the text form: a function that leaves a cancel by its own explicit exits; the indexes
     * of its pointer parameters no other memory overlaps (`var` parameters); on a `slot_close`
     * thunk, the function running the same close for its result; on a function with fallible
     * closing owners, the (plain, pending) functions that turn a close error into its result. */
    bool explicit_cancel;
    uint32_t *noalias;
    uint32_t nnoalias;
    bool has_slot_result;
    uint32_t slot_result;
    bool has_close_exit;
    uint32_t close_exit[2];
    /* Set by lowering: a closure function whose environment owns
     * resources lists the capture index and the function that closes it; a cleanup thunk that
     * closes a value in place names the type of that value. */
    MirCaptureCloser *capture_closers;
    uint32_t ncapture_closers;
    bool has_slot_close;
    MirTy slot_close;
    bool scoped, keeps_scoped; /* a closure into its maker's frame; a function that keeps such closures */
    /* Set by the range pass (`exact` lines in the text form): a bit set (`nexact` words) of the results of
     * unchecked integer arithmetic it proved cannot wrap, which later analysis treats as exact.
     * Values are never reused, so a bit stays true as the function is rewritten; the pass
     * replaces the array instead of editing it, so a copy of the function may share it. */
    uint64_t *exact;
    uint32_t nexact;
    uint8_t linkage, kind, inline_hint, sort;
    MirTy *captures; /* MFK_CLOSURE */
    uint32_t ncaptures;
    MirLoc loc;
    MirScope *scopes;
    uint32_t nscopes, cscopes;
    MirNamedValue *names;
    uint32_t nnames, cnames;
    MirTy *values; /* type of every value */
    uint32_t nvalues, cvalues;
    MirBlockData *blocks; /* block 0 is the entry */
    uint32_t nblocks, cblocks;
} MirFunc;

/* ---- module ---- */

typedef struct MirField { MsSym name; MirTy ty; } MirField;

typedef struct MirTypeDef {
    MsSym name;
    MirField *fields;
    uint32_t nfields;
    bool indirect; /* one pointer to a heap block (`type Name indirect` in the text form) */
} MirTypeDef;

typedef enum MirStd { MSTD_NONE, MSTD_RESULT, MSTD_COMPARABLE, MSTD_EQUAL } MirStd;

typedef struct MirCaseDef { MsSym name; MirField *fields; uint32_t nfields; } MirCaseDef;
typedef struct MirAltDef {
    MsSym name;
    uint8_t std;
    MirCaseDef *cases;
    uint32_t ncases;
    uint64_t borrowed;
} MirAltDef;

typedef struct MirMethodSig {
    MsSym name;
    MirTy *params;
    uint32_t nparams;
    uint64_t owned;
    MirTy ret;
} MirMethodSig;

typedef struct MirIfaceDef {
    MsSym name;
    uint8_t std;
    MirMethodSig *methods;
    uint32_t nmethods;
} MirIfaceDef;

typedef enum MirRole {
    MR_NONE, MR_BORROWS_ARGUMENT, MR_STRBUILDER_APPEND, MR_STRBUILDER_APPEND_INT, MR_STRING_CONCAT,
    MR_STRING_JOIN, MR_STRING_APPEND, MR_INT_TO_STRING, MR_LIST_SORTED, MR_RAW_SLOTS, MR_RAW_FREE,
    MR_LIST_SORT_INTS, MR_LIST_SORTED_BY_DIFFERENCE, MR_LIST_NEW, MR_MAP_NEW, MR_BYTES_VALUES,
    MR_STRING_EQ, MR_CLEANUP_DISCARD, MR_BYTES_APPEND, MR_VIEW_RESULT, MR_TAKES_DYING,
    MR_SPAWNS_TASK, MR_SHIELD_ENTER, MR_SHIELD_EXIT, MR_UNWINDING
} MirRole;

typedef struct MirExtern {
    MsSym name;
    MirParam *params;
    uint32_t nparams;
    MirTy ret;
    bool noreturn, pure, fresh, leaf, reads, retains;
    uint8_t role;
} MirExtern;

typedef struct MirConsts { int64_t *v; uint32_t n; } MirConsts;
typedef struct MirGlobal { MsSym name; MirTy ty; } MirGlobal;

/* The equality and hash functions (`fn(ptr, ptr) -> bool`, `fn(ptr) -> int`) the descriptor of an
 * aggregate type points to. */
typedef struct MirDescGlue {
    MirTy ty;
    uint32_t eq, hash; /* function ids */
} MirDescGlue;

typedef struct MirVtable {
    MsSym name;
    uint32_t iface;
    uint32_t *methods; /* function ids */
    uint32_t nmethods;
    MirTy data_ty;
} MirVtable;

/* Name -> declaration index, for one kind of declaration; the first declaration of a name wins. */
typedef struct MirSymMap { uint32_t *v; uint32_t cap; } MirSymMap;

typedef struct MirModule {
    MsArena arena;
    MsNames names;   /* every declaration name */
    MsNames strings; /* string literals; a string id is its symbol in this table */
    MsSym name;
    MsStr *files;
    uint32_t nfiles, cfiles;
    MirTyTable types;
    MirTypeDef *type_defs;
    uint32_t ntype_defs, ctype_defs;
    MirAltDef *alts;
    uint32_t nalts, calts;
    MirIfaceDef *ifaces;
    uint32_t nifaces, cifaces;
    MirVtable *vtables;
    uint32_t nvtables, cvtables;
    MirDescGlue *desc_glue;
    uint32_t ndesc_glue, cdesc_glue;
    MsStr *blobs;
    uint32_t nblobs, cblobs;
    MirConsts *list_consts;
    uint32_t nlist_consts, clist_consts;
    MirExtern *externs;
    uint32_t nexterns, cexterns;
    MirGlobal *globals;
    uint32_t nglobals, cglobals;
    MirFunc *funcs;
    uint32_t nfuncs, cfuncs;
    uint32_t entry; /* function id or MIR_NONE */
    uint32_t close; /* the `fn(move T) -> int` that kind-1 `scope.own` owners close with, or MIR_NONE */
    MirSymMap by_func, by_type, by_alt, by_iface, by_vtable, by_global, by_extern;
} MirModule;

void mir_module_init(MirModule *m);
/* Records the equality and hash functions the descriptor of aggregate `ty` points to. */
void mir_add_desc_glue(MirModule *m, MirTy ty, uint32_t eq, uint32_t hash);
void mir_module_free(MirModule *m);

/* Type table. */
MirTy mir_ty_intern(MirModule *m, const MirTyData *d);
/* The type equal to `*d` if the table already holds one (nothing is interned); false otherwise. */
bool mir_ty_find(const MirModule *m, const MirTyData *d, MirTy *out);
MirTy mir_ty_list(MirModule *m, MirTy elem);
MirTy mir_ty_opt(MirModule *m, MirTy elem);
MirTy mir_ty_type(MirModule *m, uint32_t id);
MirTy mir_ty_alt(MirModule *m, uint32_t id);
MirTy mir_ty_iface(MirModule *m, uint32_t id);
MirTy mir_ty_obj(MirModule *m, MsSym name, const MirTy *args, uint32_t nargs);
MirTy mir_ty_fn(MirModule *m, const MirTy *params, uint32_t n, MirTy ret, uint64_t owned);
static inline const MirTyData *mir_ty_data(const MirModule *m, MirTy t) {
    return &m->types.kinds[t];
}
bool mir_needs_drop(const MirModule *m, MirTy t);
/* Whether declaration name `sym` spells `text`. */
bool mir_name_is(const MirModule *m, MsSym sym, const char *text);
static inline bool mir_owns(uint64_t owned, uint32_t i) { return i < 64 && (owned >> i & 1); }

/* Declarations; each returns the new id. Names are interned. */
MsSym mir_name(MirModule *m, const char *s, size_t n);
uint32_t mir_add_string(MirModule *m, const char *s, size_t n);
uint32_t mir_add_func(MirModule *m, const MirFunc *f);
/* Rebuilds the name index after functions were removed or moved. */
void mir_funcs_reindex(MirModule *m);
uint32_t mir_add_type(MirModule *m, MsSym name);
uint32_t mir_add_alt(MirModule *m, MsSym name);
uint32_t mir_add_iface(MirModule *m, MsSym name);
uint32_t mir_add_vtable(MirModule *m, const MirVtable *v);
uint32_t mir_add_global(MirModule *m, MsSym name, MirTy ty);
uint32_t mir_add_extern(MirModule *m, const MirExtern *e);

/* Lookups by name; MIR_NONE when absent. */
uint32_t mir_func_by_name(const MirModule *m, MsSym name);
uint32_t mir_type_by_name(const MirModule *m, MsSym name);
uint32_t mir_alt_by_name(const MirModule *m, MsSym name);
uint32_t mir_iface_by_name(const MirModule *m, MsSym name);
uint32_t mir_vtable_by_name(const MirModule *m, MsSym name);
uint32_t mir_global_by_name(const MirModule *m, MsSym name);
uint32_t mir_extern_by_name(const MirModule *m, MsSym name);

/* Functions: `mir_func_new` makes an entry block whose parameters mirror `params`. */
void mir_func_init(MirModule *m, MirFunc *f, MsSym name, const MirParam *params, uint32_t n,
                   MirTy ret);
MirValue mir_new_value(MirModule *m, MirFunc *f, MirTy ty);
MirBlock mir_new_block(MirModule *m, MirFunc *f);
MirBlockData mir_block_empty(void); /* no parameters or instructions, ends in `unreachable` */
static inline MirTy mir_value_ty(const MirFunc *f, MirValue v) { return f->values[v]; }

/* Growable arrays in the module's arena: `*arr` has `*n` elements and room for `*cap`. */
void *mir_grow(MirModule *m, void *arr, uint32_t *cap, uint32_t n, size_t elem);
#define MIR_PUSH(m, arr, n, cap, T, x) \
    do { \
        if ((n) == (cap)) (arr) = (T *)mir_grow((m), (arr), &(cap), (n), sizeof(T)); \
        (arr)[(n)++] = (x); \
    } while (0)

/* ---- text form ---- */

/* Parses `src` (valid UTF-8). On failure returns false with `*line` (1-based) and `*message` set
 * (the message lives in the module's arena); the module must still be freed. */
bool mir_parse(MirModule *m, const char *src, size_t len, uint32_t *line, MsStr *message);
void mir_print_module(const MirModule *m, MsBuf *out);
void mir_print_func(const MirModule *m, const MirFunc *f, MsBuf *out);
void mir_print_ty(const MirModule *m, MirTy t, MsBuf *out);

#endif
