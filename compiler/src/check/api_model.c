/* The standard library's API model (ms/api_model.h). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/api_model.h"
#include "ms/doc.h"
#include "ms/methods.h"
#include "ms/program.h"

typedef struct ApiStrs {
    MsStr *items;
    uint32_t count, cap;
} ApiStrs;

typedef struct ApiMember {
    MsStr name, kind, signature, doc, contract, legacy_contract;
} ApiMember;

typedef struct ApiMembers {
    ApiMember *items;
    uint32_t count, cap;
} ApiMembers;

typedef struct ApiDecl {
    MsSymId sym;
    MsStr name;
    MsStr declaration;
    const char *kind;
    uint32_t nvars;
    ApiStrs operations, implements, implementations;
    ApiMembers members;
} ApiDecl;

typedef struct ApiModule {
    MsStr path;
    ApiDecl *decls;
    uint32_t ndecls, cap;
} ApiModule;

typedef struct Api {
    MsCheck *c;
    const MsStdFile *files;
    uint32_t nfiles;
    MsBuf *out;
} Api;

static const char *const empty_text = "";

/* ---- JSON ---- */

static void json_string(MsBuf *o, MsStr s) {
    ms_buf_putc(o, '"');
    for (uint32_t i = 0; i < s.len; i++) {
        const unsigned char ch = (unsigned char)s.ptr[i];
        switch (ch) {
        case '"': ms_buf_puts(o, "\\\""); break;
        case '\\': ms_buf_puts(o, "\\\\"); break;
        case '\n': ms_buf_puts(o, "\\n"); break;
        case '\r': ms_buf_puts(o, "\\r"); break;
        case '\t': ms_buf_puts(o, "\\t"); break;
        case '&': ms_buf_puts(o, "\\u0026"); break;
        case '<': ms_buf_puts(o, "\\u003c"); break;
        case '>': ms_buf_puts(o, "\\u003e"); break;
        default:
            if (ch < 0x20 || ch == 0x7f) {
                ms_buf_printf(o, "\\u%04x", ch);
            } else {
                ms_buf_putc(o, (char)ch);
            }
        }
    }
    ms_buf_putc(o, '"');
}

static void indent(MsBuf *o, int depth) {
    for (int i = 0; i < depth; i++) {
        ms_buf_puts(o, "  ");
    }
}

/* ---- the symbols a module exports ---- */

static int by_name(const void *a, const void *b) {
    const ApiDecl *x = a, *y = b;
    const uint32_t n = x->name.len < y->name.len ? x->name.len : y->name.len;
    const int r = memcmp(x->name.ptr, y->name.ptr, n);
    return r != 0 ? r : (x->name.len > y->name.len) - (x->name.len < y->name.len);
}

static void module_add(Api *api, ApiModule *m, MsSymId sym) {
    const MsStr name = ms_name(api->c->names, api->c->syms.name[sym]);
    for (uint32_t i = 0; i < m->ndecls; i++) {
        if (m->decls[i].name.len == name.len && memcmp(m->decls[i].name.ptr, name.ptr, name.len) == 0) {
            if (api->c->syms.ty[m->decls[i].sym] == MS_TY_NONE) {
                m->decls[i].sym = sym;
            }
            return;
        }
    }
    if (m->ndecls == m->cap) {
        m->cap = m->cap != 0 ? m->cap * 2 : 16;
        m->decls = ms_array_resize(m->decls, m->cap, sizeof *m->decls);
    }
    m->decls[m->ndecls++] = (ApiDecl){.sym = sym, .name = ms_name(api->c->names, api->c->syms.name[sym])};
}

static bool is_public(MsStr path) {
    return !(path.len >= 14 && memcmp(path.ptr, "@std/internal/", 14) == 0) &&
           !(path.len > 7 && memcmp(path.ptr + path.len - 7, "+source", 7) == 0);
}

/* ---- one declaration ---- */

/* These public entries have no `.ms` declaration to attach a comment to. */
static const struct {
    const char *name, *text;
} api_primitive_docs[] = {
    {"Bool", "Boolean truth values true and false; conditions require this type."},
    {"Int", "Signed whole numbers with checked arithmetic; overflow and division by zero fault."},
    {"Float", "Binary floating-point values, including signed zero, infinities and NaN."},
    {"Int8", "Signed 8-bit whole numbers (-128 to 127); arithmetic faults when the result leaves the range."},
    {"Int16", "Signed 16-bit whole numbers (-32768 to 32767); arithmetic faults when the result leaves the range."},
    {"Int32", "Signed 32-bit whole numbers (-2147483648 to 2147483647); arithmetic faults when the result leaves the range."},
    {"Int64", "Signed 64-bit whole numbers; the same type as Int while Int is 64 bits wide."},
    {"UInt8", "Unsigned 8-bit whole numbers (0 to 255); arithmetic faults when the result leaves the range."},
    {"UInt16", "Unsigned 16-bit whole numbers (0 to 65535); arithmetic faults when the result leaves the range."},
    {"UInt32", "Unsigned 32-bit whole numbers (0 to 4294967295); arithmetic faults when the result leaves the range."},
    {"UInt64", "Unsigned 64-bit whole numbers (0 to 18446744073709551615); arithmetic faults when the result leaves the range."},
    {"Float32", "Binary32 floating-point values; each operation rounds to binary32, and literals need a Float32 type to adopt it."},
    {"Float64", "Binary64 floating-point values; the same type as Float."},
    {"String", "UTF-8 text addressed by byte offsets; length is bytes, scalar_length counts Unicode scalars, and chars() walks scalars."},
    {"Void", "The single value void, used when an operation returns no useful payload."},
    {"Never", "The return type of computations that cannot return a value, such as panic."},
};

static void json_strings(MsBuf *o, const MsStr *items, size_t n, int depth) {
    if (n == 0) {
        ms_buf_puts(o, "[]");
        return;
    }
    ms_buf_puts(o, "[\n");
    for (size_t i = 0; i < n; i++) {
        indent(o, depth + 1);
        json_string(o, items[i]);
        ms_buf_puts(o, i + 1 < n ? ",\n" : "\n");
    }
    indent(o, depth);
    ms_buf_putc(o, ']');
}

static MsStr show_ty(Api *api, MsTy ty) {
    MsBuf b = {0};
    ms_ty_show(&b, api->c->names, &api->c->tys, ty);
    const MsStr text = ms_arena_fmt(&api->c->arena, "%.*s", (int)b.len, b.data == NULL ? "" : b.data);
    ms_buf_free(&b);
    return text;
}

/* `T`, or `T: Hashable & Comparable` for a bounded type variable. */
static MsStr variable_text(Api *api, MsTy var) {
    MsCheck *c = api->c;
    const MsStr name = ms_name(c->names, c->tys.name[var]);
    MsStr text = ms_arena_fmt(&c->arena, "%.*s", (int)name.len, name.ptr);
    const MsVarInfo *info = var < c->var_info_cap ? &c->var_info[var] : NULL;
    for (uint32_t i = 0; info != NULL && i < info->nbounds; i++) {
        const MsStr bound = show_ty(api, info->bounds[i]);
        text = ms_arena_fmt(&c->arena, "%.*s%s%.*s", (int)text.len, text.ptr, i == 0 ? ": " : " & ", (int)bound.len, bound.ptr);
    }
    return text;
}

/* ---- operations: `name: signature` ---- */

typedef struct ApiOp {
    MsStr key, value;
} ApiOp;

typedef struct ApiOps {
    ApiOp *items;
    size_t count, cap;
} ApiOps;

static void ops_put(ApiOps *ops, MsStr key, MsStr value) {
    for (size_t i = 0; i < ops->count; i++) { /* a later operation of the same name replaces the earlier */
        if (ops->items[i].key.len == key.len && memcmp(ops->items[i].key.ptr, key.ptr, key.len) == 0) {
            ops->items[i].value = value;
            return;
        }
    }
    if (ops->count == ops->cap) {
        ops->cap = ops->cap != 0 ? ops->cap * 2 : 16;
        ops->items = ms_array_resize(ops->items, ops->cap, sizeof *ops->items);
    }
    ops->items[ops->count++] = (ApiOp){key, value};
}

/* The operation's name, with its own type variables: `group_by[K: Hashable]`. */
static MsStr operation_name(Api *api, const MsOperation *op) {
    MsCheck *c = api->c;
    MsStr text = ms_name(c->names, op->name);
    for (uint32_t i = 0; i < op->nvars; i++) {
        const MsStr var = variable_text(api, op->vars[i]);
        text = ms_arena_fmt(&c->arena, "%.*s%s%.*s%s", (int)text.len, text.ptr, i == 0 ? "[" : ", ", (int)var.len, var.ptr,
                            i + 1 == op->nvars ? "]" : "");
    }
    return text;
}

/* The interfaces `intrinsics.ms` declares for a primitive and the families it shares. */
static const struct {
    const char *family;
    const char *const *members;
} api_shared[] = {
    {"IntegerOperations", (const char *const[]){"Int", "Int8", "Int16", "Int32", "UInt8", "UInt16", "UInt32", "UInt64", NULL}},
    {"SignedIntegerOperations", (const char *const[]){"Int", "Int8", "Int16", "Int32", NULL}},
};

