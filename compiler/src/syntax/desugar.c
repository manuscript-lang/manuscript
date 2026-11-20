/* Inherent-impl desugaring (see ms/desugar.h). Four steps over the module's declarations:
 *
 *   1. expand_set_receivers: an impl on a set alias becomes one impl per member.
 *   2. collect: keep every declaration, add the property-marker impls of bundled types, merge the
 *      inherent impls of one receiver form into the first, and report misused blocks.
 *   3. report_overlaps: two forms of one type that could match one application may not share a
 *      method name.
 *   4. emit: give each inherent impl a synthesized interface and name it as the impl's contract.
 *
 * Mirrors desugar_inherent_impls in crates/ms-check/src/passes.rs, including the order in which
 * node ids and errors are produced. Nodes of the input are shared, never changed: a declaration
 * the pass edits is copied first. Recursion over types is bounded by the parser's nesting limit. */
#include <string.h>

#include "ms/desugar.h"
#include "ms/hints.h"
#include "ms/text.h"

static const char *const builtin_scalars[] = {
    "Int", "Int8", "Int16", "Int32", "Int64", "UInt8", "UInt16", "UInt32", "UInt64", "Float",
    "Float32", "Bool", "String",
};

typedef struct Desugar {
    MsArena *arena;
    MsNames *names;
    uint32_t next_id;
    bool is_std;  /* a bundled module: the scalars have methods, and markers are read */
    MsStr source;
    MsBuf errors; /* MsInherentError */
} Desugar;

/* ---- strings ---- */

static MsStr sym_str(const Desugar *d, MsSym sym) { return ms_name(d->names, sym); }

static void put_str(MsBuf *out, MsStr s) {
    if (s.len > 0) {
        ms_buf_put(out, s.ptr, s.len);
    }
}

static MsStr arena_copy(MsArena *arena, const MsBuf *buf) {
    char *text = ms_arena_strndup(arena, buf->data == NULL ? "" : buf->data, buf->len);
    return (MsStr){text, (uint32_t)buf->len};
}

static void put_buf(MsBuf *out, const MsBuf *text) {
    if (text->len > 0) {
        ms_buf_put(out, text->data, text->len);
    }
}

static void report(Desugar *d, MsPos pos, const MsBuf *message) {
    MsInherentError error = {pos, arena_copy(d->arena, message)};
    MS_VEC_PUSH(d->errors, MsInherentError, error);
}

/* The vector's items as an arena array, and the vector freed. */
static void *take_items(MsArena *arena, MsBuf *buf, size_t align) {
    void *items = NULL;
    if (buf->len > 0) {
        items = ms_alloc(arena, buf->len, align);
        memcpy(items, buf->data, buf->len);
    }
    ms_buf_free(buf);
    return items;
}

/* ---- written types ---- */

static MsTypeRefs named_args(const MsTypeRef *t) {
    MsTypeRefs none = {NULL, 0};
    return t->kind == MS_TYPE_NAMED ? t->args : none;
}

/* The type's name; `fn` for function types. */
static MsSym type_name(Desugar *d, const MsTypeRef *t) {
    return t->kind == MS_TYPE_NAMED ? t->name : ms_intern_cstr(d->names, "fn");
}

static bool is_variable(const MsTypeRef *arg, const MsTypeParam *param) {
    return arg->kind == MS_TYPE_NAMED && arg->name == param->name && arg->args.len == 0;
}

/* Whether the receiver writes each type parameter, in order, and nothing else. */
static bool repeats_type_parameters(const MsTypeRef *receiver, MsTypeParams params) {
    MsTypeRefs args = named_args(receiver);
    if (args.len != params.len) {
        return false;
    }
    for (uint32_t i = 0; i < args.len; i++) {
        if (!is_variable(args.ptr[i], params.ptr[i])) {
            return false;
        }
    }
    return true;
}

