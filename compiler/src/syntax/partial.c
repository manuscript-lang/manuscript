/* Editor recovery: keeps the declarations of a file that parse independently. A port of
 * crates/ms-syntax/src/partial.rs; see there for the reasoning behind each heuristic. */
#include <stdlib.h>
#include <string.h>
#include "ms_rt/chars.h"

#include "ms/text.h"
#include "ms/lex.h"
#include "ms/parse.h"

typedef struct Part {
    MsArena *arena;
    MsNames *names;
    const char *src; /* borrowed from the caller */
    size_t len;
} Part;

typedef struct Line {
    size_t start, len;
} Line;

/* ---- text helpers (Rust's str::trim is Unicode White_Space) ---- */

static size_t pt_trim_start(const char *s, size_t n) {
    size_t i = 0;
    while (i < n) {
        uint32_t c;
        int k = ms_utf8_decode(s + i, n - i, &c);
        if (!ms_text_is_unicode_space(c)) {
            break;
        }
        i += (size_t)k;
    }
    return i;
}

static size_t pt_trim_end(const char *s, size_t n) {
    while (n > 0) {
        size_t i = n - 1;
        while (i > 0 && ms_utf8_is_continuation((uint8_t)s[i])) {
            i--;
        }
        uint32_t c;
        ms_utf8_decode(s + i, n - i, &c);
        if (!ms_text_is_unicode_space(c)) {
            break;
        }
        n = i;
    }
    return n;
}

/* The trimmed range of s[0..n) as an offset and a length. */
static MsStr pt_trim(const char *s, size_t n) {
    size_t lo = pt_trim_start(s, n);
    size_t hi = pt_trim_end(s + lo, n - lo);
    return (MsStr){s + lo, (uint32_t)hi};
}

static bool pt_starts(const char *s, size_t n, const char *pre) {
    size_t k = strlen(pre);
    return n >= k && memcmp(s, pre, k) == 0;
}

static bool pt_ends(const char *s, size_t n, const char *suf) {
    size_t k = strlen(suf);
    return n >= k && memcmp(s + n - k, suf, k) == 0;
}

/* The rest after `keyword`, as an offset, or -1 when the source does not start with that word. */
static long pt_after_keyword(const char *s, size_t n, const char *keyword) {
    size_t k = strlen(keyword);
    if (!pt_starts(s, n, keyword)) {
        return -1;
    }
    if (n > k && ms_ascii_is_ident((uint8_t)s[k])) {
        return -1;
    }
    return (long)k;
}

static bool pt_constant_start(const char *s, size_t n) {
    size_t name = 0;
    while (name < n && ms_ascii_is_ident((uint8_t)s[name])) {
        name++;
    }
    if (name == 0 || (s[0] >= '0' && s[0] <= '9')) {
        return false;
    }
    size_t lo = name + pt_trim_start(s + name, n - name);
    return pt_starts(s + lo, n - lo, ":=");
}

/* Recognizes declaration starts by token boundary, including contextual words only when their
 * following token selects a declaration. */
static bool pt_root_start(const char *s, size_t n) {
    static const char *const declaration_words[] = {"import", "export", "extern", "type",
                                                    "enum",   "interface", "impl", "test"};
    for (size_t i = 0; i < sizeof declaration_words / sizeof declaration_words[0]; i++) {
        if (pt_after_keyword(s, n, declaration_words[i]) >= 0) {
            return true;
        }
    }
    if (pt_constant_start(s, n)) {
        return true;
    }
    long r = pt_after_keyword(s, n, "fn");
    if (r >= 0) {
        const char *rest = s + r;
        size_t rn = n - (size_t)r;
        size_t lo = pt_trim_start(rest, rn);
        rest += lo;
        rn -= lo;
        bool name_start = rn > 0 && (ms_ascii_is_alpha((uint8_t)rest[0]) || rest[0] == '_');
        size_t name_end = 0;
        while (name_end < rn && ms_ascii_is_ident((uint8_t)rest[name_end])) {
            name_end++;
        }
        /* A named function needs a parameter or type-parameter list after its name. Inferred
         * callbacks can continue their header on later lines. */
        size_t after = name_end + pt_trim_start(rest + name_end, rn - name_end);
        if (name_start && after < rn && (rest[after] == '(' || rest[after] == '[')) {
            return true;
        }
    }
    r = pt_after_keyword(s, n, "bench");
    if (r >= 0) {
        size_t lo = (size_t)r + pt_trim_start(s + r, n - (size_t)r);
        if (lo < n && s[lo] == '"') {
            return true;
        }
    }
    r = pt_after_keyword(s, n, "opaque");
    if (r >= 0) {
        size_t lo = (size_t)r + pt_trim_start(s + r, n - (size_t)r);
        return pt_after_keyword(s + lo, n - lo, "type") >= 0 || pt_after_keyword(s + lo, n - lo, "enum") >= 0;
    }
    return false;
}

