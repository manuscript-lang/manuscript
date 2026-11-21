/* Function bodies: the types of expressions and the bindings of names (the Rust checker's
 * stmts.rs and exprs.rs).
 *
 * The pass grows by constructs. A function is checked only when every statement and expression in
 * it is one the pass handles, and every one of them is accepted without a diagnostic; otherwise
 * the function is left unchecked and no fact of it remains. That keeps the differential against the
 * Rust checker (compiler/tests/check-diff.sh) exact for what the pass claims: it compares the
 * facts of the checked functions and requires the Rust checker to report nothing inside them.
 *
 * Handled so far: functions without type parameters whose parameters, locals and result are
 * `Int`, `Float`, `Bool` or `String` (result also `Void`); `name := value`, `var name = value`
 * with an optional primitive annotation; `return`; number, bool, void and text literals, names
 * of locals, `not`, unary `-` and `+`, and the binary operators over operands of one primitive
 * type. */
#include <errno.h>
#include <math.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include "check/check_body.h"
#include "ms/doc.h"
#include "ms/ty_algebra.h"
#include "ms/implements.h"
#include "ms/check.h"
#include "ms/constfold.h"
#include "ms/facts.h"
#include "ms/hints.h"
#include "ms/import_hints.h"



static bool body_is_value_type(const MsBody *b, MsTy ty) {
    return ty != MS_TY_NONE && (ty == b->int_ty || ty == b->float_ty || ty == b->bool_ty || ty == b->string_ty);
}

bool ms_body_is_primitive_value(const MsBody *b, MsTy ty) {
    return body_is_value_type(b, ty);
}

bool ms_body_is_plain_value(const MsBody *b, MsTy ty) {
    return body_is_value_type(b, ty) || (ty != MS_TY_NONE && ms_ty_kind(&b->c->tys, ty) == MS_K_VARIABLE);
}

static bool body_is_admitted(const MsBody *b, MsTy ty);

/* `Int8` through `UInt64` and `Float32`: values that are passed, held and returned, whose
 * operations (arithmetic, comparison, literals) the pass does not check yet. */
static bool body_is_sized_number(const MsBody *b, MsTy ty) {
    const MsTyTable *tys = &b->c->tys;
    static const MsBuiltin sized[] = {MS_BI_INT8,  MS_BI_INT16,  MS_BI_INT32,  MS_BI_INT64, MS_BI_UINT8,
                                      MS_BI_UINT16, MS_BI_UINT32, MS_BI_UINT64, MS_BI_FLOAT32};
    for (size_t i = 0; ty != MS_TY_NONE && i < sizeof sized / sizeof sized[0]; i++) {
        if (ms_ty_is(tys, ty, sized[i])) {
            return true;
        }
    }
    return false;
}
static bool body_is_bindable(const MsBody *b, MsTy ty);

/* Whether `arg` meets the interfaces that bound the variable `var` (`MapEntry[T: Hashable, U]`): each
 * bound is an interface without arguments of its own, which the tables must answer for `arg`. A bound
 * the tables cannot answer, or one over other variables, counts as unmet. */
static bool body_meets_bounds(const MsBody *b, MsTy var, MsTy arg) {
    const MsVarInfo *info = ms_var_info(b->c, var);
    for (uint32_t k = 0; k < info->nbounds; k++) {
        const MsTy contract = info->bounds[k];
        if (b->methods == NULL || b->c->tys.nargs[contract] != 0 || ms_ty_has_variable(&b->c->tys, contract) ||
            ms_implements(b->c, b->methods, arg, contract) != MS_FIT_YES) {
            return false;
        }
    }
    return true;
}

/* A `type`, `enum`, interface or native type (`Bytes`, `Promise[T]`) a module declares, whose type arguments (if it has any) are
 * themselves admitted. */
static bool body_is_own_nominal(const MsBody *b, MsTy ty) {
    const MsTyTable *tys = &b->c->tys;
    const MsKind kind = ms_ty_kind(tys, ty);
    const uint32_t def = tys->def[ty];
    if ((kind != MS_K_TYPE && kind != MS_K_ALTERNATIVE && kind != MS_K_CONTRACT && kind != MS_K_NATIVE) || def == 0) {
        return false;
    }
    const MsSymId sym = def - 1;
    if (sym >= b->c->syms.count || b->c->syms.kind[sym] != MS_SYM_TYPE) {
        return false;
    }
    // An argument that must meet a bound (`K: Hashable`) is checked against it by the Rust checker.
    if (tys->nargs[ty] == 0) {
        return true;
    }
    uint32_t nvars = 0;
    const MsTy *vars = ms_sym_vars(b->c, sym, &nvars);
    if (vars == NULL || nvars < tys->nargs[ty]) {
        return false;
    }
    for (uint32_t i = 0; i < tys->nargs[ty]; i++) {
        const MsTy arg = ms_ty_args(tys, ty)[i];
        if (arg == b->invalid_ty || !(arg == b->void_ty || body_is_bindable(b, arg)) || !body_meets_bounds(b, vars[i], arg)) {
            return false;
        }
    }
    return true;
}


/* A value of a nominal type that may need a cleanup, with type arguments of primitive type
 * (`WriteStream[String]`): only the receiver of a method call, which is a temporary. */
bool ms_body_is_handle(const MsBody *b, MsTy ty) {
    const MsTyTable *tys = &b->c->tys;
    const uint32_t def = tys->def[ty];
    if (ms_ty_kind(tys, ty) != MS_K_TYPE || def == 0 || def - 1 >= b->c->syms.count ||
        b->c->syms.kind[def - 1] != MS_SYM_TYPE) {
        return false;
    }
    for (uint32_t i = 0; i < tys->nargs[ty]; i++) {
        if (!body_is_value_type(b, ms_ty_args(tys, ty)[i])) {
            return false;
        }
    }
    return true;
}

/* A type whose values the pass can pass around: primitives, lists, function values and nominal
 * types. A value that closes is classified a resource by the ownership pass; the lowering leaves
 * it to the Rust lowering until it records the close. */
static bool body_is_admitted(const MsBody *b, MsTy ty) {
    return body_is_value_type(b, ty) || body_is_sized_number(b, ty) || (ty != MS_TY_NONE && ms_ty_kind(&b->c->tys, ty) == MS_K_VARIABLE) || ms_body_is_list(b, ty) || ms_body_is_map(b, ty) || ms_body_is_set(b, ty) || ms_body_is_function_value(b, ty) ||
           body_is_own_nominal(b, ty);
}

bool ms_body_is_admitted(const MsBody *b, MsTy ty) {
    return body_is_admitted(b, ty);
}

/* `Result[T, E]` whose success type the pass can hold (or `Void`); the error type is only ever
 * passed through by `?`, so any type is accepted for it. */
bool ms_body_is_result(const MsBody *b, MsTy ty) {
    const MsTyTable *tys = &b->c->tys;
    return ty != MS_TY_NONE && ms_ty_is(tys, ty, MS_BI_RESULT) && tys->nargs[ty] == 2 &&
           (ms_ty_args(tys, ty)[0] == b->void_ty || body_is_admitted(b, ms_ty_args(tys, ty)[0]));
}

static bool body_is_optional(const MsBody *b, MsTy ty) {
    const MsTyTable *tys = &b->c->tys;
    return ty != MS_TY_NONE && ms_ty_is(tys, ty, MS_BI_OPTIONAL) && tys->nargs[ty] == 1 &&
           body_is_admitted(b, ms_ty_args(tys, ty)[0]);
}

/* What a parameter or a local can hold. */
static bool body_is_bindable(const MsBody *b, MsTy ty) {
    return ms_body_has_invalid(b, ty) || body_is_admitted(b, ty) || body_is_optional(b, ty) || ms_body_is_result(b, ty);
}

bool ms_body_is_bindable(const MsBody *b, MsTy ty) {
    return body_is_bindable(b, ty);
}

/* What a `:=` or an `if name = value` can bind: also a Void value (`bad := say(1)`), which the Rust checker binds
 * with that type and no diagnostic of its own. A Never value stays with the Rust checker: the statement ends the path. */
static bool body_is_local(const MsBody *b, MsTy ty) {
    return body_is_bindable(b, ty) || ty == b->void_ty;
}

static bool body_is_numeric(const MsBody *b, MsTy ty) {
    return ty == b->int_ty || ty == b->float_ty;
}

/* Whether the type is `<invalid>` or built from it, as `Result[Int, <invalid>]`: an earlier
 * diagnostic is why, so nothing built on it reports. */
bool ms_body_has_invalid(const MsBody *b, MsTy ty) {
    const MsTyTable *tys = &b->c->tys;
    if (ty == b->invalid_ty) {
        return true;
    }
    for (uint32_t i = 0; ty != MS_TY_NONE && i < tys->nargs[ty]; i++) {
        if (ms_body_has_invalid(b, ms_ty_args(tys, ty)[i])) {
            return true;
        }
    }
    return false;
}

/* The standard type a type declared by the standard library is: `Optional` declared in `@std/core.ms`
 * is the built-in `@std/Optional` that `Int?` writes. A type of the program's own is never one. */
MsBuiltin ms_body_standard_identity(const MsBody *b, MsTy ty) {
    if (b->c->tys.builtin[ty] != MS_B_NONE) {
        return (MsBuiltin)b->c->tys.builtin[ty];
    }
    const uint32_t def = b->c->tys.def[ty];
    if (def == 0 || def - 1 >= b->c->syms.count) {
        return MS_B_NONE;
    }
    const MsStr module = ms_name(b->c->names, b->c->mods[b->c->syms.module[def - 1]].path);
    const MsStr name = ms_name(b->c->names, b->c->syms.name[def - 1]);
    char id[128];
    if (module.len < 5 || memcmp(module.ptr, "@std/", 5) != 0 ||
        snprintf(id, sizeof id, "@std/%.*s", (int)name.len, name.ptr) >= (int)sizeof id) {
        return MS_B_NONE;
    }
    return ms_builtin_from_id((MsStr){id, (uint32_t)strlen(id)});
}

/* Whether two types are the same type: equal, or the standard type declared by its module and the
 * built-in the program writes (`List[Int]` as declared by collections.ms and as written), with the
 * same arguments. */
bool ms_body_same_type(const MsBody *b, MsTy x, MsTy y) {
    const MsTyTable *tys = &b->c->tys;
    if (x == y) {
        return true;
    }
    const MsBuiltin identity = ms_body_standard_identity(b, x);
    if (x == MS_TY_NONE || y == MS_TY_NONE || identity == MS_B_NONE || identity != ms_body_standard_identity(b, y) ||
        tys->nargs[x] != tys->nargs[y]) {
        return false;
    }
    for (uint32_t i = 0; i < tys->nargs[x]; i++) {
        if (!ms_body_same_type(b, ms_ty_args(tys, x)[i], ms_ty_args(tys, y)[i])) {
            return false;
        }
    }
    return true;
}

/* A type that is only ever the same as itself: a primitive, or a type or enum, never an interface
 * (a value converts to it), an Optional or a Result (which a plain value converts to), and the
 * Promise and Error types, which have hints of their own. */
static bool body_is_comparable(const MsBody *b, MsTy ty) {
    const MsTyTable *tys = &b->c->tys;
    if (body_is_value_type(b, ty) || body_is_sized_number(b, ty)) {
        return true;
    }
    const MsKind kind = ms_ty_kind(tys, ty);
    return body_is_admitted(b, ty) && (kind == MS_K_TYPE || kind == MS_K_ALTERNATIVE) &&
           !ms_ty_is(tys, ty, MS_BI_OPTIONAL) && !ms_ty_is(tys, ty, MS_BI_RESULT) &&
           !ms_ty_is(tys, ty, MS_BI_PROMISE) && !ms_ty_is(tys, ty, MS_BI_ERROR);
}

/* Gives up on the function; the caller returns `<invalid>` (MS_TY_NONE) up the tree. */
void (*ms_body_decline_hook)(const char *file, int line);

MsTy ms_body_unsupported_at(MsBody *b, const char *file, int line) {
    if (b->supported) {
        b->gave_up = (MsSite){file, (uint32_t)line};
        if (ms_body_decline_hook != NULL) {
            ms_body_decline_hook(file, line);
        }
    }
    b->supported = false;
    return MS_TY_NONE;
}

/* A type diagnostic at `pos`, held until the function is claimed. */
static void body_report(MsBody *b, MsPos pos, MsStr message) {
    const MsCheckDiag diag = {.diag = {.pos = pos, .message = message}, .phase = MS_PHASE_TYPE};
    MS_VEC_PUSH(b->diags, MsCheckDiag, diag);
}

void ms_body_report(MsBody *b, MsPos pos, MsStr message) {
    body_report(b, pos, message);
}

static MsStr body_show(MsBody *b, MsTy ty);

MsTy ms_body_record(MsBody *b, uint32_t node, MsTy ty) {
    b->facts->expr_ty[node] = ty;
    MS_VEC_PUSH(b->written, uint32_t, node);
    return ty;
}

/* ---- bindings ---- */

uint32_t ms_body_find_binding(const MsBody *b, MsSym name) {
    const MsBindings *bindings = &b->facts->bindings;
    for (uint32_t i = bindings->count; i > b->first_binding; i--) {
        if (bindings->name[i - 1] == name && !b->closed[i - 1]) {
            return i - 1;
        }
    }
    return MS_NONE;
}

/* Binds a name in the function's one scope. A name already bound there would be a diagnostic. */
uint32_t ms_body_bind(MsBody *b, MsSym name, MsTy ty, uint32_t node, MsPos pos, uint8_t flags, MsBindRole role) {
    if (!ms_name_is(b->c->names, name, "_") && ms_body_find_binding(b, name) != MS_NONE) {
        (void)ms_body_unsupported(b);
        return MS_NONE;
    }
    MsBindings *bindings = &b->facts->bindings;
    const uint32_t id = bindings->count++;
    b->closed[id] = false;
    bindings->reads[id] = 0;
    bindings->pos[id] = pos;
    bindings->name[id] = name;
    bindings->ty[id] = ty;
    bindings->decl_node[id] = node;
    bindings->callable[id] = b->function;
    bindings->flags[id] = flags;
    bindings->role[id] = (uint8_t)role;
    bindings->conflict[id] = MS_CONFLICT_NONE;
    bindings->conflict_ty[id] = MS_TY_NONE;
    return id;
}



/* The values a sized integer type holds, as magnitudes: the largest negative one and the largest
 * positive one. False for a type that is not a sized integer (`Int` itself is the default). */
static bool body_int_limits(const MsBody *b, MsTy ty, uint64_t *negative, uint64_t *positive) {
    static const struct {
        const char *name;
        uint64_t negative, positive;
    } limits[] = {{"Int8", 128, 127},        {"Int16", 32768, 32767},       {"Int32", 2147483648u, 2147483647u},
                  {"UInt8", 0, 255},         {"UInt16", 0, 65535},          {"UInt32", 0, 4294967295u},
                  {"UInt64", 0, UINT64_MAX}};
    if (ty == MS_TY_NONE || ms_ty_kind(&b->c->tys, ty) != MS_K_PRIMITIVE) {
        return false;
    }
    const MsStr name = ms_name(b->c->names, b->c->tys.name[ty]);
    for (size_t i = 0; i < sizeof limits / sizeof *limits; i++) {
        if (strlen(limits[i].name) == name.len && memcmp(limits[i].name, name.ptr, name.len) == 0) {
            *negative = limits[i].negative;
            *positive = limits[i].positive;
            return true;
        }
    }
    return false;
}

/* The type of a number literal: a sized integer or `Float32` the context expects when the value
 * fits it, else `Int` or `Float`. A literal outside its type is a diagnostic, left to Rust. */
