/* MIR to LLVM IR text.
 *
 * A MIR value is a run of SSA registers, one per leaf (`%v7`, `%v7.1`, ...). The calling
 * convention is the one `emit_qbe.c` writes, so both backends link against the same runtime:
 * parameters of at most 16 bytes travel as their leaves; a result of more than one leaf is written
 * through a hidden first parameter. Registers hold `i64`, `double` and `i1`; sized integers and
 * Float32 are widened in registers and narrowed only in memory. Checked arithmetic is the
 * `with.overflow` intrinsic, which splits the block: the last piece is the predecessor the
 * successors' phis name. */
#include "ms/emit_llvm.h"
#include "ms_rt/chars.h"

#include <stdio.h>
#include <stdlib.h>

#include "ms/mir_layout.h"

/* Values of at most this many bytes are passed as their leaves; larger ones are not supported yet. */
#define LL_DIRECT_BYTES 16

typedef struct LCx {
    const MirModule *m;
    const MirFunc *f;
    MsBuf *out;
    MirLayouts *layouts; /* borrowed from mir_emit_llvm */
    uint32_t next;       /* counter for generated names */
    const char *why;
} LCx;

/* What LLVM needs to know about each kind of leaf, indexed by `MirLeaf`: the register type, the
 * type in memory, and how a loaded value is widened to its register. */
typedef enum LlWiden { LL_SAME, LL_SEXT, LL_ZEXT, LL_BOOL, LL_FPEXT } LlWiden;

typedef struct LlLeafKind {
    const char *reg;
    const char *mem;
    LlWiden widen;
} LlLeafKind;

static const LlLeafKind ll_leaf_kinds[MIR_LEAF_COUNT] = {
    [MIR_LEAF_I64] = {"i64", "i64", LL_SAME},   [MIR_LEAF_F64] = {"double", "double", LL_SAME},
    [MIR_LEAF_I8] = {"i1", "i8", LL_BOOL},      [MIR_LEAF_N8] = {"i64", "i8", LL_SEXT},
    [MIR_LEAF_N16] = {"i64", "i16", LL_SEXT},   [MIR_LEAF_N32] = {"i64", "i32", LL_SEXT},
    [MIR_LEAF_U8] = {"i64", "i8", LL_ZEXT},     [MIR_LEAF_U16] = {"i64", "i16", LL_ZEXT},
    [MIR_LEAF_U32] = {"i64", "i32", LL_ZEXT},   [MIR_LEAF_F32] = {"double", "float", LL_FPEXT},
};

static const LlLeafKind *ll_leaf_kind(MirLeaf leaf) {
    return &ll_leaf_kinds[leaf < MIR_LEAF_COUNT ? leaf : MIR_LEAF_I64];
}

static const char *ll_leaf_type(MirLeaf leaf) { return ll_leaf_kind(leaf)->reg; }

static MirLeafSpan ll_leaves(const LCx *c, MirTy ty) { return mir_leaves(c->layouts, ty); }

/* The name of leaf `leaf` of value `v`: the first leaf is the bare name. */
static void ll_name(MsBuf *o, MirValue v, uint32_t leaf) {
    if (leaf == 0) {
        ms_buf_printf(o, "%%v%u", v);
    } else {
        ms_buf_printf(o, "%%v%u.%u", v, leaf);
    }
}

/* A function name as an LLVM global: quoted, with the characters LLVM cannot read raw as `\HH`. */
static void ll_sym(MsBuf *o, MsStr n) {
    ms_buf_puts(o, "@\"");
    for (uint32_t k = 0; k < n.len; k++) {
        unsigned char ch = (unsigned char)n.ptr[k];
        if (ch >= 0x20 && ch < 0x7f && ch != '"' && ch != '\\') {
            ms_buf_putc(o, (char)ch);
        } else {
            ms_buf_printf(o, "\\%02X", ch);
        }
    }
    ms_buf_putc(o, '"');
}

