/* Effect directives: reads `// ms: effect NAME` and `// ms: allow_effect PATTERN` lines from the
 * comments above a callable or in a file header, and matches effect names against patterns.
 * Mirrors crates/ms-check/src/effect_directives.rs. */
#include <string.h>

#include "ms/effects.h"
#include "ms_rt/chars.h"

/* ---- text helpers: Rust's `text_trim` family, which removes Unicode White_Space ---- */

static bool is_unicode_space(uint32_t scalar) {
    if (scalar == ' ' || (scalar >= 0x09 && scalar <= 0x0D)) {
        return true;
    }
    if (scalar < 0x85) {
        return false;
    }
    return scalar == 0x85 || scalar == 0xA0 || scalar == 0x1680 ||
           (scalar >= 0x2000 && scalar <= 0x200A) || scalar == 0x2028 || scalar == 0x2029 ||
           scalar == 0x202F || scalar == 0x205F || scalar == 0x3000;
}

/* The scalar that starts at text[at], and its length in bytes. `text` is valid UTF-8. */
static uint32_t text_scalar_at(MsStr text, uint32_t at, int *length) {
    uint32_t scalar = 0;
    *length = ms_utf8_decode(text.ptr + at, text.len - at, &scalar);
    return scalar;
}

/* The start of the last scalar that ends at text[end]. */
static uint32_t last_scalar_start(MsStr text, uint32_t end) {
    uint32_t start = end - 1;
    while (start > 0 && ms_utf8_is_continuation((uint8_t)text.ptr[start])) {
        start--;
    }
    return start;
}

static MsStr text_trim_start(MsStr text) {
    uint32_t at = 0;
    while (at < text.len) {
        int length = 0;
        if (!is_unicode_space(text_scalar_at(text, at, &length))) {
            break;
        }
        at += (uint32_t)length;
    }
    return (MsStr){text.ptr + at, text.len - at};
}

static MsStr text_trim_end(MsStr text) {
    uint32_t end = text.len;
    while (end > 0) {
        uint32_t start = last_scalar_start(text, end);
        int length = 0;
        if (!is_unicode_space(text_scalar_at(text, start, &length))) {
            break;
        }
        end = start;
    }
    return (MsStr){text.ptr, end};
}

static MsStr text_trim(MsStr text) { return text_trim_end(text_trim_start(text)); }

static bool text_starts_with(MsStr text, const char *prefix) {
    size_t length = strlen(prefix);
    return text.len >= length && memcmp(text.ptr, prefix, length) == 0;
}

static bool text_ends_with(MsStr text, const char *suffix) {
    size_t length = strlen(suffix);
    return text.len >= length && memcmp(text.ptr + text.len - length, suffix, length) == 0;
}

static MsStr text_drop_front(MsStr text, size_t count) {
    return (MsStr){text.ptr + count, (uint32_t)(text.len - count)};
}

static MsStr text_drop_back(MsStr text, size_t count) {
    return (MsStr){text.ptr, (uint32_t)(text.len - count)};
}

static bool text_equal(MsStr a, MsStr b) { return a.len == b.len && memcmp(a.ptr, b.ptr, a.len) == 0; }

/* ---- lines ---- */

MsSourceLines ms_lines_index(MsArena *arena, MsStr source) {
    uint32_t count = 1;
    for (uint32_t i = 0; i < source.len; i++) {
        count += source.ptr[i] == '\n';
    }
    MsStr *lines = MS_NEW_N(arena, MsStr, count);
    uint32_t line = 0;
    uint32_t start = 0;
    for (uint32_t i = 0; i <= source.len; i++) {
        if (i < source.len && source.ptr[i] != '\n') {
            continue;
        }
        uint32_t end = i;
        while (end > start && source.ptr[end - 1] == '\r') {
            end--;
        }
        lines[line++] = (MsStr){source.ptr + start, end - start};
        start = i + 1;
    }
    return (MsSourceLines){lines, count};
}

/* ---- directives ---- */

