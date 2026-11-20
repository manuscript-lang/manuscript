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

static bool str_equal(MsStr a, MsStr b) { return a.len == b.len && memcmp(a.ptr, b.ptr, a.len) == 0; }

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

/* A type parameter and the type argument a receiver writes for it. */
typedef struct Binding {
    MsSym name;
    MsTypeRef *with;
} Binding;

static MsTypeRef *binding_for(const Binding *bindings, uint32_t count, MsSym name) {
    for (uint32_t i = 0; i < count; i++) {
        if (bindings[i].name == name) {
            return bindings[i].with;
        }
    }
    return NULL;
}

/* `t` with each named parameter replaced by the type argument written for it. Replaced nodes are
 * shared; the nodes above them are new, with the old ids. */
static MsTypeRef *substitute_parameters(Desugar *d, const MsTypeRef *t, const Binding *bindings,
                                        uint32_t count) {
    MsTypeRef *copy = MS_NEW(d->arena, MsTypeRef);
    *copy = *t;
    if (t->kind == MS_TYPE_NAMED) {
        MsTypeRef *with = t->args.len == 0 ? binding_for(bindings, count, t->name) : NULL;
        if (with != NULL) {
            return with;
        }
        copy->args.ptr = MS_NEW_N(d->arena, MsTypeRef *, t->args.len);
        for (uint32_t i = 0; i < t->args.len; i++) {
            copy->args.ptr[i] = substitute_parameters(d, t->args.ptr[i], bindings, count);
        }
        return copy;
    }
    copy->params.ptr = MS_NEW_N(d->arena, MsParam *, t->params.len);
    for (uint32_t i = 0; i < t->params.len; i++) {
        MsParam *param = MS_NEW(d->arena, MsParam);
        *param = *t->params.ptr[i];
        if (param->ty != NULL) {
            param->ty = substitute_parameters(d, param->ty, bindings, count);
        }
        copy->params.ptr[i] = param;
    }
    copy->result = substitute_parameters(d, t->result, bindings, count);
    return copy;
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

static bool is_inherent_impl(const MsDecl *decl) {
    return decl->kind == MS_D_IMPL && decl->u.impl.contract == NULL;
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
        const MsTypeRef *receiver = is_inherent_impl(decl) ? decl->u.impl.receiver : NULL;
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
        if (str_equal(text, (MsStr){"ms: data", 8})) {
            MS_VEC_PUSH(found, const char *, "Data");
        }
        if (str_equal(text, (MsStr){"ms: clonable", 12})) {
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

/* One output declaration. An inherent impl also carries the methods merged into it and its
 * receiver form, which `collect` fills in. */
typedef struct Entry {
    MsDecl *decl;
    bool inherent;
    bool plain;      /* the receiver repeats the type's parameters and writes no bounds */
    MsSym type;      /* the receiver's type name */
    MsStr form;      /* identifies the receiver form among the type's impls */
    MsStr bounds;    /* the written bounds as text */
    MsBuf methods;   /* MsMethod *, in merge order */
} Entry;

static Entry *entry_at(MsBuf *entries, size_t at) { return &MS_VEC_AT(*entries, Entry, at); }

static void push_plain_entry(MsBuf *entries, MsDecl *decl) {
    MS_VEC_PUSH(*entries, Entry, ((Entry){.decl = decl}));
}

static void append_methods(Entry *entry, const MsDecl *impl) {
    for (uint32_t i = 0; i < impl->u.impl.methods.len; i++) {
        MS_VEC_PUSH(entry->methods, MsMethod *, impl->u.impl.methods.ptr[i]);
    }
}

/* The position of the entry for this receiver form, or SIZE_MAX. */
static size_t find_form(MsBuf *entries, MsSym type, MsStr form) {
    for (size_t i = 0; i < MS_VEC_LEN(*entries, Entry); i++) {
        const Entry *entry = entry_at(entries, i);
        if (entry->inherent && entry->type == type && str_equal(entry->form, form)) {
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

/* Adds an inherent impl of a declared type: merged into the entry for its receiver form, or the
 * first of a new form. Methods merge into one block per receiver form: the plain `T[A]`, a
 * bounded `T[A: Bound]`, or a specialized `T[Int]`. */
static void collect_inherent(Desugar *d, MsBuf *entries, const MsDecl *decl, MsSym type, const TypeInfo *info) {
    const MsTypeRef *receiver = decl->u.impl.receiver;
    MsBuf bounds = {0};
    put_bounds_key(d, &bounds, decl->u.impl.bounds);
    bool plain = repeats_type_parameters(receiver, info->params) && decl->u.impl.bounds.len == 0;
    MsBuf form = {0};
    if (!plain) {
        put_type_key(d, &form, receiver);
        ms_buf_putc(&form, '|');
        put_buf(&form, &bounds);
    }
    MsStr form_text = arena_copy(d->arena, &form);
    size_t first = find_form(entries, type, form_text);
    if (first != SIZE_MAX) {
        append_methods(entry_at(entries, first), decl);
    } else {
        MsDecl *copy = MS_NEW(d->arena, MsDecl);
        *copy = *decl;
        Entry entry = {.decl = copy, .inherent = true, .plain = plain, .type = type, .form = form_text,
                       .bounds = arena_copy(d->arena, &bounds)};
        append_methods(&entry, decl);
        MS_VEC_PUSH(*entries, Entry, entry);
    }
    ms_buf_free(&bounds);
    ms_buf_free(&form);
}

static void collect_impl(Desugar *d, MsBuf *entries, const TypeTable *types, MsDecl *decl) {
    if (decl->u.impl.contract != NULL) {
        push_plain_entry(entries, decl);
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
        collect_inherent(d, entries, decl, type, info);
    }
}

static MsBuf collect(Desugar *d, const TypeTable *types, MsBuf *expanded) {
    MsBuf entries = {0};
    for (size_t i = 0; i < MS_VEC_LEN(*expanded, MsDecl *); i++) {
        MsDecl *decl = MS_VEC_AT(*expanded, MsDecl *, i);
        if (decl->kind == MS_D_IMPL) {
            collect_impl(d, &entries, types, decl);
            continue;
        }
        push_plain_entry(&entries, decl);
        MsBuf markers = marker_impls(d, decl);
        for (size_t k = 0; k < MS_VEC_LEN(markers, MsDecl *); k++) {
            push_plain_entry(&entries, MS_VEC_AT(markers, MsDecl *, k));
        }
        ms_buf_free(&markers);
    }
    return entries;
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

static bool declares_method(const Entry *entry, MsSym name) {
    for (size_t i = 0; i < MS_VEC_LEN(entry->methods, MsMethod *); i++) {
        if (MS_VEC_AT(entry->methods, MsMethod *, i)->func.name == name) {
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
static void report_overlaps(Desugar *d, MsBuf *entries, const TypeTable *types) {
    size_t count = MS_VEC_LEN(*entries, Entry);
    for (size_t x = 0; x < count; x++) {
        const Entry *a = entry_at(entries, x);
        if (!a->inherent) {
            continue;
        }
        const TypeInfo *info = type_table_find(types, a->type);
        for (size_t y = x + 1; y < count; y++) {
            const Entry *b = entry_at(entries, y);
            if (!b->inherent || b->type != a->type || !str_equal(a->bounds, b->bounds)) {
                continue;
            }
            if (!forms_overlap(d, a->decl->u.impl.receiver, b->decl->u.impl.receiver, info->params)) {
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

/* ---- step 4: the synthesized interfaces ---- */

typedef struct Counter {
    MsSym type;
    uint32_t used;
} Counter;

/* The name of the interface for an impl: `Type$methods` for the plain form, `Type$N$methods` for
 * the Nth other form of that type. */
static MsSym contract_name(Desugar *d, const Entry *entry, MsBuf *counters) {
    MsBuf name = {0};
    put_str(&name, sym_str(d, entry->type));
    if (!entry->plain) {
        Counter *counter = NULL;
        for (size_t i = 0; i < MS_VEC_LEN(*counters, Counter) && counter == NULL; i++) {
            counter = MS_VEC_AT(*counters, Counter, i).type == entry->type ? &MS_VEC_AT(*counters, Counter, i) : NULL;
        }
        if (counter == NULL) {
            MS_VEC_PUSH(*counters, Counter, ((Counter){entry->type, 0}));
            counter = &MS_VEC_LAST(*counters, Counter);
        }
        counter->used++;
        ms_buf_printf(&name, "$%u", counter->used);
    }
    ms_buf_puts(&name, MS_INHERENT_SUFFIX);
    MsSym sym = ms_intern(d->names, name.data, name.len);
    ms_buf_free(&name);
    return sym;
}

static const MsTypeParam *written_bounds(const MsDecl *impl, MsSym name) {
    for (uint32_t i = 0; i < impl->u.impl.bounds.len; i++) {
        if (impl->u.impl.bounds.ptr[i]->name == name) {
            return impl->u.impl.bounds.ptr[i];
        }
    }
    return NULL;
}

/* `param` as the interface declares it: a bound that names a specialized parameter reads as that
 * argument, and the bounds the impl wrote for it are added. */
static MsTypeParam *interface_param(Desugar *d, const MsTypeParam *param, const MsDecl *impl,
                                    const Binding *dropped, uint32_t ndropped) {
    MsTypeParam *copy = MS_NEW(d->arena, MsTypeParam);
    *copy = *param;
    const MsTypeParam *written = written_bounds(impl, param->name);
    uint32_t extra = written == NULL ? 0 : written->bounds.len;
    copy->bounds.len = param->bounds.len + extra;
    copy->bounds.ptr = MS_NEW_N(d->arena, MsTypeRef *, copy->bounds.len);
    for (uint32_t i = 0; i < param->bounds.len; i++) {
        copy->bounds.ptr[i] = substitute_parameters(d, param->bounds.ptr[i], dropped, ndropped);
    }
    for (uint32_t i = 0; i < extra; i++) {
        copy->bounds.ptr[param->bounds.len + i] = written->bounds.ptr[i];
    }
    return copy;
}

/* The parameters the interface takes, and the receiver arguments they stand for. */
typedef struct InterfaceShape {
    MsBuf params; /* MsTypeParam * */
    MsBuf args;   /* MsTypeRef * */
} InterfaceShape;

/* The receiver arguments that are not their own parameter: a specialized argument stays in the
 * receiver, and a bound that names it reads as that argument. */
static MsBuf dropped_bindings(const Entry *entry, MsTypeParams params) {
    MsBuf dropped = {0};
    MsTypeRefs args = named_args(entry->decl->u.impl.receiver);
    for (uint32_t i = 0; i < params.len && i < args.len; i++) {
        if (!is_variable(args.ptr[i], params.ptr[i])) {
            MS_VEC_PUSH(dropped, Binding, ((Binding){params.ptr[i]->name, args.ptr[i]}));
        }
    }
    return dropped;
}

/* A type parameter written inside a larger argument (`Box[fn(Int) T]`) is still a variable of the
 * receiver form; it carries only the bounds written for it. */
static void add_nested_parameters(Desugar *d, InterfaceShape *shape, const Entry *entry, MsTypeParams params) {
    const MsDecl *impl = entry->decl;
    MsTypeRefs args = named_args(impl->u.impl.receiver);
    for (uint32_t i = 0; i < params.len; i++) {
        bool direct = false;
        bool nested = false;
        for (size_t k = 0; k < MS_VEC_LEN(shape->params, MsTypeParam *); k++) {
            direct = direct || MS_VEC_AT(shape->params, MsTypeParam *, k)->name == params.ptr[i]->name;
        }
        MsTypeParams only = {&params.ptr[i], 1};
        for (uint32_t k = 0; k < args.len; k++) {
            nested = nested || mentions_parameter(args.ptr[k], only);
        }
        if (direct || !nested) {
            continue;
        }
        MsTypeParam *param = MS_NEW(d->arena, MsTypeParam);
        *param = *params.ptr[i];
        const MsTypeParam *written = written_bounds(impl, param->name);
        param->bounds = written == NULL ? (MsTypeRefs){NULL, 0} : written->bounds;
        MS_VEC_PUSH(shape->params, MsTypeParam *, param);
        MS_VEC_PUSH(shape->args, MsTypeRef *, new_named_type(d, d->next_id, impl->pos, param->name, (MsTypeRefs){NULL, 0}));
        d->next_id++;
    }
}

static InterfaceShape interface_shape(Desugar *d, const Entry *entry, MsTypeParams params) {
    InterfaceShape shape = {{0}, {0}};
    MsBuf dropped = dropped_bindings(entry, params);
    const Binding *bindings = ms_buf_items(&dropped);
    uint32_t ndropped = (uint32_t)MS_VEC_LEN(dropped, Binding);
    MsTypeRefs args = named_args(entry->decl->u.impl.receiver);
    for (uint32_t i = 0; i < params.len && i < args.len; i++) {
        if (entry->plain || is_variable(args.ptr[i], params.ptr[i])) {
            MS_VEC_PUSH(shape.params, MsTypeParam *, interface_param(d, params.ptr[i], entry->decl, bindings, ndropped));
            MS_VEC_PUSH(shape.args, MsTypeRef *, args.ptr[i]);
        }
    }
    ms_buf_free(&dropped);
    if (!entry->plain) {
        add_nested_parameters(d, &shape, entry, params);
    }
    return shape;
}

/* A method's signature: the same declaration without a body or parameter defaults. */
static MsMethod *signature_of(Desugar *d, const MsMethod *method) {
    MsMethod *signature = MS_NEW(d->arena, MsMethod);
    *signature = *method;
    signature->func.body = (MsStmts){NULL, 0};
    signature->func.params.ptr = MS_NEW_N(d->arena, MsParam *, method->func.params.len);
    for (uint32_t i = 0; i < method->func.params.len; i++) {
        MsParam *param = MS_NEW(d->arena, MsParam);
        *param = *method->func.params.ptr[i];
        param->def = NULL;
        signature->func.params.ptr[i] = param;
    }
    return signature;
}

/* Appends the interface for `entry` and the impl, now naming it as its contract. */
static void emit_inherent(Desugar *d, MsBuf *out, Entry *entry, const TypeTable *types, MsBuf *counters) {
    MsDecl *impl = entry->decl;
    const TypeInfo *info = type_table_find(types, entry->type);
    InterfaceShape shape = interface_shape(d, entry, info->params);
    MsSym name = contract_name(d, entry, counters);
    MsDecl *interface = MS_NEW(d->arena, MsDecl);
    *interface = (MsDecl){.id = d->next_id, .pos = impl->pos, .synthetic = true, .kind = MS_D_INTERFACE};
    interface->u.iface.name = name;
    interface->u.iface.type_params.len = (uint32_t)MS_VEC_LEN(shape.params, MsTypeParam *);
    interface->u.iface.type_params.ptr = take_items(d->arena, &shape.params, _Alignof(MsTypeParam *));
    interface->u.iface.methods.len = (uint32_t)MS_VEC_LEN(entry->methods, MsMethod *);
    interface->u.iface.methods.ptr = MS_NEW_N(d->arena, MsMethod *, interface->u.iface.methods.len);
    for (uint32_t i = 0; i < interface->u.iface.methods.len; i++) {
        interface->u.iface.methods.ptr[i] = signature_of(d, MS_VEC_AT(entry->methods, MsMethod *, i));
    }
    MsTypeRefs args = {NULL, (uint32_t)MS_VEC_LEN(shape.args, MsTypeRef *)};
    args.ptr = take_items(d->arena, &shape.args, _Alignof(MsTypeRef *));
    impl->u.impl.contract = new_named_type(d, d->next_id + 1, impl->pos, name, args);
    d->next_id += 2;
    impl->u.impl.methods.len = interface->u.iface.methods.len;
    impl->u.impl.methods.ptr = take_items(d->arena, &entry->methods, _Alignof(MsMethod *));
    impl->synthetic = true;
    MS_VEC_PUSH(*out, MsDecl *, interface);
    MS_VEC_PUSH(*out, MsDecl *, impl);
}

static void emit_declarations(Desugar *d, MsBuf *entries, const TypeTable *types, MsDesugared *result) {
    MsBuf out = {0};
    MsBuf counters = {0};
    for (size_t i = 0; i < MS_VEC_LEN(*entries, Entry); i++) {
        Entry *entry = entry_at(entries, i);
        if (entry->inherent) {
            emit_inherent(d, &out, entry, types, &counters);
        } else {
            MS_VEC_PUSH(out, MsDecl *, entry->decl);
        }
    }
    ms_buf_free(&counters);
    result->ndecls = (uint32_t)MS_VEC_LEN(out, MsDecl *);
    result->decls = take_items(d->arena, &out, _Alignof(MsDecl *));
}

void ms_desugar_inherent_impls(MsArena *arena, MsNames *names, const MsDesugarInput *in, MsDesugared *out) {
    Desugar d = {.arena = arena, .names = names, .next_id = in->module->node_count, .source = in->source};
    d.is_std = ms_text_starts_with(in->file, "@std/");
    TypeTable types = build_type_table(&d, in);
    MsBuf expanded = expand_set_receivers(&d, in->module);
    MsBuf entries = collect(&d, &types, &expanded);
    ms_buf_free(&expanded);
    report_overlaps(&d, &entries, &types);
    emit_declarations(&d, &entries, &types, out);
    for (size_t i = 0; i < MS_VEC_LEN(entries, Entry); i++) {
        ms_buf_free(&entry_at(&entries, i)->methods);
    }
    ms_buf_free(&entries);
    type_table_free(&types);
    out->nerrors = (uint32_t)MS_VEC_LEN(d.errors, MsInherentError);
    out->errors = take_items(arena, &d.errors, _Alignof(MsInherentError));
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
