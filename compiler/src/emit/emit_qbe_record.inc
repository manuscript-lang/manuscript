/* Records that live behind a pointer (`type Name indirect`), for emit_qbe.c (included from it). The
 * value is one pointer to a heap block holding the leaves of every field in order, laid out as in
 * memory (mir_type_block). A collection field, held as a pointer to a header block, is not covered. */

/* Opens the block of record type `ty`; false, with `c->why` set, when this file cannot write it. */
static bool qbe_block_open(QCx *c, MirTy ty, MirRecordBlock *b) {
    bool boxed_field = false;
    if (mir_record_block(c->layouts, ty, b, &boxed_field)) {
        return true;
    }
    c->why = boxed_field ? "collection field of a record behind a pointer" : "out of memory";
    return false;
}

static bool qbe_is_indirect_record(const QCx *c, MirTy ty) {
    const MirTyData *data = mir_ty_data(c->m, ty);
    return data->kind == MK_TYPE && c->m->type_defs[data->id].indirect;
}

/* Stores the leaves of `value` as field `field` of the block at `base`. */
static void qbe_block_store_field(QCx *c, const MirRecordBlock *b, const char *base, uint32_t field, MirValue value) {
    const MirLeafSpan leaves = qbe_leaves(c, c->f->values[value]);
    for (uint32_t j = 0; j < leaves.len; j++) {
        const uint32_t slot = b->starts[field] + j;
        qbe_store_leaf(c, b->leaves.ptr[slot], value, j, qbe_address(c, base, b->offsets[slot]));
    }
}

/* `type.new`: a heap block holding the fields. */
static bool qbe_indirect_new(QCx *c, const MirInst *inst) {
    MirRecordBlock b;
    if (!qbe_block_open(c, c->f->values[inst->res], &b)) {
        return false;
    }
    ms_buf_printf(c->out, "\t%%v%u =l call $msrt_alloc(l %u)\n", inst->res, b.size > 0 ? b.size : 1);
    char base[24];
    (void)snprintf(base, sizeof base, "%%v%u", inst->res);
    for (uint32_t k = 0; k < inst->nargs; k++) {
        qbe_block_store_field(c, &b, base, k, inst->args[k]);
    }
    mir_record_block_free(&b);
    return true;
}

/* `type.get`: the leaves of one field, loaded from the block. */
static bool qbe_indirect_get(QCx *c, const MirInst *inst) {
    MirRecordBlock b;
    if (!qbe_block_open(c, c->f->values[inst->args[0]], &b)) {
        return false;
    }
    char base[24];
    (void)snprintf(base, sizeof base, "%%v%u", inst->args[0]);
    const uint32_t field = inst->imm.b;
    const uint32_t count = qbe_leaves(c, b.def->fields[field].ty).len;
    for (uint32_t j = 0; j < count; j++) {
        const uint32_t slot = b.starts[field] + j;
        qbe_load_leaf(c, b.leaves.ptr[slot], inst->res, j, qbe_address(c, base, b.offsets[slot]));
    }
    mir_record_block_free(&b);
    return true;
}

/* `type.set`, `type.fill`: the new field value replaces the old in place (`type.set` frees an old
 * string first, the runtime reads its tag; `type.fill` writes a block not yet initialised), and
 * the result is the same pointer. */
static bool qbe_indirect_set(QCx *c, const MirInst *inst) {
    MirRecordBlock b;
    if (!qbe_block_open(c, c->f->values[inst->args[0]], &b)) {
        return false;
    }
    char base[24];
    (void)snprintf(base, sizeof base, "%%v%u", inst->args[0]);
    const uint32_t field = inst->imm.b;
    if (inst->op == MOP_TypeSet && mir_ty_data(c->m, b.def->fields[field].ty)->kind == MK_STR) {
        ms_buf_printf(c->out, "\tcall $msrt_string_free(l %%a%u)\n",
                      qbe_address(c, base, b.offsets[b.starts[field]]));
    }
    qbe_block_store_field(c, &b, base, field, inst->args[1]);
    ms_buf_printf(c->out, "\t%%v%u =l copy %%v%u\n", inst->res, inst->args[0]);
    mir_record_block_free(&b);
    return true;
}
