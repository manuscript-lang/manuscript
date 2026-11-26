/* compiler/mir/mir_elab_close.c: drop elaboration, cleanup: closes or drops the owners of a scope where it
 * ends, on the paths that still hold them, and builds the error edge a failing close leaves through. */
#include "base/sort.h"
#include "compiler/mir/mir_elab.h"

static MirImm imm_ty(MirTy ty) {
  return (MirImm){.tag = MI_TY, .a = ty};
}

void em_drop_owned(ElEm *em, uint32_t at, MirValue value) {
  if (mir_needs_drop(em->m, mir_value_ty(em->f, value))) {
    em_push(em, at, MOP_Drop, &value, 1, mir_imm_none(), EM_NO_RESULT);
  }
}

static MirValue em_is_error(ElEm *em, uint32_t at, MirValue result) {
  const MirValue tag = em_push(em, at, MOP_AltTag, &result, 1, mir_imm_none(), MIR_INT);
  const MirValue error = em_iconst(em, at, 1); /* the `Error` case of a Result */
  const MirValue pair[2] = {tag, error};
  return em_push(em, at, MOP_ICmp, pair, 2, mir_imm_cc(MCC_EQ), MIR_BOOL);
}

/* Whether the shield calls exist; the error says a closing owner needs them otherwise. */
static bool shield_ready(ElEm *em) {
  return em->cx->shield_enter != MIR_NONE || el_fail(em->cx, "a closing owner needs the shield calls");
}

/* What a `slot_close` thunk left in the slot is taken out and dropped. */
static void release_slot(ElEm *em, uint32_t at, MirValue value, uint32_t close) {
  const MirFunc *closer = &em->m->funcs.ptr[close];
  if (closer->has_slot_close) {
    const MirValue left = em_push(em, at, MOP_Take, &value, 1, imm_ty(closer->slot_close), closer->slot_close);
    em_push(em, at, MOP_Drop, &left, 1, mir_imm_none(), EM_NO_RESULT);
  }
}

bool em_close_result(ElEm *em, uint32_t at, MirValue value, uint32_t close, MirValue *result) {
  uint32_t closer = 0;
  if (!shield_ready(em)) {
    return false;
  }
  em_push(em, at, MOP_CallRt, NULL, 0, mir_imm_ext(em->cx->shield_enter), MIR_VOID);
  *result = em_push(em, at, MOP_Call, &value, 1, em_imm_func(close), em->m->funcs.ptr[close].ret);
  em_push(em, at, MOP_CallRt, NULL, 0, mir_imm_ext(em->cx->shield_exit), MIR_VOID);
  if (!em_closer(em, value, &closer)) {
    return false;
  }
  release_slot(em, at, value, closer);
  return true;
}

/* Closes the live `value` of an owner that cannot fail, shielded from a stop request; the caller drops what
 * the close leaves behind. */
static bool close_infallible(ElEm *em, uint32_t at, MirValue value) {
  uint32_t close = 0;
  if (!em_closer(em, value, &close) || !shield_ready(em)) {
    return false;
  }
  em_push(em, at, MOP_CallRt, NULL, 0, mir_imm_ext(em->cx->shield_enter), MIR_VOID);
  em_push(em, at, MOP_Call, &value, 1, em_imm_func(close), MIR_VOID);
  em_push(em, at, MOP_CallRt, NULL, 0, mir_imm_ext(em->cx->shield_exit), MIR_VOID);
  return true;
}

/* Closes the infallible memory slot owner `value` that still holds its value, shielded: its close function
 * (an in-slot cleanup entry, `slot_close`) takes the address, and what the close leaves in the slot is taken
 * out and dropped. */
static bool close_slot(ElEm *em, uint32_t at, MirValue value) {
  uint32_t close = 0;
  if (!close_infallible(em, at, value) || !em_closer(em, value, &close)) {
    return false;
  }
  release_slot(em, at, value, close);
  return true;
}

