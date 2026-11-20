/* Effect directives (ms/effects.h). */
#include "ms/effects.h"

#include <string.h>

#include "ms/hints.h"

static bool is_space(char c) {
    return c == ' ' || (c >= '\t' && c <= '\r');
}

static MsStr trim_start(MsStr s) {
    while (s.len > 0 && is_space(s.ptr[0])) {
        s.ptr++;
        s.len--;
    }
    return s;
}

static MsStr trim_end(MsStr s, bool (*drop)(char)) {
    while (s.len > 0 && drop(s.ptr[s.len - 1])) {
        s.len--;
    }
    return s;
}

static bool is_carriage_return(char c) {
    return c == '\r';
}

static MsStr trim(MsStr s) {
    return trim_end(trim_start(s), is_space);
}

/* `s` without `prefix`, or false when it does not start with it. */
static bool strip_prefix(MsStr s, const char *prefix, MsStr *rest) {
    MsStr p = {prefix, (uint32_t)strlen(prefix)};
    if (!ms_str_starts_with(s, p)) {
        return false;
    }
    *rest = (MsStr){s.ptr + p.len, s.len - p.len};
    return true;
}

static bool starts_with_comment(MsStr line) {
    return ms_str_starts_with(trim_start(line), (MsStr){"//", 2});
}

typedef struct DirectiveBuf {
    MsBuf declared;
    MsBuf allow;
    bool has_allow;
} DirectiveBuf;

static void add_line(DirectiveBuf *found, MsStr text) {
    MsStr rest;
    if (!strip_prefix(trim(text), "// ms:", &rest)) {
        return;
    }
    rest = trim(rest);
    MsStr name;
    if (strip_prefix(rest, "allow_effect ", &name)) {
        found->has_allow = true;
        MS_VEC_PUSH(found->allow, MsStr, trim(name));
    } else if (strip_prefix(rest, "effect ", &name)) {
        MS_VEC_PUSH(found->declared, MsStr, trim(name));
    }
}

/* Moves the collected names into the arena. */
static MsDirectives copy_directives(MsArena *arena, DirectiveBuf *found) {
    MsDirectives out = {0};
    out.has_allow = found->has_allow;
    out.ndeclared = (uint32_t)MS_VEC_LEN(found->declared, MsStr);
    out.nallow = (uint32_t)MS_VEC_LEN(found->allow, MsStr);
    MsStr *declared = MS_NEW_N(arena, MsStr, out.ndeclared + 1);
    MsStr *allow = MS_NEW_N(arena, MsStr, out.nallow + 1);
    for (uint32_t i = 0; i < out.ndeclared; i++) {
        declared[i] = MS_VEC_AT(found->declared, MsStr, i);
    }
    for (uint32_t i = 0; i < out.nallow; i++) {
        allow[i] = MS_VEC_AT(found->allow, MsStr, i);
    }
    out.declared = declared;
    out.allow = allow;
    ms_buf_free(&found->declared);
    ms_buf_free(&found->allow);
    return out;
}

MsLines ms_lines_split(MsArena *arena, MsStr source) {
    uint32_t count = 1;
    for (uint32_t i = 0; i < source.len; i++) {
        count += source.ptr[i] == '\n';
    }
    MsStr *lines = MS_NEW_N(arena, MsStr, count);
    uint32_t n = 0;
    uint32_t start = 0;
    for (uint32_t i = 0; i <= source.len; i++) {
        if (i < source.len && source.ptr[i] != '\n') {
            continue;
        }
        MsStr line = {source.ptr + start, i - start};
        lines[n++] = trim_end(line, is_carriage_return);
        start = i + 1;
    }
    return (MsLines){lines, count};
}

MsDirectives ms_lines_header(MsArena *arena, MsLines lines) {
    DirectiveBuf found = {0};
    uint32_t comments = 0;
    while (comments < lines.count && starts_with_comment(lines.lines[comments])) {
        comments++;
    }
    bool ends_blank = comments < lines.count && trim(lines.lines[comments]).len == 0;
    for (uint32_t i = 0; comments > 0 && ends_blank && i < comments; i++) {
        add_line(&found, lines.lines[i]);
    }
    return copy_directives(arena, &found);
}

MsDirectives ms_lines_above(MsArena *arena, MsLines lines, uint32_t line) {
    DirectiveBuf found = {0};
    uint32_t at = line == 0 ? 0 : line - 1;
    if (at > lines.count) {
        at = lines.count;
    }
    while (at > 0 && starts_with_comment(lines.lines[at - 1])) {
        add_line(&found, lines.lines[at - 1]);
        at--;
    }
    return copy_directives(arena, &found);
}

bool ms_effect_matches(MsStr pattern, MsStr effect) {
    if (pattern.len == 1 && pattern.ptr[0] == '*') {
        return true;
    }
    bool prefix_form = pattern.len >= 2 && pattern.ptr[pattern.len - 2] == '.' &&
                       pattern.ptr[pattern.len - 1] == '*';
    if (prefix_form) {
        MsStr prefix = {pattern.ptr, pattern.len - 2};
        return ms_str_starts_with(effect, prefix) && effect.len > prefix.len &&
               effect.ptr[prefix.len] == '.';
    }
    if (pattern.len >= 2 && pattern.ptr[0] == '*' && pattern.ptr[1] == '.') {
        MsStr suffix = {pattern.ptr + 2, pattern.len - 2};
        uint32_t dot = effect.len;
        while (dot > 0 && effect.ptr[dot - 1] != '.') {
            dot--;
        }
        MsStr last = {effect.ptr + dot, effect.len - dot};
        return dot > 0 && ms_str_equal(last, suffix);
    }
    return ms_str_equal(pattern, effect);
}
