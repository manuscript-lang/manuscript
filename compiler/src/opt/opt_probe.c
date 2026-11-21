/* The `probe` pass: a lookup in a map or set with a fixed slot layout runs as a short probe loop in
 * the caller instead of a runtime call.
 *
 * A `Map[Int, word]`, a `Map[String, word]` and a `Set[Int]` store hash, key and value in slots the
 * generated code can read (runtime/core/map*.c). Lowering declares the runtime lookups for those
 * shapes with a role (`map_probe_int`, `map_probe_str`, `set_probe_int`); what the call answers
 * follows from its signature: a pointer is the value's address (null when absent), a bool with four
 * parameters is "contains", a bool with five also copies the value to the last parameter. No symbol
 * name is read. Each (shape, answer, map type) gets one generated function marked `inline(always)`,
 * which the inliner places in the caller, where the loop is optimised with the key computation and
 * the use of the value. Port of the former Rust crates/ms-lower/src/rtinline.rs probes.
 *
 * The map is read through its memory form, seven words: slots pointer, index pointer, length, used,
 * capacity, mask, descriptor. An index entry holds the hash tag in its high 32 bits and the slot
 * number plus one in its low 32 bits; zero is an empty entry. A slot's hash word has its top bit set
 * for a live entry. The hash functions are those of runtime/core/map_hash.c. */
#include <stdio.h>
#include <string.h>

#include "ms/mir_builder.h"
#include "ms/mir_opt.h"
#include "ms/mir_pass.h"

enum { PB_SLOTS = 0, PB_INDEX = 8, PB_LEN = 16, PB_MASK = 40 };
#define PB_LIVE INT64_MIN
#define PB_K0 ((int64_t)UINT64_C(0x9e3779b97f4a7c15))
#define PB_K1 ((int64_t)UINT64_C(0xff51afd7ed558ccd))
#define PB_LEN_MASK ((INT64_C(1) << 31) - 1)

typedef enum PbAnswer { PA_ADDRESS, PA_CONTAINS, PA_GET } PbAnswer;

typedef struct PbShape {
    int64_t stride;   /* bytes per slot */
    int64_t value_at; /* where the result points inside a slot */
    bool text;        /* the key is a String */
} PbShape;

static bool pb_shape(uint8_t role, PbShape *out) {
    switch (role) {
    case MR_MAP_PROBE_INT: *out = (PbShape){24, 16, false}; return true;
    case MR_MAP_PROBE_STR: *out = (PbShape){32, 24, true}; return true;
    case MR_SET_PROBE_INT: *out = (PbShape){16, 8, false}; return true;
    default: return false;
    }
}

static MirValue pb_add(MirBuilder *b, MirValue p, int64_t at) {
    if (at == 0) {
        return p;
    }
    const MirValue args[2] = {p, mir_b_iconst(b, at)};
    return mir_b_emit(b, MOP_PtrAdd, args, 2, (MirImm){0}, MIR_PTR);
}

static MirValue pb_past(MirBuilder *b, MirValue p, MirValue by) {
    const MirValue args[2] = {p, by};
    return mir_b_emit(b, MOP_PtrAdd, args, 2, (MirImm){0}, MIR_PTR);
}

static MirValue pb_load(MirBuilder *b, MirValue p, int64_t at, MirTy ty) {
    const MirValue addr = pb_add(b, p, at);
    return mir_b_emit(b, MOP_Load, &addr, 1, (MirImm){.tag = MI_TY, .a = ty}, ty);
}

static MirValue pb_loadu(MirBuilder *b, MirValue p, int64_t width) {
    return mir_b_emit(b, MOP_PtrLoadU, &p, 1, (MirImm){.tag = MI_INT, .i = width}, MIR_INT);
}

static MirValue pb_int(MirBuilder *b, MirOp op, MirValue x, int64_t y) {
    return mir_b_binop(b, op, x, mir_b_iconst(b, y));
}

