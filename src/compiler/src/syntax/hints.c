/* Diagnostic wording helpers; see ms/hints.h. A port of the pure functions of
 * crates/ms-check/src/hints.rs: the same suggestions, in the same order. */
#include <stdlib.h>
#include <string.h>
#include "ms_rt/chars.h"

#include "ms/hints.h"

#define EMPTY_STR ((MsStr){"", 0})

bool ms_str_equal(MsStr a, MsStr b) {
    return a.len == b.len && memcmp(a.ptr, b.ptr, a.len) == 0;
}

/* Byte-wise order, which is how Rust orders strings. */
int ms_str_compare(MsStr a, MsStr b) {
    uint32_t common = a.len < b.len ? a.len : b.len;
    int order = common == 0 ? 0 : memcmp(a.ptr, b.ptr, common);
    if (order != 0) {
        return order;
    }
    if (a.len == b.len) {
        return 0;
    }
    return a.len < b.len ? -1 : 1;
}

bool ms_str_starts_with(MsStr s, MsStr prefix) {
    return s.len >= prefix.len && memcmp(s.ptr, prefix.ptr, prefix.len) == 0;
}

static MsStr str_from_buf(MsArena *arena, const MsBuf *b) {
    if (b->len == 0) {
        return EMPTY_STR;
    }
    return (MsStr){ms_arena_strndup(arena, b->data, b->len), (uint32_t)b->len};
}

static MsStr lowercase(MsArena *arena, MsStr s) {
    char *lower = ms_alloc(arena, (size_t)s.len + 1, 1);
    for (uint32_t i = 0; i < s.len; i++) {
        lower[i] = (char)ms_ascii_to_lower((uint8_t)s.ptr[i]);
    }
    lower[s.len] = 0;
    return (MsStr){lower, s.len};
}

/* ---- edit distance ---- */

/* The scalar values of `s`, in an arena array. */
static uint32_t *scalars_of(MsArena *arena, MsStr s, size_t *count) {
    uint32_t *out = MS_NEW_N(arena, uint32_t, (size_t)s.len + 1);
    size_t n = 0;
    size_t at = 0;
    while (at < s.len) {
        uint32_t scalar = 0;
        int width = ms_utf8_decode(s.ptr + at, s.len - at, &scalar);
        out[n++] = scalar;
        at += (size_t)width;
    }
    *count = n;
    return out;
}

size_t ms_edit_distance(MsArena *arena, MsStr a, MsStr b) {
    size_t nx = 0;
    size_t ny = 0;
    const uint32_t *x = scalars_of(arena, a, &nx);
    const uint32_t *y = scalars_of(arena, b, &ny);
    size_t *previous = MS_NEW_N(arena, size_t, ny + 1);
    size_t *current = MS_NEW_N(arena, size_t, ny + 1);
    for (size_t j = 0; j <= ny; j++) {
        previous[j] = j;
    }
    for (size_t i = 1; i <= nx; i++) {
        current[0] = i;
        for (size_t j = 1; j <= ny; j++) {
            size_t cost = x[i - 1] != y[j - 1];
            size_t best = previous[j] + 1;
            if (current[j - 1] + 1 < best) {
                best = current[j - 1] + 1;
            }
            if (previous[j - 1] + cost < best) {
                best = previous[j - 1] + cost;
            }
            current[j] = best;
        }
        size_t *swap = previous;
        previous = current;
        current = swap;
    }
    return previous[ny];
}

/* ---- closest ---- */

/* How near a candidate is: the distance, and whether it neither extends nor truncates the name. */
typedef struct Nearness {
    size_t distance;
    bool unrelated;
} Nearness;

static bool nearer(Nearness a, Nearness b) {
    return a.distance != b.distance ? a.distance < b.distance : (!a.unrelated && b.unrelated);
}

static bool same_nearness(Nearness a, Nearness b) {
    return a.distance == b.distance && a.unrelated == b.unrelated;
}

static size_t smaller(size_t a, size_t b) {
    return a < b ? a : b;
}

