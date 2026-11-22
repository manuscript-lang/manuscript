/* The sorts `sortgen` generates: a stable driftsort (the algorithm of Rust's `slice::sort`) and
 * its helpers, written as MIR functions that call a known comparator directly so the backend
 * can inline it.
 *
 * The input is cut into runs: a natural run that is long enough (a descending one is reversed in
 * place) or a stretch that is left unsorted. Neighbouring runs are merged in a tree split near
 * the middle of the data; two unsorted stretches join into one, so random data is a single
 * unsorted stretch that a stable quicksort handles. The quicksort partitions through the scratch
 * list, gives an element equal to its ancestor pivot a partition of its own, so data with few
 * distinct keys sorts in O(n log k), and falls back to merge sort when it recurses deeper than
 * 2 log n. Slots are permuted as bits, so a faulting comparator leaves scratch, not an owner, in a
 * partial state.
 */

#include "compiler/opt/opt_sortgen_drift.h"
/* ---- driftsort ---- */


/* `ins(items, lo, hi, env)`: stable insertion sort of `items[lo..hi]`. */
static void sd_build_ins(SdEm *e) {
  MirValue a[4];
  mir_b_params(e->b, a, 4);
  const MirValue items = a[0], lo = a[1], hi = a[2], env = a[3];
  const MirValue first = sd_add_k(e, lo, 1);
  const MirVar iv = sd_var(e, first);
  const SdLoop outer = sd_loop(e);
  MirValue i = sd_get(e, iv);
  const MirValue done = sd_cmp(e, MCC_GE, i, hi);
  sd_brk_if(e, done, outer.exit);
  const MirValue x = sd_ld(e, items, i);
  const MirVar jv = sd_var(e, i);
  const SdLoop inner = sd_loop(e);
  MirValue j = sd_get(e, jv);
  const MirValue at_lo = sd_cmp(e, MCC_LE, j, lo);
  sd_brk_if(e, at_lo, inner.exit);
  const MirValue jm = sd_add_k(e, j, -1);
  const MirValue y = sd_ld(e, items, jm);
  const MirValue lt = sd_less(e, env, x, y);
  const MirValue ordered = sd_b2i(e, lt);
  const MirValue zero = sd_int(e, 0);
  const MirValue stay = sd_cmp(e, MCC_EQ, ordered, zero);
  sd_brk_if(e, stay, inner.exit);
  sd_st(e, items, j, y);
  sd_set(e, jv, jm);
  sd_loop_end(e, &inner);
  j = sd_get(e, jv);
  sd_st(e, items, j, x);
  i = sd_get(e, iv);
  const MirValue next = sd_add_k(e, i, 1);
  sd_set(e, iv, next);
  sd_loop_end(e, &outer);
  sd_unit_ret(e);
}

/* Copies `from..to` of `items` into `buf` (the head of a run merge). */
static void sd_copy_range(SdEm *e, MirValue items, MirValue buf, MirValue from, MirValue to) {
  const MirVar kv = sd_var(e, from);
  const SdLoop loop = sd_loop(e);
  const MirValue k = sd_get(e, kv);
  const MirValue done = sd_cmp(e, MCC_GE, k, to);
  sd_brk_if(e, done, loop.exit);
  const MirValue x = sd_ld(e, items, k);
  sd_st(e, buf, k, x);
  const MirValue k1 = sd_add_k(e, k, 1);
  sd_set(e, kv, k1);
  sd_loop_end(e, &loop);
}

/* The forward run merge: the left run waits in scratch; the right element is taken only when it
 * is smaller. */
static void sd_run_merge_forward(SdEm *e, MirValue items, MirValue buf, MirValue lo, MirValue mid,
                MirValue hi, MirValue env) {
  sd_copy_range(e, items, buf, lo, mid);
  const MirVar lv = sd_var(e, lo), rv = sd_var(e, mid), ov = sd_var(e, lo);
  const SdLoop main = sd_loop(e);
  const MirValue l = sd_get(e, lv), r = sd_get(e, rv);
  const MirValue l_done = sd_cmp(e, MCC_GE, l, mid);
  sd_brk_if(e, l_done, main.exit);
  const MirValue r_done = sd_cmp(e, MCC_GE, r, hi);
  sd_brk_if(e, r_done, main.exit);
  const MirValue pr = sd_at(e, items, r);
  const MirValue pl = sd_at(e, buf, l);
  const MirValue xr = sd_load_at(e, pr);
  const MirValue xl = sd_load_at(e, pl);
  const MirValue take_r = sd_less(e, env, xr, xl);
  const MirValue o = sd_get(e, ov);
  /* Select the address: an element that owns data cannot be selected as a value. */
  const MirValue from = mir_b_select(e->b, take_r, pr, pl);
  const MirValue x = sd_load_at(e, from);
  sd_st(e, items, o, x);
  const MirValue tr = sd_b2i(e, take_r);
  const MirValue r1 = sd_add(e, r, tr);
  const MirValue one = sd_int(e, 1);
  const MirValue keep = sd_sub(e, one, tr);
  const MirValue l1 = sd_add(e, l, keep);
  sd_set(e, rv, r1);
  sd_set(e, lv, l1);
  const MirValue o1 = sd_add_k(e, o, 1);
  sd_set(e, ov, o1);
  sd_loop_end(e, &main);
  /* What remains of the left run goes to the end; a remaining right run is in place. */
  const SdLoop rest = sd_loop(e);
  const MirValue l2 = sd_get(e, lv);
  const MirValue done = sd_cmp(e, MCC_GE, l2, mid);
  sd_brk_if(e, done, rest.exit);
  const MirValue o2 = sd_get(e, ov);
  const MirValue x2 = sd_ld(e, buf, l2);
  sd_st(e, items, o2, x2);
  const MirValue l3 = sd_add_k(e, l2, 1);
  const MirValue o3 = sd_add_k(e, o2, 1);
  sd_set(e, lv, l3);
  sd_set(e, ov, o3);
  sd_loop_end(e, &rest);
  sd_unit_ret(e);
}