/* The names of the interfaces a primitive's operations come from, own first; returns how many. */
static size_t api_intrinsic_names(Api *api, MsStr receiver, const char **names) {
    MsCheck *c = api->c;
    size_t n = 0;
    const MsStr own = ms_arena_fmt(&c->arena, "%.*sOperations", (int)receiver.len, receiver.ptr);
    names[n++] = own.ptr; /* arena text is NUL-terminated */
    for (size_t i = 0; i < sizeof api_shared / sizeof *api_shared; i++) {
        for (const char *const *m = api_shared[i].members; *m != NULL; m++) {
            if (ms_text_is(receiver, *m)) {
                names[n++] = api_shared[i].family;
            }
        }
    }
    return n;
}

static MsSymId api_intrinsic_symbol(Api *api, const char *name) {
    return ms_map_get(&api->c->std_types, ms_intern(api->c->names, name, (uint32_t)strlen(name)));
}

static void primitive_operations(Api *api, MsStr receiver, MsTy self, ApiOps *ops) {
    MsCheck *c = api->c;
    const char *names[4];
    const size_t n = api_intrinsic_names(api, receiver, names);
    for (size_t i = 0; i < n; i++) {
        const uint32_t iface = api_intrinsic_symbol(api, names[i]);
        const MsOperations *operations = iface == MS_NONE ? NULL : ms_interface_operations(c->methods, iface);
        uint32_t nvars = 0;
        const MsTy *vars = iface == MS_NONE ? NULL : ms_sym_vars(c, iface, &nvars);
        for (uint32_t k = 0; operations != NULL && k < operations->count; k++) {
            const MsOperation *op = &operations->items[k];
            MsTy ty = op->ty;
            if (nvars > 0) {
                const MsTy args[1] = {self};
                const MsTySubst subst = {.vars = vars, .args = args, .count = 1};
                ty = ms_ty_subst(&c->tys, &c->arena, ty, &subst);
            }
            ops_put(ops, ms_name(c->names, op->name), show_ty(api, ty));
        }
    }
}

static int by_key(const void *a, const void *b) {
    const MsStr x = *(const MsStr *)a, y = *(const MsStr *)b;
    const uint32_t n = x.len < y.len ? x.len : y.len;
    const int r = memcmp(x.ptr, y.ptr, n);
    return r != 0 ? r : (x.len > y.len) - (x.len < y.len);
}

static bool list_has(const MsStr *list, size_t n, MsStr text) {
    for (size_t i = 0; i < n; i++) {
        if (list[i].len == text.len && memcmp(list[i].ptr, text.ptr, text.len) == 0) {
            return true;
        }
    }
    return false;
}

/* The operations of the type: those of an interface or primitive, then the methods its impls and
 * inherent impls supply, as sorted `name: signature` texts. */
static size_t collect_operations(Api *api, MsSymId sym, MsStr *out, size_t max) {
    MsCheck *c = api->c;
    const MsDecl *decl = c->syms.decl[sym];
    ApiOps ops = {0};
    if (decl != NULL && decl->kind == MS_D_INTERFACE) {
        const MsOperations *operations = ms_interface_operations(c->methods, sym);
        for (uint32_t k = 0; operations != NULL && k < operations->count; k++) {
            ops_put(&ops, operation_name(api, &operations->items[k]), show_ty(api, operations->items[k].ty));
        }
    }
    /* `Int64` and `Float64` are the types `Int` and `Float` under other names and list nothing. */
    const bool renamed = decl == NULL && c->syms.ty[sym] != MS_TY_NONE && c->tys.name[c->syms.ty[sym]] != c->syms.name[sym];
    if (decl == NULL && !renamed) {
        primitive_operations(api, ms_name(c->names, c->syms.name[sym]), c->syms.ty[sym], &ops);
    }
    size_t n = 0;
    for (size_t i = 0; i < ops.count && n < max; i++) {
        out[n++] = ms_arena_fmt(&c->arena, "%.*s: %.*s", (int)ops.items[i].key.len, ops.items[i].key.ptr,
                                (int)ops.items[i].value.len, ops.items[i].value.ptr);
    }
    free(ops.items);
    const bool is_type = decl == NULL || decl->kind == MS_D_TYPE || decl->kind == MS_D_ENUM || decl->kind == MS_D_INTERFACE ||
                         decl->kind == MS_D_ALIAS;
    const MsMethods *rows = &c->methods->methods;
    const MsTy self = c->syms.ty[sym];
    for (uint32_t i = 0; is_type && !renamed && self != MS_TY_NONE && i < rows->count && n < max; i++) {
        if (c->tys.id[rows->receiver[i]] != c->tys.id[self] || rows->decl[i] == NULL) {
            continue;
        }
        MsStr name = ms_name(c->names, rows->decl[i]->name);
        /* The method's own variables follow the impl's. */
        uint32_t nown = rows->decl[i]->type_params.len < rows->nvars[i] ? rows->decl[i]->type_params.len : rows->nvars[i];
        const MsTy *own = rows->vars + rows->vars_at[i] + (rows->nvars[i] - nown);
        /* A native method of an unbounded receiver is an operation of the type itself, which lists
         * its own type variables; every other method is listed by its name alone. */
        bool bounded = false;
        const uint32_t receiver_sym = c->tys.def[rows->receiver[i]];
        uint32_t ndeclared = 0;
        const MsTy *declared = receiver_sym == 0 ? NULL : ms_sym_vars(c, receiver_sym - 1, &ndeclared);
        for (uint32_t k = 0; k < rows->nvars[i] - nown; k++) {
            const MsTy v = rows->vars[rows->vars_at[i] + k];
            const uint32_t has = v < c->var_info_cap ? c->var_info[v].nbounds : 0;
            const uint32_t base = k < ndeclared && declared[k] < c->var_info_cap ? c->var_info[declared[k]].nbounds : 0;
            bounded = bounded || has > base;
        }
        if (rows->decl[i]->body.len != 0 || bounded) {
            nown = 0;
        }
        for (uint32_t k = 0; k < nown; k++) {
            const MsStr var = variable_text(api, own[k]);
            name = ms_arena_fmt(&c->arena, "%.*s%s%.*s%s", (int)name.len, name.ptr, k == 0 ? "[" : ", ", (int)var.len, var.ptr,
                                k + 1 == nown ? "]" : "");
        }
        const MsStr op = ms_arena_fmt(&c->arena, "%.*s: %.*s", (int)name.len, name.ptr, (int)show_ty(api, rows->ty[i]).len,
                                      show_ty(api, rows->ty[i]).ptr);
        if (!list_has(out, n, op)) {
            out[n++] = op;
        }
    }
    qsort(out, n, sizeof *out, by_key);
    return n;
}

static MsStr bundled_text(const MsCheck *c, MsSymId sym) {
    const MsModId m = c->syms.module[sym];
    return m == MS_NONE ? (MsStr){"", 0} : c->mods[m].text;
}

static const char *decl_kind(const Api *api, MsSymId sym) {
    const MsDecl *d = api->c->syms.decl[sym];
    if (d == NULL) {
        return "type";
    }
    switch ((MsDeclKind)d->kind) {
    case MS_D_FN: return "fn";
    case MS_D_CONST: return "constant";
    case MS_D_TYPE: return d->u.type.external ? "native" : "type";
    case MS_D_ENUM: return "alternative";
    case MS_D_ALIAS: return "alias";
    case MS_D_INTERFACE: return "interface";
    default: return "type";
    }
}

static bool decl_opaque(const MsDecl *d) {
    if (d == NULL) {
        return false;
    }
    return (d->kind == MS_D_TYPE && d->u.type.opaque) || (d->kind == MS_D_ENUM && d->u.enumeration.opaque);
}

/* The type of a literal collection of literals, `List[Int]` or `Map[String, Float]`, for a constant the checker's body
 * pass does not type yet; empty when an element is not a literal. */
static MsStr api_literal_type(Api *api, const MsExpr *e) {
    MsCheck *c = api->c;
    const MsStr none = {empty_text, 0};
    switch ((MsExprKind)e->kind) {
    case MS_E_NUMBER: {
        const MsStr spelling = ms_name(c->names, e->u.sym);
        bool hex = spelling.len > 1 && spelling.ptr[0] == '0' && (spelling.ptr[1] == 'x' || spelling.ptr[1] == 'X');
        bool real = false;
        for (uint32_t i = 0; i < spelling.len && !hex; i++) {
            real = real || spelling.ptr[i] == '.' || spelling.ptr[i] == 'e' || spelling.ptr[i] == 'E';
        }
        return real ? (MsStr){"Float", 5} : (MsStr){"Int", 3};
    }
    case MS_E_BOOL: return (MsStr){"Bool", 4};
    case MS_E_TEXT: return (MsStr){"String", 6};
    case MS_E_UNARY: return e->op == MS_U_NEG || e->op == MS_U_PLUS ? api_literal_type(api, e->u.bin.left) : none;
    case MS_E_LIST: {
        if (e->u.list.len == 0) {
            return none;
        }
        const MsStr element = api_literal_type(api, e->u.list.ptr[0]);
        return element.len == 0 ? none : ms_arena_fmt(&c->arena, "List[%.*s]", (int)element.len, element.ptr);
    }
    case MS_E_MAP: {
        if (e->u.map.len == 0) {
            return none;
        }
        const MsStr key = api_literal_type(api, e->u.map.ptr[0].key), value = api_literal_type(api, e->u.map.ptr[0].value);
        return key.len == 0 || value.len == 0 ? none
                                              : ms_arena_fmt(&c->arena, "Map[%.*s, %.*s]", (int)key.len, key.ptr, (int)value.len, value.ptr);
    }
    default: return none;
    }
}

