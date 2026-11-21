/* Structural text of a record or enum that has no `to_string` of its own: `Point(x: 1, y: 2)`,
 * `Shape.Circle(1.5)` (crates/ms-lower text.rs `build_format`). One generated function per type,
 * `format(value, depth)`, writes the fields through a string builder in field-name order (an
 * enum's payload in declaration order), each field by the text form of its own type: a scalar
 * through its runtime `to_string`, a String as it is (`""` when empty), a record or enum through
 * its own `format`. A field nested 64 levels deep prints as `...`. A type is formatted by the
 * function its MIR type names, found or built on first use. */
#include <stdlib.h>
#include <string.h>

#include "ms/lower_internal.h"
#include "ms/mir_analysis.h"

enum { LF_MAX_DEPTH = 64 };

static bool lf_name_less(const Lb *lb, MsSym a, MsSym b) {
    const MsStr x = ms_name(&lb->m->names, a), y = ms_name(&lb->m->names, b);
    const size_t n = x.len < y.len ? x.len : y.len;
    const int c = memcmp(x.ptr, y.ptr, n);
    return c != 0 ? c < 0 : x.len < y.len;
}

static MirValue lf_str(Lb *lb, const char *text, size_t len) {
    const MirImm imm = {.tag = MI_STR, .a = mir_add_string(lb->m, text, len)};
    return mir_b_emit(&lb->b, MOP_StrLit, NULL, 0, imm, MIR_STR);
}

/* A call of the string builder function `name` over `args`. */
static MirValue lf_builder_call(Lb *lb, const char *name, const MirValue *args, uint32_t nargs, MirTy ret) {
    MirParam *params = MS_NEW_N(&lb->m->arena, MirParam, (size_t)nargs + 1);
    for (uint32_t i = 0; i < nargs; i++) {
        params[i] = (MirParam){mir_b_ty(&lb->b, args[i]), MM_BORROW};
    }
    const MirExtern ext = {.name = mir_name(lb->m, name, strlen(name)), .params = params, .nparams = nargs, .ret = ret, .leaf = true};
    return mir_b_call_rt(&lb->b, lt_runtime_extern(lb, &ext), args, nargs);
}

static void lf_push(Lb *lb, MirValue buffer, MirValue text) {
    const MirValue args[2] = {buffer, text};
    (void)lf_builder_call(lb, "msrt_strbuf_push", args, 2, MIR_VOID);
}

static void lf_push_text(Lb *lb, MirValue buffer, const char *text) {
    lf_push(lb, buffer, lf_str(lb, text, strlen(text)));
}

static MirValue lf_start(Lb *lb, const char *head, size_t head_len) {
    const MirValue buffer = lf_builder_call(lb, "msrt_strbuf_new", NULL, 0, MIR_PTR);
    if (head_len > 0) {
        lf_push(lb, buffer, lf_str(lb, head, head_len));
    }
    return buffer;
}

static MirValue lf_copy(Lb *lb, MirValue v) {
    return mir_b_emit(&lb->b, MOP_Clone, &v, 1, (MirImm){0}, MIR_STR);
}

static uint32_t lf_helper(Lb *lb, MirTy ty);

/* The checker type of a scalar MIR type, whose runtime declares its text form. */
static MsTy lf_scalar_ty(const Lb *lb, MirTy ty) {
    if (ty == MIR_INT) {
        return lb->int_ty;
    }
    return ty == MIR_FLOAT ? lb->float_ty : lb->bool_ty;
}

/* The text of the nested value `v` of type `ty`, an owned string: `...` once the nesting reaches
 * the limit, else the scalar's `to_string`, the String itself, or the nested type's `format`. */
