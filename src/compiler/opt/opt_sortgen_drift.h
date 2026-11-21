/* The sort builders of `sortgen`: the emitter helpers shared by the merge sort and the driftsort. */
#ifndef MS_COMPILER_OPT_OPT_SORTGEN_DRIFT_H
#define MS_COMPILER_OPT_OPT_SORTGEN_DRIFT_H

#include "compiler/mir/mir_builder.h"
#include "compiler/opt/opt_pass.h"


enum {
  SD_INSERTION_MAX = 12, /* the fallback merge sort inserts slices this short */
  SD_SMALL = 20          /* slices at most this long are sorted by insertion */
};

/* Emits straight-line and structured code for the helpers of one sort. */
typedef struct SdEm {
  MirBuilder *b;
  MirTy elem;
  uint32_t g; /* the comparator */
} SdEm;

/* A value chosen by `cond`, computing only the chosen side: `sd_pick`, the first side's code,
 * `sd_pick_else(first)`, the second side's code, `sd_pick_end(second)`. */
typedef struct SdPick {
  MirBlock other, join;
  MirValue out;
} SdPick;

/* A loop: the code after `sd_loop` repeats until it leaves through `exit` (`sd_brk_if`). */
typedef struct SdLoop {
  MirBlock head, exit;
} SdLoop;

/* The merge loop's state. */
typedef struct SdMergeVars {
  MirVar l, le, r, re, s;
} SdMergeVars;

/* The cursors a merge step reads, and the left and right cursors after its front half. */
typedef struct SdStep {
  MirValue le, re, l1, r1;
} SdStep;

/* The helpers of the driftsort, by role. */
typedef struct SdParts {
  uint32_t ins, merge, part, pivot, quick, msort, mergesort;
} SdParts;

/* The state of the scan that cuts the input into runs. */
typedef struct SdScan {
  MirValue items, ends, env, n, min_run, zero, one;
} SdScan;

MirValue sd_int(SdEm *e, int64_t v);
MirValue sd_add(SdEm *e, MirValue x, MirValue y);
MirValue sd_sub(SdEm *e, MirValue x, MirValue y);
MirValue sd_cmp(SdEm *e, MirCc cc, MirValue x, MirValue y);
MirValue sd_add_k(SdEm *e, MirValue x, int64_t k);
MirValue sd_b2i(SdEm *e, MirValue flag);
MirVar sd_var(SdEm *e, MirValue init);
MirValue sd_get(SdEm *e, MirVar v);
void sd_set(SdEm *e, MirVar v, MirValue x);
MirValue sd_at(SdEm *e, MirValue list, MirValue i);
MirValue sd_load_at(SdEm *e, MirValue p);
void sd_store_at(SdEm *e, MirValue p, MirValue v);
MirValue sd_ld(SdEm *e, MirValue list, MirValue i);
void sd_st(SdEm *e, MirValue list, MirValue i, MirValue v);
MirValue sd_ld_int(SdEm *e, MirValue ints, MirValue i);
void sd_st_int(SdEm *e, MirValue ints, MirValue i, MirValue v);
MirValue sd_less(SdEm *e, MirValue env, MirValue x, MirValue y);
MirValue sd_call(SdEm *e, uint32_t func, const MirValue *args, uint32_t n);
void sd_unit_ret(SdEm *e);
MirBlock sd_if(SdEm *e, MirValue cond);
void sd_if_end(SdEm *e, MirBlock join);
MirBlock sd_if_ret(SdEm *e, MirValue cond);
void sd_if_ret_end(SdEm *e, MirBlock rest);
SdPick sd_pick(SdEm *e, MirTy ty, MirValue cond);
void sd_pick_else(SdEm *e, const SdPick *p, MirValue first);
MirValue sd_pick_end(SdEm *e, const SdPick *p, MirValue second);
SdLoop sd_loop(SdEm *e);
void sd_loop_end(SdEm *e, const SdLoop *l);
void sd_brk_if(SdEm *e, MirValue cond, MirBlock exit);
MsName sd_name(MirModule *m, const char *prefix, uint32_t g);
uint32_t sd_declare(MirModule *m, MsName name, const MirTy *types, uint32_t n, MirTy ret);
void sd_start(MirBuilder *b, MirModule *m, uint32_t id, MirTy ret);
void sd_finish(MirBuilder *b, MirModule *m, uint32_t id);
uint32_t sd_build_merge(MirModule *m, uint32_t g, MirTy elem);

#endif
