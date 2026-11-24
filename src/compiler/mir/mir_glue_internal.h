/* compiler/mir/mir_glue_internal.h: what the glue files share: emit helpers, type queries, and the context one
 * drop or clone function is built from. Not part of the layer's interface. */
#ifndef MS_COMPILER_MIR_MIR_GLUE_INTERNAL_H
#define MS_COMPILER_MIR_MIR_GLUE_INTERNAL_H

#include "compiler/mir/mir_analysis.h"
#include "compiler/mir/mir_builder.h"
#include "compiler/mir/mir_glue.h"
#include "compiler/mir/mir_layout.h"
#include "compiler/mir/mir_pass.h"

enum {
  MIRGL_CLOSURE_CODE_OFFSET = 16,
  MIRGL_DEEP_DROP_HEADROOM = 192 << 10,
  MIRGL_MAX_CHAIN_FIELD = 32 /* a mask covers 32 fields */
};

/* ---- the table of what was made ---- */

void mirgl_record(MirGlue *glue, MirGlueKind kind, MirTy ty, uint32_t a, uint32_t b, uint32_t func);
uint32_t mirgl_count(const MirGlue *glue, MirGlueKind kind);

/* ---- emit helpers ---- */

MirValue mirgl_val(MirBuilder *b, MirOp op, const MirValue *args, uint32_t nargs, MirImm imm, MirTy ty);
MirImm mirgl_imm_ty(MirTy ty);
MirImm mirgl_imm_func(uint32_t func);
MirValue mirgl_ptr_at(MirBuilder *b, MirValue base, int64_t offset);
MirValue mirgl_clone(MirBuilder *b, MirValue value);
MirValue mirgl_take(MirBuilder *b, MirValue at, MirTy ty);
MirValue mirgl_load(MirBuilder *b, MirValue at, MirTy ty);
void mirgl_put(MirBuilder *b, MirValue to, MirValue value);
MirValue mirgl_slot(MirBuilder *b, MirTy ty);
void mirgl_drop(MirBuilder *b, MirValue value);
void mirgl_free(MirBuilder *b, MirValue value);
MirValue mirgl_alt_tag(MirBuilder *b, MirValue object);
MirValue mirgl_alt_get(MirBuilder *b, uint32_t alt, uint32_t case_index, uint32_t field, MirValue object);
void mirgl_alt_release(MirBuilder *b, uint32_t alt, uint32_t case_index, uint32_t mask, MirValue object);
MirValue mirgl_alt_new(MirBuilder *b, uint32_t alt, uint32_t case_index, const MirValue *fields,
                       uint32_t count);
MirValue mirgl_opt_is_some(MirBuilder *b, MirValue opt);
MirValue mirgl_opt_payload(MirBuilder *b, MirOp op, MirValue opt);
MirValue mirgl_list_len(MirBuilder *b, MirValue list);
MirValue mirgl_call_rt(MirBuilder *b, uint32_t external, const MirValue *args, uint32_t nargs);

/* The id of the function the builder made, or MIR_NONE when its build failed. */
uint32_t mirgl_finish(MirBuilder *b);

/* The interned name `ms.glue.mir.<n>.<suffix>`. */
MsName mirgl_name(MirModule *module, size_t n, const char *suffix);

/* The extern with this symbol, declared (borrowed parameters) on first use; `fresh` marks a result that
 * aliases nothing. */
uint32_t mirgl_extern(MirModule *module, const char *name, const MirTy *params, uint32_t nparams, MirTy ret,
                      bool fresh);

/* A zeroed array of `count` elements in the module's arena (never NULL). */
void *mirgl_array(MirModule *module, size_t element_size, size_t alignment, size_t count);
#define MIRGL_ARRAY(module, T, count) ((T *)mirgl_array((module), sizeof(T), _Alignof(T), (count)))

/* ---- type queries ---- */

bool mirgl_is_opt(const MirModule *module, MirTy ty, MirTy *inner);

/* The element of a list; `bytes` too when `seq`. MIR_NONE otherwise. */
MirTy mirgl_elem(const MirModule *module, MirTy ty, bool seq);

/* Pushes the types whose values a drop of `ty` drops. */
void mirgl_children(const MirModule *module, MirTy ty, MirTyList *out);

/* Whether dropping `ty` reaches `ty` again through its fields, cases, optional payloads and collection
 * elements: the drop of such data bounds its own nesting. */
bool mirgl_recurses(const MirModule *module, MirTy ty);

uint32_t mirgl_mem_size(const MirModule *module, MirTy ty);
bool mirgl_alt_boxed(const MirModule *module, uint32_t alt);
bool mirgl_opt_boxed(const MirModule *module, MirTy inner);

/* Whether a drop or clone function is made for `ty`: the kinds whose drop is a walk of fields. */
bool mirgl_eligible(const MirModule *module, MirLayouts *layouts, MirTy ty);

/* ---- one function being built ---- */

typedef struct GlCx {
  MirModule *module;
  MirGlue *glue;
  MsName name;
  MirParam param;
  MirTy ty;
  const MirTyData *data;
} GlCx;

/* The tail of a chain: the field of a case that holds the same boxed alternative again. */
typedef struct GlTail {
  bool some;
  uint32_t field;
  bool optional;
  int64_t offset; /* clone: where the next block's pointer lives in this block */
} GlTail;

/* ---- builders (drop, clone, closure, deep) ---- */

uint32_t mirgl_make_drop(MirModule *module, MirGlue *glue, MirTy ty);
uint32_t mirgl_make_clone(MirModule *module, MirGlue *glue, MirTy ty);
uint32_t mirgl_drop_alt(const GlCx *cx);
uint32_t mirgl_clone_alt(const GlCx *cx);

uint32_t mirgl_make_slot_drop(MirModule *module, MirTy ty);
uint32_t mirgl_make_slot_copy(MirModule *module, MirTy ty);
uint32_t mirgl_make_block_drop(MirModule *module, MirTy ty);
uint32_t mirgl_make_block_clone(MirModule *module, MirTy ty);
uint32_t mirgl_wrap_deep_drop(MirModule *module, MirGlue *glue, MirTy ty, uint32_t body);
uint32_t mirgl_wrap_deep_clone(MirModule *module, MirGlue *glue, MirTy ty, uint32_t body);

uint32_t mirgl_make_closure_drop(MirModule *module, uint32_t closure, bool framed);
uint32_t mirgl_make_closure_clone(MirModule *module, MirGlue *glue, uint32_t closure);

#endif
