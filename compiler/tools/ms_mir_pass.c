/* ms_mir_pass valid|pass NAME FILE...: runs a MIR pass on each file and prints what
 * crates/ms-mir/examples/c_pass_oracle.rs prints, so the two can be diffed byte for byte.
 * `pass NAME`: `changed N`, the module text, then the cold blocks of each function. The C tool
 * has no verifier, so the files to run on are chosen by the Rust oracle's `valid` mode. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "read_file.h"

#include "ms/mir.h"
#include "ms/mir_debug.h"
#include "ms/mir_pass.h"
#include "ms/mir_tables.h"
#include "synthetic_tables.h"

/* Runs the pass `name` on `m`; false when the name is unknown. */
/* A pass that can fail leaves its message in `failure`. */
static bool run_pass(const char *name, MirModule *m, bool *changed, MsBuf *failure) {
    *changed = true;
    if (strcmp(name, "exit_drops") == 0) {
        mir_exit_drops(m);
    } else if (strcmp(name, "expand") == 0) {
        *changed = mir_expand(m, true);
    } else if (strcmp(name, "expand-nochecks") == 0) {
        *changed = mir_expand(m, false);
    } else if (strcmp(name, "expand_owned") == 0) {
        *changed = mir_expand_owned(m);
    } else if (strcmp(name, "unwind") == 0) {
        *changed = mir_unwind(m);
    } else if (strcmp(name, "elaborate") == 0) {
        mir_elaborate(m, failure);
    } else if (strcmp(name, "elaborate-cancel") == 0) {
        mir_elaborate_with(m, true, failure);
    } else if (strcmp(name, "depth") == 0) {
        *changed = mir_depth_lower(m);
    } else if (strcmp(name, "cancel_edges") == 0) {
        *changed = mir_cancel_edges(m);
    } else if (strcmp(name, "finish") == 0) {
        MirGlue g = {0};
        const MirPipelineOptions o = {.cancel_edges = true, .checks = true, .verify = false};
        (void)mir_pipeline_finish(m, &o, &g, failure);
    } else if (strcmp(name, "count_ops") == 0) {
        mir_count_ops(m);
    } else if (strcmp(name, "copies") == 0 || strcmp(name, "slots") == 0 || strcmp(name, "tables") == 0 || strcmp(name, "debug_files") == 0 || strcmp(name, "frames") == 0) {
        /* Not a rewrite: main prints the framed values of each function. */
    } else if (strcmp(name, "debug_types") == 0) {
        /* Not a rewrite: main prints the description instead of the module. */
    } else if (strcmp(name, "glue") == 0) {
        MirGlue g = {0};
        *changed = mir_glue(m, &g);
    } else if (strcmp(name, "glue_expand") == 0) {
        MirGlue g = {0};
        mir_glue_run_and_expand(m, &g);
        *changed = true;
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

/* One line per type, then its members, then the list index of each MIR type. */
static void print_debug_types(const MirModule *m, MsBuf *out) {
    static const char *const kinds[] = {"base", "struct", "union", "pointer"};
    static const char *const encodings[] = {"bool", "signed", "unsigned", "float"};
    MirDebugTypes t = {0};
    mir_debug_types(m, &t);
    for (uint32_t i = 0; i < t.ntypes; i++) {
        const MirDebugType *d = &t.types[i];
        ms_buf_printf(out, "%u %.*s size=%u %s", i, (int)d->name.len, d->name.ptr, d->size,
                      kinds[d->kind]);
        if (d->kind == MDK_BASE) {
            ms_buf_printf(out, " %s", encodings[d->encoding]);
        } else if (d->kind == MDK_POINTER && d->pointee != MIR_NONE) {
            ms_buf_printf(out, " -> %u", d->pointee);
        }
        ms_buf_putc(out, '\n');
        for (uint32_t k = 0; k < d->nmembers; k++) {
            const MirDebugMember *mem = &d->members[k];
            ms_buf_printf(out, "  %.*s @%u: %u\n", (int)mem->name.len, mem->name.ptr, mem->offset,
                          mem->ty);
        }
    }
    ms_buf_puts(out, "of_ty");
    for (uint32_t i = 0; i < t.nty; i++) {
        ms_buf_printf(out, " %u", t.of_ty[i]);
    }
    ms_buf_putc(out, '\n');
    mir_debug_types_free(&t);
}

/* The synthetic tables (`synthetic_tables.h`): the blob in hex, then the pointers and the pc entries. */
static void print_tables(const MirModule *m, MsBuf *out) {
    MsArena arena = {0};
    MirTables t;
    synthetic_tables(&arena, m, &t);
    for (size_t i = 0; i < t.size; i++) {
        ms_buf_printf(out, "%02x", t.blob[i]);
    }
    ms_buf_putc(out, '\n');
    for (int i = 0; i < 5; i++) {
        ms_buf_printf(out, "ptr %zu %zu\n", t.pointers[i].at, t.pointers[i].to);
    }
    for (size_t i = 0; i < t.npcs; i++) {
        ms_buf_printf(out, "pc %zu %zu %u\n", t.pcs[i].at, t.pcs[i].func, t.pcs[i].off);
    }
    ms_arena_free(&arena);
}

/* Per function, `func: %slot=block ...` for the confined slots. */
static void print_slots(const MirModule *m, MsBuf *out) {
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        const MirFunc *f = &m->funcs[fi];
        MsArena arena = {0};
        const MirBlock *confined = mir_confined_slots(&arena, m, f);
        const MsStr name = ms_name(&m->names, f->name);
        ms_buf_printf(out, "%.*s:", (int)name.len, name.ptr);
        for (uint32_t v = 0; confined != NULL && v < f->nvalues; v++) {
            if (confined[v] != MIR_NONE) {
                ms_buf_printf(out, " %%%u=%u", v, confined[v]);
            }
        }
        ms_buf_putc(out, '\n');
        ms_arena_free(&arena);
    }
}

/* Per function, the values frames.rs frames. */
static void print_frames(const MirModule *m, MsBuf *out) {
    for (uint32_t fi = 0; fi < m->nfuncs; fi++) {
        const MirFunc *f = &m->funcs[fi];
        MsArena arena = {0};
        const MsStr name = ms_name(&m->names, f->name);
        ms_buf_printf(out, "%.*s", (int)name.len, name.ptr);
        const bool *sets[2] = {mir_framed_iface_borrows(&arena, m, f),
                               mir_framed_closure_objects(&arena, m, f)};
        for (int s = 0; s < 2; s++) {
            ms_buf_puts(out, s == 0 ? " iface:" : " closure:");
            for (uint32_t v = 0; sets[s] != NULL && v < f->nvalues; v++) {
                if (sets[s][v]) {
                    ms_buf_printf(out, " %u", v);
                }
            }
        }
        ms_buf_putc(out, '\n');
        ms_arena_free(&arena);
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
        src = read_whole_file(argv[i], &len);
        if (src == NULL) {
            fprintf(stderr, "cannot read %s\n", argv[i]);
            return 1;
        }
        ms_buf_printf(&out, "=== %s\n", argv[i]);
        MirModule m;
        mir_module_init(&m);
        uint32_t line;
        MsStr msg;
        bool changed = false;
        MsBuf failure = {0};
        if (!mir_parse(&m, src, len, &line, &msg)) {
            ms_buf_puts(&out, "error\n");
        } else if (!run_pass(argv[2], &m, &changed, &failure)) {
            fprintf(stderr, "unknown pass %s\n", argv[2]);
            return 2;
        } else if (failure.len > 0) {
            ms_buf_printf(&out, "fail %.*s\n", (int)failure.len, failure.data);
            ms_buf_free(&failure);
            failure = (MsBuf){0};
        } else {
            ms_buf_printf(&out, "changed %d\n", changed ? 1 : 0);
            if (strcmp(argv[2], "debug_types") == 0) {
                print_debug_types(&m, &out);
            } else if (strcmp(argv[2], "debug_files") == 0) {
                MsArena names = {0};
                const char *stdlib_dir = getenv("MS_STDLIB_DIR"); // NOLINT(concurrency-mt-unsafe)
                for (uint32_t fk = 0; fk < m.nfiles; fk++) {
                    const MsStr n = mir_debug_file_name(&names, m.files[fk], stdlib_dir);
                    ms_buf_printf(&out, "%.*s\n", (int)n.len, n.ptr);
                }
                ms_arena_free(&names);
            } else if (strcmp(argv[2], "tables") == 0) {
                print_tables(&m, &out);
            } else if (strcmp(argv[2], "slots") == 0) {
                print_slots(&m, &out);
            } else if (strcmp(argv[2], "copies") == 0) {
                mir_object_copies(&m, &out);
            } else if (strcmp(argv[2], "frames") == 0) {
                print_frames(&m, &out);
            } else {
                mir_print_module(&m, &out);
                print_cold(&m, &out);
            }
        }
        mir_module_free(&m);
        free(src);
    }
    fwrite(out.data, 1, out.len, stdout);
    ms_buf_free(&out);
    return 0;
}
