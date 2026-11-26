/* The `splitview` pass: a split whose list the function only reads in place is answered without a heap list.
 *
 * `text.split(sep)` of a variable lowers to `split_view`, the pieces of which are views of the text; the call still
 * allocates and fills a list. The runtime declares two twins of it (`@twin=split_view` on the extern):
 *
 *   - `split_first`: element 0 as a single value. When the list's only uses are reads of element 0 right after
 *     the call and its drop (`line.split(" ")[0]`), the call becomes `split_first` and no list is made.
 *   - `split_view_into`: the pieces of a short text go to a buffer in the caller's frame, and the list then owns
 *     nothing. When the list is only read (`list.len`, `list.get`) and dropped, it never leaves the function, so
 *     the buffer outlives it; a longer text or more than eight pieces still gets the heap list.
 *
 * Any other use of the list (a call, a store, a return, a block argument, taking an element out) keeps the call as it
 * is. */

#include "compiler/mir/mir_analysis.h"
#include "compiler/opt/opt_pass.h"
#include "base/safe.h"

enum { SV_FRAME_PIECES = 8 };

typedef enum SvPlan { SV_KEEP, SV_FIRST, SV_FRAME } SvPlan;

/* A read of element 0: the block and the index in it. */
typedef struct SvGet {
  MirBlock block;
  uint32_t index;
} SvGet;

typedef struct SvUses {
  MirValue list;
  bool escapes;
} SvUses;

static void term_use(void *context, MirValue value) {
  SvUses *uses = context;
  uses->escapes |= value == uses->list;
}

static bool is_zero_const(const MirFunc *f, MirValue v) {
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    const MirInstList *insts = &f->blocks.ptr[b].insts;
    for (uint32_t i = 0; i < insts->len; i++) {
      if (insts->ptr[i].res == v) {
        return insts->ptr[i].op == MOP_IConst && insts->ptr[i].imm.i == 0;
      }
    }
  }
  return false;
}

/* Whether the instructions in [from, to) of `blk` only compute values (nothing the reordered call could change). */
static bool only_computes(const MirBlockData *blk, uint32_t from, uint32_t to) {
  for (uint32_t i = from; i < to; i++) {
    const uint8_t effects = mir_op_info[blk->insts.ptr[i].op].effects;
    if ((effects & (MIR_E_WRITES | MIR_E_FAULTS | MIR_E_IO | MIR_E_OWNERSHIP | MIR_E_ALLOC)) != 0) {
      return false;
    }
  }
  return true;
}

/* The block the straight line goes on in after the call at `blk.insts[call]`, when the call is followed by an unwind
 * site (the byte test and the branch to the exit): the site's fall-through block, which only this block enters.
 * MIR_NONE when no site follows. */
static MirBlock site_continuation(const MirModule *m, const MirFunc *f, MirBlock blk_index, uint32_t call) {
  const MirBlockData *blk = &f->blocks.ptr[blk_index];
  if (call + 2 != blk->insts.len || blk->term.kind != MT_CONDBR) {
    return MIR_NONE;
  }
  const MirInst *test = &blk->insts.ptr[call + 1];
  if (test->op != MOP_CallRt || test->imm.tag != MI_EXT || m->externs.ptr[test->imm.a].role != MR_UNWINDING ||
      test->res != blk->term.value) {
    return MIR_NONE;
  }
  const MirBlock next = blk->term.b.block;
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    const MirTerm *term = &f->blocks.ptr[b].term;
    if (b != blk_index && ((term->kind == MT_BR && term->a.block == next) || (term->kind == MT_CONDBR && (term->a.block == next || term->b.block == next)))) {
      return MIR_NONE;
    }
  }
  return next;
}

/* How the list `l` made by the call at `blk.insts[call]` is used: the plan, and for SV_FIRST the instructions that read
 * element 0 (in `gets`, `*nget` of them, at most `max`). */
static SvPlan plan_of(const MirModule *m, const MirFunc *f, MirBlock blk_index, uint32_t call, MirValue l,
                      SvGet *gets, uint32_t *nget, uint32_t max) {
  SvUses uses = {.list = l};
  const MirBlock after = site_continuation(m, f, blk_index, call);
  bool first_only = true;
  *nget = 0;
  for (uint32_t b = 0; b < f->blocks.len && !uses.escapes; b++) {
    const MirBlockData *blk = &f->blocks.ptr[b];
    for (uint32_t i = 0; i < blk->insts.len; i++) {
      const MirInst *inst = &blk->insts.ptr[i];
      bool mentions = false;
      for (uint32_t k = 0; k < inst->nargs; k++) {
        mentions |= inst->args[k] == l;
      }
      if (!mentions) {
        continue;
      }
      if ((inst->op == MOP_Drop || inst->op == MOP_Forget) && inst->nargs == 1) {
        continue; /* the list's release, on the normal path or on an exit */
      }
      if (inst->op == MOP_ListLen && inst->nargs == 1) {
        first_only = false;
        continue;
      }
      if ((inst->op == MOP_ListGetU || inst->op == MOP_ListAddr || inst->op == MOP_ListAddrU) && inst->nargs == 2 &&
          inst->args[0] == l && inst->args[1] != l) {
        first_only = false; /* a read of an element that is not known to be the first */
        continue;
      }
      if ((inst->op == MOP_ListGet || inst->op == MOP_ListGetNn) && inst->nargs == 2 && inst->args[0] == l &&
          inst->args[1] != l) {
        const bool here = b == blk_index && i > call && only_computes(blk, call + 1, i);
        const bool past_site = after != MIR_NONE && b == after && only_computes(blk, 0, i);
        if ((here || past_site) && *nget < max && is_zero_const(f, inst->args[1])) {
          gets[(*nget)++] = (SvGet){.block = b, .index = i};
        } else {
          first_only = false;
        }
        continue;
      }
      uses.escapes = true;
    }
    mir_term_each_value(&blk->term, term_use, &uses);
  }
  if (uses.escapes) {
    return SV_KEEP;
  }
  return first_only && *nget > 0 ? SV_FIRST : SV_FRAME;
}

