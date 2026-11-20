/* MIR to QBE SSA text. QBE has no overflow flags, so a checked add or subtract is the sign test of
 * the wrapped result: it splits the block, and the last piece is the predecessor the successors'
 * phis name. */
#include "ms/emit_qbe.h"

typedef struct QCx {
    const MirModule *m;
    const MirFunc *f;
    MsBuf *out;
    uint32_t next; /* label counter for generated names */
    const char *why;
} QCx;

/* The QBE base type of a scalar type, 0 when the emitter does not handle it. */
static char qbe_base(MirTy t) {
    switch (t) {
    case MIR_INT: case MIR_PTR: return 'l';
    case MIR_BOOL: return 'w';
    case MIR_FLOAT: return 'd';
    default: return 0;
    }
}

/* A function name as a QBE symbol. Quoted names would skip the underscore the Mach-O targets add to
 * every symbol, so a name stays bare: characters QBE does not allow in a bare name become `.xHH`. */
static void qbe_sym(MsBuf *o, MsStr n) {
    ms_buf_putc(o, '$');
    for (uint32_t k = 0; k < n.len; k++) {
        unsigned char ch = (unsigned char)n.ptr[k];
        bool plain = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') ||
                     ch == '_' || ch == '.';
        if (plain) ms_buf_putc(o, (char)ch);
        else ms_buf_printf(o, ".x%02x", ch);
    }
}

static bool qbe_checked(MirOp op) { return op == MOP_IAddChk || op == MOP_ISubChk; }

static void qbe_label(QCx *c, uint32_t block, uint32_t part) {
    if (part == 0) ms_buf_printf(c->out, "@b%u", block);
    else ms_buf_printf(c->out, "@b%u_%u", block, part);
}

static char qbe_vty(QCx *c, MirValue v) {
    char b = qbe_base(c->f->values[v]);
    return b ? b : 'l';
}

static const char *qbe_cc(MirCc cc, bool is_unsigned, bool is_float) {
    static const char *const sgn[] = {"eq", "ne", "slt", "sle", "sgt", "sge"};
    static const char *const uns[] = {"eq", "ne", "ult", "ule", "ugt", "uge"};
    static const char *const flt[] = {"eq", "ne", "lt", "le", "gt", "ge"};
    return is_float ? flt[cc] : is_unsigned ? uns[cc] : sgn[cc];
}

