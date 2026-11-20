/* ms_mir_dump MODE FILE...: reads MIR text files and prints, per file, what
 * crates/ms-mir/examples/c_oracle.rs prints, so the two can be diffed byte for byte.
 * MODE: print (canonical text, or `error line N`), ops (the opcode table). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/mir.h"
#include "ms/mir_analysis.h"
#include "ms/mir_layout.h"
#include "ms/mir_opt.h"

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

/* One line per alternative and per optional type: whether it lives behind a pointer. */
static void dump_boxing(const MirModule *m, MsBuf *out) {
    for (uint32_t a = 0; a < m->nalts; a++) {
        ms_buf_printf(out, "alt %u %d\n", a, mir_alt_is_boxed(m, a) ? 1 : 0);
    }
    for (uint32_t t = 0; t < m->types.len; t++) {
        if (mir_ty_data(m, t)->kind == MK_OPT) {
            ms_buf_printf(out, "opt %u %d\n", t, mir_opt_is_boxed(m, mir_ty_data(m, t)->elem) ? 1 : 0);
        }
    }
}

static void put_leaves(MsBuf *out, MirLeafSpan leaves) {
    for (uint32_t i = 0; i < leaves.len; i++) {
        ms_buf_printf(out, "%s%s", i == 0 ? "" : ",", mir_leaf_name(leaves.ptr[i]));
    }
}

static void put_numbers(MsBuf *out, const uint32_t *numbers, uint32_t count) {
    for (uint32_t i = 0; i < count; i++) {
        ms_buf_printf(out, "%s%u", i == 0 ? "" : ",", numbers[i]);
    }
}

static void put_flags(MsBuf *out, const bool *flags, uint32_t count) {
    for (uint32_t i = 0; i < count; i++) {
        ms_buf_putc(out, flags[i] ? '1' : '0');
    }
}

static void dump_alt(MirLayouts *lay, MirTy t, const MirShape *shape, uint32_t alt, MsBuf *out) {
    ms_buf_printf(out, "  boxed=%d\n", mir_layouts_alt_boxed(lay, alt) ? 1 : 0);
    const char *kind = shape->alt == MIR_ALT_BOXED ? "boxed" : "inline";
    for (uint32_t c = 0; c < lay->module->alts[alt].ncases; c++) {
        ms_buf_printf(out, "  %s case %u slots=", kind, c);
        put_numbers(out, shape->slots + shape->slot_start[c], shape->slot_start[c + 1] - shape->slot_start[c]);
        ms_buf_putc(out, '\n');
    }
    uint32_t size = 0;
    if (mir_boxed_block_size(lay, t, &size)) {
        ms_buf_puts(out, "  block=");
        put_leaves(out, shape->block);
        ms_buf_printf(out, " size=%u\n", size);
    }
    const MirAltFields *fields = mir_alt_fields(lay, alt);
    for (uint32_t c = 0; c < fields->ncases; c++) {
        for (uint32_t i = fields->case_start[c]; i < fields->case_start[c + 1]; i++) {
            ms_buf_printf(out, "  field %u.%u ty=%u idx=", c, i - fields->case_start[c], fields->fields[i].ty);
            put_numbers(out, fields->fields[i].leaves, fields->fields[i].nleaves);
            ms_buf_putc(out, '\n');
        }
    }
}

