/* Unit test of the ownership pass's data: places, overlap and display. */
#include <stdio.h>
#include <string.h>

#include "ms/ownership.h"

static int failures;

#define CHECK(cond)                                                                                \
    do {                                                                                           \
        if (!(cond)) {                                                                             \
            fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, #cond);              \
            failures++;                                                                            \
        }                                                                                          \
    } while (0)

static MsStep field(MsNames *n, const char *name) {
    MsStep s = {MS_STEP_FIELD, ms_intern_cstr(n, name), 0};
    return s;
}

static MsStep index_step(uint64_t i) {
    MsStep s = {MS_STEP_INDEX, 0, i};
    return s;
}

static MsStep element(void) {
    MsStep s = {MS_STEP_ELEMENT, 0, 0};
    return s;
}

static bool shows(MsNames *n, MsPlace p, const char *want) {
    MsBuf b = {0};
    ms_place_show(&b, n, p, ms_intern_cstr(n, "b"));
    bool ok = b.len == strlen(want) && memcmp(b.data, want, b.len) == 0;
    ms_buf_free(&b);
    return ok;
}


/* ---- value classes ---- */

typedef struct ClassWorld {
    MsNames names;
    MsCheck check;
    MsClassifier *classifier;
    MsTy int_ty, string_ty, closeable_ty;
} ClassWorld;

static MsTy world_type(ClassWorld *w, const char *name, MsKind kind, MsBuiltin builtin, const MsTy *args, uint32_t nargs) {
    MsTyDesc d = {0};
    d.name = d.id = ms_intern_cstr(&w->names, name);
    d.kind = kind;
    d.builtin = builtin;
    d.args = args;
    d.nargs = nargs;
    return ms_ty_intern(&w->check.tys, &d);
}

static void world_init(ClassWorld *w) {
    ms_names_init(&w->names);
    ms_check_init(&w->check, &w->names);
    w->classifier = ms_classifier_new(&w->check);
    w->int_ty = world_type(w, "Int", MS_K_PRIMITIVE, MS_BI_INT, NULL, 0);
    w->string_ty = world_type(w, "String", MS_K_PRIMITIVE, MS_BI_STRING, NULL, 0);
    w->closeable_ty = world_type(w, "Closeable", MS_K_CONTRACT, MS_BI_CLOSEABLE, NULL, 0);
}

static void world_free(ClassWorld *w) {
    ms_classifier_free(w->classifier);
    ms_check_free(&w->check);
    ms_names_free(&w->names);
}

/* A nominal declaration with the given variables; fields and cases are filled by the caller. */
static MsTy declare_nominal(ClassWorld *w, const char *name, MsKind kind, MsTy *vars, uint32_t nvars) {
    MsSymSpec spec = {0};
    spec.name = spec.id = ms_intern_cstr(&w->names, name);
    spec.kind = MS_SYM_TYPE;
    const MsSymId sym = ms_sym_new(&w->check, MS_NONE, &spec);
    ms_def(&w->check, sym)->vars = vars;
    ms_def(&w->check, sym)->nvars = nvars;
    MsTyDesc d = {0};
    d.name = d.id = spec.id;
    d.kind = kind;
    d.def = sym + 1;
    d.args = vars;
    d.nargs = nvars;
    return ms_ty_intern(&w->check.tys, &d);
}

static MsDef *definition_of(ClassWorld *w, MsTy type) {
    return ms_def(&w->check, w->check.tys.def[type] - 1);
}


static void set_fields(ClassWorld *w, MsTy owner, const MsTy *types, uint32_t count) {
    MsTyParam *fields = MS_NEW_N(&w->check.arena, MsTyParam, count);
    for (uint32_t i = 0; i < count; i++) {
        fields[i] = (MsTyParam){ms_intern_cstr(&w->names, "f"), types[i], 0};
    }
    definition_of(w, owner)->fields = fields;
    definition_of(w, owner)->nfields = count;
}

static MsTy fresh_variable(ClassWorld *w, const char *name) {
    MsTyDesc d = {0};
    d.name = d.id = ms_intern_cstr(&w->names, name);
    d.kind = MS_K_VARIABLE;
    return ms_ty_fresh(&w->check.tys, &d);
}

