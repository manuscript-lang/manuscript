/* Unchecked list element access for emit_llvm.c (included from it); the layout is the one the
 * runtime uses (src/runtime/include/ms_rt). */

/* The element type of the list or bytes value `list_ty`. */
static MirTy ll_list_elem(const LCx *c, MirTy list_ty) {
    const MirTyData *data = mir_ty_data(c->m, list_ty);
    return data->kind == MK_BYTES ? MIR_UINT8 : data->elem;
}

/* Writes the address of element `args[1]` of list `args[0]` and returns its register in `out`. */
static void ll_element_address(LCx *c, const MirInst *inst, MirTy elem, char *out, size_t cap) {
    const uint32_t n = c->next++;
    const uint32_t stride = mir_type_mem(c->layouts, elem).size;
    ms_buf_printf(c->out,
                  "  %%e%u = mul i64 %%v%u, %u\n  %%e%ub = inttoptr i64 %%v%u to ptr\n"
                  "  %%e%up = getelementptr i8, ptr %%e%ub, i64 %%e%u\n",
                  n, inst->args[1], stride, n, inst->args[0], n, n, n);
    (void)snprintf(out, cap, "%%e%up", n);
}

/* The list operations here; `*handled` says whether `inst` is one. */
static bool ll_list_op(LCx *c, const MirInst *inst, bool *handled) {
    *handled = true;
    char at[24];
    switch ((MirOp)inst->op) {
    case MOP_ListGetU: case MOP_ListTake:
    {
        const MirTy elem = ll_list_elem(c, c->f->values[inst->args[0]]);
        ll_element_address(c, inst, elem, at, sizeof at);
        c->tbaa = ll_elem_tbaa(c, elem);
        const bool ok = ll_leaves_at(c, inst->res, at, true);
        c->tbaa = NULL;
        return ok;
    }
    case MOP_ListAddrU:
        ll_element_address(c, inst, ll_list_elem(c, c->f->values[inst->args[0]]), at, sizeof at);
        ms_buf_printf(c->out, "  %%v%u = ptrtoint ptr %s to i64\n", inst->res, at);
        return true;
    default:
        *handled = false;
        return true;
    }
}
