/* The source formatter.
 *
 * The formatter keeps the lexer's tokens and comment text. Line passes (indentation, blank lines,
 * imports, comment reflow) work on the text and the tokens of each line; the layout pass
 * (format_layout.c) breaks long expressions at their delimiters; compaction (format_compact.c)
 * rewrites statements into shorter forms. Passes repeat until the text stops changing, so a second
 * run of the formatter changes nothing. */
#include <stdlib.h>

#include "ms/format.h"
#include "ms/walk.h"

#include "format_internal.h"

/* ---- strings, lines and sections ---- */

/* A growable list of strings or tokens, built on the shared buffer. */
typedef struct StrList {
    MsBuf buf;
} StrList;

static void strs_push(StrList *l, Str s) { MS_VEC_PUSH(l->buf, Str, s); }
static size_t strs_len(const StrList *l) { return MS_VEC_LEN(l->buf, Str); }
static Str *strs_at(const StrList *l) { return ms_buf_items(&l->buf); }
static void strs_free(StrList *l) { ms_buf_free(&l->buf); }

/* `text` with "\r\n" replaced by "\n". */
static Str fmt_normalize(Fmt *f, Str text) {
    MsBuf out = {0};
    for (size_t i = 0; i < text.len; i++) {
        if (text.ptr[i] == '\r' && i + 1 < text.len && text.ptr[i + 1] == '\n') {
            continue;
        }
        ms_buf_putc(&out, text.ptr[i]);
    }
    return fmt_take(f, &out);
}

/* The lines of `text` split at '\n': one more than there are newlines. */
static size_t fmt_split_lines(Str text, StrList *lines) {
    size_t start = 0;
    for (size_t i = 0; i <= text.len; i++) {
        if (i == text.len || text.ptr[i] == '\n') {
            strs_push(lines, fmt_slice(text, start, i));
            start = i + 1;
        }
    }
    return strs_len(lines);
}

/* The lines joined by '\n'. */
static Str fmt_join_lines(Fmt *f, const Str *lines, size_t count) {
    MsBuf out = {0};
    for (size_t i = 0; i < count; i++) {
        if (i > 0) {
            ms_buf_putc(&out, '\n');
        }
        fmt_put(&out, lines[i]);
    }
    return fmt_take(f, &out);
}

/* The columns of leading whitespace in `line`, a tab counting four. */
static size_t fmt_indent_columns(Str line) {
    size_t columns = 0;
    for (size_t i = 0; i < line.len && (line.ptr[i] == ' ' || line.ptr[i] == '\t'); i++) {
        columns += line.ptr[i] == '\t' ? 4 : 1;
    }
    return columns;
}

/* Writes each full group of four leading spaces as a tab, one token per level; spaces left over
 * align continuation lines. The formatter works in spaces and converts once on exit. */
static Str fmt_tabify(Fmt *f, Str text) {
    MsBuf out = {0};
    size_t start = 0;
    for (size_t i = 0; i <= text.len; i++) {
        if (i < text.len && text.ptr[i] != '\n') {
            continue;
        }
        const Str line = fmt_slice(text, start, i);
        const size_t spaces = fmt_indent_of(line);
        if (start > 0) {
            ms_buf_putc(&out, '\n');
        }
        for (size_t tab = 0; tab < spaces / 4; tab++) {
            ms_buf_putc(&out, '\t');
        }
        fmt_put(&out, fmt_slice(line, spaces / 4 * 4, line.len));
        start = i + 1;
    }
    return fmt_take(f, &out);
}

/* Replaces each tab in a code line's leading whitespace with four spaces, leaving lines inside
 * multi-line text and block comments untouched. */
static bool fmt_expand_indent_tabs(Fmt *f, Str text, Str *out) {
    MsArena scratch = {0};
    MsLexed lexed;
    if (!fmt_lex(f, &scratch, text, &lexed)) {
        ms_arena_free(&scratch);
        return false;
    }
    MsBuf protected_ranges = {0};
    for (size_t i = 0; i < lexed.ntokens; i++) {
        const MsToken *t = &lexed.tokens[i];
        if (t->kind == MS_T_String && fmt_contains(fmt_token_text(text, t), "\n")) {
            MS_VEC_PUSH(protected_ranges, MsRange, ((MsRange){t->lo, t->hi}));
        }
    }
    for (size_t i = 0; i < lexed.nblocks; i++) {
        MS_VEC_PUSH(protected_ranges, MsRange, lexed.blocks[i]);
    }
    const MsRange *ranges = ms_buf_items(&protected_ranges);
    const size_t nranges = MS_VEC_LEN(protected_ranges, MsRange);
    MsBuf result = {0};
    size_t at = 0;
    while (at < text.len) {
        size_t end = at;
        while (end < text.len && text.ptr[end] != '\n') {
            end++;
        }
        if (end < text.len) {
            end++; // the line keeps its newline
        }
        const Str line = fmt_slice(text, at, end);
        bool inside = false;
        for (size_t k = 0; k < nranges; k++) {
            inside = inside || (ranges[k].start < at && at < ranges[k].end);
        }
        const Str body = fmt_trim_start_set(line, " \t");
        if (inside || line.ptr[0] != '\t') {
            fmt_put(&result, line);
        } else {
            for (size_t i = 0; i < line.len - body.len; i++) {
                ms_buf_puts(&result, line.ptr[i] == '\t' ? "    " : " ");
            }
            fmt_put(&result, body);
        }
        at = end;
    }
    ms_buf_free(&protected_ranges);
    ms_arena_free(&scratch);
    *out = fmt_take(f, &result);
    return true;
}

/* ---- literal text that the line passes cannot see ---- */

/* Removes `columns` of leading whitespace, a tab counting four; false when the line lacks them or
 * a tab would be split. */
static bool fmt_strip_columns(Str line, size_t columns, Str *rest) {
    size_t taken = 0;
    for (size_t at = 0; at < line.len; at++) {
        if (taken == columns) {
            *rest = fmt_slice(line, at, line.len);
            return true;
        }
        if (line.ptr[at] == ' ') {
            taken += 1;
        } else if (line.ptr[at] == '\t') {
            taken += 4;
        } else {
            return false;
        }
        if (taken > columns) {
            return false;
        }
    }
    *rest = fmt_lit("");
    return taken == columns;
}

/* Moves every line after the first of `text` from indentation `before` to `after`; the text is
 * unchanged when a line lacks the indentation to give up. */
static Str fmt_shift_lines(Fmt *f, Str text, size_t before, size_t after) {
    MsBuf out = {0};
    size_t start = 0;
    bool first = true;
    for (size_t i = 0; i <= text.len; i++) {
        if (i < text.len && text.ptr[i] != '\n') {
            continue;
        }
        const Str line = fmt_slice(text, start, i);
        start = i + 1;
        if (first) {
            fmt_put(&out, line);
            first = false;
            continue;
        }
        ms_buf_putc(&out, '\n');
        Str rest;
        if (line.len == 0) {
            continue;
        }
        if (after >= before) {
            fmt_spaces(&out, after - before);
            fmt_put(&out, line);
        } else if (fmt_strip_columns(line, before - after, &rest)) {
            fmt_put(&out, rest);
        } else {
            ms_buf_free(&out);
            return text;
        }
    }
    return fmt_take(f, &out);
}

typedef struct Span {
    size_t lo, hi;
    bool block;
} Span;

