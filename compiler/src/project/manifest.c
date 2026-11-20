/* ms.toml (project.h): the subset of TOML a manifest of `[project]` and `[aliases]` uses, and its validation. Port of
 * crates/ms-driver/src/project/manifest.rs; messages and locations match it. Anything this reader does not cover
 * (other tables and keys, values that are not strings, TOML syntax errors) fails as MS_PERR_UNSUPPORTED instead of
 * guessing, so the Rust driver reports it. */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "ms/project.h"

enum { MAX_LINE = 65535 };

typedef enum EntryKind { ENTRY_TABLE, ENTRY_PAIR } EntryKind;

/* One table header or `key = "value"` of the document, in order. */
typedef struct Entry {
    EntryKind kind;
    const char *name; /* table name, or key */
    const char *value;
    bool control; /* the value holds a control character (even a NUL, which `value` cannot show) */
    MsPos key_pos, value_pos; /* the header for a table */
} Entry;

typedef struct Reader {
    MsArena *arena;
    const char *text;
    size_t length;
    const char *file;
    MsProjectError *err;
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

static bool manifest_unsupported(const Reader *r, const char *what) {
    ms_project_error_unsupported(r->err, what);
    return false;
}

/* ---- reading the document ---- */

static bool manifest_is_bare(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-';
}

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
        return false; /* a multi-line string */
    }
    MsBuf value = {0};
    for (;;) {
        if (i >= r->length || r->text[i] == '\n' || r->text[i] == '\r') {
            ms_buf_free(&value);
            return false;
        }
        const char c = r->text[i++];
        if (c == quote) {
            break;
        }
        if (quote == '"' && c == '\\') {
            if (i >= r->length) {
                ms_buf_free(&value);
                return false;
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
                        return false;
                    }
                    scalar = scalar << 4 | (uint32_t)h;
                }
                if (scalar > 0x10ffff || (scalar >= 0xd800 && scalar < 0xe000)) {
                    ms_buf_free(&value);
                    return false;
                }
                i += digits;
                ms_utf8_put(&value, scalar);
            } else {
                ms_buf_free(&value);
                return false;
            }
            continue;
        }
        if (((unsigned char)c < 0x20 && c != '\t') || c == 0x7f) {
            ms_buf_free(&value); /* a control character: TOML rejects it, so the Rust reader words the error */
            return false;
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

/* A number or boolean on one line, skipped. Arrays, tables, dates and bare words are left to the Rust reader. */
static bool is_scalar_char(char c) { return manifest_is_bare(c) || c == '.' || c == '+'; }

static bool manifest_read_scalar(const Reader *r, size_t *at) {
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
    return manifest_end_of_line(r, at);
}

static bool manifest_read_key(const Reader *r, size_t *at, const char **out) {
    if (*at < r->length && (r->text[*at] == '"' || r->text[*at] == '\'')) {
        bool control;
        return manifest_read_string(r, at, out, &control);
    }
    const size_t start = *at;
    while (*at < r->length && manifest_is_bare(r->text[*at])) {
        (*at)++;
    }
    if (*at == start) {
        return false;
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
                return manifest_unsupported(r, "invalid ms.toml");
            }
            continue;
        }
        Entry entry = {0};
        if (c == '[') {
            entry.kind = ENTRY_TABLE;
            entry.key_pos = manifest_locate(r->text, r->length, at);
            at++;
            manifest_skip_blanks(r, &at);
            if (!manifest_read_key(r, &at, &entry.name)) {
                return manifest_unsupported(r, "invalid ms.toml");
            }
            manifest_skip_blanks(r, &at);
            if (at >= r->length || r->text[at] != ']') {
                return manifest_unsupported(r, "invalid ms.toml");
            }
            at++;
            if (!manifest_end_of_line(r, &at)) {
                return manifest_unsupported(r, "invalid ms.toml");
            }
        } else {
            entry.kind = ENTRY_PAIR;
            entry.key_pos = manifest_locate(r->text, r->length, at);
            if (!manifest_read_key(r, &at, &entry.name)) {
                return manifest_unsupported(r, "invalid ms.toml");
            }
            manifest_skip_blanks(r, &at);
            if (at >= r->length || r->text[at] != '=') {
                return manifest_unsupported(r, "invalid ms.toml");
            }
            at++;
            manifest_skip_blanks(r, &at);
            entry.value_pos = manifest_locate(r->text, r->length, at);
            if (at < r->length && (r->text[at] == '"' || r->text[at] == '\'')) {
                if (!manifest_read_string(r, &at, &entry.value, &entry.control) || !manifest_end_of_line(r, &at)) {
                    return manifest_unsupported(r, "invalid ms.toml");
                }
            } else if (!manifest_read_scalar(r, &at)) {
                return manifest_unsupported(r, "invalid ms.toml");
            } /* else entry.value stays NULL: a number or boolean, which only an unknown key may hold */
        }
        if (manifest_seen_before(entries, &entry)) {
            return manifest_unsupported(r, "duplicate key");
        }
        MS_VEC_PUSH(*entries, Entry, entry);
    }
    return true;
}

