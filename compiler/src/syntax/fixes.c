/* Machine-applicable fixes (ms/fixes.h). */
#include "ms/fixes.h"
#include "ms_rt/chars.h"

#include <string.h>

/* ---- text helpers over MsStr ---- */

static MsStr fix_text_of(const char *s) {
    return (MsStr){s, (uint32_t)strlen(s)};
}

static MsStr fix_trim_end_blank(MsStr s) {
    while (s.len > 0 && ms_ascii_is_space((uint8_t)s.ptr[s.len - 1])) {
        s.len--;
    }
    return s;
}

static bool fix_text_ends_with(MsStr s, MsStr suffix) {
    return ms_bytes_ends_with(ms_bytes_of((const uint8_t *)s.ptr, s.len), ms_bytes_of((const uint8_t *)suffix.ptr, suffix.len));
}

/* The offset of the first `needle` in `hay`. */
static bool fix_text_find(MsStr hay, MsStr needle, uint32_t *at) {
    size_t found = 0;
    if (!ms_bytes_find(ms_bytes_of((const uint8_t *)hay.ptr, hay.len), ms_bytes_of((const uint8_t *)needle.ptr, needle.len), &found)) {
        return false;
    }
    *at = (uint32_t)found;
    return true;
}

static MsStr fix_text_from(MsStr s, uint32_t from) {
    return (MsStr){s.ptr + from, s.len - from};
}

static MsStr fix_text_to(MsStr s, uint32_t to) {
    return (MsStr){s.ptr, to};
}

/* `s` after its first `separator`: Rust's `split_once(separator).1`. */
static bool fix_split_after(MsStr s, const char *separator, MsStr *rest) {
    MsStr sep = fix_text_of(separator);
    uint32_t at;
    if (!fix_text_find(s, sep, &at)) {
        return false;
    }
    *rest = fix_text_from(s, at + sep.len);
    return true;
}

/* Whether `index` is a character boundary of `s`, as `str::get` requires. */
static bool fix_on_boundary(MsStr s, uint32_t index) {
    return index == s.len || (index < s.len && ((uint8_t)s.ptr[index] & 0xC0U) != 0x80U);
}

/* The text `from..to` of the source; false when out of range or inside a character. */
static bool fix_source_range(MsStr source, uint32_t from, uint32_t to, MsStr *out) {
    if (from > to || to > source.len || !fix_on_boundary(source, from) || !fix_on_boundary(source, to)) {
        return false;
    }
    *out = (MsStr){source.ptr + from, to - from};
    return true;
}

static bool fix_is_digits(MsStr s) {
    for (uint32_t i = 0; i < s.len; i++) {
        if (s.ptr[i] < '0' || s.ptr[i] > '9') {
            return false;
        }
    }
    return s.len > 0;
}

/* ---- name fixes: fix_habits and hints ---- */

/* The single replacement a `did you mean` hint names, if exactly one. */
static bool fix_single_suggestion(MsStr message, MsStr *name) {
    MsStr rest;
    if (!fix_split_after(message, "; did you mean '", &rest)) {
        return false;
    }
    uint32_t quote;
    if (!fix_text_find(rest, fix_text_of("'"), &quote)) {
        return false;
    }
    MsStr tail = fix_text_from(rest, quote + 1);
    *name = fix_text_to(rest, quote);
    return tail.len == 1 && tail.ptr[0] == '?' && name->len > 0;
}

/* The import statement an `add: import` hint names. */
static bool fix_import_statement(MsStr message, MsStr *statement) {
    MsStr rest;
    if (!fix_split_after(message, "; add: ", &rest)) {
        return false;
    }
    uint32_t end = rest.len;
    (void)fix_text_find(rest, fix_text_of("\n"), &end);
    *statement = fix_trim_end_blank(fix_text_to(rest, end));
    return ms_str_starts_with(*statement, fix_text_of("import "));
}

typedef struct FixHabit {
    const char *from;
    const char *to;
} FixHabit;

static const FixHabit fix_habits[] = {
    {"Ok", "ok"},      {"Err", "error"},  {"err", "error"},  {"Error", "error"},
    {"True", "true"},  {"False", "false"}, {"nil", "none"},  {"null", "none"},
    {"None", "none"},  {"undefined", "none"},
};

