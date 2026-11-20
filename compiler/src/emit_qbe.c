/* MIR to QBE SSA text. QBE has no overflow flags, so a checked add or subtract is the sign test of
 * the wrapped result: it splits the block, and the last piece is the predecessor the successors'
 * phis name. */
#include "ms/emit_qbe.h"

#include <stdlib.h>

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
    const char base = qbe_base(c->f->values[v]);
    if (base == 0) {
        return 'l';
    }
    return base;
}

static const char *qbe_cc(MirCc cc, bool is_unsigned, bool is_float) {
    static const char *const signed_names[] = {"eq", "ne", "slt", "sle", "sgt", "sge"};
    static const char *const unsigned_names[] = {"eq", "ne", "ult", "ule", "ugt", "uge"};
    static const char *const float_names[] = {"eq", "ne", "lt", "le", "gt", "ge"};
    if (is_float) {
        return float_names[cc];
    }
    if (is_unsigned) {
        return unsigned_names[cc];
    }
    return signed_names[cc];
}

/* Operations that are one QBE instruction on their two operands, by opcode. */
typedef struct QbeBinary {
    MirOp op;
    const char *mnemonic;
} QbeBinary;

static const QbeBinary qbe_binary[] = {
    {MOP_IAdd, "add"}, {MOP_ISub, "sub"}, {MOP_IMul, "mul"}, {MOP_And, "and"},
    {MOP_Or, "or"},    {MOP_Xor, "xor"},  {MOP_Shl, "shl"},  {MOP_Sshr, "sar"},
    {MOP_Ushr, "shr"}, {MOP_FAdd, "add"}, {MOP_FSub, "sub"}, {MOP_FMul, "mul"},
    {MOP_FDiv, "div"}, {MOP_SDiv, "div"}, {MOP_SRem, "rem"},
};

static const char *qbe_binary_mnemonic(MirOp op) {
    for (size_t k = 0; k < sizeof qbe_binary / sizeof qbe_binary[0]; k++) {
        if (qbe_binary[k].op == op) {
            return qbe_binary[k].mnemonic;
        }
    }
    return NULL;
}

static void qbe_call(QCx *c, const MirInst *inst) {
    const MirFunc *callee = &c->m->funcs[inst->imm.a];
    if (inst->res != MIR_NONE) {
        ms_buf_printf(c->out, "\t%%v%u =%c call ", inst->res, qbe_vty(c, inst->res));
    } else {
        ms_buf_puts(c->out, "\tcall ");
    }
    qbe_sym(c->out, ms_name(&c->m->names, callee->name));
    ms_buf_putc(c->out, '(');
    for (uint32_t k = 0; k < inst->nargs; k++) {
        ms_buf_printf(c->out, "%s%c %%v%u", k ? ", " : "", qbe_vty(c, inst->args[k]),
                      inst->args[k]);
    }
    ms_buf_puts(c->out, ")\n");
}

/* A checked add or subtract. add overflows when both operands differ in sign from the result; sub
 * when the operands differ in sign and the result differs from the first. The check ends the
 * current piece of the block: the fault is a block of its own and the rest continues in a new piece. */
static void qbe_checked_arith(QCx *c, const MirInst *inst, uint32_t block, uint32_t *part) {
    MsBuf *o = c->out;
    const MirValue *a = inst->args;
    const bool add = inst->op == MOP_IAddChk;
    const uint32_t n = c->next++;
    ms_buf_printf(o, "\t%%v%u =l %s %%v%u, %%v%u\n", inst->res, add ? "add" : "sub", a[0], a[1]);
    ms_buf_printf(o, "\t%%o%ua =l xor %%v%u, %%v%u\n", n, a[0], inst->res);
    /* add: the second operand against the result; sub: the two operands against each other. */
    const MirValue second = add ? a[1] : a[0];
    const MirValue other = add ? inst->res : a[1];
    ms_buf_printf(o, "\t%%o%ub =l xor %%v%u, %%v%u\n", n, second, other);
    ms_buf_printf(o, "\t%%o%uc =l and %%o%ua, %%o%ub\n", n, n, n);
    ms_buf_printf(o, "\t%%o%us =w csltl %%o%uc, 0\n", n, n);
    (*part)++;
    ms_buf_printf(o, "\tjnz %%o%us, @f%u, ", n, n);
    qbe_label(c, block, *part);
    ms_buf_printf(o, "\n@f%u\n\tcall $msrt_fault_int_overflow()\n\thlt\n", n);
    qbe_label(c, block, *part);
    ms_buf_putc(o, '\n');
}