static bool ll_checked(MirOp op) { return op == MOP_IAddChk || op == MOP_ISubChk; }

static void ll_label(LCx *c, uint32_t block, uint32_t part) {
    if (part == 0) ms_buf_printf(c->out, "b%u", block);
    else ms_buf_printf(c->out, "b%u.%u", block, part);
}

/* The register type of a one-leaf value; `i64` for anything else (callers never ask). */
static const char *ll_vty(const LCx *c, MirValue v) {
    const MirLeafSpan leaves = ll_leaves(c, c->f->values[v]);
    if (leaves.len != 1) {
        return "i64";
    }
    return ll_leaf_type(leaves.ptr[0]);
}

static const char *ll_cc(MirCc cc, bool is_unsigned, bool is_float) {
    static const char *const signed_names[] = {"eq", "ne", "slt", "sle", "sgt", "sge"};
    static const char *const unsigned_names[] = {"eq", "ne", "ult", "ule", "ugt", "uge"};
    static const char *const float_names[] = {"oeq", "une", "olt", "ole", "ogt", "oge"};
    if (is_float) {
        return float_names[cc];
    }
    if (is_unsigned) {
        return unsigned_names[cc];
    }
    return signed_names[cc];
}

/* Operations that are one LLVM instruction on their two operands, by opcode. `masked` shifts take
 * their amount modulo the width, which LLVM leaves undefined past it. */
typedef struct LlBinary {
    MirOp op;
    const char *mnemonic;
    bool masked;
} LlBinary;

static const LlBinary ll_binary[] = {
    {MOP_IAdd, "add", false}, {MOP_ISub, "sub", false},  {MOP_IMul, "mul", false},
    {MOP_And, "and", false},  {MOP_Or, "or", false},     {MOP_Xor, "xor", false},
    {MOP_Shl, "shl", true},   {MOP_Sshr, "ashr", true},  {MOP_Ushr, "lshr", true},
    {MOP_FAdd, "fadd", false}, {MOP_FSub, "fsub", false}, {MOP_FMul, "fmul", false},
    {MOP_FDiv, "fdiv", false}, {MOP_SDiv, "sdiv", false}, {MOP_SRem, "srem", false},
};

static const LlBinary *ll_find_binary(MirOp op) {
    for (size_t k = 0; k < sizeof ll_binary / sizeof ll_binary[0]; k++) {
        if (ll_binary[k].op == op) {
            return &ll_binary[k];
        }
    }
    return NULL;
}

static void ll_binary_inst(LCx *c, const MirInst *inst, const LlBinary *b) {
    MsBuf *o = c->out;
    const char *ty = ll_vty(c, inst->res);
    if (b->masked) {
        const uint32_t n = c->next++;
        ms_buf_printf(o, "  %%m%u = and %s %%v%u, 63\n", n, ty, inst->args[1]);
        ms_buf_printf(o, "  %%v%u = %s %s %%v%u, %%m%u\n", inst->res, b->mnemonic, ty,
                      inst->args[0], n);
        return;
    }
    ms_buf_printf(o, "  %%v%u = %s %s %%v%u, %%v%u\n", inst->res, b->mnemonic, ty, inst->args[0],
                  inst->args[1]);
}

/* ---- memory and records ---- */

/* Writes the address `base + offset` as a new register and returns its number. */
static uint32_t ll_address(LCx *c, const char *base, uint32_t offset) {
    const uint32_t n = c->next++;
    ms_buf_printf(c->out, "  %%a%u = getelementptr i8, ptr %s, i64 %u\n", n, base, offset);
    return n;
}