static MirValue lf_element(Lb *lb, MirTy ty, MirValue v, MirValue depth) {
    MirBuilder *b = &lb->b;
    const MirValue one = mir_b_iconst(b, 1);
    const MirValue child = mir_b_binop(b, MOP_IAdd, depth, one);
    const MirValue limit = mir_b_iconst(b, LF_MAX_DEPTH);
    const MirValue too_deep = mir_b_icmp(b, MCC_GE, child, limit);
    const MirBlock cut = mir_b_new_block(b), fmt = mir_b_new_block(b), join = mir_b_new_block(b);
    const MirValue out = mir_b_add_block_param(b, join, MIR_STR, MM_MOVE);
    mir_b_br_if(b, too_deep, cut, NULL, 0, fmt, NULL, 0);
    mir_b_seal_block(b, cut);
    mir_b_seal_block(b, fmt);
    mir_b_switch_to(b, cut);
    const MirValue dots = lf_copy(lb, lf_str(lb, "...", 3));
    mir_b_br(b, join, &dots, 1);
    mir_b_switch_to(b, fmt);
    MirValue text = MIR_NONE;
    if (ty == MIR_STR) { // an empty string shows as `""`, so `[""]` is not read as `[]`
        const MirValue bytes = mir_b_emit(b, MOP_StrBytes, &v, 1, (MirImm){0}, MIR_INT);
        const MirValue zero = mir_b_iconst(b, 0);
        const MirValue empty = mir_b_icmp(b, MCC_EQ, bytes, zero);
        const MirBlock quoted = mir_b_new_block(b), plain = mir_b_new_block(b);
        mir_b_br_if(b, empty, quoted, NULL, 0, plain, NULL, 0);
        mir_b_seal_block(b, quoted);
        mir_b_seal_block(b, plain);
        mir_b_switch_to(b, quoted);
        const MirValue marks = lf_copy(lb, lf_str(lb, "\"\"", 2));
        mir_b_br(b, join, &marks, 1);
        mir_b_switch_to(b, plain);
        text = lf_copy(lb, v);
    } else if (lb_is_aggregate(lb, ty)) {
        const MirValue args[2] = {v, child};
        text = mir_b_call(b, lf_helper(lb, ty), args, 2);
    } else if (ty == MIR_INT || ty == MIR_FLOAT || ty == MIR_BOOL) {
        const MsTy checked = lf_scalar_ty(lb, ty);
        text = lt_scalar_text(lb, checked, v).v;
        if (text == MIR_NONE && lb->ok) {
            (void)LB_UNSUPPORTED(lb);
        }
    } else {
        (void)LB_UNSUPPORTED(lb); // a list, map or function field has no text form here yet
    }
    if (!lb->ok) {
        return MIR_NONE;
    }
    mir_b_br(b, join, &text, 1);
    mir_b_seal_block(b, join);
    mir_b_switch_to(b, join);
    return out;
}

/* Appends `(label: value, ...)` in `order`; an enum payload has no labels. */
static void lf_fields(Lb *lb, MirValue buffer, const MirField *fields, const uint32_t *order, const MirValue *values,
                      uint32_t count, bool labeled, MirValue depth) {
    lf_push_text(lb, buffer, "(");
    for (uint32_t i = 0; i < count && lb->ok; i++) {
        if (i > 0) {
            lf_push_text(lb, buffer, ", ");
        }
        if (labeled) {
            const MsStr label = ms_name(&lb->m->names, fields[order[i]].name);
            char *text = MS_NEW_N(&lb->b.scratch, char, (size_t)label.len + 3);
            memcpy(text, label.ptr, label.len);
            memcpy(text + label.len, ": ", 3);
            lf_push_text(lb, buffer, text);
        }
        const MirValue piece = lf_element(lb, fields[order[i]].ty, values[i], depth);
        if (!lb->ok) {
            return;
        }
        lf_push(lb, buffer, piece);
        lb_drop(lb, piece);
    }
    lf_push_text(lb, buffer, ")");
}

static MirValue lf_finish(Lb *lb, MirValue buffer) {
    return lf_builder_call(lb, "msrt_strbuf_finish", &buffer, 1, MIR_STR);
}

