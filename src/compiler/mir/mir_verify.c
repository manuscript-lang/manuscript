/* The MIR verifier (verify.rs): declarations, the shape of each function, SSA dominance, operand
 * types (mir_verify_types.c) and linear ownership. A function that fails an earlier stage is not
 * checked by a later one, as in the Rust verifier, so the two report the same errors.
 *
 * Ownership is checked on values whose type needs a drop. A value is owned when its defining
 * instruction returns an owned value (mir_result_mode), or it is a `move` parameter or block
 * parameter; every other value is borrowed. A consuming position needs an owned operand and removes
 * it from the live set; a borrowing position takes either, but an owned value must still be live.
 * The live set must be the same on every edge into a block and empty at `ret`. */

#include "compiler/mir/mir_verify_internal.h"

#include <stdarg.h>

#include "base/message.h"
#include "compiler/mir/mir_layout.h"
#include "compiler/mir/mir_print.h"

/* ---- errors ---- */

static void mv_push(MirVerifyErrors *errs, MsSpan func, MirBlock block, MsSpan message) {
  mir_verify_error_list_push(&errs->errors, (MirVerifyError){func, block, message});
}

void mir_verify_errors_free(MirVerifyErrors *errors) {
  mir_verify_error_list_free(&errors->errors);
  ms_arena_free(&errors->arena);
}

void mir_verify_error_text(const MirVerifyError *error, MsStrBuild *out) {
  ms_strbuild_append(out, error->func);
  ms_strbuild_append_text(out, ": ");
  if (error->block != MIR_NONE) {
    ms_strbuild_printf(out, "b%u: ", error->block);
  }
  ms_strbuild_append(out, error->message);
}

/* ---- the verifier of one function ---- */



static MsSpan mv_func_name(const Mv *v) {
  return ms_arena_copy(&v->errs->arena, ms_names_span(&v->cx.m->names, v->cx.f->name));
}

void mv_err(Mv *v, MirBlock block, const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  MsSpan message = ms_message_vformat(&v->errs->arena, fmt, ap);
  va_end(ap);
  mv_push(v->errs, mv_func_name(v), block, message);
}

static MsSpan mv_type_name(Mv *v, MirTy t) {
  MsStrBuild b = ms_strbuild_new();
  mir_print_ty(v->cx.m, t, &b);
  MsSpan text = ms_arena_copy(&v->errs->arena, ms_strbuild_span(&b));
  ms_strbuild_free(&b);
  return text;
}

const char *mv_op_name(const MirInst *in) { return mir_op_info[in->op].name; }

MirTy mv_ty(const Mv *v, MirValue x) { return v->cx.f->values.ptr[x]; }

bool mv_rc(const Mv *v, MirValue x) { return v->cx.drops[mv_ty(v, x)]; }

/* A function is Raw until `elaborate` runs: it still carries scope markers. */
bool mv_is_raw(const MirFunc *f) {
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      MirOp op = (MirOp)f->blocks.ptr[b].insts.ptr[i].op;
      if (op == MOP_ScopeBegin || op == MOP_ScopeOwn || op == MOP_ScopeEnd ||
        op == MOP_ScopeDisown || op == MOP_ScopeMark) {
        return true;
      }
    }
  }
  return false;
}

MirMode *mv_modes(Mv *v, const MirInst *in) {
  MirMode *modes = MS_ARENA_NEW_ARRAY(&v->scratch, MirMode, in->nargs + 1);
  mir_arg_modes(v->cx.m, v->cx.f, in, modes);
  return modes;
}

/* ---- shape: entry block, definitions, dominance ---- */

/* Where a value is defined: `index` is -1 for a block parameter. */
typedef struct MvDef {
  bool defined;
  uint32_t block;
  int64_t index;
} MvDef;