/* The backward run merge: the right run waits in scratch; the left element is taken only when
 * the right one is smaller. `rv` and `ov` are one past the next slot to read and to fill. */
static void sd_run_merge_backward(SdEm *e, MirValue items, MirValue buf, MirValue lo,
                 MirValue mid, MirValue hi, MirValue mm1, MirValue env) {
  sd_copy_range(e, items, buf, mid, hi);
  const MirVar lv = sd_var(e, mm1), rv = sd_var(e, hi), ov = sd_var(e, hi);
  const SdLoop main = sd_loop(e);
  const MirValue l = sd_get(e, lv), r = sd_get(e, rv);
  const MirValue l_done = sd_cmp(e, MCC_LT, l, lo);
  sd_brk_if(e, l_done, main.exit);
  const MirValue r_done = sd_cmp(e, MCC_LE, r, mid);
  sd_brk_if(e, r_done, main.exit);
  const MirValue r1 = sd_add_k(e, r, -1);
  const MirValue pr = sd_at(e, buf, r1);
  const MirValue pl = sd_at(e, items, l);
  const MirValue xr = sd_load_at(e, pr);
  const MirValue xl = sd_load_at(e, pl);
  const MirValue take_l = sd_less(e, env, xr, xl);
  const MirValue o = sd_get(e, ov);
  const MirValue o1 = sd_add_k(e, o, -1);
  const MirValue from = mir_b_select(e->b, take_l, pl, pr);
  const MirValue x = sd_load_at(e, from);
  sd_st(e, items, o1, x);
  const MirValue tl = sd_b2i(e, take_l);
  const MirValue one = sd_int(e, 1);
  const MirValue keep = sd_sub(e, one, tl);
  const MirValue l1 = sd_sub(e, l, tl);
  const MirValue r2 = sd_sub(e, r, keep);
  sd_set(e, lv, l1);
  sd_set(e, rv, r2);
  sd_set(e, ov, o1);
  sd_loop_end(e, &main);
  const SdLoop rest = sd_loop(e);
  const MirValue r3 = sd_get(e, rv);
  const MirValue done = sd_cmp(e, MCC_LE, r3, mid);
  sd_brk_if(e, done, rest.exit);
  const MirValue o2 = sd_get(e, ov);
  const MirValue r4 = sd_add_k(e, r3, -1);
  const MirValue o3 = sd_add_k(e, o2, -1);
  const MirValue x2 = sd_ld(e, buf, r4);
  sd_st(e, items, o3, x2);
  sd_set(e, rv, r4);
  sd_set(e, ov, o3);
  sd_loop_end(e, &rest);
  sd_unit_ret(e);
}

/* `run_merge(items, scratch, lo, mid, hi, env)`: merges the sorted `items[lo..mid]` and
 * `items[mid..hi]` stably, copying the shorter side into `scratch[lo..hi]`. */
static void sd_build_run_merge(SdEm *e) {
  MirValue a[6];
  mir_b_params(e->b, a, 6);
  const MirValue items = a[0], buf = a[1], lo = a[2], mid = a[3], hi = a[4], env = a[5];
  /* Already in order: nothing to do. */
  const MirValue first = sd_ld(e, items, mid);
  const MirValue mm1 = sd_add_k(e, mid, -1);
  const MirValue last = sd_ld(e, items, mm1);
  const MirValue unordered = sd_less(e, env, first, last);
  const MirValue zero = sd_int(e, 0);
  const MirValue flag = sd_b2i(e, unordered);
  const MirValue ordered = sd_cmp(e, MCC_EQ, flag, zero);
  const MirBlock rest = sd_if_ret(e, ordered);
  sd_unit_ret(e);
  sd_if_ret_end(e, rest);
  const MirValue left_len = sd_sub(e, mid, lo);
  const MirValue right_len = sd_sub(e, hi, mid);
  const MirValue left_short = sd_cmp(e, MCC_LE, left_len, right_len);
  const MirBlock fwd = mir_b_new_block(e->b), back = mir_b_new_block(e->b);
  mir_b_br_if(e->b, left_short, fwd, NULL, 0, back, NULL, 0);
  mir_b_seal_block(e->b, fwd);
  mir_b_seal_block(e->b, back);
  mir_b_switch_to(e->b, fwd);
  sd_run_merge_forward(e, items, buf, lo, mid, hi, env);
  mir_b_switch_to(e->b, back);
  sd_run_merge_backward(e, items, buf, lo, mid, hi, mm1, env);
}

