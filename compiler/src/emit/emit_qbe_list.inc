/* Unchecked list element access for emit_qbe.c (included from it). A list is three leaves (the
 * element address, the length, the capacity); element `i` lives `i * stride` bytes from the address,
 * its leaves laid out as in memory (mir_mem_layout). */

/* The element type of the list or bytes value `list_ty`. */
static MirTy qbe_list_elem(const QCx *c, MirTy list_ty) {
    const MirTyData *data = mir_ty_data(c->m, list_ty);
    return data->kind == MK_BYTES ? MIR_UINT8 : data->elem;
}

/* Writes `%e<n> =l add <list address>, index * stride` and returns the register's text in `out`. */
static void qbe_element_address(QCx *c, const MirInst *inst, MirTy elem, char *out, size_t cap) {
    const uint32_t n = c->next++;
    const uint32_t stride = mir_type_mem(c->layouts, elem).size;
    ms_buf_printf(c->out, "\t%%e%u =l mul %%v%u, %u\n\t%%e%ua =l add %%v%u, %%e%u\n", n, inst->args[1],
                  stride, n, inst->args[0], n);
    (void)snprintf(out, cap, "%%e%ua", n);
}

/* The list operations here; `*handled` says whether `inst` is one. */
static bool qbe_list_op(QCx *c, const MirInst *inst, bool *handled) {
    *handled = true;
    char at[24];
    switch ((MirOp)inst->op) {
    case MOP_ListGetU: case MOP_ListTake:
        qbe_element_address(c, inst, qbe_list_elem(c, c->f->values[inst->args[0]]), at, sizeof at);
        return qbe_load_leaves(c, inst->res, at);
    case MOP_ListAddrU:
        qbe_element_address(c, inst, qbe_list_elem(c, c->f->values[inst->args[0]]), at, sizeof at);
        ms_buf_printf(c->out, "\t%%v%u =l copy %s\n", inst->res, at);
        return true;
    default:
        *handled = false;
        return true;
    }
}