MsStr ms_closest(MsArena *arena, MsStr name, const MsStr *candidates, size_t count) {
    if (name.len < 3) {
        return EMPTY_STR;
    }
    /* A third of the name may differ, rounded down from `len + 1`: `--fix` applies the suggestion,
     * and `fail` -> `main` (two of four letters) rewrites a different function. A name that extends
     * or truncates the typed one (`testing` for `test`) keeps every typed letter, so it may differ
     * by a third rounded up. */
    size_t limit = smaller(((size_t)name.len + 1) / 3, 3);
    size_t prefix_limit = smaller(((size_t)name.len + 2) / 3, 3);
    MsStr lower_name = lowercase(arena, name);
    MsStr best = EMPTY_STR;
    Nearness best_nearness = {0, false};
    for (size_t i = 0; i < count; i++) {
        MsStr candidate = candidates[i];
        if (ms_str_equal(candidate, name)) {
            continue;
        }
        MsStr lower = lowercase(arena, candidate);
        Nearness nearness = {ms_edit_distance(arena, lower_name, lower),
                             !(ms_str_starts_with(lower_name, lower) || ms_str_starts_with(lower, lower_name))};
        if (nearness.distance > (nearness.unrelated ? limit : prefix_limit)) {
            continue;
        }
        bool better = best.len == 0 || nearer(nearness, best_nearness) ||
                      (same_nearness(nearness, best_nearness) && ms_str_compare(candidate, best) < 0);
        if (better) {
            best = candidate;
            best_nearness = nearness;
        }
    }
    return best;
}

MsStr ms_did_you_mean(MsArena *arena, MsStr name, const MsStr *candidates, size_t count) {
    MsStr match = ms_closest(arena, name, candidates, count);
    if (match.len == 0) {
        return EMPTY_STR;
    }
    return ms_arena_fmt(arena, "; did you mean '%.*s'?", (int)match.len, match.ptr);
}

/* ---- lists ---- */

int ms_str_compare_ptr(const void *a, const void *b) {
    return ms_str_compare(*(const MsStr *)a, *(const MsStr *)b);
}

size_t ms_unique_sorted(MsArena *arena, const MsStr *names, size_t count, MsStr **out) {
    MsStr *sorted = MS_NEW_N(arena, MsStr, count + 1);
    size_t kept = 0;
    for (size_t i = 0; i < count; i++) {
        if (names[i].len != 0) {
            sorted[kept++] = names[i];
        }
    }
    if (kept > 1) {
        qsort(sorted, kept, sizeof sorted[0], ms_str_compare_ptr);
    }
    size_t unique = 0;
    for (size_t i = 0; i < kept; i++) {
        if (unique == 0 || !ms_str_equal(sorted[unique - 1], sorted[i])) {
            sorted[unique++] = sorted[i];
        }
    }
    *out = sorted;
    return unique;
}

MsStr ms_hint_list(MsArena *arena, const MsStr *names, size_t count, size_t limit) {
    MsStr *sorted = NULL;
    size_t n = ms_unique_sorted(arena, names, count, &sorted);
    bool more = n > limit;
    if (more) {
        n = limit;
    }
    MsBuf out = {0};
    for (size_t i = 0; i < n; i++) {
        if (i != 0) {
            ms_buf_puts(&out, ", ");
        }
        ms_buf_put(&out, sorted[i].ptr, sorted[i].len);
    }
    if (more) {
        ms_buf_puts(&out, ", ...");
    }
    MsStr result = str_from_buf(arena, &out);
    ms_buf_free(&out);
    return result;
}

MsStr ms_type_sketch(MsArena *arena, MsStr name, size_t arity) {
    if (arity == 0) {
        return ms_arena_fmt(arena, "%.*s with no type arguments", (int)name.len, name.ptr);
    }
    MsBuf out = {0};
    ms_buf_put(&out, name.ptr, name.len);
    ms_buf_putc(&out, '[');
    for (size_t i = 0; i < arity; i++) {
        if (i != 0) {
            ms_buf_puts(&out, ", ");
        }
        ms_buf_putc(&out, 'T');
        ms_buf_putc(&out, (char)('1' + i));
    }
    ms_buf_putc(&out, ']');
    MsStr result = str_from_buf(arena, &out);
    ms_buf_free(&out);
    return result;
}

MsStr ms_plural(MsArena *arena, size_t count, const char *word) {
    return ms_arena_fmt(arena, count == 1 ? "%s" : "%ss", word);
}

/* ---- renamed modules ---- */

