/* MIR to LLVM IR text.
 *
 * A MIR value is a run of SSA registers, one per leaf (`%v7`, `%v7.1`, ...). The calling
 * convention is the runtime's:
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

#include "ms/mir_analysis.h"
#include "ms/mir_layout.h"
#include "ms/mir_pass.h"

/* Values of at most this many bytes are passed as their leaves; larger ones are not supported yet. */
#define LL_DIRECT_BYTES 16

#include "emit_llvm_debug.inc"

typedef struct LCx {
    const MirModule *m;
    const MirFunc *f;
    MsBuf *out;
    MirLayouts *layouts; /* borrowed from mir_emit_llvm */
    uint32_t next;       /* counter for generated names */
    const char *why;
    const MirData *data; /* the module's static data; NULL when it has none */
    const MirGlue *glue; /* the glue functions, for the closure objects' entries */
    bool *framed;        /* per value of `f`: a closure object kept in the frame */
    bool *borrowed;      /* per value of `f`: an `iface.borrow` kept in the frame; NULL when none */
    bool export_all;     /* every function gets an external symbol, for the tables unit to address */
    LlDebug *dbg;        /* source places for the fault tables, or NULL */
    uint32_t scope_base; /* module-wide index of the first scope of `f` */
    uint32_t body_scope; /* the scope number of `f`'s own body: past the module's scopes, one per function */
    bool noinline;       /* `f` is glue at the top of a deep chain of glue calls */
    bool pure;           /* `f` reads and writes no memory, cannot fault and always returns */
    const char *tbaa;    /* `, !tbaa !N` for the list element access being written, or NULL */
    uint32_t body_line;  /* the line of `f`'s first instruction that has one; 0 until looked up, UINT32_MAX for none */
    const struct LlTemps *temps; /* the slots of `f` that live in one block; NULL when it has none */
    bool scopes;         /* mark where each such slot starts and stops living (`MirLlvmOptions.slot_scopes`) */
    bool poison;         /* fill each such slot with LL_POISON where its block ends */
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

static uint32_t ll_record_pieces(const MirModule *m, const MirFunc *f, const MirInst *inst);

/* How many checks an operation makes, each of which ends a piece of its block. */
static uint32_t ll_pieces_core(const MirModule *m, const MirFunc *f, const MirInst *inst) {
    switch ((MirOp)inst->op) {
    case MOP_IAddChk: case MOP_ISubChk: case MOP_IMulChk: case MOP_INegChk:
    case MOP_UAddChk: case MOP_USubChk: case MOP_UMulChk: case MOP_SRemChk:
    case MOP_NarrowChk: case MOP_IntOverflowIf: case MOP_Poll: case MOP_ListNew:
        return 1;
    case MOP_SDivChk:
        return 2;
    default:
        return ll_record_pieces(m, f, inst);
    }
}

static uint32_t ll_pieces(const MirModule *m, const MirFunc *f, const MirInst *inst) {
    int64_t lo, hi;
    return ll_pieces_core(m, f, inst) + (mir_sized_result_range(m, f, inst, &lo, &hi) ? 1 : 0);
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

static void ll_f32_round(LCx *c, MirValue res, const char *src);

/* Whether the value `v` is a Float32 (one leaf, held in a double register). */
static bool ll_is_f32(LCx *c, MirValue v) {
    const MirLeafSpan leaves = ll_leaves(c, c->f->values[v]);
    return leaves.len == 1 && leaves.ptr[0] == MIR_LEAF_F32;
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
    if (strcmp(ty, "double") == 0 && ll_is_f32(c, inst->res)) {
        /* Float32 lives in a double register: compute in double (exact enough for + - * /), round once to binary32. */
        const uint32_t n = c->next++;
        ms_buf_printf(o, "  %%t%u = %s double %%v%u, %%v%u\n", n, b->mnemonic, inst->args[0], inst->args[1]);
        char src[24];
        (void)snprintf(src, sizeof src, "%%t%u", n);
        ll_f32_round(c, inst->res, src);
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
        ms_buf_printf(o, " = load %s, ptr %%a%u%s\n", kind->mem, address, c->tbaa ? c->tbaa : "");
        return;
    }
    const uint32_t n = c->next++;
    ms_buf_printf(o, "  %%l%u = load %s, ptr %%a%u%s\n  ", n, kind->mem, address, c->tbaa ? c->tbaa : "");
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
        ms_buf_printf(o, ", ptr %%a%u%s\n", address, c->tbaa ? c->tbaa : "");
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
    ms_buf_printf(o, " to %s\n  store %s %%t%u, ptr %%a%u%s\n", kind->mem, kind->mem, n, address,
                  c->tbaa ? c->tbaa : "");
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

/* The alias class of the elements of a list of scalars. A buffer holds one element type, so a scalar element never
 * lies where a list or string header does; only element accesses carry it, since a header field is also read through
 * borrowed pointers that carry no tag. The nodes are written once at the end of the module (`ll_tbaa_nodes`). */
#define LL_TBAA_ROOT 900000
#define LL_TBAA_SCALAR 900001
#define LL_TBAA_SCALAR_TAG 900002
static const char *ll_elem_tbaa(const LCx *c, MirTy elem) {
    switch (mir_ty_data(c->m, elem)->kind) {
    case MK_BOOL: case MK_INT: case MK_FLOAT: case MK_INT8: case MK_INT16: case MK_INT32: case MK_FLOAT32:
    case MK_UINT8: case MK_UINT16: case MK_UINT32: case MK_UINT64:
        return ", !tbaa !900002";
    default:
        return NULL;
    }
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

/* `str`: a short literal is two constant words; a long one is the address of its bytes and a tag. */
static bool ll_str_lit(LCx *c, const MirInst *inst) {
    bool is_static = false;
    uint64_t lo = 0, hi = 0;
    mir_str_lit_words(c->m->strings.text[inst->imm.a], c->m->strings.len[inst->imm.a], &is_static, &lo, &hi);
    if (!is_static) {
        ms_buf_printf(c->out, "  %%v%u = add i64 %lld, 0\n", inst->res, (long long)lo);
    } else if (c->data == NULL || c->data->strings[inst->imm.a] == MIR_NONE) {
        c->why = "str without static data";
        return false;
    } else {
        ms_buf_printf(c->out, "  %%v%u = ptrtoint ptr ", inst->res);
        ll_ref(c, c->out, (MirRef){MT_DATA, c->data->strings[inst->imm.a], NULL});
        ms_buf_puts(c->out, " to i64\n");
    }
    ms_buf_printf(c->out, "  %%v%u.1 = add i64 %lld, 0\n", inst->res, (long long)hi);
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

/* `ptr.field`: the address of a field of the inline record the operand points to. */
static bool ll_ptr_field(LCx *c, const MirInst *inst) {
    if (c->m->type_defs[inst->imm.a].indirect) {
        c->why = "record behind a pointer";
        return false;
    }
    ms_buf_printf(c->out, "  %%v%u = add i64 %%v%u, %u\n", inst->res, inst->args[0],
                  mir_field_offset(c->layouts, inst->imm.a, inst->imm.b));
    return true;
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

#include "emit_llvm_record.inc"

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

/* Whether a value of `ty` crosses a call as the address of a copy, not as its leaves. */
static bool ll_indirect(LCx *c, MirTy ty) {
    return mir_type_mem(c->layouts, ty).size > LL_DIRECT_BYTES;
}

/* The frame slots a call needs: the result area when the result has several leaves, and a copy of
 * each argument that passes by address. */
static void ll_frame_call(LCx *c, const MirInst *inst, uint32_t block, uint32_t index) {
    if (inst->res != MIR_NONE && ll_leaves(c, c->f->values[inst->res]).len > 1) {
        ms_buf_printf(c->out, "  %%r%u_%u = alloca [%u x i8], align 8\n", block, index,
                      ll_slot_bytes(c->layouts, c->f->values[inst->res]));
    }
    for (uint32_t k = 0; k < inst->nargs; k++) {
        const MirTy ty = c->f->values[inst->args[k]];
        if (ll_indirect(c, ty)) {
            ms_buf_printf(c->out, "  %%x%u_%u_%u = alloca [%u x i8], align 8\n", block, index, k,
                          ll_slot_bytes(c->layouts, ty));
        }
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
            } else if (inst->op == MOP_Call || inst->op == MOP_CallInd || inst->op == MOP_CallMethod) {
                ll_frame_call(c, inst, b, k);
            } else if (inst->op == MOP_ClosureNew && c->framed[inst->res]) {
                ms_buf_printf(c->out, "  %%o%u_%u = alloca [%u x i8], align 16\n", b, k,
                              mir_closure_layout(c->layouts, &c->m->funcs[inst->imm.a]).size);
            } else if (inst->op == MOP_IfaceBorrow && c->borrowed != NULL && c->borrowed[inst->res]) {
                ms_buf_printf(c->out, "  %%i%u_%u = alloca [%u x i8], align 8\n", b, k,
                              ll_slot_bytes(c->layouts, c->f->values[inst->args[0]]));
            } else if (inst->op == MOP_StrByte) {
                ms_buf_printf(c->out, "  %%y%u_%u = alloca [16 x i8], align 8\n", b, k);
            } else if (inst->op == MOP_CallRt) {
                ll_frame_rt_call(c, inst, b, k);
            }
        }
    }
}

/* Every leaf of every argument, in order, after the hidden result pointer when there is one. */
static void ll_call_arguments(LCx *c, const MirInst *inst, const char *result_area, const char *lead,
                              uint32_t block, uint32_t index) {
    MsBuf *o = c->out;
    bool first = true;
    if (result_area != NULL) {
        ms_buf_printf(o, "ptr %s", result_area);
        first = false;
    }
    if (lead != NULL) {
        ms_buf_printf(o, "%s%s", first ? "" : ", ", lead);
        first = false;
    }
    for (uint32_t k = lead != NULL ? 1 : 0; k < inst->nargs; k++) {
        const MirTy ty = c->f->values[inst->args[k]];
        if (ll_indirect(c, ty)) {
            ms_buf_printf(o, "%sptr %%x%u_%u_%u", first ? "" : ", ", block, index, k);
            first = false;
            continue;
        }
        const MirLeafSpan leaves = ll_leaves(c, ty);
        for (uint32_t j = 0; j < leaves.len; j++) {
            ms_buf_printf(o, "%s%s ", first ? "" : ", ", ll_leaf_type(leaves.ptr[j]));
            ll_name(o, inst->args[k], j);
            first = false;
        }
    }
}

/* Writes each argument that passes by address into its frame slot, before the call. */
static bool ll_spill_arguments(LCx *c, const MirInst *inst, uint32_t block, uint32_t index) {
    char slot[32];
    for (uint32_t k = 0; k < inst->nargs; k++) {
        if (!ll_indirect(c, c->f->values[inst->args[k]])) {
            continue;
        }
        (void)snprintf(slot, sizeof slot, "%%x%u_%u_%u", block, index, k);
        if (!ll_leaves_at(c, inst->args[k], slot, false)) {
            return false;
        }
    }
    return true;
}

/* A call of `callee` (an LLVM function name, or the register holding a code pointer). A result of
 * more than one leaf comes back through a stack area that the call is given and that is read leaf
 * by leaf afterwards. */
static bool ll_call_to(LCx *c, const MirInst *inst, uint32_t block, uint32_t index, const char *callee,
                       const char *lead) {
    MsBuf *o = c->out;
    if (!ll_spill_arguments(c, inst, block, index)) {
        return false;
    }
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
    if (callee != NULL) {
        ms_buf_puts(o, callee);
    } else {
        ll_sym(o, ms_name(&c->m->names, c->m->funcs[inst->imm.a].name));
    }
    ms_buf_putc(o, '(');
    ll_call_arguments(c, inst, result_leaves > 1 ? area : NULL, lead, block, index);
    ms_buf_puts(o, ")\n");
    if (result_leaves <= 1) {
        return true;
    }
    return ll_leaves_at(c, inst->res, area, true);
}

static bool ll_call(LCx *c, const MirInst *inst, uint32_t block, uint32_t index) {
    return ll_call_to(c, inst, block, index, NULL, NULL);
}

/* Whether extern `def` is a function of a C library: the runtime's own (`msrt_`, `msstd_`) take a Float32 as a double. */
static bool ll_extern_is_c(const LCx *c, const MirExtern *def) {
    const MsStr name = ms_name(&c->m->names, def->name);
    return !(name.len >= 5 && memcmp(name.ptr, "msrt_", 5) == 0) && !(name.len >= 6 && memcmp(name.ptr, "msstd_", 6) == 0);
}

/* Appends one argument of a runtime call to `args`: the leaves of `value` when `ty` passes
 * directly, else the address of a stack copy that is written first. `area` names the copy. */
static bool ll_rt_argument(LCx *c, MsBuf *args, MirTy ty, MirValue value, const char *area, bool c_float) {
    if (!ll_rt_direct(c, ty)) {
        if (!ll_leaves_at(c, value, area, false)) {
            return false;
        }
        ms_buf_printf(args, "%sptr %s", args->len > 0 ? ", " : "", area);
        return true;
    }
    if (ty == MIR_PTR) {
        char address[32];
        ll_pointer(c, value, address, sizeof address);
        ms_buf_printf(args, "%sptr %s", args->len > 0 ? ", " : "", address);
        return true;
    }
    const MirLeafSpan leaves = ll_leaves(c, ty);
    for (uint32_t j = 0; j < leaves.len; j++) {
        const char *type = ll_leaf_type(leaves.ptr[j]);
        if (leaves.ptr[j] == MIR_LEAF_F32 && c_float) {
            /* A Float32 is a double in registers; a C library function takes a float (the runtime takes a double). */
            const uint32_t n = c->next++;
            ms_buf_printf(c->out, "  %%fa%u = fptrunc double ", n);
            ll_name(c->out, value, j);
            ms_buf_puts(c->out, " to float\n");
            ms_buf_printf(args, "%sfloat %%fa%u", args->len > 0 ? ", " : "", n);
            continue;
        }
        /* C expects a `bool` argument zero-extended to a byte; LLVM leaves the upper bits of an i1 undefined. */
        ms_buf_printf(args, "%s%s%s ", args->len > 0 ? ", " : "", type, strcmp(type, "i1") == 0 ? " zeroext" : "");
        ll_name(args, value, j);
    }
    return true;
}

static const char *ll_widen_op(LlWiden widen) {
    switch (widen) {
    case LL_SEXT: return "sext";
    case LL_FPEXT: return "fpext";
    default: return "zext";
    }
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
        ok = ll_rt_argument(c, &args, def->params[k].ty, inst->args[k], area, ll_extern_is_c(c, def));
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
        const LlLeafKind *rk = direct && result.len == 1 ? ll_leaf_kind(result.ptr[0]) : NULL;
        const bool runtime_float = rk != NULL && rk->widen == LL_FPEXT && !ll_extern_is_c(c, def); /* a double */
        const bool narrow = rk != NULL && strcmp(rk->reg, rk->mem) != 0 && !runtime_float;
        if (narrow) {
            /* The C function returns the narrow type. The bits above it are the callee's to leave as they are (the
             * AAPCS64 does not make a callee extend its result), so the call carries no extension attribute: the
             * `sext` or `zext` after it reads the low bits only. */
            ms_buf_printf(c->out, "  %%v%ur = call %s ", inst->res, rk->mem);
        } else if (rk != NULL) {
            ms_buf_printf(c->out, "  %%v%u = call %s ", inst->res, rk->reg);
        } else {
            ms_buf_puts(c->out, "  call void ");
        }
        ll_sym(c->out, ms_name(&c->m->names, def->name));
        ms_buf_printf(c->out, "(%.*s)\n", (int)args.len, args.data == NULL ? "" : args.data);
        if (narrow) {
            const char *op = ll_widen_op(rk->widen);
            if (rk->widen == LL_BOOL) {
                ms_buf_printf(c->out, "  %%v%u = trunc i8 %%v%ur to i1\n", inst->res, inst->res);
            } else {
                ms_buf_printf(c->out, "  %%v%u = %s %s %%v%ur to %s\n", inst->res, op, rk->mem, inst->res,
                              rk->reg);
            }
        }
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
    int64_t lo, hi;
    const bool sized = mir_sized_result_range(c->m, c->f, inst, &lo, &hi);
    ll_fault_if(c, block, part, flag, sized ? "msrt_fault_int_range" : kind->fault, NULL, 0);
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
        ms_buf_printf(o, "  %%ob%u = and i1 %%m%u, %%n%u\n", n, n, n);
        char both[24];
        (void)snprintf(both, sizeof both, "%%ob%u", n);
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
            /* One rounding, straight to binary32: through a double it would round twice at the midpoints. */
            const uint32_t n = c->next++;
            ms_buf_printf(o, "  %%i%u = sitofp i64 %%v%u to float\n  %%v%u = fpext float %%i%u to double\n", n,
                          inst->args[0], inst->res, n);
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
        if (inst->op == MOP_FSqrt && ll_is_f32(c, inst->res)) {
            const uint32_t n = c->next++;
            char src[24];
            (void)snprintf(src, sizeof src, "%%t%u", n);
            ms_buf_printf(o, "  %%t%u = call double @llvm.sqrt.f64(double %%v%u)\n", n, inst->args[0]);
            ll_f32_round(c, inst->res, src);
            return true;
        }
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
    case MOP_TypeSet: case MOP_TypeFill: return ll_record_set(c, inst);
    case MOP_PtrField: return ll_ptr_field(c, inst);
    default:
        *handled = false;
        return true;
    }
}

/* ---- raw pointers ---- */

/* The memory type of an unsigned access `bytes` wide: `ptr.loadu` and `ptr.storeu` take 1, 2, 4 or
 * 8, and any other width is a word. */
static const char *ll_word_type(int64_t bytes) {
    switch (bytes) {
    case 1: return "i8";
    case 2: return "i16";
    case 4: return "i32";
    default: return "i64";
    }
}

/* `ptr.null`, `ptr.is_null`, `ptr.add`, `ptr.loadu`, `ptr.storeu`; false when `inst` is none. */
static bool ll_pointer_op(LCx *c, const MirInst *inst) {
    MsBuf *o = c->out;
    const int64_t width = inst->imm.tag == MI_INT ? inst->imm.i : 8;
    const char *type = ll_word_type(width);
    const bool word = type[1] == '6' && type[2] == '4';
    switch ((MirOp)inst->op) {
    case MOP_Free:
        if (inst->imm.tag != MI_NONE) {
            c->why = "free of a collection field";
            return false;
        }
        char block[32];
        ll_pointer(c, inst->args[0], block, sizeof block);
        ms_buf_printf(o, "  call void @\"msrt_free\"(ptr %s)\n", block);
        return true;
    case MOP_PtrNull:
        ms_buf_printf(o, "  %%v%u = add i64 0, 0\n", inst->res);
        return true;
    case MOP_PtrIsNull:
        ms_buf_printf(o, "  %%v%u = icmp eq i64 %%v%u, 0\n", inst->res, inst->args[0]);
        return true;
    case MOP_PtrAdd:
        ms_buf_printf(o, "  %%v%u = add i64 %%v%u, %%v%u\n", inst->res, inst->args[0], inst->args[1]);
        return true;
    case MOP_PtrLoadU: {
        char base[24];
        ll_pointer(c, inst->args[0], base, sizeof base);
        const uint32_t n = c->next++;
        ms_buf_printf(o, "  %%l%u = load %s, ptr %s\n", n, type, base);
        if (word) {
            ms_buf_printf(o, "  %%v%u = or i64 %%l%u, 0\n", inst->res, n);
        } else {
            ms_buf_printf(o, "  %%v%u = zext %s %%l%u to i64\n", inst->res, type, n);
        }
        return true;
    }
    case MOP_PtrStoreU: {
        char base[24];
        ll_pointer(c, inst->args[0], base, sizeof base);
        const uint32_t n = c->next++;
        if (word) {
            ms_buf_printf(o, "  store i64 %%v%u, ptr %s\n", inst->args[1], base);
        } else {
            ms_buf_printf(o, "  %%t%u = trunc i64 %%v%u to %s\n  store %s %%t%u, ptr %s\n", n, inst->args[1], type,
                          type, n, base);
        }
        return true;
    }
    default:
        return false;
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
        ll_fault_if(c, block, part, flag, "msrt_fault_int_range", NULL, 0);
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

/* `inarrow.opt`, `f2i.opt`: the optional is [fits, value]. The value leaf is the integer register
 * itself (or the saturating conversion of the float), which only means something when it fits. */
static void ll_opt_convert(LCx *c, const MirInst *inst) {
    MsBuf *o = c->out;
    const uint32_t n = c->next++;
    const MirValue x = inst->args[0];
    if (inst->op == MOP_INarrowOpt) {
        const MirTyData *res = mir_ty_data(c->m, c->f->values[inst->res]);
        int64_t lo, hi;
        mir_narrow_range(c->m, c->f->values[x], res->elem, &lo, &hi);
        ms_buf_printf(o, "  %%o%ua = icmp sge i64 %%v%u, %lld\n  %%o%ub = icmp sle i64 %%v%u, %lld\n", n, x,
                      (long long)lo, n, x, (long long)hi);
        ms_buf_printf(o, "  %%v%u = and i1 %%o%ua, %%o%ub\n", inst->res, n, n);
        ll_copy_leaf(c, inst->res, 1, x, 0);
        return;
    }
    ms_buf_printf(o, "  %%o%ua = fcmp oge double %%v%u, -9223372036854775808.0\n", n, x);
    ms_buf_printf(o, "  %%o%ub = fcmp olt double %%v%u, 9223372036854775808.0\n", n, x);
    ms_buf_printf(o, "  %%v%u = and i1 %%o%ua, %%o%ub\n", inst->res, n, n);
    ms_buf_printf(o, "  %%v%u.1 = call i64 @llvm.fptosi.sat.i64.f64(double %%v%u)\n", inst->res, x);
}

/* `stack.low`, `stack.near`: whether the stack pointer is below the running segment's limit (plus
 * the headroom). The limit is the word at the end of the stack's region, which is aligned to its
 * size, so one mask of the frame address finds it. */
static void ll_stack_check(LCx *c, const MirInst *inst) {
    MsBuf *o = c->out;
    const uint32_t n = c->next++;
    ms_buf_printf(o, "  %%f%u = call ptr @llvm.frameaddress.p0(i32 0)\n  %%sp%u = ptrtoint ptr %%f%u to i64\n", n, n, n);
    ms_buf_printf(o, "  %%sm%u = and i64 %%sp%u, %lld\n  %%c%u = add i64 %%sm%u, %lld\n", n, n,
                  (long long)-MIR_STACK_REGION, n, n, (long long)(MIR_STACK_REGION - MIR_STACK_LIMIT_CELL));
    ms_buf_printf(o, "  %%l%up = inttoptr i64 %%c%u to ptr\n  %%l%u = load i64, ptr %%l%up\n", n, n, n, n);
    if (inst->op == MOP_StackNear) {
        ms_buf_printf(o, "  %%l%u2 = add i64 %%l%u, %lld\n  %%v%u = icmp ult i64 %%sp%u, %%l%u2\n", n, n,
                      (long long)inst->imm.i, inst->res, n, n);
        return;
    }
    ms_buf_printf(o, "  %%v%u = icmp ult i64 %%sp%u, %%l%u\n", inst->res, n, n);
}

/* `opt.is_some`: the flag leaf of an optional held as [flag, value], or a non-null test of one held
 * as a single nullable pointer. */
static void ll_opt_is_some(LCx *c, const MirInst *inst) {
    const MirValue x = inst->args[0];
    if (mir_is_str_like(c->layouts, c->f->values[x])) {
        /* A `String?` is its two string words; none is (0, the static tag). */
        const uint32_t n = c->next++;
        ms_buf_printf(c->out, "  %%t%u = xor i64 %%v%u.1, %lld\n  %%o%u = or i64 %%v%u, %%t%u\n  %%v%u = icmp ne i64 %%o%u, 0\n",
                      n, x, (long long)MIR_STR_STATIC, n, x, n, inst->res, n);
    } else if (ll_leaves(c, c->f->values[x]).len == 1 &&
               strcmp(ll_leaf_type(ll_leaves(c, c->f->values[x]).ptr[0]), "i64") == 0) {
        ms_buf_printf(c->out, "  %%v%u = icmp ne i64 %%v%u, 0\n", inst->res, x);
    } else {
        ll_copy_leaf(c, inst->res, 0, x, 0);
    }
}

/* `conv`, `f32.round`, `narrow.chk`, the overflow flags and `int_overflow.if`; false when `inst`
 * is none of them. */
/* ---- alternatives and optionals ---- */

/* `alt.tag`: leaf 0, or the first word of the block a boxed alternative points to. */
static void ll_alt_tag(LCx *c, const MirInst *inst) {
    if (mir_shape(c->layouts, c->f->values[inst->args[0]])->alt == MIR_ALT_BOXED) {
        char base[24];
        ll_pointer(c, inst->args[0], base, sizeof base);
        ms_buf_printf(c->out, "  %%v%u = load i64, ptr %s\n", inst->res, base);
    } else {
        ll_copy_leaf(c, inst->res, 0, inst->args[0], 0);
    }
}

/* `opt.some`, `opt.view` (the same leaves; the view borrows its payload): a boxed optional is a pointer to a heap copy of the payload, a nullable one is the
 * payload itself, any other is the payload after a presence flag. */
static bool ll_opt_some(LCx *c, const MirInst *inst) {
    const MirTy inner = mir_ty_data(c->m, c->f->values[inst->res])->elem;
    MsBuf *o = c->out;
    if (mir_layouts_opt_boxed(c->layouts, inner)) {
        const MirLeafSpan leaves = ll_leaves(c, inner);
        const uint32_t size = mir_mem_layout(leaves.ptr, leaves.len, NULL).size;
        ms_buf_printf(o, "  %%v%u = call i64 @\"msrt_alloc\"(i64 %u)\n", inst->res, size > 0 ? size : 1);
        char base[24];
        ll_pointer(c, inst->res, base, sizeof base);
        return leaves.len == 0 || ll_leaves_at(c, inst->args[0], base, false);
    }
    uint32_t at = 0;
    if (mir_opt_has_flag(c->layouts, c->f->values[inst->res])) {
        ms_buf_printf(o, "  %%v%u = or i1 false, true\n", inst->res);
        at = 1;
    }
    const uint32_t n = ll_leaves(c, c->f->values[inst->args[0]]).len;
    for (uint32_t k = 0; k < n; k++) {
        ll_copy_leaf(c, inst->res, at + k, inst->args[0], k);
    }
    return true;
}

/* `opt.get`: the payload of an optional known to hold one. */
static bool ll_opt_get(LCx *c, const MirInst *inst) {
    const MirTy inner = mir_ty_data(c->m, c->f->values[inst->args[0]])->elem;
    if (mir_layouts_opt_boxed(c->layouts, inner)) {
        char base[24];
        ll_pointer(c, inst->args[0], base, sizeof base);
        return ll_leaves_at(c, inst->res, base, true);
    }
    const uint32_t skip = mir_opt_has_flag(c->layouts, c->f->values[inst->args[0]]) ? 1 : 0;
    const uint32_t n = ll_leaves(c, c->f->values[inst->res]).len;
    for (uint32_t k = 0; k < n; k++) {
        ll_copy_leaf(c, inst->res, k, inst->args[0], skip + k);
    }
    return true;
}

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
    case MOP_INarrowOpt: case MOP_F2IOpt:
        ll_opt_convert(c, inst);
        return true;
    case MOP_AltTag: ll_alt_tag(c, inst); return true;
    case MOP_OptSome: case MOP_OptView: return ll_opt_some(c, inst);
    case MOP_OptGet: return ll_opt_get(c, inst);
    case MOP_OptIsSome:
        ll_opt_is_some(c, inst);
        return true;
    case MOP_StackLow: case MOP_StackNear:
        ll_stack_check(c, inst);
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

#include "emit_llvm_closure.inc"
#include "emit_llvm_iface.inc"
#include "emit_llvm_enum.inc"
#include "emit_llvm_list.inc"
#include "emit_llvm_str.inc"
#include "emit_llvm_task.inc"

/* Writes instruction `index` of block `block`; false, with the reason in `c->why`, when it is not
 * covered yet. */
/* ---- list element access ---- */

/* Writes the element address as a pointer and names it in `out`. */
static void ll_elem_base(LCx *c, MirValue list, const char *index, uint32_t size, char *out, size_t cap) {
    const uint32_t n = c->next++;
    ms_buf_printf(c->out,
                  "  %%t%u = mul i64 %s, %u\n  %%lb%u = inttoptr i64 %%v%u to ptr\n"
                  "  %%p%u = getelementptr i8, ptr %%lb%u, i64 %%t%u\n",
                  n, index, size, n, list, n, n, n);
    (void)snprintf(out, cap, "%%p%u", n);
}

/* The result takes the address and capacity of `from`; the caller writes the length. */
static void ll_copy_list(LCx *c, const MirInst *inst, MirValue from) {
    ll_copy_leaf(c, inst->res, 0, from, 0);
    ll_copy_leaf(c, inst->res, MIR_LIST_CAP_LEAF, from, MIR_LIST_CAP_LEAF);
}

/* `list.new`: a block of `cap` elements, none for capacity 0 (the null pointer owns nothing). The
 * allocation is a block of its own and the rest of the instruction continues in a new piece. */
static bool ll_list_new(LCx *c, const MirInst *inst, uint32_t size, uint32_t block, uint32_t *part) {
    MsBuf *o = c->out;
    const uint32_t n = c->next++;
    ms_buf_printf(o, "  %%o%ub = mul i64 %%v%u, %u\n  %%o%us = icmp ne i64 %%v%u, 0\n", n, inst->args[0],
                  size > 0 ? size : 1, n, inst->args[0]);
    /* The piece that holds the branch is named by the previous part; the join is the next one. */
    const uint32_t from = *part;
    (*part)++;
    ms_buf_printf(o, "  br i1 %%o%us, label %%ln%u, label %%", n, n);
    ll_label(c, block, *part);
    ms_buf_printf(o, "\nln%u:\n  %%o%up = call i64 @\"msrt_alloc\"(i64 %%o%ub)\n  br label %%", n, n, n);
    ll_label(c, block, *part);
    ms_buf_putc(o, '\n');
    ll_label(c, block, *part);
    ms_buf_puts(o, ":\n");
    ms_buf_printf(o, "  %%v%u = phi i64 [ %%o%up, %%ln%u ], [ 0, %%", inst->res, n, n);
    ll_label(c, block, from);
    ms_buf_puts(o, " ]\n");
    ms_buf_printf(o, "  %%v%u.%u = add i64 0, 0\n", inst->res, MIR_LIST_LEN_LEAF);
    ll_copy_leaf(c, inst->res, MIR_LIST_CAP_LEAF, inst->args[0], 0);
    return true;
}

/* `list.lit`: a block holding the operands, or the empty list for none. */
static bool ll_list_lit(LCx *c, const MirInst *inst, uint32_t size) {
    MsBuf *o = c->out;
    if (inst->nargs == 0) {
        ms_buf_printf(o, "  %%v%u = add i64 0, 0\n  %%v%u.1 = add i64 0, 0\n  %%v%u.2 = add i64 0, 0\n", inst->res,
                      inst->res, inst->res);
        return true;
    }
    ms_buf_printf(o, "  %%v%u = call i64 @\"msrt_alloc\"(i64 %u)\n", inst->res, inst->nargs * (size > 0 ? size : 1));
    for (uint32_t k = 0; k < inst->nargs; k++) {
        const uint32_t n = c->next++;
        ms_buf_printf(o, "  %%a%u = add i64 %%v%u, %u\n  %%p%u = inttoptr i64 %%a%u to ptr\n", n, inst->res, k * size, n, n);
        char base[24];
        (void)snprintf(base, sizeof base, "%%p%u", n);
        if (!ll_leaves_at(c, inst->args[k], base, false)) {
            return false;
        }
    }
    ms_buf_printf(o, "  %%v%u.1 = add i64 0, %u\n  %%v%u.2 = add i64 0, %u\n", inst->res, inst->nargs, inst->res,
                  inst->nargs);
    return true;
}

/* Writes `element` at `base`, an element address of `list`, tagged with the alias class of its elements. */
static bool ll_store_element(LCx *c, MirValue list, MirValue element, const char *base) {
    c->tbaa = ll_elem_tbaa(c, ll_list_elem(c, c->f->values[list]));
    const bool ok = ll_leaves_at(c, element, base, false);
    c->tbaa = NULL;
    return ok;
}

/* The unchecked list operations: the index is in range or the length is known. Dropping an old
 * element is the job of `lower_ops`, which runs first. */
static bool ll_list_write_op(LCx *c, const MirInst *inst, uint32_t block, uint32_t *part, bool *handled) {
    *handled = true;
    char base[24], index[24];
    if (inst->op == MOP_ListNew || inst->op == MOP_ListLit) {
        const uint32_t elem_size = mir_list_elem_size(c->layouts, c->f->values[inst->res]);
        return inst->op == MOP_ListNew ? ll_list_new(c, inst, elem_size, block, part)
                                       : ll_list_lit(c, inst, elem_size);
    }
    const bool is_list = inst->op == MOP_ListSetU ||
                         inst->op == MOP_ListFillU || inst->op == MOP_ListPushU || inst->op == MOP_ListGrow;
    const uint32_t size = is_list ? mir_list_elem_size(c->layouts, c->f->values[inst->args[0]]) : 0;
    MsBuf *o = c->out;
    switch ((MirOp)inst->op) {
    case MOP_ListSetU: case MOP_ListFillU:
        (void)snprintf(index, sizeof index, "%%v%u", inst->args[1]);
        ll_elem_base(c, inst->args[0], index, size, base, sizeof base);
        ll_copy_list(c, inst, inst->args[0]);
        ll_copy_leaf(c, inst->res, MIR_LIST_LEN_LEAF, inst->args[0], MIR_LIST_LEN_LEAF);
        return ll_store_element(c, inst->args[0], inst->args[2], base);
    case MOP_ListPushU:
        (void)snprintf(index, sizeof index, "%%v%u.%u", inst->args[0], MIR_LIST_LEN_LEAF);
        ll_elem_base(c, inst->args[0], index, size, base, sizeof base);
        ll_copy_list(c, inst, inst->args[0]);
        ms_buf_printf(o, "  %%v%u.%u = add i64 %%v%u.%u, 1\n", inst->res, MIR_LIST_LEN_LEAF,
                      inst->args[0], MIR_LIST_LEN_LEAF);
        return ll_store_element(c, inst->args[0], inst->args[1], base);
    case MOP_ListDropLast:
        ll_copy_list(c, inst, inst->args[0]);
        ms_buf_printf(o, "  %%v%u.%u = sub i64 %%v%u.%u, 1\n", inst->res, MIR_LIST_LEN_LEAF,
                      inst->args[0], MIR_LIST_LEN_LEAF);
        return true;
    case MOP_ListGrow: {
        /* A block of capacity 0 is a view or empty: it is never resized, a fresh block is made. */
        const uint32_t n = c->next++;
        ms_buf_printf(o,
                      "  %%t%u = icmp eq i64 %%v%u.%u, 0\n  %%q%u = select i1 %%t%u, i64 0, i64 %%v%u\n"
                      "  %%gb%u = mul i64 %%v%u, %u\n  %%v%u = call i64 @\"msrt_realloc\"(i64 %%q%u, i64 %%gb%u)\n",
                      n, inst->args[0], MIR_LIST_CAP_LEAF, n, n, inst->args[0], n, inst->args[1],
                      size > 0 ? size : 1, inst->res, n, n);
        ll_copy_leaf(c, inst->res, MIR_LIST_LEN_LEAF, inst->args[0], MIR_LIST_LEN_LEAF);
        ll_copy_leaf(c, inst->res, MIR_LIST_CAP_LEAF, inst->args[1], 0);
        return true;
    }
    default:
        *handled = false;
        return true;
    }
}

static bool ll_inst_core(LCx *c, const MirInst *inst, uint32_t block, uint32_t index, uint32_t *part) {
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
    const bool indirect_ok = ll_indirect_op(c, inst, block, part, &handled);
    if (handled) {
        return indirect_ok;
    }
    const bool ok = ll_memory_inst(c, inst, &handled);
    if (handled) {
        return ok;
    }
    const bool closure_ok = ll_closure_op(c, inst, block, index, &handled);
    if (handled) {
        return closure_ok;
    }
    const bool write_ok = ll_list_write_op(c, inst, block, part, &handled);
    if (handled) {
        return write_ok;
    }
    const bool str_ok = ll_str_op(c, inst, block, index, part, &handled);
    if (handled) {
        return str_ok;
    }
    const bool iface_ok = ll_iface_op(c, inst, block, index, &handled);
    if (handled) {
        return iface_ok;
    }
    const bool enum_ok = ll_enum_op(c, inst, &handled);
    if (handled) {
        return enum_ok;
    }
    const bool list_ok = ll_list_op(c, inst, &handled);
    if (handled) {
        return list_ok;
    }
    const bool task_ok = ll_task_op(c, inst, block, part, &handled);
    if (handled) {
        return task_ok;
    }
    switch (inst->op) {
    case MOP_IConst: case MOP_BConst: case MOP_FConst: ll_constant(c, inst); return true;
    case MOP_StrLit: return ll_str_lit(c, inst);
    case MOP_DepthLeave: return true; /* nothing to write */
    case MOP_ListLen: ll_copy_leaf(c, inst->res, 0, inst->args[0], MIR_LIST_LEN_LEAF); return true;
    case MOP_ListCap: ll_copy_leaf(c, inst->res, 0, inst->args[0], MIR_LIST_CAP_LEAF); return true;
    case MOP_VoidConst: return true; /* nothing to write */
    case MOP_ICmp: case MOP_UICmp: case MOP_FCmp: ll_compare(c, inst); return true;
    case MOP_Call: return ll_call(c, inst, block, index);
    case MOP_CallRt: return ll_call_rt(c, inst, block, index);
    case MOP_SDivChk: case MOP_SRemChk: ll_checked_div(c, inst, block, part); return true;
    default:
        if (ll_convert(c, inst, block, part) || ll_pointer_op(c, inst)) {
            return true;
        }
        c->why = mir_op_info[inst->op].name;
        return false;
    }
}

/* A checked operation on a sized integer also faults when its result leaves the type's range. */
static bool ll_inst(LCx *c, const MirInst *inst, uint32_t block, uint32_t index, uint32_t *part) {
    if (!ll_inst_core(c, inst, block, index, part)) {
        return false;
    }
    int64_t lo, hi;
    if (!mir_sized_result_range(c->m, c->f, inst, &lo, &hi)) {
        return true;
    }
    const uint32_t n = c->next++;
    ms_buf_printf(c->out, "  %%l%ua = icmp slt i64 %%v%u, %lld\n  %%l%ub = icmp sgt i64 %%v%u, %lld\n  %%l%us = or i1 %%l%ua, %%l%ub\n",
                  n, inst->res, (long long)lo, n, inst->res, (long long)hi, n, n, n);
    char bad[24];
    (void)snprintf(bad, sizeof bad, "%%l%us", n);
    ll_fault_if(c, block, part, bad, "msrt_fault_int_range", NULL, 0);
    return true;
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

/* Whether edge `k` goes to a block an earlier edge of `t` reaches. A phi needs one predecessor per incoming value,
 * so such an edge goes through a block of its own (`t<block>_<k>`) that branches on to the target. */
static bool ll_edge_repeats(const MirTerm *t, uint32_t k) {
    for (uint32_t j = 0; j < k; j++) {
        if (ll_edge(t, j)->block == ll_edge(t, k)->block) {
            return true;
        }
    }
    return false;
}

/* The label edge `k` of the terminator of block `from` branches to. */
static void ll_edge_label(MsBuf *o, const MirTerm *t, uint32_t from, uint32_t k) {
    if (ll_edge_repeats(t, k)) {
        ms_buf_printf(o, "%%t%u_%u", from, k);
    } else {
        ms_buf_printf(o, "%%b%u", ll_edge(t, k)->block);
    }
}

/* A `switch`: the cases by value, the default last. Several cases may share a target. */
static void ll_switch(LCx *c, const MirTerm *t, uint32_t from) {
    MsBuf *o = c->out;
    /* One line, so the place tag `ll_debug_tag` adds to each indented line lands after the `]`. */
    ms_buf_printf(o, "  switch i64 %%v%u, label ", t->value);
    ll_edge_label(o, t, from, t->ncases);
    ms_buf_puts(o, " [");
    for (uint32_t k = 0; k < t->ncases; k++) {
        ms_buf_printf(o, " i64 %lld, label ", (long long)t->cases[k].value);
        ll_edge_label(o, t, from, k);
    }
    ms_buf_puts(o, " ]\n");
}

static bool ll_term(LCx *c, const MirTerm *t, uint32_t from) {
    MsBuf *o = c->out;
    switch ((MirTermKind)t->kind) {
    case MT_BR:
        ms_buf_printf(o, "  br label %%b%u\n", t->a.block);
        return true;
    case MT_CONDBR:
        ms_buf_printf(o, "  br i1 %%v%u, label ", t->value);
        ll_edge_label(o, t, from, 0);
        ms_buf_puts(o, ", label ");
        ll_edge_label(o, t, from, 1);
        ms_buf_putc(o, '\n');
        return true;
    case MT_SWITCH:
        ll_switch(c, t, from);
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
        for (uint32_t k = 0; k < ll_edge_count(t); k++) {
            const MirTarget *e = ll_edge(t, k);
            if (e->block != b) {
                continue;
            }
            ms_buf_printf(c->out, "%s[ ", first ? "" : ", ");
            ll_name(c->out, e->args[index], leaf);
            ms_buf_puts(c->out, ", %");
            if (ll_edge_repeats(t, k)) {
                ms_buf_printf(c->out, "t%u_%u", s, k);
            } else {
                ll_label(c, s, last[s]);
            }
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

/* The start of the entry block: the frame slots, then the leaves of each parameter that arrived
 * as an address. */
static bool ll_entry(LCx *c) {
    ll_frame_slots(c);
    for (uint32_t k = 0; k < c->f->nparams; k++) {
        if (!ll_indirect(c, c->f->params[k].ty)) {
            continue;
        }
        const MirValue param = c->f->blocks[0].params[k].value;
        char from[24];
        (void)snprintf(from, sizeof from, "%%in%u", param);
        if (!ll_leaves_at(c, param, from, true)) {
            return false;
        }
    }
    return true;
}

/* The line of the first instruction of `f` that has one of its own (not an inlined callee's), or the function's own
 * line when none does. */
static uint32_t ll_body_line(LCx *c) {
    if (c->body_line == 0) {
        c->body_line = UINT32_MAX;
        for (uint32_t b = 0; c->body_line == UINT32_MAX && b < c->f->nblocks; b++) {
            const MirBlockData *block = &c->f->blocks[b];
            for (uint32_t k = 0; k < block->ninsts; k++) {
                const MirLoc at = block->insts[k].loc;
                if (!mir_loc_none(at) && at.line != 0 && at.scope == 0) {
                    c->body_line = at.line;
                    break;
                }
            }
        }
    }
    return c->body_line == UINT32_MAX ? c->f->loc.line : c->body_line;
}

/* Puts the source place `loc` on the text written since `from`. An instruction with none (the stack check that
 * `depth` puts first, which faults on an overflow) sits on the first line of the body, so a trace names the
 * line the recursion is on and not the function's declaration. */
static void ll_place(LCx *c, size_t from, MirLoc loc) {
    if (c->dbg == NULL) {
        return;
    }
    const bool known = !mir_loc_none(loc) && loc.line != 0;
    const uint32_t line = known ? loc.line : ll_body_line(c);
    /* Scope 0 is the function itself; LLVM may inline it into another, so it gets a number of its own. */
    const uint32_t scope = known && loc.scope != 0 ? c->scope_base + loc.scope : c->body_scope;
    ll_debug_tag(c->out, from, ll_debug_location(c->dbg, line, scope));
}

/* A stack slot that lives in one block (`mir_confined_slots`): nothing reads it before that block's
 * first access or after its terminator, so LLVM may give its storage to another block's slot. */
typedef struct LlTemp {
    MirValue slot;
    uint32_t bytes;
} LlTemp;

/* The temporaries of a function, grouped by block: those of block `b` are `v[first[b]]` up to
 * `v[first[b + 1]]`. */
typedef struct LlTemps {
    const uint32_t *first;
    const LlTemp *v;
} LlTemps;

/* The byte a dead temporary is filled with when slots are poisoned, the one the counting runtime
 * writes over freed heap blocks. */
enum { LL_POISON = 0xDD };

/* The temporaries of `c->f`, in `arena`; NULL when it has none. */
static const LlTemps *ll_temps(LCx *c, MsArena *arena) {
    const MirFunc *f = c->f;
    const MirBlock *home = mir_confined_slots(arena, c->m, f);
    if (home == NULL) {
        return NULL;
    }
    uint32_t *first = MS_NEW_N(arena, uint32_t, (size_t)f->nblocks + 2);
    memset(first, 0, sizeof *first * ((size_t)f->nblocks + 2));
    uint32_t total = 0;
    for (MirValue v = 0; v < f->nvalues; v++) {
        if (home[v] != MIR_NONE) {
            first[home[v] + 2]++; /* counts, shifted so the fill below leaves offsets in place */
            total++;
        }
    }
    if (total == 0) {
        return NULL;
    }
    for (uint32_t b = 2; b < f->nblocks + 2; b++) {
        first[b] += first[b - 1];
    }
    LlTemp *temps = MS_NEW_N(arena, LlTemp, total);
    for (uint32_t b = 0; b < f->nblocks; b++) {
        const MirBlockData *block = &f->blocks[b];
        for (uint32_t k = 0; k < block->ninsts; k++) {
            const MirInst *inst = &block->insts[k];
            if (inst->op == MOP_Slot && inst->res != MIR_NONE && home[inst->res] != MIR_NONE) {
                temps[first[home[inst->res] + 1]++] =
                    (LlTemp){inst->res, ll_slot_bytes(c->layouts, (MirTy)inst->imm.a)};
            }
        }
    }
    LlTemps *out = MS_NEW_N(arena, LlTemps, 1);
    *out = (LlTemps){first, temps};
    return out;
}

/* Starts the life of the temporaries of block `b`, before its first instruction. */
static void ll_temps_begin(const LCx *c, uint32_t b) {
    for (uint32_t k = c->temps ? c->temps->first[b] : 0; c->temps && k < c->temps->first[b + 1]; k++) {
        if (c->scopes) {
            ms_buf_printf(c->out, "  call void @llvm.lifetime.start.p0(ptr %%s%u)\n", c->temps->v[k].slot);
        }
    }
}

/* Ends the life of the temporaries of block `b`, before its terminator. The poison fill is volatile
 * so that LLVM keeps a store to memory nothing reads again. */
static void ll_temps_end(const LCx *c, uint32_t b) {
    for (uint32_t k = c->temps ? c->temps->first[b] : 0; c->temps && k < c->temps->first[b + 1]; k++) {
        const LlTemp *temp = &c->temps->v[k];
        if (c->poison) {
            ms_buf_printf(c->out, "  call void @llvm.memset.p0.i64(ptr %%s%u, i8 %d, i64 %u, i1 true)\n", temp->slot,
                          (int)(int8_t)LL_POISON, temp->bytes);
        }
        if (c->scopes) {
            ms_buf_printf(c->out, "  call void @llvm.lifetime.end.p0(ptr %%s%u)\n", temp->slot);
        }
    }
}

static bool ll_block(LCx *c, uint32_t b, const uint32_t *last) {
    const MirBlockData *block = &c->f->blocks[b];
    ms_buf_printf(c->out, "b%u:\n", b);
    if (b == 0 && !ll_entry(c)) {
        return false;
    }
    for (uint32_t p = 0; b > 0 && p < block->nparams; p++) {
        if (!ll_phi(c, b, p, last)) {
            return false;
        }
    }
    ll_temps_begin(c, b);
    uint32_t part = 0;
    for (uint32_t k = 0; k < block->ninsts; k++) {
        const size_t from = c->out->len;
        if (!ll_inst(c, &block->insts[k], b, k, &part)) {
            return false;
        }
        ll_place(c, from, block->insts[k].loc);
    }
    const size_t from = c->out->len;
    ll_temps_end(c, b);
    if (!ll_term(c, &block->term, b)) {
        return false;
    }
    for (uint32_t k = 0; k < ll_edge_count(&block->term); k++) {
        if (ll_edge_repeats(&block->term, k)) {
            ms_buf_printf(c->out, "t%u_%u:\n  br label %%b%u\n", b, k, ll_edge(&block->term, k)->block);
        }
    }
    ll_place(c, from, block->term_loc);
    return true;
}

/* `define <result> @name(<hidden result pointer>, <leaves of each parameter>) {`. */
static void ll_header(LCx *c, uint32_t index) {
    const MirFunc *f = c->f;
    MsBuf *o = c->out;
    const bool exported = c->export_all || f->linkage == ML_EXPORT || c->m->entry == index;
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
        if (ll_indirect(c, f->params[k].ty)) {
            /* The entry block loads the leaves and nothing else touches the address: a caller's copy that is only
             * read, not kept, and one the callee owns for its whole life. */
            ms_buf_printf(o, "%sptr nonnull readonly nocapture align 8 dereferenceable(%u) %%in%u", first ? "" : ", ",
                          ll_slot_bytes(c->layouts, f->params[k].ty), param);
            first = false;
            continue;
        }
        for (uint32_t j = 0; j < leaves.len; j++) {
            ms_buf_printf(o, "%s%s ", first ? "" : ", ", ll_leaf_type(leaves.ptr[j]));
            ll_name(o, param, j);
            first = false;
        }
    }
    ms_buf_puts(o, c->noinline ? ") nounwind noinline" : ") nounwind");
    if (c->pure) {
        ms_buf_puts(o, " willreturn nofree nosync memory(none)");
    }
    if (c->dbg != NULL) {
        ms_buf_printf(o, " !dbg !%u", ll_debug_subprogram(c->dbg, ms_name(&c->m->names, f->name), f->loc.line));
    }
    ms_buf_puts(o, " {\n");
}

/* Pieces each block splits into: its checked operations each end one, and the last piece is what
 * the successors' phis name. Fills `last` with the count per block. */
static void ll_last_pieces(const MirModule *m, const MirFunc *f, uint32_t *last) {
    for (uint32_t b = 0; b < f->nblocks; b++) {
        last[b] = 0;
        for (uint32_t k = 0; k < f->blocks[b].ninsts; k++) {
            last[b] += ll_pieces(m, f, &f->blocks[b].insts[k]);
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
    c->framed = calloc(f->nvalues ? f->nvalues : 1, sizeof *c->framed); /* owned, freed below */
    if (c->framed == NULL) {
        free(last);
        c->why = "out of memory";
        return false;
    }
    mir_framed_closures(c->m, f, c->framed);
    MsArena scratch = {0};
    c->borrowed = mir_framed_iface_borrows(&scratch, c->m, f);
    c->temps = c->scopes || c->poison ? ll_temps(c, &scratch) : NULL;
    ll_last_pieces(c->m, f, last);
    ll_header(c, index);
    bool ok = true;
    for (uint32_t b = 0; ok && b < f->nblocks; b++) {
        ok = ll_block(c, b, last);
    }
    free(last);
    free(c->framed);
    c->framed = NULL;
    c->borrowed = NULL;
    c->temps = NULL;
    ms_arena_free(&scratch);
    if (ok) {
        ms_buf_puts(c->out, "}\n\n");
    }
    return ok;
}

/* The extern the module declares as `name`, or MIR_NONE. */
static uint32_t ll_extern_named(const LCx *c, const char *name) {
    for (uint32_t e = 0; e < c->m->nexterns; e++) {
        if (mir_name_is(c->m, c->m->externs[e].name, name)) {
            return e;
        }
    }
    return MIR_NONE;
}

/* The allocator functions the emitter calls itself (closure objects, `free`), declared with the
 * same word-sized signatures as every runtime function unless the module lists them. */
static void ll_declare_heap(const LCx *c) {
    if (ll_extern_named(c, "msrt_alloc") == MIR_NONE) {
        ms_buf_puts(c->out, "declare i64 @\"msrt_alloc\"(i64)\n");
    }
    if (ll_extern_named(c, "msrt_realloc") == MIR_NONE) {
        ms_buf_puts(c->out, "declare i64 @\"msrt_realloc\"(i64, i64)\n");
    }
    if (ll_extern_named(c, "msrt_free") == MIR_NONE) {
        ms_buf_puts(c->out, "declare void @\"msrt_free\"(ptr)\n");
    }
    if (ll_extern_named(c, "msrt_string_free") == MIR_NONE) {
        ms_buf_puts(c->out, "declare void @\"msrt_string_free\"(ptr)\n");
    }
}

/* One `declare` per runtime function the module lists, in the signature `ll_call_rt` calls it with.
 * A function that never returns says so, so the code after a call of it is unreachable. */
static void ll_declare_externs(LCx *c) {
    MsBuf *o = c->out;
    for (uint32_t e = 0; e < c->m->nexterns; e++) {
        const MirExtern *def = &c->m->externs[e];
        bool listed = false; /* the same runtime function listed twice (the module keeps one entry per signature) */
        for (uint32_t k = 0; k < e && !listed; k++) {
            listed = c->m->externs[k].name == def->name;
        }
        if (listed) {
            continue;
        }
        const MirLeafSpan result = ll_leaves(c, def->ret);
        const bool direct = ll_rt_direct(c, def->ret);
        const char *type = "void";
        if (direct && result.len == 1) {
            type = result.ptr[0] == MIR_LEAF_F32 && ll_extern_is_c(c, def) ? "float" : ll_leaf_type(result.ptr[0]);
        }
        ms_buf_printf(o, "declare %s ", type);
        ll_sym(o, ms_name(&c->m->names, def->name));
        ms_buf_putc(o, '(');
        bool first = true;
        for (uint32_t k = 0; k < def->nparams; k++) {
            const MirLeafSpan leaves = ll_leaves(c, def->params[k].ty);
            if (def->params[k].ty == MIR_PTR || !ll_rt_direct(c, def->params[k].ty)) {
                ms_buf_printf(o, "%sptr", first ? "" : ", ");
                first = false;
                continue;
            }
            for (uint32_t j = 0; j < leaves.len; j++) {
                const char *leaf_type = leaves.ptr[j] == MIR_LEAF_F32 && ll_extern_is_c(c, def) ? "float" : ll_leaf_type(leaves.ptr[j]);
                ms_buf_printf(o, "%s%s", first ? "" : ", ", leaf_type);
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
static const struct {
    const char *name;
    const char *params;
} ll_fault_functions[] = {
    {"msrt_fault_int_overflow", ""}, {"msrt_fault_int_range", ""},          {"msrt_fault_div_zero", ""},
    {"msrt_fault_rem_zero", ""},     {"msrt_fault_div_overflow", "i64, i64"}, {"msrt_index_fault", "i64, i64"},
    {"msrt_fault_unwrap_none", ""},  {"msrt_cancelled", ""},                {"msrt_fault_depth", ""},
};

/* The fault functions the emitter calls itself, unless the module lists one (then `ll_declare_externs` did). */
static void ll_declare_faults(const LCx *c) {
    for (size_t i = 0; i < sizeof ll_fault_functions / sizeof ll_fault_functions[0]; i++) {
        if (ll_extern_named(c, ll_fault_functions[i].name) == MIR_NONE) {
            ms_buf_printf(c->out, "declare void @%s(%s) cold noreturn nounwind\n", ll_fault_functions[i].name,
                          ll_fault_functions[i].params);
        }
    }
}

static const char ll_declarations[] =
    "declare i64 @llvm.fptosi.sat.i64.f64(double)\n"
    "declare ptr @llvm.frameaddress.p0(i32)\n"
    "declare void @llvm.memcpy.p0.p0.i64(ptr, ptr, i64, i1)\n"
    "declare void @llvm.memset.p0.i64(ptr, i8, i64, i1)\n"
    "declare void @llvm.lifetime.start.p0(ptr)\n"
    "declare void @llvm.lifetime.end.p0(ptr)\n"
    "@msrt_ascii_chars = external global [0 x i8]\n"
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
    const uint32_t words = (sym->size + 7) / 8; /* the last word is zero padded */
    ms_buf_printf(o, "[%u x i64] [", words);
    for (uint32_t w = 0; w < words; w++) {
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
        for (uint32_t k = 0; sym->bytes != NULL && k < 8 && w * 8 + k < sym->size; k++) {
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

/* The runtime's descriptors of the scalar types, which code (a `typedesc`) and data both name. */
static const char *const ll_runtime_descs[] = {"msrt_desc_int",    "msrt_desc_float", "msrt_desc_float32",
                                               "msrt_desc_bool",   "msrt_desc_string", "msrt_desc_bytes"};

static bool ll_is_runtime_desc(const char *name) {
    for (size_t k = 0; k < sizeof ll_runtime_descs / sizeof ll_runtime_descs[0]; k++) {
        if (strcmp(ll_runtime_descs[k], name) == 0) {
            return true;
        }
    }
    return false;
}

/* One definition per data symbol, preceded by a declaration of each runtime symbol it names. */
static void ll_define_data(const LCx *c) {
    MsBuf *o = c->out;
    const MirData *d = c->data;
    for (size_t k = 0; k < sizeof ll_runtime_descs / sizeof ll_runtime_descs[0]; k++) {
        ll_data_name(o, ll_runtime_descs[k]);
        ms_buf_puts(o, " = external global i8\n");
    }
    for (uint32_t i = 0; i < d->nsyms; i++) {
        for (uint32_t r = 0; r < d->syms[i].nrelocs; r++) {
            const MirRef ref = d->syms[i].relocs[r].to;
            if (ref.kind == MT_RUNTIME && !ll_is_runtime_desc(ref.runtime) &&
                !ll_runtime_seen(d, i, r, ref.runtime)) {
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

/* Whether function `i` is a scalar function whose result depends on its arguments alone: no memory, no fault, no
 * loop, and only such callees, so it always returns. LLVM cannot see that across a unit boundary, and a call of it
 * may then be merged or dropped. `state[i]` is 0 unvisited, 1 on the path (recursion: not pure), 2 pure, 3 not. */
static bool ll_acyclic_from(const MirFunc *f, uint8_t *color, MirBlock b) {
    if (color[b] != 0) {
        return color[b] == 2;
    }
    color[b] = 1;
    const MirTerm *t = &f->blocks[b].term;
    const bool branch = t->kind == MT_BR || t->kind == MT_CONDBR;
    if (branch && !ll_acyclic_from(f, color, t->a.block)) {
        return false;
    }
    if (t->kind == MT_CONDBR && !ll_acyclic_from(f, color, t->b.block)) {
        return false;
    }
    color[b] = 2;
    return true;
}

static bool ll_pure_function(LCx *c, uint8_t *state, uint32_t i) {
    if (state[i] != 0) {
        return state[i] == 2;
    }
    state[i] = 1;
    const MirFunc *f = &c->m->funcs[i];
    LCx at = *c;
    at.f = f;
    bool pure = ll_leaves(&at, f->ret).len <= 1;
    for (uint32_t k = 0; pure && k < f->nparams; k++) {
        pure = !ll_indirect(&at, f->params[k].ty);
    }
    for (uint32_t b = 0; pure && b < f->nblocks; b++) {
        const MirBlockData *block = &f->blocks[b];
        pure = block->term.kind == MT_BR || block->term.kind == MT_CONDBR || block->term.kind == MT_RET;
        for (uint32_t k = 0; pure && k < block->ninsts; k++) {
            const MirInst *inst = &block->insts[k];
            if (inst->op == MOP_Call) {
                pure = ll_pure_function(c, state, inst->imm.a);
            } else {
                pure = mir_op_info[inst->op].effects == 0 && !mir_op_is_call((MirOp)inst->op);
            }
        }
    }
    if (pure) {
        uint8_t *color = calloc(f->nblocks ? f->nblocks : 1, sizeof *color); /* owned, freed below */
        pure = color != NULL && ll_acyclic_from(f, color, 0);
        free(color);
    }
    state[i] = pure ? 2 : 3;
    return pure;
}

/* Glue calls glue per element-type level, so a deeply nested literal makes a chain. Inlining a chain nests one loop
 * per level and makes the optimizer quadratic in the depth, so glue with three or more levels of glue below it stays
 * out of line; shallow glue still inlines. `depth[i]` is 0 for unvisited, else 1 + the longest chain below `i`;
 * a function on the current path counts as a leaf, which also ends cycles. */
static uint32_t ll_glue_depth(const MirModule *m, const bool *is_glue, uint32_t *depth, uint32_t i) {
    if (depth[i] != 0) {
        return depth[i] - 1;
    }
    depth[i] = 1;
    uint32_t below = 0;
    const MirFunc *f = &m->funcs[i];
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t k = 0; k < f->blocks[b].ninsts; k++) {
            const MirInst *inst = &f->blocks[b].insts[k];
            if (inst->op != MOP_Call || inst->imm.a == i || !is_glue[inst->imm.a]) {
                continue;
            }
            const uint32_t d = 1 + ll_glue_depth(m, is_glue, depth, inst->imm.a);
            below = d > below ? d : below;
        }
    }
    depth[i] = below + 1;
    return below;
}

/* The name tools show for the program's code: the file of its first function that has one, without the folders;
 * "ms" when none has. */
static MsStr ll_source_name(const MirModule *m) {
    MsStr name = {"ms", 2};
    uint32_t file = MIR_NONE;
    for (uint32_t i = 0; i < m->nfuncs && file >= m->nfiles; i++) {
        file = m->funcs[i].loc.file;
    }
    if (file >= m->nfiles) {
        return name;
    }
    name = m->files[file];
    for (uint32_t k = name.len; k > 0; k--) {
        if (name.ptr[k - 1] == '/' || name.ptr[k - 1] == '\\') {
            return (MsStr){name.ptr + k, name.len - k};
        }
    }
    return name;
}

/* The LLVM target triple of the machine the emitter runs on, which is the one the program is built for. Without it
 * a tool that reads the IR alone (`opt`, LLVM's own analyses) assumes a generic layout and sizes loops differently
 * from the compiler. Windows executables link over the mingw-w64 CRT. */
static const char *ll_host_triple(void) {
#if defined(__x86_64__) || defined(_M_X64)
#define LL_ARCH "x86_64"
#elif defined(__aarch64__) || defined(_M_ARM64)
#define LL_ARCH "aarch64"
#else
    return NULL;
#endif
#if defined(__linux__)
    return LL_ARCH "-unknown-linux-gnu";
#elif defined(__APPLE__)
    return LL_ARCH "-apple-darwin";
#elif defined(_WIN32)
    return LL_ARCH "-w64-windows-gnu";
#else
    return NULL;
#endif
}

static bool ll_emit(const MirModule *m, const MirData *data, const MirGlue *glue, const MirLlvmOptions *how,
                    MsBuf *out, MsBuf *why) {
    const bool export_all = how->export_all, places = how->places;
    MirLayouts layouts;
    mir_layouts_init(&layouts, m);
    bool ok = true;
    const char *triple = ll_host_triple();
    if (triple != NULL) {
        ms_buf_printf(out, "target triple = \"%s\"\n", triple);
    }
    LlDebug debug = {0};
    ll_debug_init(&debug);
    LlDebug *dbg = places ? &debug : NULL;
    uint32_t scope_base = 0, total_scopes = 0;
    for (uint32_t i = 0; i < m->nfuncs; i++) {
        total_scopes += m->funcs[i].nscopes;
    }
    bool *is_glue = calloc(m->nfuncs ? m->nfuncs : 1, sizeof *is_glue);      /* owned, freed below */
    uint32_t *depth = calloc(m->nfuncs ? m->nfuncs : 1, sizeof *depth);      /* owned, freed below */
    uint8_t *purity = calloc(m->nfuncs ? m->nfuncs : 1, sizeof *purity);     /* owned, freed below */
    if (is_glue == NULL || depth == NULL || purity == NULL) {
        free(is_glue);
        free(depth);
        free(purity);
        mir_layouts_free(&layouts);
        ms_buf_puts(why, "out of memory\n");
        return false;
    }
    for (uint32_t g = 0; glue != NULL && g < glue->n; g++) {
        is_glue[glue->v[g].func] = true;
    }
    LCx module = {m, NULL, out, &layouts, 0, NULL, data, glue, NULL, NULL, export_all, dbg, 0, 0, false, false, NULL, 0, NULL, false, false};
    for (uint32_t i = 0; i < m->nfuncs; i++) {
        LCx c = {m, &m->funcs[i], out, &layouts, 0, NULL, data, glue, NULL, NULL, export_all, dbg, scope_base,
                 total_scopes + i + 1, is_glue[i] && ll_glue_depth(m, is_glue, depth, i) >= 3,
                 ll_pure_function(&module, purity, i), NULL, 0, NULL, how->slot_scopes, how->poison_slots};
        scope_base += m->funcs[i].nscopes;
        if (ll_function(&c, i)) {
            continue;
        }
        const MsStr name = ms_name(&m->names, m->funcs[i].name);
        ms_buf_printf(why, "%.*s: %s\n", (int)name.len, name.ptr, c.why ? c.why : "unsupported");
        ok = false;
    }
    free(is_glue);
    free(depth);
    free(purity);
    LCx externs = {m, NULL, out, &layouts, 0, NULL, data, glue, NULL, NULL, export_all, NULL, 0, 0, false, false, NULL, 0, NULL, false, false};
    ll_declare_externs(&externs);
    if (data != NULL) {
        ll_define_data(&externs);
    }
    ll_declare_heap(&externs);
    mir_layouts_free(&layouts);
    ll_declare_faults(&externs);
    ms_buf_puts(out, ll_declarations);
    ms_buf_printf(out,
                  "!%d = !{!\"ms.tbaa\"}\n!%d = !{!\"ms.scalar-elem\", !%d, i64 0}\n!%d = !{!%d, !%d, i64 0}\n",
                  LL_TBAA_ROOT, LL_TBAA_SCALAR, LL_TBAA_ROOT, LL_TBAA_SCALAR_TAG, LL_TBAA_SCALAR, LL_TBAA_SCALAR);
    if (places) {
        ll_debug_finish(&debug, ll_source_name(m), out);
    }
    ms_buf_free(&debug.nodes);
    return ok;
}

bool mir_emit_llvm_program(const MirModule *m, const MirData *data, const MirGlue *glue, const MirLlvmOptions *how,
                           MsBuf *out, MsBuf *why) {
    return ll_emit(m, data, glue, how, out, why);
}

bool mir_emit_llvm_with(const MirModule *m, const MirData *data, const MirGlue *glue, bool export_all,
                        MsBuf *out, MsBuf *why) {
    return ll_emit(m, data, glue, &(MirLlvmOptions){.export_all = export_all}, out, why);
}

bool mir_emit_llvm_places(const MirModule *m, const MirData *data, const MirGlue *glue, MsBuf *out, MsBuf *why) {
    return ll_emit(m, data, glue, &(MirLlvmOptions){.places = true}, out, why);
}

bool mir_emit_llvm(const MirModule *m, const MirData *data, const MirGlue *glue, MsBuf *out, MsBuf *why) {
    return ll_emit(m, data, glue, &(MirLlvmOptions){0}, out, why);
}

#include "emit_llvm_main.inc"
