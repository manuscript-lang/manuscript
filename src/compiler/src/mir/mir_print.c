/* The MIR text printer (print.rs). Values are renumbered densely in definition order and blocks are
 * labelled by index, so printing a parsed module gives the canonical text. */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/mir.h"

static void mp_sym(const MirModule *m, MsBuf *o, MsSym s) {
    MsStr n = ms_name(&m->names, s);
    ms_buf_put(o, n.ptr, n.len);
}

static void mp_ty(const MirModule *m, MirTy t, MsBuf *o) {
    const MirTyData *d = mir_ty_data(m, t);
    switch ((MirTyKind)d->kind) {
    case MK_VOID: ms_buf_puts(o, "void"); break;
    case MK_BOOL: ms_buf_puts(o, "bool"); break;
    case MK_INT: ms_buf_puts(o, "int"); break;
    case MK_FLOAT: ms_buf_puts(o, "float"); break;
    case MK_INT8: ms_buf_puts(o, "int8"); break;
    case MK_INT16: ms_buf_puts(o, "int16"); break;
    case MK_INT32: ms_buf_puts(o, "int32"); break;
    case MK_FLOAT32: ms_buf_puts(o, "float32"); break;
    case MK_UINT8: ms_buf_puts(o, "uint8"); break;
    case MK_UINT16: ms_buf_puts(o, "uint16"); break;
    case MK_UINT32: ms_buf_puts(o, "uint32"); break;
    case MK_UINT64: ms_buf_puts(o, "uint64"); break;
    case MK_STR: ms_buf_puts(o, "str"); break;
    case MK_BYTES: ms_buf_puts(o, "bytes"); break;
    case MK_PTR: ms_buf_puts(o, "ptr"); break;
    case MK_TYPE: mp_sym(m, o, m->type_defs[d->id].name); break;
    case MK_ALT: mp_sym(m, o, m->alts[d->id].name); break;
    case MK_LIST:
    case MK_OPT:
        ms_buf_puts(o, d->kind == MK_LIST ? "list<" : "opt<");
        mp_ty(m, d->elem, o);
        ms_buf_putc(o, '>');
        break;
    case MK_OBJ:
        if (d->nargs == 0) {
            ms_buf_puts(o, "obj ");
            mp_sym(m, o, d->name);
        } else {
            mp_sym(m, o, d->name);
            ms_buf_putc(o, '<');
            for (uint32_t i = 0; i < d->nargs; i++) {
                if (i > 0) {
                    ms_buf_puts(o, ", ");
                }
                mp_ty(m, d->args[i], o);
            }
            ms_buf_putc(o, '>');
        }
        break;
    case MK_FN:
        ms_buf_puts(o, "fn(");
        for (uint32_t i = 0; i < d->nargs; i++) {
            if (i > 0) {
                ms_buf_puts(o, ", ");
            }
            if (mir_owns(d->owned, i)) {
                ms_buf_puts(o, "move ");
            }
            mp_ty(m, d->args[i], o);
        }
        ms_buf_puts(o, ") -> ");
        mp_ty(m, d->elem, o);
        break;
    case MK_IFACE:
        ms_buf_puts(o, "dyn ");
        mp_sym(m, o, m->ifaces[d->id].name);
        break;
    }
}

void mir_print_ty(const MirModule *m, MirTy t, MsBuf *o) {
    mp_ty(m, mir_ty_unscoped(t), o);
    if (mir_ty_scope(t) != 0) {
        ms_buf_printf(o, "@%u", mir_ty_scope(t));
    }
}

static void mp_quote(MsBuf *o, const char *s, size_t n) {
    ms_buf_putc(o, '"');
    for (size_t i = 0; i < n; i++) {
        unsigned char c = (unsigned char)s[i];
        switch (c) {
        case '"': ms_buf_puts(o, "\\\""); break;
        case '\\': ms_buf_puts(o, "\\\\"); break;
        case '\n': ms_buf_puts(o, "\\n"); break;
        case '\t': ms_buf_puts(o, "\\t"); break;
        case '\r': ms_buf_puts(o, "\\r"); break;
        default:
            if (c < 0x20 || c == 0x7f) {
                ms_buf_printf(o, "\\x%02x", c);
            } else {
                ms_buf_putc(o, (char)c);
            }
        }
    }
    ms_buf_putc(o, '"');
}

/* The shortest decimal digits that read back as `v` (positive, finite): `digits` holds them
 * without a point, and the value is d.ddd times ten to the `exponent`. */
typedef struct ShortestDigits {
    char digits[24];
    size_t count;
    long exponent;
} ShortestDigits;