typedef struct Rename {
    const char *old_path, *new_path;
} Rename;

/* Standard modules that were renamed, with the module that replaces each. */
static const Rename renamed_modules[] = {
    {"@std/concurrency/flow.ms", "@std/concurrency/resilience.ms"},
};

const char *ms_renamed_module(MsStr path) {
    for (size_t i = 0; i < MS_COUNT_OF(renamed_modules); i++) {
        MsStr old = {renamed_modules[i].old_path, (uint32_t)strlen(renamed_modules[i].old_path)};
        if (ms_str_equal(old, path)) {
            return renamed_modules[i].new_path;
        }
    }
    return NULL;
}

/* The first occurrence of `needle` in `hay`, or SIZE_MAX. */
static size_t find_str(MsStr hay, MsStr needle) {
    if (needle.len > hay.len) {
        return SIZE_MAX;
    }
    for (size_t at = 0; at + needle.len <= hay.len; at++) {
        if (memcmp(hay.ptr + at, needle.ptr, needle.len) == 0) {
            return at;
        }
    }
    return SIZE_MAX;
}

bool ms_rename_module_path(MsArena *arena, MsStr source, MsPos from, MsStr old, MsStr new_path, MsFix *out) {
    size_t start = from.offset;
    bool on_boundary = start == source.len || (start < source.len && !ms_utf8_is_continuation((uint8_t)source.ptr[start]));
    if (start > source.len || !on_boundary) {
        return false;
    }
    MsStr rest = {source.ptr + start, (uint32_t)(source.len - start)};
    const char *newline = memchr(rest.ptr, '\n', rest.len);
    MsStr line = {rest.ptr, newline != NULL ? (uint32_t)(newline - rest.ptr) : rest.len};
    MsStr quoted = ms_arena_fmt(arena, "\"%.*s\"", (int)old.len, old.ptr);
    size_t at = find_str(line, quoted);
    if (at == SIZE_MAX) {
        return false;
    }
    uint32_t offset = (uint32_t)(start + at);
    uint32_t column = from.column + (uint32_t)at;
    out->pos = (MsPos){offset, from.line, column};
    out->end = (MsPos){offset + quoted.len, from.line, column + quoted.len};
    out->replacement = ms_arena_fmt(arena, "\"%.*s\"", (int)new_path.len, new_path.ptr);
    return true;
}

/* ---- member synonyms ---- */

typedef struct Synonym {
    const char *name;
    const char *replacements[3]; /* NULL ends the list */
} Synonym;

static const Synonym member_synonyms[] = {
    {"byte_length", {"length", NULL}},
    {"len", {"length", "scalar_length", NULL}},
    {"size", {"length", "scalar_length", NULL}},
    {"count", {"length", "scalar_length", NULL}},
    {"length", {"scalar_length", NULL}},
    {"push", {"append", "add", NULL}},
    {"add", {"append", NULL}},
    {"insert", {"append", "add", NULL}},
    {"delete", {"remove", NULL}},
    {"decode", {"to_string", NULL}},
    {"toString", {"to_string", NULL}},
    {"to_text", {"to_string", NULL}},
    {"includes", {"contains", NULL}},
    {"has", {"contains", NULL}},
    {"indexOf", {"index_of", NULL}},
    {"find_index", {"index_of", NULL}},
    {"reduce", {"fold", NULL}},
    {"each", {"for_each", NULL}},
    {"substring", {"slice", "view", NULL}},
    {"substr", {"slice", "view", NULL}},
    {"charAt", {"scalar_at", NULL}},
    {"char_at", {"scalar_at", NULL}},
    {"sort", {"sorted", NULL}},
    {"trim_left", {"trim_start", NULL}},
    {"trim_right", {"trim_end", NULL}},
    {"to_upper", {"upper", NULL}},
    {"to_lower", {"lower", NULL}},
    {"to_uppercase", {"upper", NULL}},
    {"to_lowercase", {"lower", NULL}},
    {"toUpperCase", {"upper", NULL}},
    {"toLowerCase", {"lower", NULL}},
    {"trimStart", {"trim_start", NULL}},
    {"trimEnd", {"trim_end", NULL}},
    {"to_int", {"parse_int", "truncate_to_int", NULL}},
    {"replace_all", {"replace", NULL}},
    {"replace_n", {"replace", "replace_first", NULL}},
};

