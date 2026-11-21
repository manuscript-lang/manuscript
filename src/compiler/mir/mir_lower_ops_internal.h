/* compiler/mir/mir_lower_ops_internal.h: what the two files of the lower-ops pass share. Not part of the
 * layer's interface. */
#ifndef MS_COMPILER_MIR_MIR_LOWER_OPS_INTERNAL_H
#define MS_COMPILER_MIR_MIR_LOWER_OPS_INTERNAL_H

#include "compiler/mir/mir_analysis.h"
#include "compiler/mir/mir_builder.h"
#include "compiler/mir/mir_layout.h"
#include "compiler/mir/mir_lower_ops.h"
#include "compiler/mir/mir_pass.h"

typedef struct LowerCx {
  MirModule *module;
  const MirGlue *glue;
  MirLayouts layouts;
  /* Runtime functions the pass declares on first use; MIR_NONE until then. */
  uint32_t string_clone, string_free, obj_clone, obj_drop, string_length;
  uint32_t cleanup_push, cleanup_run, fault_string, string_eq;
  MirIdList thunks;       /* by function: the cleanup thunk that calls it, MIR_NONE until made */
  MirTyList release_tys;  /* the list types `list.release` is applied to */
  MirIdList release_fns;  /* and the function made for each */
} LowerCx;

/* A runtime function with the given parameter types (borrowed), declared once; `cache` holds its id. */
uint32_t mirlo_rt(LowerCx *cx, uint32_t *cache, const char *name, const MirTy *params, uint32_t count, MirTy ret);

/* Turns `inst` into a call of runtime function `external` or module function `func`. */
void mirlo_to_call_rt(MirInst *inst, uint32_t external);
void mirlo_to_call(MirInst *inst, uint32_t func);

/* The block-level rewrites; each walks every block of `func`. */
void mirlo_list_drops(LowerCx *cx, MirFunc *func);
void mirlo_str_eq_lits(LowerCx *cx, MirFunc *func);
void mirlo_block_clones(LowerCx *cx, MirFunc *func);
void mirlo_expand_sets(LowerCx *cx, MirFunc *func);
void mirlo_split_drop_ifs(MirModule *module, MirFunc *func);
void mirlo_expand_cleanups(LowerCx *cx, MirFunc *func);
void mirlo_fault_messages(LowerCx *cx, MirFunc *func);

#endif