static void test_classes(void) {
    ClassWorld w;
    world_init(&w);
    MsClassifier *cl = w.classifier;
    CHECK(ms_classify(cl, w.int_ty) == MS_CLASS_COPY);
    CHECK(ms_classify(cl, w.string_ty) == MS_CLASS_MOVE);
    CHECK(ms_classify(cl, w.closeable_ty) == MS_CLASS_RESOURCE);

    /* a type moves whatever it holds; an alternative of scalars copies */
    MsTy point = declare_nominal(&w, "Point", MS_K_TYPE, NULL, 0);
    set_fields(&w, point, &w.int_ty, 1);
    CHECK(ms_classify(cl, point) == MS_CLASS_MOVE);
    MsTy color = declare_nominal(&w, "Color", MS_K_ALTERNATIVE, NULL, 0);
    CHECK(ms_classify(cl, color) == MS_CLASS_COPY);
    MsTy shape = declare_nominal(&w, "Shape", MS_K_ALTERNATIVE, NULL, 0);
    MsCaseRow cases[1] = {{ms_intern_cstr(&w.names, "named"), MS_NEW(&w.check.arena, MsTyParam), 1}};
    cases[0].fields[0] = (MsTyParam){ms_intern_cstr(&w.names, "text"), w.string_ty, 0};
    definition_of(&w, shape)->cases = cases;
    definition_of(&w, shape)->ncases = 1;
    CHECK(ms_classify(cl, shape) == MS_CLASS_MOVE);

    /* a generic holder takes the class of its argument */
    MsTy var = fresh_variable(&w, "T");
    MsTy *vars = MS_NEW(&w.check.arena, MsTy);
    *vars = var;
    MsTy holder = declare_nominal(&w, "Holder", MS_K_ALTERNATIVE, vars, 1);
    MsTyParam *slot = MS_NEW(&w.check.arena, MsTyParam);
    *slot = (MsTyParam){ms_intern_cstr(&w.names, "value"), var, 0};
    MsCaseRow holder_case = {ms_intern_cstr(&w.names, "some"), slot, 1};
    definition_of(&w, holder)->cases = &holder_case;
    definition_of(&w, holder)->ncases = 1;
    MsTyDesc d = {0};
    d.name = d.id = ms_intern_cstr(&w.names, "Holder");
    d.kind = MS_K_ALTERNATIVE;
    d.def = w.check.tys.def[holder];
    MsTy args_int[1] = {w.int_ty}, args_closeable[1] = {w.closeable_ty};
    d.args = args_int;
    d.nargs = 1;
    CHECK(ms_classify(cl, ms_ty_intern(&w.check.tys, &d)) == MS_CLASS_COPY);
    d.args = args_closeable;
    CHECK(ms_classify(cl, ms_ty_intern(&w.check.tys, &d)) == MS_CLASS_RESOURCE);
    CHECK(ms_classify(cl, var) == MS_CLASS_MOVE);

    /* a type marked closeable is a resource, and so is a list of it */
    MsTy door = declare_nominal(&w, "Door", MS_K_TYPE, NULL, 0);
    MsTy list_door = world_type(&w, "List", MS_K_NATIVE, MS_BI_LIST, &door, 1);
    CHECK(ms_classify(cl, door) == MS_CLASS_MOVE && ms_classify(cl, list_door) == MS_CLASS_MOVE);
    MsClassifier *marked = ms_classifier_new(&w.check);
    ms_classifier_mark_closeable(marked, w.check.tys.id[door]);
    CHECK(ms_classify(marked, door) == MS_CLASS_RESOURCE && ms_classify(marked, list_door) == MS_CLASS_RESOURCE);
    ms_classifier_free(marked);
    MsTy list_int = world_type(&w, "List", MS_K_NATIVE, MS_BI_LIST, &w.int_ty, 1);
    MsTy list_list = world_type(&w, "List", MS_K_NATIVE, MS_BI_LIST, &list_int, 1);
    CHECK(ms_classify(cl, list_int) == MS_CLASS_MOVE && ms_classify(cl, list_list) == MS_CLASS_MOVE);
    MsTy decimal = world_type(&w, "Decimal", MS_K_NATIVE, MS_BI_DECIMAL, NULL, 0);
    MsTy list_decimal = world_type(&w, "List", MS_K_NATIVE, MS_BI_LIST, &decimal, 1);
    CHECK(ms_classify(cl, decimal) == MS_CLASS_COPY && ms_classify(cl, list_decimal) == MS_CLASS_MOVE);
    world_free(&w);
}

/* A cycle moves. A type reached through the cycle must not keep a class that missed a resource the
 * cycle's start holds: Node is a resource through `door`, and Link reaches Node, so it is too,
 * whichever of the two is asked first. */
