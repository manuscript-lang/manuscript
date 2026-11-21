/* ms_mir_dump MODE FILE...: reads MIR text files and prints, per file, what
 * crates/ms-mir/examples/c_oracle.rs prints, so the two can be diffed byte for byte.
 * MODE: print (canonical text, or `error line N`), ops (the opcode table). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "read_file.h"

#include "ms/mir.h"
#include "ms/mir_interp.h"
#include "ms/mir_analysis.h"
#include "ms/mir_layout.h"
#include "ms/mir_opt.h"
#include "ms/mir_verify.h"

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

/* The owned shorthands the Rust interpreter expands first; the C one does not, so such modules are skipped. */
static bool has_shorthand(const MirModule *m) {
    for (uint32_t f = 0; f < m->nfuncs; f++) {
        for (uint32_t b = 0; b < m->funcs[f].nblocks; b++) {
            for (uint32_t i = 0; i < m->funcs[f].blocks[b].ninsts; i++) {
                switch ((MirOp)m->funcs[f].blocks[b].insts[i].op) {
                case MOP_AltOwn: case MOP_AltUnbox: case MOP_AltRelease: case MOP_TypeRelease:
                case MOP_OptUnbox: case MOP_OptUnwrap:
                    return true;
                default:
                    break;
                }
            }
        }
    }
    return false;
}

/* Internal faults quote debug output the C version does not copy: compare only that they happened. */
static const char *plain_text(MsStr text, int *length) {
    if ((text.len >= 12 && strncmp(text.ptr, "interpreter:", 12) == 0) ||
        (text.len >= 14 && strncmp(text.ptr, "entry returned", 14) == 0)) {
        *length = 11;
        return "interpreter";
    }
    *length = (int)text.len;
    return text.ptr;
}

static const char *fault_name(MirFault kind) {
    static const char *const names[] = {"IntOverflow", "DivByZero", "IndexOutOfRange", "NoneUnwrap",
                                        "Cancelled", "CallDepth", "Unreachable", "Message"};
    return names[kind];
}