/* The entry block's parameters mirror the signature; false when they do not. */
static bool mv_check_entry(Mv *v) {
  const MirFunc *f = v->cx.f;
  const MirBlockData *entry = &f->blocks.ptr[0];
  if (entry->params.len != f->nparams) {
    mv_err(v, 0, "entry block parameters do not match the function signature");
    return false;
  }
  for (uint32_t i = 0; i < f->nparams; i++) {
    const MirBlockParam *bp = &entry->params.ptr[i];
    const MirParam *p = &f->params[i];
    if (bp->value >= f->values.len || mv_ty(v, bp->value) != p->ty ||
      (v->cx.drops[p->ty] && bp->mode != p->mode)) {
      mv_err(v, 0, "entry block parameter differs from the signature");
      return false;
    }
  }
  return true;
}

static void mv_check_function_kind(Mv *v) {
  const MirFunc *f = v->cx.f;
  if (f->kind == MFK_NORMAL) {
    return;
  }
  if (f->nparams == 0 || f->params[0].ty != MIR_PTR) {
    mv_err(v, MIR_NONE, "closure and method functions take the erased environment/receiver as parameter 0 (ptr)");
  }
  if (f->nparams > 0 && f->params[0].mode == MM_MOVE) {
    mv_err(v, MIR_NONE, "closure and method functions borrow their environment/receiver");
  }
}

static void mv_define(Mv *v, MvDef *defs, MirValue x, uint32_t block, int64_t index,
           const char *what) {
  if (x >= v->cx.f->values.len) {
    mv_err(v, MIR_NONE, "%s Value(%u) out of range", what, x);
  } else if (defs[x].defined) {
    mv_err(v, MIR_NONE, "%%%u defined twice", x);
  } else {
    defs[x] = (MvDef){true, block, index};
  }
}

static MvDef *mv_collect_defs(Mv *v) {
  const MirFunc *f = v->cx.f;
  MvDef *defs = MS_ARENA_NEW_ARRAY(&v->scratch, MvDef, f->values.len + 1);
  __builtin_memset(defs, 0, sizeof *defs * (f->values.len + 1));
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    const MirBlockData *blk = &f->blocks.ptr[b];
    for (uint32_t i = 0; i < blk->params.len; i++) {
      mv_define(v, defs, blk->params.ptr[i].value, b, -1, "block parameter");
    }
    for (uint32_t i = 0; i < blk->insts.len; i++) {
      if (blk->insts.ptr[i].res != MIR_NONE) {
        mv_define(v, defs, blk->insts.ptr[i].res, b, (int64_t)i, "result");
      }
    }
  }
  return defs;
}

/* The dominator tree as entry and exit numbers of a depth-first walk, so "a dominates b" is two
 * comparisons rather than a climb up the tree: that climb made a use of a value defined at the top of
 * a long function cost its depth, and verification quadratic. Unreachable blocks have no numbers. */
typedef struct MvFlow {
  const MvDef *defs;
  const uint32_t *tin;
  const uint32_t *tout;
} MvFlow;

static MvFlow mv_flow(Mv *v, const MvDef *defs, const MirBlock *idom) {
  const uint32_t n = v->cx.f->blocks.len;
  uint32_t *tin = MS_ARENA_NEW_ARRAY(&v->scratch, uint32_t, n);
  uint32_t *tout = MS_ARENA_NEW_ARRAY(&v->scratch, uint32_t, n);
  uint32_t *child = MS_ARENA_NEW_ARRAY(&v->scratch, uint32_t, n); /* first child, then the next sibling chain */
  uint32_t *sibling = MS_ARENA_NEW_ARRAY(&v->scratch, uint32_t, n);
  uint32_t *stack = MS_ARENA_NEW_ARRAY(&v->scratch, uint32_t, n);
  for (uint32_t b = 0; b < n; b++) {
    tin[b] = tout[b] = child[b] = sibling[b] = MIR_NONE;
  }
  for (uint32_t b = n; b-- > 1;) {
    if (idom[b] != MIR_NONE && idom[b] != b) {
      sibling[b] = child[idom[b]];
      child[idom[b]] = b;
    }
  }
  uint32_t clock = 0, top = 0;
  if (n > 0) {
    tin[0] = clock++;
    stack[top++] = 0;
  }
  while (top > 0) {
    const uint32_t b = stack[top - 1];
    const uint32_t next = child[b];
    if (next == MIR_NONE) {
      tout[b] = clock++;
      top--;
    } else {
      child[b] = sibling[next];
      tin[next] = clock++;
      stack[top++] = next;
    }
  }
  return (MvFlow){defs, tin, tout};
}

