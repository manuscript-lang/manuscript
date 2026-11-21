/* compiler/mir/mir_builder.h: builds one function inside a module, with optional SSA variables.
 *
 * Mutable source variables are MirVars (declare, def, use, seal), which the builder turns into block
 * parameters (Braun et al., Simple and Efficient Construction of SSA Form) and from which it removes the
 * trivial ones. The builder never inserts clones or drops: ownership is the caller's job and the verifier
 * checks it.
 *
 * The builder owns its scratch tables, freed by mir_b_into_func or mir_b_finish; the function it builds lives
 * in the module. Every MirBuilder ends with one of those two calls. */
#ifndef MS_COMPILER_MIR_MIR_BUILDER_H
#define MS_COMPILER_MIR_MIR_BUILDER_H

#include "base/map.h"
#include "compiler/mir/mir.h"

typedef uint32_t MirVar;

typedef struct MirVarInfo {
  MirTy ty;
  uint8_t mode;
  bool single;       /* defined exactly once, read only where that definition dominates */
  MirValue only_def; /* the one definition of a single variable, or MIR_NONE */
} MirVarInfo;

MS_LIST_DEFINE(MirVarInfoList, mir_var_info_list, MirVarInfo)
MS_LIST_DEFINE(MirVarList, mir_var_list, MirVar)

/* A variable's definition in one block. */
typedef struct MirVarBlock {
  MirVar var;
  MirBlock block;
} MirVarBlock;

static inline uint64_t mir_var_block_hash(const MirVarBlock *key) {
  return ms_hash_combine(ms_hash_int(key->var), ms_hash_int(key->block));
}

static inline bool mir_var_block_equal(const MirVarBlock *a, const MirVarBlock *b) {
  return a->var == b->var && a->block == b->block;
}

MS_MAP_DEFINE(MirDefMap, mir_def_map, MirVarBlock, MirValue, mir_var_block_hash, mir_var_block_equal)

/* What a block carries during construction. */
typedef struct MirBlockLinks {
  MirIdList preds; /* every edge into the block, with repeats */
  bool sealed;
  MirVarList waiting_var; /* block parameters waiting for the block to be sealed, with their variables */
  MirIdList waiting_param;
} MirBlockLinks;

MS_LIST_DEFINE(MirBlockLinksList, mir_block_links_list, MirBlockLinks)

typedef struct MirBuilder {
  MirModule *module;
  MirFunc func;
  MirBlock cur;
  MirLoc loc;
  MirVarInfoList vars;
  MirDefMap defs;             /* the value of a variable at the end of a block */
  MirBlockLinksList links;    /* by block */
  MirIdList forward;          /* by value: the value a removed trivial parameter stands for, or MIR_NONE */
  uint32_t depth;
  bool failed; /* a read recursed too deep or met no definition; the function is not usable */
} MirBuilder;

/* Starts a function; the entry block is current and sealed. */
void mir_b_init(MirBuilder *builder, MirModule *module, MsName name, const MirParam *params, uint32_t count,
                MirTy ret);

/* A generated fast path: an internal function marked `inline(always)`. */
void mir_b_init_fast_path(MirBuilder *builder, MirModule *module, MsName name, const MirParam *params,
                          uint32_t count, MirTy ret);

/* Finishes without adding the function to the module: moves it to `out` with edge arguments naming removed
 * parameters replaced, and frees the scratch tables. False when the build failed. */
MS_NODISCARD bool mir_b_into_func(MirBuilder *builder, MirFunc *out);

/* Finishes and adds the function to the module; `*id` is its index. */
MS_NODISCARD bool mir_b_finish(MirBuilder *builder, uint32_t *id);

static inline MirFunc *mir_b_func(MirBuilder *builder) {
  return &builder->func;
}

static inline MirTy mir_b_ty(const MirBuilder *builder, MirValue value) {
  return mir_value_ty(&builder->func, value);
}

static inline MirBlock mir_b_current(const MirBuilder *builder) {
  return builder->cur;
}

static inline void mir_b_set_loc(MirBuilder *builder, MirLoc loc) {
  builder->loc = loc;
}

static inline void mir_b_switch_to(MirBuilder *builder, MirBlock block) {
  builder->cur = block;
}

/* Opens a debugger scope for code that runs in another function's frame but is emitted here (a default
 * argument): fault traces show `name` called from `call_line`. Every position set after it carries the
 * scope. Returns the scope to give mir_b_close_scope. */
uint32_t mir_b_open_scope(MirBuilder *builder, MsName name, uint32_t file, uint32_t call_line);
void mir_b_close_scope(MirBuilder *builder, uint32_t outer);

/* Writes the entry block's parameter values to `out[0..count)`; a missing one is MIR_NONE. */
void mir_b_params(const MirBuilder *builder, MirValue *out, uint32_t count);

MirBlock mir_b_new_block(MirBuilder *builder); /* starts unsealed */
MirValue mir_b_add_block_param(MirBuilder *builder, MirBlock block, MirTy ty, MirMode mode);

/* Emits an instruction; `res_ty` is MIR_NONE for one without a result. Returns the result value or MIR_NONE.
 * `args` is copied. */
MirValue mir_b_emit(MirBuilder *builder, MirOp op, const MirValue *args, uint32_t nargs, MirImm imm,
                    MirTy res_ty);

MirValue mir_b_iconst(MirBuilder *builder, int64_t value);
MirValue mir_b_bconst(MirBuilder *builder, bool value);
MirValue mir_b_unit(MirBuilder *builder);
MirValue mir_b_binop(MirBuilder *builder, MirOp op, MirValue left, MirValue right); /* typed like `left` */

/* `icmp`; an ordered comparison of UInt64 operands is the unsigned `uicmp`. */
MirValue mir_b_icmp(MirBuilder *builder, MirCc cc, MirValue left, MirValue right);
MirValue mir_b_select(MirBuilder *builder, MirValue cond, MirValue then, MirValue otherwise);
MirValue mir_b_list_new(MirBuilder *builder, MirTy elem, MirValue capacity);

/* `call` a module function; a borrowing variant passed where its ordinary alternative is expected is read as
 * one (`alt.plain`). */
MirValue mir_b_call(MirBuilder *builder, uint32_t func, const MirValue *args, uint32_t nargs);
MirValue mir_b_call_rt(MirBuilder *builder, uint32_t external, const MirValue *args, uint32_t nargs);

/* Terminators of the current block. */
void mir_b_br(MirBuilder *builder, MirBlock to, const MirValue *args, uint32_t nargs);
void mir_b_br_if(MirBuilder *builder, MirValue cond, MirBlock then, const MirValue *then_args, uint32_t nthen,
                 MirBlock otherwise, const MirValue *else_args, uint32_t nelse);
void mir_b_switch(MirBuilder *builder, MirValue value, const MirCase *cases, uint32_t ncases,
                  MirBlock fallback);
void mir_b_ret(MirBuilder *builder, MirValue value); /* MIR_NONE returns nothing */
void mir_b_fault(MirBuilder *builder, MirFault kind);
void mir_b_unreachable(MirBuilder *builder);

/* Variables. A single variable has exactly one definition that dominates every read. */
MirVar mir_b_declare_var(MirBuilder *builder, MirTy ty, MirMode mode);
MirVar mir_b_declare_single(MirBuilder *builder, MirTy ty, MirMode mode);
void mir_b_def_var(MirBuilder *builder, MirVar var, MirValue value);
MirValue mir_b_use_var(MirBuilder *builder, MirVar var);
void mir_b_seal_block(MirBuilder *builder, MirBlock block);

#endif