static MsTy body_number(MsBody *b, const MsExpr *e, MsTy expected, bool negated) {
    MsCheck *c = b->c;
    const MsStr text = ms_number_canonical(&c->arena, ms_name(c->names, e->u.sym));
    if (ms_number_is_decimal(text)) {
        return ms_body_unsupported(b);
    }
    char *digits = ms_arena_strndup(&c->arena, text.ptr, text.len);
    char *end = NULL;
    errno = 0;
    if (ms_number_is_fractional(text)) {
        const bool narrow = expected != MS_TY_NONE && expected != b->float_ty && ms_ty_kind(&c->tys, expected) == MS_K_PRIMITIVE &&
                            ms_name_is(c->names, c->tys.name[expected], "Float32");
        const double value = narrow ? (double)strtof(digits, &end) : strtod(digits, &end);
        if (*end != '\0' || isinf(value)) {
            return ms_body_unsupported(b);
        }
        return narrow ? expected : b->float_ty;
    }
    uint64_t negative = 0, positive = 0;
    if (body_int_limits(b, expected, &negative, &positive)) {
        const uint64_t value = strtoull(digits, &end, 10);
        const bool fits = *end == '\0' && errno == 0 && value <= (negated ? negative : positive);
        return fits ? expected : ms_body_unsupported(b);
    }
    (void)strtoll(digits, &end, 10);
    return *end != '\0' || errno != 0 ? ms_body_unsupported(b) : b->int_ty;
}

static MsTy body_text(MsBody *b, const MsExpr *e) {
    for (uint32_t i = 0; i < e->u.text.len; i++) {
        const MsExpr *part = e->u.text.ptr[i].expr;
        if (part == NULL) {
            continue;
        }
        const MsTy ty = ms_body_expr(b, part, MS_TY_NONE);
        if (ty == MS_TY_NONE) {
            return MS_TY_NONE;
        }
        ms_body_text_method(b, part, ty);
    }
    return b->string_ty;
}

/* ---- unknown names ---- */

/* The advice for a name other languages spell differently: `head`, then for a head that ends
 * before the name's own mention `name` and `tail`. */
typedef struct BodyNameHint {
    const char *name;
    const char *head;
    const char *tail; /* NULL when `head` is the whole hint */
} BodyNameHint;

#define PRINT_HINT                                                                                          \
    "; there is no ", ": use print(value), which writes any value and a newline; for write errors or bytes " \
                      "import stdout from \"@std/io/io.ms\" and call stdout().write(\"text\\n\")"
#define SPAWN_HINT                                                                                            \
    "; there is no free ", ": start concurrent work with promise(fn: ...) from "                           \
                           "\"@std/concurrency/promise.ms\" and call wait() on the returned Promise"
#define HANDLE_HINT                                                                                           \
    "; host handle getters were removed: import the operation itself, e.g. read_file from \"@std/os/fs.ms\", " \
    "connect from \"@std/net/net.ms\", run from \"@std/os/process.ms\", now from \"@std/time.ms\"", NULL
#define NULL_HINT                                                                                             \
    "; Manuscript has no null: absence is an Optional, written none, and a present value is just the value, " \
    "which converts where an Optional is expected", NULL
#define ERROR_HINT                                                                                            \
    "; write error(cause) for a failed Result, where cause has the Result's error type", NULL
#define TEXT_HINT "; to make text, interpolate: f\"{value}\", or call value.to_string()", NULL
#define INT_HINT                                                                                              \
    "; parse text with text.parse_int(), which returns Int?; Float has truncate_to_int()", NULL
#define FLOAT_HINT                                                                                            \
    "; parse text with parse_float (import parse_float from \"@std/math/math.ms\"), which returns a Result; " \
    "an Int converts with value.to_float()", NULL
#define COLLECTION_HINT                                                                                       \
    "; use the prelude List[T] and Map[K, V] types without imports; read a Map with m.keys(), m.values() or " \
    "m.entries()", NULL

static const BodyNameHint body_name_hints[] = {
    {"pass", "; 'pass' is not a keyword, so write 'void' for an empty block or match arm", NULL},
    {"range",
     "; there is no range function: write start..end for the integers from start up to but excluding end, or "
     "range_by from \"@std/collections/collections.ms\" for a stepped list",
     NULL},
    {"nil", NULL_HINT},
    {"null", NULL_HINT},
    {"None", NULL_HINT},
    {"undefined", NULL_HINT},
    {"Some", "; there is no Some: a plain value converts where an Optional is expected, so pass it directly", NULL},
    {"Ok", "; write the lowercase ok(value) for a successful Result", NULL},
    {"Err", ERROR_HINT},
    {"err", ERROR_HINT},
    {"Error", ERROR_HINT},
    {"True", "; booleans are lowercase: write true and false", NULL},
    {"False", "; booleans are lowercase: write true and false", NULL},
    {"len",
     "; there is no ",
     "() function: call the length member, e.g. xs.length() (String length is bytes; scalar_length counts "
     "scalars)"},
    {"str", TEXT_HINT},
    {"toString", TEXT_HINT},
    {"repr", TEXT_HINT},
    {"sprintf", TEXT_HINT},
    {"int", INT_HINT},
    {"parseInt", INT_HINT},
    {"atoi", INT_HINT},
    {"Number", INT_HINT},
    {"parse_int", INT_HINT},
    {"float", FLOAT_HINT},
    {"parseFloat", FLOAT_HINT},
    {"parse_float", FLOAT_HINT},
    {"Object", COLLECTION_HINT},
    {"Array", COLLECTION_HINT},
    {"dict", COLLECTION_HINT},
    {"list", COLLECTION_HINT},
    {"Math",
     "; the math functions (floor, sqrt, pow, ...) are in \"@std/math/math.ms\": import floor from "
     "\"@std/math/math.ms\"",
     NULL},
    {"math",
     "; the math functions (floor, sqrt, pow, ...) are in \"@std/math/math.ms\": import floor from "
     "\"@std/math/math.ms\"",
     NULL},
    {"console", PRINT_HINT},
    {"System", PRINT_HINT},
    {"fmt", PRINT_HINT},
    {"os", PRINT_HINT},
    {"println", PRINT_HINT},
    {"printf", PRINT_HINT},
    {"puts", PRINT_HINT},
    {"echo", PRINT_HINT},
    {"spawn", SPAWN_HINT},
    {"Promise", SPAWN_HINT},
    {"Future", SPAWN_HINT},
    {"Thread", SPAWN_HINT},
    {"thread", SPAWN_HINT},
    {"setTimeout", SPAWN_HINT},
    {"setInterval", SPAWN_HINT},
    {"filesystem", HANDLE_HINT},
    {"network", HANDLE_HINT},
    {"commands", HANDLE_HINT},
    {"control", HANDLE_HINT},
    {"system", HANDLE_HINT},
    {"clock", HANDLE_HINT},
    {"wall_clock", HANDLE_HINT},
    {"entropy", HANDLE_HINT},
    {"terminal", HANDLE_HINT},
    {"files", HANDLE_HINT},
};

static const BodyNameHint *body_name_hint(MsStr name) {
    for (size_t i = 0; i < sizeof body_name_hints / sizeof body_name_hints[0]; i++) {
        const BodyNameHint *hint = &body_name_hints[i];
        if (strlen(hint->name) == name.len && memcmp(hint->name, name.ptr, name.len) == 0) {
            return hint;
        }
    }
    return NULL;
}

/* Whether a method receiver is in scope, which the hints for `this` and for fields depend on. */
static bool body_has_receiver(const MsBody *b) {
    const MsBindings *bindings = &b->facts->bindings;
    for (uint32_t i = b->first_binding; i < bindings->count; i++) {
        if (bindings->role[i] == MS_ROLE_SELF) {
            return true;
        }
    }
    return false;
}

/* The names a typo could have meant: the bindings in scope and the module's functions. */
static size_t body_value_names(MsBody *b, MsArena *scratch, const MsStr **out) {
    const MsBindings *bindings = &b->facts->bindings;
    const MsNameMap *names = &b->c->mods[b->module].names;
    MsStr *list = MS_NEW_N(scratch, MsStr, (size_t)bindings->count + names->cap);
    size_t count = 0;
    for (uint32_t i = b->first_binding; i < bindings->count; i++) {
        if (!b->closed[i]) {
            list[count++] = ms_name(b->c->names, bindings->name[i]);
        }
    }
    for (uint32_t i = 0; i < names->cap; i++) {
        if (names->vals[i] != 0 && b->c->syms.kind[names->vals[i] - 1] == MS_SYM_FN) {
            list[count++] = ms_name(b->c->names, names->keys[i]);
        }
    }
    *out = list;
    return count;
}

/* The text after `unknown binding X`, or NULL when this port cannot say what Rust does yet. */
static const char *body_unknown_advice(MsBody *b, MsStr name) {
    if (body_has_receiver(b)) {
        return NULL;
    }
    if (name.len == 4 && memcmp(name.ptr, "this", 4) == 0) {
        return "; there is no 'this'; inside an impl method the receiver is 'self'";
    }
    const BodyNameHint *table = body_name_hint(name);
    if (table != NULL) {
        return table->tail == NULL
                   ? table->head
                   : ms_arena_fmt(&b->c->arena, "%s%.*s%s", table->head, (int)name.len, name.ptr, table->tail).ptr;
    }
    const MsStr import = ms_import_hint(&b->c->arena, b->c, name, b->c->mods[b->module].source);
    if (import.len != 0) {
        return ms_arena_strndup(&b->c->arena, import.ptr, import.len);
    }
    // The candidate list and the distance tables are scratch: only the advice outlives the search.
    MsArena scratch = {0};
    const MsStr *candidates = NULL;
    const size_t count = body_value_names(b, &scratch, &candidates);
    const MsStr near = ms_did_you_mean(&scratch, name, candidates, count);
    const char *advice = near.len == 0 ? NULL : ms_arena_strndup(&b->c->arena, near.ptr, near.len);
    ms_arena_free(&scratch);
    if (advice != NULL) {
        return advice;
    }
    return ms_arena_fmt(&b->c->arena,
                        "; declare it with '%.*s := ...' before use, define 'fn %.*s(...) T:', or import it from "
                        "a module",
                        (int)name.len, name.ptr, (int)name.len, name.ptr)
        .ptr;
}

/* Whether some type the module can name has an enum case called `name`: such a name is a
 * constructor, not an unknown. */
static bool body_is_case_name(const MsBody *b, MsSym name) {
    // The cases of `Result` and `Optional` are built in: the tables do not carry them.
    static const char *const builtin_cases[] = {"ok", "error", "some", "none"};
    for (size_t i = 0; i < MS_COUNT_OF(builtin_cases); i++) {
        if (ms_name_is(b->c->names, name, builtin_cases[i])) {
            return true;
        }
    }
    const MsNameMap *names = &b->c->mods[b->module].names;
    for (uint32_t i = 0; i < names->cap; i++) {
        const uint32_t sym = names->vals[i];
        if (sym == 0 || sym - 1 >= b->c->defs_cap) {
            continue;
        }
        const MsDef *def = &b->c->defs[sym - 1];
        for (uint32_t k = 0; k < def->ncases; k++) {
            if (def->cases[k].name == name) {
                return true;
            }
        }
    }
    return false;
}

/* A name that is not a binding, a module name, a source location or a case. Reported at the
 * name; the whole is invalid, which silences what uses it. */
static MsTy body_unknown_name_at(MsBody *b, MsPos pos, MsSym sym) {
    const MsStr name = ms_name(b->c->names, sym);
    const char *advice = body_unknown_advice(b, name);
    if (advice == NULL) {
        return ms_body_unsupported(b);
    }
    const MsStr message = ms_arena_fmt(&b->c->arena, "unknown binding %.*s%s", (int)name.len, name.ptr, advice);
    const MsCheckDiag diag = {.diag = {.pos = pos, .message = message},
                              .phase = MS_PHASE_RESOLUTION,
                              .unknown = sym};
    MS_VEC_PUSH(b->diags, MsCheckDiag, diag);
    return b->invalid_ty;
}

static MsTy body_unknown_name(MsBody *b, const MsExpr *e) {
    return body_unknown_name_at(b, e->pos, e->u.sym);
}

static bool body_is_unknown(const MsBody *b, MsSym name) {
    const MsStr text = ms_name(b->c->names, name);
    const bool source_location = (text.len == 8 && memcmp(text.ptr, "__LINE__", 8) == 0) ||
                                 (text.len == 8 && memcmp(text.ptr, "__FILE__", 8) == 0);
    return ms_map_get(&b->c->mods[b->module].names, name) == MS_NONE && !source_location &&
           !body_is_case_name(b, name);
}

/* A read of a module constant, its own or an imported one, whose initializer this pass has typed: a
 * call of no arguments, typed as the initializer. */
static MsTy body_constant_use(MsBody *b, const MsExpr *e) {
    const MsSymId sym = ms_map_get(&b->c->mods[b->module].names, e->u.sym);
    const MsSyms *syms = &b->c->syms;
    if (sym == MS_NONE || syms->decl[sym] == NULL ||
        syms->decl[sym]->kind != MS_D_CONST || syms->ty[sym] == MS_TY_NONE) {
        return ms_body_unsupported(b);
    }
    b->facts->res_kind[e->id] = MS_RES_SYMBOL;
    b->facts->res_ref[e->id] = sym;
    b->facts->call_callee[e->id] = sym;
    b->facts->const_use[e->id] = true;
    return b->c->tys.result[syms->ty[sym]];
}

static MsTy body_name(MsBody *b, const MsExpr *e, MsTy expected) {
    const uint32_t binding = ms_body_find_binding(b, e->u.sym);
    if (binding == MS_NONE && ms_body_is_case_of(b, expected, e->u.sym)) {
        return ms_body_case_name(b, e, expected);
    }
    if (binding == MS_NONE && !ms_name_is(b->c->names, e->u.sym, "none")) {
        const MsSymId named = ms_map_get(&b->c->mods[b->module].names, e->u.sym);
        const bool constant = named != MS_NONE && b->c->syms.decl[named] != NULL && b->c->syms.decl[named]->kind == MS_D_CONST;
        if (named != MS_NONE && b->c->syms.kind[named] == MS_SYM_FN && !constant) {
            return ms_body_function_name(b, e);
        }
        return body_is_unknown(b, e->u.sym) ? body_unknown_name(b, e) : body_constant_use(b, e);
    }
    if (binding == MS_NONE || ms_name_is(b->c->names, e->u.sym, "none")) {
        return ms_body_unsupported(b);
    }
    b->facts->res_kind[e->id] = MS_RES_BINDING;
    b->facts->res_ref[e->id] = binding;
    b->facts->bindings.reads[binding]++;
    return b->facts->bindings.ty[binding];
}

/* A call of a function this module declares, by its plain name: arguments positional, one per
 * parameter, each the parameter's type. The callee's own body is checked on its own; a callee the
 * lowering cannot handle fails the callers there. */
/* `Type(field: value, ...)` for a record this module declares without type parameters: every
 * field given once, in declaration order, named or positional, each of an admitted type. The
 * call's callee is the type, which is how the effect scan sees a constructor. */
/* Pairs the arguments of `call` with parameters as the Rust checker does: an argument labelled with
 * a parameter's name goes to it; an unlabelled one fills the first parameter no earlier argument
 * took. `slot[i]` is the parameter of argument i and `covered[p]` says parameter p got an argument.
 * False for a label no parameter has (or one that is positional-only), a parameter given twice, and
 * an unlabelled argument with no parameter left: those are diagnostics the Rust checker reports. */