/* Loads leaf `leaf` of `dst` from the address register `%a<address>`, widened to its register type. */
static void ll_load_leaf(LCx *c, MirLeaf leaf, MirValue dst, uint32_t index, uint32_t address) {
    MsBuf *o = c->out;
    const LlLeafKind *kind = ll_leaf_kind(leaf);
    if (kind->widen == LL_SAME) {
        ms_buf_puts(o, "  ");
        ll_name(o, dst, index);
        ms_buf_printf(o, " = load %s, ptr %%a%u\n", kind->mem, address);
        return;
    }
    const uint32_t n = c->next++;
    ms_buf_printf(o, "  %%l%u = load %s, ptr %%a%u\n  ", n, kind->mem, address);
    ll_name(o, dst, index);
    switch (kind->widen) {
    case LL_SEXT: ms_buf_printf(o, " = sext %s %%l%u to i64\n", kind->mem, n); break;
    case LL_ZEXT: ms_buf_printf(o, " = zext %s %%l%u to i64\n", kind->mem, n); break;
    case LL_BOOL: ms_buf_printf(o, " = trunc i8 %%l%u to i1\n", n); break;
    default: ms_buf_printf(o, " = fpext float %%l%u to double\n", n); break;
    }
}

/* Stores leaf `leaf` of `src` to the address register `%a<address>`, narrowed to its memory type. */
static void ll_store_leaf(LCx *c, MirLeaf leaf, MirValue src, uint32_t index, uint32_t address) {
    MsBuf *o = c->out;
    const LlLeafKind *kind = ll_leaf_kind(leaf);
    if (kind->widen == LL_SAME) {
        ms_buf_printf(o, "  store %s ", kind->mem);
        ll_name(o, src, index);
        ms_buf_printf(o, ", ptr %%a%u\n", address);
        return;
    }
    const uint32_t n = c->next++;
    ms_buf_printf(o, "  %%t%u = ", n);
    switch (kind->widen) {
    case LL_BOOL: ms_buf_puts(o, "zext i1 "); break;
    case LL_FPEXT: ms_buf_puts(o, "fptrunc double "); break;
    default: ms_buf_printf(o, "trunc i64 "); break;
    }
    ll_name(o, src, index);
    ms_buf_printf(o, " to %s\n  store %s %%t%u, ptr %%a%u\n", kind->mem, kind->mem, n, address);
}

/* Reads (`load`) or writes the leaves of `value` at the address in `base`. */
static bool ll_leaves_at(LCx *c, MirValue value, const char *base, bool load) {
    const MirLeafSpan leaves = ll_leaves(c, c->f->values[value]);
    uint32_t *offsets = calloc((size_t)leaves.len + 1, sizeof *offsets); /* owned, freed below */
    if (offsets == NULL) {
        c->why = "out of memory";
        return false;
    }
    (void)mir_mem_layout(leaves.ptr, leaves.len, offsets);
    for (uint32_t k = 0; k < leaves.len; k++) {
        const uint32_t address = ll_address(c, base, offsets[k]);
        if (load) ll_load_leaf(c, leaves.ptr[k], value, k, address);
        else ll_store_leaf(c, leaves.ptr[k], value, k, address);
    }
    free(offsets);
    return true;
}

/* `load`, `take`: the result's leaves from the pointer in the first operand. */
static bool ll_load(LCx *c, const MirInst *inst) {
    char base[24];
    (void)snprintf(base, sizeof base, "%%v%u", inst->args[0]);
    return ll_leaves_at(c, inst->res, base, true);
}

/* `store`, `put`: the second operand's leaves to the pointer in the first. */
static bool ll_store(LCx *c, const MirInst *inst) {
    char base[24];
    (void)snprintf(base, sizeof base, "%%v%u", inst->args[0]);
    return ll_leaves_at(c, inst->args[1], base, false);
}

/* The leaf range `[start, start + count)` that field `field` of record type `ty` occupies in a
 * value of that type. False when `ty` is not a record held as leaves. */
static bool ll_field_span(LCx *c, MirTy ty, uint32_t field, uint32_t *start, uint32_t *count) {
    const MirTyData *data = mir_ty_data(c->m, ty);
    if (data->kind != MK_TYPE || c->m->type_defs[data->id].indirect) {
        c->why = "record behind a pointer";
        return false;
    }
    const MirTypeDef *def = &c->m->type_defs[data->id];
    *start = 0;
    for (uint32_t k = 0; k < field; k++) {
        *start += ll_leaves(c, def->fields[k].ty).len;
    }
    *count = ll_leaves(c, def->fields[field].ty).len;
    return true;
}

