/* The `simplify` pass, in-place mutators: round trips through memory, shields and put-takes. */
#include "compiler/opt/opt_simplify.h"

/* ---- in-place mutators ---- */

typedef struct SmRoundtrip {
  uint32_t put_in, call, take_out, put_back;
  MirValue slot;
} SmRoundtrip;

static bool sm_has_arg(const MirInst *i, MirValue v) {
  for (uint32_t k = 0; k < i->nargs; k++) {
    if (i->args[k] == v) {
      return true;
    }
  }
  return false;
}

/* The first live instruction after `from` that satisfies `want`; false when there is none. */
static bool sm_find_after(const MirBlockData *b, const bool *removed, uint32_t from, MirOp op,
             MirValue arg, int slot_pos, uint32_t *out) {
  for (uint32_t k = from; k < b->insts.len; k++) {
    const MirInst *i = &b->insts.ptr[k];
    if (removed[k]) {
      continue;
    }
    const bool match = op == MOP_COUNT ? sm_has_arg(i, arg)
                     : i->op == op && i->nargs > (uint32_t)slot_pos &&
                        i->args[slot_pos] == arg;
    if (match) {
      *out = k;
      return true;
    }
  }
  return false;
}

/* The instruction indexes of the sequence starting with the `take` at `at`:
 * `(put into slot, call, take from slot, put back, slot)`. Instructions marked in `removed` are no
 * longer part of the block. */
static bool sm_find_roundtrip(const MirBlockData *b, const bool *removed, uint32_t at,
               const uint32_t *uses, SmRoundtrip *out) {
  const MirInst *first = &b->insts.ptr[at];
  if (first->op != MOP_Take || first->res == MIR_NONE) {
    return false;
  }
  const MirValue a = first->res, p = first->args[0];
  if (uses[a] != 1) {
    return false;
  }
  uint32_t put_in = 0;
  if (!sm_find_after(b, removed, at + 1, MOP_Put, a, 1, &put_in)) {
    return false;
  }
  const MirValue slot = b->insts.ptr[put_in].args[0];
  bool def = false;
  for (uint32_t k = put_in; k-- > 0 && !def;) {
    const MirInst *d = &b->insts.ptr[k];
    def = !removed[k] && d->res == slot && d->op == MOP_Slot && opt_imm_eq(&d->imm, &first->imm);
  }
  if (!def || uses[slot] != 3) {
    return false;
  }
  uint32_t call = 0, take_out = 0, put_back = 0;
  if (!sm_find_after(b, removed, put_in + 1, MOP_COUNT, slot, 0, &call)) {
    return false;
  }
  uint32_t slot_uses = 0;
  for (uint32_t k = 0; k < b->insts.ptr[call].nargs; k++) {
    slot_uses += b->insts.ptr[call].args[k] == slot;
  }
  if (b->insts.ptr[call].op != MOP_CallRt || slot_uses != 1) {
    return false;
  }
  if (!sm_find_after(b, removed, call + 1, MOP_COUNT, slot, 0, &take_out)) {
    return false;
  }
  const MirInst *tk = &b->insts.ptr[take_out];
  if (tk->op != MOP_Take || tk->res == MIR_NONE) {
    return false;
  }
  const MirValue bv = tk->res;
  if (uses[bv] != 1 || !opt_imm_eq(&tk->imm, &first->imm)) {
    return false;
  }
  if (!sm_find_after(b, removed, take_out + 1, MOP_COUNT, bv, 0, &put_back)) {
    return false;
  }
  const MirInst *pb = &b->insts.ptr[put_back];
  if (pb->op != MOP_Put || pb->nargs != 2 || pb->args[0] != p || pb->args[1] != bv) {
    return false;
  }
  /* The memory at `p` is touched by nothing else in the window, and nothing else in it can read
   * or write through another pointer. */
  for (uint32_t k = at + 1; k < put_back; k++) {
    if (removed[k] || k == put_in || k == call || k == take_out) {
      continue;
    }
    const MirInst *w = &b->insts.ptr[k];
    if (sm_has_arg(w, p) || mir_op_info[w->op].effects != 0) {
      return false;
    }
  }
  *out = (SmRoundtrip){put_in, call, take_out, put_back, slot};
  return true;
}

/* Turns the move-out, call, move-back sequence lowering emits around a runtime mutator of a value
 * held in memory (`a = take P; put S, a; call f(S); b = take S; put P, b`) into a call that mutates
 * `P` directly. */
