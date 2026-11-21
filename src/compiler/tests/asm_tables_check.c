/* Stands in for the runtime in src/compiler/tests/asm-tables.sh: receives the tables ms_asm_tables built and
 * checks them against the program src/compiler/tests/run/lines.mir: the entry on lines 5-9 with `helper` (lines 1-3)
 * inlined at lines 7 and 8, so there are two scopes and line ranges that belong to them. Exit 0 when they hold. */
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef struct { uintptr_t address; uint32_t size, name_offset, file_offset, line; } Func;
typedef struct { uintptr_t pc; uint32_t line, file_offset; } Line;
typedef struct {
    uint32_t abi, reserved;
    const Func *funcs; size_t nfuncs;
    const Line *lines; size_t nlines;
    const char *strings; size_t strings_len;
    const uint32_t *line_scopes;
    const void *scopes; size_t nscopes;
} Tables;

static int check(int ok, const char *what) {
    if (!ok) fprintf(stderr, "FAIL: %s\n", what);
    return !ok;
}

int msrt_start(void *entry, const Tables *t, int argc, char **argv);
int msrt_start(void *entry, const Tables *t, int argc, char **argv) {
    (void)argc; (void)argv;
    int bad = check(t != NULL && t->abi == 3, "tables with ABI 3");
    bad |= check(t->nfuncs == 1 && t->nscopes == 2, "one function, two inlined scopes");
    const Func *main_fn = t->nfuncs > 0 ? &t->funcs[0] : NULL;
    bad |= check(main_fn != NULL && strcmp(t->strings + main_fn->name_offset, "msmain") == 0, "the name");
    bad |= check(main_fn != NULL && main_fn->address == (uintptr_t)entry && main_fn->size > 0, "entry address and size");
    bad |= check(main_fn != NULL && main_fn->line == 5, "declaration line");
#ifdef MS_LLVM_LINES
    /* the inlined calls on lines 7 and 8 have no code of their own at -O0; the helper's line 2 (scoped) stands in. */
    uint32_t want_main[] = {6, 2, 8, 2, 9};
#else
    uint32_t want_main[] = {6, 7, 8, 9};
#endif
    const size_t want_count = sizeof want_main / sizeof want_main[0];
    size_t seen = 0, scoped = 0;
    uintptr_t last = 0;
    for (size_t i = 0; main_fn != NULL && i < t->nlines; i++) {
        const Line *l = &t->lines[i];
        if (l->pc < main_fn->address || l->pc >= main_fn->address + main_fn->size) continue;
        bad |= check(l->pc >= last, "rising addresses");
        last = l->pc;
        scoped += t->line_scopes[i] != 0;
        if (seen < want_count && l->line == want_main[seen]) seen++;
    }
    bad |= check(seen == want_count, "the expected lines in order inside the entry");
    bad |= check(scoped > 0, "ranges inside the inlined helper name their scope");
    return bad;
}
