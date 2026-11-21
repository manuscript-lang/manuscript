/* opt_sortgen_emit.c: see opt_sortgen_drift.h. */
#include "compiler/opt/opt_sortgen_drift.h"

MirValue sd_int(SdEm *e, int64_t v) { return mir_b_iconst(e->b, v); }
MirValue sd_add(SdEm *e, MirValue x, MirValue y) { return mir_b_binop(e->b, MOP_IAdd, x, y); }
MirValue sd_sub(SdEm *e, MirValue x, MirValue y) { return mir_b_binop(e->b, MOP_ISub, x, y); }
MirValue sd_cmp(SdEm *e, MirCc cc, MirValue x, MirValue y) {
  return mir_b_icmp(e->b, cc, x, y);
}

MirValue sd_add_k(SdEm *e, MirValue x, int64_t k) {
  const MirValue kv = sd_int(e, k);
  return sd_add(e, x, kv);
}

MirValue sd_b2i(SdEm *e, MirValue flag) {
  return mir_b_emit(e->b, MOP_B2I, &flag, 1, (MirImm){0}, MIR_INT);
}

MirVar sd_var(SdEm *e, MirValue init) {
  const MirVar v = mir_b_declare_var(e->b, MIR_INT, MM_BORROW);
  mir_b_def_var(e->b, v, init);
  return v;
}

MirValue sd_get(SdEm *e, MirVar v) { return mir_b_use_var(e->b, v); }
void sd_set(SdEm *e, MirVar v, MirValue x) { mir_b_def_var(e->b, v, x); }

MirValue sd_at(SdEm *e, MirValue list, MirValue i) {
  const MirValue args[2] = {list, i};
  return mir_b_emit(e->b, MOP_ListAddrU, args, 2, (MirImm){0}, MIR_PTR);
}

MirValue sd_load_at(SdEm *e, MirValue p) {
  return mir_b_emit(e->b, MOP_Load, &p, 1, (MirImm){.tag = MI_TY, .a = e->elem}, e->elem);
}

void sd_store_at(SdEm *e, MirValue p, MirValue v) {
  const MirValue args[2] = {p, v};
  (void)mir_b_emit(e->b, MOP_Store, args, 2, (MirImm){0}, MIR_NONE);
}

/* The element at `list[i]`, which is not bounds-checked. */
MirValue sd_ld(SdEm *e, MirValue list, MirValue i) {
  const MirValue p = sd_at(e, list, i);
  return sd_load_at(e, p);
}

void sd_st(SdEm *e, MirValue list, MirValue i, MirValue v) {
  const MirValue p = sd_at(e, list, i);
  sd_store_at(e, p, v);
}

/* The word at `ints[i]` of a scratch list of `Int`. */
MirValue sd_ld_int(SdEm *e, MirValue ints, MirValue i) {
  const MirValue p = sd_at(e, ints, i);
  return mir_b_emit(e->b, MOP_Load, &p, 1, (MirImm){.tag = MI_TY, .a = MIR_INT}, MIR_INT);
}

void sd_st_int(SdEm *e, MirValue ints, MirValue i, MirValue v) { sd_st(e, ints, i, v); }

/* `cmp(x, y) < 0`. */
MirValue sd_less(SdEm *e, MirValue env, MirValue x, MirValue y) {
  const MirValue args[3] = {env, x, y};
  const MirValue c = mir_b_call(e->b, e->g, args, 3);
  const MirValue zero = sd_int(e, 0);
  return sd_cmp(e, MCC_LT, c, zero);
}

MirValue sd_call(SdEm *e, uint32_t func, const MirValue *args, uint32_t n) {
  return mir_b_call(e->b, func, args, n);
}

void sd_unit_ret(SdEm *e) {
  const MirValue u = mir_b_unit(e->b);
  mir_b_ret(e->b, u);
}

/* Runs the code between `sd_if` and `sd_if_end` when `cond` holds, then continues after it. */
MirBlock sd_if(SdEm *e, MirValue cond) {
  const MirBlock t = mir_b_new_block(e->b), join = mir_b_new_block(e->b);
  mir_b_br_if(e->b, cond, t, NULL, 0, join, NULL, 0);
  mir_b_seal_block(e->b, t);
  mir_b_switch_to(e->b, t);
  return join;
}

void sd_if_end(SdEm *e, MirBlock join) {
  mir_b_br(e->b, join, NULL, 0);
  mir_b_seal_block(e->b, join);
  mir_b_switch_to(e->b, join);
}