/* `printf` rounds an exact tie to even, Rust's shortest digits round it up (`...3125` prints as
 * `...313`). When the exact value of `v` is a tie at `precision` digits and rounding up still
 * reads back as `v`, `text` ("d.ddde+XX") becomes the rounded-up digits. */
static void mp_round_tie_up(char *text, size_t size, double v, int precision) {
    char longer[400];
    snprintf(longer, sizeof longer, "%.*e", precision + 60, v);
    const char *tail = longer + 2 + precision; /* after "d." and `precision` digits */
    if (*tail != '5') {
        return;
    }
    for (const char *c = tail + 1; *c != 'e'; c++) {
        if (*c != '0') {
            return;
        }
    }
    char up[64];
    snprintf(up, sizeof up, "%.*e", precision, v);
    char *last = up + strcspn(up, "e") - 1;
    if (*last == '9') {
        return; /* a carry changes the exponent; leave it to printf's own rounding */
    }
    (*last)++;
    if (strtod(up, NULL) == v) {
        snprintf(text, size, "%s", up);
    }
}

static ShortestDigits mp_shortest_digits(double v) {
    char text[64] = {0};
    int found = 0;
    for (; found < 17; found++) {
        snprintf(text, sizeof text, "%.*e", found, v);
        if (strtod(text, NULL) == v) {
            break;
        }
    }
    mp_round_tie_up(text, sizeof text, v, found);
    /* text is d[.ddd]e[+-]XX */
    ShortestDigits out = {.digits = {0}};
    const char *exponent_mark = strchr(text, 'e');
    for (const char *c = text; c < exponent_mark; c++) {
        if (*c != '.') {
            out.digits[out.count++] = *c;
        }
    }
    out.exponent = strtol(exponent_mark + 1, NULL, 10);
    return out;
}

static void mp_f64_exponential(MsBuf *o, const ShortestDigits *d) {
    ms_buf_putc(o, d->digits[0]);
    if (d->count > 1) {
        ms_buf_putc(o, '.');
        ms_buf_put(o, d->digits + 1, d->count - 1);
    }
    ms_buf_printf(o, "e%ld", d->exponent);
}

static void mp_f64_decimal(MsBuf *o, const ShortestDigits *d) {
    if (d->exponent < 0) {
        ms_buf_puts(o, "0.");
        for (long i = 0; i < -d->exponent - 1; i++) {
            ms_buf_putc(o, '0');
        }
        ms_buf_put(o, d->digits, d->count);
        return;
    }
    size_t integer_digits = (size_t)d->exponent + 1;
    for (size_t i = 0; i < integer_digits; i++) {
        char digit = '0';
        if (i < d->count) {
            digit = d->digits[i];
        }
        ms_buf_putc(o, digit);
    }
    ms_buf_putc(o, '.');
    if (d->count > integer_digits) {
        ms_buf_put(o, d->digits + integer_digits, d->count - integer_digits);
    } else {
        ms_buf_putc(o, '0');
    }
}

/* Rust's `{:?}` of a finite f64: the shortest digits that read back, exponent form below 1e-4
 * and from 1e16, and always a fractional part otherwise. */
static void mp_f64(MsBuf *o, double v) {
    if (signbit(v)) {
        ms_buf_putc(o, '-');
        v = -v;
    }
    if (v == 0) {
        ms_buf_puts(o, "0.0");
        return;
    }
    ShortestDigits d = mp_shortest_digits(v);
    if (v >= 1e16 || v < 1e-4) {
        mp_f64_exponential(o, &d);
    } else {
        mp_f64_decimal(o, &d);
    }
}

static const char *mp_mode_prefix(const MirModule *m, MirTy ty, uint8_t mode) {
    (void)m;
    (void)ty;
    return mode == MM_MOVE ? "move " : "";
}