/* The success of the `Result` type `rty` (its `ok` payload is `unit`). */
static bool ok_unit(ElEm *em, uint32_t at, MirTy rty, MirValue *out) {
  const MirTyData *data = mir_ty_data(em->m, rty);
  if (data->kind != MK_ALT) {
    return el_fail(em->cx, "a fallible close returns a Result");
  }
  if (em->m->alts.ptr[data->id].cases[0].fields[0].ty != MIR_VOID) {
    return el_fail(em->cx, "a moved slot owner whose close succeeds with a value");
  }
  const MirValue unit = em_push(em, at, MOP_VoidConst, NULL, 0, mir_imm_none(), MIR_VOID);
  *out = em_push(em, at, MOP_AltNew, &unit, 1, em_imm_case(data->id, 0), rty);
  return true;
}

static bool no_flag(ElEm *em, bool slot) {
  return el_fail(em->cx, slot ? "a moved slot owner without a drop flag" : "a moved owner without a drop flag");
}

/* Splits `at` on `flag` into two fresh blocks and a join. */
static void split(ElEm *em, uint32_t at, MirValue flag, MirBlock *yes, MirBlock *no, MirBlock *join) {
  *yes = em_new_block(em);
  *no = em_new_block(em);
  *join = em_new_block(em);
  em_condbr(em, at, flag, *yes, *no);
}

/* ---- owners that cannot fail ---- */

/* The flag says whether a slot owner that may have moved still holds its value; close it only then. */
static bool cleanup_slot_flagged(ElEm *em, uint32_t *at, MirValue value, MirValue flag) {
  if (flag == MIR_NONE) {
    return no_flag(em, true);
  }
  MirBlock yes = 0, no = 0, join = 0;
  split(em, *at, flag, &yes, &no, &join);
  if (!close_slot(em, yes, value)) {
    return false;
  }
  em_br(em, yes, join, NULL, 0);
  em_br(em, no, join, NULL, 0);
  *at = join;
  return true;
}

/* Cleans up an owner whose close cannot fail: it closes only on the paths that still hold it. */
static bool cleanup_infallible(ElEm *em, uint32_t *at, MirValue value, ElSt kind, MirValue flag) {
  const bool ptr = mir_value_ty(em->f, value) == MIR_PTR;
  if (kind == EL_LIVE) {
    if (ptr) {
      return close_slot(em, *at, value);
    }
    if (!close_infallible(em, *at, value)) {
      return false;
    }
    em_push(em, *at, MOP_Drop, &value, 1, mir_imm_none(), EM_NO_RESULT);
    return true;
  }
  if (el_is_part(kind)) {
    return el_fail(em->cx, "a partially moved closing owner");
  }
  if (kind == EL_CLOSED || kind == EL_MAYBE_CLOSED) {
    return close_slot(em, *at, value); /* closing again releases what the hand close left */
  }
  if (ptr && (kind == EL_MOVED || kind == EL_MAYBE || kind == EL_CLOSED_OR_MOVED)) {
    return cleanup_slot_flagged(em, at, value, flag);
  }
  if (kind == EL_CLOSED_OR_MOVED) {
    return el_fail(em->cx, "only a memory slot owner is closed by hand");
  }
  if (flag == MIR_NONE) {
    return no_flag(em, false);
  }
  const MirValue args[2] = {flag, value};
  if (kind == EL_MOVED) {
    em_push(em, *at, MOP_DropIf, args, 2, mir_imm_none(), EM_NO_RESULT);
    return true;
  }
  const MirBlock yes = em_new_block(em);
  const MirBlock join = em_new_block(em);
  em_condbr(em, *at, flag, yes, join);
  if (!close_infallible(em, yes, value)) {
    return false;
  }
  em_br(em, yes, join, NULL, 0);
  em_push(em, join, MOP_DropIf, args, 2, mir_imm_none(), EM_NO_RESULT);
  *at = join;
  return true;
}

/* ---- slot owners whose close returns a Result ---- */

/* Closes the slot owner `value` the program may have closed by hand (the closed flag says): a hand close is
 * closed again to release the rest and its result dropped, so the outcome is a plain success. */