static bool pt_candidate(const char *line, size_t n) {
    if (n == 0 || line[0] == ' ' || line[0] == '\t') {
        return false;
    }
    MsStr t = pt_trim(line, n);
    return t.len != 0 && !pt_starts(t.ptr, t.len, "//");
}

static bool pt_declaration(const char *line, size_t n) {
    if (!pt_candidate(line, n)) {
        return false;
    }
    MsStr t = pt_trim(line, n);
    return pt_root_start(t.ptr, t.len);
}

static size_t pt_leading_space(const char *s, size_t n) {
    size_t i = 0;
    while (i < n && (s[i] == ' ' || s[i] == '\t')) {
        i++;
    }
    return i;
}

/* ---- parsing a chunk ---- */

static bool pt_chunk(Part *pt, const char *src, size_t len, uint32_t base_offset, uint32_t base_line,
                     uint32_t first_id, MsModule *m, MsDiag *d) {
    return ms_parse_chunk(pt->arena, pt->names, src, len, base_offset, base_line, first_id, m, d);
}

/* Grouped imports and constants produce several nodes for one written root. */
static bool pt_single_root(const MsModule *m) {
    bool have = false;
    uint32_t root = 0;
    for (uint32_t i = 0; i < m->nimports; i++) {
        if (have && root != m->imports[i].pos.offset) {
            return false;
        }
        root = m->imports[i].pos.offset;
        have = true;
    }
    for (uint32_t i = 0; i < m->ndecls; i++) {
        if (have && root != m->decls[i]->pos.offset) {
            return false;
        }
        root = m->decls[i]->pos.offset;
        have = true;
    }
    return have;
}

/* ---- lines ---- */

typedef struct Lines {
    Line *items;
    size_t count;
} Lines;

/* The lines of `text` as str::split_inclusive('\n') gives them: each keeps its line break. */
static Lines pt_split_lines(MsArena *arena, const char *text, size_t length) {
    size_t count = 0;
    for (size_t i = 0; i < length; i++) {
        count += text[i] == '\n';
    }
    if (length > 0 && text[length - 1] != '\n') {
        count++;
    }
    Line *items = MS_NEW_N(arena, Line, count + 1);
    size_t start = 0;
    size_t next = 0;
    for (size_t i = 0; i < length; i++) {
        if (text[i] == '\n' || i + 1 == length) {
            items[next++] = (Line){.start = start, .len = i + 1 - start};
            start = i + 1;
        }
    }
    return (Lines){.items = items, .count = count};
}

static bool *pt_new_flags(MsArena *arena, size_t count) {
    bool *flags = MS_NEW_N(arena, bool, count + 1);
    memset(flags, 0, count + 1);
    return flags;
}

/* ---- statement recovery ---- */

typedef struct Issues {
    MsDiag *items;
    uint32_t len;
    uint32_t cap;
} Issues;

static void pt_push_diag(MsArena *arena, Issues *issues, const MsDiag *diag) {
    if (issues->len == issues->cap) {
        uint32_t new_cap = issues->cap ? issues->cap * 2 : 4;
        MsDiag *items = MS_NEW_N(arena, MsDiag, new_cap);
        if (issues->len != 0) {
            memcpy(items, issues->items, issues->len * sizeof(MsDiag));
        }
        issues->items = items;
        issues->cap = new_cap;
    }
    issues->items[issues->len++] = *diag;
}