/* The declaration's type as the checker prints it; a constant shows its value's type. */
static MsStr decl_type_text(Api *api, MsSymId sym, MsStr name) {
    MsCheck *c = api->c;
    const MsDecl *decl = c->syms.decl[sym];
    if (decl == NULL) { /* `Float64` is the type `Float` under another name */
        return name;
    }
    MsTy shown = c->syms.ty[sym];
    if (decl->kind == MS_D_CONST && shown == MS_TY_NONE && decl->u.konst.ty == NULL) {
        return api_literal_type(api, decl->u.konst.value);
    }
    if (decl->kind == MS_D_CONST && shown != MS_TY_NONE) {
        shown = c->tys.result[shown]; /* a constant's symbol is a function of no parameters */
    }
    return show_ty(api, shown);
}

/* ---- lists ---- */

static void api_strs_push(ApiStrs *l, MsStr s) {
    if (l->count == l->cap) {
        l->cap = l->cap != 0 ? l->cap * 2 : 8;
        l->items = ms_array_resize(l->items, l->cap, sizeof *l->items);
    }
    l->items[l->count++] = s;
}

static void api_members_push(ApiMembers *l, ApiMember m) {
    if (l->count == l->cap) {
        l->cap = l->cap != 0 ? l->cap * 2 : 8;
        l->items = ms_array_resize(l->items, l->cap, sizeof *l->items);
    }
    l->items[l->count++] = m;
}

static void api_render_form(Api *api, MsBuf *b, const MsDecl *impl);

static int api_str_cmp(MsStr x, MsStr y) {
    const uint32_t n = x.len < y.len ? x.len : y.len;
    const int r = memcmp(x.ptr, y.ptr, n);
    return r != 0 ? r : (x.len > y.len) - (x.len < y.len);
}


static bool api_strs_has(const ApiStrs *l, MsStr text) {
    for (uint32_t i = 0; i < l->count; i++) {
        if (l->items[i].len == text.len && memcmp(l->items[i].ptr, text.ptr, text.len) == 0) {
            return true;
        }
    }
    return false;
}

static int api_by_text(const void *a, const void *b) { return api_str_cmp(*(const MsStr *)a, *(const MsStr *)b); }

static void api_sort_strs(ApiStrs *l) {
    if (l->count > 1) {
        qsort(l->items, l->count, sizeof *l->items, api_by_text);
    }
}

/* Members sort by kind, name and contract; equal ones keep their order. */
static void api_sort_members(ApiMembers *l) {
    for (uint32_t i = 1; i < l->count; i++) {
        const ApiMember m = l->items[i];
        uint32_t k = i;
        while (k > 0) {
            const ApiMember *p = &l->items[k - 1];
            int r = api_str_cmp(p->kind, m.kind);
            r = r != 0 ? r : api_str_cmp(p->name, m.name);
            r = r != 0 ? r : api_str_cmp(p->contract, m.contract);
            if (r <= 0) {
                break;
            }
            l->items[k] = *p;
            k--;
        }
        l->items[k] = m;
    }
}

/* ---- written types and signatures (crates/ms-tooling/src/guide/render.rs) ---- */

static MsStr api_arena_text(Api *api, const MsBuf *b) {
    return ms_arena_fmt(&api->c->arena, "%.*s", (int)b->len, b->data == NULL ? "" : b->data);
}

static void api_put(MsBuf *b, MsStr s) { ms_buf_put(b, s.ptr, s.len); }

static void api_put_name(Api *api, MsBuf *b, MsSym name) { api_put(b, ms_name(api->c->names, name)); }

static void render_type(Api *api, MsBuf *b, const MsTypeRef *t);

static void render_param_list(Api *api, MsBuf *b, MsParams params, const char *separator) {
    (void)separator;
    for (uint32_t i = 0; i < params.len; i++) {
        ms_buf_puts(b, i == 0 ? "" : ", ");
        ms_buf_puts(b, params.ptr[i]->moving ? "move " : "");
        ms_buf_puts(b, params.ptr[i]->is_mutable ? "var " : "");
        if (params.ptr[i]->ty != NULL) {
            render_type(api, b, params.ptr[i]->ty);
        }
    }
}

static void render_type(Api *api, MsBuf *b, const MsTypeRef *t) {
    if (t->kind == MS_TYPE_FN) {
        ms_buf_puts(b, "fn(");
        render_param_list(api, b, t->params, ", ");
        ms_buf_puts(b, ") ");
        render_type(api, b, t->result);
        return;
    }
    const MsStr name = ms_name(api->c->names, t->name);
    if (ms_text_is(name, "Optional") && t->args.len == 1) {
        const bool function = t->args.ptr[0]->kind == MS_TYPE_FN;
        ms_buf_puts(b, function ? "(" : "");
        render_type(api, b, t->args.ptr[0]);
        ms_buf_puts(b, function ? ")?" : "?");
        return;
    }
    api_put(b, name);
    for (uint32_t i = 0; i < t->args.len; i++) {
        ms_buf_puts(b, i == 0 ? "[" : ", ");
        render_type(api, b, t->args.ptr[i]);
    }
    ms_buf_puts(b, t->args.len > 0 ? "]" : "");
}

/* `[T: Bound = Default, ...]`, or nothing; `plain` leaves the defaults out. */
static void render_type_parameters(Api *api, MsBuf *b, MsTypeParams params, bool plain) {
    for (uint32_t i = 0; i < params.len; i++) {
        const MsTypeParam *p = params.ptr[i];
        ms_buf_puts(b, i == 0 ? "[" : ", ");
        api_put_name(api, b, p->name);
        for (uint32_t k = 0; k < p->bounds.len; k++) {
            ms_buf_puts(b, k == 0 ? ": " : " & ");
            render_type(api, b, p->bounds.ptr[k]);
        }
        if (p->def != NULL && !plain) {
            ms_buf_puts(b, " = ");
            render_type(api, b, p->def);
        }
    }
    ms_buf_puts(b, params.len > 0 ? "]" : "");
}

static void render_type_arguments(Api *api, MsBuf *b, MsTypeParams params) {
    for (uint32_t i = 0; i < params.len; i++) {
        ms_buf_puts(b, i == 0 ? "[" : ", ");
        api_put_name(api, b, params.ptr[i]->name);
    }
    ms_buf_puts(b, params.len > 0 ? "]" : "");
}

/* A default value in its written spelling: after the `=` that follows the parameter, up to the
 * `,` or end of line outside brackets or the bracket that closes the parameter list. `...` when
 * there is no source to read it from. */
static void render_default(Api *api, MsBuf *b, const MsParam *p, const MsStr *source) {
    if (p->def->kind == MS_E_NAME) {
        api_put_name(api, b, p->def->u.sym);
        return;
    }
    size_t at = p->pos.offset;
    while (source != NULL && at < source->len && source->ptr[at] != '=') {
        at++;
    }
    if (source == NULL || at >= source->len) {
        ms_buf_puts(b, "...");
        return;
    }
    const size_t start = at + 1;
    size_t end = start;
    int depth = 0;
    for (; end < source->len; end++) {
        const char ch = source->ptr[end];
        if (ch == '"') {
            const bool formatted = end > start && source->ptr[end - 1] == 'f';
            const size_t from = end - (formatted ? 1u : 0u);
            const size_t length = doc_text_end((MsStr){source->ptr + from, (uint32_t)(source->len - from)});
            if (length == 0) {
                break;
            }
            end = from + length - 1;
        } else if (ch == '(' || ch == '[' || ch == '{') {
            depth++;
        } else if (ch == ')' || ch == ']' || ch == '}') {
            if (depth == 0) {
                break;
            }
            depth--;
        } else if ((ch == ',' || ch == '\n') && depth == 0) {
            break;
        }
    }
    MsStr text = {source->ptr + start, (uint32_t)(end - start)};
    while (text.len > 0 && (text.ptr[0] == ' ' || text.ptr[0] == '\t')) {
        text.ptr++;
        text.len--;
    }
    while (text.len > 0 && (text.ptr[text.len - 1] == ' ' || text.ptr[text.len - 1] == '\n' || text.ptr[text.len - 1] == '\t' ||
                            text.ptr[text.len - 1] == '\r')) {
        text.len--;
    }
    api_put(b, text);
}

/* `(name: Type = default, ...)`. */
static void render_parameters(Api *api, MsBuf *b, MsParams params, const MsStr *source) {
    ms_buf_putc(b, '(');
    for (uint32_t i = 0; i < params.len; i++) {
        const MsParam *p = params.ptr[i];
        ms_buf_puts(b, i == 0 ? "" : ", ");
        ms_buf_puts(b, p->moving ? "move " : "");
        ms_buf_puts(b, p->is_mutable ? "var " : "");
        api_put_name(api, b, p->name);
        ms_buf_puts(b, ": ");
        if (p->ty != NULL) {
            render_type(api, b, p->ty);
        }
        if (p->def != NULL) {
            ms_buf_puts(b, " = ");
            render_default(api, b, p, source);
        }
    }
    ms_buf_putc(b, ')');
}

static const char *api_receiver_mode(bool mutating, bool consuming) {
    if (mutating) {
        return "var ";
    }
    return consuming ? "move " : "";
}