static int span_order(const void *a, const void *b) {
    const Span *x = a;
    const Span *y = b;
    if (x->lo != y->lo) {
        return x->lo < y->lo ? -1 : 1;
    }
    if (x->hi != y->hi) {
        return x->hi < y->hi ? -1 : 1;
    }
    return (int)x->block - (int)y->block;
}

/* A private-use marker absent from `text`, for placeholders that survive the line passes. */
static Str fmt_marker(Fmt *f, Str text) {
    for (uint32_t c = 0xE000; c <= 0xF8FF; c++) {
        MsBuf encoded = {0};
        ms_utf8_put(&encoded, c);
        if (fmt_find(text, fmt_str(encoded.data, encoded.len)) == FMT_NONE) {
            return fmt_take(f, &encoded);
        }
        ms_buf_free(&encoded);
    }
    for (size_t i = 0;; i++) {
        const Str candidate = ms_arena_fmt(f->arena, "\xee\x80\x80%zu\xee\x80\x80", i);
        if (fmt_find(text, candidate) == FMT_NONE) {
            return candidate;
        }
    }
}

static Str fmt_placeholder(Fmt *f, Str marker, size_t index, bool block) {
    return block ? ms_arena_fmt(f->arena, "//%.*s%zu%.*s", (int)marker.len, marker.ptr, index, (int)marker.len,
                                marker.ptr)
                 : ms_arena_fmt(f->arena, "\"%.*s%zu\"", (int)marker.len, marker.ptr, index);
}

static bool format_lines(Fmt *f, Str source, Str *out);

/* The multi-line string literals and block comments of `source`, in `spans`. False when the text
 * does not lex. */
static bool fmt_literal_spans(Fmt *f, Str source, MsBuf *spans) {
    MsArena scratch = {0};
    MsLexed lexed;
    if (!fmt_lex(f, &scratch, source, &lexed)) {
        ms_arena_free(&scratch);
        return false;
    }
    for (size_t i = 0; i < lexed.ntokens; i++) {
        const MsToken *t = &lexed.tokens[i];
        if (t->kind == MS_T_String && fmt_contains(fmt_token_text(source, t), "\n")) {
            MS_VEC_PUSH(*spans, Span, ((Span){t->lo, t->hi, false}));
        }
    }
    for (size_t i = 0; i < lexed.nblocks; i++) {
        MS_VEC_PUSH(*spans, Span, ((Span){lexed.blocks[i].start, lexed.blocks[i].end, true}));
    }
    ms_arena_free(&scratch);
    return true;
}

/* `source` with a one-line placeholder in place of each span. */
static Str fmt_mask_spans(Fmt *f, Str source, Str marker, const Span *spans, size_t nspans) {
    MsBuf masked = {0};
    size_t copied = 0;
    for (size_t i = 0; i < nspans; i++) {
        fmt_put(&masked, fmt_slice(source, copied, spans[i].lo));
        fmt_put(&masked, fmt_placeholder(f, marker, i, spans[i].block));
        copied = spans[i].hi;
    }
    fmt_put(&masked, fmt_slice(source, copied, source.len));
    return fmt_take(f, &masked);
}

/* `formatted` with each placeholder replaced by the span's original text, shifted to the
 * indentation of the line it landed on. */
static Str fmt_unmask_spans(Fmt *f, Str source, Str formatted, Str marker, const Span *spans, size_t nspans) {
    MsBuf result = {0};
    size_t copied = 0;
    for (size_t i = 0; i < nspans; i++) {
        const Str text = fmt_slice(source, spans[i].lo, spans[i].hi);
        const size_t line_break = fmt_rfind_byte(fmt_slice(source, 0, spans[i].lo), '\n');
        const size_t line_start = line_break == FMT_NONE ? 0 : line_break + 1;
        const size_t before = fmt_indent_of(fmt_slice(source, line_start, source.len));
        const Str placeholder = fmt_placeholder(f, marker, i, spans[i].block);
        const size_t at = copied + fmt_find(fmt_slice(formatted, copied, formatted.len), placeholder);
        fmt_put(&result, fmt_slice(formatted, copied, at));
        const Str so_far = fmt_tail(&result, 0);
        const size_t last_break = fmt_rfind_byte(so_far, '\n');
        const size_t result_line_start = last_break == FMT_NONE ? 0 : last_break + 1;
        const size_t after = fmt_indent_columns(fmt_slice(so_far, result_line_start, so_far.len));
        fmt_put(&result, fmt_shift_lines(f, text, before, after));
        copied = at + placeholder.len;
    }
    fmt_put(&result, fmt_slice(formatted, copied, formatted.len));
    return fmt_take(f, &result);
}

/* One formatting pass over `source`. */
static bool format_once(Fmt *f, Str source, Str *out) {
    MsArena scratch = {0};
    MsModule module;
    const bool valid = fmt_parse(f, &scratch, source, &module);
    ms_arena_free(&scratch);
    if (!valid) {
        return false;
    }
    Str normalized = fmt_normalize(f, source);
    if (fmt_contains(normalized, "\t") && !fmt_expand_indent_tabs(f, normalized, &normalized)) {
        return false;
    }
    MsBuf spans = {0};
    if (!fmt_literal_spans(f, normalized, &spans)) {
        return false;
    }
    const size_t nspans = MS_VEC_LEN(spans, Span);
    Span *list = ms_buf_items(&spans);
    Str lined;
    if (nspans == 0) {
        ms_buf_free(&spans);
        if (!format_lines(f, normalized, &lined)) {
            return false;
        }
        *out = fmt_tabify(f, lined);
        return true;
    }
    qsort(list, nspans, sizeof *list, span_order);
    // The line-based passes cannot see inside a multi-line text literal, so a one-line placeholder
    // stands in for each and the literal text returns afterwards, shifted with the line it lands on.
    const Str marker = fmt_marker(f, normalized);
    const Str masked = fmt_mask_spans(f, normalized, marker, list, nspans);
    const bool formatted_ok = format_lines(f, masked, &lined);
    if (formatted_ok) {
        const Str formatted = fmt_tabify(f, lined);
        *out = fmt_unmask_spans(f, normalized, formatted, marker, list, nspans);
    }
    ms_buf_free(&spans);
    if (!formatted_ok) {
        return false;
    }
    MsArena check = {0};
    const bool ok = fmt_parse(f, &check, *out, &module);
    ms_arena_free(&check);
    return ok;
}

/* ---- imports ---- */

/* Import section of a module path: public standard library, standard-library internals, then
 * everything else. `path` includes its opening quote. */
static int fmt_import_section(Str path) {
    if (fmt_starts(path, "\"@std/internal/")) {
        return 1;
    }
    return fmt_starts(path, "\"@std/") ? 0 : 2;
}

typedef struct ImportClause {
    Str *names;
    size_t nnames;
    Str path;
} ImportClause;

typedef struct ImportStatement {
    size_t lo, hi;
    ImportClause *clauses;
    size_t nclauses;
    bool commented; /* a comment splits the runs around this import */
} ImportStatement;

static int str_order(const void *a, const void *b) { return fmt_compare(*(const Str *)a, *(const Str *)b); }

typedef struct MergedImport {
    Str path;
    StrList names;
} MergedImport;