static bool mv_dominates(const MvFlow *flow, MirBlock a, MirBlock b) {
  if (a == b) {
    return true;
  }
  if (flow->tin[a] == MIR_NONE || flow->tin[b] == MIR_NONE) {
    return false;
  }
  return flow->tin[a] < flow->tin[b] && flow->tout[b] < flow->tout[a];
}

/* Whether the use of `x` at instruction `index` of `block` follows its definition. */
static bool mv_use_ok(Mv *v, const MvFlow *flow, MirValue x, MirBlock block, int64_t index,
           const char *what) {
  if (x >= v->cx.f->values.len || !flow->defs[x].defined) {
    mv_err(v, block, "%s: use of undefined value %%%u", what, x);
    return false;
  }
  const MvDef *d = &flow->defs[x];
  bool ok = d->block == block ? d->index < index : mv_dominates(flow, d->block, block);
  if (!ok) {
    mv_err(v, block, "%s: %%%u does not dominate its use", what, x);
  }
  return ok;
}

/* ---- per-instruction and per-terminator checks ---- */

static void mv_check_inst(Mv *v, const MvFlow *flow, MirBlock bi, uint32_t ii) {
  const MirInst *in = &v->cx.f->blocks.ptr[bi].insts.ptr[ii];
  const char *name = mv_op_name(in);
  if (v->require_locs && mir_loc_none(in->loc)) {
    mv_err(v, bi, "%s: missing source location", name);
  }
  /* The lowering re-invokes the function from the check on a new stack segment with the entry
   * block's parameters, so nothing may run before it. */
  if (in->op == MOP_DepthEnter && (bi != 0 || ii != 0)) {
    mv_err(v, bi, "%s: must be the first instruction of the entry block", name);
  }
  bool ok = true;
  for (uint32_t k = 0; k < in->nargs; k++) {
    ok &= mv_use_ok(v, flow, in->args[k], bi, (int64_t)ii, name);
  }
  if ((mir_op_info[in->op].has_result != 0) != (in->res != MIR_NONE)) {
    mv_err(v, bi, "%s: result presence does not match the opcode", name);
    return;
  }
  if (!ok) {
    return;
  }
  MsSpan why = mir_verify_inst_types(&v->cx, in);
  if (why.len != 0) {
    mv_err(v, bi, "%s: %S", name, why);
  }
}

typedef struct MvUses {
  Mv *v;
  const MvFlow *flow;
  MirBlock block;
  int64_t index;
  bool ok;
} MvUses;

static void mv_term_use(void *ctx, MirValue *x) { // NOLINT(readability-non-const-parameter): the MirUseFn signature lets other users rewrite the operand
  MvUses *u = ctx;
  u->ok &= mv_use_ok(u->v, u->flow, *x, u->block, u->index, "terminator");
}

static void mv_check_target(Mv *v, MirBlock bi, const MirTarget *t) {
  const MirFunc *f = v->cx.f;
  if (t->block >= f->blocks.len) {
    mv_err(v, bi, "branch to a nonexistent block");
    return;
  }
  const MirBlockData *dest = &f->blocks.ptr[t->block];
  if (t->nargs != dest->params.len) {
    mv_err(v, bi, "branch to b%u passes %u arguments for %u parameters", t->block, t->nargs,
       (uint32_t)dest->params.len);
    return;
  }
  for (uint32_t k = 0; k < t->nargs; k++) {
    MirTy have = mv_ty(v, t->args[k]), want = mv_ty(v, dest->params.ptr[k].value);
    if (have != want) {
      MsSpan have_name = mv_type_name(v, have);
      mv_err(v, bi, "branch to b%u: argument %%%u has type %S but the parameter has %S",
         t->block, t->args[k], have_name, mv_type_name(v, want));
    }
  }
}

