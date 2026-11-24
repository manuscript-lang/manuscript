/* compiler/mir/mir.h: MIR, the mid-level IR every back-end pass reads and writes.
 *
 * A function is a control-flow graph of basic blocks in SSA form; joins use block parameters. Every value
 * has one monomorphic type. Ids are indices into flat arrays of the module or the function. Lowering builds a
 * MirModule in memory and the optimizer, emitter and linker take that same module: there is no text between
 * passes (the text form is a dump format only).
 *
 * Ownership: a MirModule owns everything it points at. Fixed-size arrays (operands, parameters, fields)
 * live in the module arena; growable arrays are base lists that mir_module_free releases. Names are
 * interned in module tables, so equal names are equal ids. */
#ifndef MS_COMPILER_MIR_MIR_H
#define MS_COMPILER_MIR_MIR_H

#include "base/arena.h"
#include "base/intern.h"
#include "base/list.h"
#include "base/safe.h"

#define MIR_NONE UINT32_MAX /* no value, no function, unknown file */

typedef uint32_t MirTy; /* an id in the module's type table; the high bits hold an implementation scope */
typedef uint32_t MirValue;
typedef uint32_t MirBlock;

/* ---- types ---- */

enum {
  MIR_VOID = 0, MIR_BOOL, MIR_INT, MIR_FLOAT, MIR_STR, MIR_BYTES, MIR_PTR, MIR_INT8, MIR_INT16,
  MIR_INT32, MIR_FLOAT32, MIR_UINT8, MIR_UINT16, MIR_UINT32, MIR_UINT64,
  MIR_BUILTIN_TYPES
};

#define MIR_SCOPE_SHIFT 20

static inline MirTy mir_ty_unscoped(MirTy type) {
  return type & ((UINT32_C(1) << MIR_SCOPE_SHIFT) - 1);
}

static inline uint32_t mir_ty_scope(MirTy type) {
  return type >> MIR_SCOPE_SHIFT;
}

typedef enum MirTyKind {
  MK_VOID, MK_BOOL, MK_INT, MK_FLOAT, MK_INT8, MK_INT16, MK_INT32, MK_FLOAT32, MK_UINT8, MK_UINT16,
  MK_UINT32, MK_UINT64, MK_STR, MK_BYTES, MK_PTR,
  MK_TYPE,  /* id: a record declaration */
  MK_ALT,   /* id: an alternative declaration */
  MK_LIST,  /* elem */
  MK_OPT,   /* elem */
  MK_OBJ,   /* name, args: a runtime object such as Map[K, V] */
  MK_FN,    /* args are the parameters, elem the result, `owned` bit i set: parameter i moves in */
  MK_IFACE  /* id: an interface declaration */
} MirTyKind;

/* What a runtime object is, derived from its name when its type is made: a handle is one shared word; a
 * collection (Map, Set) keeps its contents in its own layout; a value object (BigInt) is raw bytes that copy
 * like plain data. */
typedef enum MirObjClass { MIR_OBJ_HANDLE = 0, MIR_OBJ_COLLECTION, MIR_OBJ_VALUE } MirObjClass;

typedef struct MirTyData {
  uint8_t kind;      /* a MirTyKind */
  uint8_t obj_class; /* MK_OBJ: a MirObjClass */
  uint32_t id;       /* MK_TYPE, MK_ALT, MK_IFACE */
  MirTy elem;        /* MK_LIST, MK_OPT; the result of MK_FN */
  MsName name;       /* MK_OBJ: the runtime's name */
  const MirTy *args; /* MK_OBJ, MK_FN: in the module arena */
  uint32_t nargs;
  uint64_t owned;
} MirTyData;

MS_LIST_DEFINE(MirTyDataList, mir_tydata_list, MirTyData *)
MS_LIST_DEFINE(MirTyList, mir_tylist, MirTy)
MS_LIST_DEFINE(MirIdList, mir_idlist, uint32_t)
MS_LIST_DEFINE(MirInt64List, mir_int64list, int64_t)

/* The interned types: each distinct MirTyData is one id, found through a name table keyed by its packed
 * bytes. Id 0 is the empty key, which is the void type. */
typedef struct MirTyTable {
  MsNames keys;        /* owned: packed MirTyData, id order */
  MirTyDataList kinds; /* owned: by id; each entry lives in the module arena, so a pointer from mir_ty_data stays
                          valid while later types are interned */
} MirTyTable;

