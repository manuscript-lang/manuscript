/* ms_mir_dump MODE FILE...: reads MIR text files and prints, per file, what
 * crates/ms-mir/examples/c_oracle.rs prints, so the two can be diffed byte for byte.
 * MODE: print (canonical text, or `error line N`), ops (the opcode table). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/mir.h"
#include "ms/mir_layout.h"
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

/* Runs the pass `name` on `m`; false when the name is unknown. */
static bool run_pass(const char *name, MirModule *m, bool *changed) {
    *changed = true;
    if (strcmp(name, "exit_drops") == 0) {
        mir_exit_drops(m);
    } else if (strcmp(name, "expand") == 0) {
        *changed = mir_expand(m, true);
    } else if (strcmp(name, "expand-nochecks") == 0) {
        *changed = mir_expand(m, false);
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
    if (argc < 2) {
        fputs("usage: ms_mir_dump print|ops|pass NAME FILE...\n", stderr);
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
    bool pass = argc > 2 && strcmp(argv[1], "pass") == 0;
    int first = pass ? 3 : 2;
    for (int i = first; i < argc && (boxing || layout || pass || strcmp(argv[1], "print") == 0); i++) {
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
            bool changed = false;
            if (pass && !run_pass(argv[2], &m, &changed)) {
                fprintf(stderr, "unknown pass %s\n", argv[2]);
                return 2;
            }
            if (pass) {
                ms_buf_printf(&out, "changed %d\n", changed ? 1 : 0);
            }
            mir_print_module(&m, &out);
            if (pass) {
                print_cold(&m, &out);
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