/* A text and its lines. The edits recovery makes keep every line's length, so `lines` stays valid. */
typedef struct Recovery {
    Part *part;
    char *text;
    size_t length;
    Lines lines;
    uint32_t base_offset;
    uint32_t base_line;
} Recovery;

static const char *pt_line_text(const Recovery *r, size_t index) {
    return r->text + r->lines.items[index].start;
}

static size_t pt_line_length(const Recovery *r, size_t index) {
    return r->lines.items[index].len;
}

static bool pt_line_blank(const Recovery *r, size_t index) {
    return pt_trim(pt_line_text(r, index), pt_line_length(r, index)).len == 0;
}

static size_t pt_line_indent(const Recovery *r, size_t index) {
    return pt_leading_space(pt_line_text(r, index), pt_line_length(r, index));
}

static bool pt_has_comment_or_quote(const char *line, size_t length) {
    for (size_t i = 0; i < length; i++) {
        bool slashes = line[i] == '/' && i + 1 < length && line[i + 1] == '/';
        if (line[i] == '"' || slashes) {
            return true;
        }
    }
    return false;
}

/* Trims trailing operator characters; returns the kept length. */
static size_t pt_strip_operators(const char *code, size_t length) {
    size_t kept = length;
    while (kept > 0 && (strchr(".?+-*/%<>=!,|", code[kept - 1]) != NULL || code[kept - 1] == ' ')) {
        kept--;
    }
    static const char *const words[] = {"and", "or", "not"};
    for (size_t w = 0; w < (sizeof(words) / sizeof((words)[0])); w++) {
        size_t word_length = strlen(words[w]);
        bool ends_with_word = kept > word_length && memcmp(code + kept - word_length, words[w], word_length) == 0;
        if (ends_with_word && code[kept - word_length - 1] == ' ') {
            return kept - word_length;
        }
    }
    return kept;
}

/* Removes the dangling tail of line `at` (a trailing `.`, `?.`, operator or separator) until the
 * declaration parses, keeping the line's columns by padding with spaces. Returns the new text, or
 * NULL when trimming does not make it parse. */
static char *pt_trim_dangling(const Recovery *r, size_t at) {
    const char *line = pt_line_text(r, at);
    size_t body = pt_line_length(r, at);
    while (body > 0 && (line[body - 1] == '\n' || line[body - 1] == '\r')) {
        body--;
    }
    size_t code_length = pt_trim_end(line, body);
    if (pt_has_comment_or_quote(line, code_length)) {
        return NULL;
    }
    for (int round = 0; round < 3; round++) {
        size_t kept = pt_strip_operators(line, code_length);
        if (kept == code_length || pt_trim_start(line, kept) == kept) {
            return NULL;
        }
        code_length = pt_trim_end(line, kept);
        char *attempt = ms_alloc(r->part->arena, r->length + 1, 1);
        memcpy(attempt, r->text, r->length);
        attempt[r->length] = 0;
        char *edited = attempt + r->lines.items[at].start;
        memset(edited, ' ', body);
        memcpy(edited, line, code_length);
        MsModule module;
        MsDiag diag;
        if (ms_parse(r->part->arena, r->part->names, attempt, r->length, &module, &diag)) {
            return attempt;
        }
    }
    return NULL;
}

/* A misindented line of multi-line text drops the whole statement: walk up to its opening line. */
static size_t pt_text_statement_start(const Recovery *r, size_t line) {
    while (line > 1 && line <= r->lines.count) {
        const char *text = pt_line_text(r, line - 1);
        size_t length = pt_trim_end(text, pt_line_length(r, line - 1));
        if (pt_ends(text, length, "\"\"\"")) {
            break;
        }
        line--;
    }
    return line;
}

/* The 1-based line to drop for `issue`. An unterminated delimiter is reported at the end of the
 * chunk; the statement to drop is the one that opened it. Only the first failure is redirected. */
