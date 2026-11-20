/* Interfaces for emit_llvm.c (included from it). A value is two words: the data address and the
 * address of its vtable with a tag in the low two bits (owned, boxed, view). Slot 0 of a vtable is
 * the payload drop, slot 1 + k the code of method k. */

enum { LL_TAG_OWNED = 0, LL_TAG_BOX = 1, LL_TAG_VIEW = 2, LL_TAG_MASK = 3 };

/* Writes `%tN = and i64 <word>, -4` (the vtable address) and returns the name in `out`. */
static void ll_untag(LCx *c, MirValue iface, char *out, size_t cap) {
    const uint32_t n = c->next++;
    ms_buf_printf(c->out, "  %%t%u = and i64 %%v%u.1, %d\n", n, iface, -(LL_TAG_MASK + 1));
    (void)snprintf(out, cap, "%%t%u", n);
}

/* Writes `%tN = ptrtoint ptr @vtable to i64` and returns the name in `out`. */
static bool ll_vtable_word(LCx *c, uint32_t vtable, char *out, size_t cap) {
    if (c->data == NULL || vtable >= c->m->nvtables) {
        c->why = "vtable without static data";
        return false;
    }
    const uint32_t n = c->next++;
    ms_buf_printf(c->out, "  %%t%u = ptrtoint ptr ", n);
    ll_data_name(c->out, c->data->syms[c->data->vtables[vtable]].name);
    ms_buf_puts(c->out, " to i64\n");
    (void)snprintf(out, cap, "%%t%u", n);
    return true;
}

/* `iface.new` boxes the operand on the heap (owned); `iface.borrow` keeps it in the frame when
 * nothing outlives it (view) and on the heap otherwise (boxed, freed with the value). */
static bool ll_iface_new(LCx *c, const MirInst *inst, uint32_t block, uint32_t index) {
    const MirTy ty = c->f->values[inst->args[0]];
    const bool framed = inst->op == MOP_IfaceBorrow && c->borrowed != NULL && c->borrowed[inst->res];
    uint32_t tag = LL_TAG_OWNED;
    char vt[24], obj[24];
    if (!ll_vtable_word(c, inst->imm.a, vt, sizeof vt)) {
        return false;
    }
    if (framed) {
        tag = LL_TAG_VIEW;
        (void)snprintf(obj, sizeof obj, "%%i%u_%u", block, index);
        ms_buf_printf(c->out, "  %%v%u = ptrtoint ptr %s to i64\n", inst->res, obj);
    } else {
        tag = inst->op == MOP_IfaceNew ? LL_TAG_OWNED : LL_TAG_BOX;
        const uint32_t size = mir_type_mem(c->layouts, ty).size;
        ms_buf_printf(c->out, "  %%v%u = call i64 @\"msrt_alloc\"(i64 %u)\n", inst->res, size > 0 ? size : 1);
        ll_pointer(c, inst->res, obj, sizeof obj);
    }
    if (ll_leaves(c, ty).len > 0 && !ll_leaves_at(c, inst->args[0], obj, false)) {
        return false;
    }
    ms_buf_printf(c->out, "  %%v%u.1 = add i64 %s, %u\n", inst->res, vt, tag);
    return true;
}

/* `call.method`: the code word of the method's slot, called with the data address first. */
static bool ll_call_method(LCx *c, const MirInst *inst, uint32_t block, uint32_t index) {
    char table[24], slot[24], lead[24];
    ll_untag(c, inst->args[0], table, sizeof table);
    const uint32_t n = c->next++;
    ms_buf_printf(c->out, "  %%p%u = inttoptr i64 %s to ptr\n", n, table);
    (void)snprintf(table, sizeof table, "%%p%u", n);
    ll_offset_ptr(c, table, 8 * (1 + inst->imm.b), slot, sizeof slot);
    const uint32_t k = c->next++;
    ms_buf_printf(c->out, "  %%k%u = load ptr, ptr %s\n", k, slot);
    char callee[24];
    (void)snprintf(callee, sizeof callee, "%%k%u", k);
    (void)snprintf(lead, sizeof lead, "i64 %%v%u", inst->args[0]);
    return ll_call_to(c, inst, block, index, callee, lead);
}

/* `iface.destroy`: calls the payload drop in slot 0 with the data address. */
static void ll_iface_destroy(LCx *c, const MirInst *inst) {
    char table[24];
    ll_untag(c, inst->args[0], table, sizeof table);
    const uint32_t n = c->next++;
    ms_buf_printf(c->out, "  %%p%u = inttoptr i64 %s to ptr\n  %%k%u = load ptr, ptr %%p%u\n", n, table, n, n);
    ms_buf_printf(c->out, "  call void %%k%u(i64 %%v%u)\n", n, inst->args[0]);
}

/* `clone` of an interface value: the payload copier sits in the vtable after the methods. The copy
 * owns its payload whatever the source did, so the tag bits come off. */
static bool ll_iface_clone(LCx *c, const MirInst *inst) {
    const MirTyData *d = mir_ty_data(c->m, c->f->values[inst->args[0]]);
    if (d->kind != MK_IFACE) {
        return false;
    }
    char table[24];
    ll_untag(c, inst->args[0], table, sizeof table);
    const uint32_t n = c->next++;
    ms_buf_printf(c->out, "  %%t%ua = add i64 %s, %u\n  %%p%u = inttoptr i64 %%t%ua to ptr\n  %%k%u = load ptr, ptr %%p%u\n",
                  n, table, 8 * (1 + c->m->ifaces[d->id].nmethods), n, n, n, n);
    ms_buf_printf(c->out, "  %%v%u = call i64 %%k%u(i64 %%v%u)\n  %%v%u.1 = add i64 %s, 0\n", inst->res, n,
                  inst->args[0], inst->res, table);
    return true;
}

/* The interface operations; `*handled` says whether `inst` is one. */
static bool ll_iface_op(LCx *c, const MirInst *inst, uint32_t block, uint32_t index, bool *handled) {
    *handled = true;
    char table[24];
    switch ((MirOp)inst->op) {
    case MOP_IfaceNew: case MOP_IfaceBorrow: return ll_iface_new(c, inst, block, index);
    case MOP_CallMethod: return ll_call_method(c, inst, block, index);
    case MOP_IfaceData:
        ms_buf_printf(c->out, "  %%v%u = add i64 %%v%u, 0\n", inst->res, inst->args[0]);
        return true;
    case MOP_IfaceTag:
        ms_buf_printf(c->out, "  %%v%u = and i64 %%v%u.1, %d\n", inst->res, inst->args[0], LL_TAG_MASK);
        return true;
    case MOP_IfaceView:
        ll_untag(c, inst->args[0], table, sizeof table);
        ms_buf_printf(c->out, "  %%v%u = add i64 %%v%u, 0\n  %%v%u.1 = or i64 %s, %d\n", inst->res,
                      inst->args[0], inst->res, table, LL_TAG_VIEW);
        return true;
    case MOP_Clone:
        if (ll_iface_clone(c, inst)) {
            return true;
        }
        *handled = false;
        return true;
    case MOP_IfaceIs: {
        char want[24];
        ll_untag(c, inst->args[0], table, sizeof table);
        if (!ll_vtable_word(c, inst->imm.a, want, sizeof want)) {
            return false;
        }
        ms_buf_printf(c->out, "  %%v%u = icmp eq i64 %s, %s\n", inst->res, table, want);
        return true;
    }
    case MOP_IfaceDestroy:
        ll_iface_destroy(c, inst);
        return true;
    default:
        *handled = false;
        return true;
    }
}