/* Text identifying a written type, for grouping receiver methods that share a receiver. */
static void put_type_key(Desugar *d, MsBuf *out, const MsTypeRef *t) {
    if (t->kind == MS_TYPE_NAMED) {
        put_str(out, sym_str(d, t->name));
        ms_buf_putc(out, '[');
        for (uint32_t i = 0; i < t->args.len; i++) {
            if (i > 0) {
                ms_buf_putc(out, ',');
            }
            put_type_key(d, out, t->args.ptr[i]);
        }
        ms_buf_putc(out, ']');
        return;
    }
    ms_buf_puts(out, "fn(");
    for (uint32_t i = 0; i < t->params.len; i++) {
        const MsParam *param = t->params.ptr[i];
        if (i > 0) {
            ms_buf_putc(out, ',');
        }
        ms_buf_puts(out, param->is_mutable ? "var " : "");
        if (param->ty != NULL) {
            put_type_key(d, out, param->ty);
        }
    }
    ms_buf_putc(out, ')');
    put_type_key(d, out, t->result);
}

/* The written bounds of an impl: `A:Ord&Eq;B:Show`. */
static void put_bounds_key(Desugar *d, MsBuf *out, MsTypeParams bounds) {
    for (uint32_t i = 0; i < bounds.len; i++) {
        if (i > 0) {
            ms_buf_putc(out, ';');
        }
        put_str(out, sym_str(d, bounds.ptr[i]->name));
        ms_buf_putc(out, ':');
        for (uint32_t k = 0; k < bounds.ptr[i]->bounds.len; k++) {
            if (k > 0) {
                ms_buf_putc(out, '&');
            }
            put_type_key(d, out, bounds.ptr[i]->bounds.ptr[k]);
        }
    }
}

/* Whether `t` names one of `params` anywhere, so it can match more than one application. */
static bool mentions_parameter(const MsTypeRef *t, MsTypeParams params) {
    if (t->kind == MS_TYPE_NAMED) {
        for (uint32_t i = 0; i < params.len; i++) {
            if (params.ptr[i]->name == t->name) {
                return true;
            }
        }
        for (uint32_t i = 0; i < t->args.len; i++) {
            if (mentions_parameter(t->args.ptr[i], params)) {
                return true;
            }
        }
        return false;
    }
    for (uint32_t i = 0; i < t->params.len; i++) {
        const MsTypeRef *ty = t->params.ptr[i]->ty;
        if (ty != NULL && mentions_parameter(ty, params)) {
            return true;
        }
    }
    return mentions_parameter(t->result, params);
}

static MsTypeRef *new_named_type(Desugar *d, uint32_t id, MsPos pos, MsSym name, MsTypeRefs args) {
    MsTypeRef *t = MS_NEW(d->arena, MsTypeRef);
    *t = (MsTypeRef){.id = id, .pos = pos, .kind = MS_TYPE_NAMED, .name = name, .args = args};
    return t;
}

/* `[A, B]`, or nothing for a type without parameters. */
static void put_parameter_names(Desugar *d, MsBuf *out, MsTypeParams params) {
    if (params.len == 0) {
        return;
    }
    ms_buf_putc(out, '[');
    for (uint32_t i = 0; i < params.len; i++) {
        if (i > 0) {
            ms_buf_puts(out, ", ");
        }
        put_str(out, sym_str(d, params.ptr[i]->name));
    }
    ms_buf_putc(out, ']');
}

/* ---- the types a module's methods may name ---- */

typedef struct TypeInfo {
    MsTypeParams params;
    bool is_interface;
} TypeInfo;

typedef struct TypeTable {
    MsNameMap index; /* name -> position in infos */
    MsBuf infos;     /* TypeInfo */
} TypeTable;

static void type_table_add(TypeTable *table, MsSym name, TypeInfo info) {
    uint32_t at = (uint32_t)MS_VEC_LEN(table->infos, TypeInfo);
    if (ms_map_add(&table->index, name, at)) {
        MS_VEC_PUSH(table->infos, TypeInfo, info);
    }
}