static int merged_order(const void *a, const void *b) {
    const MergedImport *x = a;
    const MergedImport *y = b;
    const int sections = fmt_import_section(x->path) - fmt_import_section(y->path);
    return sections != 0 ? sections : str_order(&x->path, &y->path);
}

/* The names joined by ", ". */
static void fmt_put_joined(MsBuf *out, const Str *names, size_t count) {
    for (size_t i = 0; i < count; i++) {
        if (i > 0) {
            ms_buf_puts(out, ", ");
        }
        fmt_put(out, names[i]);
    }
}

static Str fmt_render_imports(Fmt *f, MergedImport *merged, size_t count) {
    MsBuf out = {0};
    if (count == 1) {
        const Str *names = strs_at(&merged[0].names);
        const size_t n = strs_len(&merged[0].names);
        MsBuf flat = {0};
        ms_buf_puts(&flat, "import ");
        fmt_put_joined(&flat, names, n);
        ms_buf_puts(&flat, " from ");
        fmt_put(&flat, merged[0].path);
        if (fmt_chars(fmt_tail(&flat, 0)) <= FMT_WIDTH) {
            return fmt_take(f, &flat);
        }
        ms_buf_free(&flat);
        ms_buf_puts(&out, "import (\n");
        for (size_t i = 0; i < n; i++) {
            ms_buf_puts(&out, "    ");
            fmt_put(&out, names[i]);
            ms_buf_puts(&out, ",\n");
        }
        ms_buf_puts(&out, ") from ");
        fmt_put(&out, merged[0].path);
        return fmt_take(f, &out);
    }
    ms_buf_puts(&out, "import (\n");
    for (size_t k = 0; k < count; k++) {
        const Str *names = strs_at(&merged[k].names);
        const size_t n = strs_len(&merged[k].names);
        MsBuf flat = {0};
        ms_buf_puts(&flat, "    ");
        fmt_put_joined(&flat, names, n);
        ms_buf_puts(&flat, " from ");
        fmt_put(&flat, merged[k].path);
        ms_buf_putc(&flat, ',');
        if (fmt_chars(fmt_tail(&flat, 0)) <= FMT_WIDTH) {
            fmt_put(&out, fmt_tail(&flat, 0));
            ms_buf_putc(&out, '\n');
            ms_buf_free(&flat);
            continue;
        }
        ms_buf_free(&flat);
        // A clause too wide for a line puts one name on each line.
        for (size_t i = 0; i < n; i++) {
            ms_buf_puts(&out, "    ");
            fmt_put(&out, names[i]);
            if (i + 1 == n) {
                ms_buf_puts(&out, " from ");
                fmt_put(&out, merged[k].path);
            }
            ms_buf_puts(&out, ",\n");
        }
    }
    ms_buf_putc(&out, ')');
    return fmt_take(f, &out);
}

/* The clauses of the import statement that starts at tokens[first] and ends before tokens[end]. */
static ImportStatement fmt_read_import(Fmt *f, Str source, const MsToken *tokens, size_t ntokens, size_t first,
                                       size_t end) {
    ImportStatement stmt = {.lo = tokens[first].lo, .hi = tokens[end - 1].hi};
    StrList names = {0};
    MsBuf clauses = {0};
    for (size_t at = first + 1; at < end; at++) {
        const MsToken *t = &tokens[at];
        const bool clause_end = t->kind == MS_T_Name && fmt_is(fmt_token_text(source, t), "from") &&
                                at + 1 < ntokens && tokens[at + 1].kind == MS_T_String;
        if (clause_end) {
            ImportClause clause = {.nnames = strs_len(&names), .path = fmt_token_text(source, &tokens[at + 1])};
            clause.names = MS_NEW_N(f->arena, Str, clause.nnames);
            if (clause.nnames != 0) {
                memcpy(clause.names, strs_at(&names), clause.nnames * sizeof(Str));
            }
            MS_VEC_PUSH(clauses, ImportClause, clause);
            names.buf.len = 0;
            at++;
        } else if (t->kind == MS_T_Name) {
            strs_push(&names, fmt_token_text(source, t));
        }
    }
    strs_free(&names);
    stmt.nclauses = MS_VEC_LEN(clauses, ImportClause);
    stmt.clauses = MS_NEW_N(f->arena, ImportClause, stmt.nclauses);
    if (stmt.nclauses != 0) {
        memcpy(stmt.clauses, ms_buf_items(&clauses), stmt.nclauses * sizeof(ImportClause));
    }
    ms_buf_free(&clauses);
    stmt.commented = fmt_contains(fmt_slice(source, stmt.lo, stmt.hi), "//");
    return stmt;
}

/* Every top-level import statement, in source order. */
static void fmt_collect_imports(Fmt *f, Str source, const MsToken *tokens, size_t ntokens, MsBuf *statements) {
    size_t i = 0;
    while (i < ntokens) {
        if (tokens[i].kind != MS_T_Import) {
            i++;
            continue;
        }
        size_t end = i + 1;
        while (end < ntokens && tokens[end].kind != MS_T_Newline && tokens[end].kind != MS_T_Eof) {
            end++;
        }
        MS_VEC_PUSH(*statements, ImportStatement, fmt_read_import(f, source, tokens, ntokens, i, end));
        i = end;
    }
}

/* The merged import clause for `path`, added when new. */
static MergedImport *fmt_merged_for(MsBuf *merged_buf, Str path) {
    MergedImport *merged = ms_buf_items(merged_buf);
    const size_t nmerged = MS_VEC_LEN(*merged_buf, MergedImport);
    for (size_t m = 0; m < nmerged; m++) {
        if (fmt_eq(merged[m].path, path)) {
            return &merged[m];
        }
    }
    MS_VEC_PUSH(*merged_buf, MergedImport, ((MergedImport){.path = path}));
    return &MS_VEC_LAST(*merged_buf, MergedImport);
}

/* Sorts the names of a clause and drops duplicates. */
static void fmt_sort_names(StrList *names) {
    Str *items = strs_at(names);
    const size_t n = strs_len(names);
    if (n <= 1) {
        return;
    }
    qsort(items, n, sizeof *items, str_order);
    size_t kept = 1;
    for (size_t j = 1; j < n; j++) {
        if (!fmt_eq(items[j], items[kept - 1])) {
            items[kept++] = items[j];
        }
    }
    names->buf.len = kept * sizeof(Str);
}

/* The canonical text of the imports in list[from, to). */
static Str fmt_render_run(Fmt *f, const ImportStatement *list, size_t from, size_t to) {
    MsBuf merged_buf = {0};
    for (size_t s = from; s < to; s++) {
        for (size_t c = 0; c < list[s].nclauses; c++) {
            const ImportClause *clause = &list[s].clauses[c];
            MergedImport *target = fmt_merged_for(&merged_buf, clause->path);
            for (size_t n = 0; n < clause->nnames; n++) {
                strs_push(&target->names, clause->names[n]);
            }
        }
    }
    MergedImport *merged = ms_buf_items(&merged_buf);
    const size_t nmerged = MS_VEC_LEN(merged_buf, MergedImport);
    for (size_t m = 0; m < nmerged; m++) {
        fmt_sort_names(&merged[m].names);
    }
    if (nmerged > 1) {
        qsort(merged, nmerged, sizeof *merged, merged_order);
    }
    const Str rendered = fmt_render_imports(f, merged, nmerged);
    for (size_t m = 0; m < nmerged; m++) {
        strs_free(&merged[m].names);
    }
    ms_buf_free(&merged_buf);
    return rendered;
}