static const char *const mp_role_names[] = {
    [MR_BORROWS_ARGUMENT] = "borrows_argument", [MR_STRBUILDER_APPEND] = "strbuilder_append", [MR_STRBUILDER_APPEND_INT] = "strbuilder_append_int",
    [MR_STRING_CONCAT] = "string_concat", [MR_STRING_JOIN] = "string_join",
    [MR_STRING_APPEND] = "string_append", [MR_INT_TO_STRING] = "int_to_string",
    [MR_LIST_SORTED] = "list_sorted", [MR_LIST_SORT_INTS] = "list_sort_ints",
    [MR_LIST_SORTED_BY_DIFFERENCE] = "list_sorted_by_difference", [MR_LIST_NEW] = "list_new",
    [MR_MAP_NEW] = "map_new", [MR_BYTES_VALUES] = "bytes_values", [MR_STRING_EQ] = "string_eq",
    [MR_CLEANUP_DISCARD] = "cleanup_discard", [MR_BYTES_APPEND] = "bytes_append",
    [MR_TAKES_DYING] = "takes_dying", [MR_VIEW_RESULT] = "view_result",
    [MR_SPAWNS_TASK] = "spawns_task", [MR_SHIELD_ENTER] = "shield_enter",
    [MR_SHIELD_EXIT] = "shield_exit", [MR_UNWINDING] = "unwinding",
    [MR_MAP_PROBE_INT] = "map_probe_int", [MR_MAP_PROBE_STR] = "map_probe_str",
    [MR_SET_PROBE_INT] = "set_probe_int", [MR_STRING_SLICE] = "string_slice",
    [MR_BYTES_READ_WORD] = "bytes_read_word", [MR_BYTES_INDEX_OF_BYTE] = "bytes_index_of_byte",
    [MR_STRING_PARSE_INT] = "string_parse_int", [MR_STRING_CONTAINS] = "string_contains",
    [MR_STRING_STARTS_WITH] = "string_starts_with", [MR_STRING_ENDS_WITH] = "string_ends_with",
    [MR_STRING_COMPARE] = "string_compare", [MR_STRING_SCALAR_STEP] = "string_scalar_step",
    [MR_STRING_SCALAR_AT] = "string_scalar_at",
};

/* The role named by a textual attribute, or MR_NONE. */
int mir_role_from_name(const char *s, size_t n) {
    for (size_t i = 0; i < sizeof mp_role_names / sizeof *mp_role_names; i++) {
        if (mp_role_names[i] != NULL && strlen(mp_role_names[i]) == n &&
            memcmp(mp_role_names[i], s, n) == 0) {
            return (int)i;
        }
    }
    return MR_NONE;
}

static const char *mp_std_name(uint8_t std) {
    switch (std) {
    case MSTD_RESULT: return "result";
    case MSTD_COMPARABLE: return "comparable";
    case MSTD_EQUAL: return "equal";
    default: return NULL;
    }
}

static void mp_files(const MirModule *m, MsBuf *o) {
    for (uint32_t i = 0; i < m->nfiles; i++) {
        ms_buf_printf(o, "file %u ", i);
        mp_quote(o, m->files[i].ptr, m->files[i].len);
        ms_buf_putc(o, '\n');
    }
}

static void mp_blobs(const MirModule *m, MsBuf *o) {
    for (uint32_t i = 0; i < m->nblobs; i++) {
        ms_buf_printf(o, "blob %u \"", i);
        for (uint32_t k = 0; k < m->blobs[i].len; k++) {
            ms_buf_printf(o, "%02x", (unsigned char)m->blobs[i].ptr[k]);
        }
        ms_buf_puts(o, "\"\n");
    }
}

static void mp_consts(const MirModule *m, MsBuf *o) {
    for (uint32_t i = 0; i < m->nlist_consts; i++) {
        ms_buf_printf(o, "consts %u [", i);
        for (uint32_t k = 0; k < m->list_consts[i].n; k++) {
            ms_buf_printf(o, "%s%lld", k ? ", " : "", (long long)m->list_consts[i].v[k]);
        }
        ms_buf_puts(o, "]\n");
    }
}

static void mp_type_defs(const MirModule *m, MsBuf *o) {
    for (uint32_t i = 0; i < m->ntype_defs; i++) {
        const MirTypeDef *r = &m->type_defs[i];
        ms_buf_puts(o, "type ");
        mp_sym(m, o, r->name);
        ms_buf_puts(o, r->indirect ? " indirect { " : " { ");
        for (uint32_t k = 0; k < r->nfields; k++) {
            if (k) {
                ms_buf_puts(o, ", ");
            }
            mp_sym(m, o, r->fields[k].name);
            ms_buf_puts(o, ": ");
            mir_print_ty(m, r->fields[k].ty, o);
        }
        ms_buf_puts(o, " }\n");
    }
}

static void mp_alts(const MirModule *m, MsBuf *o) {
    for (uint32_t i = 0; i < m->nalts; i++) {
        const MirAltDef *a = &m->alts[i];
        ms_buf_puts(o, "alt ");
        mp_sym(m, o, a->name);
        if (a->borrowed != 0) {
            ms_buf_printf(o, " borrowed %llu", (unsigned long long)a->borrowed);
        }
        ms_buf_puts(o, " { ");
        for (uint32_t c = 0; c < a->ncases; c++) {
            const MirCaseDef *cd = &a->cases[c];
            if (c) {
                ms_buf_puts(o, ", ");
            }
            mp_sym(m, o, cd->name);
            if (cd->nfields > 0) {
                ms_buf_putc(o, '(');
                for (uint32_t k = 0; k < cd->nfields; k++) {
                    if (k) {
                        ms_buf_puts(o, ", ");
                    }
                    mp_sym(m, o, cd->fields[k].name);
                    ms_buf_puts(o, ": ");
                    mir_print_ty(m, cd->fields[k].ty, o);
                }
                ms_buf_putc(o, ')');
            }
        }
        ms_buf_puts(o, " }");
        if (mp_std_name(a->std)) {
            ms_buf_printf(o, " %s", mp_std_name(a->std));
        }
        ms_buf_putc(o, '\n');
    }
}