bool ms_body_bind_arguments(const MsExpr *call, const MsSym *names, const bool *positional,
                            uint32_t nparams, uint32_t *slot, bool *covered) {
    memset(covered, 0, nparams * sizeof *covered);
    uint32_t next = 0;
    for (uint32_t i = 0; i < call->u.call.args.len; i++) {
        const MsArg *arg = &call->u.call.args.ptr[i];
        uint32_t found = nparams;
        if (arg->has_name) {
            for (uint32_t p = 0; p < nparams && found == nparams; p++) {
                found = names[p] == arg->name && (positional == NULL || !positional[p]) ? p : found;
            }
        } else {
            while (next < nparams && covered[next]) {
                next++;
            }
            found = next;
        }
        if (found >= nparams || covered[found]) {
            return false;
        }
        covered[found] = true;
        slot[i] = found;
    }
    return true;
}

bool ms_body_reordered(const MsExpr *call, const uint32_t *slot) {
    for (uint32_t i = 0; i < call->u.call.args.len; i++) {
        if (slot[i] != i) {
            return true;
        }
    }
    return false;
}

/* Whether the default of field `index` of record `sym` was checked in the module that declares it
 * (`body_check_defaults`); a construction leaving the field out then takes it. */
static bool body_has_default(const MsBody *b, MsSymId sym, const MsDecl *decl, uint32_t index) {
    const MsFacts *home = b->c->mods[b->c->syms.module[sym]].facts;
    const MsExpr *def = decl->u.type.fields.ptr[index]->def;
    // A module whose bodies this run does not check (the standard library) checked its defaults when it was built.
    return home->expr_ty == NULL || home->expr_ty[def->id] != MS_TY_NONE;
}

/* A type another module declares has its field defaults typed once that module's bodies are
 * checked (body_check_defaults); a construction leaving a field out needs them. Done before the
 * caller holds pointers into the tables, which checking may move. */
void ms_body_check_home(MsBody *b, MsSymId sym) {
    const MsModId home = b->c->syms.module[sym];
    if (home != MS_NONE && home != b->module && b->methods != NULL && b->c->mods[home].facts != NULL &&
        b->c->mods[home].facts->body_checked == NULL) {
        ms_module_check_bodies_with(b->c, home, b->methods);
    }
}

/* An `extern type` the standard library declares buildable from source with no arguments
 * (`// ms: constructible` above it): `StringBuilder()`. The others have a literal or a function. */
static bool body_constructible_extern(const MsBody *b, MsSymId sym, const MsDecl *decl, MsTy record) {
    const MsSyms *syms = &b->c->syms;
    return decl != NULL && decl->kind == MS_D_TYPE && decl->u.type.external && syms->nvars[sym] == 0 &&
           ms_ty_kind(&b->c->tys, record) == MS_K_NATIVE && body_is_admitted(b, record) &&
           syms->module[sym] != MS_NONE &&
           ms_doc_has_marker(b->c->mods[syms->module[sym]].text, decl->pos.offset, "constructible");
}

/* The signature of the function `sym` names. A standard function the native tables and the module's own
 * declarations both register (`panic`) is resolved on the symbol the module declares, not on the table's. */
static MsTy body_declared_signature(const MsBody *b, MsSymId sym) {
    const MsSyms *syms = &b->c->syms;
    if (syms->ty[sym] != MS_TY_NONE) {
        return syms->ty[sym];
    }
    const MsSymId own = ms_decl_own_symbol(b->c, syms->module[sym], syms->decl[sym]);
    return own == MS_NONE ? MS_TY_NONE : syms->ty[own];
}

static MsTy body_construct(MsBody *b, const MsExpr *e, MsSymId sym) {
    ms_body_check_home(b, sym);
    const MsSyms *syms = &b->c->syms;
    const MsTy record = syms->ty[sym];
    const MsDef *def = ms_def(b->c, sym);
    const MsDecl *decl = syms->decl[sym];
    const uint32_t nargs = e->u.call.args.len;
    if (nargs == 0 && body_constructible_extern(b, sym, decl, record)) {
        b->facts->call_callee[e->id] = sym;
        return record;
    }
    if (syms->nvars[sym] != 0 || decl == NULL || decl->kind != MS_D_TYPE || decl->u.type.external ||
        (syms->module[sym] != b->module && decl->u.type.opaque) || ms_ty_kind(&b->c->tys, record) != MS_K_TYPE ||
        !body_is_admitted(b, record) || nargs > def->nfields || def->nfields != decl->u.type.fields.len) {
        return ms_body_unsupported(b);
    }
    MsSym *names = MS_NEW_N(&b->c->arena, MsSym, def->nfields + 1);
    bool *covered = MS_NEW_N(&b->c->arena, bool, def->nfields + 1);
    uint32_t *slot = MS_NEW_N(&b->c->arena, uint32_t, nargs + 1);
    for (uint32_t i = 0; i < def->nfields; i++) {
        names[i] = def->fields[i].name;
    }
    if (!ms_body_bind_arguments(e, names, NULL, def->nfields, slot, covered)) {
        return ms_body_unsupported(b);
    }
    for (uint32_t i = 0; i < def->nfields; i++) {
        // A field left out takes its default.
        if (!covered[i] && decl->u.type.fields.ptr[i]->def == NULL) {
            return ms_body_unsupported(b);
        }
    }
    for (uint32_t i = 0; i < nargs; i++) {
        const MsTy field = def->fields[slot[i]].ty;
        if (def->fields[slot[i]].flags != 0 || !body_is_bindable(b, field) ||
            ms_body_expr(b, e->u.call.args.ptr[i].value, field) == MS_TY_NONE) {
            return ms_body_unsupported(b);
        }
    }
    for (uint32_t i = 0; i < def->nfields; i++) {
        if (!covered[i] && !body_has_default(b, sym, decl, i)) {
            return ms_body_unsupported(b);
        }
    }
    b->facts->call_reordered[e->id] = ms_body_reordered(e, slot);
    b->facts->call_callee[e->id] = sym;
    return record;
}

/* "missing argument NAME: T in call to CALLEE; add 'NAME: <T>'" at the call. */
static void body_report_missing(MsBody *b, const MsExpr *call, uint32_t index, const MsTyParam *param, MsStr callee) {
    const MsStr name = ms_name(b->c->names, param->name);
    const MsStr ty = body_show(b, param->ty);
    const bool positional = (param->flags & MS_PARAM_POSITIONAL) != 0;
    body_report(b, call->pos,
                positional ? ms_arena_fmt(&b->c->arena, "missing argument %u: %.*s in call to %.*s; pass it positionally, without a label",
                                          index + 1, (int)ty.len, ty.ptr, (int)callee.len, callee.ptr)
                           : ms_arena_fmt(&b->c->arena, "missing argument %.*s: %.*s in call to %.*s; add '%.*s: <%.*s>'",
                                          (int)name.len, name.ptr, (int)ty.len, ty.ptr, (int)callee.len, callee.ptr,
                                          (int)name.len, name.ptr, (int)ty.len, ty.ptr));
}

/* The arguments of a call to `function`, in parameter order, positional or labelled with the
 * parameter's name: each is checked against its parameter with the context "argument 'NAME' of
 * CALLEE". An argument past the last parameter and a parameter with no argument are reported.
 * A parameter with a default may be left out. False when something here is left to the Rust
 * checker (labels out of order or unknown, parameters of types the pass does not admit); the
 * caller returns the unsupported mark. */
static bool body_arguments(MsBody *b, const MsExpr *call, const MsFunc *function, const MsTyParam *params, MsStr callee) {
    const uint32_t nparams = function->params.len;
    const uint32_t nargs = call->u.call.args.len;
    for (uint32_t i = 0; i < nargs; i++) {
        const MsArg *arg = &call->u.call.args.ptr[i];
        if (i >= nparams) {
            if (arg->has_name) {
                return false;
            }
            body_report(b, arg->pos, ms_arena_fmt(&b->c->arena, "too many positional arguments; every parameter is already supplied, so remove this argument"));
            if (ms_body_expr(b, arg->value, MS_TY_NONE) == MS_TY_NONE) {
                return false;
            }
            continue;
        }
        const bool handed = (params[i].flags & (MS_PARAM_VAR | MS_PARAM_MOVE)) != 0;
        if ((arg->has_name && (arg->name != params[i].name || (params[i].flags & MS_PARAM_POSITIONAL) != 0)) ||
            !(body_is_value_type(b, params[i].ty) || (!handed && ms_body_is_function_value(b, params[i].ty)) || body_is_admitted(b, params[i].ty) || body_is_optional(b, params[i].ty))) {
            return false;
        }
        const MsStr name = ms_name(b->c->names, params[i].name);
        b->context = ms_arena_fmt(&b->c->arena, "argument '%.*s' of %.*s", (int)name.len, name.ptr, (int)callee.len,
                                  callee.ptr).ptr;
        if (ms_body_expr(b, arg->value, params[i].ty) == MS_TY_NONE) {
            return false;
        }
    }
    for (uint32_t i = nargs; i < nparams; i++) {
        if (ms_body_has_invalid(b, params[i].ty)) {
            return false;
        }
        if (function->params.ptr[i]->def != NULL) {
            continue; // the default fills it
        }
        body_report_missing(b, call, i, &params[i], callee);
    }
    return true;
}

/* `name[Int](args)`: a call of a generic function of the module with written type arguments. */
static MsTy body_explicit_call(MsBody *b, const MsExpr *e) {
    const MsExpr *apply = e->u.call.callee;
    const MsSymId sym = ms_map_get(&b->c->mods[b->module].names, apply->u.apply.left->u.sym);
    const MsSyms *syms = &b->c->syms;
    if (ms_body_find_binding(b, apply->u.apply.left->u.sym) != MS_NONE || sym == MS_NONE) {
        return ms_body_unsupported(b);
    }
    if (syms->kind[sym] == MS_SYM_TYPE) {
        return ms_body_generic_construct(b, e, sym, &apply->u.apply.types);
    }
    const bool generic = syms->kind[sym] == MS_SYM_FN && syms->nvars[sym] != 0 && syms->decl[sym] != NULL &&
                         syms->decl[sym]->kind == MS_D_FN;
    return generic ? ms_body_generic_call(b, e, sym, &apply->u.apply.types, MS_TY_NONE) : ms_body_unsupported(b);
}

static MsTy body_call(MsBody *b, const MsExpr *e, MsTy expected) {
    const MsExpr *callee = e->u.call.callee;
    if (callee->kind == MS_E_MEMBER) {
        return ms_body_is_qualified_case(b, callee) ? ms_body_qualified_case_call(b, e) : ms_body_method_call(b, e);
    }
    const uint32_t called = callee->kind == MS_E_NAME ? ms_body_find_binding(b, callee->u.sym) : MS_NONE;
    if (called != MS_NONE) {
        return ms_body_call_value(b, e, called);
    }
    if (callee->kind == MS_E_APPLY && callee->u.apply.left->kind == MS_E_NAME) {
        return body_explicit_call(b, e);
    }
    if (callee->kind != MS_E_NAME) {
        return ms_body_unsupported(b);
    }
    if (body_is_unknown(b, callee->u.sym)) {
        // The arguments of a call to nothing are not checked.
        return body_unknown_name(b, callee);
    }
    const MsSymId sym = ms_map_get(&b->c->mods[b->module].names, callee->u.sym);
    const MsSyms *syms = &b->c->syms;
    if (sym == MS_NONE && ms_body_is_builtin_case(b, callee->u.sym)) {
        return ms_body_builtin_call(b, e, expected);
    }
    if (sym == MS_NONE && ms_body_is_case_of(b, expected, callee->u.sym)) {
        return ms_body_case_call(b, e, expected);
    }
    if (sym != MS_NONE && syms->kind[sym] == MS_SYM_TYPE) {
        return syms->nvars[sym] != 0 ? ms_body_generic_construct(b, e, sym, NULL) : body_construct(b, e, sym);
    }
    if (sym == MS_NONE || syms->kind[sym] != MS_SYM_FN ||
        syms->decl[sym] == NULL || syms->decl[sym]->kind != MS_D_FN) {
        return ms_body_unsupported(b);
    }
    if (syms->nvars[sym] != 0) {
        return ms_body_generic_call(b, e, sym, NULL, expected);
    }
    if (syms->ty[sym] == MS_TY_NONE) {
        ms_module_resolve_types(b->c, syms->module[sym]); // a native function's signature is resolved on first call
    }
    const MsTy sig = body_declared_signature(b, sym);
    const MsTyTable *tys = &b->c->tys;
    if (ms_ty_kind(tys, sig) != MS_K_FUNCTION) {
        return ms_body_unsupported(b);
    }
    if (tys->nparams[sig] != syms->decl[sym]->u.fn.params.len ||
        !body_arguments(b, e, &syms->decl[sym]->u.fn, ms_ty_params(tys, sig), ms_name(b->c->names, callee->u.sym))) {
        return ms_body_unsupported(b);
    }
    b->facts->call_callee[e->id] = sym;
    const MsTy result = tys->result[sig];
    if (ms_body_has_invalid(b, result)) {
        return b->invalid_ty;
    }
    return body_is_bindable(b, result) || result == b->void_ty || ms_body_is_handle(b, result) ? result
                                                                                          : ms_body_unsupported(b);
}

/* `call()?` on a `Result[T, E]` inside a function that returns `Result[_, E]`, or on an
 * `Optional[T]` inside one that returns an Optional or Void: the success value, with the failure
 * returned from the function. Only the operand of a call is handled, which is a temporary. */
static MsTy body_try(MsBody *b, const MsExpr *operand) {
    const MsTyTable *tys = &b->c->tys;
    const MsTy operand_ty = operand->kind == MS_E_CALL ? ms_body_expr(b, operand, MS_TY_NONE) : MS_TY_NONE;
    if (operand_ty == MS_TY_NONE) {
        return ms_body_unsupported(b);
    }
    if (ms_body_is_result(b, operand_ty)) {
        const bool same_error = ms_body_is_result(b, b->result) && ms_ty_args(tys, b->result)[1] == ms_ty_args(tys, operand_ty)[1];
        return same_error ? ms_ty_args(tys, operand_ty)[0] : ms_body_unsupported(b);
    }
    return ms_body_unsupported(b);
}

static MsTy body_unary(MsBody *b, const MsExpr *e, MsTy expected) {
    const MsExpr *operand = e->u.bin.left;
    const MsUnaryOp op = (MsUnaryOp)e->op;
    if (op == MS_U_TRY) {
        return body_try(b, operand);
    }
    if (op == MS_U_NEG && operand->kind == MS_E_NUMBER) {
        // A negated literal is typed as the literal; -9223372036854775808 is Int's own case.
        const MsStr text = ms_number_canonical(&b->c->arena, ms_name(b->c->names, operand->u.sym));
        if (text.len == 19 && memcmp(text.ptr, "9223372036854775808", 19) == 0) {
            return ms_body_unsupported(b);
        }
        const MsTy literal = body_number(b, operand, expected, true);
        return literal == MS_TY_NONE ? literal : ms_body_record(b, operand->id, literal);
    }
    // A sign keeps the number type the context expects, so a literal inside it fits that type.
    const MsTy hint = op != MS_U_NOT && body_is_sized_number(b, expected) ? expected : MS_TY_NONE;
    const MsTy operand_ty = ms_body_expr(b, operand, hint);
    if (operand_ty == MS_TY_NONE) {
        return MS_TY_NONE;
    }
    if (op == MS_U_NOT) {
        if (operand_ty == b->bool_ty || operand_ty == b->invalid_ty) {
            return b->bool_ty;
        }
        if (!body_is_value_type(b, operand_ty)) {
            return ms_body_unsupported(b);
        }
        const MsStr found = body_show(b, operand_ty);
        body_report(b, e->pos,
                    ms_arena_fmt(&b->c->arena, "not requires Bool, found %.*s; compare explicitly, e.g. not (x == 0)",
                                 (int)found.len, found.ptr));
        return b->bool_ty;
    }
    return body_is_numeric(b, operand_ty) ? operand_ty : ms_body_unsupported(b);
}