static bool close_maybe_closed(ElEm *em, uint32_t *at, MirValue value, uint32_t close, MirValue *out) {
  const MirTy rty = em->m->funcs.ptr[close].ret;
  MirValue key = MIR_NONE, flag = MIR_NONE;
  if (!em_flag_of(&em->ckeys, value, &key) || !em_flag_of(&em->flags, key, &flag)) {
    return el_fail(em->cx, "a maybe-closed owner without a flag");
  }
  MirBlock yes = 0, no = 0, join = 0;
  split(em, *at, flag, &yes, &no, &join);
  MirValue again = MIR_NONE, none = MIR_NONE, real = MIR_NONE;
  if (!em_close_result(em, yes, value, close, &again)) {
    return false;
  }
  em_drop_owned(em, yes, again);
  if (!ok_unit(em, yes, rty, &none)) {
    return false;
  }
  em_br(em, yes, join, &none, 1);
  if (!em_close_result(em, no, value, close, &real)) {
    return false;
  }
  em_br(em, no, join, &real, 1);
  *out = em_block_param(em, join, rty, MM_MOVE);
  *at = join;
  return true;
}

/* The `Result` of closing a slot owner that may have moved out on some path: the flag says whether the value
 * is still in the slot; a path that moved it closes nothing and adds the success. */
static bool close_flagged(ElEm *em, uint32_t *at, MirValue value, ElSt kind, uint32_t close, MirValue *out) {
  const MirTy rty = em->m->funcs.ptr[close].ret;
  MirValue flag = MIR_NONE, closed = MIR_NONE, none = MIR_NONE;
  if (!em_flag_of(&em->flags, value, &flag)) {
    return no_flag(em, true);
  }
  MirBlock yes = 0, no = 0, join = 0;
  split(em, *at, flag, &yes, &no, &join);
  if (kind == EL_CLOSED_OR_MOVED) {
    /* If the value is in the slot the closed flag says whether the program closed it. */
    uint32_t end = yes;
    if (!close_maybe_closed(em, &end, value, close, &closed)) {
      return false;
    }
    em_br(em, end, join, &closed, 1);
  } else {
    if (!em_close_result(em, yes, value, close, &closed)) {
      return false;
    }
    em_br(em, yes, join, &closed, 1);
  }
  if (!ok_unit(em, no, rty, &none)) {
    return false;
  }
  em_br(em, no, join, &none, 1);
  *out = em_block_param(em, join, rty, MM_MOVE);
  *at = join;
  return true;
}

/* The first failing close is the outcome (the `Result` it returned, owned); later results are dropped. */
static void keep_first_error(ElEm *em, uint32_t *at, MirValue first, MirValue result, MirTy rty, MirValue *out) {
  const MirValue failed = em_is_error(em, *at, first);
  const MirBlock keep = em_new_block(em);
  const MirBlock replace = em_new_block(em);
  const MirBlock join = em_new_block(em);
  em_condbr(em, *at, failed, keep, replace);
  em_drop_owned(em, keep, result);
  em_br(em, keep, join, &first, 1);
  em_drop_owned(em, replace, first);
  em_br(em, replace, join, &result, 1);
  *out = em_block_param(em, join, rty, MM_MOVE);
  *at = join;
}

/* Cleans up a memory-slot owner whose close returns a `Result` (`close` runs it): shielded, on the path that
 * still holds it. */
static bool cleanup_fallible(ElEm *em, uint32_t *at, MirValue value, ElSt kind, uint32_t close,
                             MirValue *outcome) {
  if (el_is_part(kind)) {
    return el_fail(em->cx, "a partially moved slot owner");
  }
  MirValue result = MIR_NONE;
  bool ok = true;
  if (kind == EL_CLOSED) {
    /* Closed by the program: close again to release the rest, drop that result. */
    ok = em_close_result(em, *at, value, close, &result);
    if (ok) {
      em_drop_owned(em, *at, result);
    }
    return ok;
  }
  if (kind == EL_MAYBE_CLOSED) {
    ok = close_maybe_closed(em, at, value, close, &result);
  } else if (kind == EL_LIVE) {
    ok = em_close_result(em, *at, value, close, &result);
  } else {
    ok = close_flagged(em, at, value, kind, close, &result);
  }
  if (!ok) {
    return false;
  }
  if (*outcome == MIR_NONE) {
    *outcome = result;
  } else {
    keep_first_error(em, at, *outcome, result, em->m->funcs.ptr[close].ret, outcome);
  }
  return true;
}

/* ---- one owner, one scope ---- */