static void mp_ifaces(const MirModule *m, MsBuf *o) {
    for (uint32_t i = 0; i < m->nifaces; i++) {
        const MirIfaceDef *d = &m->ifaces[i];
        ms_buf_puts(o, "iface ");
        mp_sym(m, o, d->name);
        ms_buf_puts(o, " { ");
        for (uint32_t k = 0; k < d->nmethods; k++) {
            const MirMethodSig *s = &d->methods[k];
            if (k) {
                ms_buf_puts(o, ", ");
            }
            mp_sym(m, o, s->name);
            ms_buf_putc(o, '(');
            for (uint32_t p = 0; p < s->nparams; p++) {
                if (p) {
                    ms_buf_puts(o, ", ");
                }
                ms_buf_puts(o, mir_owns(s->owned, p) ? "move " : "");
                mir_print_ty(m, s->params[p], o);
            }
            ms_buf_puts(o, ") -> ");
            mir_print_ty(m, s->ret, o);
        }
        ms_buf_puts(o, " }");
        if (mp_std_name(d->std)) {
            ms_buf_printf(o, " %s", mp_std_name(d->std));
        }
        ms_buf_putc(o, '\n');
    }
}

static void mp_externs(const MirModule *m, MsBuf *o) {
    for (uint32_t i = 0; i < m->nexterns; i++) {
        const MirExtern *e = &m->externs[i];
        ms_buf_puts(o, "extern @");
        mp_sym(m, o, e->name);
        ms_buf_putc(o, '(');
        for (uint32_t p = 0; p < e->nparams; p++) {
            if (p) {
                ms_buf_puts(o, ", ");
            }
            ms_buf_puts(o, mp_mode_prefix(m, e->params[p].ty, e->params[p].mode));
            mir_print_ty(m, e->params[p].ty, o);
        }
        ms_buf_puts(o, ") -> ");
        mir_print_ty(m, e->ret, o);
        if (e->pure) ms_buf_puts(o, " pure");
        if (e->noreturn) ms_buf_puts(o, " noreturn");
        if (e->fresh) ms_buf_puts(o, " fresh");
        if (e->leaf) ms_buf_puts(o, " leaf");
        if (e->reads) ms_buf_puts(o, " reads");
        if (e->retains) ms_buf_puts(o, " retains");
        if (e->role != MR_NONE && mp_role_names[e->role] != NULL) {
            ms_buf_printf(o, " %s", mp_role_names[e->role]);
        }
        ms_buf_putc(o, '\n');
    }
}

static void mp_globals(const MirModule *m, MsBuf *o) {
    for (uint32_t i = 0; i < m->nglobals; i++) {
        ms_buf_puts(o, "global @");
        mp_sym(m, o, m->globals[i].name);
        ms_buf_puts(o, ": ");
        mir_print_ty(m, m->globals[i].ty, o);
        ms_buf_putc(o, '\n');
    }
}

static void mp_vtables(const MirModule *m, MsBuf *o) {
    for (uint32_t i = 0; i < m->nvtables; i++) {
        const MirVtable *v = &m->vtables[i];
        ms_buf_puts(o, "vtable @");
        mp_sym(m, o, v->name);
        ms_buf_puts(o, ": ");
        mp_sym(m, o, m->ifaces[v->iface].name);
        ms_buf_puts(o, " for ");
        mir_print_ty(m, v->data_ty, o);
        ms_buf_puts(o, " { ");
        for (uint32_t k = 0; k < v->nmethods; k++) {
            ms_buf_puts(o, k ? ", @" : "@");
            mp_sym(m, o, m->funcs[v->methods[k]].name);
        }
        ms_buf_puts(o, " }\n");
    }
}

static void mp_desc_glue(const MirModule *m, MsBuf *o) {
    for (uint32_t i = 0; i < m->ndesc_glue; i++) {
        ms_buf_puts(o, "desc_glue ");
        mir_print_ty(m, m->desc_glue[i].ty, o);
        ms_buf_puts(o, " @");
        mp_sym(m, o, m->funcs[m->desc_glue[i].eq].name);
        ms_buf_puts(o, " @");
        mp_sym(m, o, m->funcs[m->desc_glue[i].hash].name);
        ms_buf_putc(o, '\n');
    }
}

