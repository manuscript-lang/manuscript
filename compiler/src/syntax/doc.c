/* Documentation comments (ms/doc.h). */
#include "ms/doc.h"
#include <stdlib.h>

static bool doc_is_space(char ch) { return ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' || ch == '\f' || ch == '\v'; }

static bool doc_is_alnum(char ch) { return (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z'); }

static MsStr doc_trim_start(MsStr s) {
    while (s.len > 0 && doc_is_space(s.ptr[0])) {
        s.ptr++;
        s.len--;
    }
    return s;
}

static MsStr doc_trim_end(MsStr s) {
    while (s.len > 0 && doc_is_space(s.ptr[s.len - 1])) {
        s.len--;
    }
    return s;
}

static MsStr doc_trim(MsStr s) { return doc_trim_end(doc_trim_start(s)); }

static bool doc_is(MsStr s, const char *text) { return s.len == strlen(text) && memcmp(s.ptr, text, s.len) == 0; }

static MsStr doc_trim_cr(MsStr s) {
    while (s.len > 0 && s.ptr[s.len - 1] == '\r') {
        s.len--;
    }
    return s;
}

size_t ms_doc_indent_columns(MsStr line) {
    size_t columns = 0;
    for (uint32_t i = 0; i < line.len && (line.ptr[i] == ' ' || line.ptr[i] == '\t'); i++) {
        columns += line.ptr[i] == '\t' ? 4 : 1;
    }
    return columns;
}

/* ---- the lines above a position, nearest first ---- */

typedef struct DocLines {
    MsStr source;
    size_t rest; /* the text before this offset is not split yet */
    bool more;
    MsStr *lines;
    size_t count, cap;
} DocLines;

static void doc_lines_init(DocLines *l, MsStr source, size_t line_start) {
    size_t end = line_start < source.len ? line_start : source.len;
    if (end > 0 && source.ptr[end - 1] == '\n') {
        end--;
    }
    *l = (DocLines){.source = source, .rest = end, .more = end > 0};
}

/* Splits lines off the end until line `upto` exists; false when the text ends first. */
static bool doc_lines_fill(DocLines *l, size_t upto) {
    while (l->count <= upto) {
        if (!l->more) {
            return false;
        }
        size_t at = l->rest;
        while (at > 0 && l->source.ptr[at - 1] != '\n') {
            at--;
        }
        if (l->count == l->cap) {
            l->cap = l->cap != 0 ? l->cap * 2 : 8;
            l->lines = ms_array_resize(l->lines, (uint32_t)l->cap, sizeof *l->lines);
        }
        l->lines[l->count++] = (MsStr){l->source.ptr + at, (uint32_t)(l->rest - at)};
        if (at == 0) {
            l->more = false;
            l->rest = 0;
        } else {
            l->rest = at - 1;
        }
    }
    return true;
}

/* The text of a block comment given as whole lines, first to last: markers removed, the common
 * indentation of the interior lines removed, and the blank lines next to the markers dropped. */
static void doc_block_text(MsBuf *out, const MsStr *lines, size_t n) {
    MsStr first = doc_trim_start(lines[0]);
    first = ms_str_starts(first, "/*") ? (MsStr){first.ptr + 2, first.len - 2} : (MsStr){first.ptr, 0};
    MsStr last = doc_trim_cr(doc_trim_end(lines[n - 1]));
    if (ms_str_ends(last, "*/")) {
        last.len -= 2;
    }
    if (n == 1) {
        if (ms_str_ends(first, "*/")) {
            first.len -= 2;
        }
        const MsStr one = doc_trim(first);
        ms_buf_put(out, one.ptr, one.len);
        return;
    }
    MsStr *rows = malloc((n + 1) * sizeof *rows);
    if (rows == NULL) {
        ms_oom();
    }
    rows[0] = doc_trim_end(first);
    for (size_t i = 1; i + 1 < n; i++) {
        rows[i] = doc_trim_end(lines[i]);
    }
    rows[n - 1] = doc_trim_end(last);
    size_t common = SIZE_MAX;
    for (size_t i = 1; i < n; i++) {
        if (doc_trim(rows[i]).len != 0) {
            const size_t lead = rows[i].len - doc_trim_start(rows[i]).len;
            common = lead < common ? lead : common;
        }
    }
    common = common == SIZE_MAX ? 0 : common;
    for (size_t i = 0; i < n; i++) {
        if (i == 0) {
            rows[i] = doc_trim_start(rows[i]);
        } else {
            rows[i] = rows[i].len >= common ? (MsStr){rows[i].ptr + common, (uint32_t)(rows[i].len - common)} : (MsStr){rows[i].ptr, 0};
        }
    }
    size_t from = 0, to = n;
    while (from < to && doc_trim(rows[from]).len == 0) {
        from++;
    }
    while (to > from && doc_trim(rows[to - 1]).len == 0) {
        to--;
    }
    for (size_t i = from; i < to; i++) {
        if (i > from) {
            ms_buf_putc(out, '\n');
        }
        ms_buf_put(out, rows[i].ptr, rows[i].len);
    }
    free(rows);
}

typedef struct DocBlock {
    size_t start, len; /* in the output buffer */
} DocBlock;

void ms_doc_comments_above(MsBuf *out, MsStr source, size_t line_start, bool has_indent, size_t indent) {
    DocLines l;
    doc_lines_init(&l, source, line_start);
    /* Blocks come nearest first; each is built in a scratch buffer, then written in reverse. */
    MsBuf scratch = {0};
    DocBlock *blocks = NULL;
    size_t nblocks = 0, cap = 0;
    size_t used = 0;
    for (;;) {
        if (!doc_lines_fill(&l, used)) {
            break;
        }
        const MsStr line = doc_trim_cr(l.lines[used]);
        if (has_indent && ms_doc_indent_columns(line) != indent) {
            break;
        }
        const MsStr text = doc_trim(line);
        size_t block_from = scratch.len;
        if (ms_str_starts(text, "// ms:")) {
            used++;
            continue;
        }
        if (ms_str_starts(text, "//")) {
            MsStr comment = {text.ptr + 2, text.len - 2};
            if (comment.len > 0 && comment.ptr[0] == ' ') {
                comment.ptr++;
                comment.len--;
            }
            comment = doc_trim_end(comment);
            ms_buf_put(&scratch, comment.ptr, comment.len);
            used++;
        } else if (ms_str_ends(text, "*/")) {
            size_t open = used;
            bool found = false;
            while (doc_lines_fill(&l, open)) {
                if (ms_str_starts(doc_trim_start(l.lines[open]), "/*")) {
                    found = true;
                    break;
                }
                open++;
            }
            if (!found || (has_indent && ms_doc_indent_columns(l.lines[open]) != indent)) {
                break;
            }
            const size_t n = open - used + 1;
            MsStr *forward = malloc(n * sizeof *forward);
            if (forward == NULL) {
                ms_oom();
            }
            for (size_t i = 0; i < n; i++) {
                forward[i] = l.lines[open - i];
            }
            doc_block_text(&scratch, forward, n);
            free(forward);
            used = open + 1;
        } else {
            break;
        }
        if (nblocks == cap) {
            cap = cap != 0 ? cap * 2 : 8;
            blocks = ms_array_resize(blocks, (uint32_t)cap, sizeof *blocks);
        }
        blocks[nblocks++] = (DocBlock){block_from, scratch.len - block_from};
    }
    for (size_t i = nblocks; i > 0; i--) {
        if (i < nblocks) {
            ms_buf_putc(out, '\n');
        }
        ms_buf_put(out, scratch.data + blocks[i - 1].start, blocks[i - 1].len);
    }
    free(blocks);
    ms_buf_free(&scratch);
    free(l.lines);
}

/* The end of the text literal that starts at `s[0]` (`"` or `f"`), or 0 when it is not closed. */
size_t ms_doc_text_end(MsStr s) {
    size_t i = 0;
    const bool formatted = s.len > 0 && s.ptr[0] == 'f';
    if (formatted) {
        i++;
    }
    i++; /* the opening quote */
    int depth = 0;
    while (i < s.len) {
        const char ch = s.ptr[i];
        if (ch == '\\') {
            i += 2;
        } else if (formatted && ch == '{') {
            depth++;
            i++;
        } else if (formatted && ch == '}' && depth > 0) {
            depth--;
            i++;
        } else if (ch == '"' && depth > 0) {
            const size_t end = ms_doc_text_end((MsStr){s.ptr + i, (uint32_t)(s.len - i)});
            if (end == 0) {
                return 0;
            }
            i += end;
        } else if (ch == '"') {
            return i + 1;
        } else {
            i++;
        }
    }
    return 0;
}

/* The `//` comment that follows code on the line holding `offset`, without its marker. */
static void doc_trailing_comment(MsBuf *out, MsStr source, size_t offset) {
    size_t start = offset;
    while (start > 0 && source.ptr[start - 1] != '\n') {
        start--;
    }
    size_t end = start;
    while (end < source.len && source.ptr[end] != '\n') {
        end++;
    }
    MsStr line = doc_trim_cr((MsStr){source.ptr + start, (uint32_t)(end - start)});
    size_t i = 0;
    while (i < line.len) {
        if (line.ptr[i] == '"') {
            const bool formatted = i > 0 && line.ptr[i - 1] == 'f' &&
                                   (i == 1 || !(doc_is_alnum(line.ptr[i - 2]) || line.ptr[i - 2] == '_'));
            const size_t from = i - (formatted ? 1u : 0u);
            const size_t length = ms_doc_text_end((MsStr){line.ptr + from, (uint32_t)(line.len - from)});
            if (length == 0) {
                return;
            }
            i = from + length;
            continue;
        }
        if (line.ptr[i] == '/' && i + 1 < line.len && line.ptr[i + 1] == '/') {
            if (doc_trim((MsStr){line.ptr, (uint32_t)i}).len == 0) {
                return;
            }
            MsStr rest = {line.ptr + i + 2, (uint32_t)(line.len - i - 2)};
            if (rest.len > 0 && rest.ptr[0] == ' ') {
                rest.ptr++;
                rest.len--;
            }
            rest = doc_trim_end(rest);
            ms_buf_put(out, rest.ptr, rest.len);
            return;
        }
        i++;
    }
}

void ms_doc_leading_comment(MsBuf *out, MsStr source, size_t offset) {
    if (offset > source.len) {
        return;
    }
    size_t line_start = offset;
    while (line_start > 0 && source.ptr[line_start - 1] != '\n') {
        line_start--;
    }
    const MsStr own_line = {source.ptr + line_start, (uint32_t)(offset - line_start)};
    const MsStr prefix = doc_trim(own_line);
    /* Names of cases and operations follow their keyword; a receiver method's name follows its
     * receiver (`fn Type.name`). Inline payload fields do not begin a declaration line. */
    const bool receiver_method = ms_str_starts(prefix, "fn ") && ms_str_ends(prefix, ".");
    if (!(prefix.len == 0 || doc_is(prefix, "export") || doc_is(prefix, "fn") || doc_is(prefix, "var fn") ||
          doc_is(prefix, "move fn") || doc_is(prefix, "case") || receiver_method)) {
        return;
    }
    const size_t before = out->len;
    ms_doc_comments_above(out, source, line_start, true, ms_doc_indent_columns(own_line));
    if (out->len == before) {
        doc_trailing_comment(out, source, offset);
    }
}

size_t ms_doc_effect_lines(MsStr source, size_t offset, MsStr *names, size_t max) {
    if (offset > source.len) {
        return 0;
    }
    size_t line_start = offset;
    while (line_start > 0 && source.ptr[line_start - 1] != '\n') {
        line_start--;
    }
    DocLines l;
    doc_lines_init(&l, source, line_start);
    size_t count = 0;
    for (size_t i = 0; doc_lines_fill(&l, i); i++) {
        const MsStr line = doc_trim_start(doc_trim_cr(l.lines[i]));
        if (!ms_str_starts(line, "//")) {
            break;
        }
        if (ms_str_starts(line, "// ms: effect ") && count < max) {
            names[count++] = doc_trim((MsStr){line.ptr + 14, line.len - 14});
        }
    }
    free(l.lines);
    for (size_t i = 0; i < count / 2; i++) { /* collected nearest first */
        const MsStr t = names[i];
        names[i] = names[count - 1 - i];
        names[count - 1 - i] = t;
    }
    return count;
}
