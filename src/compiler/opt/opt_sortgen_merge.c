/* opt_sortgen_merge.c: see opt_sortgen_drift.h. */
#include "compiler/opt/opt_sortgen_drift.h"

/* ---- merge sort ---- */

static MirVar sd_plain_var(SdEm *e) { return mir_b_declare_var(e->b, MIR_INT, MM_BORROW); }

/* The merge sort's insertion sort of a short slice. */
static void sd_merge_insertion(SdEm *e, MirValue items, MirValue lo, MirValue hi, MirValue env,
               MirValue one, MirBlock insertion) {
  mir_b_switch_to(e->b, insertion);
  const MirVar iv = sd_plain_var(e), jv = sd_plain_var(e);
  const MirValue first = sd_add(e, lo, one);
  sd_set(e, iv, first);
  const MirBlock outer = mir_b_new_block(e->b), outer_body = mir_b_new_block(e->b);
  const MirBlock inner = mir_b_new_block(e->b), inner_body = mir_b_new_block(e->b);
  const MirBlock shift = mir_b_new_block(e->b), place = mir_b_new_block(e->b);
  const MirBlock done = mir_b_new_block(e->b);
  mir_b_br(e->b, outer, NULL, 0);
  mir_b_switch_to(e->b, outer);
  MirValue i = sd_get(e, iv);
  const MirValue more = sd_cmp(e, MCC_LT, i, hi);
  mir_b_br_if(e->b, more, outer_body, NULL, 0, done, NULL, 0);
  mir_b_seal_block(e->b, outer_body);
  mir_b_seal_block(e->b, done);
  mir_b_switch_to(e->b, outer_body);
  i = sd_get(e, iv);
  const MirValue pi = sd_at(e, items, i);
  const MirValue x = sd_load_at(e, pi);
  sd_set(e, jv, i);
  mir_b_br(e->b, inner, NULL, 0);
  mir_b_switch_to(e->b, inner);
  MirValue j = sd_get(e, jv);
  const MirValue above = sd_cmp(e, MCC_GT, j, lo);
  mir_b_br_if(e->b, above, inner_body, NULL, 0, place, NULL, 0);
  mir_b_seal_block(e->b, inner_body);
  mir_b_switch_to(e->b, inner_body);
  j = sd_get(e, jv);
  const MirValue jm = sd_sub(e, j, one);
  const MirValue pjm = sd_at(e, items, jm);
  const MirValue y = sd_load_at(e, pjm);
  const MirValue lt = sd_less(e, env, x, y);
  mir_b_br_if(e->b, lt, shift, NULL, 0, place, NULL, 0);
  mir_b_seal_block(e->b, shift);
  mir_b_seal_block(e->b, place);
  mir_b_switch_to(e->b, shift);
  j = sd_get(e, jv);
  MirValue pj = sd_at(e, items, j);
  sd_store_at(e, pj, y);
  sd_set(e, jv, jm);
  mir_b_br(e->b, inner, NULL, 0);
  mir_b_seal_block(e->b, inner);
  mir_b_switch_to(e->b, place);
  j = sd_get(e, jv);
  pj = sd_at(e, items, j);
  sd_store_at(e, pj, x);
  i = sd_get(e, iv);
  const MirValue next = sd_add(e, i, one);
  sd_set(e, iv, next);
  mir_b_br(e->b, outer, NULL, 0);
  mir_b_seal_block(e->b, outer);
  mir_b_switch_to(e->b, done);
  sd_unit_ret(e);
}

/* After both halves are sorted into `buf`, when they are already in order the slice is copied
 * back as it is. */
static void sd_merge_copy_back(SdEm *e, MirValue buf, MirValue items, MirValue lo, MirValue hi,
               MirValue one, MirBlock finish) {
  mir_b_switch_to(e->b, finish);
  const MirVar kv = sd_plain_var(e);
  sd_set(e, kv, lo);
  const MirBlock head = mir_b_new_block(e->b), body = mir_b_new_block(e->b);
  const MirBlock copied = mir_b_new_block(e->b);
  mir_b_br(e->b, head, NULL, 0);
  mir_b_switch_to(e->b, head);
  MirValue k = sd_get(e, kv);
  const MirValue go = sd_cmp(e, MCC_LT, k, hi);
  mir_b_br_if(e->b, go, body, NULL, 0, copied, NULL, 0);
  mir_b_seal_block(e->b, body);
  mir_b_seal_block(e->b, copied);
  mir_b_switch_to(e->b, body);
  k = sd_get(e, kv);
  const MirValue from = sd_at(e, buf, k);
  const MirValue v = sd_load_at(e, from);
  const MirValue to = sd_at(e, items, k);
  sd_store_at(e, to, v);
  const MirValue k1 = sd_add(e, k, one);
  sd_set(e, kv, k1);
  mir_b_br(e->b, head, NULL, 0);
  mir_b_seal_block(e->b, head);
  mir_b_switch_to(e->b, copied);
  sd_unit_ret(e);
}