static void mv_check_term_kind(Mv *v, MirBlock bi) {
  const MirFunc *f = v->cx.f;
  const MirTerm *t = &f->blocks.ptr[bi].term;
  switch ((MirTermKind)t->kind) {
  case MT_CONDBR:
    if (mv_ty(v, t->value) != MIR_BOOL) {
      mv_err(v, bi, "condition must be bool");
    }
    break;
  case MT_SWITCH:
    if (mv_ty(v, t->value) != MIR_INT) {
      mv_err(v, bi, "switch value must be int");
    }
    break;
  case MT_RET: {
    MirTy ty = t->value == MIR_NONE ? (MirTy)MIR_VOID : mv_ty(v, t->value);
    if (ty != f->ret) {
      MsSpan have = mv_type_name(v, ty);
      mv_err(v, bi, "returns %S but the function returns %S", have, mv_type_name(v, f->ret));
    }
    break;
  }
  case MT_FAULT:
    if (t->fault == MF_MESSAGE && t->fault_str >= ms_names_count(&v->cx.m->strings)) {
      mv_err(v, bi, "fault message literal out of range");
    }
    break;
  case MT_BR: case MT_UNREACHABLE:
    break;
  }
}

static void mv_check_term(Mv *v, const MvFlow *flow, MirBlock bi) {
  MirBlockData *blk = &v->cx.f->blocks.ptr[bi];
  MirTerm term = blk->term; /* a copy: the use walk takes a mutable terminator */
  MvUses uses = {v, flow, bi, (int64_t)blk->insts.len, true};
  mir_term_each_use(&term, mv_term_use, &uses);
  if (!uses.ok) {
    return;
  }
  for (uint32_t k = 0; k < mir_term_ntargets(&term); k++) {
    mv_check_target(v, bi, mir_term_target_const(&term, k));
  }
  mv_check_term_kind(v, bi);
}

static void mv_check_block(Mv *v, const MvFlow *flow, MirBlock bi) {
  for (uint32_t ii = 0; ii < v->cx.f->blocks.ptr[bi].insts.len; ii++) {
    mv_check_inst(v, flow, bi, ii);
  }
  mv_check_term(v, flow, bi);
}

/* ---- one function ---- */

static void mv_check_blocks(Mv *v, const MvDef *defs) {
  const MirFunc *f = v->cx.f;
  MirBlock *rpo = NULL;
  uint32_t count = mir_rpo(&v->scratch, f, &rpo);
  MirPreds preds = mir_preds(&v->scratch, f);
  if (mir_preds_count(&preds, 0) > 0) {
    mv_err(v, 0, "the entry block must not have predecessors");
  }
  MvFlow flow = mv_flow(v, defs, mir_dominators(&v->scratch, f, rpo, count, &preds));
  for (uint32_t i = 0; i < count; i++) {
    mv_check_block(v, &flow, rpo[i]);
  }
  /* A Raw function leaves its drops to `elaborate`, so its ownership is checked after it. */
  if (mv_clean(v) && !mv_is_raw(f)) {
    mv_check_ownership(v, rpo, count);
  }
}

static void mv_run(Mv *v) {
  const MirFunc *f = v->cx.f;
  if (f->blocks.len == 0) {
    mv_err(v, MIR_NONE, "function has no blocks");
    return;
  }
  if (!mv_check_entry(v)) {
    return;
  }
  mv_check_function_kind(v);
  const MvDef *defs = mv_collect_defs(v);
  if (!mv_clean(v)) {
    return;
  }
  mv_check_blocks(v, defs);
}