/* `fn name[T](params) Result:\n`, with `var ` or `move ` before the name for a method that changes or takes `self`. */
static void render_fn(Api *api, MsBuf *b, MsStr name, const MsFunc *f, bool mutating, bool consuming, const MsStr *source) {
    ms_buf_puts(b, api_receiver_mode(mutating, consuming));
    ms_buf_puts(b, "fn ");
    api_put(b, name);
    render_type_parameters(api, b, f->type_params, false);
    render_parameters(api, b, f->params, source);
    ms_buf_putc(b, ' ');
    if (f->result != NULL) {
        render_type(api, b, f->result);
    }
    ms_buf_puts(b, ":\n");
}

/* `fn var Receiver.name(...) Result:\n`. */
static void render_receiver_fn(Api *api, MsBuf *b, MsStr receiver, MsStr name, const MsFunc *f, bool mutating, bool consuming,
                               const MsStr *source) {
    ms_buf_puts(b, "fn ");
    ms_buf_puts(b, api_receiver_mode(mutating, consuming));
    api_put(b, receiver);
    ms_buf_putc(b, '.');
    api_put(b, name);
    render_type_parameters(api, b, f->type_params, false);
    render_parameters(api, b, f->params, source);
    ms_buf_putc(b, ' ');
    if (f->result != NULL) {
        render_type(api, b, f->result);
    }
    ms_buf_puts(b, ":\n");
}

/* ---- what a declaration holds ---- */

static MsTypeParams api_decl_params(const MsDecl *d) {
    switch ((MsDeclKind)d->kind) {
    case MS_D_FN: return d->u.fn.type_params;
    case MS_D_TYPE: return d->u.type.type_params;
    case MS_D_ENUM: return d->u.enumeration.type_params;
    case MS_D_ALIAS: return d->u.alias.type_params;
    case MS_D_INTERFACE: return d->u.iface.type_params;
    default: return (MsTypeParams){0};
    }
}

static MsParams decl_fields(const MsDecl *d) { return d->kind == MS_D_TYPE ? d->u.type.fields : (MsParams){0}; }

static uint32_t decl_ncases(const MsDecl *d) { return d->kind == MS_D_ENUM ? d->u.enumeration.cases.len : 0; }

static const char *api_decl_keyword(const MsDecl *decl) {
    if (decl_ncases(decl) > 0) {
        return "enum";
    }
    return decl->kind == MS_D_INTERFACE ? "interface" : "type";
}

typedef struct ApiOwn {
    const MsMethod *method;
    const MsDecl *impl; /* the inherent block it came from, or NULL for an interface's operation */
} ApiOwn;

typedef struct ApiOwnList {
    ApiOwn *items;
    uint32_t count, cap;
} ApiOwnList;

static void api_own_push(ApiOwnList *l, ApiOwn m) {
    if (l->count == l->cap) {
        l->cap = l->cap != 0 ? l->cap * 2 : 16;
        l->items = ms_array_resize(l->items, l->cap, sizeof *l->items);
    }
    l->items[l->count++] = m;
}

static int api_own_by_position(const void *a, const void *b) {
    const uint32_t x = ((const ApiOwn *)a)->method->pos.offset, y = ((const ApiOwn *)b)->method->pos.offset;
    return (x > y) - (x < y);
}

/* Whether the inherent block's receiver is the type applied to its own parameters, with no bounds of its own:
 * the form whose bodiless methods the type itself declares. */
static bool api_plain_receiver(const MsCheck *c, const MsDecl *impl, MsTypeParams params) {
    (void)c;
    const MsTypeRef *receiver = impl->u.impl.receiver;
    if (impl->u.impl.bounds.len > 0 || receiver->args.len != params.len) {
        return false;
    }
    for (uint32_t i = 0; i < params.len; i++) {
        const MsTypeRef *arg = receiver->args.ptr[i];
        if (arg->kind != MS_TYPE_NAMED || arg->args.len > 0 || arg->name != params.ptr[i]->name) {
            return false;
        }
    }
    return true;
}

/* The methods the type declares itself, in source order: an interface's operations, or the methods of
 * the inherent blocks (`fn Type.name`) written in the type's file, whichever half of it they landed in. */
static void api_own_methods(Api *api, MsSymId sym, ApiOwnList *out) {
    MsCheck *c = api->c;
    const MsDecl *decl = c->syms.decl[sym];
    if (decl == NULL) {
        return;
    }
    if (decl->kind == MS_D_INTERFACE) {
        for (uint32_t i = 0; i < decl->u.iface.methods.len; i++) {
            api_own_push(out, (ApiOwn){decl->u.iface.methods.ptr[i], NULL});
        }
        return;
    }
    if (decl->kind != MS_D_TYPE && decl->kind != MS_D_ENUM && decl->kind != MS_D_ALIAS) {
        return;
    }
    const MsSym name = ms_decl_name(decl);
    const MsStr path = ms_name(c->names, c->mods[c->syms.module[sym]].path);
    const bool twin = path.len > 7 && memcmp(path.ptr + path.len - 7, "+source", 7) == 0;
    const MsStr base = twin ? (MsStr){path.ptr, path.len - 7} : path;
    const MsStr other = twin ? base : ms_arena_fmt(&c->arena, "%.*s+source", (int)base.len, base.ptr);
    const MsModId halves[2] = {ms_module_find(c, ms_intern(c->names, base.ptr, base.len)),
                               ms_module_find(c, ms_intern(c->names, other.ptr, other.len))};
    for (int h = 0; h < 2; h++) {
        if (halves[h] == MS_NONE || (h == 1 && halves[1] == halves[0])) {
            continue;
        }
        const MsModule *syntax = c->mods[halves[h]].syntax;
        for (uint32_t i = 0; i < syntax->ndecls; i++) {
            const MsDecl *d = syntax->decls[i];
            if (d->kind != MS_D_IMPL || d->u.impl.contract != NULL || d->u.impl.receiver == NULL || d->u.impl.receiver->name != name) {
                continue;
            }
            if (!api_plain_receiver(c, d, api_decl_params(decl))) {
                continue;
            }
            for (uint32_t k = 0; k < d->u.impl.methods.len; k++) {
                if (d->u.impl.methods.ptr[k]->func.body.len == 0) {
                    api_own_push(out, (ApiOwn){d->u.impl.methods.ptr[k], d});
                }
            }
        }
    }
    if (out->count > 1) {
        qsort(out->items, out->count, sizeof *out->items, api_own_by_position);
    }
}

/* The member name of an operation: `map[U]` for a bodiless method of an unbounded receiver, which the
 * type lists with its own type variables; the name alone otherwise. */
static MsStr api_own_member_name(Api *api, const ApiOwn *m) {
    MsBuf b = {0};
    api_put_name(api, &b, m->method->func.name);
    bool bounded = false;
    if (m->impl != NULL) {
        for (uint32_t i = 0; i < m->impl->u.impl.bounds.len; i++) {
            bounded = bounded || m->impl->u.impl.bounds.ptr[i]->bounds.len > 0;
        }
    }
    if (m->impl != NULL && !bounded && m->method->func.body.len == 0) {
        render_type_parameters(api, &b, m->method->func.type_params, true);
    }
    const MsStr text = api_arena_text(api, &b);
    ms_buf_free(&b);
    return text;
}

static MsStr api_comment_at(Api *api, MsStr source, uint32_t offset) {
    MsBuf b = {0};
    ms_doc_leading_comment(&b, source, offset);
    const MsStr text = api_arena_text(api, &b);
    ms_buf_free(&b);
    return text;
}

/* The `declaration` excerpt of a type, enum, interface or alias. `receiver_methods` are the methods written
 * under it. */
static MsStr api_document_declaration(Api *api, const MsDecl *decl, const char *keyword, MsStr name, const MsStr *source, bool opaque,
                                  const ApiOwnList *methods, MsTypeParams params) {
    MsBuf b = {0};
    ms_buf_puts(&b, opaque ? "opaque " : "");
    ms_buf_puts(&b, keyword);
    ms_buf_putc(&b, ' ');
    api_put(&b, name);
    render_type_parameters(api, &b, params, false);
    ms_buf_puts(&b, ":\n");
    const MsParams fields = decl_fields(decl);
    for (uint32_t i = 0; i < fields.len && !opaque; i++) {
        ms_buf_puts(&b, "    ");
        api_put_name(api, &b, fields.ptr[i]->name);
        ms_buf_puts(&b, ": ");
        if (fields.ptr[i]->ty != NULL) {
            render_type(api, &b, fields.ptr[i]->ty);
        }
        if (fields.ptr[i]->def != NULL) {
            ms_buf_puts(&b, " = ");
            render_default(api, &b, fields.ptr[i], source);
        }
        ms_buf_putc(&b, '\n');
    }
    for (uint32_t i = 0; i < decl_ncases(decl) && !opaque; i++) {
        const MsCase *cs = decl->u.enumeration.cases.ptr[i];
        ms_buf_puts(&b, "    ");
        api_put_name(api, &b, cs->name);
        if (cs->fields.len > 0) {
            render_parameters(api, &b, cs->fields, source);
        }
        ms_buf_putc(&b, '\n');
    }
    MsBuf receiver = {0};
    api_put(&receiver, name);
    render_type_arguments(api, &receiver, params);
    const MsStr receiver_text = api_arena_text(api, &receiver);
    ms_buf_free(&receiver);
    if ((strcmp(keyword, "type") == 0 || strcmp(keyword, "enum") == 0) && methods->count > 0) {
        ms_buf_putc(&b, '\n');
    }
    for (uint32_t i = 0; i < methods->count; i++) {
        const MsMethod *m = methods->items[i].method;
        const MsStr method_name = ms_name(api->c->names, m->func.name);
        if (strcmp(keyword, "interface") == 0) {
            MsBuf header = {0};
            render_fn(api, &header, method_name, &m->func, m->mutating, m->consuming, source);
            ms_buf_puts(&b, "    ");
            ms_buf_put(&b, header.data, header.len - 2); /* without the trailing ":\n" */
            ms_buf_putc(&b, '\n');
            ms_buf_free(&header);
        } else {
            render_receiver_fn(api, &b, receiver_text, method_name, &m->func, m->mutating, m->consuming, source);
        }
    }
    const MsStr text = api_arena_text(api, &b);
    ms_buf_free(&b);
    return text;
}

