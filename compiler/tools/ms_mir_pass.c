/* ms_mir_pass valid|pass NAME FILE...: runs a MIR pass on each file and prints what
 * crates/ms-mir/examples/c_pass_oracle.rs prints, so the two can be diffed byte for byte.
 * `pass NAME`: `changed N`, the module text, then the cold blocks of each function. The C tool
 * has no verifier, so the files to run on are chosen by the Rust oracle's `valid` mode. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/mir.h"
#include "ms/mir_pass.h"

static bool read_file(const char *path, char **data, size_t *len) {
    FILE *f = fopen(path, "rb");
    if (f == NULL) return false;
    size_t cap = 4096, n = 0;
    char *buf = malloc(cap);
    for (;;) {
        n += fread(buf + n, 1, cap - n, f);
        if (n < cap) break;
        cap *= 2;
        buf = realloc(buf, cap);
    }
    fclose(f);
    *data = buf;
    *len = n;
    return true;
}

/* Runs the pass `name` on `m`; false when the name is unknown. */
static bool run_pass(const char *name, MirModule *m, bool *changed) {
    *changed = true;
    if (strcmp(name, "exit_drops") == 0) {
        mir_exit_drops(m);
    } else if (strcmp(name, "expand") == 0) {
        *changed = mir_expand(m, true);
    } else if (strcmp(name, "expand-nochecks") == 0) {
        *changed = mir_expand(m, false);
    } else if (strcmp(name, "expand_owned") == 0) {
        *changed = mir_expand_owned(m);
    } else {
        return false;
    }
    return true;
}

static void print_cold(const MirModule *m, MsBuf *out) {
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        const MirFunc *f = &m->funcs[fi];
        bool any = false;
        for (uint32_t bi = 0; bi < f->nblocks; bi++) {
            if (!f->blocks[bi].cold) {
                continue;
            }
            if (!any) {
                MsStr name = ms_name(&m->names, f->name);
                ms_buf_printf(out, "cold %.*s: [", (int)name.len, name.ptr);
            }
            ms_buf_printf(out, "%s%u", any ? ", " : "", bi);
            any = true;
        }
        if (any) {
            ms_buf_puts(out, "]\n");
        }
    }
}

int main(int argc, char **argv) {
    if (argc < 4 || strcmp(argv[1], "pass") != 0) {
        fputs("usage: ms_mir_pass pass NAME FILE...\n", stderr);
        return 2;
    }
    MsBuf out = {0};
    for (int i = 3; i < argc; i++) {
        char *src;
        size_t len;
        if (!read_file(argv[i], &src, &len)) {
            fprintf(stderr, "cannot read %s\n", argv[i]);
            return 1;
        }
        ms_buf_printf(&out, "=== %s\n", argv[i]);
        MirModule m;
        mir_module_init(&m);
        uint32_t line;
        MsStr msg;
        bool changed = false;
        if (!mir_parse(&m, src, len, &line, &msg)) {
            ms_buf_puts(&out, "error\n");
        } else if (!run_pass(argv[2], &m, &changed)) {
            fprintf(stderr, "unknown pass %s\n", argv[2]);
            return 2;
        } else {
            ms_buf_printf(&out, "changed %d\n", changed ? 1 : 0);
            mir_print_module(&m, &out);
            print_cold(&m, &out);
        }
        mir_module_free(&m);
        free(src);
    }
    fwrite(out.data, 1, out.len, stdout);
    ms_buf_free(&out);
    return 0;
}