/* The stable-partition test: before the pivot, or (when `non_strict`) not after it. */
static MirValue sd_before(SdEm *e, MirValue non_strict, MirValue env, MirValue pivot, MirValue x) {
  const SdPick p = sd_pick(e, MIR_BOOL, non_strict);
  const MirValue after = sd_less(e, env, pivot, x);
  const MirValue z = sd_int(e, 0);
  const MirValue f = sd_b2i(e, after);
  const MirValue not_after = sd_cmp(e, MCC_EQ, f, z);
  sd_pick_else(e, &p, not_after);
  const MirValue strictly = sd_less(e, env, x, pivot);
  return sd_pick_end(e, &p, strictly);
}

/* `part(items, scratch, lo, hi, pivot, le, env)`: moves the elements before `pivot` (or, when
 * `le` is not 0, not after it) to the front of `items[lo..hi]` and the rest behind them, both in
 * their original order; returns how many moved to the front. No step branches on the
 * comparison: the store goes to a selected address. */
static void sd_build_part(SdEm *e) {
  MirValue a[7];
  mir_b_params(e->b, a, 7);
  const MirValue items = a[0], buf = a[1], lo = a[2], hi = a[3], pivot = a[4], le = a[5];
  const MirValue env = a[6];
  const MirValue zero = sd_int(e, 0);
  const MirVar iv = sd_var(e, lo), ltv = sd_var(e, zero), gev = sd_var(e, zero);
  const MirValue non_strict = sd_cmp(e, MCC_NE, le, zero);
  const SdLoop loop = sd_loop(e);
  const MirValue i = sd_get(e, iv);
  const MirValue done = sd_cmp(e, MCC_GE, i, hi);
  sd_brk_if(e, done, loop.exit);
  const MirValue x = sd_ld(e, items, i);
  const MirValue before = sd_before(e, non_strict, env, pivot, x);
  const MirValue lt = sd_get(e, ltv);
  const MirValue ge = sd_get(e, gev);
  /* One store, to the front of `items` or to the next slot of the scratch list. */
  const MirValue front = sd_add(e, lo, lt);
  const MirValue back = sd_add(e, lo, ge);
  const MirValue pf = sd_at(e, items, front);
  const MirValue pb = sd_at(e, buf, back);
  const MirValue dest = mir_b_select(e->b, before, pf, pb);
  sd_store_at(e, dest, x);
  const MirValue c = sd_b2i(e, before);
  const MirValue one = sd_int(e, 1);
  const MirValue rest = sd_sub(e, one, c);
  const MirValue lt1 = sd_add(e, lt, c);
  const MirValue ge1 = sd_add(e, ge, rest);
  sd_set(e, ltv, lt1);
  sd_set(e, gev, ge1);
  const MirValue i1 = sd_add_k(e, i, 1);
  sd_set(e, iv, i1);
  sd_loop_end(e, &loop);
  const MirValue lt2 = sd_get(e, ltv);
  const MirValue ge2 = sd_get(e, gev);
  const MirValue dst = sd_add(e, lo, lt2);
  const MirVar kv = sd_var(e, zero);
  const SdLoop copy = sd_loop(e);
  const MirValue k = sd_get(e, kv);
  const MirValue copied = sd_cmp(e, MCC_GE, k, ge2);
  sd_brk_if(e, copied, copy.exit);
  const MirValue from = sd_add(e, lo, k);
  const MirValue y = sd_ld(e, buf, from);
  const MirValue to = sd_add(e, dst, k);
  sd_st(e, items, to, y);
  const MirValue k1 = sd_add_k(e, k, 1);
  sd_set(e, kv, k1);
  sd_loop_end(e, &copy);
  mir_b_ret(e->b, lt2);
}

/* `pivot(items, a, b, c, n, env)`: the index of the median of `items[a]`, `items[b]` and
 * `items[c]`; with `n` of 8 or more, each is first the median of three slots `n / 8` apart. */
