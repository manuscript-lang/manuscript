/* Fault tables from assembly text: see ms/mir_asm_tables.h. */
#include <stdlib.h>
#include <string.h>

#include "ms/mir_asm_tables.h"
#include "ms/mir_tables.h"

typedef struct AtFunc {
    MsStr sym, name;
    uint32_t file, line;
    bool seen;
} AtFunc;

typedef struct AtLoc { uint32_t func, line, scope; } AtLoc;

/* One value the assembler fills into the blob. */
typedef enum { AT_FUNC_ADDR, AT_LOC_ADDR, AT_FUNC_SIZE, AT_BLOB_ADDR } AtKind;
typedef struct AtPatch { size_t at; AtKind kind; size_t value; } AtPatch;

static int at_patch_cmp(const void *a, const void *b) {
    const size_t x = ((const AtPatch *)a)->at, y = ((const AtPatch *)b)->at;
    return x < y ? -1 : x > y;
}

static int at_sym_cmp(const void *a, const void *b) {
    const AtFunc *x = *(const AtFunc *const *)a, *y = *(const AtFunc *const *)b;
    const size_t n = x->sym.len < y->sym.len ? x->sym.len : y->sym.len;
    const int c = memcmp(x->sym.ptr, y->sym.ptr, n);
    return c != 0 ? c : (x->sym.len > y->sym.len) - (x->sym.len < y->sym.len);
}

static uint32_t at_uint(const char **p) {
    char *end;
    const unsigned long v = strtoul(*p, &end, 10);
    *p = end;
    return (uint32_t)v;
}

static uint32_t at_file(const char **p) {
    const long v = strtol(*p, (char **)p, 10);
    return v < 0 ? MIR_NONE : (uint32_t)v;
}

typedef struct AtMeta {
    MirModule m;
    AtFunc *funcs;
    uint32_t nfuncs, cfuncs;
    MirScope *scopes;
    uint32_t nscopes, cscopes;
} AtMeta;

static void at_meta_parse(AtMeta *a, const char *text, size_t len) {
    const char *end = text + len;
    while (text < end) {
        const char *eol = memchr(text, '\n', (size_t)(end - text));
        if (eol == NULL) eol = end;
        const char *p = text + 2;
        if (text[0] == 'F') {
            const MsStr f = {p, (uint32_t)(eol - p)};
            MIR_PUSH(&a->m, a->m.files, a->m.nfiles, a->m.cfiles, MsStr, f);
        } else if (text[0] == 'Y') {
            const char *tab = memchr(p, '\t', (size_t)(eol - p));
            AtFunc f = {.sym = {p, (uint32_t)(tab - p)}};
            p = tab + 1;
            f.file = at_file(&p);
            p++;
            f.line = at_uint(&p);
            p++;
            f.name = (MsStr){p, (uint32_t)(eol - p)};
            MIR_PUSH(&a->m, a->funcs, a->nfuncs, a->cfuncs, AtFunc, f);
        } else if (text[0] == 'S') {
            MirScope s = {0};
            s.file = at_file(&p);
            p++;
            s.parent = at_uint(&p);
            p++;
            s.call_line = at_uint(&p);
            p++;
            s.name = mir_name(&a->m, p, (size_t)(eol - p));
            MIR_PUSH(&a->m, a->scopes, a->nscopes, a->cscopes, MirScope, s);
        }
        text = eol + 1;
    }
}

/* A symbol label at the start of a line, `name:` possibly followed by a comment (LLVM writes `f: # @f`);
 * returns its length, 0 when the line is not one. Local labels (`.L...`) and directives start with a dot. */
static size_t at_label_len(const char *line, size_t n) {
    if (n < 2 || line[0] == '.' || line[0] == '\t' || line[0] == ' ' || line[0] == '#') {
        return 0;
    }
    size_t k = 0;
    while (k < n && line[k] != ':' && line[k] != ' ' && line[k] != '\t') {
        k++;
    }
    return k < n && k > 0 && line[k] == ':' ? k : 0;
}