/* A field's declared type at the type arguments of the record that holds it. */
static MsTy body_field_at(MsBody *b, MsTy record, MsTy declared) {
    uint32_t nvars = 0;
    const MsTy *vars = ms_sym_vars(b->c, b->c->tys.def[record] - 1, &nvars);
    const uint32_t count = b->c->tys.nargs[record];
    if (vars == NULL || count == 0 || nvars < count) {
        return declared;
    }
    const MsTySubst subst = {.vars = vars, .args = ms_ty_args(&b->c->tys, record), .count = count};
    return ms_ty_subst(&b->c->tys, &b->c->arena, declared, &subst);
}

/* `local.field` where the local holds a record this module declares and the field is a Copy
 * primitive (Int, Float, Bool): the field's type. Anything else a member can be (a method, a case, a module path)
 * is not checked yet. */
typedef enum { MEMBER_READ, MEMBER_RECEIVER, MEMBER_STORE } MemberUse;

static MsTy body_member_of(MsBody *b, const MsExpr *e, MemberUse use);

static MsTy body_member(MsBody *b, const MsExpr *e) { return body_member_of(b, e, MEMBER_READ); }

/* A field is read as the receiver of another member when it is a record this module declares:
 * only the path matters, nothing is borrowed or moved out of the holder. */
static MsTy body_member_of(MsBody *b, const MsExpr *e, MemberUse use) {
    const MsExpr *receiver = e->u.member.left;
    if (use == MEMBER_READ && ms_body_is_qualified_case(b, e)) {
        return ms_body_qualified_case(b, e);
    }
    if (receiver->kind != MS_E_NAME && receiver->kind != MS_E_MEMBER && receiver->kind != MS_E_CALL && receiver->kind != MS_E_INDEX &&
        receiver->kind != MS_E_APPLY) {
        return ms_body_unsupported(b);
    }
    const MsTy record = receiver->kind == MS_E_MEMBER ? ms_body_record(b, receiver->id, body_member_of(b, receiver, MEMBER_RECEIVER))
                                                      : ms_body_expr(b, receiver, MS_TY_NONE);
    if (record == MS_TY_NONE) {
        return MS_TY_NONE;
    }
    const MsTyTable *tys = &b->c->tys;
    if (ms_ty_kind(tys, record) != MS_K_TYPE || !body_is_own_nominal(b, record)) {
        return ms_body_unsupported(b);
    }
    const MsDef *def = ms_def(b->c, tys->def[record] - 1);
    for (uint32_t i = 0; def != NULL && i < def->nfields; i++) {
        if (def->fields[i].name != e->u.member.name) {
            continue;
        }
        const MsTy field = body_field_at(b, record, def->fields[i].ty);
        const bool path = use == MEMBER_RECEIVER && ms_ty_kind(tys, field) == MS_K_TYPE && body_is_own_nominal(b, field);
        if (!path && use != MEMBER_STORE && !body_is_admitted(b, field)) {
            break;
        }
        b->facts->res_kind[e->id] = MS_RES_FIELD;
        b->facts->res_ref[e->id] = i;
        return field;
    }
    return ms_body_unsupported(b);
}

static bool body_is_ordering(MsBinaryOp op) {
    return op == MS_B_LT || op == MS_B_GT || op == MS_B_LE || op == MS_B_GE;
}

/* Integer arithmetic over constants that always faults is a diagnostic. */
static bool body_constant_fault(MsBody *b, const MsExpr *e) {
    const MsStr fault = ms_constant_arithmetic_fault(&b->c->arena, b->literals, (MsBinaryOp)e->op, e->u.bin.left,
                                                     e->u.bin.right, "Int", INT64_MIN, INT64_MAX);
    return fault.len != 0;
}

/* What to do about operands of two different primitive types: Int with Float, or text with a
 * number for `*`, have their own hint. */
static const char *body_operand_hint(const MsBody *b, MsBinaryOp op, MsTy left, MsTy right) {
    const bool mixed = (left == b->int_ty && right == b->float_ty) || (left == b->float_ty && right == b->int_ty);
    if (mixed) {
        return "convert the Int with value.to_float(), or the Float with value.truncate_to_int() (returns Int?)";
    }
    const bool repeat = (left == b->string_ty && right == b->int_ty) || (left == b->int_ty && right == b->string_ty);
    if (repeat && op == MS_B_MUL) {
        return "to repeat text write text.repeat(count), which returns a Result (append '?' to propagate it)";
    }
    return "convert one side so both have one type (e.g. interpolate into text with f\"{value}\", or convert "
           "between Int and Float)";
}

/* Operands of two primitive types that differ: reported at the operator, and the whole is
 * invalid (a comparison is still Bool), which silences whatever uses it. */
static MsTy body_report_operands(MsBody *b, const MsExpr *e, MsTy left, MsTy right) {
    const MsBinaryOp op = (MsBinaryOp)e->op;
    const MsStr l = body_show(b, left);
    const MsStr r = body_show(b, right);
    const MsStr message = ms_arena_fmt(
        &b->c->arena, "operator operands require the same independently known type, found %.*s %s %.*s; %s", (int)l.len,
        l.ptr, ms_binary_str(op), (int)r.len, r.ptr, body_operand_hint(b, op, left, right));
    body_report(b, e->pos, message);
    const bool comparison = op == MS_B_EQ || op == MS_B_NE || body_is_ordering(op);
    return comparison ? b->bool_ty : b->invalid_ty;
}

/* Whether `==` accepts two values of `ty` by structure: primitives, and records, enums, lists and
 * optionals built only of such parts. A type with type arguments, a native type or an interface is left to
 * the Rust checker; a written `equals` can only widen what compares, never narrow it. `depth` bounds the walk
 * (a type that holds itself is deeper than the bound and is not admitted). */
static bool body_is_native_equal(const MsBody *b, MsTy ty);

static bool body_is_equatable(MsBody *b, MsTy ty, uint32_t depth) {
    const MsTyTable *tys = &b->c->tys;
    if (ty == MS_TY_NONE || depth > 8) {
        return false;
    }
    if (body_is_value_type(b, ty) || body_is_sized_number(b, ty) || body_is_native_equal(b, ty)) {
        return true;
    }
    if (ms_ty_kind(tys, ty) == MS_K_VARIABLE) {
        return ms_implements_equal(b->c, b->methods, ty) == MS_FIT_YES;
    }
    if ((ms_ty_is(tys, ty, MS_BI_LIST) || ms_ty_is(tys, ty, MS_BI_OPTIONAL)) && tys->nargs[ty] == 1) {
        return body_is_equatable(b, ms_ty_args(tys, ty)[0], depth + 1);
    }
    const MsKind kind = ms_ty_kind(tys, ty);
    if ((kind != MS_K_TYPE && kind != MS_K_ALTERNATIVE) || tys->def[ty] == 0 || tys->builtin[ty] != 0 || tys->nargs[ty] != 0 ||
        !body_is_own_nominal(b, ty)) {
        return false;
    }
    const MsDef *def = &b->c->defs[tys->def[ty] - 1];
    for (uint32_t i = 0; i < def->nfields; i++) {
        if (!body_is_equatable(b, def->fields[i].ty, depth + 1)) {
            return false;
        }
    }
    for (uint32_t i = 0; i < def->ncases; i++) {
        for (uint32_t k = 0; k < def->cases[i].nfields; k++) {
            if (!body_is_equatable(b, def->cases[i].fields[k].ty, depth + 1)) {
                return false;
            }
        }
    }
    return true;
}

/* The standard types whose equality needs no `equals`: `Property::Equal` holds for them whatever their parts. */
static bool body_is_native_equal(const MsBody *b, MsTy ty) {
    static const MsBuiltin equal[] = {MS_BI_DECIMAL, MS_BI_BYTES, MS_BI_DURATION, MS_BI_INSTANT, MS_BI_BIGINT, MS_BI_TIMESTAMP};
    for (size_t i = 0; ty != MS_TY_NONE && i < sizeof equal / sizeof equal[0]; i++) {
        if (ms_ty_is(&b->c->tys, ty, equal[i])) {
            return true;
        }
    }
    return false;
}

/* Whether `ty` is an integer or float of any width, `BigInt` or `Decimal`: what arithmetic accepts. */
static bool body_is_numeric_operand(const MsBody *b, MsTy ty) {
    return body_is_numeric(b, ty) || body_is_sized_number(b, ty) || ms_ty_is(&b->c->tys, ty, MS_BI_BIGINT) ||
           ms_ty_is(&b->c->tys, ty, MS_BI_DECIMAL);
}

/* Whether `ty` is an integer type (`Int` or a sized one) or `BigInt`: what `%` accepts. */
static bool body_is_remainder_operand(const MsBody *b, MsTy ty) {
    return ty == b->int_ty || ms_ty_is(&b->c->tys, ty, MS_BI_BIGINT) || (body_is_sized_number(b, ty) && !ms_ty_is(&b->c->tys, ty, MS_BI_FLOAT32));
}

/* Whether `<`, `<=`, `>` and `>=` order `ty`: numbers, text and the time types. */
static bool body_is_ordered(const MsBody *b, MsTy ty) {
    return ty == b->string_ty || body_is_numeric_operand(b, ty) || ms_ty_is(&b->c->tys, ty, MS_BI_DURATION) ||
           ms_ty_is(&b->c->tys, ty, MS_BI_INSTANT);
}

/* Integer arithmetic over constants of the sized integer type `ty` that always faults is a diagnostic. */
static bool body_sized_constant_fault(MsBody *b, const MsExpr *e, MsTy ty) {
    uint64_t negative = 0, positive = 0;
    if (!body_int_limits(b, ty, &negative, &positive)) {
        return false;
    }
    const MsStr name = ms_name(b->c->names, b->c->tys.name[ty]);
    char shown[16];
    (void)snprintf(shown, sizeof shown, "%.*s", (int)name.len, name.ptr);
    const MsStr fault = ms_constant_arithmetic_fault(&b->c->arena, b->literals, (MsBinaryOp)e->op, e->u.bin.left, e->u.bin.right,
                                                     shown, -(MsInt128)negative, (MsInt128)positive);
    return fault.len != 0;
}

/* The type an unsuffixed literal operand takes from the other operand: a sized integer for an integer
 * literal tree, `Float32` for a fractional one. NONE when the operand is not such a tree. */
static MsTy body_literal_hint(MsBody *b, const MsExpr *literal, MsTy other) {
    if (!body_is_sized_number(b, other)) {
        return MS_TY_NONE;
    }
    const bool sized_float = ms_ty_is(&b->c->tys, other, MS_BI_FLOAT32);
    const MsLiteralKind kind = ms_literal_tree_kind(b->literals, literal);
    return kind == (sized_float ? MS_LITERAL_FRACTIONAL : MS_LITERAL_INTEGER) ? other : MS_TY_NONE;
}

/* `opt == plain`: the plain side wraps without `some`, so the operands compare as the Optional does. */
static bool body_is_wrapped_operand(MsBody *b, MsBinaryOp op, MsTy left, MsTy right) {
    const MsTyTable *tys = &b->c->tys;
    return (op == MS_B_EQ || op == MS_B_NE) && ms_ty_is(tys, left, MS_BI_OPTIONAL) && tys->nargs[left] == 1 &&
           ms_body_same_type(b, ms_ty_args(tys, left)[0], right) && body_is_equatable(b, left, 0);
}

/* Operands of one type that is not Int, Float, Bool or String: the number types, the time types and the types
 * `==` accepts by structure. Whatever else they do is left to the Rust checker. */
static MsTy body_binary_same(MsBody *b, const MsExpr *e, MsTy ty) {
    const MsBinaryOp op = (MsBinaryOp)e->op;
    if (op == MS_B_EQ || op == MS_B_NE) {
        return body_is_equatable(b, ty, 0) ? b->bool_ty : ms_body_unsupported(b);
    }
    if (body_is_ordering(op)) {
        return body_is_ordered(b, ty) ? b->bool_ty : ms_body_unsupported(b);
    }
    const bool remainder = op == MS_B_REM;
    if (!body_is_numeric_operand(b, ty) || (remainder && !body_is_remainder_operand(b, ty)) || body_sized_constant_fault(b, e, ty)) {
        return ms_body_unsupported(b);
    }
    return ty;
}

static MsTy body_binary(MsBody *b, const MsExpr *e) {
    const MsBinaryOp op = (MsBinaryOp)e->op;
    const MsTy left = ms_body_expr(b, e->u.bin.left, MS_TY_NONE);
    // `opt == value` compares as `opt == Optional`: the plain side wraps without `some`, but `none` has its own report.
    const MsTyTable *tys = &b->c->tys;
    const MsExpr *plain = e->u.bin.right;
    const bool none_operand = plain->kind == MS_E_NAME && ms_name_is(b->c->names, plain->u.sym, "none");
    const bool wraps = (op == MS_B_EQ || op == MS_B_NE) && left != MS_TY_NONE && ms_ty_is(tys, left, MS_BI_OPTIONAL) &&
                       tys->nargs[left] == 1 && !none_operand;
    MsTy hint = MS_TY_NONE;
    if (left != MS_TY_NONE) {
        hint = wraps ? left : body_literal_hint(b, plain, left);
    }
    const MsTy right = left == MS_TY_NONE ? MS_TY_NONE : ms_body_expr(b, plain, hint);
    if (right == MS_TY_NONE) {
        return MS_TY_NONE;
    }
    const bool comparison = op == MS_B_EQ || op == MS_B_NE || body_is_ordering(op);
    if (left == b->invalid_ty || right == b->invalid_ty) {
        // An operand already reported its own error; this one does not restate it.
        return comparison || op == MS_B_AND || op == MS_B_OR ? b->bool_ty : b->invalid_ty;
    }
    if (op == MS_B_AND || op == MS_B_OR) {
        return left == b->bool_ty && right == b->bool_ty ? b->bool_ty : ms_body_unsupported(b);
    }
    if (left != right && body_is_value_type(b, left) && body_is_value_type(b, right)) {
        return body_report_operands(b, e, left, right);
    }
    if (body_is_wrapped_operand(b, op, left, right)) {
        return b->bool_ty;
    }
    if (left == right && ms_ty_is(tys, left, MS_BI_BIGINT)) {
        return comparison ? b->bool_ty : left; // every operator applies to a BigInt; no constant range to overflow
    }
    if (left != right) {
        return ms_body_unsupported(b);
    }
    if (!body_is_value_type(b, left)) {
        return body_binary_same(b, e, left);
    }
    if (op == MS_B_EQ || op == MS_B_NE) {
        return b->bool_ty;
    }
    if (body_is_ordering(op)) {
        return left == b->bool_ty ? ms_body_unsupported(b) : b->bool_ty;
    }
    if (left == b->string_ty) {
        return op == MS_B_ADD ? left : ms_body_unsupported(b);
    }
    const bool numeric = body_is_numeric(b, left);
    const bool remainder_of_float = op == MS_B_REM && left != b->int_ty;
    if (!numeric || remainder_of_float || (left == b->int_ty && body_constant_fault(b, e))) {
        return ms_body_unsupported(b);
    }
    return left;
}

/* ---- diagnostics ---- */

static MsStr body_show(MsBody *b, MsTy ty) {
    MsBuf text = {0};
    ms_ty_show(&text, b->c->names, &b->c->tys, ty);
    const MsStr shown = ms_arena_fmt(&b->c->arena, "%.*s", (int)text.len, (const char *)text.data);
    ms_buf_free(&text);
    return shown;
}

