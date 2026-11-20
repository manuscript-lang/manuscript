/* MIR to QBE SSA text (proposals/qbe-calling-convention.md).
 *
 * A MIR value is a run of QBE temporaries, one per leaf (`%v7`, `%v7.1`, ...). Parameters of at
 * most 16 bytes travel as their leaves; a result of more than one leaf is written through a
 * hidden first parameter. QBE has no overflow flags, so a checked add or subtract is the sign test
 * of the wrapped result: it splits the block, and the last piece is the predecessor the
 * successors' phis name. */
#include "ms/emit_qbe.h"

#include <stdio.h>
#include <stdlib.h>

#include "ms/mir_layout.h"

/* Values of at most this many bytes are passed as their leaves; larger ones are not supported yet. */
#define QBE_DIRECT_BYTES 16

typedef struct QCx {
    const MirModule *m;
    const MirFunc *f;
    MsBuf *out;
    MirLayouts *layouts; /* borrowed from mir_emit_qbe */
    uint32_t next;       /* counter for generated names */
    const char *why;
} QCx;

/* What QBE needs to know about each kind of leaf, indexed by `MirLeaf`: the register type
 * (sized integers live in `l` registers, Float32 in a `d` register), and the memory instructions
 * that read and write it. */
typedef struct QbeLeafKind {
    char reg;
    const char *load;
    const char *store;
} QbeLeafKind;

static const QbeLeafKind qbe_leaf_kinds[MIR_LEAF_COUNT] = {
    [MIR_LEAF_I64] = {'l', "loadl", "storel"},  [MIR_LEAF_F64] = {'d', "loadd", "stored"},
    [MIR_LEAF_I8] = {'w', "loadub", "storeb"},  [MIR_LEAF_N8] = {'l', "loadsb", "storeb"},
    [MIR_LEAF_N16] = {'l', "loadsh", "storeh"}, [MIR_LEAF_N32] = {'l', "loadsw", "storew"},
    [MIR_LEAF_U8] = {'l', "loadub", "storeb"},  [MIR_LEAF_U16] = {'l', "loaduh", "storeh"},
    [MIR_LEAF_U32] = {'l', "loaduw", "storew"}, [MIR_LEAF_F32] = {'d', "loads", "stores"},
};

static const QbeLeafKind *qbe_leaf_kind(MirLeaf leaf) {
    return &qbe_leaf_kinds[leaf < MIR_LEAF_COUNT ? leaf : MIR_LEAF_I64];
}

static char qbe_leaf_type(MirLeaf leaf) { return qbe_leaf_kind(leaf)->reg; }

static MirLeafSpan qbe_leaves(const QCx *c, MirTy ty) { return mir_leaves(c->layouts, ty); }

