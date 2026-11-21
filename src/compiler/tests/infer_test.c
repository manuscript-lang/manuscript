/* Unit test of the type argument inference (src/compiler/src/check/infer.c): binding from argument types,
 * conflicts, explicit arguments, defaults, and the shared-node walk. */
#include <stdio.h>
#include <string.h>

#include "ms/infer.h"

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

static MsTy named(Fixture *f, const char *name, const MsTy *args, uint32_t nargs) {
    MsTyDesc d = {0};
    d.name = d.id = ms_intern_cstr(&f->names, name);
    d.kind = MS_K_TYPE;
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
    return named(f, "List", &element, 1);
}

static MsTy pair(Fixture *f, MsTy a, MsTy b) {
    const MsTy args[2] = {a, b};
    return named(f, "Pair", args, 2);
}

static MsTy function(Fixture *f, uint8_t flags, MsTy param, MsTy result) {
    const MsTyParam p = {0, param, flags};
    MsTyDesc d = {0};
    d.name = d.id = ms_intern_cstr(&f->names, "fn");
    d.kind = MS_K_FUNCTION;
    d.params = &p;
    d.nparams = 1;
    d.result = result;
    return ms_ty_intern(&f->c.tys, &d);
}

static void test_binding_and_conflict(void) {
    Fixture f;
    fixture_init(&f);
    const MsTy int_ty = named(&f, "Int", NULL, 0);
    const MsTy string = named(&f, "String", NULL, 0);
    const MsTy vars[2] = {variable(&f, "T"), variable(&f, "U")};
    MsInfer in;
    ms_infer_init(&in, &f.c, &f.arena, vars, 2);
    CHECK(ms_infer_match(&in, list_of(&f, vars[0]), list_of(&f, int_ty)) == MS_MATCH_OK);
    CHECK(in.bound[0] == int_ty && in.bound[1] == MS_TY_NONE);
    CHECK(ms_infer_match(&in, vars[0], int_ty) == MS_MATCH_OK);
    CHECK(ms_infer_match(&in, vars[0], string) == MS_MATCH_CONFLICT);
    CHECK(ms_infer_match(&in, list_of(&f, int_ty), string) == MS_MATCH_SHAPE);
    CHECK(ms_infer_match(&in, pair(&f, vars[0], vars[1]), pair(&f, int_ty, string)) == MS_MATCH_OK);
    CHECK(in.bound[1] == string);
    CHECK(ms_infer_apply(&in, list_of(&f, vars[1])) == list_of(&f, string));
    fixture_free(&f);
}

static void test_functions(void) {
    Fixture f;
    fixture_init(&f);
    const MsTy int_ty = named(&f, "Int", NULL, 0);
    const MsTy string = named(&f, "String", NULL, 0);
    const MsTy vars[2] = {variable(&f, "T"), variable(&f, "U")};
    MsInfer in;
    ms_infer_init(&in, &f.c, &f.arena, vars, 2);
    CHECK(ms_infer_match(&in, function(&f, 0, vars[0], vars[1]), function(&f, 0, int_ty, string)) == MS_MATCH_OK);
    CHECK(in.bound[0] == int_ty && in.bound[1] == string);
    MsInfer other;
    ms_infer_init(&other, &f.c, &f.arena, vars, 2);
    CHECK(ms_infer_match(&other, function(&f, 0, vars[0], vars[1]), function(&f, MS_PARAM_VAR, int_ty, string)) ==
          MS_MATCH_SHAPE);
    fixture_free(&f);
}

static void test_explicit_and_defaults(void) {
    Fixture f;
    fixture_init(&f);
    const MsTy int_ty = named(&f, "Int", NULL, 0);
    const MsTy string = named(&f, "String", NULL, 0);
    const MsTy vars[3] = {variable(&f, "A"), variable(&f, "B"), variable(&f, "C")};
    ms_var_info(&f.c, vars[1])->def = list_of(&f, vars[0]); /* B = List[A] */
    MsInfer in;
    uint32_t first = 0;
    ms_infer_init(&in, &f.c, &f.arena, vars, 3);
    const MsTy given[1] = {int_ty};
    CHECK(ms_infer_give(&in, given, 1));
    CHECK(ms_infer_defaults(&in, &first) == 1 && first == 2); /* C has no default */
    CHECK(in.bound[1] == list_of(&f, int_ty));
    CHECK(ms_infer_match(&in, vars[2], string) == MS_MATCH_OK);
    const MsTy too_many[4] = {int_ty, int_ty, int_ty, int_ty};
    CHECK(!ms_infer_give(&in, too_many, 4));
    fixture_free(&f);
}

static void test_shared_nodes(void) {
    Fixture f;
    fixture_init(&f);
    const MsTy int_ty = named(&f, "Int", NULL, 0);
    const MsTy var = variable(&f, "T");
    MsInfer in;
    ms_infer_init(&in, &f.c, &f.arena, &var, 1);
    /* Pair[T, T] nested 60 times has 2^60 paths and 60 nodes. */
    MsTy deep = var;
    MsTy plain = int_ty;
    for (int i = 0; i < 60; i++) {
        deep = pair(&f, deep, deep);
        plain = pair(&f, plain, plain);
    }
    CHECK(ms_infer_match(&in, deep, plain) == MS_MATCH_OK);
    CHECK(in.bound[0] == int_ty);
    fixture_free(&f);
}

int main(void) {
    test_binding_and_conflict();
    test_functions();
    test_explicit_and_defaults();
    test_shared_nodes();
    if (failures != 0) {
        fprintf(stderr, "infer_test: %d failure(s)\n", failures);
        return 1;
    }
    puts("infer: ok");
    return 0;
}