/* ---- validation ---- */

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

typedef struct Builder {
    const Reader *reader;
    MsProject *project;
    MsBuf aliases; /* MsAlias, sorted when the document is done */
    bool has_name, has_source, has_entry;
    MsPos source_pos, entry_pos;
} Builder;

static bool manifest_add_alias(Builder *b, const Entry *e) {
    const Reader *r = b->reader;
    if (!manifest_valid_alias(e->name) || strcmp(e->name, "@std") == 0) {
        const char *hint = "";
        if (strcmp(e->name, "std") != 0 && manifest_valid_alias(ms_arena_fmt(r->arena, "@%s", e->name).ptr)) {
            hint = ms_arena_fmt(r->arena, " (did you mean @%s?)", e->name).ptr;
        }
        return manifest_fail_at(r, e->key_pos, ms_arena_fmt(r->arena, "invalid or reserved alias %s%s; aliases look like @lib (start with @, letters/digits/underscore), cannot be @std, and must map to a path, not another alias", e->name, hint).ptr);
    }
    if (e->value[0] == '@') {
        return manifest_fail_at(r, e->value_pos, ms_arena_fmt(r->arena, "invalid alias target %s; map it to a project-local path, not another alias", e->value).ptr);
    }
    if (e->control) {
        return manifest_fail_at(r, e->value_pos, ms_arena_fmt(r->arena, "manifest value for %s contains a NUL or control character; remove it", e->name).ptr);
    }
    MsAlias alias = {.name = e->name, .target = e->value, .key_pos = e->key_pos, .value_pos = e->value_pos};
    MS_VEC_PUSH(b->aliases, MsAlias, alias);
    return true;
}

static bool manifest_add_project_key(Builder *b, const Entry *e) {
    const Reader *r = b->reader;
    MsProject *p = b->project;
    if (strcmp(e->name, "version") == 0 || strcmp(e->name, "effects") == 0) {
        return manifest_unsupported(r, "[project] version and effects");
    }
    if (strcmp(e->name, "name") != 0 && strcmp(e->name, "source") != 0 && strcmp(e->name, "entry") != 0) {
        return manifest_fail_at(r, e->key_pos, ms_arena_fmt(r->arena, "unknown project key %s; [project] accepts name, source, entry, version, and effects", e->name).ptr);
    }
    if (e->control) {
        return manifest_fail_at(r, e->value_pos, ms_arena_fmt(r->arena, "manifest value for %s contains a NUL or control character; remove it", e->name).ptr);
    }
    if (strcmp(e->name, "name") == 0) {
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
    struct stat info;
    return stat(path, &info) == 0 && S_ISDIR(info.st_mode);
}

static bool manifest_is_file(const char *path) {
    struct stat info;
    return stat(path, &info) == 0 && S_ISREG(info.st_mode);
}

/* Table and key checks in document order, as the Rust reader runs them. */
static bool manifest_read_entries(Builder *b, const Entry *entries, size_t count) {
    const Reader *r = b->reader;
    enum { NONE, PROJECT, ALIASES } section = NONE;
    for (size_t i = 0; i < count; i++) {
        const Entry *e = &entries[i];
        if (e->kind == ENTRY_TABLE) {
            if (strcmp(e->name, "project") == 0) {
                section = PROJECT;
                b->project->location = e->key_pos;
            } else if (strcmp(e->name, "aliases") == 0) {
                section = ALIASES;
            } else if (strcmp(e->name, "embed") == 0 || strcmp(e->name, "dependencies") == 0 ||
                       strcmp(e->name, "effects") == 0 || strcmp(e->name, "workspace") == 0) {
                return manifest_unsupported(r, "[embed], [dependencies], [effects] and [workspace]");
            } else {
                const char *advice = strcmp(e->name, "package") == 0 ? "rename it to [project] with name, source, and entry" : "ms.toml has no other tables";
                return manifest_fail_at(r, e->key_pos, ms_arena_fmt(r->arena, "unsupported manifest table [%s]; ms.toml supports only [project], [workspace], [aliases], [embed], [dependencies] and [effects]: %s", e->name, advice).ptr);
            }
            continue;
        }
        if (e->value == NULL && section != NONE) {
            const bool known = strcmp(e->name, "name") == 0 || strcmp(e->name, "source") == 0 || strcmp(e->name, "entry") == 0;
            if (section == PROJECT && !known && strcmp(e->name, "version") != 0 && strcmp(e->name, "effects") != 0) {
                return manifest_fail_at(r, e->key_pos, ms_arena_fmt(r->arena, "unknown project key %s; [project] accepts name, source, entry, version, and effects", e->name).ptr);
            }
            return manifest_unsupported(r, "a value that is not a string");
        }
        if (section == NONE) {
            MsPos start = manifest_locate(r->text, r->length, 0);
            return manifest_fail_at(r, start, ms_arena_fmt(r->arena, "invalid manifest assignment; %s is not a table, so put it under a [project] table header: ms.toml starts with [project] and name = \"app\" and source = \"src\" under it", e->name).ptr);
        }
        if (!(section == PROJECT ? manifest_add_project_key(b, e) : manifest_add_alias(b, e))) {
            return false;
        }
    }
    return true;
}

static int manifest_alias_order(const void *x, const void *y) {
    const MsAlias *left = x, *right = y;
    return strcmp(left->name, right->name);
}

/* Required fields, then the paths made canonical (source, entry, aliases), in the order the Rust reader checks them. */
static bool manifest_finish(Builder *b) {
    const Reader *r = b->reader;
    MsProject *p = b->project;
    MsArena *a = r->arena;
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
        if (!manifest_is_file(p->entry)) {
            return manifest_fail_at(r, b->entry_pos, ms_arena_fmt(a, "project entry must be an existing regular file; create %s or fix entry in [project]", p->entry).ptr);
        }
    }
    for (uint32_t i = 0; i < p->alias_count; i++) {
        MsAlias *alias = &p->aliases[i];
        if (!ms_project_source_path(a, p->root, alias->target, &alias->target, &cause)) {
            return manifest_fail_at(r, alias->value_pos, ms_arena_fmt(a, "alias %s target cannot be resolved: %s; external Manuscript dependency projects are unsupported, so copy the sources inside this project root and point the alias at that copy", alias->name, ms_project_error_text(a, &cause)).ptr);
        }
    }
    return true;
}