/* The single spelling an `unknown binding` hint names for a habit from another language (`Ok`,
 * `Err`, `True`, `null`, `this`). */
static bool fix_habit_replacement(MsArena *arena, MsStr message, MsStr *replacement) {
    MsStr rest;
    if (!ms_str_starts_with(message, fix_text_of("unknown binding "))) {
        return false;
    }
    rest = fix_text_from(message, fix_text_of("unknown binding ").len);
    uint32_t at;
    if (!fix_text_find(rest, fix_text_of("; "), &at)) {
        return false;
    }
    MsStr name = fix_text_to(rest, at);
    MsStr hint = fix_text_from(rest, at + 2);
    for (size_t i = 0; i < MS_COUNT_OF(fix_habits); i++) {
        if (ms_str_equal(name, fix_text_of(fix_habits[i].from))) {
            *replacement = fix_text_of(fix_habits[i].to);
            return true;
        }
    }
    if (ms_str_equal(name, fix_text_of("this")) && fix_text_ends_with(hint, fix_text_of("write self instead of this"))) {
        *replacement = fix_text_of("self");
        return true;
    }
    MsStr member = ms_arena_fmt(arena, "so write self.%.*s", (int)name.len, name.ptr);
    if (!fix_text_ends_with(hint, member)) {
        return false;
    }
    *replacement = ms_arena_fmt(arena, "self.%.*s", (int)name.len, name.ptr);
    return true;
}

static MsFix fix_over_name(MsPos pos, size_t len, MsStr replacement) {
    uint32_t n = (uint32_t)len;
    MsPos end = {pos.offset + n, pos.line, pos.column + n};
    return (MsFix){pos, end, replacement};
}

bool ms_fix_for(MsArena *arena, MsStr message, MsPos pos, size_t len, MsFix *out) {
    MsStr text;
    if (fix_habit_replacement(arena, message, &text) || fix_single_suggestion(message, &text)) {
        *out = fix_over_name(pos, len, text);
        return true;
    }
    if (!fix_import_statement(message, &text)) {
        return false;
    }
    MsPos start = {0, 1, 1};
    *out = (MsFix){start, start, ms_arena_fmt(arena, "%.*s\n", (int)text.len, text.ptr)};
    return true;
}

/* ---- declaration fixes ---- */

/* How a declaration continues after its name: `name := v`, `name: T := v` or a parameter. */
typedef struct FixBindingTail {
    uint32_t length;   /* bytes of the source the fix replaces, from the name */
    bool typed_walrus; /* `name: T :=`: the replacement keeps the type text */
    uint32_t type_len; /* bytes between the name and the `:=` of a typed binding */
} FixBindingTail;

/* Reads `name: T := v` past the name: the walrus on the same line, not after a `,` or `)`. A
 * parameter `x: T` has no `:=` on its line and only gains `var`. */
static FixBindingTail fix_typed_binding(MsStr after, uint32_t name_len) {
    uint32_t line_end = after.len;
    (void)fix_text_find(after, fix_text_of("\n"), &line_end);
    MsStr line = fix_text_to(after, line_end);
    uint32_t walrus;
    if (!fix_text_find(line, fix_text_of(":="), &walrus)) {
        return (FixBindingTail){name_len, false, 0};
    }
    for (uint32_t i = 0; i < walrus; i++) {
        if (line.ptr[i] == ',' || line.ptr[i] == ')') {
            return (FixBindingTail){name_len, false, 0};
        }
    }
    return (FixBindingTail){name_len + walrus + 2, true, walrus};
}