/* The record type of the frame buffer: eight strings. */
static MirTy frame_type(MirModule *m) {
  const MsName name = mir_name(m, ms_span_of_text("SplitFrame"));
  uint32_t id = mir_type_by_name(m, name);
  if (id == MIR_NONE) {
    id = mir_add_type(m, name);
    MirField *fields = MS_ARENA_NEW_ARRAY(&m->arena, MirField, SV_FRAME_PIECES);
    for (uint32_t k = 0; k < SV_FRAME_PIECES; k++) {
      fields[k] = (MirField){mir_name(m, ms_span_of_text("piece")), MIR_STR, 0, false};
    }
    m->type_defs.ptr[id].fields = fields;
    m->type_defs.ptr[id].nfields = SV_FRAME_PIECES;
  }
  return mir_ty_type(m, id);
}

static bool rewrite_one(MirModule *m, MirFunc *f) {
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      MirInst *call = &f->blocks.ptr[b].insts.ptr[i];
      if (call->op != MOP_CallRt || call->imm.tag != MI_EXT || call->nargs != 2 || call->res == MIR_NONE ||
          m->externs.ptr[call->imm.a].twin != MTW_SPLIT_VIEW) {
        continue;
      }
      const MirTyData *list = mir_ty_data(m, mir_value_ty(f, call->res));
      if (list->kind != MK_LIST || list->elem != MIR_STR) {
        continue;
      }
      SvGet gets[8];
      uint32_t nget = 0;
      const SvPlan plan = plan_of(m, f, b, i, call->res, gets, &nget, 8);
      if (plan == SV_KEEP) {
        continue;
      }
      const MirValue text = call->args[0], separator = call->args[1], l = call->res;
      MirBlockData *blk = &f->blocks.ptr[b];
      if (plan == SV_FRAME) {
        const MirTy str_pair[3] = {MIR_STR, MIR_STR, MIR_PTR};
        const uint32_t into = mir_extern_get(m, ms_span_of_text("msrt_string_split_view_into"), str_pair, 3, mir_value_ty(f, l),
                                             false, MR_VIEW_RESULT);
        const MirValue buffer = mir_new_value(f, MIR_PTR);
        const MirLoc loc = call->loc;
        const MirInst slot = mir_inst(MOP_Slot, (MirImm){.tag = MI_TY, .a = frame_type(m)}, buffer, loc, NULL, 0);
        mir_block_insert(blk, i, &slot);
        call = &blk->insts.ptr[i + 1];
        const MirValue args[3] = {text, separator, buffer};
        call->args = mir_args_copy(m, args, 3);
        call->nargs = 3;
        call->imm = mir_imm_ext(into);
        return true;
      }
      const MirTy str_pair[2] = {MIR_STR, MIR_STR};
      const uint32_t first = mir_extern_get(m, ms_span_of_text("msrt_string_split_first"), str_pair, 2, MIR_STR, false,
                                            MR_VIEW_RESULT);
      const MirValue piece = mir_new_value(f, MIR_STR);
      call->res = piece;
      call->imm = mir_imm_ext(first);
      /* Element 0 reads become the piece, and the drops of the list drop it. */
      for (uint32_t k = 0; k < nget; k++) {
        mir_func_replace_uses(f, f->blocks.ptr[gets[k].block].insts.ptr[gets[k].index].res, piece);
      }
      for (uint32_t k = 0; k < nget; k++) { /* the reads leave their blocks, a block at a time */
        if (gets[k].index == UINT32_MAX) {
          continue;
        }
        uint32_t *dead = MS_ARENA_NEW_ARRAY(&m->arena, uint32_t, nget);
        uint32_t ndead = 0;
        for (uint32_t j = k; j < nget; j++) {
          if (gets[j].block == gets[k].block) {
            dead[ndead++] = gets[j].index;
            gets[j].index = j == k ? gets[j].index : UINT32_MAX;
          }
        }
        mir_block_remove(&f->blocks.ptr[gets[k].block], dead, ndead);
        gets[k].index = UINT32_MAX;
      }
      for (uint32_t x = 0; x < f->blocks.len; x++) {
        MirBlockData *other = &f->blocks.ptr[x];
        for (uint32_t y = 0; y < other->insts.len; y++) {
          MirInst *inst = &other->insts.ptr[y];
          if ((inst->op == MOP_Drop || inst->op == MOP_Forget) && inst->nargs == 1 && inst->args[0] == l) {
            inst->args[0] = piece; /* the piece is the call's own result, dropped where the list was */
          }
        }
      }
      return true;
    }
  }
  return false;
}

bool opt_splitview(MirModule *m) {
  bool changed = false;
  for (uint32_t fi = 0; fi < m->funcs.len; fi++) {
    while (rewrite_one(m, &m->funcs.ptr[fi])) {
      changed = true;
    }
  }
  return changed;
}