/* Result leaf `out_index` takes the value of leaf `src_index` of `src`. LLVM has no copy: the
 * identity is an `or` with zero, which the optimiser removes. */
static void ll_copy_leaf(LCx *c, MirValue dst, uint32_t out_index, MirValue src, uint32_t src_index) {
    MsBuf *o = c->out;
    const MirLeafSpan leaves = ll_leaves(c, c->f->values[dst]);
    const char *ty = ll_leaf_type(leaves.ptr[out_index]);
    const bool is_float = ty[0] == 'd';
    ms_buf_puts(o, "  ");
    ll_name(o, dst, out_index);
    ms_buf_printf(o, is_float ? " = fadd double " : " = or %s ", ty);
    ll_name(o, src, src_index);
    ms_buf_puts(o, is_float ? ", -0.0\n" : (ty[1] == '1' && ty[2] == '\0' ? ", false\n" : ", 0\n"));
}

/* `type.new`: the leaves of the fields in order. */
static void ll_record_new(LCx *c, const MirInst *inst) {
    uint32_t at = 0;
    for (uint32_t k = 0; k < inst->nargs; k++) {
        const uint32_t count = ll_leaves(c, c->f->values[inst->args[k]]).len;
        for (uint32_t j = 0; j < count; j++) {
            ll_copy_leaf(c, inst->res, at++, inst->args[k], j);
        }
    }
}

/* `type.get`: the leaves of one field. */
static bool ll_record_get(LCx *c, const MirInst *inst) {
    uint32_t start = 0;
    uint32_t count = 0;
    if (!ll_field_span(c, c->f->values[inst->args[0]], inst->imm.b, &start, &count)) {
        return false;
    }
    for (uint32_t j = 0; j < count; j++) {
        ll_copy_leaf(c, inst->res, j, inst->args[0], start + j);
    }
    return true;
}

/* `type.set`: the record with one field's leaves replaced by the second operand's. */
static bool ll_record_set(LCx *c, const MirInst *inst) {
    const uint32_t total = ll_leaves(c, c->f->values[inst->args[0]]).len;
    uint32_t start = 0;
    uint32_t count = 0;
    if (!ll_field_span(c, c->f->values[inst->args[0]], inst->imm.b, &start, &count)) {
        return false;
    }
    for (uint32_t j = 0; j < total; j++) {
        if (j >= start && j < start + count) {
            ll_copy_leaf(c, inst->res, j, inst->args[1], j - start);
        } else {
            ll_copy_leaf(c, inst->res, j, inst->args[0], j);
        }
    }
    return true;
}

/* The `alloca` of every stack slot and every call result written through a pointer goes at the
 * top of the entry block, so a loop does not grow the stack. Slots are `%v<result>`; result areas
 * of calls are `%r<block>_<instruction>`. */
static uint32_t ll_slot_bytes(MirLayouts *layouts, MirTy ty) {
    uint32_t size = mir_type_mem(layouts, ty).size;
    if (size < 8) {
        size = 8;
    }
    return (size + 7U) / 8U * 8U;
}

static void ll_frame_slots(LCx *c) {
    for (uint32_t b = 0; b < c->f->nblocks; b++) {
        const MirBlockData *block = &c->f->blocks[b];
        for (uint32_t k = 0; k < block->ninsts; k++) {
            const MirInst *inst = &block->insts[k];
            if (inst->op == MOP_Slot) {
                ms_buf_printf(c->out, "  %%v%u = alloca [%u x i8], align 8\n", inst->res,
                              ll_slot_bytes(c->layouts, (MirTy)inst->imm.a));
            } else if (inst->op == MOP_Call && inst->res != MIR_NONE &&
                       ll_leaves(c, c->f->values[inst->res]).len > 1) {
                ms_buf_printf(c->out, "  %%r%u_%u = alloca [%u x i8], align 8\n", b, k,
                              ll_slot_bytes(c->layouts, c->f->values[inst->res]));
            }
        }
    }
}