/* A generic type's text shows its name without the type arguments. */
static size_t lf_base_len(MsStr name) {
    const char *bracket = memchr(name.ptr, '[', name.len);
    return bracket == NULL ? name.len : (size_t)(bracket - name.ptr);
}

static void lf_record(Lb *lb, MirTy ty, MirValue value, MirValue depth) {
    const MirTypeDef *def = &lb->m->type_defs[mir_ty_data(lb->m, ty)->id];
    uint32_t *order = MS_NEW_N(&lb->b.scratch, uint32_t, (size_t)def->nfields + 1);
    MirValue *values = MS_NEW_N(&lb->b.scratch, MirValue, (size_t)def->nfields + 1);
    for (uint32_t i = 0; i < def->nfields; i++) {
        order[i] = i;
    }
    for (uint32_t i = 1; i < def->nfields; i++) { // insertion sort by field name: text lists fields alphabetically
        const uint32_t moving = order[i];
        uint32_t j = i;
        for (; j > 0 && lf_name_less(lb, def->fields[moving].name, def->fields[order[j - 1]].name); j--) {
            order[j] = order[j - 1];
        }
        order[j] = moving;
    }
    const MirImm imm = {.tag = MI_FIELD, .a = mir_ty_data(lb->m, ty)->id};
    for (uint32_t i = 0; i < def->nfields; i++) {
        MirImm field = imm;
        field.b = order[i];
        values[i] = mir_b_emit(&lb->b, MOP_TypeGet, &value, 1, field, def->fields[order[i]].ty);
    }
    const MsStr name = ms_name(&lb->m->names, def->name);
    const MirValue buffer = lf_start(lb, name.ptr, lf_base_len(name));
    lf_fields(lb, buffer, def->fields, order, values, def->nfields, true, depth);
    mir_b_ret(&lb->b, lf_finish(lb, buffer));
}

static void lf_enum(Lb *lb, MirTy ty, MirValue value, MirValue depth) {
    const MirAltDef *def = &lb->m->alts[mir_ty_data(lb->m, ty)->id];
    const MirValue tag = mir_b_emit(&lb->b, MOP_AltTag, &value, 1, (MirImm){0}, MIR_INT);
    MirBlock *blocks = MS_NEW_N(&lb->b.scratch, MirBlock, (size_t)def->ncases + 1);
    MirCase *cases = MS_NEW_N(&lb->b.scratch, MirCase, (size_t)def->ncases + 1);
    for (uint32_t i = 0; i < def->ncases; i++) {
        blocks[i] = mir_b_new_block(&lb->b);
        cases[i] = (MirCase){(int64_t)i, {blocks[i], NULL, 0}};
    }
    mir_b_switch(&lb->b, tag, cases, def->ncases, blocks[0]);
    const MsStr type_name = ms_name(&lb->m->names, def->name);
    for (uint32_t i = 0; i < def->ncases && lb->ok; i++) {
        const MirCaseDef *row = &def->cases[i];
        mir_b_seal_block(&lb->b, blocks[i]);
        mir_b_switch_to(&lb->b, blocks[i]);
        const MsStr case_name = ms_name(&lb->m->names, row->name);
        const bool bare = def->std == MSTD_RESULT; // a Result prints as its cases (`ok(1)`)
        const size_t prefix = bare ? 0 : lf_base_len(type_name) + 1;
        char *head = MS_NEW_N(&lb->b.scratch, char, prefix + case_name.len + 1);
        if (!bare) {
            memcpy(head, type_name.ptr, prefix - 1);
            head[prefix - 1] = '.';
        }
        memcpy(head + prefix, case_name.ptr, case_name.len);
        const MirValue buffer = lf_start(lb, head, prefix + case_name.len);
        if (row->nfields > 0) {
            uint32_t *order = MS_NEW_N(&lb->b.scratch, uint32_t, (size_t)row->nfields + 1);
            MirValue *values = MS_NEW_N(&lb->b.scratch, MirValue, (size_t)row->nfields + 1);
            for (uint32_t slot = 0; slot < row->nfields; slot++) {
                order[slot] = slot;
                const MirImm field = {.tag = MI_ALTFIELD, .a = mir_ty_data(lb->m, ty)->id, .b = i, .c = slot};
                values[slot] = mir_b_emit(&lb->b, MOP_AltGet, &value, 1, field, row->fields[slot].ty);
            }
            lf_fields(lb, buffer, row->fields, order, values, row->nfields, false, depth);
        }
        mir_b_ret(&lb->b, lf_finish(lb, buffer));
    }
}