static const TypeInfo *type_table_find(const TypeTable *table, MsSym name) {
    uint32_t at = ms_map_get(&table->index, name);
    return at == MS_NONE ? NULL : &MS_VEC_AT(table->infos, TypeInfo, at);
}

static void type_table_free(TypeTable *table) {
    ms_map_free(&table->index);
    ms_buf_free(&table->infos);
}

/* The name, parameters and kind of a type declaration; false for any other declaration. */
static bool declared_type(const MsDecl *decl, MsSym *name, TypeInfo *info) {
    switch ((MsDeclKind)decl->kind) {
    case MS_D_TYPE:
        *name = decl->u.type.name;
        *info = (TypeInfo){decl->u.type.type_params, false};
        return true;
    case MS_D_ENUM:
        *name = decl->u.enumeration.name;
        *info = (TypeInfo){decl->u.enumeration.type_params, false};
        return true;
    case MS_D_INTERFACE:
        *name = decl->u.iface.name;
        *info = (TypeInfo){decl->u.iface.type_params, true};
        return true;
    case MS_D_FN:
    case MS_D_CONST:
    case MS_D_ALIAS:
    case MS_D_IMPL:
    case MS_D_TEST:
        return false;
    }
    return false;
}

static void add_declared_types(TypeTable *table, MsDecl *const *decls, uint32_t count) {
    for (uint32_t i = count; i > 0; i--) { /* the last declaration of a name wins */
        MsSym name = 0;
        TypeInfo info;
        if (declared_type(decls[i - 1], &name, &info)) {
            type_table_add(table, name, info);
        }
    }
}

/* Module declarations override foreign ones; a bundled module also has the built-in scalars. */
static TypeTable build_type_table(Desugar *d, const MsDesugarInput *in) {
    TypeTable table = {0};
    add_declared_types(&table, in->module->decls, in->module->ndecls);
    add_declared_types(&table, in->foreign, in->nforeign);
    if (d->is_std) {
        for (size_t i = 0; i < sizeof builtin_scalars / sizeof *builtin_scalars; i++) {
            type_table_add(&table, ms_intern_cstr(d->names, builtin_scalars[i]), (TypeInfo){{NULL, 0}, false});
        }
    }
    return table;
}

/* ---- step 1: impls on a set alias ---- */

static bool is_set_alias(const MsDecl *decl) {
    return decl->kind == MS_D_ALIAS && decl->u.alias.type_params.len == 0 && decl->u.alias.targets.len > 1;
}

/* The members of the set alias `name`; the last alias of that name counts. */
static const MsTypeRefs *find_set(const MsModule *module, MsSym name) {
    for (uint32_t i = module->ndecls; i > 0; i--) {
        const MsDecl *decl = module->decls[i - 1];
        if (is_set_alias(decl) && decl->u.alias.name == name) {
            return &decl->u.alias.targets;
        }
    }
    return NULL;
}

/* The impl's copy for one member of a set, with fresh ids from the receiver on. */
static MsDecl *impl_for_member(Desugar *d, const MsDecl *impl, const MsTypeRef *member) {
    MsDecl *copy = MS_NEW(d->arena, MsDecl);
    *copy = *impl;
    MsTypeRef *receiver = MS_NEW(d->arena, MsTypeRef);
    *receiver = *member;
    receiver->id = d->next_id;
    copy->u.impl.receiver = receiver;
    copy->id = d->next_id + 1;
    d->next_id += 2;
    copy->u.impl.methods.ptr = MS_NEW_N(d->arena, MsMethod *, impl->u.impl.methods.len);
    for (uint32_t i = 0; i < impl->u.impl.methods.len; i++) {
        copy->u.impl.methods.ptr[i] = ms_method_copy_fresh(d->arena, &d->next_id, impl->u.impl.methods.ptr[i]);
    }
    return copy;
}