/* Every leaf of every argument, in order, after the hidden result pointer when there is one. */
static void ll_call_arguments(LCx *c, const MirInst *inst, const char *result_area) {
    MsBuf *o = c->out;
    bool first = true;
    if (result_area != NULL) {
        ms_buf_printf(o, "ptr %s", result_area);
        first = false;
    }
    for (uint32_t k = 0; k < inst->nargs; k++) {
        const MirLeafSpan leaves = ll_leaves(c, c->f->values[inst->args[k]]);
        for (uint32_t j = 0; j < leaves.len; j++) {
            ms_buf_printf(o, "%s%s ", first ? "" : ", ", ll_leaf_type(leaves.ptr[j]));
            ll_name(o, inst->args[k], j);
            first = false;
        }
    }
}

/* A call. A result of more than one leaf comes back through a stack area that the call is given
 * and that is read leaf by leaf afterwards. */
static bool ll_call(LCx *c, const MirInst *inst, uint32_t block, uint32_t index) {
    const MirFunc *callee = &c->m->funcs[inst->imm.a];
    MsBuf *o = c->out;
    const uint32_t result_leaves =
        inst->res == MIR_NONE ? 0 : ll_leaves(c, c->f->values[inst->res]).len;
    char area[32] = {0};
    if (result_leaves > 1) {
        (void)snprintf(area, sizeof area, "%%r%u_%u", block, index);
    }
    if (result_leaves == 1) {
        ms_buf_printf(o, "  %%v%u = call %s ", inst->res, ll_vty(c, inst->res));
    } else {
        ms_buf_puts(o, "  call void ");
    }
    ll_sym(o, ms_name(&c->m->names, callee->name));
    ms_buf_putc(o, '(');
    ll_call_arguments(c, inst, result_leaves > 1 ? area : NULL);
    ms_buf_puts(o, ")\n");
    if (result_leaves <= 1) {
        return true;
    }
    return ll_leaves_at(c, inst->res, area, true);
}

/* A checked add or subtract: the `with.overflow` intrinsic. The check ends the current piece of
 * the block: the fault is a block of its own and the rest continues in a new piece. */
static void ll_checked_arith(LCx *c, const MirInst *inst, uint32_t block, uint32_t *part) {
    MsBuf *o = c->out;
    const MirValue *a = inst->args;
    const uint32_t n = c->next++;
    ms_buf_printf(o, "  %%x%u = call { i64, i1 } @llvm.%s.with.overflow.i64(i64 %%v%u, i64 %%v%u)\n", n,
                  inst->op == MOP_IAddChk ? "sadd" : "ssub", a[0], a[1]);
    ms_buf_printf(o, "  %%v%u = extractvalue { i64, i1 } %%x%u, 0\n", inst->res, n);
    ms_buf_printf(o, "  %%o%u = extractvalue { i64, i1 } %%x%u, 1\n", n, n);
    (*part)++;
    ms_buf_printf(o, "  br i1 %%o%u, label %%f%u, label %%", n, n);
    ll_label(c, block, *part);
    ms_buf_printf(o, "\nf%u:\n  call void @msrt_fault_int_overflow()\n  unreachable\n", n);
    ll_label(c, block, *part);
    ms_buf_puts(o, ":\n");
}

static void ll_compare(LCx *c, const MirInst *inst) {
    const bool is_float = inst->op == MOP_FCmp;
    const char *type = is_float ? "double" : ll_vty(c, inst->args[0]);
    ms_buf_printf(c->out, "  %%v%u = %s %s %s %%v%u, %%v%u\n", inst->res, is_float ? "fcmp" : "icmp",
                  ll_cc((MirCc)inst->imm.a, inst->op == MOP_UICmp, is_float), type, inst->args[0],
                  inst->args[1]);
}