/* Front of one merge step: the right run's element is taken only when it is strictly smaller. */
static SdStep sd_merge_front(SdEm *e, const SdMergeVars *v, MirValue buf, MirValue items,
              MirValue lo, MirValue env, MirValue one) {
  const MirValue l = sd_get(e, v->l), le = sd_get(e, v->le);
  const MirValue r = sd_get(e, v->r), re = sd_get(e, v->re);
  const MirBlock front_true = mir_b_new_block(e->b), front_chk = mir_b_new_block(e->b);
  const MirBlock front_cmp = mir_b_new_block(e->b), front_join = mir_b_new_block(e->b);
  const MirValue take_r = mir_b_add_block_param(e->b, front_join, MIR_BOOL, MM_BORROW);
  const MirValue left_done = sd_cmp(e, MCC_EQ, l, le);
  mir_b_br_if(e->b, left_done, front_true, NULL, 0, front_chk, NULL, 0);
  mir_b_seal_block(e->b, front_true);
  mir_b_seal_block(e->b, front_chk);
  mir_b_switch_to(e->b, front_true);
  MirValue flag = mir_b_bconst(e->b, true);
  mir_b_br(e->b, front_join, &flag, 1);
  mir_b_switch_to(e->b, front_chk);
  const MirValue right_left = sd_cmp(e, MCC_LT, r, re);
  const MirValue no = mir_b_bconst(e->b, false);
  mir_b_br_if(e->b, right_left, front_cmp, NULL, 0, front_join, &no, 1);
  mir_b_seal_block(e->b, front_cmp);
  mir_b_switch_to(e->b, front_cmp);
  const MirValue pr = sd_at(e, buf, r);
  const MirValue xr = sd_load_at(e, pr);
  const MirValue pl = sd_at(e, buf, l);
  const MirValue yl = sd_load_at(e, pl);
  flag = sd_less(e, env, xr, yl);
  mir_b_br(e->b, front_join, &flag, 1);
  mir_b_seal_block(e->b, front_join);
  mir_b_switch_to(e->b, front_join);
  const MirValue idx = mir_b_select(e->b, take_r, r, l);
  const MirValue pi = sd_at(e, buf, idx);
  const MirValue val = sd_load_at(e, pi);
  const MirValue s = sd_get(e, v->s);
  const MirValue slot = sd_add(e, lo, s);
  const MirValue po = sd_at(e, items, slot);
  sd_store_at(e, po, val);
  const MirValue tr = sd_b2i(e, take_r);
  const MirValue r1 = sd_add(e, r, tr);
  const MirValue one_minus = sd_sub(e, one, tr);
  const MirValue l1 = sd_add(e, l, one_minus);
  return (SdStep){le, re, l1, r1};
}

/* Back of one merge step: the left run's last is taken only when the right run's last is not
 * smaller. Updates the loop's variables and loops back to `head`. */
