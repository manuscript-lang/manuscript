/* Closures and indirect calls for emit_qbe.c (included from it). A closure object is a header of
 * three words, the clone, drop and code entries, then each capture at its offset
 * (`mir_closure_layout`). Its value is the object's address; the code takes that address as its
 * first leaf, so `call.ind` loads the code word and calls it with the closure first. */

enum { QBE_CLOSURE_CLONE = 0, QBE_CLOSURE_DROP = 8, QBE_CLOSURE_CODE = 16 };

/* Writes `%q<n> =l add base, offset` and returns `n`. */
static uint32_t qbe_offset_ptr(QCx *c, const char *base, uint32_t offset) {
    const uint32_t n = c->next++;
    ms_buf_printf(c->out, "\t%%q%u =l add %s, %u\n", n, base, offset);
    return n;
}

/* `call.ind`: the code word of the closure in the first operand, called with the closure first. */
static bool qbe_call_ind(QCx *c, const MirInst *inst, uint32_t block, uint32_t index) {
    char env[24], callee[24];
    (void)snprintf(env, sizeof env, "%%v%u", inst->args[0]);
    const uint32_t at = qbe_offset_ptr(c, env, QBE_CLOSURE_CODE);
    const uint32_t n = c->next++;
    ms_buf_printf(c->out, "\t%%k%u =l loadl %%q%u\n", n, at);
    (void)snprintf(callee, sizeof callee, "%%k%u", n);
    return qbe_call_to(c, inst, block, index, callee, NULL);
}

/* Stores the address of function `func` at `offset` of the closure object `obj`. */
static void qbe_store_entry(QCx *c, const char *obj, uint32_t offset, uint32_t func) {
    const uint32_t at = qbe_offset_ptr(c, obj, offset);
    ms_buf_puts(c->out, "\tstorel ");
    qbe_sym(c->out, ms_name(&c->m->names, c->m->funcs[func].name));
    ms_buf_printf(c->out, ", %%q%u\n", at);
}

/* The glue functions a closure object points at; false, with the reason, when they were not made. */
static bool qbe_closure_glue(QCx *c, uint32_t code, bool framed, uint32_t *clone, uint32_t *drop) {
    *clone = mir_glue_find(c->glue, MG_CLOSURE_CLONE, MIR_VOID, code, 0);
    *drop = mir_glue_find(c->glue, framed ? MG_CLOSURE_DROP_FRAMED : MG_CLOSURE_DROP, MIR_VOID, code, 0);
    if (*clone == MIR_NONE || *drop == MIR_NONE) {
        c->why = "closure glue was not made";
        return false;
    }
    return true;
}

/* `closure.new`: a frame slot or a heap block, the three header entries, then the captures. */
static bool qbe_closure_new(QCx *c, const MirInst *inst, uint32_t block, uint32_t index) {
    const uint32_t code = inst->imm.a;
    const bool framed = c->framed[inst->res];
    const MirClosureLayout layout = mir_closure_layout(c->layouts, &c->m->funcs[code]);
    uint32_t clone, drop;
    if (!qbe_closure_glue(c, code, framed, &clone, &drop)) {
        return false;
    }
    char obj[24];
    if (framed) {
        (void)snprintf(obj, sizeof obj, "%%o%u_%u", block, index);
        ms_buf_printf(c->out, "\t%%v%u =l copy %s\n", inst->res, obj);
    } else {
        ms_buf_printf(c->out, "\t%%v%u =l call $msrt_alloc(l %u)\n", inst->res, layout.size);
        (void)snprintf(obj, sizeof obj, "%%v%u", inst->res);
    }
    qbe_store_entry(c, obj, QBE_CLOSURE_CLONE, clone);
    qbe_store_entry(c, obj, QBE_CLOSURE_DROP, drop);
    qbe_store_entry(c, obj, QBE_CLOSURE_CODE, code);
    for (uint32_t k = 0; k < layout.ncaptures && k < inst->nargs; k++) {
        if (layout.captures[k].leaves.len == 0) {
            continue;
        }
        char at[24];
        (void)snprintf(at, sizeof at, "%%q%u", qbe_offset_ptr(c, obj, layout.captures[k].offset));
        if (!qbe_store_leaves(c, inst->args[k], at)) {
            return false;
        }
    }
    return true;
}

/* `closure.cap`, `closure.cap_addr`: capture `i` of the closure being run, by value or by address. */
static bool qbe_closure_cap(QCx *c, const MirInst *inst) {
    const MirClosureLayout layout = mir_closure_layout(c->layouts, c->f);
    const uint32_t i = inst->imm.a;
    if (i >= layout.ncaptures) {
        c->why = "capture out of range";
        return false;
    }
    const uint32_t offset = layout.captures[i].offset;
    if (inst->op == MOP_ClosureCapAddr) {
        ms_buf_printf(c->out, "\t%%v%u =l add %%v%u, %u\n", inst->res, inst->args[0], offset);
        return true;
    }
    if (layout.captures[i].leaves.len == 0) {
        return true;
    }
    char env[24], at[24];
    (void)snprintf(env, sizeof env, "%%v%u", inst->args[0]);
    (void)snprintf(at, sizeof at, "%%q%u", qbe_offset_ptr(c, env, offset));
    return qbe_load_leaves(c, inst->res, at);
}

/* The closure operations; `*handled` says whether `inst` is one. */
static bool qbe_closure_op(QCx *c, const MirInst *inst, uint32_t block, uint32_t index, bool *handled) {
    *handled = true;
    switch ((MirOp)inst->op) {
    case MOP_ClosureNew: return qbe_closure_new(c, inst, block, index);
    case MOP_ClosureCap: case MOP_ClosureCapAddr: return qbe_closure_cap(c, inst);
    case MOP_CallInd: return qbe_call_ind(c, inst, block, index);
    default:
        *handled = false;
        return true;
    }
}