void mir_print_module(const MirModule *m, MsBuf *o) {
    ms_buf_puts(o, "module ");
    MsStr module_name = ms_name(&m->names, m->name);
    mp_quote(o, module_name.ptr, module_name.len);
    ms_buf_putc(o, '\n');
    mp_files(m, o);
    mp_blobs(m, o);
    mp_consts(m, o);
    mp_type_defs(m, o);
    mp_alts(m, o);
    mp_ifaces(m, o);
    mp_externs(m, o);
    mp_globals(m, o);
    mp_vtables(m, o);
    mp_desc_glue(m, o);
    if (m->entry != MIR_NONE) {
        ms_buf_puts(o, "entry @");
        mp_sym(m, o, m->funcs[m->entry].name);
        ms_buf_putc(o, '\n');
    }
    if (m->close != MIR_NONE) {
        ms_buf_puts(o, "close @");
        mp_sym(m, o, m->funcs[m->close].name);
        ms_buf_putc(o, '\n');
    }
    for (uint32_t i = 0; i < m->nfuncs; i++) {
        ms_buf_putc(o, '\n');
        mir_print_func(m, &m->funcs[i], o);
    }
}

typedef struct PrintCx {
    const MirModule *m;
    const MirFunc *f;
    uint32_t *names; /* value -> dense number */
} PrintCx;

static void mp_val(const PrintCx *cx, MsBuf *o, MirValue v) {
    uint32_t n = cx->names[v];
    ms_buf_printf(o, "%%%llu", (unsigned long long)(n == MIR_NONE ? UINT64_MAX : n));
}

static void mp_target(const PrintCx *cx, MsBuf *o, const MirTarget *t) {
    ms_buf_printf(o, "b%u(", t->block);
    for (uint32_t i = 0; i < t->nargs; i++) {
        if (i) {
            ms_buf_puts(o, ", ");
        }
        mp_val(cx, o, t->args[i]);
    }
    ms_buf_putc(o, ')');
}

static void mp_fault(const MirModule *m, MsBuf *o, const MirTerm *t) {
    static const char *const n[] = {"int_overflow", "div_by_zero", "index_out_of_range",
                                    "none_unwrap", "cancelled", "call_depth", "unreachable_code"};
    if (t->fault == MF_MESSAGE) {
        MsStr s = ms_name(&m->strings, t->fault_str);
        mp_quote(o, s.ptr, s.len);
    } else {
        ms_buf_puts(o, n[t->fault]);
    }
}

static void mp_term(const PrintCx *cx, MsBuf *o, const MirTerm *t) {
    switch (t->kind) {
    case MT_BR:
        ms_buf_puts(o, "br ");
        mp_target(cx, o, &t->a);
        break;
    case MT_CONDBR:
        ms_buf_puts(o, "br_if ");
        mp_val(cx, o, t->value);
        ms_buf_puts(o, ", ");
        mp_target(cx, o, &t->a);
        ms_buf_puts(o, ", ");
        mp_target(cx, o, &t->b);
        break;
    case MT_SWITCH:
        ms_buf_puts(o, "switch ");
        mp_val(cx, o, t->value);
        ms_buf_puts(o, " [");
        for (uint32_t i = 0; i < t->ncases; i++) {
            ms_buf_printf(o, "%s%lld: ", i ? ", " : "", (long long)t->cases[i].value);
            mp_target(cx, o, &t->cases[i].target);
        }
        ms_buf_puts(o, "] default ");
        mp_target(cx, o, &t->b);
        break;
    case MT_RET:
        ms_buf_puts(o, "ret");
        if (t->value != MIR_NONE) {
            ms_buf_putc(o, ' ');
            mp_val(cx, o, t->value);
        }
        break;
    case MT_FAULT:
        ms_buf_puts(o, "fault ");
        mp_fault(cx->m, o, t);
        break;
    default:
        ms_buf_puts(o, "unreachable");
    }
}

static void mp_sym_pair(const MirModule *m, MsBuf *o, MsSym first, MsSym second) {
    mp_sym(m, o, first);
    ms_buf_putc(o, '.');
    mp_sym(m, o, second);
}

/* Prints the masked fields of a case or type, each preceded by a dot. */
static void mp_masked_fields(const MirModule *m, MsBuf *o, const MirField *fields, uint32_t count,
                             uint32_t mask) {
    for (uint32_t k = 0; k < count && k < 32; k++) {
        if (mask >> k & 1) {
            ms_buf_putc(o, '.');
            mp_sym(m, o, fields[k].name);
        }
    }
}