/* ---- operations ---- */

typedef enum MirImmKind {
  MIR_K_NONE, MIR_K_INT, MIR_K_FLOAT, MIR_K_BOOL, MIR_K_STR, MIR_K_FUNC, MIR_K_EXT, MIR_K_TY, MIR_K_TYPE,
  MIR_K_FIELD, MIR_K_CASE, MIR_K_ALTFIELD, MIR_K_ALTMASK, MIR_K_TYPEMASK, MIR_K_VTABLE, MIR_K_GLOBAL,
  MIR_K_METHOD, MIR_K_CC, MIR_K_IDX, MIR_K_SCOPE
} MirImmKind;

enum {
  MIR_E_READS = 1, MIR_E_WRITES = 2, MIR_E_FAULTS = 4, MIR_E_OWNERSHIP = 8, MIR_E_ALLOC = 16, MIR_E_IO = 32,
  /* with MIR_E_FAULTS: the only fault is a refused allocation, which leaves every place the operands came from
   * holding its value, so a cleanup entry for such a place need not be retired around the instruction */
  MIR_E_OOM = 64
};

typedef enum MirOp {
#define MIR_OP(id, name, imm, res, fx) MOP_##id,
#include "compiler/mir/mir_ops.def"
#undef MIR_OP
  MOP_COUNT
} MirOp;

typedef struct MirOpInfo {
  const char *name;
  uint8_t imm;        /* a MirImmKind */
  uint8_t has_result;
  uint8_t effects;    /* MIR_E_* */
} MirOpInfo;

extern const MirOpInfo mir_op_info[MOP_COUNT];

/* The op whose text name is `name`; false when there is none. */
MS_NODISCARD MS_NONNULL bool mir_op_from_name(MsSpan name, MirOp *out);

static inline bool mir_op_is_call(MirOp op) {
  return op == MOP_Call || op == MOP_CallInd || op == MOP_CallRt || op == MOP_CallMethod;
}

typedef enum MirCc { MCC_EQ, MCC_NE, MCC_LT, MCC_LE, MCC_GT, MCC_GE } MirCc;

typedef enum MirImmTag {
  MI_NONE, MI_INT, MI_FLOAT, MI_BOOL, MI_STR, MI_FUNC, MI_EXT, MI_TY, MI_TYPE, MI_FIELD, MI_CASE, MI_ALTFIELD,
  MI_ALTMASK, MI_TYPEMASK, MI_VTABLE, MI_GLOBAL, MI_METHOD, MI_CC, MI_IDX, MI_SCOPE
} MirImmTag;

/* An immediate: `i` holds an integer or the bits of a float; `a`, `b`, `c` hold ids as the tag says
 * (FIELD: type, field; CASE: alt, case; ALTFIELD: alt, case, field; ALTMASK: alt, case, mask; TYPEMASK: type,
 * mask; METHOD: iface, method; SCOPE: two numbers; the single-id tags use `a`; BOOL and CC use `a`). */
typedef struct MirImm {
  uint8_t tag;
  uint32_t a, b, c;
  int64_t i;
} MirImm;

typedef enum MirFault {
  MF_POSTED, /* a fault already posted that nothing can leave by: the program ends with its report */
  MF_UNREACHABLE
} MirFault;

typedef struct MirLoc {
  uint32_t file; /* MIR_NONE when unknown */
  uint32_t line, col, scope;
} MirLoc;

#define MIR_LOC_NONE ((MirLoc){MIR_NONE, 0, 0, 0})

static inline bool mir_loc_none(MirLoc loc) {
  return loc.file == MIR_NONE;
}

typedef enum MirMode { MM_BORROW, MM_MOVE, MM_VAR } MirMode;

typedef struct MirParam {
  MirTy ty;
  uint8_t mode; /* a MirMode */
} MirParam;

typedef struct MirBlockParam {
  MirValue value;
  uint8_t mode; /* a MirMode */
} MirBlockParam;

MS_LIST_DEFINE(MirBlockParamList, mir_block_param_list, MirBlockParam)

typedef struct MirInst {
  MirValue *args; /* in the module arena; passes edit it in place or replace it */
  MirImm imm;
  MirValue res;   /* MIR_NONE when the op defines nothing */
  uint32_t nargs;
  MirLoc loc;
  uint8_t op;     /* a MirOp */
} MirInst;

MS_LIST_DEFINE(MirInstList, mir_inst_list, MirInst)