static size_t pt_failing_line(const Recovery *r, const MsDiag *issue, int attempt) {
    size_t line = issue->pos.line - r->base_line;
    if (attempt != 0) {
        return line;
    }
    if (issue->opener_line > r->base_line) {
        line = issue->opener_line - r->base_line;
    }
    if (pt_starts(issue->message.ptr, issue->message.len, "text line is indented less")) {
        line = pt_text_statement_start(r, line);
    }
    return line;
}

/* Whether the statement at `at` ends the block: nothing after it is indented deeper. */
static bool pt_statement_is_last(const Recovery *r, size_t at, size_t indent) {
    for (size_t next = at + 1; next < r->lines.count; next++) {
        if (!pt_line_blank(r, next)) {
            return pt_line_indent(r, next) <= indent;
        }
    }
    return true;
}

/* Blanks the statement at `at` and the block it opens, keeping line breaks. */
static void pt_blank_block(Recovery *r, size_t at, size_t indent) {
    for (size_t index = at; index < r->lines.count; index++) {
        bool ends_block = index > at && !pt_line_blank(r, index) && pt_line_indent(r, index) <= indent;
        if (ends_block) {
            return;
        }
        char *line = r->text + r->lines.items[index].start;
        for (size_t b = 0; b < pt_line_length(r, index); b++) {
            if (line[b] != '\r' && line[b] != '\n') {
                line[b] = ' ';
            }
        }
    }
}

static Recovery pt_recovery_new(Part *part, const char *chunk, size_t length, uint32_t base_offset,
                                uint32_t base_line) {
    char *text = ms_alloc(part->arena, length + 1, 1);
    memcpy(text, chunk, length);
    text[length] = 0;
    return (Recovery){.part = part,
                      .text = text,
                      .length = length,
                      .lines = pt_split_lines(part->arena, text, length),
                      .base_offset = base_offset,
                      .base_line = base_line};
}

/* Retries a failed declaration chunk with each offending statement (and the block it opens)
 * blanked to spaces, so every remaining statement keeps its original position. Returns the new
 * text, or NULL when no bounded number of blankings parses; the issues found go to `issues`. */
static char *pt_recover(Part *part, const char *chunk, size_t length, uint32_t base_offset,
                        uint32_t base_line, const MsDiag *first, Issues *issues) {
    Recovery r = pt_recovery_new(part, chunk, length, base_offset, base_line);
    MsDiag issue = *first;
    for (int attempt = 0; attempt < 8; attempt++) {
        size_t line = pt_failing_line(&r, &issue, attempt);
        /* The header line (line 1) failing means the signature is unusable. */
        if (line < 2 || line > r.lines.count) {
            return NULL;
        }
        pt_push_diag(part->arena, issues, &issue);
        size_t at = line - 1;
        size_t indent = pt_line_indent(&r, at);
        if (pt_line_blank(&r, at) || indent == 0) {
            return NULL;
        }
        /* A one-line statement cut off mid-expression keeps its operands for navigation once the
         * dangling tail is trimmed. */
        char *trimmed = pt_statement_is_last(&r, at, indent) ? pt_trim_dangling(&r, at) : NULL;
        if (trimmed != NULL) {
            return trimmed;
        }
        pt_blank_block(&r, at, indent);
        MsModule module;
        if (pt_chunk(part, r.text, r.length, base_offset, base_line, 0, &module, &issue)) {
            return r.text;
        }
    }
    return NULL;
}

/* ---- declared names ---- */

/* The first two whitespace-separated fields of s; returns how many were found. */
static size_t pt_first_fields(const char *s, size_t length, MsStr fields[2]) {
    size_t found = 0;
    size_t at = 0;
    while (at < length && found < 2) {
        size_t lo = at;
        while (lo < length) {
            uint32_t c = 0;
            int width = ms_utf8_decode(s + lo, length - lo, &c);
            if (!ms_text_is_unicode_space(c)) {
                break;
            }
            lo += (size_t)width;
        }
        size_t hi = lo;
        while (hi < length) {
            uint32_t c = 0;
            int width = ms_utf8_decode(s + hi, length - hi, &c);
            if (ms_text_is_unicode_space(c)) {
                break;
            }
            hi += (size_t)width;
        }
        if (hi == lo) {
            break;
        }
        fields[found++] = (MsStr){.ptr = s + lo, .len = (uint32_t)(hi - lo)};
        at = hi;
    }
    return found;
}