static bool qbe_inst(QCx *c, const MirInst *i, uint32_t block, uint32_t *part) {
    MsBuf *o = c->out;
    char t = i->res != MIR_NONE ? qbe_vty(c, i->res) : 0;
    const MirValue *a = i->args;
    const char *op = NULL;
    switch ((MirOp)i->op) {
    case MOP_IConst:
        ms_buf_printf(o, "\t%%v%u =%c copy %lld\n", i->res, t, (long long)i->imm.i);
        return true;
    case MOP_BConst:
        ms_buf_printf(o, "\t%%v%u =%c copy %u\n", i->res, t, i->imm.a ? 1u : 0u);
        return true;
    case MOP_FConst: /* the bits as an integer, then a cast: no decimal round trip */
        ms_buf_printf(o, "\t%%v%u.b =l copy %lld\n\t%%v%u =d cast %%v%u.b\n", i->res,
                      (long long)i->imm.i, i->res, i->res);
        return true;
    case MOP_IAdd: op = "add"; break;
    case MOP_ISub: op = "sub"; break;
    case MOP_IMul: op = "mul"; break;
    case MOP_And: op = "and"; break;
    case MOP_Or: op = "or"; break;
    case MOP_Xor: op = "xor"; break;
    case MOP_Shl: op = "shl"; break;
    case MOP_Sshr: op = "sar"; break;
    case MOP_Ushr: op = "shr"; break;
    case MOP_FAdd: op = "add"; break;
    case MOP_FSub: op = "sub"; break;
    case MOP_FMul: op = "mul"; break;
    case MOP_FDiv: op = "div"; break;
    case MOP_SDiv: op = "div"; break;
    case MOP_SRem: op = "rem"; break;
    default: break;
    }
    if (op) {
        ms_buf_printf(o, "\t%%v%u =%c %s %%v%u, %%v%u\n", i->res, t, op, a[0], a[1]);
        return true;
    }
    switch ((MirOp)i->op) {
    case MOP_Not:
        ms_buf_printf(o, "\t%%v%u =%c xor %%v%u, 1\n", i->res, t, a[0]);
        return true;
    case MOP_FNeg:
        ms_buf_printf(o, "\t%%v%u =d neg %%v%u\n", i->res, a[0]);
        return true;
    case MOP_I2F:
        ms_buf_printf(o, "\t%%v%u =d sltof %%v%u\n", i->res, a[0]);
        return true;
    case MOP_B2I:
        ms_buf_printf(o, "\t%%v%u =l extuw %%v%u\n", i->res, a[0]);
        return true;
    case MOP_ICmp: case MOP_UICmp: case MOP_FCmp: {
        bool f = i->op == MOP_FCmp;
        ms_buf_printf(o, "\t%%v%u =w c%s%c %%v%u, %%v%u\n", i->res,
                      qbe_cc((MirCc)i->imm.a, i->op == MOP_UICmp, f), f ? 'd' : qbe_vty(c, a[0]),
                      a[0], a[1]);
        return true;
    }
    case MOP_Call: {
        const MirFunc *callee = &c->m->funcs[i->imm.a];
        MsStr name = ms_name(&c->m->names, callee->name);
        if (t) ms_buf_printf(o, "\t%%v%u =%c call ", i->res, t);
        else ms_buf_puts(o, "\tcall ");
        qbe_sym(o, name);
        ms_buf_putc(o, '(');
        for (uint32_t k = 0; k < i->nargs; k++) {
            ms_buf_printf(o, "%s%c %%v%u", k ? ", " : "", qbe_vty(c, a[k]), a[k]);
        }
        ms_buf_puts(o, ")\n");
        return true;
    }
    case MOP_IAddChk: case MOP_ISubChk: {
        bool add = i->op == MOP_IAddChk;
        uint32_t n = c->next++;
        ms_buf_printf(o, "\t%%v%u =l %s %%v%u, %%v%u\n", i->res, add ? "add" : "sub", a[0], a[1]);
        /* add overflows when both operands differ in sign from the result; sub when the operands
         * differ in sign and the result differs from the first. */
        ms_buf_printf(o, "\t%%o%ua =l xor %%v%u, %%v%u\n", n, a[0], i->res);
        if (add) ms_buf_printf(o, "\t%%o%ub =l xor %%v%u, %%v%u\n", n, a[1], i->res);
        else ms_buf_printf(o, "\t%%o%ub =l xor %%v%u, %%v%u\n", n, a[0], a[1]);
        ms_buf_printf(o, "\t%%o%uc =l and %%o%ua, %%o%ub\n\t%%o%us =w csltl %%o%uc, 0\n", n, n, n,
                      n, n);
        (*part)++;
        ms_buf_printf(o, "\tjnz %%o%us, @f%u, ", n, n);
        qbe_label(c, block, *part);
        ms_buf_printf(o, "\n@f%u\n\tcall $msrt_fault_int_overflow()\n\thlt\n", n);
        qbe_label(c, block, *part);
        ms_buf_putc(o, '\n');
        return true;
    }
    default:
        c->why = mir_op_info[i->op].name;
        return false;
    }
}

static bool qbe_term(QCx *c, const MirTerm *t) {
    MsBuf *o = c->out;
    switch ((MirTermKind)t->kind) {
    case MT_BR:
        ms_buf_printf(o, "\tjmp @b%u\n", t->a.block);
        return true;
    case MT_CONDBR:
        ms_buf_printf(o, "\tjnz %%v%u, @b%u, @b%u\n", t->value, t->a.block, t->b.block);
        return true;
    case MT_RET:
        if (t->value == MIR_NONE) ms_buf_puts(o, "\tret\n");
        else ms_buf_printf(o, "\tret %%v%u\n", t->value);
        return true;
    case MT_UNREACHABLE:
        ms_buf_puts(o, "\thlt\n");
        return true;
    case MT_FAULT:
        if (t->fault == MF_INT_OVERFLOW) {
            ms_buf_puts(o, "\tcall $msrt_fault_int_overflow()\n\thlt\n");
            return true;
        }
        c->why = "fault kind";
        return false;
    default:
        c->why = "switch";
        return false;
    }
}