static bool at_ends_function(const char *line, size_t n) {
    static const char *const stops[] = {".size", ".type", ".text", ".data", ".section", ".globl", ".bss", ".cfi_endproc", ".def", ".seh_endproc"};
    while (n > 0 && (line[0] == '\t' || line[0] == ' ')) { /* LLVM indents directives, QBE does not */
        line++;
        n--;
    }
    if (n == 0 || line[0] != '.') {
        return false;
    }
    for (size_t i = 0; i < sizeof stops / sizeof *stops; i++) {
        const size_t k = strlen(stops[i]);
        if (n >= k && memcmp(line, stops[i], k) == 0) {
            return true;
        }
    }
    return false;
}

/* The line and scope of a `.loc file line col` (ELF, Mach-O; QBE spaces, LLVM tabs) or `.cv_loc function file
 * line col` (COFF, LLVM) directive at the start of `text`. The scope is the column, 0 when there is none. */
static bool at_loc_args(const char *text, size_t n, AtLoc *out) {
    static const char loc[] = "\t.loc", cv[] = "\t.cv_loc";
    const bool is_cv = n > sizeof cv && memcmp(text, cv, sizeof cv - 1) == 0;
    const size_t name = is_cv ? sizeof cv - 1 : sizeof loc - 1;
    if (!is_cv && !(n > name && memcmp(text, loc, name) == 0)) {
        return false;
    }
    if (text[name] != ' ' && text[name] != '\t') {
        return false;
    }
    char *line_copy = malloc(n + 1); /* strtoul needs a NUL; owned, freed below */
    memcpy(line_copy, text + name, n - name);
    line_copy[n - name] = '\0';
    const char *q = line_copy;
    (void)at_uint(&q);
    if (is_cv) {
        (void)at_uint(&q); /* the file follows the function id */
    }
    out->line = at_uint(&q);
    out->scope = *q == ' ' || *q == '\t' ? at_uint(&q) : 0;
    free(line_copy);
    return true;
}

static AtFunc *at_find(AtFunc **sorted, uint32_t n, MsStr sym) {
    AtFunc key = {.sym = sym};
    const AtFunc *k = &key;
    AtFunc **hit = bsearch(&k, sorted, n, sizeof *sorted, at_sym_cmp);
    return hit != NULL ? *hit : NULL;
}

static void at_put_blob(MsBuf *out, const uint8_t *blob, size_t size, AtPatch *patches, size_t npatches,
                        const AtFunc *funcs, const char *prefix) {
    qsort(patches, npatches, sizeof *patches, at_patch_cmp);
    ms_buf_printf(out, "\n.data\n.balign 8\n.globl %sms_tables\n%sms_tables:\n", prefix, prefix);
    size_t at = 0, next = 0;
    while (at < size) {
        if (next < npatches && patches[next].at == at) {
            const AtPatch *pt = &patches[next++];
            const AtFunc *f = pt->kind == AT_FUNC_ADDR || pt->kind == AT_FUNC_SIZE ? &funcs[pt->value] : NULL;
            switch (pt->kind) {
            case AT_FUNC_ADDR: ms_buf_printf(out, "\t.quad %s%.*s\n", prefix, (int)f->sym.len, f->sym.ptr); at += 8; break;
            case AT_LOC_ADDR: ms_buf_printf(out, "\t.quad .Lmsl%zu\n", pt->value); at += 8; break;
            case AT_FUNC_SIZE:
                ms_buf_printf(out, "\t.long .Lmse%zu-%s%.*s\n", pt->value, prefix, (int)f->sym.len, f->sym.ptr);
                at += 4;
                break;
            case AT_BLOB_ADDR: ms_buf_printf(out, "\t.quad %sms_tables+%zu\n", prefix, pt->value); at += 8; break;
            }
            continue;
        }
        const size_t stop = next < npatches ? patches[next].at : size;
        ms_buf_puts(out, "\t.byte ");
        const size_t from = at;
        for (; at < stop && at < from + 16; at++) {
            ms_buf_printf(out, "%s%u", at == from ? "" : ",", blob[at]);
        }
        ms_buf_putc(out, '\n');
    }
}