/* The end of the run of imports that starts at list[from]: nothing but whitespace between them. */
static size_t fmt_import_run_end(Str source, const ImportStatement *list, size_t count, size_t from) {
    size_t run = from + 1;
    while (run < count && fmt_is_blank(fmt_slice(source, list[run - 1].hi, list[run].lo))) {
        run++;
    }
    return run;
}

/* Rewrites each run of adjacent top-level imports (nothing but whitespace between them) into one
 * canonical form: clauses merged per module, names sorted, clauses ordered by section (standard
 * library, internals, other) and path, with a blank line between sections. A single clause that
 * fits on a line is a bare `import names from "path"`; anything else is a grouped `import (...)`
 * with one `names from "path"` clause per line. An import with a comment, inside or after it,
 * stays as written. False when nothing changes. */
static bool fmt_group_imports(Fmt *f, Str source, const MsToken *tokens, size_t ntokens, Str *out) {
    MsBuf statements = {0};
    fmt_collect_imports(f, source, tokens, ntokens, &statements);
    const ImportStatement *list = ms_buf_items(&statements);
    const size_t count = MS_VEC_LEN(statements, ImportStatement);
    MsBuf result = {0};
    size_t copied = 0;
    bool changed = false;
    for (size_t k = 0; k < count;) {
        const size_t first = k;
        const size_t run = fmt_import_run_end(source, list, count, first);
        k = run;
        bool commented = false;
        for (size_t s = first; s < run; s++) {
            commented = commented || list[s].commented;
        }
        if (commented) {
            continue;
        }
        const size_t start = list[first].lo;
        const size_t end = list[run - 1].hi;
        const Str rendered = fmt_render_run(f, list, first, run);
        if (!fmt_eq(fmt_slice(source, start, end), rendered)) {
            fmt_put(&result, fmt_slice(source, copied, start));
            fmt_put(&result, rendered);
            copied = end;
            changed = true;
        }
    }
    ms_buf_free(&statements);
    if (!changed) {
        ms_buf_free(&result);
        return false;
    }
    fmt_put(&result, fmt_slice(source, copied, source.len));
    *out = fmt_take(f, &result);
    return true;
}

/* A bare import list wider than the line wraps into the parenthesized form, one name per line with
 * a trailing comma. Parenthesized imports keep the author's layout, so a second pass leaves the
 * wrapped form unchanged. */
static bool fmt_wrap_import(Fmt *f, const MsToken *parts, size_t nparts, Str flat, Str source, Str *out) {
    if (nparts < 2 || parts[0].kind != MS_T_Import || parts[1].kind == MS_T_LParen || fmt_chars(flat) <= FMT_WIDTH) {
        return false;
    }
    // `from` is also a valid imported name, so the clause boundary is the token just before the
    // path, not the first token spelled `from`.
    size_t path = 0;
    while (path < nparts && parts[path].kind != MS_T_String) {
        path++;
    }
    if (path == nparts || path == 0) {
        return false;
    }
    const size_t from = path - 1;
    if (from == 0 || !fmt_is(fmt_token_text(source, &parts[from]), "from") || from + 1 >= nparts) {
        return false;
    }
    MsBuf text = {0};
    const size_t indent = parts[0].pos.column - 1;
    fmt_spaces(&text, indent);
    ms_buf_puts(&text, "import (\n");
    for (size_t i = 1; i < from; i++) {
        if (parts[i].kind == MS_T_Name) {
            fmt_spaces(&text, indent + 4);
            fmt_put(&text, fmt_token_text(source, &parts[i]));
            ms_buf_puts(&text, ",\n");
        }
    }
    fmt_spaces(&text, indent);
    ms_buf_puts(&text, ") from ");
    fmt_put(&text, fmt_token_text(source, &parts[from + 1]));
    *out = fmt_take(f, &text);
    return true;
}

/* ---- comment reflow ---- */

/* `key: value` lines such as `conform:`, `ms:`, `manuscript:`, `expect-debug:` are data read by
 * tools, so they are never reflowed. */
static bool fmt_directive_key(Str body) {
    size_t start = 0;
    while (start < body.len) {
        uint32_t scalar;
        const size_t width = fmt_scalar_at(body, start, &scalar);
        if (!ms_text_is_unicode_space(scalar)) {
            break;
        }
        start += width;
    }
    size_t end = start;
    while (end < body.len) {
        uint32_t scalar;
        const size_t width = fmt_scalar_at(body, end, &scalar);
        if (ms_text_is_unicode_space(scalar)) {
            break;
        }
        end += width;
    }
    const Str word = fmt_slice(body, start, end);
    const size_t colon = fmt_find_byte(word, ':');
    if (colon == FMT_NONE || colon == 0) {
        return false;
    }
    for (size_t i = 0; i < colon; i++) {
        const char c = word.ptr[i];
        if (!((c >= 'a' && c <= 'z') || c == '-' || c == '_' || c == '.')) {
            return false;
        }
    }
    return true;
}

/* The text of a plain prose comment line (`// text`), or false for anything a reflow must leave
 * alone: code, an empty comment, indented or list or table text, a code fence, tool metadata, or a
 * block-comment placeholder. */
static bool fmt_prose_comment(Str line, Str *body_out) {
    const Str trimmed = fmt_trim_start_set(line, " ");
    if (!fmt_starts(trimmed, "// ")) {
        return false;
    }
    const Str body = fmt_slice(trimmed, 3, trimmed.len);
    if (body.len == 0) {
        return false;
    }
    uint32_t first;
    (void)fmt_scalar_at(body, 0, &first);
    const bool listed = first == '-' || first == '*' || first == '|' || first == '`' || first == '#' ||
                        first == '<' || first == '>' || (first >= 0xE000 && first <= 0xF8FF);
    bool numbered = false;
    const size_t dot = fmt_find(body, fmt_lit(". "));
    if (dot != FMT_NONE) {
        numbered = true;
        for (size_t i = 0; i < dot; i++) {
            numbered = numbered && body.ptr[i] >= '0' && body.ptr[i] <= '9';
        }
    }
    if (ms_text_is_unicode_space(first) || listed || fmt_directive_key(body) || numbered) {
        return false;
    }
    *body_out = body;
    return true;
}

/* Splits comment text into words, keeping a short backtick span whole so code is not broken
 * across lines. The words are appended to `words`. */
static void fmt_comment_words(Fmt *f, Str text, StrList *words) {
    bool open = false;
    size_t at = 0;
    while (at < text.len) {
        // The next whitespace-separated word.
        while (at < text.len) {
            uint32_t scalar;
            const size_t width = fmt_scalar_at(text, at, &scalar);
            if (!ms_text_is_unicode_space(scalar)) {
                break;
            }
            at += width;
        }
        size_t end = at;
        while (end < text.len) {
            uint32_t scalar;
            const size_t width = fmt_scalar_at(text, end, &scalar);
            if (ms_text_is_unicode_space(scalar)) {
                break;
            }
            end += width;
        }
        if (end == at) {
            break;
        }
        const Str word = fmt_slice(text, at, end);
        size_t ticks = 0;
        for (size_t i = 0; i < word.len; i++) {
            ticks += word.ptr[i] == '`';
        }
        const size_t nwords = strs_len(words);
        if (nwords > 0 && open && fmt_chars(strs_at(words)[nwords - 1]) < 60) {
            Str *last = &strs_at(words)[nwords - 1];
            *last = ms_arena_fmt(f->arena, "%.*s %.*s", (int)last->len, last->ptr, (int)word.len, word.ptr);
        } else {
            strs_push(words, word);
        }
        if (ticks % 2 == 1) {
            open = !open;
        }
        at = end;
    }
}

