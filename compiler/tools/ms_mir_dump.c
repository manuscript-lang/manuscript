/* ms_mir_dump MODE FILE...: reads MIR text files and prints, per file, what
 * crates/ms-mir/examples/c_oracle.rs prints, so the two can be diffed byte for byte.
 * MODE: print (canonical text, or `error line N`), ops (the opcode table), analysis (control-flow and
 * ownership facts). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/mir.h"
#include "ms/mir_analysis.h"

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

static char mode_char(MirMode mode) {
    return mode == MM_MOVE ? 'M' : mode == MM_VAR ? 'V' : 'B';
}

static void print_ids(MsBuf *out, const MirBlock *ids, uint32_t n) {
    for (uint32_t i = 0; i < n; i++) {
        ms_buf_printf(out, i == 0 ? "%u" : " %u", ids[i]);
    }
}

/* What the Rust oracle's `analysis` mode prints for one function. */
static void print_analysis(const MirModule *m, const MirFunc *f, MsBuf *out) {
    MsArena arena = {0};
    ms_buf_printf(out, "func %.*s\n", (int)ms_name(&m->names, f->name).len,
                  ms_name(&m->names, f->name).ptr);
    MirBlock *order = NULL;
    const uint32_t count = mir_rpo(&arena, f, &order);
    ms_buf_puts(out, "rpo ");
    print_ids(out, order, count);
    ms_buf_putc(out, '\n');
    const MirPreds preds = mir_preds(&arena, f);
    for (uint32_t b = 0; b < f->nblocks; b++) {
        ms_buf_printf(out, "preds %u: ", b);
        for (uint32_t i = 0; i < mir_preds_count(&preds, b); i++) {
            ms_buf_printf(out, i == 0 ? "%u" : " %u", mir_pred(&preds, b, i));
        }
        ms_buf_putc(out, '\n');
    }
    const MirBlock *idom = mir_dominators(&arena, f, order, count, &preds);
    ms_buf_puts(out, "idom");
    for (uint32_t b = 0; b < f->nblocks; b++) {
        if (idom[b] == MIR_NONE) {
            ms_buf_puts(out, " -");
        } else {
            ms_buf_printf(out, " %u", idom[b]);
        }
    }
    ms_buf_putc(out, '\n');
    for (uint32_t b = 0; b < f->nblocks; b++) {
        for (uint32_t i = 0; i < f->blocks[b].ninsts; i++) {
            const MirInst *inst = &f->blocks[b].insts[i];
            MirMode res = MM_BORROW;
            const bool has = mir_result_mode(m, f, inst, &res);
            ms_buf_printf(out, "%u.%u res=%c views=%d owned=%llx args=", b, i, has ? mode_char(res) : '-',
                          mir_result_views(m, f, inst), (unsigned long long)mir_indirect_owned(m, f, inst));
            MirMode *modes = MS_NEW_N(&arena, MirMode, inst->nargs + 1);
            mir_arg_modes(m, f, inst, modes);
            for (uint32_t k = 0; k < inst->nargs; k++) {
                ms_buf_putc(out, mode_char(modes[k]));
            }
            ms_buf_putc(out, '\n');
        }
    }
    ms_arena_free(&arena);
}

static void run_module(const char *mode, const MirModule *m, MsBuf *out) {
    if (strcmp(mode, "print") == 0) {
        mir_print_module(m, out);
        return;
    }
    for (uint32_t i = 0; i < m->nfuncs; i++) {
        print_analysis(m, &m->funcs[i], out);
    }
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fputs("usage: ms_mir_dump print|analysis|ops FILE...\n", stderr);
        return 2;
    }
    const char *mode = argv[1];
    MsBuf out = {0};
    if (strcmp(mode, "ops") == 0) {
        for (int i = 0; i < MOP_COUNT; i++) {
            const MirOpInfo *o = &mir_op_info[i];
            ms_buf_printf(&out, "%s imm=%d res=%d fx=%d\n", o->name, o->imm, o->has_result, o->effects);
        }
    }
    for (int i = 2; i < argc && strcmp(mode, "ops") != 0; i++) {
        char *src;
        size_t len;
        if (!read_file(argv[i], &src, &len)) {
            fprintf(stderr, "cannot read %s\n", argv[i]);
            return 1;
        }
        ms_buf_printf(&out, "=== %s\n", argv[i]);
        if (!ms_utf8_valid(src, len)) {
            ms_buf_puts(&out, "error invalid-utf8\n");
            free(src);
            continue;
        }
        MirModule m;
        mir_module_init(&m);
        uint32_t line;
        MsStr msg;
        if (mir_parse(&m, src, len, &line, &msg)) {
            run_module(mode, &m, &out);
        } else {
            ms_buf_printf(&out, "error line %u\n", line);
        }
        mir_module_free(&m);
        free(src);
    }
    if (out.len > 0) {
        fwrite(out.data, 1, out.len, stdout);
    }
    ms_buf_free(&out);
    return 0;
}