typedef struct MirTarget {
  MirBlock block;
  MirValue *args; /* in the module arena */
  uint32_t nargs;
} MirTarget;

typedef struct MirCase {
  int64_t value;
  MirTarget target;
} MirCase;

typedef enum MirTermKind { MT_BR, MT_CONDBR, MT_SWITCH, MT_RET, MT_FAULT, MT_UNREACHABLE } MirTermKind;

typedef struct MirTerm {
  uint8_t kind;        /* a MirTermKind */
  MirValue value;      /* CONDBR condition, SWITCH scrutinee, RET value (MIR_NONE for none) */
  MirTarget a, b;      /* BR: a. CONDBR: a then, b else. SWITCH: b is the default */
  MirCase *cases;      /* SWITCH: in the module arena */
  uint32_t ncases;
  uint8_t fault;       /* a MirFault */
} MirTerm;

typedef struct MirBlockData {
  MirBlockParamList params;
  MirInstList insts;
  MirTerm term;
  MirLoc term_loc;
  bool cold; /* laid out of line, branches to it unlikely; not in the text form */
} MirBlockData;

MS_LIST_DEFINE(MirBlockList, mir_block_list, MirBlockData)

typedef enum MirLinkage { ML_INTERNAL, ML_EXPORT } MirLinkage;
typedef enum MirInline { MINL_AUTO, MINL_ALWAYS, MINL_NEVER } MirInline;
typedef enum MirFuncKind { MFK_NORMAL, MFK_CLOSURE, MFK_METHOD } MirFuncKind;
typedef enum MirSort { MSORT_NONE, MSORT_GENERIC, MSORT_SPECIALIZED } MirSort;

typedef struct MirCaptureCloser {
  uint32_t capture, func;
} MirCaptureCloser;

/* A callee body inlined into a function: fault traces and profiles show it as its own frame, called from
 * `call_line` of the enclosing scope. `MirLoc.scope` is one plus an index into `MirFunc.scopes` (0 is the
 * function itself). */
typedef struct MirScope {
  MsName name;
  uint32_t file;   /* MIR_NONE when unknown */
  uint32_t parent; /* enclosing scope number */
  uint32_t call_line;
} MirScope;

MS_LIST_DEFINE(MirScopeList, mir_scope_list, MirScope)

/* A value a debugger shows under its source name; `scope` is the `MirLoc.scope` of the body declaring it. */
typedef struct MirNamedValue {
  MirValue value;
  MsName name;
  bool param; /* a parameter of the body that holds it, not a local */
  uint32_t scope;
} MirNamedValue;

MS_LIST_DEFINE(MirNamedValueList, mir_named_value_list, MirNamedValue)

typedef struct MirFunc {
  MsName name;
  MsName display; /* what a fault trace calls the function, when that is not `name`: MS_NAME_EMPTY otherwise */
  MirParam *params; /* in the module arena */
  uint32_t nparams;
  MirTy ret;
  bool ret_borrowed, ret_view;
  /* Set by passes: a function made only to run while a cancellation unwinds; one whose lists are raw slot
   * copies (they own no elements). */
  bool raw_scratch;
  bool closer; /* a consuming `close` method: its callers run it shielded, so it runs to its end and has no exit sites */
  /* A function that leaves a cancel by its own explicit exits; the indexes of its pointer parameters no
   * other memory overlaps (`var` parameters); on a `slot_close` thunk, the function running the same close
   * for its result; on a function with fallible closing owners, the (plain, pending) functions that turn a
   * close error into its result. */
  bool explicit_cancel;
  uint32_t *noalias; /* in the module arena */
  uint32_t nnoalias;
  bool has_slot_result;
  uint32_t slot_result;
  bool has_close_exit;
  uint32_t close_exit[2];
  /* Set by lowering: a closure function whose environment owns resources lists the capture index and the
   * function that closes it; a cleanup thunk that closes a value in place names the type of that value. */
  MirCaptureCloser *capture_closers; /* in the module arena */
  uint32_t ncapture_closers;
  bool has_slot_close;
  MirTy slot_close;
  bool scoped, keeps_scoped; /* a closure into its maker's frame; a function that keeps such closures */
  bool runs_once;            /* set by lowering: the body of a test block, which runs once, so a copy of a callee into it buys no speed */
  /* Set by the range pass: a bit set (`nexact` words) of the results of unchecked integer arithmetic it
   * proved cannot wrap. Values are never reused, so a bit stays true as the function is rewritten; the pass
   * replaces the array instead of editing it, so a copy of the function may share it. */
  uint64_t *exact; /* in the module arena */
  uint32_t nexact;
  uint8_t linkage, kind, inline_hint, sort; /* MirLinkage, MirFuncKind, MirInline, MirSort */
  MirTy *captures; /* MFK_CLOSURE: in the module arena */
  uint32_t ncaptures;
  MirLoc loc;
  MirScopeList scopes;
  MirNamedValueList names;
  MirTyList values;     /* the type of every value */
  MirBlockList blocks;  /* block 0 is the entry */
} MirFunc;

