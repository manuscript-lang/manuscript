/* Edits to ms.toml for `ms add` and `ms remove`: the dependency tables change and every comment and the formatting
 * of the rest of the file stay. Port of crates/ms-driver/src/project/edit.rs, byte for byte on the manifests the C
 * reader covers; a form the line scanner does not understand is MS_PERR_UNSUPPORTED, so the Rust editor handles it.
 *
 * The file is a list of lines. A comment or blank line belongs to the item that follows it, as in toml_edit: removing
 * an entry removes the comments above it, and a new table goes after the last entry, before the file's trailing
 * comments. */
#include <string.h>

#include "ms/project.h"

typedef enum EditLineKind { EDIT_BLANK, EDIT_COMMENT, EDIT_HEADER, EDIT_KEY } EditLineKind;

typedef struct EditLine {
    const char *text; /* without its newline */
    uint32_t length;
    EditLineKind kind;
    const char *name;  /* a header's table, or a key's name */
    const char *table; /* the table a key is in: "" before the first header */
    bool dropped;
} EditLine;

typedef struct EditLines {
    EditLine *items;
    uint32_t count;
} EditLines;

static bool edit_unsupported(MsProjectError *err, const char *what) {
    ms_project_error_unsupported(err, what);
    return false;
}

static bool edit_bare_char(char c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-';
}

/* The key or table name at `*p` (bare, or quoted without escapes), advancing past it. NULL when it is neither. */
static const char *edit_name(MsArena *a, const char **p, const char *end) {
    const char *s = *p;
    if (s < end && *s == '"') {
        const char *close = memchr(s + 1, '"', (size_t)(end - s - 1));
        if (close == NULL || memchr(s + 1, '\\', (size_t)(close - s - 1)) != NULL) {
            return NULL;
        }
        *p = close + 1;
        return ms_arena_strndup(a, s + 1, (size_t)(close - s - 1));
    }
    const char *e = s;
    while (e < end && edit_bare_char(*e)) {
        e++;
    }
    if (e == s) {
        return NULL;
    }
    *p = e;
    return ms_arena_strndup(a, s, (size_t)(e - s));
}

static const char *edit_skip_blanks(const char *p, const char *end) {
    while (p < end && (*p == ' ' || *p == '\t')) {
        p++;
    }
    return p;
}

/* True when the value text ends on this line: its strings are closed and its brackets balanced. */
static bool edit_value_complete(const char *p, const char *end) {
    int depth = 0;
    for (; p < end; p++) {
        if (*p == '"' || *p == '\'') {
            const char quote = *p++;
            while (p < end && *p != quote) {
                p += (quote == '"' && *p == '\\' && p + 1 < end) ? 2 : 1;
            }
            if (p >= end) {
                return false;
            }
        } else if (*p == '#') {
            break;
        } else if (*p == '[' || *p == '{') {
            depth++;
        } else if (*p == ']' || *p == '}') {
            depth--;
        }
    }
    return depth == 0;
}

static bool edit_scan_line(MsArena *a, EditLine *line, const char **table, MsProjectError *err) {
    const char *p = edit_skip_blanks(line->text, line->text + line->length);
    const char *end = line->text + line->length;
    line->table = *table;
    if (p == end) {
        line->kind = EDIT_BLANK;
        return true;
    }
    if (*p == '#') {
        line->kind = EDIT_COMMENT;
        return true;
    }
    if (*p == '[') {
        p = edit_skip_blanks(p + 1, end);
        const char *name = edit_name(a, &p, end);
        p = name == NULL ? p : edit_skip_blanks(p, end);
        if (name == NULL || p >= end || *p != ']') {
            return edit_unsupported(err, "a table header the manifest editor does not read");
        }
        p = edit_skip_blanks(p + 1, end);
        if (p != end && *p != '#') {
            return edit_unsupported(err, "a table header the manifest editor does not read");
        }
        line->kind = EDIT_HEADER;
        line->name = name;
        *table = name;
        return true;
    }
    const char *name = edit_name(a, &p, end);
    p = name == NULL ? p : edit_skip_blanks(p, end);
    if (name == NULL || p >= end || *p != '=' || !edit_value_complete(p + 1, end)) {
        return edit_unsupported(err, "a manifest line the manifest editor does not read");
    }
    if ((*table)[0] == 0 && (strcmp(name, "dependencies") == 0 || strcmp(name, "effects") == 0)) {
        return edit_unsupported(err, "a dependencies or effects table written as a key");
    }
    line->kind = EDIT_KEY;
    line->name = name;
    return true;
}

