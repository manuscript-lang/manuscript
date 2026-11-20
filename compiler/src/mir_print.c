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
    switch (d->kind) {
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
    char buf[64];
    for (int p = 0; p < 17; p++) {
        snprintf(buf, sizeof buf, "%.*e", p, v);
        if (strtod(buf, NULL) == v) {
            break;
        }
    }
    /* buf is d[.ddd]e[+-]XX */
    char digits[24];
    int nd = 0;
    char *e = strchr(buf, 'e');
    for (char *c = buf; c < e; c++) {
        if (*c != '.') {
            digits[nd++] = *c;
        }
    }
    int exp = atoi(e + 1);
    if (v >= 1e16 || v < 1e-4) {
        ms_buf_putc(o, digits[0]);
        if (nd > 1) {
            ms_buf_putc(o, '.');
            ms_buf_put(o, digits + 1, (size_t)nd - 1);
        }
        ms_buf_printf(o, "e%d", exp);
    } else if (exp >= 0) {
        for (int i = 0; i <= exp; i++) {
            ms_buf_putc(o, i < nd ? digits[i] : '0');
        }
        ms_buf_putc(o, '.');
        if (nd > exp + 1) {
            ms_buf_put(o, digits + exp + 1, (size_t)(nd - exp - 1));
        } else {
            ms_buf_putc(o, '0');
        }
    } else {
        ms_buf_puts(o, "0.");
        for (int i = 0; i < -exp - 1; i++) {
            ms_buf_putc(o, '0');
        }
        ms_buf_put(o, digits, (size_t)nd);
    }
}

static const char *mp_mode_prefix(const MirModule *m, MirTy ty, uint8_t mode) {
    return mode == MM_MOVE && mir_needs_drop(m, ty) ? "move " : "";
}