static MirValue pb_and(MirBuilder *b, MirValue x, MirValue y) { return mir_b_binop(b, MOP_And, x, y); }

static MirValue pb_fold(MirBuilder *b, MirValue x, int64_t m) {
    const MirValue k = mir_b_iconst(b, m);
    return mir_b_binop(b, MOP_Xor, mir_b_binop(b, MOP_IMul, x, k), mir_b_binop(b, MOP_UMulHi, x, k));
}

static void pb_br_if(MirBuilder *b, MirValue cond, MirBlock then, MirBlock other) {
    mir_b_br_if(b, cond, then, NULL, 0, other, NULL, 0);
    mir_b_seal_block(b, then);
    mir_b_seal_block(b, other);
}

/* `hash_bytes` of the key string at `key` (`k` is the same string as a value): short inline strings
 * are hashed from their two words, which is what lets a lookup run without a call; a text of sixteen
 * bytes or more is folded here, eight bytes at a time; the rare short text that is not inline calls
 * the runtime, which hashes it the same way. */
static MirValue pb_string_hash(MirBuilder *b, MirModule *m, MirValue key, MirValue k) {
    const MirValue w0 = pb_load(b, key, 0, MIR_INT), w1 = pb_load(b, key, 8, MIR_INT);
    const MirValue tag = pb_int(b, MOP_Ushr, w1, 62);
    const MirValue is_inline = mir_b_icmp(b, MCC_EQ, tag, mir_b_iconst(b, 1));
    const MirBlock shorter = mir_b_new_block(b), longer = mir_b_new_block(b), done = mir_b_new_block(b);
    const MirVar hash = mir_b_declare_var(b, MIR_INT, MM_BORROW);
    pb_br_if(b, is_inline, shorter, longer);
    mir_b_switch_to(b, longer);
    const MirValue size = pb_int(b, MOP_And, w1, PB_LEN_MASK);
    const MirValue wide = mir_b_icmp(b, MCC_GE, size, mir_b_iconst(b, 16));
    const MirBlock fold_in = mir_b_new_block(b), call = mir_b_new_block(b);
    const MirBlock header = mir_b_new_block(b), body = mir_b_new_block(b), tail = mir_b_new_block(b);
    pb_br_if(b, wide, fold_in, call);
    mir_b_switch_to(b, call);
    const MirTy str_param[1] = {MIR_STR};
    const uint32_t ext = mir_extern_get(m, "msrt_string_hash", str_param, 1, MIR_INT, true, MR_NONE);
    mir_b_def_var(b, hash, mir_b_call_rt(b, ext, &k, 1));
    mir_b_br(b, done, NULL, 0);
    mir_b_switch_to(b, fold_in);
    const MirValue data = pb_load(b, key, 0, MIR_PTR);
    const MirValue h0 = pb_int(b, MOP_Xor, pb_int(b, MOP_IMul, size, PB_K1), PB_K0);
    const MirVar acc = mir_b_declare_var(b, MIR_INT, MM_BORROW), at = mir_b_declare_var(b, MIR_INT, MM_BORROW);
    mir_b_def_var(b, acc, h0);
    mir_b_def_var(b, at, mir_b_iconst(b, 0));
    mir_b_br(b, header, NULL, 0);
    mir_b_switch_to(b, header);
    const MirValue i = mir_b_use_var(b, at);
    const MirValue end = pb_int(b, MOP_IAdd, i, 8);
    pb_br_if(b, mir_b_icmp(b, MCC_LE, end, size), body, tail);
    mir_b_switch_to(b, body);
    const MirValue word = pb_loadu(b, pb_past(b, data, i), 8);
    mir_b_def_var(b, acc, pb_fold(b, mir_b_binop(b, MOP_Xor, mir_b_use_var(b, acc), word), PB_K1));
    mir_b_def_var(b, at, end);
    mir_b_br(b, header, NULL, 0);
    mir_b_seal_block(b, header);
    mir_b_switch_to(b, tail);
    const MirValue last = pb_loadu(b, pb_past(b, data, pb_int(b, MOP_ISub, size, 8)), 8);
    mir_b_def_var(b, hash, pb_fold(b, mir_b_binop(b, MOP_Xor, mir_b_use_var(b, acc), last), PB_K0));
    mir_b_br(b, done, NULL, 0);
    mir_b_switch_to(b, shorter);
    /* Length, and the bytes past the eighth (the string keeps the rest of its words zero). */
    const MirValue n = pb_int(b, MOP_And, pb_int(b, MOP_Ushr, w1, 56), 15);
    const MirValue high = pb_int(b, MOP_And, w1, (INT64_C(1) << 56) - 1);
    const MirValue s0 = pb_int(b, MOP_Xor, pb_int(b, MOP_IMul, n, PB_K1), PB_K0);
    const MirValue h1 = pb_fold(b, mir_b_binop(b, MOP_Xor, s0, w0), PB_K1);
    mir_b_def_var(b, hash, pb_fold(b, mir_b_binop(b, MOP_Xor, h1, high), PB_K0));
    mir_b_br(b, done, NULL, 0);
    mir_b_seal_block(b, done);
    mir_b_switch_to(b, done);
    return mir_b_use_var(b, hash);
}