/* The module's declarations with each inherent impl on a set alias replaced by one per member. */
static MsBuf expand_set_receivers(Desugar *d, const MsModule *module) {
    MsBuf out = {0};
    bool has_sets = false;
    for (uint32_t i = 0; i < module->ndecls && !has_sets; i++) {
        has_sets = is_set_alias(module->decls[i]);
    }
    for (uint32_t i = 0; i < module->ndecls; i++) {
        MsDecl *decl = module->decls[i];
        const MsTypeRef *receiver = ms_decl_is_inherent_impl(decl) ? decl->u.impl.receiver : NULL;
        bool bare = receiver != NULL && receiver->kind == MS_TYPE_NAMED && receiver->args.len == 0;
        const MsTypeRefs *members = has_sets && bare ? find_set(module, receiver->name) : NULL;
        if (members == NULL) {
            MS_VEC_PUSH(out, MsDecl *, decl);
            continue;
        }
        for (uint32_t k = 0; k < members->len; k++) {
            MS_VEC_PUSH(out, MsDecl *, impl_for_member(d, decl, members->ptr[k]));
        }
    }
    return out;
}

/* ---- property markers of bundled types ---- */

/* The start of the line that ends before source[limit]: the byte after the last '\n' before it. */
static uint32_t line_start(MsStr source, uint32_t limit) {
    while (limit > 0 && source.ptr[limit - 1] != '\n') {
        limit--;
    }
    return limit;
}

/* The property markers (`// ms: data`, `// ms: clonable`) in the comment lines just above the
 * declaration at `offset`, nearest first. A bundled type with no methods of its own declares its
 * properties there, since a marker has nothing to write as a method. */
static MsBuf property_markers(MsStr source, uint32_t offset) {
    MsBuf found = {0};
    uint32_t end = line_start(source, offset < source.len ? offset : source.len);
    while (end > 0) {
        uint32_t start = line_start(source, end - 1);
        MsStr line = ms_text_trim((MsStr){source.ptr + start, end - 1 - start});
        if (!ms_text_starts_with(line, "//")) {
            break;
        }
        MsStr text = ms_text_trim(ms_text_drop_front(line, 2));
        if (ms_str_equal(text, (MsStr){"ms: data", 8})) {
            MS_VEC_PUSH(found, const char *, "Data");
        }
        if (ms_str_equal(text, (MsStr){"ms: clonable", 12})) {
            MS_VEC_PUSH(found, const char *, "Clonable");
        }
        end = start;
    }
    return found;
}

/* The body-less `impl Marker for Type` a bundled type declares with a marker comment. Ids: the
 * receiver, then the contract, then the receiver's arguments, then the declaration. */
static MsDecl *marker_impl(Desugar *d, const MsDecl *type_decl, MsSym type, MsTypeParams params,
                           const char *marker) {
    uint32_t id = d->next_id;
    MsPos pos = type_decl->pos;
    MsTypeRefs args = {MS_NEW_N(d->arena, MsTypeRef *, params.len), params.len};
    for (uint32_t i = 0; i < params.len; i++) {
        args.ptr[i] = new_named_type(d, id + 2 + i, pos, params.ptr[i]->name, (MsTypeRefs){NULL, 0});
    }
    MsDecl *impl = MS_NEW(d->arena, MsDecl);
    *impl = (MsDecl){.id = id + 2 + params.len, .pos = pos, .synthetic = true, .kind = MS_D_IMPL};
    impl->u.impl.receiver = new_named_type(d, id, pos, type, args);
    impl->u.impl.contract = new_named_type(d, id + 1, pos, ms_intern_cstr(d->names, marker), (MsTypeRefs){NULL, 0});
    d->next_id += 3 + params.len;
    return impl;
}

