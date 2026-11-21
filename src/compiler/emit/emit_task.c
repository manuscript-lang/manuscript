/* Owns the cancellation poll and `undef`. The stack pointer masked to the region's size finds the cell at the
 * region's end (abi/layout.h). */
#include "compiler/emit/emit_cx.h"

#include "abi/layout.h"

/* The byte of a task's header that holds its cancel flag (`offsetof(MsTaskHdr, cancel)`, runtime/core/unwind.h). */
#define TASK_HDR_CANCEL 8

/* Writes the address of the cell `back` bytes before the end of the running stack's region; its name goes to
 * `cell`. */
static void region_cell(EmitCx *cx, uint32_t back, char *cell, size_t capacity) {
  uint32_t number = cx->next++;
  ms_strbuild_printf(cx->out,
                     "  %%e%u = call ptr @llvm.frameaddress.p0(i32 0)\n  %%g%u = ptrtoint ptr %%e%u to i64\n"
                     "  %%h%u = and i64 %%g%u, %lld\n  %%j%u = add i64 %%h%u, %lld\n"
                     "  %%d%u = inttoptr i64 %%j%u to ptr\n",
                     number, number, number, number, number, -(long long)MS_STACK_REGION, number, number,
                     (long long)MS_STACK_REGION - (long long)back, number, number);
  emit_register_name(cell, capacity, "d", number);
}

/* `poll`: faults when the running task's cancel flag is set. */
static void poll(EmitCx *cx, const EmitSite *site) {
  char cell[24];
  char flag[24];
  region_cell(cx, MS_STACK_CELL_HDR, cell, sizeof cell);
  uint32_t number = cx->next++;
  ms_strbuild_printf(cx->out,
                     "  %%u%u = load i64, ptr %s\n  %%w%u = add i64 %%u%u, %d\n  %%x%u = inttoptr i64 %%w%u to ptr\n"
                     "  %%y%u = load i8, ptr %%x%u\n  %%o%u = icmp ne i8 %%y%u, 0\n",
                     number, cell, number, number, TASK_HDR_CANCEL, number, number, number, number, number, number);
  emit_register_name(flag, sizeof flag, "o", number);
  emit_fault_if(cx, site, flag, "msrt_cancelled", NULL, 0);
}

/* `undef`: any value of the type, one frozen `undef` per leaf. */
static void undef(EmitCx *cx, const MirInst *inst) {
  MsSpan leaves = emit_value_leaves(cx, inst->res);
  for (uint32_t leaf = 0; leaf < leaves.len; leaf++) {
    ms_strbuild_append_text(cx->out, "  ");
    emit_name(cx->out, inst->res, leaf);
    ms_strbuild_printf(cx->out, " = freeze %s undef\n", emit_leaf_type(leaves.ptr[leaf]));
  }
}

bool emit_task_op(EmitCx *cx, const MirInst *inst, const EmitSite *site, bool *handled) {
  *handled = true;
  switch ((MirOp)inst->op) {
  case MOP_Poll:
    poll(cx, site);
    return true;
  case MOP_Undef:
    undef(cx, inst);
    return true;
  default:
    *handled = false;
    return true;
  }
}