static void sd_merge_back(SdEm *e, const SdMergeVars *v, MirValue buf, MirValue items,
             MirValue hi, MirValue env, MirValue one, const SdStep *step,
             MirBlock head) {
  const MirValue le = step->le, re = step->re, l1 = step->l1, r1 = step->r1;
  const MirBlock back_true = mir_b_new_block(e->b), back_chk = mir_b_new_block(e->b);
  const MirBlock back_cmp = mir_b_new_block(e->b), back_join = mir_b_new_block(e->b);
  const MirValue take_l = mir_b_add_block_param(e->b, back_join, MIR_BOOL, MM_BORROW);
  const MirValue right_done = sd_cmp(e, MCC_EQ, re, r1);
  mir_b_br_if(e->b, right_done, back_true, NULL, 0, back_chk, NULL, 0);
  mir_b_seal_block(e->b, back_true);
  mir_b_seal_block(e->b, back_chk);
  mir_b_switch_to(e->b, back_true);
  MirValue flag = mir_b_bconst(e->b, true);
  mir_b_br(e->b, back_join, &flag, 1);
  mir_b_switch_to(e->b, back_chk);
  const MirValue left_left = sd_cmp(e, MCC_LT, l1, le);
  const MirValue no = mir_b_bconst(e->b, false);
  mir_b_br_if(e->b, left_left, back_cmp, NULL, 0, back_join, &no, 1);
  mir_b_seal_block(e->b, back_cmp);
  mir_b_switch_to(e->b, back_cmp);
  MirValue rem1 = sd_sub(e, re, one);
  MirValue lem1 = sd_sub(e, le, one);
  const MirValue pre = sd_at(e, buf, rem1);
  const MirValue xre = sd_load_at(e, pre);
  const MirValue ple = sd_at(e, buf, lem1);
  const MirValue yle = sd_load_at(e, ple);
  flag = sd_less(e, env, xre, yle);
  mir_b_br(e->b, back_join, &flag, 1);
  mir_b_seal_block(e->b, back_join);
  mir_b_switch_to(e->b, back_join);
  rem1 = sd_sub(e, re, one);
  lem1 = sd_sub(e, le, one);
  const MirValue idx = mir_b_select(e->b, take_l, lem1, rem1);
  const MirValue pi = sd_at(e, buf, idx);
  const MirValue val = sd_load_at(e, pi);
  const MirValue s = sd_get(e, v->s);
  const MirValue back = sd_sub(e, hi, one);
  const MirValue slot = sd_sub(e, back, s);
  const MirValue po = sd_at(e, items, slot);
  sd_store_at(e, po, val);
  const MirValue tl = sd_b2i(e, take_l);
  const MirValue le1 = sd_sub(e, le, tl);
  const MirValue keep = sd_sub(e, one, tl);
  const MirValue re1 = sd_sub(e, re, keep);
  const MirValue s1 = sd_add(e, s, one);
  sd_set(e, v->l, l1);
  sd_set(e, v->le, le1);
  sd_set(e, v->r, r1);
  sd_set(e, v->re, re1);
  sd_set(e, v->s, s1);
  mir_b_br(e->b, head, NULL, 0);
  mir_b_seal_block(e->b, head);
}

/* Merges from both ends at once, two output slots per step; an odd slice leaves one element for
 * the middle. */
static void sd_merge_runs(SdEm *e, MirValue buf, MirValue items, MirValue lo, MirValue mid,
             MirValue hi, MirValue env, MirValue n, MirValue one, MirBlock merged) {
  mir_b_switch_to(e->b, merged);
  SdMergeVars v;
  v.l = sd_plain_var(e);
  v.le = sd_plain_var(e);
  v.r = sd_plain_var(e);
  v.re = sd_plain_var(e);
  v.s = sd_plain_var(e);
  const MirValue zero = sd_int(e, 0);
  const MirValue steps = mir_b_binop(e->b, MOP_Sshr, n, one);
  sd_set(e, v.l, lo);
  sd_set(e, v.le, mid);
  sd_set(e, v.r, mid);
  sd_set(e, v.re, hi);
  sd_set(e, v.s, zero);
  const MirBlock head = mir_b_new_block(e->b), step = mir_b_new_block(e->b);
  const MirBlock tail = mir_b_new_block(e->b);
  mir_b_br(e->b, head, NULL, 0);
  mir_b_switch_to(e->b, head);
  const MirValue s = sd_get(e, v.s);
  const MirValue go = sd_cmp(e, MCC_LT, s, steps);
  mir_b_br_if(e->b, go, step, NULL, 0, tail, NULL, 0);
  mir_b_seal_block(e->b, step);
  mir_b_seal_block(e->b, tail);
  mir_b_switch_to(e->b, step);
  const SdStep moved = sd_merge_front(e, &v, buf, items, lo, env, one);
  sd_merge_back(e, &v, buf, items, hi, env, one, &moved, head);
  mir_b_switch_to(e->b, tail);
  const MirValue l = sd_get(e, v.l), le = sd_get(e, v.le), r = sd_get(e, v.r);
  const MirValue odd_bit = mir_b_binop(e->b, MOP_And, n, one);
  const MirValue zero2 = sd_int(e, 0);
  const MirValue odd = sd_cmp(e, MCC_NE, odd_bit, zero2);
  const MirBlock middle = mir_b_new_block(e->b), end = mir_b_new_block(e->b);
  mir_b_br_if(e->b, odd, middle, NULL, 0, end, NULL, 0);
  mir_b_seal_block(e->b, middle);
  mir_b_seal_block(e->b, end);
  mir_b_switch_to(e->b, middle);
  const MirValue from_left = sd_cmp(e, MCC_LT, l, le);
  const MirValue idx = mir_b_select(e->b, from_left, l, r);
  const MirValue pi = sd_at(e, buf, idx);
  const MirValue val = sd_load_at(e, pi);
  const MirValue slot = sd_add(e, lo, steps);
  const MirValue po = sd_at(e, items, slot);
  sd_store_at(e, po, val);
  mir_b_br(e->b, end, NULL, 0);
  mir_b_switch_to(e->b, end);
  sd_unit_ret(e);
}