static void sd_build_pivot(SdEm *e, const SdParts *parts) {
  MirValue a[6];
  mir_b_params(e->b, a, 6);
  const MirValue items = a[0], n = a[4], env = a[5];
  const MirValue eight = sd_int(e, 8);
  const MirValue deep = sd_cmp(e, MCC_GE, n, eight);
  const MirValue three = sd_int(e, 3);
  const MirValue n8 = mir_b_binop(e->b, MOP_Sshr, n, three);
  const MirValue four = sd_int(e, 4);
  const MirValue seven = sd_int(e, 7);
  const MirValue s4 = mir_b_binop(e->b, MOP_IMul, n8, four);
  const MirValue s7 = mir_b_binop(e->b, MOP_IMul, n8, seven);
  MirValue refined[3];
  for (uint32_t k = 0; k < 3; k++) {
    const MirValue at = a[1 + k];
    const SdPick p = sd_pick(e, MIR_INT, deep);
    const MirValue pb = sd_add(e, at, s4);
    const MirValue pc = sd_add(e, at, s7);
    const MirValue args[6] = {items, at, pb, pc, n8, env};
    const MirValue sub = sd_call(e, parts->pivot, args, 6);
    sd_pick_else(e, &p, sub);
    refined[k] = sd_pick_end(e, &p, at);
  }
  const MirValue vx = sd_ld(e, items, refined[0]);
  const MirValue vy = sd_ld(e, items, refined[1]);
  const MirValue vz = sd_ld(e, items, refined[2]);
  const MirValue lxy = sd_less(e, env, vx, vy);
  const MirValue lxz = sd_less(e, env, vx, vz);
  const MirValue lyz = sd_less(e, env, vy, vz);
  const MirValue xy = sd_b2i(e, lxy);
  const MirValue xz = sd_b2i(e, lxz);
  const MirValue yz = sd_b2i(e, lyz);
  /* When `x` is neither the least nor the greatest it is the median; otherwise `y` or `z` is. */
  const MirValue agree = sd_cmp(e, MCC_EQ, xy, xz);
  const MirValue flip = mir_b_binop(e->b, MOP_Xor, yz, xy);
  const MirValue zero = sd_int(e, 0);
  const MirValue flipped = sd_cmp(e, MCC_NE, flip, zero);
  const MirValue other = mir_b_select(e->b, flipped, refined[2], refined[1]);
  const MirValue median = mir_b_select(e->b, agree, other, refined[0]);
  mir_b_ret(e->b, median);
}

/* Partitions around `pv` with `le` set, then sorts what follows the equal elements: the slice's
 * elements up to the pivot are all equal and need no more sorting. Ends in a return. */
static void sd_quick_equal_tail(SdEm *e, const SdParts *parts, const MirValue *a, MirValue pv,
                MirValue zero, MirValue one, MirValue next) {
  const MirValue items = a[0], buf = a[1], lo = a[2], hi = a[3], env = a[7];
  const MirValue part_args[7] = {items, buf, lo, hi, pv, one, env};
  const MirValue c = sd_call(e, parts->part, part_args, 7);
  const MirValue from = sd_add(e, lo, c);
  const MirValue quick_args[8] = {items, buf, from, hi, zero, pv, next, env};
  (void)sd_call(e, parts->quick, quick_args, 8);
  sd_unit_ret(e);
}

/* `quick`'s deep case: copy the slice to `buf` and merge sort it. Ends in a return. */
static void sd_quick_spent(SdEm *e, const SdParts *parts, const MirValue *a) {
  const MirValue items = a[0], buf = a[1], lo = a[2], hi = a[3], env = a[7];
  sd_copy_range(e, items, buf, lo, hi);
  const MirValue args[5] = {buf, items, lo, hi, env};
  (void)sd_call(e, parts->mergesort, args, 5);
  sd_unit_ret(e);
}

/* The pivot of a `quick` slice of `n` elements: the median of three candidates, each refined for 64 or more. */
static MirValue sd_quick_pivot(SdEm *e, const SdParts *parts, const MirValue *a, MirValue n, MirValue zero) {
  const MirValue items = a[0], lo = a[2], env = a[7];
  const MirValue three = sd_int(e, 3);
  const MirValue n8 = mir_b_binop(e->b, MOP_Sshr, n, three);
  const MirValue four = sd_int(e, 4);
  const MirValue seven = sd_int(e, 7);
  const MirValue s4 = mir_b_binop(e->b, MOP_IMul, n8, four);
  const MirValue s7 = mir_b_binop(e->b, MOP_IMul, n8, seven);
  const MirValue pb = sd_add(e, lo, s4);
  const MirValue pc = sd_add(e, lo, s7);
  const MirValue sixty_four = sd_int(e, 64);
  const MirValue big = sd_cmp(e, MCC_GE, n, sixty_four);
  /* Below 64 slots the three are the candidates themselves. */
  const MirValue depth = mir_b_select(e->b, big, n8, zero);
  const MirValue pivot_args[6] = {items, lo, pb, pc, depth, env};
  const MirValue p = sd_call(e, parts->pivot, pivot_args, 6);
  return sd_ld(e, items, p);
}

/* `quick(items, scratch, lo, hi, anc_set, anc, limit, env)`: stable quicksort of
 * `items[lo..hi]`. `anc` (when `anc_set` is not 0) is a pivot of an enclosing call and not
 * after any element here. */