/* Whether every type in the function is one the emitter handles. */
static bool qbe_types_ok(QCx *c) {
    const MirFunc *f = c->f;
    if (f->ret != MIR_VOID && !qbe_base(f->ret)) return c->why = "result type", false;
    for (uint32_t k = 0; k < f->nvalues; k++) {
        if (f->values[k] != MIR_VOID && !qbe_base(f->values[k])) return c->why = "value type", false;
    }
    return true;
}

static bool qbe_function(QCx *c, uint32_t index) {
    const MirFunc *f = c->f;
    MsBuf *o = c->out;
    if (!qbe_types_ok(c)) return false;
    /* Pieces each block splits into: the last is what its successors' phis name. */
    uint32_t *last = MS_NEW_N(&((MirModule *)c->m)->arena, uint32_t, f->nblocks ? f->nblocks : 1);
    for (uint32_t b = 0; b < f->nblocks; b++) {
        last[b] = 0;
        for (uint32_t k = 0; k < f->blocks[b].ninsts; k++) {
            if (qbe_checked((MirOp)f->blocks[b].insts[k].op)) last[b]++;
        }
    }
    bool export_ = f->linkage == ML_EXPORT || c->m->entry == index;
    MsStr name = ms_name(&c->m->names, f->name);
    ms_buf_printf(o, "%sfunction ", export_ ? "export " : "");
    if (f->ret != MIR_VOID) ms_buf_printf(o, "%c ", qbe_base(f->ret));
    qbe_sym(o, name);
    ms_buf_putc(o, '(');
    const MirBlockData *entry = &f->blocks[0];
    for (uint32_t k = 0; k < f->nparams; k++) {
        ms_buf_printf(o, "%s%c %%v%u", k ? ", " : "", qbe_base(f->params[k].ty),
                      entry->params[k].value);
    }
    ms_buf_puts(o, ") {\n");
    for (uint32_t b = 0; b < f->nblocks; b++) {
        const MirBlockData *bd = &f->blocks[b];
        ms_buf_printf(o, "@b%u\n", b);
        for (uint32_t p = 0; b > 0 && p < bd->nparams; p++) {
            MirValue pv = bd->params[p].value;
            ms_buf_printf(o, "\t%%v%u =%c phi", pv, qbe_vty(c, pv));
            bool first = true;
            for (uint32_t s = 0; s < f->nblocks; s++) {
                const MirTerm *t = &f->blocks[s].term;
                const MirTarget *ts[3] = {NULL, NULL, NULL};
                if (t->kind == MT_BR) ts[0] = &t->a;
                else if (t->kind == MT_CONDBR) ts[0] = &t->a, ts[1] = &t->b;
                if (ts[0] && ts[1] && ts[0]->block == b && ts[1]->block == b && ts[0]->nargs) {
                    c->why = "one block reaches a target twice with arguments";
                    return false;
                }
                for (int k = 0; k < 2; k++) {
                    if (!ts[k] || ts[k]->block != b) continue;
                    ms_buf_printf(o, "%s ", first ? "" : ",");
                    qbe_label(c, s, last[s]);
                    ms_buf_printf(o, " %%v%u", ts[k]->args[p]);
                    first = false;
                }
            }
            ms_buf_putc(o, '\n');
        }
        uint32_t part = 0;
        for (uint32_t k = 0; k < bd->ninsts; k++) {
            if (!qbe_inst(c, &bd->insts[k], b, &part)) return false;
        }
        if (!qbe_term(c, &bd->term)) return false;
    }
    ms_buf_puts(o, "}\n\n");
    return true;
}

bool mir_emit_qbe(const MirModule *m, MsBuf *out, MsBuf *why) {
    bool ok = true;
    for (uint32_t i = 0; i < m->nfuncs; i++) {
        QCx c = {m, &m->funcs[i], out, 0, NULL};
        if (qbe_function(&c, i)) continue;
        MsStr n = ms_name(&m->names, m->funcs[i].name);
        ms_buf_printf(why, "%.*s: %s\n", (int)n.len, n.ptr, c.why ? c.why : "unsupported");
        ok = false;
    }
    return ok;
}