/* A constant. The float's bits go through an integer and a cast, so no decimal text can round it. */
static void ll_constant(LCx *c, const MirInst *inst) {
    MsBuf *o = c->out;
    const unsigned id = inst->res;
    switch (inst->op) {
    case MOP_FConst:
        ms_buf_printf(o, "  %%v%u = bitcast i64 %lld to double\n", id, (long long)inst->imm.i);
        return;
    case MOP_BConst:
        ms_buf_printf(o, "  %%v%u = or i1 false, %s\n", id, inst->imm.a ? "true" : "false");
        return;
    default:
        ms_buf_printf(o, "  %%v%u = add %s 0, %lld\n", id, ll_vty(c, inst->res), (long long)inst->imm.i);
        return;
    }
}

/* The one-operand operations and conversions. */
static bool ll_unary(LCx *c, const MirInst *inst) {
    MsBuf *o = c->out;
    switch ((MirOp)inst->op) {
    case MOP_Not:
        ms_buf_printf(o, "  %%v%u = xor %s %%v%u, %s\n", inst->res, ll_vty(c, inst->res), inst->args[0],
                      ll_vty(c, inst->res)[1] == '1' ? "true" : "1");
        return true;
    case MOP_FNeg: ms_buf_printf(o, "  %%v%u = fneg double %%v%u\n", inst->res, inst->args[0]); return true;
    case MOP_I2F: ms_buf_printf(o, "  %%v%u = sitofp i64 %%v%u to double\n", inst->res, inst->args[0]); return true;
    case MOP_B2I: ms_buf_printf(o, "  %%v%u = zext i1 %%v%u to i64\n", inst->res, inst->args[0]); return true;
    default: return false;
    }
}

/* The instructions that read and write memory and build records; false when `c->why` is set. */
static bool ll_memory_inst(LCx *c, const MirInst *inst, bool *handled) {
    *handled = true;
    switch ((MirOp)inst->op) {
    case MOP_Slot: return true; /* allocated at the top of the entry block */
    case MOP_Load: case MOP_Take: return ll_load(c, inst);
    case MOP_Store: case MOP_Put: return ll_store(c, inst);
    case MOP_TypeNew: ll_record_new(c, inst); return true;
    case MOP_TypeGet: return ll_record_get(c, inst);
    case MOP_TypeSet: return ll_record_set(c, inst);
    default:
        *handled = false;
        return true;
    }
}

/* Writes instruction `index` of block `block`; false, with the reason in `c->why`, when it is not
 * covered yet. */
static bool ll_inst(LCx *c, const MirInst *inst, uint32_t block, uint32_t index, uint32_t *part) {
    const LlBinary *binary = ll_find_binary((MirOp)inst->op);
    if (binary != NULL) {
        ll_binary_inst(c, inst, binary);
        return true;
    }
    if (ll_unary(c, inst)) {
        return true;
    }
    bool handled = false;
    const bool ok = ll_memory_inst(c, inst, &handled);
    if (handled) {
        return ok;
    }
    switch (inst->op) {
    case MOP_IConst: case MOP_BConst: case MOP_FConst: ll_constant(c, inst); return true;
    case MOP_ICmp: case MOP_UICmp: case MOP_FCmp: ll_compare(c, inst); return true;
    case MOP_Call: return ll_call(c, inst, block, index);
    case MOP_IAddChk: case MOP_ISubChk: ll_checked_arith(c, inst, block, part); return true;
    default:
        c->why = mir_op_info[inst->op].name;
        return false;
    }
}

/* `ret`: nothing, the one leaf, or the leaves written through the hidden result pointer. */
static bool ll_return(LCx *c, MirValue value) {
    const uint32_t leaves = value == MIR_NONE ? 0 : ll_leaves(c, c->f->values[value]).len;
    if (leaves == 0) {
        ms_buf_puts(c->out, "  ret void\n");
        return true;
    }
    if (leaves == 1) {
        ms_buf_printf(c->out, "  ret %s %%v%u\n", ll_vty(c, value), value);
        return true;
    }
    if (!ll_leaves_at(c, value, "%sret", false)) {
        return false;
    }
    ms_buf_puts(c->out, "  ret void\n");
    return true;
}