static void qbe_compare(QCx *c, const MirInst *inst) {
    const bool is_float = inst->op == MOP_FCmp;
    char type = 'd';
    if (!is_float) {
        type = qbe_vty(c, inst->args[0]);
    }
    ms_buf_printf(c->out, "\t%%v%u =w c%s%c %%v%u, %%v%u\n", inst->res,
                  qbe_cc((MirCc)inst->imm.a, inst->op == MOP_UICmp, is_float), type, inst->args[0],
                  inst->args[1]);
}

/* A constant. The float's bits go through an integer and a cast, so no decimal text can round it. */
static void qbe_constant(QCx *c, const MirInst *inst) {
    MsBuf *o = c->out;
    const unsigned id = inst->res;
    switch (inst->op) {
    case MOP_FConst:
        ms_buf_printf(o, "\t%%v%u.b =l copy %lld\n\t%%v%u =d cast %%v%u.b\n", id,
                      (long long)inst->imm.i, id, id);
        return;
    case MOP_BConst:
        ms_buf_printf(o, "\t%%v%u =w copy %u\n", id, inst->imm.a ? 1U : 0U);
        return;
    default:
        ms_buf_printf(o, "\t%%v%u =%c copy %lld\n", id, qbe_vty(c, inst->res),
                      (long long)inst->imm.i);
        return;
    }
}

/* The one-operand operations and conversions, by the QBE instruction that does them. */
static const char *qbe_unary_mnemonic(MirOp op) {
    switch (op) {
    case MOP_FNeg: return "neg";
    case MOP_I2F: return "sltof";
    case MOP_B2I: return "extuw";
    default: return NULL;
    }
}

static bool qbe_unary(QCx *c, const MirInst *inst) {
    if (inst->op == MOP_Not) {
        ms_buf_printf(c->out, "\t%%v%u =%c xor %%v%u, 1\n", inst->res, qbe_vty(c, inst->res),
                      inst->args[0]);
        return true;
    }
    const char *mnemonic = qbe_unary_mnemonic((MirOp)inst->op);
    if (mnemonic == NULL) {
        return false;
    }
    ms_buf_printf(c->out, "\t%%v%u =%c %s %%v%u\n", inst->res, qbe_vty(c, inst->res), mnemonic,
                  inst->args[0]);
    return true;
}