/* Builds `merge(src, dst, lo, hi, env)`: a stable merge sort that leaves `dst[lo..hi]` sorted by
 * the sign of `g(env, a, b)`. Both lists hold the same elements in `lo..hi` on entry; `src` is
 * scratch and holds unspecified elements there afterwards. Each level sorts its halves into the
 * other list and merges them back, so no level copies the slice. Returns the function id. */
uint32_t sd_build_merge(MirModule *m, uint32_t g, MirTy elem) {
  const MirTy list_ty = mir_ty_list(m, elem);
  const MirTy types[5] = {list_ty, list_ty, MIR_INT, MIR_INT, MIR_PTR};
  const uint32_t id = sd_declare(m, sd_name(m, "sort.mergesort.", g), types, 5, MIR_VOID);
  MirBuilder b;
  sd_start(&b, m, id, MIR_VOID);
  SdEm em = {&b, elem, g}, *e = &em;
  MirValue args[5];
  mir_b_params(&b, args, 5);
  /* `buf` is the list the merge reads from and `items` the list it writes. */
  const MirValue buf = args[0], items = args[1], lo = args[2], hi = args[3], env = args[4];
  const MirValue one = mir_b_iconst(&b, 1);
  const MirValue n = sd_sub(e, hi, lo);
  const MirValue limit = mir_b_iconst(&b, SD_INSERTION_MAX);
  const MirValue small = sd_cmp(e, MCC_LE, n, limit);
  const MirBlock insertion = mir_b_new_block(&b), big = mir_b_new_block(&b);
  mir_b_br_if(&b, small, insertion, NULL, 0, big, NULL, 0);
  mir_b_seal_block(&b, insertion);
  mir_b_seal_block(&b, big);
  sd_merge_insertion(e, items, lo, hi, env, one, insertion);

  /* Sort both halves, then merge unless they are already in order. */
  mir_b_switch_to(&b, big);
  const MirValue half = mir_b_binop(&b, MOP_Sshr, n, one);
  const MirValue mid = sd_add(e, lo, half);
  const MirValue left_args[5] = {items, buf, lo, mid, env};
  (void)sd_call(e, id, left_args, 5);
  const MirValue right_args[5] = {items, buf, mid, hi, env};
  (void)sd_call(e, id, right_args, 5);
  const MirValue pm = sd_at(e, buf, mid);
  const MirValue a = sd_load_at(e, pm);
  const MirValue mm1 = sd_sub(e, mid, one);
  const MirValue pmm = sd_at(e, buf, mm1);
  const MirValue c = sd_load_at(e, pmm);
  const MirValue unordered = sd_less(e, env, a, c);
  const MirBlock merge = mir_b_new_block(&b), finish = mir_b_new_block(&b);
  mir_b_br_if(&b, unordered, merge, NULL, 0, finish, NULL, 0);
  mir_b_seal_block(&b, merge);
  mir_b_seal_block(&b, finish);
  sd_merge_copy_back(e, buf, items, lo, hi, one, finish);
  sd_merge_runs(e, buf, items, lo, mid, hi, env, n, one, merge);
  sd_finish(&b, m, id);
  return id;
}