/* The declared name of a first non-comment line `line`, or false when it declares none. */
static bool pt_name_of_line(Part *part, MsStr line, MsStr *out) {
    const char *rest = line.ptr;
    size_t length = line.len;
    static const char *const prefixes[] = {"export ", "opaque "};
    for (size_t i = 0; i < (sizeof(prefixes) / sizeof((prefixes)[0])); i++) {
        size_t k = strlen(prefixes[i]);
        if (pt_starts(rest, length, prefixes[i])) {
            rest += k;
            length -= k;
        }
    }
    MsStr fields[2];
    if (pt_first_fields(rest, length, fields) < 2) {
        return false;
    }
    bool declares = ms_text_is(fields[0], "fn") || ms_text_is(fields[0], "type") || ms_text_is(fields[0], "enum") ||
                    ms_text_is(fields[0], "interface");
    if (!declares) {
        return false;
    }
    /* The first non-empty piece of the second field, split on ( [ : */
    const char *field = fields[1].ptr;
    size_t field_length = fields[1].len;
    size_t lo = 0;
    while (lo < field_length && strchr("([:", field[lo]) != NULL) {
        lo++;
    }
    size_t hi = lo;
    while (hi < field_length && strchr("([:", field[hi]) == NULL) {
        hi++;
    }
    if (hi == lo) {
        return false;
    }
    char *copy = ms_alloc(part->arena, hi - lo + 1, 1);
    memcpy(copy, field + lo, hi - lo);
    copy[hi - lo] = 0;
    *out = (MsStr){.ptr = copy, .len = (uint32_t)(hi - lo)};
    return true;
}

/* The name a declaration chunk introduces, for chunks that failed to parse. */
static bool pt_declared_name(Part *part, const char *chunk, size_t length, MsStr *out) {
    size_t at = 0;
    while (at <= length) {
        size_t end = at;
        while (end < length && chunk[end] != '\n') {
            end++;
        }
        MsStr line = pt_trim(chunk + at, end - at);
        at = end + 1;
        if (line.len != 0 && !pt_starts(line.ptr, line.len, "//")) {
            return pt_name_of_line(part, line, out);
        }
        if (end >= length) {
            break;
        }
    }
    return false;
}

/* ---- the splitter ---- */

typedef struct Probe {
    size_t start;
    size_t end;
    bool has_error;
    bool used;
    MsDiag error;
} Probe;

/* A lexer pass over the current root: per line, whether a delimiter is open there. */
typedef struct PrefixCache {
    bool valid;
    size_t start;
    bool *flags;
    size_t count;
} PrefixCache;

typedef struct Splitter {
    Part *part;
    Lines lines;
    bool *continuations;
    size_t *starts;
    size_t start_count;
    Probe *probes;
    size_t probe_count;
    size_t attempted_start;
    size_t continuation_end;
    size_t last_start_index;
    size_t *line_offsets;
    size_t *next_declaration;
    PrefixCache prefixes;
} Splitter;

static const char *pt_text(const Splitter *sp, size_t index) {
    return sp->part->src + sp->lines.items[index].start;
}

static size_t pt_length(const Splitter *sp, size_t index) {
    return sp->lines.items[index].len;
}

static bool pt_has_closer(const char *s, size_t length) {
    for (size_t i = 0; i < length; i++) {
        if (s[i] == ')' || s[i] == ']' || s[i] == '}') {
            return true;
        }
    }
    return false;
}