/* Rewraps each paragraph of consecutive prose `//` lines that has a line wider than the formatter
 * width, filling lines greedily up to the width. Paragraphs that already fit, and everything that
 * is not plain prose, are unchanged. */
static void fmt_wrap_comments(Fmt *f, const Str *lines, size_t count, StrList *out) {
    bool fenced = false;
    size_t i = 0;
    while (i < count) {
        const Str trimmed = fmt_trim_start_set(lines[i], " ");
        if (fmt_starts(trimmed, "// ```")) {
            fenced = !fenced;
        }
        Str first;
        if (fenced || !fmt_prose_comment(lines[i], &first)) {
            strs_push(out, lines[i]);
            i++;
            continue;
        }
        const size_t indent = lines[i].len - trimmed.len;
        size_t end = i + 1;
        Str ignored;
        while (end < count && lines[end].len - fmt_trim_start_set(lines[end], " ").len == indent &&
               fmt_prose_comment(lines[end], &ignored)) {
            end++;
        }
        bool wide = false;
        for (size_t k = i; k < end; k++) {
            wide = wide || fmt_chars(lines[k]) > FMT_WIDTH;
        }
        if (!wide) {
            for (size_t k = i; k < end; k++) {
                strs_push(out, lines[k]);
            }
            i = end;
            continue;
        }
        MsBuf prefix_buf = {0};
        fmt_spaces(&prefix_buf, indent);
        ms_buf_puts(&prefix_buf, "// ");
        const Str prefix = fmt_take(f, &prefix_buf);
        const size_t prefix_chars = fmt_chars(prefix);
        const size_t room = FMT_WIDTH > prefix_chars ? FMT_WIDTH - prefix_chars : 0;
        StrList words = {0};
        fmt_comment_words(f, first, &words);
        for (size_t k = i + 1; k < end; k++) {
            Str text;
            if (fmt_prose_comment(lines[k], &text)) {
                fmt_comment_words(f, text, &words);
            }
        }
        MsBuf row = {0};
        const Str *list = strs_at(&words);
        for (size_t w = 0; w < strs_len(&words); w++) {
            const size_t width = fmt_chars(fmt_tail(&row, 0)) + (row.len != 0) + fmt_chars(list[w]);
            if (row.len != 0 && width > room) {
                MsBuf line = {0};
                fmt_put(&line, prefix);
                fmt_put(&line, fmt_tail(&row, 0));
                strs_push(out, fmt_take(f, &line));
                row.len = 0;
            }
            if (row.len != 0) {
                ms_buf_putc(&row, ' ');
            }
            fmt_put(&row, list[w]);
        }
        MsBuf line = {0};
        fmt_put(&line, prefix);
        fmt_put(&line, fmt_tail(&row, 0));
        strs_push(out, fmt_take(f, &line));
        ms_buf_free(&row);
        strs_free(&words);
        i = end;
    }
}

/* ---- spacing between tokens on a line ---- */

/* Whether the final `)` closes the parameter list of an `fn` declaration or function type, so a
 * `(` after it opens a parenthesized return type (`fn f() (fn() Int)?`) rather than calling a
 * result. Returns -1 when the matching `(` is not among `tokens` (a line that starts at the `)`). */
static int fmt_closes_parameter_list(const MsToken *tokens, size_t count) {
    int depth = 0;
    bool found = false;
    size_t at = 0;
    for (size_t index = count; index > 0; index--) {
        const MsTok kind = (MsTok)tokens[index - 1].kind;
        if (kind == MS_T_RParen) {
            depth++;
        } else if (kind == MS_T_LParen) {
            depth--;
            if (depth == 0) {
                at = index - 1;
                found = true;
                break;
            }
        }
    }
    if (!found) {
        return -1;
    }
    if (at > 0 && tokens[at - 1].kind == MS_T_RBracket) {
        depth = 0;
        while (at > 0) {
            at--;
            if (tokens[at].kind == MS_T_RBracket) {
                depth++;
            } else if (tokens[at].kind == MS_T_LBracket) {
                depth--;
                if (depth == 0) {
                    break;
                }
            }
        }
    }
    const bool one_fn = at >= 1 && tokens[at - 1].kind == MS_T_Fn;
    const bool named_fn = at >= 2 && tokens[at - 1].kind == MS_T_Name && tokens[at - 2].kind == MS_T_Fn;
    return one_fn || named_fn;
}

static bool fmt_after_operand(MsTok previous) {
    return previous == MS_T_Plus || previous == MS_T_Minus || previous == MS_T_Star || previous == MS_T_Slash ||
           previous == MS_T_Percent;
}

bool fmt_token_space(const MsToken *tokens, size_t at) {
    const MsTok current = (MsTok)tokens[at].kind;
    const MsTok previous = (MsTok)tokens[at - 1].kind;
    if (current == MS_T_Dot && (previous == MS_T_Pipe || previous == MS_T_Try)) {
        return true;
    }
    if (previous == MS_T_Bang && current == MS_T_Name && tokens[at].lo == tokens[at - 1].hi) {
        return false;
    }
    if (current == MS_T_DotDot || previous == MS_T_DotDot) {
        return false;
    }
    switch (current) {
    case MS_T_RParen:
    case MS_T_RBracket:
    case MS_T_RBrace:
    case MS_T_Comma:
    case MS_T_Dot:
    case MS_T_Colon:
    case MS_T_Question:
    case MS_T_Bang: return false;
    default: break;
    }
    if (previous == MS_T_LParen || previous == MS_T_LBracket || previous == MS_T_LBrace || previous == MS_T_Dot) {
        return false;
    }
    if (current == MS_T_Assign && fmt_after_operand(previous) && tokens[at - 1].end.offset == tokens[at].pos.offset) {
        return false; // the two tokens of a compound assignment such as +=
    }
    if (current == MS_T_LParen &&
        (previous == MS_T_Name || previous == MS_T_RParen || previous == MS_T_RBracket || previous == MS_T_Fn)) {
        if (previous != MS_T_RParen) {
            return false;
        }
        // Per-line spacing cannot see a `(` on an earlier line; keep the authored gap.
        const int closes = fmt_closes_parameter_list(tokens, at);
        return closes < 0 ? tokens[at].lo != tokens[at - 1].hi : closes == 1;
    }
    if (current == MS_T_LBracket &&
        (previous == MS_T_Name || previous == MS_T_SelfKw || previous == MS_T_RBracket || previous == MS_T_RParen)) {
        return false;
    }
    if (previous == MS_T_Minus) {
        if (at == 1) {
            return false;
        }
        switch ((MsTok)tokens[at - 2].kind) {
        case MS_T_Assign:
        case MS_T_ColonAssign:
        case MS_T_LParen:
        case MS_T_LBracket:
        case MS_T_Comma:
        case MS_T_Colon:
        case MS_T_Return:
        case MS_T_Plus:
        case MS_T_Minus:
        case MS_T_Star:
        case MS_T_Slash:
        case MS_T_Percent:
        case MS_T_Lt:
        case MS_T_Gt:
        case MS_T_EqEq:
        case MS_T_NotEq:
        case MS_T_Le:
        case MS_T_Ge: return false;
        default: break;
        }
    }
    return true;
}