/* Whether the slot's string equals the key's: equal words (an inline string, or the very same block)
 * decide it, two blocks of 16 to 32 bytes compare with four overlapping words, and the general
 * comparison handles the rest. */
static MirValue pb_text_matches(MirBuilder *b, MirModule *m, MirValue slot, MirValue key, MirValue k,
                                MirValue h) {
    const MirBlock words = mir_b_new_block(b), compare = mir_b_new_block(b), matched = mir_b_new_block(b);
    const MirVar verdict = mir_b_declare_var(b, MIR_BOOL, MM_BORROW);
    mir_b_def_var(b, verdict, mir_b_bconst(b, false));
    const MirValue stored = pb_load(b, slot, 0, MIR_INT);
    pb_br_if(b, mir_b_icmp(b, MCC_EQ, stored, h), words, matched);
    mir_b_switch_to(b, words);
    const MirValue e0 = mir_b_icmp(b, MCC_EQ, pb_load(b, slot, 8, MIR_INT), pb_load(b, key, 0, MIR_INT));
    const MirValue e1 = mir_b_icmp(b, MCC_EQ, pb_load(b, slot, 16, MIR_INT), pb_load(b, key, 8, MIR_INT));
    mir_b_def_var(b, verdict, mir_b_bconst(b, true));
    pb_br_if(b, pb_and(b, e0, e1), matched, compare);
    mir_b_switch_to(b, compare);
    const MirValue sw = pb_load(b, slot, 16, MIR_INT), kw = pb_load(b, key, 8, MIR_INT);
    const MirValue sn = pb_int(b, MOP_And, sw, PB_LEN_MASK), kn = pb_int(b, MOP_And, kw, PB_LEN_MASK);
    const MirValue one = mir_b_iconst(b, 1);
    const MirValue sf = mir_b_icmp(b, MCC_NE, pb_int(b, MOP_Ushr, sw, 62), one);
    const MirValue kf = mir_b_icmp(b, MCC_NE, pb_int(b, MOP_Ushr, kw, 62), one);
    const MirValue conds[3] = {mir_b_icmp(b, MCC_EQ, sn, kn), mir_b_icmp(b, MCC_GE, sn, mir_b_iconst(b, 16)),
                               mir_b_icmp(b, MCC_LE, sn, mir_b_iconst(b, 32))};
    MirValue wide = pb_and(b, sf, kf);
    for (uint32_t i = 0; i < 3; i++) {
        wide = pb_and(b, wide, conds[i]);
    }
    const MirBlock blocks = mir_b_new_block(b), general = mir_b_new_block(b);
    pb_br_if(b, wide, blocks, general);
    mir_b_switch_to(b, blocks);
    const MirValue sp = pb_load(b, slot, 8, MIR_PTR), kp = pb_load(b, key, 0, MIR_PTR);
    const MirValue offsets[4] = {MIR_NONE, mir_b_iconst(b, 8), pb_int(b, MOP_ISub, sn, 16),
                                 pb_int(b, MOP_ISub, sn, 8)};
    MirValue all = mir_b_bconst(b, true);
    for (uint32_t i = 0; i < 4; i++) {
        const MirValue x = i == 0 ? sp : pb_past(b, sp, offsets[i]);
        const MirValue y = i == 0 ? kp : pb_past(b, kp, offsets[i]);
        all = pb_and(b, all, mir_b_icmp(b, MCC_EQ, pb_loadu(b, x, 8), pb_loadu(b, y, 8)));
    }
    mir_b_def_var(b, verdict, all);
    mir_b_br(b, matched, NULL, 0);
    mir_b_switch_to(b, general);
    const MirTy two_strs[2] = {MIR_STR, MIR_STR};
    const uint32_t eq = mir_extern_get(m, "msrt_string_eq", two_strs, 2, MIR_BOOL, true, MR_STRING_EQ);
    const MirValue pair[2] = {pb_load(b, slot, 8, MIR_STR), k};
    mir_b_def_var(b, verdict, mir_b_call_rt(b, eq, pair, 2));
    mir_b_br(b, matched, NULL, 0);
    mir_b_seal_block(b, matched);
    mir_b_switch_to(b, matched);
    return mir_b_use_var(b, verdict);
}

