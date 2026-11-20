/* @std/regex natives on PCRE2: see regex.h for the dialect and the limits. */
#define PCRE2_CODE_UNIT_WIDTH 8
#include "regex.h"

#include <pcre2.h>
#include <stdio.h>
#include <string.h>

#include "ms_rt/alloc.h"
#include "ms_rt/chars.h"

/* PCRE2 allocates through the runtime, so its memory is the program's memory. */
static void *re_alloc(PCRE2_SIZE size, void *unused) {
    (void)unused;
    return msrt_alloc(size);
}
static void re_free(void *p, void *unused) {
    (void)unused;
    if (p) msrt_free(p);
}

struct MsRegex {
    pcre2_code *code;
    pcre2_match_context *ctx; /* limits; read-only during matching, so a handle may be used from many threads */
    uint32_t slots;
};

/* ---- pattern screening --------------------------------------------------------------------------------------- */

static int is_hex(unsigned char c) { return (c >= '0' && c <= '9') || ((c | 0x20) >= 'a' && (c | 0x20) <= 'f'); }

/* \x takes one or two hex digits, or hex digits in braces; PCRE2 alone would read \x+1 as a NUL then a quantifier. */
static int hex_escape_ok(const unsigned char *p, size_t n, size_t i) {
    if (i + 2 < n && p[i + 2] == '{') {
        size_t j = i + 3;
        while (j < n && is_hex(p[j])) j++;
        return j > i + 3 && j < n && p[j] == '}';
    }
    return i + 2 < n && is_hex(p[i + 2]);
}

/* Returns the reason a pattern uses a feature outside the dialect, with its byte offset in *at, or NULL. Back-references
   written as \1 are found after compiling (PCRE2_INFO_BACKREFMAX); this scan finds the rest. */
static const char *screen(const unsigned char *p, size_t n, size_t *at) {
    size_t i = 0;
    while (i < n) {
        unsigned char c = p[i];
        if (c == '\\') {
            unsigned char d = i + 1 < n ? p[i + 1] : 0;
            if (d == 'Q') { /* literal text up to \E */
                i += 2;
                while (i < n && !(p[i] == '\\' && i + 1 < n && p[i + 1] == 'E')) i++;
                i += 2;
                continue;
            }
            if (d == 'g' || d == 'k') {
                *at = i;
                return "back-references and subroutine calls are not supported";
            }
            if (d == 'x' && !hex_escape_ok(p, n, i)) {
                *at = i;
                return "invalid hexadecimal escape";
            }
            i += 2;
        } else if (c == '[') {
            size_t j = i + 1;
            if (j < n && p[j] == '^') j++;
            if (j < n && p[j] == ']') j++;
            while (j < n && p[j] != ']') {
                if (p[j] == '\\') {
                    if (j + 1 < n && p[j + 1] == 'x' && !hex_escape_ok(p, n, j)) {
                        *at = j;
                        return "invalid hexadecimal escape";
                    }
                    j += 2;
                } else if (p[j] == '[' && j + 1 < n && (p[j + 1] == ':' || p[j + 1] == '.' || p[j + 1] == '=')) {
                    unsigned char q = p[j + 1];
                    j += 2;
                    while (j + 1 < n && !(p[j] == q && p[j + 1] == ']')) j++;
                    j += 2;
                } else {
                    j++;
                }
            }
            i = j + 1;
        } else if (c == '(') {
            unsigned char d = i + 1 < n ? p[i + 1] : 0;
            if (d == '*') {
                *at = i;
                return "verbs are not supported";
            }
            if (d == '?') {
                unsigned char e = i + 2 < n ? p[i + 2] : 0;
                unsigned char f = i + 3 < n ? p[i + 3] : 0;
                *at = i;
                if (e == '=' || e == '!') return "lookahead is not supported";
                if (e == '<' && (f == '=' || f == '!')) return "lookbehind is not supported";
                if (e == 'R' || e == '&' || (e >= '0' && e <= '9') || ((e == '+' || e == '-') && f >= '0' && f <= '9'))
                    return "recursion and subroutine calls are not supported";
                if (e == 'P' && (f == '>' || f == '=')) return "back-references and subroutine calls are not supported";
                if (e == '(') return "conditional groups are not supported";
                if (e == 'C') return "callouts are not supported";
                if (e == '#') { /* comment: skip it */
                    i += 3;
                    while (i < n && p[i] != ')') i++;
                    continue;
                }
            }
            i++;
        } else {
            i++;
        }
    }
    return NULL;
}

