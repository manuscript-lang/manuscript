/* Records that live behind a pointer (`type Name indirect`), for emit_llvm.c (included from it); the
 * layout is the one the runtime uses. Reading, building or freeing a collection
 * field branches, which ends the current piece of the block (ll_pieces). */

/* A conditional piece: `br cond, %i<n>, <join>`, the code of the condition's side, then the join. */
typedef struct LlIf {
    uint32_t n;
    uint32_t head, join; /* the pieces before and after, for the phis that name them */
} LlIf;

static LlIf ll_if_begin(LCx *c, const char *cond, uint32_t block, uint32_t *part) {
    LlIf s = {.n = c->next++, .head = *part, .join = ++*part};
    ms_buf_printf(c->out, "  br i1 %s, label %%i%u, label %%", cond, s.n);
    ll_label(c, block, s.join);
    ms_buf_printf(c->out, "\ni%u:\n", s.n);
    return s;
}

static void ll_if_end(LCx *c, const LlIf *s, uint32_t block) {
    ms_buf_puts(c->out, "  br label %");
    ll_label(c, block, s->join);
    ms_buf_putc(c->out, '\n');
    ll_label(c, block, s->join);
    ms_buf_puts(c->out, ":\n");
}

/* `<dst> = phi i64 [0, %head], [<value>, %i<n>]`: a word that is zero when the condition side was skipped. */
static void ll_if_phi(LCx *c, const LlIf *s, uint32_t block, const char *dst, const char *value) {
    ms_buf_printf(c->out, "  %s = phi i64 [0, %%", dst);
    ll_label(c, block, s->head);
    ms_buf_printf(c->out, "], [%s, %%i%u]\n", value, s->n);
}

/* Opens the block of record type `ty`; false, with `c->why` set, when out of memory. */
static bool ll_block_open(LCx *c, MirTy ty, MirRecordBlock *b) {
    if (mir_record_block(c->layouts, mir_ty_data(c->m, ty)->id, b)) {
        return true;
    }
    c->why = "out of memory";
    return false;
}

static bool ll_is_indirect_record(const LCx *c, MirTy ty) {
    const MirTyData *data = mir_ty_data(c->m, ty);
    return data->kind == MK_TYPE && c->m->type_defs[data->id].indirect;
}

/* Stores the leaves of `value` as field `field` of the block at `base`. */
static void ll_block_store_field(LCx *c, const MirRecordBlock *b, const char *base, uint32_t field, MirValue value) {
    const MirLeafSpan leaves = ll_leaves(c, c->f->values[value]);
    for (uint32_t j = 0; j < leaves.len; j++) {
        const uint32_t slot = b->starts[field] + j;
        ll_store_leaf(c, b->leaves.ptr[slot], value, j, ll_address(c, base, b->offsets[slot]));
    }
}

/* The header block of a map or set value: null when its first and last words are zero (the empty
 * collection), else a fresh block holding the words. Leaves the address in `%h<n>`. */
static uint32_t ll_header_store(LCx *c, MirValue value, uint32_t block, uint32_t *part) {
    const uint32_t n = c->next++;
    char cond[24];
    ms_buf_printf(c->out, "  %%u%u = or i64 %%v%u, %%v%u.%u\n  %%u%ub = icmp ne i64 %%u%u, 0\n", n, value, value,
                  MIR_MAP_WORDS - 1, n, n);
    (void)snprintf(cond, sizeof cond, "%%u%ub", n);
    const LlIf s = ll_if_begin(c, cond, block, part);
    ms_buf_printf(c->out, "  %%q%u = call i64 @\"msrt_alloc\"(i64 %u)\n  %%p%u = inttoptr i64 %%q%u to ptr\n", s.n,
                  MIR_MAP_WORDS * 8, s.n, s.n);
    char base[24];
    (void)snprintf(base, sizeof base, "%%p%u", s.n);
    for (uint32_t k = 0; k < MIR_MAP_WORDS; k++) {
        const uint32_t at = ll_address(c, base, k * 8);
        ms_buf_puts(c->out, "  store i64 ");
        ll_name(c->out, value, k);
        ms_buf_printf(c->out, ", ptr %%a%u\n", at);
    }
    ll_if_end(c, &s, block);
    char header[24], made[24];
    (void)snprintf(header, sizeof header, "%%h%u", s.n);
    (void)snprintf(made, sizeof made, "%%q%u", s.n);
    ll_if_phi(c, &s, block, header, made);
    return s.n;
}