static void test_cycles(void) {
    ClassWorld w;
    world_init(&w);
    MsTy node = declare_nominal(&w, "Node", MS_K_TYPE, NULL, 0);
    MsTy link = declare_nominal(&w, "Link", MS_K_ALTERNATIVE, NULL, 0);
    MsTy door = declare_nominal(&w, "Door", MS_K_TYPE, NULL, 0);
    MsTy node_fields[2] = {link, door};
    set_fields(&w, node, node_fields, 2);
    set_fields(&w, link, &node, 1);
    ms_classifier_mark_closeable(w.classifier, w.check.tys.id[door]);
    CHECK(ms_classify(w.classifier, node) == MS_CLASS_RESOURCE);
    CHECK(ms_classify(w.classifier, link) == MS_CLASS_RESOURCE);

    MsTy again_link = declare_nominal(&w, "Chain", MS_K_ALTERNATIVE, NULL, 0);
    MsTy again_node = declare_nominal(&w, "Rope", MS_K_TYPE, NULL, 0);
    MsTy rope_fields[2] = {again_link, door};
    set_fields(&w, again_node, rope_fields, 2);
    set_fields(&w, again_link, &again_node, 1);
    CHECK(ms_classify(w.classifier, again_link) == MS_CLASS_RESOURCE);
    CHECK(ms_classify(w.classifier, again_node) == MS_CLASS_RESOURCE);

    MsTy loop = declare_nominal(&w, "Loop", MS_K_ALTERNATIVE, NULL, 0);
    set_fields(&w, loop, &loop, 1);
    CHECK(ms_classify(w.classifier, loop) == MS_CLASS_MOVE);
    world_free(&w);
}

int main(void) {
    MsNames names;
    MsArena arena = {0};
    ms_names_init(&names);

    MsPlace whole = ms_place_local(1);
    MsPlace items = ms_place_then(&arena, whole, field(&names, "items"));
    MsPlace count = ms_place_then(&arena, whole, field(&names, "count"));
    MsPlace first = ms_place_then(&arena, items, index_step(0));
    MsPlace second = ms_place_then(&arena, items, index_step(1));
    MsPlace any = ms_place_then(&arena, items, element());

    CHECK(whole.len == 0 && items.len == 1 && first.len == 2);
    CHECK(ms_place_overlaps(whole, items) && ms_place_overlaps(items, whole));
    CHECK(!ms_place_overlaps(items, count));
    CHECK(ms_place_overlaps(items, first) && ms_place_overlaps(first, first));
    CHECK(!ms_place_overlaps(first, second));
    CHECK(ms_place_overlaps(first, any) && ms_place_overlaps(any, second));
    CHECK(!ms_place_overlaps(items, ms_place_local(2)));
    CHECK(!ms_place_overlaps(ms_place_then(&arena, any, field(&names, "x")), ms_place_then(&arena, any, element())));

    MsStep more[2] = {field(&names, "a"), index_step(7)};
    MsPlace joined = ms_place_join(&arena, items, more, 2);
    CHECK(joined.len == 3 && items.len == 1);
    CHECK(shows(&names, whole, "b"));
    CHECK(shows(&names, joined, "b.items.a[7]"));
    CHECK(shows(&names, any, "b.items[..]"));

    MsBits a = ms_bits_new(&arena, 130);
    MsBits b = ms_bits_copy(&arena, a);
    ms_bits_add(a, 3);
    ms_bits_add(a, 129);
    ms_bits_add(b, 3);
    ms_bits_add(b, 64);
    CHECK(ms_bits_has(a, 129) && !ms_bits_has(a, 64) && !ms_bits_has(a, 500) && ms_bits_count(a) == 2);
    MsBits both = ms_bits_copy(&arena, a);
    ms_bits_meet(both, b);
    CHECK(ms_bits_count(both) == 1 && ms_bits_has(both, 3));
    ms_bits_union(both, b);
    CHECK(ms_bits_count(both) == 2 && ms_bits_has(both, 64));
    ms_bits_remove(both, 3);
    CHECK(!ms_bits_has(both, 3));
    ms_bits_clear(both);
    CHECK(ms_bits_count(both) == 0 && ms_bits_count(a) == 2);

    ms_arena_free(&arena);
    ms_names_free(&names);
    test_classes();
    test_cycles();
    if (failures == 0) {
        puts("ownership: ok");
    }
    return failures != 0;
}
