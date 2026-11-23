/* compiler/emit/emit_cx.h: the state of writing one function as LLVM IR text, and the helpers every part of
 * the emitter shares.
 *
 * A MIR value is a run of SSA registers, one per leaf (`%v7`, `%v7.1`, ...). Registers hold i64, double and
 * i1; sized integers and Float32 are widened in registers and narrowed only in memory. A value of at most
 * EMIT_DIRECT_BYTES travels as its leaves; a larger one travels as the address of a copy. A result of more
 * than one leaf is written through a hidden first parameter. Checked arithmetic splits a block into pieces
 * (`b3`, `b3.1`, ...): the last piece is the predecessor the successors' phis name. */
#ifndef MS_COMPILER_EMIT_EMIT_CX_H
#define MS_COMPILER_EMIT_EMIT_CX_H

#include "base/strbuild.h"
#include "compiler/mir/mir.h"
#include "compiler/mir/mir_data.h"
#include "compiler/mir/mir_glue.h"
#include "compiler/mir/mir_layout.h"

#define EMIT_DIRECT_BYTES 16
/* The frame slot an inline string's two words are written to so its bytes have an address. */
#define STR_DATA_BYTES 16u

typedef struct EmitDebug EmitDebug;
typedef struct EmitTemps EmitTemps;
typedef struct EmitWide EmitWide;

typedef struct EmitCx {
  const MirModule *module;
  const MirFunc *func;     /* the function being written; NULL for module-level text */
  MsStrBuild *out;         /* borrowed */
  MirLayouts *layouts;     /* borrowed */
  const MirData *data;     /* borrowed: the static data; NULL when the module has none */
  const MirGlue *glue;     /* borrowed: the helper functions glue made; NULL when none */
  uint32_t next;           /* counter for generated register names */
  const char *why;         /* the reason an instruction cannot be written; static text */
  const bool *framed;      /* per value: a closure object kept in the frame; NULL when none */
  const uint32_t *pool;    /* per value: the shared cell a one-block `slot` lives in, UINT32_MAX for any other value; NULL when none */
  const bool *borrowed;    /* per value: an `iface.borrow` kept in the frame; NULL when none */
  uint32_t wide_leaves;    /* a value of more leaves than this lives in a stack cell (emit_wide.c); 0 for never */
  bool wide_hide;          /* those cells are hidden from LLVM: volatile leaf loads and an opaque `asm` */
  EmitWide *wide;          /* the values of `func` that do; NULL when none */
  const uint32_t *cell_bytes; /* the shared cells of `func`: bytes of each */
  const bool *cell_escape;    /* per cell: holds a value, so its address is hidden from LLVM's promotion to registers */
  uint32_t ncells;
  bool volatile_loads;     /* the loads being written must stay where they are (the leaves of a held value) */
  const char *tbaa;        /* `, !tbaa !N` for the list element access being written, or NULL */
  EmitDebug *debug;        /* source places for the fault tables, or NULL */
  const EmitTemps *temps;  /* the stack slots of `func` that live in one block; NULL when none */
  uint32_t scope_base;     /* module-wide index of the first scope of `func` */
  uint32_t body_scope;     /* the scope number of `func`'s own body */
  uint32_t body_line;      /* the line of the first instruction with one; 0 until looked up */
  bool export_all;         /* every function gets an external symbol */
  bool noinline;           /* `func` is glue at the top of a deep chain of glue calls */
  bool pure;               /* `func` reads and writes no memory, cannot fault and always returns */
  bool slot_scopes;        /* mark where each one-block slot starts and stops living */
  bool poison_slots;       /* fill each one-block slot with a pattern where its block ends */
} EmitCx;

/* ---- leaves and names (emit_leaf.c) ---- */

/* How LLVM sees one kind of leaf: the register type, the type in memory, and how a loaded value widens. */
typedef enum EmitWiden { EMIT_SAME, EMIT_SEXT, EMIT_ZEXT, EMIT_BOOL, EMIT_FPEXT } EmitWiden;

typedef struct EmitLeafKind {
  const char *reg;
  const char *mem;
  EmitWiden widen;
} EmitLeafKind;

