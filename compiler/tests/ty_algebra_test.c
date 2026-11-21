/* Unit test of the type algebra helpers (compiler/src/check/ty_algebra.c), with the expectations of
 * crates/ms-check/src/contracts.rs: shared-node walks, unification of implementations, type sets,
 * and the property tables. */
#include <stdio.h>
#include <string.h>

#include "ms/ty_algebra.h"

static int failures;

#define CHECK(cond)                                                                                \
    do {                                                                                           \
        if (!(cond)) {                                                                             \
            fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, #cond);              \
            failures++;                                                                            \
        }                                                                                          \
    } while (0)

typedef struct Fixture {
    MsNames names;
    MsNames *names_ptr;
    MsCheck c;
    MsArena arena;
} Fixture;

static void fixture_init(Fixture *f) {
    memset(f, 0, sizeof *f);
    ms_names_init(&f->names);
    ms_check_init(&f->c, &f->names);
}

static void fixture_free(Fixture *f) {
    ms_check_free(&f->c);
    ms_names_free(&f->names);
    ms_arena_free(&f->arena);
}

static MsTy named(Fixture *f, const char *name, MsBuiltin builtin, const MsTy *args, uint32_t nargs) {
    MsTyDesc d = {0};
    d.name = d.id = ms_intern_cstr(&f->names, name);
    d.kind = MS_K_TYPE;
    d.builtin = builtin;
    d.args = args;
    d.nargs = nargs;
    return ms_ty_intern(&f->c.tys, &d);
}

static MsTy variable(Fixture *f, const char *id) {
    MsTyDesc d = {0};
    d.name = ms_intern_cstr(&f->names, "T");
    d.id = ms_intern_cstr(&f->names, id);
    d.kind = MS_K_VARIABLE;
    return ms_ty_fresh(&f->c.tys, &d);
}

static MsTy list_of(Fixture *f, MsTy element) {
    return named(f, "List", MS_BI_LIST, &element, 1);
}

static MsTy pair(Fixture *f, MsTy a, MsTy b) {
    MsTy args[2] = {a, b};
    return named(f, "Pair", MS_B_NONE, args, 2);
}

static MsTy function(Fixture *f, const char *name, uint8_t flags, MsTy param, MsTy result) {
    MsTyParam p = {0, param, flags};
    MsTyDesc d = {0};
    d.name = d.id = ms_intern_cstr(&f->names, name);
    d.kind = MS_K_FUNCTION;
    d.params = &p;
    d.nparams = 1;
    d.result = result;
    return ms_ty_intern(&f->c.tys, &d);
}

static void test_has_variable(void) {
    Fixture f;
    fixture_init(&f);
    MsTy int_ty = named(&f, "Int", MS_BI_INT, NULL, 0);
    MsTy v = variable(&f, "T");
    CHECK(!ms_ty_has_variable(&f.c.tys, int_ty));
    CHECK(ms_ty_has_variable(&f.c.tys, v));
    CHECK(ms_ty_has_variable(&f.c.tys, list_of(&f, v)));
    CHECK(ms_ty_has_variable(&f.c.tys, function(&f, "fn1", 0, int_ty, list_of(&f, v))));
    CHECK(!ms_ty_has_variable(&f.c.tys, function(&f, "fn2", 0, int_ty, int_ty)));
    /* Pair[T, T] nested 60 times has 2^60 paths and 60 nodes. */
    MsTy deep = v;
    MsTy plain = int_ty;
    for (int i = 0; i < 60; i++) {
        deep = pair(&f, deep, deep);
        plain = pair(&f, plain, plain);
    }
    CHECK(ms_ty_has_variable(&f.c.tys, deep));
    CHECK(!ms_ty_has_variable(&f.c.tys, plain));
    fixture_free(&f);
}

