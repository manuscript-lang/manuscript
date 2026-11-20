/* Records that live behind a pointer (`type Name indirect`), for emit_qbe.c (included from it). The
 * value is one pointer to a heap block holding the leaves of every field in order, laid out as in
 * memory (mir_record_block). A map or set field is one word: the address of a header block of
 * MIR_MAP_WORDS words, null while the collection is the all-zero empty value. Reading, building or
 * freeing such a field branches, which ends the current piece of the block (qbe_splits). */

/* A conditional piece: `jnz cond, @i<n>, <join>`, the code of the condition's side, then the join. */
typedef struct QbeIf {
    uint32_t n;
    uint32_t head, join; /* the pieces before and after, for the phis that name them */
} QbeIf;

static QbeIf qbe_if_begin(QCx *c, const char *cond, uint32_t block, uint32_t *part) {
    QbeIf s = {.n = c->next++, .head = *part, .join = ++*part};
    ms_buf_printf(c->out, "\tjnz %s, @i%u, ", cond, s.n);
    qbe_label(c, block, s.join);
    ms_buf_printf(c->out, "\n@i%u\n", s.n);
    return s;
}

static void qbe_if_end(QCx *c, const QbeIf *s, uint32_t block) {
    ms_buf_puts(c->out, "\tjmp ");
    qbe_label(c, block, s->join);
    ms_buf_putc(c->out, '\n');
    qbe_label(c, block, s->join);
    ms_buf_putc(c->out, '\n');
}

/* `phi @head <zero>, @i<n> <value>` for a word that is zero when the condition side was skipped. */
static void qbe_if_phi(QCx *c, const QbeIf *s, uint32_t block, const char *dst, const char *value) {
    ms_buf_printf(c->out, "\t%s =l phi ", dst);
    qbe_label(c, block, s->head);
    ms_buf_printf(c->out, " 0, @i%u %s\n", s->n, value);
}