const EmitLeafKind *emit_leaf_kind(MirLeaf leaf);
const char *emit_leaf_type(MirLeaf leaf);
MsSpan emit_leaves(EmitCx *cx, MirTy type);
/* The leaves of value `value` of the function being written. */
MsSpan emit_value_leaves(EmitCx *cx, MirValue value);
MirTy emit_value_type(const EmitCx *cx, MirValue value);
/* The register type of a one-leaf value; i64 for anything else. */
const char *emit_value_register_type(EmitCx *cx, MirValue value);
/* Appends the name of leaf `leaf` of `value`: `%v7` for the first, `%v7.1` for the next. */
void emit_name(MsStrBuild *out, MirValue value, uint32_t leaf);
/* Appends `@"name"`, escaping what LLVM cannot read raw. */
void emit_symbol(MsStrBuild *out, MsSpan name);
void emit_label(MsStrBuild *out, uint32_t block, uint32_t part);
bool emit_is_indirect(EmitCx *cx, MirTy type);
uint32_t emit_slot_bytes(EmitCx *cx, MirTy type);
/* Appends the name of function `id`'s symbol. */
void emit_function_symbol(const EmitCx *cx, uint32_t id);

/* ---- memory (emit_memory.c) ---- */

/* Writes the address `base + offset` as a new register and returns its number. */
uint32_t emit_address(EmitCx *cx, const char *base, uint32_t offset);
void emit_load_leaf(EmitCx *cx, MirLeaf leaf, MirValue dst, uint32_t index, uint32_t address);
void emit_store_leaf(EmitCx *cx, MirLeaf leaf, MirValue src, uint32_t index, uint32_t address);
/* Reads (`load`) or writes the leaves of `value` at the address in `base`. */
void emit_leaves_at(EmitCx *cx, MirValue value, const char *base, bool load);
/* Converts the word `value` to a pointer register; writes its name to `name`. */
void emit_pointer(EmitCx *cx, MirValue value, char *name, size_t capacity);
/* `dst` leaf `out_index` takes leaf `src_index` of `src` (LLVM has no copy: an identity `or`). */
void emit_copy_leaf(EmitCx *cx, MirValue dst, uint32_t out_index, MirValue src, uint32_t src_index);
void emit_zero_leaf(EmitCx *cx, MirValue dst, uint32_t index, MirLeaf leaf);
/* Formats `%name<number>` into `out`. */
void emit_register_name(char *out, size_t capacity, const char *prefix, uint32_t number);
/* `%<prefix><number><suffix><second>`: `%w3_5`, `%u4b`, `%v7.1` (suffix NULL and second MIR_NONE for none). */
void emit_text_name(char *out, size_t capacity, const char *prefix, uint32_t number, const char *suffix,
                    uint32_t second);

/* ---- operations by family; each sets `*handled` and returns false only when `cx->why` is set ---- */

typedef struct EmitSite {
  uint32_t block;
  uint32_t index;
  uint32_t *part; /* the current piece of the block */
} EmitSite;