/* What the implicit conversion between two primitives would be, written out; "" for none. */
static const char *body_conversion_hint(MsBody *b, MsTy actual, MsTy expected) {
    if (actual == b->int_ty && expected == b->float_ty) {
        return "Int does not convert to Float implicitly; write a Float literal such as 3.0, or call to_float() on an Int value";
    }
    if (actual == b->float_ty && expected == b->int_ty) {
        return "Float does not convert to Int implicitly; truncate_to_int() returns Int?, so unwrap it, e.g. value.truncate_to_int().get(0)";
    }
    if (expected == b->string_ty && (actual == b->int_ty || actual == b->float_ty || actual == b->bool_ty)) {
        const MsStr type = body_show(b, actual);
        return ms_arena_fmt(&b->c->arena,
                            "%.*s does not convert to String implicitly; interpolate it into text, e.g. f\"{value}\"",
                            (int)type.len, type.ptr)
            .ptr;
    }
    return "";
}

/* "expected X, found Y (in <context>)" at `e`, with the conversion hint where one applies. */
static void body_report_mismatch(MsBody *b, const MsExpr *e, MsTy actual, MsTy expected, const char *context) {
    const MsStr want = body_show(b, expected);
    const MsStr found = body_show(b, actual);
    const char *hint = body_conversion_hint(b, actual, expected);
    // An empty context is a value with no statement around it, such as a field default.
    const MsStr where = *context == '\0' ? (MsStr){"", 0} : ms_arena_fmt(&b->c->arena, " (in %s)", context);
    const MsStr message = ms_arena_fmt(&b->c->arena, "expected %.*s, found %.*s%.*s%s%s", (int)want.len, want.ptr,
                                       (int)found.len, found.ptr, (int)where.len, where.ptr, *hint != '\0' ? "; " : "", hint);
    body_report(b, e->pos, message);
}

/* The type of `e` where `expected` is the type the context wants, or MS_TY_NONE for no
 * expectation. A type that is not the expected one is a diagnostic. */
/* A value checked against an Optional: `none`, a value of the Optional's own type, or a value of
 * its payload type, which is wrapped in `some` (`some_wrap`). Anything else (a mismatch, which the
 * Rust checker words) is left to the Rust checker. A wrapped payload that owns something is a view
 * of a borrowed value and a wrapper around a fresh one: the ownership pass keeps the fresh ones. */
static MsTy body_expr_optional(MsBody *b, const MsExpr *e, MsTy expected) {
    const MsTy payload = ms_ty_args(&b->c->tys, expected)[0];
    if (e->kind == MS_E_NAME && ms_name_is(b->c->names, e->u.sym, "none") && ms_body_find_binding(b, e->u.sym) == MS_NONE) {
        return ms_body_record(b, e->id, expected);
    }
    const MsTy ty = ms_body_expr(b, e, MS_TY_NONE);
    if (ty == MS_TY_NONE || ty == expected) {
        return ty;
    }
    if (ty != payload || !body_is_admitted(b, payload)) {
        return ms_body_unsupported(b);
    }
    b->facts->some_wrap[e->id] = true;
    return expected;
}

/* A value of a type this module's methods fit to an interface, passed where the interface is expected. */
static bool body_coerces_to_interface(const MsBody *b, MsTy ty, MsTy expected) {
    const MsTyTable *tys = &b->c->tys;
    return b->methods != NULL && ms_ty_kind(tys, expected) == MS_K_CONTRACT && ty != expected &&
           ms_ty_kind(tys, ty) != MS_K_CONTRACT && ms_ty_kind(tys, ty) != MS_K_VARIABLE &&
           ms_implements(b->c, b->methods, ty, expected) == MS_FIT_YES;
}

MsTy ms_body_expr(MsBody *b, const MsExpr *e, MsTy expected) {
    MsTy ty = MS_TY_NONE;
    const char *context = b->context;
    b->context = NULL;
    if (expected != MS_TY_NONE && ms_ty_is(&b->c->tys, expected, MS_BI_OPTIONAL)) {
        return body_expr_optional(b, e, expected);
    }
    switch ((MsExprKind)e->kind) {
    case MS_E_NUMBER: ty = body_number(b, e, expected, false); break;
    case MS_E_BOOL: ty = b->bool_ty; break;
    case MS_E_VOID: ty = b->void_ty; break;
    case MS_E_TEXT: ty = body_text(b, e); break;
    case MS_E_NAME: ty = body_name(b, e, expected); break;
    case MS_E_UNARY: ty = body_unary(b, e, expected); break;
    case MS_E_BINARY: ty = body_binary(b, e); break;
    case MS_E_MEMBER: ty = body_member(b, e); break;
    case MS_E_INDEX:
    case MS_E_APPLY: ty = ms_body_index(b, e); break;
    case MS_E_LIST: ty = ms_body_list(b, e, expected); break;
    case MS_E_MAP: ty = ms_body_map(b, e, expected); break;
    case MS_E_PROBE: return ms_body_unsupported(b);
    case MS_E_LAMBDA: ty = ms_body_lambda(b, e, expected); break;
    case MS_E_CALL: ty = body_call(b, e, expected); break;
    case MS_E_MATCH: ty = ms_body_match(b, e, expected); break;
    }
    if (ty == MS_TY_NONE) {
        return ty;
    }
    if (ty == b->invalid_ty) {
        // Already reported where it went wrong; nothing built on it is.
        (void)ms_body_record(b, e->id, ty);
        return expected != MS_TY_NONE ? expected : ty;
    }
    if (expected == b->invalid_ty) {
        return ms_body_record(b, e->id, ty); // what was asked for is already reported
    }
    if (expected != MS_TY_NONE && body_coerces_to_interface(b, ty, expected)) {
        b->facts->coerce_iface[e->id] = ty; // the lowering boxes it behind its vtable; the expression has the interface type
        return ms_body_record(b, e->id, expected);
    }
    if (expected != MS_TY_NONE && !ms_body_same_type(b, ty, expected) && ms_body_reads_where_var_expected(b, ty, expected)) {
        return ms_body_record(b, e->id, expected); // a function that reads where `var` is expected stands in for it
    }
    if (expected != MS_TY_NONE && !ms_body_same_type(b, ty, expected)) {
        // A value of the wrong primitive type is reported where the statement asked for it; the
        // statement goes on as if it had the expected type, as the Rust checker does.
        if (context == NULL || !body_is_comparable(b, ty) || !body_is_comparable(b, expected)) {
            return ms_body_unsupported(b);
        }
        // Rust attaches a source rewrite to these conversions in a bare context; the Rust checker keeps them.
        if (*context == '\0' && ((ty == b->int_ty && expected == b->float_ty) ||
                                 (expected == b->string_ty && (ty == b->int_ty || ty == b->float_ty || ty == b->bool_ty)))) {
            return ms_body_unsupported(b);
        }
        body_report_mismatch(b, e, ty, expected, context);
        (void)ms_body_record(b, e->id, ty);
        return expected;
    }
    return ms_body_record(b, e->id, ty);
}

/* ---- statements ---- */

/* `Name[A, B]` or `T?`: a generic type the module sees, applied to annotations; the application is
 * kept only when a local can hold it (its arguments admitted and unbounded). */
static MsTy body_applied_annotation(MsBody *b, const MsTypeRef *t) {
    const MsSymId sym = ms_map_get(&b->c->mods[b->module].names, t->name);
    if (sym == MS_NONE || b->c->syms.kind[sym] != MS_SYM_TYPE || b->c->syms.ty[sym] == MS_TY_NONE ||
        b->c->syms.nvars[sym] != t->args.len || t->args.len > 8) {
        return ms_body_unsupported(b);
    }
    MsTy args[8];
    for (uint32_t i = 0; i < t->args.len; i++) {
        args[i] = ms_body_annotation(b, t->args.ptr[i]);
        if (args[i] == MS_TY_NONE) {
            return MS_TY_NONE;
        }
    }
    const MsTy ty = ms_ty_apply(b->c, b->c->syms.ty[sym], args, t->args.len);
    if (ty == MS_TY_NONE || !body_is_bindable(b, ty)) {
        return ms_body_unsupported(b);
    }
    b->facts->type_ref_ty[t->id] = ty;
    return ty;
}

/* The `Void` a function type writes as its result, or the annotation's own type. */
static MsTy body_fn_result(MsBody *b, const MsTypeRef *t) {
    if (t->kind == MS_TYPE_NAMED && t->args.len == 0) {
        const MsSymId sym = ms_map_get(&b->c->mods[b->module].names, t->name);
        if (sym != MS_NONE && b->c->syms.ty[sym] == b->void_ty) {
            b->facts->type_ref_ty[t->id] = b->void_ty;
            return b->void_ty;
        }
    }
    return ms_body_annotation(b, t);
}

/* `fn(A, B) R`: a function type whose parameters and result are annotations the pass admits, with
 * the positional parameters the Rust resolver gives a written function type. */
static MsTy body_fn_annotation(MsBody *b, const MsTypeRef *t) {
    if (t->params.len > 16) {
        return ms_body_unsupported(b);
    }
    MsTyParam *params = MS_NEW_N(&b->c->arena, MsTyParam, t->params.len + 1);
    for (uint32_t i = 0; i < t->params.len; i++) {
        const MsParam *p = t->params.ptr[i];
        const MsTy ty = ms_body_annotation(b, p->ty);
        if (ty == MS_TY_NONE) {
            return MS_TY_NONE;
        }
        const uint8_t flags = (uint8_t)((p->is_mutable ? MS_PARAM_VAR : 0) | (p->moving ? MS_PARAM_MOVE : 0) | MS_PARAM_POSITIONAL);
        params[i] = (MsTyParam){.name = p->name, .ty = ty, .flags = flags};
    }
    const MsTy result = body_fn_result(b, t->result);
    if (result == MS_TY_NONE) {
        return MS_TY_NONE;
    }
    const MsSym fn = ms_intern_cstr(b->c->names, "fn");
    const MsTyDesc desc = {.name = fn, .id = fn, .kind = MS_K_FUNCTION, .params = params, .nparams = t->params.len, .result = result};
    const MsTy ty = ms_ty_intern(&b->c->tys, &desc);
    if (!body_is_bindable(b, ty)) {
        return ms_body_unsupported(b);
    }
    b->facts->type_ref_ty[t->id] = ty;
    return ty;
}

/* The primitive type a written annotation names, or MS_TY_NONE. */
MsTy ms_body_annotation(MsBody *b, const MsTypeRef *t) {
    if (t->kind == MS_TYPE_FN) {
        return body_fn_annotation(b, t);
    }
    if (t->kind == MS_TYPE_NAMED && t->args.len != 0) {
        const MsSymId sym = ms_map_get(&b->c->mods[b->module].names, t->name);
        const bool list = sym != MS_NONE && b->c->syms.ty[sym] != MS_TY_NONE && ms_ty_is(&b->c->tys, b->c->syms.ty[sym], MS_BI_LIST);
        return list ? ms_body_list_annotation(b, t) : body_applied_annotation(b, t);
    }
    if (t->kind == MS_TYPE_NAMED && t->args.len == 2) {
        return ms_body_map_annotation(b, t);
    }
    if (t->kind != MS_TYPE_NAMED || t->args.len != 0) {
        return ms_body_unsupported(b);
    }
    for (uint32_t i = 0; b->tparams != NULL && i < b->tparams->len; i++) {
        if (b->tparams->ptr[i]->name == t->name) {
            b->facts->type_ref_ty[t->id] = b->tvars[i];
            return b->tvars[i];
        }
    }
    const MsSymId sym = ms_map_get(&b->c->mods[b->module].names, t->name);
    const MsTy ty = sym == MS_NONE ? MS_TY_NONE : b->c->syms.ty[sym];
    const bool primitive = sym != MS_NONE && b->c->syms.decl[sym] == NULL && ty != MS_TY_NONE && body_is_admitted(b, ty) &&
                           ms_ty_kind(&b->c->tys, ty) == MS_K_PRIMITIVE;
    const bool declared = ty != MS_TY_NONE && body_is_own_nominal(b, ty) && body_is_admitted(b, ty);
    if (!primitive && !declared) {
        return ms_body_unsupported(b);
    }
    b->facts->type_ref_ty[t->id] = ty;
    return ty;
}

/* A `var (` group only changes the layout: each entry is an ordinary binding. */
static void body_bind_statement(MsBody *b, const MsStmt *s) {
    const MsPattern *pattern = s->u.bind.pattern;
    if (pattern->kind != MS_P_NAME) {
        (void)ms_body_unsupported(b);
        return;
    }
    const MsTy expected = s->u.bind.ty == NULL ? MS_TY_NONE : ms_body_annotation(b, s->u.bind.ty);
    if (!b->supported) {
        return;
    }
    if (expected != MS_TY_NONE) {
        const MsStr name = ms_name(b->c->names, pattern->u.name);
        b->context = ms_arena_fmt(&b->c->arena, "the initializer of '%.*s'", (int)name.len, name.ptr).ptr;
    }
    const MsTy value = ms_body_expr(b, s->u.bind.value, expected);
    if (value == MS_TY_NONE || !body_is_local(b, value)) {
        (void)ms_body_unsupported(b);
        return;
    }
    const uint8_t flags = s->u.bind.is_mutable ? MS_BIND_MUTABLE : 0;
    const MsBindRole role = s->u.bind.is_mutable ? MS_ROLE_VAR : MS_ROLE_LET;
    const uint32_t binding = ms_body_bind(b, pattern->u.name, value, pattern->id, pattern->pos, flags, role);
    if (binding != MS_NONE) {
        b->facts->pattern_binding[pattern->id] = binding;
    }
}

/* `name = value` where `name` is no binding: an unknown name, or a module declaration, which is
 * not an assignment target. The value is checked with no expectation. False when this is left to
 * the Rust checker. */
static bool body_assign_to_declaration(MsBody *b, const MsStmt *s) {
    const MsSym name = s->u.assign.name;
    if (body_is_unknown(b, name)) {
        if (body_unknown_name_at(b, s->pos, name) == MS_TY_NONE) {
            return false;
        }
    } else {
        const MsSymId sym = ms_map_get(&b->c->mods[b->module].names, name);
        const MsSyms *syms = &b->c->syms;
        if (sym == MS_NONE || syms->decl[sym] == NULL) {
            return false;
        }
        const bool imported = syms->module[sym] != b->module;
        const char *what = NULL;
        const MsDeclKind kind = syms->decl[sym]->kind;
        if (kind == MS_D_CONST) {
            what = imported ? "imported constant" : "constant";
        } else if (kind == MS_D_FN) {
            what = imported ? "imported function" : "function";
        } else if (kind == MS_D_TYPE) {
            what = imported ? "imported type" : "type";
        }
        if (what == NULL) {
            return false;
        }
        const MsStr text = ms_name(b->c->names, name);
        body_report(b, s->pos,
                    ms_arena_fmt(&b->c->arena, "cannot assign to %s %.*s; assignment targets are 'var' bindings and type fields",
                                 what, (int)text.len, text.ptr));
    }
    if (ms_body_expr(b, s->u.assign.value, MS_TY_NONE) == MS_TY_NONE) {
        (void)ms_body_unsupported(b);
    }
    return true;
}

/* `local.a.b = value` where `local` is a `var` and the last field is a Copy primitive: the value
 * is checked against the field's type and the statement records the local it changes. Stores into
 * other places, and every diagnostic a store can have, are left to the Rust checker. */
