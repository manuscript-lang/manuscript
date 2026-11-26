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

/* The list and the block parameters it reaches through branches that pass it or an exit's `undef` (an inlined
 * callee's result): the same list under another name. */
enum { SV_ALIASES = 8 };

typedef struct SvUses {
  MirValue alias[SV_ALIASES]; /* alias[0] is the list the call made */
  uint32_t count;
  uint32_t seen; /* the uses of an alias among a terminator's values */
  bool escapes;
} SvUses;

static bool is_alias(const SvUses *uses, MirValue value) {
  for (uint32_t k = 0; k < uses->count; k++) {
    if (uses->alias[k] == value) {
      return true;
    }
  }
  return false;
}

static void term_use(void *context, MirValue value) {
  SvUses *uses = context;
  uses->seen += is_alias(uses, value);
}

/* Whether `value` is an `undef`: the placeholder an exit path passes where a result would go. */
static bool is_undef(const MirFunc *f, MirValue value) {
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    const MirInstList *insts = &f->blocks.ptr[b].insts;
    for (uint32_t i = 0; i < insts->len; i++) {
      if (insts->ptr[i].res == value) {
        return insts->ptr[i].op == MOP_Undef;
      }
    }
  }
  return false;
}

/* Whether argument `k` of every branch into `block` is an alias or an `undef` (an exit path), so the parameter holds
 * the list or nothing. */
static bool only_list_enters(const MirFunc *f, MirBlock block, uint32_t k, const SvUses *uses) {
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    const MirTerm *term = &f->blocks.ptr[b].term;
    for (uint32_t t = 0; t < mir_term_ntargets(term); t++) {
      const MirTarget *target = mir_term_target_const(term, t);
      if (target->block == block &&
          (k >= target->nargs || (!is_alias(uses, target->args[k]) && !is_undef(f, target->args[k])))) {
        return false;
      }
    }
  }
  return true;
}

/* The block parameter that a branch of `term` passes an alias to, when every entry passes the list or an `undef`; the number of
 * such branches is added to `*taken`. Adds the parameters it finds to the aliases and reports whether it added one. */