/* A partly moved owner: release what is left of it. */
static void release_part(ElEm *em, uint32_t at, MirValue value, ElSt kind) {
  const ElPart *part = el_part_of(em->cx, kind);
  const MirImm imm = {.tag = MI_ALTMASK, .a = part->alt, .b = part->cs, .c = part->mask};
  em_push(em, at, MOP_AltRelease, &value, 1, imm, EM_NO_RESULT);
}

/* A maybe-moved closing owner: close it where the flag says it is still held. */
static bool close_where_held(ElEm *em, uint32_t *at, MirValue value, MirValue flag, MirValue *code) {
  uint32_t close = 0;
  const MirValue args[2] = {flag, value};
  MirBlock yes = 0, no = 0, join = 0;
  split(em, *at, flag, &yes, &no, &join);
  if (!em_closer(em, value, &close)) {
    return false;
  }
  const MirValue called = em_push(em, yes, MOP_Call, &value, 1, em_imm_func(close), MIR_INT);
  em_br(em, yes, join, &called, 1);
  em_push(em, no, MOP_DropIf, args, 2, mir_imm_none(), EM_NO_RESULT);
  const MirValue zero = em_iconst(em, no, 0);
  em_br(em, no, join, &zero, 1);
  *code = em_block_param(em, join, MIR_INT, MM_BORROW);
  *at = join;
  return true;
}

/* The failure code the close of a kind-1 owner returns, once its block is built. */
static bool close_code(ElEm *em, uint32_t *at, MirValue value, ElSt kind, MirValue flag, MirValue *code) {
  uint32_t close = 0;
  const int64_t tag = em->cx->tag_kind[value];
  *code = MIR_NONE;
  if (el_is_part(kind)) {
    if (tag != 0) {
      return el_fail(em->cx, "a partially moved closing owner");
    }
    release_part(em, *at, value, kind);
    return true;
  }
  if (kind == EL_CLOSED || kind == EL_MAYBE_CLOSED || kind == EL_CLOSED_OR_MOVED) {
    return el_fail(em->cx, "only a memory slot owner is closed by hand");
  }
  if (kind == EL_LIVE && tag == 0) {
    em_push(em, *at, MOP_Drop, &value, 1, mir_imm_none(), EM_NO_RESULT);
    return true;
  }
  if (kind == EL_LIVE) {
    if (!em_closer(em, value, &close)) {
      return false;
    }
    *code = em_push(em, *at, MOP_Call, &value, 1, em_imm_func(close), MIR_INT);
    return true;
  }
  if (flag == MIR_NONE) {
    return no_flag(em, false);
  }
  if (kind == EL_MOVED || tag == 0) {
    const MirValue args[2] = {flag, value};
    em_push(em, *at, MOP_DropIf, args, 2, mir_imm_none(), EM_NO_RESULT);
    return true;
  }
  return close_where_held(em, at, value, flag, code);
}

/* Cleans up a memory-slot owner: its close is fallible when the closing function says so. */
static bool cleanup_slot_owner(ElEm *em, uint32_t *at, MirValue value, ElSt kind, MirValue flag,
                               MirValue *outcome) {
  uint32_t close = 0;
  if (mir_value_ty(em->f, value) == MIR_PTR) {
    if (!em_closer(em, value, &close)) {
      return false;
    }
    if (em->m->funcs.ptr[close].has_slot_result) {
      return cleanup_fallible(em, at, value, kind, em->m->funcs.ptr[close].slot_result, outcome);
    }
  }
  return cleanup_infallible(em, at, value, kind, flag);
}

/* Cleans up one owner whose move state is `kind`. `*outcome` is the first close failure so far. */
static bool em_cleanup_one(ElEm *em, uint32_t *at, MirValue value, ElSt kind, MirValue *outcome) {
  MirValue flag = MIR_NONE, code = MIR_NONE;
  (void)em_flag_of(&em->flags, value, &flag);
  if (em->cx->tag_kind[value] >= 2) {
    return cleanup_slot_owner(em, at, value, kind, flag, outcome);
  }
  if (!close_code(em, at, value, kind, flag, &code)) {
    return false;
  }
  if (code == MIR_NONE) {
    return true;
  }
  if (*outcome == MIR_NONE) {
    *outcome = code;
    return true;
  }
  const MirValue zero = em_iconst(em, *at, 0);
  const MirValue pair[2] = {*outcome, zero};
  const MirValue failed = em_push(em, *at, MOP_ICmp, pair, 2, mir_imm_cc(MCC_NE), MIR_BOOL);
  const MirValue pick[3] = {failed, *outcome, code};
  *outcome = em_push(em, *at, MOP_Select, pick, 3, mir_imm_none(), MIR_INT);
  return true;
}