static void body_assign_field(MsBody *b, const MsStmt *s) {
    const MsExpr *target = s->u.assign.target;
    const MsExpr *root = target;
    while (root->kind == MS_E_MEMBER) {
        root = root->u.member.left;
    }
    const uint32_t binding = root->kind == MS_E_NAME ? ms_body_find_binding(b, root->u.sym) : MS_NONE;
    if (target->kind != MS_E_MEMBER || binding == MS_NONE || binding < b->lambda_floor) {
        (void)ms_body_unsupported(b);
        return;
    }
    const MsTy field = ms_body_record(b, target->id, body_member_of(b, target, MEMBER_STORE));
    if (field == MS_TY_NONE || ms_body_expr(b, s->u.assign.value, field) == MS_TY_NONE) {
        (void)ms_body_unsupported(b);
        return;
    }
    b->facts->field_store_root[s->id] = binding;
}

/* `name = value` and `name op= value` (the parser writes the second as `name = name op value`).
 * Reads of the name inside the value only feed its next value, so they do not count as reads. */
static void body_assign_statement(MsBody *b, const MsStmt *s) {
    if (s->u.assign.member_target) {
        body_assign_field(b, s);
        return;
    }
    const uint32_t binding = ms_body_find_binding(b, s->u.assign.name);
    if (binding == MS_NONE && body_assign_to_declaration(b, s)) {
        return;
    }
    if (binding == MS_NONE || binding < b->lambda_floor) {
        (void)ms_body_unsupported(b);
        return;
    }
    if ((b->facts->bindings.flags[binding] & MS_BIND_MUTABLE) == 0) {
        const MsStr name = ms_name(b->c->names, s->u.assign.name);
        const MsStr message = ms_arena_fmt(&b->c->arena,
                                           "cannot assign immutable binding %.*s; declare it with 'var %.*s = ...' "
                                           "instead of '%.*s := ...'",
                                           (int)name.len, name.ptr, (int)name.len, name.ptr, (int)name.len, name.ptr);
        body_report(b, s->pos, message);
    }
    uint32_t *reads = &b->facts->bindings.reads[binding];
    const uint32_t reads_before = *reads;
    (void)ms_body_expr(b, s->u.assign.value, b->facts->bindings.ty[binding]);
    if (*reads != reads_before) {
        b->facts->bindings.flags[binding] |= MS_BIND_FED;
    }
    *reads = reads_before;
    b->facts->assign_binding[s->id] = binding;
}

/* An expression used as a statement. A `Result` it does not propagate with `?` is a lost failure,
 * and a standalone `?` must have nothing to keep; the other forms are left to the Rust checker. */
/* Whether control leaves the statement: it does unless it is a `match` whose every arm returns or breaks. */
static bool body_call_statement(MsBody *b, const MsStmt *s) {
    const MsExpr *value = s->u.expr;
    const MsTy ty = ms_body_expr(b, value, MS_TY_NONE);
    const bool propagated = value->kind == MS_E_UNARY && value->op == MS_U_TRY;
    if (ty == MS_TY_NONE || (propagated && ty != b->void_ty && ty != b->invalid_ty)) {
        (void)ms_body_unsupported(b);
        return false;
    }
    if (value->kind == MS_E_MATCH && !b->match_falls) {
        return false;
    }
    if (propagated || !ms_ty_is(&b->c->tys, ty, MS_BI_RESULT)) {
        return true;
    }
    const MsStr shown = body_show(b, ty);
    const MsStr message = ms_arena_fmt(
        &b->c->arena,
        "this statement discards %.*s, so a failure would be lost; write a trailing '?' to propagate it, 'if value := x' "
        "or 'match' to handle it, or 'void ...' to drop it on purpose",
        (int)shown.len, shown.ptr);
    body_report(b, s->pos, message);
    return true;
}

/* Whether finishing the body, or a bare `return`, is a complete result: the function returns
 * `Void`, or `Void!`, for which it means `ok(void)`. */
static bool body_returns_nothing(const MsBody *b) {
    const MsTyTable *tys = &b->c->tys;
    return b->result == b->void_ty ||
           (ms_body_is_result(b, b->result) && ms_ty_args(tys, b->result)[0] == b->void_ty);
}

/* A `return` in a function literal whose result is not known yet: its value (or the lack of one) fixes it. */
static void body_return_deciding(MsBody *b, const MsExpr *value) {
    b->context = "the return value";
    MsTy ty = value == NULL ? b->void_ty : ms_body_builtin_open(b, value, b->result_hint);
    if (ty == MS_TY_NONE && b->supported && value != NULL) {
        ty = ms_body_expr(b, value, MS_TY_NONE);
    }
    if (ty == MS_TY_NONE || !(ty == b->void_ty || body_is_bindable(b, ty))) {
        (void)ms_body_unsupported(b);
        return;
    }
    b->result = ty;
}

static void body_return_statement(MsBody *b, const MsStmt *s) {
    const MsExpr *value = s->u.expr;
    if (b->infer_result && b->result == MS_TY_NONE) {
        body_return_deciding(b, value);
        return;
    }
    if (value == NULL) {
        if (!b->supported || body_returns_nothing(b)) {
            return;
        }
        const MsStr result = body_show(b, b->result);
        const char *example = ms_ty_is(&b->c->tys, b->result, MS_BI_RESULT)
                                  ? "'return ok(value)' for success or 'return error(e)' for failure"
                                  : "'return <value>'";
        body_report(b, s->pos,
                    ms_arena_fmt(&b->c->arena, "bare return requires Void or Void!; this function returns %.*s, so write %s",
                                 (int)result.len, result.ptr, example));
        return;
    }
    b->context = "the return value";
    (void)ms_body_expr(b, value, b->result);
}


static void body_close_scope(MsBody *b, uint32_t scope_start);

/* `if name = optional` or `if name = result`: the payload (a Result's Ok value) is bound for the then-branch only. */
static bool body_if_let_statement(MsBody *b, const MsStmt *s) {
    const MsPattern *pattern = s->u.branch.binding;
    MsTy payload = MS_TY_NONE;
    if (pattern->kind != MS_P_NAME || s->u.branch.is_mutable) {
        (void)ms_body_unsupported(b);
        return false;
    }
    const MsTy ty = ms_body_expr(b, s->u.branch.cond, MS_TY_NONE);
    const MsTyTable *tys = &b->c->tys;
    const bool result = ty != MS_TY_NONE && ms_ty_is(tys, ty, MS_BI_RESULT) && tys->nargs[ty] == 2;
    if (result) {
        payload = ms_ty_args(tys, ty)[0]; // the Ok payload; the error is not captured
    } else if (ty == b->invalid_ty) {
        payload = b->invalid_ty; // the scrutinee is reported already; the branches are still checked
    }
    if ((!result && payload == MS_TY_NONE && !ms_body_optional_payload(b, ty, &payload)) || !body_is_local(b, payload)) {
        (void)ms_body_unsupported(b);
        return false;
    }
    const uint32_t scope_start = b->facts->bindings.count;
    const uint32_t binding = ms_body_bind(b, pattern->u.name, payload, pattern->id, pattern->pos, 0, MS_ROLE_PATTERN);
    if (binding == MS_NONE) {
        return false;
    }
    b->facts->pattern_binding[pattern->id] = binding;
    const bool then_falls = ms_body_block(b, &s->u.branch.body);
    body_close_scope(b, scope_start);
    const bool else_falls = s->u.branch.else_body.len == 0 || ms_body_block(b, &s->u.branch.else_body);
    return then_falls || else_falls;
}

/* Checks a condition against `Bool`, then the branches; whether control can leave the statement. */
static bool body_if_statement(MsBody *b, const MsStmt *s) {
    if (s->u.branch.binding != NULL) {
        return body_if_let_statement(b, s);
    }
    const MsExpr *cond = s->u.branch.cond;
    b->context = "an if condition";
    if (ms_body_expr(b, cond, b->bool_ty) == MS_TY_NONE) {
        (void)ms_body_unsupported(b);
        return false;
    }
    const bool then_falls = ms_body_block(b, &s->u.branch.body);
    const bool else_falls = s->u.branch.else_body.len == 0 || ms_body_block(b, &s->u.branch.else_body);
    return then_falls || else_falls;
}


/* Whether `callee` names the standard library's `range`. */
static bool body_is_range(const MsBody *b, const MsExpr *callee) {
    if (callee->kind != MS_E_NAME || ms_body_find_binding(b, callee->u.sym) != MS_NONE) {
        return false;
    }
    const MsSymId sym = ms_map_get(&b->c->mods[b->module].names, callee->u.sym);
    if (sym == MS_NONE) {
        return false;
    }
    const MsStr id = ms_name(b->c->names, b->c->syms.id[sym]);
    return id.len == 22 && memcmp(id.ptr, "@std/collections/range", 22) == 0;
}

static bool body_while_statement(MsBody *b, const MsStmt *s) {
    const MsExpr *cond = s->u.loop.cond;
    b->context = "a while condition";
    if (ms_body_expr(b, cond, b->bool_ty) == MS_TY_NONE) {
        (void)ms_body_unsupported(b);
        return false;
    }
    const uint32_t outer_breaks = b->breaks;
    b->breaks = 0;
    b->loop_depth++;
    (void)ms_body_block(b, &s->u.loop.body);
    b->loop_depth--;
    const bool broke = b->breaks != 0;
    b->breaks = outer_breaks;
    // `while true` ends only through a `break`.
    return broke || !(cond->kind == MS_E_BOOL && cond->u.flag);
}

/* `for name in xs` over a list of Int, Float, Bool, String or lists: the element type. An element that
 * owns something is borrowed from the list. */
static bool body_for_list_element(MsBody *b, const MsExpr *iter, MsTy *element) {
    b->borrow_ok = iter; // `for c in s.chars()` reads the borrowing result in place
    const MsTy ty = ms_body_expr(b, iter, MS_TY_NONE);
    if (!ms_body_is_list(b, ty)) {
        return false;
    }
    *element = ms_ty_args(&b->c->tys, ty)[0];
    return body_is_value_type(b, *element) || body_is_sized_number(b, *element) || ms_body_is_list(b, *element) ||
           body_is_own_nominal(b, *element);
}

/* `for name in a..b` over Int bounds: the parser writes the range as a call of `range`. The
 * loop variable is an immutable Int that lives for the body. */
static bool body_for_statement(MsBody *b, const MsStmt *s) {
    const MsExpr *iter = s->u.each.iter;
    MsTy element = b->int_ty;
    if (iter->kind == MS_E_CALL && iter->u.call.args.len == 2 && body_is_range(b, iter->u.call.callee)) {
        for (uint32_t i = 0; i < 2; i++) {
            const MsArg *bound = &iter->u.call.args.ptr[i];
            if (bound->has_name || ms_body_expr(b, bound->value, b->int_ty) == MS_TY_NONE) {
                (void)ms_body_unsupported(b);
                return true;
            }
        }
        // The call itself stays untyped: the standard library's signatures are not resolved here yet.
        b->facts->call_callee[iter->id] = ms_map_get(&b->c->mods[b->module].names, iter->u.call.callee->u.sym);
    } else if (body_for_list_element(b, iter, &element)) {
        b->facts->each_list[s->id] = true;
    } else {
        (void)ms_body_unsupported(b);
        return true;
    }
    const uint32_t scope_start = b->facts->bindings.count;
    (void)ms_body_bind(b, s->u.each.name, element, s->id, s->pos, 0, MS_ROLE_LOOP);
    const uint32_t outer_breaks = b->breaks;
    b->breaks = 0;
    b->loop_depth++;
    if (b->supported) {
        (void)ms_body_block(b, &s->u.each.body);
    }
    b->loop_depth--;
    b->breaks = outer_breaks;
    body_close_scope(b, scope_start);
    return true; // a range ends
}

/* `break` and `continue` leave the innermost loop; outside one they are a diagnostic. */
static void body_jump_statement(MsBody *b, const MsStmt *s) {
    if (b->loop_depth == 0) {
        (void)ms_body_unsupported(b);
        return;
    }
    b->breaks += s->kind == MS_S_BREAK;
}

/* Checks the statements in the current scope; whether control falls out of the end. A statement after
 * one that never falls through is still checked, but it neither makes the block fall through again nor
 * counts its `break`s toward the enclosing loop. */
static bool body_run(MsBody *b, const MsStmts *body) {
    bool falls = true;
    for (uint32_t i = 0; i < body->len && b->supported; i++) {
        const MsStmt *s = body->ptr[i];
        const uint32_t breaks = b->breaks;
        bool normal = true;
        switch ((MsStmtKind)s->kind) {
        case MS_S_BIND: body_bind_statement(b, s); break;
        case MS_S_RETURN:
            body_return_statement(b, s);
            normal = false;
            break;
        case MS_S_IF: normal = body_if_statement(b, s); break;
        case MS_S_WHILE: normal = body_while_statement(b, s); break;
        case MS_S_ASSIGN: body_assign_statement(b, s); break;
        case MS_S_BREAK:
        case MS_S_CONTINUE:
            body_jump_statement(b, s);
            normal = false;
            break;
        case MS_S_CALL: normal = body_call_statement(b, s); break;
        case MS_S_FOR: normal = body_for_statement(b, s); break;
        }
        if (!falls) {
            b->breaks = breaks;
        }
        falls = falls && normal;
    }
    return falls;
}

static void body_close_scope(MsBody *b, uint32_t scope_start) {
    for (uint32_t i = scope_start; i < b->facts->bindings.count; i++) {
        b->closed[i] = true;
    }
}

bool ms_body_block(MsBody *b, const MsStmts *body) {
    const uint32_t scope_start = b->facts->bindings.count;
    const bool falls = body_run(b, body);
    body_close_scope(b, scope_start);
    return falls;
}

MsTy ms_body_block_value(MsBody *b, const MsStmts *body, const MsExpr *value, MsTy expected) {
    const uint32_t scope_start = b->facts->bindings.count;
    const bool falls = body_run(b, body);
    MsTy ty = MS_TY_NONE;
    if (b->supported && falls) {
        ty = ms_body_expr(b, value, expected);
    } else {
        (void)ms_body_unsupported(b);
    }
    body_close_scope(b, scope_start);
    return ty;
}

/* A function that returns a value must end every path with a `return`; the diagnostic is at
 * the declaration. */
static void body_statements(MsBody *b, const MsStmts *body, MsPos declaration) {
    const bool falls = ms_body_block(b, body);
    if (!b->supported || !falls || body_returns_nothing(b)) {
        return;
    }
    const MsStr result = body_show(b, b->result);
    body_report(b, declaration,
                ms_arena_fmt(&b->c->arena,
                             "reachable fallthrough in function returning %.*s; end every path with 'return <%.*s>' (or "
                             "make the last branch return)",
                             (int)result.len, result.ptr, (int)result.len, result.ptr));
}

/* ---- functions ---- */

/* Reports the diagnostics a claimed function collected, from `first` on. */
static void body_commit_diags(MsBody *b, size_t first) {
    const MsCheckDiag *diags = ms_buf_items(&b->diags);
    for (size_t i = first; i < MS_VEC_LEN(b->diags, MsCheckDiag); i++) {
        ms_report(b->c, b->module, &diags[i]);
    }
    b->diags.len = first * sizeof(MsCheckDiag);
}

static void body_undo(MsBody *b, uint32_t first_binding, size_t written_start, size_t diags_start) {
    const uint32_t *ids = ms_buf_items(&b->written);
    for (size_t i = written_start; i < MS_VEC_LEN(b->written, uint32_t); i++) {
        b->facts->expr_ty[ids[i]] = MS_TY_NONE;
        b->facts->res_kind[ids[i]] = MS_RES_NONE;
        b->facts->res_ref[ids[i]] = MS_NONE;
        b->facts->call_callee[ids[i]] = MS_NONE;
        b->facts->const_use[ids[i]] = false;
    }
    b->written.len = written_start * sizeof(uint32_t);
    b->diags.len = diags_start * sizeof(MsCheckDiag);
    b->facts->bindings.count = first_binding;
}

