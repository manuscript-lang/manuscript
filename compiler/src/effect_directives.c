/* Effect directives: reads `// ms: effect NAME` and `// ms: allow_effect PATTERN` lines from the
 * comments above a callable or in a file header, and matches effect names against patterns.
 * Mirrors crates/ms-check/src/effect_directives.rs. */
#include <string.h>

#include "ms/effects.h"
#include "ms/text.h"

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
    MsStr rest = ms_text_trim(text);
    if (!ms_text_starts_with(rest, "// ms:")) {
        return;
    }
    rest = ms_text_trim(ms_text_drop_front(rest, strlen("// ms:")));
    if (ms_text_starts_with(rest, "allow_effect ")) {
        found->has_allow = true;
        push_directive_name(&found->allow, ms_text_trim(ms_text_drop_front(rest, strlen("allow_effect "))));
    } else if (ms_text_starts_with(rest, "effect ")) {
        push_directive_name(&found->declared, ms_text_trim(ms_text_drop_front(rest, strlen("effect "))));
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

static bool is_comment_line(MsStr line) { return ms_text_starts_with(ms_text_trim_start(line), "//"); }

MsDirectives ms_lines_header(MsArena *arena, MsSourceLines lines) {
    DirectiveBuilder found = {0};
    uint32_t comments = 0;
    while (comments < lines.count && is_comment_line(lines.lines[comments])) {
        comments++;
    }
    bool ended_by_blank = comments < lines.count && ms_text_trim(lines.lines[comments]).len == 0;
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
    if (ms_text_ends_with(pattern, ".*")) {
        MsStr prefix = ms_text_drop_back(pattern, 2);
        bool has_prefix = effect.len >= prefix.len && memcmp(effect.ptr, prefix.ptr, prefix.len) == 0;
        return has_prefix && effect.len > prefix.len && effect.ptr[prefix.len] == '.';
    }
    if (ms_text_starts_with(pattern, "*.")) {
        MsStr suffix = ms_text_drop_front(pattern, 2);
        const char *last_dot = NULL;
        for (uint32_t i = effect.len; i > 0 && last_dot == NULL; i--) {
            last_dot = effect.ptr[i - 1] == '.' ? effect.ptr + i - 1 : NULL;
        }
        return last_dot != NULL &&
               ms_text_equal((MsStr){last_dot + 1, (uint32_t)(effect.ptr + effect.len - last_dot - 1)}, suffix);
    }
    return ms_text_equal(pattern, effect);
}