static const char *manifest_read_file(MsArena *a, const char *path, size_t *length, MsProjectError *err) {
    FILE *f = fopen(path, "rbe");
    if (f == NULL) {
        ms_project_error_path(err, a, "open", path, errno);
        return NULL;
    }
    MsBuf data = {0};
    char chunk[8192];
    size_t n;
    while ((n = fread(chunk, 1, sizeof chunk, f)) > 0) {
        ms_buf_put(&data, chunk, n);
    }
    const bool failed = ferror(f) != 0;
    const int saved = errno;
    fclose(f);
    if (failed) {
        ms_buf_free(&data);
        ms_project_error_path(err, a, "read", path, saved);
        return NULL;
    }
    *length = data.len;
    char *text = ms_arena_strndup(a, data.data == NULL ? "" : data.data, data.len);
    ms_buf_free(&data);
    return text;
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
    out->configuration = manifest_read_file(a, absolute, &length, err);
    if (out->configuration == NULL) {
        return false;
    }
    const Reader r = {.arena = a, .text = out->configuration, .length = length, .file = out->file, .err = err};

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
    if (!ms_utf8_valid(out->configuration, length)) {
        return manifest_unsupported(&r, "a manifest that is not UTF-8");
    }
    const size_t bom = length >= 3 && memcmp(out->configuration, "\xef\xbb\xbf", 3) == 0 ? 3 : 0;
    MsBuf entries = {0};
    Builder b = {.reader = &r, .project = out};
    bool ok = manifest_read_document(&r, bom, &entries) && manifest_read_entries(&b, ms_buf_items(&entries), MS_VEC_LEN(entries, Entry));
    ms_buf_free(&entries);
    if (ok) {
        const size_t count = MS_VEC_LEN(b.aliases, MsAlias);
        out->aliases = MS_NEW_N(a, MsAlias, count);
        if (count > 0) {
            memcpy(out->aliases, ms_buf_items(&b.aliases), count * sizeof(MsAlias));
            qsort(out->aliases, count, sizeof(MsAlias), manifest_alias_order);
        }
        out->alias_count = (uint32_t)count;
        ok = manifest_finish(&b);
    }
    ms_buf_free(&b.aliases);
    return ok;
}

const char *ms_project_find_manifest(MsArena *a, const char *filename) {
    const char *directory = ms_path_dir(a, filename);
    for (;;) {
        const char *manifest = MS_PATH_JOIN(a, directory, "ms.toml");
        struct stat info;
        if (stat(manifest, &info) == 0) {
            return manifest;
        }
        const char *parent = ms_path_dir(a, directory);
        if (strcmp(parent, directory) == 0) {
            return NULL;
        }
        directory = parent;
    }
}
