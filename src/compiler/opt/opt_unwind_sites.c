/* opt_unwind_sites: a test of the `unwinding` byte after a call that cannot park is always clear.
 *
 * A cancel is delivered only inside a park (`ms_cancel_deliver`), so the byte test after a call is needed only when
 * the call can reach a cancellation point. Elsewhere the test becomes the constant zero, and the simplifier removes
 * the branch and the exit it guarded. */
#include "compiler/mir/mir_pass.h"
#include "compiler/opt/opt_pass.h"

/* Whether `inst` is the byte test of an unwind site. */
static bool is_site_test(const MirModule *m, const MirInst *inst) {
  return inst->op == MOP_CallRt && inst->imm.tag == MI_EXT && m->externs.ptr[inst->imm.a].role == MR_UNWINDING;
}

/* Whether `inst` is a call whose result the byte test right after it guards. */
static bool is_call(const MirInst *inst) {
  return inst->op == MOP_Call || inst->op == MOP_CallRt || inst->op == MOP_CallInd || inst->op == MOP_CallMethod;
}

bool opt_unwind_sites(MirModule *m) {
  MsArena arena = ms_arena_new();
  const bool *parks = mir_parking_funcs(&arena, m);
  bool changed = false;
  for (size_t fi = 0; fi < m->funcs.len; fi++) {
    MirFunc *f = &m->funcs.ptr[fi];
    for (size_t bi = 0; bi < f->blocks.len; bi++) {
      MirInstList *insts = &f->blocks.ptr[bi].insts;
      for (size_t k = 1; k < insts->len; k++) {
        MirInst *test = &insts->ptr[k];
        const MirInst *call = &insts->ptr[k - 1];
        if (!is_site_test(m, test) || !is_call(call) || mir_inst_parks(m, parks, call)) {
          continue;
        }
        test->op = MOP_BConst;
        test->imm = (MirImm){.tag = MI_BOOL, .a = 0};
        changed = true;
      }
    }
  }
  ms_arena_free(&arena);
  return changed;
}