/* ---- suite headers ---- */

/* Re-indents a suite whose header spans several lines and ends on a line indented differently from
 * the statement's first line. Fills `out` with the new lines; false when nothing moves. */
static bool fmt_align_suite_headers(Fmt *f, const Str *lines, size_t nlines, const MsToken *tokens, size_t ntokens,
                                    StrList *out) {
    int64_t *shift = MS_NEW_N(f->arena, int64_t, nlines + 2);
    memset(shift, 0, (nlines + 2) * sizeof *shift);
    bool changed = false;
    int64_t depth = 0;
    for (size_t i = 0; i < ntokens; i++) {
        const MsTok kind = (MsTok)tokens[i].kind;
        if (fmt_is_open(kind)) {
            depth++;
        } else if (kind == MS_T_RParen || kind == MS_T_RBracket || kind == MS_T_RBrace) {
            depth--;
        }
        if (kind != MS_T_Indent || depth != 0 || i < 3 || i + 1 >= ntokens || tokens[i + 1].kind == MS_T_Dedent ||
            tokens[i - 1].kind != MS_T_Newline || tokens[i - 2].kind != MS_T_Colon) {
            continue;
        }
        size_t start = i - 2;
        // A parameter default can contain its own suite. Its layout tokens belong to the enclosing
        // group, not the start of this header.
        int groups = 0;
        while (start > 0) {
            const MsTok before = (MsTok)tokens[start - 1].kind;
            if (before == MS_T_RParen || before == MS_T_RBracket || before == MS_T_RBrace) {
                groups++;
            } else if (fmt_is_open(before)) {
                groups--;
            } else if ((before == MS_T_Newline || before == MS_T_Indent || before == MS_T_Dedent) && groups == 0) {
                break;
            }
            start--;
        }
        const uint32_t header = tokens[i - 2].pos.line;
        const uint32_t first = tokens[start].pos.line;
        if (header == first || header > nlines || fmt_indent_of(lines[header - 1]) == fmt_indent_of(lines[first - 1])) {
            continue;
        }
        size_t end = nlines;
        int nesting = 0;
        for (size_t later = i; later < ntokens; later++) {
            if (tokens[later].kind == MS_T_Indent) {
                nesting++;
            } else if (tokens[later].kind == MS_T_Dedent) {
                nesting--;
                if (nesting == 0) {
                    const size_t line = tokens[later].pos.line - 1;
                    end = end < line ? end : line;
                    break;
                }
            }
        }
        const int64_t delta = (int64_t)fmt_indent_of(lines[first - 1]) - (int64_t)fmt_indent_of(lines[header - 1]);
        for (size_t slot = header; slot <= end && slot < nlines + 2; slot++) {
            shift[slot] += delta;
        }
        changed = true;
    }
    if (!changed) {
        return false;
    }
    for (size_t index = 0; index < nlines; index++) {
        const int64_t delta = shift[index + 1];
        if (delta > 0 && !fmt_is_blank(lines[index])) {
            MsBuf line = {0};
            fmt_spaces(&line, (size_t)delta);
            fmt_put(&line, lines[index]);
            strs_push(out, fmt_take(f, &line));
        } else if (delta < 0) {
            const size_t indent = fmt_indent_of(lines[index]);
            const size_t cut = (size_t)-delta < indent ? (size_t)-delta : indent;
            strs_push(out, fmt_slice(lines[index], cut, lines[index].len));
        } else {
            strs_push(out, lines[index]);
        }
    }
    return true;
}

/* ---- blank lines between paragraphs ---- */

typedef struct Paragraphs {
    Fmt *fmt;
    const Str *lines;
    size_t nlines;
    bool *breaks; /* by line number */
} Paragraphs;

/* Keeps leading comments with the node they describe, ignoring authored blank lines. Stops at code
 * or a different indentation. */
static void para_before(Paragraphs *p, size_t line) {
    const size_t indent = fmt_indent_of(p->lines[line - 1]);
    while (line > 1) {
        const Str previous = p->lines[line - 2];
        if (fmt_is_blank(previous)) {
            line--;
            continue;
        }
        if (!fmt_starts(fmt_trim(previous), "//") || fmt_indent_of(previous) != indent) {
            break;
        }
        line--;
    }
    p->breaks[line] = true;
}

static bool para_leading_comment(const Paragraphs *p, size_t line) {
    const size_t indent = fmt_indent_of(p->lines[line - 1]);
    for (size_t i = line - 1; i > 0; i--) {
        const Str candidate = p->lines[i - 1];
        if (!fmt_is_blank(candidate)) {
            return fmt_starts(fmt_trim_start(candidate), "//") && fmt_indent_of(candidate) == indent;
        }
    }
    return false;
}

/* A binding that names something. `void value` is a binding of `_` and reads as a call. */
static bool para_is_binding(const Paragraphs *p, const MsStmt *s) {
    if (s->kind != MS_S_BIND) {
        return false;
    }
    const MsPattern *pattern = s->u.bind.pattern;
    return !(pattern->kind == MS_P_NAME && fmt_is(ms_name(p->fmt->names, pattern->u.name), "_"));
}

/* The line a binding starts on; a binding in a `var (...)` group starts on the group's keyword
 * line so the group moves as one unit. */
static size_t para_statement_line(const MsStmt *s) {
    return s->kind == MS_S_BIND && s->u.bind.has_group ? s->u.bind.group.line : s->pos.line;
}

static bool para_guard_statement(const MsStmt *s) {
    if (s->kind != MS_S_IF || s->u.branch.else_body.len != 0 || s->u.branch.body.len != 1) {
        return false;
    }
    const uint8_t kind = s->u.branch.body.ptr[0]->kind;
    return kind == MS_S_RETURN || kind == MS_S_BREAK || kind == MS_S_CONTINUE;
}

static bool para_block(const MsStmt *s) {
    // Single-step blocks belong to the surrounding cluster. Count syntax, rather than source
    // lines, so wrapping a header cannot add paragraphs on the next formatting pass.
    const MsExpr *value = fmt_statement_value(s);
    if (value != NULL) {
        while (value->kind == MS_E_UNARY) {
            value = value->u.bin.left;
        }
        if (fmt_is_written_match(value) || fmt_block_lambda(value)) {
            return true;
        }
        if (value->kind == MS_E_CALL) {
            for (uint32_t i = 0; i < value->u.call.args.len; i++) {
                if (fmt_block_lambda(value->u.call.args.ptr[i].value)) {
                    return true;
                }
            }
        }
    }
    switch ((MsStmtKind)s->kind) {
    case MS_S_IF:
        return !para_guard_statement(s) &&
               (s->u.branch.body.len > 1 || s->u.branch.else_body.len != 0 ||
                (s->u.branch.body.len == 1 && para_block(s->u.branch.body.ptr[0])));
    case MS_S_WHILE:
        return s->u.loop.body.len > 1 || (s->u.loop.body.len == 1 && para_block(s->u.loop.body.ptr[0]));
    case MS_S_FOR:
        return s->u.each.body.len > 1 || (s->u.each.body.len == 1 && para_block(s->u.each.body.ptr[0]));
    default: return false;
    }
}

