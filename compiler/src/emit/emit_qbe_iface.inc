/* Interfaces for emit_qbe.c (included from it). A value is two words: the data address and the
 * address of its vtable with a tag in the low two bits (owned, boxed, view). Slot 0 of a vtable is
 * the payload drop, slot 1 + k the code of method k. */

enum { QBE_TAG_OWNED = 0, QBE_TAG_BOX = 1, QBE_TAG_VIEW = 2, QBE_TAG_MASK = 3 };

/* Writes `%t<n> =l and <vtable word>, -4` (the vtable address) and returns `n`. */
static uint32_t qbe_untag(QCx *c, MirValue iface) {
    const uint32_t n = c->next++;
    ms_buf_printf(c->out, "\t%%t%u =l and %%v%u.1, %d\n", n, iface, -(QBE_TAG_MASK + 1));
    return n;
}

/* Writes `%t<n> =l copy $vtable` and returns `n`; false when the module has no such vtable. */
static bool qbe_vtable_word(QCx *c, uint32_t vtable, uint32_t *n) {
    if (c->data == NULL || vtable >= c->m->nvtables) {
        c->why = "vtable without static data";
        return false;
    }
    *n = c->next++;
    ms_buf_printf(c->out, "\t%%t%u =l copy ", *n);
    qbe_ref(c, c->out, (MirRef){MT_DATA, c->data->vtables[vtable], NULL});
    ms_buf_putc(c->out, '\n');
    return true;
}

/* `iface.new` boxes the operand on the heap (owned); `iface.borrow` keeps it in the frame when
 * nothing outlives it (view) and on the heap otherwise (boxed, freed with the value). */
static bool qbe_iface_new(QCx *c, const MirInst *inst, uint32_t block, uint32_t index) {
    const MirTy ty = c->f->values[inst->args[0]];
    const bool framed = inst->op == MOP_IfaceBorrow && c->borrowed != NULL && c->borrowed[inst->res];
    uint32_t vt;
    char obj[24];
    if (!qbe_vtable_word(c, inst->imm.a, &vt)) {
        return false;
    }
    uint32_t tag = inst->op == MOP_IfaceNew ? QBE_TAG_OWNED : QBE_TAG_BOX;
    if (framed) {
        tag = QBE_TAG_VIEW;
        (void)snprintf(obj, sizeof obj, "%%i%u_%u", block, index);
        ms_buf_printf(c->out, "\t%%v%u =l copy %s\n", inst->res, obj);
    } else {
        const uint32_t size = mir_type_mem(c->layouts, ty).size;
        ms_buf_printf(c->out, "\t%%v%u =l call $msrt_alloc(l %u)\n", inst->res, size > 0 ? size : 1);
        (void)snprintf(obj, sizeof obj, "%%v%u", inst->res);
    }
    if (qbe_leaves(c, ty).len > 0 && !qbe_store_leaves(c, inst->args[0], obj)) {
        return false;
    }
    ms_buf_printf(c->out, "\t%%v%u.1 =l add %%t%u, %u\n", inst->res, vt, tag);
    return true;
}

/* `call.method`: the code word of the method's slot, called with the data address first. */
static bool qbe_call_method(QCx *c, const MirInst *inst, uint32_t block, uint32_t index) {
    const uint32_t table = qbe_untag(c, inst->args[0]);
    const uint32_t slot = c->next++;
    ms_buf_printf(c->out, "\t%%t%u =l add %%t%u, %u\n", slot, table, 8 * (1 + inst->imm.b));
    const uint32_t code = c->next++;
    ms_buf_printf(c->out, "\t%%k%u =l loadl %%t%u\n", code, slot);
    char callee[24], lead[24];
    (void)snprintf(callee, sizeof callee, "%%k%u", code);
    (void)snprintf(lead, sizeof lead, "l %%v%u", inst->args[0]);
    return qbe_call_to(c, inst, block, index, callee, lead);
}

/* `iface.destroy`: calls the payload drop in slot 0 with the data address. */
static void qbe_iface_destroy(QCx *c, const MirInst *inst) {
    const uint32_t table = qbe_untag(c, inst->args[0]);
    const uint32_t code = c->next++;
    ms_buf_printf(c->out, "\t%%k%u =l loadl %%t%u\n\tcall %%k%u(l %%v%u)\n", code, table, code, inst->args[0]);
}

/* `iface.is`: whether the value's vtable is the one of the implementation. */
static bool qbe_iface_is(QCx *c, const MirInst *inst) {
    uint32_t want;
    const uint32_t table = qbe_untag(c, inst->args[0]);
    if (!qbe_vtable_word(c, inst->imm.a, &want)) {
        return false;
    }
    ms_buf_printf(c->out, "\t%%v%u =w ceql %%t%u, %%t%u\n", inst->res, table, want);
    return true;
}

/* The interface operations; `*handled` says whether `inst` is one. */
static bool qbe_iface_op(QCx *c, const MirInst *inst, uint32_t block, uint32_t index, bool *handled) {
    *handled = true;
    switch ((MirOp)inst->op) {
    case MOP_IfaceNew: case MOP_IfaceBorrow: return qbe_iface_new(c, inst, block, index);
    case MOP_CallMethod: return qbe_call_method(c, inst, block, index);
    case MOP_IfaceData:
        ms_buf_printf(c->out, "\t%%v%u =l copy %%v%u\n", inst->res, inst->args[0]);
        return true;
    case MOP_IfaceTag:
        ms_buf_printf(c->out, "\t%%v%u =l and %%v%u.1, %d\n", inst->res, inst->args[0], QBE_TAG_MASK);
        return true;
    case MOP_IfaceView: {
        const uint32_t table = qbe_untag(c, inst->args[0]);
        ms_buf_printf(c->out, "\t%%v%u =l copy %%v%u\n\t%%v%u.1 =l or %%t%u, %d\n", inst->res, inst->args[0],
                      inst->res, table, QBE_TAG_VIEW);
        return true;
    }
    case MOP_IfaceIs: return qbe_iface_is(c, inst);
    case MOP_IfaceDestroy:
        qbe_iface_destroy(c, inst);
        return true;
    default:
        *handled = false;
        return true;
    }
}
