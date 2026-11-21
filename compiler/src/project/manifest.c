/* ms.toml (project.h): the subset of TOML a manifest uses (string values, inline tables of strings, arrays of
 * strings), and its validation. Port of crates/ms-driver/src/project/manifest.rs; messages and locations match it.
 * Anything this reader does not cover (dotted keys, `[dependencies.x]` tables, multi-line strings, TOML syntax errors)
 * fails as MS_PERR_UNSUPPORTED instead of guessing, so the Rust driver reports it. */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/lock.h"
#include "ms/project.h"
#include "project/host.h"
#include "ms/text.h"
#include "ms/resolve.h"

enum { MAX_LINE = 65535 };

typedef enum EntryKind { ENTRY_TABLE, ENTRY_PAIR } EntryKind;
typedef enum ValueKind { VALUE_STRING, VALUE_SCALAR, VALUE_ARRAY, VALUE_INLINE_TABLE } ValueKind;

/* An element of an array, or a `key = value` of an inline table (`key` is NULL in an array); `value` is NULL for a
 * number or boolean. */
typedef struct Field {
    const char *key;
    const char *value;
    bool control;
    MsPos pos;
} Field;

/* One table header or `key = "value"` of the document, in order. */
typedef struct Entry {
    EntryKind kind;
    const char *name; /* table name, or key */
    const char *value; /* a string; NULL for any other kind of value */
    const char *raw;   /* the text of a value that is not a string, for the error that asks for a string */
    ValueKind value_kind;
    const Field *fields; /* an array's elements or an inline table's fields */
    uint32_t nfields;
    bool control; /* the value holds a control character (even a NUL, which `value` cannot show) */
    MsPos key_pos, value_pos; /* the header for a table */
} Entry;

/* Where and why the syntax of the document first failed; the helpers note it and the document reader reports it. */
typedef struct Bad {
    size_t at;
    const char *reason;
} Bad;

typedef struct Reader {
    MsArena *arena;
    const char *text;
    size_t length;
    const char *file;
    MsProjectError *err;
    Bad *bad;
} Reader;

static MsPos manifest_locate(const char *text, size_t length, size_t offset) {
    if (offset > length) {
        offset = length;
    }
    MsPos pos = {.offset = (uint32_t)offset, .line = 1, .column = 1};
    size_t line_start = 0;
    for (size_t i = 0; i < offset; i++) {
        if (text[i] == '\n') {
            pos.line++;
            line_start = i + 1;
        }
    }
    pos.column = (uint32_t)(offset - line_start) + 1;
    return pos;
}

static bool manifest_fail_at(const Reader *r, MsPos pos, const char *message) {
    MsProjectError *cause = MS_NEW(r->arena, MsProjectError);
    ms_project_error_message(cause, message);
    *r->err = (MsProjectError){.kind = MS_PERR_MANIFEST, .file = r->file, .line = pos.line, .column = pos.column, .offset = pos.offset, .cause = cause};
    return false;
}

static bool manifest_fail_wrapped(const Reader *r, MsPos pos, const MsProjectError *cause) {
    MsProjectError *copy = MS_NEW(r->arena, MsProjectError);
    *copy = *cause;
    *r->err = (MsProjectError){.kind = MS_PERR_MANIFEST, .file = r->file, .line = pos.line, .column = pos.column, .offset = pos.offset, .cause = copy};
    return false;
}

/* Notes the first reason the syntax failed, at `at`. */
static bool manifest_bad(const Reader *r, size_t at, const char *reason) {
    if (r->bad->reason == NULL) {
        r->bad->at = at;
        r->bad->reason = reason;
    }
    return false;
}

/* The syntax error of the document: the reason a helper noted, else `reason` at `at`. */
static bool manifest_invalid(const Reader *r, size_t at, const char *reason) {
    if (r->bad->reason != NULL) {
        at = r->bad->at;
        reason = r->bad->reason;
    }
    return manifest_fail_at(r, manifest_locate(r->text, r->length, at), ms_arena_fmt(r->arena, "invalid ms.toml: %s", reason).ptr);
}

/* ---- reading the document ---- */