bool opt_simplify_roundtrips(MirFunc *f) {
  MsArena arena = ms_arena_new();
  uint32_t *uses = mir_use_counts(&arena, f);
  bool changed = false;
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    MirBlockData *b = &f->blocks.ptr[bi];
    bool *removed = MS_ARENA_NEW_ARRAY(&arena, bool, b->insts.len);
    bool any = false;
    for (uint32_t i = 0; i < b->insts.len; i++) {
      SmRoundtrip rt;
      if (removed[i] || !sm_find_roundtrip(b, removed, i, uses, &rt)) {
        continue;
      }
      const MirValue p = b->insts.ptr[i].args[0];
      for (uint32_t k = 0; k < b->insts.ptr[rt.call].nargs; k++) {
        if (b->insts.ptr[rt.call].args[k] == rt.slot) {
          b->insts.ptr[rt.call].args[k] = p;
        }
      }
      removed[rt.put_back] = removed[rt.take_out] = removed[rt.put_in] = removed[i] = true;
      any = true;
    }
    if (any) {
      uint32_t *list = MS_ARENA_NEW_ARRAY(&arena, uint32_t, (size_t)b->insts.len + 1);
      uint32_t n = 0;
      for (uint32_t k = 0; k < b->insts.len; k++) {
        if (removed[k]) {
          list[n++] = k;
        }
      }
      mir_block_remove(b, list, n);
      changed = true;
    }
  }
  ms_arena_free(&arena);
  return changed;
}

static uint8_t sm_role(const MirModule *m, const MirInst *inst) {
  return inst->op == MOP_CallRt && inst->imm.tag == MI_EXT ? m->externs.ptr[inst->imm.a].role
                               : (uint8_t)MR_NONE;
}

/* Whether no stop request can arrive inside `inst`: plain operations and leaf runtime calls. */
static bool sm_quiet(const MirModule *m, const MirInst *inst) {
  switch ((MirOp)inst->op) {
  case MOP_Poll: case MOP_CallInd: case MOP_CallMethod: case MOP_Call:
    return false;
  case MOP_CallRt:
    if (inst->imm.tag == MI_EXT) {
      const MirExtern *d = &m->externs.ptr[inst->imm.a];
      return d->leaf || d->noreturn;
    }
    return true;
  default:
    return true;
  }
}

/* A shield pair around code that cannot reach a cancellation point shields nothing: the
 * instructions between `shield_enter` and the next `shield_exit` of a block are plain operations
 * and leaf runtime calls, so no stop request can arrive inside. Both calls go. */
bool opt_simplify_shields(MirModule *m, MirFunc *f) {
  MsArena arena = ms_arena_new();
  bool changed = false;
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    MirBlockData *b = &f->blocks.ptr[bi];
    bool *removed = MS_ARENA_NEW_ARRAY(&arena, bool, b->insts.len);
    bool is_open = false;
    uint32_t at = 0, count = 0;
    for (uint32_t i = 0; i < b->insts.len; i++) {
      const uint8_t role = sm_role(m, &b->insts.ptr[i]);
      if (role == MR_SHIELD_ENTER) {
        is_open = true;
        at = i;
      } else if (role == MR_SHIELD_EXIT && is_open) {
        removed[at] = removed[i] = true;
        count += 2;
        is_open = false;
        changed = true;
      } else if (is_open && !sm_quiet(m, &b->insts.ptr[i])) {
        is_open = false;
      }
    }
    if (count > 0) {
      uint32_t *list = MS_ARENA_NEW_ARRAY(&arena, uint32_t, (size_t)count + 1);
      uint32_t n = 0;
      for (uint32_t k = 0; k < b->insts.len; k++) {
        if (removed[k]) {
          list[n++] = k;
        }
      }
      mir_block_remove(b, list, n);
    }
  }
  ms_arena_free(&arena);
  return changed;
}

/* A value put into a slot and taken straight back out (inlining a callee that receives its
 * argument through a slot leaves `put S, v; r = take S`) is `v` itself: the pair is deleted and `r`
 * renamed to `v`, and only pure instructions may sit between the two. */
bool opt_simplify_put_takes(MirFunc *f) {
  MsArena arena = ms_arena_new();
  OptSubst subst = opt_subst_new(&arena, (uint32_t)f->values.len);
  bool **dead = opt_dead_flags(&arena, f);
  bool any = false;
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    const MirBlockData *b = &f->blocks.ptr[bi];
    for (uint32_t pi = 0; pi < b->insts.len; pi++) {
      const MirInst *put = &b->insts.ptr[pi];
      if (put->op != MOP_Put) {
        continue;
      }
      const MirValue slot = put->args[0], v = put->args[1];
      for (uint32_t ti = pi + 1; ti < b->insts.len; ti++) {
        const MirInst *take = &b->insts.ptr[ti];
        if (take->op == MOP_Take && take->args[0] == slot) {
          if (take->res != MIR_NONE && f->values.ptr[take->res] == f->values.ptr[v]) {
            opt_subst_set(&subst, take->res, v);
            dead[bi][pi] = dead[bi][ti] = true;
            any = true;
          }
          break;
        }
        if (sm_has_arg(take, slot) || mir_op_info[take->op].effects != 0) {
          break;
        }
      }
    }
  }
  if (any) {
    opt_sweep_dead(f, (bool *const *)dead, &arena);
    opt_subst_apply(f, &subst);
  }
  ms_arena_free(&arena);
  return any;
}

