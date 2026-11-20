/* MIR to QBE SSA text (proposals/qbe-calling-convention.md).
 *
 * A MIR value is a run of QBE temporaries, one per leaf (`%v7`, `%v7.1`, ...). Parameters of at
 * most 16 bytes travel as their leaves; a result of more than one leaf is written through a
 * hidden first parameter. QBE has no overflow flags, so a checked add or subtract is the sign test
 * of the wrapped result: it splits the block, and the last piece is the predecessor the
 * successors' phis name. */
#include "ms/emit_qbe.h"
#include "ms_rt/chars.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/mir_analysis.h"
#include "ms/mir_data.h"
#include "ms/mir_layout.h"

/* Values of at most this many bytes are passed as their leaves; larger ones are not supported yet. */
#define QBE_DIRECT_BYTES 16

typedef struct QCx {
    const MirModule *m;
    const MirFunc *f;
    MsBuf *out;
    MirLayouts *layouts; /* borrowed from mir_emit_qbe */
    const MirData *data; /* descriptors, vtables and globals, borrowed from mir_emit_qbe */
    const MirGlue *glue; /* the glue functions, borrowed from mir_emit_qbe */
    bool *framed;        /* per value of `f`: a closure object kept in the frame */
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
        bool plain = ms_ascii_is_ident(ch) || ch == '.';
        if (plain) ms_buf_putc(o, (char)ch);
        else ms_buf_printf(o, ".x%02x", ch);
    }
}

static MsStr qbe_cstr(const char *text) { return (MsStr){text, (uint32_t)strlen(text)}; }


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
    if (leaf == MIR_LEAF_F32) {
        const uint32_t n = c->next++;
        ms_buf_printf(o, "\t%%s%u =s loads %%a%u\n\t", n, address);
        qbe_name(o, dst, index);
        ms_buf_printf(o, " =d exts %%s%u\n", n);
        return;
    }
    ms_buf_puts(o, "\t");
    qbe_name(o, dst, index);
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

static bool qbe_rt_direct(QCx *c, MirTy ty) { return mir_rt_direct(c->m, c->layouts, ty); }

/* The frame slots one runtime call needs: a copy of each argument that does not pass directly,
 * and the result area when the result does not. */
static void qbe_frame_rt_call(QCx *c, const MirInst *inst, uint32_t block, uint32_t index) {
    const MirExtern *def = &c->m->externs[inst->imm.a];
    for (uint32_t k = 0; k < inst->nargs; k++) {
        if (!qbe_rt_direct(c, def->params[k].ty)) {
            ms_buf_printf(c->out, "\t%%p%u_%u_%u =l alloc8 %u\n", block, index, k,
                          qbe_slot_bytes(c->layouts, def->params[k].ty));
        }
    }
    if (!qbe_rt_direct(c, def->ret)) {
        ms_buf_printf(c->out, "\t%%r%u_%u =l alloc8 %u\n", block, index,
                      qbe_slot_bytes(c->layouts, def->ret));
    }
}

/* Whether a value of `ty` crosses a call as the address of a copy, not as its leaves. */
static bool qbe_indirect(QCx *c, MirTy ty) {
    return mir_type_mem(c->layouts, ty).size > QBE_DIRECT_BYTES;
}

/* The frame slots a call of `f` needs: the result area when the result has several leaves, and a
 * copy of each argument that passes by address. */
static void qbe_frame_call(QCx *c, const MirInst *inst, uint32_t block, uint32_t index) {
    if (inst->res != MIR_NONE && qbe_leaves(c, c->f->values[inst->res]).len > 1) {
        ms_buf_printf(c->out, "\t%%r%u_%u =l alloc8 %u\n", block, index,
                      qbe_slot_bytes(c->layouts, c->f->values[inst->res]));
    }
    for (uint32_t k = 0; k < inst->nargs; k++) {
        const MirTy ty = c->f->values[inst->args[k]];
        if (qbe_indirect(c, ty)) {
            ms_buf_printf(c->out, "\t%%x%u_%u_%u =l alloc8 %u\n", block, index, k,
                          qbe_slot_bytes(c->layouts, ty));
        }
    }
}

