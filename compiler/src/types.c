/* The type table: interning, display and the built-in tag lookups. */
#include <stdlib.h>
#include <string.h>

#include "ms/types.h"

const char *ms_kind_str(MsKind k) {
    static const char *const names[] = {"primitive", "invalid",     "inferred", "variable", "type",
                                         "alternative", "contract", "function", "native"};
    return names[k];
}

/* ---- built-in tags ---- */

static bool ty_str_is(MsStr s, const char *lit) {
    size_t n = strlen(lit);
    return s.len == n && memcmp(s.ptr, lit, n) == 0;
}

typedef struct {
    const char *name;
    MsBuiltin b;
} NameTag;

static const NameTag PRIMITIVES[] = {
    {"Int", MS_BI_INT},       {"Int8", MS_BI_INT8},     {"Int16", MS_BI_INT16},
    {"Int32", MS_BI_INT32},   {"Int64", MS_BI_INT64},   {"UInt8", MS_BI_UINT8},
    {"UInt16", MS_BI_UINT16}, {"UInt32", MS_BI_UINT32}, {"UInt64", MS_BI_UINT64},
    {"Float", MS_BI_FLOAT},   {"Float32", MS_BI_FLOAT32}, {"Float64", MS_BI_FLOAT64},
    {"Bool", MS_BI_BOOL},     {"String", MS_BI_STRING}, {"Void", MS_BI_VOID},
    {"Never", MS_BI_NEVER},
};

static const NameTag STANDARD[] = {
    {"Optional", MS_BI_OPTIONAL},   {"Result", MS_BI_RESULT},     {"List", MS_BI_LIST},
    {"Map", MS_BI_MAP},             {"Set", MS_BI_SET},           {"Bytes", MS_BI_BYTES},
    {"BigInt", MS_BI_BIGINT},       {"Decimal", MS_BI_DECIMAL},   {"Error", MS_BI_ERROR},
    {"Closeable", MS_BI_CLOSEABLE}, {"Hashable", MS_BI_HASHABLE}, {"Stringable", MS_BI_STRINGABLE},
    {"Comparable", MS_BI_COMPARABLE}, {"Equal", MS_BI_EQUAL},     {"Data", MS_BI_DATA},
    {"Clonable", MS_BI_CLONABLE},   {"Iterator", MS_BI_ITERATOR}, {"BytesBuilder", MS_BI_BYTESBUILDER},
    {"Regex", MS_BI_REGEX},
};

MsBuiltin ms_builtin_primitive(MsStr name) {
    for (size_t i = 0; i < sizeof PRIMITIVES / sizeof *PRIMITIVES; i++) {
        if (ty_str_is(name, PRIMITIVES[i].name)) {
            return PRIMITIVES[i].b;
        }
    }
    return MS_B_NONE;
}

MsBuiltin ms_builtin_from_id(MsStr id) {
    if (id.len < 5 || memcmp(id.ptr, "@std/", 5) != 0) {
        return MS_B_NONE;
    }
    MsStr rest = {id.ptr + 5, id.len - 5};
    for (size_t i = 0; i < sizeof STANDARD / sizeof *STANDARD; i++) {
        if (ty_str_is(rest, STANDARD[i].name)) {
            return STANDARD[i].b;
        }
    }
    return MS_B_NONE;
}

MsBuiltin ms_builtin_source(MsStr module, MsStr name) {
    static const struct {
        const char *module, *name;
        MsBuiltin b;
    } rows[] = {
        {"@std/time.ms", "Timestamp", MS_BI_TIMESTAMP},
        {"@std/time.ms", "Instant", MS_BI_INSTANT},
        {"@std/time.ms", "Duration", MS_BI_DURATION},
        {"@std/net/url.ms", "Url", MS_BI_URL},
        {"@std/net/ip.ms", "IpAddress", MS_BI_IPADDRESS},
        {"@std/net/ip.ms", "Cidr", MS_BI_CIDR},
        {"@std/data/json.ms", "JsonValue", MS_BI_JSONVALUE},
        {"@std/data/json.ms", "JsonEncode", MS_BI_JSONENCODE},
        {"@std/concurrency/promise.ms", "Promise", MS_BI_PROMISE},
        {"@std/concurrency/tasks.ms", "TaskGroup", MS_BI_TASKGROUP},
        {"@std/test/test.ms", "TestHooks", MS_BI_TESTHOOKS},
    };
    for (size_t i = 0; i < sizeof rows / sizeof *rows; i++) {
        if (ty_str_is(module, rows[i].module) && ty_str_is(name, rows[i].name)) {
            return rows[i].b;
        }
    }
    return MS_B_NONE;
}

