/* Unit test of the type table: interning identity and the display forms the Rust checker prints. */
#include <stdio.h>
#include <string.h>

#include "ms/types.h"

static int failures;

#define CHECK(cond)                                                                                \
    do {                                                                                           \
        if (!(cond)) {                                                                             \
            fprintf(stderr, "%s:%d: check failed: %s\n", __FILE__, __LINE__, #cond);              \
            failures++;                                                                            \
        }                                                                                          \
    } while (0)

static MsTy prim(MsTyTable *t, MsNames *n, const char *name) {
    MsSym s = ms_intern_cstr(n, name);
    MsTyDesc d = {0};
    d.name = d.id = s;
    d.kind = MS_K_PRIMITIVE;
    d.builtin = ms_builtin_primitive((MsStr){name, (uint32_t)strlen(name)});
    return ms_ty_intern(t, &d);
}

static MsTy applied(MsTyTable *t, MsNames *n, const char *name, const char *id, MsBuiltin b, const MsTy *args, uint32_t nargs) {
    MsTyDesc d = {0};
    d.name = ms_intern_cstr(n, name);
    d.id = ms_intern_cstr(n, id);
    d.kind = MS_K_TYPE;
    d.builtin = b;
    d.args = args;
    d.nargs = nargs;
    return ms_ty_intern(t, &d);
}

static bool shows(MsTyTable *t, MsNames *n, MsTy ty, const char *want) {
    MsBuf b = {0};
    ms_ty_show(&b, n, t, ty);
    bool ok = b.len == strlen(want) && memcmp(b.data, want, b.len) == 0;
    if (!ok) {
        fprintf(stderr, "shows %.*s, wanted %s\n", (int)b.len, b.data, want);
    }
    ms_buf_free(&b);
    return ok;
}

int main(void) {
    MsNames names;
    ms_names_init(&names);
    MsTyTable t;
    ms_tys_init(&t);

    MsTy i = prim(&t, &names, "Int"), s = prim(&t, &names, "String"), v = prim(&t, &names, "Void");
    CHECK(i != MS_TY_NONE && i == prim(&t, &names, "Int") && i != s);
    CHECK(ms_ty_is(&t, i, MS_BI_INT) && ms_ty_is(&t, s, MS_BI_STRING));
    CHECK(ms_builtin_is_int(MS_BI_UINT8) && !ms_builtin_is_int(MS_BI_FLOAT) && ms_builtin_is_float(MS_BI_FLOAT32));
    CHECK(ms_builtin_from_id((MsStr){"@std/Result", 11}) == MS_BI_RESULT);
    CHECK(ms_builtin_from_id((MsStr){"@std/Nope", 9}) == MS_B_NONE);

    MsTy list_int = applied(&t, &names, "List", "@std/List", MS_BI_LIST, &i, 1);
    CHECK(list_int == applied(&t, &names, "List", "@std/List", MS_BI_LIST, &i, 1));
    CHECK(list_int != applied(&t, &names, "List", "@std/List", MS_BI_LIST, &s, 1));
    CHECK(shows(&t, &names, list_int, "List[Int]"));

    MsTy opt_int = applied(&t, &names, "Optional", "@std/Optional", MS_BI_OPTIONAL, &i, 1);
    CHECK(shows(&t, &names, opt_int, "Int?"));

    MsTyParam ps[2] = {{ms_intern_cstr(&names, "a"), i, MS_PARAM_VAR}, {ms_intern_cstr(&names, "b"), s, MS_PARAM_MOVE}};
    MsTyDesc fd = {0};
    fd.name = fd.id = ms_intern_cstr(&names, "fn");
    fd.kind = MS_K_FUNCTION;
    fd.params = ps;
    fd.nparams = 2;
    fd.result = v;
    MsTy fn = ms_ty_intern(&t, &fd);
    CHECK(fn == ms_ty_intern(&t, &fd));
    CHECK(shows(&t, &names, fn, "fn(var Int, move String) Void"));
    ps[0].flags = 0;
    CHECK(ms_ty_intern(&t, &fd) != fn);
    CHECK(shows(&t, &names, applied(&t, &names, "Optional", "@std/Optional", MS_BI_OPTIONAL, &fn, 1), "(fn(var Int, move String) Void)?"));

    /* Variables are never shared, even with equal descriptions. */
    MsTyDesc vd = {0};
    vd.name = ms_intern_cstr(&names, "T");
    vd.id = ms_intern_cstr(&names, "x/T");
    vd.kind = MS_K_VARIABLE;
    MsTy v1 = ms_ty_fresh(&t, &vd), v2 = ms_ty_fresh(&t, &vd);
    CHECK(v1 != v2 && shows(&t, &names, v1, "T"));

    /* Many rows survive growth and rehash, and lookups still find the first copy. */
    MsTy first = list_int;
    for (int k = 0; k < 5000; k++) {
        char name[16];
        snprintf(name, sizeof name, "T%d", k);
        MsTy p = prim(&t, &names, name);
        MsTy l = applied(&t, &names, "List", "@std/List", MS_BI_LIST, &p, 1);
        CHECK(l == applied(&t, &names, "List", "@std/List", MS_BI_LIST, &p, 1));
    }
    CHECK(first == applied(&t, &names, "List", "@std/List", MS_BI_LIST, &i, 1));

    /* A deep type prints at most 64 nodes, then an ellipsis. */
    MsTy deep = i;
    for (int k = 0; k < 100; k++) {
        deep = applied(&t, &names, "List", "@std/List", MS_BI_LIST, &deep, 1);
    }
    MsBuf b = {0};
    ms_ty_show(&b, &names, &t, deep);
    ms_buf_putc(&b, 0);
    /* 64 `List[` nodes, the ellipsis, 64 closers */
    CHECK(strlen(b.data) == 64 * 5 + 3 + 64 && strstr(b.data, "[\xe2\x80\xa6]") != NULL);
    ms_buf_free(&b);

    ms_tys_free(&t);
    ms_names_free(&names);
    if (failures == 0) {
        puts("types: ok");
    }
    return failures != 0;
}