/* One block of lines per type, alternative, indirect record and function, as the Rust oracle prints. */
static void dump_layout(const MirModule *m, MsBuf *out) {
    MirLayouts lay;
    mir_layouts_init(&lay, m);
    for (uint32_t t = 0; t < m->types.len; t++) {
        const MirShape *shape = mir_shape(&lay, t);
        uint32_t offsets[64];
        uint32_t n = shape->leaves.len;
        MirMemLayout mem = mir_mem_layout(shape->leaves.ptr, n, n <= 64 ? offsets : NULL);
        ms_buf_printf(out, "ty %u leaves=", t);
        put_leaves(out, shape->leaves);
        ms_buf_printf(out, " size=%u align=%u off=", mem.size, mem.align);
        if (n <= 64) {
            put_numbers(out, offsets, n);
        }
        ms_buf_puts(out, " ptr=");
        put_flags(out, mir_pointer_leaves(&lay, t), n);
        ms_buf_puts(out, " bool=");
        put_flags(out, mir_bool_leaves(&lay, t), n);
        ms_buf_printf(out, " str=%d\n", mir_is_str_like(&lay, t) ? 1 : 0);
        const MirTyData *data = mir_ty_data(m, t);
        if (data->kind == MK_OPT) {
            ms_buf_printf(out, "  nullable=%d\n", mir_opt_is_nullable(&lay, data->elem) ? 1 : 0);
        } else if (data->kind == MK_ALT) {
            dump_alt(&lay, t, shape, data->id, out);
        }
    }
    for (uint32_t r = 0; r < m->ntype_defs; r++) {
        ms_buf_printf(out, "block %u ", r);
        put_leaves(out, mir_type_block(&lay, r));
        ms_buf_putc(out, '\n');
    }
    for (uint32_t i = 0; i < m->nfuncs; i++) {
        MirClosureLayout c = mir_closure_layout(&lay, &m->funcs[i]);
        ms_buf_printf(out, "closure %u size=%u caps=", i, c.size);
        for (uint32_t k = 0; k < c.ncaptures; k++) {
            ms_buf_printf(out, "%s%u@%u:", k == 0 ? "" : " ", c.captures[k].ty, c.captures[k].offset);
            put_leaves(out, c.captures[k].leaves);
        }
        ms_buf_putc(out, '\n');
    }
    mir_layouts_free(&lay);
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

typedef struct Pass {
    const char *name;
    bool (*run)(MirModule *m);
} Pass;

static const Pass passes[] = {
    {"bytetake", mir_opt_bytetake},
    {"strfuse", mir_opt_strfuse},
};

/* Runs the named pass and prints whether it changed the module, then the module. */
static void dump_opt(const char *pass, MirModule *m, MsBuf *out) {
    for (size_t i = 0; i < sizeof passes / sizeof passes[0]; i++) {
        if (strcmp(passes[i].name, pass) == 0) {
            ms_buf_printf(out, "changed %s\n", passes[i].run(m) ? "true" : "false");
            mir_print_module(m, out);
        }
    }
}

static void dump_analysis(const MirModule *m, MsBuf *out) {
    for (uint32_t i = 0; i < m->nfuncs; i++) {
        print_analysis(m, &m->funcs[i], out);
    }
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fputs("usage: ms_mir_dump print|analysis|ops FILE...\n       ms_mir_dump opt PASS FILE...\n", stderr);
        return 2;
    }
    MsBuf out = {0};
    if (strcmp(argv[1], "ops") == 0) {
        for (int i = 0; i < MOP_COUNT; i++) {
            const MirOpInfo *o = &mir_op_info[i];
            ms_buf_printf(&out, "%s imm=%d res=%d fx=%d\n", o->name, o->imm, o->has_result, o->effects);
        }
    }
    bool boxing = strcmp(argv[1], "boxing") == 0, layout = strcmp(argv[1], "layout") == 0;
    const bool analysis = strcmp(argv[1], "analysis") == 0, opt = strcmp(argv[1], "opt") == 0;
    const char *pass = opt && argc > 2 ? argv[2] : "";
    for (int i = opt ? 3 : 2;
         i < argc && (boxing || layout || analysis || opt || strcmp(argv[1], "print") == 0); i++) {
        char *src;
        size_t len;
        if (!read_file(argv[i], &src, &len)) {
            fprintf(stderr, "cannot read %s\n", argv[i]);
            return 1;
        }
        ms_buf_printf(&out, "=== %s\n", argv[i]);
        if (!ms_utf8_valid(src, len)) {
            ms_buf_puts(&out, boxing || layout ? "error\n" : "error invalid-utf8\n");
            free(src);
            continue;
        }
        MirModule m;
        mir_module_init(&m);
        uint32_t line;
        MsStr msg;
        if (boxing || layout) {
            if (mir_parse(&m, src, len, &line, &msg)) {
                (boxing ? dump_boxing : dump_layout)(&m, &out);
            } else {
                ms_buf_puts(&out, "error\n");
            }
        } else if (mir_parse(&m, src, len, &line, &msg)) {
            if (analysis) {
                dump_analysis(&m, &out);
            } else if (opt) {
                dump_opt(pass, &m, &out);
            } else {
                mir_print_module(&m, &out);
            }
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