/* The marker impls of `decl`, in the order its comment lines give them. */
static MsBuf marker_impls(Desugar *d, const MsDecl *decl) {
    MsBuf impls = {0};
    MsSym name = 0;
    TypeInfo info;
    if (!d->is_std || !declared_type(decl, &name, &info) || info.is_interface) {
        return impls;
    }
    MsBuf markers = property_markers(d->source, decl->pos.offset);
    for (size_t i = 0; i < MS_VEC_LEN(markers, const char *); i++) {
        MS_VEC_PUSH(impls, MsDecl *, marker_impl(d, decl, name, info.params, MS_VEC_AT(markers, const char *, i)));
    }
    ms_buf_free(&markers);
    return impls;
}

/* ---- step 2: collect ---- */

/* The output declarations and the receiver forms of the inherent impls among them. */
typedef struct Collected {
    MsBuf decls; /* MsDecl * */
    MsBuf forms; /* Form */
} Collected;

/* The inherent impls of one type that share a receiver form: the plain `T[A]`, a bounded
 * `T[A: Bound]`, or a specialized `T[Int]`. The declarations stay as written; the form only groups
 * their methods for the checks that treat them as one block. */
typedef struct Form {
    bool plain;               /* the receiver repeats the type's parameters and writes no bounds */
    MsSym type;               /* the receiver's type name */
    MsStr key;                /* identifies the receiver form among the type's impls */
    MsStr bounds;             /* the written bounds as text */
    const MsTypeRef *receiver; /* the first block's receiver */
    MsBuf methods;            /* MsMethod *, in declaration order */
} Form;

static Form *form_at(MsBuf *forms, size_t at) { return &MS_VEC_AT(*forms, Form, at); }

static void append_methods(Form *form, const MsDecl *impl) {
    for (uint32_t i = 0; i < impl->u.impl.methods.len; i++) {
        MS_VEC_PUSH(form->methods, MsMethod *, impl->u.impl.methods.ptr[i]);
    }
}

/* The position of the form for this receiver, or SIZE_MAX. */
static size_t find_form(MsBuf *forms, MsSym type, MsStr key) {
    for (size_t i = 0; i < MS_VEC_LEN(*forms, Form); i++) {
        const Form *form = form_at(forms, i);
        if (form->type == type && ms_str_equal(form->key, key)) {
            return i;
        }
    }
    return SIZE_MAX;
}

static void report_unknown_type(Desugar *d, const MsDecl *decl, MsSym type) {
    MsBuf message = {0};
    ms_buf_puts(&message, "inherent methods belong in the module that declares ");
    put_str(&message, sym_str(d, type));
    ms_buf_puts(&message, "; to add operations to another module's type, write a free function or a wrapper type");
    report(d, decl->pos, &message);
    ms_buf_free(&message);
}

static void report_interface_receiver(Desugar *d, const MsDecl *decl, MsSym type) {
    MsBuf message = {0};
    put_str(&message, sym_str(d, type));
    ms_buf_puts(&message, " is an interface; a method belongs to a type, and a type whose methods match the interface satisfies it");
    report(d, decl->pos, &message);
    ms_buf_free(&message);
}

static void report_receiver_arity(Desugar *d, const MsDecl *decl, MsSym type, MsTypeParams params) {
    MsBuf message = {0};
    ms_buf_puts(&message, "a method of ");
    put_str(&message, sym_str(d, type));
    ms_buf_puts(&message, " names one receiver argument per type parameter, as in 'fn ");
    put_str(&message, sym_str(d, type));
    put_parameter_names(d, &message, params);
    ms_buf_puts(&message, ".name()'");
    report(d, decl->pos, &message);
    ms_buf_free(&message);
}

/* The key of an inherent impl's receiver form: empty for the plain form. */
static MsStr form_key(Desugar *d, const MsDecl *impl, MsTypeParams params, bool *plain, MsStr *bounds) {
    const MsTypeRef *receiver = impl->u.impl.receiver;
    MsBuf text = {0};
    MsBuf written = {0};
    put_bounds_key(d, &written, impl->u.impl.bounds);
    *plain = repeats_type_parameters(receiver, params) && impl->u.impl.bounds.len == 0;
    if (!*plain) {
        put_type_key(d, &text, receiver);
        ms_buf_putc(&text, '|');
        put_buf(&text, &written);
    }
    *bounds = arena_copy(d->arena, &written);
    const MsStr key = arena_copy(d->arena, &text);
    ms_buf_free(&text);
    ms_buf_free(&written);
    return key;
}

