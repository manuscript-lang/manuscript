/* Editor recovery: keeps the declarations of a file that parse independently. A port of
 * crates/ms-syntax/src/partial.rs; see there for the reasoning behind each heuristic. */
#include <stdlib.h>
#include <string.h>

#include "ms/lex.h"
#include "ms/parse.h"

typedef struct Part {
    MsArena *arena;
    MsNames *names;
    const char *src;
    size_t len;
} Part;

typedef struct Line {
    size_t start, len;
} Line;

/* ---- text helpers (Rust's str::trim is Unicode White_Space) ---- */

static bool pt_white(uint32_t c) {
    return (c >= 9 && c <= 13) || c == 32 || c == 0x85 || c == 0xA0 || c == 0x1680 ||
           (c >= 0x2000 && c <= 0x200A) || c == 0x2028 || c == 0x2029 || c == 0x202F || c == 0x205F ||
           c == 0x3000;
}

static size_t pt_trim_start(const char *s, size_t n) {
    size_t i = 0;
    while (i < n) {
        uint32_t c;
        int k = ms_utf8_decode(s + i, n - i, &c);
        if (!pt_white(c)) {
            break;
        }
        i += (size_t)k;
    }
    return i;
}

static size_t pt_trim_end(const char *s, size_t n) {
    while (n > 0) {
        size_t i = n - 1;
        while (i > 0 && ((uint8_t)s[i] & 0xC0) == 0x80) {
            i--;
        }
        uint32_t c;
        ms_utf8_decode(s + i, n - i, &c);
        if (!pt_white(c)) {
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

static bool pt_word_byte(uint8_t b) {
    return (b >= '0' && b <= '9') || (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') || b == '_';
}

static bool pt_alpha_byte(uint8_t b) {
    return (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z');
}

/* The rest after `keyword`, as an offset, or -1 when the source does not start with that word. */
static long pt_after_keyword(const char *s, size_t n, const char *keyword) {
    size_t k = strlen(keyword);
    if (!pt_starts(s, n, keyword)) {
        return -1;
    }
    if (n > k && pt_word_byte((uint8_t)s[k])) {
        return -1;
    }
    return (long)k;
}

static bool pt_constant_start(const char *s, size_t n) {
    size_t name = 0;
    while (name < n && pt_word_byte((uint8_t)s[name])) {
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
    static const char *const keywords[] = {"import", "export", "extern", "type", "enum", "interface", "impl", "test"};
    for (size_t i = 0; i < sizeof keywords / sizeof keywords[0]; i++) {
        if (pt_after_keyword(s, n, keywords[i]) >= 0) {
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
        bool name_start = rn > 0 && (pt_alpha_byte((uint8_t)rest[0]) || rest[0] == '_');
        size_t name_end = 0;
        while (name_end < rn && pt_word_byte((uint8_t)rest[name_end])) {
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

/* ---- statement recovery ---- */

/* Removes the dangling tail of line `at` (a trailing `.`, `?.`, operator or separator) until the
 * declaration parses, keeping the line's columns by padding with spaces. Returns the new text, or
 * NULL when trimming does not make it parse. */
static char *pt_trim_dangling(Part *pt, const char *text, size_t len, const Line *lines, size_t at) {
    const Line ln = lines[at];
    const char *line = text + ln.start;
    size_t body = ln.len;
    while (body > 0 && (line[body - 1] == '\n' || line[body - 1] == '\r')) {
        body--;
    }
    size_t code_len = pt_trim_end(line, body);
    for (size_t i = 0; i + 1 < code_len + 1 && i < code_len; i++) {
        if (line[i] == '"' || (line[i] == '/' && i + 1 < code_len && line[i + 1] == '/')) {
            return NULL;
        }
    }
    for (int round = 0; round < 3; round++) {
        size_t kept = code_len;
        while (kept > 0 && (strchr(".?+-*/%<>=!,|", line[kept - 1]) != NULL || line[kept - 1] == ' ')) {
            kept--;
        }
        static const char *const words[] = {"and", "or", "not"};
        for (int w = 0; w < 3; w++) {
            size_t k = strlen(words[w]);
            if (kept >= k && memcmp(line + kept - k, words[w], k) == 0 && kept > k && line[kept - k - 1] == ' ') {
                kept -= k;
                break;
            }
        }
        if (kept == code_len || pt_trim_start(line, kept) == kept) {
            return NULL;
        }
        code_len = pt_trim_end(line, kept);
        char *attempt = ms_alloc(pt->arena, len + 1, 1);
        memcpy(attempt, text, len);
        memset(attempt + ln.start, ' ', body);
        memcpy(attempt + ln.start, line, code_len);
        attempt[len] = 0;
        MsModule m;
        MsDiag d;
        if (ms_parse(pt->arena, pt->names, attempt, len, &m, &d)) {
            return attempt;
        }
    }
    return NULL;
}

typedef struct Issues {
    MsDiag *items;
    uint32_t len, cap;
} Issues;

static void pt_push_diag(Part *pt, Issues *v, const MsDiag *d) {
    if (v->len == v->cap) {
        uint32_t ncap = v->cap ? v->cap * 2 : 4;
        MsDiag *n = MS_NEW_N(pt->arena, MsDiag, ncap);
        if (v->len != 0) {
            memcpy(n, v->items, v->len * sizeof(MsDiag));
        }
        v->items = n;
        v->cap = ncap;
    }
    v->items[v->len++] = *d;
}

/* Retries a failed declaration chunk with each offending statement (and the block it opens)
 * blanked to spaces, so every remaining statement keeps its original position. Returns the new
 * text, or NULL when no bounded number of blankings parses; the issues found go to `issues`. */
static char *pt_recover(Part *pt, const char *chunk, size_t len, uint32_t base_offset, uint32_t base_line,
                        const MsDiag *first, Issues *issues) {
    char *text = ms_alloc(pt->arena, len + 1, 1);
    memcpy(text, chunk, len);
    text[len] = 0;
    size_t nlines = 0;
    for (size_t i = 0; i < len; i++) {
        nlines += chunk[i] == '\n';
    }
    nlines += len > 0 && chunk[len - 1] != '\n';
    Line *lines = MS_NEW_N(pt->arena, Line, nlines + 1);
    size_t at_ = 0, k = 0;
    for (size_t i = 0; i < len; i++) {
        if (chunk[i] == '\n' || i + 1 == len) {
            lines[k++] = (Line){at_, i + 1 - at_};
            at_ = i + 1;
        }
    }
    MsDiag issue = *first;
    for (int attempt = 0; attempt < 8; attempt++) {
        /* An unterminated delimiter is reported at the end of the chunk; the statement to drop is
         * the one that opened it. Only the first failure is redirected. */
        size_t line = (size_t)(uint32_t)(issue.pos.line - base_line);
        size_t opened = issue.opener_line > base_line ? issue.opener_line - base_line : 0;
        if (opened > 0 && attempt == 0) {
            line = opened;
        }
        /* A misindented line of multi-line text drops the whole statement. */
        if (attempt == 0 && pt_starts(issue.message.ptr, issue.message.len, "text line is indented less")) {
            while (line > 1 && line <= nlines) {
                const char *l = text + lines[line - 1].start;
                size_t ll = pt_trim_end(l, lines[line - 1].len);
                if (pt_ends(l, ll, "\"\"\"")) {
                    break;
                }
                line--;
            }
        }
        /* The header line (line 1) failing means the signature is unusable. */
        if (line < 2 || line > nlines) {
            return NULL;
        }
        pt_push_diag(pt, issues, &issue);
        size_t at = line - 1;
        size_t indent = pt_leading_space(text + lines[at].start, lines[at].len);
        MsStr trimmed = pt_trim(text + lines[at].start, lines[at].len);
        if (trimmed.len == 0 || indent == 0) {
            return NULL;
        }
        /* A one-line statement cut off mid-expression keeps its operands for navigation once the
         * dangling tail is trimmed. */
        bool single = true;
        for (size_t j = at + 1; j < nlines; j++) {
            if (pt_trim(text + lines[j].start, lines[j].len).len != 0) {
                single = pt_leading_space(text + lines[j].start, lines[j].len) <= indent;
                break;
            }
        }
        if (single) {
            char *t = pt_trim_dangling(pt, text, len, lines, at);
            if (t != NULL) {
                return t;
            }
        }
        for (size_t j = at; j < nlines; j++) {
            const char *l = text + lines[j].start;
            if (j > at && pt_trim(l, lines[j].len).len != 0 && pt_leading_space(l, lines[j].len) <= indent) {
                break;
            }
            for (size_t b = 0; b < lines[j].len; b++) {
                if (text[lines[j].start + b] != '\r' && text[lines[j].start + b] != '\n') {
                    text[lines[j].start + b] = ' ';
                }
            }
        }
        MsModule m;
        MsDiag e;
        if (pt_chunk(pt, text, len, base_offset, base_line, 0, &m, &e)) {
            return text;
        }
        issue = e;
    }
    return NULL;
}

/* The name a declaration chunk introduces, for chunks that failed to parse. */
static bool pt_declared_name(Part *pt, const char *chunk, size_t len, MsStr *out) {
    size_t at = 0;
    while (at <= len) {
        size_t end = at;
        while (end < len && chunk[end] != '\n') {
            end++;
        }
        MsStr t = pt_trim(chunk + at, end - at);
        at = end + 1;
        if (t.len == 0 || pt_starts(t.ptr, t.len, "//")) {
            if (end >= len) {
                break;
            }
            continue;
        }
        const char *rest = t.ptr;
        size_t rn = t.len;
        if (pt_starts(rest, rn, "export ")) {
            rest += 7;
            rn -= 7;
        }
        if (pt_starts(rest, rn, "opaque ")) {
            rest += 7;
            rn -= 7;
        }
        /* The first two whitespace-separated fields. */
        MsStr fields[2];
        size_t nf = 0, i = 0;
        while (i < rn && nf < 2) {
            size_t lo = i;
            while (lo < rn) {
                uint32_t c;
                int k = ms_utf8_decode(rest + lo, rn - lo, &c);
                if (!pt_white(c)) {
                    break;
                }
                lo += (size_t)k;
            }
            size_t hi = lo;
            while (hi < rn) {
                uint32_t c;
                int k = ms_utf8_decode(rest + hi, rn - hi, &c);
                if (pt_white(c)) {
                    break;
                }
                hi += (size_t)k;
            }
            if (hi == lo) {
                break;
            }
            fields[nf++] = (MsStr){rest + lo, (uint32_t)(hi - lo)};
            i = hi;
        }
        if (nf < 2) {
            return false;
        }
        MsStr f0 = fields[0];
        bool known = (f0.len == 2 && memcmp(f0.ptr, "fn", 2) == 0) || (f0.len == 4 && memcmp(f0.ptr, "type", 4) == 0) ||
                     (f0.len == 4 && memcmp(f0.ptr, "enum", 4) == 0) ||
                     (f0.len == 9 && memcmp(f0.ptr, "interface", 9) == 0);
        if (!known) {
            return false;
        }
        /* The first non-empty piece of field two split on ( [ : */
        const char *f = fields[1].ptr;
        size_t fl = fields[1].len, lo = 0;
        while (lo < fl && (f[lo] == '(' || f[lo] == '[' || f[lo] == ':')) {
            lo++;
        }
        if (lo == fl) {
            return false;
        }
        size_t hi = lo;
        while (hi < fl && f[hi] != '(' && f[hi] != '[' && f[hi] != ':') {
            hi++;
        }
        char *copy = ms_alloc(pt->arena, hi - lo + 1, 1);
        memcpy(copy, f + lo, hi - lo);
        copy[hi - lo] = 0;
        *out = (MsStr){copy, (uint32_t)(hi - lo)};
        return true;
    }
    return false;
}

/* ---- the splitter ---- */

typedef struct Probe {
    size_t start, end;
    bool has_err, used;
    MsDiag err;
} Probe;

static int pt_cmp_diag(const void *a, const void *b) {
    uint32_t x = ((const MsDiag *)a)->pos.offset, y = ((const MsDiag *)b)->pos.offset;
    return x < y ? -1 : x > y;
}

/* Stable sort of the issues by offset (qsort is not stable). */
static void pt_sort_diags(MsDiag *v, uint32_t n) {
    for (uint32_t i = 1; i < n; i++) {
        MsDiag key = v[i];
        uint32_t j = i;
        while (j > 0 && pt_cmp_diag(&v[j - 1], &key) > 0) {
            v[j] = v[j - 1];
            j--;
        }
        v[j] = key;
    }
}

static bool pt_has_closer(const char *s, size_t n) {
    for (size_t i = 0; i < n; i++) {
        if (s[i] == ')' || s[i] == ']' || s[i] == '}') {
            return true;
        }
    }
    return false;
}

void ms_parse_partial(MsArena *arena, MsNames *names, const char *src, size_t len, MsModule *module,
                      MsDiagList *diagnostics) {
    Part pt = {arena, names, src, len};
    MsDiag strict;
    diagnostics->items = NULL;
    diagnostics->len = 0;
    if (ms_parse(arena, names, src, len, module, &strict)) {
        return;
    }
    memset(module, 0, sizeof *module);
    Issues diags = {0};
    /* Lines, as split_inclusive('\n'). */
    size_t nlines = 0;
    for (size_t i = 0; i < len; i++) {
        nlines += src[i] == '\n';
    }
    nlines += len > 0 && src[len - 1] != '\n';
    Line *lines = MS_NEW_N(arena, Line, nlines + 1);
    {
        size_t at = 0, k = 0;
        for (size_t i = 0; i < len; i++) {
            if (src[i] == '\n' || i + 1 == len) {
                lines[k++] = (Line){at, i + 1 - at};
                at = i + 1;
            }
        }
    }
    bool *roots = MS_NEW_N(arena, bool, nlines + 1);
    memset(roots, 0, nlines + 1);
    for (size_t i = 0; i < nlines; i++) {
        roots[i] = pt_declaration(src + lines[i].start, lines[i].len);
    }
    size_t ncont;
    bool *cont = ms_recovery_continuations(arena, src, len, roots, nlines, &ncont);

    size_t *starts = MS_NEW_N(arena, size_t, nlines + 2);
    size_t nstarts = 0;
    Probe *probes = MS_NEW_N(arena, Probe, nlines + 1);
    size_t nprobes = 0;
    size_t attempted_start = (size_t)-1, continuation_end = 0, offset = 0, last_start_index = 0;
    size_t *line_offsets = NULL, *next_declaration = NULL;
    bool have_prefixes = false;
    size_t prefix_start = 0;
    bool *prefixes = NULL;
    size_t nprefixes = 0;
    for (size_t index = 0; index < nlines; index++) {
        const char *line = src + lines[index].start;
        size_t ll = lines[index].len;
        if (offset < continuation_end || cont[index]) {
            offset += ll;
            continue;
        }
        if (pt_candidate(line, ll)) {
            bool declaration = pt_declaration(line, ll);
            /* A fresh declaration synchronizes even after an unmatched opener. */
            if (!declaration && nstarts != 0) {
                size_t last = starts[nstarts - 1];
                bool unterminated;
                if (have_prefixes && prefix_start == last) {
                    size_t k = index - last_start_index;
                    unterminated = k < nprefixes ? prefixes[k] : false;
                } else {
                    MsLexed lx;
                    MsDiag ld;
                    unterminated = !ms_lex(arena, src + last, offset - last, &lx, &ld) &&
                                   (pt_starts(ld.message.ptr, ld.message.len, "unterminated delimiter") ||
                                    pt_starts(ld.message.ptr, ld.message.len, "unterminated multi-line text"));
                }
                if (unterminated) {
                    size_t start = last;
                    if (attempted_start != start) {
                        attempted_start = start;
                        /* Probe each possible root once, up to the next possible root. */
                        if (pt_root_start(src + start, len - start)) {
                            size_t end = offset;
                            for (size_t ni = index; ni < nlines; ni++) {
                                if (!cont[ni] && pt_root_start(src + lines[ni].start, lines[ni].len)) {
                                    break;
                                }
                                end += lines[ni].len;
                            }
                            size_t start_line = last_start_index;
                            if (nstarts == 1) {
                                start = 0; /* The first chunk owns its leading trivia. */
                                start_line = 0;
                            }
                            /* An open prefix cannot parse without a later closer. */
                            if (pt_has_closer(src + offset, end - offset)) {
                                MsModule pm;
                                MsDiag pd;
                                bool ok = pt_chunk(&pt, src + start, end - start, (uint32_t)start, (uint32_t)start_line, 0, &pm, &pd);
                                bool single = ok && pt_single_root(&pm);
                                if (!ok || single) {
                                    Probe *pr = &probes[nprobes++];
                                    pr->start = start;
                                    pr->end = end;
                                    pr->has_err = !ok;
                                    pr->used = false;
                                    if (!ok) {
                                        pr->err = pd;
                                    }
                                }
                                if (single) {
                                    continuation_end = end;
                                }
                            }
                        }
                    }
                    if (continuation_end <= offset && !(have_prefixes && prefix_start == last)) {
                        if (line_offsets == NULL) {
                            line_offsets = MS_NEW_N(arena, size_t, nlines + 2);
                            next_declaration = MS_NEW_N(arena, size_t, nlines + 2);
                            line_offsets[0] = 0;
                            for (size_t k = 0; k < nlines; k++) {
                                line_offsets[k + 1] = line_offsets[k] + lines[k].len;
                            }
                            next_declaration[nlines] = nlines;
                            next_declaration[nlines + 1] = nlines;
                            for (size_t k = nlines; k > 0; k--) {
                                size_t i2 = k - 1;
                                next_declaration[i2] = (!cont[i2] && pt_declaration(src + lines[i2].start, lines[i2].len))
                                                           ? i2
                                                           : next_declaration[i2 + 1];
                            }
                        }
                        size_t end_index = next_declaration[index + 1];
                        size_t nstop = end_index - last_start_index;
                        bool *stop_at = MS_NEW_N(arena, bool, nstop + 1);
                        memset(stop_at, 0, nstop + 1);
                        for (size_t i2 = 0; i2 < nstop; i2++) {
                            size_t li = last_start_index + i2;
                            stop_at[i2] = i2 > 0 && !cont[li] && pt_candidate(src + lines[li].start, lines[li].len) &&
                                          !pt_declaration(src + lines[li].start, lines[li].len);
                        }
                        prefixes = ms_unterminated_prefixes(arena, src + last, line_offsets[end_index] - last, stop_at,
                                                            nstop, &nprefixes);
                        prefix_start = last;
                        have_prefixes = true;
                    }
                    offset += ll;
                    continue;
                }
            }
            starts[nstarts++] = offset;
            last_start_index = index;
        }
        offset += ll;
    }
    if (nstarts == 0) {
        pt_push_diag(&pt, &diags, &strict);
        diagnostics->items = diags.items;
        diagnostics->len = diags.len;
        return;
    }
    starts[0] = 0;
    starts[nstarts++] = len;
    size_t line_offset = 0, previous = 0;
    MsBuf imports = {0}, decls = {0}, omitted = {0}, recovered = {0};
    for (size_t index = 0; index + 1 < nstarts; index++) {
        size_t start = starts[index], end = starts[index + 1];
        for (size_t i = previous; i < start; i++) {
            line_offset += src[i] == '\n';
        }
        previous = start;
        const char *chunk = src + start;
        size_t clen = end - start;
        bool has_err;
        MsDiag err;
        Probe *probe = NULL;
        for (size_t k = 0; k < nprobes; k++) {
            if (!probes[k].used && probes[k].start == start) {
                probe = &probes[k];
                probe->used = true;
                break;
            }
        }
        if (probe != NULL && probe->end == end) {
            has_err = probe->has_err;
            err = probe->err;
        } else {
            MsModule cm;
            has_err = !pt_chunk(&pt, chunk, clen, (uint32_t)start, (uint32_t)line_offset, 0, &cm, &err);
        }
        const char *text = chunk;
        if (has_err) {
            Issues issues = {0};
            char *blanked = pt_recover(&pt, chunk, clen, (uint32_t)start, (uint32_t)line_offset, &err, &issues);
            if (blanked == NULL) {
                MsStr name;
                if (pt_declared_name(&pt, chunk, clen, &name)) {
                    ms_buf_put(&omitted, &name, sizeof name);
                }
                pt_push_diag(&pt, &diags, &err);
                continue;
            }
            pt_sort_diags(issues.items, issues.len);
            for (uint32_t k = 0; k < issues.len; k++) {
                pt_push_diag(&pt, &diags, &issues.items[k]);
            }
            MsSpan span = {(uint32_t)start, (uint32_t)end};
            ms_buf_put(&recovered, &span, sizeof span);
            text = blanked;
        }
        /* The chunk is known to parse; parse again in the merged node-id range. */
        MsModule parsed;
        MsDiag pd;
        if (pt_chunk(&pt, text, clen, (uint32_t)start, (uint32_t)line_offset, module->node_count, &parsed, &pd)) {
            module->node_count = parsed.node_count;
            ms_buf_put(&imports, parsed.imports, parsed.nimports * sizeof(MsImport));
            ms_buf_put(&decls, parsed.decls, parsed.ndecls * sizeof(MsDecl *));
        }
    }
    module->nimports = (uint32_t)(imports.len / sizeof(MsImport));
    module->imports = ms_alloc(arena, imports.len ? imports.len : 1, _Alignof(MsImport));
    module->ndecls = (uint32_t)(decls.len / sizeof(MsDecl *));
    module->decls = ms_alloc(arena, decls.len ? decls.len : 1, _Alignof(MsDecl *));
    module->nomitted = (uint32_t)(omitted.len / sizeof(MsStr));
    module->omitted = ms_alloc(arena, omitted.len ? omitted.len : 1, _Alignof(MsStr));
    module->nrecovered = (uint32_t)(recovered.len / sizeof(MsSpan));
    module->recovered = ms_alloc(arena, recovered.len ? recovered.len : 1, _Alignof(MsSpan));
    if (imports.len) memcpy(module->imports, imports.data, imports.len);
    if (decls.len) memcpy(module->decls, decls.data, decls.len);
    if (omitted.len) memcpy(module->omitted, omitted.data, omitted.len);
    if (recovered.len) memcpy(module->recovered, recovered.data, recovered.len);
    ms_buf_free(&imports);
    ms_buf_free(&decls);
    ms_buf_free(&omitted);
    ms_buf_free(&recovered);
    diagnostics->items = diags.items;
    diagnostics->len = diags.len;
}