/* `none`, or `some(payload)`. */
static void lf_optional(Lb *lb, MirTy ty, MirValue value, MirValue depth) {
    MirBuilder *b = &lb->b;
    const MirBlock some = mir_b_new_block(b), none = mir_b_new_block(b);
    mir_b_br_if(b, la_test(lb, value), some, NULL, 0, none, NULL, 0);
    mir_b_seal_block(b, some);
    mir_b_seal_block(b, none);
    mir_b_switch_to(b, none);
    mir_b_ret(b, lf_finish(lb, lf_start(lb, "none", 4)));
    mir_b_switch_to(b, some);
    const MirValue payload = mir_b_emit(b, MOP_OptGet, &value, 1, (MirImm){0}, mir_ty_data(lb->m, ty)->elem);
    const MirValue buffer = lf_start(lb, "some", 4);
    lf_push_text(lb, buffer, "(");
    const MirValue piece = lf_element(lb, mir_ty_data(lb->m, ty)->elem, payload, depth);
    if (!lb->ok) {
        return;
    }
    lf_push(lb, buffer, piece);
    lb_drop(lb, piece);
    lf_push_text(lb, buffer, ")");
    mir_b_ret(b, lf_finish(lb, buffer));
}

/* `[a, b, c]`: a loop over the elements with a separator before every one but the first. */
static void lf_list(Lb *lb, MirTy ty, MirValue value, MirValue depth) {
    MirBuilder *b = &lb->b;
    const MirTy elem = mir_ty_data(lb->m, ty)->elem;
    const MirValue buffer = lf_start(lb, "[", 1);
    const MirVar index = mir_b_declare_var(b, MIR_INT, MM_BORROW);
    const MirValue zero = mir_b_iconst(b, 0);
    mir_b_def_var(b, index, zero);
    const MirValue length = mir_b_emit(b, MOP_ListLen, &value, 1, (MirImm){0}, MIR_INT);
    const MirBlock header = mir_b_new_block(b), body = mir_b_new_block(b), exit = mir_b_new_block(b);
    mir_b_br(b, header, NULL, 0);
    mir_b_switch_to(b, header);
    const MirValue more = mir_b_icmp(b, MCC_LT, mir_b_use_var(b, index), length);
    mir_b_br_if(b, more, body, NULL, 0, exit, NULL, 0);
    mir_b_seal_block(b, body);
    mir_b_switch_to(b, body);
    const MirValue first = mir_b_icmp(b, MCC_EQ, mir_b_use_var(b, index), zero);
    const MirBlock separate = mir_b_new_block(b), item = mir_b_new_block(b);
    mir_b_br_if(b, first, item, NULL, 0, separate, NULL, 0);
    mir_b_seal_block(b, separate);
    mir_b_seal_block(b, item);
    mir_b_switch_to(b, separate);
    lf_push_text(lb, buffer, ", ");
    mir_b_br(b, item, NULL, 0);
    mir_b_switch_to(b, item);
    const MirValue at[2] = {value, mir_b_use_var(b, index)};
    const MirValue element = mir_b_emit(b, MOP_ListGet, at, 2, (MirImm){0}, elem);
    const MirValue piece = lf_element(lb, elem, element, depth);
    if (!lb->ok) {
        return;
    }
    lf_push(lb, buffer, piece);
    lb_drop(lb, piece);
    const MirValue current = mir_b_use_var(b, index);
    const MirValue one = mir_b_iconst(b, 1);
    mir_b_def_var(b, index, mir_b_binop(b, MOP_IAdd, current, one));
    mir_b_br(b, header, NULL, 0);
    mir_b_seal_block(b, header);
    mir_b_seal_block(b, exit);
    mir_b_switch_to(b, exit);
    lf_push_text(lb, buffer, "]");
    mir_b_ret(b, lf_finish(lb, buffer));
}