static void api_member_field(Api *api, ApiDecl *d, MsStr source, const MsParam *field, MsStr name) {
    MsBuf b = {0};
    api_put_name(api, &b, field->name);
    ms_buf_puts(&b, ": ");
    if (field->ty != NULL) {
        render_type(api, &b, field->ty);
    }
    if (field->def != NULL && name.len == 0) {
        ms_buf_puts(&b, " = ");
        render_default(api, &b, field, &source);
    }
    const MsStr signature = api_arena_text(api, &b);
    ms_buf_free(&b);
    MsStr shown = name;
    if (name.len == 0) {
        shown = ms_name(api->c->names, field->name);
    }
    api_members_push(&d->members, (ApiMember){shown, {"field", 5}, signature, api_comment_at(api, source, field->pos.offset),
                                    {empty_text, 0}, {empty_text, 0}});
}

/* Fields, cases and operations of a declaration, each with its signature and comment. */
static void api_document_members(Api *api, ApiDecl *d, const MsDecl *decl, MsStr source, const ApiOwnList *methods, bool opaque,
                             bool in_interface, bool decorate) {
    for (uint32_t i = 0; i < decl_fields(decl).len && !opaque; i++) {
        api_member_field(api, d, source, decl_fields(decl).ptr[i], (MsStr){empty_text, 0});
    }
    for (uint32_t i = 0; i < decl_ncases(decl) && !opaque; i++) {
        const MsCase *cs = decl->u.enumeration.cases.ptr[i];
        MsBuf b = {0};
        api_put_name(api, &b, cs->name);
        if (cs->fields.len > 0) {
            render_parameters(api, &b, cs->fields, NULL);
        }
        const MsStr signature = api_arena_text(api, &b);
        ms_buf_free(&b);
        api_members_push(&d->members, (ApiMember){ms_name(api->c->names, cs->name), {"case", 4}, signature,
                                        api_comment_at(api, source, cs->pos.offset), {empty_text, 0}, {empty_text, 0}});
        for (uint32_t k = 0; k < cs->fields.len; k++) {
            const MsStr qualified = ms_arena_fmt(&api->c->arena, "%.*s.%.*s", (int)ms_name(api->c->names, cs->name).len,
                                                 ms_name(api->c->names, cs->name).ptr,
                                                 (int)ms_name(api->c->names, cs->fields.ptr[k]->name).len,
                                                 ms_name(api->c->names, cs->fields.ptr[k]->name).ptr);
            MsBuf f = {0};
            api_put_name(api, &f, cs->fields.ptr[k]->name);
            ms_buf_puts(&f, ": ");
            if (cs->fields.ptr[k]->ty != NULL) {
                render_type(api, &f, cs->fields.ptr[k]->ty);
            }
            const MsStr fs = api_arena_text(api, &f);
            ms_buf_free(&f);
            api_members_push(&d->members, (ApiMember){qualified, {"field", 5}, fs, api_comment_at(api, source, cs->fields.ptr[k]->pos.offset),
                                            {empty_text, 0}, {empty_text, 0}});
        }
    }
    for (uint32_t i = 0; i < methods->count; i++) {
        const ApiOwn *m = &methods->items[i];
        MsBuf b = {0};
        render_fn(api, &b, ms_name(api->c->names, m->method->func.name), &m->method->func, m->method->mutating,
                  m->method->consuming, &source);
        MsStr signature = api_arena_text(api, &b);
        ms_buf_free(&b);
        while (signature.len > 0 && (signature.ptr[signature.len - 1] == '\n' || signature.ptr[signature.len - 1] == ' ')) {
            signature.len--;
        }
        if (in_interface && signature.len > 0 && signature.ptr[signature.len - 1] == ':') {
            signature.len--;
        }
        MsStr name = decorate ? api_own_member_name(api, m) : ms_name(api->c->names, m->method->func.name);
        api_members_push(&d->members, (ApiMember){name, {"operation", 9}, signature, api_comment_at(api, source, m->method->pos.offset),
                                        {empty_text, 0}, {empty_text, 0}});
    }
}

/* `Name$methods[T]`, `Name$1$methods[T]`: the contract an inherent block was once known by, which the site anchors of
 * the generated reference still name. A block of the plain receiver form is `$methods`; each other form of the type in
 * the module takes the next number, in the order the forms first appear. */
static MsStr api_legacy_contract(Api *api, MsSymId sym, MsModId module, uint32_t method_offset) {
    MsCheck *c = api->c;
    const MsDecl *type = c->syms.decl[sym];
    const MsStr name = ms_name(c->names, c->syms.name[sym]);
    const MsTypeParams params = type == NULL ? (MsTypeParams){0} : api_decl_params(type);
    const MsModule *syntax = c->mods[module].syntax;
    const MsDecl *forms[64];
    uint32_t nforms = 0;
    const MsDecl *mine = NULL;
    for (uint32_t i = 0; i < syntax->ndecls && mine == NULL; i++) {
        const MsDecl *d = syntax->decls[i];
        if (d->kind != MS_D_IMPL || d->u.impl.contract != NULL || d->u.impl.receiver == NULL || d->u.impl.receiver->name != c->syms.name[sym]) {
            continue;
        }
        bool found = false;
        for (uint32_t k = 0; k < d->u.impl.methods.len; k++) {
            found = found || d->u.impl.methods.ptr[k]->pos.offset == method_offset;
        }
        if (api_plain_receiver(c, d, params)) {
            if (found) {
                mine = d;
            }
            continue;
        }
        /* Blocks of one form merge into the first of them. */
        MsBuf key = {0};
        api_render_form(api, &key, d);
        uint32_t at = nforms;
        for (uint32_t f = 0; f < nforms; f++) {
            MsBuf other = {0};
            api_render_form(api, &other, forms[f]);
            const bool same = other.len == key.len && (key.len == 0 || memcmp(other.data, key.data, key.len) == 0);
            ms_buf_free(&other);
            if (same) {
                at = f;
                break;
            }
        }
        ms_buf_free(&key);
        if (at == nforms && nforms < 64) {
            forms[nforms++] = d;
        }
        if (found) {
            mine = forms[at];
        }
    }
    MsBuf b = {0};
    api_put(&b, name);
    if (mine != NULL && !api_plain_receiver(c, mine, params)) {
        uint32_t number = 1;
        for (uint32_t f = 0; f < nforms; f++) {
            number = forms[f] == mine ? f + 1 : number;
        }
        ms_buf_printf(&b, "$%u", number);
    }
    ms_buf_puts(&b, "$methods");
    const bool plain = mine == NULL || api_plain_receiver(c, mine, params);
    uint32_t shown = 0;
    for (uint32_t i = 0; i < params.len; i++) {
        const MsTypeRef *arg = mine != NULL && !plain && i < mine->u.impl.receiver->args.len ? mine->u.impl.receiver->args.ptr[i] : NULL;
        const bool variable = plain || (arg != NULL && arg->kind == MS_TYPE_NAMED && arg->args.len == 0 && arg->name == params.ptr[i]->name);
        if (variable) {
            ms_buf_puts(&b, shown++ == 0 ? "[" : ", ");
            api_put_name(api, &b, params.ptr[i]->name);
        }
    }
    ms_buf_puts(&b, shown > 0 ? "]" : "");
    const MsStr text = api_arena_text(api, &b);
    ms_buf_free(&b);
    return text;
}

/* The receiver form of an inherent block as written: the receiver and its bounds. */
static void api_render_form(Api *api, MsBuf *b, const MsDecl *impl) {
    render_type(api, b, impl->u.impl.receiver);
    for (uint32_t i = 0; i < impl->u.impl.bounds.len; i++) {
        ms_buf_puts(b, i == 0 ? "|" : ";");
        api_put_name(api, b, impl->u.impl.bounds.ptr[i]->name);
        ms_buf_putc(b, ':');
        for (uint32_t k = 0; k < impl->u.impl.bounds.ptr[i]->bounds.len; k++) {
            ms_buf_puts(b, k == 0 ? "" : "&");
            render_type(api, b, impl->u.impl.bounds.ptr[i]->bounds.ptr[k]);
        }
    }
}

/* The inherent block that declares the method at `offset` of `module`, or NULL. */
static const MsDecl *api_impl_of(const MsCheck *c, MsModId module, uint32_t offset) {
    const MsModule *syntax = c->mods[module].syntax;
    for (uint32_t i = 0; i < syntax->ndecls; i++) {
        const MsDecl *d = syntax->decls[i];
        for (uint32_t k = 0; d->kind == MS_D_IMPL && k < d->u.impl.methods.len; k++) {
            if (d->u.impl.methods.ptr[k]->pos.offset == offset) {
                return d;
            }
        }
    }
    return NULL;
}

