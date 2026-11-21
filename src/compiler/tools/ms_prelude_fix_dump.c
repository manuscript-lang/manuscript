/* ms_prelude_fix_dump: answers the sources that crates/ms-syntax/examples/c_prelude_fix_oracle.rs
 * answers, one line in, one line out, so prelude_fix.c can be diffed against prelude_imports.rs. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "dump_io.h"
#include "ms/parse.h"
#include "ms/prelude_fix.h"

static void put_fix(bool found, MsFix fix) {
    if (!found) {
        fputs("-", stdout);
        return;
    }
    printf("%u:%u:%u-%u:%u:%u=[", fix.pos.offset, fix.pos.line, fix.pos.column, fix.end.offset, fix.end.line,
           fix.end.column);
    for (uint32_t i = 0; i < fix.replacement.len; i++) {
        char c = fix.replacement.ptr[i];
        if (c == '\n') {
            fputs("\\n", stdout);
        } else if (c == '\r') {
            fputs("\\r", stdout);
        } else {
            fputc(c, stdout);
        }
    }
    fputc(']', stdout);
}

static void answer(MsArena *arena, const char *line) {
    MsStr source = dump_unescape(arena, line, true);
    MsNames names;
    ms_names_init(&names);
    MsModule mod;
    MsDiagList diagnostics;
    ms_parse_partial(arena, &names, source.ptr, source.len, &mod, &diagnostics);
    printf("%u ", mod.nimports);
    for (uint32_t i = 0; i < mod.nimports; i++) {
        MsFix fix = {0};
        bool found = ms_prelude_import_fix(arena, source, mod.imports, mod.nimports, &mod.imports[i], &fix);
        fputs(i == 0 ? "" : " | ", stdout);
        put_fix(found, fix);
    }
    fputc('\n', stdout);
    ms_names_free(&names);
}

int main(void) {
    char line[1 << 14];
    while (fgets(line, sizeof line, stdin) != NULL) {
        line[strcspn(line, "\n")] = 0;
        MsArena arena = {0};
        answer(&arena, line);
        ms_arena_free(&arena);
    }
    return 0;
}