static bool edit_split(MsArena *a, const char *text, EditLines *lines, MsProjectError *err) {
    uint32_t count = 0;
    for (const char *p = text; *p != 0; p++) {
        count += (*p == '\n') || (p[1] == 0);
    }
    lines->items = MS_NEW_N(a, EditLine, count + 1);
    lines->count = 0;
    const char *table = "";
    for (const char *p = text; *p != 0;) {
        const char *newline = strchr(p, '\n');
        const char *end = newline != NULL ? newline : p + strlen(p);
        EditLine *line = &lines->items[lines->count++];
        line->text = p;
        line->length = (uint32_t)(end - p);
        if (!edit_scan_line(a, line, &table, err)) {
            return false;
        }
        p = newline != NULL ? newline + 1 : end;
    }
    return true;
}

/* The header of table `name`, -1 when there is none; unsupported when it is written twice or as `[name.x]`. */
static bool edit_find_table(const EditLines *lines, const char *name, int *header, MsProjectError *err) {
    const size_t length = strlen(name);
    *header = -1;
    for (uint32_t i = 0; i < lines->count; i++) {
        const EditLine *line = &lines->items[i];
        if (line->kind != EDIT_HEADER) {
            continue;
        }
        if (strncmp(line->name, name, length) == 0 && line->name[length] == '.') {
            return edit_unsupported(err, "a sub-table of dependencies or effects");
        }
        if (strcmp(line->name, name) == 0) {
            if (*header >= 0) {
                return edit_unsupported(err, "a table written twice");
            }
            *header = (int)i;
        }
    }
    return true;
}

/* The line of the last entry of the table at `header`, or the header itself when it has none. */
static int edit_last_entry(const EditLines *lines, int header) {
    int last = header;
    for (uint32_t i = (uint32_t)header + 1; i < lines->count && lines->items[i].kind != EDIT_HEADER; i++) {
        if (lines->items[i].kind == EDIT_KEY) {
            last = (int)i;
        }
    }
    return last;
}

static int edit_find_key(const EditLines *lines, int header, const char *name) {
    for (uint32_t i = (uint32_t)header + 1; i < lines->count && lines->items[i].kind != EDIT_HEADER; i++) {
        if (lines->items[i].kind == EDIT_KEY && strcmp(lines->items[i].name, name) == 0) {
            return (int)i;
        }
    }
    return -1;
}

static int edit_entry_count(const EditLines *lines, int header) {
    int count = 0;
    for (uint32_t i = (uint32_t)header + 1; i < lines->count && lines->items[i].kind != EDIT_HEADER; i++) {
        count += lines->items[i].kind == EDIT_KEY && !lines->items[i].dropped;
    }
    return count;
}

/* Marks the blank and comment lines just above `index`, which belong to it, and `index` itself. */
static void edit_drop_with_prefix(EditLines *lines, int index) {
    int first = index;
    while (first > 0 && (lines->items[first - 1].kind == EDIT_BLANK || lines->items[first - 1].kind == EDIT_COMMENT)) {
        first--;
    }
    for (int i = first; i <= index; i++) {
        lines->items[i].dropped = true;
    }
}

static const char *edit_quote(MsArena *a, const char *s, MsProjectError *err) {
    for (const char *p = s; *p != 0; p++) {
        if (*p == '"' || *p == '\\' || (unsigned char)*p < 0x20 || *p == 0x7f) {
            ms_project_error_unsupported(err, "a quote, backslash or control character in a manifest value");
            return NULL;
        }
    }
    return ms_arena_fmt(a, "\"%s\"", s).ptr;
}

static const char *edit_key(MsArena *a, const char *name, MsProjectError *err) {
    bool bare = name[0] != 0;
    for (const char *p = name; *p != 0; p++) {
        bare = bare && edit_bare_char(*p);
    }
    return bare ? name : edit_quote(a, name, err);
}