/* Whether lexing source[last..offset] ends inside an open delimiter or text. */
static bool pt_is_unterminated(Splitter *sp, size_t index, size_t offset) {
    size_t last = sp->starts[sp->start_count - 1];
    if (sp->prefixes.valid && sp->prefixes.start == last) {
        size_t line = index - sp->last_start_index;
        return line < sp->prefixes.count && sp->prefixes.flags[line];
    }
    MsLexed lexed;
    MsDiag diag;
    if (ms_lex(sp->part->arena, sp->part->src + last, offset - last, &lexed, &diag)) {
        return false;
    }
    return pt_starts(diag.message.ptr, diag.message.len, "unterminated delimiter") ||
           pt_starts(diag.message.ptr, diag.message.len, "unterminated multi-line text");
}

/* A successful single-root parse proves the lines up to the next root are continuations; a failed
 * probe is remembered so the chunk is not parsed twice. */
static void pt_probe_root(Splitter *sp, size_t offset, size_t index) {
    const char *src = sp->part->src;
    size_t start = sp->starts[sp->start_count - 1];
    size_t end = offset;
    for (size_t next = index; next < sp->lines.count; next++) {
        if (!sp->continuations[next] && pt_root_start(pt_text(sp, next), pt_length(sp, next))) {
            break;
        }
        end += pt_length(sp, next);
    }
    size_t start_line = sp->last_start_index;
    if (sp->start_count == 1) {
        start = 0; /* The first chunk owns its leading trivia. */
        start_line = 0;
    }
    /* An open prefix cannot parse without a later closer. */
    if (!pt_has_closer(src + offset, end - offset)) {
        return;
    }
    MsModule module;
    MsDiag error;
    bool parsed = pt_chunk(sp->part, src + start, end - start, (uint32_t)start, (uint32_t)start_line, 0, &module, &error);
    bool single = parsed && pt_single_root(&module);
    if (!parsed || single) {
        sp->probes[sp->probe_count++] = (Probe){.start = start, .end = end, .has_error = !parsed, .error = error};
    }
    if (single) {
        sp->continuation_end = end;
    }
}

/* Line offsets and, per line, the next line that starts a declaration. Built on first use. */
static void pt_ensure_boundaries(Splitter *sp) {
    if (sp->line_offsets != NULL) {
        return;
    }
    size_t count = sp->lines.count;
    sp->line_offsets = MS_NEW_N(sp->part->arena, size_t, count + 2);
    sp->next_declaration = MS_NEW_N(sp->part->arena, size_t, count + 2);
    sp->line_offsets[0] = 0;
    for (size_t i = 0; i < count; i++) {
        sp->line_offsets[i + 1] = sp->line_offsets[i] + pt_length(sp, i);
    }
    sp->next_declaration[count] = count;
    sp->next_declaration[count + 1] = count;
    for (size_t i = count; i > 0; i--) {
        size_t line = i - 1;
        bool starts_here = !sp->continuations[line] && pt_declaration(pt_text(sp, line), pt_length(sp, line));
        sp->next_declaration[line] = starts_here ? line : sp->next_declaration[line + 1];
    }
}

/* Records, for the current root's later column-zero lines, whether a delimiter is still open. The
 * pass stops when the root would split, and the next declaration bounds it. */
static void pt_build_prefixes(Splitter *sp, size_t index) {
    size_t last = sp->starts[sp->start_count - 1];
    pt_ensure_boundaries(sp);
    size_t end_index = sp->next_declaration[index + 1];
    size_t stop_count = end_index - sp->last_start_index;
    bool *stop_at = pt_new_flags(sp->part->arena, stop_count);
    for (size_t i = 0; i < stop_count; i++) {
        size_t line = sp->last_start_index + i;
        stop_at[i] = i > 0 && !sp->continuations[line] && pt_candidate(pt_text(sp, line), pt_length(sp, line)) &&
                     !pt_declaration(pt_text(sp, line), pt_length(sp, line));
    }
    size_t count = 0;
    bool *flags = ms_unterminated_prefixes(sp->part->arena, sp->part->src + last,
                                           sp->line_offsets[end_index] - last, stop_at, stop_count, &count);
    sp->prefixes = (PrefixCache){.valid = true, .start = last, .flags = flags, .count = count};
}

/* Handles a column-zero line that is not a declaration, after an earlier root. Returns true when
 * the line continues that root. */