static void sd_build_quick(SdEm *e, const SdParts *parts) {
  MirValue a[8];
  mir_b_params(e->b, a, 8);
  const MirValue items = a[0], buf = a[1], lo = a[2], hi = a[3];
  const MirValue anc_set = a[4], anc = a[5], limit = a[6], env = a[7];
  const MirValue n = sd_sub(e, hi, lo);
  const MirValue small = sd_int(e, SD_SMALL);
  const MirValue few = sd_cmp(e, MCC_LE, n, small);
  MirBlock rest = sd_if_ret(e, few);
  const MirValue ins_args[4] = {items, lo, hi, env};
  (void)sd_call(e, parts->ins, ins_args, 4);
  sd_unit_ret(e);
  sd_if_ret_end(e, rest);
  const MirValue zero = sd_int(e, 0);
  const MirValue spent = sd_cmp(e, MCC_LE, limit, zero);
  rest = sd_if_ret(e, spent);
  sd_quick_spent(e, parts, a); /* too deep: merge sort the slice */
  sd_if_ret_end(e, rest);
  const MirValue pv = sd_quick_pivot(e, parts, a, n, zero);
  const MirValue next = sd_add_k(e, limit, -1);
  /* An element that is not after the ancestor pivot is, with this pivot, equal to it. */
  const MirValue has_anc = sd_cmp(e, MCC_NE, anc_set, zero);
  const SdPick pick = sd_pick(e, MIR_BOOL, has_anc);
  const MirValue after = sd_less(e, env, anc, pv);
  const MirValue f = sd_b2i(e, after);
  const MirValue z = sd_int(e, 0);
  const MirValue not_after = sd_cmp(e, MCC_EQ, f, z);
  sd_pick_else(e, &pick, not_after);
  const MirValue no = mir_b_bconst(e->b, false);
  const MirValue equal = sd_pick_end(e, &pick, no);
  const MirValue one = sd_int(e, 1);
  rest = sd_if_ret(e, equal);
  sd_quick_equal_tail(e, parts, a, pv, zero, one, next);
  sd_if_ret_end(e, rest);
  const MirValue part_args[7] = {items, buf, lo, hi, pv, zero, env};
  const MirValue c = sd_call(e, parts->part, part_args, 7);
  const MirValue none = sd_cmp(e, MCC_EQ, c, zero);
  rest = sd_if_ret(e, none);
  sd_quick_equal_tail(e, parts, a, pv, zero, one, next); /* the pivot is the least */
  sd_if_ret_end(e, rest);
  const MirValue mid = sd_add(e, lo, c);
  const MirValue left_args[8] = {items, buf, lo, mid, anc_set, anc, next, env};
  (void)sd_call(e, parts->quick, left_args, 8);
  const MirValue right_args[8] = {items, buf, mid, hi, one, pv, next, env};
  (void)sd_call(e, parts->quick, right_args, 8);
  sd_unit_ret(e);
}

/* The end of run `k`: `ends[k]` shifted right once (the low bit says the run is sorted). */
static MirValue sd_end_of(SdEm *e, MirValue ends, MirValue k, MirValue one) {
  const MirValue w = sd_ld_int(e, ends, k);
  return mir_b_binop(e->b, MOP_Sshr, w, one);
}

/* The index `k` after the first run that reaches `target`, searching from `first`; the split
 * leaves one run on the right. */
static MirValue sd_split_point(SdEm *e, MirValue ends, MirValue first, MirValue last,
               MirValue target, MirValue one) {
  const MirVar kv = sd_var(e, first);
  const SdLoop loop = sd_loop(e);
  const MirValue k = sd_get(e, kv);
  const MirValue at_last = sd_cmp(e, MCC_GE, k, last);
  sd_brk_if(e, at_last, loop.exit);
  const MirValue pk = sd_add_k(e, k, -1);
  const MirValue reach = sd_end_of(e, ends, pk, one);
  const MirValue enough = sd_cmp(e, MCC_GE, reach, target);
  sd_brk_if(e, enough, loop.exit);
  const MirValue k1 = sd_add_k(e, k, 1);
  sd_set(e, kv, k1);
  sd_loop_end(e, &loop);
  return sd_get(e, kv);
}

/* `runs(items, scratch, ends, i, j, limit, env)`: sorts the runs `i..j` that `ends` describes
 * (the end of run `k` shifted left once, with the low bit set when the run is already sorted) as
 * far as merging them goes. Returns 1 when the result is one unsorted slice that its caller
 * sorts, 0 when it is sorted. */
