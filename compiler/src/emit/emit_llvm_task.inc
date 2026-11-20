/* Task operations for emit_llvm.c (included from it): the cancellation poll and `undef`. The stack
 * pointer masked to the region's size finds the cell at the region's end (`MIR_STACK_REGION`). */

/* Writes the address of the cell `back` bytes before the end of the running stack's region and
 * the stack pointer itself; their names go to `sp` and `cell`. */
static void ll_region_cell(LCx *c, uint32_t back, char *sp, char *cell, size_t cap) {
    const uint32_t n = c->next++;
    ms_buf_printf(c->out,
                  "  %%e%u = call ptr @llvm.frameaddress.p0(i32 0)\n  %%g%u = ptrtoint ptr %%e%u to i64\n"
                  "  %%h%u = and i64 %%g%u, %lld\n  %%j%u = add i64 %%h%u, %lld\n"
                  "  %%d%u = inttoptr i64 %%j%u to ptr\n",
                  n, n, n, n, n, -(long long)MIR_STACK_REGION, n, n, (long long)MIR_STACK_REGION - (long long)back,
                  n, n);
    (void)snprintf(sp, cap, "%%g%u", n);
    (void)snprintf(cell, cap, "%%d%u", n);
}

/* `poll`: faults when the running task's cancel flag is set. */
static void ll_poll(LCx *c, uint32_t block, uint32_t *part) {
    char sp[24], cell[24], flag[24];
    ll_region_cell(c, MIR_STACK_HDR_CELL, sp, cell, sizeof sp);
    const uint32_t n = c->next++;
    ms_buf_printf(c->out,
                  "  %%u%u = load i64, ptr %s\n  %%w%u = add i64 %%u%u, %d\n  %%x%u = inttoptr i64 %%w%u to ptr\n"
                  "  %%y%u = load i8, ptr %%x%u\n  %%o%u = icmp ne i8 %%y%u, 0\n",
                  n, cell, n, n, MIR_HDR_CANCEL, n, n, n, n, n, n);
    (void)snprintf(flag, sizeof flag, "%%o%u", n);
    ll_fault_if(c, block, part, flag, "msrt_cancelled", NULL, 0);
}

/* `undef`: any value of the type, one frozen `undef` per leaf. */
static void ll_undef(LCx *c, const MirInst *inst) {
    const MirLeafSpan leaves = ll_leaves(c, c->f->values[inst->res]);
    for (uint32_t k = 0; k < leaves.len; k++) {
        ms_buf_puts(c->out, "  ");
        ll_name(c->out, inst->res, k);
        ms_buf_printf(c->out, " = freeze %s undef\n", ll_leaf_type(leaves.ptr[k]));
    }
}

/* The poll and undef operations; `*handled` says whether `inst` is one. */
static bool ll_task_op(LCx *c, const MirInst *inst, uint32_t block, uint32_t *part, bool *handled) {
    *handled = true;
    switch ((MirOp)inst->op) {
    case MOP_Poll: ll_poll(c, block, part); return true;
    case MOP_Undef: ll_undef(c, inst); return true;
    default:
        *handled = false;
        return true;
    }
}