static bool follow_edges(const MirFunc *f, const MirTerm *term, SvUses *uses, uint32_t *taken) {
  bool added = false;
  for (uint32_t t = 0; t < mir_term_ntargets(term); t++) {
    const MirTarget *target = mir_term_target_const(term, t);
    const MirBlockData *dest = &f->blocks.ptr[target->block];
    for (uint32_t k = 0; k < target->nargs && k < dest->params.len; k++) {
      if (!is_alias(uses, target->args[k]) || !only_list_enters(f, target->block, k, uses)) {
        continue;
      }
      *taken += 1;
      const MirValue param = dest->params.ptr[k].value;
      if (!is_alias(uses, param) && uses->count < SV_ALIASES) {
        uses->alias[uses->count++] = param;
        added = true;
      }
    }
  }
  return added;
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

/* Whether the block ends in the test of an unwind site (its only instruction is the byte test): the branch to the exit
 * is not taken on the straight line. */
static bool is_site_test(const MirModule *m, const MirBlockData *blk) {
  if (blk->insts.len != 1 || blk->term.kind != MT_CONDBR) {
    return false;
  }
  const MirInst *test = &blk->insts.ptr[0];
  return test->op == MOP_CallRt && test->imm.tag == MI_EXT && m->externs.ptr[test->imm.a].role == MR_UNWINDING &&
         test->res == blk->term.value;
}

/* Whether block `to` is `from` or follows it along unconditional branches and unwind sites, every block on the way only
 * computing (the straight line of an inlined callee that returns the list; other entries of a block carry no list). */
static bool past_site_read(const MirModule *m, const MirFunc *f, MirBlock from, MirBlock to) {
  MirBlock cur = from;
  for (uint32_t steps = 0; steps < f->blocks.len; steps++) {
    if (cur == to) {
      return true;
    }
    const MirBlockData *blk = &f->blocks.ptr[cur];
    if (is_site_test(m, blk)) {
      cur = blk->term.b.block;
    } else if (blk->term.kind == MT_BR && only_computes(blk, 0, (uint32_t)blk->insts.len)) {
      cur = blk->term.a.block;
    } else {
      return false;
    }
  }
  return false;
}

/* How the list `l` made by the call at `blk.insts[call]` is used: the plan, and for SV_FIRST the instructions that read
 * element 0 (in `gets`, `*nget` of them, at most `max`). */
static SvPlan plan_of(const MirModule *m, const MirFunc *f, MirBlock blk_index, uint32_t call, MirValue l,
                      SvUses *found, SvGet *gets, uint32_t *nget, uint32_t max) {
  SvUses uses = {.alias = {l}, .count = 1};
  *found = uses;
  for (bool grown = true; grown;) {
    grown = false;
    for (uint32_t b = 0; b < f->blocks.len; b++) {
      uint32_t taken = 0;
      grown |= follow_edges(f, &f->blocks.ptr[b].term, &uses, &taken);
    }
  }
  const MirBlock after = site_continuation(m, f, blk_index, call);
  bool first_only = true;
  *nget = 0;
  for (uint32_t b = 0; b < f->blocks.len && !uses.escapes; b++) {
    const MirBlockData *blk = &f->blocks.ptr[b];
    for (uint32_t i = 0; i < blk->insts.len; i++) {
      const MirInst *inst = &blk->insts.ptr[i];
      bool mentions = false;
      for (uint32_t k = 0; k < inst->nargs; k++) {
        mentions |= is_alias(&uses, inst->args[k]);
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
          is_alias(&uses, inst->args[0]) && !is_alias(&uses, inst->args[1])) {
        first_only = false; /* a read of an element that is not known to be the first */
        continue;
      }
      if ((inst->op == MOP_ListGet || inst->op == MOP_ListGetNn) && inst->nargs == 2 && is_alias(&uses, inst->args[0]) &&
          !is_alias(&uses, inst->args[1])) {
        const bool here = b == blk_index && i > call && only_computes(blk, call + 1, i);
        const bool past_site = after != MIR_NONE && past_site_read(m, f, after, b) && only_computes(blk, 0, i);
        if ((here || past_site) && *nget < max && is_zero_const(f, inst->args[1])) {
          gets[(*nget)++] = (SvGet){.block = b, .index = i};
        } else {
          first_only = false;
        }
        continue;
      }
      uses.escapes = true;
    }
    uint32_t taken = 0;
    (void)follow_edges(f, &blk->term, &uses, &taken);
    uses.seen = 0;
    mir_term_each_value(&blk->term, term_use, &uses);
    uses.escapes |= uses.seen > taken; /* a use other than the hand-over to a single-entry block */
  }
  *found = uses;
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
      if (call->op != MOP_CallRt || call->imm.tag != MI_EXT || call->nargs != 3 || call->res == MIR_NONE ||
          m->externs.ptr[call->imm.a].twin != MTW_SPLIT_VIEW) {
        continue;
      }
      const MirTyData *list = mir_ty_data(m, mir_value_ty(f, call->res));
      if (list->kind != MK_LIST || list->elem != MIR_STR) {
        continue;
      }
      SvGet gets[8];
      SvUses aliases;
      uint32_t nget = 0;
      const SvPlan plan = plan_of(m, f, b, i, call->res, &aliases, gets, &nget, 8);
      if (plan == SV_KEEP) {
        continue;
      }
      const MirValue text = call->args[0], separator = call->args[1], from = call->args[2], l = call->res;
      MirBlockData *blk = &f->blocks.ptr[b];
      if (plan == SV_FRAME) {
        const MirTy wanted[4] = {MIR_STR, MIR_STR, MIR_INT, MIR_PTR};
        const uint32_t into = mir_extern_get(m, ms_span_of_text("msrt_string_split_view_into"), wanted, 4, mir_value_ty(f, l),
                                             false, MR_VIEW_RESULT);
        const MirValue buffer = mir_new_value(f, MIR_PTR);
        const MirLoc loc = call->loc;
        const MirInst slot = mir_inst(MOP_Slot, (MirImm){.tag = MI_TY, .a = frame_type(m)}, buffer, loc, NULL, 0);
        mir_block_insert(blk, i, &slot);
        call = &blk->insts.ptr[i + 1];
        const MirValue args[4] = {text, separator, from, buffer};
        call->args = mir_args_copy(m, args, 4);
        call->nargs = 4;
        call->imm = mir_imm_ext(into);
        return true;
      }
      const MirTy wanted[3] = {MIR_STR, MIR_STR, MIR_INT};
      const uint32_t first = mir_extern_get(m, ms_span_of_text("msrt_string_split_first"), wanted, 3, MIR_STR, false,
                                            MR_VIEW_RESULT);
      const MirValue piece = mir_new_value(f, MIR_STR);
      call->res = piece;
      call->imm = mir_imm_ext(first);
      /* The block parameters that carried the list carry the piece, and the exits' `undef`s stand for a piece. */
      for (uint32_t k = 1; k < aliases.count; k++) {
        f->values.ptr[aliases.alias[k]] = MIR_STR;
      }
      for (uint32_t x = 0; x < f->blocks.len; x++) {
        const MirTerm *term = &f->blocks.ptr[x].term;
        for (uint32_t t = 0; t < mir_term_ntargets(term); t++) {
          const MirTarget *target = mir_term_target_const(term, t);
          const MirBlockData *dest = &f->blocks.ptr[target->block];
          for (uint32_t k = 0; k < target->nargs && k < dest->params.len; k++) {
            if (is_alias(&aliases, dest->params.ptr[k].value) && is_undef(f, target->args[k])) {
              f->values.ptr[target->args[k]] = MIR_STR;
            }
          }
        }
      }
      /* The piece stands where the list was (its drops, and the hand-over to the aliases), and element 0 reads become
       * the value they read: the piece, or the alias that carries it. */
      mir_func_replace_uses(f, l, piece);
      for (uint32_t k = 0; k < nget; k++) {
        const MirInst *read = &f->blocks.ptr[gets[k].block].insts.ptr[gets[k].index];
        mir_func_replace_uses(f, read->res, read->args[0]);
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