MS_LIST_DEFINE(MirFuncList, mir_func_list, MirFunc)

/* ---- module declarations ---- */

typedef struct MirField {
  MsName name;
  MirTy ty;
  uint32_t default_fn1; /* 1 + the function that builds the field's default in place, `fn(out, record)`; 0 for none */
} MirField;

typedef struct MirTypeDef {
  MsName name;
  MirField *fields; /* in the module arena */
  uint32_t nfields;
  bool indirect; /* one pointer to a heap block */
  bool opaque;   /* declared `opaque`: its text is the type name only */
  bool native;   /* an extern type the runtime reads and writes by address (`@repr=inline<N>`): words, no fields to name */
  bool decimal;  /* the standard `Decimal`: its shape is a number written and read as digits */
  uint32_t text_fn1; /* 1 + the function `fn(slot, out)` that writes the type's own `to_string` text, for its shape; 0 for none */
  uint32_t json_fn1; /* 1 + the function `fn(slot, writer) -> u8` that writes its own `to_json` document; 0 for none */
} MirTypeDef;

MS_LIST_DEFINE(MirTypeDefList, mir_type_def_list, MirTypeDef)

typedef enum MirStd { MSTD_NONE, MSTD_RESULT, MSTD_COMPARABLE, MSTD_EQUAL, MSTD_JSON_VALUE } MirStd;

typedef struct MirCaseDef {
  MsName name;
  MirField *fields; /* in the module arena */
  uint32_t nfields;
} MirCaseDef;

typedef struct MirAltDef {
  MsName name;
  uint8_t std; /* a MirStd */
  MirCaseDef *cases; /* in the module arena */
  uint32_t ncases;
  uint64_t borrowed;
  bool opaque; /* as for MirTypeDef */
  uint32_t text_fn1; /* as for MirTypeDef */
  uint32_t json_fn1;
  uint32_t tree_fn1; /* 1 + the constructor thunk of the untyped tree (`JsonValue`) for its shape; 0 for none */
} MirAltDef;

MS_LIST_DEFINE(MirAltDefList, mir_alt_def_list, MirAltDef)

/* The own text and JSON form of a native object type (an IP address): its shape names these functions like a record's. */
typedef struct MirObjHook {
  MirTy ty;
  uint32_t text_fn1;
  uint32_t json_fn1;
} MirObjHook;

MS_LIST_DEFINE(MirObjHookList, mir_obj_hook_list, MirObjHook)

typedef struct MirMethodSig {
  MsName name;
  MirTy *params; /* in the module arena */
  uint32_t nparams;
  uint64_t owned;
  bool consumes; /* a `move fn` operation: it takes the interface value itself */
  MirTy ret;
} MirMethodSig;

typedef struct MirIfaceDef {
  MsName name;
  uint8_t std; /* a MirStd */
  MirMethodSig *methods; /* in the module arena */
  uint32_t nmethods;
} MirIfaceDef;

MS_LIST_DEFINE(MirIfaceDefList, mir_iface_def_list, MirIfaceDef)