static void qbe_frame_slots(QCx *c) {
    for (uint32_t b = 0; b < c->f->nblocks; b++) {
        const MirBlockData *block = &c->f->blocks[b];
        for (uint32_t k = 0; k < block->ninsts; k++) {
            const MirInst *inst = &block->insts[k];
            if (inst->op == MOP_Slot) {
                ms_buf_printf(c->out, "\t%%v%u =l alloc8 %u\n", inst->res,
                              qbe_slot_bytes(c->layouts, (MirTy)inst->imm.a));
            } else if (inst->op == MOP_Call || inst->op == MOP_CallInd) {
                qbe_frame_call(c, inst, b, k);
            } else if (inst->op == MOP_CallRt) {
                qbe_frame_rt_call(c, inst, b, k);
            } else if (inst->op == MOP_ClosureNew && c->framed[inst->res]) {
                const MirClosureLayout layout =
                    mir_closure_layout(c->layouts, &c->m->funcs[inst->imm.a]);
                ms_buf_printf(c->out, "\t%%o%u_%u =l alloc8 %u\n", b, k, layout.size);
            }
        }
    }
}

/* Every leaf of every argument, in order, after the hidden result pointer when there is one. */
static bool qbe_call_arguments(QCx *c, const MirInst *inst, const char *result_area, uint32_t block,
                               uint32_t index) {
    MsBuf *o = c->out;
    bool first = true;
    if (result_area != NULL) {
        ms_buf_printf(o, "l %s", result_area);
        first = false;
    }
    for (uint32_t k = 0; k < inst->nargs; k++) {
        const MirLeafSpan leaves = qbe_leaves(c, c->f->values[inst->args[k]]);
        if (qbe_indirect(c, c->f->values[inst->args[k]])) {
            ms_buf_printf(o, "%sl %%x%u_%u_%u", first ? "" : ", ", block, index, k);
            first = false;
            continue;
        }
        for (uint32_t j = 0; j < leaves.len; j++) {
            ms_buf_printf(o, "%s%c ", first ? "" : ", ", qbe_leaf_type(leaves.ptr[j]));
            qbe_name(o, inst->args[k], j);
            first = false;
        }
    }
    return true;
}

/* Writes each argument that passes by address into its frame slot, before the call. */
static bool qbe_spill_arguments(QCx *c, const MirInst *inst, uint32_t block, uint32_t index) {
    char slot[32];
    for (uint32_t k = 0; k < inst->nargs; k++) {
        if (!qbe_indirect(c, c->f->values[inst->args[k]])) {
            continue;
        }
        (void)snprintf(slot, sizeof slot, "%%x%u_%u_%u", block, index, k);
        if (!qbe_store_leaves(c, inst->args[k], slot)) {
            return false;
        }
    }
    return true;
}

/* A call. A result of more than one leaf comes back through a stack area that the call is given
 * and that is read leaf by leaf afterwards. */
static bool qbe_call_to(QCx *c, const MirInst *inst, uint32_t block, uint32_t index, const char *target) {
    MsBuf *o = c->out;
    if (!qbe_spill_arguments(c, inst, block, index)) {
        return false;
    }
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
    if (target != NULL) {
        ms_buf_puts(o, target);
    } else {
        qbe_sym(o, ms_name(&c->m->names, c->m->funcs[inst->imm.a].name));
    }
    ms_buf_putc(o, '(');
    (void)qbe_call_arguments(c, inst, result_leaves > 1 ? area : NULL, block, index);
    ms_buf_puts(o, ")\n");
    if (result_leaves <= 1) {
        return true;
    }
    return qbe_load_leaves(c, inst->res, area);
}

