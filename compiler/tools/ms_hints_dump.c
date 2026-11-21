/* ms_hints_dump: answers the tab-separated queries that compiler/tests/hints_oracle.rs answers, one
 * line in, one line out, so hints.c can be diffed against the Rust helpers. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/hints.h"
#include "dump_io.h"

/* A comma-separated list; empty text is an empty list. */
static size_t split_items(MsArena *arena, char *text, MsStr **items) {
    size_t count = text[0] == 0 ? 0 : 1;
    for (const char *c = text; *c != 0; c++) {
        count += *c == ',';
    }
    *items = MS_NEW_N(arena, MsStr, count + 1);
    size_t n = 0;
    char *at = text;
    while (n < count) {
        char *comma = strchr(at, ',');
        if (comma != NULL) {
            *comma = 0;
        }
        (*items)[n++] = str_of(at);
        at = comma != NULL ? comma + 1 : at + strlen(at);
    }
    return n;
}

static void put_escaped(MsStr s) {
    for (uint32_t i = 0; i < s.len; i++) {
        if (s.ptr[i] == '\n') {
            fputs("\\n", stdout);
        } else {
            fputc(s.ptr[i], stdout);
        }
    }
}

static void answer_rename(MsArena *arena, char **f) {
    MsPos from = {(uint32_t)number_of(f[2]), (uint32_t)number_of(f[3]), (uint32_t)number_of(f[4])};
    MsFix fix;
    if (!ms_rename_module_path(arena, dump_unescape(arena, f[1], false), from, str_of(f[5]), str_of(f[6]), &fix)) {
        fputs("-", stdout);
        return;
    }
    printf("%u %u %u %u %u %u ", fix.pos.offset, fix.pos.line, fix.pos.column, fix.end.offset, fix.end.line,
           fix.end.column);
    put_escaped(fix.replacement);
}

static void put_unique(MsArena *arena, MsStr *items, size_t count) {
    MsStr *sorted = NULL;
    size_t n = ms_unique_sorted(arena, items, count, &sorted);
    for (size_t i = 0; i < n; i++) {
        printf("%s%.*s", i == 0 ? "" : ",", (int)sorted[i].len, sorted[i].ptr);
    }
}

static void put_optional(const char *s) {
    fputs(s != NULL ? s : "-", stdout);
}

MS_NODISCARD static bool answer(MsArena *arena, char **f, size_t nfields) {
    const char *op = f[0];
    MsStr *items = NULL;
    size_t count = 0;
    if (nfields > 2 && (strcmp(op, "closest") == 0 || strcmp(op, "didyoumean") == 0 || strcmp(op, "list") == 0 ||
                        strcmp(op, "synonym") == 0)) {
        count = split_items(arena, f[2], &items);
    }
    if (strcmp(op, "dist") == 0) {
        printf("%zu", ms_edit_distance(arena, str_of(f[1]), str_of(f[2])));
    } else if (strcmp(op, "closest") == 0) {
        put_text(ms_closest(arena, str_of(f[1]), items, count));
    } else if (strcmp(op, "didyoumean") == 0) {
        put_text(ms_did_you_mean(arena, str_of(f[1]), items, count));
    } else if (strcmp(op, "list") == 0) {
        put_text(ms_hint_list(arena, items, count, number_of(f[1])));
    } else if (strcmp(op, "unique") == 0) {
        count = split_items(arena, f[1], &items);
        put_unique(arena, items, count);
    } else if (strcmp(op, "sketch") == 0) {
        put_text(ms_type_sketch(arena, str_of(f[1]), number_of(f[2])));
    } else if (strcmp(op, "plural") == 0) {
        put_text(ms_plural(arena, number_of(f[1]), f[2]));
    } else if (strcmp(op, "renamed") == 0) {
        put_optional(ms_renamed_module(str_of(f[1])));
    } else if (strcmp(op, "synonym") == 0) {
        put_text(ms_synonym_hint(arena, str_of(f[1]), items, count));
    } else if (strcmp(op, "alias") == 0) {
        put_optional(ms_type_alias(str_of(f[1])));
    } else if (strcmp(op, "rename") == 0) {
        answer_rename(arena, f);
    } else {
        fprintf(stderr, "unknown op %s\n", op);
        return false;
    }
    return true;
}

int main(void) {
    static char empty[] = "";
    MsBuf line = {0};
    int status = 0;
    while (status == 0 && read_line(&line)) {
        MsArena arena = {0};
        char *fields[8];
        for (size_t i = 0; i < MS_COUNT_OF(fields); i++) {
            fields[i] = empty;
        }
        size_t n = split_fields(line.data, fields, MS_COUNT_OF(fields));
        status = answer(&arena, fields, n) ? 0 : 2;
        fputc('\n', stdout);
        ms_arena_free(&arena);
    }
    ms_buf_free(&line);
    return status;
}
