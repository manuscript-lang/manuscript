/* The fault tables blob. Port of fault_tables.rs. */
#include <string.h>

#include "ms/mir_tables.h"

enum { TB_HEADER = 80, TB_SCOPE = 16, TB_FUNC = 24, TB_LINE = 16, TB_ABI_VERSION = 3 };

static void tb_u32(uint8_t *blob, size_t at, uint32_t v) {
    for (int i = 0; i < 4; i++) {
        blob[at + (size_t)i] = (uint8_t)(v >> (8 * i));
    }
}

static void tb_u64(uint8_t *blob, size_t at, uint64_t v) {
    tb_u32(blob, at, (uint32_t)v);
    tb_u32(blob, at + 4, (uint32_t)(v >> 32));
}

static size_t tb_align8(size_t n) { return (n + 7) / 8 * 8; }

/* The strings the tables name, NUL-terminated and back to back. */
typedef struct TbStrings { MsBuf buf; } TbStrings;

static uint32_t tb_intern(TbStrings *s, const char *p, size_t n) {
    const uint32_t at = (uint32_t)s->buf.len;
    ms_buf_put(&s->buf, p, n);
    ms_buf_putc(&s->buf, '\0');
    return at;
}

static uint32_t tb_file(const uint32_t *files, uint32_t nfiles, uint32_t f) {
    return f < nfiles ? files[f] : UINT32_MAX;
}

typedef struct TbLayout {
    size_t funcs_at, lines_at, line_scopes_at, scopes_at, strings_at;
} TbLayout;

static void tb_scopes(uint8_t *blob, const MirModule *m, const MirScope *scopes, uint32_t nscopes,
                      const TbLayout *l, const uint32_t *files, const uint32_t *scope_names) {
    for (uint32_t n = 0; n < nscopes; n++) {
        const MirScope *sc = &scopes[n];
        const size_t at = l->scopes_at + (size_t)n * TB_SCOPE;
        tb_u32(blob, at, scope_names[n]);
        tb_u32(blob, at + 4, tb_file(files, m->nfiles, sc->file));
        tb_u32(blob, at + 8, sc->parent);
        tb_u32(blob, at + 12, sc->call_line);
    }
}

void mir_fault_tables(MsArena *arena, const MirModule *m, const MirFuncTable *funcs,
                      uint32_t nfuncs, const MirScope *scopes, uint32_t nscopes, MirTables *out) {
    TbStrings strings = {0};
    uint32_t *files = MS_NEW_N(arena, uint32_t, m->nfiles ? m->nfiles : 1);
    for (uint32_t i = 0; i < m->nfiles; i++) {
        files[i] = tb_intern(&strings, m->files[i].ptr, m->files[i].len);
    }
    uint32_t *names = MS_NEW_N(arena, uint32_t, nfuncs ? nfuncs : 1);
    for (uint32_t i = 0; i < nfuncs; i++) {
        names[i] = tb_intern(&strings, funcs[i].name.ptr, funcs[i].name.len);
    }
    uint32_t *scope_names = MS_NEW_N(arena, uint32_t, nscopes ? nscopes : 1);
    for (uint32_t i = 0; i < nscopes; i++) {
        const MsStr n = ms_name(&m->names, scopes[i].name);
        scope_names[i] = tb_intern(&strings, n.ptr, n.len);
    }
    size_t nlines = 0;
    for (uint32_t i = 0; i < nfuncs; i++) {
        nlines += funcs[i].nranges;
    }
    TbLayout l = {.funcs_at = TB_HEADER};
    l.lines_at = l.funcs_at + (size_t)nfuncs * TB_FUNC;
    l.line_scopes_at = l.lines_at + nlines * TB_LINE;
    l.scopes_at = tb_align8(l.line_scopes_at + nlines * 4);
    l.strings_at = l.scopes_at + (size_t)nscopes * TB_SCOPE;
    out->size = l.strings_at + strings.buf.len;
    out->blob = MS_NEW_N(arena, uint8_t, out->size);
    memset(out->blob, 0, out->size);
    uint8_t *blob = out->blob;
    tb_u32(blob, 0, TB_ABI_VERSION);
    tb_u64(blob, 72, nscopes);
    tb_u64(blob, 16, nfuncs);
    tb_u64(blob, 32, nlines);
    tb_u64(blob, 48, strings.buf.len);
    tb_scopes(blob, m, scopes, nscopes, &l, files, scope_names);
    if (strings.buf.len > 0) {
        memcpy(blob + l.strings_at, strings.buf.data, strings.buf.len);
    }
    out->npcs = nfuncs + nlines;
    out->pcs = MS_NEW_N(arena, MirTablePc, out->npcs ? out->npcs : 1);
    size_t npc = 0, at_line = l.lines_at;
    for (uint32_t n = 0; n < nfuncs; n++) {
        const MirFuncTable *d = &funcs[n];
        const size_t at = l.funcs_at + (size_t)n * TB_FUNC;
        out->pcs[npc++] = (MirTablePc){at, n, 0};
        tb_u32(blob, at + 8, d->size);
        tb_u32(blob, at + 12, names[n]);
        tb_u32(blob, at + 16, tb_file(files, m->nfiles, d->file));
        tb_u32(blob, at + 20, d->line);
        for (uint32_t k = 0; k < d->nranges; k++) {
            const MirCodeRange *r = &d->ranges[k];
            out->pcs[npc++] = (MirTablePc){at_line, n, r->off};
            tb_u32(blob, at_line + 8, r->line);
            tb_u32(blob, at_line + 12, tb_file(files, m->nfiles, r->file));
            tb_u32(blob, l.line_scopes_at + (at_line - l.lines_at) / TB_LINE * 4, r->scope);
            at_line += TB_LINE;
        }
    }
    const MirTablePointer pointers[5] = {{8, l.funcs_at}, {24, l.lines_at}, {40, l.strings_at},
                                         {56, l.line_scopes_at}, {64, l.scopes_at}};
    memcpy(out->pointers, pointers, sizeof pointers);
    ms_buf_free(&strings.buf);
}