static int64_t latest_first(uint8_t *env, const uint8_t *x, const uint8_t *y) {
  (void)env;
  ByPosition a, b;
  __builtin_memcpy(&a, x, sizeof a);
  __builtin_memcpy(&b, y, sizeof b);
  return (int64_t)b.pos - (int64_t)a.pos;
}

/* Closes or drops the owners of `scope`, last defined first, except `kept`: the value a failing close consumes in
 * place of the function's own result (MIR_NONE: none). */
static bool cleanup_scope(ElEm *em, uint32_t *at, ElState *state, int64_t scope, MirValue *outcome, MirValue kept) {
  const ElCx *cx = em->cx;
  if ((uint64_t)scope >= cx->nscopes) {
    return true;
  }
  if (em->tail != NULL && kept == MIR_NONE && *outcome == MIR_NONE && !state->tainted && state->tip != NULL &&
      state->tip->uniform && state->tip->scope == scope && el_share_list(em, *at, state->tip)) {
    return true; /* every owner of the state is this scope's plain drop: the chain made for the earlier exits holds them */
  }
  const MirIdList *list = &cx->owners[scope];
  /* The owners are listed in the order they were made, so they come out of the state oldest first and the sort only
   * reverses them; one buffer serves every exit. */
  if (em->nowners < list->len) {
    em->nowners = (uint32_t)list->len * 2;
    em->owners = MS_ARENA_NEW_ARRAY_UNINIT(cx->ma, ByPosition, em->nowners);
  }
  ByPosition *owners = em->owners;
  uint32_t count = 0;
  bool ascending = true;
  for (size_t i = 0; i < list->len; i++) {
    ByPosition owner = {list->ptr[i], 0, 0};
    if (el_get(state, owner.v, &owner.s) && el_position_of(state, owner.v, &owner.pos)) {
      ascending = ascending && (count == 0 || owners[count - 1].pos < owner.pos);
      owners[count++] = owner;
    }
  }
  if (ascending) {
    for (uint32_t i = 0; i < count / 2; i++) {
      const ByPosition swap = owners[i];
      owners[i] = owners[count - 1 - i];
      owners[count - 1 - i] = swap;
    }
  } else if (count > 1) {
    ms_sort((uint8_t *)owners, count, sizeof *owners, latest_first, NULL);
  }
  /* The oldest owners that are plain drops are dropped by a chain the exits share, when this is such an exit. */
  uint32_t shared = 0;
  while (em->tail != NULL && shared < count && owners[count - 1 - shared].s == EL_LIVE &&
         cx->tag_kind[owners[count - 1 - shared].v] == 0 && !mh_has(&em->flagged, owners[count - 1 - shared].v)) {
    shared++;
  }
  if (shared < 2) {
    shared = 0;
  }
  for (uint32_t i = 0; i < count; i++) {
    if (i == count - shared && shared > 0 && *outcome == MIR_NONE) {
      MirValue *values = MS_ARENA_NEW_ARRAY(cx->ma, MirValue, (size_t)shared + 1);
      for (uint32_t k = 0; k < shared; k++) {
        values[k] = owners[count - shared + k].v;
      }
      if (el_share_drops(em, *at, values, shared)) {
        return true;
      }
    }
    el_remove(em->cx, state, owners[i].v);
    if (owners[i].v == kept) {
      continue;
    }
    const bool moved_out = owners[i].s == EL_MOVED && !mh_has(&em->flagged, owners[i].v); /* nothing is left to close */
    if (!moved_out && !em_cleanup_one(em, at, owners[i].v, owners[i].s, outcome)) {
      return false;
    }
  }
  return true;
}

/* ---- the scope end ---- */

/* The failure test of the outcome of a scope: nonzero code, or an error `Result`. */
static MirValue failed_test(ElEm *em, uint32_t at, MirValue first, bool by_result) {
  if (by_result) {
    return em_is_error(em, at, first);
  }
  const MirValue zero = em_iconst(em, at, 0);
  const MirValue pair[2] = {first, zero};
  return em_push(em, at, MOP_ICmp, pair, 2, mir_imm_cc(MCC_NE), MIR_BOOL);
}

