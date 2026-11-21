/* ms_fixes_dump: answers the tab-separated cases that crates/ms-syntax/examples/c_fixes_oracle.rs
 * answers, one line in, one line out, so fixes.c can be diffed against suggestions.rs. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/fixes.h"
#include "ms/parse.h"
#include "dump_io.h"

static uint32_t number32(const char *s) { return (uint32_t)number_of(s); }

static MsPos pos_of(char **f) {
    return (MsPos){number32(f[0]), number32(f[1]), number32(f[2])};
}

static void put_pos(MsPos p) {
    printf("%u:%u:%u", p.offset, p.line, p.column);
}

static void put_fix(bool found, MsFix fix) {
    if (!found) {
        fputs("-", stdout);
        return;
    }
    put_pos(fix.pos);
    fputc('-', stdout);
    put_pos(fix.end);
    fputc('=', stdout);
    for (uint32_t i = 0; i < fix.replacement.len; i++) {
        if (fix.replacement.ptr[i] == '\n') {
            fputs("\\n", stdout);
        } else {
            fputc(fix.replacement.ptr[i], stdout);
        }
    }
}

/* The fix for the expression `f[0]` over the constant `A := text`. */
static void answer_expression(MsArena *arena, char **f, size_t nfields) {
    const char *op = f[0];
    MsStr source = ms_arena_fmt(arena, "A := %s\n", f[1]);
    MsNames names;
    ms_names_init(&names);
    MsModule mod;
    MsDiag diag;
    MsFix fix = {0};
    if (!ms_parse(arena, &names, source.ptr, source.len, &mod, &diag)) {
        fputs("parse-error", stdout);
    } else if (mod.ndecls == 0 || mod.decls[0]->kind != MS_D_CONST) {
        fputs("not-constant", stdout);
    } else {
        const MsExpr *e = mod.decls[0]->u.konst.value;
        bool found = false;
        if (strcmp(op, "call") == 0) {
            found = ms_append_call(arena, source, e, str_of("call()"), &fix);
        } else if (strcmp(op, "parens") == 0) {
            found = ms_append_parens(arena, source, e, &fix);
        } else if (strcmp(op, "interpolate") == 0) {
            found = ms_interpolate(arena, source, e, &fix);
        } else if (strcmp(op, "float") == 0) {
            found = ms_to_float(arena, source, e, &fix);
        } else if (strcmp(op, "convert") == 0 && nfields == 4) {
            found = ms_conversion_fix(arena, source, e, str_of(f[2]), str_of(f[3]), &fix);
        } else if (strcmp(op, "none") == 0 && e->kind != MS_E_BINARY) {
            fputs("not-binary", stdout);
            ms_names_free(&names);
            return;
        } else if (strcmp(op, "none") == 0) {
            found = ms_none_test(arena, source, e, e->u.bin.left, strcmp(f[2], "present") == 0, &fix);
        }
        put_fix(found, fix);
    }
    ms_names_free(&names);
}

MS_NODISCARD static bool answer(MsArena *arena, char **f, size_t nfields) {
    MsFix fix = {0};
    const char *op = f[0];
    if (strcmp(op, "F") == 0 && nfields == 6) {
        put_fix(ms_fix_for(arena, dump_unescape(arena, f[1], false), pos_of(f + 2), number32(f[5]), &fix), fix);
    } else if (strcmp(op, "B") == 0 && nfields == 5) {
        put_fix(ms_binding_to_var(arena, dump_unescape(arena, f[1], false), pos_of(f + 2), &fix), fix);
    } else if (strcmp(op, "D") == 0 && nfields == 6) {
        put_fix(ms_drop_case_parens(dump_unescape(arena, f[1], false), pos_of(f + 2), str_of(f[5]), &fix), fix);
    } else if (strcmp(op, "K") == 0 && nfields == 4) {
        MsPos at = {number32(f[2]), 1, 1};
        fputs(ms_is_compound_operator(dump_unescape(arena, f[1], false), at, str_of(f[3])) ? "true" : "false", stdout);
    } else if (strcmp(op, "X") == 0 && nfields >= 3) {
        answer_expression(arena, f + 1, nfields - 1);
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
        char empty[1] = "";
        char *fields[8];
        for (size_t i = 0; i < MS_COUNT_OF(fields); i++) {
            fields[i] = empty;
        }
        size_t nfields = split_fields(line, fields, 8);
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