/* Builds `format(value, depth)` for `ty` into the module; MIR_NONE when a field has no text form here. */
static uint32_t lf_build(Lb *lb, MirTy ty) {
    MirBuilder outer = lb->b;
    const MirParam params[2] = {{ty, MM_BORROW}, {MIR_INT, MM_BORROW}};
    mir_b_init(&lb->b, lb->m, mir_name(lb->m, "format", 6), params, 2, MIR_STR);
    lb_emit_plain(lb, MOP_DepthEnter);
    MirValue args[2];
    mir_b_params(&lb->b, args, 2);
    const uint8_t kind = mir_ty_data(lb->m, ty)->kind;
    if (kind == MK_TYPE) {
        lf_record(lb, ty, args[0], args[1]);
    } else if (kind == MK_ALT) {
        lf_enum(lb, ty, args[0], args[1]);
    } else if (kind == MK_OPT) {
        lf_optional(lb, ty, args[0], args[1]);
    } else {
        lf_list(lb, ty, args[0], args[1]);
    }
    MirFunc f = {0};
    const bool built = mir_b_into_func(&lb->b, &f);
    lb->b = outer;
    if (built) {
        mir_func_compact_blocks(&f); // blocks in reverse post-order, as every generated function is laid out
    }
    return lb->ok && built ? mir_add_func(lb->m, &f) : MIR_NONE;
}

/* The `format` function of `ty`, built on first use. */
static uint32_t lf_helper(Lb *lb, MirTy ty) {
    const MsSym name = mir_name(lb->m, "format", 6);
    for (uint32_t i = 0; i < lb->m->nfuncs; i++) {
        const MirFunc *f = &lb->m->funcs[i];
        if (f->name == name && f->nparams == 2 && f->params[0].ty == ty) {
            return i;
        }
    }
    return lf_build(lb, ty);
}

/* `value.to_string()` where the type declares no runtime method of that name: a String's copy of itself, the scalar's
 * runtime text form, or the structural text of a record or enum; another type marks the function unsupported. */
LbVal lt_to_string(Lb *lb, LbVal value, MsTy checked) {
    if (mir_b_ty(&lb->b, value.v) == MIR_STR) {
        return value.owned ? value : (LbVal){lf_copy(lb, value.v), true};
    }
    const LbVal text = lt_scalar_text(lb, checked, value.v);
    if (!lb->ok) {
        return LB_FAIL;
    }
    if (text.v == MIR_NONE) { // no declared text form: a record or enum prints its fields (owns and drops `value`)
        return lf_text(lb, value);
    }
    if (value.owned) {
        lb_drop(lb, value.v);
    }
    return text;
}

LbVal lf_text(Lb *lb, LbVal value) {
    const MirTy ty = mir_b_ty(&lb->b, value.v);
    if (!lb_is_aggregate(lb, ty)) {
        return LB_UNSUPPORTED(lb); // maps and functions have their own text, not lowered yet
    }
    const uint32_t func = lf_helper(lb, ty);
    if (func == MIR_NONE || !lb->ok) {
        return LB_UNSUPPORTED(lb);
    }
    const MirValue args[2] = {value.v, mir_b_iconst(&lb->b, 0)};
    const MirValue text = mir_b_call(&lb->b, func, args, 2);
    if (value.owned) {
        lb_drop(lb, value.v);
    }
    return (LbVal){text, true};
}