static bool pt_continues_root(Splitter *sp, size_t index, size_t offset) {
    if (!pt_is_unterminated(sp, index, offset)) {
        return false;
    }
    size_t last = sp->starts[sp->start_count - 1];
    if (sp->attempted_start != last) {
        sp->attempted_start = last;
        if (pt_root_start(sp->part->src + last, sp->part->len - last)) {
            pt_probe_root(sp, offset, index);
        }
    }
    bool cached = sp->prefixes.valid && sp->prefixes.start == last;
    if (sp->continuation_end <= offset && !cached) {
        pt_build_prefixes(sp, index);
    }
    return true;
}

/* Finds where each independently parsed declaration starts. */
static void pt_find_starts(Splitter *sp) {
    size_t offset = 0;
    for (size_t index = 0; index < sp->lines.count; index++) {
        const char *line = pt_text(sp, index);
        size_t length = pt_length(sp, index);
        bool skipped = offset < sp->continuation_end || sp->continuations[index];
        if (!skipped && pt_candidate(line, length)) {
            bool declaration = pt_declaration(line, length);
            /* A fresh declaration synchronizes even after an unmatched opener. */
            bool continues = !declaration && sp->start_count != 0 && pt_continues_root(sp, index, offset);
            if (!continues) {
                sp->starts[sp->start_count++] = offset;
                sp->last_start_index = index;
            }
        }
        offset += length;
    }
}

/* ---- the chunks ---- */

typedef struct Output {
    MsBuf imports;
    MsBuf decls;
    MsBuf omitted;
    MsBuf recovered;
    Issues diagnostics;
} Output;

static void pt_copy_out(MsArena *arena, const MsBuf *buf, size_t align, void **data, uint32_t *count, size_t size) {
    *data = ms_alloc(arena, buf->len ? buf->len : 1, align);
    *count = (uint32_t)(buf->len / size);
    if (buf->len != 0) {
        memcpy(*data, buf->data, buf->len);
    }
}

static Probe *pt_take_probe(Splitter *sp, size_t start) {
    for (size_t i = 0; i < sp->probe_count; i++) {
        if (!sp->probes[i].used && sp->probes[i].start == start) {
            sp->probes[i].used = true;
            return &sp->probes[i];
        }
    }
    return NULL;
}

/* Stable sort of the issues by offset (qsort is not stable). */
static void pt_sort_diags(MsDiag *items, uint32_t count) {
    for (uint32_t i = 1; i < count; i++) {
        MsDiag key = items[i];
        uint32_t j = i;
        while (j > 0 && items[j - 1].pos.offset > key.pos.offset) {
            items[j] = items[j - 1];
            j--;
        }
        items[j] = key;
    }
}

/* Parses chunk [start, end); on failure recovers it or omits it. Returns the text to parse into the
 * module, or NULL when the declaration is omitted. */
static const char *pt_prepare_chunk(Splitter *sp, Output *out, size_t start, size_t end, size_t line_offset) {
    Part *part = sp->part;
    const char *chunk = part->src + start;
    size_t length = end - start;
    Probe *probe = pt_take_probe(sp, start);
    MsDiag error;
    bool failed;
    if (probe != NULL && probe->end == end) {
        failed = probe->has_error;
        error = probe->error;
    } else {
        MsModule module;
        failed = !pt_chunk(part, chunk, length, (uint32_t)start, (uint32_t)line_offset, 0, &module, &error);
    }
    if (!failed) {
        return chunk;
    }
    Issues issues = {0};
    char *blanked = pt_recover(part, chunk, length, (uint32_t)start, (uint32_t)line_offset, &error, &issues);
    if (blanked == NULL) {
        MsStr name;
        if (pt_declared_name(part, chunk, length, &name)) {
            ms_buf_put(&out->omitted, &name, sizeof name);
        }
        pt_push_diag(part->arena, &out->diagnostics, &error);
        return NULL;
    }
    pt_sort_diags(issues.items, issues.len);
    for (uint32_t i = 0; i < issues.len; i++) {
        pt_push_diag(part->arena, &out->diagnostics, &issues.items[i]);
    }
    MsSpan span = {(uint32_t)start, (uint32_t)end};
    ms_buf_put(&out->recovered, &span, sizeof span);
    return blanked;
}