static const char *const mp_role_names[] = {
    [MR_STRBUILDER_APPEND] = "strbuilder_append", [MR_STRBUILDER_APPEND_INT] = "strbuilder_append_int",
    [MR_STRING_CONCAT] = "string_concat", [MR_STRING_JOIN] = "string_join",
    [MR_STRING_APPEND] = "string_append", [MR_INT_TO_STRING] = "int_to_string",
    [MR_LIST_SORTED] = "list_sorted", [MR_LIST_SORT_INTS] = "list_sort_ints",
    [MR_LIST_SORTED_BY_DIFFERENCE] = "list_sorted_by_difference", [MR_LIST_NEW] = "list_new",
    [MR_MAP_NEW] = "map_new", [MR_BYTES_VALUES] = "bytes_values", [MR_STRING_EQ] = "string_eq",
    [MR_CLEANUP_DISCARD] = "cleanup_discard", [MR_BYTES_APPEND] = "bytes_append",
    [MR_TAKES_DYING] = "takes_dying", [MR_VIEW_RESULT] = "view_result",
    [MR_SPAWNS_TASK] = "spawns_task", [MR_SHIELD_ENTER] = "shield_enter",
    [MR_SHIELD_EXIT] = "shield_exit", [MR_UNWINDING] = "unwinding",
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

void mir_print_module(const MirModule *m, MsBuf *o) {
    ms_buf_puts(o, "module ");
    MsStr mn = ms_name(&m->names, m->name);
    mp_quote(o, mn.ptr, mn.len);
    ms_buf_putc(o, '\n');
    for (uint32_t i = 0; i < m->nfiles; i++) {
        ms_buf_printf(o, "file %u ", i);
        mp_quote(o, m->files[i].ptr, m->files[i].len);
        ms_buf_putc(o, '\n');
    }
    for (uint32_t i = 0; i < m->nblobs; i++) {
        ms_buf_printf(o, "blob %u \"", i);
        for (uint32_t k = 0; k < m->blobs[i].len; k++) {
            ms_buf_printf(o, "%02x", (unsigned char)m->blobs[i].ptr[k]);
        }
        ms_buf_puts(o, "\"\n");
    }
    for (uint32_t i = 0; i < m->nlist_consts; i++) {
        ms_buf_printf(o, "consts %u [", i);
        for (uint32_t k = 0; k < m->list_consts[i].n; k++) {
            ms_buf_printf(o, "%s%lld", k ? ", " : "", (long long)m->list_consts[i].v[k]);
        }
        ms_buf_puts(o, "]\n");
    }
    for (uint32_t i = 0; i < m->ntype_defs; i++) {
        const MirTypeDef *r = &m->type_defs[i];
        ms_buf_puts(o, "type ");
        mp_sym(m, o, r->name);
        ms_buf_puts(o, " { ");
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
    for (uint32_t i = 0; i < m->nalts; i++) {
        const MirAltDef *a = &m->alts[i];
        ms_buf_puts(o, "alt ");
        mp_sym(m, o, a->name);
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
    for (uint32_t i = 0; i < m->nglobals; i++) {
        ms_buf_puts(o, "global @");
        mp_sym(m, o, m->globals[i].name);
        ms_buf_puts(o, ": ");
        mir_print_ty(m, m->globals[i].ty, o);
        ms_buf_putc(o, '\n');
    }
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
    if (m->entry != MIR_NONE) {
        ms_buf_puts(o, "entry @");
        mp_sym(m, o, m->funcs[m->entry].name);
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

static void mp_inst(const PrintCx *cx, MsBuf *o, const MirInst *in) {
    const MirModule *m = cx->m;
    const MirImm *im = &in->imm;
    ms_buf_puts(o, mir_op_info[in->op].name);
    if (im->tag == MI_CC) {
        ms_buf_putc(o, '.');
        ms_buf_puts(o, mir_cc_name[im->a]);
    } else if (im->tag != MI_NONE) {
        ms_buf_putc(o, ' ');
        switch (im->tag) {
        case MI_INT: ms_buf_printf(o, "%lld", (long long)im->i); break;
        case MI_FLOAT: {
            double v;
            uint64_t bits = (uint64_t)im->i;
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
        case MI_FUNC: ms_buf_putc(o, '@'); mp_sym(m, o, m->funcs[im->a].name); break;
        case MI_EXT: ms_buf_putc(o, '@'); mp_sym(m, o, m->externs[im->a].name); break;
        case MI_TY: mir_print_ty(m, im->a, o); break;
        case MI_TYPE: mp_sym(m, o, m->type_defs[im->a].name); break;
        case MI_FIELD:
            mp_sym(m, o, m->type_defs[im->a].name);
            ms_buf_putc(o, '.');
            mp_sym(m, o, m->type_defs[im->a].fields[im->b].name);
            break;
        case MI_CASE:
            mp_sym(m, o, m->alts[im->a].name);
            ms_buf_putc(o, '.');
            mp_sym(m, o, m->alts[im->a].cases[im->b].name);
            break;
        case MI_ALTFIELD: {
            const MirCaseDef *c = &m->alts[im->a].cases[im->b];
            mp_sym(m, o, m->alts[im->a].name);
            ms_buf_putc(o, '.');
            mp_sym(m, o, c->name);
            ms_buf_putc(o, '.');
            mp_sym(m, o, c->fields[im->c].name);
            break;
        }
        case MI_ALTMASK: {
            const MirCaseDef *c = &m->alts[im->a].cases[im->b];
            mp_sym(m, o, m->alts[im->a].name);
            ms_buf_putc(o, '.');
            mp_sym(m, o, c->name);
            for (uint32_t k = 0; k < c->nfields; k++) {
                if (k < 32 && (im->c >> k & 1)) {
                    ms_buf_putc(o, '.');
                    mp_sym(m, o, c->fields[k].name);
                }
            }
            break;
        }
        case MI_TYPEMASK: {
            const MirTypeDef *d = &m->type_defs[im->a];
            mp_sym(m, o, d->name);
            for (uint32_t k = 0; k < d->nfields; k++) {
                if (k < 32 && (im->b >> k & 1)) {
                    ms_buf_putc(o, '.');
                    mp_sym(m, o, d->fields[k].name);
                }
            }
            break;
        }
        case MI_VTABLE: ms_buf_putc(o, '@'); mp_sym(m, o, m->vtables[im->a].name); break;
        case MI_GLOBAL: ms_buf_putc(o, '@'); mp_sym(m, o, m->globals[im->a].name); break;
        case MI_METHOD:
            mp_sym(m, o, m->ifaces[im->a].name);
            ms_buf_putc(o, '.');
            mp_sym(m, o, m->ifaces[im->a].methods[im->b].name);
            break;
        case MI_IDX: ms_buf_printf(o, "%u", im->a); break;
        case MI_SCOPE: ms_buf_printf(o, "%u %u", im->a, im->b); break;
        default: break;
        }
    }
    if (mir_op_is_call(in->op)) {
        ms_buf_puts(o, " (");
        for (uint32_t i = 0; i < in->nargs; i++) {
            if (i) {
                ms_buf_puts(o, ", ");
            }
            mp_val(cx, o, in->args[i]);
        }
        ms_buf_putc(o, ')');
    } else if (in->nargs > 0) {
        ms_buf_putc(o, ' ');
        for (uint32_t i = 0; i < in->nargs; i++) {
            if (i) {
                ms_buf_puts(o, ", ");
            }
            mp_val(cx, o, in->args[i]);
        }
    }
}

static void mp_loc(MsBuf *o, MirLoc l) {
    if (!mir_loc_none(l)) {
        ms_buf_printf(o, " !%u:%u:%u", l.file, l.line, l.col);
    }
}

void mir_print_func(const MirModule *m, const MirFunc *f, MsBuf *o) {
    PrintCx cx = {m, f, malloc(sizeof(uint32_t) * (f->nvalues ? f->nvalues : 1))};
    memset(cx.names, 0xff, sizeof(uint32_t) * f->nvalues);
    uint32_t next = 0;
    for (uint32_t b = 0; b < f->nblocks; b++) {
        const MirBlockData *bd = &f->blocks[b];
        for (uint32_t i = 0; i < bd->nparams; i++) {
            if (cx.names[bd->params[i].value] == MIR_NONE) {
                cx.names[bd->params[i].value] = next++;
            }
        }
        for (uint32_t i = 0; i < bd->ninsts; i++) {
            MirValue r = bd->insts[i].res;
            if (r != MIR_NONE && cx.names[r] == MIR_NONE) {
                cx.names[r] = next++;
            }
        }
    }
    ms_buf_puts(o, "fn @");
    mp_sym(m, o, f->name);
    ms_buf_putc(o, '(');
    for (uint32_t i = 0; i < f->nparams; i++) {
        if (i) {
            ms_buf_puts(o, ", ");
        }
        mp_val(&cx, o, f->blocks[0].params[i].value);
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
    mp_loc(o, f->loc);
    ms_buf_puts(o, " {\n");
    for (uint32_t bi = 0; bi < f->nblocks; bi++) {
        const MirBlockData *b = &f->blocks[bi];
        if (bi == 0) {
            ms_buf_puts(o, "b0:\n");
        } else {
            ms_buf_printf(o, "b%u(", bi);
            for (uint32_t i = 0; i < b->nparams; i++) {
                MirTy ty = f->values[b->params[i].value];
                if (i) {
                    ms_buf_puts(o, ", ");
                }
                mp_val(&cx, o, b->params[i].value);
                ms_buf_puts(o, ": ");
                ms_buf_puts(o, mp_mode_prefix(m, ty, b->params[i].mode));
                mir_print_ty(m, ty, o);
            }
            ms_buf_puts(o, "):\n");
        }
        for (uint32_t i = 0; i < b->ninsts; i++) {
            const MirInst *in = &b->insts[i];
            ms_buf_puts(o, "  ");
            if (in->res != MIR_NONE) {
                mp_val(&cx, o, in->res);
                ms_buf_puts(o, ": ");
                mir_print_ty(m, f->values[in->res], o);
                ms_buf_puts(o, " = ");
            }
            mp_inst(&cx, o, in);
            mp_loc(o, in->loc);
            ms_buf_putc(o, '\n');
        }
        ms_buf_puts(o, "  ");
        mp_term(&cx, o, &b->term);
        mp_loc(o, b->term_loc);
        ms_buf_putc(o, '\n');
    }
    ms_buf_puts(o, "}\n");
    free(cx.names);
}
