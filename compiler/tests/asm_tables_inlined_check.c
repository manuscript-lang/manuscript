/* Stands in for the runtime in compiler/tests/asm-tables.sh: the tables of compiler/tests/asm-tables/inlined.s, where
 * LLVM inlined `inner` (lines 10 and up) into `outer` (line 1). The range at line 11 must name a scope for `inner`
 * whose parent is the function itself and whose call line is the last line of the function before it (3), and the range at line 3 must stay the function's own. Exit 0 when they hold. */
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef struct { uintptr_t address; uint32_t size, name_offset, file_offset, line; } Func;
typedef struct { uintptr_t pc; uint32_t line, file_offset; } Line;
typedef struct { uint32_t name_offset, file_offset, parent, call_line; } Scope;
typedef struct {
    uint32_t abi, reserved;
    const Func *funcs; size_t nfuncs;
    const Line *lines; size_t nlines;
    const char *strings; size_t strings_len;
    const uint32_t *line_scopes;
    const Scope *scopes; size_t nscopes;
} Tables;

int msrt_start(void *entry, const Tables *t, int argc, char **argv);
int msrt_start(void *entry, const Tables *t, int argc, char **argv) {
    (void)entry; (void)argc; (void)argv;
    int bad = !(t->nfuncs == 1 && t->nlines == 2 && t->nscopes == 1);
    if (bad) {
        fprintf(stderr, "FAIL: %zu functions, %zu lines, %zu scopes\n", t->nfuncs, t->nlines, t->nscopes);
        return 1;
    }
    const Scope *s = &t->scopes[0];
    bad |= t->lines[0].line != 3 || t->line_scopes[0] != 0;
    bad |= t->lines[1].line != 11 || t->line_scopes[1] != 1;
    bad |= strcmp(t->strings + s->name_offset, "inner") != 0 || s->parent != 0 || s->call_line != 3;
    if (bad) {
        fputs("FAIL: the inlined callee's range does not name its own scope\n", stderr);
    }
    return bad;
}

extern const Tables ms_tables;
int main(void);
int main(void) { return msrt_start(NULL, &ms_tables, 0, NULL); }