/* A parameter has no default, the `none` of an `Optional` (which `T?` implies), or a literal of
 * its own type (checked with the body, where its node gets a type). */
static bool body_default_fits(const MsBody *b, const MsParam *p, MsTy ty) {
    if (p->def == NULL) {
        return true;
    }
    switch ((MsExprKind)p->def->kind) {
    case MS_E_NAME: return ms_name_is(b->c->names, p->def->u.sym, "none") && body_is_optional(b, ty);
    case MS_E_NUMBER: return ty == b->int_ty || ty == b->float_ty;
    case MS_E_BOOL: return ty == b->bool_ty;
    case MS_E_TEXT: return ty == b->string_ty && p->def->u.text.len == 1 && p->def->u.text.ptr[0].expr == NULL;
    case MS_E_CALL: // a construction or call: checked with the body (an unchecked default refuses the function)
    case MS_E_LIST: return true;
    default: return false;
    }
}

static bool body_signature_supported(const MsBody *b, const MsFunc *fn, MsTy sig) {
    const MsTyTable *tys = &b->c->tys;
    if (ms_ty_kind(tys, sig) != MS_K_FUNCTION || tys->nparams[sig] != fn->params.len) {
        return false;
    }
    const MsTy result = tys->result[sig];
    if (!body_is_bindable(b, result) && result != b->void_ty) {
        return false;
    }
    // Defaults of type parameters and a required parameter after a defaulted one are declaration
    // diagnostics of the Rust checker, which reports them with the function.
    for (uint32_t i = 0; i < fn->type_params.len; i++) {
        if (fn->type_params.ptr[i]->def != NULL) {
            return false;
        }
    }
    bool defaulted = false;
    for (uint32_t i = 0; i < fn->params.len; i++) {
        if (fn->params.ptr[i]->def != NULL) {
            defaulted = true;
        } else if (defaulted) {
            return false;
        }
    }
    const MsTyParam *params = ms_ty_params(tys, sig);
    for (uint32_t i = 0; i < fn->params.len; i++) {
        const MsParam *p = fn->params.ptr[i];
        if (!body_default_fits(b, p, params[i].ty) || !body_is_bindable(b, params[i].ty)) {
            return false;
        }
    }
    return true;
}

/* The types a public signature mentions, each once, depth first: `ty`, its arguments, its
 * parameters, then its result. A type this module declares without `export` cannot be named by
 * the callers, which is reported at the declaration. */
typedef struct BodySeen {
    MsTy ty[32];
    uint32_t count;
} BodySeen;

static void body_expose(MsBody *b, MsTy ty, MsPos pos, BodySeen *seen) {
    const MsTyTable *tys = &b->c->tys;
    if (ty == MS_TY_NONE || seen->count == sizeof seen->ty / sizeof seen->ty[0]) {
        return;
    }
    for (uint32_t i = 0; i < seen->count; i++) {
        if (seen->ty[i] == ty) {
            return;
        }
    }
    seen->ty[seen->count++] = ty;
    const MsSyms *syms = &b->c->syms;
    const uint32_t def = tys->def[ty];
    if (def != 0 && def - 1 < syms->count && syms->module[def - 1] == b->module && !syms->is_exported[def - 1]) {
        const MsStr name = ms_name(b->c->names, syms->name[def - 1]);
        const MsStr message = ms_arena_fmt(&b->c->arena,
                                           "public signature exposes private type %.*s; add 'export' to its "
                                           "declaration or keep the function private",
                                           (int)name.len, name.ptr);
        body_report(b, pos, message);
    }
    for (uint32_t i = 0; i < tys->nargs[ty]; i++) {
        body_expose(b, ms_ty_args(tys, ty)[i], pos, seen);
    }
    if (ms_ty_kind(tys, ty) == MS_K_FUNCTION) {
        for (uint32_t i = 0; i < tys->nparams[ty]; i++) {
            body_expose(b, ms_ty_params(tys, ty)[i].ty, pos, seen);
        }
        body_expose(b, tys->result[ty], pos, seen);
    }
}

/* The fixture factory of a module with tests has a declaration check of its own (it must return
 * a type that implements the test hooks), which this pass does not make. */
static bool body_is_test_fixture(const MsBody *b, const MsFunc *fn) {
    if (!ms_name_is(b->c->names, fn->name, "make_fixture")) {
        return false;
    }
    const MsModule *syntax = b->c->mods[b->module].syntax;
    for (uint32_t i = 0; i < syntax->ndecls; i++) {
        if (syntax->decls[i]->kind == MS_D_TEST) {
            return true;
        }
    }
    return false;
}

/* The receiver of a method: `self`, of the receiver's type, borrowed unless the method is `var`. */
typedef struct BodySelf {
    MsTy ty;
    bool mutating;
} BodySelf;

/* Checks one function or method body; `node` is the declaration node that `body_checked` and the
 * bindings' `callable` name. */
static void body_check_callable(MsBody *b, uint32_t node, MsPos pos, bool exported, const MsFunc *fn, MsTy sig,
                                const BodySelf *self) {
    if (fn->external) {
        return;
    }
    if (!body_signature_supported(b, fn, sig)) {
        b->facts->refusal[node] = (MsSite){__FILE__, (uint32_t)__LINE__};
        return;
    }
    const uint32_t first_binding = b->facts->bindings.count;
    const size_t written_start = MS_VEC_LEN(b->written, uint32_t);
    const size_t diags_start = MS_VEC_LEN(b->diags, MsCheckDiag);
    b->first_binding = first_binding;
    b->function = node;
    b->supported = true;
    b->result = b->c->tys.result[sig];
    if (exported) {
        BodySeen seen = {.count = 0};
        body_expose(b, sig, pos, &seen);
    }
    if (self != NULL) {
        (void)ms_body_bind(b, ms_intern_cstr(b->c->names, "self"), self->ty, node, pos,
                           self->mutating ? MS_BIND_MUTABLE : 0, MS_ROLE_SELF);
    }
    const MsTyParam *params = ms_ty_params(&b->c->tys, sig);
    for (uint32_t i = 0; i < fn->params.len && b->supported; i++) {
        const uint8_t flags = (params[i].flags & MS_PARAM_VAR) != 0 ? MS_BIND_MUTABLE : 0;
        (void)ms_body_bind(b, params[i].name, params[i].ty, fn->params.ptr[i]->id, fn->params.ptr[i]->pos, flags, MS_ROLE_PARAM);
    }
    for (uint32_t i = 0; i < fn->params.len && b->supported; i++) {
        const MsExpr *def = fn->params.ptr[i]->def;
        if (def != NULL && def->kind != MS_E_NAME && ms_body_expr(b, def, params[i].ty) != params[i].ty) {
            (void)ms_body_unsupported(b);
        }
    }
    if (b->supported) {
        body_statements(b, &fn->body, pos);
    }
    if (b->supported) {
        b->facts->body_checked[node] = true;
        body_commit_diags(b, diags_start);
    } else {
        b->facts->refusal[node] = b->gave_up;
        body_undo(b, first_binding, written_start, diags_start);
    }
}

/* `Result[Void, Error]`, the outcome of a test block, or MS_TY_NONE when the library lacks either. */
static MsTy body_test_outcome(MsBody *b) {
    const MsSymId result = ms_map_get(&b->c->std_types, ms_intern_cstr(b->c->names, "Result"));
    const MsSymId error = ms_map_get(&b->c->std_types, ms_intern_cstr(b->c->names, "Error"));
    if (result == MS_NONE || error == MS_NONE || b->c->syms.ty[result] == MS_TY_NONE || b->c->syms.ty[error] == MS_TY_NONE) {
        return MS_TY_NONE;
    }
    const MsTy args[2] = {b->void_ty, b->c->syms.ty[error]};
    return ms_ty_apply(b->c, b->c->syms.ty[result], args, 2);
}

/* `Void!`: a `Result[Void, Error]` written out. */
static bool body_is_void_result_ref(const MsBody *b, const MsTypeRef *t) {
    return t != NULL && t->kind == MS_TYPE_NAMED && ms_name_is(b->c->names, t->name, "Result") && t->args.len == 2 &&
           t->args.ptr[0]->kind == MS_TYPE_NAMED && ms_name_is(b->c->names, t->args.ptr[0]->name, "Void") &&
           t->args.ptr[1]->kind == MS_TYPE_NAMED && ms_name_is(b->c->names, t->args.ptr[1]->name, "Error");
}

/* The type a valid `make_fixture` returns: a plain record of this module whose hooks (`before_all`,
 * `before_each`, `after_each`, `after_all`), where it declares them, are `var fn name() Void!`. A factory the
 * Rust checker would reject, or a hook it would, leaves the module's tests and factory unchecked here. */
static MsTy body_fixture_type(const MsBody *b) {
    const MsModule *syntax = b->c->mods[b->module].syntax;
    const MsDecl *factory = NULL;
    for (uint32_t i = 0; i < syntax->ndecls; i++) {
        const MsDecl *d = syntax->decls[i];
        if (d->kind == MS_D_FN && !d->synthetic && ms_name_is(b->c->names, d->u.fn.name, "make_fixture")) {
            factory = d;
        }
    }
    const MsSymId sym = factory == NULL ? MS_NONE : ms_decl_own_symbol(b->c, b->module, factory);
    if (sym == MS_NONE || factory->u.fn.type_params.len != 0 || factory->u.fn.params.len != 0) {
        return MS_TY_NONE;
    }
    const MsTyTable *tys = &b->c->tys;
    const MsTy sig = b->c->syms.ty[sym];
    if (sig == MS_TY_NONE || ms_ty_kind(tys, sig) != MS_K_FUNCTION) {
        return MS_TY_NONE;
    }
    const MsTy result = tys->result[sig];
    const uint32_t def = result == MS_TY_NONE ? 0 : tys->def[result];
    if (def == 0 || ms_ty_kind(tys, result) != MS_K_TYPE || tys->nargs[result] != 0 || b->c->syms.module[def - 1] != b->module ||
        !body_is_bindable(b, result)) {
        return MS_TY_NONE;
    }
    static const char *const hooks[] = {"before_all", "before_each", "after_each", "after_all"};
    const MsSym type_name = b->c->syms.name[def - 1];
    for (uint32_t i = 0; i < syntax->ndecls; i++) {
        const MsDecl *d = syntax->decls[i];
        if (d->kind != MS_D_IMPL || d->u.impl.contract != NULL || d->u.impl.receiver == NULL || d->u.impl.receiver->name != type_name) {
            continue;
        }
        for (uint32_t m = 0; m < d->u.impl.methods.len; m++) {
            const MsMethod *method = d->u.impl.methods.ptr[m];
            for (size_t h = 0; h < MS_COUNT_OF(hooks); h++) {
                if (ms_name_is(b->c->names, method->func.name, hooks[h]) &&
                    (!method->mutating || method->consuming || method->func.params.len != 0 || method->func.type_params.len != 0 ||
                     !body_is_void_result_ref(b, method->func.result))) {
                    return MS_TY_NONE;
                }
            }
        }
    }
    return result;
}

/* A `test` block is a function of no parameters returning `Result[Void, Error]`. A module with a fixture
 * factory binds `fixture` in its tests, which this pass does not model. */
static void body_check_test(MsBody *b, const MsDecl *d) {
    const MsModule *syntax = b->c->mods[b->module].syntax;
    for (uint32_t i = 0; b->fixture == MS_TY_NONE && i < syntax->ndecls; i++) {
        if (syntax->decls[i]->kind == MS_D_FN && ms_name_is(b->c->names, syntax->decls[i]->u.fn.name, "make_fixture")) {
            return; // a factory this pass does not accept
        }
    }
    const MsTy outcome = body_test_outcome(b);
    if (outcome == MS_TY_NONE) {
        return;
    }
    const uint32_t first_binding = b->facts->bindings.count;
    const size_t written_start = MS_VEC_LEN(b->written, uint32_t);
    const size_t diags_start = MS_VEC_LEN(b->diags, MsCheckDiag);
    b->first_binding = first_binding;
    b->function = d->id;
    b->supported = true;
    b->result = outcome;
    // A test (not a benchmark) reads the file's fixture.
    if (b->fixture != MS_TY_NONE && !d->u.test.bench) {
        (void)ms_body_bind(b, ms_intern_cstr(b->c->names, "fixture"), b->fixture, d->id, d->pos, 0, MS_ROLE_PARAM);
    }
    body_statements(b, &d->u.test.body, d->pos);
    if (b->supported) {
        b->facts->body_checked[d->id] = true;
        body_commit_diags(b, diags_start);
    } else {
        body_undo(b, first_binding, written_start, diags_start);
    }
}

static void body_check_function(MsBody *b, const MsDecl *d, MsSymId sym) {
    if (!body_is_test_fixture(b, &d->u.fn) || b->fixture != MS_TY_NONE) {
        b->tparams = &d->u.fn.type_params;
        b->tvars = ms_def(b->c, sym)->vars;
        body_check_callable(b, d->id, d->pos, d->is_exported, &d->u.fn, b->c->syms.ty[sym], NULL);
        b->tparams = NULL;
        b->tvars = NULL;
    }
}

/* The methods an impl of this module writes, each against its row of the method table: `self` of
 * the receiver's type, then the parameters of the row's signature. A method that moves its
 * receiver, a generic impl or method, and a receiver the pass cannot hold stay with the Rust checker. */
static void body_check_methods(MsBody *b) {
    if (b->methods == NULL) {
        return;
    }
    const MsMethods *m = &b->methods->methods;
    const MsMethod **rows = ms_method_rows(b->c, b->module, m, NULL);
    for (uint32_t i = 0; i < m->count; i++) {
        const MsMethod *method = rows[i];
        if (method == NULL ||
            !body_is_admitted(b, m->receiver[i])) {
            continue;
        }
        // A method written once for a set of receivers is expanded into one copy per member, all
        // at the same position: the original is the one Rust checks, so the copies are left to it.
        bool shared = false;
        for (uint32_t k = 0; k < m->count; k++) {
            shared = shared || (k != i && rows[k] != NULL && rows[k]->pos.offset == method->pos.offset);
        }
        if (shared) {
            continue;
        }
        // A diagnostic already reported at the method's name is a declaration problem the Rust
        // checker words and places; the body stays with it.
        const MsModuleRow *row = &b->c->mods[b->module];
        bool reported = false;
        for (uint32_t k = 0; k < row->ndiags; k++) {
            reported = reported || row->diags[k].diag.pos.offset == method->pos.offset;
        }
        if (reported) {
            continue;
        }
        const BodySelf self = {.ty = m->receiver[i], .mutating = (m->access[i] & MS_METHOD_MUTATING) != 0};
        body_check_callable(b, method->id, method->pos, false, &method->func, m->ty[i], &self);
    }
}