static size_t column_of(const char *pattern, size_t offset) {
    size_t col = 1;
    for (size_t i = 0; i < offset; i++)
        if (!ms_utf8_is_continuation((uint8_t)pattern[i])) col++;
    return col;
}

static void put_message(char *msg, size_t cap, const char *reason, size_t column) {
    if (!cap) return;
    size_t used = 0;
    const char *at = " at column ";
    for (const char *s = reason; *s && used + 1 < cap; s++) msg[used++] = *s;
    for (const char *s = at; *s && used + 1 < cap; s++) msg[used++] = *s;
    char digits[24];
    size_t nd = 0;
    do {
        digits[nd++] = (char)('0' + column % 10);
        column /= 10;
    } while (column);
    while (nd && used + 1 < cap) msg[used++] = digits[--nd];
    msg[used] = 0;
}

MsRegex *ms_re_compile(const char *pattern, size_t len, char *msg, size_t cap) {
    size_t at = 0;
    if (len > MS_RE_PATTERN_MAX) {
        put_message(msg, cap, "pattern is too long", 1);
        return NULL;
    }
    const char *why = screen((const unsigned char *)pattern, len, &at);
    if (why) {
        put_message(msg, cap, why, column_of(pattern, at));
        return NULL;
    }
    pcre2_general_context *gc = pcre2_general_context_create(re_alloc, re_free, NULL);
    pcre2_compile_context *cc = gc ? pcre2_compile_context_create(gc) : NULL;
    if (!cc) {
        pcre2_general_context_free(gc);
        put_message(msg, cap, "out of memory", 1);
        return NULL;
    }
    pcre2_set_newline(cc, PCRE2_NEWLINE_LF);
    int code_err = 0;
    PCRE2_SIZE off = 0;
    uint32_t options = PCRE2_UTF | PCRE2_UCP | PCRE2_DOLLAR_ENDONLY | PCRE2_NEVER_BACKSLASH_C;
    pcre2_code *code = pcre2_compile((PCRE2_SPTR)pattern, len, options, &code_err, &off, cc);
    pcre2_compile_context_free(cc);
    MsRegex *re = NULL;
    if (!code) {
        PCRE2_UCHAR buf[160];
        if (pcre2_get_error_message(code_err, buf, sizeof buf) < 0) snprintf((char *)buf, sizeof buf, "invalid pattern");
        put_message(msg, cap, (const char *)buf, column_of(pattern, off));
        goto out;
    }
    uint32_t backref = 0, captures = 0;
    pcre2_pattern_info(code, PCRE2_INFO_BACKREFMAX, &backref);
    pcre2_pattern_info(code, PCRE2_INFO_CAPTURECOUNT, &captures);
    if (backref) {
        put_message(msg, cap, "back-references and subroutine calls are not supported", 1);
        pcre2_code_free(code);
        goto out;
    }
    pcre2_jit_compile(code, PCRE2_JIT_COMPLETE); /* no JIT on this machine is not an error: the interpreter runs */
    pcre2_match_context *ctx = pcre2_match_context_create(gc);
    re = msrt_alloc(sizeof *re);
    if (!ctx || !re) {
        pcre2_match_context_free(ctx);
        pcre2_code_free(code);
        put_message(msg, cap, "out of memory", 1);
        re = NULL;
        goto out;
    }
    pcre2_set_match_limit(ctx, MS_RE_MATCH_LIMIT);
    pcre2_set_depth_limit(ctx, MS_RE_DEPTH_LIMIT);
    pcre2_set_heap_limit(ctx, MS_RE_HEAP_KIB);
    re->code = code;
    re->ctx = ctx;
    re->slots = captures + 1;
out:
    pcre2_general_context_free(gc);
    return re;
}

void ms_re_free(MsRegex *re) {
    if (!re) return;
    pcre2_match_context_free(re->ctx);
    pcre2_code_free(re->code);
    msrt_free(re);
}

size_t ms_re_slots(const MsRegex *re) { return re->slots; }

const char *ms_re_group_name(const MsRegex *re, size_t i, size_t *len) {
    uint32_t count = 0, size = 0;
    PCRE2_SPTR table = NULL;
    pcre2_pattern_info(re->code, PCRE2_INFO_NAMECOUNT, &count);
    pcre2_pattern_info(re->code, PCRE2_INFO_NAMEENTRYSIZE, &size);
    pcre2_pattern_info(re->code, PCRE2_INFO_NAMETABLE, &table);
    for (uint32_t k = 0; k < count; k++) {
        const unsigned char *entry = table + (size_t)k * size;
        if ((size_t)(entry[0] << 8 | entry[1]) == i) {
            *len = strlen((const char *)entry + 2);
            return (const char *)entry + 2;
        }
    }
    return NULL;
}