/* The text with `entry` (one line) added to `table`, which is created after the last entry of the file when absent. */
static const char *edit_insert(MsArena *a, const EditLines *lines, int header, const char *table, const char *entry, int replace) {
    MsBuf out = {0};
    int after = header >= 0 ? edit_last_entry(lines, header) : -1;
    int content = -1;
    for (uint32_t i = 0; i < lines->count; i++) {
        content = lines->items[i].kind == EDIT_HEADER || lines->items[i].kind == EDIT_KEY ? (int)i : content;
    }
    for (uint32_t i = 0; i < lines->count; i++) {
        if ((int)i != replace) {
            ms_buf_put(&out, lines->items[i].text, lines->items[i].length);
        } else {
            ms_buf_puts(&out, entry);
        }
        ms_buf_putc(&out, '\n');
        if ((int)i == after && replace < 0) {
            ms_buf_printf(&out, "%s\n", entry);
        }
        if (header < 0 && (int)i == content) {
            ms_buf_printf(&out, "\n[%s]\n%s\n", table, entry);
        }
    }
    if (header < 0 && lines->count == 0) {
        ms_buf_printf(&out, "[%s]\n%s\n", table, entry);
    }
    const char *text = ms_arena_strndup(a, out.data == NULL ? "" : out.data, out.len);
    ms_buf_free(&out);
    return text;
}

/* `text` with its line endings turned to `\n`, and whether they were `\r\n`. */
static const char *edit_normalise(MsArena *a, const char *text, bool *crlf) {
    *crlf = strstr(text, "\r\n") != NULL;
    if (!*crlf) {
        return text;
    }
    MsBuf out = {0};
    for (const char *p = text; *p != 0; p++) {
        if (!(p[0] == '\r' && p[1] == '\n')) {
            ms_buf_putc(&out, *p);
        }
    }
    const char *plain = ms_arena_strndup(a, out.data == NULL ? "" : out.data, out.len);
    ms_buf_free(&out);
    return plain;
}

static const char *edit_restore(MsArena *a, const char *text, bool crlf) {
    if (!crlf) {
        return text;
    }
    MsBuf out = {0};
    for (const char *p = text; *p != 0; p++) {
        if (*p == '\n') {
            ms_buf_putc(&out, '\r');
        }
        ms_buf_putc(&out, *p);
    }
    const char *crlf_text = ms_arena_strndup(a, out.data == NULL ? "" : out.data, out.len);
    ms_buf_free(&out);
    return crlf_text;
}

/* ---- the edits ---- */

static const char *edit_effects_array(MsArena *a, const char *const *effects, uint32_t count, MsProjectError *err) {
    MsBuf out = {0};
    ms_buf_putc(&out, '[');
    for (uint32_t i = 0; i < count; i++) {
        const char *quoted = edit_quote(a, effects[i], err);
        if (quoted == NULL) {
            ms_buf_free(&out);
            return NULL;
        }
        ms_buf_printf(&out, "%s%s", i > 0 ? ", " : "", quoted);
    }
    ms_buf_putc(&out, ']');
    const char *text = ms_arena_strndup(a, out.data, out.len);
    ms_buf_free(&out);
    return text;
}

/* True when a table can be appended to `lines`: the file has an item to follow, or has no line at all. */
static bool edit_can_append(const EditLines *lines) {
    for (uint32_t i = 0; i < lines->count; i++) {
        if (lines->items[i].kind == EDIT_HEADER || lines->items[i].kind == EDIT_KEY) {
            return true;
        }
    }
    return lines->count == 0;
}

bool ms_manifest_add_dependency(MsArena *a, const char *text, const char *name, const char *url, MsPinKind pin, const char *pinned,
                                const char **out, MsProjectError *err) {
    bool crlf;
    EditLines lines;
    int header;
    const char *plain = edit_normalise(a, text, &crlf);
    if (!edit_split(a, plain, &lines, err) || !edit_find_table(&lines, "dependencies", &header, err)) {
        return false;
    }
    if (header >= 0 && edit_find_key(&lines, header, name) >= 0) {
        ms_project_error_message(err, ms_arena_fmt(a, "%s is already in [dependencies]; run `ms remove %s` first, or edit its entry", name, name).ptr);
        return false;
    }
    static const char *const pin_keys[] = {"tag", "sha", "version"};
    const char *key = edit_key(a, name, err);
    const char *quoted_url = edit_quote(a, url, err);
    const char *quoted_pin = edit_quote(a, pinned, err);
    if (key == NULL || quoted_url == NULL || quoted_pin == NULL) {
        return false;
    }
    if (header < 0 && !edit_can_append(&lines)) {
        return edit_unsupported(err, "a manifest without a table");
    }
    const char *entry = ms_arena_fmt(a, "%s = { url = %s, %s = %s }", key, quoted_url, pin_keys[pin], quoted_pin).ptr;
    *out = edit_restore(a, edit_insert(a, &lines, header, "dependencies", entry, -1), crlf);
    return true;
}