/* Immediates that name a declaration or a field of one. */
static void mp_imm_declared(const MirModule *m, MsBuf *o, const MirImm *im) {
    switch ((MirImmTag)im->tag) {
    case MI_FUNC: ms_buf_putc(o, '@'); mp_sym(m, o, m->funcs[im->a].name); break;
    case MI_EXT: ms_buf_putc(o, '@'); mp_sym(m, o, m->externs[im->a].name); break;
    case MI_TYPE: mp_sym(m, o, m->type_defs[im->a].name); break;
    case MI_FIELD:
        mp_sym_pair(m, o, m->type_defs[im->a].name, m->type_defs[im->a].fields[im->b].name);
        break;
    case MI_CASE:
        mp_sym_pair(m, o, m->alts[im->a].name, m->alts[im->a].cases[im->b].name);
        break;
    case MI_ALTFIELD: {
        const MirCaseDef *c = &m->alts[im->a].cases[im->b];
        mp_sym_pair(m, o, m->alts[im->a].name, c->name);
        ms_buf_putc(o, '.');
        mp_sym(m, o, c->fields[im->c].name);
        break;
    }
    case MI_ALTMASK: {
        const MirCaseDef *c = &m->alts[im->a].cases[im->b];
        mp_sym_pair(m, o, m->alts[im->a].name, c->name);
        mp_masked_fields(m, o, c->fields, c->nfields, im->c);
        break;
    }
    case MI_TYPEMASK: {
        const MirTypeDef *d = &m->type_defs[im->a];
        mp_sym(m, o, d->name);
        mp_masked_fields(m, o, d->fields, d->nfields, im->b);
        break;
    }
    case MI_VTABLE: ms_buf_putc(o, '@'); mp_sym(m, o, m->vtables[im->a].name); break;
    case MI_GLOBAL: ms_buf_putc(o, '@'); mp_sym(m, o, m->globals[im->a].name); break;
    case MI_METHOD:
        mp_sym_pair(m, o, m->ifaces[im->a].name, m->ifaces[im->a].methods[im->b].name);
        break;
    case MI_NONE: case MI_INT: case MI_FLOAT: case MI_BOOL: case MI_STR: case MI_TY: case MI_CC:
    case MI_IDX: case MI_SCOPE:
        break;
    }
}

/* The text after the mnemonic for an immediate (a comparison condition is part of the mnemonic). */
static void mp_imm(const MirModule *m, MsBuf *o, const MirImm *im) {
    switch ((MirImmTag)im->tag) {
    case MI_INT: ms_buf_printf(o, "%lld", (long long)im->i); break;
    case MI_FLOAT: {
        uint64_t bits = (uint64_t)im->i;
        double v = 0;
        memcpy(&v, &bits, sizeof v);
        if (isfinite(v)) {
            mp_f64(o, v);
        } else {
            ms_buf_printf(o, "0x%016llx", (unsigned long long)bits);
        }
        break;
    }
    case MI_BOOL: ms_buf_puts(o, im->a ? "true" : "false"); break;
    case MI_STR: {
        MsStr s = ms_name(&m->strings, im->a);
        mp_quote(o, s.ptr, s.len);
        break;
    }
    case MI_TY: mir_print_ty(m, im->a, o); break;
    case MI_IDX: ms_buf_printf(o, "%u", im->a); break;
    case MI_SCOPE: ms_buf_printf(o, "%u %u", im->a, im->b); break;
    case MI_NONE: case MI_CC: break;
    default: mp_imm_declared(m, o, im); break;
    }
}

static void mp_value_list(const PrintCx *cx, MsBuf *o, const MirValue *values, uint32_t count) {
    for (uint32_t i = 0; i < count; i++) {
        if (i) {
            ms_buf_puts(o, ", ");
        }
        mp_val(cx, o, values[i]);
    }
}

static void mp_inst(const PrintCx *cx, MsBuf *o, const MirInst *in) {
    const MirImm *im = &in->imm;
    ms_buf_puts(o, mir_op_info[in->op].name);
    if (im->tag == MI_CC) {
        ms_buf_putc(o, '.');
        ms_buf_puts(o, mir_cc_name[im->a]);
    } else if (im->tag != MI_NONE) {
        ms_buf_putc(o, ' ');
        mp_imm(cx->m, o, im);
    }
    if (mir_op_is_call((MirOp)in->op)) {
        ms_buf_puts(o, " (");
        mp_value_list(cx, o, in->args, in->nargs);
        ms_buf_putc(o, ')');
    } else if (in->nargs > 0) {
        ms_buf_putc(o, ' ');
        mp_value_list(cx, o, in->args, in->nargs);
    }
}