typedef enum MirRole {
  MR_NONE, MR_BORROWS_ARGUMENT, MR_STRING_CONCAT,
  MR_STRING_JOIN, MR_STRING_JOIN_GROW, MR_STRING_APPEND, MR_INT_TO_STRING, MR_LIST_SORTED, MR_RAW_SLOTS, MR_RAW_FREE,
  MR_LIST_SORT_INTS, MR_LIST_SORTED_BY_DIFFERENCE, MR_LIST_NEW, MR_MAP_NEW, MR_BYTES_VALUES, MR_STRING_EQ,
  MR_BYTES_APPEND, MR_BYTES_CONCAT, MR_BYTES_CONCAT_GROW, MR_VIEW_RESULT, MR_TAKES_DYING, MR_SHIELD_ENTER,
  MR_SHIELD_EXIT, MR_UNWINDING, MR_MAP_PROBE_INT, MR_MAP_PROBE_STR, MR_SET_PROBE_INT, MR_STRING_SLICE,
  MR_BYTES_READ_WORD, MR_BYTES_INDEX_OF_BYTE, MR_STRING_PARSE_INT, MR_STRING_CONTAINS,
  MR_STRING_STARTS_WITH, MR_STRING_ENDS_WITH, MR_STRING_COMPARE, MR_STRING_SCALAR_STEP,
  MR_STRING_SCALAR_AT, MR_SET_PROBE_STR, MR_STRING_SCALAR_TEXT,
  MR_KEEPS_SLOT,
  MR_POSTS_FAULT /* posts a fault: the block then leaves by its exit, and each post keeps its own location */
} MirRole;

/* The family of borrowing twins an extern declares: other runtime functions that answer the same call without
 * building its result (`opt_splitview`). */
typedef enum MirTwin { MTW_NONE, MTW_SPLIT_VIEW } MirTwin;

typedef struct MirExtern {
  MsName name;
  MirParam *params; /* in the module arena */
  uint32_t nparams;
  MirTy ret;
  bool noreturn, pure, fresh, leaf, reads, retains;
  uint8_t role; /* a MirRole */
  uint8_t twin; /* a MirTwin */
} MirExtern;

MS_LIST_DEFINE(MirExternList, mir_extern_list, MirExtern)

/* A constant list: `count` elements starting at `start` in the module's `list_const_values`. */
typedef struct MirListConst {
  uint32_t start, count;
} MirListConst;

MS_LIST_DEFINE(MirListConstList, mir_list_const_list, MirListConst)

typedef struct MirGlobal {
  MsName name;
  MirTy ty;
} MirGlobal;

MS_LIST_DEFINE(MirGlobalList, mir_global_list, MirGlobal)

/* The equality and hash functions (`fn(ptr, ptr) -> bool`, `fn(ptr) -> int`) the descriptor of an aggregate
 * type points to. */
typedef struct MirDescGlue {
  MirTy ty;
  uint32_t eq, hash; /* function ids */
} MirDescGlue;

MS_LIST_DEFINE(MirDescGlueList, mir_desc_glue_list, MirDescGlue)

typedef struct MirVtable {
  MsName name;
  uint32_t iface;
  uint32_t *methods; /* function ids, in the module arena */
  uint32_t nmethods;
  MirTy data_ty;
  uint32_t close_drop; /* function id + 1 of the payload drop that closes a resource, or 0 for the type's plain drop */
} MirVtable;

MS_LIST_DEFINE(MirVtableList, mir_vtable_list, MirVtable)

typedef struct MirModule {
  MsArena arena;
  MsNames names;   /* every declaration name */
  MsNames strings; /* string literals; a string id is its name in this table */
  MsName name;
  MsSpanList files; /* source file names, by file id (arena text) */
  MirTyTable types;
  MirTypeDefList type_defs;
  MirAltDefList alts;
  MirObjHookList obj_hooks;
  MirIfaceDefList ifaces;
  MirVtableList vtables;
  MirDescGlueList desc_glue;
  MsSpanList blobs;                /* constant byte strings, by blob id (arena text) */
  MirListConstList list_consts;    /* constant lists, by id */
  MirInt64List list_const_values;  /* the elements of every constant list */
  MirExternList externs;
  MirGlobalList globals;
  MirFuncList funcs;
  uint32_t entry; /* function id or MIR_NONE */
  uint32_t inline_base; /* instruction count up to which the optimiser inlines a callee; set by mir_optimize; 0 for the default */
  uint32_t close; /* the `fn(move T) -> int` that kind-1 `scope.own` owners close with, or MIR_NONE */
  /* Declaration index by name id, MIR_NONE where the name declares nothing; the first declaration wins. */
  MirIdList by_func, by_type, by_alt, by_iface, by_vtable, by_global, by_extern;
} MirModule;

void mir_module_init(MirModule *module);
void mir_module_free(MirModule *module);

/* ---- type table ---- */

/* The id of the type equal to `data`, adding it when new; `args` is copied. */
MirTy mir_ty_intern(MirModule *module, const MirTyData *data);