static void para_visit_block(void *ctx, MsStmts body) {
    Paragraphs *p = ctx;
    for (uint32_t i = 1; i < body.len; i++) {
        const MsStmt *previous = body.ptr[i - 1];
        const MsStmt *current = body.ptr[i];
        const size_t line = para_statement_line(current);
        if (para_statement_line(previous) == line) {
            continue;
        }
        const bool lone_return = body.len == 2 && current->kind == MS_S_RETURN;
        if (para_block(previous) || para_block(current) ||
            (para_guard_statement(previous) && !para_guard_statement(current) && !lone_return) ||
            (!para_is_binding(p, previous) && para_is_binding(p, current)) || para_leading_comment(p, line)) {
            para_before(p, line);
        }
    }
}

enum { GROUP_NONE, GROUP_CONSTANT, GROUP_ALIAS, GROUP_IMPORT };

static void fmt_paragraph_breaks(Fmt *f, const MsModule *module, const Str *lines, size_t nlines, bool *breaks) {
    Paragraphs p = {.fmt = f, .lines = lines, .nlines = nlines, .breaks = breaks};
    // Imports may be interleaved with declarations. Separate each import section while keeping
    // consecutive imports, constants and aliases together.
    uint8_t *group_of = MS_NEW_N(f->arena, uint8_t, nlines + 2);
    memset(group_of, GROUP_NONE, nlines + 2);
    MsBuf top_level = {0};
    for (uint32_t i = 0; i < module->ndecls; i++) {
        const MsDecl *d = module->decls[i];
        MS_VEC_PUSH(top_level, uint32_t, d->pos.line);
        if (d->kind == MS_D_CONST) {
            group_of[d->pos.line] = GROUP_CONSTANT;
        } else if (d->kind == MS_D_ALIAS) {
            group_of[d->pos.line] = GROUP_ALIAS;
        }
    }
    for (uint32_t i = 0; i < module->nimports; i++) {
        const uint32_t line = module->imports[i].pos.line;
        if (group_of[line] == GROUP_NONE) {
            MS_VEC_PUSH(top_level, uint32_t, line);
        }
        group_of[line] = GROUP_IMPORT;
    }
    uint32_t *lines_sorted = ms_buf_items(&top_level);
    const size_t ntop = MS_VEC_LEN(top_level, uint32_t);
    // Insertion into a sorted order by line number.
    for (size_t i = 1; i < ntop; i++) {
        const uint32_t key = lines_sorted[i];
        size_t j = i;
        while (j > 0 && lines_sorted[j - 1] > key) {
            lines_sorted[j] = lines_sorted[j - 1];
            j--;
        }
        lines_sorted[j] = key;
    }
    for (size_t i = 1; i < ntop; i++) {
        const uint8_t a = group_of[lines_sorted[i - 1]];
        const uint8_t b = group_of[lines_sorted[i]];
        if (a == GROUP_NONE || a != b) {
            para_before(&p, lines_sorted[i]);
        }
    }
    ms_buf_free(&top_level);
    // Clauses of a grouped import are separated by section.
    for (uint32_t i = 1; i < module->nimports; i++) {
        const MsImport *a = &module->imports[i - 1];
        const MsImport *b = &module->imports[i];
        if (a->pos.offset == b->pos.offset && a->pos.line == b->pos.line && a->pos.column == b->pos.column &&
            (a->clause.offset != b->clause.offset || a->clause.line != b->clause.line ||
             a->clause.column != b->clause.column)) {
            const Str qa = ms_arena_fmt(f->arena, "\"%.*s", (int)a->path.len, a->path.ptr);
            const Str qb = ms_arena_fmt(f->arena, "\"%.*s", (int)b->path.len, b->path.ptr);
            if (fmt_import_section(qa) != fmt_import_section(qb)) {
                para_before(&p, b->clause.line);
            }
        }
    }
    const MsVisitor visitor = {.ctx = &p, .block = para_visit_block};
    for (uint32_t i = 0; i < module->ndecls; i++) {
        const MsDecl *d = module->decls[i];
        // Implementation bodies are separate reading units. Interface signatures remain a compact
        // list of the contract's operations.
        if (d->kind == MS_D_IMPL) {
            for (uint32_t m = 1; m < d->u.impl.methods.len; m++) {
                para_before(&p, d->u.impl.methods.ptr[m]->pos.line);
            }
        }
        ms_walk_decl(&visitor, d);
    }
}

/* ---- the line pass ---- */

typedef enum LineStep { LINE_FAILED, LINE_DONE, LINE_AGAIN } LineStep;

/* The code tokens of a source (layout tokens left out), grouped by line: line `n` holds the run
 * of `count[n]` tokens starting at `code[first[n]]`. */
typedef struct LineTokens {
    MsToken *code;
    uint32_t *first, *count;
} LineTokens;

static LineTokens fmt_line_tokens(Fmt *f, const MsLexed *lexed, size_t nlines) {
    LineTokens index = {.code = MS_NEW_N(f->arena, MsToken, lexed->ntokens + 1),
                        .first = MS_NEW_N(f->arena, uint32_t, nlines + 3),
                        .count = MS_NEW_N(f->arena, uint32_t, nlines + 3)};
    memset(index.count, 0, (nlines + 3) * sizeof *index.count);
    size_t ncode = 0;
    for (size_t i = 0; i < lexed->ntokens; i++) {
        const MsToken *t = &lexed->tokens[i];
        if (fmt_layout_token((MsTok)t->kind)) {
            continue;
        }
        if (index.count[t->pos.line] == 0) {
            index.first[t->pos.line] = (uint32_t)ncode;
        }
        index.count[t->pos.line]++;
        index.code[ncode++] = *t;
    }
    return index;
}

/* One line of code: token spacing, a wrapped import, and the trailing comment kept. */
static Str fmt_code_line(Fmt *f, Str source, Str line, const MsToken *parts, size_t nparts) {
    MsBuf formatted = {0};
    fmt_spaces(&formatted, parts[0].pos.column - 1);
    for (size_t i = 0; i < nparts; i++) {
        if (i > 0 && fmt_token_space(parts, i)) {
            ms_buf_putc(&formatted, ' ');
        }
        fmt_put(&formatted, fmt_token_text(source, &parts[i]));
    }
    const MsToken *last = &parts[nparts - 1];
    const size_t tail = last->pos.column - 1 + (last->hi - last->lo);
    Str rows;
    if (fmt_wrap_import(f, parts, nparts, fmt_str(formatted.data, formatted.len), source, &rows)) {
        formatted.len = 0;
        fmt_put(&formatted, rows);
    }
    if (tail < line.len) {
        const size_t comment = fmt_find(fmt_slice(line, tail, line.len), fmt_lit("//"));
        if (comment != FMT_NONE) {
            ms_buf_puts(&formatted, "  ");
            fmt_put(&formatted, fmt_trim_end_set(fmt_slice(line, tail + comment, line.len), " \t"));
        }
    }
    return fmt_take(f, &formatted);
}

