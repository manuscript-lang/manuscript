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
#include <string.h>

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
    const MirData *data; /* the module's static data; NULL when it has none */
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

/* How many checks an operation makes, each of which ends a piece of its block. */
static uint32_t ll_pieces(MirOp op) {
    switch (op) {
    case MOP_IAddChk: case MOP_ISubChk: case MOP_IMulChk: case MOP_INegChk:
    case MOP_UAddChk: case MOP_USubChk: case MOP_UMulChk: case MOP_SRemChk:
    case MOP_NarrowChk: case MOP_IntOverflowIf:
        return 1;
    case MOP_SDivChk:
        return 2;
    default:
        return 0;
    }
}

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
    const char *mnemonic;
    MirOp op;
    bool masked;
} LlBinary;

static const LlBinary ll_binary[] = {
    {"add", MOP_IAdd, false}, {"sub", MOP_ISub, false},  {"mul", MOP_IMul, false},
    {"and", MOP_And, false},  {"or", MOP_Or, false},     {"xor", MOP_Xor, false},
    {"shl", MOP_Shl, true},   {"ashr", MOP_Sshr, true},  {"lshr", MOP_Ushr, true},
    {"fadd", MOP_FAdd, false}, {"fsub", MOP_FSub, false}, {"fmul", MOP_FMul, false},
    {"fdiv", MOP_FDiv, false}, {"sdiv", MOP_SDiv, false}, {"srem", MOP_SRem, false},
};

static const LlBinary *ll_find_binary(MirOp op) {
    for (size_t k = 0; k < sizeof ll_binary / sizeof ll_binary[0]; k++) {
        if (ll_binary[k].op == op) {
            return &ll_binary[k];
        }
    }
    return NULL;
}

/* Rotates are funnel shifts of a value with itself; the high half of an unsigned product is a
 * 128-bit multiply. Neither has a one-instruction form. */