/* The name of leaf `leaf` of value `v`: the first leaf is the bare name. */
static void qbe_name(MsBuf *o, MirValue v, uint32_t leaf) {
    if (leaf == 0) {
        ms_buf_printf(o, "%%v%u", v);
    } else {
        ms_buf_printf(o, "%%v%u.%u", v, leaf);
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

/* The register type of a one-leaf value; `l` for anything else (callers never ask). */
static char qbe_vty(const QCx *c, MirValue v) {
    const MirLeafSpan leaves = qbe_leaves(c, c->f->values[v]);
    if (leaves.len != 1) {
        return 'l';
    }
    return qbe_leaf_type(leaves.ptr[0]);
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

/* ---- memory and records ---- */

/* Writes the address `base + offset` as a new temporary and returns its number. */
static uint32_t qbe_address(QCx *c, const char *base, uint32_t offset) {
    const uint32_t n = c->next++;
    ms_buf_printf(c->out, "\t%%a%u =l add %s, %u\n", n, base, offset);
    return n;
}

static const char *qbe_load_mnemonic(MirLeaf leaf) { return qbe_leaf_kind(leaf)->load; }

static const char *qbe_store_mnemonic(MirLeaf leaf) { return qbe_leaf_kind(leaf)->store; }

/* Loads leaf `leaf` of `dst` from the address temporary `%a<address>`. A Float32 is read as a
 * single and widened, because it lives in a double register. */
static void qbe_load_leaf(QCx *c, MirLeaf leaf, MirValue dst, uint32_t index, uint32_t address) {
    MsBuf *o = c->out;
    ms_buf_puts(o, "\t");
    qbe_name(o, dst, index);
    if (leaf == MIR_LEAF_F32) {
        const uint32_t n = c->next++;
        ms_buf_printf(o, " =d exts %%s%u\n", n);
        ms_buf_printf(o, "\t%%s%u =s loads %%a%u\n", n, address);
        return;
    }
    ms_buf_printf(o, " =%c %s %%a%u\n", qbe_leaf_type(leaf), qbe_load_mnemonic(leaf), address);
}

/* Stores leaf `leaf` of `src` to the address temporary `%a<address>`. */
static void qbe_store_leaf(QCx *c, MirLeaf leaf, MirValue src, uint32_t index, uint32_t address) {
    MsBuf *o = c->out;
    if (leaf == MIR_LEAF_F32) {
        const uint32_t n = c->next++;
        ms_buf_printf(o, "\t%%s%u =s truncd ", n);
        qbe_name(o, src, index);
        ms_buf_printf(o, "\n\tstores %%s%u, %%a%u\n", n, address);
        return;
    }
    ms_buf_printf(o, "\t%s ", qbe_store_mnemonic(leaf));
    qbe_name(o, src, index);
    ms_buf_printf(o, ", %%a%u\n", address);
}

/* Reads the leaves of `dst` from memory at the address in `base` (a temporary's name). */
static bool qbe_load_leaves(QCx *c, MirValue dst, const char *base) {
    const MirLeafSpan leaves = qbe_leaves(c, c->f->values[dst]);
    uint32_t *offsets = calloc((size_t)leaves.len + 1, sizeof *offsets); /* owned, freed below */
    if (offsets == NULL) {
        c->why = "out of memory";
        return false;
    }
    (void)mir_mem_layout(leaves.ptr, leaves.len, offsets);
    for (uint32_t k = 0; k < leaves.len; k++) {
        qbe_load_leaf(c, leaves.ptr[k], dst, k, qbe_address(c, base, offsets[k]));
    }
    free(offsets);
    return true;
}

/* Writes the leaves of `src` to memory at the address in `base`. */
static bool qbe_store_leaves(QCx *c, MirValue src, const char *base) {
    const MirLeafSpan leaves = qbe_leaves(c, c->f->values[src]);
    uint32_t *offsets = calloc((size_t)leaves.len + 1, sizeof *offsets); /* owned, freed below */
    if (offsets == NULL) {
        c->why = "out of memory";
        return false;
    }
    (void)mir_mem_layout(leaves.ptr, leaves.len, offsets);
    for (uint32_t k = 0; k < leaves.len; k++) {
        qbe_store_leaf(c, leaves.ptr[k], src, k, qbe_address(c, base, offsets[k]));
    }
    free(offsets);
    return true;
}

/* `load`, `take`: the result's leaves from the pointer in the first operand. */
static bool qbe_load(QCx *c, const MirInst *inst) {
    char base[24];
    (void)snprintf(base, sizeof base, "%%v%u", inst->args[0]);
    return qbe_load_leaves(c, inst->res, base);
}

/* `store`, `put`: the second operand's leaves to the pointer in the first. */
static bool qbe_store(QCx *c, const MirInst *inst) {
    char base[24];
    (void)snprintf(base, sizeof base, "%%v%u", inst->args[0]);
    return qbe_store_leaves(c, inst->args[1], base);
}

/* The leaf range `[start, start + count)` that field `field` of record type `ty` occupies in a
 * value of that type. False when `ty` is not a record held as leaves. */
static bool qbe_field_span(QCx *c, MirTy ty, uint32_t field, uint32_t *start, uint32_t *count) {
    const MirTyData *data = mir_ty_data(c->m, ty);
    if (data->kind != MK_TYPE || c->m->type_defs[data->id].indirect) {
        c->why = "record behind a pointer";
        return false;
    }
    const MirTypeDef *def = &c->m->type_defs[data->id];
    *start = 0;
    for (uint32_t k = 0; k < field; k++) {
        *start += qbe_leaves(c, def->fields[k].ty).len;
    }
    *count = qbe_leaves(c, def->fields[field].ty).len;
    return true;
}

/* Result leaf `out_index` takes the value of leaf `src_index` of `src`. */
static void qbe_copy_leaf(QCx *c, MirValue dst, uint32_t out_index, MirValue src, uint32_t src_index) {
    MsBuf *o = c->out;
    const MirLeafSpan leaves = qbe_leaves(c, c->f->values[dst]);
    ms_buf_puts(o, "\t");
    qbe_name(o, dst, out_index);
    ms_buf_printf(o, " =%c copy ", qbe_leaf_type(leaves.ptr[out_index]));
    qbe_name(o, src, src_index);
    ms_buf_putc(o, '\n');
}

/* `type.new`: the leaves of the fields in order. */
static void qbe_record_new(QCx *c, const MirInst *inst) {
    uint32_t at = 0;
    for (uint32_t k = 0; k < inst->nargs; k++) {
        const uint32_t count = qbe_leaves(c, c->f->values[inst->args[k]]).len;
        for (uint32_t j = 0; j < count; j++) {
            qbe_copy_leaf(c, inst->res, at++, inst->args[k], j);
        }
    }
}

/* `type.get`: the leaves of one field. */
static bool qbe_record_get(QCx *c, const MirInst *inst) {
    uint32_t start = 0;
    uint32_t count = 0;
    if (!qbe_field_span(c, c->f->values[inst->args[0]], inst->imm.b, &start, &count)) {
        return false;
    }
    for (uint32_t j = 0; j < count; j++) {
        qbe_copy_leaf(c, inst->res, j, inst->args[0], start + j);
    }
    return true;
}

/* `type.set`: the record with one field's leaves replaced by the second operand's. */
static bool qbe_record_set(QCx *c, const MirInst *inst) {
    const uint32_t total = qbe_leaves(c, c->f->values[inst->args[0]]).len;
    uint32_t start = 0;
    uint32_t count = 0;
    if (!qbe_field_span(c, c->f->values[inst->args[0]], inst->imm.b, &start, &count)) {
        return false;
    }
    for (uint32_t j = 0; j < total; j++) {
        if (j >= start && j < start + count) {
            qbe_copy_leaf(c, inst->res, j, inst->args[1], j - start);
        } else {
            qbe_copy_leaf(c, inst->res, j, inst->args[0], j);
        }
    }
    return true;
}

/* The `alloc8` of every stack slot and every call result written through a pointer goes at the
 * top of the entry block, so a loop does not grow the stack. Slots are `%v<result>`; result areas
 * of calls are `%r<block>_<instruction>`. */
static uint32_t qbe_slot_bytes(MirLayouts *layouts, MirTy ty) {
    uint32_t size = mir_type_mem(layouts, ty).size;
    if (size < 8) {
        size = 8;
    }
    return (size + 7U) / 8U * 8U;
}

static void qbe_frame_slots(QCx *c) {
    for (uint32_t b = 0; b < c->f->nblocks; b++) {
        const MirBlockData *block = &c->f->blocks[b];
        for (uint32_t k = 0; k < block->ninsts; k++) {
            const MirInst *inst = &block->insts[k];
            if (inst->op == MOP_Slot) {
                ms_buf_printf(c->out, "\t%%v%u =l alloc8 %u\n", inst->res,
                              qbe_slot_bytes(c->layouts, (MirTy)inst->imm.a));
            } else if (inst->op == MOP_Call && inst->res != MIR_NONE &&
                       qbe_leaves(c, c->f->values[inst->res]).len > 1) {
                ms_buf_printf(c->out, "\t%%r%u_%u =l alloc8 %u\n", b, k,
                              qbe_slot_bytes(c->layouts, c->f->values[inst->res]));
            }
        }
    }
}

/* Every leaf of every argument, in order, after the hidden result pointer when there is one. */
static void qbe_call_arguments(QCx *c, const MirInst *inst, const char *result_area) {
    MsBuf *o = c->out;
    bool first = true;
    if (result_area != NULL) {
        ms_buf_printf(o, "l %s", result_area);
        first = false;
    }
    for (uint32_t k = 0; k < inst->nargs; k++) {
        const MirLeafSpan leaves = qbe_leaves(c, c->f->values[inst->args[k]]);
        for (uint32_t j = 0; j < leaves.len; j++) {
            ms_buf_printf(o, "%s%c ", first ? "" : ", ", qbe_leaf_type(leaves.ptr[j]));
            qbe_name(o, inst->args[k], j);
            first = false;
        }
    }
}

/* A call. A result of more than one leaf comes back through a stack area that the call is given
 * and that is read leaf by leaf afterwards. */
static bool qbe_call(QCx *c, const MirInst *inst, uint32_t block, uint32_t index) {
    const MirFunc *callee = &c->m->funcs[inst->imm.a];
    MsBuf *o = c->out;
    const uint32_t result_leaves =
        inst->res == MIR_NONE ? 0 : qbe_leaves(c, c->f->values[inst->res]).len;
    char area[32] = {0};
    if (result_leaves > 1) {
        (void)snprintf(area, sizeof area, "%%r%u_%u", block, index);
    }
    if (result_leaves == 1) {
        ms_buf_printf(o, "\t%%v%u =%c call ", inst->res, qbe_vty(c, inst->res));
    } else {
        ms_buf_puts(o, "\tcall ");
    }
    qbe_sym(o, ms_name(&c->m->names, callee->name));
    ms_buf_putc(o, '(');
    qbe_call_arguments(c, inst, result_leaves > 1 ? area : NULL);
    ms_buf_puts(o, ")\n");
    if (result_leaves <= 1) {
        return true;
    }
    return qbe_load_leaves(c, inst->res, area);
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

/* The instructions that read and write memory and build records; false when `c->why` is set. */
static bool qbe_memory_inst(QCx *c, const MirInst *inst, bool *handled) {
    *handled = true;
    switch ((MirOp)inst->op) {
    case MOP_Slot: return true; /* allocated at the top of the entry block */
    case MOP_Load: case MOP_Take: return qbe_load(c, inst);
    case MOP_Store: case MOP_Put: return qbe_store(c, inst);
    case MOP_TypeNew: qbe_record_new(c, inst); return true;
    case MOP_TypeGet: return qbe_record_get(c, inst);
    case MOP_TypeSet: return qbe_record_set(c, inst);
    default:
        *handled = false;
        return true;
    }
}

/* Writes instruction `index` of block `block`; false, with the reason in `c->why`, when it is not
 * covered yet. */
static bool qbe_inst(QCx *c, const MirInst *inst, uint32_t block, uint32_t index, uint32_t *part) {
    const char *mnemonic = qbe_binary_mnemonic((MirOp)inst->op);
    if (mnemonic != NULL) {
        ms_buf_printf(c->out, "\t%%v%u =%c %s %%v%u, %%v%u\n", inst->res, qbe_vty(c, inst->res),
                      mnemonic, inst->args[0], inst->args[1]);
        return true;
    }
    if (qbe_unary(c, inst)) {
        return true;
    }
    bool handled = false;
    const bool ok = qbe_memory_inst(c, inst, &handled);
    if (handled) {
        return ok;
    }
    switch (inst->op) {
    case MOP_IConst: case MOP_BConst: case MOP_FConst: qbe_constant(c, inst); return true;
    case MOP_ICmp: case MOP_UICmp: case MOP_FCmp: qbe_compare(c, inst); return true;
    case MOP_Call: return qbe_call(c, inst, block, index);
    case MOP_IAddChk: case MOP_ISubChk: qbe_checked_arith(c, inst, block, part); return true;
    default:
        c->why = mir_op_info[inst->op].name;
        return false;
    }
}

/* `ret`: nothing, the one leaf, or the leaves written through the hidden result pointer. */
static bool qbe_return(QCx *c, MirValue value) {
    const uint32_t leaves = value == MIR_NONE ? 0 : qbe_leaves(c, c->f->values[value]).len;
    if (leaves == 0) {
        ms_buf_puts(c->out, "\tret\n");
        return true;
    }
    if (leaves == 1) {
        ms_buf_printf(c->out, "\tret %%v%u\n", value);
        return true;
    }
    if (!qbe_store_leaves(c, value, "%sret")) {
        return false;
    }
    ms_buf_puts(c->out, "\tret\n");
    return true;
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
        return qbe_return(c, t->value);
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

/* Whether the function's boundary is one the emitter handles: parameters of at most 16 bytes, and
 * layouts that did not fail. */
static bool qbe_types_ok(QCx *c) {
    const MirFunc *f = c->f;
    for (uint32_t k = 0; k < f->nparams; k++) {
        if (mir_type_mem(c->layouts, f->params[k].ty).size > QBE_DIRECT_BYTES) {
            c->why = "parameter of more than 16 bytes";
            return false;
        }
    }
    for (uint32_t k = 0; k < f->nvalues; k++) {
        (void)qbe_leaves(c, f->values[k]);
    }
    if (c->layouts->failed) {
        c->why = "type layout";
        return false;
    }
    return true;
}

/* The edges into block `b` and the label each leaves from, for one block parameter. */
static bool qbe_phi_leaf(QCx *c, uint32_t b, uint32_t index, uint32_t leaf, const uint32_t *last) {
    const MirFunc *f = c->f;
    const MirValue param = f->blocks[b].params[index].value;
    ms_buf_puts(c->out, "\t");
    qbe_name(c->out, param, leaf);
    ms_buf_printf(c->out, " =%c phi", qbe_leaf_type(qbe_leaves(c, f->values[param]).ptr[leaf]));
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
            ms_buf_putc(c->out, ' ');
            qbe_name(c->out, edges[k]->args[index], leaf);
            first = false;
        }
    }
    ms_buf_putc(c->out, '\n');
    return true;
}

/* The phis of block parameter `index` of block `b`: one per leaf. */
static bool qbe_phi(QCx *c, uint32_t b, uint32_t index, const uint32_t *last) {
    const MirValue param = c->f->blocks[b].params[index].value;
    const uint32_t leaves = qbe_leaves(c, c->f->values[param]).len;
    for (uint32_t leaf = 0; leaf < leaves; leaf++) {
        if (!qbe_phi_leaf(c, b, index, leaf, last)) {
            return false;
        }
    }
    return true;
}

static bool qbe_block(QCx *c, uint32_t b, const uint32_t *last) {
    const MirBlockData *block = &c->f->blocks[b];
    ms_buf_printf(c->out, "@b%u\n", b);
    if (b == 0) {
        qbe_frame_slots(c);
    }
    for (uint32_t p = 0; b > 0 && p < block->nparams; p++) {
        if (!qbe_phi(c, b, p, last)) {
            return false;
        }
    }
    uint32_t part = 0;
    for (uint32_t k = 0; k < block->ninsts; k++) {
        if (!qbe_inst(c, &block->insts[k], b, k, &part)) {
            return false;
        }
    }
    return qbe_term(c, &block->term);
}

/* `export function <result> $name(<hidden result pointer>, <leaves of each parameter>) {`. */
static void qbe_header(QCx *c, uint32_t index) {
    const MirFunc *f = c->f;
    MsBuf *o = c->out;
    const bool exported = f->linkage == ML_EXPORT || c->m->entry == index;
    const MirLeafSpan result = qbe_leaves(c, f->ret);
    ms_buf_printf(o, "%sfunction ", exported ? "export " : "");
    if (result.len == 1) {
        ms_buf_printf(o, "%c ", qbe_leaf_type(result.ptr[0]));
    }
    qbe_sym(o, ms_name(&c->m->names, f->name));
    ms_buf_putc(o, '(');
    bool first = true;
    if (result.len > 1) {
        ms_buf_puts(o, "l %sret");
        first = false;
    }
    for (uint32_t k = 0; k < f->nparams; k++) {
        const MirValue param = f->blocks[0].params[k].value;
        const MirLeafSpan leaves = qbe_leaves(c, f->params[k].ty);
        for (uint32_t j = 0; j < leaves.len; j++) {
            ms_buf_printf(o, "%s%c ", first ? "" : ", ", qbe_leaf_type(leaves.ptr[j]));
            qbe_name(o, param, j);
            first = false;
        }
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
    MirLayouts layouts;
    mir_layouts_init(&layouts, m);
    bool ok = true;
    for (uint32_t i = 0; i < m->nfuncs; i++) {
        QCx c = {m, &m->funcs[i], out, &layouts, 0, NULL};
        if (qbe_function(&c, i)) {
            continue;
        }
        const MsStr name = ms_name(&m->names, m->funcs[i].name);
        ms_buf_printf(why, "%.*s: %s\n", (int)name.len, name.ptr, c.why ? c.why : "unsupported");
        ok = false;
    }
    mir_layouts_free(&layouts);
    return ok;
}