/* A comment-only line: indentation snapped down to a multiple of four. */
static Str fmt_comment_line(Fmt *f, Str line) {
    const Str stripped = fmt_trim_start_set(line, " ");
    MsBuf text = {0};
    fmt_spaces(&text, (size_t)((line.len - stripped.len) / 4) * 4);
    fmt_put(&text, fmt_trim_end_set(stripped, " \t"));
    return fmt_take(f, &text);
}

/* The formatted lines of `lines`, with paragraph breaks. `*realigned` is set when a comment-only
 * line changed indentation: it can need the blank lines a dedent gets, which only the next pass
 * sees. */
static void fmt_format_lines(Fmt *f, Str source, const Str *lines, size_t nlines, const bool *breaks,
                             const LineTokens *index, StrList *output, bool *realigned) {
    bool blank = true;
    for (size_t at = 0; at < nlines; at++) {
        const Str line = lines[at];
        if (breaks[at + 1] && !blank) {
            strs_push(output, fmt_lit(""));
            blank = true;
        }
        const size_t nparts = index->count[at + 1];
        if (nparts != 0) {
            strs_push(output, fmt_code_line(f, source, line, &index->code[index->first[at + 1]], nparts));
            blank = false;
        } else if (!fmt_is_blank(line)) {
            *realigned = *realigned || fmt_indent_of(line) % 4 != 0;
            strs_push(output, fmt_comment_line(f, line));
            blank = false;
        } else if (!blank && at > 0 && fmt_starts(fmt_trim(lines[at - 1]), "//")) {
            // A blank line after a comment-only line separates the comment block from what follows
            // (a module header from the first declaration's doc).
            strs_push(output, fmt_lit(""));
            blank = true;
        }
    }
}

/* Reflows comments and lays out expressions in the formatted lines; false when the text stops
 * parsing. */
static bool fmt_finish_lines(Fmt *f, const StrList *output, Str *result) {
    size_t nout = strs_len(output);
    while (nout > 0 && strs_at(output)[nout - 1].len == 0) {
        nout--;
    }
    if (nout == 0) {
        *result = fmt_lit("");
        return true;
    }
    StrList wrapped = {0};
    fmt_wrap_comments(f, strs_at(output), nout, &wrapped);
    MsBuf joined = {0};
    for (size_t i = 0; i < strs_len(&wrapped); i++) {
        fmt_put(&joined, strs_at(&wrapped)[i]);
        ms_buf_putc(&joined, '\n');
    }
    strs_free(&wrapped);
    const Str joined_text = fmt_take(f, &joined);
    MsModule module;
    MsArena check = {0};
    const bool valid = fmt_expression_layout(f, joined_text, result) && fmt_parse(f, &check, *result, &module);
    ms_arena_free(&check);
    return valid;
}

/* The suite headers re-laid out by expression layout move their suites with them: the lines and
 * the lexed tokens are replaced. */
static bool fmt_realign_headers(Fmt *f, MsArena *scratch, StrList *aligned, Str *normalized, MsLexed *lexed) {
    *normalized = fmt_join_lines(f, strs_at(aligned), strs_len(aligned));
    MsArena relex = {0};
    if (!fmt_lex(f, &relex, *normalized, lexed)) {
        ms_arena_free(&relex);
        return false;
    }
    // The new tokens live in `relex`, which replaces the first arena for the rest of the pass.
    ms_arena_free(scratch);
    *scratch = relex;
    return true;
}

/* One run of the line passes. LINE_AGAIN means `*out` is a rewritten source to run them on again. */
static LineStep format_lines_step(Fmt *f, Str source, Str *out) {
    Str normalized = fmt_normalize(f, source);
    StrList line_list = {0};
    size_t nlines = fmt_split_lines(normalized, &line_list);
    const Str *lines = strs_at(&line_list);
    MsArena scratch = {0};
    LineStep step = LINE_FAILED;
    StrList aligned = {0};
    StrList output = {0};
    MsModule module;
    MsLexed lexed;
    Str changed;
    if (!fmt_parse(f, &scratch, normalized, &module)) {
        goto done;
    }
    if (fmt_compact(f, &module, normalized, &changed)) {
        MsArena probe = {0};
        MsModule compacted_module;
        const bool parses = fmt_parse(f, &probe, changed, &compacted_module);
        ms_arena_free(&probe);
        if (parses) {
            *out = changed;
            step = LINE_AGAIN;
            goto done;
        }
    }
    bool *breaks = MS_NEW_N(f->arena, bool, nlines + 2);
    memset(breaks, 0, (nlines + 2) * sizeof *breaks);
    fmt_paragraph_breaks(f, &module, lines, nlines, breaks);
    if (!fmt_lex(f, &scratch, normalized, &lexed)) {
        goto done;
    }
    if (fmt_group_imports(f, normalized, lexed.tokens, lexed.ntokens, &changed)) {
        *out = changed;
        step = LINE_AGAIN;
        goto done;
    }
    if (fmt_align_suite_headers(f, lines, nlines, lexed.tokens, lexed.ntokens, &aligned)) {
        nlines = strs_len(&aligned);
        lines = strs_at(&aligned);
        if (!fmt_realign_headers(f, &scratch, &aligned, &normalized, &lexed)) {
            goto done;
        }
    }
    const LineTokens index = fmt_line_tokens(f, &lexed, nlines);
    bool realigned = false;
    fmt_format_lines(f, normalized, lines, nlines, breaks, &index, &output, &realigned);
    Str result;
    if (!fmt_finish_lines(f, &output, &result)) {
        goto done;
    }
    *out = result;
    step = realigned && !fmt_eq(result, source) ? LINE_AGAIN : LINE_DONE;
done:
    ms_arena_free(&scratch);
    strs_free(&aligned);
    strs_free(&output);
    strs_free(&line_list);
    return step;
}

static bool format_lines(Fmt *f, Str source, Str *out) {
    for (;;) {
        const LineStep step = format_lines_step(f, source, out);
        if (step != LINE_AGAIN) {
            return step == LINE_DONE;
        }
        source = *out;
    }
}

/* ---- the entry point ---- */

bool ms_format(MsArena *result_arena, const char *src, size_t len, MsBuf *out, MsDiag *diag) {
    MsArena arena = {0};
    MsNames names;
    ms_names_init(&names);
    Fmt f = {.arena = &arena, .names = &names};
    Str text = fmt_str(src, len);
    bool ok = format_once(&f, text, &text);
    // Joining a multi-line header can make an `if` body eligible for the one-line form, which the
    // compact pass judged on the unjoined text, so the output is formatted again until the pass
    // has nothing left to do; a second run of `ms fmt` then changes nothing.
    for (int round = 0; ok && round < 4; round++) {
        MsArena scratch = {0};
        MsModule module;
        Str compacted;
        const bool parsed = fmt_parse(&f, &scratch, text, &module);
        const bool again = parsed && fmt_compact(&f, &module, text, &compacted);
        ms_arena_free(&scratch);
        ok = parsed;
        if (!again) {
            break;
        }
        ok = format_once(&f, text, &text);
    }
    if (ok) {
        ms_buf_put(out, text.ptr, text.len);
    } else {
        *diag = f.diag;
        diag->message = ms_arena_fmt(result_arena, "%.*s", (int)f.diag.message.len, f.diag.message.ptr);
        diag->replacement = ms_arena_fmt(result_arena, "%.*s", (int)f.diag.replacement.len, f.diag.replacement.ptr);
    }
    ms_names_free(&names);
    ms_arena_free(&arena);
    return ok;
}