/* `// Receiver: List[T]; T: Clonable\n` when the methods of an impl are not simply those of the declared type. */
static MsStr api_receiver_context(Api *api, const MsMethods *rows, uint32_t i, MsTy declared) {
    MsCheck *c = api->c;
    MsBuf b = {0};
    const uint32_t nown = rows->decl[i] == NULL ? 0 : rows->decl[i]->type_params.len;
    const uint32_t nimpl = rows->nvars[i] > nown ? rows->nvars[i] - nown : 0;
    uint32_t bounded = 0;
    MsBuf bounds = {0};
    /* The checker lists a variable's bounds as the type declares them twice over, then the impl's own. */
    const MsDecl *impl = api_impl_of(c, rows->module[i], rows->pos[i].offset);
    const uint32_t receiver_sym = c->tys.def[rows->receiver[i]];
    uint32_t ndeclared = 0;
    const MsTy *type_vars = receiver_sym == 0 ? NULL : ms_sym_vars(c, receiver_sym - 1, &ndeclared);
    for (uint32_t k = 0; k < nimpl; k++) {
        const MsTy v = rows->vars[rows->vars_at[i] + k];
        MsBuf one = {0};
        uint32_t listed = 0;
        for (int pass = 0; pass < 2 && k < ndeclared && type_vars[k] < c->var_info_cap; pass++) {
            for (uint32_t b2 = 0; b2 < c->var_info[type_vars[k]].nbounds; b2++) {
                ms_buf_puts(&one, listed++ == 0 ? "" : " & ");
                api_put(&one, show_ty(api, c->var_info[type_vars[k]].bounds[b2]));
            }
        }
        for (uint32_t w = 0; impl != NULL && w < impl->u.impl.bounds.len; w++) {
            if (impl->u.impl.bounds.ptr[w]->name != c->tys.name[v]) {
                continue;
            }
            for (uint32_t b2 = 0; b2 < impl->u.impl.bounds.ptr[w]->bounds.len; b2++) {
                const MsTypeRef *written = impl->u.impl.bounds.ptr[w]->bounds.ptr[b2];
                ms_buf_puts(&one, listed++ == 0 ? "" : " & ");
                /* The resolved bound reads as the checker prints it (a type set lists its members). */
                bool resolved = false;
                for (uint32_t r = 0; v < c->var_info_cap && r < c->var_info[v].nbounds && !resolved; r++) {
                    const MsTy bound = c->var_info[v].bounds[r];
                    if (c->tys.name[bound] == written->name) {
                        api_put(&one, show_ty(api, bound));
                        resolved = true;
                    }
                }
                if (!resolved) {
                    render_type(api, &one, written);
                }
            }
        }
        if (listed > 0) {
            ms_buf_puts(&bounds, bounded++ == 0 ? "" : ", ");
            api_put_name(api, &bounds, c->tys.name[v]);
            ms_buf_puts(&bounds, ": ");
            ms_buf_put(&bounds, one.data, one.len);
        }
        ms_buf_free(&one);
    }
    const MsTy receiver = rows->receiver[i];
    const bool same = c->tys.id[receiver] == c->tys.id[declared] && c->tys.nargs[receiver] == c->tys.nargs[declared] &&
                      (c->tys.nargs[receiver] == 0 || receiver == declared);
    if (bounded > 0 || !same) {
        ms_buf_puts(&b, "// Receiver: ");
        api_put(&b, show_ty(api, receiver));
        if (bounded > 0) {
            ms_buf_puts(&b, "; ");
            ms_buf_put(&b, bounds.data, bounds.len);
        }
        ms_buf_putc(&b, '\n');
    }
    ms_buf_free(&bounds);
    const MsStr text = api_arena_text(api, &b);
    ms_buf_free(&b);
    return text;
}

/* Where the block that holds a method sits among its module's impls once blocks of one receiver form merge into
 * the first of them, which is the order the checker lists them in. */
static uint32_t api_group_position(Api *api, MsModId module, uint32_t offset) {
    MsCheck *c = api->c;
    const MsModule *syntax = c->mods[module].syntax;
    const MsDecl *mine = api_impl_of(c, module, offset);
    for (uint32_t i = 0; mine != NULL && i < syntax->ndecls; i++) {
        const MsDecl *d = syntax->decls[i];
        if (d->kind != MS_D_IMPL || d->u.impl.receiver == NULL) {
            continue;
        }
        if (d == mine) {
            return i;
        }
        if (d->u.impl.contract != NULL || mine->u.impl.contract != NULL || d->u.impl.receiver->name != mine->u.impl.receiver->name) {
            continue;
        }
        MsBuf x = {0}, y = {0};
        api_render_form(api, &x, d);
        api_render_form(api, &y, mine);
        const bool same = x.len == y.len && (x.len == 0 || memcmp(x.data, y.data, x.len) == 0);
        ms_buf_free(&x);
        ms_buf_free(&y);
        if (same) {
            return i;
        }
    }
    return UINT32_MAX;
}

typedef struct ApiRowKey {
    uint32_t module, group, row;
} ApiRowKey;

static int api_by_row_key(const void *a, const void *b) {
    const ApiRowKey *x = a, *y = b;
    if (x->module != y->module) {
        return x->module < y->module ? -1 : 1;
    }
    if (x->group != y->group) {
        return x->group < y->group ? -1 : 1;
    }
    return (x->row > y->row) - (x->row < y->row);
}

/* The declaration, member and operation text of the method `f` that row `i` of the method table gives `d`. */
static void api_add_implementation_row(Api *api, ApiDecl *d, uint32_t i, const MsFunc *f, MsStr contract, MsTy self) {
    MsCheck *c = api->c;
    const MsMethods *rows = &c->methods->methods;
    const bool inherent = rows->inherent[i];
    const MsStr name = ms_name(c->names, f->name);
    const MsStr context = api_receiver_context(api, rows, i, self);
    const bool mutating = (rows->access[i] & MS_METHOD_MUTATING) != 0, consuming = (rows->access[i] & MS_METHOD_CONSUMING) != 0;
    const MsStr module_text = c->mods[rows->module[i]].text;
    MsBuf b = {0};
    api_put(&b, context);
    if (inherent) {
        render_receiver_fn(api, &b, show_ty(api, rows->receiver[i]), name, f, mutating, consuming, NULL);
    } else {
        ms_buf_puts(&b, "impl ");
        api_put(&b, contract);
        ms_buf_puts(&b, " for ");
        api_put(&b, show_ty(api, rows->receiver[i]));
        ms_buf_puts(&b, ":\n    ");
        render_fn(api, &b, name, f, mutating, consuming, NULL);
    }
    api_strs_push(&d->implementations, api_arena_text(api, &b));
    ms_buf_free(&b);
    MsBuf sig = {0};
    api_put(&sig, context);
    MsBuf header = {0};
    render_fn(api, &header, name, f, mutating, consuming, &module_text);
    MsStr trimmed = {header.data, (uint32_t)header.len};
    while (trimmed.len > 0 && (trimmed.ptr[trimmed.len - 1] == '\n' || trimmed.ptr[trimmed.len - 1] == ' ')) {
        trimmed.len--;
    }
    api_put(&sig, trimmed);
    const MsStr signature = api_arena_text(api, &sig);
    ms_buf_free(&sig);
    ms_buf_free(&header);
    api_members_push(&d->members, (ApiMember){name, {"operation", 9}, signature, api_comment_at(api, module_text, rows->pos[i].offset),
                                             inherent ? (MsStr){empty_text, 0} : contract,
                                             inherent ? api_legacy_contract(api, d->sym, rows->module[i], rows->pos[i].offset)
                                                      : (MsStr){empty_text, 0}});
}

/* The contracts a type implements, and the declaration, member and operation of each method an impl or an inherent block
 * outside the type itself gives it. */
static void api_document_implementations(Api *api, ApiDecl *d, const ApiOwnList *own) {
    MsCheck *c = api->c;
    const MsSymId sym = d->sym;
    const MsDecl *decl = c->syms.decl[sym];
    const MsTy self = c->syms.ty[sym];
    const bool is_type = decl == NULL || decl->kind == MS_D_TYPE || decl->kind == MS_D_ENUM || decl->kind == MS_D_INTERFACE ||
                         decl->kind == MS_D_ALIAS;
    const bool renamed = decl == NULL && self != MS_TY_NONE && c->tys.name[self] != c->syms.name[sym];
    if (!is_type || renamed || self == MS_TY_NONE) {
        return;
    }
    const MsMethods *rows = &c->methods->methods;
    const MsFunc *done[512];
    uint32_t ndone = 0;
    ApiRowKey *order = malloc((rows->count + 1u) * sizeof *order);
    if (order == NULL) {
        ms_oom();
    }
    uint32_t norder = 0;
    for (uint32_t i = 0; i < rows->count; i++) {
        if (c->tys.id[rows->receiver[i]] == c->tys.id[self]) {
            order[norder++] = (ApiRowKey){rows->module[i], api_group_position(api, rows->module[i], rows->pos[i].offset), i};
        }
    }
    qsort(order, norder, sizeof *order, api_by_row_key);
    for (uint32_t at = 0; at < norder; at++) {
        const uint32_t i = order[at].row;
        const bool inherent = rows->inherent[i];
        const MsStr contract = rows->contract[i] == MS_TY_NONE ? (MsStr){"<unknown>", 9} : show_ty(api, rows->contract[i]);
        if (!inherent && !api_strs_has(&d->implements, contract)) {
            api_strs_push(&d->implements, contract);
        }
        const MsFunc *f = rows->decl[i];
        if (f == NULL) {
            continue;
        }
        bool seen = false;
        for (uint32_t k = 0; k < own->count; k++) {
            seen = seen || f == &own->items[k].method->func;
        }
        for (uint32_t k = 0; k < ndone; k++) {
            seen = seen || f == done[k];
        }
        if (seen || ndone == 512) {
            continue;
        }
        done[ndone++] = f;
        api_add_implementation_row(api, d, i, f, contract, self);
    }
    free(order);
    api_sort_strs(&d->implements);
    api_sort_members(&d->members);
}