/* The probe loop: the value address of the key at `key` in the map at `map`, or null. */
static MirValue pb_find(MirBuilder *b, MirModule *m, const PbShape *shape, MirValue map, MirValue key) {
    const MirValue null = mir_b_emit(b, MOP_PtrNull, NULL, 0, (MirImm){0}, MIR_PTR);
    const MirBlock go = mir_b_new_block(b), hit = mir_b_new_block(b), miss = mir_b_new_block(b);
    const MirValue len = pb_load(b, map, PB_LEN, MIR_INT);
    pb_br_if(b, mir_b_icmp(b, MCC_EQ, len, mir_b_iconst(b, 0)), miss, go);
    mir_b_switch_to(b, go);
    const MirValue k = pb_load(b, key, 0, shape->text ? MIR_STR : MIR_INT);
    MirValue h;
    if (shape->text) {
        h = pb_string_hash(b, m, key, k);
    } else {
        const MirValue x = pb_int(b, MOP_Xor, k, PB_K0);
        h = mir_b_binop(b, MOP_Xor, pb_int(b, MOP_IMul, x, PB_K1), mir_b_binop(b, MOP_UMulHi, x, mir_b_iconst(b, PB_K1)));
    }
    h = pb_int(b, MOP_Or, h, PB_LIVE);
    const MirValue index = pb_load(b, map, PB_INDEX, MIR_PTR);
    const MirValue slots = pb_load(b, map, PB_SLOTS, MIR_PTR);
    const MirValue mask = pb_load(b, map, PB_MASK, MIR_INT);
    const MirValue start = pb_and(b, mir_b_binop(b, MOP_Xor, h, pb_int(b, MOP_Ushr, h, 32)), mask);
    const MirVar pos = mir_b_declare_var(b, MIR_INT, MM_BORROW);
    mir_b_def_var(b, pos, start);
    const MirBlock header = mir_b_new_block(b), tagged = mir_b_new_block(b), check = mir_b_new_block(b);
    const MirBlock next = mir_b_new_block(b);
    mir_b_br(b, header, NULL, 0);
    mir_b_switch_to(b, header);
    const MirValue at = mir_b_use_var(b, pos);
    const MirValue entry = mir_b_emit(b, MOP_Load, (MirValue[]){pb_past(b, index, pb_int(b, MOP_Shl, at, 3))}, 1,
                                      (MirImm){.tag = MI_TY, .a = MIR_INT}, MIR_INT);
    pb_br_if(b, mir_b_icmp(b, MCC_EQ, entry, mir_b_iconst(b, 0)), miss, tagged);
    mir_b_switch_to(b, tagged);
    const MirValue diff = mir_b_binop(b, MOP_Xor, entry, h);
    pb_br_if(b, mir_b_icmp(b, MCC_EQ, pb_int(b, MOP_Ushr, diff, 32), mir_b_iconst(b, 0)), check, next);
    mir_b_switch_to(b, check);
    const MirValue number = pb_int(b, MOP_ISub, pb_int(b, MOP_And, entry, 0xffffffff), 1);
    const MirValue slot = pb_past(b, slots, pb_int(b, MOP_IMul, number, shape->stride));
    MirValue found;
    if (shape->text) {
        found = pb_text_matches(b, m, slot, key, k, h);
    } else {
        found = mir_b_icmp(b, MCC_EQ, pb_load(b, slot, 8, MIR_INT), k);
    }
    pb_br_if(b, found, hit, next);
    mir_b_switch_to(b, next);
    mir_b_def_var(b, pos, pb_and(b, pb_int(b, MOP_IAdd, at, 1), mask));
    mir_b_br(b, header, NULL, 0);
    mir_b_seal_block(b, header);
    const MirVar out = mir_b_declare_var(b, MIR_PTR, MM_BORROW);
    const MirBlock done = mir_b_new_block(b);
    mir_b_switch_to(b, miss);
    mir_b_def_var(b, out, null);
    mir_b_br(b, done, NULL, 0);
    mir_b_switch_to(b, hit);
    mir_b_def_var(b, out, pb_add(b, slot, shape->value_at));
    mir_b_br(b, done, NULL, 0);
    mir_b_seal_block(b, done);
    mir_b_switch_to(b, done);
    return mir_b_use_var(b, out);
}