/* A directive being collected: both lists grow in a scratch buffer, then are copied out. */
typedef struct DirectiveBuilder {
    MsBuf declared; /* MsStr values */
    MsBuf allow;    /* MsStr values */
    bool has_allow;
} DirectiveBuilder;

static void push_directive_name(MsBuf *list, MsStr name) { ms_buf_put(list, &name, sizeof name); }

/* Reads one comment line: `// ms: allow_effect X` or `// ms: effect X`; anything else is ignored. */
static void read_directive_line(DirectiveBuilder *found, MsStr text) {
    MsStr rest = text_trim(text);
    if (!text_starts_with(rest, "// ms:")) {
        return;
    }
    rest = text_trim(text_drop_front(rest, strlen("// ms:")));
    if (text_starts_with(rest, "allow_effect ")) {
        found->has_allow = true;
        push_directive_name(&found->allow, text_trim(text_drop_front(rest, strlen("allow_effect "))));
    } else if (text_starts_with(rest, "effect ")) {
        push_directive_name(&found->declared, text_trim(text_drop_front(rest, strlen("effect "))));
    }
}

static MsEffectScope directive_scope(MsArena *arena, const MsBuf *list, bool present) {
    uint32_t count = (uint32_t)(list->len / sizeof(MsStr));
    MsStr *names = MS_NEW_N(arena, MsStr, count);
    if (count != 0) {
        memcpy(names, list->data, list->len);
    }
    return (MsEffectScope){names, count, present};
}

static MsDirectives finish_directives(MsArena *arena, DirectiveBuilder *found) {
    MsDirectives result = {
        .declared = directive_scope(arena, &found->declared, true),
        .allow = directive_scope(arena, &found->allow, found->has_allow),
    };
    ms_buf_free(&found->declared);
    ms_buf_free(&found->allow);
    return result;
}

static bool is_comment_line(MsStr line) { return text_starts_with(text_trim_start(line), "//"); }

MsDirectives ms_lines_header(MsArena *arena, MsSourceLines lines) {
    DirectiveBuilder found = {0};
    uint32_t comments = 0;
    while (comments < lines.count && is_comment_line(lines.lines[comments])) {
        comments++;
    }
    bool ended_by_blank = comments < lines.count && text_trim(lines.lines[comments]).len == 0;
    if (comments != 0 && ended_by_blank) {
        for (uint32_t i = 0; i < comments; i++) {
            read_directive_line(&found, lines.lines[i]);
        }
    }
    return finish_directives(arena, &found);
}

MsDirectives ms_lines_above(MsArena *arena, MsSourceLines lines, uint32_t line) {
    DirectiveBuilder found = {0};
    uint32_t at = line == 0 ? 0 : line - 1;
    if (at > lines.count) {
        at = 0; /* a line past the end has no comment block above it */
    }
    while (at > 0 && is_comment_line(lines.lines[at - 1])) {
        read_directive_line(&found, lines.lines[at - 1]);
        at--;
    }
    return finish_directives(arena, &found);
}

/* ---- patterns ---- */

bool ms_effect_matches(MsStr pattern, MsStr effect) {
    if (pattern.len == 1 && pattern.ptr[0] == '*') {
        return true;
    }
    if (text_ends_with(pattern, ".*")) {
        MsStr prefix = text_drop_back(pattern, 2);
        bool has_prefix = effect.len >= prefix.len && memcmp(effect.ptr, prefix.ptr, prefix.len) == 0;
        return has_prefix && effect.len > prefix.len && effect.ptr[prefix.len] == '.';
    }
    if (text_starts_with(pattern, "*.")) {
        MsStr suffix = text_drop_front(pattern, 2);
        const char *last_dot = NULL;
        for (uint32_t i = effect.len; i > 0 && last_dot == NULL; i--) {
            last_dot = effect.ptr[i - 1] == '.' ? effect.ptr + i - 1 : NULL;
        }
        return last_dot != NULL &&
               text_equal((MsStr){last_dot + 1, (uint32_t)(effect.ptr + effect.len - last_dot - 1)}, suffix);
    }
    return text_equal(pattern, effect);
}