/* A primitive's members: those of the interfaces `intrinsics.ms` declares for it, with `T`, the receiver the shared
 * families are written over, spelled as this type. */
static void api_primitive_members(Api *api, ApiDecl *d) {
    MsCheck *c = api->c;
    const bool renamed = c->syms.ty[d->sym] == MS_TY_NONE || c->tys.name[c->syms.ty[d->sym]] != c->syms.name[d->sym];
    if (renamed) {
        return;
    }
    const char *names[4];
    const size_t n = api_intrinsic_names(api, d->name, names);
    for (size_t i = 0; i < n; i++) {
        const MsSymId iface = api_intrinsic_symbol(api, names[i]);
        const MsDecl *decl = iface == MS_NONE ? NULL : c->syms.decl[iface];
        if (decl == NULL || decl->kind != MS_D_INTERFACE) {
            continue;
        }
        ApiOwnList methods = {0};
        api_own_methods(api, iface, &methods);
        const MsStr source = bundled_text(c, iface);
        if (i == 0) {
            d->declaration = api_document_declaration(api, decl, "type", d->name, NULL, false, &methods, api_decl_params(decl));
        }
        const uint32_t first = d->members.count;
        api_document_members(api, d, decl, source, &methods, false, true, false);
        uint32_t nvars = 0;
        (void)ms_sym_vars(c, iface, &nvars);
        for (uint32_t k = first; nvars > 0 && k < d->members.count; k++) {
            ApiMember *m = &d->members.items[k];
            MsStr signature = m->signature;
            const MsStr from[2] = {{"(other: T)", 10}, {") T", 3}};
            const MsStr to[2] = {ms_arena_fmt(&c->arena, "(other: %.*s)", (int)d->name.len, d->name.ptr),
                                 ms_arena_fmt(&c->arena, ") %.*s", (int)d->name.len, d->name.ptr)};
            for (int r = 0; r < 2; r++) {
                MsBuf b = {0};
                size_t at = 0;
                while (at < signature.len) {
                    if (at + from[r].len <= signature.len && memcmp(signature.ptr + at, from[r].ptr, from[r].len) == 0) {
                        api_put(&b, to[r]);
                        at += from[r].len;
                    } else {
                        ms_buf_putc(&b, signature.ptr[at++]);
                    }
                }
                signature = api_arena_text(api, &b);
                ms_buf_free(&b);
            }
            m->signature = signature;
        }
        free(methods.items);
    }
}

/* The declaration, members and implementation texts of a symbol. */
static void api_prepare_decl(Api *api, ApiDecl *d) {
    MsCheck *c = api->c;
    const MsSymId sym = d->sym;
    const MsDecl *decl = c->syms.decl[sym];
    const MsStr source = bundled_text(c, sym);
    const MsStr name = d->name;
    ApiOwnList methods = {0};
    api_own_methods(api, sym, &methods);
    d->declaration = (MsStr){empty_text, 0};
    d->kind = decl_kind(api, sym);
    (void)ms_sym_vars(c, sym, &d->nvars);
    if (decl != NULL && decl->kind == MS_D_FN) {
        MsBuf b = {0};
        render_fn(api, &b, name, &decl->u.fn, false, false, &source);
        d->declaration = api_arena_text(api, &b);
        ms_buf_free(&b);
    } else if (decl != NULL && decl->kind == MS_D_CONST) {
        const MsStr type = decl_type_text(api, sym, name);
        d->declaration = ms_arena_fmt(&c->arena, "%.*s: %.*s\n", (int)name.len, name.ptr, (int)type.len, type.ptr);
    } else if (decl != NULL) {
        const char *keyword = api_decl_keyword(decl);
        d->declaration = api_document_declaration(api, decl, keyword, name, &source, decl_opaque(decl), &methods, api_decl_params(decl));
        api_document_members(api, d, decl, source, &methods, decl_opaque(decl), decl->kind == MS_D_INTERFACE, decl->kind != MS_D_INTERFACE);
    } else {
        d->declaration = ms_arena_fmt(&c->arena, "type %.*s:\n", (int)name.len, name.ptr);
        api_primitive_members(api, d);
    }
    api_document_implementations(api, d, &methods);
    free(methods.items);
    MsStr operations[512];
    const size_t noperations = collect_operations(api, sym, operations, 512);
    for (size_t i = 0; i < noperations; i++) {
        api_strs_push(&d->operations, operations[i]);
    }
    api_sort_members(&d->members);
}

/* The doc text of `d` into `doc` and its effect lines into `effects`; the number of effect lines. */
static size_t api_doc_and_effects(const Api *api, const ApiDecl *d, MsBuf *doc, MsStr effects[16]) {
    MsCheck *c = api->c;
    const MsDecl *decl = c->syms.decl[d->sym];
    size_t neffects = 0;
    if (decl == NULL) {
        for (size_t i = 0; i < sizeof api_primitive_docs / sizeof *api_primitive_docs; i++) {
            if (ms_text_is(d->name, api_primitive_docs[i].name)) {
                ms_buf_puts(doc, api_primitive_docs[i].text);
            }
        }
    } else {
        ms_doc_leading_comment(doc, bundled_text(c, d->sym), decl->pos.offset);
        neffects = ms_doc_effect_lines(bundled_text(c, d->sym), decl->pos.offset, effects, 16);
    }
    return neffects;
}

/* The `members` array of `d`. */
static void emit_members(MsBuf *o, const ApiDecl *d, int depth) {
    ms_buf_puts(o, "\"members\": ");
    if (d->members.count == 0) {
        ms_buf_puts(o, "[]");
    } else {
        ms_buf_puts(o, "[\n");
        for (uint32_t i = 0; i < d->members.count; i++) {
            const ApiMember *m = &d->members.items[i];
            const struct {
                const char *key;
                MsStr value;
            } fields[] = {{"name", m->name}, {"kind", m->kind}, {"signature", m->signature},
                          {"doc", m->doc},   {"contract", m->contract}, {"legacy_contract", m->legacy_contract}};
            indent(o, depth + 2);
            ms_buf_puts(o, "{\n");
            for (size_t k = 0; k < sizeof fields / sizeof *fields; k++) {
                indent(o, depth + 3);
                ms_buf_printf(o, "\"%s\": ", fields[k].key);
                json_string(o, fields[k].value);
                ms_buf_puts(o, k + 1 < sizeof fields / sizeof *fields ? ",\n" : "\n");
            }
            indent(o, depth + 2);
            ms_buf_puts(o, i + 1 < d->members.count ? "},\n" : "}\n");
        }
        indent(o, depth + 1);
        ms_buf_putc(o, ']');
    }
}