/* `type.new`: a heap block holding the fields. */
static bool ll_indirect_new(LCx *c, const MirInst *inst, uint32_t block, uint32_t *part) {
    MirRecordBlock b;
    if (!ll_block_open(c, c->f->values[inst->res], &b)) {
        return false;
    }
    ms_buf_printf(c->out, "  %%v%u = call i64 @\"msrt_alloc\"(i64 %u)\n", inst->res, b.size > 0 ? b.size : 1);
    char base[24];
    ll_pointer(c, inst->res, base, sizeof base);
    for (uint32_t k = 0; k < inst->nargs; k++) {
        if (!b.boxed[k]) {
            ll_block_store_field(c, &b, base, k, inst->args[k]);
            continue;
        }
        const uint32_t h = ll_header_store(c, inst->args[k], block, part);
        const uint32_t at = ll_address(c, base, b.offsets[b.starts[k]]);
        ms_buf_printf(c->out, "  store i64 %%h%u, ptr %%a%u\n", h, at);
    }
    mir_record_block_free(&b);
    return true;
}

/* `type.get`: the leaves of one field, loaded from the block; a collection is read through its
 * header, or is all zero when that is null. */
static bool ll_indirect_get(LCx *c, const MirInst *inst, uint32_t block, uint32_t *part) {
    MirRecordBlock b;
    if (!ll_block_open(c, c->f->values[inst->args[0]], &b)) {
        return false;
    }
    char base[24];
    ll_pointer(c, inst->args[0], base, sizeof base);
    const uint32_t field = inst->imm.b;
    if (!b.boxed[field]) {
        const uint32_t count = ll_leaves(c, b.def->fields[field].ty).len;
        for (uint32_t j = 0; j < count; j++) {
            const uint32_t slot = b.starts[field] + j;
            ll_load_leaf(c, b.leaves.ptr[slot], inst->res, j, ll_address(c, base, b.offsets[slot]));
        }
        mir_record_block_free(&b);
        return true;
    }
    const uint32_t n = c->next++;
    const uint32_t slot = ll_address(c, base, b.offsets[b.starts[field]]);
    ms_buf_printf(c->out, "  %%g%u = load i64, ptr %%a%u\n  %%g%ub = icmp ne i64 %%g%u, 0\n", n, slot, n, n);
    char cond[24];
    (void)snprintf(cond, sizeof cond, "%%g%ub", n);
    const LlIf s = ll_if_begin(c, cond, block, part);
    ms_buf_printf(c->out, "  %%gp%u = inttoptr i64 %%g%u to ptr\n", n, n);
    char header[24];
    (void)snprintf(header, sizeof header, "%%gp%u", n);
    for (uint32_t k = 0; k < MIR_MAP_WORDS; k++) {
        const uint32_t at = ll_address(c, header, k * 8);
        ms_buf_printf(c->out, "  %%w%u_%u = load i64, ptr %%a%u\n", s.n, k, at);
    }
    ll_if_end(c, &s, block);
    for (uint32_t k = 0; k < MIR_MAP_WORDS; k++) {
        char dst[24], word[24];
        (void)snprintf(dst, sizeof dst, k == 0 ? "%%v%u" : "%%v%u.%u", inst->res, k);
        (void)snprintf(word, sizeof word, "%%w%u_%u", s.n, k);
        ll_if_phi(c, &s, block, dst, word);
    }
    mir_record_block_free(&b);
    return true;
}

/* `type.set`, `type.fill`: the new field value replaces the old in place, and the result is the same
 * pointer. A collection field frees its old header first. The old value's own drop is a separate
 * `drop` that mir_lower_ops puts before a `type.set`, which it turns into `type.fill`. */