bool ms_manifest_allow_effects(MsArena *a, const char *text, const char *name, const char *const *effects, uint32_t count, const char **out,
                               MsProjectError *err) {
    bool crlf;
    EditLines lines;
    int header;
    const char *plain = edit_normalise(a, text, &crlf);
    if (!edit_split(a, plain, &lines, err) || !edit_find_table(&lines, "effects", &header, err)) {
        return false;
    }
    const char *key = edit_key(a, name, err);
    const char *array = edit_effects_array(a, effects, count, err);
    if (key == NULL || array == NULL) {
        return false;
    }
    const int existing = header >= 0 ? edit_find_key(&lines, header, name) : -1;
    if (existing >= 0 && memchr(lines.items[existing].text, '#', lines.items[existing].length) != NULL) {
        return edit_unsupported(err, "an [effects] entry with a comment");
    }
    if (header < 0 && !edit_can_append(&lines)) {
        return edit_unsupported(err, "a manifest without a table");
    }
    const char *entry = ms_arena_fmt(a, "%s = %s", key, array).ptr;
    *out = edit_restore(a, edit_insert(a, &lines, header, "effects", entry, existing), crlf);
    return true;
}

/* Drops `name` from the table at `header` and, when that leaves it empty, the table. */
static void edit_drop_entry(EditLines *lines, int header, const char *name) {
    const int key = edit_find_key(lines, header, name);
    if (key >= 0) {
        edit_drop_with_prefix(lines, key);
    }
    if (edit_entry_count(lines, header) == 0) {
        edit_drop_with_prefix(lines, header);
    }
}

bool ms_manifest_remove_dependency(MsArena *a, const char *text, const char *name, const char **out, MsProjectError *err) {
    bool crlf;
    EditLines lines;
    int dependencies;
    int effects;
    const char *plain = edit_normalise(a, text, &crlf);
    if (!edit_split(a, plain, &lines, err) || !edit_find_table(&lines, "dependencies", &dependencies, err) ||
        !edit_find_table(&lines, "effects", &effects, err)) {
        return false;
    }
    if (dependencies < 0 || edit_find_key(&lines, dependencies, name) < 0) {
        ms_project_error_message(err, ms_arena_fmt(a, "%s is not in [dependencies]", name).ptr);
        return false;
    }
    edit_drop_entry(&lines, dependencies, name);
    if (effects >= 0) {
        edit_drop_entry(&lines, effects, name);
    }
    MsBuf result = {0};
    for (uint32_t i = 0; i < lines.count; i++) {
        if (!lines.items[i].dropped) {
            ms_buf_put(&result, lines.items[i].text, lines.items[i].length);
            ms_buf_putc(&result, '\n');
        }
    }
    *out = edit_restore(a, ms_arena_strndup(a, result.data == NULL ? "" : result.data, result.len), crlf);
    ms_buf_free(&result);
    return true;
}

const char *ms_manifest_default_name(MsArena *a, const char *url) {
    size_t length = strlen(url);
    while (length > 0 && url[length - 1] == '/') {
        length--;
    }
    size_t start = length;
    while (start > 0 && url[start - 1] != '/' && url[start - 1] != ':') {
        start--;
    }
    const char *base = url + start;
    length -= start;
    if (length >= 4 && memcmp(base + length - 4, ".git", 4) == 0) {
        length -= 4;
    }
    if (length >= 3 && memcmp(base, "ms-", 3) == 0) {
        base += 3;
        length -= 3;
    }
    char *name = MS_NEW_N(a, char, length + 2);
    name[0] = '@';
    for (size_t i = 0; i < length; i++) {
        const char c = base[i];
        name[i + 1] = c == '-' ? '_' : c;
    }
    return ms_manifest_valid_alias(name) ? name : NULL;
}