static MirValue pb_is_null(MirBuilder *b, MirValue p) {
    return mir_b_emit(b, MOP_PtrIsNull, &p, 1, (MirImm){0}, MIR_BOOL);
}

/* The answer built from the address `p` the probe found; `out` is the address a `get` copies to. */
static MirValue pb_answer(MirBuilder *b, PbAnswer answer, MirValue p, MirValue out) {
    if (answer == PA_ADDRESS) {
        return p;
    }
    const MirValue missing = pb_is_null(b, p);
    if (answer == PA_CONTAINS) {
        return mir_b_emit(b, MOP_Not, &missing, 1, (MirImm){0}, MIR_BOOL);
    }
    const MirBlock copy = mir_b_new_block(b), done = mir_b_new_block(b);
    const MirVar verdict = mir_b_declare_var(b, MIR_BOOL, MM_BORROW);
    mir_b_def_var(b, verdict, mir_b_bconst(b, false));
    pb_br_if(b, missing, done, copy);
    mir_b_switch_to(b, copy);
    const MirValue stored[2] = {out, pb_load(b, p, 0, MIR_INT)};
    (void)mir_b_emit(b, MOP_Store, stored, 2, (MirImm){0}, MIR_NONE);
    mir_b_def_var(b, verdict, mir_b_bconst(b, true));
    mir_b_br(b, done, NULL, 0);
    mir_b_seal_block(b, done);
    mir_b_switch_to(b, done);
    return mir_b_use_var(b, verdict);
}

/* Builds `map_probe(map, key[, out])`; a map value is stored to a slot to be read through its memory
 * form, a map held in memory arrives as its address. */