/* The id of the type equal to `data` when the table holds one (nothing is added). */
MS_NODISCARD MS_NONNULL bool mir_ty_find(const MirModule *module, const MirTyData *data, MirTy *out);

MirTy mir_ty_list(MirModule *module, MirTy elem);
MirTy mir_ty_opt(MirModule *module, MirTy elem);
MirTy mir_ty_type(MirModule *module, uint32_t id);
MirTy mir_ty_alt(MirModule *module, uint32_t id);
MirTy mir_ty_iface(MirModule *module, uint32_t id);
MirTy mir_ty_obj(MirModule *module, MsName name, const MirTy *args, uint32_t nargs);
MirTy mir_ty_fn(MirModule *module, const MirTy *params, uint32_t count, MirTy ret, uint64_t owned);

static inline const MirTyData *mir_ty_data(const MirModule *module, MirTy type) {
  return module->types.kinds.ptr[type];
}

/* Whether dropping a value of `type` does anything. */
bool mir_needs_drop(const MirModule *module, MirTy type);

static inline bool mir_owns(uint64_t owned, uint32_t index) {
  return index < 32 && ((owned >> index) & 1) != 0;
}

/* A function type's `var` parameters are the bits above its owned ones: such an argument is passed as the address
 * of a slot. */
enum { MIR_FN_VAR_SHIFT = 32 };
static inline bool mir_param_is_var(uint64_t owned, uint32_t index) {
  return index < 32 && ((owned >> (MIR_FN_VAR_SHIFT + index)) & 1) != 0;
}

/* ---- declarations; each add returns the new id and indexes the name ---- */

MsName mir_name(MirModule *module, MsSpan text);
bool mir_name_is(const MirModule *module, MsName name, const char *text);
uint32_t mir_add_string(MirModule *module, MsSpan text);
uint32_t mir_add_file(MirModule *module, MsSpan path);
uint32_t mir_add_func(MirModule *module, const MirFunc *func);
uint32_t mir_add_type(MirModule *module, MsName name);
uint32_t mir_add_alt(MirModule *module, MsName name);
uint32_t mir_add_iface(MirModule *module, MsName name);
uint32_t mir_add_vtable(MirModule *module, const MirVtable *vtable);
uint32_t mir_add_global(MirModule *module, MsName name, MirTy type);
uint32_t mir_add_extern(MirModule *module, const MirExtern *external);
void mir_add_desc_glue(MirModule *module, MirTy type, uint32_t eq, uint32_t hash);

/* Rebuilds the function name index after functions were removed or moved. */
void mir_funcs_reindex(MirModule *module);

/* Lookups by name; MIR_NONE when absent. */
uint32_t mir_func_by_name(const MirModule *module, MsName name);
uint32_t mir_type_by_name(const MirModule *module, MsName name);
uint32_t mir_alt_by_name(const MirModule *module, MsName name);
uint32_t mir_iface_by_name(const MirModule *module, MsName name);
uint32_t mir_vtable_by_name(const MirModule *module, MsName name);
uint32_t mir_global_by_name(const MirModule *module, MsName name);
uint32_t mir_extern_by_name(const MirModule *module, MsName name);

/* The targets of a terminator in order: br has one, condbr two (then, else), switch its cases then the default,
 * the rest none. */
static inline uint32_t mir_term_ntargets(const MirTerm *term) {
  switch ((MirTermKind)term->kind) {
  case MT_BR:
    return 1;
  case MT_CONDBR:
    return 2;
  case MT_SWITCH:
    return term->ncases + 1;
  case MT_RET: case MT_FAULT: case MT_UNREACHABLE:
    return 0;
  }
  return 0;
}
/* Removes argument `k` of the edge. */
void mir_target_remove_arg(MirTarget *t, uint32_t k);
MirTarget *mir_term_target(MirTerm *term, uint32_t index);

/* ---- functions ---- */

/* Starts `func` with an entry block whose parameters mirror `params`. */
void mir_func_init(MirModule *module, MirFunc *func, MsName name, const MirParam *params, uint32_t count,
                   MirTy ret);
MirValue mir_new_value(MirFunc *func, MirTy type);
MirBlock mir_new_block(MirFunc *func);
MirBlockData mir_block_empty(void); /* no parameters or instructions, ends in `unreachable` */

static inline MirTy mir_value_ty(const MirFunc *func, MirValue value) {
  return func->values.ptr[value];
}

#endif