static void dump_run(const MirModule *m, MsBuf *out) {
    if (has_shorthand(m)) {
        ms_buf_puts(out, "skip expand\n");
        return;
    }
    MirInterp *interp = mir_interp_new(m);
    mir_interp_set_fuel(interp, 2000000);
    int64_t code = 0;
    bool ok = mir_interp_run_entry(interp, &code);
    MsStr text = mir_interp_stdout(interp);
    ms_buf_puts(out, "stdout=");
    for (uint32_t i = 0; i < text.len; i++) {
        if (text.ptr[i] == '\n') ms_buf_puts(out, "\\n"); else ms_buf_putc(out, text.ptr[i]);
    }
    ms_buf_putc(out, '\n');
    if (ok) {
        ms_buf_printf(out, "exit %lld\n", (long long)code);
    } else {
        const MirInterpFault *f = mir_interp_fault(interp);
        int length = 0;
        const char *message = plain_text(f->message, &length);
        ms_buf_printf(out, "fault %s ", fault_name(f->kind));
        ms_buf_put(out, message, (size_t)length);
        ms_buf_printf(out, " fuel=%d\n", f->fuel_exhausted ? 1 : 0);
        for (uint32_t i = 0; i < f->nstack; i++) {
            ms_buf_printf(out, "  at %.*s\n", (int)f->stack[i].len, f->stack[i].ptr);
        }
        for (uint32_t i = 0; i < f->ncleanup_faults; i++) {
            message = plain_text(f->cleanup_faults[i], &length);
            ms_buf_puts(out, "  cleanup ");
            ms_buf_put(out, message, (size_t)length);
            ms_buf_putc(out, '\n');
        }
    }
    ms_buf_printf(out, "drops %llu steps %llu\n", (unsigned long long)mir_interp_drops(interp),
                  (unsigned long long)mir_interp_steps(interp));
    mir_interp_free(interp);
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

/* The whole pipeline at one level, verifying after every pass; a failure is printed in place of
 * the module. */
static bool run_pipeline(MirModule *m, MirOptLevel level) {
    MsBuf error = {0};
    if (!mir_optimize(m, level, true, &error)) {
        fwrite(error.data, 1, error.len, stderr);
    }
    ms_buf_free(&error);
    return true;
}

static bool pipeline_none(MirModule *m) { return run_pipeline(m, MIR_OPT_NONE); }
static bool pipeline_speed(MirModule *m) { return run_pipeline(m, MIR_OPT_SPEED); }

typedef struct Pass {
    const char *name;
    bool (*run)(MirModule *m);
} Pass;

static const Pass passes[] = {
    {"bytetake", mir_opt_bytetake},
    {"strfuse", mir_opt_strfuse},
    {"loopslot", mir_opt_loopslot},
    {"optparam", mir_opt_optparam},
    {"ifconv", mir_opt_ifconv},
    {"reserve", mir_opt_reserve},
    {"appendfast", mir_opt_appendfast},
    {"probe", mir_opt_probe},
    {"sortgen", mir_opt_sortgen},
    {"copyelim", mir_opt_copyelim},
    {"copytakes", mir_opt_copyelim_takes},
    {"lastuse", mir_opt_lastuse},
    {"range", mir_opt_range},
    {"simplify", mir_opt_simplify},
    {"phis", mir_opt_simplify_phis},
    {"inline", mir_opt_inline},
    {"inlinesmall", mir_opt_inline_small},
    {"pipeline0", pipeline_none},
    {"pipeline", pipeline_speed},
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

/* The verifier's errors, one per line, or `ok`. */
static void dump_verify(const MirModule *m, MsBuf *out) {
    MirVerifyErrors errs = {0};
    if (mir_verify_module(m, false, &errs)) {
        ms_buf_puts(out, "ok\n");
    }
    for (uint32_t i = 0; i < errs.count; i++) {
        mir_verify_error_text(&errs.errors[i], out);
        ms_buf_putc(out, '\n');
    }
    mir_verify_errors_free(&errs);
}

static void dump_analysis(const MirModule *m, MsBuf *out) {
    for (uint32_t i = 0; i < m->nfuncs; i++) {
        print_analysis(m, &m->funcs[i], out);
    }
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fputs("usage: ms_mir_dump print|analysis|verify|ops FILE...\n", stderr);
        return 2;
    }
    MsBuf out = {0};
    if (strcmp(argv[1], "ops") == 0) {
        for (int i = 0; i < MOP_COUNT; i++) {
            const MirOpInfo *o = &mir_op_info[i];
            ms_buf_printf(&out, "%s imm=%d res=%d fx=%d\n", o->name, o->imm, o->has_result, o->effects);
        }
    }
    bool boxing = strcmp(argv[1], "boxing") == 0, layout = strcmp(argv[1], "layout") == 0, run = strcmp(argv[1], "run") == 0;
    const bool analysis = strcmp(argv[1], "analysis") == 0, opt = strcmp(argv[1], "opt") == 0;
    const bool verify = strcmp(argv[1], "verify") == 0;
    const char *pass = opt && argc > 2 ? argv[2] : "";
    for (int i = opt ? 3 : 2;
         i < argc && (boxing || layout || run || analysis || verify || opt || strcmp(argv[1], "print") == 0); i++) {
        char *src;
        size_t len;
        src = read_whole_file(argv[i], &len);
        if (src == NULL) {
            fprintf(stderr, "cannot read %s\n", argv[i]);
            return 1;
        }
        ms_buf_printf(&out, "=== %s\n", argv[i]);
        if (!ms_utf8_valid(src, len)) {
            ms_buf_puts(&out, boxing || layout || run ? "error\n" : "error invalid-utf8\n");
            free(src);
            continue;
        }
        MirModule m;
        mir_module_init(&m);
        uint32_t line;
        MsStr msg;
        if (boxing || layout || run) {
            if (mir_parse(&m, src, len, &line, &msg)) {
                (boxing ? dump_boxing : layout ? dump_layout : dump_run)(&m, &out);
            } else {
                ms_buf_puts(&out, "error\n");
            }
        } else if (mir_parse(&m, src, len, &line, &msg)) {
            if (analysis) {
                dump_analysis(&m, &out);
            } else if (verify) {
                dump_verify(&m, &out);
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
