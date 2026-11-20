/* ms_effects_dump: answers the tab-separated cases that compiler/tests/effects_oracle.rs answers,
 * one line in, one line out, so effects.c can be diffed against effect_directives.rs. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/effects.h"

static MsStr str_of(const char *s) {
    return (MsStr){s, (uint32_t)strlen(s)};
}

/* The source text with "\n" and "\r" escapes turned back into characters. */
static MsStr unescape(MsArena *arena, const char *s) {
    char *out = ms_arena_strndup(arena, s, strlen(s));
    size_t n = 0;
    for (size_t i = 0; s[i] != 0; i++) {
        bool escape = s[i] == '\\' && (s[i + 1] == 'n' || s[i + 1] == 'r');
        if (escape) {
            out[n++] = s[i + 1] == 'n' ? '\n' : '\r';
            i++;
        } else {
            out[n++] = s[i];
        }
    }
    out[n] = 0;
    return (MsStr){out, (uint32_t)n};
}

static void put_names(const MsStr *names, uint32_t count) {
    for (uint32_t i = 0; i < count; i++) {
        printf("%s%.*s", i == 0 ? "" : ";", (int)names[i].len, names[i].ptr);
    }
}

static void put_directives(MsDirectives d) {
    fputs("allow=", stdout);
    if (d.has_allow) {
        fputc('<', stdout);
        put_names(d.allow, d.nallow);
        fputc('>', stdout);
    } else {
        fputc('-', stdout);
    }
    fputs(" declared=<", stdout);
    put_names(d.declared, d.ndeclared);
    fputc('>', stdout);
}

/* Splits `line` at tabs in place; returns the field count (at most `max`). */
static size_t split_fields(char *line, char **fields, size_t max) {
    size_t n = 0;
    char *at = line;
    while (n < max) {
        fields[n++] = at;
        char *tab = strchr(at, '\t');
        if (tab == NULL) {
            break;
        }
        *tab = 0;
        at = tab + 1;
    }
    return n;
}

MS_NODISCARD static bool answer(MsArena *arena, char **f, size_t nfields) {
    if (strcmp(f[0], "M") == 0 && nfields == 3) {
        fputs(ms_effect_matches(str_of(f[1]), str_of(f[2])) ? "true" : "false", stdout);
    } else if (strcmp(f[0], "H") == 0 && nfields == 2) {
        put_directives(ms_lines_header(arena, ms_lines_split(arena, unescape(arena, f[1]))));
    } else if (strcmp(f[0], "A") == 0 && nfields == 3) {
        MsLines lines = ms_lines_split(arena, unescape(arena, f[2]));
        put_directives(ms_lines_above(arena, lines, (uint32_t)strtoul(f[1], NULL, 10)));
    } else {
        return false;
    }
    fputc('\n', stdout);
    return true;
}

int main(void) {
    char line[1 << 14];
    while (fgets(line, sizeof line, stdin) != NULL) {
        line[strcspn(line, "\n")] = 0;
        char *fields[4];
        size_t nfields = split_fields(line, fields, 4);
        MsArena arena = {0};
        bool ok = answer(&arena, fields, nfields);
        ms_arena_free(&arena);
        if (!ok) {
            fprintf(stderr, "bad case: %s\n", fields[0]);
            return 1;
        }
    }
    return 0;
}