/* ---- matching ------------------------------------------------------------------------------------------------ */

static pcre2_match_data *scratch_for(const MsRegex *re, void **cache) {
    if (cache && *cache) return *cache;
    pcre2_general_context *gc = pcre2_general_context_create(re_alloc, re_free, NULL);
    pcre2_match_data *md = gc ? pcre2_match_data_create(re->slots, gc) : NULL;
    pcre2_general_context_free(gc); /* the match data keeps its own allocator */
    if (cache) *cache = md;
    return md;
}

static int run(const MsRegex *re, pcre2_match_data *md, const char *text, size_t len, size_t start) {
    int rc = pcre2_match(re->code, (PCRE2_SPTR)text, len, start, PCRE2_NO_UTF_CHECK, md, re->ctx);
    if (rc == PCRE2_ERROR_JIT_STACKLIMIT) {
        /* The default JIT stack (32 KiB) was too small: retry once on a stack that grows to the cap. */
        pcre2_match_context *big = pcre2_match_context_copy(re->ctx);
        pcre2_jit_stack *stack = big ? pcre2_jit_stack_create(64 << 10, MS_RE_JIT_STACK_MAX, NULL) : NULL;
        if (!stack) {
            pcre2_match_context_free(big);
            return MS_RE_LIMIT;
        }
        pcre2_jit_stack_assign(big, NULL, stack);
        rc = pcre2_match(re->code, (PCRE2_SPTR)text, len, start, PCRE2_NO_UTF_CHECK, md, big);
        pcre2_match_context_free(big);
        pcre2_jit_stack_free(stack);
    }
    if (rc >= 0) return MS_RE_MATCHED;
    if (rc == PCRE2_ERROR_NOMATCH) return MS_RE_NOMATCH;
    if (rc == PCRE2_ERROR_MATCHLIMIT || rc == PCRE2_ERROR_DEPTHLIMIT || rc == PCRE2_ERROR_HEAPLIMIT ||
        rc == PCRE2_ERROR_JIT_STACKLIMIT || rc == PCRE2_ERROR_NOMEMORY)
        return MS_RE_LIMIT;
    return MS_RE_FAULT;
}

static void read_slots(const MsRegex *re, pcre2_match_data *md, int64_t *slots) {
    const PCRE2_SIZE *ov = pcre2_get_ovector_pointer(md);
    for (uint32_t i = 0; i < re->slots; i++) {
        int set = ov[(size_t)i * 2] != PCRE2_UNSET;
        const size_t first = (size_t)i * 2;
        slots[first] = set ? (int64_t)ov[first] : -1;
        slots[first + 1] = set ? (int64_t)ov[first + 1] : -1;
    }
}

int ms_re_match(const MsRegex *re, const char *text, size_t len, size_t start, int64_t *slots) {
    pcre2_match_data *md = scratch_for(re, NULL);
    if (!md) return MS_RE_LIMIT;
    int rc = run(re, md, text, len, start);
    if (rc == MS_RE_MATCHED && slots) read_slots(re, md, slots);
    pcre2_match_data_free(md);
    return rc;
}

void ms_re_iter_init(MsRegexIter *it) {
    it->pos = 0;
    it->prev_end = SIZE_MAX;
    it->scratch = NULL;
}

void ms_re_iter_done(MsRegexIter *it) {
    if (it->scratch) pcre2_match_data_free(it->scratch);
    it->scratch = NULL;
}

int ms_re_next(const MsRegex *re, const char *text, size_t len, MsRegexIter *it, int64_t *slots) {
    pcre2_match_data *md = scratch_for(re, &it->scratch);
    if (!md) return MS_RE_LIMIT;
    while (it->pos <= len) {
        int rc = run(re, md, text, len, it->pos);
        if (rc != MS_RE_MATCHED) return rc;
        const PCRE2_SIZE *ov = pcre2_get_ovector_pointer(md);
        size_t s = ov[0], e = ov[1];
        int accept = 1;
        if (e == it->pos) {
            if (s == it->prev_end) accept = 0;
            size_t step = 1;
            if (it->pos < len)
                while (it->pos + step < len && ms_utf8_is_continuation((uint8_t)text[it->pos + step])) step++;
            it->pos += step;
        } else {
            it->pos = e;
        }
        it->prev_end = e;
        if (accept) {
            if (slots) read_slots(re, md, slots);
            return MS_RE_MATCHED;
        }
    }
    return MS_RE_NOMATCH;
}
