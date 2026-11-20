/* Alternatives and optionals for emit_qbe.c (included from it). An alternative that does not
 * contain itself is leaves in registers: the case index, then payload slots shared between cases by
 * leaf kind. One that does is a pointer to a heap block with the same slots in memory; a case with
 * no payload is a shared static block (MirData.units). */

/* A zero of the register type of `leaf`. */
static void qbe_zero_leaf(QCx *c, MirValue dst, uint32_t index, MirLeaf leaf) {
    MsBuf *o = c->out;
    ms_buf_puts(o, "\t");
    qbe_name(o, dst, index);
    ms_buf_printf(o, " =%c copy %s\n", qbe_leaf_type(leaf), qbe_leaf_type(leaf) == 'd' ? "d_0" : "0");
}

/* `alt.new`, `alt.view` of an alternative held as leaves: the case index, the payload leaves in
 * their slots, zeros elsewhere. */
static void qbe_alt_inline(QCx *c, const MirInst *inst, const MirAltFields *fields) {
    const uint32_t case_index = inst->imm.b;
    const MirLeafSpan leaves = qbe_leaves(c, c->f->values[inst->res]);
    ms_buf_printf(c->out, "\t%%v%u =l copy %u\n", inst->res, case_index);
    for (uint32_t j = 1; j < leaves.len; j++) {
        uint32_t operand = 0, leaf = 0;
        if (mir_alt_slot_source(fields, case_index, j, &operand, &leaf)) {
            qbe_copy_leaf(c, inst->res, j, inst->args[operand], leaf);
        } else {
            qbe_zero_leaf(c, inst->res, j, leaves.ptr[j]);
        }
    }
}

/* Byte offsets of the slots of the block of a boxed alternative; NULL, with `c->why` set, when out of memory. */
static uint32_t *qbe_block_offsets(QCx *c, const MirShape *shape) {
    uint32_t *offsets = calloc((size_t)shape->block.len + 1, sizeof *offsets);
    if (offsets == NULL) {
        c->why = "out of memory";
        return NULL;
    }
    (void)mir_mem_layout(shape->block.ptr, shape->block.len, offsets);
    return offsets;
}

/* `alt.new`, `alt.view` of a boxed alternative: the shared unit block of a case without payload,
 * else a fresh block holding the case index and the payload. */
static bool qbe_alt_block(QCx *c, const MirInst *inst, const MirAltFields *fields, const MirShape *shape) {
    const uint32_t case_index = inst->imm.b;
    const bool unit = fields->case_start[case_index + 1] == fields->case_start[case_index];
    if (unit) {
        const uint32_t sym = c->data == NULL ? MIR_NONE : mir_data_unit(c->data, inst->imm.a, case_index);
        if (sym == MIR_NONE) {
            c->why = "alt.new without a unit block";
            return false;
        }
        ms_buf_printf(c->out, "\t%%v%u =l copy ", inst->res);
        qbe_ref(c, c->out, (MirRef){MT_DATA, sym, NULL});
        ms_buf_putc(c->out, '\n');
        return true;
    }
    uint32_t *offsets = qbe_block_offsets(c, shape);
    if (offsets == NULL) {
        return false;
    }
    const uint32_t size = mir_mem_layout(shape->block.ptr, shape->block.len, NULL).size;
    ms_buf_printf(c->out, "\t%%v%u =l call $msrt_alloc(l %u)\n", inst->res, size);
    char base[24];
    (void)snprintf(base, sizeof base, "%%v%u", inst->res);
    ms_buf_printf(c->out, "\tstorel %u, %%a%u\n", case_index, qbe_address(c, base, offsets[0]));
    for (uint32_t f = fields->case_start[case_index]; f < fields->case_start[case_index + 1]; f++) {
        for (uint32_t k = 0; k < fields->fields[f].nleaves; k++) {
            const uint32_t slot = fields->fields[f].leaves[k];
            qbe_store_leaf(c, shape->block.ptr[slot], inst->args[f - fields->case_start[case_index]], k,
                           qbe_address(c, base, offsets[slot]));
        }
    }
    free(offsets);
    return true;
}

/* `alt.new`, `alt.view`. */
static bool qbe_alt_new(QCx *c, const MirInst *inst) {
    const MirShape *shape = mir_shape(c->layouts, c->f->values[inst->res]);
    const MirAltFields *fields = mir_alt_fields(c->layouts, inst->imm.a);
    if (shape->alt == MIR_ALT_BOXED) {
        return qbe_alt_block(c, inst, fields, shape);
    }
    qbe_alt_inline(c, inst, fields);
    return true;
}

/* `alt.get`, `alt.take`: the leaves of one payload field, from the registers or from the block. */
static bool qbe_alt_get(QCx *c, const MirInst *inst) {
    const MirTy ty = c->f->values[inst->args[0]];
    const MirShape *shape = mir_shape(c->layouts, ty);
    const MirAltFields *fields = mir_alt_fields(c->layouts, inst->imm.a);
    const MirAltField *field = &fields->fields[fields->case_start[inst->imm.b] + inst->imm.c];
    if (shape->alt != MIR_ALT_BOXED) {
        for (uint32_t k = 0; k < field->nleaves; k++) {
            qbe_copy_leaf(c, inst->res, k, inst->args[0], field->leaves[k]);
        }
        return true;
    }
    uint32_t *offsets = qbe_block_offsets(c, shape);
    if (offsets == NULL) {
        return false;
    }
    char base[24];
    (void)snprintf(base, sizeof base, "%%v%u", inst->args[0]);
    for (uint32_t k = 0; k < field->nleaves; k++) {
        const uint32_t slot = field->leaves[k];
        qbe_load_leaf(c, shape->block.ptr[slot], inst->res, k, qbe_address(c, base, offsets[slot]));
    }
    free(offsets);
    return true;
}

/* `opt.none`: absent is all zero, except that a string's second word keeps the static tag. */
static void qbe_opt_none(QCx *c, const MirInst *inst) {
    const MirLeafSpan leaves = qbe_leaves(c, c->f->values[inst->res]);
    if (mir_is_str_like(c->layouts, c->f->values[inst->res])) {
        ms_buf_printf(c->out, "\t%%v%u =l copy 0\n\t%%v%u.1 =l copy %lld\n", inst->res, inst->res,
                      (long long)MIR_STR_STATIC);
        return;
    }
    for (uint32_t j = 0; j < leaves.len; j++) {
        qbe_zero_leaf(c, inst->res, j, leaves.ptr[j]);
    }
}

/* `alt.plain`: the same leaves under the plain alternative type. */
static void qbe_alt_plain(QCx *c, const MirInst *inst) {
    const uint32_t count = qbe_leaves(c, c->f->values[inst->res]).len;
    for (uint32_t j = 0; j < count; j++) {
        qbe_copy_leaf(c, inst->res, j, inst->args[0], j);
    }
}

/* The alternative and optional operations here; `*handled` says whether `inst` is one. */
static bool qbe_enum_op(QCx *c, const MirInst *inst, bool *handled) {
    *handled = true;
    switch ((MirOp)inst->op) {
    case MOP_AltNew: case MOP_AltView: return qbe_alt_new(c, inst);
    case MOP_AltGet: case MOP_AltTake: return qbe_alt_get(c, inst);
    case MOP_AltPlain: qbe_alt_plain(c, inst); return true;
    case MOP_OptNone: qbe_opt_none(c, inst); return true;
    default:
        *handled = false;
        return true;
    }
}
