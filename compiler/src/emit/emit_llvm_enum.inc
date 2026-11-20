/* Alternatives and optionals for emit_llvm.c (included from it); the layout is the one the
 * runtime uses. */

/* A zero of the register type of `leaf`. */
static void ll_zero_leaf(LCx *c, MirValue dst, uint32_t index, MirLeaf leaf) {
    MsBuf *o = c->out;
    const char *ty = ll_leaf_type(leaf);
    ms_buf_puts(o, "  ");
    ll_name(o, dst, index);
    if (strcmp(ty, "double") == 0) {
        ms_buf_puts(o, " = fadd double 0.0, 0.0\n");
    } else if (strcmp(ty, "i1") == 0) {
        ms_buf_puts(o, " = or i1 false, false\n");
    } else {
        ms_buf_puts(o, " = add i64 0, 0\n");
    }
}

/* `alt.new`, `alt.view` of an alternative held as leaves: the case index, the payload leaves in
 * their slots, zeros elsewhere. */
static void ll_alt_inline(LCx *c, const MirInst *inst, const MirAltFields *fields) {
    const uint32_t case_index = inst->imm.b;
    const MirLeafSpan leaves = ll_leaves(c, c->f->values[inst->res]);
    ms_buf_printf(c->out, "  %%v%u = add i64 %u, 0\n", inst->res, case_index);
    for (uint32_t j = 1; j < leaves.len; j++) {
        uint32_t operand = 0, leaf = 0;
        if (mir_alt_slot_source(fields, case_index, j, &operand, &leaf)) {
            ll_copy_leaf(c, inst->res, j, inst->args[operand], leaf);
        } else {
            ll_zero_leaf(c, inst->res, j, leaves.ptr[j]);
        }
    }
}

/* Byte offsets of the slots of the block of a boxed alternative; NULL, with `c->why` set, when out of memory. */
static uint32_t *ll_block_offsets(LCx *c, const MirShape *shape) {
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
static bool ll_alt_block(LCx *c, const MirInst *inst, const MirAltFields *fields, const MirShape *shape) {
    const uint32_t case_index = inst->imm.b;
    if (fields->case_start[case_index + 1] == fields->case_start[case_index]) {
        const uint32_t sym = c->data == NULL ? MIR_NONE : mir_data_unit(c->data, inst->imm.a, case_index);
        if (sym == MIR_NONE) {
            c->why = "alt.new without a unit block";
            return false;
        }
        ms_buf_printf(c->out, "  %%v%u = ptrtoint ptr ", inst->res);
        ll_ref(c, c->out, (MirRef){MT_DATA, sym, NULL});
        ms_buf_puts(c->out, " to i64\n");
        return true;
    }
    uint32_t *offsets = ll_block_offsets(c, shape);
    if (offsets == NULL) {
        return false;
    }
    const uint32_t size = mir_mem_layout(shape->block.ptr, shape->block.len, NULL).size;
    ms_buf_printf(c->out, "  %%v%u = call i64 @\"msrt_alloc\"(i64 %u)\n", inst->res, size);
    char base[24];
    ll_pointer(c, inst->res, base, sizeof base);
    ms_buf_printf(c->out, "  store i64 %u, ptr %%a%u\n", case_index, ll_address(c, base, offsets[0]));
    const uint32_t first = fields->case_start[case_index];
    for (uint32_t f = first; f < fields->case_start[case_index + 1]; f++) {
        for (uint32_t k = 0; k < fields->fields[f].nleaves; k++) {
            const uint32_t slot = fields->fields[f].leaves[k];
            ll_store_leaf(c, shape->block.ptr[slot], inst->args[f - first], k, ll_address(c, base, offsets[slot]));
        }
    }
    free(offsets);
    return true;
}

/* `alt.new`, `alt.view`. */
static bool ll_alt_new(LCx *c, const MirInst *inst) {
    const MirShape *shape = mir_shape(c->layouts, c->f->values[inst->res]);
    const MirAltFields *fields = mir_alt_fields(c->layouts, inst->imm.a);
    if (shape->alt == MIR_ALT_BOXED) {
        return ll_alt_block(c, inst, fields, shape);
    }
    ll_alt_inline(c, inst, fields);
    return true;
}

/* `alt.get`, `alt.take`: the leaves of one payload field, from the registers or from the block. */
static bool ll_alt_get(LCx *c, const MirInst *inst) {
    const MirShape *shape = mir_shape(c->layouts, c->f->values[inst->args[0]]);
    const MirAltFields *fields = mir_alt_fields(c->layouts, inst->imm.a);
    const MirAltField *field = &fields->fields[fields->case_start[inst->imm.b] + inst->imm.c];
    if (shape->alt != MIR_ALT_BOXED) {
        for (uint32_t k = 0; k < field->nleaves; k++) {
            ll_copy_leaf(c, inst->res, k, inst->args[0], field->leaves[k]);
        }
        return true;
    }
    uint32_t *offsets = ll_block_offsets(c, shape);
    if (offsets == NULL) {
        return false;
    }
    char base[24];
    ll_pointer(c, inst->args[0], base, sizeof base);
    for (uint32_t k = 0; k < field->nleaves; k++) {
        const uint32_t slot = field->leaves[k];
        ll_load_leaf(c, shape->block.ptr[slot], inst->res, k, ll_address(c, base, offsets[slot]));
    }
    free(offsets);
    return true;
}

/* `opt.none`: absent is all zero, except that a string's second word keeps the static tag. */
static void ll_opt_none(LCx *c, const MirInst *inst) {
    const MirLeafSpan leaves = ll_leaves(c, c->f->values[inst->res]);
    if (mir_is_str_like(c->layouts, c->f->values[inst->res])) {
        ms_buf_printf(c->out, "  %%v%u = add i64 0, 0\n  %%v%u.1 = add i64 %lld, 0\n", inst->res, inst->res,
                      (long long)MIR_STR_STATIC);
        return;
    }
    for (uint32_t j = 0; j < leaves.len; j++) {
        ll_zero_leaf(c, inst->res, j, leaves.ptr[j]);
    }
}

/* `alt.plain`: the same leaves under the plain alternative type. */
static void ll_alt_plain(LCx *c, const MirInst *inst) {
    const uint32_t count = ll_leaves(c, c->f->values[inst->res]).len;
    for (uint32_t j = 0; j < count; j++) {
        ll_copy_leaf(c, inst->res, j, inst->args[0], j);
    }
}

/* The alternative and optional operations here; `*handled` says whether `inst` is one. */
static bool ll_enum_op(LCx *c, const MirInst *inst, bool *handled) {
    *handled = true;
    switch ((MirOp)inst->op) {
    case MOP_AltNew: case MOP_AltView: return ll_alt_new(c, inst);
    case MOP_AltGet: case MOP_AltTake: return ll_alt_get(c, inst);
    case MOP_AltPlain: ll_alt_plain(c, inst); return true;
    case MOP_OptNone: ll_opt_none(c, inst); return true;
    default:
        *handled = false;
        return true;
    }
}