static bool ll_term(LCx *c, const MirTerm *t) {
    MsBuf *o = c->out;
    switch ((MirTermKind)t->kind) {
    case MT_BR:
        ms_buf_printf(o, "  br label %%b%u\n", t->a.block);
        return true;
    case MT_CONDBR:
        ms_buf_printf(o, "  br i1 %%v%u, label %%b%u, label %%b%u\n", t->value, t->a.block, t->b.block);
        return true;
    case MT_RET:
        return ll_return(c, t->value);
    case MT_UNREACHABLE:
        ms_buf_puts(o, "  unreachable\n");
        return true;
    case MT_FAULT:
        if (t->fault == MF_INT_OVERFLOW) {
            ms_buf_puts(o, "  call void @msrt_fault_int_overflow()\n  unreachable\n");
            return true;
        }
        c->why = "fault kind";
        return false;
    default:
        c->why = "switch";
        return false;
    }
}

/* Whether the function's boundary is one the emitter handles: parameters of at most 16 bytes,
 * layouts that did not fail, and an entry block that nothing branches to (it cannot hold phis). */
static bool ll_types_ok(LCx *c) {
    const MirFunc *f = c->f;
    for (uint32_t k = 0; k < f->nparams; k++) {
        if (mir_type_mem(c->layouts, f->params[k].ty).size > LL_DIRECT_BYTES) {
            c->why = "parameter of more than 16 bytes";
            return false;
        }
    }
    for (uint32_t k = 0; k < f->nvalues; k++) {
        (void)ll_leaves(c, f->values[k]);
    }
    if (c->layouts->failed) {
        c->why = "type layout";
        return false;
    }
    for (uint32_t b = 0; b < f->nblocks; b++) {
        const MirTerm *t = &f->blocks[b].term;
        const bool br = t->kind == MT_BR || t->kind == MT_CONDBR;
        if (br && (t->a.block == 0 || (t->kind == MT_CONDBR && t->b.block == 0))) {
            c->why = "entry block is a branch target";
            return false;
        }
    }
    return true;
}

/* One phi per leaf of block parameter `index` of block `b`, naming the last piece of each
 * predecessor. */
static bool ll_phi_leaf(LCx *c, uint32_t b, uint32_t index, uint32_t leaf, const uint32_t *last) {
    const MirFunc *f = c->f;
    const MirValue param = f->blocks[b].params[index].value;
    const char *type = ll_leaf_type(ll_leaves(c, f->values[param]).ptr[leaf]);
    ms_buf_puts(c->out, "  ");
    ll_name(c->out, param, leaf);
    ms_buf_printf(c->out, " = phi %s ", type);
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
            ms_buf_printf(c->out, "%s[ ", first ? "" : ", ");
            ll_name(c->out, edges[k]->args[index], leaf);
            ms_buf_puts(c->out, ", %");
            ll_label(c, s, last[s]);
            ms_buf_puts(c->out, " ]");
            first = false;
        }
    }
    ms_buf_putc(c->out, '\n');
    return true;
}

static bool ll_phi(LCx *c, uint32_t b, uint32_t index, const uint32_t *last) {
    const MirValue param = c->f->blocks[b].params[index].value;
    const uint32_t leaves = ll_leaves(c, c->f->values[param]).len;
    for (uint32_t leaf = 0; leaf < leaves; leaf++) {
        if (!ll_phi_leaf(c, b, index, leaf, last)) {
            return false;
        }
    }
    return true;
}

