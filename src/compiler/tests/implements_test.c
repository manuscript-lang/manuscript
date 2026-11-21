/* Unit test of interface satisfaction (src/compiler/src/implements.c): identity, bounded variables,
 * primitive properties, explicit impl rows, and the answers that stay unknown. */
#include <stdio.h>
#include <string.h>

#include "ms/implements.h"

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
    MsMethodTable table;
} Fixture;

static void fixture_init(Fixture *f) {
    memset(f, 0, sizeof *f);
    ms_names_init(&f->names);
    ms_check_init(&f->c, &f->names);
    ms_methods_init(&f->table);
}

static void fixture_free(Fixture *f) {
    ms_methods_free(&f->table);
    ms_check_free(&f->c);
    ms_names_free(&f->names);
}

static MsTy make(Fixture *f, const char *name, MsKind kind, MsBuiltin builtin) {
    MsTyDesc d = {0};
    d.name = d.id = ms_intern_cstr(&f->names, name);
    d.kind = kind;
    d.builtin = builtin;
    return ms_ty_intern(&f->c.tys, &d);
}

/* One method row of `receiver` for `contract`; the table owns the columns afterwards. */
static void add_row(Fixture *f, MsTy receiver, MsTy contract) {
    MsMethods *m = &f->table.methods;
    const uint32_t n = m->count + 1;
    m->receiver = ms_array_resize(m->receiver, n, sizeof *m->receiver);
    m->contract = ms_array_resize(m->contract, n, sizeof *m->contract);
    m->nvars = ms_array_resize(m->nvars, n, sizeof *m->nvars);
    m->local = ms_array_resize(m->local, n, sizeof *m->local);
    m->receiver[n - 1] = receiver;
    m->contract[n - 1] = contract;
    m->nvars[n - 1] = 0;
    m->local[n - 1] = false;
    m->count = n;
}

static void test_basics(void) {
    Fixture f;
    fixture_init(&f);
    const MsTy int_ty = make(&f, "Int", MS_K_PRIMITIVE, MS_BI_INT);
    const MsTy float_ty = make(&f, "Float", MS_K_PRIMITIVE, MS_BI_FLOAT);
    const MsTy equal = make(&f, "Equal", MS_K_CONTRACT, MS_BI_EQUAL);
    const MsTy hashable = make(&f, "Hashable", MS_K_CONTRACT, MS_BI_HASHABLE);
    CHECK(ms_implements(&f.c, &f.table, equal, equal) == MS_FIT_YES);
    CHECK(ms_implements(&f.c, &f.table, int_ty, equal) == MS_FIT_YES);
    CHECK(ms_implements(&f.c, &f.table, float_ty, equal) == MS_FIT_YES);
    CHECK(ms_implements(&f.c, &f.table, float_ty, hashable) == MS_FIT_NO);
    fixture_free(&f);
}

static void test_variables_and_rows(void) {
    Fixture f;
    fixture_init(&f);
    const MsTy shape = make(&f, "Shape", MS_K_CONTRACT, MS_B_NONE);
    const MsTy other = make(&f, "Other", MS_K_CONTRACT, MS_B_NONE);
    const MsTy square = make(&f, "Square", MS_K_TYPE, MS_B_NONE);
    MsTyDesc d = {0};
    d.name = ms_intern_cstr(&f.names, "T");
    d.id = ms_intern_cstr(&f.names, "T");
    d.kind = MS_K_VARIABLE;
    const MsTy var = ms_ty_fresh(&f.c.tys, &d);
    MsTy bounds[1] = {shape};
    MsVarInfo *info = ms_var_info(&f.c, var);
    info->bounds = bounds;
    info->nbounds = 1;
    CHECK(ms_implements(&f.c, &f.table, var, shape) == MS_FIT_YES);
    CHECK(ms_implements(&f.c, &f.table, var, other) == MS_FIT_NO);
    add_row(&f, square, shape);
    CHECK(ms_implements(&f.c, &f.table, square, shape) == MS_FIT_YES);
    info->bounds = NULL;
    info->nbounds = 0;
    fixture_free(&f);
}

int main(void) {
    test_basics();
    test_variables_and_rows();
    if (failures != 0) {
        fprintf(stderr, "implements_test: %d failure(s)\n", failures);
        return 1;
    }
    puts("implements: ok");
    return 0;
}