/* The code after `sd_if_ret` ends in a return when `cond` holds; `sd_if_ret_end` continues. */
MirBlock sd_if_ret(SdEm *e, MirValue cond) {
  const MirBlock t = mir_b_new_block(e->b), rest = mir_b_new_block(e->b);
  mir_b_br_if(e->b, cond, t, NULL, 0, rest, NULL, 0);
  mir_b_seal_block(e->b, t);
  mir_b_seal_block(e->b, rest);
  mir_b_switch_to(e->b, t);
  return rest;
}

void sd_if_ret_end(SdEm *e, MirBlock rest) { mir_b_switch_to(e->b, rest); }


SdPick sd_pick(SdEm *e, MirTy ty, MirValue cond) {
  const MirBlock ta = mir_b_new_block(e->b), tc = mir_b_new_block(e->b);
  const MirBlock join = mir_b_new_block(e->b);
  const MirValue out = mir_b_add_block_param(e->b, join, ty, MM_BORROW);
  mir_b_br_if(e->b, cond, ta, NULL, 0, tc, NULL, 0);
  mir_b_seal_block(e->b, ta);
  mir_b_seal_block(e->b, tc);
  mir_b_switch_to(e->b, ta);
  return (SdPick){tc, join, out};
}

void sd_pick_else(SdEm *e, const SdPick *p, MirValue first) {
  mir_b_br(e->b, p->join, &first, 1);
  mir_b_switch_to(e->b, p->other);
}

MirValue sd_pick_end(SdEm *e, const SdPick *p, MirValue second) {
  mir_b_br(e->b, p->join, &second, 1);
  mir_b_seal_block(e->b, p->join);
  mir_b_switch_to(e->b, p->join);
  return p->out;
}


SdLoop sd_loop(SdEm *e) {
  const MirBlock head = mir_b_new_block(e->b), exit = mir_b_new_block(e->b);
  mir_b_br(e->b, head, NULL, 0);
  mir_b_switch_to(e->b, head);
  return (SdLoop){head, exit};
}

void sd_loop_end(SdEm *e, const SdLoop *l) {
  mir_b_br(e->b, l->head, NULL, 0);
  mir_b_seal_block(e->b, l->head);
  mir_b_seal_block(e->b, l->exit);
  mir_b_switch_to(e->b, l->exit);
}

/* Leaves the loop through `exit` when `cond` holds. */
void sd_brk_if(SdEm *e, MirValue cond, MirBlock exit) {
  const MirBlock go = mir_b_new_block(e->b);
  mir_b_br_if(e->b, cond, exit, NULL, 0, go, NULL, 0);
  mir_b_seal_block(e->b, go);
  mir_b_switch_to(e->b, go);
}

/* ---- declarations ---- */

/* A function's name: `<prefix><name of the comparator>`. */
MsName sd_name(MirModule *m, const char *prefix, uint32_t g) {
  const MsSpan tag = ms_names_span(&m->names, m->funcs.ptr[g].name);
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, prefix);
  ms_strbuild_append(&text, tag);
  const MsName name = mir_name(m, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  return name;
}

/* Adds a function with borrowed parameters of the given types, to be replaced by its body once
 * built; the other helpers call it by id meanwhile. */
uint32_t sd_declare(MirModule *m, MsName name, const MirTy *types, uint32_t n, MirTy ret) {
  MirParam params[8];
  for (uint32_t i = 0; i < n; i++) {
    params[i] = (MirParam){types[i], MM_BORROW};
  }
  MirFunc f;
  mir_func_init(m, &f, name, params, n, ret);
  return mir_add_func(m, &f);
}

/* Starts the body of `id`, one of the declared functions. */
void sd_start(MirBuilder *b, MirModule *m, uint32_t id, MirTy ret) {
  const MirFunc *declared = &m->funcs.ptr[id];
  mir_b_init(b, m, declared->name, declared->params, declared->nparams, ret);
  mir_b_func(b)->raw_scratch = true;
}

/* Replaces the declared function `id` by the finished body. */
void sd_finish(MirBuilder *b, MirModule *m, uint32_t id) {
  MirFunc f = {0};
  const bool ok = mir_b_into_func(b, &f);
  (void)ok; /* a failed build only repeats the declaration's own failure */
  m->funcs.ptr[id] = f;
}