static bool ll_block(LCx *c, uint32_t b, const uint32_t *last) {
    const MirBlockData *block = &c->f->blocks[b];
    ms_buf_printf(c->out, "b%u:\n", b);
    if (b == 0) {
        ll_frame_slots(c);
    }
    for (uint32_t p = 0; b > 0 && p < block->nparams; p++) {
        if (!ll_phi(c, b, p, last)) {
            return false;
        }
    }
    uint32_t part = 0;
    for (uint32_t k = 0; k < block->ninsts; k++) {
        if (!ll_inst(c, &block->insts[k], b, k, &part)) {
            return false;
        }
    }
    return ll_term(c, &block->term);
}

/* `define <result> @name(<hidden result pointer>, <leaves of each parameter>) {`. */
static void ll_header(LCx *c, uint32_t index) {
    const MirFunc *f = c->f;
    MsBuf *o = c->out;
    const bool exported = f->linkage == ML_EXPORT || c->m->entry == index;
    const MirLeafSpan result = ll_leaves(c, f->ret);
    ms_buf_printf(o, "define %s%s ", exported ? "" : "internal ", result.len == 1 ? ll_leaf_type(result.ptr[0]) : "void");
    ll_sym(o, ms_name(&c->m->names, f->name));
    ms_buf_putc(o, '(');
    bool first = true;
    if (result.len > 1) {
        ms_buf_puts(o, "ptr %sret");
        first = false;
    }
    for (uint32_t k = 0; k < f->nparams; k++) {
        const MirValue param = f->blocks[0].params[k].value;
        const MirLeafSpan leaves = ll_leaves(c, f->params[k].ty);
        for (uint32_t j = 0; j < leaves.len; j++) {
            ms_buf_printf(o, "%s%s ", first ? "" : ", ", ll_leaf_type(leaves.ptr[j]));
            ll_name(o, param, j);
            first = false;
        }
    }
    ms_buf_puts(o, ") nounwind {\n");
}

/* Pieces each block splits into: its checked operations each end one, and the last piece is what
 * the successors' phis name. Fills `last` with the count per block. */
static void ll_last_pieces(const MirFunc *f, uint32_t *last) {
    for (uint32_t b = 0; b < f->nblocks; b++) {
        last[b] = 0;
        for (uint32_t k = 0; k < f->blocks[b].ninsts; k++) {
            if (ll_checked((MirOp)f->blocks[b].insts[k].op)) {
                last[b]++;
            }
        }
    }
}

static bool ll_function(LCx *c, uint32_t index) {
    const MirFunc *f = c->f;
    if (!ll_types_ok(c)) {
        return false;
    }
    uint32_t *last = calloc(f->nblocks, sizeof *last); /* owned, freed below */
    if (last == NULL) {
        c->why = "out of memory";
        return false;
    }
    ll_last_pieces(f, last);
    ll_header(c, index);
    bool ok = true;
    for (uint32_t b = 0; ok && b < f->nblocks; b++) {
        ok = ll_block(c, b, last);
    }
    free(last);
    if (ok) {
        ms_buf_puts(c->out, "}\n\n");
    }
    return ok;
}

bool mir_emit_llvm(const MirModule *m, MsBuf *out, MsBuf *why) {
    MirLayouts layouts;
    mir_layouts_init(&layouts, m);
    bool ok = true;
    for (uint32_t i = 0; i < m->nfuncs; i++) {
        LCx c = {m, &m->funcs[i], out, &layouts, 0, NULL};
        if (ll_function(&c, i)) {
            continue;
        }
        const MsStr name = ms_name(&m->names, m->funcs[i].name);
        ms_buf_printf(why, "%.*s: %s\n", (int)name.len, name.ptr, c.why ? c.why : "unsupported");
        ok = false;
    }
    mir_layouts_free(&layouts);
    ms_buf_puts(out, "declare void @msrt_fault_int_overflow() cold noreturn nounwind\n");
    ms_buf_puts(out, "declare { i64, i1 } @llvm.sadd.with.overflow.i64(i64, i64)\n");
    ms_buf_puts(out, "declare { i64, i1 } @llvm.ssub.with.overflow.i64(i64, i64)\n");
    return ok;
}