MsStr ms_inherent_form(MsArena *arena, MsNames *names, const MsDecl *impl, MsTypeParams params) {
    Desugar d = {.arena = arena, .names = names};
    bool plain = false;
    MsStr bounds = {0};
    return form_key(&d, impl, params, &plain, &bounds);
}

/* Records an inherent impl of a declared type in the form it belongs to. */
static void collect_inherent(Desugar *d, MsBuf *forms, const MsDecl *decl, MsSym type, const TypeInfo *info) {
    bool plain = false;
    MsStr bounds = {0};
    const MsStr key = form_key(d, decl, info->params, &plain, &bounds);
    size_t at = find_form(forms, type, key);
    if (at == SIZE_MAX) {
        Form form = {.plain = plain, .type = type, .key = key, .bounds = bounds, .receiver = decl->u.impl.receiver};
        MS_VEC_PUSH(*forms, Form, form);
        at = MS_VEC_LEN(*forms, Form) - 1;
    }
    append_methods(form_at(forms, at), decl);
}

/* Keeps an impl unless its receiver is misused, which is reported. */
static void collect_impl(Desugar *d, Collected *out, const TypeTable *types, MsDecl *decl) {
    if (decl->u.impl.contract != NULL) {
        MS_VEC_PUSH(out->decls, MsDecl *, decl);
        return;
    }
    MsSym type = type_name(d, decl->u.impl.receiver);
    const TypeInfo *info = type_table_find(types, type);
    if (info == NULL) {
        report_unknown_type(d, decl, type);
    } else if (info->is_interface) {
        report_interface_receiver(d, decl, type);
    } else if (named_args(decl->u.impl.receiver).len != info->params.len) {
        report_receiver_arity(d, decl, type, info->params);
    } else {
        collect_inherent(d, &out->forms, decl, type, info);
        MS_VEC_PUSH(out->decls, MsDecl *, decl);
    }
}

static Collected collect(Desugar *d, const TypeTable *types, MsBuf *expanded) {
    Collected out = {0};
    for (size_t i = 0; i < MS_VEC_LEN(*expanded, MsDecl *); i++) {
        MsDecl *decl = MS_VEC_AT(*expanded, MsDecl *, i);
        if (decl->kind == MS_D_IMPL) {
            collect_impl(d, &out, types, decl);
            continue;
        }
        MS_VEC_PUSH(out.decls, MsDecl *, decl);
        MsBuf markers = marker_impls(d, decl);
        for (size_t k = 0; k < MS_VEC_LEN(markers, MsDecl *); k++) {
            MS_VEC_PUSH(out.decls, MsDecl *, MS_VEC_AT(markers, MsDecl *, k));
        }
        ms_buf_free(&markers);
    }
    return out;
}

/* ---- step 3: overlapping receiver forms ---- */

/* Whether two receiver forms of one type could match the same application: at each parameter
 * position one side is open or both write the same type. */
static bool forms_overlap(Desugar *d, const MsTypeRef *a, const MsTypeRef *b, MsTypeParams params) {
    MsTypeRefs left = named_args(a);
    MsTypeRefs right = named_args(b);
    for (uint32_t i = 0; i < params.len && i < left.len && i < right.len; i++) {
        if (mentions_parameter(left.ptr[i], params) || mentions_parameter(right.ptr[i], params)) {
            continue;
        }
        MsBuf x = {0};
        MsBuf y = {0};
        put_type_key(d, &x, left.ptr[i]);
        put_type_key(d, &y, right.ptr[i]);
        bool same = x.len == y.len && (x.len == 0 || memcmp(x.data, y.data, x.len) == 0);
        ms_buf_free(&x);
        ms_buf_free(&y);
        if (!same) {
            return false;
        }
    }
    return true;
}