/* Opens the block of record type `ty`; false, with `c->why` set, when out of memory. */
static bool qbe_block_open(QCx *c, MirTy ty, MirRecordBlock *b) {
    if (mir_record_block(c->layouts, mir_ty_data(c->m, ty)->id, b)) {
        return true;
    }
    c->why = "out of memory";
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

/* The header block of a map or set value: null when its first and last words are zero (the empty
 * collection), else a fresh block holding the words. Leaves the address in `%h<n>`. */
static uint32_t qbe_header_store(QCx *c, MirValue value, uint32_t block, uint32_t *part) {
    const uint32_t words = MIR_MAP_WORDS;
    char cond[24];
    const uint32_t n = c->next++;
    ms_buf_printf(c->out, "\t%%u%u =l or %%v%u, %%v%u.%u\n\t%%u%ub =w cnel %%u%u, 0\n", n, value, value, words - 1, n, n);
    (void)snprintf(cond, sizeof cond, "%%u%ub", n);
    const QbeIf s = qbe_if_begin(c, cond, block, part);
    ms_buf_printf(c->out, "\t%%p%u =l call $msrt_alloc(l %u)\n", s.n, words * 8);
    char base[24];
    (void)snprintf(base, sizeof base, "%%p%u", s.n);
    for (uint32_t k = 0; k < words; k++) {
        const uint32_t at = qbe_address(c, base, k * 8);
        ms_buf_puts(c->out, "\tstorel ");
        qbe_name(c->out, value, k);
        ms_buf_printf(c->out, ", %%a%u\n", at);
    }
    qbe_if_end(c, &s, block);
    char header[24], made[24];
    (void)snprintf(header, sizeof header, "%%h%u", s.n);
    (void)snprintf(made, sizeof made, "%%p%u", s.n);
    qbe_if_phi(c, &s, block, header, made);
    return s.n;
}

/* `type.new`: a heap block holding the fields. */
static bool qbe_indirect_new(QCx *c, const MirInst *inst, uint32_t block, uint32_t *part) {
    MirRecordBlock b;
    if (!qbe_block_open(c, c->f->values[inst->res], &b)) {
        return false;
    }
    ms_buf_printf(c->out, "\t%%v%u =l call $msrt_alloc(l %u)\n", inst->res, b.size > 0 ? b.size : 1);
    char base[24];
    (void)snprintf(base, sizeof base, "%%v%u", inst->res);
    for (uint32_t k = 0; k < inst->nargs; k++) {
        if (!b.boxed[k]) {
            qbe_block_store_field(c, &b, base, k, inst->args[k]);
            continue;
        }
        const uint32_t h = qbe_header_store(c, inst->args[k], block, part);
        const uint32_t at = qbe_address(c, base, b.offsets[b.starts[k]]);
        ms_buf_printf(c->out, "\tstorel %%h%u, %%a%u\n", h, at);
    }
    mir_record_block_free(&b);
    return true;
}

/* `type.get`: the leaves of one field, loaded from the block; a collection is read through its
 * header, or is all zero when that is null. */
static bool qbe_indirect_get(QCx *c, const MirInst *inst, uint32_t block, uint32_t *part) {
    MirRecordBlock b;
    if (!qbe_block_open(c, c->f->values[inst->args[0]], &b)) {
        return false;
    }
    char base[24];
    (void)snprintf(base, sizeof base, "%%v%u", inst->args[0]);
    const uint32_t field = inst->imm.b;
    if (!b.boxed[field]) {
        const uint32_t count = qbe_leaves(c, b.def->fields[field].ty).len;
        for (uint32_t j = 0; j < count; j++) {
            const uint32_t slot = b.starts[field] + j;
            qbe_load_leaf(c, b.leaves.ptr[slot], inst->res, j, qbe_address(c, base, b.offsets[slot]));
        }
        mir_record_block_free(&b);
        return true;
    }
    const uint32_t n = c->next++;
    const uint32_t slot = qbe_address(c, base, b.offsets[b.starts[field]]);
    ms_buf_printf(c->out, "\t%%g%u =l loadl %%a%u\n\t%%g%ub =w cnel %%g%u, 0\n", n, slot, n, n);
    char cond[24];
    (void)snprintf(cond, sizeof cond, "%%g%ub", n);
    const QbeIf s = qbe_if_begin(c, cond, block, part);
    char header[24];
    (void)snprintf(header, sizeof header, "%%g%u", n);
    for (uint32_t k = 0; k < MIR_MAP_WORDS; k++) {
        const uint32_t at = qbe_address(c, header, k * 8);
        ms_buf_printf(c->out, "\t%%w%u_%u =l loadl %%a%u\n", s.n, k, at);
    }
    qbe_if_end(c, &s, block);
    for (uint32_t k = 0; k < MIR_MAP_WORDS; k++) {
        char dst[24], word[24];
        (void)snprintf(dst, sizeof dst, k == 0 ? "%%v%u" : "%%v%u.%u", inst->res, k);
        (void)snprintf(word, sizeof word, "%%w%u_%u", s.n, k);
        qbe_if_phi(c, &s, block, dst, word);
    }
    mir_record_block_free(&b);
    return true;
}

/* `type.set`, `type.fill`: the new field value replaces the old in place, and the result is the same
 * pointer. A collection field frees its old header first. The old value's own drop is a separate
 * `drop` that mir_lower_ops puts before a `type.set`, which it turns into `type.fill`. */
static bool qbe_indirect_set(QCx *c, const MirInst *inst, uint32_t block, uint32_t *part) {
    MirRecordBlock b;
    if (!qbe_block_open(c, c->f->values[inst->args[0]], &b)) {
        return false;
    }
    char base[24];
    (void)snprintf(base, sizeof base, "%%v%u", inst->args[0]);
    const uint32_t field = inst->imm.b;
    if (b.boxed[field]) {
        const uint32_t slot = qbe_address(c, base, b.offsets[b.starts[field]]);
        const uint32_t n = c->next++;
        ms_buf_printf(c->out, "\t%%g%u =l loadl %%a%u\n\t%%g%ub =w cnel %%g%u, 0\n", n, slot, n, n);
        char cond[24];
        (void)snprintf(cond, sizeof cond, "%%g%ub", n);
        const QbeIf s = qbe_if_begin(c, cond, block, part);
        ms_buf_printf(c->out, "\tcall $msrt_free(l %%g%u)\n", n);
        qbe_if_end(c, &s, block);
        const uint32_t h = qbe_header_store(c, inst->args[1], block, part);
        ms_buf_printf(c->out, "\tstorel %%h%u, %%a%u\n", h, slot);
    } else {
        qbe_block_store_field(c, &b, base, field, inst->args[1]);
    }
    ms_buf_printf(c->out, "\t%%v%u =l copy %%v%u\n", inst->res, inst->args[0]);
    mir_record_block_free(&b);
    return true;
}

/* `free` of a collection field: the header block behind the field of the record block, if any. */
static bool qbe_free_field(QCx *c, const MirInst *inst, uint32_t block, uint32_t *part) {
    MirRecordBlock b;
    if (!mir_record_block(c->layouts, inst->imm.a, &b)) {
        c->why = "out of memory";
        return false;
    }
    char base[24];
    (void)snprintf(base, sizeof base, "%%v%u", inst->args[0]);
    const uint32_t n = c->next++;
    const uint32_t slot = qbe_address(c, base, b.offsets[b.starts[inst->imm.b]]);
    ms_buf_printf(c->out, "\t%%g%u =l loadl %%a%u\n\t%%g%ub =w cnel %%g%u, 0\n", n, slot, n, n);
    char cond[24];
    (void)snprintf(cond, sizeof cond, "%%g%ub", n);
    const QbeIf s = qbe_if_begin(c, cond, block, part);
    ms_buf_printf(c->out, "\tcall $msrt_free(l %%g%u)\n", n);
    qbe_if_end(c, &s, block);
    mir_record_block_free(&b);
    return true;
}

/* How many pieces `inst` ends: one per branch of the operations above. */
static uint32_t qbe_record_splits(const MirModule *m, const MirFunc *f, const MirInst *inst) {
    const MirTy subject = inst->op == MOP_TypeNew ? f->values[inst->res]
                          : inst->nargs > 0        ? f->values[inst->args[0]]
                                                   : MIR_NONE;
    if (inst->op == MOP_Free && inst->imm.tag != MI_NONE) {
        return 1;
    }
    if (subject == MIR_NONE || mir_ty_data(m, subject)->kind != MK_TYPE ||
        !m->type_defs[mir_ty_data(m, subject)->id].indirect) {
        return 0;
    }
    const MirTypeDef *def = &m->type_defs[mir_ty_data(m, subject)->id];
    uint32_t boxed = 0;
    switch ((MirOp)inst->op) {
    case MOP_TypeNew:
        for (uint32_t k = 0; k < def->nfields; k++) {
            boxed += mir_ty_is_map_or_set(m, def->fields[k].ty);
        }
        return boxed;
    case MOP_TypeGet:
        return mir_ty_is_map_or_set(m, def->fields[inst->imm.b].ty);
    case MOP_TypeSet: case MOP_TypeFill:
        return mir_ty_is_map_or_set(m, def->fields[inst->imm.b].ty) ? 2 : 0;
    default:
        return 0;
    }
}

/* The operations on records behind a pointer; `*handled` says whether `inst` is one. */
static bool qbe_indirect_op(QCx *c, const MirInst *inst, uint32_t block, uint32_t *part, bool *handled) {
    *handled = true;
    switch ((MirOp)inst->op) {
    case MOP_TypeNew:
        if (qbe_is_indirect_record(c, c->f->values[inst->res])) {
            return qbe_indirect_new(c, inst, block, part);
        }
        break;
    case MOP_TypeGet:
        if (qbe_is_indirect_record(c, c->f->values[inst->args[0]])) {
            return qbe_indirect_get(c, inst, block, part);
        }
        break;
    case MOP_TypeSet: case MOP_TypeFill:
        if (qbe_is_indirect_record(c, c->f->values[inst->args[0]])) {
            return qbe_indirect_set(c, inst, block, part);
        }
        break;
    case MOP_Free:
        if (inst->imm.tag != MI_NONE) {
            return qbe_free_field(c, inst, block, part);
        }
        break;
    default:
        break;
    }
    *handled = false;
    return true;
}