/* Writes one instruction; false, with the reason in `c->why`, when it is not covered yet. */
static bool qbe_inst(QCx *c, const MirInst *inst, uint32_t block, uint32_t *part) {
    const char *mnemonic = qbe_binary_mnemonic((MirOp)inst->op);
    if (mnemonic != NULL) {
        ms_buf_printf(c->out, "\t%%v%u =%c %s %%v%u, %%v%u\n", inst->res, qbe_vty(c, inst->res),
                      mnemonic, inst->args[0], inst->args[1]);
        return true;
    }
    if (qbe_unary(c, inst)) {
        return true;
    }
    switch (inst->op) {
    case MOP_IConst: case MOP_BConst: case MOP_FConst: qbe_constant(c, inst); return true;
    case MOP_ICmp: case MOP_UICmp: case MOP_FCmp: qbe_compare(c, inst); return true;
    case MOP_Call: qbe_call(c, inst); return true;
    case MOP_IAddChk: case MOP_ISubChk: qbe_checked_arith(c, inst, block, part); return true;
    default:
        c->why = mir_op_info[inst->op].name;
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
    if (f->ret != MIR_VOID && qbe_base(f->ret) == 0) {
        c->why = "result type";
        return false;
    }
    for (uint32_t k = 0; k < f->nvalues; k++) {
        if (f->values[k] != MIR_VOID && qbe_base(f->values[k]) == 0) {
            c->why = "value type";
            return false;
        }
    }
    return true;
}

/* The phi of block parameter `index` of block `b`: one arm per predecessor edge that reaches it.
 * `last` is the final piece of each block, which is the label an edge leaves from. */
static bool qbe_phi(QCx *c, uint32_t b, uint32_t index, const uint32_t *last) {
    const MirFunc *f = c->f;
    const MirValue param = f->blocks[b].params[index].value;
    ms_buf_printf(c->out, "\t%%v%u =%c phi", param, qbe_vty(c, param));
    bool first = true;
    for (uint32_t s = 0; s < f->nblocks; s++) {
        const MirTerm *t = &f->blocks[s].term;
        const MirTarget *edges[2] = {NULL, NULL};
        if (t->kind == MT_BR) {
            edges[0] = &t->a;
        } else if (t->kind == MT_CONDBR) {
            edges[0] = &t->a;
            edges[1] = &t->b;
        }
        if (edges[1] != NULL && edges[0]->block == b && edges[1]->block == b && edges[0]->nargs > 0) {
            c->why = "one block reaches a target twice with arguments";
            return false;
        }
        for (size_t k = 0; k < 2; k++) {
            if (edges[k] == NULL || edges[k]->block != b) {
                continue;
            }
            ms_buf_printf(c->out, "%s ", first ? "" : ",");
            qbe_label(c, s, last[s]);
            ms_buf_printf(c->out, " %%v%u", edges[k]->args[index]);
            first = false;
        }
    }
    ms_buf_putc(c->out, '\n');
    return true;
}

static bool qbe_block(QCx *c, uint32_t b, const uint32_t *last) {
    const MirBlockData *block = &c->f->blocks[b];
    ms_buf_printf(c->out, "@b%u\n", b);
    for (uint32_t p = 0; b > 0 && p < block->nparams; p++) {
        if (!qbe_phi(c, b, p, last)) {
            return false;
        }
    }
    uint32_t part = 0;
    for (uint32_t k = 0; k < block->ninsts; k++) {
        if (!qbe_inst(c, &block->insts[k], b, &part)) {
            return false;
        }
    }
    return qbe_term(c, &block->term);
}

static void qbe_header(QCx *c, uint32_t index) {
    const MirFunc *f = c->f;
    MsBuf *o = c->out;
    const bool exported = f->linkage == ML_EXPORT || c->m->entry == index;
    ms_buf_printf(o, "%sfunction ", exported ? "export " : "");
    if (f->ret != MIR_VOID) {
        ms_buf_printf(o, "%c ", qbe_base(f->ret));
    }
    qbe_sym(o, ms_name(&c->m->names, f->name));
    ms_buf_putc(o, '(');
    for (uint32_t k = 0; k < f->nparams; k++) {
        ms_buf_printf(o, "%s%c %%v%u", k ? ", " : "", qbe_base(f->params[k].ty),
                      f->blocks[0].params[k].value);
    }
    ms_buf_puts(o, ") {\n");
}

/* Pieces each block splits into: its checked operations each end one, and the last piece is what
 * the successors' phis name. Fills `last` with the count per block. */
static void qbe_last_pieces(const MirFunc *f, uint32_t *last) {
    for (uint32_t b = 0; b < f->nblocks; b++) {
        last[b] = 0;
        for (uint32_t k = 0; k < f->blocks[b].ninsts; k++) {
            if (qbe_checked((MirOp)f->blocks[b].insts[k].op)) {
                last[b]++;
            }
        }
    }
}

static bool qbe_function(QCx *c, uint32_t index) {
    const MirFunc *f = c->f;
    if (!qbe_types_ok(c)) {
        return false;
    }
    uint32_t *last = calloc(f->nblocks, sizeof *last); /* owned, freed below */
    if (last == NULL) {
        c->why = "out of memory";
        return false;
    }
    qbe_last_pieces(f, last);
    qbe_header(c, index);
    bool ok = true;
    for (uint32_t b = 0; ok && b < f->nblocks; b++) {
        ok = qbe_block(c, b, last);
    }
    free(last);
    if (ok) {
        ms_buf_puts(c->out, "}\n\n");
    }
    return ok;
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