bool ms_builtin_is_int(MsBuiltin b) { return b >= MS_BI_INT && b <= MS_BI_UINT64; }
bool ms_builtin_is_float(MsBuiltin b) { return b >= MS_BI_FLOAT && b <= MS_BI_FLOAT64; }

/* ---- the table ---- */

#define NO_RESULT UINT32_MAX

static void *grow(void *p, uint32_t *cap, uint32_t need, size_t elem) {
    if (need <= *cap) {
        return p;
    }
    uint32_t c = *cap ? *cap : 64;
    while (c < need) {
        c *= 2;
    }
    void *q = realloc(p, (size_t)c * elem);
    if (q == NULL) {
        abort();
    }
    *cap = c;
    return q;
}

void ms_tys_init(MsTyTable *t) {
    memset(t, 0, sizeof *t);
    t->mask = 255;
    t->slots = calloc(256, sizeof(uint32_t));
    if (t->slots == NULL) {
        abort();
    }
    /* row 0: no type */
    MsTyDesc none = {0};
    none.kind = MS_K_INVALID;
    ms_ty_fresh(t, &none);
}

void ms_tys_free(MsTyTable *t) {
    free(t->name); free(t->id); free(t->kind); free(t->builtin); free(t->def);
    free(t->args_at); free(t->nargs); free(t->params_at); free(t->nparams); free(t->result);
    free(t->args_pool); free(t->params_pool); free(t->slots);
    memset(t, 0, sizeof *t);
}

static uint64_t mix(uint64_t h, uint64_t v) {
    return (h ^ v) * 0x9e3779b97f4a7c15ull + (h >> 29);
}

static uint64_t hash_desc(const MsTyDesc *d) {
    uint64_t h = mix(mix(mix(1, d->id), d->kind), mix(d->builtin, d->def));
    h = mix(h, d->result);
    for (uint32_t i = 0; i < d->nargs; i++) {
        h = mix(h, d->args[i]);
    }
    for (uint32_t i = 0; i < d->nparams; i++) {
        h = mix(mix(mix(h, d->params[i].name), d->params[i].ty), d->params[i].flags);
    }
    return h ^ (h >> 32);
}

static bool row_equals(const MsTyTable *t, uint32_t r, const MsTyDesc *d) {
    if (t->id[r] != d->id || t->kind[r] != d->kind || t->builtin[r] != d->builtin ||
        t->def[r] != d->def || t->result[r] != d->result || t->nargs[r] != d->nargs ||
        t->nparams[r] != d->nparams || t->name[r] != d->name) {
        return false;
    }
    for (uint32_t i = 0; i < d->nargs; i++) {
        if (t->args_pool[t->args_at[r] + i] != d->args[i]) {
            return false;
        }
    }
    for (uint32_t i = 0; i < d->nparams; i++) {
        const MsTyParam *p = &t->params_pool[t->params_at[r] + i];
        if (p->name != d->params[i].name || p->ty != d->params[i].ty || p->flags != d->params[i].flags) {
            return false;
        }
    }
    return true;
}

static MsTy add_row(MsTyTable *t, const MsTyDesc *d) {
    uint32_t r = t->count;
    uint32_t cap = t->cap;
    uint32_t need = r + 1;
    if (need > cap) {
        uint32_t c = cap;
        t->name = grow(t->name, &c, need, sizeof *t->name);
        c = cap; t->id = grow(t->id, &c, need, sizeof *t->id);
        c = cap; t->kind = grow(t->kind, &c, need, sizeof *t->kind);
        c = cap; t->builtin = grow(t->builtin, &c, need, sizeof *t->builtin);
        c = cap; t->def = grow(t->def, &c, need, sizeof *t->def);
        c = cap; t->args_at = grow(t->args_at, &c, need, sizeof *t->args_at);
        c = cap; t->nargs = grow(t->nargs, &c, need, sizeof *t->nargs);
        c = cap; t->params_at = grow(t->params_at, &c, need, sizeof *t->params_at);
        c = cap; t->nparams = grow(t->nparams, &c, need, sizeof *t->nparams);
        c = cap; t->result = grow(t->result, &c, need, sizeof *t->result);
        t->cap = c;
    }
    t->args_pool = grow(t->args_pool, &t->args_cap, t->args_len + d->nargs, sizeof *t->args_pool);
    t->params_pool = grow(t->params_pool, &t->params_cap, t->params_len + d->nparams, sizeof *t->params_pool);
    t->name[r] = d->name;
    t->id[r] = d->id;
    t->kind[r] = (uint8_t)d->kind;
    t->builtin[r] = (uint8_t)d->builtin;
    t->def[r] = d->def;
    t->result[r] = d->result;
    t->args_at[r] = t->args_len;
    t->nargs[r] = d->nargs;
    if (d->nargs != 0) {
        memcpy(t->args_pool + t->args_len, d->args, d->nargs * sizeof(MsTy));
    }
    t->args_len += d->nargs;
    t->params_at[r] = t->params_len;
    t->nparams[r] = d->nparams;
    if (d->nparams != 0) {
        memcpy(t->params_pool + t->params_len, d->params, d->nparams * sizeof(MsTyParam));
    }
    t->params_len += d->nparams;
    t->count = r + 1;
    return r;
}