static void test_overlap(void) {
    Fixture f;
    fixture_init(&f);
    MsTy int_ty = named(&f, "Int", MS_BI_INT, NULL, 0);
    MsTy string = named(&f, "String", MS_BI_STRING, NULL, 0);
    MsTy t = variable(&f, "T");
    MsTy u = variable(&f, "U");
    MsTy vars[2] = {t, u};
    /* List[T] and List[Int] unify; List[Int] and List[String] do not. */
    CHECK(ms_ty_overlap(&f.c.tys, &f.arena, list_of(&f, t), int_ty, list_of(&f, int_ty), int_ty, vars, 1));
    CHECK(!ms_ty_overlap(&f.c.tys, &f.arena, list_of(&f, int_ty), int_ty, list_of(&f, string), int_ty, vars, 1));
    /* The same variable must take one type in both positions. */
    CHECK(!ms_ty_overlap(&f.c.tys, &f.arena, t, t, int_ty, string, vars, 1));
    CHECK(ms_ty_overlap(&f.c.tys, &f.arena, t, u, int_ty, string, vars, 2));
    /* A variable does not unify with a type that contains it. */
    CHECK(!ms_ty_overlap(&f.c.tys, &f.arena, t, int_ty, list_of(&f, t), int_ty, vars, 1));
    /* A name that is not in `vars` is an ordinary type: it matches only itself. */
    CHECK(!ms_ty_overlap(&f.c.tys, &f.arena, t, int_ty, int_ty, int_ty, vars, 0));
    /* Functions agree on parameter mutability, parameter and result types. */
    MsTy by_value = function(&f, "fn", 0, t, int_ty);
    MsTy by_var = function(&f, "fn", MS_PARAM_VAR, t, int_ty);
    MsTy concrete = function(&f, "fn", 0, string, int_ty);
    CHECK(ms_ty_overlap(&f.c.tys, &f.arena, by_value, int_ty, concrete, int_ty, vars, 1));
    CHECK(!ms_ty_overlap(&f.c.tys, &f.arena, by_var, int_ty, concrete, int_ty, vars, 1));
    fixture_free(&f);
}

static void test_type_sets(void) {
    Fixture f;
    fixture_init(&f);
    MsTy int_ty = named(&f, "Int", MS_BI_INT, NULL, 0);
    MsTy string = named(&f, "String", MS_BI_STRING, NULL, 0);
    MsTy bool_ty = named(&f, "Bool", MS_BI_BOOL, NULL, 0);
    MsTy wide_members[2] = {int_ty, string};
    MsTy narrow_members[1] = {int_ty};
    MsTy wide = named(&f, "TypeSet", MS_BI_TYPESET, wide_members, 2);
    MsTy narrow = named(&f, "TypeSet", MS_BI_TYPESET, narrow_members, 1);
    CHECK(ms_type_set_admits(&f.c, int_ty, wide));
    CHECK(!ms_type_set_admits(&f.c, bool_ty, wide));
    /* A variable bounded by a set is admitted where all of that set's members are. */
    MsTy v = variable(&f, "V");
    MsVarInfo *info = ms_var_info(&f.c, v);
    info->bounds = ms_array_resize(NULL, 1, sizeof *info->bounds);
    info->bounds[0] = narrow;
    info->nbounds = 1;
    CHECK(ms_type_set_admits(&f.c, v, wide));
    CHECK(!ms_type_set_admits(&f.c, variable(&f, "W"), wide));
    MsTy other = named(&f, "TypeSet", MS_BI_TYPESET, &bool_ty, 1);
    CHECK(!ms_type_set_admits(&f.c, v, other));
    fixture_free(&f);
}

static void test_tables(void) {
    CHECK(ms_builtin_comparable(MS_BI_INT));
    CHECK(ms_builtin_comparable(MS_BI_UINT8));
    CHECK(ms_builtin_comparable(MS_BI_FLOAT32));
    CHECK(ms_builtin_comparable(MS_BI_STRING));
    CHECK(ms_builtin_comparable(MS_BI_TIMESTAMP));
    CHECK(!ms_builtin_comparable(MS_BI_BOOL));
    CHECK(!ms_builtin_comparable(MS_BI_LIST));
    CHECK(!ms_builtin_comparable(MS_B_NONE));
    for (int p = MS_PROP_EQUAL; p <= MS_PROP_DATA; p++) {
        MsProperty back;
        CHECK(ms_property_of(ms_property_builtin((MsProperty)p), &back) && back == (MsProperty)p);
    }
    MsProperty ignored;
    CHECK(!ms_property_of(MS_BI_COMPARABLE, &ignored));
    CHECK(strcmp(ms_property_name(MS_PROP_HASHABLE), "Hashable") == 0);
}

int main(void) {
    test_has_variable();
    test_overlap();
    test_type_sets();
    test_tables();
    if (failures != 0) {
        fprintf(stderr, "%d check(s) failed\n", failures);
        return 1;
    }
    puts("ty_algebra: ok");
    return 0;
}