static void mv_function(MirVerifyErrors *errs, const MirModule *m, const MirFunc *f, const bool *drops,
                        MirLayouts *layouts, bool require_locs) {
  Mv v = {.errs = errs,
      .cx = {m, f, drops, &errs->arena, layouts},
      .scratch = {0},
      .require_locs = require_locs,
      .first = errs->errors.len};
  mv_run(&v);
  if (mv_clean(&v)) {
    mv_scoped_closures(&v);
  }
  ms_arena_free(&v.scratch);
}

/* ---- module ---- */

static void mv_module_err(MirVerifyErrors *errs, const char *fmt, ...);

static void mv_module_err(MirVerifyErrors *errs, const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  MsSpan message = ms_message_vformat(&errs->arena, fmt, ap);
  va_end(ap);
  MsSpan func = ms_span_of_text("<module>");
  mv_push(errs, func, MIR_NONE, message);
}

static MsSpan mv_sym(MirVerifyErrors *errs, const MirModule *m, MsName s) {
  return ms_arena_copy(&errs->arena, ms_names_span(&m->names, s));
}

/* Whether `f` implements interface method `sig`: a method function taking the receiver first. */
static bool mv_implements(const MirFunc *f, const MirMethodSig *sig) {
  if (f->kind != MFK_METHOD || f->nparams != sig->nparams + 1 || f->ret != sig->ret) {
    return false;
  }
  for (uint32_t k = 0; k < sig->nparams; k++) {
    const MirParam *p = &f->params[k + 1];
    if (p->ty != sig->params[k] || (p->mode == MM_MOVE) != mir_owns(sig->owned, k)) {
      return false;
    }
  }
  return true;
}

static void mv_check_vtable(MirVerifyErrors *errs, const MirModule *m, uint32_t index) {
  const MirVtable *vt = &m->vtables.ptr[index];
  const MirIfaceDef *iface = &m->ifaces.ptr[vt->iface];
  if (vt->nmethods != iface->nmethods) {
    mv_module_err(errs, "vtable %S has %u methods, interface %S has %u", mv_sym(errs, m, vt->name),
           vt->nmethods, mv_sym(errs, m, iface->name), iface->nmethods);
    return;
  }
  for (uint32_t k = 0; k < vt->nmethods; k++) {
    const MirFunc *f = &m->funcs.ptr[vt->methods[k]];
    if (!mv_implements(f, &iface->methods[k])) {
      mv_module_err(errs, "vtable %S (#%u): function %S does not implement method %S",
             mv_sym(errs, m, vt->name), index, mv_sym(errs, m, f->name),
             mv_sym(errs, m, iface->methods[k].name));
    }
  }
}

static void mv_check_declarations(MirVerifyErrors *errs, const MirModule *m) {
  for (uint32_t i = 0; i < m->vtables.len; i++) {
    mv_check_vtable(errs, m, i);
  }
  if (m->entry != MIR_NONE) {
    const MirFunc *f = &m->funcs.ptr[m->entry];
    if (f->nparams != 0 || f->ret != MIR_INT) {
      mv_module_err(errs, "entry %S must be fn() -> int", mv_sym(errs, m, f->name));
    }
  }
}

bool mir_verify_module(const MirModule *m, bool require_locs, MirVerifyErrors *out) {
  mv_check_declarations(out, m);
  MsArena scratch = ms_arena_new();
  MirLayouts layouts;
  mir_layouts_init(&layouts, m);
  bool *drops = MS_ARENA_NEW_ARRAY(&scratch, bool, m->types.kinds.len + 1);
  for (uint32_t t = 0; t < m->types.kinds.len; t++) {
    drops[t] = mir_needs_drop(m, t);
  }
  for (uint32_t i = 0; i < m->funcs.len; i++) {
    mv_function(out, m, &m->funcs.ptr[i], drops, &layouts, require_locs);
  }
  mir_layouts_free(&layouts);
  ms_arena_free(&scratch);
  return out->errors.len == 0;
}