bool ms_binding_to_var(MsArena *arena, MsStr source, MsPos decl, MsFix *out) {
    MsStr rest;
    if (!fix_source_range(source, decl.offset, source.len, &rest)) {
        return false;
    }
    uint32_t name_len = 0;
    while (name_len < rest.len && ms_ascii_is_ident((uint8_t)rest.ptr[name_len])) {
        name_len++;
    }
    if (name_len == 0) {
        return false;
    }
    MsStr name = fix_text_to(rest, name_len);
    MsStr after = fix_text_from(rest, name_len);
    uint32_t spaces = 0;
    while (spaces < after.len && after.ptr[spaces] == ' ') {
        spaces++;
    }
    MsStr here = fix_text_from(after, spaces);
    FixBindingTail tail;
    MsStr replacement;
    if (ms_str_starts_with(here, fix_text_of(":="))) {
        tail = (FixBindingTail){name_len + spaces + 2, false, 0};
        replacement = ms_arena_fmt(arena, "var %.*s =", (int)name.len, name.ptr);
    } else if (ms_str_starts_with(here, fix_text_of(":"))) {
        tail = fix_typed_binding(after, name_len);
        MsStr type_text = fix_trim_end_blank(fix_text_to(after, tail.type_len));
        replacement = tail.typed_walrus
                          ? ms_arena_fmt(arena, "var %.*s%.*s =", (int)name.len, name.ptr, (int)type_text.len,
                                         type_text.ptr)
                          : ms_arena_fmt(arena, "var %.*s", (int)name.len, name.ptr);
    } else {
        return false;
    }
    MsPos end = {decl.offset + tail.length, decl.line, decl.column + tail.length};
    *out = (MsFix){decl, end, replacement};
    return true;
}

bool ms_drop_case_parens(MsStr source, MsPos pos, MsStr name, MsFix *out) {
    MsStr rest;
    if (!fix_source_range(source, pos.offset, source.len, &rest) || !ms_str_starts_with(rest, name)) {
        return false;
    }
    if (!ms_str_starts_with(fix_text_from(rest, name.len), fix_text_of("()"))) {
        return false;
    }
    MsPos start = {pos.offset + name.len, pos.line, pos.column + name.len};
    MsPos end = {start.offset + 2, pos.line, start.column + 2};
    *out = (MsFix){start, end, fix_text_of("")};
    return true;
}

bool ms_is_compound_operator(MsStr source, MsPos pos, MsStr op) {
    uint64_t at = (uint64_t)pos.offset + op.len;
    return at < source.len && source.ptr[at] == '=';
}

/* ---- expression fixes ---- */

MsPos ms_expr_start(const MsExpr *e) {
    switch ((MsExprKind)e->kind) {
    case MS_E_MEMBER:
        return ms_expr_start(e->u.member.left);
    case MS_E_APPLY:
        return ms_expr_start(e->u.apply.left);
    case MS_E_INDEX:
    case MS_E_BINARY:
    case MS_E_PROBE:
        return ms_expr_start(e->u.bin.left);
    case MS_E_CALL:
        return ms_expr_start(e->u.call.callee);
    case MS_E_NUMBER:
    case MS_E_BOOL:
    case MS_E_VOID:
    case MS_E_TEXT:
    case MS_E_NAME:
    case MS_E_LIST:
    case MS_E_MAP:
    case MS_E_UNARY:
    case MS_E_LAMBDA:
    case MS_E_MATCH:
        break;
    }
    return e->pos;
}

/* The written expression: its range and text, and whether a `.method()` suffix binds to all of it
 * without parentheses. */
typedef struct FixExprText {
    MsPos pos, end;
    MsStr text;
    bool atomic;
} FixExprText;

static bool fix_is_atomic(const MsExpr *e) {
    switch ((MsExprKind)e->kind) {
    case MS_E_NAME:
    case MS_E_MEMBER:
    case MS_E_CALL:
    case MS_E_INDEX:
    case MS_E_APPLY:
    case MS_E_LIST:
    case MS_E_MAP:
        return true;
    case MS_E_NUMBER:
    case MS_E_BOOL:
    case MS_E_VOID:
    case MS_E_TEXT:
    case MS_E_PROBE:
    case MS_E_UNARY:
    case MS_E_BINARY:
    case MS_E_LAMBDA:
    case MS_E_MATCH:
        break;
    }
    return false;
}

static bool fix_expr_text(MsStr source, const MsExpr *e, FixExprText *out) {
    MsPos start = ms_expr_start(e);
    if (e->end.offset <= start.offset || !fix_source_range(source, start.offset, e->end.offset, &out->text)) {
        return false;
    }
    out->pos = start;
    out->end = e->end;
    out->atomic = fix_is_atomic(e);
    return true;
}

static MsFix fix_replace_expr(const FixExprText *t, MsStr replacement) {
    return (MsFix){t->pos, t->end, replacement};
}

/* `text.call`, or `(text).call` when the text does not bind as one operand. */
static MsStr fix_call_on(MsArena *arena, const FixExprText *t, MsStr call) {
    const char *open = t->atomic ? "" : "(";
    const char *close = t->atomic ? "" : ")";
    return ms_arena_fmt(arena, "%s%.*s%s.%.*s", open, (int)t->text.len, t->text.ptr, close, (int)call.len,
                        call.ptr);
}