static bool qbe_call(QCx *c, const MirInst *inst, uint32_t block, uint32_t index) {
    return qbe_call_to(c, inst, block, index, NULL);
}

/* ---- static data ---- */

/* The text of the address `to` names: a data symbol, a function, or a runtime symbol. */
static void qbe_ref(const QCx *c, MsBuf *o, MirRef to) {
    if (to.kind == MT_DATA) {
        qbe_sym(o, qbe_cstr(c->data->syms[to.index].name));
    } else if (to.kind == MT_FUNC) {
        qbe_sym(o, ms_name(&c->m->names, c->m->funcs[to.index].name));
    } else {
        qbe_sym(o, qbe_cstr(to.runtime));
    }
}

/* Writes the bytes `[from, to)` of `s` as one `b` field, or a `z` field when they are all zero. */
static void qbe_data_bytes(MsBuf *o, const MirDataSym *s, uint32_t from, uint32_t to) {
    bool zero = true;
    for (uint32_t i = from; zero && s->bytes != NULL && i < to; i++) {
        zero = s->bytes[i] == 0;
    }
    if (zero) {
        ms_buf_printf(o, "z %u", to - from);
        return;
    }
    ms_buf_puts(o, "b");
    for (uint32_t i = from; i < to; i++) {
        ms_buf_printf(o, " %u", s->bytes[i]);
    }
}

/* One symbol: its bytes, with an `l` field at each relocation. The relocations are in offset order. */
static void qbe_data_sym(const QCx *c, const MirDataSym *s) {
    MsBuf *o = c->out;
    ms_buf_puts(o, "data ");
    qbe_sym(o, qbe_cstr(s->name));
    ms_buf_printf(o, " = align %u {", s->align);
    uint32_t at = 0;
    const char *sep = " ";
    for (uint32_t r = 0; r < s->nrelocs; r++) {
        if (s->relocs[r].offset > at) {
            ms_buf_puts(o, sep);
            qbe_data_bytes(o, s, at, s->relocs[r].offset);
            sep = ", ";
        }
        ms_buf_printf(o, "%sl ", sep);
        qbe_ref(c, o, s->relocs[r].to);
        sep = ", ";
        at = s->relocs[r].offset + 8;
    }
    if (at < s->size || s->size == 0) {
        ms_buf_puts(o, sep);
        qbe_data_bytes(o, s, at, s->size);
    }
    ms_buf_puts(o, " }\n");
}

/* `typedesc`, `func.addr`: the address of a descriptor or a function. */
static bool qbe_address_of(QCx *c, const MirInst *inst) {
    MirRef to;
    if (inst->op == MOP_TypeDesc) {
        if (inst->imm.tag != MI_TY) {
            c->why = "typedesc without a type";
            return false;
        }
        to = mir_data_desc(c->data, inst->imm.a);
    } else {
        to = (MirRef){MT_FUNC, inst->imm.a, NULL};
    }
    ms_buf_printf(c->out, "\t%%v%u =l copy ", inst->res);
    qbe_ref(c, c->out, to);
    ms_buf_putc(c->out, '\n');
    return true;
}

/* `global.get`, `global.set`: the leaves of the global's data symbol. */
static bool qbe_global(QCx *c, const MirInst *inst) {
    const uint32_t n = c->next++;
    ms_buf_printf(c->out, "\t%%g%u =l copy ", n);
    qbe_ref(c, c->out, (MirRef){MT_DATA, c->data->globals[inst->imm.a], NULL});
    ms_buf_putc(c->out, '\n');
    char base[24];
    (void)snprintf(base, sizeof base, "%%g%u", n);
    return inst->op == MOP_GlobalGet ? qbe_load_leaves(c, inst->res, base)
                                     : qbe_store_leaves(c, inst->args[0], base);
}

/* ---- runtime calls ---- */

/* Appends one argument of a runtime call: the leaves of `value` when `ty` passes directly, else
 * the address of a stack copy that is written first. `area` names the copy's frame slot. */