static bool ll_indirect_set(LCx *c, const MirInst *inst, uint32_t block, uint32_t *part) {
    MirRecordBlock b;
    if (!ll_block_open(c, c->f->values[inst->args[0]], &b)) {
        return false;
    }
    char base[24];
    ll_pointer(c, inst->args[0], base, sizeof base);
    const uint32_t field = inst->imm.b;
    if (b.boxed[field]) {
        const uint32_t slot = ll_address(c, base, b.offsets[b.starts[field]]);
        const uint32_t n = c->next++;
        ms_buf_printf(c->out, "  %%g%u = load i64, ptr %%a%u\n  %%g%ub = icmp ne i64 %%g%u, 0\n", n, slot, n, n);
        char cond[24];
        (void)snprintf(cond, sizeof cond, "%%g%ub", n);
        const LlIf s = ll_if_begin(c, cond, block, part);
        ms_buf_printf(c->out, "  call void @\"msrt_free\"(i64 %%g%u)\n", n);
        ll_if_end(c, &s, block);
        const uint32_t h = ll_header_store(c, inst->args[1], block, part);
        ms_buf_printf(c->out, "  store i64 %%h%u, ptr %%a%u\n", h, slot);
    } else {
        ll_block_store_field(c, &b, base, field, inst->args[1]);
    }
    ms_buf_printf(c->out, "  %%v%u = add i64 %%v%u, 0\n", inst->res, inst->args[0]);
    mir_record_block_free(&b);
    return true;
}

/* `free` of a collection field: the header block behind the field of the record block, if any. */
static bool ll_free_field(LCx *c, const MirInst *inst, uint32_t block, uint32_t *part) {
    MirRecordBlock b;
    if (!mir_record_block(c->layouts, inst->imm.a, &b)) {
        c->why = "out of memory";
        return false;
    }
    char base[24];
    ll_pointer(c, inst->args[0], base, sizeof base);
    const uint32_t n = c->next++;
    const uint32_t slot = ll_address(c, base, b.offsets[b.starts[inst->imm.b]]);
    ms_buf_printf(c->out, "  %%g%u = load i64, ptr %%a%u\n  %%g%ub = icmp ne i64 %%g%u, 0\n", n, slot, n, n);
    char cond[24];
    (void)snprintf(cond, sizeof cond, "%%g%ub", n);
    const LlIf s = ll_if_begin(c, cond, block, part);
    ms_buf_printf(c->out, "  call void @\"msrt_free\"(i64 %%g%u)\n", n);
    ll_if_end(c, &s, block);
    mir_record_block_free(&b);
    return true;
}

/* How many pieces `inst` ends: one per branch of the operations above. */
static uint32_t ll_record_pieces(const MirModule *m, const MirFunc *f, const MirInst *inst) {
    if (inst->op == MOP_Free && inst->imm.tag != MI_NONE) {
        return 1;
    }
    MirTy subject = MIR_NONE;
    if (inst->op == MOP_TypeNew) {
        subject = f->values[inst->res];
    } else if (inst->nargs > 0) {
        subject = f->values[inst->args[0]];
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
static bool ll_indirect_op(LCx *c, const MirInst *inst, uint32_t block, uint32_t *part, bool *handled) {
    *handled = true;
    switch ((MirOp)inst->op) {
    case MOP_TypeNew:
        if (ll_is_indirect_record(c, c->f->values[inst->res])) {
            return ll_indirect_new(c, inst, block, part);
        }
        break;
    case MOP_TypeGet:
        if (ll_is_indirect_record(c, c->f->values[inst->args[0]])) {
            return ll_indirect_get(c, inst, block, part);
        }
        break;
    case MOP_TypeSet: case MOP_TypeFill:
        if (ll_is_indirect_record(c, c->f->values[inst->args[0]])) {
            return ll_indirect_set(c, inst, block, part);
        }
        break;
    case MOP_Free:
        if (inst->imm.tag != MI_NONE) {
            return ll_free_field(c, inst, block, part);
        }
        break;
    default:
        break;
    }
    *handled = false;
    return true;
}