static bool declares_method(const Form *form, MsSym name) {
    for (size_t i = 0; i < MS_VEC_LEN(form->methods, MsMethod *); i++) {
        if (MS_VEC_AT(form->methods, MsMethod *, i)->func.name == name) {
            return true;
        }
    }
    return false;
}

static void report_overlap(Desugar *d, const MsMethod *method, MsSym type) {
    MsBuf message = {0};
    ms_buf_puts(&message, "duplicate or overlapping implementation of ");
    put_str(&message, sym_str(d, method->func.name));
    ms_buf_puts(&message, " on ");
    put_str(&message, sym_str(d, type));
    ms_buf_puts(&message, ": another receiver form of the same type could match the same application");
    report(d, method->pos, &message);
    ms_buf_free(&message);
}

/* Two forms of one type under the same written bounds must not declare one method name. Each form
 * is compared with the later forms of its own group. */
static void report_overlaps(Desugar *d, MsBuf *forms, const TypeTable *types) {
    size_t count = MS_VEC_LEN(*forms, Form);
    for (size_t x = 0; x < count; x++) {
        const Form *a = form_at(forms, x);
        const TypeInfo *info = type_table_find(types, a->type);
        for (size_t y = x + 1; y < count; y++) {
            const Form *b = form_at(forms, y);
            if (b->type != a->type || !ms_str_equal(a->bounds, b->bounds)) {
                continue;
            }
            if (!forms_overlap(d, a->receiver, b->receiver, info->params)) {
                continue;
            }
            for (size_t k = 0; k < MS_VEC_LEN(b->methods, MsMethod *); k++) {
                const MsMethod *method = MS_VEC_AT(b->methods, MsMethod *, k);
                if (declares_method(a, method->func.name)) {
                    report_overlap(d, method, a->type);
                }
            }
        }
    }
}

void ms_desugar_inherent_impls(MsArena *arena, MsNames *names, const MsDesugarInput *in, MsDesugared *out) {
    Desugar d = {.arena = arena, .names = names, .next_id = in->module->node_count, .source = in->source};
    d.is_std = ms_text_starts_with(in->file, "@std/");
    TypeTable types = build_type_table(&d, in);
    MsBuf expanded = expand_set_receivers(&d, in->module);
    Collected collected = collect(&d, &types, &expanded);
    ms_buf_free(&expanded);
    report_overlaps(&d, &collected.forms, &types);
    out->nerrors = (uint32_t)MS_VEC_LEN(d.errors, MsInherentError);
    out->errors = take_items(arena, &d.errors, _Alignof(MsInherentError));
    out->ndecls = (uint32_t)MS_VEC_LEN(collected.decls, MsDecl *);
    out->decls = take_items(arena, &collected.decls, _Alignof(MsDecl *));
    for (size_t i = 0; i < MS_VEC_LEN(collected.forms, Form); i++) {
        ms_buf_free(&form_at(&collected.forms, i)->methods);
    }
    ms_buf_free(&collected.forms);
    type_table_free(&types);
    out->node_count = d.next_id;
}

void ms_module_desugar(MsCheck *c, MsModId module, MsStr source, MsDecl *const *foreign,
                       uint32_t nforeign, MsInherentError **errors, uint32_t *nerrors) {
    MsModuleRow *row = &c->mods[module];
    MsDesugarInput in = {ms_name(c->names, row->path), source, row->syntax, foreign, nforeign};
    MsDesugared result;
    ms_desugar_inherent_impls(&c->arena, c->names, &in, &result);
    MsModule *desugared = MS_NEW(&c->arena, MsModule);
    *desugared = *row->syntax;
    desugared->decls = result.decls;
    desugared->ndecls = result.ndecls;
    desugared->node_count = result.node_count;
    row->syntax = desugared;
    *errors = result.errors;
    *nerrors = result.nerrors;
}
