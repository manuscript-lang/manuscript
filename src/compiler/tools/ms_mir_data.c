/* ms_mir_data FILE: reads MIR text, runs glue, and prints the static data of the module: one line
 * per symbol, then its relocations. Tests pin it; the emitters print the same symbols. */
#include <stdio.h>
#include <stdlib.h>

#include "ms/mir_data.h"
#include "read_file.h"

static void print_target(const MirModule *m, const MirData *d, MirRef t) {
    if (t.kind == MT_DATA) {
        printf("%s", d->syms[t.index].name);
    } else if (t.kind == MT_FUNC) {
        const MsStr name = ms_name(&m->names, m->funcs[t.index].name);
        printf("@%.*s", (int)name.len, name.ptr);
    } else {
        printf("%s", t.runtime);
    }
}

static void print_sym(const MirModule *m, const MirData *d, const MirDataSym *s) {
    printf("%s size %u align %u %s%s", s->name, s->size, s->align, s->writable ? "rw" : "ro",
           s->bytes == NULL ? " zero" : "");
    for (uint32_t i = 0; s->bytes != NULL && i < s->size; i++) {
        printf("%s%02x", i % 8 == 0 ? " " : "", s->bytes[i]);
    }
    putchar('\n');
    for (uint32_t i = 0; i < s->nrelocs; i++) {
        printf("  +%u -> ", s->relocs[i].offset);
        print_target(m, d, s->relocs[i].to);
        putchar('\n');
    }
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fputs("usage: ms_mir_data FILE\n", stderr);
        return 2;
    }
    size_t n = 0;
    char *src = read_whole_file(argv[1], &n);
    if (src == NULL) {
        fprintf(stderr, "cannot read %s\n", argv[1]);
        return 1;
    }
    MirModule m;
    mir_module_init(&m);
    uint32_t line;
    MsStr message;
    if (!mir_parse(&m, src, n, &line, &message)) {
        fprintf(stderr, "%s:%u: %.*s\n", argv[1], line, (int)message.len, message.ptr);
        mir_module_free(&m);
        free(src);
        return 1;
    }
    MirGlue glue = {0};
    mir_glue_run_and_expand(&m, &glue);
    MirData data;
    mir_data_build(&m, &glue, &data);
    for (uint32_t i = 0; i < data.nsyms; i++) {
        print_sym(&m, &data, &data.syms[i]);
    }
    free(src);
    mir_module_free(&m);
    return 0;
}