static void rehash(MsTyTable *t) {
    uint32_t size = (t->mask + 1) * 2;
    free(t->slots);
    t->slots = calloc(size, sizeof(uint32_t));
    if (t->slots == NULL) {
        abort();
    }
    t->mask = size - 1;
    for (uint32_t r = 1; r < t->count; r++) {
        if (t->kind[r] == MS_K_VARIABLE) {
            continue; /* fresh rows are never found by structure */
        }
        MsTyDesc d = {t->name[r], t->id[r], (MsKind)t->kind[r], (MsBuiltin)t->builtin[r], t->def[r],
                      t->args_pool + t->args_at[r], t->nargs[r], t->params_pool + t->params_at[r],
                      t->nparams[r], t->result[r]};
        uint32_t i = (uint32_t)hash_desc(&d) & t->mask;
        while (t->slots[i] != 0) {
            i = (i + 1) & t->mask;
        }
        t->slots[i] = r + 1;
    }
}

MsTy ms_ty_intern(MsTyTable *t, const MsTyDesc *d) {
    uint32_t i = (uint32_t)hash_desc(d) & t->mask;
    while (t->slots[i] != 0) {
        uint32_t r = t->slots[i] - 1;
        if (row_equals(t, r, d)) {
            return r;
        }
        i = (i + 1) & t->mask;
    }
    MsTy r = add_row(t, d);
    t->slots[i] = r + 1;
    if ((size_t)t->count * 2 > t->mask) {
        rehash(t);
    }
    return r;
}

MsTy ms_ty_fresh(MsTyTable *t, const MsTyDesc *d) {
    return add_row(t, d);
}

/* ---- display ---- */

#define DISPLAY_NODE_BUDGET 64

static void show(MsBuf *out, const MsNames *names, const MsTyTable *t, MsTy ty, uint32_t *budget) {
    if (*budget == 0) {
        ms_buf_puts(out, "\xe2\x80\xa6");
        return;
    }
    (*budget)--;
    if (t->kind[ty] == MS_K_FUNCTION) {
        ms_buf_puts(out, "fn(");
        const MsTyParam *ps = ms_ty_params(t, ty);
        for (uint32_t i = 0; i < t->nparams[ty]; i++) {
            if (i > 0) {
                ms_buf_puts(out, ", ");
            }
            if (ps[i].flags & MS_PARAM_MOVE) {
                ms_buf_puts(out, "move ");
            }
            if (ps[i].flags & MS_PARAM_VAR) {
                ms_buf_puts(out, "var ");
            }
            show(out, names, t, ps[i].ty, budget);
        }
        ms_buf_puts(out, ") ");
        if (t->result[ty] == MS_TY_NONE) {
            ms_buf_puts(out, "<unknown>");
        } else {
            show(out, names, t, t->result[ty], budget);
        }
        return;
    }
    if (t->builtin[ty] == MS_BI_OPTIONAL && t->nargs[ty] == 1) {
        MsTy inner = ms_ty_args(t, ty)[0];
        bool paren = t->kind[inner] == MS_K_FUNCTION;
        if (paren) {
            ms_buf_putc(out, '(');
        }
        show(out, names, t, inner, budget);
        ms_buf_puts(out, paren ? ")?" : "?");
        return;
    }
    MsStr n = ms_name(names, t->name[ty]);
    ms_buf_put(out, n.ptr, n.len);
    if (t->nargs[ty] != 0) {
        ms_buf_putc(out, '[');
        const MsTy *as = ms_ty_args(t, ty);
        for (uint32_t i = 0; i < t->nargs[ty]; i++) {
            if (i > 0) {
                ms_buf_puts(out, ", ");
            }
            show(out, names, t, as[i], budget);
        }
        ms_buf_putc(out, ']');
    }
}

void ms_ty_show(MsBuf *out, const MsNames *names, const MsTyTable *t, MsTy ty) {
    uint32_t budget = DISPLAY_NODE_BUDGET;
    show(out, names, t, ty, &budget);
}