/* What else is live when a failing close leaves the function: the owners the cleanup did not reach, latest
 * first. */
static bool drop_rest(ElEm *em, uint32_t at, ElState *rest, bool by_result) {
  uint32_t count = 0;
  const ElOwner *owners = el_owners(em->cx, rest, &count);
  for (uint32_t i = count; i-- > 0;) {
    const MirValue value = owners[i].v;
    MirValue flag = MIR_NONE;
    /* A fallible outcome consumes the value the function was about to return. */
    if (by_result && em->pending == value) {
      continue;
    }
    if (owners[i].st == EL_LIVE) {
      em_push(em, at, MOP_Drop, &value, 1, mir_imm_none(), EM_NO_RESULT);
    } else if (mh_has(&em->flagged, value)) {
      if (!em_flag_of(&em->flags, value, &flag)) {
        return el_fail(em->cx, "no drop flag for %%%u", value);
      }
      const MirValue args[2] = {flag, value};
      em_push(em, at, MOP_DropIf, args, 2, mir_imm_none(), EM_NO_RESULT);
    }
  }
  return true;
}

/* The value an error edge returns: the outcome itself, or a call to the function's close exit. */
static bool error_result(ElEm *em, uint32_t at, MirValue outcome, bool by_result, MirValue *ret) {
  *ret = outcome;
  if (!by_result) {
    return true;
  }
  /* The function leaves here: undo its recursion guard like any return. */
  if (em->counts_depth) {
    em_push(em, at, MOP_DepthLeave, NULL, 0, mir_imm_none(), EM_NO_RESULT);
  }
  if (!em->f->has_close_exit) {
    return el_fail(em->cx, "a fallible close needs the function's close exit");
  }
  const MirFunc *func = em->f;
  const MirValue with_pending[2] = {outcome, em->pending};
  *ret = em->pending != MIR_NONE
             ? em_push(em, at, MOP_Call, with_pending, 2, em_imm_func(func->close_exit[1]), func->ret)
             : em_push(em, at, MOP_Call, &outcome, 1, em_imm_func(func->close_exit[0]), func->ret);
  return true;
}

/* The error edge: the enclosing scopes' cleanup, then what else is live, then return. */
static bool error_edge(ElEm *em, uint32_t at, ElState *state, int64_t scope, MirValue first, bool by_result) {
  ElCx *cx = em->cx;
  ElState rest = *state;
  MirValue outcome = first, ret = MIR_NONE;
  int64_t current = (uint64_t)scope < cx->nscopes && cx->has_parent[scope] ? cx->parent[scope] : -1;
  while (current >= 0) {
    if (!cleanup_scope(em, &at, &rest, current, &outcome, by_result ? em->pending : MIR_NONE)) {
      return false;
    }
    current = (uint64_t)current < cx->nscopes && cx->has_parent[current] ? cx->parent[current] : -1;
  }
  if (!drop_rest(em, at, &rest, by_result) || !error_result(em, at, outcome, by_result, &ret)) {
    return false;
  }
  MirTerm *term = &em->f->blocks.ptr[at].term;
  *term = (MirTerm){.kind = MT_RET, .value = ret};
  return true;
}

/* The cleanup of `scope` at a `scope.end`. `*cur` becomes the block to continue in. */
bool em_exit(ElEm *em, uint32_t *cur, ElState *state, int64_t scope) {
  MirValue first = MIR_NONE;
  if (!cleanup_scope(em, cur, state, scope, &first, MIR_NONE)) {
    return false;
  }
  if (first == MIR_NONE) {
    return true;
  }
  const bool by_result = mir_value_ty(em->f, first) != MIR_INT;
  const MirValue failed = failed_test(em, *cur, first, by_result);
  const MirBlock err = em_new_block(em);
  const MirBlock after = em_new_block(em);
  if (by_result) {
    em_drop_owned(em, after, first);
  }
  em_condbr(em, *cur, failed, err, after);
  if (!error_edge(em, err, state, scope, first, by_result)) {
    return false;
  }
  *cur = after;
  return true;
}