/* `fooBar` -> `foo_bar`, or empty when `name` has no uppercase letter. */
static MsStr snake_case(MsArena *arena, MsStr name) {
    bool has_upper = false;
    for (uint32_t i = 0; i < name.len; i++) {
        has_upper = has_upper || ms_ascii_is_upper((uint8_t)name.ptr[i]);
    }
    if (!has_upper) {
        return EMPTY_STR;
    }
    MsBuf out = {0};
    for (uint32_t i = 0; i < name.len; i++) {
        if (ms_ascii_is_upper((uint8_t)name.ptr[i])) {
            ms_buf_putc(&out, '_');
        }
        ms_buf_putc(&out, (char)ms_ascii_to_lower((uint8_t)name.ptr[i]));
    }
    MsStr result = str_from_buf(arena, &out);
    ms_buf_free(&out);
    return result;
}

static bool contains_name(const MsStr *names, size_t count, MsStr name) {
    for (size_t i = 0; i < count; i++) {
        if (ms_str_equal(names[i], name)) {
            return true;
        }
    }
    return false;
}

static void put_quoted(MsBuf *out, MsStr name) {
    ms_buf_putc(out, '\'');
    ms_buf_put(out, name.ptr, name.len);
    ms_buf_putc(out, '\'');
}

MsStr ms_synonym_hint(MsArena *arena, MsStr name, const MsStr *available, size_t count) {
    MsBuf found = {0};
    size_t nfound = 0;
    MsStr snake = snake_case(arena, name);
    if (snake.len != 0 && contains_name(available, count, snake)) {
        put_quoted(&found, snake);
        nfound++;
    }
    for (size_t i = 0; i < MS_COUNT_OF(member_synonyms); i++) {
        if (strlen(member_synonyms[i].name) != name.len || memcmp(member_synonyms[i].name, name.ptr, name.len) != 0) {
            continue;
        }
        for (size_t k = 0; member_synonyms[i].replacements[k] != NULL; k++) {
            MsStr candidate = {member_synonyms[i].replacements[k], (uint32_t)strlen(member_synonyms[i].replacements[k])};
            for (size_t a = 0; a < count; a++) {
                if (!ms_str_equal(available[a], candidate)) {
                    continue;
                }
                if (nfound++ != 0) {
                    ms_buf_puts(&found, " or ");
                }
                put_quoted(&found, candidate);
            }
        }
    }
    MsStr result = EMPTY_STR;
    if (nfound != 0) {
        result = ms_arena_fmt(arena, "; did you mean %.*s?", (int)found.len, found.data);
    }
    ms_buf_free(&found);
    return result;
}

/* ---- type aliases ---- */

typedef struct TypeAlias {
    const char *spelling, *builtin;
} TypeAlias;

static const TypeAlias type_aliases[] = {
    {"Integer", "Int"}, {"long", "Int"}, {"Long", "Int"}, {"i64", "Int"}, {"int64", "Int"}, {"number", "Int"},
    {"Number", "Int"}, {"double", "Float"}, {"Double", "Float"}, {"f64", "Float"}, {"float64", "Float"},
    {"str", "String"}, {"Str", "String"}, {"string", "String"}, {"char", "String"}, {"Char", "String"},
    {"Text", "String"}, {"boolean", "Bool"}, {"Boolean", "Bool"}, {"bool", "Bool"}, {"void", "Void"},
    {"None", "Void"}, {"NoneType", "Void"}, {"Vec", "List"}, {"Vector", "List"}, {"Array", "List"},
    {"ArrayList", "List"}, {"array", "List"}, {"Dict", "Map"}, {"Dictionary", "Map"}, {"HashMap", "Map"},
    {"dict", "Map"}, {"TreeMap", "Map"}, {"HashSet", "Set"}, {"TreeSet", "Set"},
};

const char *ms_type_alias(MsStr name) {
    for (size_t i = 0; i < MS_COUNT_OF(type_aliases); i++) {
        MsStr spelling = {type_aliases[i].spelling, (uint32_t)strlen(type_aliases[i].spelling)};
        if (ms_str_equal(spelling, name)) {
            return type_aliases[i].builtin;
        }
    }
    return NULL;
}