static void emit_decl(Api *api, const ApiDecl *d, int depth) {
    MsBuf *o = api->out;
    MsCheck *c = api->c;
    const MsSymId sym = d->sym;
    const MsDecl *decl = c->syms.decl[sym];
    indent(o, depth);
    ms_buf_puts(o, "{\n");
    indent(o, depth + 1);
    ms_buf_puts(o, "\"declaration\": ");
    json_string(o, d->declaration);
    ms_buf_puts(o, ",\n");
    indent(o, depth + 1);
    ms_buf_puts(o, "\"name\": ");
    json_string(o, d->name);
    ms_buf_puts(o, ",\n");
    indent(o, depth + 1);
    MsBuf doc = {0};
    MsStr effects[16];
    const size_t neffects = api_doc_and_effects(api, d, &doc, effects);
    ms_buf_puts(o, "\"doc\": ");
    json_string(o, (MsStr){doc.data == NULL ? "" : doc.data, (uint32_t)doc.len});
    ms_buf_free(&doc);
    ms_buf_puts(o, ",\n");
    indent(o, depth + 1);
    ms_buf_puts(o, "\"effects\": ");
    json_strings(o, effects, neffects, depth + 1);
    ms_buf_puts(o, ",\n");
    indent(o, depth + 1);
    ms_buf_printf(o, "\"kind\": \"%s\",\n", decl_kind(api, sym));
    indent(o, depth + 1);
    ms_buf_printf(o, "\"opaque\": %s,\n", decl_opaque(decl) ? "true" : "false");
    indent(o, depth + 1);
    ms_buf_puts(o, "\"type\": ");
    json_string(o, decl_type_text(api, sym, d->name));
    ms_buf_puts(o, ",\n");
    indent(o, depth + 1);
    MsStr list[256] = {{0}};
    uint32_t nvars = 0;
    const MsTy *vars = c->syms.ty[sym] == MS_TY_NONE && decl == NULL ? NULL : ms_sym_vars(c, sym, &nvars);
    size_t nlist = 0;
    for (uint32_t i = 0; i < nvars && nlist < 256; i++) {
        list[nlist++] = variable_text(api, vars[i]);
    }
    ms_buf_puts(o, "\"type_parameters\": ");
    json_strings(o, list, nlist, depth + 1);
    ms_buf_puts(o, ",\n");
    indent(o, depth + 1);
    nlist = 0;
    const bool nominal = decl != NULL && (decl->kind == MS_D_TYPE || decl->kind == MS_D_ENUM || decl->kind == MS_D_INTERFACE);
    const MsDef def = nominal ? *ms_def(api->c, sym) : (MsDef){0};
    for (uint32_t i = 0; i < def.nfields && !decl_opaque(decl) && nlist < 256; i++) {
        const MsStr ft = show_ty(api, def.fields[i].ty);
        const MsStr fname = ms_name(c->names, def.fields[i].name);
        list[nlist++] = ms_arena_fmt(&c->arena, "%.*s: %.*s", (int)fname.len, fname.ptr, (int)ft.len, ft.ptr);
    }
    ms_buf_puts(o, "\"fields\": ");
    json_strings(o, list, nlist, depth + 1);
    ms_buf_puts(o, ",\n");
    indent(o, depth + 1);
    nlist = 0;
    for (uint32_t i = 0; i < def.ncases && !decl_opaque(decl) && nlist < 256; i++) {
        const MsCaseRow *cs = &def.cases[i];
        MsStr text = ms_name(c->names, cs->name);
        for (uint32_t k = 0; k < cs->nfields; k++) {
            const MsStr ft = show_ty(api, cs->fields[k].ty);
            const MsStr fname = ms_name(c->names, cs->fields[k].name);
            text = ms_arena_fmt(&c->arena, "%.*s%s%.*s: %.*s%s", (int)text.len, text.ptr, k == 0 ? "(" : ", ", (int)fname.len,
                                fname.ptr, (int)ft.len, ft.ptr, k + 1 == cs->nfields ? ")" : "");
        }
        list[nlist++] = text;
    }
    ms_buf_puts(o, "\"cases\": ");
    json_strings(o, list, nlist, depth + 1);
    ms_buf_puts(o, ",\n");
    indent(o, depth + 1);
    ms_buf_puts(o, "\"operations\": ");
    json_strings(o, d->operations.items, d->operations.count, depth + 1);
    ms_buf_puts(o, ",\n");
    indent(o, depth + 1);
    emit_members(o, d, depth);
    ms_buf_puts(o, ",\n");
    indent(o, depth + 1);
    ms_buf_puts(o, "\"implements\": ");
    json_strings(o, d->implements.items, d->implements.count, depth + 1);
    ms_buf_puts(o, ",\n");
    indent(o, depth + 1);
    ms_buf_puts(o, "\"implementation_declarations\": ");
    json_strings(o, d->implementations.items, d->implementations.count, depth + 1);
    ms_buf_putc(o, '\n');
    indent(o, depth);
    ms_buf_putc(o, '}');
}

/* A type satisfies a plain interface by shape: list each one whose operations the type has among its own, though
 * no `impl` names it. An interface with type parameters of its own has no exact operation text to compare. */
static void api_shape_interfaces(ApiModule *mods, uint32_t nmods) {
    for (uint32_t m = 0; m < nmods; m++) {
        for (uint32_t k = 0; k < mods[m].ndecls; k++) {
            ApiDecl *d = &mods[m].decls[k];
            if (strcmp(d->kind, "interface") == 0 || d->operations.count == 0) {
                continue;
            }
            for (uint32_t m2 = 0; m2 < nmods; m2++) {
                for (uint32_t k2 = 0; k2 < mods[m2].ndecls; k2++) {
                    const ApiDecl *iface = &mods[m2].decls[k2];
                    if (strcmp(iface->kind, "interface") != 0 || iface->nvars != 0 || iface->operations.count == 0 ||
                        api_strs_has(&d->implements, iface->name)) {
                        continue;
                    }
                    bool all = true;
                    for (uint32_t o = 0; o < iface->operations.count && all; o++) {
                        all = api_strs_has(&d->operations, iface->operations.items[o]);
                    }
                    if (all) {
                        api_strs_push(&d->implements, iface->name);
                    }
                }
            }
            api_sort_strs(&d->implements);
        }
    }
}

/* ---- the model ---- */

static int by_path(const void *a, const void *b) {
    const ApiModule *x = a, *y = b;
    const uint32_t n = x->path.len < y->path.len ? x->path.len : y->path.len;
    const int r = memcmp(x->path.ptr, y->path.ptr, n);
    return r != 0 ? r : (x->path.len > y->path.len) - (x->path.len < y->path.len);
}

static bool api_has_constant(const MsCheck *c, MsModId m) {
    const MsModule *syntax = c->mods[m].syntax;
    for (uint32_t i = 0; i < syntax->ndecls; i++) {
        if (syntax->decls[i]->kind == MS_D_CONST) {
            return true;
        }
    }
    return false;
}

/* The source half of a mixed file names the types its native half declares. */
static void api_share_native_names(MsCheck *c, MsModId m) {
    const MsStr path = ms_name(c->names, c->mods[m].path);
    if (path.len <= 7 || memcmp(path.ptr + path.len - 7, "+source", 7) != 0) {
        return;
    }
    const MsModId native = ms_module_find(c, ms_intern(c->names, path.ptr, path.len - 7));
    if (native == MS_NONE) {
        return;
    }
    const MsNameMap *scope = &c->mods[native].scope;
    for (uint32_t i = 0; i < scope->cap; i++) {
        if (scope->vals[i] != 0) {
            (void)ms_map_add(&c->mods[m].names, scope->keys[i], scope->vals[i] - 1);
        }
    }
}

/* Declares, resolves and checks every module so the tables the model reads are complete. */
static void api_prepare_program(MsCheck *c) {
    program_desugar_bundled(c);
    for (MsModId m = 0; m < c->nmods; m++) {
        ms_module_declare(c, m);
        api_share_native_names(c, m);
    }
    for (MsModId m = 0; m < c->nmods; m++) {
        ms_module_resolve_types(c, m);
    }
    ms_program_begin(c);
    for (MsModId m = 0; m < c->nmods; m++) {
        ms_module_ensure_operations(c, m, c->methods);
        ms_module_add_implementations(c, m, c->methods);
    }
    /* A constant's type comes from checking its initializer. */
    for (MsModId m = 0; m < c->nmods; m++) {
        if (api_has_constant(c, m)) {
            ms_module_check_bodies_with(c, m, c->methods);
        }
    }
}

void ms_api_model_json(MsBuf *out, MsCheck *c, const MsStdFile *files, uint32_t nfiles) {
    Api api = {.c = c, .files = files, .nfiles = nfiles, .out = out};
    api_prepare_program(c);
    ApiModule *mods = calloc(c->nmods + 1u, sizeof *mods);
    uint32_t nmods = 0;
    ApiModule prelude = {.path = cstr("prelude")};
    for (MsModId m = 0; m < c->nmods; m++) {
        const MsStr path = ms_name(c->names, c->mods[m].path);
        if (!is_public(path)) {
            continue;
        }
        ApiModule *mod = &mods[nmods];
        mod->path = path;
        /* A mixed file's source half exports under the file's own name too. */
        const MsStr twin_path = ms_arena_fmt(&c->arena, "%.*s+source", (int)path.len, path.ptr);
        const MsModId twin = ms_module_find(c, ms_intern(c->names, twin_path.ptr, twin_path.len));
        for (MsSymId s = 0; s < c->syms.count; s++) {
            if (c->syms.is_exported[s] && c->syms.module[s] != MS_NONE && (c->syms.module[s] == m || c->syms.module[s] == twin)) {
                module_add(&api, mod, s);
            }
        }
        nmods += mod->ndecls > 0 ? 1 : 0;
    }
    for (size_t i = 0; i < ms_primitive_count(); i++) {
        const MsStr name = cstr(ms_primitive_name(i));
        const uint32_t sym = ms_map_get(&c->primitives, ms_intern(c->names, name.ptr, name.len));
        if (sym != MS_NONE) {
            module_add(&api, &prelude, sym);
        }
    }
    for (size_t i = 0; i < sizeof prelude_names / sizeof *prelude_names; i++) {
        const uint32_t sym = ms_map_get(&c->std_types, ms_intern(c->names, prelude_names[i], (uint32_t)strlen(prelude_names[i])));
        if (sym != MS_NONE) {
            module_add(&api, &prelude, sym);
        }
    }
    if (prelude.ndecls > 0) {
        mods[nmods++] = prelude;
    }
    qsort(mods, nmods, sizeof *mods, by_path);
    for (uint32_t i = 0; i < nmods; i++) {
        qsort(mods[i].decls, mods[i].ndecls, sizeof *mods[i].decls, by_name);
        for (uint32_t k = 0; k < mods[i].ndecls; k++) {
            api_prepare_decl(&api, &mods[i].decls[k]);
        }
    }
    api_shape_interfaces(mods, nmods);
    ms_buf_puts(out, "{\n  \"modules\": [\n");
    for (uint32_t i = 0; i < nmods; i++) {
        ms_buf_puts(out, "    {\n      \"path\": ");
        json_string(out, mods[i].path);
        ms_buf_puts(out, ",\n      \"declarations\": [\n");
        for (uint32_t k = 0; k < mods[i].ndecls; k++) {
            emit_decl(&api, &mods[i].decls[k], 4);
            ms_buf_puts(out, k + 1 < mods[i].ndecls ? ",\n" : "\n");
        }
        ms_buf_puts(out, "      ]\n    }");
        ms_buf_puts(out, i + 1 < nmods ? ",\n" : "\n");
        free(mods[i].decls);
    }
    ms_buf_puts(out, "  ]\n}\n");
    free(mods);
}