static bool qbe_rt_argument(QCx *c, MsBuf *args, MirTy ty, MirValue value, const char *area) {
    const MirLeafSpan leaves = qbe_leaves(c, ty);
    if (!qbe_rt_direct(c, ty)) {
        if (!qbe_store_leaves(c, value, area)) {
            return false;
        }
        ms_buf_printf(args, "%sl %s", args->len > 0 ? ", " : "", area);
        return true;
    }
    for (uint32_t j = 0; j < leaves.len; j++) {
        ms_buf_printf(args, "%s%c ", args->len > 0 ? ", " : "", qbe_leaf_type(leaves.ptr[j]));
        qbe_name(args, value, j);
    }
    return true;
}

/* A call of a runtime function, which follows the C ABI of `ms-rt-abi`: scalars by value,
 * everything else by the address of a copy, and a result that is not a scalar through a trailing
 * output pointer. */
static bool qbe_call_rt(QCx *c, const MirInst *inst, uint32_t block, uint32_t index) {
    const MirExtern *def = &c->m->externs[inst->imm.a];
    MsBuf args = {0};
    char area[40];
    bool ok = true;
    for (uint32_t k = 0; ok && k < inst->nargs; k++) {
        (void)snprintf(area, sizeof area, "%%p%u_%u_%u", block, index, k);
        ok = qbe_rt_argument(c, &args, def->params[k].ty, inst->args[k], area);
    }
    const MirLeafSpan result = qbe_leaves(c, def->ret);
    const bool direct = qbe_rt_direct(c, def->ret);
    if (ok && direct && result.len > 1) {
        c->why = "runtime result of several scalars";
        ok = false;
    }
    if (ok) {
        (void)snprintf(area, sizeof area, "%%r%u_%u", block, index);
        if (!direct) {
            ms_buf_printf(&args, "%sl %s", args.len > 0 ? ", " : "", area);
        }
        if (direct && result.len == 1) {
            ms_buf_printf(c->out, "\t%%v%u =%c call ", inst->res, qbe_leaf_type(result.ptr[0]));
        } else {
            ms_buf_puts(c->out, "\tcall ");
        }
        qbe_sym(c->out, ms_name(&c->m->names, def->name));
        ms_buf_printf(c->out, "(%.*s)\n", (int)args.len, args.data == NULL ? "" : args.data);
        if (!direct && inst->res != MIR_NONE) {
            ok = qbe_load_leaves(c, inst->res, area);
        }
    }
    ms_buf_free(&args);
    return ok;
}

/* Ends the current piece of the block with a branch on the flag `%o<n>s`: the fault `call` (its
 * text, such as `$msrt_fault_int_overflow()`) is a block of its own and the rest of the block
 * continues in a new piece. */
static void qbe_fault_branch(QCx *c, uint32_t n, const char *call, uint32_t block, uint32_t *part) {
    MsBuf *o = c->out;
    (*part)++;
    ms_buf_printf(o, "\tjnz %%o%us, @f%u, ", n, n);
    qbe_label(c, block, *part);
    ms_buf_printf(o, "\n@f%u\n\tcall %s\n\thlt\n", n, call);
    qbe_label(c, block, *part);
    ms_buf_putc(o, '\n');
}

/* Writes `sum = a +/- b` and the flag `%o<n>s`: add overflows when both operands differ in sign
 * from the result; sub when the operands differ in sign and the result differs from the first. */
