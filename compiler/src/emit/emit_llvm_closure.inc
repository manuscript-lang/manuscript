/* Closures and indirect calls for emit_llvm.c (included from it). A closure object is a header of
 * three words, the clone, drop and code entries, then each capture at its offset
 * (`mir_closure_layout`). Its value is the object's address; the code takes that address as its
 * first leaf, so `call.ind` loads the code word and calls it with the closure first. */

/* The header word offsets of a closure object. */
enum { LL_CLOSURE_CLONE = 0, LL_CLOSURE_DROP = 8, LL_CLOSURE_CODE = 16 };

/* Writes `%<name>N = getelementptr i8, ptr <base>, i64 offset` and returns the name in `out`. */
static void ll_offset_ptr(LCx *c, const char *base, uint32_t offset, char *out, size_t cap) {
    const uint32_t n = c->next++;
    ms_buf_printf(c->out, "  %%q%u = getelementptr i8, ptr %s, i64 %u\n", n, base, offset);
    (void)snprintf(out, cap, "%%q%u", n);
}

/* The name of function `id` as an LLVM global. */
static void ll_func_sym(const LCx *c, MsBuf *o, uint32_t id) {
    ll_sym(o, ms_name(&c->m->names, c->m->funcs[id].name));
}

/* `call.ind`: the code word of the closure in the first operand, called with the closure first. */
static bool ll_call_ind(LCx *c, const MirInst *inst, uint32_t block, uint32_t index) {
    char env[24], code_at[24], callee[24];
    ll_pointer(c, inst->args[0], env, sizeof env);
    ll_offset_ptr(c, env, LL_CLOSURE_CODE, code_at, sizeof code_at);
    const uint32_t n = c->next++;
    ms_buf_printf(c->out, "  %%k%u = load ptr, ptr %s\n", n, code_at);
    (void)snprintf(callee, sizeof callee, "%%k%u", n);
    return ll_call_to(c, inst, block, index, callee, NULL);
}

/* Stores `@func` at `offset` of the closure object `obj`. */
static void ll_store_entry(LCx *c, const char *obj, uint32_t offset, uint32_t func) {
    char at[24];
    ll_offset_ptr(c, obj, offset, at, sizeof at);
    ms_buf_puts(c->out, "  store ptr ");
    ll_func_sym(c, c->out, func);
    ms_buf_printf(c->out, ", ptr %s\n", at);
}

/* `closure.new`: a frame slot or a heap block, the three header entries, then the captures. */
static bool ll_closure_new(LCx *c, const MirInst *inst, uint32_t block, uint32_t index) {
    const uint32_t code = inst->imm.a;
    const bool framed = c->framed[inst->res];
    const MirClosureLayout layout = mir_closure_layout(c->layouts, &c->m->funcs[code]);
    if (c->glue == NULL) {
        c->why = "closure without glue";
        return false;
    }
    const uint32_t clone = mir_glue_find(c->glue, MG_CLOSURE_CLONE, MIR_VOID, code, 0);
    const uint32_t drop =
        mir_glue_find(c->glue, framed ? MG_CLOSURE_DROP_FRAMED : MG_CLOSURE_DROP, MIR_VOID, code, 0);
    if (clone == MIR_NONE || drop == MIR_NONE) {
        c->why = "closure glue was not made";
        return false;
    }
    char obj[24];
    if (framed) {
        (void)snprintf(obj, sizeof obj, "%%o%u_%u", block, index);
        ms_buf_printf(c->out, "  %%v%u = ptrtoint ptr %s to i64\n", inst->res, obj);
    } else {
        ms_buf_printf(c->out, "  %%v%u = call i64 @\"msrt_alloc\"(i64 %u)\n", inst->res, layout.size);
        ll_pointer(c, inst->res, obj, sizeof obj);
    }
    ll_store_entry(c, obj, LL_CLOSURE_CLONE, clone);
    ll_store_entry(c, obj, LL_CLOSURE_DROP, drop);
    ll_store_entry(c, obj, LL_CLOSURE_CODE, code);
    for (uint32_t k = 0; k < layout.ncaptures && k < inst->nargs; k++) {
        if (layout.captures[k].leaves.len == 0) {
            continue;
        }
        char at[24];
        ll_offset_ptr(c, obj, layout.captures[k].offset, at, sizeof at);
        if (!ll_leaves_at(c, inst->args[k], at, false)) {
            return false;
        }
    }
    return true;
}

/* `closure.cap`, `closure.cap_addr`: capture `i` of the closure being run, by value or by address. */
static bool ll_closure_cap(LCx *c, const MirInst *inst) {
    const MirClosureLayout layout = mir_closure_layout(c->layouts, c->f);
    const uint32_t i = inst->imm.a;
    if (i >= layout.ncaptures) {
        c->why = "capture out of range";
        return false;
    }
    const uint32_t offset = layout.captures[i].offset;
    if (inst->op == MOP_ClosureCapAddr) {
        ms_buf_printf(c->out, "  %%v%u = add i64 %%v%u, %u\n", inst->res, inst->args[0], offset);
        return true;
    }
    if (layout.captures[i].leaves.len == 0) {
        return true;
    }
    char env[24], at[24];
    ll_pointer(c, inst->args[0], env, sizeof env);
    ll_offset_ptr(c, env, offset, at, sizeof at);
    return ll_leaves_at(c, inst->res, at, true);
}

/* The closure and function-address operations; `*handled` says whether `inst` is one. */
static bool ll_closure_op(LCx *c, const MirInst *inst, uint32_t block, uint32_t index, bool *handled) {
    *handled = true;
    switch ((MirOp)inst->op) {
    case MOP_FuncAddr:
        ms_buf_printf(c->out, "  %%v%u = ptrtoint ptr ", inst->res);
        ll_func_sym(c, c->out, inst->imm.a);
        ms_buf_puts(c->out, " to i64\n");
        return true;
    case MOP_ClosureNew: return ll_closure_new(c, inst, block, index);
    case MOP_ClosureCap: case MOP_ClosureCapAddr: return ll_closure_cap(c, inst);
    case MOP_CallInd: return ll_call_ind(c, inst, block, index);
    default:
        *handled = false;
        return true;
    }
}