static void sd_build_runs(SdEm *e, const SdParts *parts) {
  MirValue a[7];
  mir_b_params(e->b, a, 7);
  const MirValue items = a[0], buf = a[1], ends = a[2], i = a[3], j = a[4];
  const MirValue limit = a[5], env = a[6];
  const MirValue zero = sd_int(e, 0);
  const MirValue one = sd_int(e, 1);
  const MirValue count = sd_sub(e, j, i);
  const MirValue single = sd_cmp(e, MCC_EQ, count, one);
  MirBlock rest = sd_if_ret(e, single);
  const MirValue w = sd_ld_int(e, ends, i);
  const MirValue bit = mir_b_binop(e->b, MOP_And, w, one);
  const MirValue unsorted = sd_sub(e, one, bit);
  mir_b_ret(e->b, unsorted);
  sd_if_ret_end(e, rest);
  /* The run before `i` ends where run `i` starts. */
  const MirValue has_prev = sd_cmp(e, MCC_GT, i, zero);
  const SdPick pick = sd_pick(e, MIR_INT, has_prev);
  const MirValue prev = sd_add_k(e, i, -1);
  const MirValue prev_end = sd_end_of(e, ends, prev, one);
  sd_pick_else(e, &pick, prev_end);
  const MirValue origin = sd_int(e, 0);
  const MirValue start = sd_pick_end(e, &pick, origin);
  const MirValue last = sd_add_k(e, j, -1);
  const MirValue finish = sd_end_of(e, ends, last, one);
  const MirValue span = sd_sub(e, finish, start);
  const MirValue half = mir_b_binop(e->b, MOP_Sshr, span, one);
  const MirValue target = sd_add(e, start, half);
  const MirValue first = sd_add_k(e, i, 1);
  const MirValue k = sd_split_point(e, ends, first, last, target, one);
  const MirValue pk = sd_add_k(e, k, -1);
  const MirValue mid = sd_end_of(e, ends, pk, one);
  const MirValue left_args[7] = {items, buf, ends, i, k, limit, env};
  const MirValue left = sd_call(e, parts->msort, left_args, 7);
  const MirValue right_args[7] = {items, buf, ends, k, j, limit, env};
  const MirValue right = sd_call(e, parts->msort, right_args, 7);
  const MirValue both = mir_b_binop(e->b, MOP_And, left, right);
  const MirValue merged_open = sd_cmp(e, MCC_NE, both, zero);
  rest = sd_if_ret(e, merged_open);
  mir_b_ret(e->b, one);
  sd_if_ret_end(e, rest);
  const MirValue dummy = sd_ld(e, items, start);
  const MirValue left_open = sd_cmp(e, MCC_NE, left, zero);
  MirBlock join = sd_if(e, left_open);
  const MirValue lq[8] = {items, buf, start, mid, zero, dummy, limit, env};
  (void)sd_call(e, parts->quick, lq, 8);
  sd_if_end(e, join);
  const MirValue right_open = sd_cmp(e, MCC_NE, right, zero);
  join = sd_if(e, right_open);
  const MirValue rq[8] = {items, buf, mid, finish, zero, dummy, limit, env};
  (void)sd_call(e, parts->quick, rq, 8);
  sd_if_end(e, join);
  const MirValue merge_args[6] = {items, buf, start, mid, finish, env};
  (void)sd_call(e, parts->merge, merge_args, 6);
  mir_b_ret(e->b, zero);
}

/* Reverses `items[from..to]` in place. */
static void sd_reverse(SdEm *e, MirValue items, MirValue from, MirValue to) {
  const MirVar fv = sd_var(e, from), bv = sd_var(e, to);
  const SdLoop loop = sd_loop(e);
  const MirValue f = sd_get(e, fv);
  const MirValue b = sd_get(e, bv);
  const MirValue b1 = sd_add_k(e, b, -1);
  const MirValue crossed = sd_cmp(e, MCC_GE, f, b1);
  sd_brk_if(e, crossed, loop.exit);
  const MirValue x = sd_ld(e, items, f);
  const MirValue y = sd_ld(e, items, b1);
  sd_st(e, items, f, y);
  sd_st(e, items, b1, x);
  const MirValue f1 = sd_add_k(e, f, 1);
  sd_set(e, fv, f1);
  sd_set(e, bv, b1);
  sd_loop_end(e, &loop);
}

/* The shortest run kept as it is: 64, or about the square root of `n` for long inputs. */
static MirValue sd_min_run(SdEm *e, MirValue n, MirValue one) {
  const MirValue sixty_four = sd_int(e, 64);
  const MirValue wide = sd_int(e, 4096);
  const MirValue is_long = sd_cmp(e, MCC_GT, n, wide);
  const MirValue half = mir_b_binop(e->b, MOP_Sshr, n, one);
  const MirValue upper = sd_sub(e, n, half);
  const MirValue short_cut = sd_cmp(e, MCC_LT, upper, sixty_four);
  const MirValue short_min = mir_b_select(e->b, short_cut, upper, sixty_four);
  const MirVar sv = sd_var(e, sixty_four);
  const MirBlock join = sd_if(e, is_long);
  const SdLoop loop = sd_loop(e);
  const MirValue s = sd_get(e, sv);
  const MirValue sq = mir_b_binop(e->b, MOP_IMul, s, s);
  const MirValue enough = sd_cmp(e, MCC_GE, sq, n);
  sd_brk_if(e, enough, loop.exit);
  const MirValue two = sd_int(e, 2);
  const MirValue s2 = mir_b_binop(e->b, MOP_IMul, s, two);
  sd_set(e, sv, s2);
  sd_loop_end(e, &loop);
  sd_if_end(e, join);
  const MirValue root = sd_get(e, sv);
  return mir_b_select(e->b, is_long, root, short_min);
}

/* Quicksort depth: twice the floor of log2 of `n`. */
static MirValue sd_depth_limit(SdEm *e, MirValue n, MirValue zero, MirValue one) {
  const MirVar tv = sd_var(e, n), lv = sd_var(e, zero);
  const SdLoop loop = sd_loop(e);
  const MirValue t = sd_get(e, tv);
  const MirValue done = sd_cmp(e, MCC_LE, t, one);
  sd_brk_if(e, done, loop.exit);
  const MirValue t1 = mir_b_binop(e->b, MOP_Sshr, t, one);
  sd_set(e, tv, t1);
  const MirValue count = sd_get(e, lv);
  const MirValue count1 = sd_add_k(e, count, 1);
  sd_set(e, lv, count1);
  sd_loop_end(e, &loop);
  const MirValue l = sd_get(e, lv);
  return mir_b_binop(e->b, MOP_IAdd, l, l);
}