static void body_allocate(MsBody *b, MsFacts *facts) {
    MsArena *arena = &b->c->arena;
    const size_t nodes = (size_t)facts->node_count + 1;
    b->closed = MS_NEW_N(arena, bool, nodes);
    memset(b->closed, 0, nodes * sizeof *b->closed);
    facts->expr_ty = MS_NEW_N(arena, MsTy, nodes);
    facts->res_kind = MS_NEW_N(arena, uint8_t, nodes);
    facts->res_ref = MS_NEW_N(arena, uint32_t, nodes);
    facts->pattern_binding = MS_NEW_N(arena, uint32_t, nodes);
    facts->arm_case = MS_NEW_N(arena, uint32_t, nodes);
    memset(facts->arm_case, 0xff, nodes * sizeof *facts->arm_case);
    facts->arm_contract = MS_NEW_N(arena, MsTy, nodes);
    memset(facts->arm_contract, 0, nodes * sizeof *facts->arm_contract);
    facts->body_checked = MS_NEW_N(arena, bool, nodes);
    facts->refusal = MS_NEW_N(arena, MsSite, nodes);
    memset(facts->refusal, 0, nodes * sizeof *facts->refusal);
    facts->param_consumed = MS_NEW_N(arena, uint32_t, nodes);
    memset(facts->param_consumed, 0, nodes * sizeof *facts->param_consumed);
    facts->ret_borrowed = MS_NEW_N(arena, bool, nodes);
    memset(facts->ret_borrowed, 0, nodes * sizeof *facts->ret_borrowed);
    facts->const_use = MS_NEW_N(arena, bool, nodes);
    memset(facts->const_use, 0, nodes * sizeof *facts->const_use);
    facts->call_callee = MS_NEW_N(arena, uint32_t, nodes);
    memset(facts->call_callee, 0xff, nodes * sizeof *facts->call_callee);
    facts->call_owned_borrow = MS_NEW_N(arena, uint8_t, nodes);
    facts->call_owned_param = MS_NEW_N(arena, uint32_t, nodes);
    memset(facts->call_owned_borrow, 0, nodes * sizeof *facts->call_owned_borrow);
    memset(facts->call_owned_param, 0, nodes * sizeof *facts->call_owned_param);
    facts->call_method = MS_NEW_N(arena, uint32_t, nodes);
    facts->call_receiver = MS_NEW_N(arena, MsTy, nodes);
    facts->call_interface = MS_NEW_N(arena, MsTy, nodes);
    memset(facts->call_method, 0xff, nodes * sizeof *facts->call_method);
    facts->text_method = MS_NEW_N(arena, uint32_t, nodes);
    memset(facts->text_method, 0xff, nodes * sizeof *facts->text_method);
    memset(facts->call_receiver, 0, nodes * sizeof *facts->call_receiver);
    memset(facts->call_interface, 0, nodes * sizeof *facts->call_interface);
    facts->call_type_args_at = MS_NEW_N(arena, uint32_t, nodes);
    facts->call_type_args_len = MS_NEW_N(arena, uint32_t, nodes);
    memset(facts->call_type_args_at, 0, nodes * sizeof *facts->call_type_args_at);
    memset(facts->call_type_args_len, 0, nodes * sizeof *facts->call_type_args_len);
    facts->lambda_first = MS_NEW_N(arena, uint32_t, nodes);
    memset(facts->lambda_first, 0xff, nodes * sizeof *facts->lambda_first);
    facts->each_list = MS_NEW_N(arena, bool, nodes);
    memset(facts->each_list, 0, nodes * sizeof *facts->each_list);
    facts->call_borrows = MS_NEW_N(arena, bool, nodes);
    memset(facts->call_borrows, 0, nodes * sizeof *facts->call_borrows);
    facts->field_store_root = MS_NEW_N(arena, uint32_t, nodes);
    memset(facts->field_store_root, 0xff, nodes * sizeof *facts->field_store_root);
    facts->coerce_iface = MS_NEW_N(arena, MsTy, nodes);
    memset(facts->coerce_iface, 0, nodes * sizeof *facts->coerce_iface);
    facts->call_reordered = MS_NEW_N(arena, bool, nodes);
    memset(facts->call_reordered, 0, nodes * sizeof *facts->call_reordered);
    facts->some_wrap = MS_NEW_N(arena, bool, nodes);
    memset(facts->some_wrap, 0, nodes * sizeof *facts->some_wrap);
    facts->moved_out = MS_NEW_N(arena, bool, nodes);
    memset(facts->moved_out, 0, nodes * sizeof *facts->moved_out);
    facts->borrowed_match = MS_NEW_N(arena, bool, nodes);
    memset(facts->borrowed_match, 0, nodes * sizeof *facts->borrowed_match);
    facts->assign_binding = MS_NEW_N(arena, uint32_t, nodes);
    memset(facts->assign_binding, 0xff, nodes * sizeof *facts->assign_binding);
    memset(facts->expr_ty, 0, nodes * sizeof *facts->expr_ty);
    memset(facts->res_kind, 0, nodes * sizeof *facts->res_kind);
    memset(facts->res_ref, 0xff, nodes * sizeof *facts->res_ref);
    memset(facts->pattern_binding, 0xff, nodes * sizeof *facts->pattern_binding);
    memset(facts->body_checked, 0, nodes * sizeof *facts->body_checked);
    // Every binding is introduced by its own syntax node, so a column per node holds them all.
    MsBindings *bindings = &facts->bindings;
    bindings->name = MS_NEW_N(arena, MsSym, nodes);
    bindings->ty = MS_NEW_N(arena, MsTy, nodes);
    bindings->decl_node = MS_NEW_N(arena, uint32_t, nodes);
    bindings->callable = MS_NEW_N(arena, uint32_t, nodes);
    bindings->reads = MS_NEW_N(arena, uint32_t, nodes);
    bindings->pos = MS_NEW_N(arena, MsPos, nodes);
    bindings->flags = MS_NEW_N(arena, uint8_t, nodes);
    bindings->role = MS_NEW_N(arena, uint8_t, nodes);
    bindings->conflict = MS_NEW_N(arena, uint8_t, nodes);
    bindings->conflict_ty = MS_NEW_N(arena, MsTy, nodes);
    bindings->count = 0;
}


/* Whether `name` is a module constant whose initializer this pass has already typed (constants are checked in
 * declaration order, so an earlier one): a use of it is a call of no arguments. */
static bool body_names_constant(const MsBody *b, MsSym name) {
    const MsSymId sym = ms_map_get(&b->c->mods[b->module].names, name);
    const MsSyms *syms = &b->c->syms;
    return sym != MS_NONE && syms->decl[sym] != NULL && syms->decl[sym]->kind == MS_D_CONST && syms->ty[sym] != MS_TY_NONE &&
           ms_body_find_binding(b, name) == MS_NONE;
}

/* How far a constant's initializer is from literals and operators. */
typedef enum BodyConstant { BODY_CONSTANT_OK, BODY_CONSTANT_REJECTED, BODY_CONSTANT_UNSURE } BodyConstant;

/* Walks an initializer in the order Rust does and stops at the first part that is not a literal
 * or an operator: a call, an index or a lambda is rejected at `*at`; a name, member or collection
 * is not classified here. */
static BodyConstant body_constant_kind(const MsBody *b, const MsExpr *e, const MsExpr **at) {
    switch ((MsExprKind)e->kind) {
    case MS_E_NUMBER:
    case MS_E_BOOL:
    case MS_E_VOID: return BODY_CONSTANT_OK;
    case MS_E_TEXT:
        for (uint32_t i = 0; i < e->u.text.len; i++) {
            const MsExpr *part = e->u.text.ptr[i].expr;
            const BodyConstant kind = part == NULL ? BODY_CONSTANT_OK : body_constant_kind(b, part, at);
            if (kind != BODY_CONSTANT_OK) {
                return kind;
            }
        }
        return BODY_CONSTANT_OK;
    case MS_E_UNARY: return body_constant_kind(b, e->u.bin.left, at);
    case MS_E_BINARY: {
        const BodyConstant left = body_constant_kind(b, e->u.bin.left, at);
        return left != BODY_CONSTANT_OK ? left : body_constant_kind(b, e->u.bin.right, at);
    }
    case MS_E_NAME: return body_names_constant(b, e->u.sym) ? BODY_CONSTANT_OK : BODY_CONSTANT_UNSURE;
    case MS_E_LIST:
        for (uint32_t i = 0; i < e->u.list.len; i++) {
            const BodyConstant kind = body_constant_kind(b, e->u.list.ptr[i], at);
            if (kind != BODY_CONSTANT_OK) {
                return kind;
            }
        }
        return BODY_CONSTANT_OK;
    case MS_E_MAP:
        for (uint32_t i = 0; i < e->u.map.len; i++) {
            const BodyConstant key = body_constant_kind(b, e->u.map.ptr[i].key, at);
            const BodyConstant value = key != BODY_CONSTANT_OK ? key : body_constant_kind(b, e->u.map.ptr[i].value, at);
            if (value != BODY_CONSTANT_OK) {
                return value;
            }
        }
        return BODY_CONSTANT_OK;
    case MS_E_MEMBER: return BODY_CONSTANT_UNSURE;
    case MS_E_APPLY:
    case MS_E_INDEX:
    case MS_E_PROBE:
    case MS_E_LAMBDA:
    case MS_E_CALL:
    case MS_E_MATCH: *at = e; return BODY_CONSTANT_REJECTED;
    }
    return BODY_CONSTANT_UNSURE;
}

/* A module constant `NAME := value` (or `NAME: Type := value`) whose initializer is literals and
 * operators. The Rust checker types it as a function of no parameters, in a scope of its own. */
static void body_check_constant(MsBody *b, const MsDecl *d, MsSymId sym) {
    const uint32_t first_binding = b->facts->bindings.count;
    const size_t written_start = MS_VEC_LEN(b->written, uint32_t);
    const size_t diags_start = MS_VEC_LEN(b->diags, MsCheckDiag);
    b->first_binding = first_binding;
    b->function = d->id;
    b->supported = true;
    MsTy expected = MS_TY_NONE;
    if (d->u.konst.ty != NULL) {
        expected = ms_body_annotation(b, d->u.konst.ty);
    }
    const MsExpr *rejected = NULL;
    const BodyConstant kind = body_constant_kind(b, d->u.konst.value, &rejected);
    const bool literal = kind == BODY_CONSTANT_OK;
    MsTy ty = MS_TY_NONE;
    if (b->supported && kind == BODY_CONSTANT_REJECTED) {
        // Rust reports the first part and types the constant `<invalid>`, which silences its uses.
        body_report(b, rejected->pos,
                    ms_arena_fmt(&b->c->arena, "a constant takes literals, operators, collections, and other constants; "
                                                   "compute this value in a function"));
        ty = b->invalid_ty;
    } else if (b->supported && literal) {
        ty = ms_body_expr(b, d->u.konst.value, expected);
    }
    if (b->supported && (literal || kind == BODY_CONSTANT_REJECTED) && (ty == b->invalid_ty || body_is_value_type(b, ty) || ms_body_is_list(b, ty) || ms_body_is_map(b, ty))) {
        b->facts->body_checked[d->id] = true;
        body_commit_diags(b, diags_start);
        // Like the Rust checker's, the constant's symbol is a function of no parameters.
        const MsSym fn = ms_intern_cstr(b->c->names, "fn");
        const MsTyDesc desc = {.name = fn, .id = fn, .kind = MS_K_FUNCTION, .result = ty};
        b->c->syms.ty[sym] = ms_ty_intern(&b->c->tys, &desc);
    } else {
        body_undo(b, first_binding, written_start, diags_start);
    }
}

/* The defaults of the record fields this module declares, each checked once here, where its names
 * resolve; a default outside what this pass handles stays unchecked and a construction leaving
 * that field out is left to the Rust checker. */
static void body_check_defaults(MsBody *b) {
    const MsModule *syntax = b->c->mods[b->module].syntax;
    for (uint32_t i = 0; i < syntax->ndecls; i++) {
        const MsDecl *d = syntax->decls[i];
        const MsSymId sym = d->kind == MS_D_TYPE && !d->synthetic ? ms_decl_own_symbol(b->c, b->module, d) : MS_NONE;
        if (sym == MS_NONE || b->c->syms.nvars[sym] != 0 || d->u.type.external || ms_def(b->c, sym)->nfields != d->u.type.fields.len) {
            continue;
        }
        // A default reads the fields declared before it; its mistakes are the type's, reported once.
        const uint32_t first_binding = b->facts->bindings.count;
        b->first_binding = first_binding;
        b->function = 0;
        b->result = MS_TY_NONE;
        for (uint32_t f = 0; f < d->u.type.fields.len; f++) {
            const MsParam *param = d->u.type.fields.ptr[f];
            const MsTy field = ms_def(b->c, sym)->fields[f].ty;
            if (param->def != NULL && body_is_bindable(b, field)) {
                const uint32_t bindings_start = b->facts->bindings.count;
                const size_t written_start = MS_VEC_LEN(b->written, uint32_t);
                const size_t diags_start = MS_VEC_LEN(b->diags, MsCheckDiag);
                b->supported = true;
                b->context = "";
                if (ms_body_expr(b, param->def, field) == MS_TY_NONE || !b->supported) {
                    body_undo(b, bindings_start, written_start, diags_start);
                } else {
                    body_commit_diags(b, diags_start);
                }
            }
            b->supported = true;
            if (!body_is_bindable(b, field)) {
                break; // a later default might read it
            }
            (void)ms_body_bind(b, ms_def(b->c, sym)->fields[f].name, field, param->id, param->pos,
                               param->is_mutable ? MS_BIND_MUTABLE : 0, MS_ROLE_PARAM);
        }
    }
}

void ms_module_check_bodies(MsCheck *c, MsModId module) {
    ms_module_check_bodies_with(c, module, NULL);
}

void ms_module_check_bodies_with(MsCheck *c, MsModId module, MsMethodTable *methods) {
    ms_module_resolve_types(c, module);
    const MsModId intrinsics = ms_map_get(&c->module_by_path, ms_intern_cstr(c->names, "@std/intrinsics.ms"));
    if (methods != NULL && intrinsics != MS_NONE) {
        ms_module_ensure_operations(c, intrinsics, methods); // what a primitive receiver offers
    }
    MsModuleRow *row = &c->mods[module];
    MsFacts *facts = row->facts;
    // A module that already ran its bodies keeps its facts.
    if (facts->body_checked != NULL) {
        return;
    }
    MsBody b = {.c = c,
              .module = module,
              .facts = facts,
              .int_ty = ms_check_primitive(c, "Int"),
              .float_ty = ms_check_primitive(c, "Float"),
              .bool_ty = ms_check_primitive(c, "Bool"),
              .string_ty = ms_check_primitive(c, "String"),
              .void_ty = ms_check_primitive(c, "Void"),
              .never_ty = ms_check_primitive(c, "Never"),
              .methods = methods,
              .invalid_ty = ms_check_invalid_ty(c)};
    body_allocate(&b, facts);
    b.fixture = body_fixture_type(&b);
    facts->methods = methods == NULL ? NULL : &methods->methods;
    b.literals = ms_literal_facts_new(&c->arena, c->names, facts->node_count);
    // Constants first: a function reads them wherever they are declared.
    for (uint32_t pass = 0; pass < 2; pass++) {
        if (pass == 1) {
            body_check_defaults(&b);
        }
        const MsDeclKind kind = pass == 0 ? MS_D_CONST : MS_D_FN;
        for (uint32_t i = 0; i < row->syntax->ndecls; i++) {
            const MsDecl *d = row->syntax->decls[i];
            const MsSymId sym = d->kind == kind && !d->synthetic ? ms_decl_own_symbol(c, module, d) : MS_NONE;
            if (sym == MS_NONE) {
                continue;
            }
            if (kind == MS_D_FN) {
                body_check_function(&b, d, sym);
            } else {
                body_check_constant(&b, d, sym);
            }
        }
    }
    for (uint32_t i = 0; i < row->syntax->ndecls; i++) {
        if (row->syntax->decls[i]->kind == MS_D_TEST) {
            body_check_test(&b, row->syntax->decls[i]);
        }
    }
    body_check_methods(&b);
    ms_buf_free(&b.written);
    ms_buf_free(&b.diags);
}