/* Parses every chunk between consecutive starts into `module`. */
static void pt_parse_chunks(Splitter *sp, Output *out, MsModule *module) {
    const char *src = sp->part->src;
    size_t line_offset = 0;
    size_t previous = 0;
    for (size_t index = 0; index + 1 < sp->start_count; index++) {
        size_t start = sp->starts[index];
        size_t end = sp->starts[index + 1];
        for (size_t i = previous; i < start; i++) {
            line_offset += src[i] == '\n';
        }
        previous = start;
        const char *text = pt_prepare_chunk(sp, out, start, end, line_offset);
        if (text == NULL) {
            continue;
        }
        /* The chunk is known to parse; parse again in the merged node-id range. */
        MsModule parsed;
        MsDiag ignored;
        if (pt_chunk(sp->part, text, end - start, (uint32_t)start, (uint32_t)line_offset, module->node_count, &parsed, &ignored)) {
            module->node_count = parsed.node_count;
            ms_buf_put(&out->imports, parsed.imports, parsed.nimports * sizeof(MsImport));
            ms_buf_put(&out->decls, parsed.decls, parsed.ndecls * sizeof(MsDecl *));
        }
    }
}

static Splitter pt_splitter_new(Part *part) {
    MsArena *arena = part->arena;
    Lines lines = pt_split_lines(arena, part->src, part->len);
    bool *roots = pt_new_flags(arena, lines.count);
    for (size_t i = 0; i < lines.count; i++) {
        roots[i] = pt_declaration(part->src + lines.items[i].start, lines.items[i].len);
    }
    size_t continuation_count = 0;
    bool *continuations = ms_recovery_continuations(arena, part->src, part->len, roots, lines.count, &continuation_count);
    return (Splitter){.part = part,
                      .lines = lines,
                      .continuations = continuations,
                      .starts = MS_NEW_N(arena, size_t, lines.count + 2),
                      .probes = MS_NEW_N(arena, Probe, lines.count + 1),
                      .attempted_start = (size_t)-1};
}

static void pt_finish(MsArena *arena, Output *out, MsModule *module, MsDiagList *diagnostics) {
    pt_copy_out(arena, &out->imports, _Alignof(MsImport), (void **)&module->imports, &module->nimports, sizeof(MsImport));
    pt_copy_out(arena, &out->decls, _Alignof(MsDecl *), (void **)&module->decls, &module->ndecls, sizeof(MsDecl *));
    pt_copy_out(arena, &out->omitted, _Alignof(MsStr), (void **)&module->omitted, &module->nomitted, sizeof(MsStr));
    pt_copy_out(arena, &out->recovered, _Alignof(MsSpan), (void **)&module->recovered, &module->nrecovered, sizeof(MsSpan));
    ms_buf_free(&out->imports);
    ms_buf_free(&out->decls);
    ms_buf_free(&out->omitted);
    ms_buf_free(&out->recovered);
    diagnostics->items = out->diagnostics.items;
    diagnostics->len = out->diagnostics.len;
}

void ms_parse_partial(MsArena *arena, MsNames *names, const char *src, size_t len, MsModule *module,
                      MsDiagList *diagnostics) {
    *diagnostics = (MsDiagList){0};
    MsDiag strict;
    if (ms_parse(arena, names, src, len, module, &strict)) {
        return;
    }
    memset(module, 0, sizeof *module);
    Part part = {.arena = arena, .names = names, .src = src, .len = len};
    Splitter splitter = pt_splitter_new(&part);
    pt_find_starts(&splitter);
    Output out = {0};
    if (splitter.start_count == 0) {
        pt_push_diag(arena, &out.diagnostics, &strict);
        diagnostics->items = out.diagnostics.items;
        diagnostics->len = out.diagnostics.len;
        return;
    }
    splitter.starts[0] = 0;
    splitter.starts[splitter.start_count++] = len;
    pt_parse_chunks(&splitter, &out, module);
    pt_finish(arena, &out, module, diagnostics);
}