bool emit_memory_inst(EmitCx *cx, const MirInst *inst, const EmitSite *site, bool *handled);
bool emit_scalar_op(EmitCx *cx, const MirInst *inst, const EmitSite *site, bool *handled);
bool emit_checked_op(EmitCx *cx, const MirInst *inst, const EmitSite *site, bool *handled);
/* Whether the runtime takes a value of `type` as its scalar leaves; anything else crosses by address. */
bool emit_rt_direct(EmitCx *cx, MirTy type);
/* Whether the runtime returns `type` (an `opt<scalar>`) as a `u8` flag, the payload through a trailing out pointer. */
bool emit_rt_scalar_option(EmitCx *cx, MirTy type);
/* Whether extern `def` is a function of a C library (not the runtime's own, which takes a Float32 as a double). */
bool emit_extern_is_c(const EmitCx *cx, const MirExtern *def);
/* `typedesc`, `str`, `global.get`, `global.set`: the operations that name static data. */
bool emit_data_op(EmitCx *cx, const MirInst *inst, const EmitSite *site, bool *handled);
/* One definition per data symbol, preceded by a declaration of each runtime symbol it names. */
void emit_define_data(EmitCx *cx);
/* A call of the code at register `callee` (NULL: the MIR function `inst` names), `lead` first when given. */
void emit_call_to(EmitCx *cx, const MirInst *inst, const EmitSite *site, const char *callee, const char *lead);
/* Writes `%q<n> = getelementptr i8, ptr <base>, i64 offset` and names it in `out`. */
void emit_offset_pointer(EmitCx *cx, const char *base, uint32_t offset, char *out, size_t capacity);
/* Closures and function addresses, interfaces, and the cancellation poll. */
bool emit_closure_op(EmitCx *cx, const MirInst *inst, const EmitSite *site, bool *handled);
bool emit_iface_op(EmitCx *cx, const MirInst *inst, const EmitSite *site, bool *handled);
bool emit_call_op(EmitCx *cx, const MirInst *inst, const EmitSite *site, bool *handled);
bool emit_record_op(EmitCx *cx, const MirInst *inst, const EmitSite *site, bool *handled);
bool emit_option_op(EmitCx *cx, const MirInst *inst, const EmitSite *site, bool *handled);
bool emit_list_op(EmitCx *cx, const MirInst *inst, const EmitSite *site, bool *handled);
bool emit_string_op(EmitCx *cx, const MirInst *inst, const EmitSite *site, bool *handled);
bool emit_task_op(EmitCx *cx, const MirInst *inst, const EmitSite *site, bool *handled);
/* How many pieces `inst` ends: one per check or branch it writes. */
uint32_t emit_pieces(const MirModule *module, const MirFunc *func, const MirInst *inst);
uint32_t emit_record_pieces(const MirModule *module, const MirFunc *func, const MirInst *inst);
/* Ends the current piece with a check: when `condition` holds the program calls `fault` (with the `i64`
 * values `args`) and does not return; otherwise it continues in a new piece. */
void emit_fault_if(EmitCx *cx, const EmitSite *site, const char *condition, const char *fault,
                   const MirValue *args, uint32_t arg_count);
void emit_frame_slots(EmitCx *cx);
/* Gives each slot confined to its own block the cell of its rank among that block's confined slots, so blocks share
 * storage; per value, UINT32_MAX for the rest. NULL when no slot is confined. */
const uint32_t *emit_slot_pool(MsArena *arena, EmitCx *cx, const bool *held);

/* ---- values held in stack cells (emit_wide.c) ---- */

/* Decides which values of the function are held; the result flags those that need a cell (NULL for none). */
const bool *emit_wide_plan(EmitCx *cx, MsArena *arena);
void emit_wide_end(EmitCx *cx);
/* Writes the leaf name of a held value read outside the block that makes it; false for any other value. */
bool emit_wide_name(MsStrBuild *out, MirValue value, uint32_t leaf);
void emit_wide_start(EmitCx *cx, MirValue defining);
/* After a value is made: writes it to its cell. */
void emit_wide_store(EmitCx *cx, MirValue value);
/* After an instruction is written: the loads of the leaves it read from cells, to go before it. */
void emit_wide_loads(EmitCx *cx);
bool emit_wide_edge_copies(const EmitCx *cx, const MirTerm *term, uint32_t index);
void emit_wide_copy_edge(EmitCx *cx, const MirTerm *term, uint32_t index);
bool emit_wide_return(EmitCx *cx, MirValue value);
bool emit_wide_held(const EmitCx *cx, MirValue value);
bool emit_wide_result(EmitCx *cx, MirValue value, char *out, size_t capacity);
bool emit_wide_address(const EmitCx *cx, MirValue value, char *out, size_t capacity);


/* The one-block shape: a branch on `condition`, the code of its side, a join. */
typedef struct EmitIf {
  uint32_t id;
  uint32_t head, join; /* the pieces before and after, for the phis that name them */
} EmitIf;

EmitIf emit_if_begin(EmitCx *cx, const char *condition, const EmitSite *site);
void emit_if_end(EmitCx *cx, const EmitIf *branch, const EmitSite *site);
/* `<dst> = phi i64 [0, %head], [<value>, %i<id>]`: a word that is zero when the side was skipped. */
void emit_if_phi(EmitCx *cx, const EmitIf *branch, const EmitSite *site, const char *dst, const char *value);

#endif