static void mp_loc(MsBuf *o, MirLoc l) {
    if (!mir_loc_none(l)) {
        ms_buf_printf(o, " !%u:%u:%u", l.file, l.line, l.col);
        if (l.scope != 0) {
            ms_buf_printf(o, ":%u", l.scope);
        }
    }
}

/* Numbers values densely in the order they are defined. */
static void mp_number_values(PrintCx *cx) {
    const MirFunc *f = cx->f;
    uint32_t next = 0;
    for (uint32_t b = 0; b < f->nblocks; b++) {
        const MirBlockData *block = &f->blocks[b];
        for (uint32_t i = 0; i < block->nparams; i++) {
            uint32_t *name = &cx->names[block->params[i].value];
            if (*name == MIR_NONE) {
                *name = next++;
            }
        }
        for (uint32_t i = 0; i < block->ninsts; i++) {
            MirValue result = block->insts[i].res;
            if (result != MIR_NONE && cx->names[result] == MIR_NONE) {
                cx->names[result] = next++;
            }
        }
    }
}

static void mp_func_kind(const MirModule *m, const MirFunc *f, MsBuf *o) {
    if (f->kind == MFK_METHOD) {
        ms_buf_puts(o, " method");
    } else if (f->kind == MFK_CLOSURE) {
        ms_buf_puts(o, " closure(");
        for (uint32_t i = 0; i < f->ncaptures; i++) {
            if (i) {
                ms_buf_puts(o, ", ");
            }
            mir_print_ty(m, f->captures[i], o);
        }
        ms_buf_putc(o, ')');
    }
    if (f->sort == MSORT_GENERIC) ms_buf_puts(o, " sort_cmp");
    if (f->sort == MSORT_SPECIALIZED) ms_buf_puts(o, " sort_cmp_for");
    if (f->explicit_cancel) ms_buf_puts(o, " explicit_cancel");
    if (f->nnoalias > 0) {
        ms_buf_puts(o, " noalias(");
        for (uint32_t i = 0; i < f->nnoalias; i++) {
            ms_buf_printf(o, i ? ", %u" : "%u", f->noalias[i]);
        }
        ms_buf_putc(o, ')');
    }
    if (f->has_slot_result) {
        ms_buf_puts(o, " slot_result(@");
        mp_sym(m, o, m->funcs[f->slot_result].name);
        ms_buf_putc(o, ')');
    }
    if (f->has_close_exit) {
        ms_buf_puts(o, " close_exit(@");
        mp_sym(m, o, m->funcs[f->close_exit[0]].name);
        ms_buf_puts(o, ", @");
        mp_sym(m, o, m->funcs[f->close_exit[1]].name);
        ms_buf_putc(o, ')');
    }
    if (f->ret_borrowed) ms_buf_puts(o, " ret_borrowed");
    if (f->ret_view) ms_buf_puts(o, " ret_view");
    if (f->scoped) ms_buf_puts(o, " scoped");
    if (f->keeps_scoped) ms_buf_puts(o, " keeps_scoped");
    if (f->unwind_only) ms_buf_puts(o, " unwind_only");
    if (f->raw_scratch) ms_buf_puts(o, " raw_scratch");
    if (f->has_slot_close) {
        ms_buf_puts(o, " slot_close(");
        mir_print_ty(m, f->slot_close, o);
        ms_buf_putc(o, ')');
    }
    if (f->ncapture_closers > 0) {
        ms_buf_puts(o, " capture_closers(");
        for (uint32_t i = 0; i < f->ncapture_closers; i++) {
            ms_buf_printf(o, i ? ", %u @" : "%u @", f->capture_closers[i].capture);
            mp_sym(m, o, m->funcs[f->capture_closers[i].func].name);
        }
        ms_buf_putc(o, ')');
    }
}

static void mp_func_header(const PrintCx *cx, MsBuf *o) {
    const MirModule *m = cx->m;
    const MirFunc *f = cx->f;
    ms_buf_puts(o, "fn @");
    mp_sym(m, o, f->name);
    ms_buf_putc(o, '(');
    for (uint32_t i = 0; i < f->nparams; i++) {
        if (i) {
            ms_buf_puts(o, ", ");
        }
        mp_val(cx, o, f->blocks[0].params[i].value);
        ms_buf_puts(o, ": ");
        ms_buf_puts(o, mp_mode_prefix(m, f->params[i].ty, f->params[i].mode));
        mir_print_ty(m, f->params[i].ty, o);
    }
    ms_buf_puts(o, ") -> ");
    mir_print_ty(m, f->ret, o);
    if (f->linkage == ML_EXPORT) {
        ms_buf_puts(o, " export");
    }
    if (f->inline_hint == MINL_ALWAYS) ms_buf_puts(o, " inline(always)");
    if (f->inline_hint == MINL_NEVER) ms_buf_puts(o, " inline(never)");
    mp_func_kind(m, f, o);
    mp_loc(o, f->loc);
    ms_buf_puts(o, " {\n");
}