static void qbe_add_flag(QCx *c, uint32_t n, bool add, MirValue a, MirValue b, const char *sum) {
    MsBuf *o = c->out;
    ms_buf_printf(o, "\t%s =l %s %%v%u, %%v%u\n", sum, add ? "add" : "sub", a, b);
    ms_buf_printf(o, "\t%%o%ua =l xor %%v%u, %s\n", n, a, sum);
    /* add: the second operand against the result; sub: the two operands against each other. */
    if (add) {
        ms_buf_printf(o, "\t%%o%ub =l xor %%v%u, %s\n", n, b, sum);
    } else {
        ms_buf_printf(o, "\t%%o%ub =l xor %%v%u, %%v%u\n", n, a, b);
    }
    ms_buf_printf(o, "\t%%o%uc =l and %%o%ua, %%o%ub\n", n, n, n);
    ms_buf_printf(o, "\t%%o%us =w csltl %%o%uc, 0\n", n, n);
}

/* Writes `prod = a * b` and the flag `%o<n>s`. QBE has no overflow flag and no high multiply, so
 * the product is divided back: it overflowed when `prod / a != b`. A zero or minus-one `a` would
 * trap or lie in the division, so the divisor is replaced by 1 there; `a == 0` never overflows and
 * `a == -1` overflows exactly when `b` is the minimum. All of it is straight-line code. */
static void qbe_mul_flag(QCx *c, uint32_t n, MirValue a, MirValue b, const char *prod) {
    MsBuf *o = c->out;
    ms_buf_printf(o, "\t%s =l mul %%v%u, %%v%u\n", prod, a, b);
    ms_buf_printf(o, "\t%%o%ua =w ceql %%v%u, 0\n", n, a);
    ms_buf_printf(o, "\t%%o%ub =w ceql %%v%u, -1\n", n, a);
    ms_buf_printf(o, "\t%%o%uc =w or %%o%ua, %%o%ub\n", n, n, n);
    ms_buf_printf(o, "\t%%o%ud =l extuw %%o%uc\n", n, n);
    /* divisor = a when `a` is safe, else 1: a - (a - 1) * unsafe */
    ms_buf_printf(o, "\t%%o%ue =l sub %%v%u, 1\n", n, a);
    ms_buf_printf(o, "\t%%o%uf =l mul %%o%ue, %%o%ud\n", n, n, n);
    ms_buf_printf(o, "\t%%o%ug =l sub %%v%u, %%o%uf\n", n, a, n);
    ms_buf_printf(o, "\t%%o%uh =l div %s, %%o%ug\n", n, prod, n);
    ms_buf_printf(o, "\t%%o%ui =w cnel %%o%uh, %%v%u\n", n, n, b);
    ms_buf_printf(o, "\t%%o%uj =w xor %%o%uc, 1\n", n, n);
    ms_buf_printf(o, "\t%%o%uk =w and %%o%ui, %%o%uj\n", n, n, n);
    ms_buf_printf(o, "\t%%o%ul =w ceql %%v%u, -1\n", n, a);
    ms_buf_printf(o, "\t%%o%um =w ceql %%v%u, -9223372036854775808\n", n, b);
    ms_buf_printf(o, "\t%%o%un =w and %%o%ul, %%o%um\n", n, n, n);
    ms_buf_printf(o, "\t%%o%us =w or %%o%uk, %%o%un\n", n, n, n);
}

#define QBE_FAULT_OVERFLOW "$msrt_fault_int_overflow()"

static void qbe_checked_arith(QCx *c, const MirInst *inst, uint32_t block, uint32_t *part) {
    const uint32_t n = c->next++;
    char sum[24];
    (void)snprintf(sum, sizeof sum, "%%v%u", inst->res);
    qbe_add_flag(c, n, inst->op == MOP_IAddChk, inst->args[0], inst->args[1], sum);
    qbe_fault_branch(c, n, QBE_FAULT_OVERFLOW, block, part);
}