static bool ll_wide_inst(LCx *c, const MirInst *inst) {
    MsBuf *o = c->out;
    const MirValue *a = inst->args;
    const uint32_t n = c->next++;
    switch ((MirOp)inst->op) {
    case MOP_Rotl: case MOP_Rotr:
        ms_buf_printf(o, "  %%v%u = call i64 @llvm.%s.i64(i64 %%v%u, i64 %%v%u, i64 %%v%u)\n", inst->res,
                      inst->op == MOP_Rotl ? "fshl" : "fshr", a[0], a[0], a[1]);
        return true;
    case MOP_UMulHi:
        ms_buf_printf(o, "  %%w%ua = zext i64 %%v%u to i128\n  %%w%ub = zext i64 %%v%u to i128\n", n, a[0], n, a[1]);
        ms_buf_printf(o, "  %%w%uc = mul i128 %%w%ua, %%w%ub\n  %%w%ud = lshr i128 %%w%uc, 64\n", n, n, n, n, n);
        ms_buf_printf(o, "  %%v%u = trunc i128 %%w%ud to i64\n", inst->res, n);
        return true;
    case MOP_Select:
        ms_buf_printf(o, "  %%v%u = select i1 %%v%u, %s %%v%u, %s %%v%u\n", inst->res, a[0],
                      ll_vty(c, inst->res), a[1], ll_vty(c, inst->res), a[2]);
        return true;
    default:
        return false;
    }
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

/* Pointers are `i64` registers like any word, so an address is converted where memory is touched:
 * writes `%pN = inttoptr` of `value` and the name `%pN` to `name`. LLVM folds the round trip of a
 * stack slot back into the alloca. */
static void ll_pointer(LCx *c, MirValue value, char *name, size_t cap) {
    const uint32_t n = c->next++;
    ms_buf_printf(c->out, "  %%p%u = inttoptr i64 %%v%u to ptr\n", n, value);
    (void)snprintf(name, cap, "%%p%u", n);
}

/* ---- static data ---- */

static void ll_data_name(MsBuf *o, const char *name) {
    ll_sym(o, (MsStr){name, (uint32_t)strlen(name)});
}

/* The address a relocation or a data reference names, as an LLVM constant. */
static void ll_ref(const LCx *c, MsBuf *o, MirRef ref) {
    if (ref.kind == MT_DATA) {
        ll_data_name(o, c->data->syms[ref.index].name);
    } else if (ref.kind == MT_FUNC) {
        ll_sym(o, ms_name(&c->m->names, c->m->funcs[ref.index].name));
    } else {
        ll_data_name(o, ref.runtime);
    }
}

/* `typedesc`: the address of the descriptor for the type, as a word. */
static bool ll_typedesc(LCx *c, const MirInst *inst) {
    if (c->data == NULL) {
        c->why = "no static data";
        return false;
    }
    const MirRef ref = mir_data_desc(c->data, (MirTy)inst->imm.a);
    if (ref.kind == MT_RUNTIME && ref.runtime == NULL) {
        c->why = "typedesc of a type the data table did not see";
        return false;
    }
    ms_buf_printf(c->out, "  %%v%u = ptrtoint ptr ", inst->res);
    ll_ref(c, c->out, ref);
    ms_buf_puts(c->out, " to i64\n");
    return true;
}

/* `global.get`, `global.set`: the leaves of the value at the global's address. */
static bool ll_global(LCx *c, const MirInst *inst) {
    if (c->data == NULL) {
        c->why = "no static data";
        return false;
    }
    char base[96];
    MsBuf name = {0};
    ll_data_name(&name, c->data->syms[c->data->globals[inst->imm.a]].name);
    (void)snprintf(base, sizeof base, "%.*s", (int)name.len, name.data);
    ms_buf_free(&name);
    const bool get = inst->op == MOP_GlobalGet;
    return ll_leaves_at(c, get ? inst->res : inst->args[0], base, get);
}

/* `load`, `take`: the result's leaves from the pointer in the first operand. */
static bool ll_load(LCx *c, const MirInst *inst) {
    char base[24];
    ll_pointer(c, inst->args[0], base, sizeof base);
    return ll_leaves_at(c, inst->res, base, true);
}

/* `store`, `put`: the second operand's leaves to the pointer in the first. */
static bool ll_store(LCx *c, const MirInst *inst) {
    char base[24];
    ll_pointer(c, inst->args[0], base, sizeof base);
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
    const char *identity = ", 0\n";
    const char *op = " = or ";
    if (ty[0] == 'd') {
        op = " = fadd ";
        identity = ", -0.0\n";
    } else if (ty[1] == '1') {
        identity = ", false\n";
    }
    ms_buf_puts(o, "  ");
    ll_name(o, dst, out_index);
    ms_buf_printf(o, "%s%s ", op, ty);
    ll_name(o, src, src_index);
    ms_buf_puts(o, identity);
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

static bool ll_rt_direct(LCx *c, MirTy ty) { return mir_rt_direct(c->m, c->layouts, ty); }

/* The frame slots one runtime call needs: a copy of each argument that does not pass directly,
 * and the result area when the result does not. */
static void ll_frame_rt_call(LCx *c, const MirInst *inst, uint32_t block, uint32_t index) {
    const MirExtern *def = &c->m->externs[inst->imm.a];
    for (uint32_t k = 0; k < inst->nargs; k++) {
        if (!ll_rt_direct(c, def->params[k].ty)) {
            ms_buf_printf(c->out, "  %%p%u_%u_%u = alloca [%u x i8], align 8\n", block, index, k,
                          ll_slot_bytes(c->layouts, def->params[k].ty));
        }
    }
    if (!ll_rt_direct(c, def->ret)) {
        ms_buf_printf(c->out, "  %%r%u_%u = alloca [%u x i8], align 8\n", block, index,
                      ll_slot_bytes(c->layouts, def->ret));
    }
}

static void ll_frame_slots(LCx *c) {
    for (uint32_t b = 0; b < c->f->nblocks; b++) {
        const MirBlockData *block = &c->f->blocks[b];
        for (uint32_t k = 0; k < block->ninsts; k++) {
            const MirInst *inst = &block->insts[k];
            if (inst->op == MOP_Slot) {
                ms_buf_printf(c->out, "  %%s%u = alloca [%u x i8], align 8\n  %%v%u = ptrtoint ptr %%s%u to i64\n",
                              inst->res, ll_slot_bytes(c->layouts, (MirTy)inst->imm.a), inst->res, inst->res);
            } else if (inst->op == MOP_Call && inst->res != MIR_NONE &&
                       ll_leaves(c, c->f->values[inst->res]).len > 1) {
                ms_buf_printf(c->out, "  %%r%u_%u = alloca [%u x i8], align 8\n", b, k,
                              ll_slot_bytes(c->layouts, c->f->values[inst->res]));
            } else if (inst->op == MOP_CallRt) {
                ll_frame_rt_call(c, inst, b, k);
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

/* Appends one argument of a runtime call to `args`: the leaves of `value` when `ty` passes
 * directly, else the address of a stack copy that is written first. `area` names the copy. */
static bool ll_rt_argument(LCx *c, MsBuf *args, MirTy ty, MirValue value, const char *area) {
    if (!ll_rt_direct(c, ty)) {
        if (!ll_leaves_at(c, value, area, false)) {
            return false;
        }
        ms_buf_printf(args, "%sptr %s", args->len > 0 ? ", " : "", area);
        return true;
    }
    const MirLeafSpan leaves = ll_leaves(c, ty);
    for (uint32_t j = 0; j < leaves.len; j++) {
        ms_buf_printf(args, "%s%s ", args->len > 0 ? ", " : "", ll_leaf_type(leaves.ptr[j]));
        ll_name(args, value, j);
    }
    return true;
}

/* A call of a runtime function, which follows the C ABI of the runtime: scalars by value,
 * everything else by the address of a copy, and a result that is not a scalar through a trailing
 * output pointer. */
static bool ll_call_rt(LCx *c, const MirInst *inst, uint32_t block, uint32_t index) {
    const MirExtern *def = &c->m->externs[inst->imm.a];
    MsBuf args = {0};
    char area[40];
    bool ok = true;
    for (uint32_t k = 0; ok && k < inst->nargs; k++) {
        (void)snprintf(area, sizeof area, "%%p%u_%u_%u", block, index, k);
        ok = ll_rt_argument(c, &args, def->params[k].ty, inst->args[k], area);
    }
    const MirLeafSpan result = ll_leaves(c, def->ret);
    const bool direct = ll_rt_direct(c, def->ret);
    if (ok && direct && result.len > 1) {
        c->why = "runtime result of several scalars";
        ok = false;
    }
    if (ok) {
        (void)snprintf(area, sizeof area, "%%r%u_%u", block, index);
        if (!direct) {
            ms_buf_printf(&args, "%sptr %s", args.len > 0 ? ", " : "", area);
        }
        if (direct && result.len == 1) {
            ms_buf_printf(c->out, "  %%v%u = call %s ", inst->res, ll_leaf_type(result.ptr[0]));
        } else {
            ms_buf_puts(c->out, "  call void ");
        }
        ll_sym(c->out, ms_name(&c->m->names, def->name));
        ms_buf_printf(c->out, "(%.*s)\n", (int)args.len, args.data == NULL ? "" : args.data);
        if (!direct && inst->res != MIR_NONE) {
            ok = ll_leaves_at(c, inst->res, area, true);
        }
    }
    ms_buf_free(&args);
    return ok;
}

/* Ends the current piece of a block with a check: when `cond` holds the program calls the fault
 * function `fault` (with `nargs` leaves of `args`, all `i64`) and does not return; otherwise it
 * continues in a new piece. */
static void ll_fault_if(LCx *c, uint32_t block, uint32_t *part, const char *cond, const char *fault,
                        const MirValue *args, uint32_t nargs) {
    MsBuf *o = c->out;
    const uint32_t n = c->next++;
    (*part)++;
    ms_buf_printf(o, "  br i1 %s, label %%f%u, label %%", cond, n);
    ll_label(c, block, *part);
    ms_buf_printf(o, "\nf%u:\n  call void @%s(", n, fault);
    for (uint32_t k = 0; k < nargs; k++) {
        ms_buf_printf(o, "%si64 %%v%u", k == 0 ? "" : ", ", args[k]);
    }
    ms_buf_puts(o, ")\n  unreachable\n");
    ll_label(c, block, *part);
    ms_buf_puts(o, ":\n");
}

/* The operations that are an `llvm.<prefix>.with.overflow` intrinsic: the result is the first
 * member of the pair and the second says whether it overflowed. Signed overflow faults as
 * overflow, unsigned as out of range. */
typedef struct LlOverflow {
    const char *intrinsic;
    const char *fault;
    MirOp op;
} LlOverflow;

static const LlOverflow ll_overflow[] = {
    {"sadd", "msrt_fault_int_overflow", MOP_IAddChk}, {"ssub", "msrt_fault_int_overflow", MOP_ISubChk},
    {"smul", "msrt_fault_int_overflow", MOP_IMulChk}, {"ssub", "msrt_fault_int_overflow", MOP_INegChk},
    {"uadd", "msrt_fault_int_range", MOP_UAddChk},    {"usub", "msrt_fault_int_range", MOP_USubChk},
    {"umul", "msrt_fault_int_range", MOP_UMulChk},
};

static const LlOverflow *ll_find_overflow(MirOp op) {
    for (size_t k = 0; k < sizeof ll_overflow / sizeof ll_overflow[0]; k++) {
        if (ll_overflow[k].op == op) {
            return &ll_overflow[k];
        }
    }
    return NULL;
}

/* A checked add, subtract, multiply or negation. */
static void ll_checked_arith(LCx *c, const MirInst *inst, const LlOverflow *kind, uint32_t block,
                             uint32_t *part) {
    MsBuf *o = c->out;
    const MirValue *a = inst->args;
    const uint32_t n = c->next++;
    const bool negate = inst->op == MOP_INegChk;
    ms_buf_printf(o, "  %%x%u = call { i64, i1 } @llvm.%s.with.overflow.i64(i64 ", n, kind->intrinsic);
    if (negate) ms_buf_puts(o, "0, i64 ");
    else ms_buf_printf(o, "%%v%u, i64 ", a[0]);
    ms_buf_printf(o, "%%v%u)\n", negate ? a[0] : a[1]);
    ms_buf_printf(o, "  %%v%u = extractvalue { i64, i1 } %%x%u, 0\n", inst->res, n);
    char flag[24];
    (void)snprintf(flag, sizeof flag, "%%o%u", n);
    ms_buf_printf(o, "  %s = extractvalue { i64, i1 } %%x%u, 1\n", flag, n);
    ll_fault_if(c, block, part, flag, kind->fault, NULL, 0);
}

/* `sdiv.chk` faults on a zero divisor and on the one quotient that does not fit, `Int.min / -1`;
 * `srem.chk` faults on a zero divisor and answers 0 for a divisor of -1 (the remainder is
 * defined there, but the instruction is not). */
static void ll_checked_div(LCx *c, const MirInst *inst, uint32_t block, uint32_t *part) {
    MsBuf *o = c->out;
    const MirValue *a = inst->args;
    const bool div = inst->op == MOP_SDivChk;
    const uint32_t n = c->next++;
    ms_buf_printf(o, "  %%z%u = icmp eq i64 %%v%u, 0\n", n, a[1]);
    char zero[24];
    (void)snprintf(zero, sizeof zero, "%%z%u", n);
    ll_fault_if(c, block, part, zero, div ? "msrt_fault_div_zero" : "msrt_fault_rem_zero", NULL, 0);
    if (div) {
        ms_buf_printf(o, "  %%m%u = icmp eq i64 %%v%u, -1\n  %%n%u = icmp eq i64 %%v%u, %lld\n", n, a[1], n,
                      a[0], (long long)INT64_MIN);
        ms_buf_printf(o, "  %%b%u = and i1 %%m%u, %%n%u\n", n, n, n);
        char both[24];
        (void)snprintf(both, sizeof both, "%%b%u", n);
        ll_fault_if(c, block, part, both, "msrt_fault_div_overflow", a, 2);
        ms_buf_printf(o, "  %%v%u = sdiv i64 %%v%u, %%v%u\n", inst->res, a[0], a[1]);
        return;
    }
    ms_buf_printf(o, "  %%m%u = icmp eq i64 %%v%u, -1\n  %%d%u = select i1 %%m%u, i64 1, i64 %%v%u\n", n,
                  a[1], n, n, a[1]);
    ms_buf_printf(o, "  %%r%u = srem i64 %%v%u, %%d%u\n  %%v%u = select i1 %%m%u, i64 0, i64 %%r%u\n", n,
                  a[0], n, inst->res, n, n);
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

static const char *ll_float_function(uint8_t op) {
    switch (op) {
    case MOP_FSqrt: return "sqrt";
    case MOP_FAbs: return "fabs";
    case MOP_FFloor: return "floor";
    case MOP_FCeil: return "ceil";
    default: return "trunc";
    }
}

/* Rounds the double in `%v<src>` to the nearest float and back, into `%v<res>`: a Float32 lives in a
 * double register. */
static void ll_f32_round(LCx *c, MirValue res, const char *src) {
    const uint32_t n = c->next++;
    ms_buf_printf(c->out, "  %%r%u = fptrunc double %s to float\n  %%v%u = fpext float %%r%u to double\n", n, src,
                  res, n);
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
    case MOP_I2F:
        if (ll_leaves(c, c->f->values[inst->res]).ptr[0] == MIR_LEAF_F32) {
            const uint32_t n = c->next++;
            ms_buf_printf(o, "  %%i%u = sitofp i64 %%v%u to double\n", n, inst->args[0]);
            char src[24];
            (void)snprintf(src, sizeof src, "%%i%u", n);
            ll_f32_round(c, inst->res, src);
            return true;
        }
        ms_buf_printf(o, "  %%v%u = sitofp i64 %%v%u to double\n", inst->res, inst->args[0]);
        return true;
    case MOP_B2I: ms_buf_printf(o, "  %%v%u = zext i1 %%v%u to i64\n", inst->res, inst->args[0]); return true;
    case MOP_INeg: ms_buf_printf(o, "  %%v%u = sub i64 0, %%v%u\n", inst->res, inst->args[0]); return true;
    case MOP_Clz: case MOP_Ctz:
        ms_buf_printf(o, "  %%v%u = call i64 @llvm.%s.i64(i64 %%v%u, i1 false)\n", inst->res,
                      inst->op == MOP_Clz ? "ctlz" : "cttz", inst->args[0]);
        return true;
    case MOP_Popcnt: ms_buf_printf(o, "  %%v%u = call i64 @llvm.ctpop.i64(i64 %%v%u)\n", inst->res, inst->args[0]); return true;
    case MOP_FSqrt: case MOP_FAbs: case MOP_FFloor: case MOP_FCeil: case MOP_FTrunc:
        ms_buf_printf(o, "  %%v%u = call double @llvm.%s.f64(double %%v%u)\n", inst->res,
                      ll_float_function(inst->op), inst->args[0]);
        return true;
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
    case MOP_TypeDesc: return ll_typedesc(c, inst);
    case MOP_GlobalGet: case MOP_GlobalSet: return ll_global(c, inst);
    case MOP_TypeNew: ll_record_new(c, inst); return true;
    case MOP_TypeGet: return ll_record_get(c, inst);
    case MOP_TypeSet: return ll_record_set(c, inst);
    default:
        *handled = false;
        return true;
    }
}

/* ---- conversions and checks on sizes ---- */

/* The width and signedness of the sized integer kinds `narrow.chk` checks against. */
typedef struct LlNarrow {
    MirTyKind kind;
    uint8_t bits;
    bool sign;
} LlNarrow;

static const LlNarrow ll_narrows[] = {
    {MK_INT8, 8, true},   {MK_INT16, 16, true},   {MK_INT32, 32, true},
    {MK_UINT8, 8, false}, {MK_UINT16, 16, false}, {MK_UINT32, 32, false},
};

/* `narrow.chk`: faults unless the value survives a round trip through the result's width. Other
 * result types hold every `Int`. */
static void ll_narrow_chk(LCx *c, const MirInst *inst, uint32_t block, uint32_t *part) {
    const MirTyKind kind = mir_ty_data(c->m, c->f->values[inst->res])->kind;
    for (size_t k = 0; k < sizeof ll_narrows / sizeof ll_narrows[0]; k++) {
        if (ll_narrows[k].kind != kind) {
            continue;
        }
        const uint32_t n = c->next++;
        const LlNarrow *w = &ll_narrows[k];
        ms_buf_printf(c->out, "  %%n%u = trunc i64 %%v%u to i%u\n  %%e%u = %s i%u %%n%u to i64\n  %%z%u = icmp ne i64 %%e%u, %%v%u\n",
                      n, inst->args[0], w->bits, n, w->sign ? "sext" : "zext", w->bits, n, n, n, inst->args[0]);
        char flag[24];
        (void)snprintf(flag, sizeof flag, "%%z%u", n);
        ll_fault_if(c, block, part, flag, "msrt_fault_int_overflow", NULL, 0);
        break;
    }
    ll_copy_leaf(c, inst->res, 0, inst->args[0], 0);
}

/* `iadd.overflow`, `imul.overflow`: whether the signed operation overflows. */
static void ll_overflow_flag(LCx *c, const MirInst *inst) {
    const char *op = inst->op == MOP_IAddOverflow ? "sadd" : "smul";
    const uint32_t n = c->next++;
    ms_buf_printf(c->out, "  %%x%u = call { i64, i1 } @llvm.%s.with.overflow.i64(i64 %%v%u, i64 %%v%u)\n  %%v%u = extractvalue { i64, i1 } %%x%u, 1\n",
                  n, op, inst->args[0], inst->args[1], inst->res, n);
}

/* `conv`, `f32.round`, `narrow.chk`, the overflow flags and `int_overflow.if`; false when `inst`
 * is none of them. */
static bool ll_convert(LCx *c, const MirInst *inst, uint32_t block, uint32_t *part) {
    char src[24];
    switch ((MirOp)inst->op) {
    case MOP_F32Round:
        (void)snprintf(src, sizeof src, "%%v%u", inst->args[0]);
        ll_f32_round(c, inst->res, src);
        return true;
    case MOP_Conv: {
        const MirLeafSpan out = ll_leaves(c, c->f->values[inst->res]);
        const bool round = out.len == 1 && out.ptr[0] == MIR_LEAF_F32 &&
                           ll_leaves(c, c->f->values[inst->args[0]]).ptr[0] == MIR_LEAF_F64;
        (void)snprintf(src, sizeof src, "%%v%u", inst->args[0]);
        if (round) {
            ll_f32_round(c, inst->res, src);
            return true;
        }
        for (uint32_t k = 0; k < out.len; k++) {
            ll_copy_leaf(c, inst->res, k, inst->args[0], k);
        }
        return true;
    }
    case MOP_NarrowChk:
        ll_narrow_chk(c, inst, block, part);
        return true;
    case MOP_IAddOverflow: case MOP_IMulOverflow:
        ll_overflow_flag(c, inst);
        return true;
    case MOP_IntOverflowIf:
        (void)snprintf(src, sizeof src, "%%v%u", inst->args[0]);
        ll_fault_if(c, block, part, src, "msrt_fault_int_overflow", NULL, 0);
        return true;
    default:
        return false;
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
    if (ll_wide_inst(c, inst)) {
        return true;
    }
    const LlOverflow *overflow = ll_find_overflow((MirOp)inst->op);
    if (overflow != NULL) {
        ll_checked_arith(c, inst, overflow, block, part);
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
    case MOP_CallRt: return ll_call_rt(c, inst, block, index);
    case MOP_SDivChk: case MOP_SRemChk: ll_checked_div(c, inst, block, part); return true;
    default:
        if (ll_convert(c, inst, block, part)) {
            return true;
        }
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

/* The runtime function a `fault` terminator calls, and how many zero words it takes. */
typedef struct LlFault {
    const char *name;
    uint32_t words;
    MirFault kind;
} LlFault;

static const LlFault ll_faults[] = {
    {"msrt_fault_int_overflow", 0, MF_INT_OVERFLOW}, {"msrt_fault_div_zero", 0, MF_DIV_BY_ZERO},
    {"msrt_index_fault", 2, MF_INDEX_OUT_OF_RANGE},  {"msrt_fault_unwrap_none", 0, MF_NONE_UNWRAP},
    {"msrt_cancelled", 0, MF_CANCELLED},             {"msrt_fault_depth", 0, MF_CALL_DEPTH},
};

/* A `switch`: the cases by value, the default last. Several cases may share a target. */
static void ll_switch(LCx *c, const MirTerm *t) {
    MsBuf *o = c->out;
    ms_buf_printf(o, "  switch i64 %%v%u, label %%b%u [", t->value, t->b.block);
    for (uint32_t k = 0; k < t->ncases; k++) {
        ms_buf_printf(o, "\n    i64 %lld, label %%b%u", (long long)t->cases[k].value, t->cases[k].target.block);
    }
    ms_buf_puts(o, "\n  ]\n");
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
    case MT_SWITCH:
        ll_switch(c, t);
        return true;
    case MT_RET:
        return ll_return(c, t->value);
    case MT_UNREACHABLE:
        ms_buf_puts(o, "  unreachable\n");
        return true;
    case MT_FAULT:
        if (t->fault == MF_UNREACHABLE) {
            ms_buf_puts(o, "  unreachable\n");
            return true;
        }
        for (size_t k = 0; k < sizeof ll_faults / sizeof ll_faults[0]; k++) {
            if (ll_faults[k].kind != t->fault) {
                continue;
            }
            ms_buf_printf(o, "  call void @%s(", ll_faults[k].name);
            for (uint32_t w = 0; w < ll_faults[k].words; w++) {
                ms_buf_printf(o, "%si64 0", w == 0 ? "" : ", ");
            }
            ms_buf_puts(o, ")\n  unreachable\n");
            return true;
        }
        c->why = "fault with a message";
        return false;
    default:
        c->why = "terminator";
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

/* The edges leaving a block, in a fixed order: a branch has one, a conditional two, a switch its
 * cases and then its default. */
static uint32_t ll_edge_count(const MirTerm *t) {
    switch ((MirTermKind)t->kind) {
    case MT_BR: return 1;
    case MT_CONDBR: return 2;
    case MT_SWITCH: return t->ncases + 1;
    default: return 0;
    }
}

static const MirTarget *ll_edge(const MirTerm *t, uint32_t k) {
    if (t->kind == MT_SWITCH && k < t->ncases) {
        return &t->cases[k].target;
    }
    return k == 0 && t->kind != MT_SWITCH ? &t->a : &t->b;
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
        uint32_t reached = 0;
        const MirTarget *edge = NULL;
        for (uint32_t k = 0; k < ll_edge_count(t); k++) {
            const MirTarget *e = ll_edge(t, k);
            if (e->block == b) {
                reached++;
                edge = e;
            }
        }
        if (reached > 1 && edge->nargs > 0) {
            c->why = "one block reaches a target twice with arguments";
            return false;
        }
        if (edge == NULL) {
            continue;
        }
        ms_buf_printf(c->out, "%s[ ", first ? "" : ", ");
        ll_name(c->out, edge->args[index], leaf);
        ms_buf_puts(c->out, ", %");
        ll_label(c, s, last[s]);
        ms_buf_puts(c->out, " ]");
        first = false;
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
            last[b] += ll_pieces((MirOp)f->blocks[b].insts[k].op);
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

/* One `declare` per runtime function the module lists, in the signature `ll_call_rt` calls it with.
 * A function that never returns says so, so the code after a call of it is unreachable. */
static void ll_declare_externs(LCx *c) {
    MsBuf *o = c->out;
    for (uint32_t e = 0; e < c->m->nexterns; e++) {
        const MirExtern *def = &c->m->externs[e];
        const MirLeafSpan result = ll_leaves(c, def->ret);
        const bool direct = ll_rt_direct(c, def->ret);
        ms_buf_printf(o, "declare %s ", direct && result.len == 1 ? ll_leaf_type(result.ptr[0]) : "void");
        ll_sym(o, ms_name(&c->m->names, def->name));
        ms_buf_putc(o, '(');
        bool first = true;
        for (uint32_t k = 0; k < def->nparams; k++) {
            const MirLeafSpan leaves = ll_leaves(c, def->params[k].ty);
            if (!ll_rt_direct(c, def->params[k].ty)) {
                ms_buf_printf(o, "%sptr", first ? "" : ", ");
                first = false;
                continue;
            }
            for (uint32_t j = 0; j < leaves.len; j++) {
                ms_buf_printf(o, "%s%s", first ? "" : ", ", ll_leaf_type(leaves.ptr[j]));
                first = false;
            }
        }
        if (!direct) {
            ms_buf_printf(o, "%sptr", first ? "" : ", ");
        }
        ms_buf_printf(o, ")%s\n", def->noreturn ? " noreturn" : "");
    }
}

/* What the code above may call, declared once at the end of the module: the runtime's fault
 * functions (which never return) and the LLVM intrinsics. An unused declaration costs nothing. */
static const char ll_declarations[] =
    "declare void @msrt_fault_int_overflow() cold noreturn nounwind\n"
    "declare void @msrt_fault_int_range() cold noreturn nounwind\n"
    "declare void @msrt_fault_div_zero() cold noreturn nounwind\n"
    "declare void @msrt_fault_rem_zero() cold noreturn nounwind\n"
    "declare void @msrt_fault_div_overflow(i64, i64) cold noreturn nounwind\n"
    "declare void @msrt_index_fault(i64, i64) cold noreturn nounwind\n"
    "declare void @msrt_fault_unwrap_none() cold noreturn nounwind\n"
    "declare void @msrt_cancelled() cold noreturn nounwind\n"
    "declare void @msrt_fault_depth() cold noreturn nounwind\n"
    "declare { i64, i1 } @llvm.sadd.with.overflow.i64(i64, i64)\n"
    "declare { i64, i1 } @llvm.ssub.with.overflow.i64(i64, i64)\n"
    "declare { i64, i1 } @llvm.smul.with.overflow.i64(i64, i64)\n"
    "declare { i64, i1 } @llvm.uadd.with.overflow.i64(i64, i64)\n"
    "declare { i64, i1 } @llvm.usub.with.overflow.i64(i64, i64)\n"
    "declare { i64, i1 } @llvm.umul.with.overflow.i64(i64, i64)\n"
    "declare i64 @llvm.fshl.i64(i64, i64, i64)\n"
    "declare i64 @llvm.fshr.i64(i64, i64, i64)\n"
    "declare i64 @llvm.ctlz.i64(i64, i1)\n"
    "declare i64 @llvm.cttz.i64(i64, i1)\n"
    "declare i64 @llvm.ctpop.i64(i64)\n"
    "declare double @llvm.sqrt.f64(double)\n"
    "declare double @llvm.fabs.f64(double)\n"
    "declare double @llvm.floor.f64(double)\n"
    "declare double @llvm.ceil.f64(double)\n"
    "declare double @llvm.trunc.f64(double)\n";

/* The words of a data symbol: its bytes with each relocation's address in place. */
static void ll_data_words(const LCx *c, MsBuf *o, const MirDataSym *sym) {
    ms_buf_printf(o, "[%u x i64] [", sym->size / 8);
    for (uint32_t w = 0; w < sym->size / 8; w++) {
        const MirReloc *at = NULL;
        for (uint32_t r = 0; r < sym->nrelocs; r++) {
            if (sym->relocs[r].offset == w * 8) {
                at = &sym->relocs[r];
            }
        }
        ms_buf_printf(o, "%si64 ", w == 0 ? "" : ", ");
        if (at != NULL) {
            ms_buf_puts(o, "ptrtoint (ptr ");
            ll_ref(c, o, at->to);
            ms_buf_puts(o, " to i64)");
            continue;
        }
        uint64_t word = 0;
        for (uint32_t k = 0; sym->bytes != NULL && k < 8; k++) {
            word |= (uint64_t)sym->bytes[w * 8 + k] << (8 * k);
        }
        ms_buf_printf(o, "%lld", (long long)word);
    }
    ms_buf_putc(o, ']');
}

/* Whether a relocation before (`sym`, `reloc`) names the runtime symbol `name`. */
static bool ll_runtime_seen(const MirData *d, uint32_t sym, uint32_t reloc, const char *name) {
    for (uint32_t j = 0; j <= sym; j++) {
        const uint32_t end = j < sym ? d->syms[j].nrelocs : reloc;
        for (uint32_t q = 0; q < end; q++) {
            const MirRef other = d->syms[j].relocs[q].to;
            if (other.kind == MT_RUNTIME && strcmp(other.runtime, name) == 0) {
                return true;
            }
        }
    }
    return false;
}

/* One definition per data symbol, preceded by a declaration of each runtime symbol it names. */
static void ll_define_data(const LCx *c) {
    MsBuf *o = c->out;
    const MirData *d = c->data;
    for (uint32_t i = 0; i < d->nsyms; i++) {
        for (uint32_t r = 0; r < d->syms[i].nrelocs; r++) {
            const MirRef ref = d->syms[i].relocs[r].to;
            if (ref.kind == MT_RUNTIME && !ll_runtime_seen(d, i, r, ref.runtime)) {
                ll_data_name(o, ref.runtime);
                ms_buf_puts(o, " = external global i8\n");
            }
        }
    }
    for (uint32_t i = 0; i < d->nsyms; i++) {
        const MirDataSym *sym = &d->syms[i];
        ll_data_name(o, sym->name);
        ms_buf_printf(o, " = hidden %s ", sym->writable ? "global" : "constant");
        if (sym->bytes == NULL && sym->nrelocs == 0) {
            ms_buf_printf(o, "[%u x i8] zeroinitializer", sym->size);
        } else {
            ll_data_words(c, o, sym);
        }
        ms_buf_printf(o, ", align %u\n", sym->align);
    }
}

bool mir_emit_llvm(const MirModule *m, const MirData *data, MsBuf *out, MsBuf *why) {
    MirLayouts layouts;
    mir_layouts_init(&layouts, m);
    bool ok = true;
    for (uint32_t i = 0; i < m->nfuncs; i++) {
        LCx c = {m, &m->funcs[i], out, &layouts, 0, NULL, data};
        if (ll_function(&c, i)) {
            continue;
        }
        const MsStr name = ms_name(&m->names, m->funcs[i].name);
        ms_buf_printf(why, "%.*s: %s\n", (int)name.len, name.ptr, c.why ? c.why : "unsupported");
        ok = false;
    }
    LCx externs = {m, NULL, out, &layouts, 0, NULL, data};
    ll_declare_externs(&externs);
    if (data != NULL) {
        ll_define_data(&externs);
    }
    mir_layouts_free(&layouts);
    ms_buf_puts(out, ll_declarations);
    return ok;
}