static void mp_block_label(const PrintCx *cx, MsBuf *o, uint32_t index) {
    const MirBlockData *block = &cx->f->blocks[index];
    if (index == 0) {
        ms_buf_puts(o, "b0:\n");
        return;
    }
    ms_buf_printf(o, "b%u(", index);
    for (uint32_t i = 0; i < block->nparams; i++) {
        MirTy ty = cx->f->values[block->params[i].value];
        if (i) {
            ms_buf_puts(o, ", ");
        }
        mp_val(cx, o, block->params[i].value);
        ms_buf_puts(o, ": ");
        ms_buf_puts(o, mp_mode_prefix(cx->m, ty, block->params[i].mode));
        mir_print_ty(cx->m, ty, o);
    }
    ms_buf_puts(o, "):\n");
}

static void mp_block(const PrintCx *cx, MsBuf *o, uint32_t index) {
    const MirBlockData *block = &cx->f->blocks[index];
    mp_block_label(cx, o, index);
    for (uint32_t i = 0; i < block->ninsts; i++) {
        const MirInst *in = &block->insts[i];
        ms_buf_puts(o, "  ");
        if (in->res != MIR_NONE) {
            mp_val(cx, o, in->res);
            ms_buf_puts(o, ": ");
            mir_print_ty(cx->m, cx->f->values[in->res], o);
            ms_buf_puts(o, " = ");
        }
        mp_inst(cx, o, in);
        mp_loc(o, in->loc);
        ms_buf_putc(o, '\n');
    }
    ms_buf_puts(o, "  ");
    mp_term(cx, o, &block->term);
    mp_loc(o, block->term_loc);
    ms_buf_putc(o, '\n');
}

/* Inlined scopes, named values and values proved exact, after the blocks, only when present. */
static void mp_facts(const PrintCx *cx, MsBuf *o) {
    const MirFunc *f = cx->f;
    const MirModule *m = cx->m;
    for (uint32_t i = 0; i < f->nscopes; i++) {
        const MsStr name = ms_name(&m->names, f->scopes[i].name);
        ms_buf_puts(o, "  scope ");
        mp_quote(o, name.ptr, name.len);
        ms_buf_printf(o, " %u %u %u\n", f->scopes[i].file, f->scopes[i].parent, f->scopes[i].call_line);
    }
    for (uint32_t i = 0; i < f->nnames; i++) {
        const MirNamedValue *n = &f->names[i];
        if (n->value >= f->nvalues || cx->names[n->value] == MIR_NONE) {
            continue; /* its value no longer exists */
        }
        const MsStr name = ms_name(&m->names, n->name);
        ms_buf_printf(o, "  name %%%u ", cx->names[n->value]);
        mp_quote(o, name.ptr, name.len);
        ms_buf_printf(o, " %s %u\n", n->param ? "param" : "local", n->scope);
    }
    if (f->nexact == 0) {
        return;
    }
    /* In printed-number order, which is not the value order after a pass moved values. */
    uint32_t *by_number = malloc(sizeof(uint32_t) * (f->nvalues ? f->nvalues : 1));
    if (by_number == NULL) {
        abort();
    }
    memset(by_number, 0xff, sizeof(uint32_t) * (f->nvalues ? f->nvalues : 1));
    for (uint32_t v = 0; v < f->nvalues; v++) {
        if (cx->names[v] != MIR_NONE) {
            by_number[cx->names[v]] = v;
        }
    }
    for (uint32_t k = 0; k < f->nvalues; k++) {
        const uint32_t v = by_number[k];
        if (v != MIR_NONE && (v >> 6) < f->nexact && ((f->exact[v >> 6] >> (v & 63)) & 1) != 0) {
            ms_buf_printf(o, "  exact %%%u\n", k);
        }
    }
    free(by_number);
}

void mir_print_func(const MirModule *m, const MirFunc *f, MsBuf *o) {
    size_t count = f->nvalues ? f->nvalues : 1;
    PrintCx cx = {m, f, malloc(sizeof(uint32_t) * count)};
    if (cx.names == NULL) {
        abort(); /* out of memory, as everywhere in libms */
    }
    memset(cx.names, 0xff, sizeof(uint32_t) * count);
    mp_number_values(&cx);
    mp_func_header(&cx, o);
    for (uint32_t i = 0; i < f->nblocks; i++) {
        mp_block(&cx, o, i);
    }
    mp_facts(&cx, o);
    ms_buf_puts(o, "}\n");
    free(cx.names);
}