bool mir_asm_tables(const char *meta, size_t meta_len, const char *asm_text, size_t asm_len,
                    const char *prefix, bool strip_lines, MsBuf *out, MsBuf *why) {
    AtMeta a = {0};
    mir_module_init(&a.m);
    at_meta_parse(&a, meta, meta_len);
    AtFunc **sorted = malloc((a.nfuncs ? a.nfuncs : 1) * sizeof *sorted);
    for (uint32_t i = 0; i < a.nfuncs; i++) sorted[i] = &a.funcs[i];
    qsort(sorted, a.nfuncs, sizeof *sorted, at_sym_cmp);
    MsBuf locs = {0};
    const size_t plen = strlen(prefix);
    int cur = -1;
    AtLoc l;
    const char *p = asm_text, *end = asm_text + asm_len;
    while (p < end) {
        const char *eol = memchr(p, '\n', (size_t)(end - p));
        if (eol == NULL) eol = end;
        const size_t n = (size_t)(eol - p);
        if (cur >= 0 && at_ends_function(p, n)) {
            ms_buf_printf(out, ".Lmse%d:\n", cur);
            cur = -1;
        }
        const bool is_loc = cur >= 0 && at_loc_args(p, n, &l);
        if (!(is_loc && strip_lines)) {
            ms_buf_put(out, p, n);
            ms_buf_putc(out, '\n');
        }
        const size_t label = at_label_len(p, n);
        if (label > plen && memcmp(p, prefix, plen) == 0) {
            AtFunc *f = at_find(sorted, a.nfuncs, (MsStr){p + plen, (uint32_t)(label - plen)});
            if (f != NULL && !f->seen) {
                f->seen = true;
                cur = (int)(f - a.funcs);
            }
        } else if (is_loc && l.line != 0) { /* line 0 is code LLVM made up: the range before it goes on */
            l.func = (uint32_t)cur;
            ms_buf_printf(out, ".Lmsl%zu:\n", locs.len / sizeof l);
            ms_buf_put(&locs, &l, sizeof l);
        }
        p = eol + 1;
    }
    if (cur >= 0) {
        ms_buf_printf(out, ".Lmse%d:\n", cur);
    }
    bool ok = true;
    for (uint32_t i = 0; i < a.nfuncs; i++) {
        if (!a.funcs[i].seen) {
            ms_buf_printf(why, "no code for %.*s\n", (int)a.funcs[i].sym.len, a.funcs[i].sym.ptr);
            ok = false;
        }
    }
    if (ok) {
        const size_t nlocs = locs.len / sizeof(AtLoc);
        const AtLoc *all = (const AtLoc *)(const void *)locs.data;
        MirFuncTable *tables = MS_NEW_N(&a.m.arena, MirFuncTable, a.nfuncs ? a.nfuncs : 1);
        MirCodeRange *ranges = MS_NEW_N(&a.m.arena, MirCodeRange, nlocs ? nlocs : 1);
        size_t at = 0;
        for (uint32_t f = 0; f < a.nfuncs; f++) {
            const size_t first = at;
            for (size_t k = 0; k < nlocs; k++) {
                if (all[k].func == f) {
                    ranges[at++] = (MirCodeRange){(uint32_t)k + 1, MIR_NONE, all[k].line, all[k].scope};
                }
            }
            tables[f] = (MirFuncTable){a.funcs[f].name, a.funcs[f].file, a.funcs[f].line, 0, ranges + first,
                                       (uint32_t)(at - first)};
        }
        MirTables t;
        mir_fault_tables(&a.m.arena, &a.m, tables, a.nfuncs, a.scopes, a.nscopes, &t);
        AtPatch *patches = MS_NEW_N(&a.m.arena, AtPatch, t.npcs * 2 + 5 + a.nfuncs + 1);
        size_t np = 0;
        for (size_t i = 0; i < t.npcs; i++) {
            const MirTablePc *pc = &t.pcs[i];
            if (pc->off == 0) {
                patches[np++] = (AtPatch){pc->at, AT_FUNC_ADDR, pc->func};
                patches[np++] = (AtPatch){pc->at + 8, AT_FUNC_SIZE, pc->func};
            } else {
                patches[np++] = (AtPatch){pc->at, AT_LOC_ADDR, pc->off - 1};
            }
        }
        for (int i = 0; i < 5; i++) {
            patches[np++] = (AtPatch){t.pointers[i].at, AT_BLOB_ADDR, t.pointers[i].to};
        }
        at_put_blob(out, t.blob, t.size, patches, np, a.funcs, prefix);
    }
    free(sorted);
    ms_buf_free(&locs);
    mir_module_free(&a.m);
    return ok;
}