/* A natural run at `pos`: non-descending, or strictly descending. Returns the length variable and
 * leaves the descending flag in `*descv`. */
static MirVar sd_natural_run(SdEm *e, const SdScan *s, MirValue pos, MirVar *descv) {
  const MirValue left = sd_sub(e, s->n, pos);
  const MirValue two = sd_int(e, 2);
  const MirValue pair = sd_cmp(e, MCC_GE, left, two);
  const MirVar lenv = sd_var(e, s->one);
  *descv = sd_var(e, s->zero);
  const MirBlock join = sd_if(e, pair);
  const MirValue p1 = sd_add_k(e, pos, 1);
  const MirValue x1 = sd_ld(e, s->items, p1);
  const MirValue x0 = sd_ld(e, s->items, pos);
  const MirValue down = sd_less(e, s->env, x1, x0);
  const MirValue d = sd_b2i(e, down);
  sd_set(e, *descv, d);
  sd_set(e, lenv, two);
  const SdLoop stop = sd_loop(e);
  const MirValue len = sd_get(e, lenv);
  const MirValue at = sd_add(e, pos, len);
  const MirValue end = sd_cmp(e, MCC_GE, at, s->n);
  sd_brk_if(e, end, stop.exit);
  const MirValue before = sd_add_k(e, at, -1);
  const MirValue cur = sd_ld(e, s->items, at);
  const MirValue prev = sd_ld(e, s->items, before);
  const MirValue step = sd_less(e, s->env, cur, prev);
  const MirValue st = sd_b2i(e, step);
  const MirValue dd = sd_get(e, *descv);
  const MirValue stops = sd_cmp(e, MCC_NE, st, dd);
  sd_brk_if(e, stops, stop.exit);
  const MirValue len1 = sd_add_k(e, len, 1);
  sd_set(e, lenv, len1);
  sd_loop_end(e, &stop);
  sd_if_end(e, join);
  return lenv;
}

/* The entry recorded for the run at `pos`: a kept natural run (reversed first when it descends)
 * or a stretch of `min_run` slots left unsorted. */
static MirValue sd_run_entry(SdEm *e, const SdScan *s, MirValue pos, MirVar lenv, MirVar descv) {
  const MirValue len = sd_get(e, lenv);
  const MirValue kept = sd_cmp(e, MCC_GE, len, s->min_run);
  const SdPick pick = sd_pick(e, MIR_INT, kept);
  const MirValue down = sd_get(e, descv);
  const MirValue flip = sd_cmp(e, MCC_NE, down, s->zero);
  const MirValue end = sd_add(e, pos, len);
  const MirBlock join = sd_if(e, flip);
  sd_reverse(e, s->items, pos, end);
  sd_if_end(e, join);
  const MirValue shifted = mir_b_binop(e->b, MOP_Shl, end, s->one);
  const MirValue sorted_entry = mir_b_binop(e->b, MOP_Or, shifted, s->one);
  sd_pick_else(e, &pick, sorted_entry);
  const MirValue rest = sd_sub(e, s->n, pos);
  const MirValue fits = sd_cmp(e, MCC_LT, rest, s->min_run);
  const MirValue chunk = mir_b_select(e->b, fits, rest, s->min_run);
  const MirValue stretch_end = sd_add(e, pos, chunk);
  const MirValue open_entry = mir_b_binop(e->b, MOP_Shl, stretch_end, s->one);
  return sd_pick_end(e, &pick, open_entry);
}

/* Cuts the input into runs, recording each in `ends`; returns the number of runs. */
static MirValue sd_cut_runs(SdEm *e, const SdScan *s) {
  const MirVar pv = sd_var(e, s->zero), rv = sd_var(e, s->zero);
  const SdLoop loop = sd_loop(e);
  const MirValue pos = sd_get(e, pv);
  const MirValue done = sd_cmp(e, MCC_GE, pos, s->n);
  sd_brk_if(e, done, loop.exit);
  MirVar descv = 0;
  const MirVar lenv = sd_natural_run(e, s, pos, &descv);
  const MirValue entry = sd_run_entry(e, s, pos, lenv, descv);
  const MirValue end = mir_b_binop(e->b, MOP_Sshr, entry, s->one);
  const MirValue r = sd_get(e, rv);
  sd_st_int(e, s->ends, r, entry);
  const MirValue r1 = sd_add_k(e, r, 1);
  sd_set(e, rv, r1);
  sd_set(e, pv, end);
  sd_loop_end(e, &loop);
  return sd_get(e, rv);
}