static uint32_t pb_build(MirModule *m, const PbShape *shape, PbAnswer answer, MirTy map_ty) {
    MirParam params[3] = {{map_ty, MM_BORROW}, {MIR_PTR, MM_BORROW}, {MIR_PTR, MM_BORROW}};
    MirBuilder b;
    char name[32]; /* the module needs distinct names: one helper per shape, answer and map type */
    (void)snprintf(name, sizeof name, "map_probe.%u", m->nfuncs);
    mir_b_init_fast_path(&b, m, ms_intern_cstr(&m->names, name), params, answer == PA_GET ? 3 : 2,
                         answer == PA_ADDRESS ? MIR_PTR : MIR_BOOL);
    MirValue ps[3];
    mir_b_params(&b, ps, 3);
    MirValue map = ps[0];
    if (map_ty != MIR_PTR) {
        map = mir_b_emit(&b, MOP_Slot, NULL, 0, (MirImm){.tag = MI_TY, .a = map_ty}, MIR_PTR);
        const MirValue stored[2] = {map, ps[0]};
        (void)mir_b_emit(&b, MOP_Store, stored, 2, (MirImm){0}, MIR_NONE);
    }
    const MirValue p = pb_find(&b, m, shape, map, ps[1]);
    mir_b_ret(&b, pb_answer(&b, answer, p, ps[2]));
    uint32_t id = MIR_NONE;
    return mir_b_finish(&b, &id) ? id : MIR_NONE;
}

/* What a call to extern `e` answers, or false when it is not a probe. */
static bool pb_probe_of(const MirModule *m, uint32_t e, PbShape *shape, PbAnswer *answer) {
    const MirExtern *ext = &m->externs[e];
    if (!pb_shape(ext->role, shape)) {
        return false;
    }
    if (ext->ret == MIR_PTR) {
        *answer = PA_ADDRESS;
    } else {
        *answer = ext->nparams == 5 ? PA_GET : PA_CONTAINS;
    }
    return true;
}

typedef struct PbHelper {
    uint8_t role;
    PbAnswer answer;
    MirTy map_ty;
    uint32_t func;
} PbHelper;

bool mir_opt_probe(MirModule *m) {
    const uint32_t original = m->nfuncs; /* the helpers keep their own calls to the runtime */
    PbHelper *helpers = NULL;
    uint32_t nhelpers = 0, chelpers = 0;
    bool changed = false;
    for (uint32_t fi = 0; fi < original; fi++) {
        for (uint32_t bi = 0; bi < m->funcs[fi].nblocks; bi++) {
            for (uint32_t ii = 0; ii < m->funcs[fi].blocks[bi].ninsts; ii++) {
                MirInst *inst = &m->funcs[fi].blocks[bi].insts[ii];
                PbShape shape;
                PbAnswer answer;
                if (inst->op != MOP_CallRt || !pb_probe_of(m, inst->imm.a, &shape, &answer)) {
                    continue;
                }
                const uint8_t role = m->externs[inst->imm.a].role;
                const MirTy map_ty = mir_value_ty(&m->funcs[fi], inst->args[0]);
                uint32_t helper = MIR_NONE;
                for (uint32_t h = 0; h < nhelpers; h++) {
                    if (helpers[h].role == role && helpers[h].answer == answer && helpers[h].map_ty == map_ty) {
                        helper = helpers[h].func;
                    }
                }
                if (helper == MIR_NONE) {
                    helper = pb_build(m, &shape, answer, map_ty);
                    if (helper == MIR_NONE) {
                        continue;
                    }
                    MIR_PUSH(m, helpers, nhelpers, chelpers, PbHelper, ((PbHelper){role, answer, map_ty, helper}));
                    inst = &m->funcs[fi].blocks[bi].insts[ii]; /* the function array may have moved */
                }
                /* The descriptors are unused: the helper takes the map, the key, and for a get the
                 * address to copy to. */
                const uint32_t kept = answer == PA_GET ? 3 : 2;
                MirValue *args = MS_NEW_N(&m->arena, MirValue, kept);
                args[0] = inst->args[0];
                args[1] = inst->args[3];
                if (answer == PA_GET) {
                    args[2] = inst->args[4];
                }
                inst->args = args;
                inst->nargs = kept;
                inst->op = MOP_Call;
                inst->imm = (MirImm){.tag = MI_FUNC, .a = helper};
                changed = true;
            }
        }
    }
    return changed;
}
