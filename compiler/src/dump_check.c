/* Canonical text form of the checker tables, compared with the Rust checker's. */
#include <stdlib.h>
#include <string.h>

#include "ms/dump.h"

static const MsCheck *g_sort;

static int by_symbol_name(const void *a, const void *b) {
    MsStr x = ms_name(g_sort->names, g_sort->syms.name[*(const MsSymId *)a]);
    MsStr y = ms_name(g_sort->names, g_sort->syms.name[*(const MsSymId *)b]);
    uint32_t n = x.len < y.len ? x.len : y.len;
    int r = memcmp(x.ptr, y.ptr, n);
    return r != 0 ? r : (x.len > y.len) - (x.len < y.len);
}

static void put_name(MsBuf *out, const MsCheck *c, MsSym s) {
    MsStr n = ms_name(c->names, s);
    ms_buf_put(out, n.ptr, n.len);
}

static const char *sym_kind_text(MsSymKind kind) {
    switch (kind) {
    case MS_SYM_FN: return " fn";
    case MS_SYM_ALIAS: return " alias";
    case MS_SYM_TYPE: return " type";
    }
    return " type";
}

void ms_dump_std_tables(MsBuf *out, const MsCheck *c) {
    for (uint32_t m = 0; m < c->nmods; m++) {
        const MsModule *mod = c->mods[m].syntax;
        for (uint32_t i = 0; i < mod->ndecls; i++) {
            const MsDecl *d = mod->decls[i];
            if (d->kind != MS_D_TYPE || !d->u.type.external) {
                continue;
            }
            uint32_t s = ms_map_get(&c->std_types, d->u.type.name);
            ms_buf_puts(out, "extern ");
            put_name(out, c, c->mods[m].path);
            ms_buf_putc(out, ' ');
            put_name(out, c, d->u.type.name);
            ms_buf_puts(out, " id=");
            put_name(out, c, c->syms.id[s]);
            ms_buf_printf(out, " export=%s vars=%u\n", c->syms.is_exported[s] ? "true" : "false", c->syms.nvars[s]);
        }
    }
    for (uint32_t m = 0; m < c->nmods; m++) {
        if (c->mods[m].source) {
            continue;
        }
        ms_buf_puts(out, "module ");
        put_name(out, c, c->mods[m].path);
        ms_buf_putc(out, '\n');
        uint32_t n = c->mods[m].norder;
        MsSymId *rows = malloc(sizeof *rows * (n + 1));
        uint32_t k = 0;
        for (uint32_t i = 0; i < n; i++) {
            MsSymId s = c->mods[m].order[i];
            if (c->syms.is_exported[s] && c->syms.native[s] != MS_NATIVE_SOURCE) {
                rows[k++] = s;
            }
        }
        g_sort = c;
        qsort(rows, k, sizeof *rows, by_symbol_name);
        for (uint32_t i = 0; i < k; i++) {
            MsSymId s = rows[i];
            ms_buf_puts(out, "  ");
            put_name(out, c, c->syms.name[s]);
            ms_buf_puts(out, sym_kind_text(c->syms.kind[s]));
            ms_buf_puts(out, " export=true id=");
            put_name(out, c, c->syms.id[s]);
            ms_buf_puts(out, " native=");
            switch (c->syms.native[s]) {
            case MS_NATIVE_CONTRACT: ms_buf_puts(out, "contract"); break;
            case MS_NATIVE_EXTERN: ms_buf_puts(out, "extern:"); put_name(out, c, c->syms.native_name[s]); break;
            default: ms_buf_puts(out, "builtin:"); put_name(out, c, c->syms.native_name[s]); break;
            }
            ms_buf_printf(out, " vars=%u\n", c->syms.nvars[s]);
        }
        free(rows);
    }
}