/* `drift(scratch, items, 0, n, env)`: the entry point. */
static void sd_build_top(SdEm *e, const SdParts *parts) {
  MirValue a[5];
  mir_b_params(e->b, a, 5);
  const MirValue buf = a[0], items = a[1], n = a[3], env = a[4];
  const MirValue zero = sd_int(e, 0);
  const MirValue one = sd_int(e, 1);
  const MirValue small = sd_int(e, SD_SMALL);
  const MirValue few = sd_cmp(e, MCC_LE, n, small);
  const MirBlock rest = sd_if_ret(e, few);
  const MirValue ins_args[4] = {items, zero, n, env};
  (void)sd_call(e, parts->ins, ins_args, 4);
  sd_unit_ret(e);
  sd_if_ret_end(e, rest);
  const MirValue min_run = sd_min_run(e, n, one);
  const MirValue limit = sd_depth_limit(e, n, zero, one);
  const MirValue max_runs = mir_b_binop(e->b, MOP_SDiv, n, min_run);
  const MirValue cap = sd_add_k(e, max_runs, 2);
  const MirValue ends = mir_b_list_new(e->b, MIR_INT, cap);
  const SdScan scan = {items, ends, env, n, min_run, zero, one};
  const MirValue runs = sd_cut_runs(e, &scan);
  const MirValue msort_args[7] = {items, buf, ends, zero, runs, limit, env};
  const MirValue open = sd_call(e, parts->msort, msort_args, 7);
  const MirValue dummy = sd_ld(e, items, zero);
  const MirValue unsorted = sd_cmp(e, MCC_NE, open, zero);
  const MirBlock join = sd_if(e, unsorted);
  const MirValue quick_args[8] = {items, buf, zero, n, zero, dummy, limit, env};
  (void)sd_call(e, parts->quick, quick_args, 8);
  sd_if_end(e, join);
  (void)mir_b_emit(e->b, MOP_Drop, &ends, 1, (MirImm){0}, MIR_NONE);
  sd_unit_ret(e);
}

/* Builds the driftsort for comparator `g` over `elem` slots and returns the entry point,
 * `drift(scratch, items, 0, n, env)`: a stable sort of `items[0..n]` by the sign of
 * `g(env, a, b)`, the algorithm of Rust's `slice::sort`. */
uint32_t opt_sortgen_drift(MirModule *m, uint32_t g, MirTy elem) {
  const MirTy list_ty = mir_ty_list(m, elem);
  const MirTy i = MIR_INT, p = MIR_PTR;
  SdParts parts = {0};
  parts.mergesort = sd_build_merge(m, g, elem);
  const MirTy ins_types[4] = {list_ty, i, i, p};
  parts.ins = sd_declare(m, sd_name(m, "sort.ins.", g), ins_types, 4, MIR_VOID);
  const MirTy merge_types[6] = {list_ty, list_ty, i, i, i, p};
  parts.merge = sd_declare(m, sd_name(m, "sort.run_merge.", g), merge_types, 6, MIR_VOID);
  const MirTy part_types[7] = {list_ty, list_ty, i, i, elem, i, p};
  parts.part = sd_declare(m, sd_name(m, "sort.part.", g), part_types, 7, MIR_INT);
  const MirTy pivot_types[6] = {list_ty, i, i, i, i, p};
  parts.pivot = sd_declare(m, sd_name(m, "sort.pivot.", g), pivot_types, 6, MIR_INT);
  const MirTy quick_types[8] = {list_ty, list_ty, i, i, i, elem, i, p};
  parts.quick = sd_declare(m, sd_name(m, "sort.quick.", g), quick_types, 8, MIR_VOID);
  const MirTy int_list = mir_ty_list(m, MIR_INT);
  const MirTy runs_types[7] = {list_ty, list_ty, int_list, i, i, i, p};
  parts.msort = sd_declare(m, sd_name(m, "sort.runs.", g), runs_types, 7, MIR_INT);
  const MirTy drift_types[5] = {list_ty, list_ty, i, i, p};
  const uint32_t drift = sd_declare(m, sd_name(m, "sort.drift.", g), drift_types, 5, MIR_VOID);

  MirBuilder b;
  SdEm e = {&b, elem, g};
  sd_start(&b, m, parts.ins, MIR_VOID);
  sd_build_ins(&e);
  sd_finish(&b, m, parts.ins);
  sd_start(&b, m, parts.merge, MIR_VOID);
  sd_build_run_merge(&e);
  sd_finish(&b, m, parts.merge);
  sd_start(&b, m, parts.part, MIR_INT);
  sd_build_part(&e);
  sd_finish(&b, m, parts.part);
  sd_start(&b, m, parts.pivot, MIR_INT);
  sd_build_pivot(&e, &parts);
  sd_finish(&b, m, parts.pivot);
  sd_start(&b, m, parts.quick, MIR_VOID);
  sd_build_quick(&e, &parts);
  sd_finish(&b, m, parts.quick);
  sd_start(&b, m, parts.msort, MIR_INT);
  sd_build_runs(&e, &parts);
  sd_finish(&b, m, parts.msort);
  sd_start(&b, m, drift, MIR_VOID);
  sd_build_top(&e, &parts);
  sd_finish(&b, m, drift);
  return drift;
}