static int manifest_hex_digit(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

/* A quoted string at text[*at] on one line; *at moves past the closing quote. False for anything else. */
static bool manifest_read_string(const Reader *r, size_t *at, const char **out, bool *control) {
    const char quote = r->text[*at];
    size_t i = *at + 1;
    if (i + 1 < r->length && r->text[i] == quote && r->text[i + 1] == quote) {
        return manifest_bad(r, *at, "multi-line strings are not supported in ms.toml");
    }
    MsBuf value = {0};
    for (;;) {
        if (i >= r->length || r->text[i] == '\n' || r->text[i] == '\r') {
            ms_buf_free(&value);
            return manifest_bad(r, *at, "unterminated string");
        }
        const char c = r->text[i++];
        if (c == quote) {
            break;
        }
        if (quote == '"' && c == '\\') {
            if (i >= r->length) {
                ms_buf_free(&value);
                return manifest_bad(r, *at, "unterminated string");
            }
            const char e = r->text[i++];
            const char *plain = strchr("btnfr\"\\", e);
            if (plain != NULL && e != 0) {
                ms_buf_putc(&value, "\b\t\n\f\r\"\\"[plain - "btnfr\"\\"]);
            } else if (e == 'u' || e == 'U') {
                const size_t digits = e == 'u' ? 4 : 8;
                uint32_t scalar = 0;
                for (size_t d = 0; d < digits; d++) {
                    const int h = i + d < r->length ? manifest_hex_digit(r->text[i + d]) : -1;
                    if (h < 0) {
                        ms_buf_free(&value);
                        return manifest_bad(r, i - 2, "invalid Unicode escape");
                    }
                    scalar = scalar << 4 | (uint32_t)h;
                }
                if (scalar > 0x10ffff || (scalar >= 0xd800 && scalar < 0xe000)) {
                    ms_buf_free(&value);
                    return manifest_bad(r, i - 2, "invalid Unicode scalar");
                }
                i += digits;
                ms_utf8_put(&value, scalar);
            } else {
                ms_buf_free(&value);
                return manifest_bad(r, i - 2, "invalid string escape");
            }
            continue;
        }
        if (((unsigned char)c < 0x20 && c != '\t') || c == 0x7f) {
            ms_buf_free(&value);
            return manifest_bad(r, i - 1, "control character in string");
        }
        ms_buf_putc(&value, c);
    }
    *control = false;
    for (size_t k = 0; k < value.len; k++) {
        const unsigned char byte = (unsigned char)value.data[k];
        *control |= byte < 0x20 || byte == 0x7f;
    }
    *out = ms_arena_strndup(r->arena, value.data == NULL ? "" : value.data, value.len);
    ms_buf_free(&value);
    *at = i;
    return true;
}

static void manifest_skip_blanks(const Reader *r, size_t *at) {
    while (*at < r->length && (r->text[*at] == ' ' || r->text[*at] == '\t')) {
        (*at)++;
    }
}

/* The rest of the line after a table header or value: blanks, a comment, then the line end. */
static bool manifest_end_of_line(const Reader *r, size_t *at) {
    manifest_skip_blanks(r, at);
    if (*at < r->length && r->text[*at] == '#') {
        while (*at < r->length && r->text[*at] != '\n') {
            (*at)++;
        }
    }
    if (*at < r->length && r->text[*at] == '\r') {
        (*at)++;
    }
    if (*at < r->length && r->text[*at] != '\n') {
        return false;
    }
    if (*at < r->length) {
        (*at)++;
    }
    return true;
}

/* A number or boolean on one line, skipped. A date, a bare word or anything else is not a value ms.toml uses. */
static bool is_scalar_char(char c) { return ms_text_is_bare_key_char(c) || c == '.' || c == '+'; }

static bool manifest_skip_scalar(const Reader *r, size_t *at) {
    char first = '\0';
    if (*at < r->length) {
        first = r->text[*at];
    }
    const bool word = strncmp(r->text + *at, "true", 4) == 0 || strncmp(r->text + *at, "false", 5) == 0;
    if (!word && !(first >= '0' && first <= '9') && first != '+' && first != '-') {
        return false;
    }
    while (*at < r->length && (is_scalar_char(r->text[*at]))) {
        (*at)++;
    }
    return true;
}

/* A string or scalar inside an array or an inline table. */
static bool manifest_read_item(const Reader *r, size_t *at, Field *f) {
    f->pos = manifest_locate(r->text, r->length, *at);
    if (*at < r->length && (r->text[*at] == '"' || r->text[*at] == '\'')) {
        return manifest_read_string(r, at, &f->value, &f->control);
    }
    return manifest_skip_scalar(r, at) || manifest_bad(r, *at, "invalid value");
}

/* Blanks, comments and line ends between the elements of an array. */
static void manifest_skip_space(const Reader *r, size_t *at) {
    for (;;) {
        manifest_skip_blanks(r, at);
        if (*at < r->length && r->text[*at] == '#') {
            while (*at < r->length && r->text[*at] != '\n') {
                (*at)++;
            }
        }
        if (*at < r->length && (r->text[*at] == '\n' || r->text[*at] == '\r')) {
            (*at)++;
            continue;
        }
        return;
    }
}

static bool manifest_read_key(const Reader *r, size_t *at, const char **out);

/* `{ key = "value", ... }` on one line; the elements go to the entry. */
static bool manifest_read_inline_table(const Reader *r, size_t *at, Entry *e) {
    MsBuf fields = {0};
    (*at)++;
    manifest_skip_blanks(r, at);
    bool ok = true;
    while (ok && !(*at < r->length && r->text[*at] == '}')) {
        Field f = {0};
        ok = manifest_read_key(r, at, &f.key);
        manifest_skip_blanks(r, at);
        ok = ok && *at < r->length && r->text[*at] == '=';
        if (!ok) {
            manifest_bad(r, *at, "expected equals");
        } else {
            (*at)++;
            manifest_skip_blanks(r, at);
            ok = manifest_read_item(r, at, &f);
        }
        for (size_t i = 0; ok && i < MS_VEC_LEN(fields, Field); i++) {
            ok = strcmp(MS_VEC_AT(fields, Field, i).key, f.key) != 0 || manifest_bad(r, *at, "duplicate key");
        }
        if (ok) {
            MS_VEC_PUSH(fields, Field, f);
            manifest_skip_blanks(r, at);
            if (*at < r->length && r->text[*at] == ',') {
                (*at)++;
                manifest_skip_blanks(r, at);
                /* no trailing comma in an inline table */
                ok = !(*at < r->length && r->text[*at] == '}') || manifest_bad(r, *at, "trailing comma in inline table");
            } else {
                ok = (*at < r->length && r->text[*at] == '}') || manifest_bad(r, *at, "expected inline table comma");
            }
        }
    }
    (*at)++;
    e->value_kind = VALUE_INLINE_TABLE;
    e->nfields = (uint32_t)MS_VEC_LEN(fields, Field);
    Field *copy = MS_NEW_N(r->arena, Field, e->nfields + 1);
    if (e->nfields > 0) {
        memcpy(copy, ms_buf_items(&fields), e->nfields * sizeof(Field));
    }
    e->fields = copy;
    ms_buf_free(&fields);
    return ok;
}

/* `[ "a", "b" ]`, over any number of lines. */
static bool manifest_read_array(const Reader *r, size_t *at, Entry *e) {
    MsBuf fields = {0};
    (*at)++;
    bool ok = true;
    for (;;) {
        manifest_skip_space(r, at);
        if (*at < r->length && r->text[*at] == ']') {
            break;
        }
        Field f = {0};
        ok = manifest_read_item(r, at, &f);
        if (!ok) {
            break;
        }
        MS_VEC_PUSH(fields, Field, f);
        manifest_skip_space(r, at);
        if (*at < r->length && r->text[*at] == ',') {
            (*at)++;
        } else if (!(*at < r->length && r->text[*at] == ']')) {
            ok = manifest_bad(r, *at, "expected array comma");
            break;
        }
    }
    (*at)++;
    e->value_kind = VALUE_ARRAY;
    e->nfields = (uint32_t)MS_VEC_LEN(fields, Field);
    Field *copy = MS_NEW_N(r->arena, Field, e->nfields + 1);
    if (e->nfields > 0) {
        memcpy(copy, ms_buf_items(&fields), e->nfields * sizeof(Field));
    }
    e->fields = copy;
    ms_buf_free(&fields);
    return ok;
}

static bool manifest_read_key(const Reader *r, size_t *at, const char **out) {
    if (*at < r->length && (r->text[*at] == '"' || r->text[*at] == '\'')) {
        bool control;
        return manifest_read_string(r, at, out, &control);
    }
    const size_t start = *at;
    while (*at < r->length && ms_text_is_bare_key_char(r->text[*at])) {
        (*at)++;
    }
    if (*at == start) {
        return manifest_bad(r, start, "expected key");
    }
    *out = ms_arena_strndup(r->arena, r->text + start, *at - start);
    return true;
}

/* True when `entry` repeats a table, or a key of the table it is in: TOML rejects both. */
static bool manifest_seen_before(const MsBuf *entries, const Entry *entry) {
    for (size_t i = MS_VEC_LEN(*entries, Entry); i-- > 0;) {
        const Entry *other = &MS_VEC_AT(*entries, Entry, i);
        if (entry->kind == ENTRY_TABLE) {
            if (other->kind == ENTRY_TABLE && strcmp(other->name, entry->name) == 0) {
                return true;
            }
        } else if (other->kind == ENTRY_TABLE) {
            return false;
        } else if (strcmp(other->name, entry->name) == 0) {
            return true;
        }
    }
    return false;
}

/* The key of a table header or assignment at `at`: a dotted key and a table array are valid TOML that ms.toml does not use. */
static bool manifest_read_name(const Reader *r, size_t *at, const char **name, const char *dotted) {
    if (*at < r->length && r->text[*at] == '[') {
        return manifest_bad(r, *at, "table arrays are not supported in ms.toml");
    }
    if (!manifest_read_key(r, at, name)) {
        return false;
    }
    manifest_skip_blanks(r, at);
    if (*at < r->length && r->text[*at] == '.') {
        return manifest_bad(r, *at, dotted);
    }
    return true;
}

/* A `[table]` header after its opening bracket. */
static bool manifest_read_header(const Reader *r, size_t *at, Entry *entry) {
    manifest_skip_blanks(r, at);
    if (!manifest_read_name(r, at, &entry->name, "nested tables are not supported in ms.toml")) {
        return manifest_invalid(r, *at, "expected key");
    }
    if (*at >= r->length || r->text[*at] != ']') {
        return manifest_invalid(r, *at, "expected closing table bracket");
    }
    (*at)++;
    return manifest_end_of_line(r, at) || manifest_invalid(r, *at, "unexpected trailing text");
}

/* The value of an assignment after its `=`. */
static bool manifest_read_value(const Reader *r, size_t *at, Entry *entry) {
    const size_t start = *at;
    entry->value_pos = manifest_locate(r->text, r->length, start);
    char c = '\0';
    if (start < r->length) {
        c = r->text[start];
    }
    if (c == '"' || c == '\'') {
        entry->value_kind = VALUE_STRING;
        if (!manifest_read_string(r, at, &entry->value, &entry->control)) {
            return manifest_invalid(r, *at, "invalid value");
        }
    } else if (c == '{') {
        if (!manifest_read_inline_table(r, at, entry)) {
            return manifest_invalid(r, *at, "invalid inline table");
        }
    } else if (c == '[') {
        if (!manifest_read_array(r, at, entry)) {
            return manifest_invalid(r, *at, "invalid array");
        }
    } else if (manifest_skip_scalar(r, at)) {
        entry->value_kind = VALUE_SCALAR; /* value stays NULL: a number or boolean, which only an unknown key may hold */
    } else {
        return manifest_invalid(r, *at, "invalid value");
    }
    if (entry->value == NULL) {
        entry->raw = ms_arena_strndup(r->arena, r->text + start, *at - start);
    }
    return manifest_end_of_line(r, at) || manifest_invalid(r, *at, "unexpected trailing text");
}

/* The tables and assignments of the text, in order. */
static bool manifest_read_document(const Reader *r, size_t at, MsBuf *entries) {
    while (at < r->length) {
        manifest_skip_blanks(r, &at);
        if (at >= r->length) {
            break;
        }
        const char c = r->text[at];
        if (c == '\n' || c == '\r' || c == '#') {
            if (!manifest_end_of_line(r, &at)) {
                return manifest_invalid(r, at, "unexpected trailing text");
            }
            continue;
        }
        Entry entry = {0};
        entry.key_pos = manifest_locate(r->text, r->length, at);
        if (c == '[') {
            entry.kind = ENTRY_TABLE;
            at++;
            if (!manifest_read_header(r, &at, &entry)) {
                return false;
            }
        } else {
            entry.kind = ENTRY_PAIR;
            if (!manifest_read_name(r, &at, &entry.name, "dotted keys are not supported in ms.toml")) {
                return manifest_invalid(r, at, "expected key");
            }
            manifest_skip_blanks(r, &at);
            if (at >= r->length || r->text[at] != '=') {
                return manifest_invalid(r, at, "expected equals");
            }
            at++;
            manifest_skip_blanks(r, &at);
            if (!manifest_read_value(r, &at, &entry)) {
                return false;
            }
        }
        if (manifest_seen_before(entries, &entry)) {
            return manifest_fail_at(r, entry.key_pos, "invalid ms.toml: duplicate key");
        }
        MS_VEC_PUSH(*entries, Entry, entry);
    }
    return true;
}

/* ---- validation ---- */

/* `key = 1` where the key wants a string: the error shows the string that was meant, as `write key = "1"`. */
static bool manifest_not_string(const Reader *r, const Entry *e) {
    size_t from = 0;
    size_t to = e->raw == NULL ? 0 : strlen(e->raw);
    while (to > from && (e->raw[to - 1] == ' ' || e->raw[to - 1] == '\t' || e->raw[to - 1] == '"')) {
        to--;
    }
    while (from < to && (e->raw[from] == ' ' || e->raw[from] == '\t' || e->raw[from] == '"')) {
        from++;
    }
    return manifest_fail_at(r, e->value_pos, ms_arena_fmt(r->arena, "%s must be a string; write %s = \"%.*s\"", e->name, e->name, (int)(to - from), e->raw == NULL ? "" : e->raw + from).ptr);
}

static bool manifest_valid_alias(const char *key) {
    if (key[0] != '@' || key[1] == 0) {
        return false;
    }
    for (size_t i = 1; key[i] != 0; i++) {
        const char c = key[i];
        const bool letter = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_';
        const bool digit = c >= '0' && c <= '9';
        if (!letter && !(digit && i > 1)) {
            return false;
        }
    }
    return true;
}

typedef struct DepRow {
    MsDependency dep; /* first, so that rows sort by alias */
    MsPos key_pos, value_pos;
} DepRow;

typedef struct EffectRow {
    MsEffectRule rule; /* first, so that rows sort by name */
    MsPos key_pos;
} EffectRow;

/* The id of an assigned key (`aliases.@lib`) and where it was written; the Rust reader's `assignments`. */
typedef struct Assignment {
    const char *id;
    MsPos key_pos;
} Assignment;

typedef struct Builder {
    const Reader *reader;
    MsProject *project;
    MsBuf aliases;      /* MsAlias, sorted when the document is done */
    MsBuf embed;        /* MsAlias */
    MsBuf deps;         /* DepRow */
    MsBuf path_deps;    /* MsAlias, the target as written until it is resolved */
    MsBuf effects;      /* EffectRow */
    MsBuf assignments;  /* Assignment */
    const char **members;
    bool has_name, has_source, has_entry;
    MsPos source_pos, entry_pos;
} Builder;

static bool manifest_control(const Reader *r, const Entry *e) {
    return manifest_fail_at(r, e->value_pos, ms_arena_fmt(r->arena, "manifest value for %s contains a NUL or control character; remove it", e->name).ptr);
}

static bool manifest_valid_name(const char *key) {
    return manifest_valid_alias(key) && strcmp(key, "@std") != 0;
}

static bool manifest_add_alias(Builder *b, const Entry *e) {
    const Reader *r = b->reader;
    if (e->control) {
        return manifest_control(r, e);
    }
    if (!manifest_valid_name(e->name)) {
        const char *hint = "";
        if (strcmp(e->name, "std") != 0 && manifest_valid_alias(ms_arena_fmt(r->arena, "@%s", e->name).ptr)) {
            hint = ms_arena_fmt(r->arena, " (did you mean @%s?)", e->name).ptr;
        }
        return manifest_fail_at(r, e->key_pos, ms_arena_fmt(r->arena, "invalid or reserved alias %s%s; aliases look like @lib (start with @, letters/digits/underscore), cannot be @std, and must map to a path, not another alias", e->name, hint).ptr);
    }
    if (e->value[0] == '@') {
        return manifest_fail_at(r, e->value_pos, ms_arena_fmt(r->arena, "invalid alias target %s; map it to a project-local path, not another alias", e->value).ptr);
    }
    MsAlias alias = {.name = e->name, .target = e->value, .key_pos = e->key_pos, .value_pos = e->value_pos};
    MS_VEC_PUSH(b->aliases, MsAlias, alias);
    return true;
}

static bool manifest_add_embed(Builder *b, const Entry *e) {
    const Reader *r = b->reader;
    if (e->control) {
        return manifest_control(r, e);
    }
    if (!manifest_valid_name(e->name)) {
        return manifest_fail_at(r, e->key_pos, ms_arena_fmt(r->arena, "invalid or reserved embed name %s; embed names look like @assets (start with @, letters/digits/underscore) and cannot be @std", e->name).ptr);
    }
    if (e->value[0] == '@') {
        return manifest_fail_at(r, e->value_pos, ms_arena_fmt(r->arena, "invalid embed target %s; map it to a project-local directory, not an alias", e->value).ptr);
    }
    MsAlias embed = {.name = e->name, .target = e->value, .key_pos = e->key_pos, .value_pos = e->value_pos};
    MS_VEC_PUSH(b->embed, MsAlias, embed);
    return true;
}

typedef struct ListKind {
    const char *noun, *plural, *example, *first_example;
    bool spaces; /* directory names may hold spaces; effect patterns may not */
} ListKind;

static const ListKind manifest_effect_list = {"effect", "effects", "[\"std.net.*\", \"std.fs.read\"]", "\"std.net.*\"", false};
static const ListKind manifest_member_list = {"member", "members", "[\"app\", \"libs/*\"]", "\"app\"", true};

/* An array of strings; NULL with `*error` set to the Rust message when it is not one. */
static const char *const *manifest_string_list(const Reader *r, const Entry *e, const ListKind *kind, uint32_t *count, const char **error) {
    MsArena *a = r->arena;
    const char *shape = ms_arena_fmt(a, "%s are a list of strings: %s", kind->plural, kind->example).ptr;
    if (e->value_kind != VALUE_ARRAY) {
        *error = shape;
        return NULL;
    }
    const char **list = MS_NEW_N(a, const char *, e->nfields + 1);
    *count = 0;
    for (uint32_t i = 0; i < e->nfields; i++) {
        const char *text = e->fields[i].value;
        if (text == NULL) {
            *error = shape;
            return NULL;
        }
        bool bad = text[0] == 0 || e->fields[i].control;
        for (const char *c = text; !bad && *c != 0; c++) {
            bad = (unsigned char)*c < 0x20 || *c == 0x7f || (!kind->spaces && (*c == ' ' || *c == '\t'));
        }
        if (bad) {
            *error = ms_arena_fmt(a, "invalid %s %s; write one %s per string, such as %s", kind->noun, ms_debug_quote(a, text), kind->spaces ? "directory" : "pattern", kind->first_example).ptr;
            return NULL;
        }
        for (uint32_t k = 0; k < *count; k++) {
            if (strcmp(list[k], text) == 0) {
                *error = ms_arena_fmt(a, "%s %s is listed twice; remove one", kind->noun, text).ptr;
                return NULL;
            }
        }
        list[(*count)++] = text;
    }
    return list;
}

static bool manifest_check_package_name(const Reader *r, const Entry *e) {
    if (manifest_valid_name(e->name)) {
        return true;
    }
    return manifest_fail_at(r, e->key_pos, ms_arena_fmt(r->arena, "invalid or reserved package name %s; names look like @pg (start with @, letters/digits/underscore) and cannot be @std", e->name).ptr);
}

static bool manifest_add_effects(Builder *b, const Entry *e) {
    const Reader *r = b->reader;
    const char *error = "";
    EffectRow row = {.rule = {.name = e->name}, .key_pos = e->key_pos};
    row.rule.patterns = manifest_string_list(r, e, &manifest_effect_list, &row.rule.count, &error);
    if (row.rule.patterns == NULL) {
        return manifest_fail_at(r, e->value_pos, ms_arena_fmt(r->arena, "%s: %s", e->name, error).ptr);
    }
    if (!manifest_check_package_name(r, e)) {
        return false;
    }
    MS_VEC_PUSH(b->effects, EffectRow, row);
    return true;
}

static bool manifest_add_workspace(Builder *b, const Entry *e) {
    const Reader *r = b->reader;
    MsProject *p = b->project;
    if (strcmp(e->name, "members") != 0) {
        return manifest_fail_at(r, e->key_pos, ms_arena_fmt(r->arena, "unknown workspace key %s; [workspace] accepts members", e->name).ptr);
    }
    const char *error = "";
    p->members = manifest_string_list(r, e, &manifest_member_list, &p->member_count, &error);
    if (p->members == NULL) {
        return manifest_fail_at(r, e->value_pos, ms_arena_fmt(r->arena, "members: %s", error).ptr);
    }
    return true;
}

#define MANIFEST_DEP_SHAPE "write { url = \"https://github.com/acme/pg.git\", version = \"1.0\" }, or tag = \"v1.0.0\" or sha = \"<40-digit commit>\" in place of version"

/* A dependency is a table with `url` and exactly one of `tag`, `sha` and `version`, or only `path`. Returns NULL and
 * fills `row` (or `*path`), or the message. */
static const char *manifest_dependency(MsArena *a, const Entry *e, DepRow *row, const char **path) {
    if (e->value_kind != VALUE_INLINE_TABLE) {
        return "a dependency is a table; " MANIFEST_DEP_SHAPE;
    }
    const char *url = NULL, *tag = NULL, *sha = NULL, *version = NULL;
    *path = NULL;
    for (uint32_t i = 0; i < e->nfields; i++) {
        const Field *f = &e->fields[i];
        if (f->value == NULL || f->control) {
            return ms_arena_fmt(a, "%s must be a string; " MANIFEST_DEP_SHAPE, f->key).ptr;
        }
        const struct {
            const char *name;
            const char **slot;
        } fields[] = {{"url", &url}, {"tag", &tag}, {"sha", &sha}, {"version", &version}, {"path", path}};
        const char **slot = NULL;
        for (size_t k = 0; k < sizeof fields / sizeof *fields; k++) {
            if (strcmp(f->key, fields[k].name) == 0) {
                slot = fields[k].slot;
            }
        }
        if (slot == NULL) {
            return ms_arena_fmt(a, "unknown field %s; a dependency has url and one of version, tag or sha, or only path", f->key).ptr;
        }
        *slot = f->value;
    }
    if (*path != NULL) {
        if (url != NULL || tag != NULL || sha != NULL || version != NULL || (*path)[0] == 0) {
            return "a path dependency has only path = \"../member\"";
        }
        return NULL;
    }
    if (url == NULL) {
        return "url is missing; " MANIFEST_DEP_SHAPE;
    }
    MsDependency *d = &row->dep;
    d->url = url;
    const char *reference = "v0.0.0";
    if (version != NULL && tag == NULL && sha == NULL) {
        const char *error;
        d->kind = MS_DEP_VERSION;
        if (!ms_requirement_parse(a, version, &d->requirement, &error)) {
            return error;
        }
    } else if (tag != NULL && version == NULL && sha == NULL) {
        d->kind = MS_DEP_TAG;
        d->reference = reference = tag;
    } else if (sha != NULL && version == NULL && tag == NULL) {
        if (!ms_is_hex(sha, strlen(sha)) || strlen(sha) != 40) {
            return "sha must be the full 40-digit lowercase commit";
        }
        d->kind = MS_DEP_SHA;
        d->reference = reference = sha;
    } else {
        return "name exactly one of version, tag and sha; " MANIFEST_DEP_SHAPE;
    }
    /* A requirement has no tag to check yet; a url is checked the same way as a pinned spec. */
    return ms_spec_check(a, ms_arena_fmt(a, "%s#%s", url, reference).ptr);
}

static bool manifest_add_dependency(Builder *b, const Entry *e) {
    const Reader *r = b->reader;
    MsArena *a = r->arena;
    if (!manifest_check_package_name(r, e)) {
        return false;
    }
    DepRow row = {.dep = {.alias = e->name}, .key_pos = e->key_pos, .value_pos = e->value_pos};
    const char *path;
    const char *error = manifest_dependency(a, e, &row, &path);
    if (error != NULL) {
        return manifest_fail_at(r, e->value_pos, ms_arena_fmt(a, "dependency %s: %s", e->name, error).ptr);
    }
    if (path == NULL) {
        MS_VEC_PUSH(b->deps, DepRow, row);
        return true;
    }
    MsProjectError cause;
    const char *target;
    if (!ms_path_eval_symlinks(a, MS_PATH_JOIN(a, b->project->root, path), &target, &cause)) {
        return manifest_fail_at(r, e->value_pos, ms_arena_fmt(a, "dependency %s: path %s cannot be resolved: %s", e->name, ms_debug_quote(a, path), ms_project_error_text(a, &cause)).ptr);
    }
    MsAlias dep = {.name = e->name, .target = target, .key_pos = e->key_pos, .value_pos = e->value_pos};
    MS_VEC_PUSH(b->path_deps, MsAlias, dep);
    return true;
}

static bool manifest_add_project_key(Builder *b, const Entry *e) {
    const Reader *r = b->reader;
    MsProject *p = b->project;
    MsArena *a = r->arena;
    if (strcmp(e->name, "effects") == 0) {
        const char *error = "";
        p->effects = manifest_string_list(r, e, &manifest_effect_list, &p->effect_count, &error);
        if (p->effects == NULL) {
            return manifest_fail_at(r, e->value_pos, ms_arena_fmt(a, "effects: %s", error).ptr);
        }
        return true;
    }
    if (strcmp(e->name, "name") != 0 && strcmp(e->name, "source") != 0 && strcmp(e->name, "entry") != 0 && strcmp(e->name, "version") != 0) {
        return manifest_fail_at(r, e->key_pos, ms_arena_fmt(a, "unknown project key %s; [project] accepts name, source, entry, version, and effects", e->name).ptr);
    }
    if (e->value == NULL) {
        return manifest_not_string(r, e);
    }
    if (e->control) {
        return manifest_control(r, e);
    }
    if (strcmp(e->name, "version") == 0) {
        const char *error;
        p->has_version = true;
        if (!ms_version_parse(a, e->value, &p->version, &error)) {
            return manifest_fail_at(r, e->value_pos, ms_arena_fmt(a, "version: %s", error).ptr);
        }
    } else if (strcmp(e->name, "name") == 0) {
        p->name = e->value;
        b->has_name = true;
    } else if (strcmp(e->name, "source") == 0) {
        p->source = e->value;
        b->has_source = true;
        b->source_pos = e->value_pos;
    } else {
        p->entry = e->value;
        b->has_entry = true;
        b->entry_pos = e->value_pos;
    }
    return true;
}

static bool manifest_is_dir(const char *path) {
    MsSysStat info;
    return ms_sys_fs_stat(path, true, &info) == 0 && host_is_dir(&info);
}

bool ms_project_is_file(const char *path) {
    MsSysStat info;
    return ms_sys_fs_stat(path, true, &info) == 0 && host_is_reg(&info);
}

typedef enum Section { SECTION_NONE, SECTION_PROJECT, SECTION_ALIASES, SECTION_EMBED, SECTION_DEPENDENCIES, SECTION_EFFECTS, SECTION_WORKSPACE } Section;

static const struct {
    const char *name;
    Section section;
} manifest_sections[] = {{"project", SECTION_PROJECT}, {"aliases", SECTION_ALIASES}, {"embed", SECTION_EMBED}, {"dependencies", SECTION_DEPENDENCIES}, {"effects", SECTION_EFFECTS}, {"workspace", SECTION_WORKSPACE}};

static bool manifest_add_pair(Builder *b, Section section, const Entry *e) {
    switch (section) {
    case SECTION_EFFECTS: return manifest_add_effects(b, e);
    case SECTION_WORKSPACE: return manifest_add_workspace(b, e);
    case SECTION_DEPENDENCIES: return manifest_add_dependency(b, e);
    case SECTION_PROJECT: return manifest_add_project_key(b, e);
    case SECTION_NONE:
    case SECTION_ALIASES:
    case SECTION_EMBED: break;
    }
    if (e->value == NULL) {
        return manifest_not_string(b->reader, e);
    }
    return section == SECTION_EMBED ? manifest_add_embed(b, e) : manifest_add_alias(b, e);
}

/* Table and key checks in document order, as the Rust reader runs them. */
static bool manifest_read_entries(Builder *b, const Entry *entries, size_t count) {
    const Reader *r = b->reader;
    MsArena *a = r->arena;
    Section section = SECTION_NONE;
    const char *section_name = "";
    for (size_t i = 0; i < count; i++) {
        const Entry *e = &entries[i];
        if (e->kind == ENTRY_TABLE) {
            section = SECTION_NONE;
            for (size_t k = 0; k < sizeof manifest_sections / sizeof *manifest_sections; k++) {
                if (strcmp(e->name, manifest_sections[k].name) == 0) {
                    section = manifest_sections[k].section;
                    section_name = manifest_sections[k].name;
                }
            }
            if (section == SECTION_NONE) {
                const char *advice = strcmp(e->name, "package") == 0 ? "rename it to [project] with name, source, and entry" : "ms.toml has no other tables";
                return manifest_fail_at(r, e->key_pos, ms_arena_fmt(a, "unsupported manifest table [%s]; ms.toml supports only [project], [workspace], [aliases], [embed], [dependencies] and [effects]: %s", e->name, advice).ptr);
            }
            if (section == SECTION_PROJECT) {
                b->project->location = e->key_pos;
            }
            if (section == SECTION_WORKSPACE) {
                b->project->is_workspace = true; /* a bare [workspace] is a root with no members yet */
            }
            continue;
        }
        if (section == SECTION_NONE) {
            MsPos start = manifest_locate(r->text, r->length, 0);
            return manifest_fail_at(r, start, ms_arena_fmt(a, "invalid manifest assignment; %s is not a table, so put it under a [project] table header: ms.toml starts with [project] and name = \"app\" and source = \"src\" under it", e->name).ptr);
        }
        Assignment assignment = {.id = ms_arena_fmt(a, "%s.%s", section_name, e->name).ptr, .key_pos = e->key_pos};
        MS_VEC_PUSH(b->assignments, Assignment, assignment);
        if (!manifest_add_pair(b, section, e)) {
            return false;
        }
    }
    return true;
}

/* Orders rows whose first member is the name (MsAlias, DepRow, EffectRow), as the Rust maps iterate. */
/* The rows of `buf` sorted by name and copied into the arena. */
static void *manifest_sorted(MsArena *a, MsBuf *buf, size_t size, uint32_t *count) {
    const size_t n = buf->len / size;
    void *rows = ms_buf_items(buf);
    if (n > 1) {
        qsort(rows, n, size, ms_cmp_cstr);
    }
    void *copy = ms_alloc(a, (n + 1) * size, _Alignof(max_align_t));
    if (n > 0) {
        memcpy(copy, rows, n * size);
    }
    *count = (uint32_t)n;
    return copy;
}

static bool manifest_has_name(const MsAlias *rows, uint32_t count, const char *name) {
    for (uint32_t i = 0; i < count; i++) {
        if (strcmp(rows[i].name, name) == 0) {
            return true;
        }
    }
    return false;
}

/* The key that makes a workspace root without [project] invalid: the smallest assignment outside [workspace]. */
static const Assignment *manifest_stray_assignment(const Builder *b) {
    const Assignment *stray = NULL;
    for (size_t i = 0; i < MS_VEC_LEN(b->assignments, Assignment); i++) {
        const Assignment *x = &MS_VEC_AT(b->assignments, Assignment, i);
        if (strncmp(x->id, "workspace.", 10) != 0 && (stray == NULL || strcmp(x->id, stray->id) < 0)) {
            stray = x;
        }
    }
    return stray;
}

static bool manifest_has_project_key(const Builder *b) {
    for (size_t i = 0; i < MS_VEC_LEN(b->assignments, Assignment); i++) {
        if (strncmp(MS_VEC_AT(b->assignments, Assignment, i).id, "project.", 8) == 0) {
            return true;
        }
    }
    return false;
}

/* Names declared in more than one place, effects for a name that is no dependency, and the embedded directories. */
static bool manifest_check_declared(Builder *b) {
    const Reader *r = b->reader;
    const MsProject *p = b->project;
    MsArena *a = r->arena;
    const DepRow *deps = ms_buf_items(&b->deps);
    for (uint32_t i = 0; i < p->dependency_count; i++) {
        if (manifest_has_name(p->aliases, p->alias_count, deps[i].dep.alias) || manifest_has_name(p->embed, p->embed_count, deps[i].dep.alias)) {
            return manifest_fail_at(r, deps[i].key_pos, ms_arena_fmt(a, "%s is declared in [dependencies] and also as an alias or embed; rename one so an import names a single thing", deps[i].dep.alias).ptr);
        }
    }
    for (uint32_t i = 0; i < p->path_dependency_count; i++) {
        const MsAlias *dep = &p->path_dependencies[i];
        if (manifest_has_name(p->aliases, p->alias_count, dep->name) || manifest_has_name(p->embed, p->embed_count, dep->name)) {
            return manifest_fail_at(r, dep->key_pos, ms_arena_fmt(a, "%s is declared in [dependencies] and also as an alias or embed; rename one so an import names a single thing", dep->name).ptr);
        }
    }
    const EffectRow *effects = ms_buf_items(&b->effects);
    for (uint32_t i = 0; i < p->allowed_effect_count; i++) {
        const char *name = effects[i].rule.name;
        bool known = manifest_has_name(p->path_dependencies, p->path_dependency_count, name);
        for (uint32_t k = 0; !known && k < p->dependency_count; k++) {
            known = strcmp(deps[k].dep.alias, name) == 0;
        }
        if (!known) {
            return manifest_fail_at(r, effects[i].key_pos, ms_arena_fmt(a, "[effects] names %s, which is not under [dependencies]; remove it or add the dependency", name).ptr);
        }
    }
    for (uint32_t i = 0; i < p->embed_count; i++) {
        MsAlias *embed = &p->embed[i];
        if (manifest_has_name(p->aliases, p->alias_count, embed->name)) {
            return manifest_fail_at(r, embed->key_pos, ms_arena_fmt(a, "%s is declared in both [aliases] and [embed]; rename one so an import names a single thing", embed->name).ptr);
        }
        MsProjectError cause;
        const char *target;
        if (!ms_project_source_path(a, p->root, embed->target, &target, &cause)) {
            return manifest_fail_at(r, embed->value_pos, ms_arena_fmt(a, "embed %s target cannot be resolved: %s; keep embedded directories inside the project root", embed->name, ms_project_error_text(a, &cause)).ptr);
        }
        if (!manifest_is_dir(target)) {
            return manifest_fail_at(r, embed->value_pos, ms_arena_fmt(a, "embed %s must name an existing directory; %s is not one, so create it or fix the path in [embed]", embed->name, ms_project_quote(a, target)).ptr);
        }
        embed->target = target;
    }
    return true;
}

/* Required fields, then the paths made canonical (source, entry, aliases), in the order the Rust reader checks them. */
static bool manifest_finish(Builder *b) {
    const Reader *r = b->reader;
    MsProject *p = b->project;
    MsArena *a = r->arena;
    if (p->is_workspace) {
        if (!manifest_has_project_key(b)) { /* a root that only lists members has no source of its own */
            const Assignment *stray = manifest_stray_assignment(b);
            if (stray != NULL) {
                const size_t dot = strcspn(stray->id, ".");
                return manifest_fail_at(r, stray->key_pos, ms_arena_fmt(a, "a workspace root without [project] holds only [workspace]; move [%.*s] into a member or add a [project] table", (int)dot, stray->id).ptr);
            }
            return true;
        }
    }
    if (p->name[0] == 0 || p->source[0] == 0) {
        return manifest_fail_at(r, p->location, ms_arena_fmt(a, "[project] requires name and source; missing: %s%s%s, e.g. name = \"app\", source = \"src\" (add entry = \"src/main.ms\" for an executable)", p->name[0] == 0 ? "name" : "", p->name[0] == 0 && p->source[0] == 0 ? ", " : "", p->source[0] == 0 ? "source" : "").ptr);
    }
    MsProjectError cause;
    if (!ms_project_source_path(a, p->root, p->source, &p->source, &cause)) {
        return manifest_fail_wrapped(r, b->source_pos, &cause);
    }
    if (!manifest_is_dir(p->source)) {
        return manifest_fail_at(r, b->source_pos, ms_arena_fmt(a, "project source must be an existing directory; %s does not exist or is not a directory, so create it or fix source in [project]", ms_project_quote(a, p->source)).ptr);
    }
    if (b->has_entry) {
        if (p->entry[0] == 0) {
            return manifest_fail_at(r, b->entry_pos, "project entry cannot be empty; omit entry for a library or set it to a .ms file such as \"src/main.ms\"");
        }
        if (!ms_project_source_path(a, p->root, p->entry, &p->entry, &cause)) {
            return manifest_fail_wrapped(r, b->entry_pos, &cause);
        }
        if (strcmp(ms_path_ext(p->entry), ".ms") != 0) {
            return manifest_fail_at(r, b->entry_pos, "entry requires .ms extension; set entry to a .ms file such as \"src/main.ms\"");
        }
        if (!ms_project_is_file(p->entry)) {
            return manifest_fail_at(r, b->entry_pos, ms_arena_fmt(a, "project entry must be an existing regular file; create %s or fix entry in [project]", p->entry).ptr);
        }
    }
    for (uint32_t i = 0; i < p->alias_count; i++) {
        MsAlias *alias = &p->aliases[i];
        if (!ms_project_source_path(a, p->root, alias->target, &alias->target, &cause)) {
            return manifest_fail_at(r, alias->value_pos, ms_arena_fmt(a, "alias %s target cannot be resolved: %s; external Manuscript dependency projects are unsupported, so copy the sources inside this project root and point the alias at that copy", alias->name, ms_project_error_text(a, &cause)).ptr);
        }
    }
    return manifest_check_declared(b);
}

const char *ms_project_read_file(MsArena *a, const char *path, size_t *length, MsProjectError *err) {
    MsSysFd fd;
    MsSysError failure = ms_sys_fs_open(path, MS_SYS_O_READ, 0, &fd);
    if (failure != 0) {
        ms_project_error_path(err, a, "open", path, failure);
        return NULL;
    }
    MsBuf data = {0};
    uint8_t chunk[16384];
    size_t n = 1;
    while (n > 0 && (failure = ms_sys_fs_read(fd, chunk, sizeof chunk, &n)) == 0) {
        ms_buf_put(&data, chunk, n);
    }
    ms_sys_fs_close_quietly(fd);
    if (failure != 0) {
        ms_buf_free(&data);
        ms_project_error_path(err, a, "read", path, failure);
        return NULL;
    }
    *length = data.len;
    char *text = ms_arena_strndup(a, data.data == NULL ? "" : data.data, data.len);
    ms_buf_free(&data);
    return text;
}

/* How many bytes the UTF-8 sequence that starts with `lead` has. */
static size_t manifest_utf8_size(unsigned char lead) {
    if (lead < 0x80) {
        return 1;
    }
    if (lead >= 0xf0) {
        return 4;
    }
    return lead >= 0xe0 ? 3 : 2;
}

/* The text with each byte that is not valid UTF-8 replaced by U+FFFD, so a stray byte in a comment reads as it does everywhere else. */
static const char *manifest_lossy(MsArena *a, const char *text, size_t *length) {
    if (ms_utf8_valid(text, *length)) {
        return text;
    }
    MsBuf out = {0};
    for (size_t i = 0; i < *length;) {
        const unsigned char lead = (unsigned char)text[i];
        const size_t size = manifest_utf8_size(lead);
        if (i + size <= *length && ms_utf8_valid(text + i, size)) {
            ms_buf_put(&out, text + i, size);
            i += size;
        } else {
            ms_buf_puts(&out, "\xef\xbf\xbd");
            i++;
        }
    }
    const char *copy = ms_arena_strndup(a, out.data, out.len);
    *length = out.len;
    ms_buf_free(&out);
    return copy;
}

bool ms_project_read(MsArena *a, const char *manifest, MsProject *out, MsProjectError *err) {
    const char *absolute;
    if (!ms_path_abs(a, manifest, &absolute, err)) {
        return false;
    }
    const char *root;
    if (!ms_path_eval_symlinks(a, ms_path_dir(a, absolute), &root, err)) {
        return false;
    }
    *out = (MsProject){.root = root, .file = ms_path_base(a, absolute), .name = "", .source = "", .entry = ""};
    out->location = (MsPos){.line = 1, .column = 1};
    size_t length = 0;
    out->configuration = ms_project_read_file(a, absolute, &length, err);
    if (out->configuration == NULL) {
        return false;
    }
    out->configuration = manifest_lossy(a, out->configuration, &length);
    Bad bad = {0};
    const Reader r = {.arena = a, .text = out->configuration, .length = length, .file = out->file, .err = err, .bad = &bad};

    size_t line_start = 0;
    uint32_t line = 1;
    for (size_t i = 0; i <= length; i++) {
        if (i == length || out->configuration[i] == '\n') {
            if (i - line_start > MAX_LINE) {
                return manifest_fail_at(&r, (MsPos){.line = line, .column = 1}, "line too long; keep each ms.toml line under 64 KiB");
            }
            line_start = i + 1;
            line++;
        }
    }
    const size_t bom = length >= 3 && memcmp(out->configuration, "\xef\xbb\xbf", 3) == 0 ? 3 : 0;
    MsBuf entries = {0};
    Builder b = {.reader = &r, .project = out};
    bool ok = manifest_read_document(&r, bom, &entries) && manifest_read_entries(&b, ms_buf_items(&entries), MS_VEC_LEN(entries, Entry));
    ms_buf_free(&entries);
    if (ok) {
        out->aliases = manifest_sorted(a, &b.aliases, sizeof(MsAlias), &out->alias_count);
        out->embed = manifest_sorted(a, &b.embed, sizeof(MsAlias), &out->embed_count);
        out->path_dependencies = manifest_sorted(a, &b.path_deps, sizeof(MsAlias), &out->path_dependency_count);
        DepRow *deps = manifest_sorted(a, &b.deps, sizeof(DepRow), &out->dependency_count);
        out->dependencies = MS_NEW_N(a, MsDependency, out->dependency_count + 1);
        for (uint32_t i = 0; i < out->dependency_count; i++) {
            out->dependencies[i] = deps[i].dep;
        }
        EffectRow *effects = manifest_sorted(a, &b.effects, sizeof(EffectRow), &out->allowed_effect_count);
        out->allowed_effects = MS_NEW_N(a, MsEffectRule, out->allowed_effect_count + 1);
        for (uint32_t i = 0; i < out->allowed_effect_count; i++) {
            out->allowed_effects[i] = effects[i].rule;
        }
        ok = manifest_finish(&b);
    }
    ms_buf_free(&b.aliases);
    ms_buf_free(&b.embed);
    ms_buf_free(&b.deps);
    ms_buf_free(&b.path_deps);
    ms_buf_free(&b.effects);
    ms_buf_free(&b.assignments);
    return ok;
}

const char *ms_project_dependency_row(MsArena *a, const MsDependency *d) {
    static const char *const kinds[] = {"tag", "sha", "version"};
    return ms_arena_fmt(a, "%s\t%s\t%s\t%s", d->alias, d->url, kinds[d->kind], d->kind == MS_DEP_VERSION ? ms_dependency_describe(a, d) : d->reference).ptr;
}

const char *ms_project_find_manifest(MsArena *a, const char *filename) {
    const char *directory = ms_path_dir(a, filename);
    for (;;) {
        const char *manifest = MS_PATH_JOIN(a, directory, "ms.toml");
        MsSysStat info;
        if (ms_sys_fs_stat(manifest, true, &info) == 0) {
            return manifest;
        }
        const char *parent = ms_path_dir(a, directory);
        if (strcmp(parent, directory) == 0) {
            return NULL;
        }
        directory = parent;
    }
}