static void qbe_checked_mul(QCx *c, const MirInst *inst, uint32_t block, uint32_t *part) {
    const uint32_t n = c->next++;
    char prod[24];
    (void)snprintf(prod, sizeof prod, "%%v%u", inst->res);
    qbe_mul_flag(c, n, inst->args[0], inst->args[1], prod);
    qbe_fault_branch(c, n, QBE_FAULT_OVERFLOW, block, part);
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

/* `inarrow.opt`, `f2i.opt`: the optional is [fits, value]. The value leaf is the integer register
 * itself (or the saturating conversion of the float), which only means something when it fits. */
static bool qbe_opt_convert(QCx *c, const MirInst *inst) {
    MsBuf *o = c->out;
    const uint32_t n = c->next++;
    const MirValue x = inst->args[0];
    if (inst->op == MOP_INarrowOpt) {
        const MirTyData *res = mir_ty_data(c->m, c->f->values[inst->res]);
        int64_t lo, hi;
        mir_narrow_range(c->m, c->f->values[x], res->elem, &lo, &hi);
        ms_buf_printf(o, "\t%%o%ua =w csgel %%v%u, %lld\n\t%%o%ub =w cslel %%v%u, %lld\n", n, x,
                      (long long)lo, n, x, (long long)hi);
        ms_buf_printf(o, "\t%%v%u =w and %%o%ua, %%o%ub\n\t%%v%u.1 =l copy %%v%u\n", inst->res, n, n,
                      inst->res, x);
        return true;
    }
    ms_buf_printf(o, "\t%%o%ua =w cged %%v%u, d_-9223372036854775808\n", n, x);
    ms_buf_printf(o, "\t%%o%ub =w cltd %%v%u, d_9223372036854775808\n", n, x);
    ms_buf_printf(o, "\t%%v%u =w and %%o%ua, %%o%ub\n\t%%v%u.1 =l dtosi %%v%u\n", inst->res, n, n,
                  inst->res, x);
    return true;
}

/* `stack.low`, `stack.near`: whether the stack pointer is below the running segment's limit (plus
 * the headroom). The limit is the word at the end of the stack's region, which is aligned to its
 * size, so one mask of any address in the frame finds it. The frame's address is that of its
 * `%sp` slot. */
static void qbe_stack_check(QCx *c, const MirInst *inst) {
    MsBuf *o = c->out;
    const uint32_t n = c->next++;
    ms_buf_printf(o, "\t%%o%ub =l and %%sp, %lld\n", n, (long long)-MIR_STACK_REGION);
    ms_buf_printf(o, "\t%%o%uc =l add %%o%ub, %lld\n\t%%o%ul =l loadl %%o%uc\n", n, n,
                  (long long)(MIR_STACK_REGION - MIR_STACK_LIMIT_CELL), n, n);
    if (inst->op == MOP_StackNear) {
        ms_buf_printf(o, "\t%%o%ul2 =l add %%o%ul, %lld\n", n, n, (long long)inst->imm.i);
        ms_buf_printf(o, "\t%%v%u =w cultl %%sp, %%o%ul2\n", inst->res, n);
        return;
    }
    ms_buf_printf(o, "\t%%v%u =w cultl %%sp, %%o%ul\n", inst->res, n);
}

/* `opt.is_some`: the flag leaf of an optional held as [flag, value], or a non-null test of one held
 * as a single nullable pointer. */
static void qbe_opt_is_some(QCx *c, const MirInst *inst) {
    const MirValue x = inst->args[0];
    if (qbe_leaves(c, c->f->values[x]).len == 1) {
        ms_buf_printf(c->out, "\t%%v%u =w cnel %%v%u, 0\n", inst->res, x);
    } else {
        ms_buf_printf(c->out, "\t%%v%u =w copy %%v%u\n", inst->res, x);
    }
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

#include "emit_qbe_scalar.inc"
#include "emit_qbe_closure.inc"

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
    const bool scalar_ok = qbe_scalar_inst(c, inst, block, part, &handled);
    if (handled) {
        return scalar_ok;
    }
    const bool closure_ok = qbe_closure_op(c, inst, block, index, &handled);
    if (handled) {
        return closure_ok;
    }
    switch (inst->op) {
    case MOP_IConst: case MOP_BConst: case MOP_FConst: qbe_constant(c, inst); return true;
    case MOP_ICmp: case MOP_UICmp: case MOP_FCmp: qbe_compare(c, inst); return true;
    case MOP_Call: return qbe_call(c, inst, block, index);
    case MOP_CallRt: return qbe_call_rt(c, inst, block, index);
    case MOP_INarrowOpt: case MOP_F2IOpt: return qbe_opt_convert(c, inst);
    case MOP_OptIsSome: qbe_opt_is_some(c, inst); return true;
    case MOP_StackLow: case MOP_StackNear: qbe_stack_check(c, inst); return true;
    case MOP_TypeDesc: case MOP_FuncAddr: return qbe_address_of(c, inst);
    case MOP_GlobalGet: case MOP_GlobalSet: return qbe_global(c, inst);
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

/* The runtime function a `fault` terminator calls, and how many zero words it takes. */
typedef struct QbeFault {
    const char *name;
    uint8_t words;
    MirFault kind;
} QbeFault;

static const QbeFault qbe_faults[] = {
    {"msrt_fault_int_overflow", 0, MF_INT_OVERFLOW}, {"msrt_fault_div_zero", 0, MF_DIV_BY_ZERO},
    {"msrt_index_fault", 2, MF_INDEX_OUT_OF_RANGE},  {"msrt_fault_unwrap_none", 0, MF_NONE_UNWRAP},
    {"msrt_cancelled", 0, MF_CANCELLED},             {"msrt_fault_depth", 0, MF_CALL_DEPTH},
};

static bool qbe_fault_term(QCx *c, const MirTerm *t) {
    MsBuf *o = c->out;
    if (t->fault == MF_UNREACHABLE) {
        ms_buf_puts(o, "\thlt\n");
        return true;
    }
    for (size_t k = 0; k < sizeof qbe_faults / sizeof qbe_faults[0]; k++) {
        if (qbe_faults[k].kind != t->fault) {
            continue;
        }
        ms_buf_printf(o, "\tcall $%s(", qbe_faults[k].name);
        for (uint32_t w = 0; w < qbe_faults[k].words; w++) {
            ms_buf_printf(o, "%sl 0", w == 0 ? "" : ", ");
        }
        ms_buf_puts(o, ")\n\thlt\n");
        return true;
    }
    c->why = "fault with a message";
    return false;
}

/* A `switch`: QBE has none, so the cases are a chain of compares. A target with block arguments
 * would need its phis to name the chain's blocks, which they do not yet. */
static bool qbe_switch(QCx *c, const MirTerm *t, uint32_t block) {
    MsBuf *o = c->out;
    bool args = t->b.nargs > 0;
    for (uint32_t k = 0; k < t->ncases; k++) {
        args = args || t->cases[k].target.nargs > 0;
    }
    if (args) {
        c->why = "switch with block arguments";
        return false;
    }
    for (uint32_t k = 0; k < t->ncases; k++) {
        const uint32_t n = c->next++;
        ms_buf_printf(o, "\t%%s%u =w ceql %%v%u, %lld\n\tjnz %%s%u, @b%u, @s%u_%u\n@s%u_%u\n", n, t->value,
                      (long long)t->cases[k].value, n, t->cases[k].target.block, block, k, block, k);
    }
    ms_buf_printf(o, "\tjmp @b%u\n", t->b.block);
    return true;
}

static bool qbe_term(QCx *c, const MirTerm *t, uint32_t block) {
    switch ((MirTermKind)t->kind) {
    case MT_BR:
        ms_buf_printf(c->out, "\tjmp @b%u\n", t->a.block);
        return true;
    case MT_CONDBR:
        ms_buf_printf(c->out, "\tjnz %%v%u, @b%u, @b%u\n", t->value, t->a.block, t->b.block);
        return true;
    case MT_RET:
        return qbe_return(c, t->value);
    case MT_UNREACHABLE:
        ms_buf_puts(c->out, "\thlt\n");
        return true;
    case MT_FAULT:
        return qbe_fault_term(c, t);
    case MT_SWITCH:
        return qbe_switch(c, t, block);
    }
    return false;
}

/* Whether the function's boundary is one the emitter handles: parameters of at most 16 bytes, and
 * layouts that did not fail. */
static bool qbe_types_ok(QCx *c) {
    const MirFunc *f = c->f;
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

/* The start of the entry block: the frame slots, then the leaves of each parameter that arrived
 * as an address. */
static bool qbe_uses_stack_check(const QCx *c) {
    for (uint32_t b = 0; b < c->f->nblocks; b++) {
        for (uint32_t k = 0; k < c->f->blocks[b].ninsts; k++) {
            const uint8_t op = c->f->blocks[b].insts[k].op;
            if (op == MOP_StackLow || op == MOP_StackNear) {
                return true;
            }
        }
    }
    return false;
}

static bool qbe_entry(QCx *c) {
    qbe_frame_slots(c);
    if (qbe_uses_stack_check(c)) {
        ms_buf_puts(c->out, "\t%sp =l alloc8 8\n");
    }
    for (uint32_t k = 0; k < c->f->nparams; k++) {
        if (!qbe_indirect(c, c->f->params[k].ty)) {
            continue;
        }
        const MirValue param = c->f->blocks[0].params[k].value;
        char from[24];
        (void)snprintf(from, sizeof from, "%%in%u", param);
        if (!qbe_load_leaves(c, param, from)) {
            return false;
        }
    }
    return true;
}

static bool qbe_block(QCx *c, uint32_t b, const uint32_t *last) {
    const MirBlockData *block = &c->f->blocks[b];
    ms_buf_printf(c->out, "@b%u\n", b);
    if (b == 0 && !qbe_entry(c)) {
        return false;
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
    return qbe_term(c, &block->term, b);
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
        if (qbe_indirect(c, f->params[k].ty)) {
            ms_buf_printf(o, "%sl %%in%u", first ? "" : ", ", param);
            first = false;
            continue;
        }
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
static void qbe_last_pieces(const MirModule *m, const MirFunc *f, uint32_t *last) {
    for (uint32_t b = 0; b < f->nblocks; b++) {
        last[b] = 0;
        for (uint32_t k = 0; k < f->blocks[b].ninsts; k++) {
            last[b] += qbe_splits(m, f, &f->blocks[b].insts[k]);
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
    c->framed = calloc(f->nvalues ? f->nvalues : 1, sizeof *c->framed); /* owned, freed below */
    if (c->framed == NULL) {
        free(last);
        c->why = "out of memory";
        return false;
    }
    mir_framed_closures(c->m, f, c->framed);
    qbe_last_pieces(c->m, f, last);
    qbe_header(c, index);
    bool ok = true;
    for (uint32_t b = 0; ok && b < f->nblocks; b++) {
        ok = qbe_block(c, b, last);
    }
    free(last);
    free(c->framed);
    c->framed = NULL;
    if (ok) {
        ms_buf_puts(c->out, "}\n\n");
    }
    return ok;
}

bool mir_emit_qbe(MirModule *m, MsBuf *out, MsBuf *why) {
    MirGlue glue = {0};
    mir_glue_run_and_expand(m, &glue);
    mir_lower_ops(m, &glue);
    MirData data;
    mir_data_build(m, &glue, &data);
    MirLayouts layouts;
    mir_layouts_init(&layouts, m);
    bool ok = true;
    for (uint32_t i = 0; i < data.nsyms; i++) {
        const QCx c = {m, NULL, out, &layouts, &data, &glue, NULL, 0, NULL};
        qbe_data_sym(&c, &data.syms[i]);
    }
    for (uint32_t i = 0; i < m->nfuncs; i++) {
        QCx c = {m, &m->funcs[i], out, &layouts, &data, &glue, NULL, 0, NULL};
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