bool ms_append_call(MsArena *arena, MsStr source, const MsExpr *e, MsStr call, MsFix *out) {
    FixExprText t;
    if (!fix_expr_text(source, e, &t)) {
        return false;
    }
    *out = fix_replace_expr(&t, fix_call_on(arena, &t, call));
    return true;
}

bool ms_append_parens(MsArena *arena, MsStr source, const MsExpr *e, MsFix *out) {
    FixExprText t;
    if (!fix_expr_text(source, e, &t) || !t.atomic) {
        return false;
    }
    *out = fix_replace_expr(&t, ms_arena_fmt(arena, "%.*s()", (int)t.text.len, t.text.ptr));
    return true;
}

bool ms_none_test(MsArena *arena, MsStr source, const MsExpr *whole, const MsExpr *other, bool present,
                  MsFix *out) {
    FixExprText range;
    FixExprText inner;
    if (!fix_expr_text(source, whole, &range) || !fix_expr_text(source, other, &inner)) {
        return false;
    }
    MsStr call = fix_text_of(present ? "is_some()" : "is_none()");
    *out = fix_replace_expr(&range, fix_call_on(arena, &inner, call));
    return true;
}

static bool fix_has_any_of(MsStr s, const char *set) {
    for (uint32_t i = 0; i < s.len; i++) {
        if (strchr(set, s.ptr[i]) != NULL) {
            return true;
        }
    }
    return false;
}

bool ms_interpolate(MsArena *arena, MsStr source, const MsExpr *e, MsFix *out) {
    FixExprText t;
    if (!fix_expr_text(source, e, &t)) {
        return false;
    }
    /* A plain integer literal is its own text; `f"{3}"` would read as a regex quantifier. */
    if (e->kind == MS_E_NUMBER && fix_is_digits(t.text)) {
        *out = fix_replace_expr(&t, ms_arena_fmt(arena, "\"%.*s\"", (int)t.text.len, t.text.ptr));
        return true;
    }
    if (fix_has_any_of(t.text, "\"{}\n")) {
        return false;
    }
    *out = fix_replace_expr(&t, ms_arena_fmt(arena, "f\"{%.*s}\"", (int)t.text.len, t.text.ptr));
    return true;
}

/* `3` becomes `3.0` for a plain decimal Int literal. */
static bool fix_float_literal(MsArena *arena, MsStr source, const MsExpr *e, MsFix *out) {
    FixExprText t;
    if (e->kind != MS_E_NUMBER || !fix_expr_text(source, e, &t) || !fix_is_digits(t.text)) {
        return false;
    }
    *out = fix_replace_expr(&t, ms_arena_fmt(arena, "%.*s.0", (int)t.text.len, t.text.ptr));
    return true;
}

bool ms_to_float(MsArena *arena, MsStr source, const MsExpr *e, MsFix *out) {
    return fix_float_literal(arena, source, e, out) || ms_append_call(arena, source, e, fix_text_of("to_float()"), out);
}

bool ms_conversion_fix(MsArena *arena, MsStr source, const MsExpr *e, MsStr actual, MsStr expected,
                       MsFix *out) {
    bool to_string = ms_str_equal(expected, fix_text_of("String"));
    if (ms_str_equal(actual, fix_text_of("Int")) && ms_str_equal(expected, fix_text_of("Float"))) {
        return ms_to_float(arena, source, e, out);
    }
    bool scalar = ms_str_equal(actual, fix_text_of("Int")) || ms_str_equal(actual, fix_text_of("Float")) ||
                  ms_str_equal(actual, fix_text_of("Bool"));
    if (scalar && to_string) {
        return ms_interpolate(arena, source, e, out);
    }
    bool error = ms_str_equal(expected, fix_text_of("Error")) || ms_str_equal(expected, fix_text_of("@std/Error"));
    FixExprText t;
    if (ms_str_equal(actual, fix_text_of("String")) && error && fix_expr_text(source, e, &t)) {
        *out = fix_replace_expr(&t, ms_arena_fmt(arena, "Error(%.*s)", (int)t.text.len, t.text.ptr));
        return true;
    }
    return false;
}
